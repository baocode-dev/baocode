import 'package:flutter/material.dart';

import '../../theme/cursor_theme.dart';
import '../chat_models.dart';
import 'file_label.dart';
import 'hover_builder.dart';

/// Compact one-line tool invocation, e.g. "Read  main.dart  L1-562".
class ToolCallRow extends StatelessWidget {
  const ToolCallRow({
    super.key,
    required this.kind,
    required this.target,
    this.detail,
  });

  final ToolKind kind;
  final String target;
  final String? detail;

  (IconData, String) get _visual => switch (kind) {
    ToolKind.read => (Icons.article_outlined, 'Read'),
    ToolKind.grep => (Icons.search_rounded, 'Grepped'),
    ToolKind.listDir => (Icons.folder_open_outlined, 'Listed'),
    ToolKind.search => (Icons.travel_explore_rounded, 'Searched'),
  };

  bool get _targetIsFile => kind == ToolKind.read;

  @override
  Widget build(BuildContext context) {
    final (icon, label) = _visual;
    return HoverBuilder(
      builder: (context, hovered) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: hovered ? CursorColors.hover : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: CursorColors.textMuted),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: CursorColors.textMuted,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: _targetIsFile
                  ? FileLabel(target)
                  : Text(
                      target,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: CursorColors.text,
                        fontFamily: CursorFonts.mono,
                        fontSize: 12,
                      ),
                    ),
            ),
            if (detail != null) ...[
              const SizedBox(width: 8),
              Text(
                detail!,
                style: const TextStyle(
                  color: CursorColors.textFaint,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
