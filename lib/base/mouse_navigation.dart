import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Where the mouse's back and forward buttons (its side buttons) go back
/// and forward in what it holds (#516): out of a subagent, from a file's
/// changes to their list, to the conversation before.
///
/// [onBack] and [onForward] say whether they went anywhere. The innermost
/// one under the pointer that did has the press: those around it let it
/// be, as the IDE's history does while a subagent in its chat goes back.
class MouseNavigation extends StatelessWidget {
  const MouseNavigation({
    super.key,
    this.onBack,
    this.onForward,
    required this.child,
  });

  final bool Function()? onBack;
  final bool Function()? onForward;
  final Widget child;

  /// The last press one went back or forward with: seen innermost first.
  static int? _taken;

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (event) {
      if (event.pointer == _taken) return;
      final go = event.buttons & kBackMouseButton != 0
          ? onBack
          : event.buttons & kForwardMouseButton != 0
          ? onForward
          : null;
      if (go != null && go()) _taken = event.pointer;
    },
    child: child,
  );
}
