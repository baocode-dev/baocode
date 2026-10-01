import 'dart:async';

import 'package:flutter/material.dart';

import '../../ide/ide_menu.dart';
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../../theme/workbench_theme.dart' show themeColors;

/// A setting's choice, a dropdown (`.monaco-select-box`) of the others.
class SettingsDropdown extends StatefulWidget {
  const SettingsDropdown({
    super.key,
    required this.current,
    required this.semanticLabel,
    required this.entries,
  });

  /// The choice in effect, as shown.
  final String current;

  /// The setting and its choice, as read out.
  final String semanticLabel;
  final List<IdeMenuEntry> Function() entries;

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
            height: 26,
            constraints: const BoxConstraints(minWidth: 140, maxWidth: 240),
            padding: const EdgeInsets.only(left: 8, right: 4),
            decoration: BoxDecoration(
              color: colors['dropdown.background'],
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: _hover
                    ? colors['focusBorder']
                    : colors.get('dropdown.border') ?? AppColors.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
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
                const SizedBox(width: 12),
                Icon(
                  Codicons.chevronDown,
                  size: 14,
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
