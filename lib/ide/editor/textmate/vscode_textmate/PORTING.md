# vscode-textmate port

This is a Dart port of **vscode-textmate 9.3.2** (tag `v9.3.2`, commit
`25b68dad91920b1ed79d357534b8c4582f62d80d`), the version locked by VS Code
`6a598d4a13031703d483d103c1d934a36ad27971` together with vscode-oniguruma
1.7.0. The goal is tokens and colors identical to that VS Code revision, so
every branch, edge case and ordering follows the TypeScript sources. The
library is pure Dart (no Flutter imports) and can run in a background isolate.
Source-derived files carry a header naming their upstream file and are
covered by the MIT license in [LICENSE.md](LICENSE.md).

| Upstream `src/` path | Dart path |
| --- | --- |
| `main.ts` | `main.dart` (barrel and public API) |
| `registry.ts` | `registry.dart` |
| `rule.ts` | `rule.dart` |
| `theme.ts` | `theme.dart` (re-exports `raw_theme.dart`) |
| `theme.ts` (`IRawTheme`, `IRawThemeSetting`) | `raw_theme.dart` (shared contract) |
| `matcher.ts` | `matcher.dart` |
| `encodedTokenAttributes.ts` | `encoded_token_attributes.dart` |
| `utils.ts` | `utils.dart` |
| `debug.ts` | `debug.dart` |
| `onigLib.ts` | `onig_lib.dart` (shared contract) |
| `parseRawGrammar.ts` | `parse_raw_grammar.dart` |
| `json.ts` | `json.dart` |
| `plist.ts` | `plist.dart` |
| `rawGrammar.ts` | `raw_grammar.dart` |
| `diffStateStacks.ts` | `diff_state_stacks.dart` |
| `grammar/index.ts` | `grammar/index.dart` |
| `grammar/grammar.ts` | `grammar/grammar.dart` |
| `grammar/tokenizeString.ts` | `grammar/tokenize_string.dart` |
| `grammar/grammarDependencies.ts` | `grammar/grammar_dependencies.dart` |
| `grammar/basicScopesAttributeProvider.ts` | `grammar/basic_scopes_attribute_provider.dart` |
| (none) | `js_semantics.dart`: JavaScript behaviors upstream relies on |

Tests live in `test/ide/editor/textmate/vscode_textmate/`:

| Upstream | Dart |
| --- | --- |
| `src/tests/json.test.ts` | `json_test.dart` |
| `src/tests/matcher.test.ts` | `matcher_test.dart` |
| `src/tests/grammar.test.ts` | `grammar_test.dart` |
| `src/tests/themes.test.ts`, `themeTest.ts`, `themedTokenizer.ts` | `themes_test.dart` |
| `src/tests/tokenization.test.ts` | `tokenization_test.dart` |
| `src/tests/resolver.ts` | `support/resolver.dart` |
| `src/tests/onigLibs.ts` | `support/onig.dart` |
| `test-cases/{first-mate,suite1,themes}` | `fixtures/` |

`fixtures/` keeps upstream's `LICENSE.md` and `ThirdPartyNotices.txt`. It omits
`themes/go` (unused by the tests), `themes/tsconfig.json` and the 2.5 MB
`themes/fixtures/test2.ts` benchmark input; the test2.ts timing test is
skipped. Run the port's tests with
`flutter test test/ide/editor/textmate/vscode_textmate/`.

## Regex engine in tests

Every test that needs a regex engine gets its `IOnigLib` from
`testOnigLib()` in `support/onig.dart`: native Oniguruma
(`lib/ide/editor/textmate/oniguruma/`), as upstream's tests run on
vscode-oniguruma. End-to-end parity with VS Code (grammar factory, theme
loader and this port together, token by token over every colorize sample of
every built-in language in every bundled theme) is
`test/ide/editor/textmate/textmate_parity_test.dart`.

## Use in the editor

The IDE editor runs this port only in its TextMate worker
(`lib/ide/editor/textmate/textmate_worker.dart`), a background isolate. The
UI isolate gets binary tokens and never calls into it. One `Registry` holds
every bundled grammar and the editor's theme. Lines go through
`grammar.tokenizeLine2(line, state, 500)`, as VS Code's
`TextMateTokenizationSupport` calls it, with VS Code's line-length limit in
front. The Monaco port's PORTING.md ("TextMate highlighting in the editor")
maps that loop to its upstream files and lists how it deviates; none
changes tokens. `test/ide/editor/textmate/textmate_syntax_test.dart` checks
that the worker gives every colorize sample VS Code's tokens in the
editor's theme.

## Dart API adaptations

- Upstream interfaces over JSON objects stay JSON-shaped. `IRawGrammar`,
  `IRawRepository`, `IRawRule`, `IRawCaptures` and `ILocation` are extension
  types over the decoded `Map<String, Object?>`; wrap a decoded map with
  `IRawGrammar(map)`. The grammar code reads them with JavaScript semantics
  and only mutates its own deep copy (`initGrammar`): rule ids are written to
  the copy's rule maps under `id` (an `Expando` for non-map rules), and
  `$self`/`$base` are added to the copy's repository.
- `RegistryOptions` is a class with a const constructor; `loadGrammar`
  returns `Future<IRawGrammar?>`. `IEmbeddedLanguagesMap` and
  `ITokenTypeMap` are `Map<String, int>` typedefs. `IToken`,
  `ITokenizeLineResult` (with `fonts`), `ITokenizeLineResult2` (tokens as
  `Uint32List`) and `IGrammarConfiguration` are classes. `StateStack` has no
  `_stackElementBrand`; `INITIAL` is a `final`.
- Enum-like constants use Dart names: `FontStyle.notSet/none/italic/bold/
  underline/strikethrough`, `StandardTokenType.other/comment/string/regEx`,
  `OptionalStandardTokenType.notSet`. Bit values are upstream's.
- `main.dart` also exports `EncodedTokenAttributes`, `StandardTokenType`,
  `OptionalStandardTokenType`, `FontStyle`, the raw theme types,
  `IRawThemeSettingStyleWithFont`, all raw grammar types, and
  `StateStackFrame`/`AttributedScopeStackFrame` (used by `StackDiff`).
- Renames where TypeScript allows what Dart does not: static
  `ScopeStack.push(path, names)` is `ScopeStack.pushAll`,
  `ScopeStack.from(...segments)` takes a `List`, `ScopeStack.extends` is
  `extendsStack`, static `AttributedScopeStack.equals(a, b)` is
  `equalsStacks`, `FontAttribute.with` is `withStyle`, `_tokenizeString` is
  `tokenizeStringImpl`, `IRawRule.while` is `$while`, and
  `this.constructor.name` is `Rule.debugClassName`. Intersection types become
  `IRuleRegistryAndOnigLib` and `IGrammarRepositoryAndThemeProvider`.
  `getRule` returns `Rule?`.
- `raw_theme.dart` (shared contract) has no font fields, which 9.3.2 reads for
  `fonts`/`IFontInfo`. `theme.dart` adds `IRawThemeSettingStyleWithFont`
  (`fontFamily`, `fontSize`, `lineHeight`); plain `IRawThemeSettingStyle`
  values behave as upstream settings without those keys. Token colors do not
  depend on it.
- The contract types `IRawThemeSetting.settings` as required and
  `IRawTheme.settings` as a list. Upstream skips entries without `settings`;
  loaders should drop them, which shifts `ParsedThemeRule.index` but keeps the
  relative order that sorting uses. A truthy non-object `settings` value
  cannot be represented.
- `debug.dart`: `DebugFlags.inDebugMode` starts false (upstream reads
  `VSCODE_TEXTMATE_DEBUG`). It only makes `parseRawGrammar` record
  `$vscodeTextmateLocation`; debug logging is omitted.
  `useOnigurumaFindOptions` is `const false`, as upstream.
- `performance.now()` and `Date.now()` become `Stopwatch`; `timeLimit` is in
  milliseconds. The time check skips the stopwatch when `timeLimit` is 0.

## Behavior notes

- `js_semantics.dart` reproduces what upstream gets from JavaScript:
  truthiness, clamping `substring`/`substr`, `''.split(sep) == ['']`, `trim`
  without U+0085, `parseInt`/`parseFloat`, `String()` of JSON values, object
  key order (array-index keys first, ascending) for every `for…in`/
  `Object.keys`, property reads that throw on null, and V8's TimSort for
  `Array.prototype.sort`, so comparators such as `_cmpBySpecificity` order
  rules exactly as in VS Code.
- `clone` turns null (JavaScript `typeof null === 'object'`) and non-JSON
  objects (plist dates) into empty maps, as upstream does.
- Capture indices are sliced with JavaScript clamping, so the unmatched-group
  offsets vscode-oniguruma reports (`0xFFFFFFFF` on ASCII lines, the line
  length otherwise) give empty strings.
- A non-string regex value reaches the scanner as the empty pattern (what
  vscode-oniguruma compiles for it); a non-empty array throws where upstream's
  `charAt` call does. A non-string `name`/`contentName` throws a typed error
  where upstream would put the value into scope names. `IRawGrammar.scopeName`
  must be a string.
- `Object.prototype` members are not modeled: keys such as `__proto__` or
  `constructor` behave as ordinary keys (upstream can read inherited
  properties for them).
- `jsonDecode` yields `int` for integer literals where JavaScript has doubles;
  `parseJSON` yields doubles. Values compare and stringify the same.
- `parseRawGrammar` throws `FormatException` when the file's root is not an
  object (upstream returns the value unchecked).
- `plist.dart`: `<date>` becomes a `DateTime`, or `InvalidPlistDate` where
  JavaScript's `Date` would be invalid; Dart's parser accepts fewer formats.
  `<integer>` is an `int` (a double beyond 2^53).
- `ColorMap.getColorMap` fills the unset index 0 with `''` where upstream
  returns a sparse array.
  A color map given to `Registry`/`setTheme`/`ColorMap` is `List<String?>`:
  a null entry is a hole, as index 0 of VS Code's `tokenColorMap` is, and
  names no color.
- `${n:/upcase}`/`${n:/downcase}` use Dart's `toUpperCase`/`toLowerCase`,
  which may differ from JavaScript's for a few special-casing characters.
- `FontAttribute` cache keys print doubles such as `3.0` differently from
  JavaScript; only cache sharing is affected, not values.
