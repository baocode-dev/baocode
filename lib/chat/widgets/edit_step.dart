import 'package:flutter/material.dart';

import '../../theme/cursor_theme.dart';
import '../chat_models.dart';
import 'step_header.dart';

/// A file edit as a step: "Edited main.dart +12 -3", opening to its diff.
class EditStep extends StatelessWidget {
  const EditStep({
    super.key,
    required this.item,
    this.expanded = false,
    this.onToggle,
  });

  final CodeDiffItem item;
  final bool expanded;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    const count = TextStyle(fontFamily: CursorFonts.mono, fontSize: 11.5);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StepHeader(
          verb: 'Edited',
          object: item.fileName,
          expanded: expanded,
          onToggle: onToggle,
          trailing: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '+${item.added}',
                  style: const TextStyle(color: CursorColors.added),
                ),
                TextSpan(
                  text: ' -${item.removed}',
                  style: const TextStyle(color: CursorColors.removed),
                ),
              ],
            ),
            style: count,
          ),
        ),
        if (expanded)
          StepBody(
            maxHeight: 320,
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [for (final line in item.lines) _DiffLineRow(line)],
            ),
          ),
      ],
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
