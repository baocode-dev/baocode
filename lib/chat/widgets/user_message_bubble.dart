import 'package:flutter/material.dart';

import '../../theme/cursor_theme.dart';
import 'assistant_text.dart';
import 'file_label.dart';

class UserMessageBubble extends StatelessWidget {
  const UserMessageBubble({
    super.key,
    required this.text,
    this.attachments = const [],
  });

  final String text;
  final List<String> attachments;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
      decoration: BoxDecoration(
        color: CursorColors.surfaceRaised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CursorColors.borderStrong),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (attachments.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final name in attachments) _ContextPill(name)],
            ),
            const SizedBox(height: 8),
          ],
          Text.rich(
            inlineCodeSpan(
              text,
              const TextStyle(
                color: CursorColors.textPrimary,
                fontSize: 13.5,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContextPill extends StatelessWidget {
  const _ContextPill(this.fileName);

  final String fileName;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: CursorColors.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: CursorColors.border),
      ),
      child: FileLabel(fileName, fontSize: 11.5),
    );
  }
}
