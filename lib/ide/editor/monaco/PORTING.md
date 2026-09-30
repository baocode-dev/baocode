# Monaco editor core port

This is an incremental Dart port of Monaco Editor **v0.57.0** at commit
`d61824269f1377111d34306e4a47172327777083`. That Monaco revision pins
VS Code to `vscodeRef` `6a598d4a13031703d483d103c1d934a36ad27971`.
The authoritative sources for the core types are the **VS Code** files at that
revision, not the Monaco repository's generated bundles:

| Upstream VS Code path | Dart path |
| --- | --- |
| `src/vs/editor/common/core/position.ts` | `vs/editor/common/core/position.dart` |
| `src/vs/editor/common/core/range.ts` | `vs/editor/common/core/range.dart` |
| `src/vs/editor/common/core/selection.ts` | `vs/editor/common/core/selection.dart` |
| `src/vs/editor/common/core/editOperation.ts` | `vs/editor/common/core/edit_operation.dart` |
| `src/vs/editor/common/core/edits/textEdit.ts` (subset) | `vs/editor/common/core/edits/text_edit.dart` |
| `src/vs/editor/common/core/textChange.ts` | `vs/editor/common/core/text_change.dart` |
| `src/vs/editor/common/core/misc/eolCounter.ts` | `vs/editor/common/core/misc/eol_counter.dart` |
| `src/vs/editor/common/core/cursorColumns.ts` | `vs/editor/common/core/cursor_columns.dart` |
| `src/vs/editor/common/tokens/lineTokens.ts` | `vs/editor/common/tokens/line_tokens.dart` |
| `src/vs/editor/common/encodedTokenAttributes.ts` | `vs/editor/common/encoded_token_attributes.dart` |
| `src/vs/base/common/strings.ts` (cursor-related helpers) | `vs/base/common/strings_cursor.dart` |
| `src/vs/editor/common/model/pieceTreeTextBuffer/rbTreeBase.ts` | `vs/editor/common/model/piece_tree_text_buffer/rb_tree_base.dart` |
| `src/vs/editor/common/model/pieceTreeTextBuffer/pieceTreeBase.ts` | `vs/editor/common/model/piece_tree_text_buffer/piece_tree_base.dart` |
| `src/vs/editor/common/model/pieceTreeTextBuffer/pieceTreeTextBuffer.ts` | `vs/editor/common/model/piece_tree_text_buffer/piece_tree_text_buffer.dart` |
| `src/vs/editor/common/model/pieceTreeTextBuffer/pieceTreeTextBufferBuilder.ts` | `vs/editor/common/model/piece_tree_text_buffer/piece_tree_text_buffer_builder.dart` |
| `src/vs/editor/common/model/textModelSearch.ts` (subset) | `vs/editor/common/model/search/piece_tree_search.dart` |
| `src/vs/editor/common/model/intervalTree.ts` | `vs/editor/common/model/interval_tree.dart` |
| `src/vs/editor/common/model/textModel.ts` (subset) | `vs/editor/common/model/text_model.dart` |
| `src/vs/editor/common/textModelEvents.ts` (subset) | `vs/editor/common/text_model_events.dart` |
| `src/vs/editor/common/model/editStack.ts` (subset) | `vs/editor/common/model/edit_stack.dart` |
| `src/vs/platform/undoRedo/common/undoRedoService.ts` (subset) | `vs/platform/undo_redo/common/undo_redo_service.dart` |
| `src/vs/editor/common/languages/supports/tokenization.ts` | `vs/editor/common/languages/supports/tokenization.dart` |
| `src/vs/editor/common/model/prefixSumComputer.ts` | `vs/editor/common/model/prefix_sum_computer.dart` |
| `src/vs/editor/common/cursor/cursorAtomicMoveOperations.ts` | `vs/editor/common/cursor/cursor_atomic_move_operations.dart` |
| `src/vs/editor/common/viewLayout/{lineHeights,linesLayout}.ts` | `vs/editor/common/view_layout/` |
| `src/vs/editor/common/diff/{rangeMapping,defaultLinesDiffComputer/*}.ts` (subset) | `vs/editor/common/diff/` |
| `src/vs/editor/standalone/common/monarch/{monarchTypes,monarchCommon,monarchCompile,monarchLexer}.ts` | `vs/editor/standalone/common/monarch/` |
| `src/vs/editor/common/commands/{replaceCommand,surroundSelectionCommand,trimTrailingWhitespaceCommand,shiftCommand}.ts` (subsets) | `vs/editor/common/commands/` |
| `src/vs/editor/contrib/find/browser/replacePattern.ts` | `vs/editor/contrib/find/browser/replace_pattern.dart` |
| `src/vs/base/common/json.ts` (scanner, `visit`, `parse`, `getNodeType`) | `vs/base/common/json.dart` |
| `src/vs/base/common/jsonErrorMessages.ts` | `vs/base/common/json_error_messages.dart` |
| `src/vs/base/common/color.ts` (subset: `RGBA`, `Color`, CSS hex format/parse) | `vs/base/common/color.dart` |
| `src/vs/platform/theme/common/theme.ts` | `vs/platform/theme/common/theme.dart` |
| `src/vs/workbench/services/themes/common/workbenchThemeService.ts` (subset) | `vs/workbench/services/themes/common/workbench_theme_service.dart` |
| `src/vs/workbench/services/themes/common/themeCompatibility.ts` | `vs/workbench/services/themes/common/theme_compatibility.dart` |
| `src/vs/workbench/services/themes/common/plistParser.ts` (`parse`) | `vs/workbench/services/themes/common/plist_parser.dart` |
| `src/vs/workbench/services/themes/common/colorThemeData.ts` (subset) | `vs/workbench/services/themes/common/color_theme_data.dart` |
| `src/vs/workbench/services/textMate/common/TMGrammars.ts` (subset) | `vs/workbench/services/text_mate/common/tm_grammars.dart` |
| `src/vs/workbench/services/textMate/common/TMScopeRegistry.ts` | `vs/workbench/services/text_mate/common/tm_scope_registry.dart` |
| `src/vs/workbench/services/textMate/common/TMGrammarFactory.ts` | `vs/workbench/services/text_mate/common/tm_grammar_factory.dart` |
| `src/vs/workbench/services/textMate/browser/textMateTokenizationFeatureImpl.ts` (subset) | `vs/workbench/services/text_mate/browser/text_mate_tokenization_feature_impl.dart` |
| `src/vs/editor/test/common/core/range.test.ts` | `test/ide/editor/monaco/vs/editor/common/core/range_test.dart` |
| `src/vs/base/test/common/json.test.ts` | `test/ide/editor/textmate/workbench/json_test.dart` |

`Position`, `Range`, `Selection`, the `EditOperation` factories, `TextChange`,
and the EOL counter are ported editor-core primitives. Dart tests live in
`test/ide/editor/monaco/vs/editor/common/core/`; the Range tests mirror the
upstream test file, while the other tests cover cases derived from the pinned
TypeScript implementations. The piece-tree buffer, builder, and red-black tree
are also partially ported. The base tree shares an append-only change buffer
for short edits; large inserts use immutable chunks. Search has an adapted
standalone piece-tree service, but the optimized node-level search path is
missing. A separate `TextModel` subset supports editing, versions, events and
basic decorations. It can opt into a single-resource `EditStack`/undo service,
but it is not wired to the app's raw-file boundary. Bound history deliberately
keeps EOL changes in separate entries and clears resource history on disposal;
upstream groups EOL into an open entry and delegates detachment to ModelService. View-model,
rendering, accessibility, provider services and extension APIs remain partial
or absent. Continue against the pinned revision, recording source/test
provenance and behavior differences for each addition. Source-derived code is
covered by the pinned VS Code MIT license in [LICENSE.txt](LICENSE.txt).

Dart API adaptations:

- Coordinates are integral and one-based (`lineNumber` and `column`); Dart
  `int` replaces upstream TypeScript `number`. `Position.delta` clamps each
  coordinate to at least 1, as upstream does.
- Upstream `Position.with` is `withPosition` because `with` is a Dart keyword.
  Where TypeScript provides static and instance methods with the same name,
  the Dart static method is renamed (for example `Position.equalsPositions`,
  `Range.containsPositionInRange`, `Range.intersectTwoRanges`,
  `Range.plusRanges`, `Range.equalsRanges`, `Range.startPositionOf` and
  `Range.endPositionOf`). Consult the Dart declarations for other names.
- Upstream `isIPosition`/`isIRange` inspect structural objects; Dart accepts
  typed interface implementations or maps with numeric coordinate fields.
  `toJson()` returns a coordinate map in place of TypeScript `toJSON()`.
  Neither method validates that a position is within a particular document.
- `CursorColumns` uses the pinned upstream grapheme/width approximations; they
  are not a general-purpose Unicode grapheme implementation. The piece-tree
  factory returns a buffer directly, and its content-change notifications use
  subscribe/unsubscribe callbacks instead of the upstream event object.
- The Flutter boundary is `flutter/selection_adapter.dart`, used by
  `lib/ide/ide_editor.dart`: Monaco-style `Position`/`Selection` represent
  logical line/column coordinates, while Flutter `TextSelection` uses zero-based
  UTF-16 offsets. `flutter/document_snapshot.dart` indexes line starts for
  repeated O(log lineCount) caret lookup. These Flutter adapters are not ports
  of the Monaco text model; they preserve selection direction and use the
  current raw document text without normalizing line endings.
- `flutter/editor_document_model.dart` wraps the tree with per-document edit
  history and a saved-text baseline. It preserves decoded BOM and mixed EOL,
  avoiding the upstream buffer's normalization of inverse edits where that
  would change raw file contents. `IdeWorkspace` uses it as each document's
  text/saved-text backing store; the existing Flutter `TextField` still owns
  platform input and its editing undo. External full-value TextField updates
  invalidate the bridge's own undo history to avoid competing histories. This
  is an app bridge, **not** a port of `TextModel` or its undo/redo service.
  `findMatches` and directional find call the adapted piece-tree search service.
  The app's find bar supports replacement through the source-derived find
  pattern parser; this UI remains a subset of Monaco's full FindController.
- `flutter/viewport_layout.dart` uses Flutter `TextPainter` for caret, hit-test,
  selection, wrapping, and visible-row geometry. Identical logical lines share
  shaped paragraphs, and compatible shapes survive edits. It still traverses
  every line to compute exact row positions; the initial layout of all-distinct
  lines is eager, and Monaco tab-stop rendering is absent.

Next boundaries: connect and complete the separate `TextModel`, edit stack,
decorations and undo service at the app boundary without losing raw-file content;
optimize piece-tree search; and extend cursor/command contracts, view model,
language services, diff editor, standalone API, and browser-to-Flutter
input/rendering/accessibility adapters. A geometry helper or isolated command subset does not count as a port
of those systems. The custom
Flutter editor surface remains experimental; do not remove the `TextField`
fallback until IME, native menus, selection, undo, accessibility, and large-file
regressions have platform coverage. The separate search and text-command
subsets under `vs/editor/common/model/search/` and `vs/editor/common/commands/`
currently adapt upstream behavior but do not implement their full APIs.

The test fixtures in `test/ide/editor/monaco/vs/editor/common/core/` mirror
upstream Range cases and cover extra ported behavior. Run the port's tests with
`flutter test test/ide/editor/monaco/` and verify the app with `flutter test`.
The reference source can be checked out outside the repository at the pinned
`vscodeRef`; do not commit the complete VS Code checkout or minified bundles.
`tool/generate_monaco_core_fixtures.mjs` runs the pinned upstream Position,
Range, and Selection TypeScript under Node 22's type transformer to regenerate
`test/fixtures/monaco/core.json`; `upstream_parity_test.dart` compares the Dart
results against these fixtures (including signed 32-bit comparison cases).
`tool/generate_monaco_languages.mjs` executes the pinned Monaco v0.57.0
language definitions and serializes **86** named grammar variants (including
FreeMarker variants and regex patterns) plus **89** registrations with upstream
filenames/extensions/aliases into `assets/monaco/languages/`. The Flutter
resolver matches filenames, extensions and first-line patterns; the syntax
service passes the document's first line for extensionless files. MIME/alias
priority and language-provider registration are still pending.
`assets/monaco/LICENSE.txt` retains the Monaco source license. The Flutter
`MonacoLanguageAssets` loader revives patterns, validates registrations and
revisions, and `MonacoSyntaxService` runs the pinned Monarch compiler/lexer
across document lines. `tool/generate_monaco_themes.mjs` exports Monaco's
four built-in theme rule sets; the ported `TokenTheme` supplies colors and
font styles to the **opt-in** Flutter surface. Tokenization reuses unchanged
prefix lines and suffix lines once the lexical state converges; an edit can
still require retokenizing the rest of the document. The view reuses compatible
shaped paragraphs but recomputes all row positions after an edit. Semantic
tokens, language workers, provider services and a fully incremental view are
still absent.

## 2026-09-29 additions

Ported (VS Code `6a598d4a…`, headers in each file record deviations):

- `cursor/{cursorCommon,cursorWordOperations,cursorTypeOperations,cursorDeleteOperations,cursorColumnSelection}.ts`,
  `core/wordCharacterClassifier.ts`, `model/indentationGuesser.ts` (upstream tests ported),
  `languages/{languageConfiguration,languageConfigurationRegistry (resolved subset),autoIndent,enterAction}`,
  `languages/supports/{characterPair,onEnter,indentRules}`, extended `commands/shiftCommand.ts`.
- `contrib/comment/browser/{lineCommentCommand,blockCommentCommand}.ts`,
  `contrib/linesOperations/browser` (move/copy/delete/expand lines),
  `contrib/multicursor/browser` (session + next match), `contrib/folding/browser/{foldingRanges,indentRangeProvider}.ts`.

Flutter adaptations (not ports): `flutter/editor_keybindings.dart` (platform
keybindings, macOS selectors, `runEditorCommand`/`editorCommandLabels` for the
palette), `language_configuration_assets.dart` (asset `configuration` →
`LanguageConfiguration`), `editor_folding.dart` (fold state shifted by line
delta, not decorations), `viewport_layout.dart` (virtualized when not wrapping),
`editor_decorations.dart`, `editor_view_theme.dart`, `bracket_matching.dart`
(token-agnostic, 2000-line window), `editor_scrollbar.dart`, `editor_minimap.dart`,
`editor_view_painters.dart`. `monaco_syntax.dart` time-slices and cancels
tokenization and builds spans lazily per painted line.

Known deviations: string/comment context for auto-closing is a line scan, not
tokens; overlapping edits from multiple cursors drop the later edit; multi-line
platform input bypasses the typing path; auto-closed pairs and decorations are
tracked by offset; inserted newlines use the document's dominant EOL.

## Language servers (LSP, 2026-09-29)

Ported from VS Code `6a598d4a…` (MIT header, upstream path and deviations in
each file):

- `base/common/filters.ts` → `vs/base/common/filters.dart` (fuzzyScore and
  helpers used by suggest; upstream tests ported).
- `contrib/snippet/browser/{snippetParser,snippetSession}.ts` (parser with
  upstream tests; the session keeps tabstops, mirrors and choices on the
  controller; nested snippets are not merged into a running session).
- `contrib/suggest/browser/completionModel.ts` (filtering/scoring/sorting;
  no word-distance ranking, insert mode only).
- `contrib/codeAction/common/types.ts` (kinds, filters, ordering).
- `contrib/gotoError/browser/markerNavigation.ts` (next/previous across files).

Flutter adaptations in `lib/ide/lsp_ui/` (not ports): the per-editor
`EditorLanguageSession` (debounced, version-checked requests; hover, links,
lightbulb, signature help, suggest), suggest/hover/signature/rename/code action
widgets, the Problems and References panels, Outline, breadcrumbs symbols,
semantic token overlay (Dark Modern semantic colors), language status items,
minimal-edit formatting (line diff → one undo step keeping cursors) and
workspace edit application. Rename edits to unopened files open them as dirty
tabs; resource operations are refused. References go to a panel, not a peek.

Client (`lib/ide/lsp/`, Monad code, not VS Code): `json_rpc.dart`,
`lsp_client.dart`, `lsp_manager.dart`, `lsp_process*.dart`, `lsp_glob.dart`;
contracts `lsp_protocol.dart`, `lsp_server_definition.dart`,
`language_features.dart`. `EditorDocumentModel.changes` emits LSP-ordered
content changes (CR/LF pairs are never split). Not advertised: pull
diagnostics, semantic token ranges/deltas, resource operations, `showDocument`,
completion `data`/`commitCharacters` item defaults.

Catalog and installer:

- `node tool/generate_lsp_languages.mjs [helix-checkout|languages.toml]
  [out-dir] [--mason registry.json(.zip)]` writes `assets/lsp/languages.json`
  from Helix `languages.toml` at `ba40e547426b0f9896c8bdc699a4ab11f2b37dbc`
  (MPL-2.0, `assets/lsp/LICENSE-helix`). Helix `config` is sent as
  `initializationOptions` and answers `workspace/configuration`. Per-language
  `only-features`/`except-features` become derived server ids
  (`id#except=…`). Matching: file name, glob, longest extension, shebang,
  then a pack's `firstLine`.
- `node tool/generate_mason_registry.mjs [registry.json(.zip)] [out-dir]`
  writes `assets/lsp/mason-registry.json` from mason-registry
  `2026-09-29-glass-hat` (`27cabd46dfb4e97187a4619d7de966589e3945f7`,
  Apache-2.0, `assets/lsp/LICENSE-mason-registry`). Run it after the
  languages script; without arguments both fetch the pinned inputs into /tmp.
- `MasonServerProvider` installs github releases (per-platform assets),
  npm, pypi (venv), golang and cargo packages into
  `AppPaths.dataDir/servers/`, staged then renamed. opam, nuget, luarocks,
  composer, gem, openvsx and build-from-source packages are not installable;
  `version_overrides` are ignored. zip/tar/tar.gz/gz unpack in Dart;
  `.tar.xz/.bz2/.zst` use the system `tar`.
- User overrides: `AppPaths.dataDir/lsp.json`; language packs:
  `AppPaths.dataDir/language-packs/<name>/` (`manifest.json`, Monarch
  `grammar.json`, `configuration.json`, optional `server.json`), documented in
  `lib/ide/lsp/packs/README.md`.

## Workbench hover and codicons (2026-09-30)

- `lib/ide/ide_hover.dart` adapts `src/vs/platform/hover/browser/{hover.ts,
  hover.css,hoverWidget.ts}` and `base/browser/ui/hover/hoverWidget.css`
  (Dark 2026 colors since the Modern UI update below, compact 12px, `workbench.hover.delay` 1500/500 ms,
  pointer for the activity and status bars) over Flutter's `RawTooltip`.
  Deviations: instant re-show while another hover is still up rather than
  within 200 ms of a hide; hides 100 ms after the pointer leaves; pointer
  hovers do not flip sides; no hover actions/status row.
- `tool/generate_codicons.mjs` bundles `@vscode/codicons@0.0.46-40` (pinned by
  the VS Code checkout's package-lock) as `assets/codicons/codicon.ttf` with
  `lib/theme/codicons.dart` generated from `codiconsLibrary.ts`/`codicons.ts`.
  Completion/symbol icons follow `CompletionItemKinds`/`SymbolKinds.toIcon`
  and `symbolIcons.ts` colors; code action groups follow `codeActionMenu.ts`.

## Modern UI and editor hover markdown (2026-09-30)

- `lib/ide/ide_modern_ui.dart` ports the default-density Modern UI layout
  (`browser/media/floatingPanels.css`, `contrib/modernUI/browser/media/
  {activityBar,editorBorder,sashHandles}.css`, `activitybarPart.ts` floating
  sizes, `baseSizes.ts` tokens) with Dark 2026 colors (`2026-dark.json`).
  Deviations: no compact density; activity bar on the left only.
- `lib/ide/lsp_ui/hover_markdown.dart` renders hover/signature/suggest
  markdown like `.monaco-hover` (`hoverWidget.css`, `hover.css`,
  `hoverContribution.ts`); fenced code goes through
  `MonacoSyntaxService.colorize` like `EditorMarkdownCodeBlockRenderer`
  (fence language via `getLanguageIdByLanguageName`, else the editor's).
  Deviations: no hover status bar row; tables and HTML shown as text; only
  http(s)/mailto links open.

## TextMate assets, fixtures and color themes (2026-09-30)

- `tool/generate_textmate_assets.mjs` copies, at the pinned revision, the
  `typescript-basics` grammars and language configuration, the `jsx-tags`
  registration (`extensions/javascript`), and the `theme-defaults`, Monokai,
  Monokai Dimmed, Solarized, Abyss, Kimbie Dark, Quiet Light, Red and Tomorrow
  Night Blue themes (with their `include` chains) into `assets/textmate/`,
  with `manifest.json` (the `contributes` entries, labels localized) and
  `LICENSE.txt` (VS Code MIT plus the grammar/theme notices).
  `lib/ide/editor/textmate/textmate_manifest.dart` models the manifest.
- `tool/generate_textmate_fixtures.mjs` runs vscode-textmate 9.3.2 and
  vscode-oniguruma 1.7.0 the way `TMGrammarFactory` and
  `textMateTokenizationFeatureImpl.ts` do, with the themes converted by the
  upstream theme code, and writes `test/fixtures/textmate/`: the colorize
  samples, `typescript_tokens.json` (decoded tokens per sample and theme,
  scopes, a `textModel.ts` benchmark) and `themes/<id>.json` (each theme's
  IRawTheme and token color map). It cross-checks scopes and colors against
  `extensions/vscode-colorize-tests/test/colorize-results`.
- The theme loader ports read files through a
  `Future<String> Function(String path)` reader instead of URIs and cover a
  theme's defaults only: no user customizations, transient colors, semantic
  token styling or font index. `colors` keeps the theme's strings;
  `getColor` applies `Color.fromHex`. `toRawTheme` drops a rule's font
  family, size and line height, which `IRawThemeSettingStyle` cannot hold.
  `test/ide/editor/textmate/workbench/` checks every bundled theme against
  its fixture.
