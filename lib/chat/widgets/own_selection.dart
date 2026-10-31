import 'package:flutter/widgets.dart';

/// What selects on its own in the conversation (an editor in a card): out
/// of the conversation's selection, and a press in it neither starts that
/// selection nor clears it, nor takes the focus from it ([pressedIn]).
class OwnSelection extends StatelessWidget {
  const OwnSelection({super.key, required this.child});

  final Widget child;

  /// The last press in one: seen before the conversation's own, which is
  /// further out.
  static int? _pointer;

  /// Whether [event], a press going down, is in one.
  static bool pressedIn(PointerDownEvent event) => event.pointer == _pointer;

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (event) => _pointer = event.pointer,
    child: SelectionContainer.disabled(child: child),
  );
}
