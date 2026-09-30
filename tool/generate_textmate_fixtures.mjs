// Runs the real upstream vscode-textmate and vscode-oniguruma, never the Dart port,
// set up exactly as VS Code does, to create TextMate tokenization parity data.
// Usage: node --experimental-transform-types tool/generate_textmate_fixtures.mjs [assets-dir] [fixtures-dir]
// (defaults: assets/textmate, written by tool/generate_textmate_assets.mjs, and test/fixtures/textmate)
//
// Everything below mirrors VS Code 6a598d4a13031703d483d103c1d934a36ad27971; each
// piece names the upstream file and lines it reproduces. Upstream json.ts, color.ts
// and plistParser.ts are downloaded and imported unchanged (import paths aside).
import { execFileSync } from 'node:child_process';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { tmpdir } from 'node:os';
import { join, posix } from 'node:path';
import { pathToFileURL } from 'node:url';

const revision = '6a598d4a13031703d483d103c1d934a36ad27971';
// VS Code's package-lock.json at `revision` locks these.
const textmateVersion = '9.3.2';
const onigurumaVersion = '1.7.0';
const source = `https://raw.githubusercontent.com/microsoft/vscode/${revision}/`;
const listing = `https://api.github.com/repos/microsoft/vscode/contents/extensions/vscode-colorize-tests/test/colorize-fixtures?ref=${revision}`;
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

  // --- Upstream modules the theme code uses ---
  const upstream = {
    'json.ts': 'src/vs/base/common/json.ts',
    'charCode.ts': 'src/vs/base/common/charCode.ts',
    'color.ts': 'src/vs/base/common/color.ts',
    'plistParser.ts': 'src/vs/workbench/services/themes/common/plistParser.ts',
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

  const manifest = JSON.parse(await readFile(join(assets, 'manifest.json'), 'utf8'));
  if (manifest.revision !== revision) throw new Error(`${assets} is from ${manifest.revision}; run tool/generate_textmate_assets.mjs`);
  const readAsset = path => readFile(join(assets, path), 'utf8');

  // --- Language ids ---
  // LanguageIdCodec (src/vs/editor/common/services/languagesRegistry.ts L38-55) reserves
  // 0 for the null language and 1 for plaintext, then numbers languages in registration
  // order. The fixture fixes that order: plaintext, then the manifest's languages.
  const languageIds = { plaintext: 1 };
  for (const language of manifest.languages) languageIds[language.id] ??= Object.keys(languageIds).length + 1;
  const isRegisteredLanguageId = id => Object.hasOwn(languageIds, id);

  // --- Grammar definitions ---
  // textMateTokenizationFeatureImpl.ts `_validateGrammarDefinition` (L146-214) and
  // `validateGrammarExtensionPoint` (L496-528), applied to the package.json contributions.
  const StandardTokenType = { Other: 0, Comment: 1, String: 2, RegEx: 3 }; // encodedTokenAttributes.ts L38-43
  function asStringArray(array, defaultValue) {
    if (!Array.isArray(array)) return defaultValue;
    if (!array.every(e => typeof e === 'string')) return defaultValue;
    return array;
  }
  const grammarDefinitions = [];
  for (const grammar of manifest.grammars) {
    if (grammar.language && (typeof grammar.language !== 'string' || !isRegisteredLanguageId(grammar.language))) throw new Error(`Unknown language ${grammar.language}`);
    const embeddedLanguages = Object.create(null);
    for (const scope of Object.keys(grammar.embeddedLanguages ?? {})) {
      const language = grammar.embeddedLanguages[scope];
      if (typeof language !== 'string') continue;
      if (isRegisteredLanguageId(language)) embeddedLanguages[scope] = languageIds[language];
    }
    const tokenTypes = Object.create(null);
    for (const scope of Object.keys(grammar.tokenTypes ?? {})) {
      switch (grammar.tokenTypes[scope]) {
        case 'string': tokenTypes[scope] = StandardTokenType.String; break;
        case 'other': tokenTypes[scope] = StandardTokenType.Other; break;
        case 'comment': tokenTypes[scope] = StandardTokenType.Comment; break;
        case 'regex': tokenTypes[scope] = StandardTokenType.RegEx; break;
      }
    }
    grammarDefinitions.push({
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

  // --- TMGrammarFactory (src/vs/workbench/services/textMate/common/TMGrammarFactory.ts L38-168) ---
  const scopeRegistry = Object.create(null); // TMScopeRegistry.ts L41-56
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

  // --- Color themes: src/vs/workbench/services/themes/common/colorThemeData.ts ---
  const DEFAULT_COLOR_CONFIG_VALUE = 'default'; // platform/theme/common/colorUtils.ts L89
  // themeCompatibility.ts L12-76: global tmTheme settings -> color ids.
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
  function convertSettings(oldSettings, result) { // themeCompatibility.ts L21-48
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
  function readSemanticTokenRule(selectorString, settings) { // L936-953
    // TokenClassificationRegistry.parseTokenSelector never throws; the fixtures only
    // need the rule's style (tokenClassificationRegistry.ts TokenStyle.fromSettings L106-110).
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
  async function loadSyntaxTokens(location, result) { // L835-851
    const contentValue = plist.parse(await readAsset(location));
    const settings = contentValue.settings;
    if (!Array.isArray(settings)) throw new Error(`Problem parsing tmTheme file: ${location}. 'settings' is not array.`);
    convertSettings(settings, result);
  }
  async function loadColorTheme(location, result) { // `_loadColorTheme` L774-833
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
  function normalizeColor(color) { // L1076-1113
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
  const defaultThemeColors = { // L853-878
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
  // Registry defaults of the colors `tokenColors` reads: editorColors.ts L19-25,
  // baseColors.ts L13-15; resolved as colorUtils.ts `resolveDefaultColor` (L216-223)
  // and `resolveColorValue` (L352-366) do.
  const colorDefaults = {
    'editor.background': { light: '#ffffff', dark: '#1E1E1E', hcDark: Color.black, hcLight: Color.white },
    'editor.foreground': { light: '#333333', dark: '#BBBBBB', hcDark: Color.white, hcLight: 'foreground' },
    foreground: { dark: '#CCCCCC', light: '#616161', hcDark: '#FFFFFF', hcLight: '#292929' },
  };
  function getColor(theme, colorId) { // L152-171 without customizations or transient colors
    const color = theme.colors[colorId];
    if (color !== undefined) return color;
    const colorValue = colorDefaults[colorId][theme.type];
    if (colorValue instanceof Color) return colorValue;
    return colorValue[0] === '#' ? Color.fromHex(colorValue) : getColor(theme, colorValue);
  }
  function tokenColors(theme) { // `get tokenColors` L104-150 (no user customizations)
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
  function tokenColorMap(theme, rules) { // `getTokenColorIndex` L269-290, TokenColorIndex L993-1037
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
    // The registry's default semantic rules (tokenClassificationRegistry.ts L517-598) all
    // probe TextMate scopes; none has a per-theme-type color to add.
    return id2color;
  }
  function themeType(uiTheme) { // `fromExtensionTheme` L744-757 and `get type` L649-664
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
    const result = { colors: {}, textMateRules: [], semanticTokenRules: [], semanticHighlighting: false }; // `load` L597-617
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
    // textMateTokenizationFeatureImpl.ts `_updateTheme` L347-351: the IRawTheme and color map.
    theme.rawTheme = { name: contribution.label, settings: theme.tokenColors };
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

  // --- Samples ---
  const entries = JSON.parse((await download(listing)).toString('utf8'));
  const sampleNames = entries.map(entry => entry.name).filter(name => /\.tsx?$/.test(name)).sort();
  await rm(join(fixtures, 'samples'), { recursive: true, force: true });
  await mkdir(join(fixtures, 'samples', 'bench'), { recursive: true });
  const samples = [];
  for (const name of sampleNames) {
    const bytes = await download(`extensions/vscode-colorize-tests/test/colorize-fixtures/${name}`);
    await writeFile(join(fixtures, 'samples', name), bytes);
    // colorizer.test.ts names results `fixture.replace('.', '_') + '.json'`.
    const results = JSON.parse((await download(`extensions/vscode-colorize-tests/test/colorize-results/${name.replace('.', '_')}.json`)).toString('utf8'));
    samples.push({ name, path: `samples/${name}`, text: bytes.toString('utf8'), results });
  }
  const benchBytes = await download(benchPath);
  const benchName = posix.basename(benchPath);
  await writeFile(join(fixtures, 'samples', 'bench', benchName), benchBytes);

  const splitLines = str => str.split(/\r\n|\r|\n/); // strings.ts L259-261, as the text model splits
  const languageOf = name => manifest.languages.find(language => (language.extensions ?? []).some(ext => name.endsWith(ext))).id;

  // --- The editor's per-line loop ---
  // tokenizationSupportWithLineLimit.ts L38-45 (editor.maxTokenizationLineLength, default
  // 20_000 in editorConfigurationSchema.ts L94-98) and textMateTokenizationSupport.ts L50-92.
  const maxTokenizationLineLength = 20_000;
  const timeLimitMs = 500;
  const MetadataConsts = { // encodedTokenAttributes.ts L68-94
    LANGUAGEID_MASK: 0xFF, TOKEN_TYPE_MASK: 0x300, BALANCED_BRACKETS_MASK: 0x400,
    FONT_STYLE_MASK: 0x7800, FOREGROUND_MASK: 0xFF8000, BACKGROUND_MASK: 0xFF000000,
  };
  function nullTokenizeEncoded(languageId) { // nullTokenize.ts L22-34
    return Uint32Array.of(0, ((languageId << 0) | (0 << 8) | (0 << 11) | (1 << 15) | (2 << 24)) >>> 0);
  }
  function tokenizeLines(grammar, lines, encodedLanguageId) {
    let state = vsctm.INITIAL;
    const result = [];
    for (const line of lines) {
      if (line.length >= maxTokenizationLineLength) {
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
  function decode(tokens, colorMap) {
    const flat = [];
    for (let i = 0; i < tokens.length; i += 2) {
      const metadata = tokens[i + 1];
      flat.push(
        tokens[i],
        (metadata & MetadataConsts.LANGUAGEID_MASK) >>> 0,
        (metadata & MetadataConsts.TOKEN_TYPE_MASK) >>> 8,
        (metadata & MetadataConsts.FONT_STYLE_MASK) >>> 11,
        (metadata & MetadataConsts.BALANCED_BRACKETS_MASK) ? 1 : 0,
        colorMap[(metadata & MetadataConsts.FOREGROUND_MASK) >>> 15],
        colorMap[(metadata & MetadataConsts.BACKGROUND_MASK) >>> 24],
      );
    }
    return flat;
  }

  const outputSamples = [];
  const cases = [];
  const mismatches = [];
  let checkedTokens = 0, checkedColors = 0;
  const themeByColorizeName = new Map(themes
    .filter(theme => theme.contribution.extension === 'theme-defaults')
    .map(theme => [posix.basename(theme.contribution.path, '.json'), theme]));
  const grammars = new Map();
  const grammarFor = async languageId => {
    if (!grammars.has(languageId)) grammars.set(languageId, await createGrammar(languageId, languageIds[languageId]));
    return grammars.get(languageId);
  };

  for (const sample of samples) {
    const languageId = languageOf(sample.name);
    const grammar = await grammarFor(languageId);
    const lines = splitLines(sample.text);

    // Scopes: `tokenizeLine` as the colorize tests' Snapper._tokenize runs it
    // (src/vs/workbench/contrib/themes/browser/themes.test.contribution.ts).
    const scopeTable = [];
    const scopeIndex = new Map();
    const scopeLines = [];
    const colorizeTokens = []; // {c, t, line, start}
    let state = null;
    lines.forEach((line, lineIndex) => {
      const r = grammar.tokenizeLine(line, state);
      const flat = [];
      let lastScopes = null;
      for (const token of r.tokens) {
        const scopes = token.scopes.join(' ');
        if (!scopeIndex.has(scopes)) {
          scopeIndex.set(scopes, scopeTable.length);
          scopeTable.push(scopes);
        }
        flat.push(token.startIndex, scopeIndex.get(scopes));
        const text = line.substring(token.startIndex, token.endIndex);
        if (lastScopes === scopes) {
          colorizeTokens[colorizeTokens.length - 1].c += text;
        } else {
          lastScopes = scopes;
          colorizeTokens.push({ c: text, t: scopes, line: lineIndex, start: token.startIndex });
        }
      }
      scopeLines.push(flat);
      state = r.ruleStack;
    });
    const kept = colorizeTokens.filter(token => token.c.length > 0);
    outputSamples.push({
      name: sample.name,
      path: sample.path,
      language: languageId,
      scopeName: languageToScope.get(languageId),
      lineCount: lines.length,
      scopeTable,
      scopes: scopeLines,
    });

    // Cross-check the scopes against VS Code's colorize results.
    const expected = sample.results;
    const length = Math.max(expected.length, kept.length);
    checkedTokens += expected.length;
    for (let i = 0; i < length; i++) {
      const a = kept[i], b = expected[i];
      if (!a || !b || a.c !== b.c || a.t !== b.t) {
        mismatches.push(`${sample.name}: token ${i}: scopes ${JSON.stringify(a && { c: a.c, t: a.t })}, colorize-results ${JSON.stringify(b && { c: b.c, t: b.t })}`);
        break;
      }
    }

    const perTheme = new Map();
    for (const theme of themes) {
      grammarRegistry.setTheme(theme.rawTheme, theme.tokenColorMap);
      const colorMap = grammarRegistry.getColorMap();
      const binary = tokenizeLines(grammar, lines, languageIds[languageId]);
      const decoded = binary.map(tokens => decode(tokens, colorMap));
      const key = JSON.stringify(decoded);
      const same = perTheme.get(key);
      if (same) {
        cases.push({ sample: sample.name, theme: theme.contribution.id, sameAs: same });
      } else {
        perTheme.set(key, theme.contribution.id);
        cases.push({ sample: sample.name, theme: theme.contribution.id, lines: decoded });
      }

      // Cross-check the colors against VS Code's colorize results (Snapper._enrichResult
      // and ThemeDocument.explainTokenColor: the color of the binary token at each scope token).
      const colorizeName = [...themeByColorizeName].find(([, t]) => t === theme)?.[0];
      if (!colorizeName) continue;
      let reported = 0;
      kept.forEach((token, i) => {
        const explanation = expected[i]?.r?.[colorizeName];
        if (explanation === undefined || expected[i].c !== token.c) return;
        const tokens = binary[token.line];
        let j = 0;
        while (j + 2 < tokens.length && tokens[j + 2] <= token.start) j += 2;
        const hex = colorMap[(tokens[j + 1] & MetadataConsts.FOREGROUND_MASK) >>> 15];
        const actual = Color.Format.CSS.formatHexA(Color.fromHex(hex), true).toUpperCase();
        const wanted = explanation.substring(explanation.lastIndexOf(': ') + 2);
        checkedColors++;
        if (actual !== wanted && reported++ < 5) {
          mismatches.push(`${sample.name} [${colorizeName}] token ${i} ${JSON.stringify(token.c)} (${token.t}): ${actual}, colorize-results ${explanation}`);
        }
      });
      if (reported > 5) mismatches.push(`${sample.name} [${colorizeName}]: ${reported - 5} more color mismatches`);
    }
  }
  const colorizeThemes = [...themeByColorizeName.keys()].filter(name => samples.some(sample => sample.results.some(token => token.r?.[name] !== undefined)));
  const missing = [...new Set(samples.flatMap(sample => sample.results.flatMap(token => Object.keys(token.r ?? {}))))]
    .filter(name => !themeByColorizeName.has(name));
  if (missing.length) mismatches.push(`colorize-results themes without a manifest theme: ${missing.join(', ')}`);

  // --- Benchmark: the editor loop over a large real file, Dark+ ---
  const benchLines = splitLines(benchBytes.toString('utf8'));
  const bench = themes.find(theme => theme.contribution.id === benchTheme);
  grammarRegistry.setTheme(bench.rawTheme, bench.tokenColorMap);
  const benchGrammar = await grammarFor('typescript');
  const timings = [];
  let benchTokens;
  for (let run = 0; run < 12; run++) {
    const start = process.hrtime.bigint();
    benchTokens = tokenizeLines(benchGrammar, benchLines, languageIds.typescript);
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
    maxTokenizationLineLength,
    timeLimitMs,
    tokenFields: ['startIndex', 'languageId', 'tokenType', 'fontStyle', 'balancedBrackets', 'foreground', 'background'],
    samples: outputSamples,
    cases,
    // The benchmark file, one theme only, to keep the fixture small.
    bench: {
      name: benchName,
      path: `samples/bench/${benchName}`,
      source: benchPath,
      language: 'typescript',
      scopeName: languageToScope.get('typescript'),
      theme: benchTheme,
      lineCount: benchLines.length,
      lines: benchTokens.map(tokens => decode(tokens, grammarRegistry.getColorMap())),
    },
    colorizeCheck: {
      themes: colorizeThemes,
      tokens: checkedTokens,
      colors: checkedColors,
      mismatches,
    },
  };
  await writeFile(join(fixtures, 'typescript_tokens.json'), JSON.stringify(fixture) + '\n');

  const full = cases.filter(c => c.lines).length;
  console.log(`Wrote ${join(fixtures, 'typescript_tokens.json')}: ${samples.length} samples x ${themes.length} themes (${full} distinct cases, ${cases.length - full} duplicates)`);
  console.log(`Colorize cross-check of ${checkedTokens} tokens and ${checkedColors} colors (${colorizeThemes.join(', ')}): ${mismatches.length ? `${mismatches.length} MISMATCHES` : 'all scopes and colors match'}`);
  for (const mismatch of mismatches) console.log(`  ${mismatch}`);
  console.log(`Benchmark ${benchPath} (${benchLines.length} lines, ${benchBytes.length} bytes, ${tokenCount} tokens, ${benchTheme}), node ${process.version}:`);
  console.log(`  first run ${timings[0].toFixed(1)} ms, second ${timings[1].toFixed(1)} ms`);
  console.log(`  warm (${warm.length} runs): min ${warm[0].toFixed(1)} ms, median ${warm[warm.length >> 1].toFixed(1)} ms, max ${warm[warm.length - 1].toFixed(1)} ms`);
} finally {
  await rm(temporary, { recursive: true, force: true });
}
