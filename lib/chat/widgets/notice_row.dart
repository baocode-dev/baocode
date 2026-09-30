import 'package:flutter/material.dart';

import '../../theme/cursor_theme.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../chat_models.dart';
import 'markdown_view.dart';

/// A line from the runtime rather than the agent: a compaction divider, a
/// retry or error, a hint, or the output of a command run in the session.
class NoticeRow extends StatelessWidget {
  const NoticeRow({super.key, required this.item});

  final NoticeItem item;

  @override
  Widget build(BuildContext context) {
    final text = item.text;
    switch (item.kind) {
      case NoticeKind.compaction:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(child: Divider(color: CursorColors.border)),
              const SizedBox(width: 10),
              Icon(
                Icons.compress_rounded,
                size: 13,
                color: CursorColors.textFaint,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  text,
                  style: TextStyle(color: CursorColors.textFaint, fontSize: 12),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: Divider(color: CursorColors.border)),
            ],
          ),
        );
      case NoticeKind.command:
        return Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            color: CursorColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: CursorColors.border),
          ),
          child: MarkdownView(
            text,
            style: MarkdownView.baseStyle.copyWith(fontSize: 13),
          ),
        );
      case NoticeKind.retry ||
          NoticeKind.error ||
          NoticeKind.info ||
          NoticeKind.warning:
        final error = themeColors['errorForeground'];
        final (icon, color) = switch (item.kind) {
          NoticeKind.error => (Icons.error_outline_rounded, error),
          NoticeKind.warning || NoticeKind.retry => (
            Icons.warning_amber_rounded,
            themeColors['notificationsWarningIcon.foreground'],
          ),
          _ => (Icons.info_outline_rounded, CursorColors.textMuted),
        };
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(icon, size: 14, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    color: item.kind == NoticeKind.error
                        ? error
                        : CursorColors.textMuted,
                    fontSize: 12.5,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        );
    }
  }
}
