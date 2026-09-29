import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../vs/editor/common/core/range.dart';
import '../vs/editor/common/languages/language_configuration.dart'
    show CharacterPair, FoldingRules;
import 'bracket_matching.dart';
import 'document_snapshot.dart';
import 'editor_decorations.dart';
import 'editor_folding.dart';
import 'editor_keybindings.dart';
import 'editor_minimap.dart';
import 'editor_scrollbar.dart';
import 'editor_surface_controller.dart';
import 'editor_view_painters.dart';
import 'editor_view_theme.dart';
import 'viewport_layout.dart';

export 'editor_decorations.dart'
    show EditorDecoration, EditorDecorationKind, EditorUnderlineStyle;
export 'editor_view_painters.dart' show EditorRenderWhitespace;
export 'editor_view_theme.dart' show EditorViewTheme;

/// Opt-in native-painted editor view, not a drop-in IdeEditor replacement.
///
/// Monaco-style view parts: glyph margin, line numbers, indent/marker
/// folding, virtualized text with fixed line height, current line, multiple
/// selections and blinking carets, bracket and selection-occurrence
/// highlights, indent guides, decorations, overlay scrollbars with an
/// overview ruler, and a minimap. Keys and native selectors are delegated to
/// [handleEditorKeyEvent]/[handleEditorSelector]; the surface implements
/// [EditorViewHost] for their view queries.
///
/// This is not complete accessibility or Monaco parity: there are no
/// word-navigation semantics, context menus/selection handles, column
/// selection, sticky scroll, glyph-margin widgets, or tab-stop rendering
/// (tabs use Flutter paragraph shaping).
class EditorSurface extends StatefulWidget {
  const EditorSurface({
    super.key,
    required this.controller,
    this.focusNode,
    this.style = const TextStyle(
      fontFamily: 'monospace',
      fontSize: 14,
      height: 1.35,
      color: Color(0xffdddddd),
    ),
    this.backgroundColor = const Color(0xff1e1e1e),
    this.selectionColor = const Color(0xff264f78),
    this.caretColor = const Color(0xffaeafad),
    this.wrap = false,
    this.styledLines,
    this.readOnly = false,
    this.theme = const EditorViewTheme(),
    this.decorations = const [],
    this.lineNumbers = true,
    this.glyphMargin = true,
    this.folding = true,
    this.foldingRules,
    this.brackets,
    this.matchBrackets = true,
    this.selectionHighlight = true,
    this.indentGuides = true,
    this.renderWhitespace = EditorRenderWhitespace.none,
    this.showMinimap = true,
    this.minimapWidth = 80,
    this.scrollBeyondLastLine = true,
    this.onKeyEvent,
    this.onHover,
    this.onContentPointerDown,
    this.onContextMenu,
    this.onViewChanged,
    this.contentCursor,
  });

  final EditorSurfaceController controller;
  final FocusNode? focusNode;
  final TextStyle style;
  final Color backgroundColor;

  /// Selection fill while focused (`editor.selectionBackground`).
  final Color selectionColor;
  final Color caretColor;
  final bool wrap;

  /// Optional one-based token spans, supplied by the active theme/tokenizer.
  /// Read lazily for painted lines; spans whose text no longer matches a
  /// line are ignored until the caller supplies fresh ones.
  final Map<int, List<TextSpan>>? styledLines;

  /// Allows selection and copying, but no user-originated text mutations.
  /// Programmatic changes to [controller] are still reflected in the surface.
  final bool readOnly;

  /// Colors for gutter, highlights, scrollbars and minimap.
  final EditorViewTheme theme;

  /// View decorations (find matches, diagnostics) over the current text.
  /// Only those intersecting visible lines are painted; pass the same list
  /// instance while unchanged.
  final List<EditorDecoration> decorations;

  final bool lineNumbers;

  /// Reserves Monaco's glyph margin (one line height) left of line numbers.
  final bool glyphMargin;

  /// Indentation-based folding with chevrons in the gutter.
  final bool folding;

  /// Folding markers/off-side rule; defaults to the controller's
  /// `languageConfiguration.folding`.
  final FoldingRules? foldingRules;

  /// Bracket pairs for matching; defaults to the controller's
  /// `languageConfiguration.brackets`, then `()[]{}`.
  final List<CharacterPair>? brackets;
  final bool matchBrackets;

  /// Highlights other visible occurrences of a single-line selection.
  final bool selectionHighlight;
  final bool indentGuides;
  final EditorRenderWhitespace renderWhitespace;

  /// Minimap on the right; hidden automatically in narrow editors.
  final bool showMinimap;
  final double minimapWidth;

  /// Allows scrolling until the last line is at the top of the viewport.
  final bool scrollBeyondLastLine;

  /// Sees focused key events before the editor's own bindings; return
  /// [KeyEventResult.handled] to consume one (e.g. a suggest widget's arrows).
  final KeyEventResult Function(KeyEvent event)? onKeyEvent;

  /// The text offset under the mouse (null once it leaves the text), with
  /// the pointer's surface-local position, for hovers and links.
  final void Function(int? offset, Offset localPosition)? onHover;

  /// A primary-button press on the text at [offset]; return true to consume
  /// it (e.g. Cmd/Ctrl+click to go to a definition).
  final bool Function(int offset, PointerDownEvent event)? onContentPointerDown;

  /// A secondary-button press on the text, at [globalPosition]: the caret
  /// has moved there unless it was in a selection (`ContextMenuController`).
  final ValueChanged<Offset>? onContextMenu;

  /// Called after the view scrolls or is laid out anew, so overlays anchored
  /// with [EditorSurfaceView] can follow.
  final VoidCallback? onViewChanged;

  /// Overrides the text cursor over the content (e.g. a pointer on a link).
  final MouseCursor? contentCursor;

  @override
  State<EditorSurface> createState() => _EditorSurfaceState();
}

/// View geometry an [EditorSurface]'s state exposes (through its key) for
/// anchoring overlays such as hovers and the suggest widget. Rects are in
/// the surface's local coordinates; null before the first layout.
abstract interface class EditorSurfaceView {
  /// The caret box at [offset] (one line tall), clipped to nothing.
  Rect? caretRectAt(int offset);

  /// The union of the boxes of `[start, end)` on the line of [start].
  Rect? rangeRectAt(int start, int end);

  /// The text area (right of the gutter, left of the minimap).
  Rect? get textArea;

  /// The glyph margin cell of [lineNumber], when visible.
  Rect? glyphMarginRect(int lineNumber);

  /// The text offset at a surface-local [position], or null outside the
  /// text of a line.
  int? textOffsetAt(Offset position);

  /// Scrolls so that `[start, end)` is visible, centered when it is not.
  void revealRange(int start, int end);

  double get lineHeight;
}

enum _Part {
  none,
  content,
  gutter,
  minimap,
  verticalScrollbar,
  horizontalScrollbar,
}

enum _DragMode {
  none,
  text,
  word,
  line,
  column,
  verticalScrollbar,
  horizontalScrollbar,
  minimap,
}

class _EditorSurfaceState extends State<EditorSurface>
    with TextInputClient, TickerProviderStateMixin
    implements EditorViewHost, EditorSurfaceView {
  final GlobalKey _paintKey = GlobalKey();
  late FocusNode _focusNode;
  late bool _ownsFocusNode;
  TextInputConnection? _connection;
  bool _updatingFromPlatform = false;
  bool _scrollToCaret = false;

  // Layout and its inputs.
  ViewportLayout? _layout;
  DocumentSnapshot? _layoutSnapshot;
  TextStyle? _layoutStyle;
  Size? _layoutSize;
  TextDirection? _layoutDirection;
  TextScaler? _layoutScaler;
  bool? _layoutWrap;
  Map<int, List<TextSpan>>? _layoutStyledLines;
  HiddenLineRanges? _layoutHidden;
  int? _layoutTabSize;
  EditorViewGeometry? _geometry;
  EditorGutterGlyphs? _glyphs;
  double _scrollLeft = 0;
  double _scrollTop = 0;

  // Folding.
  final EditorFoldingModel _folding = EditorFoldingModel();
  int _foldingVersion = 0;
  Timer? _foldTimer;
  DocumentSnapshot? _foldTimerSnapshot;
  Object? _foldingConfig;
  List<TextSelection> _revealedSelections = const [];
  static const int _syncFoldingLineLimit = 3000;

  // Decorations, brackets and caches.
  List<EditorDecoration>? _decorationSource;
  SortedDecorations _decorations = SortedDecorations.empty;
  Object? _bracketKey;
  BracketMatch? _bracketMatch;
  final IndentGuideCache _guideCache = IndentGuideCache();
  final MinimapCache _minimapCache = MinimapCache();
  final OverviewRulerCache _overviewCache = OverviewRulerCache();

  // Caret blinking.
  final ValueNotifier<bool> _caretVisible = ValueNotifier(true);
  Timer? _blinkTimer;
  bool _tickersEnabled = true;
  static const Duration _blinkInterval = Duration(milliseconds: 530);

  // Scrollbars.
  late final AnimationController _scrollbarFade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );
  Timer? _scrollbarHideTimer;
  ScrollbarPart _hoveredScrollbar = ScrollbarPart.none;
  bool _pointerInside = false;
  _Part _hover = _Part.none;

  // Pointer interaction.
  _DragMode _dragMode = _DragMode.none;
  int? _dragPointer;
  int _dragAnchor = 0;
  TextRange _dragWordAnchor = TextRange.empty;
  Offset _dragPosition = Offset.zero;
  Offset _dragStart = Offset.zero;
  double _dragStartScroll = 0;
  Timer? _autoScrollTimer;
  Duration? _lastClickTime;
  Offset? _lastClickPosition;
  int _clickCount = 0;
  static const Duration _multiClickTimeout = Duration(milliseconds: 500);
  bool _focusFromPointer = false;

  bool get _isSelectionDrag =>
      _dragPointer != null &&
      (_dragMode == _DragMode.text ||
          _dragMode == _DragMode.word ||
          _dragMode == _DragMode.line);

  @override
  void initState() {
    super.initState();
    _ownsFocusNode = widget.focusNode == null;
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChange);
    widget.controller.addListener(_onControllerChange);
  }

  @override
  void didUpdateWidget(covariant EditorSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChange);
      widget.controller.addListener(_onControllerChange);
      if (_connection?.attached == true) {
        _connection!.setEditingState(widget.controller.value);
      }
    }
    if (oldWidget.focusNode != widget.focusNode) {
      _focusNode.removeListener(_onFocusChange);
      _detach();
      if (_ownsFocusNode) _focusNode.dispose();
      _ownsFocusNode = widget.focusNode == null;
      _focusNode = widget.focusNode ?? FocusNode();
      _focusNode.addListener(_onFocusChange);
      if (_focusNode.hasFocus) _onFocusChange();
    }
    if (oldWidget.readOnly != widget.readOnly) _onFocusChange();
  }

  void _onFocusChange() {
    // Focus from a pointer press must not reveal the old caret (e.g. when
    // clicking the minimap or a scrollbar); the press sets its own selection.
    if (_focusNode.hasFocus && !_focusFromPointer) _scrollToCaret = true;
    _focusFromPointer = false;
    if (_focusNode.hasFocus && !widget.readOnly) {
      if (_connection?.attached != true) {
        _connection = TextInput.attach(
          this,
          TextInputConfiguration(
            viewId: View.of(context).viewId,
            inputType: TextInputType.multiline,
            inputAction: TextInputAction.newline,
            autocorrect: false,
            smartDashesType: SmartDashesType.disabled,
            smartQuotesType: SmartQuotesType.disabled,
            enableSuggestions: false,
            enableInteractiveSelection: false,
          ),
        );
      }
      _connection!.setEditingState(widget.controller.value);
      _connection!.show();
      _scheduleGeometry();
    } else {
      _detach();
    }
    _restartBlink();
    if (mounted) setState(() {});
  }

  void _detach() {
    _connection?.close();
    _connection = null;
  }

  void _onControllerChange() {
    // While drag-selecting, auto-scroll (not caret reveal) moves the view.
    if (!_isSelectionDrag) _scrollToCaret = true;
    if (!_updatingFromPlatform && _connection?.attached == true) {
      _connection!.setEditingState(widget.controller.value);
    }
    _restartBlink();
    if (mounted) setState(() {});
  }

  /// Carets stay solid while typing or moving, then blink (Monaco `blink`).
  void _restartBlink() {
    _blinkTimer?.cancel();
    _blinkTimer = null;
    _caretVisible.value = true;
    if (!mounted || !_focusNode.hasFocus || !_tickersEnabled) return;
    _blinkTimer = Timer.periodic(_blinkInterval, (_) {
      _caretVisible.value = !_caretVisible.value;
    });
  }

  @override
  TextEditingValue get currentTextEditingValue => widget.controller.value;

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  void updateEditingValue(TextEditingValue value) {
    if (!_canEdit || _connection?.attached != true) return;
    _updatingFromPlatform = true;
    try {
      widget.controller.value = value;
    } finally {
      _updatingFromPlatform = false;
    }
    // Auto-closing, surround and multi-cursor replication can make the model
    // differ from what the platform sent; the platform must see the result.
    final result = widget.controller.value;
    if (result != value && _connection?.attached == true) {
      _connection!.setEditingState(result);
    }
  }

  @override
  void performAction(TextInputAction action) {
    if (!_focusNode.hasFocus) return;
    if (_canEdit && action == TextInputAction.newline) {
      widget.controller.newline();
    }
    if (action == TextInputAction.done) _focusNode.unfocus();
  }

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}

  @override
  void showAutocorrectionPromptRect(int start, int end) {}

  @override
  bool onFocusReceived() {
    _focusNode.requestFocus();
    return true;
  }

  @override
  void connectionClosed() {
    _connection = null;
    _focusNode.unfocus();
  }

  bool get _canEdit => mounted && _focusNode.hasFocus && !widget.readOnly;

  bool get _canCopy {
    final value = widget.controller.value;
    return mounted &&
        _focusNode.hasFocus &&
        value.selection.isValid &&
        !value.selection.isCollapsed &&
        value.selection.end <= value.text.length;
  }

  bool get _canCopyOrLine {
    final selection = widget.controller.value.selection;
    return mounted && _focusNode.hasFocus && selection.isValid;
  }

  void _requestSemanticFocus() {
    if (!_focusNode.canRequestFocus) return;
    _focusNode.requestFocus();
    if (!widget.readOnly) _connection?.show();
  }

  void _setSemanticText(String text) {
    if (!_canEdit) return;
    // A full accessibility replacement commits any active composition, just
    // like Flutter's editable text semantics. Never normalize the raw text.
    widget.controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _setSemanticSelection(TextSelection selection) {
    if (!mounted || !_focusNode.hasFocus || !selection.isValid) return;
    // Selection commands use the controller's composition-commit policy;
    // exposing semantics alone never changes the editing value or composition.
    widget.controller.select(selection.baseOffset, selection.extentOffset);
  }

  void _moveSemanticCursor(int direction, bool extendSelection) {
    if (!mounted || !_focusNode.hasFocus) return;
    widget.controller.moveHorizontal(
      direction,
      extend: extendSelection,
      collapseSelection: false,
    );
  }

  void _invokeTextAction(Intent intent) {
    final actionContext = _paintKey.currentContext;
    if (mounted && _focusNode.hasFocus && actionContext != null) {
      Actions.maybeInvoke(actionContext, intent);
    }
  }

  Future<void> _copyOrCut(CopySelectionTextIntent intent) {
    final controller = widget.controller;
    return intent.collapseSelection
        ? controller.cut(
            canEdit: () => _canEdit && identical(widget.controller, controller),
          )
        : controller.copy();
  }

  Future<void> _paste(PasteTextIntent intent) {
    final controller = widget.controller;
    return controller.paste(
      canEdit: () => _canEdit && identical(widget.controller, controller),
    );
  }

  @override
  void performSelector(String selectorName) {
    if (!_focusNode.hasFocus) return;
    handleEditorSelector(widget.controller, this, selectorName);
  }

  // EditorViewHost.

  @override
  bool get canEdit => _canEdit;

  @override
  void invokeTextAction(Intent intent) => _invokeTextAction(intent);

  @override
  int get pageRowCount {
    final layout = _layout;
    if (layout == null || layout.lineHeight <= 0) return 1;
    return math.max(
      1,
      (layout.viewportSize.height / layout.lineHeight).floor(),
    );
  }

  /// Moves by view rows (collapsed folds count as one row). Moving above the
  /// first row goes to the document start and below the last row to its end,
  /// like Monaco's cursor up/down.
  @override
  ({int offset, double x}) verticalTarget(
    int offset,
    int rows, {
    double? preferredX,
  }) {
    final layout = _layout;
    if (layout == null) return (offset: offset, x: preferredX ?? 0);
    final length = layout.snapshot.text.length;
    final origin = layout.caretRect(offset.clamp(0, length));
    final x = preferredX ?? origin.left + layout.horizontalScrollOffset;
    final y =
        origin.center.dy +
        layout.verticalScrollOffset +
        rows * layout.lineHeight;
    if (y < 0) return (offset: 0, x: x);
    if (y >= layout.contentHeight) return (offset: length, x: x);
    final target = layout.hitTest(
      Offset(
        x - layout.horizontalScrollOffset,
        y - layout.verticalScrollOffset,
      ),
    );
    return (offset: target, x: x);
  }

  // EditorSurfaceView.

  @override
  double get lineHeight => _layout?.lineHeight ?? 0;

  @override
  Rect? get textArea => _geometry?.contentRect;

  @override
  Rect? caretRectAt(int offset) {
    final layout = _layout;
    final geometry = _geometry;
    if (layout == null || geometry == null) return null;
    final length = layout.snapshot.text.length;
    final caret = layout.caretRect(offset.clamp(0, length));
    return Rect.fromLTWH(
      caret.left,
      caret.top,
      caret.width,
      layout.lineHeight,
    ).shift(geometry.contentRect.topLeft);
  }

  @override
  Rect? rangeRectAt(int start, int end) {
    final layout = _layout;
    final geometry = _geometry;
    if (layout == null || geometry == null) return null;
    final a = caretRectAt(start);
    if (a == null) return null;
    final snapshot = layout.snapshot;
    final line = snapshot.positionAtOffset(start).lineNumber - 1;
    final clampedEnd = end.clamp(start, snapshot.contentEnds[line]);
    final b = layout
        .caretRect(clampedEnd, affinity: TextAffinity.upstream)
        .shift(geometry.contentRect.topLeft);
    return Rect.fromLTRB(
      a.left,
      a.top,
      math.max(a.left + 1, b.left),
      a.top + layout.lineHeight,
    );
  }

  @override
  Rect? glyphMarginRect(int lineNumber) {
    final layout = _layout;
    final geometry = _geometry;
    if (layout == null || geometry == null || !widget.glyphMargin) return null;
    final snapshot = layout.snapshot;
    if (lineNumber < 1 || lineNumber > snapshot.lineCount) return null;
    final caret = layout.caretRect(snapshot.lineStarts[lineNumber - 1]);
    final top = caret.top + geometry.contentRect.top;
    if (top + layout.lineHeight < 0 || top > geometry.size.height) return null;
    return Rect.fromLTWH(0, top, geometry.glyphMarginWidth, layout.lineHeight);
  }

  @override
  int? textOffsetAt(Offset position) {
    final layout = _layout;
    final geometry = _geometry;
    if (layout == null || geometry == null) return null;
    if (!geometry.contentRect.contains(position)) return null;
    final local = position - geometry.contentRect.topLeft;
    final offset = layout.hitTest(local);
    final snapshot = layout.snapshot;
    final line = snapshot.positionAtOffset(offset).lineNumber - 1;
    final top = layout.caretRect(offset).top;
    // Below the last line (hitTest clamps).
    if (local.dy >= top + layout.lineHeight) return null;
    final end = layout.caretRect(
      snapshot.contentEnds[line],
      affinity: TextAffinity.upstream,
    );
    if (local.dx > end.left + 1) return null;
    return offset;
  }

  @override
  void revealRange(int start, int end) {
    final layout = _layout;
    if (layout == null) return;
    final length = layout.snapshot.text.length;
    final caret = layout.caretRect(start.clamp(0, length));
    final h = layout.viewportSize.height;
    if (caret.top >= 0 && caret.bottom <= h) return;
    _scrollToCaret = false;
    _setScroll(top: _scrollTop + caret.top - (h - layout.lineHeight) / 2);
  }

  // Scrolling.

  double _scrollHeight(ViewportLayout layout) {
    final viewport = layout.viewportSize.height;
    final extra = widget.scrollBeyondLastLine
        ? math.max(0.0, viewport - layout.lineHeight)
        : 0.0;
    return math.max(layout.contentHeight + extra, viewport);
  }

  double _maxScrollTop(ViewportLayout layout) =>
      math.max(0.0, _scrollHeight(layout) - layout.viewportSize.height);

  double _scrollWidth(ViewportLayout layout) => layout.wrap
      ? layout.viewportSize.width
      : layout.contentWidth +
            EditorCaretPainter.caretWidth +
            4 * layout.averageCharWidth;

  double _maxScrollLeft(ViewportLayout layout) =>
      math.max(0.0, _scrollWidth(layout) - layout.viewportSize.width);

  void _setScroll({double? top, double? left}) {
    final layout = _layout;
    if (layout == null) return;
    final nextTop = (top ?? _scrollTop).clamp(0.0, _maxScrollTop(layout));
    final nextLeft = (left ?? _scrollLeft).clamp(0.0, _maxScrollLeft(layout));
    if (nextTop == _scrollTop && nextLeft == _scrollLeft) return;
    setState(() {
      _scrollTop = nextTop;
      _scrollLeft = nextLeft;
      layout.setScrollOffset(horizontal: nextLeft, vertical: nextTop);
    });
    _revealScrollbars();
    _scheduleGeometry();
    widget.onViewChanged?.call();
  }

  void _scrollBy(double dx, double dy) {
    _scrollToCaret = false;
    _setScroll(top: _scrollTop + dy, left: _scrollLeft + dx);
  }

  void _revealScrollbars() {
    _scrollbarFade.value = 1;
    _scheduleScrollbarHide();
  }

  void _scheduleScrollbarHide() {
    _scrollbarHideTimer?.cancel();
    _scrollbarHideTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted || _pointerInside || _dragMode != _DragMode.none) return;
      _scrollbarFade.animateTo(0);
    });
  }

  void _scheduleGeometry() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _layout == null || _geometry == null) return;
      final render = _paintKey.currentContext?.findRenderObject();
      if (render is! RenderBox || !render.hasSize) return;
      final layout = _layout!;
      final origin = _geometry!.contentRect.topLeft;
      final selection = widget.controller.value.selection;
      final offset = selection.isValid ? selection.extentOffset : 0;
      final length = layout.snapshot.text.length;
      final caretRect = layout.caretRect(
        offset.clamp(0, length),
        affinity: selection.affinity,
      );
      final caret = caretRect;
      if (_scrollToCaret) {
        _scrollToCaret = false;
        final revealOffset = widget.controller.revealOffset.clamp(0, length);
        final caret = revealOffset == offset
            ? caretRect
            : layout.caretRect(revealOffset);
        final h = layout.viewportSize.height;
        final w = layout.viewportSize.width;
        final nextV = caret.top < 0
            ? _scrollTop + caret.top
            : caret.bottom > h
            ? _scrollTop + caret.bottom - h
            : _scrollTop;
        final nextH = caret.left < 0
            ? _scrollLeft + caret.left
            : caret.left + EditorCaretPainter.caretWidth > w
            ? _scrollLeft + caret.left + EditorCaretPainter.caretWidth - w
            : _scrollLeft;
        if (nextV != _scrollTop || nextH != _scrollLeft) {
          _setScroll(top: nextV, left: nextH);
          return; // _setScroll schedules the IME geometry again.
        }
      }
      // Selection/reveal still scrolls a read-only or unfocused surface. Only
      // the platform IME geometry requires an attached input connection.
      if (_connection?.attached != true) return;
      _connection!.setEditableSizeAndTransform(
        render.size,
        render.getTransformTo(null),
      );
      _connection!.updateStyle(
        TextInputStyle(
          fontFamily: widget.style.fontFamily,
          fontSize: widget.style.fontSize,
          fontWeight: widget.style.fontWeight,
          textDirection: Directionality.of(context),
          textAlign: TextAlign.start,
        ),
      );
      _connection!.setCaretRect(caret.shift(origin));
      final composing = widget.controller.value.composing;
      var composingRect = caret;
      if (composing.isValid &&
          !composing.isCollapsed &&
          composing.start >= 0 &&
          composing.end <= length) {
        final boxes = layout.selectionRects(
          Range.fromPositions(
            layout.snapshot.positionAtOffset(composing.start),
            layout.snapshot.positionAtOffset(composing.end),
          ),
        );
        composingRect = boxes.isNotEmpty
            ? boxes.reduce((a, b) => a.expandToInclude(b))
            : layout.caretRect(composing.start);
      }
      _connection!.setComposingRect(composingRect.shift(origin));
    });
  }

  // Folding.

  FoldingRules? get _foldingRules =>
      widget.foldingRules ?? widget.controller.languageConfiguration?.folding;

  void _syncFolding(DocumentSnapshot snapshot) {
    if (!widget.folding) {
      if (_folding.hasCollapsed && _folding.unfoldAll()) _foldingVersion++;
      return;
    }
    if (_folding.updateSnapshot(
      snapshot,
      shiftRegions: snapshot.lineCount > _syncFoldingLineLimit,
    )) {
      _foldingVersion++;
    }
    final config = (_foldingRules, widget.controller.tabSize);
    final configChanged = config != _foldingConfig;
    if (!_folding.isStale && !configChanged) return;
    _foldingConfig = config;
    if (snapshot.lineCount <= _syncFoldingLineLimit) {
      _foldTimer?.cancel();
      _foldTimer = null;
      _recomputeFolding();
    } else if (configChanged ||
        _foldTimer == null ||
        !identical(_foldTimerSnapshot, snapshot)) {
      _foldTimer?.cancel();
      _foldTimerSnapshot = snapshot;
      // Debounced like Monaco's folding update; regions shift meanwhile.
      _foldTimer = Timer(const Duration(milliseconds: 250), () {
        _foldTimer = null;
        if (mounted) setState(_recomputeFolding);
      });
    }
  }

  void _recomputeFolding() {
    _folding.recompute(
      tabSize: widget.controller.tabSize,
      rules: _foldingRules,
      selections: widget.controller.selections,
    );
    _foldingVersion++;
  }

  void _revealSelectionsInFolds(List<TextSelection> selections) {
    if (listEquals(selections, _revealedSelections)) return;
    _revealedSelections = selections;
    if (!_folding.hasCollapsed) return;
    final snapshot = widget.controller.document.snapshot;
    final lines = [
      for (final selection in selections)
        if (selection.isValid) ...[
          snapshot.positionAtOffset(selection.baseOffset).lineNumber,
          snapshot.positionAtOffset(selection.extentOffset).lineNumber,
        ],
    ];
    if (_folding.reveal(lines)) _foldingVersion++;
  }

  /// Toggles the fold headed by [lineNumber]. Collapsing moves cursors that
  /// would become hidden to the end of the header line.
  void _toggleFold(int lineNumber) {
    if (!_folding.toggle(lineNumber)) return;
    setState(() => _foldingVersion++);
    final hidden = _folding.hiddenLines;
    if (hidden.isEmpty) return;
    final controller = widget.controller;
    final snapshot = controller.document.snapshot;
    var moved = false;
    final next = <TextSelection>[];
    for (final selection in controller.selections) {
      if (!selection.isValid) {
        next.add(selection);
        continue;
      }
      final base = snapshot.positionAtOffset(selection.baseOffset).lineNumber;
      final extent = snapshot
          .positionAtOffset(selection.extentOffset)
          .lineNumber;
      if (hidden.isHidden(base) || hidden.isHidden(extent)) {
        moved = true;
        final header =
            hidden
                .rangeContaining(hidden.isHidden(extent) ? extent : base)!
                .$1 -
            1;
        final caret = TextSelection.collapsed(
          offset: snapshot.contentEnds[header - 1],
        );
        if (!next.contains(caret)) next.add(caret);
      } else if (!next.contains(selection)) {
        next.add(selection);
      }
    }
    if (moved) controller.setSelections(next);
  }

  // Pointer handling.

  _Part _hitPart(Offset position) {
    final geometry = _geometry;
    final layout = _layout;
    if (geometry == null || layout == null) return _Part.none;
    if (geometry.verticalScrollbarRect.contains(position)) {
      return _Part.verticalScrollbar;
    }
    if (_maxScrollLeft(layout) > 0 &&
        geometry.horizontalScrollbarRect.contains(position)) {
      return _Part.horizontalScrollbar;
    }
    if (geometry.minimapWidth > 0 && geometry.minimapRect.contains(position)) {
      return _Part.minimap;
    }
    if (position.dx < geometry.contentLeft) return _Part.gutter;
    return _Part.content;
  }

  int _registerClick(PointerDownEvent event) {
    final last = _lastClickTime;
    final lastPosition = _lastClickPosition;
    if (last != null &&
        lastPosition != null &&
        event.timeStamp - last <= _multiClickTimeout &&
        event.timeStamp >= last &&
        (event.localPosition - lastPosition).distance <= 6) {
      _clickCount = _clickCount % 3 + 1;
    } else {
      _clickCount = 1;
    }
    _lastClickTime = event.timeStamp;
    _lastClickPosition = event.localPosition;
    return _clickCount;
  }

  ScrollbarSlider _verticalSlider(
    ViewportLayout layout,
    EditorViewGeometry g,
  ) => ScrollbarSlider.compute(
    trackSize: g.verticalScrollbarRect.height,
    visibleSize: layout.viewportSize.height,
    scrollSize: _scrollHeight(layout),
    scrollPosition: _scrollTop,
  );

  ScrollbarSlider _horizontalSlider(
    ViewportLayout layout,
    EditorViewGeometry g,
  ) => ScrollbarSlider.compute(
    trackSize: g.horizontalScrollbarRect.width,
    visibleSize: layout.viewportSize.width,
    scrollSize: math.max(_scrollWidth(layout), layout.viewportSize.width),
    scrollPosition: _scrollLeft,
  );

  MinimapGeometry _minimapGeometry(
    ViewportLayout layout,
    EditorViewGeometry g,
  ) => MinimapGeometry.compute(
    height: g.minimapRect.height,
    lineHeight: layout.lineHeight,
    viewportHeight: layout.viewportSize.height,
    scrollTop: _scrollTop,
    scrollHeight: _scrollHeight(layout),
  );

  void _onPointerDown(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.mouse &&
        event.buttons == kSecondaryMouseButton) {
      _onContextMenuDown(event);
      return;
    }
    if (event.kind == PointerDeviceKind.mouse &&
        event.buttons != kPrimaryMouseButton) {
      return; // The middle button does not move the selection.
    }
    if (!_focusNode.hasFocus) {
      _focusFromPointer = true;
      _focusNode.requestFocus();
    }
    final layout = _layout;
    final geometry = _geometry;
    if (layout == null || geometry == null) return;
    final position = event.localPosition;
    _dragPointer = event.pointer;
    _dragPosition = position;
    _dragStart = position;
    _dragMode = _DragMode.none;
    switch (_hitPart(position)) {
      case _Part.verticalScrollbar:
        final slider = _verticalSlider(layout, geometry);
        if (!slider.needed) return;
        final y = position.dy - geometry.verticalScrollbarRect.top;
        if (y < slider.position || y >= slider.position + slider.size) {
          // Clicking the track pages toward the pointer.
          final page = layout.viewportSize.height;
          _scrollBy(0, y < slider.position ? -page : page);
          return;
        }
        _dragStartScroll = _scrollTop;
        setState(() => _dragMode = _DragMode.verticalScrollbar);
        _revealScrollbars();
      case _Part.horizontalScrollbar:
        final slider = _horizontalSlider(layout, geometry);
        if (!slider.needed) return;
        final x = position.dx - geometry.horizontalScrollbarRect.left;
        if (x < slider.position || x >= slider.position + slider.size) {
          final page = layout.viewportSize.width;
          _scrollBy(x < slider.position ? -page : page, 0);
          return;
        }
        _dragStartScroll = _scrollLeft;
        setState(() => _dragMode = _DragMode.horizontalScrollbar);
        _revealScrollbars();
      case _Part.minimap:
        final minimap = _minimapGeometry(layout, geometry);
        final y = position.dy - geometry.minimapRect.top;
        if (y < minimap.sliderTop ||
            y >= minimap.sliderTop + minimap.sliderHeight) {
          // Clicking outside the slider centers that line, then drags.
          _scrollToCaret = false;
          _setScroll(
            top: minimap.scrollForClick(
              y,
              layout.lineHeight,
              layout.viewportSize.height,
            ),
          );
        }
        _dragStartScroll = _scrollTop;
        setState(() => _dragMode = _DragMode.minimap);
      case _Part.gutter:
        _onGutterDown(event, layout, geometry);
      case _Part.content:
        _onContentDown(event, layout, geometry);
      case _Part.none:
        break;
    }
  }

  /// `ContextMenuController._onContextMenu`: focuses the editor and, when
  /// the press is outside every selection, moves the caret there first.
  void _onContextMenuDown(PointerDownEvent event) {
    final onContextMenu = widget.onContextMenu;
    final layout = _layout;
    final geometry = _geometry;
    if (onContextMenu == null || layout == null || geometry == null) return;
    final part = _hitPart(event.localPosition);
    if (part != _Part.content && part != _Part.gutter) return;
    if (!_focusNode.hasFocus) {
      _focusFromPointer = true;
      _focusNode.requestFocus();
    }
    if (part == _Part.content) {
      final offset = layout.hitTest(
        event.localPosition - geometry.contentRect.topLeft,
      );
      final controller = widget.controller;
      final inSelection = controller.selections.any(
        (selection) =>
            !selection.isCollapsed &&
            offset >= selection.start &&
            offset <= selection.end,
      );
      if (!inSelection) controller.select(offset, offset);
    }
    onContextMenu(event.position);
  }

  int? _lineAtY(ViewportLayout layout, double y) {
    final offset = layout.hitTest(Offset(-1e6, y));
    return layout.snapshot.positionAtOffset(offset).lineNumber;
  }

  void _onGutterDown(
    PointerDownEvent event,
    ViewportLayout layout,
    EditorViewGeometry geometry,
  ) {
    final position = event.localPosition;
    final line = _lineAtY(layout, position.dy)!;
    if (widget.folding &&
        position.dx >= geometry.decorationsLeft &&
        _folding.regionAt(line) >= 0) {
      _toggleFold(line);
      return;
    }
    _registerClick(event);
    final controller = widget.controller;
    final offset = layout.snapshot.lineStarts[line - 1];
    final primary = controller.value.selection;
    if (HardwareKeyboard.instance.isShiftPressed && primary.isValid) {
      _dragAnchor = primary.baseOffset;
      controller.selectLineAt(offset, anchorOffset: _dragAnchor);
    } else {
      _dragAnchor = offset;
      controller.selectLineAt(offset);
    }
    _dragMode = _DragMode.line;
  }

  void _onContentDown(
    PointerDownEvent event,
    ViewportLayout layout,
    EditorViewGeometry geometry,
  ) {
    final local = event.localPosition - geometry.contentRect.topLeft;
    if (_folding.hasCollapsed) {
      for (final line in layout.visibleLineNumbers) {
        if (_folding.isCollapsedAt(line) &&
            EditorTextPainter.placeholderRect(
              layout,
              _glyphs!,
              line,
            ).inflate(2).contains(local)) {
          if (_folding.setCollapsed(line, false)) {
            setState(() => _foldingVersion++);
          }
          return;
        }
      }
    }
    final controller = widget.controller;
    final offset = layout.hitTest(local);
    if (widget.onContentPointerDown?.call(offset, event) ?? false) {
      _dragPointer = null;
      return;
    }
    final clicks = _registerClick(event);
    final keyboard = HardwareKeyboard.instance;
    final primary = controller.value.selection;
    if (clicks == 2) {
      _dragWordAnchor = controller.wordRangeAt(offset);
      controller.selectWordAt(offset);
      _dragMode = _DragMode.word;
    } else if (clicks == 3) {
      _dragAnchor = offset;
      controller.selectLineAt(offset);
      _dragMode = _DragMode.line;
    } else if (keyboard.isShiftPressed && primary.isValid) {
      _dragAnchor = primary.baseOffset;
      controller.setSelections([
        TextSelection(baseOffset: _dragAnchor, extentOffset: offset),
      ]);
      _dragMode = _DragMode.text;
    } else if (keyboard.isAltPressed && keyboard.isShiftPressed) {
      _dragAnchor = primary.isValid ? primary.baseOffset : offset;
      controller.columnSelect(_dragAnchor, offset);
      _dragMode = _DragMode.column;
    } else if (keyboard.isAltPressed) {
      controller.addCursor(offset);
    } else {
      _dragAnchor = offset;
      controller.setSelections([TextSelection.collapsed(offset: offset)]);
      _dragMode = _DragMode.text;
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_dragPointer != event.pointer) return;
    final layout = _layout;
    final geometry = _geometry;
    if (layout == null || geometry == null) return;
    _dragPosition = event.localPosition;
    switch (_dragMode) {
      case _DragMode.text ||
          _DragMode.word ||
          _DragMode.line ||
          _DragMode.column:
        _extendDragSelection();
        _updateAutoScroll();
      case _DragMode.verticalScrollbar:
        _setScroll(
          top: _verticalSlider(
            layout,
            geometry,
          ).scrollForDrag(_dragStartScroll, _dragPosition.dy - _dragStart.dy),
        );
      case _DragMode.horizontalScrollbar:
        _setScroll(
          left: _horizontalSlider(
            layout,
            geometry,
          ).scrollForDrag(_dragStartScroll, _dragPosition.dx - _dragStart.dx),
        );
      case _DragMode.minimap:
        final perPixel = _minimapGeometry(layout, geometry).pixelsPerScroll;
        if (perPixel > 0) {
          _scrollToCaret = false;
          _setScroll(
            top:
                _dragStartScroll +
                (_dragPosition.dy - _dragStart.dy) / perPixel,
          );
        }
      case _DragMode.none:
        break;
    }
  }

  void _extendDragSelection() {
    final layout = _layout;
    final geometry = _geometry;
    if (layout == null || geometry == null) return;
    final controller = widget.controller;
    // Outside the viewport, target the nearest edge; auto-scroll reveals more.
    final content = geometry.contentRect;
    final local = _dragPosition - content.topLeft;
    final point = Offset(
      local.dx,
      local.dy.clamp(0.0, math.max(0.0, content.height - 1)),
    );
    switch (_dragMode) {
      case _DragMode.column:
        controller.columnSelect(_dragAnchor, layout.hitTest(point));
      case _DragMode.text:
        controller.setSelections([
          TextSelection(
            baseOffset: _dragAnchor,
            extentOffset: layout.hitTest(point),
          ),
        ]);
      case _DragMode.word:
        final offset = layout.hitTest(point);
        final word = controller.wordRangeAt(offset);
        controller.setSelections([
          offset < _dragWordAnchor.start
              ? TextSelection(
                  baseOffset: _dragWordAnchor.end,
                  extentOffset: math.min(word.start, offset),
                )
              : TextSelection(
                  baseOffset: _dragWordAnchor.start,
                  extentOffset: math.max(word.end, offset),
                ),
        ]);
      case _DragMode.line:
        controller.selectLineAt(
          layout.hitTest(Offset(-1e6, point.dy)),
          anchorOffset: _dragAnchor,
        );
      default:
        break;
    }
  }

  /// How far the drag pointer is beyond the content edges (0 when inside).
  Offset _dragOvershoot() {
    final geometry = _geometry!;
    final content = geometry.contentRect;
    final p = _dragPosition;
    final dy = p.dy < content.top
        ? p.dy - content.top
        : p.dy > content.bottom
        ? p.dy - content.bottom
        : 0.0;
    var dx = 0.0;
    if (_dragMode != _DragMode.line) {
      dx = p.dx < content.left
          ? p.dx - content.left
          : p.dx > content.right
          ? p.dx - content.right
          : 0.0;
    }
    return Offset(dx, dy);
  }

  /// Timer-driven scrolling while a selection drag is outside the content.
  void _updateAutoScroll() {
    if (_dragOvershoot() == Offset.zero) {
      _autoScrollTimer?.cancel();
      _autoScrollTimer = null;
      return;
    }
    _autoScrollTimer ??= Timer.periodic(const Duration(milliseconds: 30), (_) {
      if (!mounted || _dragMode == _DragMode.none || _layout == null) {
        _autoScrollTimer?.cancel();
        _autoScrollTimer = null;
        return;
      }
      final overshoot = _dragOvershoot();
      if (overshoot == Offset.zero) {
        _autoScrollTimer?.cancel();
        _autoScrollTimer = null;
        return;
      }
      final lineHeight = _layout!.lineHeight;
      double speed(double distance) {
        if (distance == 0) return 0;
        final magnitude = (distance.abs() / 2).clamp(2.0, lineHeight * 4);
        return distance.sign * magnitude;
      }

      _scrollBy(speed(overshoot.dx), speed(overshoot.dy));
      _extendDragSelection();
    });
  }

  void _onPointerUp(PointerEvent event) {
    _focusFromPointer = false;
    if (_dragPointer != event.pointer) return;
    _dragPointer = null;
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    final wasScrollbar =
        _dragMode == _DragMode.verticalScrollbar ||
        _dragMode == _DragMode.horizontalScrollbar ||
        _dragMode == _DragMode.minimap;
    _dragMode = _DragMode.none;
    if (wasScrollbar && mounted) {
      setState(() {});
      _scheduleScrollbarHide();
    }
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || _layout == null) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (resolved) {
      final scroll = resolved as PointerScrollEvent;
      var dx = scroll.scrollDelta.dx;
      var dy = scroll.scrollDelta.dy;
      final keyboard = HardwareKeyboard.instance;
      if (keyboard.isShiftPressed && dx == 0) {
        dx = dy;
        dy = 0;
      }
      if (keyboard.isAltPressed) {
        // Monaco fastScrollSensitivity.
        dx *= 5;
        dy *= 5;
      }
      _scrollBy(dx, dy);
    });
  }

  void _onPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    // Trackpad scrolling: content follows the fingers pixel for pixel.
    _scrollBy(-event.localPanDelta.dx, -event.localPanDelta.dy);
  }

  void _onHover(PointerHoverEvent event) {
    _updateHover(event.localPosition);
    _reportTextHover(event.localPosition);
  }

  int? _hoverOffset;

  void _reportTextHover(Offset? position) {
    final onHover = widget.onHover;
    if (onHover == null) return;
    final offset = position == null ? null : textOffsetAt(position);
    if (offset == null && _hoverOffset == null && position != null) return;
    _hoverOffset = offset;
    onHover(offset, position ?? Offset.zero);
  }

  void _updateHover(Offset position) {
    final part = _hitPart(position);
    final layout = _layout;
    final geometry = _geometry;
    var scrollbar = ScrollbarPart.none;
    if (layout != null && geometry != null) {
      if (part == _Part.verticalScrollbar) {
        final slider = _verticalSlider(layout, geometry);
        final y = position.dy - geometry.verticalScrollbarRect.top;
        if (slider.needed &&
            y >= slider.position &&
            y < slider.position + slider.size) {
          scrollbar = ScrollbarPart.vertical;
        }
      } else if (part == _Part.horizontalScrollbar) {
        final slider = _horizontalSlider(layout, geometry);
        final x = position.dx - geometry.horizontalScrollbarRect.left;
        if (slider.needed &&
            x >= slider.position &&
            x < slider.position + slider.size) {
          scrollbar = ScrollbarPart.horizontal;
        }
      }
    }
    if (part != _hover || scrollbar != _hoveredScrollbar) {
      setState(() {
        _hover = part;
        _hoveredScrollbar = scrollbar;
      });
    }
  }

  void _onEnter(PointerEnterEvent event) {
    _pointerInside = true;
    _revealScrollbars();
    _updateHover(event.localPosition);
  }

  void _onExit(PointerExitEvent event) {
    _pointerInside = false;
    _reportTextHover(null);
    _scheduleScrollbarHide();
    if (_hover != _Part.none || _hoveredScrollbar != ScrollbarPart.none) {
      setState(() {
        _hover = _Part.none;
        _hoveredScrollbar = ScrollbarPart.none;
      });
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!_focusNode.hasFocus) return KeyEventResult.ignored;
    final intercepted = widget.onKeyEvent?.call(event);
    if (intercepted != null && intercepted != KeyEventResult.ignored) {
      return intercepted;
    }
    return handleEditorKeyEvent(widget.controller, this, event);
  }

  Widget _textSemantics(Widget child, TextDirection direction) {
    final value = widget.controller.value;
    final selection = value.selection;
    final validSelection =
        selection.isValid && selection.end <= value.text.length;
    final focused = _focusNode.hasFocus;
    return Semantics(
      container: true,
      textField: true,
      multiline: true,
      readOnly: widget.readOnly,
      focused: _focusNode.canRequestFocus ? focused : null,
      textDirection: direction,
      value: value.text,
      onFocus: _focusNode.canRequestFocus ? _requestSemanticFocus : null,
      onTap: _focusNode.canRequestFocus ? _requestSemanticFocus : null,
      onSetText: _canEdit ? _setSemanticText : null,
      onSetSelection: focused ? _setSemanticSelection : null,
      onMoveCursorBackwardByCharacter:
          focused && validSelection && selection.extentOffset > 0
          ? (extend) => _moveSemanticCursor(-1, extend)
          : null,
      onMoveCursorForwardByCharacter:
          focused &&
              validSelection &&
              selection.extentOffset < value.text.length
          ? (extend) => _moveSemanticCursor(1, extend)
          : null,
      onCopy: _canCopy
          ? () => _invokeTextAction(CopySelectionTextIntent.copy)
          : null,
      onCut: _canEdit && _canCopy
          ? () => _invokeTextAction(
              const CopySelectionTextIntent.cut(SelectionChangedCause.keyboard),
            )
          : null,
      onPaste: _canEdit
          ? () => _invokeTextAction(
              const PasteTextIntent(SelectionChangedCause.keyboard),
            )
          : null,
      // Flutter has no built-in select-all semantics action. Expose a localized
      // custom action, backed by the same public intent as keyboard commands.
      customSemanticsActions: focused && value.text.isNotEmpty
          ? {
              CustomSemanticsAction(
                label:
                    Localizations.of<MaterialLocalizations>(
                      context,
                      MaterialLocalizations,
                    )?.selectAllButtonLabel ??
                    'Select all',
              ): () => _invokeTextAction(
                const SelectAllTextIntent(SelectionChangedCause.keyboard),
              ),
            }
          : null,
      child: _TextSelectionSemantics(
        selection: validSelection ? selection : null,
        // The editor is one document node, not one node per painted visible row.
        child: ExcludeSemantics(child: child),
      ),
    );
  }

  // Build.

  void _syncDecorations() {
    final source = widget.decorations;
    if (identical(source, _decorationSource)) return;
    final previous = _decorationSource;
    _decorationSource = source;
    if (previous != null && listEquals(previous, source)) return;
    _decorations = source.isEmpty
        ? SortedDecorations.empty
        : SortedDecorations(source);
  }

  EditorGutterGlyphs _ensureGlyphs(TextScaler scaler) {
    final theme = widget.theme;
    final key = (
      widget.style,
      scaler,
      theme.lineNumberForeground,
      theme.activeLineNumberForeground,
      theme.foldPlaceholderForeground,
    );
    final current = _glyphs;
    if (current != null && current.key == key) return current;
    current?.dispose();
    return _glyphs = EditorGutterGlyphs(
      style: widget.style,
      textScaler: scaler,
      foreground: theme.lineNumberForeground,
      activeForeground: theme.activeLineNumberForeground,
      placeholderForeground: theme.foldPlaceholderForeground,
    );
  }

  ViewportLayout _ensureLayout(
    DocumentSnapshot snapshot,
    EditorViewGeometry geometry,
    TextDirection direction,
    TextScaler scaler,
  ) {
    final size = Size(geometry.contentWidth, geometry.size.height);
    final hidden = _folding.hiddenLines;
    final wrap = widget.wrap && size.width > 0;
    final current = _layout;
    if (current != null &&
        identical(_layoutSnapshot, snapshot) &&
        _layoutStyle == widget.style &&
        _layoutSize == size &&
        _layoutDirection == direction &&
        _layoutScaler == scaler &&
        _layoutWrap == wrap &&
        identical(_layoutStyledLines, widget.styledLines) &&
        _layoutHidden == hidden &&
        _layoutTabSize == widget.controller.tabSize) {
      return current;
    }
    final layout = ViewportLayout(
      snapshot: snapshot,
      style: widget.style,
      viewportSize: size,
      wrap: wrap,
      textDirection: direction,
      textScaler: scaler,
      styledLines: widget.styledLines,
      tabSize: widget.controller.tabSize,
      hiddenLines: hidden,
      previousLayout: current,
      horizontalScrollOffset: _scrollLeft,
      verticalScrollOffset: _scrollTop,
    );
    current?.dispose();
    _layout = layout;
    _layoutSnapshot = snapshot;
    _layoutStyle = widget.style;
    _layoutSize = size;
    _layoutDirection = direction;
    _layoutScaler = scaler;
    _layoutWrap = wrap;
    _layoutStyledLines = widget.styledLines;
    _layoutHidden = hidden;
    _layoutTabSize = widget.controller.tabSize;
    return layout;
  }

  @override
  Widget build(BuildContext context) {
    final tickers = TickerMode.valuesOf(context).enabled;
    if (tickers != _tickersEnabled) {
      _tickersEnabled = tickers;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _restartBlink();
      });
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        assert(
          constraints.hasBoundedWidth && constraints.hasBoundedHeight,
          'EditorSurface needs bounded width and height',
        );
        final size = constraints.biggest;
        final direction = Directionality.of(context);
        final scaler = MediaQuery.textScalerOf(context);
        final controller = widget.controller;
        final snapshot = controller.document.snapshot;
        final selections = controller.selections;
        final value = controller.value;
        final theme = widget.theme;
        _syncDecorations();
        _syncFolding(snapshot);
        _revealSelectionsInFolds(selections);
        final glyphs = _ensureGlyphs(scaler);
        final geometry = EditorViewGeometry.compute(
          size: size,
          lineHeight: glyphs.lineHeight,
          digitWidth: glyphs.digitWidth,
          lineCount: snapshot.lineCount,
          glyphMargin: widget.glyphMargin,
          lineNumbers: widget.lineNumbers,
          folding: widget.folding,
          minimapWidth: widget.showMinimap ? widget.minimapWidth : 0,
        );
        _geometry = geometry;
        final layout = _ensureLayout(snapshot, geometry, direction, scaler);
        final maxTop = _maxScrollTop(layout);
        final maxLeft = _maxScrollLeft(layout);
        if (_scrollTop > maxTop || _scrollLeft > maxLeft) {
          _scrollTop = math.min(_scrollTop, maxTop);
          _scrollLeft = math.min(_scrollLeft, maxLeft);
        }
        layout.setScrollOffset(horizontal: _scrollLeft, vertical: _scrollTop);

        final primary = value.selection;
        final pairs =
            widget.brackets ??
            controller.languageConfiguration?.brackets ??
            defaultBracketPairs;
        final bracketKey = (
          snapshot,
          primary.isValid ? primary.extentOffset : -1,
          pairs,
          widget.matchBrackets,
        );
        if (bracketKey != _bracketKey) {
          _bracketKey = bracketKey;
          _bracketMatch = widget.matchBrackets && primary.isValid
              ? matchBracket(snapshot, primary.extentOffset, pairs: pairs)
              : null;
        }
        final activeLines = <int>{
          for (final selection in selections)
            if (selection.isValid)
              snapshot
                  .positionAtOffset(
                    selection.extentOffset.clamp(0, snapshot.text.length),
                  )
                  .lineNumber,
        };
        final focused = _focusNode.hasFocus;
        final contentRect = geometry.contentRect;
        final scrollHeight = _scrollHeight(layout);

        if (_scrollToCaret || _connection?.attached == true) {
          _scheduleGeometry();
        }

        final layers = Stack(
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: EditorOverlayPainter(
                    layout: layout,
                    contentRect: contentRect,
                    scrollTop: _scrollTop,
                    scrollLeft: _scrollLeft,
                    theme: theme,
                    selections: selections,
                    focused: focused,
                    selectionColor: widget.selectionColor,
                    decorations: _decorations,
                    bracketMatch: _bracketMatch,
                    folding: _folding,
                    foldingVersion: _foldingVersion,
                    indentGuides: widget.indentGuides,
                    guideCache: _guideCache,
                    tabSize: controller.tabSize,
                    occurrences: widget.selectionHighlight,
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: EditorTextPainter(
                    layout: layout,
                    contentRect: contentRect,
                    scrollTop: _scrollTop,
                    scrollLeft: _scrollLeft,
                    theme: theme,
                    folding: _folding,
                    foldingVersion: _foldingVersion,
                    glyphs: glyphs,
                    renderWhitespace: widget.renderWhitespace,
                    decorations: _decorations,
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: EditorCaretPainter(
                    layout: layout,
                    contentRect: contentRect,
                    scrollTop: _scrollTop,
                    scrollLeft: _scrollLeft,
                    selections: selections,
                    affinity: primary.affinity,
                    composing: value.composing,
                    focused: focused,
                    caretColor: widget.caretColor,
                    visible: _caretVisible,
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: CustomPaint(
                painter: EditorGutterPainter(
                  layout: layout,
                  geometry: geometry,
                  scrollTop: _scrollTop,
                  background: widget.backgroundColor,
                  theme: theme,
                  glyphs: glyphs,
                  lineNumbers: widget.lineNumbers,
                  activeLines: activeLines,
                  folding: _folding,
                  foldingVersion: _foldingVersion,
                  showFoldingControls: _hover == _Part.gutter,
                  foldingEnabled: widget.folding,
                ),
              ),
            ),
            if (geometry.minimapWidth > 0)
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: EditorMinimapPainter(
                      cache: _minimapCache,
                      layout: layout,
                      rect: geometry.minimapRect,
                      geometry: _minimapGeometry(layout, geometry),
                      styledLines: widget.styledLines,
                      foreground: widget.style.color ?? const Color(0xffcccccc),
                      background: widget.backgroundColor,
                      theme: theme,
                      tabSize: controller.tabSize,
                      selections: selections,
                      decorations: _decorations,
                      showSlider: _hover == _Part.minimap,
                      sliderActive: _dragMode == _DragMode.minimap,
                    ),
                  ),
                ),
              ),
            Positioned.fill(
              child: CustomPaint(
                painter: EditorScrollbarPainter(
                  layout: layout,
                  theme: theme,
                  contentRect: contentRect,
                  verticalTrack: geometry.verticalScrollbarRect,
                  horizontalTrack: geometry.horizontalScrollbarRect,
                  vertical: _verticalSlider(layout, geometry),
                  horizontal: _horizontalSlider(layout, geometry),
                  scrollTop: _scrollTop,
                  scrollLeft: _scrollLeft,
                  scrollHeight: scrollHeight,
                  decorations: _decorations,
                  overviewCache: _overviewCache,
                  cursorLines: activeLines.toList(),
                  hovered: _hoveredScrollbar,
                  dragging: switch (_dragMode) {
                    _DragMode.verticalScrollbar => ScrollbarPart.vertical,
                    _DragMode.horizontalScrollbar => ScrollbarPart.horizontal,
                    _ => ScrollbarPart.none,
                  },
                  fade: _scrollbarFade,
                ),
              ),
            ),
          ],
        );
        final textCursor =
            _hover == _Part.content ||
            _dragMode == _DragMode.text ||
            _dragMode == _DragMode.word;
        final paintedSurface = MouseRegion(
          cursor: textCursor
              ? (_hover == _Part.content ? widget.contentCursor : null) ??
                    SystemMouseCursors.text
              : MouseCursor.defer,
          onEnter: _onEnter,
          onExit: _onExit,
          onHover: _onHover,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
            onPointerCancel: _onPointerUp,
            onPointerSignal: _onPointerSignal,
            onPointerPanZoomUpdate: _onPanZoomUpdate,
            child: ColoredBox(
              key: _paintKey,
              color: widget.backgroundColor,
              child: SizedBox.fromSize(size: size, child: layers),
            ),
          ),
        );
        return Actions(
          actions: <Type, Action<Intent>>{
            CopySelectionTextIntent: _EditorTextAction<CopySelectionTextIntent>(
              // Monaco copies/cuts the whole line for an empty selection.
              enabled: (intent) =>
                  _canCopyOrLine && (!intent.collapseSelection || _canEdit),
              onInvoke: _copyOrCut,
            ),
            PasteTextIntent: _EditorTextAction<PasteTextIntent>(
              enabled: (_) => _canEdit,
              onInvoke: _paste,
            ),
            SelectAllTextIntent: _EditorTextAction<SelectAllTextIntent>(
              enabled: (_) =>
                  mounted &&
                  _focusNode.hasFocus &&
                  widget.controller.value.text.isNotEmpty,
              onInvoke: (_) {
                widget.controller.selectAll();
                return null;
              },
            ),
          },
          child: Focus(
            focusNode: _focusNode,
            includeSemantics: false,
            onKeyEvent: _onKey,
            child: _textSemantics(paintedSurface, direction),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChange);
    _focusNode.removeListener(_onFocusChange);
    _detach();
    if (_ownsFocusNode) _focusNode.dispose();
    _blinkTimer?.cancel();
    _foldTimer?.cancel();
    _autoScrollTimer?.cancel();
    _scrollbarHideTimer?.cancel();
    _scrollbarFade.dispose();
    _caretVisible.dispose();
    _minimapCache.dispose();
    _overviewCache.dispose();
    _glyphs?.dispose();
    _layout?.dispose();
    super.dispose();
  }
}

class _EditorTextAction<T extends Intent> extends Action<T> {
  _EditorTextAction({required this.enabled, required this.onInvoke});

  final bool Function(T) enabled;
  final Object? Function(T) onInvoke;

  @override
  bool isEnabled(T intent) => enabled(intent);

  @override
  Object? invoke(T intent) => isEnabled(intent) ? onInvoke(intent) : null;
}

/// [Semantics] exposes editing callbacks, but only the public rendering API
/// exposes selection base/extent. Merge this annotation into its document node.
class _TextSelectionSemantics extends SingleChildRenderObjectWidget {
  const _TextSelectionSemantics({
    required this.selection,
    required super.child,
  });

  final TextSelection? selection;

  @override
  _RenderTextSelectionSemantics createRenderObject(BuildContext context) =>
      _RenderTextSelectionSemantics(selection);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderTextSelectionSemantics renderObject,
  ) {
    renderObject.selection = selection;
  }
}

class _RenderTextSelectionSemantics extends RenderProxyBox {
  _RenderTextSelectionSemantics(this._selection);

  TextSelection? _selection;

  set selection(TextSelection? value) {
    if (_selection == value) return;
    _selection = value;
    markNeedsSemanticsUpdate();
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    if (_selection != null) config.textSelection = _selection;
  }
}
