import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/material_file_icons.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../chat_models.dart';
import '../side_panel/file_link.dart';
import '../side_panel/file_open.dart';
import 'code_citation.dart';
import 'hover_builder.dart';
import 'step_header.dart';

/// A file edit as a step: "Edited main.dart +12 -3", a click opening it
/// to its diff, under the file's icon and name; where the chat's files
/// open (see [FileOpenScope]), a click on those shows its changes there.
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
    const count = TextStyle(fontFamily: AppFonts.mono, fontSize: 11.5);
    final files = FileOpenScope.maybeOf(context);
    final path = files?.resolve(item.path);
    final first = item.firstChangedLine;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StepHeader(
          verb: context.l10n.toolEdited,
          object: item.fileName,
          expanded: expanded,
          onToggle: onToggle,
          trailing: Text.rich(
            TextSpan(
              // A count of none is left out.
              children: [
                if (item.added > 0)
                  TextSpan(
                    text: '+${item.added}',
                    style: TextStyle(
                      color: themeColors['chat.linesAddedForeground'],
                    ),
                  ),
                if (item.added > 0 && item.removed > 0)
                  const TextSpan(text: ' '),
                if (item.removed > 0)
                  TextSpan(
                    text: '-${item.removed}',
                    style: TextStyle(
                      color: themeColors['chat.linesRemovedForeground'],
                    ),
                  ),
              ],
            ),
            style: count,
          ),
        ),
        if (expanded)
          StepBody(
            maxHeight: CodeCitationCard.maxCodeHeight,
            padding: const EdgeInsets.symmetric(vertical: 6),
            header: _FileHeader(
              item: item,
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
            child: _Diff(item),
          ),
      ],
    );
  }
}

/// The edited file's icon and name over its diff: a click shows its
/// changes where the chat's files open, when they do.
class _FileHeader extends StatelessWidget {
  const _FileHeader({required this.item, this.onOpen});

  final CodeDiffItem item;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final onOpen = this.onOpen;
    Widget row(bool hovered) {
      final hover = AppColors.hover;
      return Container(
        // Faintly lit while hovered, as a code card's title.
        color: hovered ? hover.withValues(alpha: hover.a * 0.6) : null,
        padding: const EdgeInsets.fromLTRB(12, 5, 12, 5),
        child: Row(
          children: [
            FileIcon(item.fileName, size: 15),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                item.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.text, fontSize: 12.5),
              ),
            ),
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

/// The diff's lines, in the editor's colors once [CodeCitationScope]
/// colors them: the old side (context and removed) and the new (context
/// and added) each as code of its own, so what spans lines stays right.
class _Diff extends StatefulWidget {
  const _Diff(this.item);

  final CodeDiffItem item;

  @override
  State<_Diff> createState() => _DiffState();
}

class _DiffState extends State<_Diff> {
  CodeColorizer? _colorize;
  List<DiffLine>? _colored;

  /// By line, null for those not colored.
  List<List<TextSpan>?> _colors = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _colorSoon();
  }

  @override
  void didUpdateWidget(_Diff oldWidget) {
    super.didUpdateWidget(oldWidget);
    _colorSoon();
  }

  void _colorSoon() {
    final colorize = CodeCitationScope.maybeOf(context)?.colorize;
    final lines = widget.item.lines;
    if (colorize == _colorize && identical(lines, _colored)) return;
    _colorize = colorize;
    _colored = lines;
    // Built next anyway: the old colors are of other lines.
    _colors = const [];
    if (colorize == null) return;
    final path = widget.item.fileName;
    final old = [
      for (final (i, line) in lines.indexed)
        if (line.type != DiffLineType.added) i,
    ];
    final now = [
      for (final (i, line) in lines.indexed)
        if (line.type != DiffLineType.removed) i,
    ];
    String code(List<int> side) =>
        [for (final i in side) lines[i].text].join('\n');
    Future.wait([colorize(path, code(old)), colorize(path, code(now))]).then((
      sides,
    ) {
      if (!mounted || colorize != _colorize || !identical(lines, _colored)) {
        return;
      }
      final colors = List<List<TextSpan>?>.filled(lines.length, null);
      for (final (side, indices) in [(sides[0], old), (sides[1], now)]) {
        if (side == null) continue;
        for (final (j, i) in indices.indexed) {
          if (j < side.length) colors[i] = side[j];
        }
      }
      setState(() => _colors = colors);
    }, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (i, line) in widget.item.lines.indexed)
        _DiffLineRow(line, i < _colors.length ? _colors[i] : null),
    ],
  );
}

class _DiffLineRow extends StatelessWidget {
  const _DiffLineRow(this.line, this.colors);

  final DiffLine line;

  /// [line]'s text in the editor's colors.
  final List<TextSpan>? colors;

  @override
  Widget build(BuildContext context) {
    final (prefix, prefixColor, background) = switch (line.type) {
      DiffLineType.added => ('+', AppColors.added, AppColors.addedBackground),
      DiffLineType.removed => (
        '-',
        AppColors.removed,
        AppColors.removedBackground,
      ),
      DiffLineType.context => (' ', AppColors.textFaint, Colors.transparent),
    };
    const mono = TextStyle(
      fontFamily: AppFonts.mono,
      fontSize: 12,
      height: 1.5,
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
              style: mono.copyWith(color: AppColors.textFaint),
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
            child: Text.rich(
              TextSpan(
                children: colors,
                text: colors == null ? line.text : null,
              ),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: mono.copyWith(
                color: colors != null
                    ? themeColors['editor.foreground']
                    : line.type == DiffLineType.context
                    ? AppColors.textMuted
                    : AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }
}
