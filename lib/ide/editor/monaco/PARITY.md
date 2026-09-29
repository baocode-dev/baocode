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

| Boundary | Current state | Required before parity |
| --- | --- | --- |
| Position, Range, Selection | Source ports with tests | Maintain pinned behavior tests and documented Dart API names |
| Edit factories, TextChange, EOL, cursor columns | Source ports with tests | Integration, API mapping and boundary regressions |
| Piece-tree buffer and builder | Partial source port with shared append-only change buffer | Remaining cache/edit-path fidelity, optimized node search, edge-case parity/performance |
| Search | Adapted standalone service with directional find wired to the app, source-derived replace-pattern parser, and basic find/replace UI | Complete FindController behaviors, word segmentation, JS/Dart regex differences |
| Commands and TextEdit | Partial source ports | Full command contract, marker tracking, composition/overwrite/language-sensitive behavior |
| TextModel and model services | Separate source-derived subset with versions/events/validated positions/options/basic decorations and opt-in single-resource undo binding; app still uses raw-text Flutter bridge | App resource lifecycle, complete model parts, token/word/bracket integration and exact file-EOL boundary |
| Undo/redo service | Flutter bridge history plus separate bound single-model edit-stack/per-resource source ports | App/model binding, upstream EOL grouping/disposal behavior, atomic multi-model groups, selection integration across tabs, serialized history |
| Cursor engine | Experimental single caret | Multiple cursors, column selection, preferred x, language-aware typing, full keybindings |
| Decorations/interval tree | Interval tree source port, not integrated | Stickiness/model edit tracking, marker ownership and rendered decorations |
| View model and layout | Flutter geometry with shared shaped paragraphs across equal lines and edits; exact row positions still rebuilt | Model/view projections, hidden/wrapped lines, injected text, whitespace/view zones, incremental virtualization |
| Native input and pointer handling | Experimental painted surface | Real IME/native menu tests, undo grouping, drag autoscroll, gestures, clipboard metadata |
| Accessibility | Pending native validation | Text semantics, navigation/announcements, accessible diff, VoiceOver/Narrator |
| Rendering | Experimental painted surface with Monarch token spans and pinned dark theme | Line numbers, glyph margins, guides, rulers, minimap, overlays, complete font and decoration behavior |
| Tokenization and language providers | Token data and Monarch compiler/lexer ported, 86 pinned grammar variants/89 registrations bundled; first-line matching and prefix/converged-suffix reuse; opt-in surface uses built-in `vs-dark` rules | Full incremental invalidation, theme/provider registry, cancellation, language workers/services |
| Editor contributions | Pending | Completion/snippets, hover, diagnostics, navigation, formatting/actions, rename, folding, links/colors/inlay/CodeLens, sticky scroll |
| Diff editor | Source-derived subset of line/character diff and range mappings, no UI | Full moved-line heuristics, mapping helpers, workers, inline/side-by-side UI, navigation/revert, hidden regions and accessibility |
| Standalone API/services | Pending | Editor/model creation, options/events/view state, actions/context keys, themes/markers/providers/workers |

## Integration gates

1. Do not replace the production `TextField` just because the custom surface can
   type text. Keep the fallback while native input and accessibility regressions
   are being closed.
2. Keep exact decoded file contents and saved baselines at the Monad file
   boundary. If the upstream model normalizes text, explicitly map that boundary
   rather than making an opened document dirty or rewriting unchanged bytes.
3. Port tests with their modules. Add randomized edit/inverse tests, Unicode and
   newline regressions, widget tests, and platform smoke checks.
4. Record omissions and deliberate deviations in `PORTING.md` and source headers;
   do not turn missing implementations into no-op APIs to claim coverage.
5. Full parity requires checking all public API/option/contribution entries,
   native platforms, and representative performance/large-file cases. This
   checklist is not yet complete and is not a declaration of completion.
