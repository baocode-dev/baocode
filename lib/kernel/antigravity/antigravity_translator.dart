import 'dart:convert';
import 'dart:math' as math;

import '../../chat/chat_models.dart';
import '../claude_code/claude_sdk_tools.dart';
import '../kernel_event.dart';
import '../kernel_types.dart';

/// Turns a conversation's steps, as agy's language server tells them
/// (`StreamAgentStateUpdates`), into the kernel's events: its messages,
/// thoughts and tool calls as items, its edits as changes to review.
///
/// A step is told whole each time it changes (a reply as it is written,
/// a command as it ends), by its index: applying it again changes
/// nothing, and what grew is streamed as deltas.
class AntigravityTranslator {
  AntigravityTranslator({
    required this.emit,
    required this.nextSeq,
    this.ownsMessage,
    this.originalOf,
  });

  final void Function(KernelEvent event) emit;
  final int Function() nextSeq;

  /// Whether the message [clientMessageId] is a turn this app sent (shown
  /// as it was sent, not as agy keeps it).
  final bool Function(String clientMessageId)? ownsMessage;

  /// The text of [path] before the conversation changed it, where agy
  /// did not say in the edit itself (its `GetTrajectoryFileDiffs`).
  final Future<String?> Function(String path)? originalOf;

  /// Told of text as it streams (to meter the model's pace).
  void Function(String text, {required bool thought})? onDelta;

  /// Called with step [index] waiting on the user (a permission, a
  /// question): once, and again if what it asks changes; [onWaitingOver]
  /// once it no longer waits.
  void Function(int index, Map<String, Object?> step)? onWaiting;
  void Function(int index)? onWaitingOver;

  /// Called as the background tasks changed ([tasks]).
  void Function()? onTasksChanged;

  /// The turn its edits are made in.
  String? turnId;

  /// Whether the turn under way plans (Plan mode): what agy writes of its
  /// own then (a markdown file in its folder) is its plan. Read from each
  /// message too, as agy keeps it.
  bool planning = false;

  /// The steps as last told, by index.
  final Map<int, _Step> _steps = {};

  /// The background tasks the commands left running, by task id.
  final Map<String, KernelTask> tasks = {};

  /// The step each task's command is, by task id.
  final Map<String, int> _taskSteps = {};

  int get stepCount => _steps.isEmpty ? 0 : _steps.keys.reduce(math.max) + 1;

  /// Whether a tool call is under way.
  bool get calling => _steps.values.any(
    (step) => step.running && step.type != _planner && step.type != _user,
  );

  /// The index of the message sent as [clientMessageId], once agy has it.
  int? indexOf(String clientMessageId) => _messages[clientMessageId];
  final Map<String, int> _messages = {};

  static String _id(int index) => 'agy-s$index';

  // --- Steps -----------------------------------------------------------------------

  static const _user = 'CORTEX_STEP_TYPE_USER_INPUT';
  static const _planner = 'CORTEX_STEP_TYPE_PLANNER_RESPONSE';

  /// Applies the steps told, each at its index; [history] for the
  /// conversation read back (its edits were reviewed then, not now).
  void steps(
    List<int> indices,
    List<Map<String, Object?>> steps, {
    bool history = false,
  }) {
    final told = [
      for (var i = 0; i < indices.length && i < steps.length; i++)
        (indices[i], steps[i]),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    for (final (index, raw) in told) {
      final step = _steps.putIfAbsent(index, () => _Step(index))
        ..raw = raw
        ..history = history;
      _apply(step);
      _waitingOf(step);
    }
  }

  void _apply(_Step step) {
    switch (step.type) {
      case _user:
        _userInput(step);
      case _planner:
        _plannerResponse(step);
      case 'CORTEX_STEP_TYPE_RUN_COMMAND':
        _runCommand(step);
      case 'CORTEX_STEP_TYPE_CODE_ACTION':
        _codeAction(step);
      case 'CORTEX_STEP_TYPE_SYSTEM_MESSAGE':
        _systemMessage(step);
      case 'CORTEX_STEP_TYPE_ERROR_MESSAGE':
        _errorMessage(step);
      case 'CORTEX_STEP_TYPE_INVOKE_SUBAGENT':
        _subagent(step);
      case 'CORTEX_STEP_TYPE_ASK_QUESTION':
        _askQuestion(step);
      case 'CORTEX_STEP_TYPE_CHECKPOINT' ||
          'CORTEX_STEP_TYPE_EPHEMERAL_MESSAGE' ||
          'CORTEX_STEP_TYPE_NOTIFY_USER':
        break;
      default:
        _tool(step);
    }
  }

  // --- The user's messages -----------------------------------------------------------

  /// The user's messages read back, by step index: timed once their
  /// turns are known ([timeTurns]).
  final Map<int, UserMessageItem> _users = {};
  final Map<int, (Duration?, TurnUsage?)> _timed = {};

  void _userInput(_Step step) {
    final input = _map(step.raw['userInput']);
    final texts = <String>[];
    var plan = false;
    for (final item in input['items'] as List? ?? const []) {
      switch (item) {
        case {'text': final String text}:
          texts.add(text);
        case {'item': {'slashCommand': {'info': {'name': 'plan'}}}}:
          plan = true;
        case {'item': {'slashCommand': {'name': 'plan'}}}:
          plan = true;
      }
    }
    planning = plan;
    step.user = true;
    if (input['clientMessageId'] case final String id) {
      _messages[id] = step.index;
      if (ownsMessage?.call(id) ?? false) {
        step.own = true;
        return;
      }
    }
    if (_users.containsKey(step.index)) return;
    // A message after a plan: the plan was gone on from.
    endPlanRound();
    resolvePlan(started: true);
    final message = UserMessageItem(
      text: withoutReminders(texts.join()),
      images: [
        for (final image in input['images'] as List? ?? const [])
          if (image case {
            'base64Data': final String data,
            'mimeType': final String type,
          })
            ImageAttachment(bytes: base64Decode(data), mediaType: type),
      ],
      sentAt: step.createdAt,
    );
    _users[step.index] = message;
    emit(ItemUpserted(nextSeq(), _id(step.index), message));
  }

  static final _reminders = RegExp(
    r'<system-reminder>[\s\S]*?(</system-reminder>|$)',
  );

  /// [text] without what the app told agy beside the user's words (its
  /// notes, each a `<system-reminder>`), which agy keeps as part of the
  /// message: read back with it, and its title made of it.
  static String withoutReminders(String text) {
    if (!text.contains('<system-r')) return text.trim();
    var plain = text.replaceAll(_reminders, '');
    // A title cut in one.
    final cut = plain.indexOf('<system-r');
    if (cut >= 0) plain = plain.substring(0, cut);
    return plain.trim();
  }

  /// Times the turns read back, now that their steps are known: when each
  /// message was sent, how long its turn took and what it spent, as agy's
  /// steps say. The turn under way ([running]) is left to its end.
  void timeTurns({bool running = false}) {
    final users = _steps.keys.where((i) => _steps[i]!.user).toList()..sort();
    final count = stepCount;
    for (var u = 0; u < users.length; u++) {
      final index = users[u];
      final end = u + 1 < users.length ? users[u + 1] : count;
      if (running && u == users.length - 1) continue;
      final message = _users[index];
      if (message == null) continue;
      final started = message.sentAt;
      DateTime? last;
      for (var i = index + 1; i < end; i++) {
        final at = _steps[i]?.endedAt;
        if (at != null && (last == null || at.isAfter(last))) last = at;
      }
      final worked = started != null && last != null && last.isAfter(started)
          ? last.difference(started)
          : null;
      final usage = usageFrom(index, until: end);
      final timed = (worked, usage);
      final before = _timed[index];
      if (before != null &&
          before.$1 == timed.$1 &&
          before.$2?.inputTokens == usage?.inputTokens &&
          before.$2?.outputTokens == usage?.outputTokens) {
        continue;
      }
      _timed[index] = timed;
      emit(
        ItemUpserted(
          nextSeq(),
          _id(index),
          UserMessageItem(
            text: message.text,
            images: message.images,
            sentAt: message.sentAt,
            worked: worked,
            usage: usage,
          ),
        ),
      );
    }
  }

  /// What the model spent from step [index] on (to [until]), as the steps
  /// say; null where none says.
  TurnUsage? usageFrom(int index, {int? until}) {
    var input = 0;
    var output = 0;
    var any = false;
    for (final MapEntry(key: i, value: step) in _steps.entries) {
      if (i < index || (until != null && i >= until)) continue;
      final usage = _map(_map(step.raw['metadata'])['modelUsage']);
      if (usage.isEmpty) continue;
      any = true;
      input += _int(usage['inputTokens']);
      output += _int(usage['outputTokens']);
    }
    return any ? TurnUsage(inputTokens: input, outputTokens: output) : null;
  }

  // --- Replies -----------------------------------------------------------------------

  void _plannerResponse(_Step step) {
    final reply = _map(step.raw['plannerResponse']);
    final thinking = reply['thinking'] as String? ?? '';
    final response = reply['response'] as String? ?? '';
    final generating = step.status == 'CORTEX_STEP_STATUS_GENERATING';
    final thinkId = '${_id(step.index)}-think';
    final textId = _id(step.index);
    if (thinking.isNotEmpty) {
      final thoughtOver = !generating || response.isNotEmpty;
      if (!step.thinkOpen && !step.thinkDone) {
        if (thoughtOver) {
          emit(ItemUpserted(nextSeq(), thinkId, _thought(step, thinking)));
          step.thinkDone = true;
        } else {
          step.thinkOpen = true;
          step.thinkingSince = DateTime.now();
          emit(
            ItemUpserted(
              nextSeq(),
              thinkId,
              ThinkingItem(text: '', tokens: 0, startedAt: step.thinkingSince),
              streaming: true,
            ),
          );
        }
      }
      if (step.thinkOpen) {
        _stream(thinkId, step.thinking, thinking, thought: true);
        if (thoughtOver) {
          step.thinkOpen = false;
          step.thinkDone = true;
          emit(
            ItemCompleted(nextSeq(), thinkId, item: _thought(step, thinking)),
          );
        }
      } else if (step.thinkDone &&
          (thinking != step.thinking || (!generating && !step.thoughtFinal))) {
        // Told whole once more as the step ends: with what it cost.
        emit(ItemUpserted(nextSeq(), thinkId, _thought(step, thinking)));
      }
      if (!generating) step.thoughtFinal = true;
      step.thinking = thinking;
    }
    if (response.isNotEmpty) {
      if (!step.textOpen && !step.textDone) {
        if (generating) {
          step.textOpen = true;
          emit(
            ItemUpserted(
              nextSeq(),
              textId,
              const AssistantTextItem(''),
              streaming: true,
            ),
          );
        } else {
          step.textDone = true;
          emit(ItemUpserted(nextSeq(), textId, AssistantTextItem(response)));
        }
      }
      if (step.textOpen) {
        _stream(textId, step.text, response, thought: false);
        if (!generating) {
          step.textOpen = false;
          step.textDone = true;
          emit(
            ItemCompleted(nextSeq(), textId, item: AssistantTextItem(response)),
          );
        }
      } else if (step.textDone && response != step.text) {
        emit(ItemUpserted(nextSeq(), textId, AssistantTextItem(response)));
      }
      step.text = response;
    } else if (!generating && step.textOpen) {
      step.textOpen = false;
      step.textDone = true;
      emit(
        ItemCompleted(nextSeq(), textId, item: AssistantTextItem(step.text)),
      );
    }
    if (!generating && !step.noted) {
      step.noted = true;
      switch (reply['stopReason']) {
        case 'STOP_REASON_MAX_TOKENS':
          _notice(
            step,
            NoticeKind.warning,
            'The reply hit the model’s output limit',
          );
        case 'STOP_REASON_CONTENT_FILTER' || 'STOP_REASON_SAFETY':
          _notice(step, NoticeKind.error, 'The model’s reply was filtered');
        case 'STOP_REASON_RECITATION':
          _notice(
            step,
            NoticeKind.error,
            'The model stopped: its reply resembled copyrighted text',
          );
      }
    }
  }

  /// Streams what [now] has beyond [before] as deltas of [id]; written
  /// over whole where it is not a continuation.
  void _stream(String id, String before, String now, {required bool thought}) {
    if (now == before) return;
    if (now.startsWith(before)) {
      final delta = now.substring(before.length);
      emit(
        TextDelta(
          nextSeq(),
          id,
          before.length,
          delta,
          tokens: thought ? _tokensOf(now) : null,
        ),
      );
      onDelta?.call(delta, thought: thought);
      return;
    }
    emit(
      ItemUpserted(
        nextSeq(),
        id,
        thought
            ? ThinkingItem(text: '', tokens: 0, startedAt: DateTime.now())
            : const AssistantTextItem(''),
        streaming: true,
      ),
    );
    emit(
      TextDelta(nextSeq(), id, 0, now, tokens: thought ? _tokensOf(now) : null),
    );
  }

  ThinkingItem _thought(_Step step, String text) {
    final usage = _map(_map(step.raw['metadata'])['modelUsage']);
    final tokens = _int(usage['thinkingOutputTokens']);
    final reply = _map(step.raw['plannerResponse']);
    final seconds = switch (reply['thinkingDuration']) {
      final String duration when duration.endsWith('s') => double.tryParse(
        duration.substring(0, duration.length - 1),
      )?.ceil(),
      _ => null,
    };
    return ThinkingItem(
      text: text,
      tokens: tokens > 0 ? tokens : _tokensOf(text),
      seconds: math.max(
        1,
        seconds ??
            switch (step.thinkingSince) {
              final since? => DateTime.now().difference(since).inSeconds,
              null => 1,
            },
      ),
    );
  }

  static int _tokensOf(String text) => (text.length / 4).ceil();

  void _notice(_Step step, NoticeKind kind, String text) => emit(
    ItemUpserted(nextSeq(), '${_id(step.index)}-note', NoticeItem(kind, text)),
  );

  // --- Commands ------------------------------------------------------------------------

  void _runCommand(_Step step) {
    final command = _map(step.raw['runCommand']);
    final arguments = step.arguments;
    final line =
        command['commandLine'] as String? ??
        _string(arguments['CommandLine']) ??
        '';
    final task = _map(step.raw['taskDetails']);
    final taskId = task['id'] as String?;
    final background = taskId != null || command['blocking'] == false;
    final exit = command['exitCode'];
    final denied = step.denied || command['userRejected'] == true;
    final running =
        step.running ||
        (taskId != null && tasks[taskId]?.status == CommandStatus.running);
    final item = TerminalItem(
      command: line,
      description: _string(arguments['toolSummary']),
      output: denied && _output(command).isEmpty
          ? 'Not allowed'
          : _output(command),
      status: running && !denied
          ? CommandStatus.running
          : denied || step.failed || (exit is int && exit != 0)
          ? CommandStatus.failed
          : CommandStatus.succeeded,
      background: background,
      startedAt: step.createdAt,
    );
    emit(ItemUpserted(nextSeq(), _id(step.index), item));
    if (taskId == null) return;
    _taskSteps[taskId] = step.index;
    if (tasks[taskId] case final known?) {
      // The step ends (its command did) before agy drops the task.
      if (!step.running && known.status == CommandStatus.running) {
        tasks[taskId] = known.copyWith(status: item.status);
        onTasksChanged?.call();
      }
      return;
    }
    // A command still running in the background (the step stays live till
    // it ends); one read back done was over long since.
    if (!step.running) return;
    tasks[taskId] = KernelTask(
      id: taskId,
      description:
          _string(task['description']) ??
          _string(task['title']) ??
          _string(arguments['toolSummary']) ??
          line,
      kind: KernelTaskKind.command,
      status: CommandStatus.running,
      startedAt: step.createdAt ?? DateTime.now(),
      toolUseId: _id(step.index),
      background: true,
      outputFile: switch (task['logUri']) {
        final String uri => _pathOf(uri),
        _ => null,
      },
    );
    onTasksChanged?.call();
  }

  /// What agy prints before a command's output (when it was run, its exit
  /// code, the sandbox's note) left out: the output alone.
  static String _output(Map<String, Object?> command) {
    final full = switch (command['combinedOutput']) {
      {'full': final String full} => full,
      _ => command['stdout'] as String? ?? '',
    };
    const marker = 'Command output:\n';
    final at = full.indexOf(marker);
    if (at >= 0) return full.substring(at + marker.length).trimRight();
    return full
        .split('\n')
        .where(
          (line) =>
              !line.startsWith('Created At: ') &&
              !line.startsWith('Completed At: '),
        )
        .join('\n')
        .trim();
  }

  /// A task's end, as agy tells it ([terminal] its command's output, if
  /// it said): the task and its command's card.
  void _endTask(
    String taskId, {
    required bool failed,
    String? summary,
    Map<String, Object?>? terminal,
  }) {
    final task = tasks[taskId];
    if (task == null || task.status != CommandStatus.running) return;
    tasks[taskId] = task.copyWith(
      status: failed ? CommandStatus.failed : CommandStatus.succeeded,
      summary: summary,
    );
    if (_steps[_taskSteps[taskId]] case final step?) {
      if (terminal != null) step.taskOutput = terminal;
      _runCommand(step);
    }
    onTasksChanged?.call();
  }

  /// The background tasks as agy lists them running: one no longer listed
  /// has ended.
  void backgroundTasks(List<Map<String, Object?>> listed) {
    final running = {
      for (final task in listed)
        if (_map(task['taskSnapshot'])['taskId'] case final String id) id,
    };
    for (final MapEntry(key: id, value: task) in [...tasks.entries]) {
      if (task.status == CommandStatus.running && !running.contains(id)) {
        _endTask(id, failed: false);
      }
    }
  }

  static final _taskEnd = RegExp(
    r'''[Tt]ask (?:id )?"?([\w./-]*task-\d+)"? (finished|failed|was cancelled|was killed|completed|exited)''',
  );

  void _systemMessage(_Step step) {
    final system = _map(step.raw['systemMessage']);
    final render = _map(system['renderInfo']);
    final message = system['message'] as String? ?? '';
    final terminal = [
      for (final block in render['contentBlocks'] as List? ?? const [])
        if (block case {'terminal': final Map<String, Object?> terminal})
          terminal,
    ].firstOrNull;
    final match = _taskEnd.firstMatch(message);
    if (match != null || terminal != null) {
      final taskId =
          match?.group(1) ??
          tasks.keys
              .where(
                (id) =>
                    id.split('/').last.isNotEmpty &&
                    message.contains(id.split('/').last),
              )
              .firstOrNull;
      if (taskId != null) {
        final exit = terminal?['exitCode'];
        _endTask(
          taskId,
          failed:
              (match != null &&
                  match.group(2) != 'finished' &&
                  match.group(2) != 'completed') ||
              (exit is int && exit != 0) ||
              RegExp(r'exit code:?\s*[1-9]').hasMatch(message),
          summary: _firstLine(message.substring(match?.end ?? 0)),
          terminal: terminal,
        );
      }
      return;
    }
    if (render['hidden'] == true || message.isEmpty || step.history) return;
    if (render.isEmpty) return;
    emit(
      ItemUpserted(
        nextSeq(),
        _id(step.index),
        NoticeItem(NoticeKind.info, render['title'] as String? ?? message),
      ),
    );
  }

  static String? _firstLine(String text) {
    final line = text
        .replaceFirst(RegExp(r'^\s*(with result:?)?\s*'), '')
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .firstOrNull;
    if (line == null) return null;
    return line.length > 160 ? '${line.substring(0, 160)}…' : line;
  }

  void _errorMessage(_Step step) {
    final error = _map(_map(step.raw['errorMessage'])['error']);
    final text =
        _string(error['userErrorMessage']) ??
        _string(error['shortError']) ??
        _string(error['fullError']) ??
        'Antigravity reported an error';
    final retry = RegExp(r'attempt \d|[Rr]etr(y|ies|ying)').hasMatch(text);
    emit(
      ItemUpserted(
        nextSeq(),
        _id(step.index),
        NoticeItem(retry ? NoticeKind.retry : NoticeKind.error, text),
      ),
    );
  }

  // --- Edits -------------------------------------------------------------------------

  void _codeAction(_Step step) {
    final action = _map(step.raw['codeAction']);
    final spec = _map(action['actionSpec']);
    final edit = _map(_map(action['actionResult'])['edit']);
    final uri =
        edit['absoluteUri'] as String? ??
        _map(_map(spec['createFile'])['path'])['absoluteUri'] as String? ??
        _map(_map(spec['command'])['file'])['absoluteUri'] as String? ??
        _map(_map(spec['deleteFile'])['path'])['absoluteUri'] as String? ??
        _string(step.arguments['AbsolutePath']) ??
        _string(step.arguments['TargetFile']);
    final path = uri == null ? null : _pathOf(uri);
    final created =
        edit['createFile'] == true || spec.containsKey('createFile');
    if (path != null && _planWrite(step, path, created)) return;
    final lines = _diffLines(_map(edit['diff']));
    final stats = _map(action['diffStats']);
    final added = stats.isEmpty ? null : _int(stats['additions']);
    final removed = stats.isEmpty ? null : _int(stats['deletions']);
    if (path == null) {
      _tool(step);
      return;
    }
    if (step.running || step.failed || step.denied) {
      emit(
        ItemUpserted(
          nextSeq(),
          _id(step.index),
          ToolCallItem(
            kind: ToolKind.edit,
            target: _base(path),
            path: path,
            detail: _string(step.arguments['toolSummary']),
            status: step.denied
                ? ToolStatus.denied
                : step.running
                ? ToolStatus.running
                : ToolStatus.failed,
            callId: _id(step.index),
          ),
        ),
      );
      return;
    }
    final slash = path.lastIndexOf(RegExp(r'[/\\]'));
    emit(
      ItemUpserted(
        nextSeq(),
        _id(step.index),
        CodeDiffItem(
          fileName: path.substring(slash + 1),
          directory: slash < 0 ? '' : path.substring(0, slash),
          lines: lines,
          added: added,
          removed: removed,
        ),
      ),
    );
    if (step.edited || step.history || agyOwnFile(path)) return;
    step.edited = true;
    final change = FileChange(
      path: path,
      added: added ?? lines.where((l) => l.type == DiffLineType.added).length,
      removed:
          removed ?? lines.where((l) => l.type == DiffLineType.removed).length,
    );
    final turn = turnId;
    if (edit['originalContent'] case final String before) {
      emit(
        FileEdited(
          nextSeq(),
          change,
          turnId: turn,
          original: OriginalText(before),
        ),
      );
    } else if (created) {
      emit(
        FileEdited(
          nextSeq(),
          change,
          turnId: turn,
          original: const OriginalText(null),
        ),
      );
    } else if (originalOf case final original?) {
      original(path)
          .then(
            (before) => emit(
              FileEdited(
                nextSeq(),
                change,
                turnId: turn,
                original: before == null ? null : OriginalText(before),
              ),
            ),
          )
          .catchError((_) => emit(FileEdited(nextSeq(), change, turnId: turn)));
    } else {
      emit(FileEdited(nextSeq(), change, turnId: turn));
    }
  }

  /// The lines of an edit's unified diff, numbered as in the file after
  /// (added and kept lines; removed ones as before). agy tells where the
  /// diff ends (`endLine`, in the file after) rather than where it starts:
  /// counted back from there.
  static List<DiffLine> _diffLines(Map<String, Object?> diff) {
    final unified = _map(diff['unifiedDiff']);
    final raw = [
      for (final line
          in unified['lines'] as List? ??
              unified['changes'] as List? ??
              const [])
        if (line is Map)
          (
            line['text'] as String? ?? '',
            switch (line['type']) {
              'UNIFIED_DIFF_LINE_TYPE_INSERT' ||
              'UNIFIED_DIFF_CHANGE_TYPE_INSERT' => DiffLineType.added,
              'UNIFIED_DIFF_LINE_TYPE_DELETE' ||
              'UNIFIED_DIFF_CHANGE_TYPE_DELETE' => DiffLineType.removed,
              _ => DiffLineType.context,
            },
          ),
    ];
    final afterCount = raw.where((l) => l.$2 != DiffLineType.removed).length;
    final start = switch (diff['startLine'] ?? unified['startLine']) {
      final told? => math.max(1, _int(told)),
      null => switch (diff['endLine']) {
        final told? => math.max(1, _int(told) - afterCount + 1),
        null => 1,
      },
    };
    var before = start;
    var after = start;
    return [
      for (final (text, type) in raw)
        switch (type) {
          DiffLineType.added => DiffLine(type, after++, text),
          DiffLineType.removed => DiffLine(type, before++, text),
          DiffLineType.context => () {
            before++;
            return DiffLine(type, after++, text);
          }(),
        },
    ];
  }

  // --- Other tools -------------------------------------------------------------------

  void _tool(_Step step) {
    final name = step.toolName;
    final status = step.denied
        ? ToolStatus.denied
        : step.running
        ? ToolStatus.running
        : step.failed
        ? ToolStatus.failed
        : ToolStatus.succeeded;
    final id = _id(step.index);
    final arguments = step.arguments;
    final summary = _string(arguments['toolSummary']);
    final raw = step.raw;
    final ChatItem item;
    if (raw['viewFile'] case final Map<String, Object?> view) {
      final path = _pathOf(view['absolutePathUri'] as String? ?? '');
      item = ToolCallItem(
        kind: ToolKind.read,
        target: _base(path),
        path: path,
        status: status,
        callId: id,
      );
    } else if (raw['viewFileOutline'] case final Map<String, Object?> view) {
      final path = _pathOf(
        view['absolutePathUri'] as String? ??
            view['absolutePath'] as String? ??
            '',
      );
      item = ToolCallItem(
        kind: ToolKind.read,
        target: _base(path),
        path: path,
        status: status,
        callId: id,
      );
    } else if (raw['listDirectory'] case final Map<String, Object?> list) {
      final path = _pathOf(list['directoryPathUri'] as String? ?? '');
      item = ToolCallItem(
        kind: ToolKind.listDir,
        target: path,
        path: path,
        status: status,
        output: (list['children'] as List? ?? const []).join('\n'),
        callId: id,
      );
    } else if (raw['grepSearch'] case final Map<String, Object?> grep) {
      item = ToolCallItem(
        kind: ToolKind.grep,
        target: grep['query'] as String? ?? '',
        detail: switch (grep['searchPathUri']) {
          final String uri => _pathOf(uri),
          _ => null,
        },
        status: status,
        output: grep['rawOutput'] as String?,
        callId: id,
      );
    } else if (raw['codeSearch'] case final Map<String, Object?> search) {
      item = ToolCallItem(
        kind: ToolKind.grep,
        target: search['query'] as String? ?? '',
        status: status,
        callId: id,
      );
    } else if (raw['find'] case final Map<String, Object?> find) {
      item = ToolCallItem(
        kind: ToolKind.search,
        target: find['pattern'] as String? ?? '',
        detail: find['searchDirectory'] as String?,
        status: status,
        output: find['rawOutput'] as String?,
        callId: id,
      );
    } else if (raw['searchWeb'] case final Map<String, Object?> web) {
      item = ToolCallItem(
        kind: ToolKind.web,
        target: web['query'] as String? ?? '',
        status: status,
        output: web['summary'] as String?,
        callId: id,
      );
    } else if (raw['readUrlContent'] case final Map<String, Object?> read) {
      item = ToolCallItem(
        kind: ToolKind.web,
        target: read['url'] as String? ?? '',
        status: status,
        callId: id,
      );
    } else if (raw['generic'] != null || raw['mcpTool'] != null) {
      if (name == null) {
        // A placeholder: what is asked of the user shows as that.
        if (step.raw['requestedInteraction'] != null || step.running) return;
      }
      final generic = _map(raw['generic'] ?? raw['mcpTool']);
      final result = _map(generic['result']);
      final args = switch (generic['args']) {
        final Map<String, Object?> args when args.isNotEmpty => args,
        _ => arguments,
      };
      final output =
          _string(result['result']) ??
          _string(generic['result'] is String ? generic['result'] : null) ??
          [
            for (final block
                in _map(result['stepRenderInfo'])['contentBlocks'] as List? ??
                    const [])
              if (block case {'markdown': final String markdown}) markdown,
          ].join('\n');
      if (name != null && name.startsWith('mcp_')) {
        item = _mcpItem(id, name, args, summary, output, status);
      } else {
        item = ToolCallItem(
          kind: ToolKind.other,
          label: name,
          target:
              summary ??
              _map(result['stepRenderInfo'])['title'] as String? ??
              '',
          status: status,
          output: output.isEmpty ? null : output,
          callId: id,
          input: args,
        );
      }
    } else if (name == null) {
      return;
    } else {
      item = ToolCallItem(
        kind: ToolKind.other,
        label: name,
        target: summary ?? '',
        status: status,
        callId: id,
        input: arguments,
      );
    }
    emit(ItemUpserted(nextSeq(), id, item));
  }

  /// The MCP server's prefix agy names a tool of the app's own with.
  static const _ownPrefix = 'mcp_${ClaudeSdkTools.server}_';

  /// [name] as Claude Code would name it (`mcp__baocode__<tool>`), when one
  /// of the app's own tools.
  static String? ownToolName(String name) => name.startsWith(_ownPrefix)
      ? 'mcp__${ClaudeSdkTools.server}__${name.substring(_ownPrefix.length)}'
      : null;

  ChatItem _mcpItem(
    String id,
    String name,
    Map<String, Object?> args,
    String? summary,
    String output,
    ToolStatus status,
  ) {
    final input = {...args}..remove('toolSummary');
    final said = summary ?? '';
    if (ownToolName(name) case final own?) {
      if (ClaudeSdkTools.called(own) case ClaudeSdkTool(
        name: final toolName,
        :final kind?,
        summary: final describe,
      )) {
        return ToolCallItem(
          kind: kind,
          tool: toolName,
          callId: id,
          input: input,
          label: said.isEmpty ? null : '',
          target: said.isNotEmpty
              ? said
              : describe?.call(input, output.isEmpty ? null : output) ?? '',
          status: status,
          output: output.isEmpty ? null : output,
        );
      }
    }
    return ToolCallItem(
      kind: ToolKind.mcp,
      label: name.substring(4),
      target: said,
      status: status,
      output: output.isEmpty ? null : output,
      callId: id,
      input: input,
    );
  }

  void _askQuestion(_Step step) {
    final questions = [
      for (final question
          in _map(step.raw['askQuestion'])['questions'] as List? ?? const [])
        if (question is Map) question.cast<String, Object?>(),
    ];
    final answers = <String>[];
    for (final question in questions) {
      final picked = (question['selectedOptionIds'] as List? ?? const [])
          .toSet();
      final texts = [
        for (final option in question['options'] as List? ?? const [])
          if (option case {'id': final id, 'text': final String text}
              when picked.contains(id))
            text,
        ?_string(question['writeInResponse']),
      ];
      if (texts.isNotEmpty) answers.add(texts.join(', '));
    }
    emit(
      ItemUpserted(
        nextSeq(),
        _id(step.index),
        ToolCallItem(
          kind: ToolKind.question,
          target: questions
              .map((question) => question['question'] as String? ?? '')
              .where((text) => text.isNotEmpty)
              .join(' / '),
          status: step.running
              ? ToolStatus.running
              : step.failed
              ? ToolStatus.failed
              : ToolStatus.succeeded,
          output: answers.isEmpty ? null : answers.join('\n'),
          callId: _id(step.index),
        ),
      ),
    );
  }

  void _subagent(_Step step) {
    final invoke = _map(step.raw['invokeSubagent']);
    final spec = switch (invoke['subagents']) {
      [final Map<String, Object?> first, ...] => first,
      _ => const <String, Object?>{},
    };
    // What it was asked shows; its work and its report stay agy's, the
    // report told in agy's next reply.
    emit(
      ItemUpserted(
        nextSeq(),
        _id(step.index),
        AgentItem(
          description:
              _string(spec['role']) ??
              _string(invoke['subagentName']) ??
              _string(step.arguments['Role']) ??
              'Subagent',
          agentType: switch (_string(spec['typeName'])) {
            'self' || null => null,
            final type => type,
          },
          prompt:
              _string(invoke['prompt']) ??
              _string(spec['initialPrompt']) ??
              _string(step.arguments['Prompt']),
          status: step.running
              ? CommandStatus.running
              : step.failed
              ? CommandStatus.failed
              : CommandStatus.succeeded,
          startedAt: step.running ? step.createdAt : null,
        ),
      ),
    );
  }

  // --- Waiting on the user ---------------------------------------------------------------

  void _waitingOf(_Step step) {
    final request = step.status == 'CORTEX_STEP_STATUS_WAITING'
        ? step.raw['requestedInteraction']
        : null;
    final key = request == null ? null : jsonEncode(request);
    if (key == step.waitingKey) return;
    step.waitingKey = key;
    if (key == null) {
      onWaitingOver?.call(step.index);
    } else {
      onWaiting?.call(step.index, step.raw);
    }
  }

  /// Ends what streams as the turn ends; calls still under way are shown
  /// given up ([interrupted]) until agy says.
  void settle({bool interrupted = false}) {
    for (final step in _steps.values) {
      if (step.textOpen || step.thinkOpen) {
        if (step.thinkOpen) {
          step.thinkOpen = false;
          step.thinkDone = true;
          emit(
            ItemCompleted(
              nextSeq(),
              '${_id(step.index)}-think',
              item: _thought(step, step.thinking),
            ),
          );
        }
        if (step.textOpen) {
          step.textOpen = false;
          step.textDone = true;
          emit(
            ItemCompleted(
              nextSeq(),
              _id(step.index),
              item: AssistantTextItem(step.text),
            ),
          );
        }
      }
      if (interrupted &&
          step.running &&
          step.type != _planner &&
          step.type != _user) {
        step.givenUp = true;
        _apply(step);
      }
    }
  }

  // --- Plans -----------------------------------------------------------------------

  /// The card of the round of planning under way, by the step that began
  /// it; the one awaiting the user, once the turn is over.
  String? _planCard;
  String? _awaitingCard;
  final Map<String, PlanItem> _plans = {};
  int _planRounds = 0;

  /// The plan put to the user, until they go on from it.
  PlanItem? get awaitingPlan => _plans[_awaitingCard];

  /// Whether [path] is in agy's own folder for its conversations
  /// (`~/.gemini/antigravity-cli/brain`), not the project's.
  static bool agyOwnFile(String path) =>
      RegExp(r'[/\\]antigravity-cli[/\\]brain[/\\]').hasMatch(path);

  /// Shows [step] on the plan's card, if it writes the plan.
  bool _planWrite(_Step step, String path, bool created) {
    if (!planning && !step.planWrite) return false;
    if (!agyOwnFile(path) || !path.endsWith('.md')) return false;
    if (path.endsWith('walkthrough.md') || path.endsWith('task.md')) {
      return false;
    }
    step.planWrite = true;
    final card = _planCard ??= _id(step.index);
    final known = _plans[card];
    final text = _planText(step) ?? known?.text;
    var writes = known?.writes ?? 0;
    final written = !step.running && !step.done && !step.failed;
    if (written) {
      step.done = true;
      writes++;
    }
    final plan = _plans[card] = PlanItem(
      path: path,
      round: known?.round ?? ++_planRounds,
      title: PlanItem.titleOf(text) ?? known?.title,
      text: text,
      writes: writes,
    );
    emit(ItemUpserted(nextSeq(), card, plan));
    if (written && !step.history) emit(PlanWritten(nextSeq(), path));
    return true;
  }

  /// The plan as written: the file's content, from the call that wrote it
  /// (whole, `write_file`), else the lines added by its diff.
  static String? _planText(_Step step) {
    if (_string(step.arguments['Content']) case final content?) return content;
    final diff = _map(
      _map(_map(_map(step.raw['codeAction'])['actionResult'])['edit'])['diff'],
    );
    final lines = _diffLines(diff);
    if (lines.isEmpty) return null;
    return [
      for (final line in lines)
        if (line.type != DiffLineType.removed) line.text,
    ].join('\n');
  }

  /// The turn is over: the plan it wrote, if any, awaits the user.
  void endPlanRound() {
    final card = _planCard;
    if (card == null) return;
    _planCard = null;
    _awaitingCard = card;
    _putPlan(card, _plans[card]!.copyWith(status: PlanStatus.awaiting));
  }

  /// The user went on from the plan awaiting: [started] it, or said what
  /// should change ([feedback]).
  void resolvePlan({required bool started, String? feedback}) {
    final card = _awaitingCard;
    if (card == null) return;
    _awaitingCard = null;
    final plan = _plans[card]!;
    _putPlan(
      card,
      started
          ? plan.copyWith(status: PlanStatus.approved)
          : plan.copyWith(status: PlanStatus.sentBack, feedback: feedback),
    );
  }

  void _putPlan(String card, PlanItem plan) {
    _plans[card] = plan;
    emit(ItemUpserted(nextSeq(), card, plan));
  }

  // --- Helpers ---------------------------------------------------------------------

  static Map<String, Object?> _map(Object? value) => switch (value) {
    final Map<String, Object?> map => map,
    final Map map => map.cast<String, Object?>(),
    _ => const {},
  };

  /// A number as proto JSON writes it: 64-bit ones as strings.
  static int _int(Object? value) => switch (value) {
    final int n => n,
    final num n => n.toInt(),
    final String s => int.tryParse(s) ?? 0,
    _ => 0,
  };

  static String? _string(Object? value) =>
      value is String && value.trim().isNotEmpty ? value : null;

  static String _base(String path) => path.split(RegExp(r'[/\\]')).last;

  /// A path from a `file://` URI (as agy names files), else as given.
  static String _pathOf(String uri) {
    if (!uri.startsWith('file:')) return uri;
    try {
      return Uri.parse(uri).toFilePath();
    } on Object {
      return Uri.decodeFull(uri.replaceFirst(RegExp('^file://'), ''));
    }
  }
}

/// A step as last told, and what was shown of it.
class _Step {
  _Step(this.index);

  final int index;
  Map<String, Object?> raw = const {};
  bool history = false;

  String get type => raw['type'] as String? ?? '';
  String get status => raw['status'] as String? ?? '';

  static const _live = {
    '',
    'CORTEX_STEP_STATUS_UNSPECIFIED',
    'CORTEX_STEP_STATUS_PENDING',
    'CORTEX_STEP_STATUS_RUNNING',
    'CORTEX_STEP_STATUS_WAITING',
    'CORTEX_STEP_STATUS_GENERATING',
  };

  /// Shown given up: the turn was stopped before agy said.
  bool givenUp = false;

  bool get running => !givenUp && _live.contains(status);

  bool get failed =>
      givenUp ||
      status == 'CORTEX_STEP_STATUS_CANCELED' ||
      status == 'CORTEX_STEP_STATUS_ERROR' ||
      status == 'CORTEX_STEP_STATUS_FAILED';

  /// Whether the user turned it down.
  bool get denied {
    for (final interaction
        in raw['completedInteractions'] as List? ?? const []) {
      if (interaction case {
        'response': {'permission': {'allow': final allow}},
      }) {
        return allow != true;
      }
    }
    return false;
  }

  Map<String, Object?> get metadata =>
      AntigravityTranslator._map(raw['metadata']);

  String? get toolName => AntigravityTranslator._string(
    AntigravityTranslator._map(metadata['toolCall'])['name'],
  );

  /// The tool call's arguments, as the model wrote them.
  Map<String, Object?> get arguments {
    final json = AntigravityTranslator._map(
      metadata['toolCall'],
    )['argumentsJson'];
    if (json is! String || json.isEmpty) return const {};
    if (_argumentsOf == json) return _arguments;
    _argumentsOf = json;
    try {
      _arguments = AntigravityTranslator._map(jsonDecode(json));
    } on FormatException {
      _arguments = const {};
    }
    return _arguments;
  }

  String? _argumentsOf;
  Map<String, Object?> _arguments = const {};

  DateTime? get createdAt => _time(metadata['createdAt']);

  /// When it ended, as best its metadata says.
  DateTime? get endedAt =>
      _time(metadata['completedAt']) ??
      _time(metadata['finishedGeneratingAt']) ??
      createdAt;

  static DateTime? _time(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toLocal() : null;

  // What was shown.
  bool user = false;
  bool own = false;
  String text = '';
  String thinking = '';
  bool textOpen = false;
  bool textDone = false;
  bool thinkOpen = false;
  bool thinkDone = false;

  /// Whether the thought was shown as the step ended, its cost known.
  bool thoughtFinal = false;
  DateTime? thinkingSince;
  bool noted = false;
  bool edited = false;
  bool done = false;
  bool planWrite = false;
  String? waitingKey;

  /// A background command's output as its task ended, when agy told it
  /// with the end rather than in the step.
  Map<String, Object?>? taskOutput;
}
