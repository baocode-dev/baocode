// Download the pinned VS Code TextMate grammars, color themes and language data
// for the Flutter TextMate port; no JavaScript runs in the Flutter app.
// Usage: node tool/generate_textmate_assets.mjs [output-directory]
// (default output: assets/textmate; the directory is replaced.)
import { mkdir, rm, writeFile } from 'node:fs/promises';
import { dirname, join, posix } from 'node:path';

const revision = '6a598d4a13031703d483d103c1d934a36ad27971';
const source = `https://raw.githubusercontent.com/microsoft/vscode/${revision}/`;
const output = process.argv[2] ?? 'assets/textmate';
if (process.argv.length > 3) throw new Error('Usage: node tool/generate_textmate_assets.mjs [output-directory]');

const grammarExtensions = ['typescript-basics'];
const themeExtensions = [
  'theme-defaults', 'theme-monokai', 'theme-monokai-dimmed', 'theme-solarized-dark',
  'theme-solarized-light', 'theme-abyss', 'theme-kimbie-dark', 'theme-quietlight',
  'theme-red', 'theme-tomorrow-night-blue',
];
// Language registrations the grammars need: TypeScript's own, and `jsx-tags`
// (extensions/javascript), which source.tsx's `embeddedLanguages` maps to. VS Code
// drops an embedded language that is not registered (textMateTokenizationFeatureImpl.ts).
const languageRegistrations = {
  'typescript-basics': ['typescript', 'typescriptreact'],
  javascript: ['jsx-tags'],
};

async function download(path) {
  for (let attempt = 1; ; attempt++) {
    try {
      const response = await fetch(source + path);
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

// VS Code's `replaceNLStrings` for a `%key%` value (extensionManifestPropertiesService).
function localize(value, nls) {
  const match = typeof value === 'string' && /^%([\w\d.-]+)%$/.exec(value);
  if (!match) return value;
  const entry = nls?.[match[1]];
  return typeof entry === 'string' ? entry : entry?.message ?? value;
}

const extensionRoot = extension => `extensions/${extension}/`;
const files = new Map(); // asset path -> bytes

async function copy(kind, extension, relativePath) {
  const normalized = posix.normalize(relativePath);
  if (normalized.startsWith('..')) throw new Error(`${extension}: ${relativePath} leaves the extension`);
  const assetPath = `${kind}/${extension}/${normalized}`;
  if (!files.has(assetPath)) {
    const bytes = await download(extensionRoot(extension) + normalized);
    if (!bytes) throw new Error(`Missing ${extensionRoot(extension)}${normalized}`);
    files.set(assetPath, bytes);
  }
  return assetPath;
}

async function readExtension(extension) {
  const manifest = parseJsonc(await downloadText(extensionRoot(extension) + 'package.json'));
  const nlsBytes = await download(extensionRoot(extension) + 'package.nls.json');
  const nls = nlsBytes ? parseJsonc(nlsBytes.toString('utf8')) : undefined;
  const cgBytes = await download(extensionRoot(extension) + 'cgmanifest.json');
  const cgmanifest = cgBytes ? parseJsonc(cgBytes.toString('utf8')) : undefined;
  return { extension, manifest, nls, cgmanifest };
}

const pick = (object, keys) =>
  Object.fromEntries(keys.filter(key => object[key] !== undefined).map(key => [key, object[key]]));

const grammars = [];
const languages = [];
const themes = [];
const components = [];

for (const extension of grammarExtensions) {
  const data = await readExtension(extension);
  components.push(data);
  for (const grammar of data.manifest.contributes?.grammars ?? []) {
    const path = await copy('grammars', extension, grammar.path);
    grammars.push({
      extension,
      ...pick(grammar, ['language', 'scopeName']),
      path,
      ...pick(grammar, ['embeddedLanguages', 'tokenTypes', 'injectTo', 'balancedBracketScopes', 'unbalancedBracketScopes']),
    });
  }
}

for (const [extension, ids] of Object.entries(languageRegistrations)) {
  const data = grammarExtensions.includes(extension)
    ? components.find(component => component.extension === extension)
    : await readExtension(extension);
  for (const id of ids) {
    const registration = (data.manifest.contributes?.languages ?? []).find(language => language.id === id);
    if (!registration) throw new Error(`${extension} does not register ${id}`);
    const entry = { extension, ...pick(registration, ['id', 'aliases', 'extensions', 'filenames', 'filenamePatterns', 'firstLine', 'mimetypes']) };
    if (registration.configuration) {
      entry.configuration = await copy('grammars', extension, registration.configuration);
    }
    languages.push(entry);
  }
}

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

for (const extension of themeExtensions) {
  const data = await readExtension(extension);
  components.push(data);
  for (const theme of data.manifest.contributes?.themes ?? []) {
    themes.push({
      extension,
      id: theme.id,
      label: localize(theme.label, data.nls),
      uiTheme: theme.uiTheme,
      path: await copyTheme(extension, theme.path),
    });
  }
}

// License: VS Code's MIT license plus the upstream notices of the grammars and
// themes (their cgmanifest.json registrations and ThirdPartyNotices.txt entries).
const vscodeLicense = await downloadText('LICENSE.txt');
const notices = (await downloadText('ThirdPartyNotices.txt'))
  .split(/\n-{57}\n\n-{57}\n/).map(section => section.replace(/^\n+|\n-{57}\n*$/g, ''));
const upstream = [];
const noticeTexts = [];
for (const { extension, cgmanifest } of components) {
  for (const registration of cgmanifest?.registrations ?? []) {
    const component = registration.component;
    const name = component.git?.name ?? component.other?.name;
    const location = component.git
      ? `${component.git.repositoryUrl} at ${component.git.commitHash}`
      : component.other?.downloadUrl;
    upstream.push(`- extensions/${extension}: ${name} ${registration.version ?? ''} (${location})` +
      (registration.license ? `, ${registration.license}` : '') +
      (registration.description ? `.\n  ${registration.description}` : '.'));
    const header = new RegExp(`^(\\S+/)?${name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')} ${registration.version}\\b`, 'm');
    const notice = notices.find(section => header.test(section.split('\n\n')[0]));
    if (!notice) throw new Error(`No ThirdPartyNotices entry for ${name} ${registration.version}`);
    if (!noticeTexts.includes(notice)) noticeTexts.push(notice);
  }
}
const license = [
  `The files in this directory were downloaded from Visual Studio Code`,
  `(https://github.com/microsoft/vscode) at revision ${revision}`,
  `by tool/generate_textmate_assets.mjs. The directory layout mirrors each`,
  `extension's: grammars/<extension>/... and themes/<extension>/... are the files of`,
  `extensions/<extension>/... Files without a separate notice below (the default`,
  `themes, the JSDoc injection grammars, language configurations) are part of`,
  `Visual Studio Code:`,
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
  'Their entries from Visual Studio Code\'s ThirdPartyNotices.txt:',
  '',
  ...noticeTexts.flatMap(notice => ['-'.repeat(57), '', notice.trim(), '']),
].join('\n');

const manifest = {
  revision,
  attribution: 'Copyright (c) Microsoft Corporation and others. See LICENSE.txt in this directory.',
  grammars,
  languages,
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
console.log(`Wrote ${files.size} files, ${grammars.length} grammars, ${languages.length} languages, ${themes.length} themes to ${output}`);
console.log('Asset directories for pubspec.yaml:');
for (const directory of directories) console.log(`    - ${posix.join(output, directory)}/`);
