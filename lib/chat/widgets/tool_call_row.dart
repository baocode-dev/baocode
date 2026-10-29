import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../chat_models.dart';
import '../floating/hover_tooltip.dart';
import '../side_panel/file_link.dart';
import '../side_panel/file_link_menu.dart';
import '../side_panel/file_open.dart';
import 'content_image.dart';
import 'hover_builder.dart';
import 'step_header.dart';

/// A message to another agent's icon (Remix Icon's speak-ai-line).
const speakIcon = 'assets/icons/speak-ai-line.svg';

/// A todo's mark by its status (Remix Icon's): done, in progress, to do.
const todoDoneIcon = 'assets/icons/checkbox-circle-fill.svg';
const todoDoingIcon = 'assets/icons/progress-4-line.svg';
const todoOpenIcon = 'assets/icons/checkbox-blank-circle-line.svg';

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
    this.tool,
    this.input = const {},
    this.status = ToolStatus.succeeded,
    this.output,
    this.images = const [],
    this.imageFiles = const [],
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

  /// The tool's own name and what it was called with, for a kind each of
  /// whose tools says its own way (see [todoStep]).
  final String? tool;
  final Map<String, Object?> input;
  final ToolStatus status;
  final String? output;

  /// The pictures it returned (an image file read, a screenshot), shown
  /// under what it said as they are.
  final List<ImageAttachment> images;

  /// Where the CLI saved them (see [ToolCallItem.imageFiles]).
  final List<String> imageFiles;

  List<ChatImage> get _images => status == ToolStatus.failed
      ? const []
      : chatImagesOf(images, imageFilesOf(kind, path, imageFiles));
  final bool expanded;
  final VoidCallback? onToggle;

  /// Sets a proposed goal ([ToolKind.goal]; its condition the output).
  final ValueChanged<String>? onSetGoal;

  bool get _running => status == ToolStatus.running;

  String? get _shown => switch (output?.trimRight()) {
    final text? when text.isNotEmpty => text,
    _ => null,
  };

  bool get _opens => results.isNotEmpty || _shown != null || images.isNotEmpty;

  /// The list written or read, each item marked by its status (its
  /// output says it as text).
  List<TodoItem>? get _todos => status == ToolStatus.failed
      ? null
      : switch (todoItems(tool, input, output)) {
          final todos? when todos.isNotEmpty => todos,
          _ => null,
        };

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
    final todo = kind == ToolKind.todo
        ? todoStep(tool, input, target, output: output, l10n: context.l10n)
        : null;
    Widget header = StepHeader(
      verb:
          label ??
          todo?.verb ??
          toolVerb(kind, status: status, l10n: context.l10n),
      object: todo?.object ?? target,
      detail: todo?.detail ?? detail,
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
        ToolKind.todo => Icon(
          Icons.checklist_rounded,
          size: 15,
          color: AppColors.textMuted,
        ),
        _ => null,
      },
      trailingGap: 0,
      trailing: images.isEmpty || status == ToolStatus.failed
          ? null
          : StepThumbnails(images: _images, shown: !expanded),
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
    if (file != null) {
      header = FileLinkMenuRegion(
        menu: files!.menuFor(
          file.path,
          () => files.onOpen(file),
          context: context,
        ),
        child: header,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        if (_todos case final todos? when expanded)
          StepBody(child: _TodoList(todos: todos))
        else if (expanded && (results.isNotEmpty || _shown != null))
          StepBody(
            child: results.isNotEmpty && files != null
                ? _Results(results: results, files: files)
                : Text(
                    results.isNotEmpty ? results.join('\n') : _shown!,
                    style: stepMono,
                  ),
          ),
        if (expanded && images.isNotEmpty) ToolImages(images: _images),
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
          style: TextStyle(
            fontFamily: AppFonts.mono,
            fontFamilyFallback: AppFonts.monoFallbacks,
            fontSize: 12,
          ),
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

/// A todo list, each item after its mark: done ones faint and struck
/// through, as the todo panel had them.
class _TodoList extends StatelessWidget {
  const _TodoList({required this.todos});

  final List<TodoItem> todos;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final todo in todos) _item(todo)],
    );
  }

  Widget _item(TodoItem todo) {
    final done = todo.status == 'completed';
    final (icon, color) = switch (todo.status) {
      'completed' => (todoDoneIcon, themeColors['charts.green']),
      'in_progress' => (todoDoingIcon, themeColors['charts.blue']),
      _ => (todoOpenIcon, AppColors.textMuted),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: SvgPicture.asset(
            icon,
            width: 14,
            height: 14,
            colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            todo.content,
            style: TextStyle(
              color: done ? AppColors.textFaint : AppColors.text,
              fontSize: 12.5,
              height: 1.6,
              decoration: done ? TextDecoration.lineThrough : null,
              decorationColor: AppColors.textFaint,
            ),
          ),
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
      children: [for (final result in results) _result(result)],
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

/// An item of a todo list, and its status: `pending`, `in_progress` or
/// `completed`.
typedef TodoItem = ({String content, String status});

/// The items of the todo list a call wrote (TodoWrite) or read (TaskList,
/// from the lines it returned: `#1 [completed] Ship it`); null for another
/// call.
List<TodoItem>? todoItems(
  String? tool,
  Map<String, Object?> input,
  String? output,
) => switch (tool) {
  'TodoWrite' => [
    for (final todo in input['todos'] as List? ?? const [])
      if (todo is Map)
        (
          content: '${todo['content'] ?? ''}',
          status: '${todo['status'] ?? 'pending'}',
        ),
  ],
  'TaskList' => [
    for (final line in const LineSplitter().convert(output ?? ''))
      if (_taskLine.firstMatch(line) case final match?)
        (content: match[2]!, status: match[1]!),
  ],
  _ => null,
};

final _taskLine = RegExp(r'^#\S+ \[(\w+)\] (.+)$');

/// What a call of a todo tool ([ToolKind.todo]) did to the list, as
/// [tool], its [input] and [output] say, and what about: "Todos 1/3" and
/// the item in progress (the call's [target]), "Added todo" and the item,
/// "Checked todos", the item in progress and "1/3"; null for another tool,
/// or a list not written yet. In [l10n]'s language (English when null).
({String verb, String object, String? detail})? todoStep(
  String? tool,
  Map<String, Object?> input,
  String target, {
  String? output,
  AppLocalizations? l10n,
}) {
  final s = l10n ?? englishLocalizations;
  final todos = todoItems(tool, input, output);
  final done = todos?.where((todo) => todo.status == 'completed').length;
  switch (tool) {
    case 'TodoWrite':
      if (todos == null || todos.isEmpty) return null;
      return (
        verb: s.todoCount(done!, todos.length),
        object: target.isEmpty && done == todos.length ? s.todoAllDone : target,
        detail: null,
      );
    // Read: what is in progress, and how far the list is.
    case 'TaskList':
      if (todos == null || todos.isEmpty) {
        return (
          verb: s.todoChecked,
          object: output == null ? '' : s.todoNone,
          detail: null,
        );
      }
      return (
        verb: s.todoChecked,
        object:
            todos
                .where((todo) => todo.status == 'in_progress')
                .firstOrNull
                ?.content ??
            (done == todos.length ? s.todoAllDone : ''),
        detail: '$done/${todos.length}',
      );
  }
  final verb = switch (tool) {
    'TaskCreate' => s.todoAdded,
    'TaskUpdate' => switch (input['status']) {
      'in_progress' => s.todoStarted,
      'completed' => s.todoCompleted,
      'deleted' => s.todoRemoved,
      _ => s.todoUpdated,
    },
    'TaskGet' => s.todoChecked,
    _ => null,
  };
  return verb == null ? null : (verb: verb, object: target, detail: null);
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
    ToolKind.image =>
      running
          ? s.toolGeneratingImage
          : status == ToolStatus.succeeded
          ? s.toolGeneratedImage
          : s.toolImageFailed,
    ToolKind.browser || ToolKind.other => running ? s.toolUsing : s.toolUsed,
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
