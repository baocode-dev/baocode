import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../l10n/command_titles.dart';
import '../l10n/l10n.dart';
import '../theme/codicons.dart';
import '../theme/workbench_theme.dart' show themeColors;
import 'ide_commands.dart';
import 'ide_quick_input.dart';

/// The editor area with no open file: the key shortcuts, VS Code's
/// watermark (workbench/browser/parts/editor/media/editorgroupview.css),
/// each also clickable; without a folder, the ones to start with and the
/// [recent] folders, as its welcome page's Start and Recent.
class IdeWelcome extends StatelessWidget {
  const IdeWelcome({
    super.key,
    required this.commands,
    this.recent = const [],
    this.onOpenRecent,
  });

  final List<IdeCommand> commands;

  /// Folders opened last, most recent first; [onOpenRecent] opens one.
  final List<String> recent;
  final ValueChanged<String>? onOpenRecent;

  /// Recent folders listed, at most.
  static const recentShown = 5;

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    return ColoredBox(
      // An empty group's, else the editor's under it.
      color:
          colors.get('editorGroup.emptyBackground') ??
          colors['editor.background'],
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // In place of the letterpress image, which is no theme color:
              // the text's, faint.
              Icon(
                Codicons.code,
                size: 56,
                color: colors['foreground'].withValues(alpha: .08),
              ),
              const SizedBox(height: 20),
              for (final command in commands) _WelcomeEntry(command: command),
              if (onOpenRecent case final open? when recent.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(
                  context.l10n.ideWelcomeRecent,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: colors['descriptionForeground'],
                  ),
                ),
                const SizedBox(height: 6),
                for (final path in recent.take(recentShown))
                  _RecentEntry(path: path, onOpen: () => open(path)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A recent folder: its name, a link, and where it is.
class _RecentEntry extends StatefulWidget {
  const _RecentEntry({required this.path, required this.onOpen});

  final String path;
  final VoidCallback onOpen;

  @override
  State<_RecentEntry> createState() => _RecentEntryState();
}

class _RecentEntryState extends State<_RecentEntry> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    final name = p.basename(widget.path);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: SizedBox(
            width: 282,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: name.isEmpty ? widget.path : name,
                    style: TextStyle(
                      color: _hover
                          ? colors['textLink.activeForeground']
                          : colors['textLink.foreground'],
                    ),
                  ),
                  TextSpan(
                    text: '   ${p.dirname(widget.path)}',
                    style: TextStyle(color: colors['descriptionForeground']),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5),
            ),
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
