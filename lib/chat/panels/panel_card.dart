import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/workbench_theme.dart' show themeColors;

/// Shared chrome for the panels stacked above the composer.
class PanelCard extends StatelessWidget {
  const PanelCard({
    super.key,
    required this.header,
    required this.child,
    this.highlighted = false,
    this.maxBodyHeight = 280,
    this.collapsed = false,
  });

  final Widget header;
  final Widget child;
  final bool highlighted;
  final double maxBodyHeight;

  /// The header alone, so the chat above it has the room.
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: AppColors.bubbleFill,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: highlighted
              ? themeColors['focusBorder']
              : AppColors.bubbleBorder(),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(12, 9, 10, collapsed ? 9 : 6),
            child: header,
          ),
          if (!collapsed)
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxBodyHeight),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(8, 0, 10, 10),
                child: child,
              ),
            ),
        ],
      ),
    );
  }
}
