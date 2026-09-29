import 'package:flutter/material.dart';

import '../theme/codicons.dart';
import '../theme/cursor_theme.dart';
import 'ide_commands.dart';
import 'ide_quick_input.dart';

/// The editor area with no open file: the key shortcuts, VS Code's
/// watermark, each also clickable.
class IdeWelcome extends StatelessWidget {
  const IdeWelcome({super.key, required this.commands});

  final List<IdeCommand> commands;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: CursorColors.background,
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Codicons.code, size: 56, color: Color(0x14FFFFFF)),
              const SizedBox(height: 20),
              for (final command in commands) _WelcomeEntry(command: command),
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
                  widget.command.label,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: _hover ? CursorColors.text : CursorColors.textMuted,
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
