# xterm.js core port

This is an incremental Dart port of the xterm.js terminal core that VS Code
uses at the Monaco port's `vscodeRef`
`6a598d4a13031703d483d103c1d934a36ad27971`. That revision's
`package-lock.json` pins:

| Package | Version |
| --- | --- |
| `@xterm/xterm` | `6.1.0-beta.304` |
| `@xterm/headless` | `6.1.0-beta.303` |
| `@xterm/addon-unicode11` | `0.10.0-beta.301` |
| `@xterm/addon-search` | `0.17.0-beta.301` |
| `@xterm/addon-serialize` | `0.15.0-beta.301` |

All of them were published from xterm.js commit
`c58ea3637f3968e0e6e79cd92cf9aace7ef89ee2` (npm `gitHead`; 2026-08-30,
"Merge pull request #5879 from PerBothner/image-ext"). That commit is the
authoritative source; the port does not follow newer xterm.js. A shallow
checkout lives at `/private/tmp/monad-xterm-6.1.0-beta.304`.

Source-derived code is covered by the xterm.js MIT license in
[LICENSE.txt](LICENSE.txt).

## Layout

| Upstream | Dart |
| --- | --- |
| `src/common/buffer/BufferLine.ts` | `lib/ide/terminal/xterm/common/buffer/buffer_line.dart` |
| `src/headless/public/Terminal.ts` | `lib/ide/terminal/xterm/headless/public/terminal.dart` |
| `typings/xterm-headless.d.ts` | `lib/ide/terminal/xterm/typings/xterm_headless.dart` |
| `addons/addon-unicode11/src/UnicodeV11.ts` | `lib/ide/terminal/xterm/addons/addon_unicode11/unicode_v11.dart` |
| `src/common/buffer/BufferLine.test.ts` | `test/ide/terminal/xterm/common/buffer/buffer_line_test.dart` |
| `src/common/TestUtils.test.ts` | `test/ide/terminal/xterm/common/test_utils.dart` (helpers, not a test) |

Directories keep upstream's names (lower case, `-` → `_`); file names are
upstream's in snake_case.

## Conventions

Every ported file follows these, so the parts ported separately fit.

- **Header.** Upstream's copyright line, the license, and the source:

  ```dart
  // Copyright (c) 2018 The xterm.js authors. All rights reserved.
  // Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
  // Ported from xterm.js src/common/buffer/BufferLine.ts (c58ea36).
  ```

  Tests say `Adapted from xterm.js src/common/buffer/BufferLine.test.ts
  (c58ea36).`
- **Pure Dart.** The core compiles for the web: only `dart:async`,
  `dart:collection`, `dart:convert`, `dart:math`, `dart:typed_data` and
  relative imports inside `xterm/`. No `package:flutter`, `dart:io`,
  `dart:ffi` or `dart:html`.
- **Names.** Upstream's: `IBufferService`, `BufferLine`, `translateToString`,
  so that VS Code's terminal code ports onto it name for name. Interfaces are
  `abstract interface class IFoo`. Upstream `private` members read by other
  files or by the ported tests are public, documented as such
  (`/// Upstream private; public for the ported tests.`).
- **Enums.** A numeric `const enum` used in arithmetic or bit operations is an
  `abstract final class` of `static const int`s under the same names
  (`Attributes.CM_DEFAULT` → `Attributes.cmDefault`, lowerCamelCase). Other
  enums and string unions are Dart `enum`s or `String` constants, whichever
  keeps call sites closest.
- **Events and disposables.** `Event.ts` and `Lifecycle.ts` are ported as they
  are: `typedef IEvent<T> = IDisposable Function(void Function(T e) listener)`,
  `Emitter<T>` with `event`/`fire`/`dispose`, `Disposable` with `register`,
  `MutableDisposable`, `toDisposable`. Upstream's free function `dispose(...)`
  is `disposeAll(...)`.
- **Services.** `InstantiationService`, `ServiceRegistry` and
  `createDecorator` (TypeScript decorators) are not ported. A service takes the
  services it depends on as constructor parameters, in upstream's order of the
  decorated parameters; `CoreTerminal` wires them. The `I*Service` interfaces
  stay.
- **Numbers.** `number` is `int` for integers (coordinates, code points,
  attribute words, flags) and `double` for fractions (sizes, ratios). JS
  bitwise operators work on 32 bits: mask what must stay 32-bit
  (`& 0xFFFFFFFF`), use `>>>` for `>>>`, and `.toSigned(32)` where upstream
  relies on `| 0`. The code must be right both on the VM (64-bit ints) and
  under dart2js (bitwise results are unsigned 32-bit).
- **Strings.** Both are UTF-16: `charCodeAt` → `codeUnitAt`;
  `String.fromCharCode` takes code points above `0xFFFF` in Dart.
- **Typed arrays.** `Uint32Array` → `Uint32List` (etc.), `subarray(a, b)` →
  `Uint32List.sublistView(list, a, b)`, `set(src, offset)` → `setRange`,
  `fill(v, a, b)` → `fillRange(a, b, v)`.
- **Absent values.** `undefined` and `null` are `null`. Options objects are
  classes with named constructor parameters.
- **Timers.** `setTimeout` → `Timer`; `requestIdleCallback` → upstream's
  non-browser fallback on `Timer`; `performance.now()` → a `Stopwatch`.
- **Tests.** `package:flutter_test/flutter_test.dart` (the repository's
  convention) with `group`/`test`/`setUp`. `assert.equal(a, b)` →
  `expect(a, b)`, `assert.deepEqual` → `expect(a, equals(b))`,
  `assert.throws` → `expect(..., throwsA(...))`. A test that needs a DOM or the
  browser terminal is left out and listed below with the reason.
- **Formatting.** `dart format` one file at a time, never a directory.

## Ported files

<!-- Rows are added as each part lands: upstream path, Dart path, and
     "subset" with what is missing where only part is ported. -->

| Upstream | Dart | Notes |
| --- | --- | --- |
| `src/common/Event.ts` | `common/event.dart` | |
| `src/common/Lifecycle.ts` | `common/lifecycle.dart` | |
| `src/common/Types.ts` | `common/types.dart` | |
| `src/common/Platform.ts` | `common/platform.dart` | host set by `initPlatform` |
| `src/common/Async.ts` | `common/async.dart` | |
| `src/common/TaskQueue.ts` | `common/task_queue.dart` | idle queue is the timer fallback |
| `src/common/Version.ts` | `common/version.dart` | |
| `src/common/CircularList.ts` | `common/circular_list.dart` | |
| `src/common/SortedList.ts` | `common/sorted_list.dart` | |
| `src/common/MultiKeyMap.ts` | `common/multi_key_map.dart` | |
| `src/common/StringBuilder.ts` | `common/string_builder.dart` | |
| `src/common/Color.ts` | `common/color.dart` | subset: no canvas fallback in `css.toColor` (as upstream under Node.js) |
| `src/common/data/EscapeSequences.ts` | `common/data/escape_sequences.dart` | |
| `src/common/data/Charsets.ts` | `common/data/charsets.dart` | |
| `src/common/buffer/Constants.ts` | `common/buffer/constants.dart` | |
| `src/common/buffer/Types.ts` | `common/buffer/types.dart` | |
| `src/common/buffer/AttributeData.ts` | `common/buffer/attribute_data.dart` | |
| `src/common/buffer/CellData.ts` | `common/buffer/cell_data.dart` | |
| `src/common/buffer/BufferRange.ts` | `common/buffer/buffer_range.dart` | |
| `src/common/buffer/Marker.ts` | `common/buffer/marker.dart` | |
| `src/common/parser/Types.ts` | `common/parser/types.dart` | subset: no `IParamsConstructor` |
| `src/common/parser/Constants.ts` | `common/parser/constants.dart` | |
| `src/common/input/TextDecoder.ts` | `common/input/text_decoder.dart` | |
| `src/common/input/UnicodeV6.ts` | `common/input/unicode_v6.dart` | |
| `src/common/services/Services.ts` | `common/services/services.dart` | subset: no DI (`createDecorator`, `IInstantiationService`, `IBrandedService`) |
| `src/common/services/OptionsService.ts` | `common/services/options_service.dart` | |
| `src/common/services/LogService.ts` | `common/services/log_service.dart` | |
| `src/common/services/UnicodeService.ts` | `common/services/unicode_service.dart` | |
| `typings/xterm-headless.d.ts` | `typings/xterm_headless.dart` | shared declarations re-exported from `xterm.dart` |
| `typings/xterm.d.ts` | `typings/xterm.dart` | subset: what `src/common` and `src/headless` use; no browser `Terminal`, `ITerminalAddon`, links, render dimensions |
| `src/common/buffer/BufferLine.ts` | `common/buffer/buffer_line.dart` | `Uint32List` storage; out-of-range reads give 0 and writes are dropped, as with JS typed arrays |
| `src/common/buffer/Buffer.ts` | `common/buffer/buffer.dart` | with reflow; `_removeMarker` ignores a marker it cannot find (upstream's `splice(-1, 1)` would drop the last one) |
| `src/common/buffer/BufferReflow.ts` | `common/buffer/buffer_reflow.dart` | |
| `src/common/buffer/BufferSet.ts` | `common/buffer/buffer_set.dart` | |
| `src/common/WindowsMode.ts` | `common/windows_mode.dart` | |
| `src/common/services/BufferService.ts` | `common/services/buffer_service.dart` | |
| `src/common/services/CharsetService.ts` | `common/services/charset_service.dart` | the sparse array is a list padded with nulls |
| `src/common/services/CoreService.ts` | `common/services/core_service.dart` | |
| `src/common/services/DecorationService.ts` | `common/services/decoration_service.dart` | `DecorationLineCache` and `Decoration` are public |
| `src/common/services/MouseStateService.ts` | `common/services/mouse_state_service.dart` | |
| `src/common/services/OscLinkService.ts` | `common/services/osc_link_service.dart` | |
| `src/common/TestUtils.test.ts` | `test/ide/terminal/xterm/common/test_utils.dart` | every mock, plus `cloneDefaultOptions()` |
| `src/common/parser/Params.ts` | `common/parser/params.dart` | protected fields are read-only getters |
| `src/common/parser/OscParser.ts` | `common/parser/osc_parser.dart` | `OscHandler.payloadLimit` is a public static so tests can change it |
| `src/common/parser/DcsParser.ts` | `common/parser/dcs_parser.dart` | as OSC |
| `src/common/parser/ApcParser.ts` | `common/parser/apc_parser.dart` | as OSC |
| `src/common/parser/EscapeSequenceParser.ts` | `common/parser/escape_sequence_parser.dart` | the `Uint16List` transition table, fast paths and async resume stack as upstream; protected members public |
| `src/common/input/Keyboard.ts` | `common/input/keyboard.dart` | |
| `src/common/input/KittyKeyboard.ts` | `common/input/kitty_keyboard.dart` | `SUPER` is `super_` |
| `src/common/input/Win32InputMode.ts` | `common/input/win32_input_mode.dart` | |
| `src/common/input/WriteBuffer.ts` | `common/input/write_buffer.dart` | |
| `src/common/input/XParseColor.ts` | `common/input/x_parse_color.dart` | |
| `src/common/InputHandler.ts` | `common/input_handler.dart` | the title stacks are public; handlers to which `IInputHandler` gives an optional `collect` take it and ignore it; the slow async handler warning is a 5 s timer and never rethrows |
| `src/common/CoreTerminal.ts` | `common/core_terminal.dart` | protected members are public (`bufferService`, `logService`, `charsetService`, `oscLinkService`, `inputHandler`, `setup()`, the `on*Emitter`s); `onResize` fires `({int cols, int rows})` |
| `src/headless/Terminal.ts` | `headless/terminal.dart` | keeps the name `Terminal`; the public file imports it `as internal` |
| `src/headless/public/Terminal.ts` | `headless/public/terminal.dart` | `core` is upstream's `_core`; no `_verifyIntegers` (the parameters are `int`) |
| `src/common/public/AddonManager.ts` | `common/public/addon_manager.dart` | an addon that disposes itself stays loaded (its `dispose` cannot be swapped) and is disposed again with the terminal |
| `src/common/public/BufferApiView.ts` | `common/public/buffer_api_view.dart` | |
| `src/common/public/BufferLineApiView.ts` | `common/public/buffer_line_api_view.dart` | |
| `src/common/public/BufferNamespaceApi.ts` | `common/public/buffer_namespace_api.dart` | |
| `src/common/public/ParserApi.ts` | `common/public/parser_api.dart` | keeps the deprecated `add*Handler` aliases |
| `src/common/public/UnicodeApi.ts` | `common/public/unicode_api.dart` | the `IUnicodeHandling` adapter; `UnicodeService` is unchanged |
| `addons/addon-unicode11/src/UnicodeV11.ts` | `addons/addon_unicode11/unicode_v11.dart` | tables under `// dart format off` |
| `addons/addon-unicode11/src/Unicode11Addon.ts` | `addons/addon_unicode11/unicode11_addon.dart` | |
| `addons/addon-unicode-graphemes/src/UnicodeGraphemeProvider.ts` | `addons/addon_unicode_graphemes/unicode_grapheme_provider.dart` | |
| `addons/addon-unicode-graphemes/src/UnicodeGraphemesAddon.ts` | `addons/addon_unicode_graphemes/unicode_graphemes_addon.dart` | |
| `addons/addon-unicode-graphemes/src/third-party/tiny-inflate.ts` | `addons/addon_unicode_graphemes/third_party/tiny_inflate.dart` | the default export is `tinfUncompress`; tables built on first use; throws `ArgumentError('Data error')` |
| `addons/addon-unicode-graphemes/src/third-party/unicode-trie.ts` | `addons/addon_unicode_graphemes/third_party/unicode_trie.dart` | reads its header at the data's offset (upstream's `DataView(data.buffer)` ignores it) |
| `addons/addon-unicode-graphemes/src/third-party/UnicodeProperties.ts` | `addons/addon_unicode_graphemes/third_party/unicode_properties.dart` | trie data in adjacent string literals |
| `addons/addon-webgl/src/customGlyphs/Types.ts` | `addons/addon_webgl/custom_glyphs/types.dart` | |
| `addons/addon-webgl/src/customGlyphs/CustomGlyphDefinitions.ts` | `addons/addon_webgl/custom_glyphs/custom_glyph_definitions.dart` | converted by script; all 778 definitions and `blockPatternCodepoints` checked equal; under `// dart format off` |
| `addons/addon-webgl/src/customGlyphs/CustomGlyphRasterizer.ts` | `lib/ide/terminal/terminal_custom_glyphs.dart` | Flutter painter, outside `xterm/`: `tryDrawCustomGlyph` is `paintCustomGlyph`; no `createPatternCanvas` |
| `src/browser/Types.ts` | `lib/ide/terminal/terminal_colors.dart` | subset: `DEFAULT_ANSI_COLORS` is `terminalAnsiColors` |
| `src/browser/selection/Types.ts` | `browser/selection/types.dart` | |
| `src/browser/selection/SelectionModel.ts` | `browser/selection/selection_model.dart` | |
| `src/browser/Clipboard.ts` | `browser/clipboard.dart` | subset: `prepareTextForTerminal`, `bracketTextForPaste`, `paste` (no textarea) |
| `src/browser/input/MoveToCell.ts` | `browser/input/move_to_cell.dart` | |
| `src/browser/input/Mouse.ts` | `browser/input/mouse.dart` | subset: `getCoords`, from a position relative to the grid |
| `src/browser/services/SelectionService.ts` | `lib/ide/terminal/terminal_selection.dart` | adapted: Flutter pointer events; the platform is a parameter, not `isMac` |
| `src/browser/services/MouseService.ts`, `CoreBrowserTerminal.ts` (mouse) | `lib/ide/terminal/terminal_mouse.dart` | adapted, as selection |
| `src/browser/services/KeyboardService.ts`, `CoreBrowserTerminal.ts` (keys) | `lib/ide/terminal/terminal_keyboard.dart` | adapted: Flutter `KeyEvent`s, with VS Code's terminal keybindings |
| `src/browser/Clipboard.ts` (events), VS Code's clipboard commands | `lib/ide/terminal/terminal_clipboard.dart` | adapted |
| `addons/addon-webgl/src/WebglRenderer.ts`, `src/browser/renderer/shared/RendererUtils.ts`, `SelectionRenderModel.ts`, `src/browser/services/RenderService.ts` | `lib/ide/terminal/terminal_renderer.dart` | adapted: `dart:ui` instead of WebGL; a model per viewport row, its picture cached by content; at most one paint per frame |
| `src/browser/Viewport.ts`, `src/browser/decorations/OverviewRulerRenderer.ts`, `ColorZoneStore.ts`, `src/browser/input/Mouse.ts` (grid coordinates) | `lib/ide/terminal/terminal_widget.dart` | adapted; the scrollbar follows VS Code's `ScrollableElement` |
| `src/browser/services/ThemeService.ts`, `src/browser/ColorContrastCache.ts`, `CoreBrowserTerminal.ts` (color requests) | `lib/ide/terminal/terminal_render_theme.dart` | adapted; VS Code's option and theme defaults as `vscodeTerminalOptions` / `vscodeTerminalTheme` |
| `src/browser/services/CharSizeService.ts`, `src/browser/renderer/dom/WidthCache.ts`, `WebglRenderer._updateDimensions` | `lib/ide/terminal/terminal_render_metrics.dart` | adapted: measured with `dart:ui` paragraphs |
| `addons/addon-webgl/src/CursorBlinkStateManager.ts`, `src/browser/renderer/shared/TextBlinkStateManager.ts` | `lib/ide/terminal/terminal_render_blink.dart` | |
| `CoreBrowserTerminal.ts` (`_showCursor`) | `lib/ide/terminal/terminal_instance.dart` (`showCursor`) | called on the view's focus and on each key the keyboard sends (its `onKey`), where upstream calls it |
| `src/browser/public/Terminal.ts` (selection, `registerDecoration`) | `lib/ide/terminal/terminal_xterm.dart` | the headless public `Terminal` plus the browser terminal's selection and decorations, as the search addon's `ISearchTerminal`; VS Code's `XtermTerminal` |
| `addons/addon-search/typings/addon-search.d.ts` | `addons/addon_search/typings/addon_search.dart` | adds `ISearchTerminal`, the browser `Terminal`'s selection and decorations |
| `addons/addon-search/src/SearchAddon.ts` | `addons/addon_search/search_addon.dart` | `activate` takes a `covariant ISearchTerminal` |
| `addons/addon-search/src/SearchEngine.ts` | `addons/addon_search/search_engine.dart` | an invalid regex throws `FormatException` |
| `addons/addon-search/src/SearchLineCache.ts` | `addons/addon_search/search_line_cache.dart` | the sparse cache array is a map |
| `addons/addon-search/src/SearchResultTracker.ts` | `addons/addon_search/search_result_tracker.dart` | |
| `addons/addon-search/src/SearchState.ts` | `addons/addon_search/search_state.dart` | |
| `addons/addon-search/src/DecorationManager.ts` | `addons/addon_search/decoration_manager.dart` | subset: no `_applyStyles` (CSS class and outline on the DOM element), so `matchBorder`/`activeMatchBorder` go unused |
| VS Code's `terminalFindWidget.ts`, `simpleFindWidget.ts` (state), `xtermTerminal.ts` (search) | `lib/ide/terminal/terminal_find.dart` | adapted: the find widget's state and actions, no widget |

Every ported `*.test.ts` of these files is ported in full under
`test/ide/terminal/xterm/common/` (Event, CircularList, SortedList,
MultiKeyMap, StringBuilder, Color, CellData, BufferRange, TextDecoder,
UnicodeV6, OptionsService, UnicodeService). SortedList.test.ts defines its own
`MockLogService` until TestUtils lands; the Event `thisArgs` case listens with
a bound tear-off; OptionsService prints instead of silencing `console.error`.

The tests of the buffer, services, parser and input files, `InputHandler`,
the headless `Terminal` and `AddonManager` are ported in full (same cases and
counts). `InputHandler.test.ts` records what reaches the parser instead of
monkeypatching `_parser.parse`, and compares color events, link data and
extended attributes field by field; the headless tests add cases marked "New:
not upstream" (the Windows wrapping heuristics, resize flushing pending
writes, the minimum size, RIS, `onWriteParsed`, OSC 633 handlers, the API
adapters). The addons' Playwright tests keep every assertion,
run against a `UnicodeService` behind a stand-in `Terminal`; tests marked
"New: not upstream" add width and grapheme cases, and exercise tiny-inflate
through `dart:io`'s `ZLibEncoder` (VM only). `WriteBuffer`'s tests use real
timers.

The search addon's tests (SearchEngine, SearchLineCache, DecorationManager
and the Playwright `SearchAddon.test.ts`) are ported in full. They run on
`test/.../addon_search/search_test_terminal.dart`, the headless public
terminal with a `SelectionModel` and a `DecorationService` standing in for
the browser terminal; its `getSelectionPositionMock` and
`registerDecorationMock` replace upstream's method assignments. An invalid
regex expects `FormatException`; the Playwright decoration options give
`matchOverviewRuler: ''` where upstream omits it; the #2444 fixture is copied
under `fixtures/` and read with `dart:io` (VM only). A case marked "New: not
upstream" covers a wide character wrapped to the next line.

## Tests not ported

| Upstream test | Reason |
| --- | --- |
| `addons/addon-webgl/src/customGlyphs/CustomGlyphRasterizer.test.ts` | tests `createPatternCanvas`; shades are drawn as device-pixel squares instead |
| `addons/addon-webgl/test/WebglCustomGlyphs.test.ts` (document adoption) | needs an iframe, the DOM and the WebGL atlas; the shade cases are in `terminal_custom_glyphs_test.dart` with pixel tests |
| `addons/addon-unicode-graphemes/benchmark/` | a benchmark |
| `src/browser/services/MouseService.test.ts` (`AltMouseCursorController`, document listeners of several windows) | DOM only; covered by the `mouseEventsEnabled` and `mouseCursor` tests |
| `src/browser/Clipboard.test.ts` (DOM copy and paste events) | needs a DOM |
| `src/browser/input/CompositionHelper.test.ts`, `src/browser/Terminal.test.ts`, `Terminal2.test.ts` | need the DOM textarea or the whole browser terminal |

## Dart API adaptations

Foundation (common, typings); later parts follow these.

- **Events.** `IEvent<T>` is exactly the typedef above: upstream's optional
  `thisArgs` and `disposables` are dropped (closures bind `this`; register the
  result yourself). `Emitter<T> implements IDisposable`; an `Emitter<void>`
  fires with `fire(null)` and is listened to with `(_) {...}`.
  `EventUtils.forward/map/any/runAndSubscribe` are static; `any` takes a list.
- **Disposables.** `Disposable` has `register<T extends IDisposable>(T o)`
  (upstream `_register`), `store` (upstream `_store`) and `Disposable.none`.
  Field initializers cannot call `register`, so emitters are
  `late final _onFoo = register(Emitter<Foo>());` plus
  `late final IEvent<Foo> onFoo = _onFoo.event;`, or are set up in the
  constructor body where upstream relies on construction order.
  `disposeAll(iterable)` replaces `dispose(array)`, `combinedDisposable` takes
  a list. `DisposableStore` has `add/clear/dispose/isDisposed`.
- **Errors.** `throw new Error(msg)` is a Dart `Error` with upstream's message
  (`ArgumentError`, `RangeError` or `StateError`, whichever fits).
- **Constants.** `SCREAMING_CASE` constants are lowerCamelCase too:
  `DEFAULT_ATTR` → `defaultAttr`, `NULL_CELL_CHAR` → `nullCellChar`,
  `DEFAULT_OPTIONS` → `defaultOptions`, `CHARSETS` → `charsets`,
  `XTERM_VERSION` → `xtermVersion`. String `const enum`s are classes of
  `String` constants (`C0.ESC` → `C0.esc`, `C1ESCAPED.ST` → `C1ESCAPED.st`).
  Regular `enum LogLevelEnum` is ints too.
- **String unions** are `String` (named ones get a typedef:
  `CursorStyle`, `CursorInactiveStyle`, `LogLevel`); `FontWeight` is `Object`
  (a `String` or a `num`).
- **Object-literal interfaces** (options, events, positions, state bags such
  as `IDecPrivateModes`, `ICoreMouseEvent`, `IBufferRange`) are classes with
  named constructor parameters and mutable fields (final where upstream says
  `readonly`); `IColor`, `IBufferRange`, `IBufferCellPosition` and the viewport
  range classes have `==`. Interfaces that objects implement are
  `abstract interface class`es: mutable members are `abstract` fields,
  members that upstream implements with a getter are getters. Optional methods
  (`ILinkHandler.hover`) are nullable function fields. Inline object types in
  events and returns are named records: `IEvent<({int start, int end})>`,
  `getWrappedRangeForLine` → `({int first, int last})`,
  `onBufferActivate` → `({IBuffer activeBuffer, IBuffer inactiveBuffer})`.
  The union `IColorEvent` element is the sealed `IColorRequest`.
- **Tuples.** `CharData` is the record `(int attr, String char, int width,
  int code)`: `value[CHAR_DATA_CHAR_INDEX]` is `value.$2`. Homogeneous tuples
  are lists: `IColorRGB` and `BufferIndex` are `List<int>`, `ParamsArray` is
  `List<Object>` (`int` or `List<int>`).
- **Rest parameters** are a trailing list: `splice(start, count, [items])`,
  `ILogService.debug(message, [optionalParams])`, `ILogger.info(message,
  [args])`. A function in `optionalParams` is evaluated lazily.
- **Promises.** `boolean | Promise<boolean>` is `FutureOr<bool>`;
  `void | Promise<boolean>` is `Future<bool>?`.
- **Parser types.** `IFunctionIdentifier.final` is `final_`. The fallback
  handler typedefs take the payload as a required `Object?` (null where
  upstream omits it); `ExecuteHandlerType` is `bool Function()` (the `ident`
  is never passed). `IHandlerCollection<T>` is `Map<int, List<T>>`.
- **Options.** One options class for all: typings' `ITerminalOptions` has
  every option nullable (null = unset), including `ITerminalInitOnlyOptions`'
  `cols`/`rows`/`showCursorImmediately` (it implements that interface, since
  Dart has no intersection type) and the internal `termName`; `Services.ts`,
  `common/Types.ts` and the headless typings re-export it. It has
  `operator []`, `operator []=` and `keys` (the set keys) for upstream's
  `for (key in options)` loops. `Required<ITerminalOptions>` is
  `RequiredTerminalOptions`: typed non-null accessors (`int get scrollback`)
  over `operator []`/`[]=`, `keys` and `allKeys`. `OptionsService.rawOptions`
  is a `RawTerminalOptions` (fields); `options` is a validating proxy that
  throws `ArgumentError` for unknown keys. A new proxy (the headless
  `Terminal.options`) only overrides the two index operators.
  `onOptionChange` fires the key string; `onSpecificOptionChange<T>(key,
  (T value) {...})`. Numbers: sizes and ratios (`fontSize`, `lineHeight`,
  `letterSpacing`, `minimumContrastRatio`, `*ScrollSensitivity`,
  `IScrollbarOptions.width`) are `double`, the rest `int`.
- **Services.** No `serviceBrand`. `ILogService` messages are `String`.
  DOM types in service and typings signatures (`HTMLElement`, `MouseEvent`,
  `WheelEvent`) are `Object`. `IInternalDecoration._indexedStartLine` is
  `indexedStartLine`.
- **Typings.** `xterm_headless.dart` re-exports the declarations it shares
  with `xterm.dart` (Dart has no structural typing, so the core implements
  them once); only `Terminal` and `ITerminalAddon` are headless declarations.
  The headless `ITerminalOptions`, `ITheme` (with `selection` added) and
  `IParser` (`FutureOr<bool>` callbacks) are thus the xterm supersets, which
  the core accepts at runtime anyway. `Terminal.options` gets a
  `RequiredTerminalOptions` and sets an `ITerminalOptions`; the constructor
  and static `strings` live on the implementing class. Both the typings and
  the core declare `IBuffer`, `IBufferLine`, `IMarker`, `IModes` (and
  `IBufferCell`): core files import the typings `as api`. The internal
  buffer `IMarker` implements `api.IMarker`; `CellData` implements
  `api.IBufferCell`.
- **Platform.** `isMac`, `isWindows`, ... are getters over values the
  embedder sets with `initPlatform(userAgent:, platform:)`; until then they are
  upstream's Node.js values (`isNode` true, the rest false).
- **Timers.** `TaskQueue` tasks are `Object? Function()` returning `true` to
  run again; `IdleTaskQueue` is a typedef of `PriorityTaskQueue`.
  `IntervalTimer.cancelAndSet` has no window `context`. Times are `int`
  milliseconds.
- **JavaScript semantics kept.** `CircularList` indexes with `remainder`, so
  a negative cyclic index reads null as JavaScript's `%` and array read do;
  `SortedList` sorts stably; `Color` rounds halves up like `Math.round` and
  masks results with `& 0xFFFFFFFF` where upstream uses `>>> 0`.

Later parts:

- **Parser.** `parse(data, length, [promiseResult])` returns `Future<bool>?`:
  null when done synchronously, else a future to await before calling
  `parse` again with the same chunk and the awaited result. A Dart `async`
  function always pauses the parser, so only handlers that wait are async.
  `collect` and `ident` emulate JavaScript's 32-bit shifts with
  `& 0xFFFFFFFF`. Handlers given as object literals are `FnDcsHandler` /
  `FnApcHandler` in tests; the test accessors are renamed where they clash
  (`params` → `paramsArray`, `collect` → `collectString`, `test()` →
  `testSeq`). `getSubParams` returns a view valid only during the handler.
- **Keyboard.** `IKeyboardEvent` has every field required;
  `evaluateKeyboardEvent(ev, applicationCursorMode, isMac, macOptionIsMeta)`
  as upstream. `WriteBuffer.writeSync` is not `@Deprecated`.
- **InputHandler.** Where `IInputHandler` declares an optional `collect`
  (`scrollDown`, `setMode`, `resetMode`, `deviceStatus`, `softReset`,
  `setCursorStyle`, `setScrollRegion`) the method takes `[String? collect]`
  and ignores it (Dart overrides must accept what the interface does). Debug
  logs pass closures, evaluated only at debug level. Upstream quirks are kept:
  DECRQSS for an unknown cursor style reports `NaN`, OSC 4/104 with an index
  past 255 is invalid, selecting an unknown G set is a no-op. `print` uses a
  precomputed ASCII table.
- **Terminal.** `CoreTerminal`'s protected members are public, emitters as
  `on*Emitter`. Options that may only be set in the constructor throw
  `ArgumentError` when set through `options`; the proposed API without
  `allowProposedApi`, disposing an addon that is not loaded, and a buffer
  that is neither normal nor alt throw `StateError`. `modes` builds a new
  object on each read; `markers` is the live list.
- **Search addon.** Upstream's addon runs on the browser `Terminal`; the
  typings add `ISearchTerminal`, the headless `Terminal` plus the browser
  one's `onSelectionChange`, `registerDecoration`, `hasSelection`,
  `getSelection`, `getSelectionPosition` (the selection service's 0-based
  `[x, y]` start and exclusive end), `clearSelection` and `select`, which the
  embedder implements over its selection and decoration services.
  `SearchAddon.activate` narrows `ITerminalAddon`'s parameter with
  `covariant`, so `loadAddon` must hand the addon the `ISearchTerminal` itself
  (a subclass of the public `Terminal` does). `ISearchOptions`,
  `ISearchDecorationOptions`, `ISearchAddonOptions` (a nullable
  `highlightLimit`: upstream's `Partial`), `ISearchResultChangeEvent` and
  `ISearchResult` are classes, the last two with `==`; `LineCacheEntry` is
  the record `(String lineAsString, List<int> lineOffsets)`; `IHighlight` and
  `IMultiHighlight` are classes, and `IMultiHighlight` implements the
  tracker's `ISelectedDecoration`. Getter/setter pairs over a field are
  fields. `indexOf`/`lastIndexOf` clamp their start as JavaScript does, and a
  `g` regex's `exec` from `lastIndex` is `allMatches` from there. Upstream
  quirks are kept: `incremental` is never read, and new options with the same
  term do not highlight again (the options are compared with themselves). The
  delayed search after new output runs with `''` if the term was cleared
  meanwhile (upstream: `undefined`, which finds nothing the same way).
