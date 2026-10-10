import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../chat_models.dart';
import '../step_folds.dart';
import 'agent_step.dart';
import 'step_header.dart';

/// A run of quick steps, folded: "Read 3 files, ran 2 commands", the
/// counts standing out; then, fainter, how long it thought. Opens to the
/// steps.
class StepsFoldLine extends StatelessWidget {
  const StepsFoldLine({
    super.key,
    required this.tally,
    required this.expanded,
    required this.onToggle,
  });

  final StepTally tally;
  final bool expanded;
  final VoidCallback onToggle;

  /// What the steps did, each phrase with its count in it.
  static List<(String, int)> _actions(StepTally tally, AppLocalizations l10n) {
    final actions = [
      for (final action in StepAction.values)
        if (tally.counts[action] case final count?)
          (
            switch (action) {
              StepAction.read => l10n.stepsRead(count),
              StepAction.search => l10n.stepsSearched(count),
              StepAction.list => l10n.stepsListed(count),
              StepAction.fetch => l10n.stepsFetched(count),
              StepAction.run => l10n.stepsRan(count),
              StepAction.use => l10n.stepsUsed(count),
            },
            count,
          ),
    ];
    // The line starts as a sentence does.
    if (actions.firstOrNull case (final first, final count)) {
      actions[0] = (first[0].toUpperCase() + first.substring(1), count);
    }
    return actions;
  }

  static String? _thought(StepTally tally, AppLocalizations l10n) =>
      tally.thought > 0
      ? l10n.stepsThought(
          AgentStep.formatDuration(
            Duration(seconds: tally.thought),
            l10n: l10n,
          ),
        )
      : null;

  /// The line as text, e.g. for copying; in [l10n]'s language (English
  /// when null).
  static String text(StepTally tally, {AppLocalizations? l10n}) {
    final strings = l10n ?? englishLocalizations;
    return [
      _actions(tally, strings).map((a) => a.$1).join(strings.stepsSeparator),
      ?_thought(tally, strings),
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final count = TextStyle(color: AppColors.text, fontWeight: FontWeight.w600);
    final faint = TextStyle(color: AppColors.textFaint);
    final actions = _actions(tally, l10n);
    return _FoldSemantics(
      expanded: expanded,
      onToggle: onToggle,
      child: StepHeader(
        verb: text(tally, l10n: l10n),
        expanded: expanded,
        onToggle: onToggle,
        spans: [
          for (final (i, (phrase, n)) in actions.indexed) ...[
            if (i > 0) TextSpan(text: l10n.stepsSeparator),
            ..._withCount(phrase, n, count),
          ],
          if (_thought(tally, l10n) case final thought?)
            TextSpan(text: ' · $thought', style: faint),
        ],
      ),
    );
  }

  /// [phrase] with its [count] in [style].
  static List<InlineSpan> _withCount(
    String phrase,
    int count,
    TextStyle style,
  ) {
    final digits = '$count';
    final at = phrase.indexOf(digits);
    if (at < 0) return [TextSpan(text: phrase)];
    return [
      TextSpan(text: phrase.substring(0, at)),
      TextSpan(text: digits, style: style),
      TextSpan(text: phrase.substring(at + digits.length)),
    ];
  }
}

/// A finished turn's work, folded before its answer: "Worked for 4m 32s",
/// with the files it edited. Opens to the work.
class WorkFoldLine extends StatelessWidget {
  const WorkFoldLine({
    super.key,
    required this.worked,
    required this.edits,
    required this.expanded,
    required this.onToggle,
  });

  final Duration worked;
  final TurnEdits edits;
  final bool expanded;
  final VoidCallback onToggle;

  /// The line as text, e.g. for copying; in [l10n]'s language (English
  /// when null).
  static String text(
    Duration worked,
    TurnEdits edits, {
    AppLocalizations? l10n,
  }) {
    final strings = l10n ?? englishLocalizations;
    return [
      strings.turnWorked(AgentStep.formatDuration(worked, l10n: strings)),
      if (edits.files > 0)
        [
          strings.turnFiles(edits.files),
          if (edits.added > 0) '+${edits.added}',
          if (edits.removed > 0) '-${edits.removed}',
        ].join(' '),
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final faint = TextStyle(color: AppColors.textFaint);
    final count = TextStyle(
      fontFamily: AppFonts.mono,
      fontFamilyFallback: AppFonts.monoFallbacks,
      fontSize: 11.5,
    );
    final header = StepHeader(
      verb: text(worked, edits, l10n: l10n),
      expanded: expanded,
      onToggle: onToggle,
      spans: [
        TextSpan(
          text: l10n.turnWorked(AgentStep.formatDuration(worked, l10n: l10n)),
        ),
        if (edits.files > 0) ...[
          TextSpan(text: ' · ${l10n.turnFiles(edits.files)}', style: faint),
          if (edits.added > 0)
            TextSpan(
              text: ' +${edits.added}',
              style: count.copyWith(
                color: themeColors['chat.linesAddedForeground'],
              ),
            ),
          if (edits.removed > 0)
            TextSpan(
              text: ' -${edits.removed}',
              style: count.copyWith(
                color: themeColors['chat.linesRemovedForeground'],
              ),
            ),
        ],
      ],
    );
    return _FoldSemantics(
      expanded: expanded,
      onToggle: onToggle,
      // As wide as it reads.
      child: Align(alignment: Alignment.centerLeft, child: header),
    );
  }
}

/// The files a turn edited, and the lines added and removed in them.
typedef TurnEdits = ({int files, int added, int removed});

/// The edits among [items].
TurnEdits turnEdits(Iterable<ChatItem> items) {
  final files = <String>{};
  var added = 0;
  var removed = 0;
  for (final item in items) {
    if (item is! CodeDiffItem) continue;
    files.add('${item.directory}/${item.fileName}');
    added += item.added;
    removed += item.removed;
  }
  return (files: files.length, added: added, removed: removed);
}

/// A fold's line, to assistive technology: a button that opens it.
class _FoldSemantics extends StatelessWidget {
  const _FoldSemantics({
    required this.expanded,
    required this.onToggle,
    required this.child,
  });

  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    expanded: expanded,
    onTap: onToggle,
    child: child,
  );
}
