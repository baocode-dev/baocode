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
  });

  final Widget header;
  final Widget child;
  final bool highlighted;
  final double maxBodyHeight;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: highlighted
              ? themeColors['focusBorder']
              : AppColors.borderStrong,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 10, 6),
            child: header,
          ),
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
