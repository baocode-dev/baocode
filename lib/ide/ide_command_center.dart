import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../keybindings/keybinding_service.dart';
import '../l10n/l10n.dart';
import '../theme/codicons.dart';
import '../theme/workbench_theme.dart' show themeColors;
import 'ide_hover.dart';

/// VS Code's command center, in the middle of the title bar: Go Back and
/// Go Forward (#539), then the search box that opens Quick Open. The IDE's
/// own title bar has it, and Windows' header over the IDE.
class IdeCommandCenter extends StatelessWidget {
  const IdeCommandCenter({
    super.key,
    required this.label,
    required this.tooltip,
    required this.onSearch,
    required this.navigation,
    required this.onNavigate,
  });

  /// What the search box reads: the project's name.
  final String label;

  /// `Search baocode (⌘P)`: upstream's `CommandCenterCenterViewItem
  /// .getTooltip` (commandCenterControl.ts), but the window title after it.
  final String tooltip;
  final VoidCallback onSearch;

  /// Whether Go Back and Go Forward have somewhere to go.
  final ValueListenable<({bool back, bool forward})> navigation;

  /// Goes back, or (false) forward.
  final ValueChanged<bool> onNavigate;

  static const backCommand = 'workbench.action.navigateBack';
  static const forwardCommand = 'workbench.action.navigateForward';

  @override
  Widget build(BuildContext context) {
    final keys = KeybindingService.instance;
    final l10n = context.l10n;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ValueListenableBuilder(
          valueListenable: navigation,
          builder: (context, can, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IdeActionButton(
                icon: Codicons.arrowLeft,
                tooltip: keys.titleWithKeybinding(l10n.cmdGoBack, backCommand),
                onPressed: can.back ? () => onNavigate(true) : null,
              ),
              const SizedBox(width: 2),
              IdeActionButton(
                icon: Codicons.arrowRight,
                tooltip: keys.titleWithKeybinding(
                  l10n.cmdGoForward,
                  forwardCommand,
                ),
                onPressed: can.forward ? () => onNavigate(false) : null,
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: _SearchBox(label: label, tooltip: tooltip, onTap: onSearch),
        ),
      ],
    );
  }
}

/// VS Code's title bar search box: opens Quick Open.
class _SearchBox extends StatefulWidget {
  const _SearchBox({
    required this.label,
    required this.tooltip,
    required this.onTap,
  });

  final String label;
  final String tooltip;
  final VoidCallback onTap;

  @override
  State<_SearchBox> createState() => _SearchBoxState();
}

class _SearchBoxState extends State<_SearchBox> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    final foreground =
        colors[_hover
            ? 'commandCenter.activeForeground'
            : 'commandCenter.foreground'];
    return IdeHover(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 380, minWidth: 160),
            height: 22,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            // `.command-center-center` (titlebarpart.css).
            decoration: BoxDecoration(
              color:
                  colors[_hover
                      ? 'commandCenter.activeBackground'
                      : 'commandCenter.background'],
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color:
                    colors[_hover
                        ? 'commandCenter.activeBorder'
                        : 'commandCenter.border'],
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Codicons.search, size: 14, color: foreground),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: foreground),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
