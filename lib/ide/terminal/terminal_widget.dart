// Copyright (c) 2014-2024 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// The viewport is ported from xterm.js src/browser/Viewport.ts, the overview
// ruler from src/browser/decorations/OverviewRulerRenderer.ts and
// ColorZoneStore.ts, the grid coordinates from src/browser/input/Mouse.ts
// and services/MouseService.ts, the composition view's place from
// input/CompositionHelper.ts (c58ea36); the scrollbar behaves as VS Code
// 6a598d4a's ScrollableElement (src/vs/base/browser/ui/scrollbar/).
//
// The terminal on screen: [TerminalRenderer]'s grid, the scrollbar at the
// right edge with xterm.js' overview ruler under its slider, and the IME's
// composition view at the cursor. The grid sits inside [TerminalWidget.
// padding] at the bottom of the space left of the scrollbar, as VS Code
// places its xterm element; [TerminalWidget.onResize] reports the columns
// and rows that fit there.
//
// Wheel scrolling keeps to a gesture as WheelLatch does (see
// lib/chat/widgets/wheel_latch.dart): a wheel gesture started over the
// terminal while it can scroll that way (or while it takes wheel events
// itself) scrolls only the terminal; any other goes to the view around it.
// Trackpad pans are claimed from the start when the terminal can scroll.
//
// Keyboard input, the selection and mouse reports are the input
// controllers': they get the pointer events on the grid through the
// callbacks, and set what to draw on [TerminalRenderController].

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../chat/widgets/wheel_latch.dart';
import '../editor/monaco/flutter/editor_scrollbar.dart';
import 'terminal_render_source.dart';
import 'terminal_render_theme.dart';
import 'terminal_renderer.dart';
import 'xterm/common/color.dart' as color_lib;
import 'xterm/common/lifecycle.dart';
import 'xterm/common/services/services.dart';

/// A pointer event on the grid: [gridPosition] is from the grid's top left
/// (the terminal's screen, inside the padding), in logical pixels.
typedef TerminalPointerCallback<T extends PointerEvent> = void Function(
  T event,
  Offset gridPosition,
);

/// A wheel or trackpad scroll on the grid; returns the logical pixels the
/// viewport is to scroll, positive down (0 when the terminal took it).
typedef TerminalScrollCallback<T extends PointerEvent> = double Function(
  T event,
  Offset gridPosition,
);

/// What the input controllers set for the terminal to draw, and the grid's
/// geometry for them. Valid while a [TerminalWidget] shows it; listeners
/// hear of geometry changes (after the frame that made them).
class TerminalRenderController extends ChangeNotifier {
  _TerminalWidgetState? _state;

  TerminalRenderer? get renderer => _state?._renderer;

  TerminalSelectionRange? _selection;

  /// The selection to draw (upstream `handleSelectionChanged`): buffer
  /// lines, not viewport rows. Null or empty for none.
  TerminalSelectionRange? get selection => _selection;
  set selection(TerminalSelectionRange? value) {
    _selection = value;
    renderer?.selection = value;
  }

  /// Sets [selection] from xterm.js' `[x, y]` pairs, as the selection
  /// service fires them.
  void setSelection(
    List<int>? start,
    List<int>? end, {
    bool columnSelectMode = false,
  }) {
    selection = start == null || end == null
        ? null
        : TerminalSelectionRange(
            start: (x: start[0], y: start[1]),
            end: (x: end[0], y: end[1]),
            columnSelectMode: columnSelectMode,
          );
  }

  TerminalLinkUnderline? _linkUnderline;

  /// The hovered link's underline, or null.
  TerminalLinkUnderline? get linkUnderline => _linkUnderline;
  set linkUnderline(TerminalLinkUnderline? value) {
    _linkUnderline = value;
    renderer?.linkUnderline = value;
  }

  String? _composition;

  /// The IME's composing text, drawn over the cursor's cell; null or empty
  /// for none.
  String? get composition => _composition;
  set composition(String? value) {
    if (value == _composition) return;
    _composition = value;
    _state?._handleCompositionChanged();
  }

  /// Shows the cursor and restarts its blinking (on input).
  void restartCursorBlink() => renderer?.restartCursorBlink();

  // --- Geometry ---------------------------------------------------------

  _TerminalGeometry? get _geometry => _state?._geometry;

  bool get hasValidSize => _geometry?.cellSize.isEmpty == false;

  /// A cell's size, in logical pixels.
  Size get cellSize => _geometry?.cellSize ?? Size.zero;

  /// The grid's top left in the widget.
  Offset get gridOrigin => _geometry?.origin ?? Offset.zero;

  /// The grid drawn (the terminal's columns and rows), in the widget.
  Rect get gridRect => _geometry?.gridRect ?? Rect.zero;

  /// The columns and rows that fit, as last reported to `onResize`.
  ({int cols, int rows})? get fit => _geometry?.fit;

  /// The scrollbar and overview ruler, in the widget.
  Rect get scrollbarRect => _geometry?.scrollbarRect ?? Rect.zero;

  /// The widget's render box, for global coordinates.
  RenderBox? get renderBox => _state?.context.findRenderObject() as RenderBox?;

  /// A widget position on the grid.
  Offset toGrid(Offset localPosition) => localPosition - gridOrigin;

  /// Upstream `getCoords` (Mouse.ts): the 1-based cell at [gridPosition],
  /// clamped to the grid; a selection's column is the nearer cell edge and
  /// may be one past the last column.
  ({int col, int row})? getCoords(
    Offset gridPosition, {
    bool isSelection = false,
  }) {
    final geometry = _geometry;
    if (geometry == null || geometry.cellSize.isEmpty) return null;
    final cell = geometry.cellSize;
    var col =
        ((gridPosition.dx + (isSelection ? cell.width / 2 : 0)) / cell.width)
            .ceil();
    var row = (gridPosition.dy / cell.height).ceil();
    col = math.min(math.max(col, 1), geometry.cols + (isSelection ? 1 : 0));
    row = math.min(math.max(row, 1), geometry.rows);
    return (col: col, row: row);
  }

  /// Upstream `getMouseReportCoords` (MouseService.ts): the 0-based cell
  /// and the pixel, clamped to the grid.
  ({int col, int row, int x, int y})? getMouseReportCoords(
    Offset gridPosition,
  ) {
    final geometry = _geometry;
    if (geometry == null || geometry.cellSize.isEmpty) return null;
    final cell = geometry.cellSize;
    final x = gridPosition.dx.clamp(0.0, geometry.gridRect.width - 1);
    final y = gridPosition.dy.clamp(0.0, geometry.gridRect.height - 1);
    return (
      col: (x / cell.width).floor(),
      row: (y / cell.height).floor(),
      x: x.floor(),
      y: y.floor(),
    );
  }

  /// The cursor's cell in the widget, or null when it is out of view: the
  /// composition view's place, and the IME's.
  Rect? get cursorRect {
    final rect = renderer?.cursorRect;
    return rect?.shift(gridOrigin);
  }

  void _geometryChanged() => notifyListeners();
}

/// The terminal's grid, scrollbar and composition view.
class TerminalWidget extends StatefulWidget {
  const TerminalWidget({
    super.key,
    required this.source,
    this.controller,
    this.focusNode,
    this.padding = EdgeInsets.zero,
    this.alignBottom = true,
    this.onResize,
    this.onPointerDown,
    this.onPointerMove,
    this.onPointerHover,
    this.onPointerUp,
    this.onPointerCancel,
    this.onWheel,
    this.onPanZoomUpdate,
    this.capturesWheel,
    this.mouseCursor = SystemMouseCursors.text,
  });

  final TerminalRenderSource source;
  final TerminalRenderController? controller;

  /// The terminal's focus (the input controllers' node): the cursor and the
  /// selection are drawn inactive without it. A pointer down on the grid
  /// requests it.
  final FocusNode? focusNode;

  /// Around the grid; the scrollbar is outside it, at the right edge.
  /// VS Code pads its terminal 20 on the left only.
  final EdgeInsets padding;

  /// Whether the grid sits at the bottom of its space (VS Code) rather
  /// than the top.
  final bool alignBottom;

  /// The columns and rows that fit, when they change (after the frame).
  final void Function(int cols, int rows)? onResize;

  /// Pointer events on the grid (not on the scrollbar), for the mouse
  /// controller: `TerminalMouse`'s handlers fit.
  final TerminalPointerCallback<PointerDownEvent>? onPointerDown;
  final TerminalPointerCallback<PointerMoveEvent>? onPointerMove;
  final TerminalPointerCallback<PointerHoverEvent>? onPointerHover;
  final TerminalPointerCallback<PointerUpEvent>? onPointerUp;
  final TerminalPointerCallback<PointerCancelEvent>? onPointerCancel;

  /// A wheel event the terminal took: returns what to scroll (reporting it
  /// to the app instead returns 0). Without it the viewport scrolls by the
  /// event's delta times `scrollSensitivity` (`fastScrollSensitivity` more
  /// with alt).
  final TerminalScrollCallback<PointerScrollEvent>? onWheel;

  /// A trackpad pan the terminal took, as [onWheel].
  final TerminalScrollCallback<PointerPanZoomUpdateEvent>? onPanZoomUpdate;

  /// Whether the terminal takes wheel events even where its viewport
  /// cannot scroll: mouse reporting with the wheel, or the alternate screen
  /// turning them into arrow keys.
  final bool Function()? capturesWheel;

  /// The pointer over the grid.
  final MouseCursor mouseCursor;

  @override
  State<TerminalWidget> createState() => _TerminalWidgetState();
}

@immutable
class _TerminalGeometry {
  const _TerminalGeometry({
    required this.size,
    required this.origin,
    required this.cellSize,
    required this.cols,
    required this.rows,
    required this.scrollbarRect,
    required this.fit,
  });

  final Size size;
  final Offset origin;
  final Size cellSize;
  final int cols;
  final int rows;
  final Rect scrollbarRect;
  final ({int cols, int rows})? fit;

  Rect get gridRect =>
      origin & Size(cols * cellSize.width, rows * cellSize.height);

  @override
  bool operator ==(Object other) =>
      other is _TerminalGeometry &&
      other.size == size &&
      other.origin == origin &&
      other.cellSize == cellSize &&
      other.cols == cols &&
      other.rows == rows &&
      other.scrollbarRect == scrollbarRect &&
      other.fit == fit;

  @override
  int get hashCode =>
      Object.hash(size, origin, cellSize, cols, rows, scrollbarRect, fit);
}

class _TerminalWidgetState extends State<TerminalWidget>
    with TickerProviderStateMixin {
  late TerminalRenderer _renderer;
  final DisposableStore _subscriptions = DisposableStore();
  final GlobalKey _gridKey = GlobalKey();
  final _Repaint _scrollbarRepaint = _Repaint();
  TerminalRenderController? _ownController;
  _TerminalGeometry? _geometry;
  ({int cols, int rows})? _reportedFit;

  // Upstream Viewport's scroll position, in logical pixels.
  double _scrollTop = 0;

  // The scrollbar: VS Code shows it on hover and scrolls, and fades it out
  // (800ms) half a second later.
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 100),
    reverseDuration: const Duration(milliseconds: 800),
  );
  Timer? _hideTimer;
  bool _mouseOver = false;
  bool _sliderHovered = false;
  ({double startY, double startScroll})? _sliderDrag;
  int _lastYdisp = 0;

  final Set<int> _panZoomPointers = {};

  TerminalRenderController get _controller =>
      widget.controller ?? (_ownController ??= TerminalRenderController());

  TerminalRenderSource get _source => widget.source;

  @override
  void initState() {
    super.initState();
    _watchWheels();
    _createRenderer();
    widget.focusNode?.addListener(_handleFocusChange);
    PaintingBinding.instance.systemFonts.addListener(_handleSystemFonts);
  }

  void _createRenderer() {
    _renderer = TerminalRenderer(
      _source,
      onNeedsPaint: _handleNeedsPaint,
      onDimensionsChanged: _handleDimensionsChanged,
      isFocused: widget.focusNode?.hasFocus ?? false,
    );
    _renderer
      ..selection = _controller.selection
      ..linkUnderline = _controller.linkUnderline;
    _controller._state = this;
    _lastYdisp = _source.buffer.ydisp;
    _scrollTop = _lastYdisp * _renderer.dimensions.cellHeight;
    final source = _source;
    _subscriptions
      ..add(source.onRender((_) => _handleContentChanged()))
      ..add(source.onScroll((_) => _handleContentChanged()))
      ..add(source.onResize((_) => _handleResize()))
      ..add(source.onBufferActivate((_) => _handleResize()))
      ..add(
        source.optionsService.onSpecificOptionChange<Object?>(
          'scrollbar',
          (_) => _handleResize(),
        ),
      );
    final decorations = source.decorationService;
    if (decorations != null) {
      _subscriptions
        ..add(
          decorations.onDecorationRegistered((_) => _scrollbarRepaint.fire()),
        )
        ..add(decorations.onDecorationRemoved((_) => _scrollbarRepaint.fire()));
    }
    _subscriptions.add(
      source.themeService.onChangeColors((_) => _scrollbarRepaint.fire()),
    );
  }

  void _disposeRenderer() {
    _subscriptions.clear();
    if (_controller._state == this) _controller._state = null;
    _renderer.dispose();
  }

  @override
  void didUpdateWidget(TerminalWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_handleFocusChange);
      widget.focusNode?.addListener(_handleFocusChange);
      _renderer.isFocused = widget.focusNode?.hasFocus ?? false;
    }
    if (oldWidget.controller != widget.controller) {
      final old = oldWidget.controller ?? _ownController;
      if (old?._state == this) old!._state = null;
      if (widget.controller != null) {
        _ownController?.dispose();
        _ownController = null;
      }
      _controller._state = this;
      _renderer
        ..selection = _controller.selection
        ..linkUnderline = _controller.linkUnderline;
    }
    if (oldWidget.source != widget.source) {
      _disposeRenderer();
      _createRenderer();
      _renderer.devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _renderer.devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    _renderer.viewportVisible = TickerMode.valuesOf(context).enabled;
  }

  @override
  void dispose() {
    PaintingBinding.instance.systemFonts.removeListener(_handleSystemFonts);
    widget.focusNode?.removeListener(_handleFocusChange);
    _hideTimer?.cancel();
    _fade.dispose();
    _disposeRenderer();
    _subscriptions.dispose();
    _ownController?.dispose();
    _scrollbarRepaint.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    _renderer.isFocused = widget.focusNode?.hasFocus ?? false;
  }

  void _handleSystemFonts() => _renderer.remeasure();

  void _handleNeedsPaint() {
    final render = _gridKey.currentContext?.findRenderObject();
    if (render is! RenderObject || !render.attached) return;
    // A paint may ask for another (a blink turned on): after it.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (render.attached) render.markNeedsPaint();
      });
    } else {
      render.markNeedsPaint();
    }
  }

  void _handleDimensionsChanged() {
    if (mounted) setState(() {});
  }

  void _handleResize() {
    _syncScrollTop();
    if (mounted) setState(() {});
    _scrollbarRepaint.fire();
  }

  void _handleContentChanged() {
    final ydisp = _source.buffer.ydisp;
    if (ydisp != _lastYdisp) {
      _lastYdisp = ydisp;
      _syncScrollTop();
      _reveal();
    }
    _scrollbarRepaint.fire();
  }

  void _handleCompositionChanged() {
    if (mounted) setState(() {});
  }

  // --- Layout -----------------------------------------------------------

  double get _scrollbarWidth {
    final scrollbar = _source.optionsService.rawOptions.scrollbar;
    if (scrollbar.showScrollbar == false) return 0;
    return scrollbar.width ?? 14;
  }

  _TerminalGeometry _layout(Size size) {
    final dims = _renderer.dimensions;
    final dpr = dims.devicePixelRatio;
    final padding = widget.padding;
    final scrollbarWidth = _scrollbarWidth;
    final width = math.max(
      0.0,
      size.width - padding.horizontal - scrollbarWidth,
    );
    final height = math.max(0.0, size.height - padding.vertical);
    final cellSize = Size(dims.cellWidth, dims.cellHeight);
    final cols = _source.cols;
    final rows = _source.rows;
    final gridHeight = rows * cellSize.height;
    final top = widget.alignBottom
        ? padding.top + height - gridHeight
        : padding.top;
    // Whole device pixels, so that cells meet without seams.
    double snap(double v) => (v * dpr).roundToDouble() / dpr;
    final origin = Offset(snap(padding.left), snap(top));
    final valid = _renderer.metrics.hasValidSize && width > 0 && height > 0;
    return _TerminalGeometry(
      size: size,
      origin: origin,
      cellSize: cellSize,
      cols: cols,
      rows: rows,
      scrollbarRect: Rect.fromLTWH(
        size.width - scrollbarWidth,
        origin.dy,
        scrollbarWidth,
        gridHeight,
      ),
      fit: valid ? dims.fit(width, height) : null,
    );
  }

  void _applyGeometry(_TerminalGeometry geometry) {
    if (geometry == _geometry) return;
    _geometry = geometry;
    final fit = geometry.fit;
    final report = fit != null && fit != _reportedFit;
    if (report) _reportedFit = fit;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (report) widget.onResize?.call(fit.cols, fit.rows);
      _controller._geometryChanged();
    });
  }

  // --- Scrolling (Viewport) ---------------------------------------------

  double get _cellHeight => _renderer.dimensions.cellHeight;

  double get _maxScrollTop => _source.buffer.ybase * _cellHeight;

  /// Upstream `_sync`: the scroll position follows the viewport's line when
  /// something else moved it.
  void _syncScrollTop() {
    if (_source.synchronizedOutput) return;
    final ydisp = _source.buffer.ydisp;
    if ((_scrollTop / _cellHeight).round() != ydisp) {
      _scrollTop = ydisp * _cellHeight;
    }
  }

  /// Upstream `_handleScroll`: scrolls to [scrollTop] and the viewport to
  /// its nearest line.
  void _scrollTo(double scrollTop) {
    _scrollTop = scrollTop.clamp(0.0, _maxScrollTop);
    final newRow = (_scrollTop / _cellHeight).round();
    final diff = newRow - _source.buffer.ydisp;
    if (diff != 0) _source.scrollLines(diff);
    _scrollbarRepaint.fire();
  }

  void _scrollBy(double pixels) {
    if (pixels == 0 || !pixels.isFinite) return;
    _syncScrollTop();
    _scrollTo(_scrollTop + pixels);
  }

  bool _canScroll(double delta) {
    if (widget.capturesWheel?.call() ?? false) return true;
    final buffer = _source.buffer;
    return delta < 0
        ? buffer.ydisp > 0
        : delta > 0 && buffer.ydisp < buffer.ybase;
  }

  double _defaultScrollDelta(double deltaY) {
    final options = _source.optionsService.rawOptions;
    var delta = deltaY * options.scrollSensitivity;
    if (HardwareKeyboard.instance.isAltPressed) {
      delta *= options.fastScrollSensitivity;
    }
    return delta;
  }

  // One wheel gesture at a time, app wide (as WheelLatch): the last wheel
  // event, and the terminal that has the gesture (null: none of them).
  static Duration? _lastWheel;
  static Object? _latched;
  static Duration? _latchedAt;
  static bool _watching = false;

  static void _watch(PointerEvent event) {
    if (event is! PointerScrollEvent) return;
    final last = _lastWheel;
    final starts = last == null || event.timeStamp - last >= WheelLatch.gap;
    if (starts && _latchedAt != event.timeStamp) _latched = null;
    _lastWheel = event.timeStamp;
  }

  static void _watchWheels() {
    if (_watching) return;
    _watching = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_watch);
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final delta = event.scrollDelta.dy;
    final last = _lastWheel;
    if (last == null || event.timeStamp - last >= WheelLatch.gap) {
      _latched = _canScroll(delta) ? this : null;
      _latchedAt = event.timeStamp;
    }
    if (_latched != this || delta == 0) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      if (!mounted) return;
      final scroll = event as PointerScrollEvent;
      final onWheel = widget.onWheel;
      final pixels = onWheel != null
          ? onWheel(scroll, _controller.toGrid(scroll.localPosition))
          : _defaultScrollDelta(scroll.scrollDelta.dy);
      _scrollBy(pixels);
      _reveal();
    });
  }

  bool _acceptsPanZoom(PointerPanZoomStartEvent event) =>
      (widget.capturesWheel?.call() ?? false) || _source.buffer.ybase > 0;

  void _handlePanZoomAccepted(int pointer) => _panZoomPointers.add(pointer);

  void _handlePanZoomUpdate(PointerPanZoomUpdateEvent event) {
    if (!_panZoomPointers.contains(event.pointer)) return;
    final onPanZoom = widget.onPanZoomUpdate;
    final pixels = onPanZoom != null
        ? onPanZoom(event, _controller.toGrid(event.localPosition))
        : _defaultScrollDelta(-event.localPanDelta.dy);
    _scrollBy(pixels);
    _reveal();
  }

  void _handlePanZoomEnd(PointerPanZoomEndEvent event) =>
      _panZoomPointers.remove(event.pointer);

  // --- Scrollbar --------------------------------------------------------

  ScrollbarSlider _slider() {
    final geometry = _geometry;
    if (geometry == null || _source.isAlternateBuffer) {
      return ScrollbarSlider.compute(
        trackSize: 0,
        visibleSize: 0,
        scrollSize: 0,
        scrollPosition: 0,
      );
    }
    final track = geometry.scrollbarRect.height;
    return ScrollbarSlider.compute(
      trackSize: track,
      visibleSize: track,
      scrollSize: _source.buffer.lines.length * _cellHeight,
      scrollPosition: _source.buffer.ydisp * _cellHeight,
    );
  }

  void _reveal() {
    if (_scrollbarWidth <= 0) return;
    _fade.forward();
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (_mouseOver || _sliderDrag != null) return;
    _hideTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) _fade.reverse();
    });
  }

  void _handleScrollbarDown(PointerDownEvent event) {
    if (event.buttons != kPrimaryButton) return;
    final slider = _slider();
    if (!slider.needed) return;
    final y = event.localPosition.dy;
    _syncScrollTop();
    if (y < slider.position || y >= slider.position + slider.size) {
      // VS Code: a click on the track centers the slider there, then drags.
      _scrollTo(((y - slider.size / 2) / slider.ratio).roundToDouble());
    }
    _sliderDrag = (startY: y, startScroll: _scrollTop);
    _fade.forward();
    _hideTimer?.cancel();
    _scrollbarRepaint.fire();
  }

  void _handleScrollbarMove(PointerMoveEvent event) {
    final drag = _sliderDrag;
    if (drag == null) return;
    final slider = _slider();
    _scrollTo(
      slider.scrollForDrag(
        drag.startScroll,
        event.localPosition.dy - drag.startY,
      ),
    );
  }

  void _handleScrollbarUp(PointerEvent event) {
    if (_sliderDrag == null) return;
    _sliderDrag = null;
    _scheduleHide();
    _scrollbarRepaint.fire();
  }

  void _handleScrollbarHover(PointerHoverEvent event) {
    final slider = _slider();
    final y = event.localPosition.dy;
    final hovered =
        slider.needed &&
        y >= slider.position &&
        y < slider.position + slider.size;
    if (hovered != _sliderHovered) {
      _sliderHovered = hovered;
      _scrollbarRepaint.fire();
    }
  }

  // --- Grid pointer -----------------------------------------------------

  void _handleGridDown(PointerDownEvent event) {
    widget.focusNode?.requestFocus();
    // Upstream restarts the blink on any mouse down.
    _renderer.restartCursorBlink();
    widget.onPointerDown?.call(event, _controller.toGrid(event.localPosition));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final geometry = _layout(size);
        _applyGeometry(geometry);
        final controller = _controller;
        final composition = controller.composition;
        final cursorRect = composition == null || composition.isEmpty
            ? null
            : _renderer.cursorRect?.shift(geometry.origin);
        return MouseRegion(
          onEnter: (_) {
            _mouseOver = true;
            _reveal();
          },
          onExit: (_) {
            _mouseOver = false;
            if (_sliderHovered) {
              _sliderHovered = false;
              _scrollbarRepaint.fire();
            }
            _scheduleHide();
          },
          child: Listener(
            onPointerSignal: _handlePointerSignal,
            onPointerPanZoomUpdate: _handlePanZoomUpdate,
            onPointerPanZoomEnd: _handlePanZoomEnd,
            child: Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.hardEdge,
              children: [
                Listener(
                  onPointerDown: _handleGridDown,
                  onPointerMove: (e) => widget.onPointerMove?.call(
                    e,
                    controller.toGrid(e.localPosition),
                  ),
                  onPointerHover: (e) => widget.onPointerHover?.call(
                    e,
                    controller.toGrid(e.localPosition),
                  ),
                  onPointerUp: (e) => widget.onPointerUp?.call(
                    e,
                    controller.toGrid(e.localPosition),
                  ),
                  onPointerCancel: (e) => widget.onPointerCancel?.call(
                    e,
                    controller.toGrid(e.localPosition),
                  ),
                  child: MouseRegion(
                    cursor: widget.mouseCursor,
                    child: RawGestureDetector(
                      gestures: {
                        _TrackpadScrollRecognizer:
                            GestureRecognizerFactoryWithHandlers<
                              _TrackpadScrollRecognizer
                            >(
                              () => _TrackpadScrollRecognizer(debugOwner: this),
                              (recognizer) => recognizer
                                ..accepts = _acceptsPanZoom
                                ..onAccept = _handlePanZoomAccepted,
                            ),
                      },
                      child: _TerminalGrid(
                        key: _gridKey,
                        renderer: _renderer,
                        origin: geometry.origin,
                      ),
                    ),
                  ),
                ),
                if (geometry.scrollbarRect.width > 0)
                  Positioned.fromRect(
                    rect: geometry.scrollbarRect,
                    child: Listener(
                      onPointerDown: _handleScrollbarDown,
                      onPointerMove: _handleScrollbarMove,
                      onPointerUp: _handleScrollbarUp,
                      onPointerCancel: _handleScrollbarUp,
                      onPointerHover: _handleScrollbarHover,
                      child: MouseRegion(
                        child: CustomPaint(painter: _ScrollbarPainter(this)),
                      ),
                    ),
                  ),
                if (cursorRect != null)
                  Positioned(
                    left: cursorRect.left,
                    top: cursorRect.top,
                    height: cursorRect.height,
                    child: IgnorePointer(
                      child: _CompositionView(
                        text: composition!,
                        renderer: _renderer,
                        maxWidth: math.max(0, size.width - cursorRect.left),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Repaint extends ChangeNotifier {
  void fire() => notifyListeners();
}

/// Claims trackpad pans (pointer pan/zoom) from their start, when the
/// terminal can scroll, before a scroll view around it can.
class _TrackpadScrollRecognizer extends OneSequenceGestureRecognizer {
  _TrackpadScrollRecognizer({super.debugOwner})
    : super(supportedDevices: {PointerDeviceKind.trackpad});

  bool Function(PointerPanZoomStartEvent event)? accepts;
  void Function(int pointer)? onAccept;

  @override
  bool isPointerAllowed(PointerDownEvent event) => false;

  @override
  bool isPointerPanZoomAllowed(PointerPanZoomStartEvent event) =>
      super.isPointerPanZoomAllowed(event) && (accepts?.call(event) ?? false);

  @override
  void addAllowedPointerPanZoom(PointerPanZoomStartEvent event) {
    super.addAllowedPointerPanZoom(event);
    startTrackingPointer(event.pointer, event.transform);
    resolve(GestureDisposition.accepted);
    onAccept?.call(event.pointer);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerPanZoomEndEvent || event is PointerCancelEvent) {
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'terminal trackpad scroll';
}

/// The grid: the theme's background over the whole widget, and the rows.
class _TerminalGrid extends LeafRenderObjectWidget {
  const _TerminalGrid({
    super.key,
    required this.renderer,
    required this.origin,
  });

  final TerminalRenderer renderer;
  final Offset origin;

  @override
  _RenderTerminalGrid createRenderObject(BuildContext context) =>
      _RenderTerminalGrid(renderer, origin);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderTerminalGrid renderObject,
  ) {
    renderObject
      ..renderer = renderer
      ..origin = origin;
  }
}

class _RenderTerminalGrid extends RenderBox {
  _RenderTerminalGrid(this._renderer, this._origin);

  TerminalRenderer _renderer;
  set renderer(TerminalRenderer value) {
    if (identical(value, _renderer)) return;
    _renderer = value;
    markNeedsPaint();
  }

  Offset _origin;
  set origin(Offset value) {
    if (value == _origin) return;
    _origin = value;
    markNeedsPaint();
  }

  @override
  bool get isRepaintBoundary => true;

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    final bounds = offset & size;
    canvas
      ..save()
      ..clipRect(bounds)
      ..drawRect(bounds, Paint()..color = _renderer.backgroundColor);
    _renderer.paint(canvas, offset + _origin);
    canvas.restore();
  }
}

/// The scrollbar: the overview ruler (upstream OverviewRulerRenderer, not on
/// the alternate screen) and the slider over it.
class _ScrollbarPainter extends CustomPainter {
  _ScrollbarPainter(this._state)
    : super(
        repaint: Listenable.merge([_state._scrollbarRepaint, _state._fade]),
      );

  final _TerminalWidgetState _state;

  @override
  void paint(Canvas canvas, Size size) {
    final source = _state._source;
    final colors = source.themeService.colors;
    final dpr = _state._renderer.devicePixelRatio;
    final scrollbar = source.optionsService.rawOptions.scrollbar;
    final ruler = scrollbar.overviewRuler;
    if (ruler != null && !source.isAlternateBuffer) {
      _paintRuler(canvas, size, dpr, colors, ruler);
    }
    final slider = _state._slider();
    final opacity = _state._sliderDrag != null ? 1.0 : _state._fade.value;
    if (!slider.needed || opacity <= 0) return;
    final color = _state._sliderDrag != null
        ? colors.scrollbarSliderActiveBackground
        : _state._sliderHovered
        ? colors.scrollbarSliderHoverBackground
        : colors.scrollbarSliderBackground;
    final argb = argbOfRgba(color.rgba);
    final alpha = ((argb >>> 24) * opacity).round();
    canvas.drawRect(
      Rect.fromLTWH(0, slider.position, size.width, slider.size),
      Paint()..color = Color((alpha << 24) | (argb & 0xFFFFFF)),
    );
  }

  void _paintRuler(
    Canvas canvas,
    Size size,
    double dpr,
    TerminalColorSet colors,
    IOverviewRulerOptions ruler,
  ) {
    // Upstream draws on a canvas of device pixels.
    final width = (size.width * dpr).round();
    final height = (size.height * dpr).round();
    if (width <= 1 || height <= 1) return;
    canvas.save();
    canvas.scale(1 / dpr);
    final paint = Paint()
      ..color = Color(argbOfRgba(colors.overviewRulerBorder.rgba));
    canvas.drawRect(Rect.fromLTWH(0, 0, 1, height.toDouble()), paint);
    if (ruler.showTopBorder ?? false) {
      canvas.drawRect(Rect.fromLTWH(1, 0, width - 1.0, 1), paint);
    }
    if (ruler.showBottomBorder ?? false) {
      canvas.drawRect(Rect.fromLTWH(1, height - 1.0, width - 1.0, 1), paint);
    }
    final decorations = _state._source.decorationService;
    if (decorations != null) {
      final lines = _state._source.buffer.lines.length;
      final zones = _colorZones(decorations, lines, height, dpr);
      final outer = ((width - 1) / 3).floor();
      final inner = ((width - 1) / 3).ceil();
      final pixelsPerLine = height / lines;
      final nonFull = (math.max(math.min(pixelsPerLine, 12), 6) * dpr)
          .roundToDouble();
      final full = (2 * dpr).roundToDouble();
      for (final pass in const [false, true]) {
        for (final zone in zones) {
          final isFull = zone.position == 'full';
          if (isFull != pass) continue;
          final (x, w) = switch (zone.position) {
            'left' => (1, outer),
            'center' => (1 + outer, inner),
            'right' => (1 + outer + inner, outer),
            _ => (1, width),
          };
          final drawHeight = isFull ? full : nonFull;
          final y = ((height - 1) * (zone.start / lines) - drawHeight / 2)
              .round();
          final h =
              ((height - 1) * ((zone.end - zone.start) / lines) + drawHeight)
                  .round();
          paint.color = zone.color;
          canvas.drawRect(
            Rect.fromLTWH(
              x.toDouble(),
              y.toDouble(),
              w.toDouble(),
              h.toDouble(),
            ),
            paint,
          );
        }
      }
    }
    canvas.restore();
  }

  /// Upstream ColorZoneStore: decorations of one color and lane on
  /// adjacent lines merge into a zone.
  List<_ColorZone> _colorZones(
    IDecorationService service,
    int lines,
    int height,
    double dpr,
  ) {
    final zones = <_ColorZone>[];
    final pixelsPerLine = height / lines;
    final nonFull = (math.max(math.min(pixelsPerLine, 12), 6) * dpr)
        .roundToDouble();
    final full = (2 * dpr).roundToDouble();
    int padding(String position) =>
        (lines / (height - 1) * (position == 'full' ? full : nonFull)).floor();
    outer:
    for (final decoration in service.decorations) {
      final options = decoration.options.overviewRulerOptions;
      if (options == null) continue;
      final line = decoration.marker.line;
      final position = options.position ?? 'full';
      final color = _cssColor(options.color);
      if (color == null) continue;
      for (final zone in zones) {
        if (zone.css != options.color || zone.position != position) continue;
        if (line >= zone.start && line <= zone.end) continue outer;
        final pad = padding(position);
        if (line >= zone.start - pad && line <= zone.end + pad) {
          zone
            ..start = math.min(zone.start, line)
            ..end = math.max(zone.end, line);
          continue outer;
        }
      }
      zones.add(_ColorZone(options.color, color, position, line, line));
    }
    return zones;
  }

  static Color? _cssColor(String css) {
    try {
      return Color(argbOfRgba(color_lib.css.toColor(css).rgba));
    } on Object {
      return null;
    }
  }

  @override
  bool shouldRepaint(_ScrollbarPainter oldDelegate) => true;
}

class _ColorZone {
  _ColorZone(this.css, this.color, this.position, this.start, this.end);

  final String css;
  final Color color;
  final String position;
  int start;
  int end;
}

/// Upstream's composition view: the composing text in white on black, in
/// the terminal's font, over the cursor's cell.
class _CompositionView extends StatelessWidget {
  const _CompositionView({
    required this.text,
    required this.renderer,
    required this.maxWidth,
  });

  final String text;
  final TerminalRenderer renderer;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final font = renderer.metrics.font;
    final cellHeight = renderer.dimensions.cellHeight;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        color: const Color(0xFF000000),
        height: cellHeight,
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.clip,
          textDirection: TextDirection.ltr,
          style: TextStyle(
            color: const Color(0xFFFFFFFF),
            fontFamily: font.family,
            fontFamilyFallback: font.fallback,
            fontSize: font.size,
            fontWeight: font.weight,
            height: 1,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}
