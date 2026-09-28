import 'package:flutter/material.dart';

import '../../theme/cursor_theme.dart';
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
      verb: label ?? toolVerb(kind, running: _running),
      object: target,
      detail: detail,
      running: _running,
      expanded: expanded,
      onToggle: _opens ? onToggle : null,
      icon: kind == ToolKind.message
          ? const Icon(
              Icons.swap_horiz_rounded,
              size: 15,
              color: CursorColors.syntaxCommand,
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
    final lines = detail?.replaceFirst('L', 'Lines ').replaceAll('-', '–');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          path!,
          style: const TextStyle(fontFamily: CursorFonts.mono, fontSize: 12),
        ),
        if (lines != null)
          Text(
            lines,
            style: const TextStyle(
              color: CursorColors.textMuted,
              fontSize: 11.5,
            ),
          ),
      ],
    );
  }
}

/// What a kind of tool call did, or does while [running].
String toolVerb(ToolKind kind, {bool running = false}) => switch (kind) {
  ToolKind.read => running ? 'Reading' : 'Read',
  ToolKind.grep => running ? 'Grepping' : 'Grepped',
  ToolKind.listDir => running ? 'Listing' : 'Listed',
  ToolKind.search => running ? 'Searching' : 'Searched',
  ToolKind.edit => running ? 'Editing' : 'Edited',
  ToolKind.command => running ? 'Running' : 'Ran',
  ToolKind.web => running ? 'Fetching' : 'Fetched',
  ToolKind.agent => 'Agent',
  ToolKind.mcp => 'MCP',
  ToolKind.todo => running ? 'Updating todos' : 'Updated todos',
  ToolKind.message => running ? 'Sending' : 'Sent',
  ToolKind.other => running ? 'Using' : 'Used',
};
