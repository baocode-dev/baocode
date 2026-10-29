import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../engine/session.dart';
import '../engine/tasks.dart';
import '../permissions/decision.dart';
import '../permissions/shell_command.dart';
import '../util/ids.dart';
import '../util/json.dart';
import '../util/processes.dart';
import 'tool.dart';

/// Runs a shell command.
class BashTool extends Tool {
  const BashTool();

  static const defaultTimeout = Duration(minutes: 2);
  static const maxTimeout = Duration(minutes: 10);
  static const defaultBackgroundTimeout = Duration(minutes: 30);
  static const maxBackgroundTimeout = Duration(hours: 2);
  static const defaultMaxOutput = 30000;

  @override
  String get name => 'Bash';

  @override
  String get description => 'Runs a shell command and returns what it printed.';

  @override
  String promptFor(AgentSession session) =>
      '''Runs a command in a shell and gives back what it printed.

- The shell starts where the last command left it, but give absolute paths where you can: a `cd` inside a compound command may need the user's say-so. Variables and functions do not carry over from call to call; the shell is set up from the user's profile.
- Do not use it to read or change files (cat, head, tail, sed, awk, echo): Read, Edit and Write do that better, and the user can follow them. Use it for that only when nothing else will do, or the user asked for it.
- ${_search(session)} Keep a search narrow (a folder, a file type) and its output short (`-l`, `| head`).
- What a command prints is shown to you, not always to the user: say what matters in your reply.
- `timeout` is in milliseconds: ${defaultTimeout.inMilliseconds} unless given, at most ${maxTimeout.inMilliseconds} in the foreground.
- `run_in_background` starts it detached: it runs on across turns, and you are woken when it ends. `timeout` then bounds how long it may run (${defaultBackgroundTimeout.inMilliseconds} unless given, at most ${maxBackgroundTimeout.inMilliseconds}): at that limit it is stopped, and you are told. It needs no `&`.

# Git
- Nothing interactive works here: no `git rebase -i`, no `git add -i`.
- Use `gh` for GitHub: pull requests, issues, the API.
- Make commits and push them only when told to; on the default branch, start a branch for them first.
- End commit messages and pull request descriptions with the attribution lines the conversation gives in a <system-reminder>, when it gives any.''';

  /// How to search, with what this machine has: a model told of `rg`
  /// where there is none spends a call finding that out.
  static String _search(AgentSession session) =>
      session.fileIndex.ripgrep != null
      ? "To find files and what is in them, search here: `rg` (or `grep -rn`) for text, `rg --files -g '<glob>'` (or `find`) for names."
      : 'To find files and what is in them, search here: `grep -rn` for text, `find` for names (ripgrep is not installed: no `rg`).';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': {
      'command': {'type': 'string', 'description': 'The command to run'},
      'timeout': {
        'type': 'number',
        'description': 'How long it may run, in milliseconds (at most 600000 in the foreground)',
      },
      'description': {
        'type': 'string',
        'description': 'What the command does, in 5 to 10 words: the user sees it in place of the command',
      },
      'run_in_background': {
        'type': 'boolean',
        'description': 'Start it detached and go on: you are woken when it ends. `timeout` then bounds how long it may run (1800000 unless given, at most 7200000)',
      },
      'dangerouslyDisableSandbox': {
        'type': 'boolean',
        'description': 'Run it outside the sandbox, where there is one',
      },
    },
    'required': ['command'],
    'additionalProperties': false,
  };

  @override
  bool isReadOnly(Map<String, Object?> input) =>
      isReadOnlyCommand('${input['command'] ?? ''}');

  @override
  String? describe(Map<String, Object?> input) =>
      asString(input['description']);

  @override
  String? ruleContent(Map<String, Object?> input) => asString(input['command']);

  /// How long a command runs in the foreground before it is shown as a
  /// task.
  static const foregroundTaskAfter = Duration(seconds: 1);

  @override
  Future<PermissionDecision> checkPermissions(
    Map<String, Object?> input,
    ToolContext context,
  ) async => context.session.permissions.checkBash(
    '${input['command'] ?? ''}',
    context.cwd,
    context.run.permissionMode,
  );

  @override
  Future<String?> validate(
    Map<String, Object?> input,
    ToolContext context,
  ) async {
    final command = '${input['command'] ?? ''}';
    if (command.trim().isEmpty) return 'command must not be empty';
    // A `sleep` alone, waited on, only wastes the user's time.
    final sleep = RegExp(r'^\s*sleep\s+(\d+)\s*$').firstMatch(command);
    if (sleep != null &&
        int.parse(sleep[1]!) > 120 &&
        input['run_in_background'] != true) {
      return 'Blocked: a long `sleep` on its own. Run what you are waiting '
          'for in the background and you will be told when it finishes.';
    }
    return null;
  }

  @override
  Future<ToolOutput> call(
    Map<String, Object?> input,
    ToolContext context,
  ) async {
    final session = context.session;
    final command = '${input['command']}';
    final description =
        asText(input['description']) ??
        (command.length > 60 ? '${command.substring(0, 60)}…' : command);
    if (input['run_in_background'] == true) {
      final task = await session.tasks.startShell(
        command: command,
        description: description,
        cwd: context.cwd,
        toolUseId: context.toolUseId,
        limit: Duration(
          milliseconds:
              (asInt(input['timeout']) ??
                      defaultBackgroundTimeout.inMilliseconds)
                  .clamp(1000, maxBackgroundTimeout.inMilliseconds),
        ),
      );
      return _backgroundOutput(task);
    }
    final timeout = _timeout(input, session);
    final shell = session.shell;
    final cwdFile = p.join(
      Directory.systemTemp.path,
      'bao-cwd-${randomId(10)}',
    );
    final Process process;
    try {
      process = await Process.start(
        shell.executable,
        shell.arguments(command, cwdFile),
        workingDirectory: Directory(context.cwd).existsSync()
            ? context.cwd
            : session.cwd,
        environment: session.shellEnvironment,
        includeParentEnvironment: false,
      );
    } on ProcessException catch (error) {
      return ToolOutput.error(
        'Could not start ${shell.executable}: ${error.message}',
      );
    }
    unawaited(process.stdin.close().catchError((_) {}));
    final running = ForegroundCommand(
      process: process,
      command: command,
      description: description,
      toolUseId: context.toolUseId,
    );
    session.tasks.foreground[context.toolUseId] = running;
    // Shown as a task once it has gone on a while: one the user can send
    // to the background.
    final shown = Timer(foregroundTaskAfter, () {
      if (running.task == null) session.tasks.registerForeground(running);
    });
    final streams = Future.wait([
      process.stdout.listen(running.addStdout).asFuture<void>(),
      process.stderr.listen(running.addStderr).asFuture<void>(),
    ]);
    var timedOut = false;
    var interrupted = false;
    final ended = Completer<String>();
    unawaited(
      process.exitCode.then((_) {
        if (!ended.isCompleted) ended.complete('exit');
      }),
    );
    final timer = Timer(timeout, () {
      if (!ended.isCompleted) ended.complete('timeout');
    });
    unawaited(
      context.cancel.whenCancelled.then((_) {
        if (!ended.isCompleted) ended.complete('cancel');
      }),
    );
    unawaited(
      running.backgrounded.then((_) {
        if (!ended.isCompleted) ended.complete('background');
      }),
    );
    final how = await ended.future;
    timer.cancel();
    shown.cancel();
    switch (how) {
      case 'background':
        session.tasks.foreground.remove(context.toolUseId);
        final task = running.task!;
        unawaited(() async {
          final code = await process.exitCode;
          await streams.catchError((_) => <void>[]);
          await running.closeSink();
          task.exitCode = code;
          session.tasks.finish(
            task,
            task.status == TaskStatus.killed
                ? TaskStatus.killed
                : code == 0
                ? TaskStatus.completed
                : TaskStatus.failed,
          );
        }());
        return _backgroundOutput(task);
      case 'timeout':
        timedOut = true;
        await killTree(process.pid);
      case 'cancel':
        interrupted = true;
        await killTree(process.pid);
    }
    final code = await process.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        Process.killPid(process.pid, ProcessSignal.sigkill);
        return -9;
      },
    );
    await streams
        .timeout(const Duration(seconds: 2), onTimeout: () => [])
        .catchError((_) => <void>[]);
    session.tasks.foreground.remove(context.toolUseId);
    if (running.registered case final task?) {
      task.exitCode = code;
      session.tasks.finish(
        task,
        interrupted || timedOut || task.status == TaskStatus.killed
            ? TaskStatus.killed
            : code == 0
            ? TaskStatus.completed
            : TaskStatus.failed,
      );
    }
    final cwdNote = _followCwd(cwdFile, context);
    final maxOutput =
        asInt(session.environment['BASH_MAX_OUTPUT_LENGTH']) ??
        defaultMaxOutput;
    final stdout = _truncate(_trimEnd(running.stdout.toString()), maxOutput);
    final stderr = _truncate(_trimEnd(running.stderr.toString()), maxOutput);
    final parts = <String>[
      if (stdout.isNotEmpty) stdout,
      if (stderr.isNotEmpty) stderr,
    ];
    var text = parts.join('\n');
    if (timedOut) {
      text = [
        if (text.isNotEmpty) text,
        'Command timed out after ${_seconds(timeout)}',
      ].join('\n');
    } else if (interrupted) {
      text = [if (text.isNotEmpty) text, 'Command was interrupted'].join('\n');
    } else if (code != 0) {
      text = ['Exit code $code', if (text.isNotEmpty) text].join('\n');
    }
    if (cwdNote != null) text = [if (text.isNotEmpty) text, cwdNote].join('\n');
    final isError = timedOut || interrupted || code != 0;
    return ToolOutput(
      text.isEmpty ? '(Bash completed with no output)' : text,
      isError: isError,
      result: {
        'stdout': stdout,
        'stderr': stderr,
        'interrupted': timedOut || interrupted,
        'isImage': false,
        'exitCode': code,
        if (timedOut) 'timedOut': true,
      },
    );
  }

  static ToolOutput _backgroundOutput(BackgroundTask task) => ToolOutput(
    'Command running in background with ID: ${task.id}. Output is being '
    'written to: ${task.outputFile}. You will be notified when it finishes; '
    'read that file to see how it is going meanwhile.',
    result: {
      'stdout': '',
      'stderr': '',
      'interrupted': false,
      'isImage': false,
      'backgroundTaskId': task.id,
      'outputFile': task.outputFile,
    },
  );

  static Duration _timeout(Map<String, Object?> input, AgentSession session) {
    final env = session.environment;
    final defaultMs =
        asInt(env['BASH_DEFAULT_TIMEOUT_MS']) ?? defaultTimeout.inMilliseconds;
    final maxMs =
        asInt(env['BASH_MAX_TIMEOUT_MS']) ??
        (defaultMs > maxTimeout.inMilliseconds
            ? defaultMs
            : maxTimeout.inMilliseconds);
    final asked = asInt(input['timeout']) ?? defaultMs;
    return Duration(milliseconds: asked.clamp(1000, maxMs));
  }

  static String _seconds(Duration duration) =>
      duration.inMinutes >= 1 && duration.inSeconds % 60 == 0
      ? '${duration.inMinutes}m'
      : '${duration.inSeconds}s';

  /// Moves the agent's shell to where the command left it, inside the
  /// working folders; elsewhere, back to the project, and says so.
  static String? _followCwd(String cwdFile, ToolContext context) {
    final file = File(cwdFile);
    String? ended;
    try {
      if (file.existsSync()) ended = file.readAsStringSync().trim();
    } on FileSystemException {
      ended = null;
    }
    try {
      if (file.existsSync()) file.deleteSync();
    } on FileSystemException {
      // Left in the temp folder.
    }
    if (ended == null || ended.isEmpty) return null;
    final permissions = context.session.permissions;
    if (permissions.inWorkingDirectories(ended) ||
        _sameDirectory(ended, context.cwd)) {
      context.run.cwd = ended;
      return null;
    }
    final project = context.session.cwd;
    context.run.cwd = project;
    return 'Shell cwd was reset to $project';
  }

  static bool _sameDirectory(String a, String b) {
    try {
      return Directory(a).resolveSymbolicLinksSync() ==
          Directory(b).resolveSymbolicLinksSync();
    } on FileSystemException {
      return false;
    }
  }

  static String _trimEnd(String text) => text.replaceFirst(RegExp(r'\s+$'), '');

  /// [text] cut to [max] characters, from its middle.
  static String _truncate(String text, int max) {
    if (text.length <= max) return text;
    final head = text.substring(0, max ~/ 2);
    final tail = text.substring(text.length - max ~/ 2);
    final dropped = '\n'
        .allMatches(text.substring(max ~/ 2, text.length - max ~/ 2))
        .length;
    return '$head\n\n... [$dropped lines truncated] ...\n\n$tail';
  }
}

/// Stops a background task.
class TaskStopTool extends Tool {
  const TaskStopTool();

  @override
  String get name => 'TaskStop';

  @override
  List<String> get aliases => const ['KillShell', 'KillBash'];

  @override
  String get description =>
      'Stops a background task, a shell or an agent, by its ID: one that runs '
      'too long or is no longer needed. Says whether it was stopped.';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': {
      'task_id': {
        'type': 'string',
        'description': 'The ID of the task to stop',
      },
      'shell_id': {'type': 'string', 'description': 'Older name of task_id'},
    },
    'additionalProperties': false,
  };

  @override
  Future<PermissionDecision> checkPermissions(
    Map<String, Object?> input,
    ToolContext context,
  ) async => const PermissionAllow();

  @override
  Future<ToolOutput> call(
    Map<String, Object?> input,
    ToolContext context,
  ) async {
    final id = asText(input['task_id']) ?? asText(input['shell_id']);
    if (id == null) return ToolOutput.error('task_id is required');
    final task = context.session.tasks[id];
    if (task == null) return ToolOutput.error('No task found with ID: $id');
    if (task.status.done) {
      return ToolOutput.error(
        'Task $id is not running (it is ${task.status.name}).',
      );
    }
    await context.session.tasks.stop(id);
    return ToolOutput(
      'Successfully stopped task: $id (${task.description})',
      result: {
        'message': 'Successfully stopped task: $id',
        'task_id': id,
        'task_type': task.type,
        'command': task.command ?? task.description,
      },
    );
  }
}
