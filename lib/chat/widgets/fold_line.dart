import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../chat_models.dart';
import '../step_folds.dart';
import 'agent_step.dart';
import 'content_image.dart';
import 'step_header.dart';
import 'web_step_icons.dart';

export 'web_step_icons.dart'
    show
        FoldWebBrowserIcon,
        FoldWebIcon,
        FoldWebSearchIcon,
        FoldWebSiteIcon,
        StepWebIcons,
        foldWebIcons;

/// A run of quick steps, folded: "Read 3 files, ran 2 commands", the
/// counts standing out; then, fainter, how long it thought. Opens to the
/// steps.
class StepsFoldLine extends StatelessWidget {
  const StepsFoldLine({
    super.key,
    required this.tally,
    required this.expanded,
    required this.onToggle,
    this.images = const [],
    this.webIcons = const [],
  });

  final StepTally tally;
  final bool expanded;
  final VoidCallback onToggle;

  /// The steps' pictures (see [foldImages]), small after the line.
  final List<ChatImage> images;

  /// The steps' web icons (see [foldWebIcons]), stacked before [images].
  final List<FoldWebIcon> webIcons;

  /// What the steps did, each phrase with its count in it.
  static List<(String, int)> _actions(
    StepTally tally,
    AppLocalizations l10n, {
    bool capitalize = true,
  }) {
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
              StepAction.browse => l10n.stepsBrowsed(count),
              StepAction.use => l10n.stepsUsed(count),
            },
            count,
          ),
    ];
    // The line starts as a sentence does.
    if (capitalize) {
      if (actions.firstOrNull case (final first, final count)) {
        actions[0] = (first[0].toUpperCase() + first.substring(1), count);
      }
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
  static String text(
    StepTally tally, {
    AppLocalizations? l10n,
    bool capitalize = true,
  }) {
    final strings = l10n ?? englishLocalizations;
    final actions = _actions(
      tally,
      strings,
      capitalize: capitalize,
    ).map((a) => a.$1).join(strings.stepsSeparator);
    return [
      if (actions.isNotEmpty) actions,
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
        trailingGap: 0,
        trailing: _foldTrailing(
          context,
          webIcons: webIcons,
          images: images,
          expanded: expanded,
        ),
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
/// with the files it edited and (while closed) the tally of its steps.
/// Opens to the work.
class WorkFoldLine extends StatelessWidget {
  const WorkFoldLine({
    super.key,
    required this.worked,
    required this.edits,
    required this.expanded,
    required this.onToggle,
    this.tally,
    this.images = const [],
    this.webIcons = const [],
    this.stopped = false,
  });

  final Duration worked;

  /// The user stopped the turn: "Stopped after 4m 32s".
  final bool stopped;
  final TurnEdits edits;

  /// The turn's quick-step tally (reads, commands, browser actions, thinking),
  /// shown while closed so the user sees what happened without opening it.
  final StepTally? tally;
  final bool expanded;
  final VoidCallback onToggle;

  /// The turn's pictures (see [foldImages]), small after the line.
  final List<ChatImage> images;

  /// The turn's web and browser icons (see [foldWebIcons]), stacked before
  /// [images].
  final List<FoldWebIcon> webIcons;

  /// The line as text, e.g. for copying; in [l10n]'s language (English
  /// when null).
  static String text(
    Duration worked,
    TurnEdits edits, {
    StepTally? tally,
    AppLocalizations? l10n,
    bool stopped = false,
  }) {
    final strings = l10n ?? englishLocalizations;
    final steps = tally == null || tally.isEmpty
        ? ''
        : StepsFoldLine.text(tally, l10n: strings, capitalize: false);
    return [
      _worked(strings, worked, stopped: stopped),
      if (edits.files > 0)
        [
          strings.turnFiles(edits.files),
          if (edits.added > 0) '+${edits.added}',
          if (edits.removed > 0) '-${edits.removed}',
        ].join(' '),
      if (steps.isNotEmpty) steps,
    ].join(' · ');
  }

  static String _worked(
    AppLocalizations l10n,
    Duration worked, {
    required bool stopped,
  }) {
    final duration = AgentStep.formatDuration(worked, l10n: l10n);
    return stopped ? l10n.turnStopped(duration) : l10n.turnWorked(duration);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final faint = TextStyle(color: AppColors.textFaint);
    final stepCount = TextStyle(
      color: AppColors.text,
      fontWeight: FontWeight.w600,
    );
    final count = TextStyle(
      fontFamily: AppFonts.mono,
      fontFamilyFallback: AppFonts.monoFallbacks,
      fontSize: 11.5,
    );
    final shownTally = !expanded && tally != null && !tally!.isEmpty
        ? tally
        : null;
    final actions = shownTally == null
        ? const <(String, int)>[]
        : StepsFoldLine._actions(shownTally, l10n, capitalize: false);
    final thought = shownTally == null
        ? null
        : StepsFoldLine._thought(shownTally, l10n);
    final header = StepHeader(
      verb: text(worked, edits, tally: shownTally, l10n: l10n, stopped: stopped),
      expanded: expanded,
      onToggle: onToggle,
      trailingGap: 0,
      trailing: _foldTrailing(
        context,
        webIcons: webIcons,
        images: images,
        expanded: expanded,
      ),
      spans: [
        TextSpan(text: _worked(l10n, worked, stopped: stopped)),
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
        if (actions.isNotEmpty) ...[
          TextSpan(text: ' · ', style: faint),
          for (final (i, (phrase, n)) in actions.indexed) ...[
            if (i > 0) TextSpan(text: l10n.stepsSeparator),
            ...StepsFoldLine._withCount(phrase, n, stepCount),
          ],
        ],
        if (thought != null) TextSpan(text: ' · $thought', style: faint),
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

/// Everything a fold's header shows, collected in one pass over its items so
/// long conversations do not allocate sublists or scan the fold repeatedly.
class FoldSummary {
  const FoldSummary({
    required this.tally,
    required this.edits,
    required this.images,
    required this.webIcons,
  });

  static final empty = FoldSummary(
    tally: StepTally(),
    edits: (files: 0, added: 0, removed: 0),
    images: const [],
    webIcons: const [],
  );

  /// Summarizes items `[start, end)` from [itemAt] in a single pass.
  factory FoldSummary.of(
    int start,
    int end,
    ChatItem Function(int index) itemAt,
  ) {
    if (start >= end) return empty;
    final tally = StepTally();
    final files = <String>{};
    var added = 0;
    var removed = 0;
    final images = <ChatImage>[];
    final webCollector = FoldWebIconCollector();
    for (var i = start; i < end; i++) {
      final item = itemAt(i);
      tally.add(item);
      if (item is CodeDiffItem) {
        files.add('${item.directory}/${item.fileName}');
        added += item.added;
        removed += item.removed;
      } else if (item is ToolCallItem && !standsOutOfWork(item)) {
        if (item.images.isNotEmpty) {
          images.addAll(toolImages(item));
        }
        webCollector.add(item);
      }
    }
    return FoldSummary(
      tally: tally,
      edits: (files: files.length, added: added, removed: removed),
      images: images,
      webIcons: webCollector.icons,
    );
  }

  final StepTally tally;
  final TurnEdits edits;
  final List<ChatImage> images;
  final List<FoldWebIcon> webIcons;
}

/// A fold's stacked web icons (before its pictures) and small [images] after
/// its line while it is closed; none without either.
Widget? _foldTrailing(
  BuildContext context, {
  required List<FoldWebIcon> webIcons,
  required List<ChatImage> images,
  required bool expanded,
}) {
  final thumbs = _thumbnails(context, images, expanded: expanded);
  if (webIcons.isEmpty) return thumbs;
  final badges = StepWebIcons(icons: webIcons, shown: !expanded);
  if (thumbs == null) return badges;
  return Row(mainAxisSize: MainAxisSize.min, children: [badges, thumbs]);
}

/// A fold's [images] small after its line while it is closed, a click on
/// one showing them all whole; none without any.
Widget? _thumbnails(
  BuildContext context,
  List<ChatImage> images, {
  required bool expanded,
}) => images.isEmpty
    ? null
    : StepThumbnails(
        images: images,
        shown: !expanded,
        max: 4,
        onOpen: (index) => showChatImages(context, images, index),
      );

/// The pictures among [items] (a screenshot, an image file read), in
/// order: what their fold shows, small, so they are not hidden in it.
List<ChatImage> foldImages(Iterable<ChatItem> items) => [
  for (final item in items)
    // Pictures made show whole, out of the fold (see [standsOutOfWork]).
    if (item is ToolCallItem && !standsOutOfWork(item)) ...toolImages(item),
];

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
