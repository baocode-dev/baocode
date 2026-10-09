// Generates assets/exthost/core_configuration.json: VS Code's own settings
// (schemas, defaults, `[lang]` configuration defaults), as the desktop
// workbench of the pinned upstream registers them, for the extension host's
// `IConfigurationInitData.defaults` and the settings editor.
//
// Usage (after `npm ci --prefix tool/exthost_codegen`):
//   node tool/generate_core_configuration.mjs <vscode-checkout> assets/exthost/core_configuration.json [--product <product.json>]
//
// How: the workbench's own module graph is run in Node, once per platform
// (darwin, win32, linux), from `src/vs/workbench/workbench.desktop.main.ts`:
// every `.ts` module is transpiled with esbuild on `require`, with
// `globalThis.vscode.process` (what the sandboxed renderer reads) faking the
// platform. Upstream's `Registry.as(Extensions.Configuration)` then holds
// what the desktop registers at startup. What cannot run in Node is
// replaced by an inert stand-in: CSS, npm packages, and every module whose
// top-level code throws (the failure is reported, and the modules
// importing it go on with the stand-in). Values that come out of a
// stand-in are reported and dropped.
//
// Output:
//   { upstreamCommit, product, properties: { key: { ...schema, scope, title, order } },
//     platformDefaults: { darwin|win32|linux: { key: default } },     // keys whose default differs
//     platformSchemas: { darwin|win32|linux: { key: { field: value } } }, // other fields that differ
//     configurationDefaults: { key or "[lang]": value },            // core `registerDefaultConfigurations`
//     builtinExtensionDefaults: { extensionId: { key or "[lang]": value } } }
// `properties` holds Linux's schemas; a property registered on some
// platforms only lists them in `platforms`.

import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync, mkdtempSync, rmSync } from 'node:fs';
import Module, { createRequire, isBuiltin } from 'node:module';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const require = createRequire(new URL('./exthost_codegen/package.json', import.meta.url));
const self = fileURLToPath(import.meta.url);
const platforms = ['darwin', 'win32', 'linux'];

const args = process.argv.slice(2);
if (args[0] === '--child') {
  await child(args[1], args[2], args[3], args[4]);
  process.exit(0);
}

const productIndex = args.indexOf('--product');
const productPath = productIndex >= 0 ? args.splice(productIndex, 2)[1] : undefined;
const [checkout, outPath] = args;
if (!checkout || !outPath) {
  console.error(
    'Usage: node tool/generate_core_configuration.mjs <vscode-checkout> <out.json> [--product <product.json>]',
  );
  process.exit(2);
}
await main(path.resolve(checkout), path.resolve(outPath), path.resolve(productPath ?? path.join(checkout, 'product.json')));

// ---------------------------------------------------------------------------
// Parent: one child per platform, then merging.

async function main(checkout, outPath, productPath) {
  const commit = execFileSync('git', ['-C', checkout, 'rev-parse', 'HEAD'], { encoding: 'utf8' }).trim();
  const tmp = mkdtempSync(path.join(os.tmpdir(), 'core-config-'));
  const runs = {};
  try {
    for (const platform of platforms) {
      const out = path.join(tmp, `${platform}.json`);
      execFileSync(process.execPath, ['--stack-size=4000', self, '--child', platform, checkout, productPath, out], {
        stdio: ['ignore', 'ignore', 'inherit'],
        maxBuffer: 1 << 28,
      });
      runs[platform] = JSON.parse(readFileSync(out, 'utf8'));
    }
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }

  const base = runs.linux;
  const properties = {};
  const platformDefaults = Object.fromEntries(platforms.map((p) => [p, {}]));
  const allKeys = [...new Set(platforms.flatMap((p) => Object.keys(runs[p].properties)))].sort();
  const platformSchemas = Object.fromEntries(platforms.map((p) => [p, {}]));
  const platformOnly = {};
  const schemaDiffers = [];
  for (const key of allKeys) {
    const present = platforms.filter((p) => key in runs[p].properties);
    const reference = runs[present.includes('linux') ? 'linux' : present[0]].properties[key];
    properties[key] = { ...reference };
    if (present.length < platforms.length) {
      properties[key].platforms = present;
      platformOnly[key] = present;
    }
    const defaults = present.map((p) => JSON.stringify(runs[p].properties[key].default));
    if (new Set(defaults).size > 1) {
      for (const p of present) platformDefaults[p][key] = runs[p].properties[key].default;
    }
    // Other fields differing (descriptions naming Cmd or Ctrl…): per platform.
    for (const p of present) {
      const schema = runs[p].properties[key];
      for (const field of Object.keys(schema)) {
        if (field === 'default' || JSON.stringify(schema[field]) === JSON.stringify(reference[field])) continue;
        ((platformSchemas[p][key] ??= {}))[field] = schema[field];
        if (!schemaDiffers.includes(key)) schemaDiffers.push(key);
      }
    }
  }

  const output = {
    upstreamCommit: commit,
    product: { nameShort: base.product.nameShort, quality: base.product.quality ?? null },
    properties,
    platformDefaults,
    platformSchemas,
    configurationDefaults: base.configurationDefaults,
    builtinExtensionDefaults: builtinExtensionDefaults(checkout),
  };
  mkdirSync(path.dirname(outPath), { recursive: true });
  writeFileSync(outPath, `${JSON.stringify(output, null, 1)}\n`);

  const report = (label, list) => {
    console.log(`${label}: ${list.length}`);
    for (const item of list) console.log(`  ${item}`);
  };
  console.log(`upstream ${commit}, product ${productPath}`);
  console.log(`properties: ${allKeys.length}`);
  for (const p of platforms) {
    console.log(`  ${p}: ${Object.keys(runs[p].properties).length} registered, ${Object.keys(platformDefaults[p]).length} platform defaults`);
  }
  console.log(`configurationDefaults: ${Object.keys(output.configurationDefaults).length}`);
  console.log(`builtinExtensionDefaults: ${Object.keys(output.builtinExtensionDefaults).join(', ')}`);
  report('properties on some platforms only', Object.entries(platformOnly).map(([k, v]) => `${k} (${v.join(', ')})`));
  report('schemas differing by platform (in platformSchemas)', schemaDiffers);
  report('modules that could not run (replaced by stand-ins)', base.failures);
  report('values from stand-ins (dropped)', base.stubbed);
}

// The `configurationDefaults` of upstream's declarative built-in extensions
// (language basics: no code, so not in the runtime, whose languages the app
// provides itself), e.g. `[markdown]` from markdown-basics, by extension id.
function builtinExtensionDefaults(checkout) {
  const out = {};
  const dir = path.join(checkout, 'extensions');
  for (const name of readdirSync(dir).sort()) {
    const file = path.join(dir, name, 'package.json');
    if (!existsSync(file) || name.startsWith('vscode-')) continue;
    const pkg = JSON.parse(readFileSync(file, 'utf8'));
    const defaults = pkg.contributes?.configurationDefaults;
    if (!defaults || pkg.main || pkg.browser) continue;
    out[`${pkg.publisher}.${pkg.name}`] = defaults;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Child: runs the workbench's registrations for one platform.

async function child(platform, checkout, productPath, outPath) {
  const esbuild = require('esbuild');
  const src = path.join(checkout, 'src');
  const product = JSON.parse(readFileSync(productPath, 'utf8'));
  const pkg = JSON.parse(readFileSync(path.join(checkout, 'package.json'), 'utf8'));
  if (!product.version) product.version = pkg.version;

  // -- Stand-ins -------------------------------------------------------------
  const STUB = Symbol('stub');
  const stubCache = new Map();
  function stub(name, callable = true) {
    const key = `${callable}:${name}`;
    if (stubCache.has(key)) return stubCache.get(key);
    const children = new Map();
    const target = callable ? function () {} : {};
    const proxy = new Proxy(target, {
      get(t, p) {
        if (p === STUB) return name;
        if (p === 'prototype' && callable) return t.prototype;
        if (p === Symbol.toPrimitive) return (hint) => (hint === 'number' ? 0 : '');
        if (p === Symbol.iterator) return function* () {};
        if (typeof p === 'symbol') return undefined;
        if (p === 'then' || p === 'toJSON' || p === '__esModule') return undefined;
        if (p === 'toString' || p === 'valueOf') return () => '';
        if (!children.has(p)) children.set(p, stub(`${name}.${p}`));
        return children.get(p);
      },
      apply: () => stub(`${name}()`),
      construct: () => stub(`new ${name}`, false),
      set: () => true,
      has: () => true,
      defineProperty: () => true,
      deleteProperty: () => true,
      getPrototypeOf: () => (callable ? Function.prototype : Object.prototype),
    });
    stubCache.set(key, proxy);
    return proxy;
  }
  const isStub = (v) => (typeof v === 'object' || typeof v === 'function') && v !== null && v[STUB] !== undefined;

  // -- The renderer's globals ------------------------------------------------
  const fakeProcess = {
    platform,
    arch: 'x64',
    env: {},
    versions: { node: process.versions.node, electron: '39.0.0', chrome: '142.0.0' },
    type: 'renderer',
    execPath: '/app',
    cwd: () => '/',
    shellEnv: async () => ({}),
    getProcessMemoryInfo: async () => ({}),
    on: () => {},
  };
  globalThis.vscode = {
    process: fakeProcess,
    context: {
      configuration: () => ({ product, windowId: 1, appRoot: '/app', userEnv: {}, nls: { messages: [], language: 'en' } }),
      resolveConfiguration: async () => ({}),
    },
    ipcRenderer: stub('ipcRenderer'),
    ipcMessagePort: stub('ipcMessagePort'),
    webFrame: stub('webFrame'),
    webUtils: stub('webUtils'),
  };
  globalThis._VSCODE_FILE_ROOT = pathToFileURL(src).href;
  const windowStub = new Proxy({}, {
    get(t, p) {
      if (p in t) return t[p];
      if (p in globalThis && p !== 'window') return globalThis[p];
      if (typeof p === 'symbol') return undefined;
      return stub(`window.${String(p)}`);
    },
    set(t, p, v) { t[p] = v; return true; },
    has: () => true,
  });
  const domGlobals = [
    'document', 'HTMLElement', 'Element', 'Node', 'HTMLDivElement', 'HTMLInputElement', 'HTMLCanvasElement',
    'HTMLIFrameElement', 'HTMLImageElement', 'HTMLAnchorElement', 'HTMLTextAreaElement', 'HTMLSelectElement',
    'HTMLButtonElement', 'HTMLSpanElement', 'HTMLStyleElement', 'HTMLLinkElement', 'HTMLMediaElement',
    'HTMLVideoElement', 'HTMLAudioElement', 'SVGElement', 'Text', 'DocumentFragment', 'ShadowRoot', 'Range',
    'Selection', 'UIEvent', 'MouseEvent', 'KeyboardEvent', 'PointerEvent', 'DragEvent', 'FocusEvent',
    'WheelEvent', 'TouchEvent', 'ClipboardEvent', 'InputEvent', 'CompositionEvent', 'ErrorEvent', 'DOMParser',
    'MutationObserver', 'ResizeObserver', 'IntersectionObserver', 'getComputedStyle', 'requestAnimationFrame',
    'cancelAnimationFrame', 'requestIdleCallback', 'cancelIdleCallback', 'matchMedia', 'localStorage',
    'sessionStorage', 'location', 'Worker', 'SharedWorker', 'CSS', 'CSSStyleSheet', 'FontFace', 'Image',
    'Audio', 'XMLHttpRequest', 'FileReader', 'DataTransfer', 'IDBFactory', 'indexedDB', 'screen', 'history',
    'getSelection', 'trustedTypesPolicyFactory', 'ClipboardItem', 'OffscreenCanvas', 'ImageData',
    'AudioContext', 'MediaRecorder', 'speechSynthesis', 'SpeechSynthesisUtterance', 'HTMLTemplateElement',
    'customElements', 'HTMLSlotElement', 'HTMLTableElement', 'HTMLBodyElement', 'HTMLHeadElement', 'HTMLLabelElement',
    'HTMLOptionElement', 'HTMLLIElement', 'HTMLUListElement', 'HTMLParagraphElement', 'HTMLPreElement', 'HTMLFormElement',
    'HTMLDialogElement', 'Document', 'Window', 'StyleSheet', 'CSSRule', 'StaticRange', 'NodeFilter', 'TreeWalker',
    'DOMRect', 'DOMMatrix', 'Path2D', 'CanvasRenderingContext2D', 'WebGL2RenderingContext', 'GPU', 'MediaQueryList',
  ];
  for (const name of domGlobals) {
    if (!(name in globalThis)) globalThis[name] = stub(name, !['document', 'location', 'localStorage', 'sessionStorage', 'screen', 'history', 'indexedDB'].includes(name));
  }
  // Timers the workbench's modules start never run: their callbacks expect
  // a window (and loop on stand-ins). Promise jobs do.
  const realSetTimeout = globalThis.setTimeout;
  globalThis.setTimeout = globalThis.setInterval = globalThis.setImmediate = () => 0;
  globalThis.window = windowStub;
  globalThis.self = windowStub;
  globalThis.addEventListener ??= () => {};
  globalThis.removeEventListener ??= () => {};
  globalThis.devicePixelRatio = 1;
  globalThis.isSecureContext = true;

  // -- Loading upstream's sources --------------------------------------------
  const failures = [];
  const failed = new Map();
  const transpile = (module, filename) => {
    const code = esbuild.transformSync(readFileSync(filename, 'utf8'), {
      loader: filename.endsWith('.ts') ? 'ts' : 'js',
      format: 'cjs',
      target: 'es2022',
      platform: 'node',
      sourcefile: filename,
      logLevel: 'silent',
      define: { 'import.meta.url': '__import_meta_url' },
      tsconfigRaw: { compilerOptions: { experimentalDecorators: true, useDefineForClassFields: false } },
    }).code;
    module._compile(`const __import_meta_url = require('url').pathToFileURL(__filename).href;${code}`, filename, 'commonjs');
  };
  // Loads a source module as CommonJS, bypassing Node's own format detection
  // (upstream's package.json says `"type": "module"`).
  const loadSource = (filename, parent) => {
    const cached = Module._cache[filename];
    if (cached) return cached.exports;
    const module = new Module(filename, parent);
    module.filename = filename;
    module.paths = Module._nodeModulePaths(path.dirname(filename));
    Module._cache[filename] = module;
    if (process.env.CORE_CONFIG_TRACE) console.error(`load ${rel(filename)}`);
    try {
      transpile(module, filename);
    } catch (e) {
      delete Module._cache[filename];
      throw e;
    }
    module.loaded = true;
    return module.exports;
  };

  const rel = (f) => path.relative(src, f);
  const originalLoad = Module._load;
  Module._load = function (request, parent, isMain) {
    if (!parent?.filename?.startsWith(src)) return originalLoad.call(this, request, parent, isMain);
    if (/\.(css|svg|png|html|wasm|ttf)$/.test(request)) return stub(request);
    if (request.startsWith('.') || path.isAbsolute(request)) {
      let resolved = path.resolve(path.dirname(parent.filename), request);
      if (resolved.endsWith('.js') && !existsSync(resolved) && existsSync(`${resolved.slice(0, -3)}.ts`)) {
        resolved = `${resolved.slice(0, -3)}.ts`;
      }
      if (failed.has(resolved)) return failed.get(resolved);
      if (!existsSync(resolved)) return stub(rel(resolved));
      if (resolved.endsWith('.json')) return JSON.parse(readFileSync(resolved, 'utf8'));
      try {
        return loadSource(resolved, parent);
      } catch (e) {
        const s = stub(rel(resolved));
        failed.set(resolved, s);
        failures.push(`${rel(resolved)}: ${String(e?.message ?? e).split('\n')[0]}`);
        return s;
      }
    }
    if (isBuiltin(request)) return originalLoad.call(this, request, parent, isMain);
    return stub(request);
  };
  process.on('uncaughtException', () => {});
  process.on('unhandledRejection', () => {});

  const load = (file) => Module._load(path.join(src, file), { filename: path.join(src, 'vs', 'entry.ts'), paths: [] }, false);
  // Loaded first so the registry is the real one even when a module fails.
  const { Registry } = load('vs/platform/registry/common/platform.ts');
  const { Extensions } = load('vs/platform/configuration/common/configurationRegistry.ts');
  load('vs/workbench/workbench.desktop.main.ts');
  // Registrations a workbench contribution makes once the window is up
  // (with what it knows only then: detected terminal profiles, terminal
  // suggest providers…) keep the startup registration.
  await new Promise((resolve) => realSetTimeout(resolve, 100));

  const registry = Registry.as(Extensions.Configuration);
  const groups = new Map();
  const walk = (node, title, order) => {
    const nodeTitle = node.title ?? title;
    const nodeOrder = node.order ?? order;
    for (const key of Object.keys(node.properties ?? {})) {
      if (!groups.has(key)) groups.set(key, { title: nodeTitle, order: nodeOrder });
    }
    for (const sub of node.allOf ?? []) walk(sub, nodeTitle, nodeOrder);
  };
  for (const node of registry.getConfigurations()) walk(node, undefined, undefined);

  const stubbed = [];
  const clean = (value, where) => {
    if (isStub(value)) {
      stubbed.push(`${where}: ${value[STUB]}`);
      return undefined;
    }
    if (Array.isArray(value)) return value.map((v, i) => clean(v, `${where}[${i}]`) ?? null);
    if (value instanceof RegExp) return value.source;
    if (typeof value === 'function') return undefined;
    if (value && typeof value === 'object') {
      const out = {};
      for (const [k, v] of Object.entries(value)) {
        const c = clean(v, `${where}.${k}`);
        if (c !== undefined) out[k] = c;
      }
      return out;
    }
    return value;
  };
  const internal = new Set(['source', 'defaultValueSource', 'defaultDefaultValue', 'policy', 'experiment', 'defaultSnippets', 'agentHostSettingId', 'section', 'agentsWindow', 'agentHost', 'included']);
  const properties = {};
  const all = registry.getConfigurationProperties();
  const overridden = registry.getConfigurationDefaultsOverrides();
  for (const key of Object.keys(all).sort()) {
    // `[lang]` entries registerDefaultConfigurations adds: in configurationDefaults.
    if (/^(\[[^\]]+\])+$/.test(key)) continue;
    const schema = all[key];
    const out = {};
    for (const [k, v] of Object.entries(schema)) {
      if (internal.has(k)) continue;
      const c = clean(v, `${key}.${k}`);
      if (c !== undefined) out[k] = c;
    }
    // The registered default, before `configurationDefaults` (kept apart).
    // (`default` is that when no configuration default applies; when none is
    // registered either, upstream's `getDefaultValue(type)`.)
    const typeDefault = (type) => ({ boolean: false, integer: 0, number: 0, string: '', array: [], object: {} })[Array.isArray(type) ? type[0] : type] ?? null;
    const original = overridden.has(key) ? (schema.defaultDefaultValue ?? typeDefault(schema.type)) : schema.default;
    out.default = clean(original, `${key}.default`) ?? null;
    // The registering node's title and order (`order` stays the property's).
    const group = groups.get(key);
    if (group?.title !== undefined) out.title = clean(group.title, `${key}.title`);
    if (group?.order !== undefined) out.groupOrder = group.order;
    properties[key] = out;
  }

  const configurationDefaults = {};
  for (const [key, { value }] of registry.getConfigurationDefaultsOverrides()) {
    configurationDefaults[key] = clean(value, `configurationDefaults.${key}`);
  }

  writeFileSync(
    outPath,
    JSON.stringify({ product, properties, configurationDefaults, failures, stubbed }),
  );
}
