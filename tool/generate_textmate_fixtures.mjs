// Runs the real upstream vscode-textmate and vscode-oniguruma, never the Dart port,
// set up exactly as VS Code does, to create TextMate tokenization parity data.
// Usage: node --experimental-transform-types tool/generate_textmate_fixtures.mjs [assets-dir] [fixtures-dir]
// (defaults: assets/textmate, written by tool/generate_textmate_assets.mjs, and test/fixtures/textmate)
//
// Everything below mirrors VS Code 6a598d4a13031703d483d103c1d934a36ad27971; each
// piece names the upstream file it reproduces. Upstream json.ts, color.ts,
// plistParser.ts and TMHelper.ts are downloaded and imported unchanged (import paths
// aside).
//
// Writes, under the fixtures directory:
// - samples/: every extensions/vscode-colorize-tests/test/colorize-fixtures file
//   (a `.dart` sample gets a `.txt` suffix so the analyzer leaves it alone) and
//   samples/bench/textModel.ts; the hand-written extra/ samples, for the languages
//   with a grammar but no colorize fixture, are read in place;
// - themes/<id>.json: each bundled theme's IRawTheme and token color map;
// - tokens.json.gz: per sample, the language VS Code tokenizes it as, its scopes
//   (`tokenizeLine`) and, in every bundled theme, the editor's binary tokens
//   (`tokenizeLine2` in the editor's per-line loop); each theme's color map; a
//   benchmark file's tokens; and the result of cross-checking every sample against
//   VS Code's colorize-results (scopes, and every listed theme's color explanation).
import { execFileSync } from 'node:child_process';
import { mkdir, mkdtemp, readdir, readFile, rm, writeFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { tmpdir } from 'node:os';
import { join, posix } from 'node:path';
import { pathToFileURL } from 'node:url';
import { gzipSync } from 'node:zlib';

const revision = '6a598d4a13031703d483d103c1d934a36ad27971';
// VS Code's package-lock.json at `revision` locks these.
const textmateVersion = '9.3.2';
const onigurumaVersion = '1.7.0';
const source = `https://raw.githubusercontent.com/microsoft/vscode/${revision}/`;
const colorizeTests = 'extensions/vscode-colorize-tests/test/';
const listing = `https://api.github.com/repos/microsoft/vscode/contents/${colorizeTests}colorize-fixtures?ref=${revision}`;
const benchPath = 'src/vs/editor/common/model/textModel.ts';
const benchTheme = 'Dark+';
const [assets = 'assets/textmate', fixtures = 'test/fixtures/textmate'] = process.argv.slice(2);
if (process.argv.length > 4) throw new Error('Usage: node --experimental-transform-types tool/generate_textmate_fixtures.mjs [assets-dir] [fixtures-dir]');

async function download(path) {
  for (let attempt = 1; ; attempt++) {
    try {
      const response = await fetch(path.startsWith('https:') ? path : source + path, { headers: { 'User-Agent': 'monad-textmate-fixtures' } });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      return Buffer.from(await response.arrayBuffer());
    } catch (error) {
      if (attempt >= 4) throw new Error(`Cannot download ${path}: ${error.message}`);
      await new Promise(resolve => setTimeout(resolve, 500 * attempt));
    }
  }
}

const temporary = await mkdtemp(join(tmpdir(), 'monad-textmate-fixtures-'));
try {
  // --- Pinned engine, installed outside the repository ---
  await writeFile(join(temporary, 'package.json'), '{"private":true,"type":"module"}');
  execFileSync('npm', ['install', '--no-audit', '--no-fund', '--ignore-scripts', '--no-package-lock',
    `vscode-textmate@${textmateVersion}`, `vscode-oniguruma@${onigurumaVersion}`], { cwd: temporary, stdio: 'inherit' });
  const require = createRequire(join(temporary, 'package.json'));
  for (const [name, version] of [['vscode-textmate', textmateVersion], ['vscode-oniguruma', onigurumaVersion]]) {
    const installed = require(`${name}/package.json`).version;
    if (installed !== version) throw new Error(`Expected ${name}@${version}, installed ${installed}`);
  }
  const vsctm = require('vscode-textmate');
  const oniguruma = require('vscode-oniguruma');
  const wasm = await readFile(require.resolve('vscode-oniguruma/release/onig.wasm'));
  await oniguruma.loadWASM(wasm.buffer.slice(wasm.byteOffset, wasm.byteOffset + wasm.byteLength));

  // --- Upstream modules the theme code and the colorize check use ---
  const upstream = {
    'json.ts': 'src/vs/base/common/json.ts',
    'charCode.ts': 'src/vs/base/common/charCode.ts',
    'color.ts': 'src/vs/base/common/color.ts',
    'plistParser.ts': 'src/vs/workbench/services/themes/common/plistParser.ts',
    'TMHelper.ts': 'src/vs/workbench/services/textMate/common/TMHelper.ts',
  };
  for (const [name, path] of Object.entries(upstream)) {
    // Node's TypeScript loader needs real .ts import extensions; no logic changes.
    const text = (await download(path)).toString('utf8').replace("from './charCode.js'", "from './charCode.ts'");
    await writeFile(join(temporary, name), text);
  }
  const load = name => import(pathToFileURL(join(temporary, name)).href).catch(error => {
    throw new Error(`Cannot load upstream ${name} (run node with --experimental-transform-types): ${error.message}`);
  });
  const Json = await load('json.ts');
  const { Color } = await load('color.ts');
  const plist = await load('plistParser.ts');
  const { findMatchingThemeRule } = await load('TMHelper.ts');

  const manifest = JSON.parse(await readFile(join(assets, 'manifest.json'), 'utf8'));
  if (manifest.revision !== revision) throw new Error(`${assets} is from ${manifest.revision}; run tool/generate_textmate_assets.mjs`);
  const readAsset = path => readFile(join(assets, path), 'utf8');

  // --- Language ids ---
  // LanguageIdCodec (src/vs/editor/common/services/languagesRegistry.ts) reserves 0 for
  // the null language and 1 for plaintext, then numbers each language the first time
  // `_registerLanguage` sees it: the manifest's registration order (plaintext first).
  const languageIds = {};
  for (const language of manifest.languages) languageIds[language.id] ??= Object.keys(languageIds).length + 1;
  if (languageIds.plaintext !== 1) throw new Error('The manifest does not register plaintext first');
  const isRegisteredLanguageId = id => Object.hasOwn(languageIds, id);

  // --- Grammar definitions ---
  // textMateTokenizationFeatureImpl.ts `validateGrammarExtensionPoint` and
  // `_validateGrammarDefinition`, applied to the package.json contributions in
  // registration order (`_handleGrammarsExtPoint`).
  const StandardTokenType = { Other: 0, Comment: 1, String: 2, RegEx: 3 }; // encodedTokenAttributes.ts
  const isObject = value => typeof value === 'object' && value !== null && !Array.isArray(value) && !(value instanceof RegExp) && !(value instanceof Date); // types.ts
  function asStringArray(array, defaultValue) {
    if (!Array.isArray(array)) return defaultValue;
    if (!array.every(e => typeof e === 'string')) return defaultValue;
    return array;
  }
  const rejectedGrammars = [];
  function validateGrammarExtensionPoint(syntax) {
    if (syntax.language && ((typeof syntax.language !== 'string') || !isRegisteredLanguageId(syntax.language))) return false;
    if (!syntax.scopeName || (typeof syntax.scopeName !== 'string')) return false;
    if (!syntax.path || (typeof syntax.path !== 'string')) return false;
    if (syntax.injectTo && (!Array.isArray(syntax.injectTo) || syntax.injectTo.some(scope => typeof scope !== 'string'))) return false;
    if (syntax.embeddedLanguages && !isObject(syntax.embeddedLanguages)) return false;
    if (syntax.tokenTypes && !isObject(syntax.tokenTypes)) return false;
    return true;
  }
  const grammarDefinitions = [];
  for (const grammar of manifest.grammars) {
    if (!validateGrammarExtensionPoint(grammar)) {
      rejectedGrammars.push(`${grammar.extension}: ${grammar.scopeName}`);
      continue;
    }
    const embeddedLanguages = Object.create(null);
    if (grammar.embeddedLanguages) {
      for (const scope of Object.keys(grammar.embeddedLanguages)) {
        const language = grammar.embeddedLanguages[scope];
        if (typeof language !== 'string') continue;
        if (isRegisteredLanguageId(language)) embeddedLanguages[scope] = languageIds[language];
      }
    }
    const tokenTypes = Object.create(null);
    if (grammar.tokenTypes) {
      for (const scope of Object.keys(grammar.tokenTypes)) {
        switch (grammar.tokenTypes[scope]) {
          case 'string': tokenTypes[scope] = StandardTokenType.String; break;
          case 'other': tokenTypes[scope] = StandardTokenType.Other; break;
          case 'comment': tokenTypes[scope] = StandardTokenType.Comment; break;
          case 'regex': tokenTypes[scope] = StandardTokenType.RegEx; break;
        }
      }
    }
    grammarDefinitions.push({
      extension: grammar.extension,
      location: grammar.path,
      language: grammar.language && isRegisteredLanguageId(grammar.language) ? grammar.language : undefined,
      scopeName: grammar.scopeName,
      embeddedLanguages,
      tokenTypes,
      injectTo: grammar.injectTo,
      balancedBracketSelectors: asStringArray(grammar.balancedBracketScopes, ['*']),
      unbalancedBracketSelectors: asStringArray(grammar.unbalancedBracketScopes, []),
    });
  }

  // The asset generator minifies JSON grammars as VS Code's build does; vscode-textmate
  // must read the bundled file exactly as the repository's (same values, same key order).
  const grammarPrefix = /^grammars\/([^/]+)\/(.*)$/;
  for (const grammar of manifest.grammars) {
    const [, extension, path] = grammarPrefix.exec(grammar.path);
    const original = (await download(`extensions/${extension}/${path}`)).toString('utf8');
    const bundled = await readAsset(grammar.path);
    const same = posix.extname(path) === '.json'
      ? JSON.stringify(vsctm.parseRawGrammar(original, path)) === JSON.stringify(vsctm.parseRawGrammar(bundled, path))
      : original === bundled;
    if (!same) throw new Error(`${grammar.path} does not read as extensions/${extension}/${path}`);
  }

  // --- TMGrammarFactory (src/vs/workbench/services/textMate/common/TMGrammarFactory.ts) ---
  const scopeRegistry = Object.create(null); // TMScopeRegistry.ts
  const injections = {};
  const injectedEmbeddedLanguages = {};
  const languageToScope = new Map();
  const grammarRegistry = new vsctm.Registry({
    onigLib: Promise.resolve({
      createOnigScanner: sources => oniguruma.createOnigScanner(sources),
      createOnigString: str => oniguruma.createOnigString(str),
    }),
    loadGrammar: async scopeName => {
      const grammarDefinition = scopeRegistry[scopeName];
      if (!grammarDefinition) return null;
      return vsctm.parseRawGrammar(await readAsset(grammarDefinition.location), grammarDefinition.location);
    },
    getInjections: scopeName => {
      const scopeParts = scopeName.split('.');
      let result = [];
      for (let i = 1; i <= scopeParts.length; i++) {
        const subScopeName = scopeParts.slice(0, i).join('.');
        result = [...result, ...(injections[subScopeName] || [])];
      }
      return result;
    },
  });
  for (const validGrammar of grammarDefinitions) {
    scopeRegistry[validGrammar.scopeName] = validGrammar;
    if (validGrammar.injectTo) {
      for (const injectScope of validGrammar.injectTo) (injections[injectScope] ??= []).push(validGrammar.scopeName);
      if (validGrammar.embeddedLanguages) {
        for (const injectScope of validGrammar.injectTo) (injectedEmbeddedLanguages[injectScope] ??= []).push(validGrammar.embeddedLanguages);
      }
    }
    if (validGrammar.language) languageToScope.set(validGrammar.language, validGrammar.scopeName);
  }
  async function createGrammar(languageId, encodedLanguageId) {
    const scopeName = languageToScope.get(languageId);
    const grammarDefinition = scopeRegistry[scopeName];
    const embeddedLanguages = grammarDefinition.embeddedLanguages;
    for (const injected of injectedEmbeddedLanguages[scopeName] ?? []) {
      for (const scope of Object.keys(injected)) embeddedLanguages[scope] = injected[scope];
    }
    return grammarRegistry.loadGrammarWithConfiguration(scopeName, encodedLanguageId, {
      embeddedLanguages,
      tokenTypes: grammarDefinition.tokenTypes,
      balancedBracketSelectors: grammarDefinition.balancedBracketSelectors,
      unbalancedBracketSelectors: grammarDefinition.unbalancedBracketSelectors,
    });
  }
  // vscode-textmate keeps one grammar per scope name, created with the language id of
  // the first request: which language asks first decides the other's tokens (ini and
  // properties share source.ini). The fixture records the order.
  const grammars = new Map();
  const grammarOrder = [];
  const grammarFor = async languageId => {
    if (!grammars.has(languageId)) {
      grammarOrder.push(languageId);
      grammars.set(languageId, await createGrammar(languageId, languageIds[languageId]));
    }
    return grammars.get(languageId);
  };

  // --- Color themes: src/vs/workbench/services/themes/common/colorThemeData.ts ---
  const DEFAULT_COLOR_CONFIG_VALUE = 'default'; // platform/theme/common/colorUtils.ts
  // themeCompatibility.ts: global tmTheme settings -> color ids.
  const settingToColorIdMapping = {};
  const addSettingMapping = (settingId, colorId) => (settingToColorIdMapping[settingId] ??= []).push(colorId);
  addSettingMapping('background', 'editor.background');
  addSettingMapping('foreground', 'editor.foreground');
  addSettingMapping('selection', 'editor.selectionBackground');
  addSettingMapping('inactiveSelection', 'editor.inactiveSelectionBackground');
  addSettingMapping('selectionHighlightColor', 'editor.selectionHighlightBackground');
  addSettingMapping('findMatchHighlight', 'editor.findMatchHighlightBackground');
  addSettingMapping('currentFindMatchHighlight', 'editor.findMatchBackground');
  addSettingMapping('hoverHighlight', 'editor.hoverHighlightBackground');
  addSettingMapping('wordHighlight', 'editor.wordHighlightBackground');
  addSettingMapping('wordHighlightStrong', 'editor.wordHighlightStrongBackground');
  addSettingMapping('findRangeHighlight', 'editor.findRangeHighlightBackground');
  addSettingMapping('findMatchHighlight', 'peekViewResult.matchHighlightBackground');
  addSettingMapping('referenceHighlight', 'peekViewEditor.matchHighlightBackground');
  addSettingMapping('lineHighlight', 'editor.lineHighlightBackground');
  addSettingMapping('rangeHighlight', 'editor.rangeHighlightBackground');
  addSettingMapping('caret', 'editorCursor.foreground');
  addSettingMapping('invisibles', 'editorWhitespace.foreground');
  addSettingMapping('guide', 'editorIndentGuide.background1');
  addSettingMapping('activeGuide', 'editorIndentGuide.activeBackground1');
  for (const color of ['ansiBlack', 'ansiRed', 'ansiGreen', 'ansiYellow', 'ansiBlue', 'ansiMagenta', 'ansiCyan', 'ansiWhite',
    'ansiBrightBlack', 'ansiBrightRed', 'ansiBrightGreen', 'ansiBrightYellow', 'ansiBrightBlue', 'ansiBrightMagenta', 'ansiBrightCyan', 'ansiBrightWhite']) {
    addSettingMapping(color, 'terminal.' + color);
  }
  function convertSettings(oldSettings, result) { // themeCompatibility.ts `convertSettings`
    for (const rule of oldSettings) {
      result.textMateRules.push(rule);
      if (!rule.scope) {
        const settings = rule.settings;
        if (!settings) {
          rule.settings = {};
        } else {
          for (const key in settings) {
            const mappings = settingToColorIdMapping[key];
            if (mappings) {
              const colorHex = settings[key];
              if (typeof colorHex === 'string') {
                const color = Color.fromHex(colorHex);
                for (const colorId of mappings) result.colors[colorId] = color;
              }
            }
            if (key !== 'foreground' && key !== 'background' && key !== 'fontStyle') delete settings[key];
          }
        }
      }
    }
  }
  const isString = value => typeof value === 'string';
  const isBoolean = value => value === true || value === false;
  function readSemanticTokenRule(selectorString, settings) { // `readSemanticTokenRule`
    // TokenClassificationRegistry.parseTokenSelector never throws; the fixtures only
    // need the rule's style (tokenClassificationRegistry.ts TokenStyle.fromSettings).
    let foreground;
    if (typeof settings === 'string') {
      foreground = Color.fromHex(settings);
    } else if (settings && (isString(settings.foreground) || isString(settings.fontStyle) || isBoolean(settings.italic)
      || isBoolean(settings.underline) || isBoolean(settings.strikethrough) || isBoolean(settings.bold))) {
      foreground = settings.foreground !== undefined ? Color.fromHex(settings.foreground) : undefined;
    } else {
      return undefined;
    }
    return { selector: selectorString, style: { foreground } };
  }
  async function loadSyntaxTokens(location, result) { // `_loadSyntaxTokens`
    const contentValue = plist.parse(await readAsset(location));
    const settings = contentValue.settings;
    if (!Array.isArray(settings)) throw new Error(`Problem parsing tmTheme file: ${location}. 'settings' is not array.`);
    convertSettings(settings, result);
  }
  async function loadColorTheme(location, result) { // `_loadColorTheme`
    if (posix.extname(location) !== '.json') return loadSyntaxTokens(location, result);
    const errors = [];
    const contentValue = Json.parse(await readAsset(location), errors);
    if (errors.length > 0) throw new Error(`Problems parsing JSON theme file ${location}: ${JSON.stringify(errors)}`);
    if (Json.getNodeType(contentValue) !== 'object') throw new Error(`Invalid format for JSON theme file ${location}: Object expected.`);
    if (contentValue.include) await loadColorTheme(posix.join(posix.dirname(location), contentValue.include), result);
    if (Array.isArray(contentValue.settings)) {
      convertSettings(contentValue.settings, result);
      return;
    }
    result.semanticHighlighting = result.semanticHighlighting || contentValue.semanticHighlighting;
    const colors = contentValue.colors;
    if (colors) {
      if (typeof colors !== 'object') throw new Error(`Problem parsing color theme file: ${location}. Property 'colors' is not of type 'object'.`);
      for (const colorId in colors) {
        const colorVal = colors[colorId];
        if (colorVal === DEFAULT_COLOR_CONFIG_VALUE) delete result.colors[colorId];
        else if (typeof colorVal === 'string') result.colors[colorId] = Color.fromHex(colors[colorId]);
      }
    }
    const tokenColors = contentValue.tokenColors;
    if (tokenColors) {
      if (Array.isArray(tokenColors)) result.textMateRules.push(...tokenColors);
      else if (typeof tokenColors === 'string') await loadSyntaxTokens(posix.join(posix.dirname(location), tokenColors), result);
      else throw new Error(`Problem parsing color theme file: ${location}. Property 'tokenColors' should be either an array specifying colors or a path to a TextMate theme file`);
    }
    const semanticTokenColors = contentValue.semanticTokenColors;
    if (semanticTokenColors && typeof semanticTokenColors === 'object') {
      for (const key in semanticTokenColors) {
        const rule = readSemanticTokenRule(key, semanticTokenColors[key]);
        if (rule) result.semanticTokenRules.push(rule);
      }
    }
  }
  function normalizeColor(color) { // `normalizeColor`
    if (!color) return undefined;
    if (typeof color !== 'string') color = Color.Format.CSS.formatHexA(color, true);
    const len = color.length;
    if (color.charCodeAt(0) !== 0x23 || (len !== 4 && len !== 5 && len !== 7 && len !== 9)) return undefined;
    const result = [0x23];
    for (let i = 1; i < len; i++) {
      const upper = hexUpper(color.charCodeAt(i));
      if (!upper) return undefined;
      result.push(upper);
      if (len === 4 || len === 5) result.push(upper);
    }
    if (result.length === 9 && result[7] === 0x46 && result[8] === 0x46) result.length = 7;
    return String.fromCharCode(...result);
  }
  function hexUpper(charCode) {
    if (charCode >= 0x30 && charCode <= 0x39 || charCode >= 0x41 && charCode <= 0x46) return charCode;
    if (charCode >= 0x61 && charCode <= 0x66) return charCode - 0x61 + 0x41;
    return 0;
  }
  const defaultThemeColors = { // `defaultThemeColors`
    light: [
      { scope: 'token.info-token', settings: { foreground: '#316bcd' } },
      { scope: 'token.warn-token', settings: { foreground: '#cd9731' } },
      { scope: 'token.error-token', settings: { foreground: '#cd3131' } },
      { scope: 'token.debug-token', settings: { foreground: '#800080' } },
    ],
    dark: [
      { scope: 'token.info-token', settings: { foreground: '#6796e6' } },
      { scope: 'token.warn-token', settings: { foreground: '#cd9731' } },
      { scope: 'token.error-token', settings: { foreground: '#f44747' } },
      { scope: 'token.debug-token', settings: { foreground: '#b267e6' } },
    ],
    hcLight: [
      { scope: 'token.info-token', settings: { foreground: '#316bcd' } },
      { scope: 'token.warn-token', settings: { foreground: '#cd9731' } },
      { scope: 'token.error-token', settings: { foreground: '#cd3131' } },
      { scope: 'token.debug-token', settings: { foreground: '#800080' } },
    ],
    hcDark: [
      { scope: 'token.info-token', settings: { foreground: '#6796e6' } },
      { scope: 'token.warn-token', settings: { foreground: '#008000' } },
      { scope: 'token.error-token', settings: { foreground: '#FF0000' } },
      { scope: 'token.debug-token', settings: { foreground: '#b267e6' } },
    ],
  };
  // Registry defaults of the colors `tokenColors` reads: editorColors.ts, baseColors.ts;
  // resolved as colorUtils.ts `resolveDefaultColor` and `resolveColorValue` do.
  const colorDefaults = {
    'editor.background': { light: '#ffffff', dark: '#1E1E1E', hcDark: Color.black, hcLight: Color.white },
    'editor.foreground': { light: '#333333', dark: '#BBBBBB', hcDark: Color.white, hcLight: 'foreground' },
    foreground: { dark: '#CCCCCC', light: '#616161', hcDark: '#FFFFFF', hcLight: '#292929' },
  };
  function getColor(theme, colorId) { // `getColor` without customizations or transient colors
    const color = theme.colors[colorId];
    if (color !== undefined) return color;
    const colorValue = colorDefaults[colorId][theme.type];
    if (colorValue instanceof Color) return colorValue;
    return colorValue[0] === '#' ? Color.fromHex(colorValue) : getColor(theme, colorValue);
  }
  function tokenColors(theme) { // `get tokenColors` (no user customizations)
    const result = [];
    const foreground = getColor(theme, 'editor.foreground');
    const background = getColor(theme, 'editor.background');
    result.push({ settings: { foreground: normalizeColor(foreground), background: normalizeColor(background) } });
    let hasDefaultTokens = false;
    function addRule(rule) {
      if (rule.scope && rule.settings) {
        if (rule.scope === 'token.info-token') hasDefaultTokens = true;
        const ruleSettings = rule.settings;
        result.push({
          scope: rule.scope, settings: {
            foreground: normalizeColor(ruleSettings.foreground),
            background: normalizeColor(ruleSettings.background),
            fontStyle: ruleSettings.fontStyle,
            fontSize: ruleSettings.fontSize,
            fontFamily: ruleSettings.fontFamily,
            lineHeight: ruleSettings.lineHeight,
          },
        });
      }
    }
    theme.themeTokenColors.forEach(addRule);
    if (!hasDefaultTokens) defaultThemeColors[theme.type].forEach(addRule);
    return result;
  }
  function tokenColorMap(theme, rules) { // `getTokenColorIndex`, TokenColorIndex
    const id2color = [];
    const color2id = Object.create(null);
    let lastColorId = 0;
    const add = color => {
      color = normalizeColor(color);
      if (color === undefined || color2id[color]) return;
      color2id[color] = ++lastColorId;
      id2color[lastColorId] = color;
    };
    for (const rule of rules) {
      add(rule.settings.foreground);
      add(rule.settings.background);
    }
    theme.semanticTokenRules.forEach(rule => add(rule.style.foreground));
    // The registry's default semantic rules (tokenClassificationRegistry.ts) all probe
    // TextMate scopes; none has a per-theme-type color to add.
    return id2color;
  }
  function themeType(uiTheme) { // `fromExtensionTheme` and `get type`
    switch ((uiTheme || 'vs-dark').split(' ')[0]) {
      case 'vs': return 'light';
      case 'hc-black': return 'hcDark';
      case 'hc-light': return 'hcLight';
      default: return 'dark';
    }
  }

  const themes = [];
  await rm(join(fixtures, 'themes'), { recursive: true, force: true });
  await mkdir(join(fixtures, 'themes'), { recursive: true });
  for (const contribution of manifest.themes) {
    if (/[\\/:*?"<>|]/.test(contribution.id)) throw new Error(`Theme id ${contribution.id} is not a portable file name`);
    const result = { colors: {}, textMateRules: [], semanticTokenRules: [], semanticHighlighting: false }; // `load`
    await loadColorTheme(contribution.path, result);
    const theme = {
      contribution,
      type: themeType(contribution.uiTheme),
      colors: result.colors,
      themeTokenColors: result.textMateRules,
      semanticTokenRules: result.semanticTokenRules,
    };
    theme.tokenColors = tokenColors(theme);
    theme.tokenColorMap = tokenColorMap(theme, theme.tokenColors);
    // textMateTokenizationFeatureImpl.ts `_updateTheme`: the IRawTheme and color map.
    theme.rawTheme = { name: contribution.label, settings: theme.tokenColors };
    // themes.test.contribution.ts `getThemeName`: the colorize-results key of a
    // theme-defaults theme (its id is `vscode-theme-defaults-themes-<file>-json`).
    theme.colorizeName = contribution.extension === 'theme-defaults' ? posix.basename(contribution.path, '.json') : undefined;
    themes.push(theme);
    await writeFile(join(fixtures, 'themes', `${contribution.id}.json`), JSON.stringify({
      revision,
      id: contribution.id,
      type: theme.type,
      // JSON drops the rules' undefined settings, as a structured clone to the worker keeps them.
      rawTheme: theme.rawTheme,
      tokenColorMap: theme.tokenColorMap,
    }, null, 1) + '\n');
  }
  const colorizeThemes = themes.filter(theme => theme.colorizeName);
  // The colorize results of light_vs and light_plus, Light (Visual Studio)
  // and Light+, which generate_textmate_assets.mjs leaves out: not checked.
  const unbundledColorizeThemes = ['light_vs', 'light_plus'];

  // --- Language of a file name: src/vs/editor/common/services/languagesAssociations.ts ---
  // The colorize test calls `guessLanguageIdByFilepathOrFirstLine(URI.file(fileName))`
  // with the fixture's base name (themes.test.contribution.ts `captureTokens`), so the
  // path is `/<name>` and no first line takes part. `_mergeLanguage` (languagesRegistry.ts)
  // registers each language's extensions, then file names, then file patterns.
  const associations = [];
  for (const language of manifest.languages) {
    for (const extension of language.extensions ?? []) associations.push({ id: language.id, extension });
    for (const filename of language.filenames ?? []) associations.push({ id: language.id, filename });
    for (const filepattern of language.filenamePatterns ?? []) {
      associations.push({ id: language.id, filepattern, filepatternParsed: globToRegExp(filepattern), filepatternOnPath: filepattern.includes('/') });
    }
  }
  // The glob.ts syntax the built-in file patterns use: `**`, `*`, `?`, `{a,b}`, with
  // `ignoreCase` (toLanguageAssociationItem).
  function globToRegExp(pattern) {
    let regex = '';
    for (let i = 0; i < pattern.length; i++) {
      const c = pattern[i];
      if (c === '*' && pattern[i + 1] === '*') {
        const slash = pattern[i + 2] === '/';
        regex += slash ? '(?:.*/)?' : '.*';
        i += slash ? 2 : 1;
      } else if (c === '*') {
        regex += '[^/]*';
      } else if (c === '?') {
        regex += '[^/]';
      } else if (c === '{') {
        const end = pattern.indexOf('}', i);
        regex += '(?:' + pattern.slice(i + 1, end).split(',').map(part => part.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('|') + ')';
        i = end;
      } else if (c === '[') {
        throw new Error(`Unsupported glob ${pattern}`);
      } else {
        regex += c.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&');
      }
    }
    return new RegExp(`^${regex}$`, 'i');
  }
  function languageOfFileName(name) { // `getAssociations` and `getAssociationByPath`
    const path = `/${name}`.toLowerCase();
    const filename = posix.basename(path);
    let filenameMatch, patternMatch, extensionMatch;
    for (let i = associations.length - 1; i >= 0; i--) {
      const association = associations[i];
      if (association.filename !== undefined && filename === association.filename.toLowerCase()) {
        filenameMatch = association;
        break;
      }
      if (association.filepattern) {
        if (!patternMatch || association.filepattern.length > patternMatch.filepattern.length) {
          if (association.filepatternParsed.test(association.filepatternOnPath ? path : filename)) patternMatch = association;
        }
      }
      if (association.extension) {
        if (!extensionMatch || association.extension.length > extensionMatch.extension.length) {
          if (filename.endsWith(association.extension.toLowerCase())) extensionMatch = association;
        }
      }
    }
    return (filenameMatch ?? patternMatch ?? extensionMatch)?.id;
  }

  // --- Samples ---
  const entries = JSON.parse((await download(listing)).toString('utf8'));
  const sampleNames = entries.filter(entry => entry.type === 'file').map(entry => entry.name).sort();
  await rm(join(fixtures, 'samples'), { recursive: true, force: true });
  await mkdir(join(fixtures, 'samples', 'bench'), { recursive: true });
  const samples = [];
  for (const name of sampleNames) {
    const bytes = await download(`${colorizeTests}colorize-fixtures/${name}`);
    if (bytes[0] === 0xEF && bytes[1] === 0xBB && bytes[2] === 0xBF) throw new Error(`${name} starts with a BOM`);
    // `.txt` keeps test.dart from the analyzer and test.log from .gitignore.
    const path = `samples/${name}${/\.(dart|log)$/.test(name) ? '.txt' : ''}`;
    await writeFile(join(fixtures, path), bytes);
    // colorizer.test.ts names results `fixture.replace('.', '_') + '.json'`.
    const results = JSON.parse((await download(`${colorizeTests}colorize-results/${name.replace('.', '_')}.json`)).toString('utf8'));
    samples.push({ name, path, text: bytes.toString('utf8'), results });
  }
  // Languages with a grammar but no colorize fixture get a hand-written sample in
  // extra/, tokenized as the language its file name selects. No file name selects
  // these (other grammars embed them), so their samples' names select nothing and
  // the language is given here.
  const unassociated = {
    'combined.markdown_latex_combined': 'markdown_latex_combined',
    'embedded.cpp_embedded_latex': 'cpp_embedded_latex',
    'math.markdown-math': 'markdown-math',
  };
  for (const name of (await readdir(join(fixtures, 'extra'))).sort()) {
    const text = await readFile(join(fixtures, 'extra', name), 'utf8');
    const byName = languageOfFileName(name);
    if (byName !== undefined && unassociated[name] !== undefined) throw new Error(`extra/${name} selects ${byName}`);
    const language = byName ?? unassociated[name];
    if (language === undefined) throw new Error(`extra/${name} selects no language`);
    samples.push({ name: `extra/${name}`, path: `extra/${name}`, text, language });
  }
  const benchBytes = await download(benchPath);
  const benchName = posix.basename(benchPath);
  await writeFile(join(fixtures, 'samples', 'bench', benchName), benchBytes);

  const splitLines = str => str.split(/\r\n|\r|\n/); // strings.ts `splitLines`, as the text model splits

  // --- The editor's per-line loop ---
  // tokenizationSupportWithLineLimit.ts with `editor.maxTokenizationLineLength` for the
  // document's language (20_000 in editorConfigurationSchema.ts unless an extension's
  // configurationDefaults set it for the language), and textMateTokenizationSupport.ts.
  const defaultMaxTokenizationLineLength = 20_000;
  const maxTokenizationLineLengthOf = languageId =>
    manifest.configurationDefaults?.[`[${languageId}]`]?.['editor.maxTokenizationLineLength'] ?? defaultMaxTokenizationLineLength;
  const timeLimitMs = 500;
  const MetadataConsts = { // encodedTokenAttributes.ts
    LANGUAGEID_MASK: 0xFF, TOKEN_TYPE_MASK: 0x300, BALANCED_BRACKETS_MASK: 0x400,
    FONT_STYLE_MASK: 0x7800, FOREGROUND_MASK: 0xFF8000, BACKGROUND_MASK: 0xFF000000,
  };
  function nullTokenizeEncoded(languageId) { // nullTokenize.ts
    return Uint32Array.of(0, ((languageId << 0) | (0 << 8) | (0 << 11) | (1 << 15) | (2 << 24)) >>> 0);
  }
  function tokenizeLines(grammar, lines, encodedLanguageId, maxLineLength) {
    let state = vsctm.INITIAL;
    const result = [];
    for (const line of lines) {
      if (line.length >= maxLineLength) {
        result.push(nullTokenizeEncoded(encodedLanguageId));
        continue;
      }
      const r = grammar.tokenizeLine2(line, state, timeLimitMs);
      if (r.stoppedEarly) {
        // VS Code keeps these tokens and tokenizes the next line from `state` (the state
        // at the start of this line); a fixture must not depend on timing.
        throw new Error(`Time limit reached when tokenizing line: ${line.substring(0, 100)}`);
      }
      result.push(r.tokens);
      state = state.equals(r.ruleStack) ? state : r.ruleStack;
    }
    return result;
  }
  const foregroundOf = metadata => (metadata & MetadataConsts.FOREGROUND_MASK) >>> 15;

  // --- The colorize test (themes.test.contribution.ts `Snapper`) ---
  function snapperTokenize(grammar, lines) { // `_tokenize`
    let state = null;
    const result = [];
    for (const line of lines) {
      const tokenizationResult = grammar.tokenizeLine(line, state);
      let lastScopes = null;
      for (const token of tokenizationResult.tokens) {
        const tokenText = line.substring(token.startIndex, token.endIndex);
        const tokenScopes = token.scopes.join(' ');
        if (lastScopes === tokenScopes) {
          result[result.length - 1].c += tokenText;
        } else {
          lastScopes = tokenScopes;
          result.push({ c: tokenText, t: tokenScopes, r: {} });
        }
      }
      state = tokenizationResult.ruleStack;
    }
    return result;
  }
  function themedTokenize(grammar, lines, colorMap) { // `_themedTokenize`
    let state = null;
    const result = [];
    for (const line of lines) {
      const tokenizationResult = grammar.tokenizeLine2(line, state);
      const count = tokenizationResult.tokens.length >>> 1;
      for (let j = 0; j < count; j++) {
        const startOffset = tokenizationResult.tokens[j << 1];
        const endOffset = j + 1 < count ? tokenizationResult.tokens[(j + 1) << 1] : line.length;
        result.push({ text: line.substring(startOffset, endOffset), color: colorMap[foregroundOf(tokenizationResult.tokens[(j << 1) + 1])] });
      }
      state = tokenizationResult.ruleStack;
    }
    return result;
  }
  function explainTokenColor(theme, scopes, color) { // `ThemeDocument`
    let defaultColor = '#000000';
    for (const rule of theme.tokenColors) if (!rule.scope) defaultColor = rule.settings.foreground;
    const explanation = (selector, c) => `${selector}: ${Color.Format.CSS.formatHexA(c, true).toUpperCase()}`;
    const matchingRule = findMatchingThemeRule(theme, scopes.split(' '));
    if (!matchingRule) {
      if (!color.equals(Color.fromHex(defaultColor))) throw new Error(`Unexpected color ${Color.Format.CSS.formatHexA(color)} for ${scopes}`);
      return explanation('default', color);
    }
    if (!color.equals(Color.fromHex(matchingRule.settings.foreground))) throw new Error(`Unexpected color ${Color.Format.CSS.formatHexA(color)} for ${scopes}`);
    return explanation(matchingRule.rawSelector, color);
  }
  function enrichResult(result, themesResult) { // `_enrichResult`
    const index = {};
    const themeNames = Object.keys(themesResult);
    for (const themeName of themeNames) index[themeName] = 0;
    for (const token of result) {
      for (const themeName of themeNames) {
        const themedToken = themesResult[themeName].tokens[index[themeName]];
        themedToken.text = themedToken.text.substr(token.c.length);
        if (themedToken.color) {
          token.r[themeName] = explainTokenColor(themesResult[themeName].theme, token.t, themedToken.color);
        }
        if (themedToken.text.length === 0) index[themeName]++;
      }
    }
  }

  const outputSamples = [];
  const mismatches = [];
  const ambiguities = [];
  let checkedTokens = 0, checkedColors = 0, storedCases = 0, storedTokens = 0;
  const colorMaps = {};
  const setTheme = theme => {
    grammarRegistry.setTheme(theme.rawTheme, theme.tokenColorMap);
    const colorMap = grammarRegistry.getColorMap();
    colorMaps[theme.contribution.id] ??= colorMap;
    return colorMap;
  };

  for (const sample of samples) {
    const expected = sample.results;
    let languageId = sample.language;
    if (expected) {
      // The language VS Code tokenized the sample as: colorize-results' root scope names
      // the grammar, whose `language` is the answer; the file name must agree.
      const rootScope = expected[0].t.split(' ')[0];
      const candidates = [...languageToScope].filter(([, scope]) => scope === rootScope).map(([language]) => language);
      const byName = languageOfFileName(sample.name);
      if (!candidates.includes(byName)) {
        mismatches.push(`${sample.name}: file name gives ${byName}, colorize-results' root scope ${rootScope} is ${candidates.join(', ') || 'no language'}`);
        continue;
      }
      if (candidates.length > 1) ambiguities.push(`${sample.name}: ${rootScope} is the grammar of ${candidates.join(', ')}; the file name gives ${byName}`);
      languageId = byName;
    }
    const grammar = await grammarFor(languageId);
    const lines = splitLines(sample.text);
    const maxLineLength = maxTokenizationLineLengthOf(languageId);

    // Scopes, as `tokenizeLine` gives them: [startIndex, endIndex, scope index] per token.
    const scopeTable = [];
    const scopeIndex = new Map();
    let state = null;
    const scopes = lines.map(line => {
      const r = grammar.tokenizeLine(line, state);
      state = r.ruleStack;
      return r.tokens.flatMap(token => {
        const joined = token.scopes.join(' ');
        if (!scopeIndex.has(joined)) {
          scopeIndex.set(joined, scopeTable.length);
          scopeTable.push(joined);
        }
        return [token.startIndex, token.endIndex, scopeIndex.get(joined)];
      });
    });

    // Cross-check against VS Code's colorize results: scopes, and every listed theme's
    // color explanation (`captureSyntaxTokens`). Extra samples have none.
    if (expected) {
      const snapped = snapperTokenize(grammar, lines);
      const themesResult = {};
      for (const theme of colorizeThemes) {
        const colorMap = setTheme(theme).map(hex => (hex ? Color.fromHex(hex) : null)); // `toColorMap`
        themesResult[theme.colorizeName] = { theme, tokens: themedTokenize(grammar, lines, colorMap) };
      }
      try {
        enrichResult(snapped, themesResult);
      } catch (error) {
        mismatches.push(`${sample.name}: ${error.message}`);
      }
      const actual = snapped.filter(token => token.c.length > 0);
      checkedTokens += expected.length;
      if (actual.length !== expected.length) mismatches.push(`${sample.name}: ${actual.length} tokens, colorize-results ${expected.length}`);
      let reported = 0;
      for (let i = 0; i < Math.min(actual.length, expected.length); i++) {
        const a = actual[i], b = expected[i];
        const names = new Set([...Object.keys(a.r), ...Object.keys(b.r ?? {})].filter(name => !unbundledColorizeThemes.includes(name)));
        checkedColors += names.size;
        const differs = a.c !== b.c || a.t !== b.t || [...names].some(name => a.r[name] !== b.r?.[name]);
        if (differs && reported++ < 5) mismatches.push(`${sample.name} token ${i}: ${JSON.stringify(a)}, colorize-results ${JSON.stringify(b)}`);
      }
      if (reported > 5) mismatches.push(`${sample.name}: ${reported - 5} more mismatching tokens`);
    }

    // The editor's binary tokens in every bundled theme.
    const cases = {};
    const seen = new Map();
    for (const theme of themes) {
      setTheme(theme);
      const tokens = tokenizeLines(grammar, lines, languageIds[languageId], maxLineLength).map(line => [...line]);
      const key = JSON.stringify(tokens);
      if (seen.has(key)) {
        cases[theme.contribution.id] = { sameAs: seen.get(key) };
      } else {
        seen.set(key, theme.contribution.id);
        cases[theme.contribution.id] = tokens;
        storedCases++;
        storedTokens += tokens.reduce((sum, line) => sum + line.length / 2, 0);
      }
    }
    outputSamples.push({
      name: sample.name,
      path: sample.path,
      language: languageId,
      scopeName: languageToScope.get(languageId),
      lineCount: lines.length,
      maxTokenizationLineLength: maxLineLength,
      scopeTable,
      scopes,
      cases,
    });
  }
  const unlisted = [...new Set(samples.flatMap(sample => (sample.results ?? []).flatMap(token => Object.keys(token.r ?? {}))))]
    .filter(name => !colorizeThemes.some(theme => theme.colorizeName === name) && !unbundledColorizeThemes.includes(name));
  if (unlisted.length) mismatches.push(`colorize-results themes without a bundled theme: ${unlisted.join(', ')}`);

  // --- Benchmark: the editor loop over a large real file, Dark+ ---
  const benchLines = splitLines(benchBytes.toString('utf8'));
  const bench = themes.find(theme => theme.contribution.id === benchTheme);
  setTheme(bench);
  const benchGrammar = await grammarFor('typescript');
  const timings = [];
  let benchTokens;
  for (let run = 0; run < 12; run++) {
    const start = process.hrtime.bigint();
    benchTokens = tokenizeLines(benchGrammar, benchLines, languageIds.typescript, maxTokenizationLineLengthOf('typescript'));
    timings.push(Number(process.hrtime.bigint() - start) / 1e6);
  }
  const warm = timings.slice(2).sort((a, b) => a - b);
  const tokenCount = benchTokens.reduce((sum, tokens) => sum + tokens.length / 2, 0);

  const fixture = {
    revision,
    vscodeTextmate: textmateVersion,
    vscodeOniguruma: onigurumaVersion,
    attribution: 'Copyright (c) Microsoft Corporation. Licensed under the MIT License; samples and grammars from VS Code, see assets/textmate/LICENSE.txt.',
    generator: 'tool/generate_textmate_fixtures.mjs',
    languageIds,
    // The order the samples first asked for each language's grammar.
    grammarOrder,
    defaultMaxTokenizationLineLength,
    timeLimitMs,
    // Binary tokens as `tokenizeLine2` returns them: [startIndex, metadata] per token;
    // metadata's colors index the theme's color map (index 0 unused).
    colorMaps,
    samples: outputSamples,
    bench: {
      name: benchName,
      path: `samples/bench/${benchName}`,
      source: benchPath,
      language: 'typescript',
      theme: benchTheme,
      lineCount: benchLines.length,
      tokens: benchTokens.map(tokens => [...tokens]),
    },
    colorizeCheck: {
      themes: colorizeThemes.map(theme => theme.colorizeName),
      tokens: checkedTokens,
      colors: checkedColors,
      mismatches,
      ambiguities,
      rejectedGrammars,
    },
  };
  const fixturePath = join(fixtures, 'tokens.json.gz');
  const gzipped = gzipSync(JSON.stringify(fixture) + '\n', { level: 9 });
  await writeFile(fixturePath, gzipped);

  console.log(`Wrote ${fixturePath} (${(gzipped.length / 1024).toFixed(0)} KiB): ${samples.length} samples (${samples.filter(sample => !sample.results).length} extra), ${storedCases} distinct cases, ${storedTokens} tokens; language ids for ${Object.keys(languageIds).length} languages`);
  console.log(`Colorize cross-check of ${checkedTokens} tokens and ${checkedColors} color explanations (${colorizeThemes.map(theme => theme.colorizeName).join(', ')}): ${mismatches.length ? `${mismatches.length} MISMATCHES` : 'all scopes and colors match'}`);
  for (const mismatch of mismatches) console.log(`  ${mismatch}`);
  for (const ambiguity of ambiguities) console.log(`  ambiguous: ${ambiguity}`);
  for (const rejected of rejectedGrammars) console.log(`  VS Code rejects grammar ${rejected}`);
  console.log(`Benchmark ${benchPath} (${benchLines.length} lines, ${benchBytes.length} bytes, ${tokenCount} tokens, ${benchTheme}), node ${process.version}:`);
  console.log(`  first run ${timings[0].toFixed(1)} ms, second ${timings[1].toFixed(1)} ms`);
  console.log(`  warm (${warm.length} runs): min ${warm[0].toFixed(1)} ms, median ${warm[warm.length >> 1].toFixed(1)} ms, max ${warm[warm.length - 1].toFixed(1)} ms`);
} finally {
  await rm(temporary, { recursive: true, force: true });
}
