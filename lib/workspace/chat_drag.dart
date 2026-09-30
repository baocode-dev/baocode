import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'chat_grid.dart';
import 'window_controls.dart';
import 'workspace.dart';

/// Where an agent dragged over the conversations would go, released there:
/// the half of [target]'s pane on [side], or [target]'s place (null
/// [side]). [thread] shown already, its own pane: released, it is focused.
@immutable
class ChatDrop {
  const ChatDrop({
    required this.thread,
    required this.target,
    required this.side,
    required this.preview,
    this.growth = Size.zero,
    this.fits = true,
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

  @override
  bool operator ==(Object other) =>
      other is ChatDrop &&
      identical(other.thread, thread) &&
      identical(other.target, target) &&
      other.side == side &&
      other.preview == preview &&
      other.growth == growth &&
      other.fits == fits;

  @override
  int get hashCode => Object.hash(thread, target, side, preview, growth, fits);
}

/// An agent dragged from the sidebar onto the conversations, to show it
/// beside the others (see [ChatGridView]).
///
/// It follows the pointer that started it, wherever it goes: released
/// where the grid shows a drop, the drop is made ([onDrop]); anywhere
/// else, or on a right click or Esc on the way, nothing is.
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

  int? _pointer;

  void start(AgentThread thread, int pointer, Offset position) {
    if (_thread != null) _stop();
    _thread = thread;
    _pointer = pointer;
    _position = position;
    _room = null;
    // Every event of the pointer, wherever it is (not only over the row
    // that started it, which may go: the drawer closes).
    GestureBinding.instance.pointerRouter.addGlobalRoute(_route);
    HardwareKeyboard.instance.addHandler(_key);
    onStart?.call();
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
    _stop();
    notifyListeners();
  }

  void _route(PointerEvent event) {
    if (event.pointer != _pointer || _thread == null) return;
    switch (event) {
      // A right click on the way: the button joins the one held.
      case PointerMoveEvent(:final buttons)
          when buttons & kSecondaryMouseButton != 0:
        cancel();
      case PointerMoveEvent():
        _position = event.position;
        _update();
      case PointerUpEvent():
        final drop = _drop;
        _stop();
        notifyListeners();
        if (drop != null && drop.fits) onDrop(drop);
      case PointerCancelEvent():
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

  /// Asks the grid again where the agent would go.
  void _update() {
    final thread = _thread;
    if (thread == null) return;
    _drop = resolve?.call(thread, _position);
    notifyListeners();
  }

  void _stop() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_route);
    HardwareKeyboard.instance.removeHandler(_key);
    _thread = null;
    _pointer = null;
    _drop = null;
  }

  @override
  void dispose() {
    if (_thread != null) _stop();
    super.dispose();
  }
}

/// Makes [child] (a row of the sidebar) drag [thread] once the pointer
/// pressed on it has moved [ChatDrag.threshold]: a shorter move is still
/// the click it was.
class ChatDragSource extends StatefulWidget {
  const ChatDragSource({
    super.key,
    required this.drag,
    required this.thread,
    required this.child,
  });

  /// None for now (e.g. while the row is renamed): [child] as it is.
  final ChatDrag? drag;
  final AgentThread thread;
  final Widget child;

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

/// A pan (of the primary button, as by default) that begins past
/// [ChatDrag.threshold], not the mouse's 2 pixels: a click that slips a
/// little still opens the agent.
class _DragRecognizer extends PanGestureRecognizer {
  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) => globalDistanceMoved.abs() > ChatDrag.threshold;
}
