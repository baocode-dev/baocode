import 'package:flutter/material.dart';

import 'hover_builder.dart';

/// A [Scrollbar] shown while the mouse is over what it scrolls, as VS
/// Code's editors' are, not only as it scrolls: what scrolls further shows
/// so as the mouse comes in.
class HoverScrollbar extends StatelessWidget {
  const HoverScrollbar({
    super.key,
    required this.controller,
    required this.child,
    this.notificationPredicate,
  });

  final ScrollController controller;
  final Widget child;

  /// Which scrolls it follows; those of [child] itself when null.
  final ScrollNotificationPredicate? notificationPredicate;

  @override
  Widget build(BuildContext context) => HoverBuilder(
    builder: (context, hovered) => Scrollbar(
      controller: controller,
      thumbVisibility: hovered,
      notificationPredicate: notificationPredicate,
      child: child,
    ),
  );
}
