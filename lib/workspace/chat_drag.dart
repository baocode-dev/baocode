import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'chat_grid.dart';
import 'window_controls.dart';
import 'workspace.dart';

/// Where an agent dragged over the conversations would go, released there:
/// the half of [target]'s pane on [side], or [target]'s place (null
/// [side]). From the sidebar, [thread] shown already only focuses its own
/// pane. From a title bar ([rearrange]), the center swaps their places.
@immutable
class ChatDrop {
  const ChatDrop({
    required this.thread,
    required this.target,
    required this.side,
    required this.preview,
    this.growth = Size.zero,
    this.fits = true,
    this.rearrange = false,
  });

  final AgentThread thread;
  final AgentThread target;
  final PaneSide? side;

  /// Where its pane would be, in the grid.
  final Rect preview;

  /// How much wider and taller the window must get for the panes to keep
  /// their least size ([ChatGridView.minPane]).
  final Size growth;

  /// Whether the window can get that much larger on its screen; released
  /// where it cannot, nothing happens.
  final bool fits;

  /// A title bar's pane moved within the grid, not an agent opened from
  /// the sidebar: the center swaps their places, the edges move it beside.
  final bool rearrange;

  @override
  bool operator ==(Object other) =>
      other is ChatDrop &&
      identical(other.thread, thread) &&
      identical(other.target, target) &&
      other.side == side &&
      other.preview == preview &&
      other.growth == growth &&
      other.fits == fits &&
      other.rearrange == rearrange;

  @override
  int get hashCode =>
      Object.hash(thread, target, side, preview, growth, fits, rearrange);
}

/// Where else than the grid a dragged agent can go: the sidebar's list,
/// to order it among the others.
abstract interface class ChatDragList {
  /// Whether [position] (in the window) is over the list; it shows where
  /// [threads] would go there, if anywhere, until asked again.
  bool hover(List<AgentThread> threads, Offset position);

  /// [threads] released at [position], over the list.
  void drop(List<AgentThread> threads, Offset position);
}

/// An agent dragged from the sidebar onto the conversations, to show it
/// beside the others (see [ChatGridView]), or within the sidebar
/// ([list]), to order it. From a title bar ([rearranging]), its existing
/// pane is rearranged within the grid instead.
///
/// It follows the pointer that started it, wherever it goes: released
/// where the grid shows a drop, the drop is made ([onDrop]); over the
/// list, the list takes it; anywhere else, or on a right click or Esc on
/// the way, nothing is.
class ChatDrag extends ChangeNotifier {
  ChatDrag({required this.onDrop, this.onStart});

  /// Released over a drop the window can make room for.
  final ValueChanged<ChatDrop> onDrop;

  /// A drag began: e.g. the sidebar's drawer gets out of the way.
  final VoidCallback? onStart;

  /// Moved this far, a press on an agent drags it (rather than opening it).
  static const threshold = 4.0;

  /// The agent dragged; null when there is no drag.
  AgentThread? get thread => _thread;
  AgentThread? _thread;

  /// A pane dragged by its title bar: stays within the grid, never reorders
  /// the sidebar's list.
  bool get rearranging => _rearranging;
  bool _rearranging = false;

  /// The selection at drag start, in sidebar order; empty while idle.
  List<AgentThread> get threads => _threads;
  List<AgentThread> _threads = const [];

  /// Where the pointer is, in the window.
  Offset get position => _position;
  Offset _position = Offset.zero;

  /// Where a release now would put the agent, if anywhere.
  ChatDrop? get drop => _drop;
  ChatDrop? _drop;

  /// How much larger the window can get, asked as the drag begins; null
  /// until it answers, or where there is no window to ask (then the grid
  /// takes it that the window can grow).
  Size? get room => _room;
  Size? _room;

  /// Where the grid under the pointer would put the agent: set by the grid
  /// (there is none in the IDE).
  ChatDrop? Function(AgentThread thread, Offset position)? resolve;

  /// The sidebar's list, where it shows: over it, the grid shows no drop.
  ChatDragList? list;

  /// Whether the pointer is over [list].
  bool get overList => _overList;
  bool _overList = false;

  int? _pointer;
  AppLifecycleListener? _lifecycle;

  /// Told as the drag ends without a drop on the grid (released elsewhere,
  /// or cancelled): an agent made for it goes then.
  VoidCallback? _onMissed;

  /// [onMissed]: told where it ends without a drop on the grid, e.g. to
  /// take back an agent made to be dragged (see [ChatNewDragSource]); such
  /// a drag does not go over the list (it is in no order there yet).
  void start(
    AgentThread thread,
    int pointer,
    Offset position, {
    List<AgentThread>? threads,
    VoidCallback? onMissed,
    bool rearrange = false,
  }) {
    if (_thread != null) _stop();
    _thread = thread;
    _rearranging = rearrange;
    _threads = List.unmodifiable(threads ?? [thread]);
    _pointer = pointer;
    _position = position;
    _room = null;
    _onMissed = onMissed;
    _lifecycle = AppLifecycleListener(onInactive: cancel);
    // Every event of the pointer, wherever it is (not only over the row
    // that started it, which may go: the drawer closes).
    GestureBinding.instance.pointerRouter.addGlobalRoute(_route);
    HardwareKeyboard.instance.addHandler(_key);
    // A batch stays in the list, including when it is in a drawer.
    if (_threads.length == 1) onStart?.call();
    _update();
    unawaited(
      WindowControls.growRoom().then((room) {
        if (!identical(_thread, thread)) return;
        _room = room;
        _update();
      }),
    );
  }

  /// Ends the drag; nothing is dropped.
  void cancel() {
    if (_thread == null) return;
    final missed = _onMissed;
    _stop();
    notifyListeners();
    missed?.call();
  }

  void _route(PointerEvent event) {
    if (_thread == null) return;
    // Another press means the original release was lost; the drag's cursor
    // layer must not keep swallowing the rest of the window's input.
    if (event is PointerDownEvent) {
      cancel();
      return;
    }
    if (event.pointer != _pointer) return;
    switch (event) {
      case PointerHoverEvent():
        cancel();
      // A right click on the way, or a move with the primary button up.
      case PointerMoveEvent(:final buttons)
          when buttons & kPrimaryButton == 0 ||
              buttons & kSecondaryMouseButton != 0:
        cancel();
      case PointerMoveEvent():
        _position = event.position;
        _update();
      case PointerUpEvent():
        final drop = _drop;
        final (threads, overList, list) = (_threads, _overList, this.list);
        final missed = _onMissed;
        _stop();
        notifyListeners();
        if (overList) {
          list?.drop(threads, event.position);
        } else if (drop != null && drop.fits) {
          onDrop(drop);
        } else {
          missed?.call();
        }
      case PointerCancelEvent() || PointerRemovedEvent():
        cancel();
    }
  }

  bool _key(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape ||
        _thread == null) {
      return false;
    }
    cancel();
    return true;
  }

  /// Rechecks the drop when the sidebar scrolls under a stationary pointer.
  void refresh() => _update();

  /// Asks the list or grid again where the agents would go.
  void _update() {
    final thread = _thread;
    if (thread == null) return;
    // One made to be dragged is in no order of the list yet; a pane moved
    // within the grid never reorders it.
    _overList =
        _onMissed == null &&
        !_rearranging &&
        (list?.hover(_threads, _position) ?? false);
    _drop = _overList || _threads.length != 1
        ? null
        : resolve?.call(thread, _position);
    notifyListeners();
  }

  void _stop() {
    _lifecycle?.dispose();
    _lifecycle = null;
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_route);
    HardwareKeyboard.instance.removeHandler(_key);
    _thread = null;
    _rearranging = false;
    _threads = const [];
    _pointer = null;
    _drop = null;
    _overList = false;
    _onMissed = null;
  }

  @override
  void dispose() {
    if (_thread != null) _stop();
    super.dispose();
  }
}

/// Makes [child] (a sidebar row, or a pane's title) drag [thread] once the pointer
/// pressed on it has moved [ChatDrag.threshold]: a shorter move is still
/// the click it was.
class ChatDragSource extends StatefulWidget {
  const ChatDragSource({
    super.key,
    required this.drag,
    required this.thread,
    required this.child,
    this.threads,
    this.rearrange = false,
  });

  /// None for now (e.g. while the row is renamed): [child] as it is.
  final ChatDrag? drag;
  final AgentThread thread;
  final Widget child;
  final List<AgentThread> Function()? threads;

  /// The title of an existing pane, not a sidebar row.
  final bool rearrange;

  @override
  State<ChatDragSource> createState() => _ChatDragSourceState();
}

class _ChatDragSourceState extends State<ChatDragSource> {
  int? _pointer;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) => _pointer = event.pointer,
      child: RawGestureDetector(
        gestures: {
          if (widget.drag case final drag?)
            _DragRecognizer:
                GestureRecognizerFactoryWithHandlers<_DragRecognizer>(
                  _DragRecognizer.new,
                  (recognizer) => recognizer
                    ..onStart = (details) {
                      if (_pointer case final pointer?) {
                        drag.start(
                          widget.thread,
                          pointer,
                          details.globalPosition,
                          threads: widget.threads?.call(),
                          rearrange: widget.rearrange,
                        );
                      }
                    },
                ),
        },
        child: widget.child,
      ),
    );
  }
}

/// Makes [child] (a New Agent button) drag a new agent once the pointer
/// pressed on it has moved [ChatDrag.threshold]: [make] makes it as the
/// drag begins, [onMissed] takes it back where it is not dropped on the
/// grid. A shorter move is still the click it was.
class ChatNewDragSource extends StatefulWidget {
  const ChatNewDragSource({
    super.key,
    required this.drag,
    required this.make,
    required this.onMissed,
    required this.child,
  });

  /// None: [child] as it is.
  final ChatDrag? drag;
  final AgentThread Function() make;
  final ValueChanged<AgentThread> onMissed;
  final Widget child;

  @override
  State<ChatNewDragSource> createState() => _ChatNewDragSourceState();
}

class _ChatNewDragSourceState extends State<ChatNewDragSource> {
  int? _pointer;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) => _pointer = event.pointer,
      child: RawGestureDetector(
        gestures: {
          if (widget.drag case final drag?)
            _DragRecognizer:
                GestureRecognizerFactoryWithHandlers<_DragRecognizer>(
                  _DragRecognizer.new,
                  (recognizer) => recognizer
                    ..onStart = (details) {
                      final pointer = _pointer;
                      if (pointer == null) return;
                      final thread = widget.make();
                      final missed = widget.onMissed;
                      drag.start(
                        thread,
                        pointer,
                        details.globalPosition,
                        onMissed: () => missed(thread),
                      );
                    },
                ),
        },
        child: widget.child,
      ),
    );
  }
}

/// A pan (of the primary button, as by default) that begins past
/// [ChatDrag.threshold], not the mouse's 2 pixels: a click that slips a
/// little still opens the agent.
class _DragRecognizer extends PanGestureRecognizer {
  // A two-finger pan scrolls the list; only a pressed pointer drags a chat.
  @override
  bool isPointerPanZoomAllowed(PointerPanZoomStartEvent event) => false;

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) => globalDistanceMoved.abs() > ChatDrag.threshold;
}
