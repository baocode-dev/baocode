import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../chat_models.dart';
import '../floating/hover_tooltip.dart';
import 'step_header.dart';

/// One tool call as a step, e.g. "Read main.dart L1-562"; opens to what it
/// found or returned, when there is anything.
class ToolCallRow extends StatelessWidget {
  const ToolCallRow({
    super.key,
    required this.kind,
    required this.target,
    this.detail,
    this.path,
    this.results = const [],
    this.label,
    this.status = ToolStatus.succeeded,
    this.output,
    this.expanded = false,
    this.onToggle,
  });

  final ToolKind kind;
  final String target;
  final String? detail;
  final String? path;
  final List<String> results;
  final String? label;
  final ToolStatus status;
  final String? output;
  final bool expanded;
  final VoidCallback? onToggle;

  bool get _running => status == ToolStatus.running;

  String? get _shown => switch (output?.trimRight()) {
    final text? when text.isNotEmpty => text,
    _ => null,
  };

  bool get _opens => results.isNotEmpty || _shown != null;

  @override
  Widget build(BuildContext context) {
    Widget header = StepHeader(
      verb: label ?? toolVerb(kind, status: status, l10n: context.l10n),
      object: target,
      detail: detail,
      running: _running,
      expanded: expanded,
      onToggle: _opens ? onToggle : null,
      // A message to another agent: someone speaking.
      icon: kind == ToolKind.message
          ? Icon(
              Icons.record_voice_over_outlined,
              size: 15,
              color: AppColors.syntaxCommand,
            )
          : null,
    );
    // A file read shows only its name: the whole path on hover.
    if (kind == ToolKind.read && path != null) {
      header = HoverTooltip(content: _pathTooltip, child: header);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        if (expanded && _opens)
          StepBody(
            child: Text(
              results.isNotEmpty ? results.join('\n') : _shown!,
              style: stepMono,
            ),
          ),
      ],
    );
  }

  Widget _pathTooltip(BuildContext context) {
    final lines = switch (detail) {
      final detail? when detail.startsWith('L') => context.l10n.toolLines(
        detail.substring(1).replaceAll('-', '–'),
      ),
      final detail => detail?.replaceAll('-', '–'),
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          path!,
          style: const TextStyle(fontFamily: AppFonts.mono, fontSize: 12),
        ),
        if (lines != null)
          Text(
            lines,
            style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
          ),
      ],
    );
  }
}

/// What a kind of tool call did, or does while running, as its [status]
/// says; in [l10n]'s language (English when null).
String toolVerb(
  ToolKind kind, {
  ToolStatus status = ToolStatus.succeeded,
  AppLocalizations? l10n,
}) {
  final s = l10n ?? englishLocalizations;
  final running = status == ToolStatus.running;
  return switch (kind) {
    ToolKind.read => running ? s.toolReading : s.toolRead,
    ToolKind.grep => running ? s.toolGrepping : s.toolGrepped,
    ToolKind.listDir => running ? s.toolListing : s.toolListed,
    ToolKind.search => running ? s.toolSearching : s.toolSearched,
    ToolKind.edit => running ? s.toolEditing : s.toolEdited,
    ToolKind.command => running ? s.toolRunning : s.toolRan,
    ToolKind.web => running ? s.toolFetching : s.toolFetched,
    ToolKind.agent => s.toolAgent,
    ToolKind.mcp => 'MCP',
    ToolKind.todo => running ? s.toolUpdatingTodos : s.toolUpdatedTodos,
    ToolKind.message => running ? s.toolSending : s.toolSent,
    // Refused: answered for the user, not asked.
    ToolKind.question =>
      running
          ? s.toolAsking
          : status == ToolStatus.denied
          ? s.toolQuestionSkipped
          : s.toolAsked,
    ToolKind.other => running ? s.toolUsing : s.toolUsed,
  };
}
