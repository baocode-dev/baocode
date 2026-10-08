/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// VS Code's text button (`.monaco-text-button`), in the color theme.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/base/browser/ui/button/button.css and button.ts, with the color
// theme's `button.*` colors (platform/theme/browser/defaultStyles.ts
// `defaultButtonStyles`).

import 'package:flutter/material.dart';

import '../theme/codicons.dart';
import '../theme/workbench_theme.dart' show themeColors;
import 'ide_spinning.dart';

/// The color theme's `button.*` colors.
abstract final class IdeButtonColors {
  static Color get background => themeColors['button.background'];
  static Color get hoverBackground => themeColors['button.hoverBackground'];
  static Color get foreground => themeColors['button.foreground'];

  /// Transparent where the theme has none: there is always a border.
  static Color get border => themeColors['button.border'];
  static Color get secondaryBackground =>
      themeColors['button.secondaryBackground'];
  static Color get secondaryHoverBackground =>
      themeColors['button.secondaryHoverBackground'];
  static Color get secondaryForeground =>
      themeColors['button.secondaryForeground'];

  /// `button.secondaryBorder`, else `button.border`.
  static Color get secondaryBorder =>
      themeColors.get('button.secondaryBorder') ?? border;

  /// Between a split button's parts.
  static Color get separator => themeColors['button.separator'];
}

/// A text button: 12px text, `padding: 4px 8px`, 4px corners, a 1px
/// border; [secondary] for all but a group's first.
class IdeButton extends StatefulWidget {
  const IdeButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.spinning = false,
    this.counts = const [],
    this.secondary = false,
    this.expand = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
  });

  final String label;
  final VoidCallback? onPressed;

  /// A 16px codicon before [label], as `$(icon) label` gives.
  final IconData? icon;

  /// `$(sync~spin)` in [icon]'s place.
  final bool spinning;

  /// After [label], each count and its icon (` 2$(arrow-up)`).
  final List<(int, IconData)> counts;
  final bool secondary;

  /// Less in a bar lower than a button, e.g. a title bar.
  final EdgeInsets padding;

  /// As wide as it may be (`width: 100%`), else as its label.
  final bool expand;

  @override
  State<IdeButton> createState() => _IdeButtonState();
}

class _IdeButtonState extends State<IdeButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final secondary = widget.secondary;
    final foreground = secondary
        ? IdeButtonColors.secondaryForeground
        : IdeButtonColors.foreground;
    final style = TextStyle(fontSize: 12, height: 16 / 12, color: foreground);
    // With counts, one line: they keep their room, the label gives way.
    final counted = widget.counts.isNotEmpty;
    Widget label = Text(
      widget.label,
      textAlign: TextAlign.center,
      maxLines: counted ? 1 : null,
      overflow: counted ? TextOverflow.ellipsis : null,
      style: style,
    );
    final icon = widget.spinning
        ? IdeSpinning(Icon(Codicons.sync, size: 16, color: foreground))
        : widget.icon == null
        ? null
        : Icon(widget.icon, size: 16, color: foreground);
    if (icon != null || counted) {
      label = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[icon, const SizedBox(width: 4)],
          Flexible(child: label),
          for (final (count, icon) in widget.counts) ...[
            Text(' $count', style: style),
            // `.monaco-text-button .codicon { margin: 0 0.2em }`.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.4),
              child: Icon(icon, size: 16, color: foreground),
            ),
          ],
        ],
      );
    }
    final background = secondary
        ? (_hover && enabled
              ? IdeButtonColors.secondaryHoverBackground
              : IdeButtonColors.secondaryBackground)
        : (_hover && enabled
              ? IdeButtonColors.hoverBackground
              : IdeButtonColors.background);
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: Opacity(
            opacity: enabled ? 1 : 0.4,
            child: Container(
              padding: widget.padding,
              alignment: widget.expand ? Alignment.center : null,
              decoration: BoxDecoration(
                color: background,
                border: Border.all(
                  color: secondary
                      ? IdeButtonColors.secondaryBorder
                      : IdeButtonColors.border,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: label,
            ),
          ),
        ),
      ),
    );
  }
}
