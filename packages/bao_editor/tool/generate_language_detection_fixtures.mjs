// Runs the real upstream VS Code language detection code, never the Dart port,
// to create the golden data replayed by
// test/ide/editor/monaco/vs/editor/common/services/language_detection_golden_test.dart.
//
// Usage: node tool/generate_language_detection_fixtures.mjs [vscode-checkout] [output.json]
//   [vscode-checkout]  a checkout of microsoft/vscode at `revision` (default: a sparse,
//                      blob-less clone into /tmp/baocode-language-detection-vscode-<rev>)
//   [output.json]      default test/fixtures/textmate/language_detection.json; the
//                      ECMAScript lower-case table goes next to it as
//                      language_detection_lowercase.json.
//   --print-lowercase-table  also prints the run-length table used by
//                      lib/ide/editor/monaco/vs/base/common/ecmascript_lower_case.dart.
//
// What it does, at VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// 1. Bundles the unmodified languagesRegistry.ts, languagesAssociations.ts,
//    modesRegistry.ts, glob.ts, uri.ts, path.ts and their imports with esbuild
//    (the version build/package.json pins), and evaluates the bundle once per
//    platform (darwin, linux, win32). platform.ts and process.ts read
//    `globalThis.vscode.process` when they are evaluated, which selects the
//    platform exactly like a sandboxed VS Code renderer does.
// 2. Collects the `contributes.languages` of every built-in extension the
//    desktop product ships, in the order the workbench hands them to
//    `LanguagesRegistry.setDynamicLanguages`:
//    - local extensions: extensions/*/package.json minus `excludedExtensions`
//      and minus names listed in product.json `builtInExtensions`
//      (build/lib/extensions.ts `doPackageLocalExtensionsStream`), plus
//      `copilot`, which is excluded there but packaged by
//      `packageCopilotExtensionStream` (build/gulpfile.vscode.ts runs
//      `compileCopilotExtensionBuildTask` for every desktop package);
//    - product.json `builtInExtensions` (marketplace VSIXs, SHA-256 checked,
//      installed into a folder named after the extension);
//    - sorted by folder name with `<` (extensionCmp in
//      src/vs/workbench/services/extensions/common/extensionDescriptionRegistry.ts;
//      all of them are in the Builtin bucket), then in package.json order
//      (AbstractExtensionService._handleExtensionPoint);
//    - `%key%` strings replaced from package.nls.json (extension scanner), entries
//      filtered by `isValidLanguageExtensionPoint` and mapped like
//      WorkbenchLanguageService in src/vs/workbench/services/language/common/languageService.ts.
//    The core `plaintext` language comes first through ModesRegistry
//    (src/vs/editor/common/languages/modesRegistry.ts). Other workbench-core
//    ModesRegistry languages (code-text-binary, Log, log, scminput) are not part
//    of this set.
// 3. Records guessLanguageIdByFilepathOrFirstLine for a corpus of resources and
//    first lines, the name/mime/codec lookups, and a glob.match matrix.
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync } from 'node:fs';
import { mkdir, mkdtemp, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { tmpdir } from 'node:os';
import { dirname, join, posix } from 'node:path';
import { pathToFileURL } from 'node:url';
import { inflateRawSync } from 'node:zlib';

const revision = '6a598d4a13031703d483d103c1d934a36ad27971';
const repository = 'https://github.com/microsoft/vscode.git';
const platforms = ['darwin', 'linux', 'win32'];

const flags = process.argv.slice(2).filter(a => a.startsWith('--'));
const positional = process.argv.slice(2).filter(a => !a.startsWith('--'));
if (positional.length > 2 || flags.some(f => f !== '--print-lowercase-table')) {
  throw new Error('Usage: node tool/generate_language_detection_fixtures.mjs [vscode-checkout] [output.json] [--print-lowercase-table]');
}
const printLowercaseTable = flags.includes('--print-lowercase-table');
const [checkoutArg, output = 'test/fixtures/textmate/language_detection.json'] = positional;

function git(args, options = {}) {
  return execFileSync('git', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'inherit'], ...options });
}

// --- Pinned sources -------------------------------------------------------------

const sparsePaths = [
  '/src/vs/base/common/', '/src/vs/nls.ts', '/src/vs/nls.messages.ts',
  '/src/vs/editor/common/', '/src/vs/platform/registry/common/', '/src/vs/platform/instantiation/common/',
  '/src/vs/platform/configuration/common/', '/src/vs/platform/jsonschemas/common/', '/src/vs/platform/product/common/',
  '/src/vs/workbench/services/extensions/common/extensionDescriptionRegistry.ts',
  '/src/vs/workbench/services/extensions/common/abstractExtensionService.ts',
  '/src/vs/workbench/services/language/common/languageService.ts',
  '/extensions/*/package.json', '/extensions/*/package.nls.json', '/extensions/vscode-colorize-tests/test/colorize-fixtures/',
  '/build/lib/extensions.ts', '/build/gulpfile.vscode.ts', '/build/gulpfile.extensions.ts', '/build/package.json', '/product.json',
];

async function checkout() {
  const root = checkoutArg ?? join(tmpdir(), `baocode-language-detection-vscode-${revision.slice(0, 8)}`);
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

// --- Built-in extension set and order (verified against the build sources) -----

const extensionsTs = await read('build/lib/extensions.ts');
const excludedMatch = /const excludedExtensions = \[([^\]]*)\];/.exec(extensionsTs);
if (!excludedMatch) throw new Error('excludedExtensions not found in build/lib/extensions.ts');
const excludedExtensions = [...excludedMatch[1].matchAll(/'([^']+)'/g)].map(m => m[1]);
if (!/\.filter\(\(\{ name \}\) => excludedExtensions\.indexOf\(name\) === -1\)/.test(extensionsTs) ||
  !/\.filter\(\(\{ name \}\) => builtInExtensions\.every\(b => b\.name !== name\)\)/.test(extensionsTs) ||
  !/glob\.sync\('extensions\/\*\/package\.json'\)/.test(extensionsTs)) {
  throw new Error('doPackageLocalExtensionsStream no longer matches the documented rule');
}
if (!/export function packageCopilotExtensionStream\(\)[\s\S]*?path\.join\(root, 'extensions', 'copilot'\)/.test(extensionsTs)) {
  throw new Error('packageCopilotExtensionStream no longer packages extensions/copilot');
}
const gulpfileVscode = await read('build/gulpfile.vscode.ts');
if (!/compileNonNativeExtensionsBuildTask,\s*compileCopilotExtensionBuildTask,/.test(gulpfileVscode)) {
  throw new Error('build/gulpfile.vscode.ts no longer packages the copilot extension');
}
const registrySource = await read('src/vs/workbench/services/extensions/common/extensionDescriptionRegistry.ts');
if (!/const aLastSegment = path\.posix\.basename\(a\.extensionLocation\.path\);[\s\S]*?if \(aLastSegment < bLastSegment\)/.test(registrySource)) {
  throw new Error('extensionCmp no longer sorts by folder name');
}
const languageServiceSource = await read('src/vs/workbench/services/language/common/languageService.ts');
if (!/this\._registry\.setDynamicLanguages\(allValidLanguages\);/.test(languageServiceSource)) {
  throw new Error('WorkbenchLanguageService no longer calls setDynamicLanguages');
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
      const response = await fetch(url, { headers: { 'User-Agent': 'baocode-language-detection-fixtures' } });
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
    folder, source: folder === 'copilot' ? 'copilot' : 'local',
    manifest: JSON.parse(await readFile(manifestPath, 'utf8')),
    nls: existsSync(nlsPath) ? JSON.parse(await readFile(nlsPath, 'utf8')) : undefined,
  });
}
for (const extension of marketplaceBuiltIns) {
  // build/lib/extensions.ts fromGithub: the release's .vsix, checked against product.json.
  const release = `${extension.repo}/releases/download/v${extension.version}/${extension.name}.${extension.version}.vsix`;
  const vsix = await download(release);
  const sha256 = createHash('sha256').update(vsix).digest('hex');
  if (sha256 !== extension.sha256) throw new Error(`Checksum mismatch for ${release}: ${sha256}`);
  const nls = readZipEntry(vsix, 'extension/package.nls.json');
  builtIns.push({
    folder: extension.name, source: `marketplace ${extension.name}@${extension.version}`,
    manifest: JSON.parse(readZipEntry(vsix, 'extension/package.json').toString('utf8')),
    nls: nls ? JSON.parse(nls.toString('utf8')) : undefined,
  });
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

// isUndefinedOrStringArray / isValidLanguageExtensionPoint from languageService.ts.
const isUndefinedOrStringArray = value => typeof value === 'undefined' || (Array.isArray(value) && value.every(item => typeof item === 'string'));
function isValidLanguageExtensionPoint(value) {
  return !!value && typeof value.id === 'string' &&
    isUndefinedOrStringArray(value.extensions) && isUndefinedOrStringArray(value.filenames) &&
    (typeof value.firstLine === 'undefined' || typeof value.firstLine === 'string') &&
    (typeof value.configuration === 'undefined' || typeof value.configuration === 'string') &&
    isUndefinedOrStringArray(value.aliases) && isUndefinedOrStringArray(value.mimetypes) &&
    (typeof value.icon === 'undefined' || (typeof value.icon === 'object' && typeof value.icon.light === 'string' && typeof value.icon.dark === 'string'));
}

const registrations = [];
const extensionSummary = [];
for (const { folder, source, manifest, nls } of builtIns) {
  if (manifest.contributes?.configurationDefaults?.['files.associations']) {
    throw new Error(`${folder} contributes files.associations defaults; the fixture would need them`);
  }
  const languages = manifest.contributes?.languages;
  if (languages === undefined) { extensionSummary.push({ folder, source, languages: 0 }); continue; }
  if (!Array.isArray(languages)) throw new Error(`${folder}: contributes.languages is not an array`);
  let count = 0;
  for (const raw of localize(languages, nls)) {
    if (!isValidLanguageExtensionPoint(raw)) { console.warn(`Skipping invalid language in ${folder}: ${JSON.stringify(raw)}`); continue; }
    const registration = { extension: folder, id: raw.id };
    for (const key of ['extensions', 'filenames', 'filenamePatterns', 'firstLine', 'aliases', 'mimetypes']) {
      if (raw[key] !== undefined) registration[key] = raw[key];
    }
    // joinPath(extensionLocation, configuration) upstream; only its presence matters here.
    if (raw.configuration) registration.configuration = posix.join(folder, raw.configuration);
    if (raw.icon) registration.icon = { light: posix.join(folder, raw.icon.light), dark: posix.join(folder, raw.icon.dark) };
    registrations.push(registration);
    count++;
  }
  extensionSummary.push({ folder, source, languages: count });
}

// --- Bundle the upstream modules -----------------------------------------------

const temporary = await mkdtemp(join(tmpdir(), 'baocode-language-detection-'));
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
    `export { LanguagesRegistry, LanguageIdCodec } from '${vs}/editor/common/services/languagesRegistry.ts';`,
    `export { ModesRegistry, PLAINTEXT_LANGUAGE_ID } from '${vs}/editor/common/languages/modesRegistry.ts';`,
    `export { URI } from '${vs}/base/common/uri.ts';`,
    `export * as glob from '${vs}/base/common/glob.ts';`,
    `export * as platform from '${vs}/base/common/platform.ts';`,
  ].join('\n');
  const bundled = await esbuild.build({
    stdin: { contents: entry, resolveDir: vs, loader: 'ts', sourcefile: 'entry.ts' },
    bundle: true, format: 'esm', platform: 'neutral', write: false, logLevel: 'warning',
    // src/tsconfig.base.json settings that affect emitted JavaScript.
    tsconfigRaw: { compilerOptions: { experimentalDecorators: true, useDefineForClassFields: false, target: 'ES2024' } },
  });
  const bundlePath = join(temporary, 'language-detection.mjs');
  await writeFile(bundlePath, bundled.outputFiles[0].text);

  async function loadFor(platform) {
    globalThis.vscode = { process: { platform, arch: 'x64', env: {}, versions: {}, cwd: () => (platform === 'win32' ? 'C:\\' : '/') } };
    try {
      return await import(`${pathToFileURL(bundlePath).href}?platform=${platform}`);
    } finally {
      delete globalThis.vscode;
    }
  }

  // --- Corpus ---------------------------------------------------------------------

  const fixturesDir = 'extensions/vscode-colorize-tests/test/colorize-fixtures';
  const fixtureNames = (await readdir(join(root, fixturesDir))).sort();
  const firstLineOf = text => text.split(/\r\n|\r|\n/)[0];
  const fixtureFirstLines = await Promise.all(fixtureNames.map(async n => firstLineOf(await read(`${fixturesDir}/${n}`))));

  const trickyNames = [
    'Dockerfile', 'dockerfile', 'DOCKERFILE', 'Dockerfile.dev', 'Dockerfile.prod.local', 'Containerfile', 'Containerfile.build', 'app.dockerfile', 'Dockerfile-dev',
    'Makefile', 'makefile', 'GNUmakefile', 'OCamlMakefile', 'Makefile.am', 'Makefile.in', 'x.mk', 'x.mak',
    'CMakeLists.txt', 'x.cmake', '.gitignore', '.gitattributes', '.gitmodules', '.git-blame-ignore-revs', 'gitconfig', '.gitconfig',
    'x.d.ts', 'x.ts', 'x.mts', 'x.cts', 'x.d.mts', 'x.tsx', 'x.js', 'x.mjs', 'x.cjs', 'x.jsx', 'x.es6', 'jakefile', 'x.jake',
    '.env', '.env.local', '.env.production.local', '.envrc', '.flaskenv', 'x.env', 'user-dirs.dirs',
    '.bashrc', '.bash_profile', '.bash_aliases', '.zshrc', 'zshrc', '.zshenv', '.zprofile', '.profile', '.hushlogin', 'PKGBUILD', 'APKBUILD', 'x.sh', 'x.bash', 'x.zsh', 'x.fish', 'x.ksh',
    'package.json', 'package-lock.json', 'composer.lock', 'bun.lock', 'x.lock', 'tsconfig.json', 'tsconfig.base.json', 'tsconfig-app.json', 'tsconfig.app.json', 'jsconfig.json', 'jsconfig.test.json',
    'settings.json', 'launch.json', 'tasks.json', 'keybindings.json', 'extensions.json', 'mcp.json', 'argv.json', 'profiles.json', 'devcontainer.json', '.devcontainer.json',
    'x.code-workspace', 'x.code-snippets', 'x.code-profile', 'x.json', 'x.jsonc', 'x.jsonl', 'x.json5', 'x.geojson', 'x.webmanifest', 'x.har', 'x.ipynb',
    '.babelrc', '.babelrc.json', 'babel.config.json', '.eslintrc', '.eslintrc.json', '.jshintrc', '.jscsrc', '.prettierrc', '.swcrc', '.watchmanconfig', '.ember-cli', 'typedoc.json',
    'CHANGELOG.md', 'README', 'README.md', 'readme.MD', 'LICENSE', 'LICENSE.txt', 'x.txt', 'X.TXT', 'x.text', 'x.md', 'x.markdown', 'x.mdown', 'x.copilotmd',
    'FOO.JSON', 'Foo.Ts', 'A.B.C.D.TS', 'x.min.js', 'x.test.tsx', 'x.spec.ts', 'archive.tar.gz', 'x.', 'x..ts', '.ts', '.d.ts', '.txt', '.JSON', 'txt', 'ts', '.', '..', '...',
    'SKILL.md', 'skill.md', 'x.prompt.md', 'x.instructions.md', 'x.chatmode.md', 'x.agent.md', 'AGENTS.md', 'CLAUDE.md', 'copilot-instructions.md',
    '.copilotignore', '.vscodeignore', '.npmignore', '.dockerignore', '.eslintignore', '.prettierignore',
    'compose.yml', 'compose.yaml', 'compose.override.yml', 'docker-compose.yml', 'docker-compose.override.yaml', 'my-docker-compose.yml', 'x.yml', 'x.yaml', 'x.YML', '.clang-format', '.clangd',
    'Jenkinsfile', 'Jenkinsfile.prod', 'jenkinsfile', 'x.groovy', 'x.gradle', 'x.gvy', 'x.nf',
    'Gemfile', 'gemfile', 'Rakefile', 'Vagrantfile', 'Podfile', 'Brewfile', 'berksfile.lock', 'x.rb', 'x.gemspec', 'x.rake', 'x.erb',
    'SConstruct', 'SConscript', 'x.py', 'x.pyi', 'x.pyw', 'x.gyp', 'x.rpy', 'x.pyx',
    'COMMIT_EDITMSG', 'MERGE_MSG', 'git-rebase-todo', 'x.patch', 'x.diff', 'x.rej', 'x.log', 'x.csv', 'x.tsv',
    'x.svg', 'x.xml', 'x.xsd', 'x.xsl', 'x.plist', 'x.csproj', 'x.props', 'x.targets', 'x.xaml', 'x.resx', 'x.vcxproj', 'x.config', 'x.rss',
    'x.html', 'x.htm', 'x.xhtml', 'x.shtml', 'x.vue', 'x.css', 'x.scss', 'x.sass', 'x.less', 'x.styl',
    'x.rs', 'x.go', 'go.mod', 'go.sum', 'go.work', 'Cargo.toml', 'Cargo.lock', 'x.toml',
    'x.ini', 'x.cfg', 'x.conf', 'x.properties', 'x.editorconfig', '.editorconfig', 'x.sql', 'x.dsql',
    'x.ps1', 'x.psm1', 'x.psd1', 'x.bat', 'x.cmd', 'x.c', 'x.h', 'x.i', 'x.hpp', 'x.hh', 'x.cc', 'x.cpp', 'x.cxx', 'x.c++', 'x.ino', 'x.cu', 'x.cuh', 'x.m', 'x.mm',
    'x.cs', 'x.csx', 'x.cake', 'x.fs', 'x.fsx', 'x.fsi', 'x.java', 'x.jav', 'x.kt', 'x.swift', 'x.dart', 'x.lua', 'x.pl', 'x.pm', 'x.pod', 'x.t', 'x.p6', 'x.raku', 'x.rakumod',
    'x.php', 'x.phtml', 'x.ctp', 'x.tex', 'x.ltx', 'x.sty', 'x.cls', 'x.bib', 'x.bbx', 'x.r', 'x.rhistory', 'x.rprofile', 'x.jl', 'x.hbs', 'x.handlebars', 'x.pug', 'x.jade', 'x.cshtml', 'x.razor',
    'x.hlsl', 'x.hlsli', 'x.fx', 'x.shader', 'x.clj', 'x.cljs', 'x.edn', 'x.coffee', 'x.cson', 'x.vb', 'x.vbs', 'x.bas', 'x.rst', 'x.wat', 'x.wasm', 'x.code-search', 'x.mdc', 'x.lock.json', 'x.bowerrc',
  ];
  const posixDirs = ['/home/user/project/', '/Users/Me/Work Space/', ''];
  const posixPathCases = [
    ...trickyNames.flatMap(n => posixDirs.map(d => d + n)),
    '/home/user/project/.vscode/settings.json', '/home/user/project/.vscode/launch.json', '/home/user/project/.vscode/extensions.json',
    '/home/user/.config/git/config', '/home/user/project/.git/config', '/home/user/project/.git/info/exclude', '/home/user/project/.git/COMMIT_EDITMSG',
    '/home/user/project/.git/rebase-merge/done', '/home/user/project/.git/rebase-merge/git-rebase-todo', '/home/user/project/rebase-merge/done.txt',
    '/home/user/project/.github/hooks/pre-commit.json', '/home/user/project/.github/hooks/nested/x.json', '/home/user/project/.github/agents/reviewer.md', '/home/user/project/.claude/agents/x.md',
    '/home/user/project/.claude/rules/a.md', '/home/user/project/.claude/rules/a/b/c.md', '/home/user/project/.cursor/rules/x.mdc', '/home/user/project/.cursor/x.mdc', '/home/user/x.mdc',
    '/Users/me/Library/Application Support/Code/User/snippets/ts.json', '/Users/me/Library/Application Support/Code/User/profiles/abc/snippets/x.json',
    '/home/user/project/snippets.json', '/home/user/project/snippets-extra.json', '/home/user/project/my.snippets.json',
    '/home/user/project/b.ts/c', '/home/user/project/x.ts/', '/home/user/project/Dockerfile/', '/a/b/C:/x.ts', '/tmp/a#b.py', '/tmp/a%20b.py', '/tmp/a%b.json', '/tmp/a b/c d.yaml',
    '/tmp/x?.json', '/tmp/a\\b.ts', 'C:\\Users\\me\\x.ts', 'C:\\Users\\me\\.git\\config', 'relative/dir/x.py', 'relative\\dir\\Makefile',
    '/tmp/İNDEX.JS', '/tmp/FOO.İNİ', '/tmp/Ω.JSON', '/tmp/ΑΣ.md', '/tmp/ΑΣ', '/tmp/straße.TXT', '/tmp/\u212A.ts', '/tmp/x.\u212Aml', '/tmp/ﬁle.txt', '/tmp/ÉCOLE.CSS', '/tmp/日本語.md',
  ];
  const windowsPathCases = [
    'C:\\Users\\me\\project\\Dockerfile', 'C:\\Users\\me\\project\\x.TS', 'c:\\users\\me\\project\\.vscode\\settings.json', 'C:\\x\\.git\\config', 'C:\\x\\.config\\git\\config',
    'C:\\x\\.git\\rebase-merge\\done', 'C:\\x\\.github\\hooks\\a.json', 'C:\\x\\.github\\agents\\a.md', 'C:\\x\\.claude\\rules\\a\\b.md', 'C:\\x\\.cursor\\rules\\a.mdc',
    'C:\\Users\\me\\AppData\\Roaming\\Code\\User\\snippets\\ts.json', 'C:\\Users\\me\\AppData\\Roaming\\Code\\User\\profiles\\p\\snippets\\x.json',
    'D:\\a b\\c d\\README.md', 'D:\\docker-compose.yml', 'D:\\compose.yaml', 'D:\\.env.local', 'D:\\GNUmakefile', 'D:\\x.d.ts',
    '\\\\server\\share\\project\\CMakeLists.txt', '\\\\server\\share\\x.ps1', '\\\\Server\\Share\\.gitignore', '\\x\\y.py', 'x\\y\\z.rs', 'C:\\x/mixed/.git\\config', 'C:\\x\\a#b.cs', 'C:\\x\\İ.JSON',
  ];

  const unknownScript = '/home/user/project/script';
  const firstLines = [
    '#!/usr/bin/env node', '#!/usr/bin/node', '#!/usr/local/bin/nodejs --harmony', '#!/usr/bin/env -S node --experimental-strip-types', '#!/usr/bin/env nodemon',
    '#!/bin/bash', '#!/bin/sh', '#!/usr/bin/env bash', '#!/usr/bin/env zsh', '#!/usr/bin/env fish', '#!/bin/dash', '#!/bin/ksh', '#!/bin/csh -f', '#!/usr/bin/env sh -e',
    '#!/usr/bin/env python3', '#!/usr/bin/python2.7', '#! /usr/bin/env python', '#!python', '#!/usr/bin/env pypy3',
    '#!/usr/bin/env -S deno run', '#!/usr/bin/env -S deno run --allow-net', '#!/usr/bin/deno', '#!/usr/bin/env bun', '#!/usr/bin/env ts-node', '#!/usr/bin/env -S ts-node --esm',
    '#!/usr/bin/env perl', '#!/usr/bin/perl -w', '#!/usr/bin/env perl6', '#!/usr/bin/env raku', 'use v6;', 'my class Foo {}', '=begin pod', 'raku', 'this line mentions raku',
    '#!/usr/bin/env ruby', '#!/usr/bin/ruby', '#!/usr/bin/env php', '#!/usr/bin/php', '<?php', '<?php echo 1;',
    '<?xml version="1.0" encoding="UTF-8"?>', '<?xml', '<svg xmlns="http://www.w3.org/2000/svg">', '<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN">', '<!doctype svg>', '<!DOCTYPE html>', '<html>',
    '---', '--- ', '#cloud-config', '#cloud-config ', '#!/usr/bin/make -f', '#!/usr/bin/env make', '#!/usr/bin/env pwsh', '#!/usr/bin/pwsh -NoProfile', '#!/usr/bin/env groovy',
    '#!/usr/bin/env julia', '#!/usr/local/bin/julia1.9', '(module', '(module $m', '# -*- mode: shell-script -*-', '# -*- coding: utf-8; mode: shell-script -*-',
    '\uFEFF#!/bin/bash', '\uFEFF<?xml version="1.0"?>', '\uFEFF', ' #!/bin/bash', '#!/usr/bin/env python3 # bash', '#!/usr/bin/env bash # node', '{', '{"a": 1}', 'hello world', '\t', '#', '#!',
  ];

  const cases = [];
  const add = (uri, firstLine, platformsFor) => {
    const c = { uri };
    if (firstLine !== undefined) c.firstLine = firstLine;
    if (platformsFor) c.platforms = platformsFor;
    cases.push(c);
  };
  // Characters Windows file names cannot hold (Dart's Uri.file(windows: true) rejects them).
  const invalidOnWindows = p => /[<>"|?*]/.test(p) || p.slice(/^[A-Za-z]:/.test(p) ? 2 : 0).includes(':');
  for (const [i, name] of fixtureNames.entries()) {
    add({ file: `/work/colorize-fixtures/${name}` });
    add({ file: `/work/colorize-fixtures/${name}` }, fixtureFirstLines[i]);
    add({ file: unknownScript }, fixtureFirstLines[i]);
  }
  for (const p of posixPathCases) add({ file: p }, undefined, invalidOnWindows(p) ? ['darwin', 'linux'] : undefined);
  for (const p of windowsPathCases) add({ file: p });
  for (const line of firstLines) {
    add({ file: unknownScript }, line);
    add({ file: '/home/user/project/x.unknownext' }, line);
  }
  for (const [file, line] of [['/p/x.ts', '#!/bin/bash'], ['/p/x.py', '<?xml version="1.0"?>'], ['/p/Dockerfile', '#!/usr/bin/env node'], ['/p/x.txt', '#!/bin/bash'], ['/p/x.md', '---'], ['/p/README', '#!/usr/bin/env python3']]) {
    add({ file }, line);
  }
  for (const line of ['#!/bin/bash', '<?php', '']) add(null, line);
  add(null);
  for (const uri of ['untitled:Untitled-1', 'untitled:foo.py', 'untitled:/home/u/Dockerfile', 'https://example.com/a/B.TS?x=1#y', 'http://example.com/Makefile',
    'vscode-remote://ssh-remote%2Bhost/home/u/Dockerfile', 'vscode-userdata:/Users/u/Library/Application%20Support/Code/User/settings.json',
    'vscode-notebook-cell:/a/b.ipynb#W0sZmlsZQ%3D%3D', 'git:/repo/a.ts?%7B%7D', 'vscode-vfs://github/microsoft/vscode/.github/hooks/x.json', 'inmemory://model/1', 'output:extension-output-1', 'file:///C:/Users/me/x.ts', 'file://server/share/x.yml']) {
    add({ parse: uri });
    add({ parse: uri }, '#!/bin/bash');
  }
  for (const path of [';label:something.data;description:data,', 'text/plain;label:foo.ts;description:x,abc', ';label:Dockerfile;size:10;base64,AAAA', ';description:x;label:script,', 'image/png;base64,AAAA']) {
    add({ components: { scheme: 'data', path } });
    add({ components: { scheme: 'data', path } }, '#!/bin/bash');
  }

  const globPatterns = [...new Set([
    ...registrations.flatMap(r => r.filenamePatterns ?? []),
    '**/*.js', '**/*.JS', '*.js', '**/foo.js', '**/package.json', '{**/*.d.ts,**/*.js}', '{**/package.json,**/project.json}', '**/node_modules/**', 'test/**', '**/.*',
    'node_modules', 'test/**/*.js', '**/foo/bar', 'foo/bar', '*.{html,js}', 'foo.[0-9]', 'foo.[!0-9]', 'foo.[]-]', '**/*(.js', '?', '*', '**', 'some/*/Random/*/Path.FILE',
    '{**/BAR,**/BAZ}', 'PATH/FOO.js', 'C:/DNXConsoleApp/**/*.cs', ' **/*.ts ', '**/x/**/*.md', '**/*.{md,mdc}',
  ])];
  const globPaths = [
    'foo.js', 'FOO.JS', '/foo.js', 'folder/foo.js', 'folder\\foo.js', 'C:\\folder\\foo.js', 'foo.d.ts', 'package.json', '/a/package.json', 'node_modules', '/a/node_modules/b', 'test', 'test/x/y.js',
    '.git', '/a/.git', 'foo.5', 'foo.f', 'foo.]', 'foo.-', 'h', 'html.js', '', 'some/very/random/unusual/path.file', 'bar', 'BAR', 'path/foo.js', 'C:\\DNXConsoleApp\\foo\\Program.cs',
    'dockerfile.dev', 'Dockerfile.dev', 'containerfile.x', '.env.local', 'jenkinsfile2', 'compose.yml', 'my-docker-compose.yml', 'tsconfig.app.json', '.copilotignore',
    '/p/.github/hooks/a.json', '\\p\\.github\\hooks\\a.json', '/p/user/snippets/a.json', '/p/user/profiles/x/snippets/a.json', 'snippets.json', '/p/.cursor/a/b.mdc', '/p/.claude/rules/a/b.md',
    '/p/.github/agents/a.md', '/p/.claude/agents/a.md', '/p/.config/git/config', 'c:\\p\\.git\\config', '/p/rebase-merge/done', 'x.ts', '/x/y/z.md',
  ];

  const lookupsFor = registry => {
    const ids = registry.getRegisteredLanguageIds();
    const aliases = [...new Set(registrations.flatMap(r => r.aliases ?? []).concat(ids, 'Plain Text', 'text'))];
    const names = [...new Set(aliases.flatMap(a => [a, a.toLowerCase(), a.toUpperCase(), ` ${a}`]).concat(
      '', 'nonexistent', 'constructor', '__proto__', 'hasOwnProperty', 'toString', 'İNI', 'ınİ', 'JSON with Comments', 'c++', 'C#', 'F#', 'shell script', 'Shell Script'))];
    const mimes = [...new Set(ids.map(id => registry.getMimeType(id)).concat(registrations.flatMap(r => r.mimetypes ?? []), ids.map(id => `text/x-${id}`),
      'text/plain', 'TEXT/PLAIN', 'text/unknown', '', 'application/json', 'text/x-code-binary', 'text/x-code-output'))];
    const codec = registry.languageIdCodec;
    return {
      registeredLanguageIds: ids,
      sortedLanguageNames: registry.getSortedRegisteredLanguageNames().map(p => [p.languageName, p.languageId]),
      languages: Object.fromEntries(ids.map(id => [id, {
        name: registry.getLanguageName(id), mimeType: registry.getMimeType(id), extensions: registry.getExtensions(id),
        filenames: registry.getFilenames(id), configurationFiles: registry.getConfigurationFiles(id).length, encoded: codec.encodeLanguageId(id),
      }])),
      languageName: [...ids, 'unknown', 'Plain Text', ''].map(id => [id, registry.getLanguageName(id)]),
      languageIdByName: names.map(n => [n, registry.getLanguageIdByLanguageName(n)]),
      languageIdByMime: mimes.map(mime => [mime, registry.getLanguageIdByMimeType(mime)]),
      encode: [...ids, 'unknown', 'vs.editor.nullLanguage', '', 'Plaintext'].map(id => [id, codec.encodeLanguageId(id)]),
      decode: Array.from({ length: ids.length + 4 }, (_, i) => i - 1).map(i => [i, codec.decodeLanguageId(i)]),
      isRegistered: [...ids, 'unknown', '', 'Plaintext', 'constructor'].map(id => [id, registry.isRegisteredLanguageId(id)]),
    };
  };

  const results = {};
  let sharedLookups;
  for (const platform of platforms) {
    const m = await loadFor(platform);
    if (m.platform.isWindows !== (platform === 'win32') || m.platform.isLinux !== (platform === 'linux') || m.platform.isMacintosh !== (platform === 'darwin')) {
      throw new Error(`Platform override failed for ${platform}`);
    }
    if (m.ModesRegistry.getLanguages().map(l => l.id).join() !== 'plaintext') throw new Error('Unexpected core ModesRegistry languages');
    const registry = new m.LanguagesRegistry(true, false);
    registry.setDynamicLanguages(registrations.map(r => ({
      id: r.id, extensions: r.extensions, filenames: r.filenames, filenamePatterns: r.filenamePatterns, firstLine: r.firstLine,
      aliases: r.aliases, mimetypes: r.mimetypes,
      configuration: r.configuration === undefined ? undefined : m.URI.file(`/vscode/extensions/${r.configuration}`),
      icon: r.icon && { light: m.URI.file(`/vscode/extensions/${r.icon.light}`), dark: m.URI.file(`/vscode/extensions/${r.icon.dark}`) },
    })));
    const toUri = uri => uri === null ? null : uri.file !== undefined ? m.URI.file(uri.file) : uri.parse !== undefined ? m.URI.parse(uri.parse) : m.URI.from(uri.components);
    const guesses = [];
    for (const [index, c] of cases.entries()) {
      if (c.platforms && !c.platforms.includes(platform)) continue;
      guesses.push([index, registry.guessLanguageIdByFilepathOrFirstLine(toUri(c.uri), c.firstLine)]);
    }
    const lookups = lookupsFor(registry);
    if (sharedLookups === undefined) sharedLookups = lookups;
    else if (JSON.stringify(lookups) !== JSON.stringify(sharedLookups)) throw new Error(`Lookups differ on ${platform}`);
    const glob = {};
    for (const ignoreCase of [false, true]) {
      glob[ignoreCase ? 'ignoreCase' : 'caseSensitive'] = globPatterns.map(p => globPaths.map(path => m.glob.match(p, path, { ignoreCase }) ? '1' : '0').join(''));
    }
    results[platform] = { guesses, glob };
    registry.dispose();
  }

  // --- ECMAScript String.prototype.toLowerCase of every code point that changes ---
  const lowercase = [];
  for (let c = 0; c <= 0x10FFFF; c++) {
    if (c >= 0xD800 && c <= 0xDFFF) continue;
    const s = String.fromCodePoint(c);
    const lower = s.toLowerCase();
    if (lower !== s) lowercase.push([c, [...lower].map(ch => ch.codePointAt(0))]);
  }
  if (printLowercaseTable) {
    // Runs of [start, count, step, delta] for single code point mappings above ASCII.
    const runs = [];
    for (const [c, mapped] of lowercase) {
      if (c < 0x80 || mapped.length !== 1) continue;
      const delta = mapped[0] - c, last = runs[runs.length - 1];
      if (last && last.delta === delta && (last.count === 1 ? (c - last.end === 1 || c - last.end === 2) : c - last.end === last.step)) {
        if (last.count === 1) last.step = c - last.end;
        last.count++; last.end = c; continue;
      }
      runs.push({ start: c, count: 1, step: 1, delta, end: c });
    }
    console.log(runs.map(r => `0x${r.start.toString(16)}, ${r.count}, ${r.step}, ${r.delta},`).join('\n'));
  }

  const fixture = {
    revision,
    generator: 'tool/generate_language_detection_fixtures.mjs',
    node: process.version,
    esbuild: esbuildVersion,
    rules: {
      extensions: 'extensions/*/package.json minus build/lib/extensions.ts excludedExtensions and product.json builtInExtensions names, plus copilot (packageCopilotExtensionStream), plus product.json builtInExtensions (VSIX, folder = name)',
      order: 'plaintext (ModesRegistry), then extensions sorted by folder name with < (extensionCmp), then contributes.languages order',
      excludedExtensions,
    },
    extensions: extensionSummary,
    registrations,
    cases,
    lookups: sharedLookups,
    globPatterns,
    globPaths,
    platforms: results,
  };
  // Pretty-printed, but values that fit on a line stay on one line.
  const format = (value, indent = '') => {
    const inline = JSON.stringify(value);
    if (value === null || typeof value !== 'object' || inline.length <= 160) return inline;
    const next = `${indent} `;
    if (Array.isArray(value)) return `[\n${value.map(v => next + format(v, next)).join(',\n')}\n${indent}]`;
    return `{\n${Object.entries(value).map(([k, v]) => `${next}${JSON.stringify(k)}: ${format(v, next)}`).join(',\n')}\n${indent}}`;
  };
  await mkdir(dirname(output), { recursive: true });
  await writeFile(output, `${format(fixture)}\n`);
  const lowercaseOutput = join(dirname(output), 'language_detection_lowercase.json');
  await writeFile(lowercaseOutput, `${JSON.stringify({ node: process.version, unicode: process.versions.unicode, icu: process.versions.icu, mappings: lowercase })}\n`);
  const counts = platforms.map(p => `${p}: ${results[p].guesses.length}`).join(', ');
  console.log(`Wrote ${output} (${registrations.length} registrations from ${extensionSummary.length} extensions; guesses ${counts}) and ${lowercaseOutput}`);
} finally {
  await rm(temporary, { recursive: true, force: true });
}
