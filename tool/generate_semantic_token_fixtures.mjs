// Runs the real upstream VS Code semantic token styling code, never the Dart
// port, to create the golden data replayed by
// test/ide/editor/textmate/workbench/semantic_token_styling_test.dart.
//
// Usage: node tool/generate_semantic_token_fixtures.mjs [vscode-checkout] [output.json.gz]
//   [vscode-checkout]  a checkout of microsoft/vscode at `revision` (default: a sparse,
//                      blob-less clone into /tmp/baocode-semantic-tokens-vscode-<rev>)
//   [output.json.gz]   default test/fixtures/theme/semantic_tokens.json.gz
//
// What it does, at VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// 1. Bundles the unmodified tokenClassificationRegistry.ts, colorThemeData.ts,
//    tokenClassificationExtensionPoint.ts, semanticTokensProviderStyling.ts and
//    their imports with esbuild (the version build/package.json pins). The only
//    stub is the extension registry (workbench/services/extensions/common/
//    extensionsRegistry.ts): it records the extension points so their handlers
//    can be called directly.
// 2. Collects the built-in extensions the desktop product ships, as
//    generate_language_detection_fixtures.mjs does (build/lib/extensions.ts:
//    local extensions minus `excludedExtensions` and product.json
//    `builtInExtensions`, plus `copilot`, plus the marketplace VSIXs, sorted by
//    folder name like extensionCmp), and hands their `semanticTokenTypes`,
//    `semanticTokenModifiers` and `semanticTokenScopes` to the upstream
//    handlers in extension point registration order, as the workbench does.
// 3. Loads every contributed color theme with `ColorThemeData.fromExtensionTheme`
//    and `ensureLoaded`, without customizations, and checks the set against
//    assets/textmate/manifest.json. Two small synthetic themes (stored in the
//    fixture) add semantic font styles and scope selector forms the bundled
//    themes lack.
// 4. Records, per theme, `semanticHighlighting`, `tokenColorMap`, and
//    `SemanticTokensProviderStyling.getMetadata` for every token type of a
//    legend × modifier set × language. `metadata` lists the distinct values;
//    `matrix[(language * types + type) * modifierSets + set]` indexes it.
//    It also records the registry's default rules and selector match scores.
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync } from 'node:fs';
import { mkdir, mkdtemp, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { gzipSync, inflateRawSync } from 'node:zlib';

const revision = '6a598d4a13031703d483d103c1d934a36ad27971';
const repository = 'https://github.com/microsoft/vscode.git';

const args = process.argv.slice(2);
if (args.length > 2 || args.some(a => a.startsWith('--'))) {
  throw new Error('Usage: node tool/generate_semantic_token_fixtures.mjs [vscode-checkout] [output.json.gz]');
}
const [checkoutArg, output = 'test/fixtures/theme/semantic_tokens.json.gz'] = args;

function git(gitArgs, options = {}) {
  return execFileSync('git', gitArgs, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'inherit'], ...options });
}

// --- Pinned sources -------------------------------------------------------------

const sparsePaths = [
  '/src/vs/base/', '/src/vs/nls.ts', '/src/vs/nls.messages.ts', '/src/vs/platform/', '/src/vs/editor/common/',
  '/src/vs/workbench/services/themes/common/', '/src/vs/workbench/services/extensions/common/',
  '/extensions/*/package.json', '/extensions/*/package.nls.json', '/extensions/theme-*/themes/',
  '/build/lib/extensions.ts', '/build/gulpfile.vscode.ts', '/build/package.json', '/product.json',
];

async function checkout() {
  const root = checkoutArg ?? join(tmpdir(), `baocode-semantic-tokens-vscode-${revision.slice(0, 8)}`);
  if (!existsSync(join(root, '.git'))) {
    if (checkoutArg) throw new Error(`${root} is not a git checkout`);
    git(['clone', '--filter=blob:none', '--no-checkout', '--sparse', repository, root], { stdio: 'inherit' });
    git(['-C', root, 'sparse-checkout', 'set', '--no-cone', ...sparsePaths], { stdio: 'inherit' });
    git(['-C', root, 'checkout', '--quiet', revision], { stdio: 'inherit' });
  }
  const head = git(['-C', root, 'rev-parse', 'HEAD']).trim();
  if (head !== revision) throw new Error(`Expected ${root} at ${revision}, found ${head}`);
  return root;
}

const root = await checkout();
const read = path => readFile(join(root, path), 'utf8');

// --- Built-in extension set and order -------------------------------------------

const extensionsTs = await read('build/lib/extensions.ts');
const excludedMatch = /const excludedExtensions = \[([^\]]*)\];/.exec(extensionsTs);
if (!excludedMatch) throw new Error('excludedExtensions not found in build/lib/extensions.ts');
const excludedExtensions = [...excludedMatch[1].matchAll(/'([^']+)'/g)].map(m => m[1]);
if (!/\.filter\(\(\{ name \}\) => excludedExtensions\.indexOf\(name\) === -1\)/.test(extensionsTs) ||
  !/\.filter\(\(\{ name \}\) => builtInExtensions\.every\(b => b\.name !== name\)\)/.test(extensionsTs) ||
  !/export function packageCopilotExtensionStream\(\)[\s\S]*?path\.join\(root, 'extensions', 'copilot'\)/.test(extensionsTs)) {
  throw new Error('build/lib/extensions.ts no longer matches the documented rule');
}
const product = JSON.parse(await read('product.json'));
const marketplaceBuiltIns = product.builtInExtensions ?? [];

function readZipEntry(buffer, name) {
  const eocd = buffer.lastIndexOf(Buffer.from([0x50, 0x4b, 0x05, 0x06]));
  if (eocd < 0) throw new Error('Not a zip file');
  const count = buffer.readUInt16LE(eocd + 10);
  let offset = buffer.readUInt32LE(eocd + 16);
  for (let i = 0; i < count; i++) {
    const method = buffer.readUInt16LE(offset + 10);
    const size = buffer.readUInt32LE(offset + 20);
    const nameLength = buffer.readUInt16LE(offset + 28);
    const extraLength = buffer.readUInt16LE(offset + 30);
    const commentLength = buffer.readUInt16LE(offset + 32);
    const local = buffer.readUInt32LE(offset + 42);
    if (buffer.toString('utf8', offset + 46, offset + 46 + nameLength) === name) {
      const start = local + 30 + buffer.readUInt16LE(local + 26) + buffer.readUInt16LE(local + 28);
      const data = buffer.subarray(start, start + size);
      if (method === 0) return data;
      if (method === 8) return inflateRawSync(data);
      throw new Error(`Unsupported zip method ${method}`);
    }
    offset += 46 + nameLength + extraLength + commentLength;
  }
  return undefined;
}

async function download(url) {
  for (let attempt = 1; ; attempt++) {
    try {
      const response = await fetch(url, { headers: { 'User-Agent': 'baocode-semantic-token-fixtures' } });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      return Buffer.from(await response.arrayBuffer());
    } catch (error) {
      if (attempt >= 4) throw new Error(`Cannot download ${url}: ${error.message}`);
      await new Promise(resolve => setTimeout(resolve, 500 * attempt));
    }
  }
}

const builtIns = [];
for (const folder of (await readdir(join(root, 'extensions'))).sort()) {
  const manifestPath = join(root, 'extensions', folder, 'package.json');
  if (!existsSync(manifestPath)) continue;
  const local = !excludedExtensions.includes(folder) && marketplaceBuiltIns.every(b => b.name !== folder);
  if (!local && folder !== 'copilot') continue;
  const nlsPath = join(root, 'extensions', folder, 'package.nls.json');
  builtIns.push({
    folder, location: join(root, 'extensions', folder),
    manifest: JSON.parse(await readFile(manifestPath, 'utf8')),
    nls: existsSync(nlsPath) ? JSON.parse(await readFile(nlsPath, 'utf8')) : undefined,
  });
}
for (const extension of marketplaceBuiltIns) {
  const release = `${extension.repo}/releases/download/v${extension.version}/${extension.name}.${extension.version}.vsix`;
  const vsix = await download(release);
  const sha256 = createHash('sha256').update(vsix).digest('hex');
  if (sha256 !== extension.sha256) throw new Error(`Checksum mismatch for ${release}: ${sha256}`);
  const nls = readZipEntry(vsix, 'extension/package.nls.json');
  const manifest = JSON.parse(readZipEntry(vsix, 'extension/package.json').toString('utf8'));
  if (manifest.contributes?.themes) throw new Error(`${extension.name} contributes color themes; load them from the VSIX`);
  builtIns.push({ folder: extension.name, manifest, nls: nls ? JSON.parse(nls.toString('utf8')) : undefined });
}
// extensionCmp: Builtin bucket, then the last path segment of the location, compared with `<`.
builtIns.sort((a, b) => a.folder < b.folder ? -1 : a.folder > b.folder ? 1 : 0);

function localize(value, nls) {
  if (typeof value === 'string') {
    const m = /^%([\w\d.-]+)%$/.exec(value);
    if (m && nls && m[1] in nls) return typeof nls[m[1]] === 'string' ? nls[m[1]] : nls[m[1]].message;
    return value;
  }
  if (Array.isArray(value)) return value.map(v => localize(v, nls));
  if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, localize(v, nls)]));
  return value;
}

// --- Bundle the upstream modules -----------------------------------------------

const temporary = await mkdtemp(join(tmpdir(), 'baocode-semantic-tokens-'));
try {
  const esbuildVersion = JSON.parse(await read('build/package.json')).devDependencies.esbuild;
  await writeFile(join(temporary, 'package.json'), '{"private":true,"type":"module"}');
  execFileSync('npm', ['install', '--no-audit', '--no-fund', '--no-package-lock', `esbuild@${esbuildVersion}`],
    { cwd: temporary, stdio: 'inherit', shell: process.platform === 'win32' });
  const require = createRequire(join(temporary, 'package.json'));
  const installed = require('esbuild/package.json').version;
  if (installed !== esbuildVersion) throw new Error(`Expected esbuild ${esbuildVersion}, installed ${installed}`);
  const esbuild = require('esbuild');

  const vs = join(root, 'src', 'vs').replaceAll('\\', '/');
  const entry = [
    `export { ColorThemeData } from '${vs}/workbench/services/themes/common/colorThemeData.ts';`,
    `export { getTokenClassificationRegistry } from '${vs}/platform/theme/common/tokenClassificationRegistry.ts';`,
    `export { TokenClassificationExtensionPoints } from '${vs}/workbench/services/themes/common/tokenClassificationExtensionPoint.ts';`,
    `export { SemanticTokensProviderStyling } from '${vs}/editor/common/services/semanticTokensProviderStyling.ts';`,
    `export { URI } from '${vs}/base/common/uri.ts';`,
  ].join('\n');
  // The extension registry: records each point so its handler can be called.
  const extensionsRegistryStub = {
    name: 'extensions-registry-stub',
    setup(build) {
      // One module for every importer.
      build.onResolve({ filter: /\/extensions\/common\/extensionsRegistry\.js$/ }, () => ({ path: 'extensionsRegistry', namespace: 'stub' }));
      build.onLoad({ filter: /.*/, namespace: 'stub' }, () => ({
        loader: 'js',
        contents: `export const extensionPoints = [];
export const ExtensionsRegistry = {
  registerExtensionPoint(description) {
    const point = { name: description.extensionPoint, handler: undefined, setHandler(handler) { point.handler = handler; } };
    extensionPoints.push(point);
    return point;
  },
};
export class ExtensionMessageCollector {}`,
      }));
    },
  };
  const bundled = await esbuild.build({
    stdin: { contents: `${entry}\nexport { extensionPoints } from '${vs}/workbench/services/extensions/common/extensionsRegistry.js';`, resolveDir: vs, loader: 'ts', sourcefile: 'entry.ts' },
    bundle: true, format: 'esm', platform: 'neutral', write: false, logLevel: 'warning',
    // src/tsconfig.base.json settings that affect emitted JavaScript.
    tsconfigRaw: { compilerOptions: { experimentalDecorators: true, useDefineForClassFields: false, target: 'ES2024' } },
    plugins: [extensionsRegistryStub],
  });
  const bundlePath = join(temporary, 'semantic-tokens.mjs');
  await writeFile(bundlePath, bundled.outputFiles[0].text);
  globalThis.vscode = { process: { platform: 'linux', arch: 'x64', env: {}, versions: {}, cwd: () => '/' } };
  const upstream = await import(pathToFileURL(bundlePath).href);
  delete globalThis.vscode;
  const { ColorThemeData, TokenClassificationExtensionPoints, SemanticTokensProviderStyling, URI, extensionPoints } = upstream;
  const registry = upstream.getTokenClassificationRegistry();

  // --- Extension contributions, as AbstractExtensionService hands them over ------

  new TokenClassificationExtensionPoints();
  const pointNames = extensionPoints.map(p => p.name);
  if (pointNames.join() !== 'semanticTokenTypes,semanticTokenModifiers,semanticTokenScopes') {
    throw new Error(`Unexpected extension points ${pointNames}`);
  }
  const contributions = [];
  for (const { manifest, nls } of builtIns) {
    const contributes = localize(manifest.contributes ?? {}, nls);
    const entry = { extension: `${manifest.publisher}.${manifest.name}` };
    for (const name of pointNames) {
      if (Object.prototype.hasOwnProperty.call(contributes, name)) entry[name] = contributes[name];
    }
    if (Object.keys(entry).length > 1) contributions.push(entry);
  }
  const errors = [];
  for (const point of extensionPoints) {
    const users = contributions.filter(c => point.name in c).map(c => ({
      description: { identifier: { value: c.extension } },
      value: c[point.name],
      collector: { error: m => errors.push(m), warn: m => errors.push(m), info: () => { } },
    }));
    point.handler(users, { added: users, removed: [] });
  }
  if (errors.length) throw new Error(`Extension point errors: ${errors.join('; ')}`);

  // --- Themes -------------------------------------------------------------------

  const loader = { readExtensionResource: async uri => readFile(uri.fsPath, 'utf8') };
  const contributedThemes = [];
  for (const { location, manifest, nls } of builtIns) {
    const themes = localize(manifest.contributes?.themes ?? [], nls);
    for (const theme of themes) {
      // ThemeRegistry (themeExtensionPoints.ts): joinPath(extensionLocation, theme.path).
      const extensionData = { extensionId: `${manifest.publisher}.${manifest.name}`, extensionPublisher: manifest.publisher, extensionName: manifest.name, extensionIsBuiltin: true };
      contributedThemes.push(ColorThemeData.fromExtensionTheme(theme, URI.file(join(location, theme.path)), extensionData));
    }
  }
  const assetManifest = JSON.parse(await readFile('assets/textmate/manifest.json', 'utf8'));
  if (assetManifest.revision !== revision) throw new Error('assets/textmate/manifest.json is for another revision');
  const bundledIds = assetManifest.themes.map(t => t.id);
  // Contributed themes generate_textmate_assets.mjs leaves out of the manifest.
  const excludedThemes = ['Visual Studio Light', 'Light+'];
  const contributedIds = contributedThemes.map(t => t.settingsId).filter(id => !excludedThemes.includes(id));
  if ([...bundledIds].sort().join('\n') !== [...contributedIds].sort().join('\n')) {
    throw new Error(`Bundled themes ${bundledIds} differ from the contributed ${contributedIds}`);
  }
  const themes = bundledIds.map(id => contributedThemes.find(t => t.settingsId === id));
  for (const theme of themes) await theme.ensureLoaded(loader);

  // Synthetic themes: semantic font styles and scope selector forms.
  const syntheticDir = join(temporary, 'synthetic');
  await mkdir(syntheticDir);
  const synthetic = [
    {
      id: 'Synthetic Dark', uiTheme: 'vs-dark', path: 'synthetic-dark.json',
      files: {
        'synthetic-dark.json': JSON.stringify({
          include: './synthetic-base.json',
          semanticHighlighting: true,
          semanticTokenColors: {
            'variable.readonly': { foreground: '#ff0000', fontStyle: 'italic underline' },
            'parameter': { bold: true },
            'property.static': { strikethrough: true, italic: false },
            '*.deprecated': { strikethrough: true },
            'method.declaration': { fontStyle: '' },
            'function:typescript': '#00ff00',
            'class.defaultLibrary:python': { foreground: '#0000ff', underline: true },
            'enumMember': { foreground: '#abc', fontStyle: 'bold strikethrough italic underline' },
            'type': { foreground: '#12345678' },
            'member': '#fedcba',
            'label.async': { italic: true },
          },
        }, null, '\t'),
        'synthetic-base.json': JSON.stringify({
          colors: { 'editor.foreground': '#cccccc', 'editor.background': '#101010' },
          tokenColors: [
            { scope: 'comment', settings: { foreground: '#608b4e', fontStyle: 'italic' } },
            { scope: ['string', 'constant.numeric'], settings: { foreground: '#d69d85' } },
            { scope: 'keyword.control, keyword.operator', settings: { foreground: '#c586c0', fontStyle: 'bold' } },
            { scope: 'entity.name.type - entity.name.type.parameter', settings: { foreground: '#4ec9b0', fontStyle: 'underline' } },
            { scope: 'entity.name.type.parameter', settings: { fontStyle: '' } },
            { scope: '(entity.name.function | support.function)', settings: { foreground: '#dcdcaa' } },
            { scope: 'R:variable.other.readwrite', settings: { foreground: '#9cdcfe' } },
            { scope: 'L:variable.other.constant', settings: { foreground: '#4fc1ff', fontStyle: 'strikethrough' } },
            { scope: 'variable.other.property', settings: { foreground: '#9cdcfe', fontStyle: 'italic bold' } },
            { scope: 'variable.other.property.ts', settings: { foreground: '#aaaaaa' } },
            { scope: 'support.class', settings: { foreground: '#aa00aa', fontStyle: 'underline italic' } },
            { scope: 'variable.parameter', settings: { foreground: '#bbbbbb' } },
            { scope: 'entity.name.namespace', settings: { foreground: '#ABCDEF80' } },
            { scope: 'variable.other.enummember', settings: {} },
            { name: 'no scope', settings: { foreground: '#123456' } },
            { scope: 'support.variable', settings: { foreground: '#fff' } },
          ],
        }, null, '\t'),
      },
    },
    {
      id: 'Synthetic Light', uiTheme: 'vs', path: 'synthetic-light.json',
      files: {
        'synthetic-light.json': JSON.stringify({
          semanticTokenColors: { 'variable': { foreground: '#010203', bold: false } },
          tokenColors: [
            { scope: 'variable.other.readwrite', settings: { foreground: '#001080' } },
            { scope: 'entity.name.function', settings: { foreground: '#795e26', fontStyle: 'bold' } },
          ],
        }, null, '\t'),
      },
    },
  ];
  const syntheticThemes = [];
  for (const s of synthetic) {
    for (const [name, content] of Object.entries(s.files)) await writeFile(join(syntheticDir, name), content);
    const theme = ColorThemeData.fromExtensionTheme({ id: s.id, label: s.id, uiTheme: s.uiTheme, path: `./${s.path}` },
      URI.file(join(syntheticDir, s.path)), { extensionId: 'test.synthetic', extensionPublisher: 'test', extensionName: 'synthetic', extensionIsBuiltin: false });
    await theme.ensureLoaded(loader);
    syntheticThemes.push({ spec: s, theme });
  }

  // --- The matrix -----------------------------------------------------------------

  // LSP 3.18 standard token types, the registry's own, the types themes select,
  // and legend entries naming a modifier or a language.
  const tokenTypes = [
    'namespace', 'type', 'class', 'enum', 'interface', 'struct', 'typeParameter', 'parameter', 'variable', 'property',
    'enumMember', 'event', 'function', 'method', 'macro', 'keyword', 'modifier', 'comment', 'string', 'number', 'regexp',
    'operator', 'decorator', 'label', 'member', 'newOperator', 'stringLiteral', 'customLiteral', 'numberLiteral',
    'unknownType', 'variable.readonly', 'function:typescript', 'property:python',
  ];
  const tokenModifiers = [
    'declaration', 'definition', 'readonly', 'static', 'deprecated', 'abstract', 'async', 'modification', 'documentation',
    'defaultLibrary', 'local',
  ];
  const modifierSetNames = [
    [], ...tokenModifiers.map(m => [m]),
    ['declaration', 'readonly'], ['static', 'readonly'], ['readonly', 'defaultLibrary'], ['static', 'defaultLibrary'],
    ['declaration', 'static'], ['declaration', 'async'], ['declaration', 'deprecated'], ['declaration', 'local'],
    ['readonly', 'local'], ['declaration', 'readonly', 'static'], ['readonly', 'static', 'defaultLibrary'],
    ['declaration', 'definition', 'readonly', 'static', 'deprecated', 'abstract', 'async', 'modification'],
  ];
  const modifierSets = modifierSetNames.map(names => names.reduce((set, m) => set | (1 << tokenModifiers.indexOf(m)), 0));
  const languages = ['typescript', 'typescriptreact', 'javascript', 'javascriptreact', 'dart', 'python', 'rust', 'plaintext'];
  const legend = { tokenTypes, tokenModifiers };
  const languageIds = new Map(languages.map((l, i) => [l, i + 1]));
  const languageService = { languageIdCodec: { encodeLanguageId: id => languageIds.get(id) } };
  const logService = { getLevel: () => 0, trace() { }, warn() { } };

  function record(theme) {
    const styling = new SemanticTokensProviderStyling(legend, { getColorTheme: () => theme }, languageService, logService);
    const metadata = [];
    const index = new Map();
    const matrix = [];
    for (const language of languages) {
      for (let type = 0; type < tokenTypes.length; type++) {
        for (const set of modifierSets) {
          const value = styling.getMetadata(type, set, language);
          if (!index.has(value)) {
            index.set(value, metadata.length);
            metadata.push(value);
          }
          matrix.push(index.get(value));
        }
      }
    }
    return {
      id: theme.settingsId, type: theme.type, semanticHighlighting: theme.semanticHighlighting,
      tokenColorMap: Array.from(theme.tokenColorMap, c => c ?? null), metadata, matrix,
    };
  }

  // --- Registry and selectors -----------------------------------------------------

  const defaultRules = registry.getTokenStylingDefaultRules().map(r => ({
    selector: r.selector.id, scopesToProbe: r.defaults.scopesToProbe ?? null,
  }));
  const selectorProbes = [
    ['variable', [], 'typescript'], ['variable', ['readonly'], 'typescript'], ['variable', ['readonly', 'static'], 'dart'],
    ['member', ['defaultLibrary'], 'dart'], ['method', ['defaultLibrary'], 'dart'], ['label', [], 'plaintext'],
    ['unknownType', ['declaration'], 'python'], ['', [], ''],
  ];
  const selectorStrings = [
    ['*'], ['*.declaration'], ['variable'], ['variable.readonly'], ['variable.readonly:typescript'], ['variable:dart'],
    ['variable.static.readonly'], ['method'], ['method.defaultLibrary'], ['member'], [''], ['.readonly'], [':typescript'],
    ['a:b:c'], ['variable', 'typescript'], ['variable:dart', 'typescript'], ['*.readonly', 'dart'], ['label'],
  ];
  const selectors = selectorStrings.map(([s, language]) => {
    const selector = registry.parseTokenSelector(s, language);
    return {
      selector: s, language: language ?? null, id: selector.id,
      scores: selectorProbes.map(([t, m, l]) => selector.match(t, m, l)),
    };
  });

  const fixture = {
    revision,
    generator: 'tool/generate_semantic_token_fixtures.mjs',
    contributions,
    tokenTypes: registry.getTokenTypes().map(t => ({ id: t.id, superType: t.superType ?? null })),
    tokenModifiers: registry.getTokenModifiers().map(m => m.id),
    defaultRules,
    selectorProbes,
    selectors,
    legend,
    modifierSets,
    languages,
    themes: themes.map(record),
    syntheticThemes: syntheticThemes.map(({ spec, theme }) => ({
      ...record(theme), uiTheme: spec.uiTheme, path: spec.path, files: spec.files,
    })),
  };
  await mkdir(dirname(output), { recursive: true });
  const json = JSON.stringify(fixture);
  await writeFile(output, gzipSync(json, { level: 9 }));
  console.log(`Wrote ${output}: ${fixture.themes.length} themes + ${fixture.syntheticThemes.length} synthetic, ` +
    `${fixture.themes[0].matrix.length} styles each, ${json.length} bytes of JSON`);
} finally {
  await rm(temporary, { recursive: true, force: true });
}
