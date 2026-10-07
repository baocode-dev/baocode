import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../chat_models.dart';
import '../floating/hover_tooltip.dart';
import '../side_panel/file_link.dart';
import '../side_panel/file_open.dart';
import 'hover_builder.dart';
import 'step_header.dart';

/// A message to another agent's icon (Remix Icon's speak-ai-line).
const speakIcon = 'assets/icons/speak-ai-line.svg';

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
    this.onSetGoal,
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

  /// Sets a proposed goal ([ToolKind.goal]; its condition the output).
  final ValueChanged<String>? onSetGoal;

  bool get _running => status == ToolStatus.running;

  String? get _shown => switch (output?.trimRight()) {
    final text? when text.isNotEmpty => text,
    _ => null,
  };

  bool get _opens => results.isNotEmpty || _shown != null;

  /// The file read or written, where the chat's files open (see
  /// [FileOpenScope]) and it is in the project.
  FileOpenRequest? _file(FileOpenScope? files) {
    final path = this.path;
    if (files == null || path == null) return null;
    if (kind != ToolKind.read && kind != ToolKind.edit) return null;
    final full = files.resolve(path);
    if (full == null) return null;
    return FileOpenRequest(
      full,
      range: kind == ToolKind.read ? FileLineRange.parseDetail(detail) : null,
      diff: kind == ToolKind.edit,
    );
  }

  @override
  Widget build(BuildContext context) {
    final files = FileOpenScope.maybeOf(context);
    final file = _file(files);
    Widget header = StepHeader(
      verb: label ?? toolVerb(kind, status: status, l10n: context.l10n),
      object: target,
      detail: detail,
      running: _running,
      expanded: expanded,
      onToggle: _opens ? onToggle : null,
      onOpen: file == null ? null : () => files!.onOpen(file),
      openTooltip: file == null ? null : context.l10n.sidePanelOpenFile,
      icon: switch (kind) {
        // A message to another agent: someone speaking, standing out.
        ToolKind.message => SvgPicture.asset(
          speakIcon,
          width: 15,
          height: 15,
          colorFilter: ColorFilter.mode(_amber, BlendMode.srcIn),
        ),
        ToolKind.goal => Icon(Icons.flag_outlined, size: 15, color: _amber),
        _ => null,
      },
      action: switch ((kind, _shown, onSetGoal)) {
        (ToolKind.goal, final condition?, final set?) when !_running =>
          _SetGoalButton(onTap: () => set(condition)),
        _ => null,
      },
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
            child: results.isNotEmpty && files != null
                ? _Results(results: results, files: files)
                : Text(
                    results.isNotEmpty ? results.join('\n') : _shown!,
                    style: stepMono,
                  ),
          ),
      ],
    );
  }

  /// The theme's for an event: warm, standing out without the warning's
  /// mustard.
  static Color get _amber => themeColors['symbolIcon.eventForeground'];

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

/// A search's matches (`path`, `path:line`), each opening its file where
/// it is in the project.
class _Results extends StatelessWidget {
  const _Results({required this.results, required this.files});

  final List<String> results;
  final FileOpenScope files;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final result in results) _result(result),
      ],
    );
  }

  Widget _result(String result) {
    final link = FileLink.parseText(result, blanks: true);
    final path = link == null ? null : files.resolve(link.path);
    final text = Text(result, style: stepMono);
    if (link == null || path == null) return text;
    return HoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (context, hovered) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => files.openLink(link),
        child: Text(
          result,
          style: stepMono.copyWith(
            color: hovered ? AppColors.text : null,
            decoration: hovered ? TextDecoration.underline : null,
          ),
        ),
      ),
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
    ToolKind.goal => running ? s.toolProposingGoal : s.toolProposedGoal,
    ToolKind.other => running ? s.toolUsing : s.toolUsed,
  };
}

/// Sets a proposed goal; once it has, says so.
class _SetGoalButton extends StatefulWidget {
  const _SetGoalButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_SetGoalButton> createState() => _SetGoalButtonState();
}

class _SetGoalButtonState extends State<_SetGoalButton> {
  bool _set = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (_set) {
      return Text(
        l10n.goalAdopted,
        style: TextStyle(color: AppColors.textFaint, fontSize: 12),
      );
    }
    return Semantics(
      button: true,
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          onTap: () {
            setState(() => _set = true);
            widget.onTap();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: hovered ? AppColors.hover : null,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: AppColors.borderStrong),
            ),
            child: Text(
              l10n.goalAdopt,
              style: TextStyle(color: AppColors.text, fontSize: 12),
            ),
          ),
        ),
      ),
    );
  }
}
