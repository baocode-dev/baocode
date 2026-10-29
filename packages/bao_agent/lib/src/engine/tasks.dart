import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../util/cancel.dart';
import '../util/ids.dart';
import '../util/processes.dart';
import 'session.dart';

/// Where a task stands.
enum TaskStatus {
  running,
  completed,
  failed,
  killed;

  bool get done => this != running;
}

/// Work going on beside the conversation: a command run in the background,
/// a subagent working on its own.
class BackgroundTask {
  BackgroundTask({
    required this.id,
    required this.type,
    required this.description,
    required this.outputFile,
    this.toolUseId,
    this.command,
    this.agentType,
  }) : started = DateTime.now();

  final String id;

  /// `local_bash` or `local_agent`.
  final String type;
  final String description;
  final String outputFile;
  final String? toolUseId;
  final String? command;
  final String? agentType;
  final DateTime started;
  final CancelToken cancel = CancelToken();

  TaskStatus status = TaskStatus.running;
  int? exitCode;
  DateTime? ended;
  Process? process;

  /// Whether it was started in the background, or sent there.
  bool backgrounded = true;

  /// Completes when a subagent working in the foreground is sent to the
  /// background (`background_tasks`): its call returns, it goes on.
  final Completer<void> toBackground = Completer<void>();

  /// Whether it ran past its time and was stopped.
  bool timedOut = false;

  /// A subagent's last words, its tokens and calls.
  String? result;
  int tokens = 0;
  int toolUses = 0;
  String? error;

  final Completer<void> _done = Completer<void>();

  /// Completes once it has ended.
  Future<void> get done => _done.future;

  bool get isShell => type == 'local_bash';

  /// What it has written so far.
  String output() {
    try {
      return File(outputFile).readAsStringSync();
    } on FileSystemException {
      return '';
    }
  }

  Map<String, Object?> toJson() => {
    'task_id': id,
    'task_type': type,
    'description': description,
    'status': status.name,
    'tool_use_id': ?toolUseId,
    'output_file': outputFile,
    'exit_code': ?exitCode,
  };
}

/// The session's background tasks: started, read, stopped, and each one's
/// end told the model (a `<task-notification>` it takes up as a turn of
/// its own) and the host (`task_notification`).
class TaskManager {
  TaskManager(this.session);

  final AgentSession session;

  final Map<String, BackgroundTask> tasks = {};

  /// Commands run in the foreground, by their call: one may be sent to the
  /// background (`background_tasks`).
  final Map<String, ForegroundCommand> foreground = {};

  String get outputDir =>
      session.paths.tasksDir(session.cwd, session.sessionId);

  String newId(String prefix) {
    while (true) {
      final id = '$prefix${randomId(8)}';
      if (!tasks.containsKey(id)) return id;
    }
  }

  BackgroundTask? operator [](String id) => tasks[id];

  Iterable<BackgroundTask> get running =>
      tasks.values.where((task) => task.status == TaskStatus.running);

  BackgroundTask _register({
    required String type,
    required String description,
    String? toolUseId,
    String? command,
    String? agentType,
    String? id,
  }) {
    final taskId = id ?? newId(type == 'local_bash' ? 'b' : 'a');
    Directory(outputDir).createSync(recursive: true);
    final task = BackgroundTask(
      id: taskId,
      type: type,
      description: description,
      outputFile: p.join(outputDir, '$taskId.output'),
      toolUseId: toolUseId,
      command: command,
      agentType: agentType,
    );
    File(task.outputFile).writeAsStringSync('');
    tasks[taskId] = task;
    return task;
  }

  void _started(BackgroundTask task) {
    session.emitSystem('task_started', {
      'task_id': task.id,
      'task_type': task.type,
      'tool_use_id': ?task.toolUseId,
      'description': task.description,
      'is_backgrounded': task.backgrounded,
      'output_file': task.outputFile,
    });
  }

  /// Runs [command] in the background, from [cwd], for [limit] at most.
  Future<BackgroundTask> startShell({
    required String command,
    required String description,
    required String cwd,
    String? toolUseId,
    Duration? limit,
  }) async {
    final task = _register(
      type: 'local_bash',
      description: description,
      toolUseId: toolUseId,
      command: command,
    );
    final shell = session.shell;
    final cwdFile = p.join(outputDir, '${task.id}.cwd');
    final process = await Process.start(
      shell.executable,
      shell.arguments(command, cwdFile),
      workingDirectory: cwd,
      environment: session.shellEnvironment,
      includeParentEnvironment: false,
    );
    task.process = process;
    unawaited(process.stdin.close().catchError((_) {}));
    final sink = File(task.outputFile).openWrite(mode: FileMode.append);
    final written = Future.wait([
      process.stdout.listen(sink.add).asFuture<void>(),
      process.stderr.listen(sink.add).asFuture<void>(),
    ]);
    _started(task);
    final timer = limit == null
        ? null
        : Timer(limit, () {
            if (task.status.done) return;
            task.timedOut = true;
            unawaited(killTree(process.pid));
          });
    unawaited(() async {
      final code = await process.exitCode;
      timer?.cancel();
      await written.catchError((_) => <void>[]);
      await sink.flush();
      await sink.close();
      task.exitCode = code;
      finish(
        task,
        task.status == TaskStatus.killed
            ? TaskStatus.killed
            : code == 0 && !task.timedOut
            ? TaskStatus.completed
            : TaskStatus.failed,
      );
    }());
    return task;
  }

  /// A command in the foreground that has gone on a while: a task the
  /// host shows, that the user can send to the background.
  BackgroundTask registerForeground(ForegroundCommand command) {
    final task = _register(
      type: 'local_bash',
      description: command.description,
      toolUseId: command.toolUseId,
      command: command.command,
    );
    task
      ..process = command.process
      ..backgrounded = false;
    command.registered = task;
    _started(task);
    return task;
  }

  /// Takes on a command that was running in the foreground: its output so
  /// far and what follows go to its file.
  BackgroundTask adoptShell(ForegroundCommand command) {
    final BackgroundTask task;
    if (command.registered case final registered?) {
      task = registered..backgrounded = true;
      command.background(task);
      session.emitSystem('task_updated', {
        'task_id': task.id,
        'patch': {'is_backgrounded': true},
      });
    } else {
      task = _register(
        type: 'local_bash',
        description: command.description,
        toolUseId: command.toolUseId,
        command: command.command,
      );
      task.process = command.process;
      command.background(task);
      _started(task);
    }
    session.emitSystem('background_tasks_changed', {
      'tasks': [
        for (final t in running) {'task_id': t.id},
      ],
    });
    return task;
  }

  /// A subagent working in the background.
  BackgroundTask registerAgent({
    required String description,
    required String agentId,
    String? toolUseId,
    String? agentType,
    bool background = true,
  }) {
    final task = _register(
      type: 'local_agent',
      description: description,
      toolUseId: toolUseId,
      agentType: agentType,
      id: agentId,
    );
    task.backgrounded = background;
    _started(task);
    return task;
  }

  /// Notes what a background subagent did: a step in its output file,
  /// and progress for the host.
  void agentProgress(BackgroundTask task, {String? lastTool, String? summary}) {
    session.emitSystem('task_progress', {
      'task_id': task.id,
      'tool_use_id': ?task.toolUseId,
      'description': ?summary,
      'last_tool_name': ?lastTool,
      'usage': {
        'total_tokens': task.tokens,
        'tool_uses': task.toolUses,
        'duration_ms': DateTime.now().difference(task.started).inMilliseconds,
      },
    });
  }

  /// Ends [task] as [status]: the host told, and the model, unless it was
  /// stopped on purpose.
  void finish(BackgroundTask task, TaskStatus status, {String? result}) {
    if (task.status.done && task._done.isCompleted) return;
    task.status = status;
    task.ended = DateTime.now();
    if (result != null) task.result = result;
    if (!task._done.isCompleted) task._done.complete();
    final summary = _summary(task);
    session.emitSystem('task_notification', {
      'task_id': task.id,
      'tool_use_id': ?task.toolUseId,
      'status': status.name,
      'summary': summary,
      'output_file': task.outputFile,
      'usage': {
        'total_tokens': task.tokens,
        'tool_uses': task.toolUses,
        'duration_ms': task.ended!.difference(task.started).inMilliseconds,
      },
    });
    // A subagent in the foreground answers its call; one stopped on
    // purpose needs no telling.
    if (task.backgrounded && status != TaskStatus.killed) {
      session.taskEnded(task, notification(task, summary));
    }
  }

  static String _summary(BackgroundTask task) {
    final what = task.isShell
        ? 'Background command "${task.description}"'
        : 'Agent "${task.description}"';
    return switch (task.status) {
      TaskStatus.completed =>
        task.isShell
            ? '$what completed (exit code ${task.exitCode ?? 0})'
            : '$what completed',
      TaskStatus.failed =>
        task.isShell
            ? task.timedOut
                  ? '$what ran out of time and was stopped'
                  : '$what failed with exit code ${task.exitCode}'
            : '$what failed: ${task.error ?? 'unknown error'}',
      TaskStatus.killed => '$what was stopped',
      TaskStatus.running => '$what is running',
    };
  }

  /// What the model is told when [task] ends.
  static String notification(BackgroundTask task, String summary) {
    final out = StringBuffer('<task-notification>\n')
      ..writeln('<task-id>${task.id}</task-id>')
      ..writeln('<tool-use-id>${task.toolUseId ?? ''}</tool-use-id>')
      ..writeln('<status>${task.status.name}</status>')
      ..writeln('<summary>$summary</summary>');
    if (task.isShell) {
      out.writeln('<output-file>${task.outputFile}</output-file>');
    } else if (task.result != null) {
      out.writeln('<result>${task.result}</result>');
    }
    out.write('</task-notification>');
    if (task.isShell) {
      out.write(
        '\nRead the output file to retrieve the result: ${task.outputFile}',
      );
    }
    return out.toString();
  }

  /// Stops [id]; false when there is no such task running.
  Future<bool> stop(String id) async {
    final task = tasks[id];
    if (task == null || task.status.done) return false;
    task.status = TaskStatus.killed;
    task.cancel.cancel('stopped');
    if (task.process case final process?) {
      await killTree(process.pid);
    }
    if (!task.isShell) finish(task, TaskStatus.killed);
    // A shell's end is noted when its process exits: soon after.
    await task.done.timeout(const Duration(seconds: 3), onTimeout: () {});
    return true;
  }

  /// Stops them all: the session is ending.
  Future<void> stopAll() async {
    for (final task in [...running]) {
      await stop(task.id);
    }
    for (final command in [...foreground.values]) {
      await killTree(command.process.pid);
    }
  }
}

/// A command running in the foreground, its output gathered for its call's
/// result, until it ends or is sent to the background.
class ForegroundCommand {
  ForegroundCommand({
    required this.process,
    required this.command,
    required this.description,
    required this.toolUseId,
  });

  final Process process;
  final String command;
  final String description;
  final String toolUseId;

  final StringBuffer stdout = StringBuffer();
  final StringBuffer stderr = StringBuffer();

  /// Set once it went to the background, as that task.
  BackgroundTask? task;

  /// Its task while it runs in the foreground, once it has gone on long
  /// enough to be shown as one.
  BackgroundTask? registered;
  IOSink? _sink;
  final Completer<BackgroundTask> _backgrounded = Completer();

  /// Completes when it is sent to the background.
  Future<BackgroundTask> get backgrounded => _backgrounded.future;

  void addStdout(List<int> bytes) {
    if (_sink case final sink?) {
      sink.add(bytes);
    } else {
      stdout.write(utf8.decode(bytes, allowMalformed: true));
    }
  }

  void addStderr(List<int> bytes) {
    if (_sink case final sink?) {
      sink.add(bytes);
    } else {
      stderr.write(utf8.decode(bytes, allowMalformed: true));
    }
  }

  void background(BackgroundTask task) {
    this.task = task;
    final sink = _sink = File(task.outputFile).openWrite(mode: FileMode.append);
    sink.write(stdout.toString());
    sink.write(stderr.toString());
    if (!_backgrounded.isCompleted) _backgrounded.complete(task);
  }

  Future<void> closeSink() async {
    final sink = _sink;
    if (sink == null) return;
    await sink.flush();
    await sink.close();
  }
}
