import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'chat_drag.dart' show ChatDrag;
import 'window_controls.dart';

/// A title bar the app draws under the macOS traffic lights: a double click
/// on its empty part does what one on the system's own title bar does
/// (zoom, by default; see [WindowControls.handleTitleDoubleClick]), and a
/// press dragged there moves the window ([WindowControls.dragWindow]).
///
/// The window does not move itself by its title bar (MainFlutterWindow.swift):
/// the Window Server would start that drag before Flutter saw the press, so
/// what else the press might be, a pane's title dragged ([onDragStart]) or a
/// control's, could not keep it. Here the press is the app's to give.
///
/// Its empty part is where no control of [child] is hit, a control being
/// what listens to the pointer (a [Listener], so any [GestureDetector],
/// button or field): those keep their clicks, double clicks and drags, no
/// later than without it. Labels, icons and backgrounds are empty, so a
/// long title leaves the bar no less to drag the window by. A label that
/// is a control (a double click renames it) can still move the window:
/// see [TitleBarDragHandle].
///
/// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971: the title
/// bar's `.titlebar-drag-region` lies under its content, whose controls are
/// `-webkit-app-region: no-drag` (src/vs/workbench/browser/parts/titlebar/
/// titlebarPart.ts `createContentArea`, media/titlebarpart.css), and
/// Electron acts on a double click in the drag region (see
/// MainFlutterWindow.swift). Unlike there, the clicks are timed as
/// Flutter's double taps are ([kDoubleTapTimeout]), not by the system's
/// setting.
///
/// Elsewhere (Windows, the web) it is only [child], unless [onDragStart]
/// lets a pane's title bar drag that pane.
class TitleBarDoubleClick extends StatefulWidget {
  const TitleBarDoubleClick({
    super.key,
    required this.child,
    this.onDragStart,
    this.windowTitleBar = true,
    this.windowStart = 0,
  });

  final Widget child;

  /// A press in the bar's empty area moved far enough to drag a pane, not
  /// the window. Controls keep their own drags, just as they keep their
  /// double clicks.
  final ValueChanged<PointerMoveEvent>? onDragStart;

  /// How much of the bar's start is the window's even with [onDragStart]:
  /// the room left for the traffic lights, so panes side by side, the
  /// sidebar hidden, leave the window something to be dragged by.
  final double windowStart;

  /// False for a pane below another: it can drag but neither moves nor
  /// zooms the system's window.
  final bool windowTitleBar;

  @override
  State<TitleBarDoubleClick> createState() => _TitleBarDoubleClickState();
}

class _TitleBarDoubleClickState extends State<TitleBarDoubleClick> {
  /// Whether a press in the empty part is the system's window's: on macOS,
  /// for the bars along the window's top.
  bool get _ownsWindow =>
      widget.windowTitleBar && WindowControls.handlesTitleDoubleClick;

  /// Where the first click of a pair was pressed, until it is too late for
  /// the second.
  Offset? _firstClick;
  Timer? _firstClickTimer;

  /// The press under way, if any, and where it went down.
  int? _pointer;
  Offset _pressedAt = Offset.zero;

  /// Whether the press under way is in the [TitleBarDoubleClick.windowStart].
  bool _pressedInWindowStart = false;

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
        _pressedInWindowStart =
            _ownsWindow && event.localPosition.dx < widget.windowStart;
      case PointerMoveEvent(pointer: final pointer) when pointer == _pointer:
        if (event.buttons != kPrimaryButton) {
          _reset();
          return;
        }
        final distance = (event.position - _pressedAt).distance;
        if (widget.onDragStart case final start?
            when distance > ChatDrag.threshold && !_pressedInWindowStart) {
          _reset();
          start(event);
        } else if (distance > kDoubleTapTouchSlop) {
          // A drag, not a click: the window's, as on the system's title bar.
          _reset();
          if (_ownsWindow) {
            unawaited(
              WindowControls.dragWindow(viewId: View.of(context).viewId),
            );
          }
        }
      case PointerUpEvent(pointer: final pointer) when pointer == _pointer:
        _pointer = null;
        if (!_ownsWindow) {
          _reset();
          return;
        }
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
    if (widget.onDragStart == null && !_ownsWindow) return widget.child;
    return _EmptyAreaListener(onEvent: _onEvent, child: widget.child);
  }
}

/// Controls side by side in a [TitleBarDoubleClick]'s bar, the gaps between
/// them included: not its empty part, as VS Code's title bar toolbars are
/// `no-drag` as a whole (titlebarpart.css), so a double click that misses a
/// button by a little does nothing.
class TitleBarControls extends StatelessWidget {
  const TitleBarControls({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Listener(behavior: HitTestBehavior.opaque, child: child);
}

/// A control in a [TitleBarDoubleClick]'s bar that keeps its clicks but not
/// its drags: those move the window, as the system's title moves its
/// window when dragged. For the chat's title, which a double click renames.
/// Elsewhere than macOS it is only [child].
class TitleBarDragHandle extends StatefulWidget {
  const TitleBarDragHandle({super.key, required this.child});

  final Widget child;

  @override
  State<TitleBarDragHandle> createState() => _TitleBarDragHandleState();
}

class _TitleBarDragHandleState extends State<TitleBarDragHandle> {
  /// The press under way, if any, and where it went down.
  int? _pointer;
  Offset _pressedAt = Offset.zero;

  @override
  Widget build(BuildContext context) {
    if (!WindowControls.handlesTitleDoubleClick) return widget.child;
    return Listener(
      onPointerDown: (event) {
        if (event.buttons != kPrimaryButton) return;
        _pointer = event.pointer;
        _pressedAt = event.position;
      },
      onPointerMove: (event) {
        if (event.pointer != _pointer) return;
        if (event.buttons != kPrimaryButton) {
          _pointer = null;
        } else if ((event.position - _pressedAt).distance >
            kDoubleTapTouchSlop) {
          // A drag, not a click: as the bar's empty part's.
          _pointer = null;
          unawaited(WindowControls.dragWindow(viewId: View.of(context).viewId));
        }
      },
      onPointerUp: (_) => _pointer = null,
      onPointerCancel: (_) => _pointer = null,
      child: widget.child,
    );
  }
}

/// Gives [onEvent] the pointer events of presses where no control of [child]
/// is hit, and takes those presses (the bar is on top there, as the drag
/// region is); where one is hit, it is not there. A control is what listens
/// to the pointer ([RenderPointerListener]); labels, icons and backgrounds,
/// hit as they may be, are not.
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
    // Looked at apart first: the entries keep the transforms of the result
    // they are added to.
    final under = BoxHitTestResult();
    if (hitTestChildren(under, position: position) &&
        under.path.any((entry) => entry.target is RenderPointerListener)) {
      return hitTestChildren(result, position: position);
    }
    // Labels still get the pointer, for a cursor of their own.
    hitTestChildren(result, position: position);
    result.add(BoxHitTestEntry(this, position));
    return true;
  }

  @override
  void handleEvent(PointerEvent event, HitTestEntry entry) => onEvent(event);
}
