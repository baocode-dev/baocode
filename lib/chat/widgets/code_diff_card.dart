import 'package:flutter/material.dart';

import '../../theme/cursor_theme.dart';
import '../chat_models.dart';
import 'file_label.dart';

class CodeDiffCard extends StatelessWidget {
  const CodeDiffCard({
    super.key,
    required this.fileName,
    required this.directory,
    required this.lines,
  });

  final String fileName;
  final String directory;
  final List<DiffLine> lines;

  @override
  Widget build(BuildContext context) {
    final added = lines.where((l) => l.type == DiffLineType.added).length;
    final removed = lines.where((l) => l.type == DiffLineType.removed).length;

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
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: const BoxDecoration(
              color: CursorColors.surface,
              border: Border(bottom: BorderSide(color: CursorColors.border)),
            ),
            child: Row(
              children: [
                FileLabel(fileName),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    directory,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: CursorColors.textFaint,
                      fontSize: 12,
                    ),
                  ),
                ),
                Text(
                  '+$added',
                  style: const TextStyle(
                    color: CursorColors.added,
                    fontFamily: CursorFonts.mono,
                    fontSize: 11.5,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '-$removed',
                  style: const TextStyle(
                    color: CursorColors.removed,
                    fontFamily: CursorFonts.mono,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [for (final line in lines) _DiffLineRow(line)],
            ),
          ),
        ],
      ),
    );
  }
}

class _DiffLineRow extends StatelessWidget {
  const _DiffLineRow(this.line);

  final DiffLine line;

  @override
  Widget build(BuildContext context) {
    final (prefix, prefixColor, background) = switch (line.type) {
      DiffLineType.added => (
        '+',
        CursorColors.added,
        CursorColors.addedBackground,
      ),
      DiffLineType.removed => (
        '-',
        CursorColors.removed,
        CursorColors.removedBackground,
      ),
      DiffLineType.context => (' ', CursorColors.textFaint, Colors.transparent),
    };
    const mono = TextStyle(
      fontFamily: CursorFonts.mono,
      fontSize: 12,
      height: 1.6,
    );

    return ColoredBox(
      color: background,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            child: Text(
              '${line.lineNumber}',
              textAlign: TextAlign.right,
              style: mono.copyWith(color: CursorColors.textFaint),
            ),
          ),
          SizedBox(
            width: 22,
            child: Text(
              prefix,
              textAlign: TextAlign.center,
              style: mono.copyWith(color: prefixColor),
            ),
          ),
          Expanded(
            child: Text(
              line.text,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: mono.copyWith(
                color: line.type == DiffLineType.context
                    ? CursorColors.textMuted
                    : CursorColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }
}
