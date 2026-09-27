import 'package:flutter/material.dart';

import '../../theme/cursor_theme.dart';

class TerminalCard extends StatelessWidget {
  const TerminalCard({
    super.key,
    required this.command,
    required this.output,
    this.succeeded = true,
  });

  final String command;
  final String output;
  final bool succeeded;

  @override
  Widget build(BuildContext context) {
    final statusColor = succeeded ? CursorColors.added : CursorColors.removed;
    return Container(
      decoration: BoxDecoration(
        color: CursorColors.code,
        borderRadius: BorderRadius.circular(8),
      ),
      // The border goes on top: under the children, the header's fill,
      // clipped to the outer corner, would cover it there.
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CursorColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: const BoxDecoration(
              color: CursorColors.surface,
              border: Border(bottom: BorderSide(color: CursorColors.border)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.terminal_rounded,
                  size: 14,
                  color: CursorColors.textMuted,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Terminal',
                  style: TextStyle(color: CursorColors.textMuted, fontSize: 12),
                ),
                const Spacer(),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  succeeded ? 'Success' : 'Failed',
                  style: const TextStyle(
                    color: CursorColors.textMuted,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    style: const TextStyle(
                      fontFamily: CursorFonts.mono,
                      fontSize: 12,
                      height: 1.5,
                    ),
                    children: [
                      const TextSpan(
                        text: '\$ ',
                        style: TextStyle(color: CursorColors.textFaint),
                      ),
                      TextSpan(
                        text: command,
                        style: const TextStyle(color: CursorColors.textPrimary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  output,
                  style: const TextStyle(
                    color: CursorColors.textMuted,
                    fontFamily: CursorFonts.mono,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
