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
| `src/vs/base/common/color.ts` (see "Color registry") | `vs/base/common/color.dart` |
| `src/vs/platform/theme/common/theme.ts` | `vs/platform/theme/common/theme.dart` |
| `src/vs/workbench/services/themes/common/workbenchThemeService.ts` (subset) | `vs/workbench/services/themes/common/workbench_theme_service.dart` |
| `src/vs/workbench/services/themes/common/themeCompatibility.ts` | `vs/workbench/services/themes/common/theme_compatibility.dart` |
| `src/vs/workbench/services/themes/common/plistParser.ts` (`parse`) | `vs/workbench/services/themes/common/plist_parser.dart` |
| `src/vs/workbench/services/themes/common/colorThemeData.ts` (subset) | `vs/workbench/services/themes/common/color_theme_data.dart` |
| `src/vs/workbench/services/textMate/common/TMGrammars.ts` (subset) | `vs/workbench/services/text_mate/common/tm_grammars.dart` |
| `src/vs/workbench/services/textMate/common/TMScopeRegistry.ts` | `vs/workbench/services/text_mate/common/tm_scope_registry.dart` |
| `src/vs/workbench/services/textMate/common/TMGrammarFactory.ts` | `vs/workbench/services/text_mate/common/tm_grammar_factory.dart` |
| `src/vs/workbench/services/textMate/browser/textMateTokenizationFeatureImpl.ts` (subset) | `vs/workbench/services/text_mate/browser/text_mate_tokenization_feature_impl.dart` |
| `src/vs/editor/test/common/core/range.test.ts` | `test/monaco/vs/editor/common/core/range_test.dart` |
| `src/vs/base/test/common/json.test.ts` | `test/textmate/workbench/json_test.dart` |

`Position`, `Range`, `Selection`, the `EditOperation` factories, `TextChange`,
and the EOL counter are ported editor-core primitives. Dart tests live in
`test/monaco/vs/editor/common/core/`; the Range tests mirror the
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
  `../../lib/ide/ide_editor.dart`: Monaco-style `Position`/`Selection` represent
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

The test fixtures in `test/monaco/vs/editor/common/core/` mirror
upstream Range cases and cover extra ported behavior. Run the port's tests with
`flutter test test/monaco/` and verify the app with `flutter test`.
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

Flutter adaptations in `../../lib/ide/lsp_ui/` (not ports): the per-editor
`EditorLanguageSession` (debounced, version-checked requests; hover, links,
lightbulb, signature help, suggest), suggest/hover/signature/rename/code action
widgets, the Problems and References panels, Outline, breadcrumbs symbols,
semantic token overlay (Dark Modern semantic colors), language status items,
minimal-edit formatting (line diff → one undo step keeping cursors) and
workspace edit application. Rename edits to unopened files open them as dirty
tabs; resource operations are refused. References go to a panel, not a peek.

Client (`../../lib/ide/lsp/`, BaoCode code, not VS Code): `json_rpc.dart`,
`lsp_client.dart`, `lsp_manager.dart`, `lsp_process*.dart`, `lsp_glob.dart`;
contracts `lsp_protocol.dart`, `lsp_server_definition.dart`,
`language_features.dart`. `EditorDocumentModel.changes` emits LSP-ordered
content changes (CR/LF pairs are never split). Not advertised: pull
diagnostics, semantic token ranges/deltas, resource operations, `showDocument`,
completion `data`/`commitCharacters` item defaults.

Catalog and installer:

- `node ../../tool/generate_lsp_languages.mjs [helix-checkout|languages.toml]
  [out-dir] [--mason registry.json(.zip)]` writes `../../assets/lsp/languages.json`
  from Helix `languages.toml` at `ba40e547426b0f9896c8bdc699a4ab11f2b37dbc`
  (MPL-2.0, `../../assets/lsp/LICENSE-helix`). Helix `config` is sent as
  `initializationOptions` and answers `workspace/configuration`. Per-language
  `only-features`/`except-features` become derived server ids
  (`id#except=…`). Matching: file name, glob, longest extension, shebang,
  then a pack's `firstLine`.
- `node ../../tool/generate_mason_registry.mjs [registry.json(.zip)] [out-dir]`
  writes `../../assets/lsp/mason-registry.json` from mason-registry
  `2026-09-29-glass-hat` (`27cabd46dfb4e97187a4619d7de966589e3945f7`,
  Apache-2.0, `../../assets/lsp/LICENSE-mason-registry`). Run it after the
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
  `../../lib/ide/lsp/packs/README.md`.

## Workbench hover and codicons (2026-09-30)

- `../../lib/ide/ide_hover.dart` adapts `src/vs/platform/hover/browser/{hover.ts,
  hover.css,hoverWidget.ts}` and `base/browser/ui/hover/hoverWidget.css`
  (Dark 2026 colors since the Modern UI update below, compact 12px, `workbench.hover.delay` 1500/500 ms,
  pointer for the activity and status bars) over Flutter's `RawTooltip`.
  Deviations: instant re-show while another hover is still up rather than
  within 200 ms of a hide; hides 100 ms after the pointer leaves; pointer
  hovers do not flip sides; no hover actions/status row.
- `IdeHover.followMouse` is the `mouse` hover delegate (labels' and list
  rows' titles, `getDefaultHoverDelegate('mouse')`): below the target from
  10px right of the pointer (`setupManagedHover`, `hoverWidget.ts`
  `computeXCordinate`/`computeYCordinate`). An explorer row's title is its
  path, tildified (`labels.ts` `tildify`, in
  `vs/base/common/labels.dart`), then its decoration's, as
  `ResourceLabel` builds it. Every other tooltip, in the IDE and the chat,
  is this hover (no Material `Tooltip`); the chat's `HoverTooltip` keeps its
  own timing and selectable text in the same box (`IdeHoverBox`).
- `../../tool/generate_codicons.mjs` bundles `@vscode/codicons@0.0.46-40` (pinned by
  the VS Code checkout's package-lock) as `../../assets/codicons/codicon.ttf` with
  `../../lib/theme/codicons.dart` generated from `codiconsLibrary.ts`/`codicons.ts`.
  Completion/symbol icons follow `CompletionItemKinds`/`SymbolKinds.toIcon`
  and `symbolIcons.ts` colors; code action groups follow `codeActionMenu.ts`.

## Workbench layout (2026-09-30)

- `../../lib/ide/ide_columns.dart` sizes the side bar, editor and chat as the
  grid's `splitview.ts` does. Deviation: a view snaps shut a sixth of its
  minimum past it (upstream: half), for the view dragged and the one
  pushed; the panel's rows keep upstream's half.
- The chat's sash, past the side bar's snapping and the editor's minimum by
  a sixth of it, snaps the editor shut: the chat is maximized (upstream's
  `setAuxiliaryBarMaximized`, reached by a command there). As upstream,
  showing the side bar, hiding the chat or opening an editor
  (`showEditorIfHidden`) ends it; also dragging the sash back, which keeps
  the pointer, and the sash's double click. Deviation: the panel stays,
  below the chat (`IdeRows.minChat` 160), where upstream hides it.
- Deviation: VS Code's window is wide enough for all its parts; here a
  window too narrow for the side bar and the chat both hides the side bar
  (`IdeLayout.sidebarVisible`), and either opened by the user
  (`IdeLayout.showSidebar`/`showChat`) hides the editor instead
  (`IdeLayout.editorHidden`: the two side by side, the panel below both),
  or, with too little room even for the two, closes the other. Hiding
  either or opening an editor brings the editor back. With the chat
  hidden, the side bar shares too little room with the editor by their
  minimums, as the chat does.
- `../../lib/workspace/title_bar_double_click.dart`: on macOS a double click on a
  title bar's empty part does what `AppleActionOnDoubleClick` says, as
  Electron's `-[NativeWidgetMacNSWindow sendEvent:]` does in VS Code's
  `.titlebar-drag-region`; controls, `TitleBarControls` groups included,
  are `no-drag`. Deviations: any hit widget (a `Text`) is not empty; the
  clicks are timed by `kDoubleTapTimeout`, not the system's setting.

## Source Control action button (2026-10-01)

- `../../lib/ide/git/ide_scm_view.dart` picks the button below the commit
  message as the Git extension's `actionButton.ts` does: Commit while
  `repositoryHasChangesToCommit` (staged changes, or others where the
  smart commit would stage them or offer to), else Publish Branch (a
  branch without an upstream), else Sync Changes (ahead of the upstream
  or behind it, `Sync Changes 1↓ 2↑`), else Commit, disabled; the icon
  spins (`sync~spin`, 1.5s in 30 steps) while it syncs.
- Sync Changes asks first (`git.confirmSync`), then pulls
  (`git pull --tags remote branch`) and pushes (`git push remote
  branch:upstream`) if the branch was ahead, as `Repository._sync` does;
  Publish Branch pushes with `-u` to the only remote.
- Deviations: Don't Show Again lasts for the session; no remote providers,
  so with no remotes Publish Branch only warns (upstream offers Publish to
  GitHub); with more, a menu at the button picks the remote, where upstream
  has a quick pick with Add Remote; no fetch before pulling, rebase,
  auto-stash, tag conflict handling, read-only remotes or status bar sync
  item; and without VS Code's askpass, a remote that asks for credentials
  fails (`GIT_TERMINAL_PROMPT=0`) and is reported.

## Diff editor (2026-10-01)

- `flutter/diff_editor_model.dart`: `DiffEditorModel` computes the diff
  with `DefaultLinesDiffComputer` (`ignoreTrimWhitespace`, 5000ms), again
  200ms after either side changes (`diffEditorViewModel.ts`), on another
  isolate past 10000 lines. `computeDiffAlignments` is
  `computeRangeAlignment` (inner hunk alignment side by side);
  `computeDiffZones` is `DiffEditorViewZones` (side by side, a diagonal
  fill on the side with fewer lines; inline, the deleted code above the
  change in the modified editor and `gutter-delete` room in the
  original's); `computeDiffDecorations` is `DiffEditorDecorations`
  (`line-insert`/`line-delete` with their margin and `+`/`-` signs,
  `char-insert`/`char-delete` filling the line break and marking empty
  ranges, the whole line where the other side has none).
- `flutter/diff_editor.dart`: side by side wider than 900px
  (`renderSideBySideInlineBreakpoint`), else inline, where the original
  shows only its line numbers; the sash keeps each editor 100px wide and a
  double click puts it back in the middle; the 30px overview ruler has a
  lane per side and the viewport slider; the two editors share one scroll
  position.
- `flutter/viewport_layout.dart` and `editor_surface.dart` have view zones
  (`LinesLayout` whitespaces, `EditorViewZone`): rows lay out around them,
  arrow keys step over them, and a press in one does not move the caret;
  the gutter paints margin decorations and line decoration icons.
- `../../lib/ide/ide_workspace.dart`: diff tabs (`openDiff`) and read-only
  revision tabs (`openRevision`), keyed by path and label; a working tree
  diff tab shares its file's model with the file's tab (edits, undo, dirty
  state, saving, language server sync); revisions are read again on each
  Git status, as `git:` documents follow the repository.
- `../../lib/ide/git/git_change_editor.dart` ports `ResourceCommandResolver`'s
  `getLeftResource`, `getRightResource` and `getTitle` and
  `sanitizeRef`; `IdeGitService.show` runs `git show --textconv
  ref:path`. A click on a change, and Open Changes, open its diff
  (`a.dart (Working Tree)`, `(Index)`), or its one side
  (`(Deleted)`); Open File (HEAD) opens the left side or warns that it is
  not available.
- Deviations: no moved code, hidden unchanged regions, gutter menu or
  revert arrows, change navigation, accessible diff viewer or word wrap;
  an edit does not move the diff until it is computed again; deleted code
  is not selectable; no preview editors, so a click opens a lasting tab;
  a change with only its file (untracked, both modified) opens the file's
  own tab without the label; one with neither side (added by us or them),
  where upstream's command fails, opens its file; a revision Git cannot
  read shows as empty, where upstream reports the file not found; the
  Graph's and the Timeline's files still open the file.

## Modern UI and editor hover markdown (2026-09-30)

- `../../lib/ide/ide_modern_ui.dart` ports the default-density Modern UI layout
  (`browser/media/floatingPanels.css`, `contrib/modernUI/browser/media/
  {activityBar,editorBorder,sashHandles}.css`, `activitybarPart.ts` floating
  sizes, `baseSizes.ts` tokens) in the color theme's colors (see "Workbench
  color theme"). Deviations: no compact density; activity bar on the left
  only.
- `../../lib/ide/lsp_ui/hover_markdown.dart` renders hover/signature/suggest
  markdown like `.monaco-hover` (`hoverWidget.css`, `hover.css`,
  `hoverContribution.ts`); fenced code goes through
  `MonacoSyntaxService.colorize` like `EditorMarkdownCodeBlockRenderer`
  (fence language via `getLanguageIdByLanguageName`, else the editor's).
  Deviations: no hover status bar row; tables and HTML shown as text; only
  http(s)/mailto links open.

## TextMate assets, fixtures and color themes (2026-09-30)

- `tool/generate_textmate_assets.mjs` copies, at the pinned revision, every
  built-in extension the product build ships into `assets/textmate/`: all
  `extensions/*` folders with a package.json, minus `excludedExtensions` in
  `build/lib/extensions.ts` (the API, colorize and resolver test extensions,
  the node-debug pair) and product.json `builtInExtensions` (marketplace
  downloads). `copilot` is excluded there but ships through its own VSIX
  step (`packageCopilotExtensionStream`, `downloadCopilotVsix.ts`), so it is
  kept. Of each it takes every `contributes.grammars` and
  `contributes.languages` field and the language configurations; `%nls%`
  strings are localized as `replaceNLStrings` does. The themes are the same
  19 as before (with their `include` chains). Grammar JSON is minified, as
  the build's `minifyExtensionResources` does; the fixture generator checks
  each still parses to the same raw grammar as the original. `LICENSE.txt`
  holds VS Code's MIT license and the ThirdPartyNotices entries of the
  copied components; each extension's `cgmanifest.json` is copied next to
  its files.
- Deviation (2026-10-08): `installedExtensions` adds marketplace extensions
  for languages VS Code has no grammar for, as if installed: Vue - Official
  (vuejs/language-tools, pinned commit, MIT, its license at the end of
  `LICENSE.txt`). They come after the built-in ones, as `extensionCmp`
  sorts installed extensions. Only their listed languages (`vue`) are
  taken, not Vue's configurations for `html`, `markdown` and `jade`, and
  their injections only into those languages' grammars: Vue's would also
  reach `text.html.derivative` (VS Code's HTML grammar), `text.pug` and
  Markdown, which then no longer match the colorize results. `manifest.json`
  records where they come from (`installedExtensions`), for the fixture
  generator's raw-grammar check; `extra/App.vue` is their parity sample.
- `manifest.json` order is VS Code's registration order: `plaintext` first
  (`modesRegistry.ts`, no `extension` key), then the extensions by folder
  name as `extensionCmp` (`extensionDescriptionRegistry.ts`) sorts them,
  each in package.json order. Language ids are the `LanguageIdCodec`
  numbering of that order (first registration wins). Deviation: the
  languages workbench contributions register in code through
  `ModesRegistry` (`Log`, `log`, `code-text-binary`, `scminput`) are not
  modeled; in VS Code they may take ids before the extension languages. Grammars keep every entry; lookups by scope or language are
  last-wins, as `TMGrammarFactory` builds its maps. `configurationDefaults`
  keeps the per-language `editor.maxTokenizationLineLength` defaults.
  `lib/textmate/textmate_manifest.dart` models the manifest.
- `tool/generate_textmate_fixtures.mjs` runs vscode-textmate 9.3.2 and
  vscode-oniguruma 1.7.0 the way `TMGrammarFactory` and
  `textMateTokenizationFeatureImpl.ts` do, with every bundled grammar
  (validated as `validateGrammarExtensionPoint` does) and the themes
  converted by the upstream theme code, and writes `test/fixtures/textmate/`:
  every colorize sample (`samples/`; `test.dart` is stored as
  `test.dart.txt` so the analyzer skips it), `tokens.json.gz` and
  `themes/<id>.json` (each theme's IRawTheme and token color map).
  `tokens.json.gz` holds, per sample, the `tokenizeLine` scopes and the
  binary tokens of the editor's line loop in all 19 themes, the language
  ids, the order grammars were first requested in (vscode-textmate keeps
  one grammar per scope name, made with the first requester's language id:
  `ini`/`properties`, `yaml`/`dockercompose`), and a `textModel.ts`
  benchmark. A sample's language is the one its colorize result's root
  scope maps to, and must equal what `getAssociationByPath` gives its file
  name. The 14 languages with a grammar but no colorize fixture (jsonc,
  jsonl, properties, dockercompose, ignore, xsl, search-result, prompt,
  instructions, chatagent, skill, markdown-math, markdown_latex_combined,
  cpp_embedded_latex) get hand-written inputs in `extra/`, tokenized the same
  way; the last three are selected by no file name, so the generator names
  their language. Scopes and the full color explanations in the 10
  `theme-defaults` themes are checked against
  `extensions/vscode-colorize-tests/test/colorize-results` as
  `themes.test.contribution.ts` computes them: no differences.
- `test/textmate/textmate_parity_test.dart` repeats all of that
  in Dart. `textmate_assets_test.dart` parses every grammar with
  `parseRawGrammar` and every language configuration with `json.dart`, and
  compares what `language_configuration_assets.dart` reads with what VS
  Code's `extractValidConfig` keeps. Known differences, not fixed there:
  `onEnterRules` `action.indent` (the key VS Code reads) is not read (11
  configurations), the `["$", ""]` surrounding pair of the JavaScript and
  TypeScript configurations is dropped (empty close), and xsl's empty
  `lineComment` reads as none.
- The theme loader ports read files through a
  `Future<String> Function(String path)` reader instead of URIs and cover a
  theme's defaults only: no user customizations, transient colors, semantic
  token styling or font index. `colors` keeps the theme's strings;
  `getColor` applies `Color.fromHex`. `toRawTheme` drops a rule's font
  family, size and line height, which `IRawThemeSettingStyle` cannot hold.
  `test/textmate/workbench/` checks every bundled theme against
  its fixture.

## Language detection (2026-09-30)

VS Code's resource-to-language mapping, ported from the pinned revision so
that `guessLanguageIdByFilepathOrFirstLine` returns what VS Code returns.

| Upstream VS Code path | Dart path |
| --- | --- |
| `src/vs/editor/common/services/languagesRegistry.ts` | `vs/editor/common/services/languages_registry.dart` |
| `src/vs/editor/common/services/languagesAssociations.ts` | `vs/editor/common/services/languages_associations.dart` |
| `src/vs/editor/common/languages/modesRegistry.ts` (core part, `PLAINTEXT_*`) and `ILanguageExtensionPoint`/`ILanguageIcon` from `language.ts` | `vs/editor/common/languages/modes_registry.dart` |
| `src/vs/base/common/glob.ts` | `vs/base/common/glob.dart` |
| `src/vs/base/common/{path,extpath,strings,uri,resources,mime,network,platform,lifecycle}.ts` (subsets) | `vs/base/common/<same name>.dart` |
| (none: JavaScript `toLowerCase`) | `vs/base/common/ecmascript_lower_case.dart` |

- Golden data: `node tool/generate_language_detection_fixtures.mjs
  [vscode-checkout] [output.json]` (Node 22; clones the pinned revision
  sparsely into `/tmp` when no checkout is given). It bundles the unmodified
  TypeScript with esbuild 0.27.2 (the `build/package.json` pin), evaluates
  it with `globalThis.vscode.process.platform` set to darwin, linux and
  win32, and writes `test/fixtures/textmate/language_detection.json`
  (registrations, 1534 cases, per-platform guesses, 1141 lookups, a 55 x 50
  glob matrix in both case modes) and `language_detection_lowercase.json`
  (JavaScript's lower-case mapping of every code point). Nothing is derived
  from the Dart code. `language_detection_golden_test.dart` replays all of
  it.
- Registrations are what the desktop product hands to `setDynamicLanguages`:
  `extensions/*/package.json` minus `excludedExtensions` (copilot,
  vscode-api-tests, vscode-colorize-tests, vscode-colorize-perf-tests,
  vscode-test-resolver, ms-vscode.node-debug, ms-vscode.node-debug2) and
  minus product.json `builtInExtensions` names
  (`build/lib/extensions.ts` `doPackageLocalExtensionsStream`); plus
  `copilot` (`packageCopilotExtensionStream`, run for every desktop package
  by `build/gulpfile.vscode.ts`); plus the product.json marketplace VSIXs
  (js-debug contributes `wat`), SHA-256 checked. Order: folder name compared
  with `<` (`extensionCmp`, extensionDescriptionRegistry.ts), then
  `contributes.languages` order (`_handleExtensionPoint`); `%key%` strings
  from package.nls.json; `isValidLanguageExtensionPoint` and the
  WorkbenchLanguageService mapping. 95 extensions give 84 entries and 76
  language ids. `plaintext` comes first through `modesRegistry`, not the
  list. Other workbench-core ModesRegistry languages (code-text-binary, Log,
  log, scminput) are not included.
- Platform: `platform.dart` reads the host from `dart:io`;
  `debugOperatingSystemOverride` switches `isWindows`/`isMacintosh`/`isLinux`
  and everything derived from them (`path.sep`, `basename`, `URI.fsPath`,
  glob separators) at any time. The glob cache is cleared on a change.
  Tests run the Windows and POSIX paths on one machine.
- Deviations (each covered by a test or the golden replay):
  - Resources are Dart `Uri`s, turned into VS Code URIs by `URI.fromUri`
    from their decoded components. `Uri.file(p)` equals upstream
    `URI.file(p)`. Dart has already removed `.`/`..` segments and
    lower-cased the scheme and host; VS Code keeps them. `Uri.parse`
    rejects `data:;label:x.ts,`: build it as
    `Uri(scheme: 'data', path: ';label:x.ts,')`.
  - Lower-casing follows JavaScript (`jsToLowerCase`, Unicode 17.0 full
    mappings) except for the context-dependent Final_Sigma rule. Case-
    insensitive glob regular expressions use Dart's `caseSensitive: false`.
  - glob's overloaded `parse`/`match` are split into `parse`/`match` and
    `parseExpression`/`matchExpression`; `matchExpression` returns `null`
    for a missing path where upstream returns `false`.
  - Events are listener callbacks. `configuration` and icon paths are
    strings. Override identifiers are not registered with the configuration
    registry. `__proto__` is not special-cased. Invalid `firstLine`
    expressions and overwrite warnings go to `dart:developer` `log`.
  - Associations, the glob cache and `modesRegistry` are library-level
    state, as upstream. Every `LanguagesRegistry` refresh clears the
    platform associations, so use one registry per app.
- Integrator notes:
  - `files.associations`: do what `WorkbenchLanguageService.updateMime` does.
    Call `clearConfiguredLanguageAssociations()`. Then, for each
    `pattern -> languageId` with a string value, call
    `registerConfiguredLanguageAssociation(ILanguageAssociation(id:
    languageId, mime: registry.getMimeType(languageId) ?? 'text/x-$languageId',
    filepattern: pattern))`. After that, re-guess open models. Configured
    associations beat all platform ones and survive `setDynamicLanguages`.
  - Priority: configured before platform. Within each: exact filename, then
    the longest `filenamePatterns` match, then the longest extension; on a
    tie the last registered wins. `firstLine` is used only when nothing
    matches the path. A match returns `[id, 'plaintext']`; no match returns
    `['unknown']`; a null resource with no first line returns `[]`.
  - Case: filenames, extensions and patterns match case-insensitively on
    every platform (the path is lower-cased).
    `getLanguageIdByLanguageName` lower-cases its input;
    `getLanguageIdByMimeType` is case-sensitive.
  - Windows: `file` URIs use `fsPath` (backslashes, lower-case drive
    letter), `basename` splits on `\` and `/`, and patterns containing `/`
    match against the full path. Build URIs with `Uri.file(path)` (the host
    style) or `Uri.file(path, windows: true)`.
  - Keep `aliases` null when absent: `aliases: []` means "no name" upstream.
    `TextMateLanguageRegistration` defaults it to `const []`, so pass `null`
    or use `ILanguageExtensionPoint.fromJson`.

## TextMate highlighting in the editor (2026-09-30)

The editor highlights with VS Code's TextMate grammars and the Dark 2026
theme; all tokenization runs in a background isolate, as VS Code runs it in
a web worker.

| Upstream VS Code path | Dart path |
| --- | --- |
| `src/vs/editor/common/tokens/contiguousTokensStore.ts` | `vs/editor/common/tokens/contiguous_tokens_store.dart` |
| `src/vs/editor/common/tokens/contiguousTokensEditing.ts` | `vs/editor/common/tokens/contiguous_tokens_editing.dart` |
| `src/vs/editor/common/model/textModelTokens.ts` (line-oriented part) | `vs/editor/common/model/text_model_tokens.dart` |
| `src/vs/editor/common/model/fixedArray.ts` | `vs/editor/common/model/fixed_array.dart` |
| `src/vs/editor/common/languages/nullTokenize.ts` (`nullTokenizeEncoded`) | `vs/editor/common/languages/null_tokenize.dart` |
| `src/vs/workbench/services/textMate/browser/tokenizationSupport/textMateTokenizationSupport.ts` | `vs/workbench/services/text_mate/browser/tokenization_support/text_mate_tokenization_support.dart` |
| `src/vs/workbench/services/textMate/browser/tokenizationSupport/tokenizationSupportWithLineLimit.ts` | `vs/workbench/services/text_mate/browser/tokenization_support/tokenization_support_with_line_limit.dart` |
| `src/vs/workbench/services/textMate/browser/backgroundTokenization/worker/textMateWorkerTokenizer.ts` | `vs/workbench/services/text_mate/browser/background_tokenization/worker/text_mate_worker_tokenizer.dart` |
| `.../backgroundTokenization/worker/textMateTokenizationWorker.worker.ts` (grammar factory, documents) | `lib/textmate/textmate_worker.dart` (`TextMateWorker`) |
| `.../backgroundTokenization/textMateWorkerTokenizerController.ts`, `textMateTokenizationFeatureImpl.ts` (registry, theme, color map) | `lib/textmate/textmate_syntax.dart` (`TextMateDocument`, `TextMateSyntax`) |

- Wiring: `IdeEditor._computeSyntax` asks `TextMateSyntax.languageIdForPath`
  first. A language pack that claims the path keeps its Monarch grammar.
  Otherwise `guessLanguageIdByFilepathOrFirstLine` picks the language, and
  TextMate highlights it when a grammar exists for it (`TMGrammarFactory.has`).
  Everything else, and every file on the web or when the native Oniguruma
  library does not load (no worker starts), goes to `MonacoSyntaxService` as
  before. Hover code blocks go through `TextMateSyntax.colorize`, which
  resolves a fence's language name or alias with
  `getLanguageIdByLanguageName`; Monarch is the fallback.
- Theme: the workbench's color theme (`WorkbenchThemeService`,
  ../../lib/theme/workbench_theme.dart). On a change the worker gets the new theme
  (`$acceptTheme`) and every document's tokens are requested again, as
  `setColorMap` resets tokenization of every model upstream; a change that
  keeps the token rules and color map only swaps the editor colors. Until
  a document's first new tokens arrive, its visible lines keep their old
  colors rather than flashing plain text.
  `editor.background`/`editor.foreground` color the editor.
  Spans follow `TokenMetadata.getClassNameFromMetadata`: foreground, plus
  italic, bold, underline and strikethrough. Token backgrounds are not
  painted, as in VS Code.
- The UI isolate never tokenizes. The worker owns the `Registry` and one
  `TextMateWorkerTokenizer` per document. Each line runs through
  `TokenizationSupportWithLineLimit(TextMateTokenizationSupport(...))`, in
  batches of more than 200 lines or 20 ms, with a 10 ms debounce after
  changes, and stops once the end states converge. The UI isolate keeps a
  `ContiguousTokensStore`; on an edit it shifts the stored tokens with
  `acceptEdit` at once and sends the changed lines. Tokens computed for an
  older version are moved past the later changes, or dropped on the lines
  those changes touched (`setTokensAndStates`). A closed document's worker
  tokenizer is disposed.
- Deviations:
  - Viewport tokenization (`tokenizeHeuristically` on the main thread) runs
    in the worker, from the last viewport the editor sent (50 ms debounce,
    as `AttachedViewHandler`). The worker keeps that viewport until the
    grammar has loaded. Heuristic tokens are replaced when the background
    pass reaches their lines.
  - Changes are whole-line replacements, not `IModelChangedEvent`s. The
    editor's snapshot diff yields a single replacement: the common prefix
    and suffix, never splitting a CRLF. No state deltas return to the UI
    isolate, and no font tokens.
  - Grammar and theme files are read by the UI isolate as bytes and decoded
    in the worker (UTF-8, byte order mark dropped, as `TextDecoder` does).
    `loadString` would decode large files through `compute`.
  - A `colorize` request that throws answers null, logged, so a hover never
    waits forever.
  - `TextMateTokenizationSupport` grows `seenLanguages` with `false`
    entries: Dart lists cannot be sparse.
  - `editor.maxTokenizationLineLength` comes only from the bundled
    extensions' `configurationDefaults` (2500 for javascript and csharp);
    there are no user settings.
  - VS Code ids that Monarch names differently are mapped when Monarch
    colors them (`monarchLanguageIdFor`: shellscript→shell,
    javascriptreact→javascript, typescriptreact→typescript, properties→ini,
    dockercompose→yaml, cuda-cpp→cpp, jade→pug). Language servers keep the
    catalog's ids (`../../lib/ide/lsp/packs/README.md`).
  - `semantic_tokens.dart` is unchanged: semantic tokens still paint over
    whichever highlighter runs.
- Tests: `../../test/ide/editor/textmate/textmate_syntax_test.dart` covers the
  worker's tokens for every colorize sample against VS Code's (Dark 2026),
  language detection, codec numbering, background and viewport-first
  tokenization, edit convergence (including seeded random edits) and
  isolate-only tokenization. `textmate_editor_test.dart` covers the editor
  on TS, Python, Markdown (with a code block), HTML (CSS and JS), JSON and
  Rust, edits, and the Monarch fallback. `textmate_languages_test.dart`
  covers pack precedence and id mapping, and
  `../../test/ide/lsp_ui/hover_code_highlight_test.dart` covers hovers. Widget
  tests run the worker in their own isolate (`../../test/flutter_test_config.dart`).
  `../../tool/textmate_perf_app.dart` measures it in profile mode.

## Semantic token styling (2026-09-30)

Semantic tokens take the style VS Code gives them in the editor's color
theme (`ColorThemeData.getTokenStyleMetadata` as `SemanticTokensProviderStyling`
encodes it), instead of a hardcoded Dark+ palette. Ported at
`6a598d4a13031703d483d103c1d934a36ad27971`:

| Upstream VS Code path | Dart path |
| --- | --- |
| `src/vs/platform/theme/common/tokenClassificationRegistry.ts` | `vs/platform/theme/common/token_classification_registry.dart` |
| `src/vs/workbench/services/themes/common/colorThemeData.ts` (token style resolution: `getTokenStyle`, `resolveTokenStyleValue`, `getTokenStyleMetadata`, `resolveScopes`, `getScopeMatcher`, `nameMatcher`, `readSemanticTokenRule`) | `vs/workbench/services/themes/common/color_theme_token_styles.dart` |
| `src/vs/platform/theme/common/themeService.ts` (`ITokenStyle`) | `vs/workbench/services/themes/common/color_theme_token_styles.dart` |
| `src/vs/workbench/services/themes/common/textMateScopeMatcher.ts` | `vs/workbench/services/themes/common/text_mate_scope_matcher.dart` |
| `src/vs/workbench/services/themes/common/tokenClassificationExtensionPoint.ts`, plus the built-in extensions' `semanticTokenScopes` | `vs/workbench/services/themes/common/token_classification_extension_point.dart` |
| `src/vs/editor/common/services/semanticTokensProviderStyling.ts` (`getMetadata`) | `vs/editor/common/services/semantic_tokens_provider_styling.dart` |
| `src/vs/editor/contrib/semanticTokens/common/semanticTokensConfig.ts`, the `editor.semanticHighlighting.enabled` default | `vs/editor/contrib/semanticTokens/common/semantic_tokens_config.dart` |
| `src/vs/editor/common/tokens/sparseTokensStore.ts` (the `SEMANTIC_USE_*` merge) | `../../lib/ide/lsp_ui/semantic_tokens.dart` (`IdeTokenStyle.applyTo`) |

- `../../lib/ide/lsp_ui/semantic_tokens.dart`: `IdeSemanticTokenStyler` (type,
  modifiers, language id → `IdeTokenStyle?`), `ideSemanticTokenStyler(theme)`
  (cached per type, modifiers and language; nothing when the theme has no
  `semanticHighlighting`, as the `configuredByTheme` default says), and
  `ideDefaultSemanticTokenStyler()` (Dark 2026 from the bundled assets).
  `EditorLanguageSession` takes `semanticTokenStyler` and `languageId`
  (settable; setting restyles the latest tokens) and falls back to the
  default styler.
- Golden data: `tool/generate_semantic_token_fixtures.mjs` bundles the
  unmodified upstream modules with esbuild (only the extension registry is
  stubbed), registers the built-in extensions' contributions through the
  upstream handlers, loads the 17 bundled themes plus two synthetic ones, and
  writes `test/fixtures/theme/semantic_tokens.json.gz`: the metadata of 33
  legend types × 24 modifier sets × 8 languages per theme, the registry and
  selector scores. `test/textmate/workbench/semantic_token_styling_test.dart`
  replays it; `../../test/ide/lsp_ui/semantic_tokens_test.dart` checks the styler
  and the overlay against it.

Deviations:

- The token style members of ColorThemeData live in `ColorThemeTokenStyles`,
  which reads a loaded theme's public API (`semanticTokenColors`,
  `themeTokenColors`, `type`, `getTokenColorId`, `tokenColorMap`); it is a
  snapshot of the theme. User customizations (custom semantic and TextMate
  rules) are not ported.
- Token colors: upstream encodes a foreground as an index into
  `tokenColorMap` (`getTokenColorIndex`, which also collects the theme's
  semantic rule colors). The Dart styler computes the same index, so a color
  missing from the index still paints nothing, then maps it through
  `tokenColorMap` to a Flutter `Color`: `IdeTokenStyle` holds colors, not
  indices.
- The editor paints `TextSpan`s rather than merging metadata: the attributes
  whose `SEMANTIC_USE_*` bit is set replace the span's color, `FontStyle`,
  `FontWeight`, and the underline/line-through of its decoration (an
  overline is kept). Backgrounds are never set upstream either.
- Token decoding and span splitting are the existing Dart code, not a port of
  `toMultilineTokens2`: overlapping tokens are split, where upstream drops a
  token that overlaps the previous styled one. Tokens are requested even when
  the theme disables semantic highlighting, and then paint nothing.
- The built-in contributions (`vscode.javascript`, `vscode.typescript`) are
  copied into Dart and compared with what upstream registers; the extension
  point handlers take them directly and collect errors in a list.
- `TokenStyle.fromSettings` takes a rule's JSON values: non-boolean flags
  become their JavaScript truthiness, and a non-string font style is matched
  as `String(value)`. Malformed TextMate rules that make upstream throw (a
  `null` rule, a foreground that is neither a string nor an array) are
  ignored; a non-string scope is converted as `RegExp.exec` does.
- `SemanticTokensProviderStyling` gets the theme through a callback and
  caches by the language id string; `semanticTokenStyleToMetadata` exposes
  the metadata encoding for callers with type and modifier names.
  `isSemanticColoringEnabled` takes the setting's value and the theme's
  flag.
- The session's `languageId` defaults to `plaintext`, the model's default
  language upstream. Without a styler, the session loads Dark 2026
  asynchronously and paints tokens once it has loaded.

## Workbench color theme (2026-09-30)

- `../../lib/theme/workbench_theme.dart` is the color theme part of
  `IWorkbenchThemeService` (`browser/workbenchThemeService.ts`,
  `common/workbenchThemeService.ts`): `ThemeSettingDefaults`,
  `migrateThemeSettingsId`, the constructor's restore, `setColorTheme(id,
  'preview' | 'auto')` through one sequencer, `applyTheme` and
  `restoreColorTheme`. `ColorThemeData` gained `toStorage`,
  `fromStorageData`, `createUnloadedTheme` and
  `createUnloadedThemeForThemeType`; `COLOR_THEME_{DARK,LIGHT}_INITIAL_COLORS`
  are in `../../lib/theme/workbench_theme_initial_colors.dart`.
- The `workbench.colorTheme` setting and the `colorThemeData` storage entry
  are the `colorTheme` and `colorThemeData` preferences the `Workspace` keeps
  (`ColorThemeStorage`). `main()` reads them before the first frame, paints
  the stored theme, then loads the theme file (`initialize`). A preview is
  neither kept nor written to storage; an applied theme is kept once loaded.
- Preferences: Color Theme (`workbench.action.selectTheme`, ⌘K ⌘T) is
  `../../lib/ide/ide_color_theme_picker.dart` over `IdeQuickPick`, whose
  `onDidChangeActive` previews after 200ms; the service implements its
  `IdeColorThemeController`. The workbench resolves two-key chords as
  `abstractKeybindingService.ts` does (see that file's header).
- Widgets read `themeColors[id]` (`IColorTheme.getColor`). `AppColors`
  (../../lib/theme/app_theme.dart) and `IdeModernUI` are getters over color
  ids (`sideBar.background`, `editorWidget.background`, `menu.background`,
  `panel.border`, `foreground`, `descriptionForeground`,
  `disabledForeground`, `textLink.foreground`, `surface.*`,
  `modernActivityBarItem.*`, …). A change rebuilds every element and
  repaints every render object (`WorkbenchThemeScope`), as a theme change
  restyles the whole workbench upstream.
- Editor: TextMate gets the new theme and every document is tokenized again
  (see "TextMate highlighting in the editor"); `EditorViewTheme.fromColors`
  reads the `editor.*`, `editorLineNumber.*`, `scrollbarSlider.*`,
  `minimap*` and `editorOverviewRuler.*` ids; Monarch highlights with the
  built-in theme of the theme's type (`getThemeTypeSelector`); semantic
  tokens use the theme's rules; terminals take
  `TerminalColorTheme.resolve` of it (`getXtermTheme`).
- macOS: the window's `NSAppearance` follows the theme's type (`aqua` or
  `darkAqua`, for the sidebar material, traffic lights and system menus),
  kept in `UserDefaults` for the next launch.
- Deviations: no settings editor or `settings.json`, so no
  `workbench.colorCustomizations`, `editor.tokenColorCustomizations`,
  `window.autoDetectColorScheme`, preferred dark/light/high contrast themes
  or `workbench.preferredColorTheme`; only the bundled themes, none watched
  for changes, and not Light (Visual Studio) or Light+:
  `generate_textmate_assets.mjs` leaves them out (light_vs.json and
  light_plus.json stay, as Light Modern includes them; the fixture generators
  skip them; `tokens.json.gz` keeps their cases until regenerated and the
  parity test skips them). A kept theme no longer bundled falls back to
  the default of the kept theme's type, as `initializeColorTheme` does; no file or product icon themes; the Windows window frame
  does not follow the theme's type; storage is one JSON string. Colors a
  widget cached outside `build`/`paint` would miss a change, so none are
  cached. Where CSS would inherit, `themeColors[id]` of a text color without
  a value (`sideBar.foreground` and the like) is the workbench's
  `foreground`; other missing colors are transparent. A rounded box takes one
  border color in Flutter, so a keybinding label's `bottomBorder` is a line
  under the box. The IDE's shell (around the Modern UI cards) is the agent
  sidebar's color (`sideBar.background`, a tint over the macOS material)
  rather than `modernUI.shellBackground`, and the status bar has no
  background or top border of its own: its text is `statusBar.foreground`
  where the theme's `statusBar.background` is the side bar's (or unset), else
  the side bar's foreground. `../../test/theme/theme_sweep_test.dart` paints the workbench and
  the chat in every bundled theme (`BAOCODE_THEME_SNAPSHOTS=<dir>` writes what
  each paints).

## Color registry (2026-09-30)

| Upstream VS Code path | Dart path |
| --- | --- |
| `src/vs/base/common/color.ts` (all of it) | `vs/base/common/color.dart` |
| `src/vs/platform/theme/common/colorUtils.ts` (`ColorValue`, `ColorTransform`, `ColorDefaults`, `ColorContribution`, the registry, `executeTransform`, `resolveColorValue`) | `vs/platform/theme/common/color_utils.dart` |
| `src/vs/platform/theme/common/themeService.ts` (`IColorTheme`: `type`, `getColor`, `defines`) | `vs/platform/theme/common/color_utils.dart` |
| every `registerColor` the desktop workbench runs, plus built-in `contributes.colors` (`colorExtensionPoint.ts`) | `vs/platform/theme/common/color_registry_data.g.dart` (generated) |
| `src/vs/workbench/services/themes/common/colorThemeData.ts` (`getColor`, `getDefault`, `defines`) | `vs/workbench/services/themes/common/color_theme_data.dart` |
| `src/vs/base/test/common/color.test.ts` | `test/monaco/vs/base/common/color_test.dart` |

- `tool/generate_color_registry.mjs` (Node 22) evaluates the unmodified
  upstream code, never the Dart port. It greps `src/vs` (no tests, no
  `vs/editor/standalone`) for `registerColor(` and keeps the files reachable
  from `workbench.desktop.main.ts`, in that bundle's evaluation order (65 of
  67; the two left out belong to the Agent Sessions window). esbuild (the
  version `build/package.json` pins) bundles them into one module: the color
  files, `base/common`, `nls`, `platform/{theme,jsonschemas,instantiation}/
  common` and the theme loader files are real; every other import is a
  CommonJS stub whose exports are one universal Proxy, so widget and service
  code evaluates without effect. `Registry.as` of an id no real module added
  returns the stub, and `ExtensionsRegistry` records extension points so the
  real `ColorExtensionPoint` handler receives the built-in extensions'
  `contributes.colors` (extensions/* minus `excludedExtensions` and
  product.json `builtInExtensions`, plus `copilot`; sorted as `extensionCmp`;
  only the Git extension contributes colors). The run fails if a registered
  value is not a string, `Color` or transform (a stub leaked), if a
  `registerColor` call site in the color files did not run at load, if files
  register out of the desktop order, or if the darwin, linux and win32
  evaluations differ. Result: 950 ids, 939 from the workbench and 11 from
  `extensions/git`.
- It writes `color_registry_data.g.dart` (const data: id and per-scheme
  default as a `ColorLiteral` hex or exact RGBA, a `ColorReference` or a
  transform tree) and `test/fixtures/theme/color_registry.json.gz`: for the
  17 bundled themes, loaded by the real `ColorThemeData` from the upstream
  theme files, and an empty theme per color scheme, every id's
  `getColor(id)`, `getColor(id, false)` and `defines(id)` (RGBA plus any
  HSLA/HSVA the color was made from), and real `color.ts` results for seeded
  random inputs. `test/textmate/workbench/color_registry_test.dart`
  and `color_test.dart` replay them with 0 differences.
- API: `getColorRegistry().getColors()` (ids in registration order),
  `resolveDefaultColor(id, theme)`, `resolveColorValue`, `executeTransform`,
  `resolveColors(theme)` (every registered id to `theme.getColor(id)`), and
  `ColorThemeData.getColor(id, {useDefault})`, `getDefault`, `defines`.
- Deviations: a bare ColorValue default is stored as the same value for all
  four schemes (what `resolveDefaultColor` does with it); ColorValue is a
  sealed class (`ColorLiteral`, `ColorReference`, one class per transform)
  instead of `Color | string | ColorTransform`; descriptions,
  `needsTransparency`, deprecation messages, JSON schemas and
  `notifyThemeUpdate` are not ported; `useDefault` is a named parameter.
  In `color.dart`, JavaScript number semantics are reproduced (`Math.round`
  halves up, `| 0`, NaN through `Math.min`/`Math.max`, `%` as `remainder`);
  `new Color(hsla|hsva)` is `Color.fromHSLA`/`fromHSVA`; the static
  `Color.transparent` is `Color.transparentColor` and the static `equals` are
  `equalsRGBA`/`equalsHSLA`/`equalsHSVA`/`equalsColors` (Dart forbids a
  static and an instance member of one name); `flatten` takes a list;
  `parse` throws a `FormatException`; `toString` now follows upstream
  (`Color.Format.CSS.format`: hex if opaque, else `rgba(...)`). `math.pow`
  differs from V8's `Math.pow` in the last bit for 32 of the 256 channel
  luminances, but `getRelativeLuminance` (rounded to 4 decimals) equals
  upstream's for all 2^24 RGB colors, which the test checks.

## Editor keyboard commands (2026-10-01)

Ported from VS Code `6a598d4a…` (headers record deviations):
`contrib/smartSelect/browser/{smartSelect,bracketSelections,wordSelections}.ts`
(`smart_select.dart`), `contrib/wordPartOperations/browser/wordPartOperations.ts`
(in `cursor_word_operations.dart`), `JoinLinesAction` and
`DuplicateSelectionAction` (`lines_operations.dart`),
`InsertCursorAtEndOfEachLineSelected` (`multicursor.dart`), `lineBreakInsert`
(`cursor_type_operations.dart`) and the folding actions' model calls
(`editor_folding.dart`).

`flutter/editor_keybindings.dart` has upstream's keyboard commands
(`editorKeyboardCommandLabels`: cursor, selection, deletion, scrolling,
snippet, find widget, suggest, parameter hints, rename and message commands)
and their keybindings (`editorExtraKeybindings`, upstream's rules in
`KeybindingsRegistry` order, `when` = `kbExpr && precondition`), and the
context keys they read (`editorContextKeys`). With the app's keybindings
(`IdeEditor.keyResolver`) every key goes through them: the IDE editor
resolves a key in its own context (`IdeEditorState.contextKey`) and runs the
editor's and its widgets' commands; a key no keybinding has does nothing when
the editor would otherwise use it (Enter types a line break), and macOS
selectors are not used. Without a resolver the built-in keys still apply.
