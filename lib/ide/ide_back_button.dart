import 'package:flutter/material.dart';

import '../chat/widgets/hover_builder.dart';
import '../theme/app_theme.dart';
import '../theme/codicons.dart';
import 'ide_hover.dart';

/// The way back out of a page: "← Back" atop the settings' sidebar,
/// "← Models" over a provider's page. [IdeBackButton.icon] is the arrow
/// alone, with its words on hover (over a subagent's conversation).
class IdeBackButton extends StatelessWidget {
  /// The arrow and [label], muted, on a row's hover.
  const IdeBackButton({
    super.key,
    required this.label,
    required this.onTap,
    this.expand = false,
  }) : hover = null,
       focusNode = null,
       _iconOnly = false;

  /// The arrow alone; [hover] (else [label]) shows hovered.
  const IdeBackButton.icon({
    super.key,
    required this.label,
    required this.onTap,
    this.hover,
    this.focusNode,
  }) : expand = false,
       _iconOnly = true;

  final String label;
  final VoidCallback onTap;

  /// As wide as it is let be (a sidebar's row), else as its words.
  final bool expand;

  /// What the arrow alone says hovered: [label] with its key, say.
  final String? hover;
  final FocusNode? focusNode;

  final bool _iconOnly;

  /// The arrow's size, as the sidebars' icons.
  static const _iconSize = 15.0;

  @override
  Widget build(BuildContext context) {
    if (_iconOnly) return _buildIcon(context);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: hovered ? AppColors.hover : null,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              children: [
                Icon(
                  Codicons.arrowLeft,
                  size: _iconSize,
                  color: AppColors.textMuted,
                ),
                const SizedBox(width: 8),
                Flexible(
                  fit: expand ? FlexFit.tight : FlexFit.loose,
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIcon(BuildContext context) {
    return IdeHover(
      message: hover ?? label,
      child: IconButton(
        focusNode: focusNode,
        onPressed: onTap,
        tooltip: null,
        visualDensity: VisualDensity.compact,
        iconSize: _iconSize,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 26, height: 26),
        style: IconButton.styleFrom(
          hoverColor: AppColors.hover,
          foregroundColor: AppColors.textMuted,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        icon: Semantics(label: label, child: const Icon(Codicons.arrowLeft)),
      ),
    );
  }
}
