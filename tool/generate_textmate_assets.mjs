// Download the pinned VS Code TextMate grammars, language registrations and
// configurations, and color themes for the Flutter TextMate port; no JavaScript
// runs in the Flutter app.
// Usage: node tool/generate_textmate_assets.mjs [output-directory]
// (default output: assets/textmate; the directory is replaced.)
//
// Which extensions: every built-in extension the desktop product build ships at
// `revision`. build/lib/extensions.ts `doPackageLocalExtensionsStream` packages each
// `extensions/*/package.json` folder except `excludedExtensions` (the test extensions
// vscode-api-tests, vscode-colorize-tests, vscode-colorize-perf-tests and
// vscode-test-resolver, plus copilot) and except product.json `builtInExtensions`
// (marketplace downloads, none of them a local folder). Copilot is excluded there only
// because the product build ships it separately: the pipeline's Copilot stage packages
// extensions/copilot as a VSIX that build/azure-pipelines/common/downloadCopilotVsix.ts
// extracts to .build/extensions/copilot (local builds: `packageCopilotExtensionStream`),
// so it is included here, from its package.json at `revision`.
//
// Order: `extensionCmp` (src/vs/workbench/services/extensions/common/
// extensionDescriptionRegistry.ts) sorts built-in extensions by folder name with
// JavaScript's `<`; `_handleExtensionPoint` (abstractExtensionService.ts) hands the
// `languages` and `grammars` extension points their contributions in that order, and
// each handler walks an extension's array in package.json order (languageService.ts,
// textMateTokenizationFeatureImpl.ts `_handleGrammarsExtPoint`). `LanguagesRegistry`
// (languagesRegistry.ts) registers ModesRegistry's languages first: `plaintext`
// (src/vs/editor/common/languages/modesRegistry.ts) leads the manifest's languages.
import { mkdir, rm, writeFile } from 'node:fs/promises';
import { dirname, join, posix } from 'node:path';

const revision = '6a598d4a13031703d483d103c1d934a36ad27971';
const source = `https://raw.githubusercontent.com/microsoft/vscode/${revision}/`;
const extensionListing = `https://api.github.com/repos/microsoft/vscode/contents/extensions?ref=${revision}`;
const output = process.argv[2] ?? 'assets/textmate';
if (process.argv.length > 3) throw new Error('Usage: node tool/generate_textmate_assets.mjs [output-directory]');

const themeExtensions = [
  'theme-defaults', 'theme-monokai', 'theme-monokai-dimmed', 'theme-solarized-dark',
  'theme-solarized-light', 'theme-abyss', 'theme-kimbie-dark', 'theme-quietlight',
  'theme-red', 'theme-tomorrow-night-blue',
];
// Contributed themes left out of the manifest: Light (Visual Studio) and
// Light+. Their light_vs.json and light_plus.json are still copied, as Light
// Modern includes them.
const excludedThemes = ['Visual Studio Light', 'Light+'];

async function download(path) {
  for (let attempt = 1; ; attempt++) {
    try {
      const response = await fetch(path.startsWith('https:') ? path : source + path, { headers: { 'User-Agent': 'baocode-textmate-assets' } });
      if (response.status === 404) return null;
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      return Buffer.from(await response.arrayBuffer());
    } catch (error) {
      if (attempt >= 4) throw new Error(`Cannot download ${path}: ${error.message}`);
      await new Promise(resolve => setTimeout(resolve, 500 * attempt));
    }
  }
}

async function downloadText(path) {
  const bytes = await download(path);
  if (!bytes) throw new Error(`Missing ${path} at ${revision}`);
  return bytes.toString('utf8');
}

// Enough JSONC for package.json and theme files: comments and trailing commas.
function parseJsonc(text) {
  let result = '';
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (c === '"') {
      const start = i;
      for (i++; i < text.length && text[i] !== '"'; i++) if (text[i] === '\\') i++;
      result += text.slice(start, i + 1);
    } else if (c === '/' && text[i + 1] === '/') {
      while (i < text.length && text[i] !== '\n') i++;
      result += '\n';
    } else if (c === '/' && text[i + 1] === '*') {
      const end = text.indexOf('*/', i + 2);
      i = end < 0 ? text.length : end + 1;
      result += ' ';
    } else {
      result += c;
    }
  }
  return JSON.parse(result.replace(/,(\s*[}\]])/g, '$1'));
}

// `replaceNLStrings` (src/vs/platform/extensionManagement/common/extensionNls.ts):
// every `%key%` string in the manifest becomes its package.nls.json message (English,
// no fallback messages); a key without a message keeps the placeholder.
function localizeManifest(manifest, messages) {
  const processEntry = (obj, key) => {
    const value = obj[key];
    if (typeof value === 'string') {
      if (value.length > 1 && value[0] === '%' && value[value.length - 1] === '%') {
        const translated = messages[value.substr(1, value.length - 2)];
        const message = typeof translated === 'string' ? translated : translated?.message;
        if (message) obj[key] = message;
      }
    } else if (Array.isArray(value)) {
      for (let i = 0; i < value.length; i++) processEntry(value, i);
    } else if (value !== null && typeof value === 'object') {
      for (const k in value) if (Object.hasOwn(value, k)) processEntry(value, k);
    }
  };
  for (const key in manifest) if (Object.hasOwn(manifest, key)) processEntry(manifest, key);
  return manifest;
}

const files = new Map(); // asset path -> bytes

// Copies an extension file to `<kind>/<extension>/<path>`; `transform` may rewrite it.
async function copy(kind, extension, relativePath, transform) {
  const normalized = posix.normalize(relativePath);
  if (normalized.startsWith('..')) throw new Error(`${extension}: ${relativePath} leaves the extension`);
  const assetPath = `${kind}/${extension}/${normalized}`;
  if (!files.has(assetPath)) {
    const bytes = await download(`extensions/${extension}/${normalized}`);
    if (!bytes) throw new Error(`Missing extensions/${extension}/${normalized}`);
    files.set(assetPath, transform ? transform(bytes) : bytes);
  }
  return assetPath;
}

// Grammar JSON as the product build ships it (build/lib/extensions.ts
// `minifyExtensionResources` stringifies every JSON file that parses): whitespace
// dropped, key order and values as a JavaScript parser sees them.
// tool/generate_textmate_fixtures.mjs checks vscode-textmate reads both alike.
function minifyGrammar(bytes) {
  let value;
  try {
    value = JSON.parse(bytes.toString('utf8'));
  } catch {
    return bytes;
  }
  return Buffer.from(JSON.stringify(value));
}

async function readExtension(extension) {
  const packageBytes = await download(`extensions/${extension}/package.json`);
  if (!packageBytes) return null;
  const nlsBytes = await download(`extensions/${extension}/package.nls.json`);
  const nls = nlsBytes ? parseJsonc(nlsBytes.toString('utf8')) : {};
  const manifest = localizeManifest(parseJsonc(packageBytes.toString('utf8')), nls);
  const cgBytes = await download(`extensions/${extension}/cgmanifest.json`);
  return { extension, manifest, cgBytes, cgmanifest: cgBytes ? parseJsonc(cgBytes.toString('utf8')) : undefined, copied: false };
}

const pick = (object, keys) =>
  Object.fromEntries(keys.filter(key => object[key] !== undefined).map(key => [key, object[key]]));

// --- The shipped extensions, in `extensionCmp` order ---
const buildScript = await downloadText('build/lib/extensions.ts');
const excludedMatch = /const excludedExtensions = \[([^\]]*)\]/.exec(buildScript);
if (!excludedMatch || !buildScript.includes('export function packageCopilotExtensionStream')) {
  throw new Error('build/lib/extensions.ts changed shape; re-read its packaging rules');
}
const excludedExtensions = [...excludedMatch[1].matchAll(/'([^']+)'/g)].map(match => match[1]);
const shippedSeparately = ['copilot'];
const marketplaceExtensions = (JSON.parse(await downloadText('product.json')).builtInExtensions ?? []).map(e => e.name);
const folders = JSON.parse(await downloadText(extensionListing))
  .filter(entry => entry.type === 'dir')
  .map(entry => entry.name)
  .filter(name => !excludedExtensions.includes(name) || shippedSeparately.includes(name))
  .filter(name => !marketplaceExtensions.includes(name))
  .sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
const extensions = [];
for (const folder of folders) {
  const data = await readExtension(folder);
  if (data) extensions.push(data); // folders without package.json (`types`) are not extensions
}

// --- Languages: `isValidLanguageExtensionPoint` (languageService.ts) ---
const isStringArray = value => value === undefined || (Array.isArray(value) && value.every(item => typeof item === 'string'));
function isValidLanguage(value) {
  return value && typeof value.id === 'string'
    && isStringArray(value.extensions) && isStringArray(value.filenames)
    && (value.firstLine === undefined || typeof value.firstLine === 'string')
    && (value.configuration === undefined || typeof value.configuration === 'string')
    && isStringArray(value.aliases) && isStringArray(value.mimetypes);
}
const languages = [
  // modesRegistry.ts: `nls.localize('plainText.alias', "Plain Text")`, `Mimes.text`.
  { id: 'plaintext', extensions: ['.txt'], aliases: ['Plain Text', 'text'], mimetypes: ['text/plain'] },
];
const skipped = [];
for (const data of extensions) {
  const contributed = data.manifest.contributes?.languages;
  if (contributed === undefined) continue;
  if (!Array.isArray(contributed)) throw new Error(`${data.extension}: contributes.languages is not an array`);
  for (const language of contributed) {
    if (!isValidLanguage(language)) {
      skipped.push(`${data.extension}: invalid language ${JSON.stringify(language)}`);
      continue;
    }
    const entry = {
      extension: data.extension,
      ...pick(language, ['id', 'aliases', 'extensions', 'filenames', 'filenamePatterns', 'firstLine', 'mimetypes']),
    };
    if (language.configuration) {
      entry.configuration = await copy('grammars', data.extension, language.configuration);
      data.copied = true;
    }
    languages.push(entry);
  }
}
const registered = new Set(languages.map(language => language.id));

// --- Grammars, all fields of each `contributes.grammars` entry ---
const grammars = [];
for (const data of extensions) {
  for (const grammar of data.manifest.contributes?.grammars ?? []) {
    if (typeof grammar.path !== 'string') throw new Error(`${data.extension}: grammar without a path`);
    const transform = posix.extname(grammar.path) === '.json' ? minifyGrammar : undefined;
    const path = await copy('grammars', data.extension, grammar.path, transform);
    data.copied = true;
    if (grammar.language && !registered.has(grammar.language)) {
      skipped.push(`${data.extension}: grammar ${grammar.scopeName} for unregistered language ${grammar.language}`);
    }
    grammars.push({
      extension: data.extension,
      ...pick(grammar, ['language', 'scopeName']),
      path,
      ...pick(grammar, ['embeddedLanguages', 'tokenTypes', 'injectTo', 'balancedBracketScopes', 'unbalancedBracketScopes']),
    });
  }
}

// --- Language-specific configuration defaults the tokenizer reads ---
// `editor.maxTokenizationLineLength` is read per language
// (textMateTokenizationFeatureImpl.ts `observableConfigValue`); extensions set it in
// `contributes.configurationDefaults` under `[language]` keys.
const configurationDefaults = {};
for (const data of extensions) {
  for (const [key, value] of Object.entries(data.manifest.contributes?.configurationDefaults ?? {})) {
    const setting = value?.['editor.maxTokenizationLineLength'];
    if (!/^\[.*\]$/.test(key) || setting === undefined) continue;
    configurationDefaults[key] = { ...configurationDefaults[key], 'editor.maxTokenizationLineLength': setting };
  }
}

// --- Color themes ---
// A color theme file with everything `_loadColorTheme` (colorThemeData.ts) reads
// from it: its `include` chain and a `tokenColors` path to a .tmTheme file.
async function copyTheme(extension, relativePath) {
  const assetPath = await copy('themes', extension, relativePath);
  if (posix.extname(relativePath) !== '.json') return assetPath;
  const content = parseJsonc(files.get(assetPath).toString('utf8'));
  const base = posix.dirname(posix.normalize(relativePath));
  if (content.include) await copyTheme(extension, posix.join(base, content.include));
  if (typeof content.tokenColors === 'string') await copy('themes', extension, posix.join(base, content.tokenColors));
  return assetPath;
}

const themes = [];
for (const extension of themeExtensions) {
  const data = extensions.find(candidate => candidate.extension === extension);
  if (!data) throw new Error(`${extension} is not shipped`);
  data.copied = true;
  for (const theme of data.manifest.contributes?.themes ?? []) {
    if (excludedThemes.includes(theme.id)) continue;
    themes.push({ extension, id: theme.id, label: theme.label, uiTheme: theme.uiTheme, path: await copyTheme(extension, theme.path) });
  }
}

// --- License: VS Code's MIT license, each bundled extension's cgmanifest.json
// (copied beside its files) and the matching ThirdPartyNotices.txt entries ---
const vscodeLicense = await downloadText('LICENSE.txt');
const notices = (await downloadText('ThirdPartyNotices.txt'))
  .split(/\n-{57}\n\n-{57}\n/).map(section => section.replace(/^\n+|\n-{57}\n*$/g, ''));
const escapeRegExp = text => text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const upstream = [];
const noticeTexts = [];
for (const data of extensions) {
  if (!data.copied || !data.cgmanifest) continue;
  const kind = themeExtensions.includes(data.extension) ? 'themes' : 'grammars';
  files.set(`${kind}/${data.extension}/cgmanifest.json`, data.cgBytes);
  for (const registration of data.cgmanifest.registrations ?? []) {
    const component = registration.component;
    const name = component.git?.name ?? component.other?.name ?? component.npm?.name;
    const location = component.git
      ? `${component.git.repositoryUrl} at ${component.git.commitHash}`
      : component.other?.downloadUrl ?? component.npm?.version;
    const license = typeof registration.license === 'string' ? registration.license : registration.license?.type;
    upstream.push(`- extensions/${data.extension}: ${name} ${registration.version ?? ''} (${location})` +
      (license ? `, ${license}` : '') + (registration.description ? `.\n  ${registration.description}` : '.'));
    // ThirdPartyNotices.txt names a component `[owner/]name version - license`; its
    // versions lag some cgmanifest.json files, so the name alone selects the entries.
    const header = new RegExp(`^(\\S+/)?${escapeRegExp(name)} `);
    const matches = notices.filter(section => header.test(section.split('\n')[0]));
    const texts = matches.length
      ? matches
      : registration.licenseDetail ? [`${name} ${registration.version ?? ''}\n\n${registration.licenseDetail.join('\n')}`] : [];
    if (!texts.length) throw new Error(`No notice for ${name} (${data.extension})`);
    for (const text of texts) if (!noticeTexts.includes(text)) noticeTexts.push(text);
  }
}
const license = [
  `The files in this directory were downloaded from Visual Studio Code`,
  `(https://github.com/microsoft/vscode) at revision ${revision}`,
  `by tool/generate_textmate_assets.mjs. The directory layout mirrors each`,
  `extension's: grammars/<extension>/... and themes/<extension>/... are the files of`,
  `extensions/<extension>/..., with each extension's cgmanifest.json (its component`,
  `registrations). JSON grammars are minified as VS Code's build minifies them.`,
  `Files without a separate notice below (the default themes, the JSDoc injection`,
  `grammars, language configurations) are part of Visual Studio Code:`,
  '',
  vscodeLicense.trim(),
  '',
  '='.repeat(79),
  '',
  'Grammars and themes derived from other projects, as registered in the',
  "extensions' cgmanifest.json files:",
  '',
  ...upstream,
  '',
  "Their entries from Visual Studio Code's ThirdPartyNotices.txt (or, for components",
  'it does not list, the license text in cgmanifest.json):',
  '',
  ...noticeTexts.flatMap(notice => ['-'.repeat(57), '', notice.trim(), '']),
].join('\n');

const manifest = {
  revision,
  attribution: 'Copyright (c) Microsoft Corporation and others. See LICENSE.txt in this directory.',
  grammars,
  languages,
  configurationDefaults,
  themes,
};

await rm(output, { recursive: true, force: true });
for (const [path, bytes] of files) {
  await mkdir(dirname(join(output, path)), { recursive: true });
  await writeFile(join(output, path), bytes);
}
await writeFile(join(output, 'LICENSE.txt'), license);
await writeFile(join(output, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
const directories = [...new Set([...files.keys()].map(path => posix.dirname(path)))].sort();
const bytes = [...files.values()].reduce((sum, file) => sum + file.length, 0);
console.log(`${extensions.length} extensions (excluded: ${excludedExtensions.filter(name => !shippedSeparately.includes(name)).join(', ')})`);
console.log(`Wrote ${files.size} files (${(bytes / 1024).toFixed(0)} KiB), ${grammars.length} grammars, ${languages.length} languages, ${themes.length} themes to ${output}`);
for (const message of skipped) console.log(`  VS Code skips ${message}`);
console.log('Asset directories for pubspec.yaml:');
console.log(`    - ${output}/`);
for (const directory of directories) console.log(`    - ${posix.join(output, directory)}/`);
