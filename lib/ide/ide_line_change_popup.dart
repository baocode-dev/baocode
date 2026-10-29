// A change of the file since its last commit, shown under its lines once
// its mark by the line numbers is pressed: JetBrains IDEs' change popup
// (VS Code's dirty diff peek). The way to the previous and the next
// change, Rollback, Show Diff and Copy, and what the lines were.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:bao_editor/monaco/flutter/document_snapshot.dart';
import 'package:bao_editor/monaco/flutter/editor_surface.dart';
import 'package:bao_editor/monaco/vs/editor/common/diff/range_mapping.dart';

import '../l10n/l10n.dart';
import '../theme/codicons.dart';
import '../theme/workbench_theme.dart' hide ColorScheme;
import 'git/git_line_changes.dart';
import 'ide_hover.dart';

/// [change], the [index]th of [count], under its lines in the editor
/// [view] shows ([text] its text, [original] HEAD's), kept there as the
/// text scrolls ([repaint]).
class IdeLineChangePopup extends StatelessWidget {
  const IdeLineChangePopup({
    super.key,
    required this.change,
    required this.index,
    required this.count,
    required this.text,
    required this.original,
    required this.view,
    required this.repaint,
    required this.style,
    required this.onPrevious,
    required this.onNext,
    required this.onRollback,
    required this.onShowDiff,
    required this.onCopy,
  });

  final LineRangeMapping change;
  final int index;
  final int count;
  final DocumentSnapshot text;
  final DocumentSnapshot original;
  final EditorSurfaceView? Function() view;
  final Listenable repaint;

  /// The code's, for the lines it was.
  final TextStyle style;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onRollback;
  final VoidCallback onShowDiff;
  final VoidCallback onCopy;

  /// The most lines of the original shown before it scrolls.
  static const maxLines = 12;

  /// [change]'s lines in [original], their line breaks between them.
  static String originalOf(LineRangeMapping change, DocumentSnapshot original) {
    final range = change.original;
    if (range.isEmpty) return '';
    final start = original.lineStarts[range.startLineNumber - 1];
    final end = original.contentEnds[range.endLineNumberExclusive - 2];
    return original.text.substring(start, end);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => ListenableBuilder(
      listenable: repaint,
      builder: (context, _) {
        final view = this.view();
        final area = view?.textArea;
        if (view == null || area == null) return const SizedBox.shrink();
        final last = ideLineChangeLines(change).last.clamp(1, text.lineCount);
        final bottom = view.caretRectAt(text.lineStarts[last - 1])?.bottom;
        if (bottom == null) return const SizedBox.shrink();
        final left = math.max(0.0, area.left - 4);
        final width = math.min(720.0, constraints.maxWidth - left - 16);
        if (width < 160) return const SizedBox.shrink();
        return Stack(
          children: [
            Positioned(
              left: left,
              top: bottom + 1,
              width: width,
              child: _body(context, view.lineHeight),
            ),
          ],
        );
      },
    ),
  );

  Widget _body(BuildContext context, double lineHeight) {
    final l10n = context.l10n;
    final colors = themeColors;
    final was = originalOf(change, original);
    return Material(
      color: colors['editorWidget.background'],
      elevation: 6,
      shadowColor: colors['widget.shadow'],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(
          color: colors.get('editorWidget.border') ?? colors['widget.border'],
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 28,
            child: Row(
              children: [
                const SizedBox(width: 4),
                IdeActionButton(
                  icon: Codicons.arrowUp,
                  tooltip: l10n.lineChangePrevious,
                  onPressed: count > 1 ? onPrevious : null,
                ),
                IdeActionButton(
                  icon: Codicons.arrowDown,
                  tooltip: l10n.lineChangeNext,
                  onPressed: count > 1 ? onNext : null,
                ),
                IdeActionButton(
                  icon: Codicons.discard,
                  tooltip: l10n.lineChangeRollback,
                  onPressed: onRollback,
                ),
                IdeActionButton(
                  icon: Codicons.diff,
                  tooltip: l10n.lineChangeShowDiff,
                  onPressed: onShowDiff,
                ),
                if (was.isNotEmpty)
                  IdeActionButton(
                    icon: Codicons.copy,
                    tooltip: l10n.lineChangeCopy,
                    onPressed: onCopy,
                  ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    l10n.diffDifferenceOf(index + 1, count),
                    style: TextStyle(
                      fontSize: 12,
                      color: colors['descriptionForeground'],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (was.isNotEmpty)
            Container(
              constraints: BoxConstraints(maxHeight: lineHeight * maxLines),
              color:
                  colors.get('diffEditor.removedLineBackground') ??
                  colors['diffEditor.removedTextBackground'],
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(8, 2, 8, 2),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Text(was, softWrap: false, style: style),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
