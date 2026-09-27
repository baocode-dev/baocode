import 'package:flutter/material.dart';

import '../../theme/cursor_theme.dart';
import '../chat_models.dart';
import 'file_label.dart';
import 'hover_builder.dart';
import '../floating/hover_tooltip.dart';

/// Compact one-line tool invocation, e.g. "Read  main.dart  L1-562".
class ToolCallRow extends StatelessWidget {
  const ToolCallRow({
    super.key,
    required this.kind,
    required this.target,
    this.detail,
    this.path,
    this.results = const [],
  });

  final ToolKind kind;
  final String target;
  final String? detail;
  final String? path;
  final List<String> results;

  (IconData, String) get _visual => switch (kind) {
    ToolKind.read => (Icons.article_outlined, 'Read'),
    ToolKind.grep => (Icons.search_rounded, 'Grepped'),
    ToolKind.listDir => (Icons.folder_open_outlined, 'Listed'),
    ToolKind.search => (Icons.travel_explore_rounded, 'Searched'),
  };

  bool get _targetIsFile => kind == ToolKind.read;

  /// Details on hover: what exactly was read, or what the search found.
  Widget? _tooltip(BuildContext context) {
    const mono = TextStyle(fontFamily: CursorFonts.mono, fontSize: 12);
    const muted = TextStyle(color: CursorColors.textMuted, fontSize: 11.5);
    switch (kind) {
      case ToolKind.read:
        final lines = detail?.replaceFirst('L', 'Lines ').replaceAll('-', '–');
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(path ?? target, style: mono),
            if (lines != null) Text(lines, style: muted),
          ],
        );
      case ToolKind.grep:
        final files = {for (final match in results) match.split(':').first};
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(target, style: mono),
            Text(
              '${results.length} results in ${files.length} '
              '${files.length == 1 ? 'file' : 'files'}',
              style: muted,
            ),
            if (results.isNotEmpty) const SizedBox(height: 6),
            for (final match in results)
              Text(match, style: mono.copyWith(color: CursorColors.textMuted)),
          ],
        );
      case ToolKind.listDir || ToolKind.search:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final row = _buildRow(context);
    final tooltip = _tooltip(context);
    return tooltip == null
        ? row
        : HoverTooltip(content: (_) => tooltip, child: row);
  }

  Widget _buildRow(BuildContext context) {
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
