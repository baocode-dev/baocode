import 'dart:async';

import 'package:flutter/material.dart';

import '../../ide/ide_menu.dart';
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../../theme/workbench_theme.dart' show themeColors;

/// A setting's choice, a dropdown of the others: as wide as the choice
/// shown (or [width]), its chevron after it.
class SettingsDropdown extends StatefulWidget {
  const SettingsDropdown({
    super.key,
    required this.current,
    required this.semanticLabel,
    required this.entries,
    this.width,
  });

  /// The choice in effect, as shown.
  final String current;

  /// The setting and its choice, as read out.
  final String semanticLabel;
  final List<IdeMenuEntry> Function() entries;
  final double? width;

  @override
  State<SettingsDropdown> createState() => _SettingsDropdownState();
}

class _SettingsDropdownState extends State<SettingsDropdown> {
  bool _hover = false;

  void _open() {
    final box = context.findRenderObject()! as RenderBox;
    unawaited(
      showIdeMenu(
        context,
        anchor: box.localToGlobal(Offset.zero) & box.size,
        entries: widget.entries(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      excludeSemantics: true,
      onTap: _open,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _open,
          child: Container(
            width: widget.width,
            height: 26,
            constraints: const BoxConstraints(maxWidth: 260),
            padding: const EdgeInsets.only(left: 9, right: 6),
            decoration: BoxDecoration(
              color: _hover ? AppColors.hover : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.borderStrong),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  fit: widget.width == null ? FlexFit.loose : FlexFit.tight,
                  child: Text(
                    widget.current,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors['dropdown.foreground'],
                      fontSize: 12.5,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Codicons.chevronDown,
                  size: 13,
                  color: colors['dropdown.foreground'],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
