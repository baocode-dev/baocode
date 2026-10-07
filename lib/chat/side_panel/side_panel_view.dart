import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../ide/file_service.dart';
import '../../ide/ide_hover.dart';
import '../../ide/ide_list.dart';
import '../../ide/ide_modern_ui.dart';
import '../../keybindings/chat_keybindings.dart';
import '../../keybindings/keybinding_service.dart';
import '../../l10n/l10n.dart';
import '../../sidebar/sidebar.dart' show SidebarIconButton;
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../../theme/material_file_icons.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../chat_session.dart';
import '../panels/change_tree.dart';
import '../widgets/code_citation.dart' show CodeColorizer;
import '../widgets/hover_builder.dart';
import 'file_link.dart';
import 'file_open.dart';
import 'file_preview.dart';
import 'side_panel_controller.dart';

/// [child] (the conversations) and, at its right while [panel] shows, the
/// side panel [builder] builds: beside it, its left edge dragged to make
/// it wider or narrower (a double click gives back its width); over it,
/// where the conversations would be narrower than [minChat] beside it.
class AgentSidePanelArea extends StatefulWidget {
  const AgentSidePanelArea({
    super.key,
    required this.panel,
    required this.builder,
    required this.child,
  });

  final AgentSidePanel panel;
  final WidgetBuilder builder;
  final Widget child;

  /// The least the conversations keep beside it.
  static const minChat = 360.0;

  /// The strip at its left edge that takes the drag.
  static const sashWidth = 5.0;

  @override
  State<AgentSidePanelArea> createState() => _AgentSidePanelAreaState();
}

class _AgentSidePanelAreaState extends State<AgentSidePanelArea> {
  bool _dragging = false;
  ({double x, double width})? _dragStart;

  AgentSidePanel get _panel => widget.panel;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _panel,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final room = constraints.maxWidth;
        final shown = _panel.shown;
        final overlay = room - _panel.width < AgentSidePanelArea.minChat;
        final width = overlay
            ? math.min(_panel.width, math.max(0.0, room - 48))
            : _panel.width;
        // The conversations stay the first child, the panel shown or
        // not, beside or over them, so they are never built anew for it.
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              right: shown && !overlay
                  ? width + AgentSidePanelArea.sashWidth
                  : 0,
              child: widget.child,
            ),
            if (shown) ...[
              if (overlay)
                Positioned.fill(
                  child: GestureDetector(
                    onTap: _panel.hide,
                    child: const ColoredBox(color: Color(0x33000000)),
                  ),
                ),
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                width: width + AgentSidePanelArea.sashWidth,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    boxShadow: overlay
                        ? [
                            BoxShadow(
                              color: themeColors['widget.shadow'],
                              blurRadius: 24,
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _sash(),
                      Expanded(
                        child: ColoredBox(
                          color: AppColors.background,
                          child: widget.builder(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_dragging)
                const Positioned.fill(
                  child: MouseRegion(cursor: SystemMouseCursors.resizeColumn),
                ),
            ],
          ],
        );
      },
    ),
  );

  Widget _sash() => MouseRegion(
    cursor: SystemMouseCursors.resizeColumn,
    child: GestureDetector(
      key: const ValueKey('side-panel-sash'),
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      onHorizontalDragStart: (details) => setState(() {
        _dragging = true;
        _dragStart = (x: details.globalPosition.dx, width: _panel.width);
      }),
      onHorizontalDragUpdate: (details) {
        final start = _dragStart;
        if (start == null) return;
        final room = (context.size?.width ?? double.infinity) -
            AgentSidePanelArea.minChat;
        _panel.width = math.min(
          start.width - (details.globalPosition.dx - start.x),
          math.max(AgentSidePanel.minWidth, room),
        );
      },
      onHorizontalDragEnd: (_) => _endDrag(),
      onHorizontalDragCancel: _endDrag,
      onDoubleTap: () {
        _panel.width = AgentSidePanel.defaultWidth;
        _panel.save();
      },
      child: Container(
        width: AgentSidePanelArea.sashWidth,
        alignment: Alignment.centerRight,
        // At rest the line between the two; dragged, as thick as the IDE's
        // sashes, in their `sash.hoverBorder`.
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: _dragging ? IdeModernUI.gap : 1,
          color: _dragging ? IdeModernUI.sashHover : AppColors.border,
        ),
      ),
    ),
  );

  void _endDrag() {
    if (!mounted) return;
    setState(() {
      _dragging = false;
      _dragStart = null;
    });
    _panel.save();
  }
}

/// The side panel for [session]'s conversation: its tabs (the changes,
/// then the files opened) over the one in front.
class AgentSidePanelView extends StatelessWidget {
  const AgentSidePanelView({
    super.key,
    required this.panel,
    required this.session,
    required this.files,
    this.readBytes,
    this.paths,
    this.colorize,
    this.onOpenInIde,
  });

  final AgentSidePanel panel;
  final ChatSession session;

  /// The project's, on its host.
  final IdeFileService files;
  final Future<Uint8List> Function(String path)? readBytes;
  final p.Context? paths;
  final CodeColorizer? colorize;

  /// Opens a file shown in the IDE instead.
  final ValueChanged<FileOpenRequest>? onOpenInIde;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([panel, session]),
      builder: (context, _) {
        final tabs = panel.tabsOf(session);
        final active = tabs.active;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TabBar(
              panel: panel,
              session: session,
              tabs: tabs,
              changes: session.fileChanges.length,
            ),
            Expanded(
              child: active == null
                  ? _Changes(panel: panel, session: session)
                  : FilePreview(
                      key: ValueKey((active.path, active.diff)),
                      request: active.request,
                      reveal: active.reveal,
                      files: files,
                      root: session.root,
                      readBytes: readBytes,
                      paths: paths,
                      colorize: colorize,
                      onOpenFile: (request) {
                        final root = session.root;
                        if (root == null) return;
                        final path = FileLink.resolvePath(
                          request.path,
                          root,
                          paths: paths,
                        );
                        if (path != null) {
                          panel.open(
                            session,
                            FileOpenRequest(path, range: request.range),
                          );
                        }
                      },
                      actions: [
                        if (onOpenInIde case final open?)
                          IdeActionButton(
                            icon: Codicons.goToFile,
                            tooltip: context.l10n.sidePanelOpenInIde,
                            onPressed: () => open(active.request),
                          ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// The tabs: Changes first, then the files open, the one in front marked;
/// Hide at the end.
class _TabBar extends StatelessWidget {
  const _TabBar({
    required this.panel,
    required this.session,
    required this.tabs,
    required this.changes,
  });

  final AgentSidePanel panel;
  final ChatSession session;
  final SidePanelTabs tabs;
  final int changes;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      height: AppMetrics.titleBarHeight + 5,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                children: [
                  _Tab(
                    active: tabs.active == null,
                    icon: Icon(
                      Codicons.diffMultiple,
                      size: 14,
                      color: AppColors.textMuted,
                    ),
                    label: changes == 0
                        ? l10n.sidePanelChanges
                        : '${l10n.sidePanelChanges}  $changes',
                    onTap: () => panel.activate(session, null),
                  ),
                  for (final tab in tabs.files)
                    _Tab(
                      key: ValueKey((tab.path, tab.diff)),
                      active: identical(tabs.active, tab),
                      icon: FileIcon(tab.path, size: 14),
                      label: p.basename(tab.path),
                      diff: tab.diff,
                      tooltip: tab.path,
                      onTap: () => panel.activate(session, tab),
                      onClose: () => panel.close(session, tab),
                    ),
                ],
              ),
            ),
          ),
          IdeActionButton(
            icon: Codicons.close,
            tooltip: KeybindingService.instance.titleWithKeybinding(
              l10n.sidePanelHide,
              ChatCommandIds.toggleSidePanel,
            ),
            onPressed: panel.hide,
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    super.key,
    required this.active,
    required this.icon,
    required this.label,
    required this.onTap,
    this.diff = false,
    this.tooltip,
    this.onClose,
  });

  final bool active;
  final Widget icon;
  final String label;
  final VoidCallback onTap;

  /// It shows a file's changes: marked so beside the file's own tab.
  final bool diff;
  final String? tooltip;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final tab = HoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (context, hovered) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        // A middle click closes it, as an editor's tab.
        onTertiaryTapUp: onClose == null ? null : (_) => onClose!(),
        child: Container(
          height: 26,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: EdgeInsets.only(left: 8, right: onClose == null ? 10 : 2),
          decoration: BoxDecoration(
            color: active
                ? AppColors.hover
                : hovered
                ? AppColors.hover.withValues(alpha: AppColors.hover.a * 0.5)
                : null,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon,
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: active ? AppColors.textPrimary : AppColors.textMuted,
                  ),
                ),
              ),
              if (diff) ...[
                const SizedBox(width: 4),
                Icon(Codicons.diff, size: 12, color: AppColors.textFaint),
              ],
              if (onClose case final close?)
                Opacity(
                  opacity: active || hovered ? 1 : 0,
                  child: IdeActionButton(
                    icon: Codicons.close,
                    iconSize: 13,
                    size: 20,
                    tooltip: context.l10n.sidePanelCloseTab,
                    onPressed: close,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      selected: active,
      label: tooltip ?? label,
      child: tab,
    );
  }
}

/// The files the agent changed (see [ChangeTree]), each opening its
/// changes in a tab; or, while there are none, what goes here.
class _Changes extends StatelessWidget {
  const _Changes({required this.panel, required this.session});

  final AgentSidePanel panel;
  final ChatSession session;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final changes = session.fileChanges;
    final root = session.root;
    if (changes.isEmpty || root == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Codicons.diffMultiple, size: 22, color: AppColors.textFaint),
              const SizedBox(height: 10),
              Text(
                l10n.sidePanelNoChanges,
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.sidePanelNoChangesDetail,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textFaint, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Align(
          alignment: Alignment.topCenter,
          child: ChangeTree(
            root: root,
            changes: changes,
            maxRows: math.max(
              1,
              ((constraints.maxHeight - 12) / IdeListColors.rowHeight).floor(),
            ),
            onOpen: (change) => panel.open(
              session,
              FileOpenRequest(
                change.path,
                diff: true,
                change: change,
                original: session.originalOf(change),
              ),
            ),
            onKeep: session.keepChanges,
            onUndo: session.undoChanges,
          ),
        ),
      ),
    );
  }
}

/// The title bar's button for the side panel: the layout icon, which
/// shows whether it is open; its hover Toggle Side Panel's title.
class SidePanelToggle extends StatelessWidget {
  const SidePanelToggle({
    super.key,
    required this.shown,
    required this.onTap,
    this.size = 24,
  });

  final bool shown;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) => SidebarIconButton(
    icon: shown ? Codicons.layoutSidebarRight : Codicons.layoutSidebarRightOff,
    tooltip: context.l10n.cmdToggleSidePanel,
    command: ChatCommandIds.toggleSidePanel,
    size: size,
    onTap: onTap,
  );
}
