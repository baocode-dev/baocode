// Generates packages/bao_exthost/lib/src/generated/ from the pinned VS Code's
// extension host protocol: the proxy identifiers, a Dart interface, a fallback
// implementation and a dispatcher for every main thread shape (the side
// BaoCode implements; `unsupportedMainThreadActors` has a fallback actor for
// each), a typed proxy for every extension host shape (the side BaoCode
// calls), and the main thread methods by shape for the parity report.
// Only `$` methods are generated: RPC proxies forward nothing else.
// Set EXTHOST_CODEGEN_FALLBACKS=1 to list the parameters typed Object?.
//
// Usage (after `npm ci --prefix tool/exthost_codegen`):
//   node tool/generate_exthost_protocol.mjs <vscode-checkout> \
//     <reh>/out/vs/workbench/api/node/extensionHostProcess.js \
//     packages/bao_exthost/lib/src/generated
//
// <vscode-checkout> must be VS Code at the pinned commit (see `revision`);
// the bundle is the pinned VSCodium REH's compiled extension host. The proxy
// identifiers' numbers come from the bundle: its compiled
// `createProxyIdentifier` calls are run in a sandbox, and the numbers are
// checked against the order in extHost.protocol.ts (a mismatch fails).
//
// Type mapping (TypeScript -> Dart), applied to parameters and results:
//   string, string literal, template literal, string enum -> String
//   number -> num; number literal, numeric enum -> int; boolean -> bool
//   any, unknown, type parameters, functions, mixed unions -> Object?
//   T | undefined, T | null, optional parameters -> T? (nullable)
//   UriComponents, URI -> VsUri (decoded with VsUri.revive)
//   VSBuffer -> RpcBuffer; SerializableObjectWithBuffers<T> -> Object?
//     (callers pass an RpcObjectWithBuffers)
//   CancellationToken (last parameter) -> `{CancellationToken? token}` on
//     proxies; on main thread shapes a trailing `CancellationToken token`
//     (an actor passes what RpcProtocol appended, or CancellationToken.none)
//   T[], ReadonlyArray<T>, Array<T>, ...rest: T[] -> List<T>
//   Record<string, T>, IStringDictionary<T>, index signatures -> Map<String, T>
//   tuples -> List<Object?>
//   Promise<T> -> Future<T>; main thread results: void and Promise<void> ->
//     FutureOr<void>, other non-promise T -> FutureOr<T>; proxies always
//     return Future<T>
//   a CancellationToken before other parameters (upstream sends it as JSON
//     and it cancels nothing) -> CancellationToken (CancellationToken.none
//     from actors; proxies send `{isCancellationRequested}`)
//   every other interface, class, object literal, mapped or DTO type
//     -> Map<String, Object?>; anything else -> Object?
// Unions whose members map to the same Dart type take that type; unions of
// object types take Map<String, Object?>; other unions take Object?.
//
// Proxies send a null argument whose type admits `undefined` (and not
// `null`) as `undefined` (rpcUndefined), as upstream does.

import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';
import vm from 'node:vm';

const require = createRequire(new URL('./exthost_codegen/package.json', import.meta.url));
const ts = require('typescript');

const revision = '08d4889f9ec4a1685d257b9b95de036c8e1ce1e5';
const version = '1.135.0';
const protocolPath = 'src/vs/workbench/api/common/extHost.protocol.ts';

const [checkout, bundlePath, outDir] = process.argv.slice(2);
if (!checkout || !bundlePath || !outDir) {
  console.error('Usage: node tool/generate_exthost_protocol.mjs <vscode-checkout> <extensionHostProcess.js> <out-dir>');
  process.exit(64);
}
const head = execFileSync('git', ['-C', checkout, 'rev-parse', 'HEAD'], { encoding: 'utf8' }).trim();
if (head !== revision) {
  throw new Error(`${checkout} is at ${head}; expected VS Code ${version} (${revision})`);
}

// --- Proxy identifiers from the compiled bundle -----------------------------

/**
 * Finds the bundle's `ProxyIdentifier` class (the one with
 * `_proxyIdentifierBrand` and `nid=++X.count`), the function that creates
 * them, and every call of that function; runs those calls, in order, in a
 * sandbox with the compiled class and function, and returns the identifiers
 * with the numbers the compiled code gives them.
 */
function bundleIdentifiers(file) {
  const text = readFileSync(file, 'utf8');
  const sf = ts.createSourceFile(file, text, ts.ScriptTarget.Latest, true, ts.ScriptKind.JS);
  let cls;
  const walk = (node, visit) => { visit(node); ts.forEachChild(node, (c) => walk(c, visit)); };
  walk(sf, (node) => {
    if ((ts.isClassDeclaration(node) || ts.isClassExpression(node)) && /_proxyIdentifierBrand/.test(node.getText(sf))
      && /\.nid=\+\+/.test(node.getText(sf).replace(/\s/g, ''))) {
      if (cls) throw new Error('Two ProxyIdentifier classes in the bundle');
      cls = node;
    }
  });
  if (!cls) throw new Error('No ProxyIdentifier class in the bundle');
  // `class X {…}` or `var X = class Y {…}`: X is what the factory uses.
  let className;
  let classText;
  if (ts.isClassDeclaration(cls)) {
    className = cls.name.text;
    classText = cls.getText(sf);
  } else if (ts.isVariableDeclaration(cls.parent) && ts.isIdentifier(cls.parent.name)) {
    className = cls.parent.name.text;
    classText = `var ${className} = ${cls.getText(sf)};`;
  } else {
    throw new Error('The ProxyIdentifier class is not bound to a name');
  }
  let factory;
  walk(sf, (node) => {
    if (ts.isFunctionDeclaration(node) && node.name && node.body && node.parameters.length === 1) {
      let creates = false;
      walk(node.body, (n) => {
        if (ts.isNewExpression(n) && ts.isIdentifier(n.expression) && n.expression.text === className) creates = true;
      });
      if (creates) {
        if (factory) throw new Error('Two createProxyIdentifier functions in the bundle');
        factory = node;
      }
    }
  });
  if (!factory) throw new Error('No createProxyIdentifier function in the bundle');
  const factoryName = factory.name.text;
  // What the factory uses besides the class (upstream's `identifiers`
  // registry): each must be a variable with a literal value next to it.
  const locals = new Set([...factory.parameters.map((p) => p.name.getText(sf))]);
  walk(factory.body, (n) => { if (ts.isVariableDeclaration(n)) locals.add(n.name.getText(sf)); });
  const free = new Set();
  walk(factory.body, (n) => {
    if (ts.isIdentifier(n) && !locals.has(n.text) && n.text !== className
      && !(ts.isPropertyAccessExpression(n.parent) && n.parent.name === n)) {
      free.add(n.text);
    }
  });
  const support = [];
  for (const name of free) {
    let init;
    walk(factory.parent, (n) => {
      if (ts.isVariableDeclaration(n) && ts.isIdentifier(n.name) && n.name.text === name && n.initializer) init ??= n.initializer;
    });
    if (!init || !(ts.isArrayLiteralExpression(init) || ts.isObjectLiteralExpression(init))
      || init.getText(sf).length > 2) {
      throw new Error(`createProxyIdentifier (${factoryName}) uses ${name}, which is not an empty literal`);
    }
    support.push(`var ${name} = ${init.getText(sf)};`);
  }
  // Every `new ProxyIdentifier(...)` must be the factory's.
  let news = 0;
  walk(sf, (node) => {
    if (ts.isNewExpression(node) && ts.isIdentifier(node.expression) && node.expression.text === className) news++;
  });
  if (news !== 1) throw new Error(`The bundle creates ProxyIdentifiers outside ${factoryName} (${news})`);
  // The calls, as they are evaluated: the bundle's module scope runs in
  // source order, and the factory is only called in object literals there.
  const calls = [];
  walk(sf, (node) => {
    if (ts.isCallExpression(node) && ts.isIdentifier(node.expression) && node.expression.text === factoryName) {
      // A same-named function in another scope shadows the factory: the
      // calls we want are `KEY:N("SID")` in object literals.
      if (node.arguments.length === 1 && ts.isStringLiteral(node.arguments[0])
        && ts.isPropertyAssignment(node.parent) && ts.isObjectLiteralExpression(node.parent.parent)) {
        calls.push(node);
      }
    }
  });
  const literals = [...new Set(calls.map((c) => c.parent.parent))];
  if (literals.length !== 2) throw new Error(`Expected MainContext and ExtHostContext literals, found ${literals.length}`);
  for (const lit of literals) {
    for (const prop of lit.properties) {
      if (!ts.isPropertyAssignment(prop) || !calls.includes(prop.initializer)) {
        throw new Error(`Unexpected member in a proxy identifier literal: ${prop.getText(sf).slice(0, 80)}`);
      }
    }
  }
  const script = `${classText}\n${support.join('\n')}\n${factory.getText(sf)}\n`
    + `[${literals.map((l) => `(${l.getText(sf)})`).join(',')}]`;
  const [main, ext] = vm.runInNewContext(script, {}, { timeout: 5000 });
  const out = [];
  for (const [context, obj] of [['MainContext', main], ['ExtHostContext', ext]]) {
    for (const [key, id] of Object.entries(obj)) out.push({ context, key, sid: id.sid, nid: id.nid });
  }
  if (!out.every((e) => e.context === 'MainContext' ? e.key.startsWith('MainThread') : e.key.startsWith('ExtHost'))) {
    throw new Error('The bundle\'s identifier literals are not MainContext then ExtHostContext');
  }
  return out;
}

// --- The protocol, with the TypeScript checker ------------------------------

const absProtocol = path.resolve(checkout, protocolPath);
const baseConfig = ts.readConfigFile(path.join(checkout, 'src/tsconfig.base.json'), ts.sys.readFile);
if (baseConfig.error) throw new Error(ts.flattenDiagnosticMessageText(baseConfig.error.messageText, '\n'));
const parsed = ts.parseJsonConfigFileContent(baseConfig.config, ts.sys, path.join(checkout, 'src'));
// The protocol uses the global `DebugProtocol` namespace, which no import
// brings in.
const globals = [path.resolve(checkout, 'src/vs/workbench/contrib/debug/common/debugProtocol.d.ts')];
const program = ts.createProgram([absProtocol, ...globals], {
  ...parsed.options, noEmit: true, skipLibCheck: true, types: [],
});
const checker = program.getTypeChecker();
const sf = program.getSourceFile(absProtocol);
if (!sf) throw new Error(`Cannot read ${absProtocol}`);

/** `MainContext`/`ExtHostContext` entries in source order. */
function sourceIdentifiers() {
  const out = [];
  for (const st of sf.statements) {
    if (!ts.isVariableStatement(st)) continue;
    for (const decl of st.declarationList.declarations) {
      const context = decl.name.getText(sf);
      if (context !== 'MainContext' && context !== 'ExtHostContext') continue;
      for (const prop of decl.initializer.properties) {
        const call = prop.initializer;
        if (!ts.isCallExpression(call) || call.expression.getText(sf) !== 'createProxyIdentifier'
          || call.typeArguments?.length !== 1 || !ts.isStringLiteral(call.arguments[0])) {
          throw new Error(`Unexpected ${context} member ${prop.getText(sf)}`);
        }
        out.push({
          context, key: prop.name.getText(sf), sid: call.arguments[0].text,
          nid: out.length + 1, shapeNode: call.typeArguments[0],
        });
      }
    }
  }
  if (!out.length) throw new Error('No proxy identifiers in extHost.protocol.ts');
  return out;
}

const fromBundle = bundleIdentifiers(bundlePath);
const identifiers = sourceIdentifiers();
{
  const problems = [];
  if (fromBundle.length !== identifiers.length) {
    problems.push(`bundle has ${fromBundle.length} identifiers, source ${identifiers.length}`);
  }
  for (const b of fromBundle) {
    const s = identifiers.find((i) => i.nid === b.nid);
    if (!s || s.context !== b.context || s.key !== b.key || s.sid !== b.sid) {
      problems.push(`nid ${b.nid}: bundle ${b.context}.${b.key}('${b.sid}'), source ${s ? `${s.context}.${s.key}('${s.sid}')` : 'none'}`);
    }
  }
  if (problems.length) {
    throw new Error(`Proxy identifiers differ between the bundle and extHost.protocol.ts:\n  ${problems.join('\n  ')}`);
  }
}

// --- Type mapping -------------------------------------------------------------

/** Dart types: {kind, nullable, elem?, undef?}. */
const T = {
  string: { kind: 'string' }, num: { kind: 'num' }, int: { kind: 'int' }, bool: { kind: 'bool' },
  object: { kind: 'object' }, map: { kind: 'map' }, uri: { kind: 'uri' }, buffer: { kind: 'buffer' },
  void: { kind: 'void' }, null: { kind: 'null' }, undef: { kind: 'undefined' }, token: { kind: 'token' },
};
const list = (elem) => ({ kind: 'list', elem });
const dict = (elem) => ({ kind: 'dict', elem });
const future = (elem) => ({ kind: 'future', elem });
const tupleList = list(T.object);

function sameType(a, b) {
  return a.kind === b.kind && !!a.nullable === !!b.nullable
    && (a.elem === undefined || sameType(a.elem, b.elem));
}

const isObjectish = (t) => t.kind === 'map' || t.kind === 'dict';

/** Combines union members. */
function union(members) {
  let nullable = false;
  let undef = false;
  let hasNull = false;
  const rest = [];
  for (const m of members) {
    if (m.kind === 'undefined' || m.kind === 'void') { nullable = true; undef = true; continue; }
    if (m.kind === 'null') { nullable = true; hasNull = true; continue; }
    if (m.nullable) { nullable = true; undef ||= m.undef; hasNull ||= m.hasNull; }
    rest.push({ ...m, nullable: false, undef: false, hasNull: false });
  }
  let t;
  if (!rest.length) t = T.object;
  else if (rest.every((m) => sameType(m, rest[0]))) t = rest[0];
  else if (rest.every((m) => m.kind === 'int' || m.kind === 'num')) t = T.num;
  else if (rest.every(isObjectish)) t = T.map;
  else t = T.object;
  return nullable ? { ...t, nullable: true, undef: undef && !hasNull, hasNull } : t;
}

const declFile = (decl) => path.relative(path.join(checkout, 'src'), decl.getSourceFile().fileName);

function resolveSymbol(node) {
  let sym = checker.getSymbolAtLocation(node);
  if (sym && sym.flags & ts.SymbolFlags.Alias) sym = checker.getAliasedSymbol(sym);
  return sym;
}

function enumKind(decl) {
  const values = decl.members.map((m) => {
    const v = checker.getConstantValue(m);
    return typeof v;
  });
  if (values.every((v) => v === 'number')) return T.int;
  if (values.every((v) => v === 'string')) return T.string;
  return T.object;
}

/** Maps a type with the checker, for what has no syntax of its own. */
function mapType(type, depth = 0) {
  if (depth > 8) return T.object;
  const f = type.flags;
  if (f & (ts.TypeFlags.Any | ts.TypeFlags.Unknown | ts.TypeFlags.Never)) return T.object;
  if (f & ts.TypeFlags.Undefined || f & ts.TypeFlags.Void) return T.undef;
  if (f & ts.TypeFlags.Null) return T.null;
  if (type.isUnion()) {
    // `boolean` is `true | false`.
    if (f & ts.TypeFlags.Boolean) return T.bool;
    return union(type.types.map((t) => mapType(t, depth + 1)));
  }
  if (f & (ts.TypeFlags.NumberLiteral | ts.TypeFlags.EnumLiteral) && f & ts.TypeFlags.NumberLike) {
    return f & ts.TypeFlags.NumberLiteral && !Number.isInteger(type.value) ? T.num : T.int;
  }
  if (f & ts.TypeFlags.StringLike) return T.string;
  if (f & ts.TypeFlags.NumberLike) return T.num;
  if (f & ts.TypeFlags.BooleanLike) return T.bool;
  if (f & ts.TypeFlags.TypeParameter) return T.object;
  if (f & ts.TypeFlags.Object || type.isIntersection()) {
    const name = (type.aliasSymbol ?? type.symbol)?.name;
    if (name === 'UriComponents' || name === 'URI') return T.uri;
    if (name === 'VSBuffer') return T.buffer;
    if (checker.isTupleType(type)) return tupleList;
    if (checker.isArrayType(type)) return list(mapType(checker.getTypeArguments(type)[0], depth + 1));
    if (type.getCallSignatures().length && !type.getProperties().length) return T.object;
    if (!type.getProperties().length) {
      const index = checker.getIndexInfosOfType(type);
      if (index.length === 1) return dict(mapType(index[0].type, depth + 1));
    }
    return T.map;
  }
  return T.object;
}

/** Maps a type node; [seen] guards recursive aliases. */
function mapNode(node, seen = new Set()) {
  switch (node.kind) {
    case ts.SyntaxKind.ParenthesizedType: return mapNode(node.type, seen);
    case ts.SyntaxKind.StringKeyword: return T.string;
    case ts.SyntaxKind.NumberKeyword: return T.num;
    case ts.SyntaxKind.BooleanKeyword: return T.bool;
    case ts.SyntaxKind.AnyKeyword: case ts.SyntaxKind.UnknownKeyword: case ts.SyntaxKind.NeverKeyword:
    case ts.SyntaxKind.BigIntKeyword: case ts.SyntaxKind.SymbolKeyword: case ts.SyntaxKind.FunctionType:
    case ts.SyntaxKind.ConstructorType:
      return T.object;
    case ts.SyntaxKind.ObjectKeyword: return T.map;
    case ts.SyntaxKind.VoidKeyword: return T.void;
    case ts.SyntaxKind.UndefinedKeyword: return T.undef;
    case ts.SyntaxKind.TemplateLiteralType: return T.string;
    case ts.SyntaxKind.LiteralType: {
      const lit = node.literal;
      if (lit.kind === ts.SyntaxKind.NullKeyword) return T.null;
      if (ts.isStringLiteral(lit)) return T.string;
      if (ts.isNumericLiteral(lit)) return Number.isInteger(Number(lit.text)) ? T.int : T.num;
      if (lit.kind === ts.SyntaxKind.TrueKeyword || lit.kind === ts.SyntaxKind.FalseKeyword) return T.bool;
      if (ts.isPrefixUnaryExpression(lit)) return T.int; // -1
      return mapType(checker.getTypeFromTypeNode(node));
    }
    case ts.SyntaxKind.UnionType: {
      const members = node.types.map((t) => mapNode(t, seen));
      return union(members);
    }
    case ts.SyntaxKind.ArrayType: return list(mapNode(node.elementType, seen));
    case ts.SyntaxKind.TupleType: return tupleList;
    case ts.SyntaxKind.TypeOperator:
      if (node.operator === ts.SyntaxKind.ReadonlyKeyword) return mapNode(node.type, seen);
      return mapType(checker.getTypeFromTypeNode(node));
    case ts.SyntaxKind.TypeLiteral: {
      const members = node.members;
      if (members.length === 1 && ts.isIndexSignatureDeclaration(members[0])) {
        return dict(mapNode(members[0].type, seen));
      }
      return T.map;
    }
    case ts.SyntaxKind.MappedType: return T.map;
    case ts.SyntaxKind.IntersectionType: {
      const members = node.types.map((t) => mapNode(t, seen));
      if (members.some(isObjectish)) return T.map;
      return mapType(checker.getTypeFromTypeNode(node));
    }
    case ts.SyntaxKind.TypeReference: return mapReference(node, seen);
    default:
      return mapType(checker.getTypeFromTypeNode(node));
  }
}

function mapReference(node, seen) {
  const sym = resolveSymbol(node.typeName);
  const args = node.typeArguments ?? [];
  if (!sym) return T.object;
  const name = sym.name;
  const decl = sym.declarations?.[0];
  if (!decl) return T.object;
  const file = declFile(decl);
  if (file.startsWith('..') || file.includes('node_modules') || /typescript[\\/]lib/.test(decl.getSourceFile().fileName)) {
    // The standard library.
    switch (name) {
      case 'Promise': case 'PromiseLike': return future(args[0] ? mapNode(args[0], seen) : T.object);
      case 'Array': case 'ReadonlyArray': return list(args[0] ? mapNode(args[0], seen) : T.object);
      case 'Record': {
        const key = args[0] ? mapNode(args[0], seen) : T.object;
        if (key.kind === 'string' || key.kind === 'num' || key.kind === 'int') return dict(mapNode(args[1], seen));
        return T.map;
      }
      case 'Partial': case 'Readonly': case 'Required': case 'Pick': case 'Omit':
        return T.map;
      default:
        return mapType(checker.getTypeFromTypeNode(node));
    }
  }
  if ((name === 'UriComponents' || name === 'URI') && file === 'vs/base/common/uri.ts') return T.uri;
  if (name === 'VSBuffer' && file === 'vs/base/common/buffer.ts') return T.buffer;
  if (name === 'CancellationToken' && file === 'vs/base/common/cancellation.ts') return T.token;
  if (name === 'SerializableObjectWithBuffers') return T.object;
  if (name === 'Thenable') return future(args[0] ? mapNode(args[0], seen) : T.object);
  if ((name === 'IStringDictionary' || name === 'INumberDictionary') && args.length === 1) {
    return dict(mapNode(args[0], seen));
  }
  if (ts.isTypeParameterDeclaration(decl)) return T.object;
  if (ts.isEnumDeclaration(decl)) return enumKind(decl);
  if (ts.isEnumMember(decl)) return enumKind(decl.parent);
  if (ts.isTypeAliasDeclaration(decl)) {
    if (decl.typeParameters?.length || seen.has(decl)) return mapType(checker.getTypeFromTypeNode(node));
    const next = new Set(seen);
    next.add(decl);
    return mapNode(decl.type, next);
  }
  if (ts.isInterfaceDeclaration(decl) || ts.isClassDeclaration(decl)) {
    const type = checker.getTypeFromTypeNode(node);
    if (checker.isArrayType(type)) return list(mapType(checker.getTypeArguments(type)[0]));
    return T.map;
  }
  return mapType(checker.getTypeFromTypeNode(node));
}

// --- Shapes -------------------------------------------------------------------

const dartKeywords = new Set(('assert break case catch class const continue default do else enum extends false '
  + 'final finally for if in is new null rethrow return super switch this throw true try var void while with '
  + 'await yield late required covariant dynamic Function').split(' '));

function dartParamName(name, taken) {
  let n = name.replace(/^_+/, '');
  if (!n) n = 'arg';
  if (dartKeywords.has(n)) n = `${n}Arg`;
  while (taken.has(n)) n = `${n}Arg`;
  taken.add(n);
  return n;
}

const collapse = (s) => s.replace(/\s+/g, ' ').replace(/\( /g, '(').replace(/ \)/g, ')').trim();

function methodsOf(entry) {
  const shapeType = checker.getTypeFromTypeNode(entry.shapeNode);
  const methods = [];
  for (const prop of checker.getPropertiesOfType(shapeType)) {
    const name = prop.name;
    // RPC proxies only forward `$` names (`RPCProtocol._createProxy`).
    if (!name.startsWith('$')) continue;
    const decls = prop.declarations ?? [];
    if (decls.length !== 1) throw new Error(`${entry.key}.${name}: ${decls.length} declarations (overloads are not supported)`);
    let sig = decls[0];
    let docNode = sig;
    if (ts.isPropertySignature(sig) && sig.type && ts.isFunctionTypeNode(sig.type)) sig = sig.type;
    if (!ts.isMethodSignature(sig) && !ts.isFunctionTypeNode(sig)) {
      throw new Error(`${entry.key}.${name}: not a method`);
    }
    const taken = new Set(['token']);
    const params = [];
    let token = false;
    sig.parameters.forEach((p, i) => {
      // A destructured parameter has no name of its own.
      const pname = ts.isIdentifier(p.name) ? p.name.text : `arg${i}`;
      let t = p.type ? mapNode(p.type) : T.object;
      if (t.kind === 'token' && i === sig.parameters.length - 1) {
        token = true;
        return;
      }
      if (t.kind === 'token') {
        // Upstream only takes a token off the end of the arguments: one
        // before others goes as JSON (what `CancellationToken.None` is),
        // and cannot cancel anything.
        params.push({ tsName: pname, name: dartParamName(pname, taken), type: { kind: 'inlineToken' }, optional: false, rest: false });
        return;
      }
      if (t.kind === 'void' || t.kind === 'undefined' || t.kind === 'null') t = T.object;
      if (p.questionToken) t = t.kind === 'object' ? t : { ...t, nullable: true, undef: !t.hasNull };
      const rest = !!p.dotDotDotToken;
      if (rest && t.kind !== 'list') throw new Error(`${entry.key}.${name}: rest parameter ${pname} is not an array`);
      params.push({
        tsName: pname, name: dartParamName(pname, taken), type: t, optional: !!p.questionToken, rest,
        ts: collapse(p.getText()),
      });
    });
    if (token && params.some((p) => p.rest)) throw new Error(`${entry.key}.${name}: rest parameters and a token`);
    let result = sig.type ? mapNode(sig.type) : T.object;
    const isPromise = result.kind === 'future';
    if (isPromise) result = result.elem;
    if (result.kind === 'undefined' || result.kind === 'null') result = T.void;
    const jsDoc = ts.getJSDocCommentsAndTags(docNode).filter(ts.isJSDoc)
      .map((d) => (typeof d.comment === 'string' ? d.comment : ts.getTextOfJSDocComment(d.comment) ?? ''))
      .join('\n').trim();
    methods.push({
      name, params, token, result, isPromise, jsDoc,
      ts: collapse(`${name}(${sig.parameters.map((p) => p.getText()).join(', ')})${sig.type ? `: ${sig.type.getText()}` : ''}`),
    });
  }
  return methods;
}

// --- Dart rendering -------------------------------------------------------------

function dart(t) {
  let s;
  switch (t.kind) {
    case 'string': s = 'String'; break;
    case 'num': s = 'num'; break;
    case 'int': s = 'int'; break;
    case 'bool': s = 'bool'; break;
    case 'uri': s = 'VsUri'; break;
    case 'buffer': s = 'RpcBuffer'; break;
    case 'map': s = 'Map<String, Object?>'; break;
    case 'dict': s = `Map<String, ${dart(t.elem)}>`; break;
    case 'list': s = `List<${dart(t.elem)}>`; break;
    case 'object': case 'null': case 'undefined': case 'token': return 'Object?';
    case 'inlineToken': return 'CancellationToken';
    case 'void': return 'void';
    default: throw new Error(`No Dart type for ${t.kind}`);
  }
  return t.nullable ? `${s}?` : s;
}

function decoder(t) {
  let d;
  switch (t.kind) {
    case 'string': d = 'decodeString'; break;
    case 'num': d = 'decodeNum'; break;
    case 'int': d = 'decodeInt'; break;
    case 'bool': d = 'decodeBool'; break;
    case 'uri': d = 'decodeUri'; break;
    case 'buffer': d = 'decodeBuffer'; break;
    case 'map': d = 'decodeMap'; break;
    case 'dict': d = `decodeMapOf(${decoder(t.elem)})`; break;
    case 'list': d = `decodeListOf(${decoder(t.elem)})`; break;
    case 'object': case 'null': case 'undefined': case 'token': return 'decodeObject';
    default: throw new Error(`No decoder for ${t.kind}`);
  }
  return t.nullable ? `decodeNullable(${d})` : d;
}

const lowerFirst = (s) => s[0].toLowerCase() + s.slice(1);
const dartString = (s) => (s.includes("'") ? `"${s}"` : `'${s}'`);
const raw = (s) => `r'${s}'`;

function docLines(indent, method) {
  const lines = [];
  if (method.jsDoc) {
    for (const l of method.jsDoc.split('\n')) lines.push(`${indent}/// ${l.trim()}`.trimEnd());
    lines.push(`${indent}///`);
  }
  lines.push(`${indent}/// \`${method.ts.replace(/`/g, "'")}\``);
  return lines.join('\n');
}

function header(what) {
  return `/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// GENERATED FILE - DO NOT EDIT. Regenerate with tool/generate_exthost_protocol.mjs.
//
// ${what}
//
// Generated from VS Code ${revision} (${version}):
// ${protocolPath}; proxy identifier numbers from the compiled
// out/vs/workbench/api/node/extensionHostProcess.js.`;
}

const mainEntries = identifiers.filter((e) => e.context === 'MainContext');
const extEntries = identifiers.filter((e) => e.context === 'ExtHostContext');
for (const e of identifiers) e.methods = methodsOf(e);

function renderIdentifiers() {
  const out = [header('The extension host protocol\'s proxy identifiers (`MainContext`, `ExtHostContext`).'), `
/// A numbered RPC actor (\`ProxyIdentifier\`): [nid] on the wire, [sid] in
/// logs, [key] its name in \`MainContext\`/\`ExtHostContext\`.
final class ProxyIdentifier {
  const ProxyIdentifier(this.nid, this.sid, this.key);

  final int nid;
  final String sid;
  final String key;

  @override
  String toString() => sid;
}
`];
  for (const [name, entries, doc] of [
    ['MainContext', mainEntries, 'The actors on the main thread (BaoCode), which the extension host calls.'],
    ['ExtHostContext', extEntries, 'The actors in the extension host, which the main thread calls.'],
  ]) {
    out.push(`/// \`${name}\`: ${doc}\nabstract final class ${name} {`);
    for (const e of entries) {
      out.push(`  static const ${lowerFirst(e.key)} = ProxyIdentifier(${e.nid}, ${dartString(e.sid)}, ${dartString(e.key)});`);
    }
    out.push(`\n  static const all = [${entries.map((e) => lowerFirst(e.key)).join(', ')}];\n}\n`);
  }
  out.push('/// Every proxy identifier\'s [ProxyIdentifier.sid], by [ProxyIdentifier.nid].');
  out.push('const Map<int, String> proxyIdentifierNames = {');
  for (const e of identifiers) out.push(`  ${e.nid}: ${dartString(e.sid)},`);
  out.push('};\n');
  return out.join('\n');
}

function shapeParams(m) {
  const ps = m.params.map((p) => `${dart(p.type)} ${p.name}`);
  if (m.token) ps.push('CancellationToken token');
  return ps.join(', ');
}

function mainResult(m) {
  if (m.result.kind === 'void') return 'FutureOr<void>';
  return m.isPromise ? `Future<${dart(m.result)}>` : `FutureOr<${dart(m.result)}>`;
}

function renderMainThread() {
  const out = [header('The main thread\'s shapes (`MainThread*Shape`): what the extension host\n// calls. Each has an interface, a fallback that rejects every call (extend\n// it and override what is supported) and an actor that decodes requests.'), `
// ignore_for_file: non_constant_identifier_names

import 'dart:async';

import '../base/cancellation.dart';
import '../base/uri.dart';
import '../parity.dart';
import '../rpc/rpc_args.dart';
import '../rpc/rpc_protocol.dart';
import 'proxy_identifiers.g.dart';

Never _unsupported(String shape, String method) {
  ExtHostParity.instance.recordUnsupported(shape, method);
  throw RpcUnsupported('$shape.$method');
}
`];
  for (const e of mainEntries) {
    const shape = `${e.key}Shape`;
    const unsupported = `${e.key}Unsupported`;
    const actor = `${e.key}Actor`;
    const id = `MainContext.${lowerFirst(e.key)}`;
    out.push(`// --- ${e.key} ${'-'.repeat(Math.max(3, 74 - e.key.length))}\n`);
    out.push(`/// \`${e.shapeNode.getText()}\` (\`${e.sid}\`).`);
    out.push(`abstract interface class ${shape} {`);
    e.methods.forEach((m, i) => {
      if (i) out.push('');
      out.push(docLines('  ', m));
      out.push(`  ${mainResult(m)} ${m.name}(${shapeParams(m)});`);
    });
    out.push('}\n');
    out.push(`/// [${shape}] with every method rejected as unsupported, and counted in`);
    out.push('/// [ExtHostParity]. Implementations extend it and override what they support.');
    out.push(`base class ${unsupported} implements ${shape} {`);
    out.push(`  const ${unsupported}();\n`);
    e.methods.forEach((m, i) => {
      if (i) out.push('');
      out.push(`  @override\n  ${mainResult(m)} ${m.name}(${shapeParams(m)}) =>\n      _unsupported(${dartString(e.key)}, ${raw(m.name)});`);
    });
    out.push('}\n');
    out.push(`/// Decodes requests to [${id}] and calls [target].`);
    out.push(`final class ${actor} implements RpcActor {\n  ${actor}(this.target);\n`);
    out.push(`  static const identifier = ${id};\n\n  final ${shape} target;\n`);
    out.push('  @override\n  Future<Object?> invoke(String method, List<Object?> args) async {');
    if (!e.methods.length) {
      out.push(`    throw RpcUnsupported('${e.key}.$method');\n  }\n}\n`);
      continue;
    }
    out.push(`    final a = RpcArgs('${e.key}.$method', args);`);
    out.push('    switch (method) {');
    for (const m of e.methods) {
      const call = [
        ...m.params.map((p, i) => (p.type.kind === 'inlineToken' ? 'CancellationToken.none' : p.rest
          ? `a.rest(${i}, ${decoder(p.type.elem)}, '${p.tsName}')`
          : `a.arg(${i}, ${decoder(p.type)}, '${p.tsName}')`)),
        ...(m.token ? ['a.token'] : []),
      ].join(', ');
      out.push(`      case ${raw(m.name)}:`);
      if (m.result.kind === 'void') {
        out.push(`        await target.${m.name}(${call});\n        return null;`);
      } else {
        out.push(`        return await target.${m.name}(${call});`);
      }
    }
    out.push(`      default:\n        throw RpcUnsupported('${e.key}.$method');\n    }\n  }\n}\n`);
  }
  out.push('/// For every main thread shape, by [ProxyIdentifier.nid], an actor whose');
  out.push('/// every method is rejected as unsupported and counted in [ExtHostParity]:');
  out.push('/// register these for the shapes BaoCode does not implement.');
  out.push('Map<int, RpcActor Function()> get unsupportedMainThreadActors => {');
  for (const e of mainEntries) {
    out.push(`  MainContext.${lowerFirst(e.key)}.nid: () => ${e.key}Actor(const ${e.key}Unsupported()),`);
  }
  out.push('};\n');
  return out.join('\n');
}

function encodeArg(p) {
  if (p.type.kind === 'inlineToken') return `encodeInlineToken(${p.name})`;
  if (p.type.nullable && p.type.undef) return `${p.name} ?? rpcUndefined`;
  return p.name;
}

function renderExtHost() {
  const out = [header('Proxies for the extension host\'s shapes (`ExtHost*Shape`): what the main\n// thread calls.'), `
// ignore_for_file: non_constant_identifier_names

import '../base/cancellation.dart';
import '../base/uri.dart';
import '../rpc/rpc_args.dart';
import '../rpc/rpc_protocol.dart';
import 'proxy_identifiers.g.dart';
`];
  for (const e of extEntries) {
    const proxy = `${e.key}Proxy`;
    const id = `ExtHostContext.${lowerFirst(e.key)}`;
    out.push(`/// Calls \`${e.shapeNode.getText()}\` (\`${e.sid}\`) in the extension host.`);
    out.push(`final class ${proxy} {\n  ${proxy}(this._rpc);\n\n  static const identifier = ${id};\n`);
    // A shape with no methods yet has nothing to call.
    if (!e.methods.length) out.push('  // ignore: unused_field');
    out.push('  final RpcProtocol _rpc;');
    for (const m of e.methods) {
      // Trailing optional parameters stay optional for callers.
      let firstOptional = m.params.length;
      while (firstOptional > 0 && m.params[firstOptional - 1].optional && !m.params[firstOptional - 1].rest) firstOptional--;
      const proxyParam = (p) => `${dart(p.type)}${p.type.kind === 'inlineToken' ? '?' : ''} ${p.name}`;
      const required = m.params.slice(0, firstOptional).map(proxyParam);
      const optional = m.params.slice(firstOptional).map(proxyParam);
      let params = required.join(', ');
      if (optional.length && !m.token) params += `${params ? ', ' : ''}[${optional.join(', ')}]`;
      else if (optional.length) params += `${params ? ', ' : ''}${optional.map((o) => o).join(', ')}`;
      if (m.token) params += `${params ? ', ' : ''}{CancellationToken? token}`;
      const args = m.params.map((p) => (p.rest ? `...${p.name}` : encodeArg(p))).join(', ');
      const call = `_rpc.call(identifier.nid, ${raw(m.name)}, [${args}]${m.token ? ', token: token' : ''})`;
      out.push('');
      out.push(docLines('  ', m));
      const res = m.result;
      if (res.kind === 'void') {
        out.push(`  Future<void> ${m.name}(${params}) => ${call};`);
      } else if (res.kind === 'object' || res.kind === 'null' || res.kind === 'undefined') {
        out.push(`  Future<Object?> ${m.name}(${params}) => ${call};`);
      } else {
        out.push(`  Future<${dart(res)}> ${m.name}(${params}) async =>\n      decodeReply(${raw(`${e.key}.${m.name}`)}, await ${call}, ${decoder(res)});`);
      }
    }
    out.push('}\n');
  }
  return out.join('\n');
}

function renderMethods() {
  const out = [header('The main thread shapes\' methods, for parity reports.'), `
/// Every main thread shape's (\`MainContext\` key's) \`$\` methods.
Map<String, List<String>> get exthostProtocolMethods => const {`];
  for (const e of mainEntries) {
    out.push(`  ${dartString(e.key)}: [${e.methods.map((m) => raw(m.name)).join(', ')}],`);
  }
  out.push('};\n');
  return out.join('\n');
}

mkdirSync(outDir, { recursive: true });
const files = {
  'proxy_identifiers.g.dart': renderIdentifiers(),
  'main_thread_shapes.g.dart': renderMainThread(),
  'ext_host_proxies.g.dart': renderExtHost(),
  'protocol_methods.g.dart': renderMethods(),
};
for (const [name, text] of Object.entries(files)) writeFileSync(path.join(outDir, name), text);
try {
  execFileSync('dart', ['format', ...Object.keys(files).map((f) => path.join(outDir, f))], { stdio: 'ignore' });
} catch {
  console.warn('dart format failed or is missing: the generated files are unformatted');
}

const count = (es) => es.reduce((n, e) => n + e.methods.length, 0);
const fallbacks = identifiers.flatMap((e) => e.methods.flatMap((m) => m.params)).filter((p) => p.type.kind === 'object').length;
if (process.env.EXTHOST_CODEGEN_FALLBACKS) {
  // What maps to Object?, to review the mapping.
  for (const e of identifiers) {
    for (const m of e.methods) {
      for (const p of m.params.filter((p) => p.type.kind === 'object')) console.log(`  ${e.key}.${m.name} ${p.ts}`);
    }
  }
}
console.log(`${identifiers.length} proxy identifiers (bundle and source agree); `
  + `${mainEntries.length} main thread shapes, ${count(mainEntries)} methods; `
  + `${extEntries.length} extension host shapes, ${count(extEntries)} methods; `
  + `${fallbacks} parameters as Object?`);
if (!existsSync(path.join(outDir, 'proxy_identifiers.g.dart'))) process.exit(1);
