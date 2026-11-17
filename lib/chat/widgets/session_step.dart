import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../chat_models.dart';
import '../session_links.dart';
import 'step_header.dart';

/// A call of one of the `session_*` tools as a step: what was done, to
/// which conversations, by their names ("Handed work to Worker"), one of
/// them opened with a click. It opens to what was sent and what came of
/// it.
class SessionStep extends StatelessWidget {
  const SessionStep({
    super.key,
    required this.item,
    this.expanded = false,
    this.onToggle,
  });

  final ToolCallItem item;
  final bool expanded;
  final VoidCallback? onToggle;

  /// The conversations [item] is about, by their ids.
  static List<String> idsOf(ToolCallItem item) => [
    if (item.tool == 'session_new') ?_started.firstMatch(item.output ?? '')?[1],
    if (item.input['session'] case final String id when id.isNotEmpty) id,
    if (item.input['sessions'] case final List<Object?> ids)
      ...ids.whereType<String>(),
  ];

  static final _started = RegExp(r'^Started: (\S+)');

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final links = SessionLinks.of(context);
    final action = (item.tool ?? '').replaceFirst('session_', '');
    final running = item.status == ToolStatus.running;
    final ids = idsOf(item);
    final names = [for (final id in ids) links?.titleOf(id)];
    final object = switch (item.tool) {
      'session_new' =>
        names.firstOrNull ??
            switch (item.input['title']) {
              final String title when title.trim().isNotEmpty => title.trim(),
              _ => '',
            },
      _ when names.isNotEmpty && names.every((name) => name != null) =>
        names.join(
          Localizations.localeOf(context).languageCode == 'zh' ? '、' : ', ',
        ),
      _ => item.target,
    };
    final opens = ids.length == 1 && names.single != null && links != null;
    final sent = switch (item.input['text']) {
      final String text when text.trim().isNotEmpty => text.trim(),
      _ => null,
    };
    // What came of it, for the agent: shown where it says more than that
    // it was done (a read, a wait, a failure), not for work handed on.
    final output = switch (item.tool) {
      'session_new' ||
      'session_send' when item.status == ToolStatus.succeeded => '',
      _ => item.output?.trim() ?? '',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StepHeader(
          verb: running
              ? l10n.sessionStepRunning(action)
              : l10n.sessionStepDone(action),
          object: object,
          running: running,
          expanded: expanded,
          onToggle: sent == null && output.isEmpty ? null : onToggle,
          onOpen: opens ? () => links.open(ids.single) : null,
          openTooltip: opens ? l10n.sessionOpen : null,
          icon: Icon(
            Codicons.commentDiscussion,
            size: 14,
            color: AppColors.textMuted,
          ),
        ),
        if (expanded && (sent != null || output.isNotEmpty))
          StepBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (sent != null)
                  Text(
                    sent,
                    style: TextStyle(color: AppColors.text, fontSize: 12.5),
                  ),
                if (sent != null && output.isNotEmpty)
                  const SizedBox(height: 8),
                if (output.isNotEmpty) Text(output, style: stepMono),
              ],
            ),
          ),
      ],
    );
  }
}
