import 'package:flutter/gestures.dart' show kMiddleMouseButton;
import 'package:flutter/material.dart';

import '../chat/widgets/hover_builder.dart';
import '../chat/widgets/hover_scroll_text.dart';
import '../ide/ide_chat_title.dart' show IdeThreadIcon;
import '../ide/ide_hover.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import '../theme/codicons.dart';
import '../theme/workbench_theme.dart' show themeColors;
import 'thread_status_mark.dart';
import 'workspace.dart';

/// A pane's agents as tabs in its title bar, in place of its title: as
/// the bar's buttons are, without the editor tabs' borders. The one shown
/// is filled; a click shows another, its close button (or a middle click)
/// closes it, a right click opens its menu.
class PaneTabs extends StatelessWidget {
  const PaneTabs({
    super.key,
    required this.tabs,
    required this.shown,
    required this.onSelect,
    required this.onClose,
    required this.onMenu,
  });

  final List<AgentThread> tabs;
  final AgentThread shown;
  final ValueChanged<AgentThread> onSelect;
  final ValueChanged<AgentThread> onClose;
  final void Function(AgentThread tab, Offset position) onMenu;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final (i, tab) in tabs.indexed) ...[
          if (i > 0) const SizedBox(width: 2),
          _PaneTab(
            tab: tab,
            active: identical(tab, shown),
            onSelect: () => onSelect(tab),
            onClose: () => onClose(tab),
            onMenu: (position) => onMenu(tab, position),
          ),
        ],
      ],
    ),
  );
}

class _PaneTab extends StatelessWidget {
  const _PaneTab({
    required this.tab,
    required this.active,
    required this.onSelect,
    required this.onClose,
    required this.onMenu,
  });

  final AgentThread tab;
  final bool active;
  final VoidCallback onSelect;
  final VoidCallback onClose;
  final ValueChanged<Offset> onMenu;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = themeColors;
    return ThreadStatusBuilder(
      tab,
      (context, status) => HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) {
          final foreground = active || hovered
              ? AppColors.textPrimary
              : AppColors.textMuted;
          // The close button while hovered or shown; else what its agent
          // is waiting on, if anything.
          final mark = switch (status) {
            ThreadStatus.needsInput ||
            ThreadStatus.unread => ThreadStatusMark(status),
            _ => null,
          };
          return Listener(
            onPointerDown: (event) {
              if (event.buttons & kMiddleMouseButton != 0) onClose();
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onSelect,
              onSecondaryTapUp: (details) => onMenu(details.globalPosition),
              child: Container(
                height: 22,
                constraints: const BoxConstraints(maxWidth: 220),
                padding: const EdgeInsets.only(left: 7, right: 3),
                decoration: BoxDecoration(
                  color: active
                      ? colors['list.inactiveSelectionBackground']
                      : hovered
                      ? colors['toolbar.hoverBackground']
                      : null,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconTheme.merge(
                      data: IconThemeData(size: 14, color: foreground),
                      child: SizedBox.square(
                        dimension: 16,
                        child: Center(child: IdeThreadIcon(tab)),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      // Too long for the tab: scrolled to the rest while
                      // hovered, back to its start once left.
                      child: HoverScrollText(
                        tab.localizedTitle(l10n),
                        style: TextStyle(
                          color: foreground,
                          fontSize: 12,
                          fontWeight: active ? FontWeight.w500 : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    SizedBox.square(
                      dimension: 16,
                      child: hovered || (active && mark == null)
                          ? IdeHover(
                              message: l10n.commonClose,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: onClose,
                                child: Icon(
                                  Codicons.close,
                                  size: 12,
                                  color: foreground,
                                ),
                              ),
                            )
                          : Center(child: mark),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
