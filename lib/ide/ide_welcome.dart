import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:bao_editor/monaco/vs/base/common/labels.dart' show tildify;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../l10n/command_titles.dart';
import '../l10n/l10n.dart';
import '../platform/app_paths.dart';
import '../theme/codicons.dart';
import '../theme/workbench_theme.dart' show themeColors;
import 'ide_commands.dart';
import 'ide_quick_input.dart';

/// The editor area with no open file: the key shortcuts, VS Code's
/// watermark (workbench/browser/parts/editor/media/editorgroupview.css),
/// each also clickable. Without a folder, [IdeStartPage] instead.
class IdeWelcome extends StatelessWidget {
  const IdeWelcome({super.key, required this.commands});

  final List<IdeCommand> commands;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _emptyBackground,
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final command in commands) _WelcomeEntry(command: command),
            ],
          ),
        ),
      ),
    );
  }
}

/// An empty group's, else the editor's under it.
Color get _emptyBackground =>
    themeColors.get('editorGroup.emptyBackground') ??
    themeColors['editor.background'];

/// A window without a folder, VS Code's New Window as the Fast Ide shows
/// it: tiles for what to start with ([actions], each with
/// its keys), and the [recent] folders, the last opened first, with all of
/// them a click away ([onShowAllRecent], Open Recent).
class IdeStartPage extends StatelessWidget {
  const IdeStartPage({
    super.key,
    required this.actions,
    this.recent = const [],
    this.onOpenRecent,
    this.onShowAllRecent,
    this.home,
  });

  final List<IdeCommand> actions;

  /// Folders opened last, most recent first; [onOpenRecent] opens one.
  final List<String> recent;
  final ValueChanged<String>? onOpenRecent;
  final VoidCallback? onShowAllRecent;

  /// The home folder, shown as `~` in the recent folders' paths; the
  /// user's, by default.
  final String? home;

  /// Recent folders listed, at most.
  static const recentShown = 5;

  static const _width = 560.0;

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    final l10n = context.l10n;
    final home =
        this.home ?? (kIsWeb ? '' : AppPaths.home(Platform.environment));
    return ColoredBox(
      color: _emptyBackground,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = math.min(_width, constraints.maxWidth - 48);
          final columns = width >= 420 ? 3 : (width >= 260 ? 2 : 1);
          const gap = 10.0;
          final tile = (width - gap * (columns - 1)) / columns;
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: SizedBox(
                width: math.max(0, width),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        for (final action in actions)
                          SizedBox(
                            width: math.max(0, tile),
                            child: _StartTile(command: action),
                          ),
                      ],
                    ),
                    if (onOpenRecent case final open?
                        when recent.isNotEmpty) ...[
                      const SizedBox(height: 32),
                      // In line with the rows' insides.
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                l10n.ideStartRecent,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: colors['descriptionForeground'],
                                ),
                              ),
                            ),
                            if (onShowAllRecent case final showAll?)
                              _Link(
                                label: l10n.ideStartViewAll(recent.length),
                                onTap: showAll,
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      for (final path in recent.take(recentShown))
                        _RecentRow(
                          path: path,
                          home: home,
                          onOpen: () => open(path),
                        ),
                    ],
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

/// One of the start page's tiles: its icon, its name and its keys.
class _StartTile extends StatefulWidget {
  const _StartTile({required this.command});

  final IdeCommand command;

  @override
  State<_StartTile> createState() => _StartTileState();
}

class _StartTileState extends State<_StartTile> {
  bool _hover = false;

  static IconData _icon(String id) => switch (id) {
    'workbench.action.files.openFolder' => Codicons.folderOpened,
    'workbench.action.files.openFile' => Codicons.goToFile,
    'workbench.action.files.newUntitledFile' => Codicons.newFile,
    'workbench.action.openRecent' => Codicons.history,
    'workbench.action.newWindow' => Codicons.emptyWindow,
    'baocode.window.showChat' => Codicons.commentDiscussion,
    _ => Codicons.play,
  };

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    final command = widget.command;
    final shortcut = command.shortcutLabel();
    // A menu's ellipsis is no tile's.
    final label = localizedCommandLabel(
      context.l10n,
      command.id,
      command.label,
    ).replaceFirst(RegExp(r'(\.\.\.|…)$'), '');
    final background =
        colors.get('welcomePage.tileBackground') ??
        colors['editorWidget.background'];
    return Semantics(
      button: true,
      label: label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: command.enabled ? command.run : null,
          child: Container(
            constraints: const BoxConstraints(minHeight: 76),
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            decoration: BoxDecoration(
              color: _hover
                  ? colors.get('welcomePage.tileHoverBackground') ??
                        Color.alphaBlend(
                          colors['foreground'].withValues(alpha: .05),
                          background,
                        )
                  : background,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color:
                    colors.get('welcomePage.tileBorder') ??
                    colors['widget.border'],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _icon(command.id),
                      size: 18,
                      color: colors['foreground'],
                    ),
                    const SizedBox(width: 8),
                    // At the tile's right edge.
                    if (shortcut != null)
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: IdeKeycap(shortcut),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: colors['foreground']),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// View all (N): a link.
class _Link extends StatefulWidget {
  const _Link({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_Link> createState() => _LinkState();
}

class _LinkState extends State<_Link> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Text(
          widget.label,
          style: TextStyle(
            fontSize: 12.5,
            color: _hover
                ? colors['textLink.activeForeground']
                : colors['textLink.foreground'],
          ),
        ),
      ),
    );
  }
}

/// A recent folder on the start page: its name, and where it is (`~` for
/// the home folder), the row lit under the pointer.
class _RecentRow extends StatefulWidget {
  const _RecentRow({
    required this.path,
    required this.home,
    required this.onOpen,
  });

  final String path;
  final String home;
  final VoidCallback onOpen;

  @override
  State<_RecentRow> createState() => _RecentRowState();
}

class _RecentRowState extends State<_RecentRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    final name = p.basename(widget.path);
    final parent = p.dirname(widget.path);
    final home = widget.home;
    final where = home.isEmpty
        ? parent
        : p.equals(parent, home)
        ? '~'
        : tildify(parent, home);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onOpen,
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: _hover
                ? colors['list.hoverBackground']
                : const Color(0x00000000),
            borderRadius: BorderRadius.circular(4),
          ),
          // The path at the row's right edge; either, if long, takes half.
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Codicons.folder,
                      size: 14,
                      color: colors['icon.foreground'],
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        name.isEmpty ? widget.path : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: colors['foreground'],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Text(
                    where,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: colors['descriptionForeground'],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WelcomeEntry extends StatefulWidget {
  const _WelcomeEntry({required this.command});

  final IdeCommand command;

  @override
  State<_WelcomeEntry> createState() => _WelcomeEntryState();
}

class _WelcomeEntryState extends State<_WelcomeEntry> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final shortcut = widget.command.shortcutLabel();
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.command.run,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 160,
                child: Text(
                  localizedCommandLabel(
                    context.l10n,
                    widget.command.id,
                    widget.command.label,
                  ),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 12.5,
                    // `.shortcuts dl`; the text's on hover.
                    color: _hover
                        ? themeColors['foreground']
                        : themeColors['descriptionForeground'],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 110,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: shortcut == null
                      ? const SizedBox.shrink()
                      : IdeKeycap(shortcut),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
