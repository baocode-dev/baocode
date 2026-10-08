import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'window_caption.dart';
import 'window_controls.dart';

/// A title bar the app draws under the macOS traffic lights: a double click
/// on its empty part does what one on the system's own title bar does
/// (zoom, by default; see [WindowControls.handleTitleDoubleClick]).
///
/// Its empty part is where none of [child]'s widgets is hit: buttons,
/// fields and anything else there keep their clicks, double clicks
/// included, no later than without it. So [child] should not have a
/// background of its own that is hit (a [ColoredBox]): color the bar
/// around this instead.
///
/// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971: the title
/// bar's `.titlebar-drag-region` lies under its content, whose controls are
/// `-webkit-app-region: no-drag` (src/vs/workbench/browser/parts/titlebar/
/// titlebarPart.ts `createContentArea`, media/titlebarpart.css), and
/// Electron acts on a double click in the drag region (see
/// MainFlutterWindow.swift). Unlike there, a label that is hit (any [Text])
/// is not empty: wrap one that should be in [IgnorePointer]. And the clicks
/// are timed as Flutter's double taps are ([kDoubleTapTimeout]), not by the
/// system's setting.
///
/// Elsewhere (Windows, the web) it is only [child].
class TitleBarDoubleClick extends StatefulWidget {
  const TitleBarDoubleClick({super.key, required this.child});

  final Widget child;

  @override
  State<TitleBarDoubleClick> createState() => _TitleBarDoubleClickState();
}

class _TitleBarDoubleClickState extends State<TitleBarDoubleClick> {
  /// Where the first click of a pair was pressed, until it is too late for
  /// the second.
  Offset? _firstClick;
  Timer? _firstClickTimer;

  /// The press under way, if any, and where it went down.
  int? _pointer;
  Offset _pressedAt = Offset.zero;

  // Outside the gesture arena: nothing that also gets these presses (an
  // ancestor's recognizer) waits for it, or wins or loses to it. As
  // DoubleTapGestureRecognizer otherwise: the second press within
  // kDoubleTapTimeout of the first click's release and kDoubleTapSlop of its
  // press, neither moving past kDoubleTapTouchSlop; acted on at the second
  // release, as AppKit and Chromium do.
  void _onEvent(PointerEvent event) {
    switch (event) {
      case PointerDownEvent():
        // One press at a time, of the primary button.
        if (_pointer != null || event.buttons != kPrimaryButton) {
          _reset();
          return;
        }
        if (_firstClick case final first?
            when (event.position - first).distance > kDoubleTapSlop) {
          _reset();
        }
        // The second press may be held as long as it takes.
        _firstClickTimer?.cancel();
        _pointer = event.pointer;
        _pressedAt = event.position;
      case PointerMoveEvent(pointer: final pointer) when pointer == _pointer:
        // A drag, not a click.
        if ((event.position - _pressedAt).distance > kDoubleTapTouchSlop) {
          _reset();
        }
      case PointerUpEvent(pointer: final pointer) when pointer == _pointer:
        _pointer = null;
        if (_firstClick == null) {
          _firstClick = _pressedAt;
          _firstClickTimer = Timer(kDoubleTapTimeout, _reset);
        } else {
          _reset();
          unawaited(WindowControls.handleTitleDoubleClick());
        }
      case PointerCancelEvent(pointer: final pointer) when pointer == _pointer:
        _reset();
    }
  }

  void _reset() {
    _firstClickTimer?.cancel();
    _firstClickTimer = null;
    _firstClick = null;
    _pointer = null;
  }

  @override
  void dispose() {
    _firstClickTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!WindowControls.handlesTitleDoubleClick) return widget.child;
    return _EmptyAreaListener(onEvent: _onEvent, child: widget.child);
  }
}

/// Controls side by side in a [TitleBarDoubleClick]'s bar, the gaps between
/// them included: not its empty part, as VS Code's title bar toolbars are
/// `no-drag` as a whole (titlebarpart.css), so a double click that misses a
/// button by a little does nothing.
///
/// Where the app draws the window's caption (see [WindowCaption]), the
/// window leaves their pixels to Flutter, rather than dragging itself by
/// them.
class TitleBarControls extends StatefulWidget {
  const TitleBarControls({super.key, required this.child});

  final Widget child;

  @override
  State<TitleBarControls> createState() => _TitleBarControlsState();
}

class _TitleBarControlsState extends State<TitleBarControls> {
  WindowCaptionState? _caption;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final caption = WindowCaption.maybeOf(context);
    if (identical(caption, _caption)) return;
    _caption?.remove(context);
    _caption = caption?..add(context);
  }

  @override
  void dispose() {
    _caption?.remove(context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Listener(behavior: HitTestBehavior.opaque, child: widget.child);
}

/// Gives [onEvent] the pointer events of presses where none of [child] is
/// hit, and takes those presses (the bar is on top there, as the drag region
/// is); where [child] is hit, it is not there.
class _EmptyAreaListener extends SingleChildRenderObjectWidget {
  const _EmptyAreaListener({required this.onEvent, required super.child});

  final ValueChanged<PointerEvent> onEvent;

  @override
  _RenderEmptyAreaListener createRenderObject(BuildContext context) =>
      _RenderEmptyAreaListener(onEvent);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderEmptyAreaListener renderObject,
  ) {
    renderObject.onEvent = onEvent;
  }
}

class _RenderEmptyAreaListener extends RenderProxyBox {
  _RenderEmptyAreaListener(this.onEvent);

  ValueChanged<PointerEvent> onEvent;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) return false;
    if (hitTestChildren(result, position: position)) return true;
    result.add(BoxHitTestEntry(this, position));
    return true;
  }

  @override
  void handleEvent(PointerEvent event, HitTestEntry entry) => onEvent(event);
}
