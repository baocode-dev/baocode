// Evaluates the real upstream VS Code color registrations, never the Dart port, to write
// lib/monaco/vs/platform/theme/common/color_registry_data.g.dart and the golden
// data test/textmate/workbench/color_registry_test.dart replays.
//
// Usage: node tool/generate_color_registry.mjs [vscode-source] [--keep]
//   [vscode-source]  the VS Code sources at `revision`: a git checkout, or a directory this
//                    script extracted (default: the GitHub tarball of `revision`, extracted into
//                    /tmp/baocode-color-registry-vscode-<rev>; its pax header names the commit).
//   --keep           keeps the temporary esbuild install and bundle (printed at the end).
//
// What it does, at VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// 1. Finds the files that register colors: every non-test .ts file under src/vs outside
//    vs/editor/standalone whose text contains `registerColor(` (colorUtils.ts `registerColor`
//    and the `IColorRegistry.registerColor` method). The desktop workbench executes the ones
//    reachable from src/vs/workbench/workbench.desktop.main.ts: esbuild (the version
//    build/package.json pins) bundles that entry with a metafile, and the bundle's module order
//    is the ESM evaluation order. Files outside that graph (the Agent Sessions window's
//    vs/sessions/browser and vs/sessions/contrib) are reported and left out; the order of the
//    rest is the desktop evaluation order. Every one of them is statically imported.
// 2. Bundles those files, unmodified, into one module with esbuild and evaluates it in Node,
//    once per platform (darwin, linux, win32; platform.ts reads `globalThis.vscode.process` like
//    a sandboxed renderer). Real modules: the color files themselves, src/vs/base/common/**,
//    nls.ts, src/vs/platform/{theme,jsonschemas,instantiation}/common/**, and, for the goldens,
//    colorThemeData.ts, themeCompatibility.ts, plistParser.ts, textMateScopeMatcher.ts and
//    encodedTokenAttributes.ts. Every other import (DOM, widgets, services, actions,
//    node_modules) becomes a CommonJS stub whose exports are one "universal" Proxy: any property,
//    call or `new` of it yields itself, so module-level code such as `registerAction2(...)` or
//    `class X extends Widget` runs without effect. Two modules are replaced by small shims:
//    platform/registry/common/platform.ts wraps the real Registry so that `Registry.as(id)` of an
//    id no real module added returns the stub (upstream: null), and
//    workbench/services/extensions/common/extensionsRegistry.ts records extension points so the
//    real ColorExtensionPoint handler can be called. A stub value can never reach the registry
//    unnoticed: every registered id and default is validated (strings, `Color`s and ColorTransform
//    objects only) and the run fails otherwise.
//    Every `registerColor` call is recorded with its stack; the run fails unless every call site
//    in the color files ran (so no registration hides in a function the load does not call), and
//    unless the files register in the desktop evaluation order.
// 3. Registers the built-in extensions' `contributes.colors` through the real ColorExtensionPoint
//    handler (colorExtensionPoint.ts), as AbstractExtensionService._handleExtensionPoint delivers
//    them: extensions/*/package.json minus `excludedExtensions` (build/lib/extensions.ts) and minus
//    product.json `builtInExtensions` names, plus `copilot` (packaged separately), sorted by folder
//    name (extensionCmp), `%key%` strings replaced from package.nls.json. The marketplace
//    `builtInExtensions` (js-debug, js-debug-companion, js-profile-table) are not included; their
//    release VSIXs (checked against product.json) contribute no colors.
// 4. Writes the registry (`getColors()`: id and defaults) as const Dart data. A bare ColorValue
//    default becomes the same value for the four color schemes, which is what
//    `resolveDefaultColor` does with it. Hex strings are normalized through
//    `Color.Format.CSS.formatHexA(Color.fromHex(s), true)`, which keeps the exact RGBA.
// 5. Writes test/fixtures/theme/color_registry.json.gz: for the 17 bundled color themes, loaded by
//    the real ColorThemeData (`fromExtensionTheme` + `ensureLoaded` on the upstream theme files),
//    and for an empty theme of each color scheme (`createUnloadedThemeForThemeType`), every
//    registered id's `getColor(id)`, `getColor(id, false)` and `defines(id)`. Colors are stored
//    once in a value table. It also holds real color.ts results for random inputs (`colorOps`)
//    and the 256 luminance components, which the Dart color.dart tests replay.
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, realpathSync } from 'node:fs';
import { mkdir, mkdtemp, readFile, readdir, rm, stat, writeFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { tmpdir } from 'node:os';
import { dirname, join, relative, sep } from 'node:path';
import { pathToFileURL } from 'node:url';
import { gunzipSync, gzipSync } from 'node:zlib';

const revision = '6a598d4a13031703d483d103c1d934a36ad27971';
const platforms = ['darwin', 'linux', 'win32'];
const dartOutput = 'lib/monaco/vs/platform/theme/common/color_registry_data.g.dart';
const fixtureOutput = 'test/fixtures/theme/color_registry.json.gz';
const manifestPath = 'assets/textmate/manifest.json';

const flags = process.argv.slice(2).filter(a => a.startsWith('--'));
const positional = process.argv.slice(2).filter(a => !a.startsWith('--'));
if (positional.length > 1 || flags.some(f => f !== '--keep')) {
  throw new Error('Usage: node tool/generate_color_registry.mjs [vscode-source] [--keep]');
}
const keep = flags.includes('--keep');

// --- Pinned sources ----------------------------------------------------------------

async function download(url) {
  for (let attempt = 1; ; attempt++) {
    try {
      const response = await fetch(url, { headers: { 'User-Agent': 'baocode-color-registry' } });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      return Buffer.from(await response.arrayBuffer());
    } catch (error) {
      if (attempt >= 4) throw new Error(`Cannot download ${url}: ${error.message}`);
      await new Promise(resolve => setTimeout(resolve, 1000 * attempt));
    }
  }
}

const marker = '.baocode-revision';

async function sources() {
  if (positional[0]) {
    const root = positional[0];
    if (existsSync(join(root, '.git'))) {
      const head = execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], { encoding: 'utf8' }).trim();
      if (head !== revision) throw new Error(`Expected ${root} at ${revision}, found ${head}`);
      const dirty = execFileSync('git', ['-C', root, 'status', '--porcelain', '--', 'src', 'extensions', 'build', 'product.json'], { encoding: 'utf8' });
      if (dirty.trim()) throw new Error(`${root} has local changes:\n${dirty}`);
    } else if (!existsSync(join(root, marker)) || readFileSync(join(root, marker), 'utf8').trim() !== revision) {
      throw new Error(`${root} is neither a git checkout nor a tarball extracted by this script`);
    }
    return root;
  }
  const parent = join(tmpdir(), `baocode-color-registry-vscode-${revision.slice(0, 8)}`);
  const root = join(parent, `vscode-${revision}`);
  if (existsSync(join(root, marker))) return root;
  await rm(parent, { recursive: true, force: true });
  await mkdir(parent, { recursive: true });
  const tarball = await download(`https://codeload.github.com/microsoft/vscode/tar.gz/${revision}`);
  // The pax global header of a GitHub tarball records the commit it was made from.
  const header = gunzipSync(tarball.subarray(0, Math.min(tarball.length, 1 << 16)), { finishFlush: 2 }).subarray(0, 1024).toString('latin1');
  const comment = /\d+ comment=([0-9a-f]{40})\n/.exec(header);
  if (comment?.[1] !== revision) throw new Error(`The tarball does not name ${revision} (found ${comment?.[1]})`);
  const archive = join(parent, 'vscode.tar.gz');
  await writeFile(archive, tarball);
  execFileSync('tar', ['-xzf', archive, '-C', parent, `vscode-${revision}/src/vs`, `vscode-${revision}/extensions`,
    `vscode-${revision}/build/lib/extensions.ts`, `vscode-${revision}/build/package.json`, `vscode-${revision}/product.json`], { stdio: 'inherit' });
  await rm(archive);
  await writeFile(join(root, marker), revision + '\n');
  return root;
}

// esbuild reports real paths (macOS /tmp is /private/tmp).
const root = realpathSync(await sources());
const read = path => readFile(join(root, path), 'utf8');
const posixPath = path => path.split(sep).join('/');

// --- Files that register colors ------------------------------------------------------

async function walk(dir, out = []) {
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) await walk(path, out);
    else out.push(path);
  }
  return out;
}

const grepHits = [];
for (const file of (await walk(join(root, 'src', 'vs'))).map(f => posixPath(relative(root, f))).sort()) {
  if (!file.endsWith('.ts') || file.endsWith('.d.ts')) continue;
  if (file.startsWith('src/vs/editor/standalone/') || /\/test\//.test(file) || /\.test\.ts$/.test(file)) continue;
  if (/registerColor\(/.test(await read(file))) grepHits.push(file);
}

// --- esbuild, pinned by build/package.json ---------------------------------------------

const temporary = await mkdtemp(join(tmpdir(), 'baocode-color-registry-'));
const esbuildVersion = JSON.parse(await read('build/package.json')).devDependencies.esbuild;
await writeFile(join(temporary, 'package.json'), '{"private":true,"type":"module"}');
execFileSync('npm', ['install', '--no-audit', '--no-fund', '--no-package-lock', `esbuild@${esbuildVersion}`],
  { cwd: temporary, stdio: 'inherit', shell: process.platform === 'win32' });
const require = createRequire(join(temporary, 'package.json'));
const installed = require('esbuild/package.json').version;
if (installed !== esbuildVersion) throw new Error(`Expected esbuild ${esbuildVersion}, installed ${installed}`);
const esbuild = require('esbuild');

// src/tsconfig.base.json settings that affect emitted JavaScript.
const tsconfigRaw = { compilerOptions: { experimentalDecorators: true, useDefineForClassFields: false, target: 'ES2024' } };
const emptyLoaders = Object.fromEntries(['.css', '.svg', '.png', '.gif', '.jpg', '.ttf', '.woff', '.woff2', '.wasm', '.mp3', '.html', '.txt', '.md', '.scm'].map(e => [e, 'empty']));

/** Module order of an esbuild ESM bundle: the `// path` comment in front of each module. */
function moduleMarkers(text) {
  const markers = [];
  const lines = text.split('\n');
  for (let i = 0; i < lines.length; i++) {
    const m = /^\/\/ (\S+)$/.exec(lines[i]);
    if (m) markers.push({ line: i + 1, file: m[1] });
  }
  return { markers, lines };
}

// The desktop workbench's module graph and evaluation order.
const desktop = await esbuild.build({
  absWorkingDir: root,
  entryPoints: ['src/vs/workbench/workbench.desktop.main.ts'],
  bundle: true, format: 'esm', platform: 'neutral', write: false, metafile: true, logLevel: 'error',
  loader: emptyLoaders, tsconfigRaw,
  plugins: [{ name: 'externals', setup(build) {
    build.onResolve({ filter: /^[^./]/ }, args => args.kind === 'entry-point' ? undefined : { path: args.path, external: true });
  } }],
});
for (const [file, input] of Object.entries(desktop.metafile.inputs)) {
  for (const imported of input.imports) {
    if (!imported.external && imported.kind !== 'import-statement') throw new Error(`${file} reaches ${imported.path} by ${imported.kind}; the evaluation order below assumes static imports`);
  }
}
const desktopOrder = new Map(moduleMarkers(desktop.outputFiles[0].text).markers.map((m, i) => [m.file, i]));
const colorFiles = grepHits.filter(f => desktopOrder.has(f)).sort((a, b) => desktopOrder.get(a) - desktopOrder.get(b));
const notInDesktop = grepHits.filter(f => !desktopOrder.has(f));
for (const file of notInDesktop) {
  if (!file.startsWith('src/vs/sessions/')) throw new Error(`${file} registers colors but is not part of the desktop workbench; decide whether it belongs`);
}
const colorFileSet = new Set(colorFiles);

// --- The evaluation bundle ----------------------------------------------------------------

const colorUtilsFile = 'src/vs/platform/theme/common/colorUtils.ts';
const extensionPointFile = 'src/vs/workbench/services/themes/common/colorExtensionPoint.ts';
const registryFile = 'src/vs/platform/registry/common/platform.ts';
const extensionsRegistryFile = 'src/vs/workbench/services/extensions/common/extensionsRegistry.ts';
if (!colorFileSet.has(colorUtilsFile) || !colorFileSet.has(extensionPointFile)) throw new Error('colorUtils.ts or colorExtensionPoint.ts is not part of the desktop workbench');

const realPrefixes = ['src/vs/base/common/', 'src/vs/platform/theme/common/', 'src/vs/platform/jsonschemas/common/', 'src/vs/platform/instantiation/common/'];
const realFiles = new Set([
  'src/vs/nls.ts', 'src/vs/nls.messages.ts',
  'src/vs/workbench/services/themes/common/colorThemeData.ts',
  'src/vs/workbench/services/themes/common/themeCompatibility.ts',
  'src/vs/workbench/services/themes/common/plistParser.ts',
  'src/vs/workbench/services/themes/common/textMateScopeMatcher.ts',
  'src/vs/editor/common/encodedTokenAttributes.ts',
]);
const isReal = file => colorFileSet.has(file) || realFiles.has(file) || realPrefixes.some(p => file.startsWith(p));

const entry = [
  `import { registrations } from 'baocode:instrument';`,
  ...colorFiles.map(f => `import './${f}';`),
  `export { registrations };`,
  `export { extensionPoints, registryFallbacks } from 'baocode:extensions-registry';`,
  `export { ColorExtensionPoint } from './${extensionPointFile}';`,
  `export { ColorThemeData } from './src/vs/workbench/services/themes/common/colorThemeData.ts';`,
  `export { getColorRegistry, isColorDefaults, resolveColorValue } from './${colorUtilsFile}';`,
  `export { Color, RGBA, HSLA, HSVA } from './src/vs/base/common/color.ts';`,
  `export { ColorScheme } from './src/vs/platform/theme/common/theme.ts';`,
  `export { URI } from './src/vs/base/common/uri.ts';`,
  `export { joinPath } from './src/vs/base/common/resources.ts';`,
].join('\n');

const universalStub = 'module.exports = globalThis.__baocodeUniversalStub;';
const stubbed = new Set();
const baocodeModules = {
  // Records every registration with its call stack, before any color file runs.
  'instrument': `
    import { getColorRegistry } from './${colorUtilsFile}';
    export const registrations = [];
    const registry = getColorRegistry();
    const registerColor = registry.registerColor;
    registry.registerColor = function () {
      registrations.push({ id: arguments[0], stack: new Error().stack });
      return registerColor.apply(this, arguments);
    };`,
  // The real Registry; ids that only stubbed modules would add resolve to the stub.
  'registry': `
    import { Registry as real } from 'baocode:real-registry';
    import { registryFallbacks } from 'baocode:extensions-registry';
    const stub = globalThis.__baocodeUniversalStub;
    export const Registry = {
      add: (id, data) => real.add(id, data),
      knows: id => real.knows(id),
      as(id) {
        if (typeof id === 'string' && real.knows(id)) return real.as(id);
        registryFallbacks.push(typeof id === 'string' ? id : '<stub>');
        return stub;
      },
      dispose: () => real.dispose(),
    };`,
  // ExtensionsRegistry.registerExtensionPoint, keeping the handlers.
  'extensions-registry': `
    export const extensionPoints = [];
    export const registryFallbacks = [];
    export const ExtensionsRegistry = {
      registerExtensionPoint(description) {
        const point = {
          name: description.extensionPoint,
          handler: undefined,
          setHandler(handler) {
            if (point.handler) throw new Error('Handler already set!');
            point.handler = handler;
            return { dispose() { point.handler = undefined; } };
          },
        };
        extensionPoints.push(point);
        return point;
      },
      getExtensionPoints: () => extensionPoints,
    };`,
};

const bundled = await esbuild.build({
  absWorkingDir: root,
  stdin: { contents: entry, resolveDir: root, loader: 'ts', sourcefile: 'baocode-entry.ts' },
  bundle: true, format: 'esm', platform: 'neutral', write: false, metafile: true, logLevel: 'warning',
  loader: emptyLoaders, tsconfigRaw,
  plugins: [{ name: 'baocode-stubs', setup(build) {
    build.onResolve({ filter: /^baocode:/ }, args => {
      const name = args.path.slice('baocode:'.length);
      if (name === 'real-registry') return { path: join(root, registryFile) };
      return { path: name, namespace: 'baocode' };
    });
    build.onResolve({ filter: /.*/ }, async args => {
      if (args.pluginData?.inner || args.kind === 'entry-point' || args.path.startsWith('baocode:')) return undefined;
      if (!args.path.startsWith('.') && !args.path.startsWith('/')) {
        stubbed.add(args.path);
        return { path: args.path, namespace: 'stub' };
      }
      const resolved = await build.resolve(args.path, { kind: args.kind, resolveDir: args.resolveDir, importer: args.importer, pluginData: { inner: true } });
      if (resolved.errors.length) throw new Error(`Cannot resolve ${args.path} from ${args.importer}`);
      const file = posixPath(relative(root, resolved.path));
      if (Object.keys(emptyLoaders).some(e => file.endsWith(e))) return { path: resolved.path };
      if (file === registryFile) return { path: 'registry', namespace: 'baocode' };
      if (file === extensionsRegistryFile) return { path: 'extensions-registry', namespace: 'baocode' };
      if (isReal(file)) return { path: resolved.path };
      stubbed.add(file);
      return { path: file, namespace: 'stub' };
    });
    build.onLoad({ filter: /.*/, namespace: 'baocode' }, args => ({ contents: baocodeModules[args.path], loader: 'js', resolveDir: root }));
    build.onLoad({ filter: /.*/, namespace: 'stub' }, () => ({ contents: universalStub, loader: 'js' }));
  } }],
});
const bundleText = bundled.outputFiles[0].text;
const bundlePath = join(temporary, 'color-registry.mjs');
await writeFile(bundlePath, bundleText);
const realModules = Object.keys(bundled.metafile.inputs).filter(f => !f.includes(':'));

// Module segments of the bundle, to attribute stack frames and call sites to files.
const { markers, lines: bundleLines } = moduleMarkers(bundleText);
function fileAtLine(line) {
  let lo = 0, hi = markers.length - 1, found = null;
  while (lo <= hi) {
    const mid = (lo + hi) >> 1;
    if (markers[mid].line <= line) { found = markers[mid].file; lo = mid + 1; } else hi = mid - 1;
  }
  return found;
}
const bundleOrder = new Map(markers.map((m, i) => [m.file, i]));
for (let i = 1; i < colorFiles.length; i++) {
  if (!(bundleOrder.get(colorFiles[i - 1]) < bundleOrder.get(colorFiles[i]))) {
    throw new Error(`The bundle evaluates ${colorFiles[i]} before ${colorFiles[i - 1]}, unlike the desktop workbench`);
  }
}
// Static `registerColor(` call sites per color file, as bundle line:column.
const callSites = new Map();
for (let i = 0; i < markers.length; i++) {
  const { file, line } = markers[i];
  if (!colorFileSet.has(file) || file === colorUtilsFile) continue;
  const end = i + 1 < markers.length ? markers[i + 1].line : bundleLines.length + 1;
  const sites = new Set();
  for (let l = line; l < end; l++) {
    for (const m of bundleLines[l - 1].matchAll(/\bregisterColor\s*\(/g)) {
      if (/function\s+$/.test(bundleLines[l - 1].slice(0, m.index))) continue;
      sites.add(`${l}:${m.index + 1}`);
    }
  }
  callSites.set(file, sites);
}

// --- Universal stub ----------------------------------------------------------------------

function universalStub_() {
  const handler = {
    get(_, key) {
      if (key === Symbol.toPrimitive) return () => '';
      if (key === 'then') return undefined;
      if (key === '__esModule') return true;
      return stub;
    },
    getPrototypeOf: () => prototype,
    apply: () => stub,
    construct: () => stub,
  };
  const stub = new Proxy(function () { }, handler);
  // `__toESM` copies nothing from the stub; named imports then read through this prototype.
  const prototype = new Proxy({}, { get: (_, key) => handler.get(_, key) });
  return stub;
}
const universal = universalStub_();
globalThis.__baocodeUniversalStub = universal;

// --- Built-in extensions, as the desktop product ships them -----------------------------

const extensionsTs = await read('build/lib/extensions.ts');
const excludedMatch = /const excludedExtensions = \[([^\]]*)\];/.exec(extensionsTs);
if (!excludedMatch) throw new Error('excludedExtensions not found in build/lib/extensions.ts');
const excludedExtensions = [...excludedMatch[1].matchAll(/'([^']+)'/g)].map(m => m[1]);
if (!/\.filter\(\(\{ name \}\) => excludedExtensions\.indexOf\(name\) === -1\)/.test(extensionsTs) ||
  !/\.filter\(\(\{ name \}\) => builtInExtensions\.every\(b => b\.name !== name\)\)/.test(extensionsTs) ||
  !/export function packageCopilotExtensionStream\(\)[\s\S]*?path\.join\(root, 'extensions', 'copilot'\)/.test(extensionsTs)) {
  throw new Error('build/lib/extensions.ts no longer matches the documented packaging rule');
}
const marketplaceBuiltIns = JSON.parse(await read('product.json')).builtInExtensions ?? [];

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

const builtIns = [];
for (const folder of (await readdir(join(root, 'extensions'))).sort()) {
  const manifestFile = join(root, 'extensions', folder, 'package.json');
  if (!existsSync(manifestFile)) continue;
  const local = !excludedExtensions.includes(folder) && marketplaceBuiltIns.every(b => b.name !== folder);
  if (!local && folder !== 'copilot') continue;
  const nlsFile = join(root, 'extensions', folder, 'package.nls.json');
  const manifest = JSON.parse(await readFile(manifestFile, 'utf8'));
  builtIns.push({
    folder,
    manifest: localize(manifest, existsSync(nlsFile) ? JSON.parse(await readFile(nlsFile, 'utf8')) : undefined),
  });
}
// extensionCmp (extensionDescriptionRegistry.ts): all built-in, by folder name with `<`.
builtIns.sort((a, b) => a.folder < b.folder ? -1 : a.folder > b.folder ? 1 : 0);

// --- Evaluation --------------------------------------------------------------------------

function frames(stack) {
  const result = [];
  for (const line of stack.split('\n').slice(1)) {
    const m = /(?:\(|at )file:\/\/[^\s)]*?:(\d+):(\d+)\)?$/.exec(line.trim());
    if (m) result.push({ line: +m[1], column: +m[2], file: fileAtLine(+m[1]) });
  }
  return result;
}

async function evaluate(platform) {
  globalThis.vscode = { process: { platform, arch: 'x64', env: {}, versions: {}, cwd: () => (platform === 'win32' ? 'C:\\' : '/') } };
  const previousLimit = Error.stackTraceLimit;
  Error.stackTraceLimit = 100;
  let mod;
  try {
    mod = await import(`${pathToFileURL(bundlePath).href}?platform=${platform}`);
  } finally {
    delete globalThis.vscode;
  }
  const coreCount = mod.registrations.length;

  // colorExtensionPoint.ts: the workbench creates one ColorExtensionPoint, and the extension
  // service hands the `colors` users to its handler in extension order.
  new mod.ColorExtensionPoint();
  const points = mod.extensionPoints.filter(p => p.name === 'colors');
  if (points.length !== 1 || !points[0].handler) throw new Error('The colors extension point has no handler');
  const collectorMessages = [];
  const users = builtIns.filter(e => e.manifest.contributes && Object.prototype.hasOwnProperty.call(e.manifest.contributes, 'colors')).map(e => ({
    description: { identifier: { value: `${e.manifest.publisher}.${e.manifest.name}` }, name: e.manifest.name, isBuiltin: true },
    value: e.manifest.contributes.colors,
    collector: {
      error: message => collectorMessages.push(`error ${e.folder}: ${message}`),
      warn: message => collectorMessages.push(`warning ${e.folder}: ${message}`),
      info: message => collectorMessages.push(`info ${e.folder}: ${message}`),
    },
    folder: e.folder,
  }));
  points[0].handler(users, { added: users, removed: [] });
  Error.stackTraceLimit = previousLimit;

  // Attribute registrations to files and check the call sites.
  const executed = new Map();
  const sources = [];
  for (const [index, { id, stack }] of mod.registrations.entries()) {
    const site = frames(stack).find(f => f.file !== 'baocode:instrument' && f.file !== colorUtilsFile);
    if (!site || !colorFileSet.has(site.file)) throw new Error(`Cannot attribute the registration of ${id} (${site?.file})`);
    if (!executed.has(site.file)) executed.set(site.file, new Set());
    executed.get(site.file).add(`${site.line}:${site.column}`);
    sources.push(index < coreCount ? site.file : `extensions/${users.find(u => u.value.some(c => c.id === id))?.folder}/package.json`);
  }
  for (const [file, sites] of callSites) {
    const ran = executed.get(file) ?? new Set();
    const missing = [...sites].filter(s => !ran.has(s));
    const unknown = [...ran].filter(s => !sites.has(s));
    if (missing.length || unknown.length) {
      throw new Error(`${file}: registerColor call sites not run at load: ${missing.map(s => bundleLines[+s.split(':')[0] - 1].trim()).join(' | ')} ${unknown.length ? `(unexpected ${unknown})` : ''}`);
    }
  }
  const firstIndex = new Map();
  sources.forEach((file, i) => { if (!firstIndex.has(file)) firstIndex.set(file, i); });
  const coreFiles = [...firstIndex.keys()].filter(f => colorFileSet.has(f));
  for (let i = 1; i < coreFiles.length; i++) {
    if (desktopOrder.get(coreFiles[i - 1]) > desktopOrder.get(coreFiles[i])) throw new Error(`${coreFiles[i]} registered before ${coreFiles[i - 1]}`);
  }
  for (const id of ['base.contributions.colors', 'base.contributions.json']) {
    if (mod.registryFallbacks.includes(id)) throw new Error(`Registry.as('${id}') fell back to the stub`);
  }
  return { mod, coreCount, sources, collectorMessages };
}

// --- Serialization ---------------------------------------------------------------------

const schemes = ['dark', 'light', 'hcDark', 'hcLight'];
const transformOps = ['darken', 'lighten', 'transparent', 'opaque', 'oneOf', 'lessProminent', 'ifDefinedThenElse', 'mix'];

function makeSerializer({ Color, HSLA, HSVA, RGBA }) {
  const warnings = [];
  const number = (n, where) => {
    if (typeof n !== 'number' || !Number.isFinite(n)) throw new Error(`${where}: ${String(n)} is not a finite number`);
    return n;
  };
  const literal = (color, where) => {
    // A Color made from HSLA/HSVA (e.g. `Color.black.lighten(0.2)`) answers `hsla`/`hsva` with
    // the value it was made from; a hex literal is only the same color if that equals the
    // conversion of its RGBA.
    if ((color._hsla !== undefined && !HSLA.equals(color._hsla, HSLA.fromRGBA(color.rgba))) ||
      (color._hsva !== undefined && !HSVA.equals(color._hsva, HSVA.fromRGBA(color.rgba)))) {
      throw new Error(`${where}: a Color made from HSLA/HSVA needs a literal kind the Dart data does not have`);
    }
    const hex = Color.Format.CSS.formatHexA(color, true);
    if (Color.fromHex(hex).equals(color)) return { hex };
    // An alpha that is not n/255 (e.g. `new RGBA(100, 100, 100, 0.7)`) is kept as it is.
    const { r, g, b, a } = color.rgba;
    if (!new Color(new RGBA(r, g, b, a)).equals(color)) throw new Error(`${where}: cannot keep ${JSON.stringify(color.rgba)}`);
    return { rgba: [r, g, b, a] };
  };
  function value(v, where) {
    if (v === null || v === undefined) return null;
    if (typeof v === 'string') {
      if (v.length === 0) throw new Error(`${where}: empty color value`);
      if (v[0] === '#') {
        // resolveColorValue: Color.fromHex, red for an invalid hex string.
        if (!Color.Format.CSS.parseHex(v)) warnings.push(`${where}: invalid hex ${v} resolves to red`);
        return literal(Color.fromHex(v), where);
      }
      return { ref: v };
    }
    if (v instanceof Color) return literal(v, where);
    if (typeof v === 'object' && typeof v.op === 'number' && transformOps[v.op]) {
      const op = transformOps[v.op];
      const keys = { darken: ['value', 'factor'], lighten: ['value', 'factor'], transparent: ['value', 'factor'], opaque: ['value', 'background'], oneOf: ['values'], lessProminent: ['value', 'background', 'factor', 'transparency'], ifDefinedThenElse: ['if', 'then', 'else'], mix: ['color', 'with', 'ratio'] }[op];
      const extra = Object.keys(v).filter(k => k !== 'op' && !keys.includes(k));
      if (extra.length) throw new Error(`${where}: unexpected ${op} fields ${extra}`);
      const t = { op };
      for (const key of keys) {
        const field = v[key];
        if (key === 'factor' || key === 'transparency') t[key] = number(field, where);
        else if (key === 'ratio') t[key] = field === undefined ? undefined : number(field, where);
        else if (key === 'if') { if (typeof field !== 'string') throw new Error(`${where}: ifDefinedThenElse.if is not an id`); t[key] = field; }
        else if (key === 'values') { if (!Array.isArray(field)) throw new Error(`${where}: oneOf.values`); t[key] = field.map((x, i) => value(x, `${where}.values[${i}]`)); }
        else {
          if (field === null || field === undefined) throw new Error(`${where}: ${op}.${key} is missing`);
          t[key] = value(field, `${where}.${key}`);
        }
      }
      return t;
    }
    throw new Error(`${where}: unexpected color value ${typeof v === 'function' ? '<stub>' : String(v)} (${typeof v})`);
  }
  return { value, warnings };
}

function serializeRegistry(mod) {
  const serializer = makeSerializer(mod);
  const colors = mod.getColorRegistry().getColors().map(({ id, defaults }) => {
    if (typeof id !== 'string' || id.length === 0) throw new Error(`Registered id ${String(id)} is not a string`);
    // resolveDefaultColor: falsy defaults resolve to undefined; ColorDefaults by theme type;
    // any other value is the default of every theme type.
    if (!defaults) return { id, defaults: null };
    if (mod.isColorDefaults(defaults)) {
      const extra = Object.keys(defaults).filter(k => !schemes.includes(k));
      if (extra.length) throw new Error(`${id}: unexpected ColorDefaults keys ${extra}`);
      return { id, defaults: Object.fromEntries(schemes.map(s => [s, serializer.value(defaults[s], `${id}.${s}`)])) };
    }
    const single = serializer.value(defaults, id);
    return { id, defaults: Object.fromEntries(schemes.map(s => [s, single])), single: true };
  });
  return { colors, warnings: serializer.warnings };
}

// --- Run ------------------------------------------------------------------------------

const runs = {};
for (const platform of platforms) runs[platform] = await evaluate(platform);
const main = runs.darwin;
const registry = serializeRegistry(main.mod);
for (const platform of platforms.slice(1)) {
  if (JSON.stringify(serializeRegistry(runs[platform].mod)) !== JSON.stringify(registry)) throw new Error(`The ${platform} registry differs from darwin's`);
}
const ids = registry.colors.map(c => c.id);
if (new Set(ids).size !== ids.length) throw new Error('Duplicate ids in getColors()');
const coreIds = new Set(main.mod.registrations.slice(0, main.coreCount).map(r => r.id));
const sourceOf = new Map();
main.mod.registrations.forEach((r, i) => { if (!sourceOf.has(r.id)) sourceOf.set(r.id, main.sources[i]); });

// --- Dart -------------------------------------------------------------------------------

const dartString = s => `'${s.replaceAll('\\', '\\\\').replaceAll("'", "\\'").replaceAll('$', '\\$')}'`;
const dartNumber = n => { const s = String(n); return /[.e]/.test(s) ? s : `${s}.0`; };
function dartValue(v) {
  if (v === null) return 'null';
  if (v.hex) return `ColorLiteral(${dartString(v.hex)})`;
  if (v.rgba) return `ColorLiteral.rgba(${v.rgba.slice(0, 3).join(', ')}, ${dartNumber(v.rgba[3])})`;
  if (v.ref !== undefined) return `ColorReference(${dartString(v.ref)})`;
  switch (v.op) {
    case 'darken': return `DarkenTransform(${dartValue(v.value)}, ${dartNumber(v.factor)})`;
    case 'lighten': return `LightenTransform(${dartValue(v.value)}, ${dartNumber(v.factor)})`;
    case 'transparent': return `TransparentTransform(${dartValue(v.value)}, ${dartNumber(v.factor)})`;
    case 'opaque': return `OpaqueTransform(${dartValue(v.value)}, ${dartValue(v.background)})`;
    case 'oneOf': return `OneOfTransform([${v.values.map(dartValue).join(', ')}])`;
    case 'lessProminent': return `LessProminentTransform(${dartValue(v.value)}, ${dartValue(v.background)}, ${dartNumber(v.factor)}, ${dartNumber(v.transparency)})`;
    case 'ifDefinedThenElse': return `IfDefinedThenElseTransform(${dartString(v.if)}, ${dartValue(v.then)}, ${dartValue(v.else)})`;
    case 'mix': return `MixTransform(${dartValue(v.color)}, ${dartValue(v.with)}${v.ratio === undefined ? '' : `, ${dartNumber(v.ratio)}`})`;
  }
  throw new Error(`Cannot write ${JSON.stringify(v)}`);
}

const extensionColorCount = ids.length - ids.filter(id => coreIds.has(id)).length;
const dartLines = [
  '/*---------------------------------------------------------------------------------------------',
  ' *  Copyright (c) Microsoft Corporation. All rights reserved.',
  ' *  Licensed under the MIT License. See ../../../../LICENSE.txt for license information.',
  ' *--------------------------------------------------------------------------------------------*/',
  '// GENERATED FILE - DO NOT EDIT. Written by tool/generate_color_registry.mjs from VS Code',
  `// ${revision}: the color registry`,
  '// (src/vs/platform/theme/common/colorUtils.ts `getColorRegistry().getColors()`) after the',
  `// desktop workbench's registrations (${colorFiles.length} files, ${ids.length - extensionColorCount} ids) and the built-in`,
  `// extensions' \`contributes.colors\` (${extensionColorCount} ids), in registration order. A default that is a single`,
  '// ColorValue upstream is written for all four color schemes. Hex strings and `Color`s are',
  '// written as `Color.Format.CSS.formatHexA(color, true)`, or as their RGBA where that hex',
  '// would not keep the alpha.',
  '',
  "import 'color_utils.dart';",
  '',
  '/// The registered colors, in registration order.',
  'const List<ColorContribution> colorRegistryData = [',
];
let previousSource;
for (const color of registry.colors) {
  const source = sourceOf.get(color.id);
  if (source !== previousSource) {
    dartLines.push(`  // ${source.startsWith('extensions/') ? `${source} contributes.colors` : source}`);
    previousSource = source;
  }
  const d = color.defaults;
  const defaults = d === null ? 'null' : `ColorDefaults(${schemes.map(s => `${s}: ${dartValue(d[s])}`).join(', ')},)`;
  dartLines.push(`  ColorContribution(${dartString(color.id)}, ${defaults},),`);
}
dartLines.push('];', '');
await mkdir(dirname(dartOutput), { recursive: true });
await writeFile(dartOutput, dartLines.join('\n'));
execFileSync('dart', ['format', dartOutput], { stdio: 'inherit', shell: process.platform === 'win32' });

// --- Goldens ------------------------------------------------------------------------------

const { mod } = main;
const { Color, HSLA, HSVA, RGBA, ColorThemeData, ColorScheme, URI, joinPath } = mod;

const values = [];
const valueIndex = new Map();
const num = n => Number.isNaN(n) ? 'NaN' : n;
function colorKey(color) {
  // The RGBA, plus the HSLA/HSVA a Color keeps when it was made from one (it answers `hsla`
  // with that instead of converting its RGBA).
  let key = `${color.rgba.r},${color.rgba.g},${color.rgba.b},${num(color.rgba.a)}`;
  if (color._hsla) key += `|hsla:${color._hsla.h},${num(color._hsla.s)},${num(color._hsla.l)},${num(color._hsla.a)}`;
  if (color._hsva) key += `|hsva:${color._hsva.h},${num(color._hsva.s)},${num(color._hsva.v)},${num(color._hsva.a)}`;
  return key;
}
function valueOf(color) {
  if (color === undefined) return null;
  if (!(color instanceof Color)) throw new Error(`getColor returned ${String(color)}`);
  const key = colorKey(color);
  if (!valueIndex.has(key)) { valueIndex.set(key, values.length); values.push(key); }
  return valueIndex.get(key);
}
function record(theme) {
  return {
    getColor: ids.map(id => valueOf(theme.getColor(id))),
    getColorNoDefault: ids.map(id => valueOf(theme.getColor(id, false))),
    defines: ids.map(id => theme.defines(id) ? 1 : 0).join(''),
  };
}

const manifest = JSON.parse(await readFile(manifestPath, 'utf8'));
// VS Code's themes; BaoCode's own (generate_textmate_assets.mjs `localThemes`)
// have no upstream to match.
manifest.themes = manifest.themes.filter(theme => theme.extension !== 'theme-bao');
// Contributed themes generate_textmate_assets.mjs leaves out of the manifest.
const excludedThemes = ['Visual Studio Light', 'Light+'];
const themeContributions = builtIns.flatMap(e => (e.manifest.contributes?.themes ?? []).map(t => ({ extension: e, theme: t })))
  .filter(({ theme }) => !excludedThemes.includes(theme.id));
if (themeContributions.length !== manifest.themes.length) throw new Error(`The built-in extensions contribute ${themeContributions.length} color themes, ${manifestPath} lists ${manifest.themes.length}`);
const themes = [];
for (const bundledTheme of manifest.themes) {
  const match = themeContributions.find(c => c.theme.id === bundledTheme.id && c.extension.folder === bundledTheme.extension);
  if (!match) throw new Error(`${bundledTheme.id} is not contributed by ${bundledTheme.extension}`);
  const { extension, theme } = match;
  if (theme.label !== bundledTheme.label || theme.uiTheme !== bundledTheme.uiTheme) throw new Error(`${bundledTheme.id}: the manifest's label or uiTheme differs from upstream`);
  const extensionLocation = URI.file(join(root, 'extensions', extension.folder));
  const data = ColorThemeData.fromExtensionTheme(theme, joinPath(extensionLocation, theme.path), {
    extensionId: `${extension.manifest.publisher}.${extension.manifest.name}`,
    extensionPublisher: extension.manifest.publisher,
    extensionName: extension.manifest.name,
    extensionIsBuiltin: true,
  });
  await data.ensureLoaded({ readExtensionResource: uri => readFile(uri.fsPath, 'utf8') });
  themes.push({ name: bundledTheme.id, uiTheme: theme.uiTheme, type: data.type, ...record(data) });
}
for (const scheme of [ColorScheme.DARK, ColorScheme.LIGHT, ColorScheme.HIGH_CONTRAST_DARK, ColorScheme.HIGH_CONTRAST_LIGHT]) {
  const data = ColorThemeData.createUnloadedThemeForThemeType(scheme);
  themes.push({ name: null, type: data.type, ...record(data) });
}

// color.ts results for seeded random inputs.
let seed = 0x6a598d4a;
const random = () => { seed = (seed + 0x6d2b79f5) | 0; let t = seed; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const randomInt = n => Math.floor(random() * n);
const pick = list => list[randomInt(list.length)];
const factors = [0, 0.05, 0.1, 0.2, 0.25, 0.3, 0.4, 0.5, 0.6, 0.7, 0.75, 0.8, 1, 1.5, -0.2];
const randomFactor = () => random() < 0.5 ? pick(factors) : Math.round(random() * 1000) / 1000;
const special = [[0, 0, 0, 1], [255, 255, 255, 1], [0, 0, 0, 0], [255, 0, 0, 1], [128, 128, 128, 1], [18, 19, 20, 1], [255, 255, 255, 0.5]];
function randomColor() {
  const kind = random();
  if (kind < 0.1) return new Color(new RGBA(...pick(special)));
  if (kind < 0.2) return new Color(new HSLA(randomInt(361), Math.round(random() * 1000) / 1000, Math.round(random() * 1000) / 1000, pick([1, 0.5, 0.25])));
  if (kind < 0.25) return new Color(new HSVA(randomInt(361), Math.round(random() * 1000) / 1000, Math.round(random() * 1000) / 1000, pick([1, 0.5])));
  const alpha = random() < 0.6 ? 1 : randomInt(256) / 255;
  return new Color(new RGBA(randomInt(256), randomInt(256), randomInt(256), alpha));
}
const colorJson = c => {
  const out = { rgba: [c.rgba.r, c.rgba.g, c.rgba.b, num(c.rgba.a)] };
  if (c._hsla) out.hsla = [c._hsla.h, num(c._hsla.s), num(c._hsla.l), num(c._hsla.a)];
  if (c._hsva) out.hsva = [c._hsva.h, num(c._hsva.s), num(c._hsva.v), num(c._hsva.a)];
  return out;
};
const resultJson = r => r instanceof Color ? { color: colorJson(r) } : r instanceof HSLA ? { hsla: [r.h, num(r.s), num(r.l), num(r.a)] } : r instanceof HSVA ? { hsva: [r.h, num(r.s), num(r.v), num(r.a)] } : r instanceof RGBA ? { rgba: [r.r, r.g, r.b, num(r.a)] } : typeof r === 'number' ? { number: num(r) } : r === undefined ? { undefined: true } : { value: r };
const colorOps = [];
const op = (name, args, run) => colorOps.push({ op: name, args: args.map(a => a instanceof Color ? { color: colorJson(a) } : { number: num(a) }), result: resultJson(run()) });
for (let i = 0; i < 80; i++) {
  const a = randomColor(), b = randomColor(), c = randomColor(), f = randomFactor(), g = randomFactor();
  const opaqueB = new Color(new RGBA(b.rgba.r, b.rgba.g, b.rgba.b, 1));
  op('hsla', [a], () => a.hsla);
  op('hsva', [a], () => a.hsva);
  op('lighten', [a, f], () => a.lighten(f));
  op('darken', [a, f], () => a.darken(f));
  op('lighten.darken', [a, f, g], () => a.lighten(f).darken(g));
  op('darken.lighten.hsla', [a, f, g], () => a.darken(f).lighten(g).hsla);
  op('transparent', [a, f], () => a.transparent(f));
  op('opposite', [a], () => a.opposite());
  op('blend', [a, b], () => a.blend(b));
  op('mix', [a, b, f], () => a.mix(b, f));
  op('mixDefault', [a, b], () => a.mix(b));
  op('makeOpaque', [a, opaqueB], () => a.makeOpaque(opaqueB));
  op('makeOpaque', [a, b], () => a.makeOpaque(b));
  op('flatten', [a, b, c], () => a.flatten(b, c));
  op('flatten', [a, b], () => a.flatten(b));
  op('getRelativeLuminance', [a], () => a.getRelativeLuminance());
  op('getContrastRatio', [a, b], () => a.getContrastRatio(b));
  op('isDarker', [a], () => a.isDarker());
  op('isLighter', [a], () => a.isLighter());
  op('isDarkerThan', [a, b], () => a.isDarkerThan(b));
  op('isLighterThan', [a, b], () => a.isLighterThan(b));
  op('getLighterColor', [a, b, f], () => Color.getLighterColor(a, b, f));
  op('getDarkerColor', [a, b, f], () => Color.getDarkerColor(a, b, f));
  op('getLighterColorDefault', [a, b], () => Color.getLighterColor(a, b));
  op('getDarkerColorDefault', [a, b], () => Color.getDarkerColor(a, b));
  const ratio = 1 + random() * 20;
  op('ensureConstrast', [a, b, ratio], () => a.ensureConstrast(b, ratio));
  op('equals', [a, b], () => a.equals(b));
  op('equalsSelf', [a], () => a.equals(new Color(new RGBA(a.rgba.r, a.rgba.g, a.rgba.b, a.rgba.a))));
  op('toString', [a], () => a.toString());
  op('formatRGB', [a], () => Color.Format.CSS.formatRGB(a));
  op('formatRGBA', [a], () => Color.Format.CSS.formatRGBA(a));
  op('formatHSL', [a], () => Color.Format.CSS.formatHSL(a));
  op('formatHSLA', [a], () => Color.Format.CSS.formatHSLA(a));
  op('formatHexA', [a], () => Color.Format.CSS.formatHexA(a));
  op('toNumber32Bit', [a], () => a.toNumber32Bit());
  op('hslaToRGBA', [a], () => HSLA.toRGBA(a.hsla));
  op('hsvaToRGBA', [a], () => HSVA.toRGBA(a.hsva));
}
// Equal luminance, where getLighterColor/getDarkerColor divide 0 by 0.
for (const [x, y] of [[[0, 0, 0, 1], [0, 0, 0, 1]], [[0, 0, 0, 1], [0, 0, 0, 0.5]], [[255, 255, 255, 1], [255, 255, 255, 1]], [[10, 200, 30, 1], [10, 200, 30, 0.2]]]) {
  const a = new Color(new RGBA(...x)), b = new Color(new RGBA(...y));
  op('getLighterColor', [a, b, 0.4], () => Color.getLighterColor(a, b, 0.4));
  op('getDarkerColor', [a, b, 0.4], () => Color.getDarkerColor(a, b, 0.4));
  op('darken', [a, NaN], () => a.darken(NaN));
  op('lighten', [a, NaN], () => a.lighten(NaN));
  op('transparent', [a, NaN], () => a.transparent(NaN));
}
const luminance = [];
for (let c = 0; c < 256; c++) luminance.push(Color._relativeLuminanceForComponent(c));

const fixture = {
  revision,
  generator: 'tool/generate_color_registry.mjs',
  ids,
  extensionIds: ids.filter(id => !coreIds.has(id)),
  values,
  themes,
  luminance,
  colorOps,
};
await mkdir(dirname(fixtureOutput), { recursive: true });
await writeFile(fixtureOutput, gzipSync(Buffer.from(JSON.stringify(fixture)), { level: 9 }));

// --- Summary -------------------------------------------------------------------------------

console.log(`VS Code ${revision}, esbuild ${installed}`);
console.log(`grep 'registerColor(': ${grepHits.length} files; desktop workbench: ${colorFiles.length}; left out: ${notInDesktop.join(', ') || 'none'}`);
const fallbacks = [...new Set(main.mod.registryFallbacks)].sort();
console.log(`bundle: ${realModules.length} real modules, ${stubbed.size} stubbed imports; Registry.as fell back to the stub for ${main.mod.registryFallbacks.length} calls (${fallbacks.join(', ')})`);
console.log(`registrations: ${main.coreCount} core calls, ${ids.length} ids (${ids.length - extensionColorCount} core, ${extensionColorCount} from extensions: ${[...new Set(main.sources.slice(main.coreCount))].join(', ')})`);
console.log(`identical registries for ${platforms.join(', ')}`);
for (const message of main.collectorMessages) console.log(`extension point: ${message}`);
for (const warning of registry.warnings) console.log(`warning: ${warning}`);
const fixtureSize = (await stat(fixtureOutput)).size;
console.log(`wrote ${dartOutput} and ${fixtureOutput} (${themes.length} themes, ${values.length} distinct colors, ${colorOps.length} color ops, ${fixtureSize} bytes)`);
if (keep) console.log(`kept ${temporary}`);
else await rm(temporary, { recursive: true, force: true });
