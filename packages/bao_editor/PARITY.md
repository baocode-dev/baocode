# Monaco v0.57.0 parity checklist

Target: the public editor/languages APIs and feature registrations of Monaco
v0.57.0, backed by VS Code `6a598d4a13031703d483d103c1d934a36ad27971`.
The upstream editor is TypeScript plus browser services. Dart source ports and
Flutter platform adaptations have separate validation requirements. A green
Dart test suite does not establish full Monaco parity.

Authoritative inventories in the pinned VS Code checkout:

- `src/vs/monaco.d.ts`: public API and options.
- `src/vs/editor/editor.api.ts`: exports.
- `src/vs/editor/editor.all.ts`: contributed feature registrations.
- `src/vs/editor/editor.main.ts`: standalone composition.
- Monaco's pinned repository: language definitions and language-service workers.

The complete VS Code extension host is not part of Monaco Editor.

This checklist ships with the bao_editor package (MIT; not on pub.dev yet, see
[HANDOFF.md](HANDOFF.md) for the publishing plan). Rows marked "BaoCode, not
Monaco" and the contributions over LSP belong to the app (`../../lib/ide/`,
GPL-3.0-only), not to the package.

| Boundary | Current state | Required before parity |
| --- | --- | --- |
| Position, Range, Selection | Source ports with tests | Maintain pinned behavior tests and documented Dart API names |
| Edit factories, TextChange, EOL, cursor columns | Source ports with tests | Integration, API mapping and boundary regressions |
| Piece-tree buffer and builder | Partial source port with shared append-only change buffer | Remaining cache/edit-path fidelity, optimized node search, edge-case parity/performance |
| Search | Adapted standalone service with directional find wired to the app, source-derived replace-pattern parser, and basic find/replace UI | Complete FindController behaviors, word segmentation, JS/Dart regex differences |
| Commands and TextEdit | Partial source ports | Full command contract, marker tracking, composition/overwrite/language-sensitive behavior |
| TextModel and model services | Separate source-derived subset with versions/events/validated positions/options/basic decorations and opt-in single-resource undo binding; app still uses raw-text Flutter bridge | App resource lifecycle, complete model parts, token/word/bracket integration and exact file-EOL boundary |
| Undo/redo service | Flutter bridge history with selection restore and typing coalescing, plus separate bound single-model edit-stack/per-resource source ports | App/model binding, upstream EOL grouping/disposal behavior, atomic multi-model groups, serialized history |
| Cursor engine | Multi-cursor (add cursor, add next/all occurrences, cursors above/below, column select), word/smart-home/page/sticky-x navigation, language-aware typing (auto-close/skip-over/surround, onEnter/indent rules, electric outdent), comment/line commands; cursorCommon/WordOperations/TypeOperations/DeleteOperations/ColumnSelection ports | Token-based string/comment detection (currently a line scan), IME composition across secondary cursors, full keybinding table |
| Decorations/interval tree | Interval tree source port driving tracked decorations (`interval_tree.dart`, `editor_tracked_decorations.dart`); decoration types (`registerTextEditorDecorationType`/`setDecorations`/fast form/`removeDecorationType`, render options and CSS values in `editor_decoration_types.dart`), surfaces decorations (find matches, diagnostics kinds, custom) painted with backgrounds/borders/outlines/text styles, overview-ruler lanes, gutter icons, `before`/`after` injected text and hover messages | Marker ownership, per-range `rangeBehavior` on model changes beyond the tracked ranges |
| View model and layout | Virtualized fixed-line-height layout (only visible lines shaped, shared LRU), tab stops, indent/marker folding with hidden lines, view zones (CodeLens, ghost text), and injected text (`LineInjectedText.fromDecorations` order, cursor stops, column/offset mapping, hit-testing that skips it) | Wrapped-line virtualization |
| Native input and pointer handling | Experimental painted surface | Real IME/native menu tests, undo grouping, drag autoscroll, gestures, clipboard metadata |
| Accessibility | Pending native validation | Text semantics, navigation/announcements, accessible diff, VoiceOver/Narrator |
| Rendering | Gutter with line numbers and fold chevrons, current line, multi-selection/carets with blink, bracket match, selection occurrences, indent guides, whitespace, overlay scrollbars with overview ruler, block minimap, Monarch token colors | Glyph widgets, sticky scroll, smooth scrolling, character minimap, rulers |
| Tokenization and language providers | Token data and Monarch compiler/lexer ported, 86 pinned grammar variants/89 registrations bundled; first-line matching and prefix/converged-suffix reuse; opt-in surface uses built-in `vs-dark` rules | Full incremental invalidation, theme/provider registry, cancellation, language workers/services |
| Editor contributions | Over LSP (`../../lib/ide/lsp_ui/`): diagnostics squiggles/overview marks/Problems panel/F8, markdown hover, definition/type definition/implementation/references (panel, not peek), ⌘-click links, back/forward, suggest widget with fuzzy filter (`filters.ts` port), resolve, commit characters and snippets (`snippetParser`/`snippetSession` ports), signature help, rename, document/selection formatting, document symbols in breadcrumbs/outline/`@` quick open, code actions (lightbulb, ⌘.), semantic token overlay; editor-side **inlay hints** (`editor_inlay_hints.dart`: word anchors, part-wise injected labels, paddings, kinds, links/tooltips, `maximumLength`), **CodeLens** (`editor_code_lens.dart`: zones above lines, ` \| ` separators, codicons, hover/click, lazy resolve) and **inline completion ghost text** (`editor_inline_suggest.dart`: single/multi-line, Tab/Escape/Cmd+Right) with the app glue in `../../lib/ide/ide_editor_features.dart` | Peek views, links/colors from the server, server folding, sticky scroll, word-distance ranking, nested snippets, Outline sort/filter |
| Diff editor | Source-derived subset of line/character diff and range mappings; side-by-side/inline UI (900px breakpoint) with view zones, deleted code, decorations, overview ruler and sash, opened from Source Control changes | Moved-line heuristics, workers, navigation/revert, gutter menu, hidden unchanged regions, word wrap, accessibility; Timeline/Graph diffs |
| Language servers (BaoCode, not Monaco) | Generic LSP 3.17 client over stdio (UTF-16, incremental sync, dynamic registration, configuration, watched files, progress, applyEdit); per-root × server processes with idle stop, crash backoff, reaping; Helix-derived language map; mason-registry installer; user overrides and language packs | Pull diagnostics, semantic token ranges/deltas, resource operations in workspace edits, `showDocument`, process-group kill, symlink-resolved document keys |
| Workbench look (BaoCode, not Monaco) | VS Code 1.140 defaults: Modern UI cards (activity bar, side bar, editor, chat; 4px gaps, 8px corners, grip sashes), Dark 2026 colors, workbench hovers, codicons; editor hovers render markdown with editor-tokenized code blocks | Compact density, right-side activity bar, hover status bar actions, markdown tables/HTML in hovers |
| Workbench side bar (BaoCode, not Monaco) | Explorer (Folders with Git decorations, inline new/rename, delete/trash confirmations, cut/copy/paste, VS Code context menu; Outline and Timeline panes), Source Control (tree view by default with View & Sort, changes, smart commit, undo, discard, Generate Commit Message with Claude Haiku, graph with lanes/references; rows grow in and shrink out on expand and refresh), Timeline (Git provider), Search (regex/case/word, include/exclude, `.gitignore`, replace with preserve case), Extensions (language servers: installed/recommended, search, install/uninstall via mason), animated panes, self-drawn context menus | Timeline/Graph diffs, fetch/stash/branches, multi-select, multi-line search, search editor/history, local history, extension details editor, VS Code extensions |
| Standalone API/services | Pending | Editor/model creation, options/events/view state, actions/context keys, themes/markers/providers/workers |

## Integration gates

1. The painted surface is now the Fast IDE default (2026-09-29). Keep the
   `TextField` fallback (`--dart-define=BAOCODE_NATIVE_EDITOR=false`) while native
   IME, menus and accessibility still lack platform validation.
2. Keep exact decoded file contents and saved baselines at the BaoCode file
   boundary. If the upstream model normalizes text, explicitly map that boundary
   rather than making an opened document dirty or rewriting unchanged bytes.
3. Port tests with their modules. Add randomized edit/inverse tests, Unicode and
   newline regressions, widget tests, and platform smoke checks.
4. Record omissions and deliberate deviations in `PORTING.md` and source headers;
   do not turn missing implementations into no-op APIs to claim coverage.
5. Full parity requires checking all public API/option/contribution entries,
   native platforms, and representative performance/large-file cases. This
   checklist is not yet complete and is not a declaration of completion.
6. Language features go through `LanguageFeatures` (`../../lib/ide/lsp/language_features.dart`);
   UI tests use an in-memory fake, the client is tested end to end against
   `../../test/fixtures/lsp/fake_lsp_server.dart`, and the real `dart language-server`
   smoke test runs only with `--run-skipped -t lsp-smoke`.
