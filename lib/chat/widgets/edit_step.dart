import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../ide/ide_code_diff.dart';
import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/material_file_icons.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../chat_models.dart';
import '../edit_detail.dart';
import '../side_panel/file_link.dart';
import '../side_panel/file_open.dart';
import 'code_citation.dart';
import 'hover_builder.dart';
import 'own_selection.dart';
import 'step_header.dart';

/// A file edit, as [EditDetail] has it: a card of the file's icon, name
/// and counts over its diff; or a step, "Edited main.dart +12 -3", a click
/// opening it to that card. Where the chat's files open (see
/// [FileOpenScope]), a click on the file's name shows its changes there.
class EditStep extends StatelessWidget {
  const EditStep({
    super.key,
    required this.item,
    this.expanded = false,
    this.onToggle,
  });

  final CodeDiffItem item;

  /// Whether the step is open, as [EditDetail.compact] shows it; a card
  /// is always.
  final bool expanded;
  final VoidCallback? onToggle;

  /// How tall the card's diff grows before it scrolls.
  static const maxCardHeight = 160.0;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: EditDetail.current,
    builder: (context, detail, _) => switch (detail) {
      EditDetail.card => _card(
        context,
        counts: true,
        maxHeight: maxCardHeight,
        // The lines start right under the name.
        padding: EdgeInsets.zero,
      ),
      EditDetail.compact => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StepHeader(
            verb: context.l10n.toolEdited,
            object: item.fileName,
            expanded: expanded,
            onToggle: onToggle,
            trailing: _Counts(item),
          ),
          if (expanded)
            _card(
              context,
              counts: false,
              maxHeight: CodeCitationCard.maxCodeHeight,
              padding: EdgeInsets.zero,
            ),
        ],
      ),
    },
  );

  /// The file's name over its diff; its [counts] at the right when the
  /// card stands alone.
  Widget _card(
    BuildContext context, {
    required bool counts,
    required double maxHeight,
    required EdgeInsetsGeometry padding,
  }) {
    final files = FileOpenScope.maybeOf(context);
    final path = files?.resolve(item.path);
    final first = item.firstChangedLine;
    return _Card(
      item: item,
      maxHeight: maxHeight,
      padding: padding,
      header: _FileHeader(
        item: item,
        counts: counts,
        onOpen: path == null
            ? null
            : () => files!.onOpen(
                FileOpenRequest(
                  path,
                  diff: true,
                  range: first == null ? null : FileLineRange(first),
                ),
              ),
      ),
    );
  }
}

/// The file's [header] over its diff, scrolling past [maxHeight], with
/// scrollbars across each side's text along its bottom: the diff is as
/// tall as its lines, its editors' own out of view at its foot.
class _Card extends StatefulWidget {
  const _Card({
    required this.item,
    required this.maxHeight,
    required this.padding,
    required this.header,
  });

  final CodeDiffItem item;
  final double maxHeight;
  final EdgeInsetsGeometry padding;
  final Widget header;

  @override
  State<_Card> createState() => _CardState();
}

class _CardState extends State<_Card> {
  final _horizontal = ValueNotifier<List<IdeDiffHorizontal>>(const []);

  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  /// Its scrollbars as the change view's editors' are: square, against the
  /// edge, in their colors at rest, under the pointer and dragged; a little
  /// thinner ([_AcrossBar.thickness]).
  static ScrollbarThemeData _bars(BuildContext context) {
    final rest = themeColors['scrollbarSlider.background'];
    final hover = themeColors['scrollbarSlider.hoverBackground'];
    final active = themeColors['scrollbarSlider.activeBackground'];
    return ScrollbarTheme.of(context).copyWith(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.dragged)
            ? active
            : states.contains(WidgetState.hovered)
            ? hover
            : rest,
      ),
      thickness: const WidgetStatePropertyAll(_AcrossBar.thickness),
      radius: Radius.zero,
      crossAxisMargin: 0,
      mainAxisMargin: 0,
    );
  }

  @override
  Widget build(BuildContext context) =>
      ScrollbarTheme(data: _bars(context), child: _body());

  Widget _body() => StepBody(
    maxHeight: widget.maxHeight,
    padding: widget.padding,
    // Its lines fade under the name and at the bottom as they scroll.
    fadeEdges: true,
    scrollbar: true,
    // A line round it, no background.
    codeBlock: true,
    // Scrolled to its end, a wheel goes on to the conversation only from
    // outside it.
    keepWheel: true,
    header: widget.header,
    bottom: (context, hovered) => ValueListenableBuilder(
      valueListenable: _horizontal,
      builder: (context, editors, _) => SizedBox(
        height: _AcrossBar.thickness,
        child: Stack(
          children: [
            for (final editor in editors)
              if (editor.max > 0)
                Positioned(
                  left: editor.left,
                  width: editor.width,
                  top: 0,
                  bottom: 0,
                  child: _AcrossBar(editor: editor, visible: hovered),
                ),
          ],
        ),
      ),
    ),
    child: _Diff(widget.item, horizontal: _horizontal),
  );
}

/// A scrollbar across an [editor]'s text, as the card's own down it is
/// ([ScrollbarThemeData]): shown while [visible], or dragged.
class _AcrossBar extends StatefulWidget {
  const _AcrossBar({required this.editor, required this.visible});

  final IdeDiffHorizontal editor;
  final bool visible;

  /// Its and the card's own down it: a little thinner than the change
  /// view's editors' (14 down, 12 across).
  static const thickness = 10.0;

  @override
  State<_AcrossBar> createState() => _AcrossBarState();
}

class _AcrossBarState extends State<_AcrossBar> {
  bool _dragging = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final IdeDiffHorizontal(:width, :max, :scroll) = widget.editor;
    final theme = ScrollbarTheme.of(context);
    final length = math.min(
      width,
      math.max(theme.minThumbLength ?? 48, width * width / (width + max)),
    );
    final travel = width - length;
    return ValueListenableBuilder(
      valueListenable: scroll,
      builder: (context, offset, _) => Stack(
        children: [
          Positioned(
            left: travel * (offset.dx / max).clamp(0.0, 1.0),
            width: length,
            top: 0,
            bottom: 0,
            child: MouseRegion(
              onEnter: (_) => setState(() => _hovered = true),
              onExit: (_) => setState(() => _hovered = false),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: (_) => setState(() => _dragging = true),
                onHorizontalDragUpdate: (details) {
                  if (travel <= 0) return;
                  final at = scroll.value;
                  scroll.value = Offset(
                    (at.dx + details.delta.dx * max / travel).clamp(0.0, max),
                    at.dy,
                  );
                },
                onHorizontalDragEnd: (_) => setState(() => _dragging = false),
                onHorizontalDragCancel: () => setState(() => _dragging = false),
                child: Visibility.maintain(
                  visible: widget.visible || _dragging,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.thumbColor?.resolve({
                        if (_dragging) WidgetState.dragged,
                        if (_hovered) WidgetState.hovered,
                      }),
                      borderRadius: BorderRadius.all(
                        theme.radius ?? const Radius.circular(4),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "+12 -3", in the chat's colors for lines added and removed; a count of
/// none is left out.
class _Counts extends StatelessWidget {
  const _Counts(this.item);

  final CodeDiffItem item;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        if (item.added > 0)
          TextSpan(
            text: '+${item.added}',
            style: TextStyle(color: themeColors['chat.linesAddedForeground']),
          ),
        if (item.added > 0 && item.removed > 0) const TextSpan(text: ' '),
        if (item.removed > 0)
          TextSpan(
            text: '-${item.removed}',
            style: TextStyle(color: themeColors['chat.linesRemovedForeground']),
          ),
      ],
    ),
    style: TextStyle(
      fontFamily: AppFonts.mono,
      fontFamilyFallback: AppFonts.monoFallbacks,
      fontSize: 11.5,
    ),
  );
}

/// The edited file's icon and name over its diff, its counts at the right
/// when [counts]: a click shows its changes where the chat's files open,
/// when they do.
class _FileHeader extends StatelessWidget {
  const _FileHeader({required this.item, this.counts = false, this.onOpen});

  final CodeDiffItem item;
  final bool counts;
  final VoidCallback? onOpen;

  /// How tall it is: its name's line and room round it, as tall as a code
  /// block's title.
  static double heightOf(BuildContext context) =>
      (MediaQuery.textScalerOf(context).scale(12.5) * 1.3 + 16).roundToDouble();

  @override
  Widget build(BuildContext context) {
    final onOpen = this.onOpen;
    Widget row(bool hovered) {
      final hover = AppColors.hover;
      return Container(
        height: heightOf(context),
        // Faintly lit while hovered, as a code card's title.
        color: hovered ? hover.withValues(alpha: hover.a * 0.6) : null,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            FileIcon(item.fileName, size: 15),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                item.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.text, fontSize: 12.5),
              ),
            ),
            if (counts) ...[const SizedBox(width: 8), _Counts(item)],
          ],
        ),
      );
    }

    if (onOpen == null) return SelectionContainer.disabled(child: row(false));
    return SelectionContainer.disabled(
      child: Semantics(
        button: true,
        label: context.l10n.sidePanelOpenDiff,
        child: HoverBuilder(
          cursor: SystemMouseCursors.click,
          builder: (context, hovered) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onOpen,
            child: row(hovered),
          ),
        ),
      ),
    );
  }
}

/// The diff's two sides, as texts of their own: the old (its context and
/// removed lines) and the new (its context and added lines), each line
/// with the number it has in its file.
class DiffSides {
  DiffSides(List<DiffLine> lines) {
    final original = <String>[], modified = <String>[];
    // The next line's numbers on each side, to number the old side's
    // context (a line keeps its new number).
    int? oldNext, newNext;
    for (final line in lines) {
      switch (line.type) {
        case DiffLineType.context:
          // After a gap (the next hunk), the lines between moved both
          // sides alike.
          final old = newNext == null || oldNext == null
              ? line.lineNumber
              : line.lineNumber - newNext + oldNext;
          original.add(line.text);
          originalNumbers.add(old);
          modified.add(line.text);
          modifiedNumbers.add(line.lineNumber);
          oldNext = old + 1;
          newNext = line.lineNumber + 1;
        case DiffLineType.removed:
          original.add(line.text);
          originalNumbers.add(line.lineNumber);
          oldNext = line.lineNumber + 1;
        case DiffLineType.added:
          modified.add(line.text);
          modifiedNumbers.add(line.lineNumber);
          newNext = line.lineNumber + 1;
      }
    }
    this.original = original.join('\n');
    this.modified = modified.join('\n');
  }

  late final String original;
  late final String modified;
  final List<int> originalNumbers = [];
  final List<int> modifiedNumbers = [];

  /// A new file's: nothing on the old side.
  bool get created => originalNumbers.isEmpty;

  int originalNumberOf(int line) =>
      originalNumbers.elementAtOrNull(line - 1) ?? line;
  int modifiedNumberOf(int line) =>
      modifiedNumbers.elementAtOrNull(line - 1) ?? line;

  /// How many lines tall the diff is: the longer side's, side by side; a
  /// new file's alone.
  int get rows => created
      ? modifiedNumbers.length
      : (originalNumbers.length > modifiedNumbers.length
            ? originalNumbers.length
            : modifiedNumbers.length);
}

/// The diff as the IDE's diff editor shows it ([IdeCodeDiff]), side by
/// side (a new file alone), its lines numbered as in the file, as tall as
/// they are: the card scrolls it.
class _Diff extends StatefulWidget {
  const _Diff(this.item, {required this.horizontal});

  final CodeDiffItem item;

  /// Told how its editors scroll across ([IdeCodeDiff.horizontal]).
  final ValueNotifier<List<IdeDiffHorizontal>> horizontal;

  @override
  State<_Diff> createState() => _DiffState();
}

class _DiffState extends State<_Diff> {
  late DiffSides _sides = DiffSides(widget.item.lines);

  @override
  void didUpdateWidget(_Diff oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.item.lines, widget.item.lines)) {
      _sides = DiffSides(widget.item.lines);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sides = _sides;
    final rows = sides.rows < 1 ? 1 : sides.rows;
    return SizedBox(
      height: rows * IdeCodeDiff.lineHeight(context),
      // The editors' own selection, apart from the conversation's.
      child: OwnSelection(
        child: IdeCodeDiff(
          path: widget.item.fileName,
          original: sides.original,
          modified: sides.modified,
          syntax: CodeCitationScope.maybeOf(context)?.syntax?.call(),
          sideBySide: !sides.created,
          originalLineNumberOf: sides.originalNumberOf,
          modifiedLineNumberOf: sides.modifiedNumberOf,
          embedded: true,
          horizontal: widget.horizontal,
        ),
      ),
    );
  }
}
