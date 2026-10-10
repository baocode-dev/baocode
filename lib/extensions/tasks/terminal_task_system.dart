/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Tasks run in terminals: a shell task's command line through the default
// shell (`-c`), a process task's executable, an extension's custom
// execution in its Pseudoterminal; its dependencies first (in parallel or
// in sequence); its variables resolved (asking for inputs); the output's
// lines through its problem matchers into the markers; a background task
// active and inactive as its matchers' begin and end patterns say; its
// terminal shown as `presentation` asks and reused by the next task.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/contrib/tasks/browser/terminalTaskSystem.ts.
//
// Deviations: no reconnection to tasks' terminals across restarts; no
// split terminals for `presentation.group` (the group still chooses which
// idle terminal is reused); no task status decorations on the terminals'
// tabs; a rerun resolves its variables again even when the task says
// `reevaluateOnRerun: false`.

import 'dart:async';
import 'dart:math';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:path/path.dart' as p;

import '../../ide/terminal/pty.dart';
import '../../ide/terminal/terminal_instance.dart';
import '../../ide/terminal/terminal_service.dart';
import '../../ide/terminal/terminal_shell.dart';
import '../host/init_data.dart';
import '../language/marker_service.dart';
import 'problem_collectors.dart';
import 'problem_matcher.dart';
import 'task_configuration.dart';
import 'tasks.dart';

/// `ITaskSystemInfo`: how an extension host resolves a folder's variables
/// (`$resolveVariables`) and finds executables, for its scheme.
final class TaskSystemInfo {
  const TaskSystemInfo({
    required this.platform,
    required this.resolveVariables,
    this.uriProvider,
    this.findExecutable,
  });

  final TaskPlatform platform;

  /// The values of [variables] (`${name}`), by name without `${}`, and the
  /// process when [process] is asked; null when an input was cancelled.
  final Future<({String? process, Map<String, String> variables})?> Function(
    ExtHostWorkspaceFolder folder,
    Set<String> variables, {
    ({String name, String? cwd, String? path})? process,
  })
  resolveVariables;
  final VsUri Function(String path)? uriProvider;
  final Future<String?> Function(
    String command,
    String? cwd,
    List<String>? paths,
  )?
  findExecutable;
}

/// What the task system asks to resolve variables
/// (`IConfigurationResolverService`).
abstract interface class TaskVariableResolver {
  /// Every one of [variables] (`${…}`), asking for inputs and running
  /// commands; by name without `${}`; null when cancelled.
  Future<Map<String, String>?> resolveWithInteraction(
    ExtHostWorkspaceFolder? folder,
    List<String> variables,
  );

  /// [value] with the variables that need no interaction resolved.
  Future<String> resolveAsync(ExtHostWorkspaceFolder? folder, String value);
}

/// `ITaskResolver`: a dependency's task.
typedef TaskResolver = Future<Task?> Function(VsUri? uri, Object identifier);

/// `TaskExecuteKind`.
enum TaskExecuteKind { started, active }

/// `ITaskExecuteResult`.
typedef TaskExecuteResult = ({
  TaskExecuteKind kind,
  Task task,
  Future<TaskSummary> promise,
  bool background,
});

final class _ActiveTerminalData {
  _ActiveTerminalData(this.task, this.count);

  final Task task;
  late final Future<TaskSummary> promise;
  TerminalInstance? terminal;
  TaskEventKind? state;
  final _InstanceCount count;
}

final class _InstanceCount {
  int count = 0;
}

final class _TerminalData {
  _TerminalData(this.terminal, this.lastTask, this.group, this.nonce);

  final TerminalInstance terminal;
  String lastTask;
  final String? group;
  final String? nonce;
}

/// `VariableResolver` of the terminal task system: the values resolved for
/// a run, else asked of [_resolver].
final class _RunVariables {
  _RunVariables(this.folder, this.info, this.values, this._resolver);

  final ExtHostWorkspaceFolder? folder;
  final TaskSystemInfo? info;
  final Map<String, String> values;
  final TaskVariableResolver _resolver;

  static final _regex = RegExp(r'\$\{(.*?)\}');

  Future<String> resolve(String value) async {
    final matches = _regex.allMatches(value).toList();
    if (matches.isEmpty) return value;
    final replacements = await Future.wait([
      for (final match in matches) _replacer(match.group(0)!),
    ]);
    var index = 0;
    return value.replaceAllMapped(_regex, (_) => replacements[index++]);
  }

  Future<String> _replacer(String match) async {
    final result = values[match.substring(2, match.length - 1)];
    if (result != null) return result;
    return _resolver.resolveAsync(folder, match);
  }
}

/// `TerminalTaskSystem`.
final class TerminalTaskSystem {
  TerminalTaskSystem({
    required this.terminals,
    required this.markers,
    required this.matchers,
    required this.variableResolver,
    this.taskSystemInfo,
    this.extensionPty,
    this.workspaceFolders,
    this.isOpen,
    this.files,
    this.log,
    this.openProblems,
    this.platform,
  });

  /// Where its terminals go.
  final TerminalService Function() terminals;
  final MarkerService markers;
  final ProblemMatcherRegistry matchers;
  final TaskVariableResolver variableResolver;

  /// The registered task system of a folder's scheme.
  final TaskSystemInfo? Function(ExtHostWorkspaceFolder? folder)?
  taskSystemInfo;

  /// The extension host's Pseudoterminals, for custom executions.
  final Future<Pty> Function(TerminalInstance instance)? Function()?
  extensionPty;

  /// The workspace's folders, for a task of none.
  final List<ExtHostWorkspaceFolder> Function()? workspaceFolders;
  final bool Function(VsUri resource)? isOpen;
  final ProblemFileSystem? files;

  /// The Tasks output.
  final void Function(String text)? log;

  /// Opens the Problems view (`revealProblems`).
  final void Function()? openProblems;
  final TaskPlatform? platform;

  static const _processVarName = '__process__';
  static const _taskTerminalType = 'Task';

  static const _shellQuotes = <String, ShellQuotingOptions>{
    'cmd': ShellQuotingOptions(strong: '"'),
    'powershell': ShellQuotingOptions(
      escapeChar: '`',
      charsToEscape: ' "\'()',
      strong: "'",
      weak: '"',
    ),
    'bash': ShellQuotingOptions(
      escapeChar: r'\',
      charsToEscape: ' "\'',
      strong: "'",
      weak: '"',
    ),
    'zsh': ShellQuotingOptions(
      escapeChar: r'\',
      charsToEscape: ' "\'',
      strong: "'",
      weak: '"',
    ),
  };

  final _activeTasks = <String, _ActiveTerminalData>{};
  final _busyTasks = <String, Task>{};
  final _taskErrors = <String, bool>{};
  final _taskDependencies = <String, List<String>>{};
  final _terminals = <int, _TerminalData>{};

  /// Idle terminals by the task last in them; the last idled first.
  var _idleTaskTerminals = <String, int>{};
  final _sameTaskTerminals = <String, int>{};
  Future<void> _terminalCreationQueue = Future.value();
  final _onDidStateChange = StreamController<TaskEvent>.broadcast(sync: true);
  final _capturedTaskVariables = <String, String>{};
  final _random = Random();
  ({Task task, TaskResolver resolver})? _lastTask;
  bool _disposed = false;

  Stream<TaskEvent> get onDidStateChange => _onDidStateChange.stream;

  /// Variables background tasks captured (`${taskVar:name}`).
  Map<String, String> get capturedTaskVariables => _capturedTaskVariables;

  TaskPlatform get _platform => platform ?? TaskPlatform.current;

  void _log(String value) => log?.call('$value\n');

  void _fireTaskEvent(TaskEvent event) {
    if (event.kind != TaskEventKind.changed &&
        event.kind != TaskEventKind.problemMatcherEnded &&
        event.kind != TaskEventKind.problemMatcherStarted) {
      final active = _activeTasks[event.task!.getMapKey()];
      active?.state = event.kind;
    }
    if (!_onDidStateChange.isClosed) _onDidStateChange.add(event);
  }

  /// `run`.
  TaskExecuteResult run(Task task, TaskResolver resolver) {
    task = task.clone();
    final instances = _isTaskEmpty(task)
        ? <_ActiveTerminalData>[]
        : _getInstances(task);
    final validInstance =
        instances.length < (task.runOptions.instanceLimit ?? 1);
    final instance = instances.firstOrNull?.count.count ?? 0;
    if (instance > 0) task.instance = instance;
    final current = (task: task, resolver: resolver);
    if (!validInstance) {
      final terminalData = instances.last;
      _lastTask = current;
      return (
        kind: TaskExecuteKind.active,
        task: terminalData.task,
        promise: terminalData.promise,
        background: task.configurationProperties.isBackground ?? false,
      );
    }
    final promise = _executeTask(task, resolver, {}, {});
    unawaited(
      promise.then((_) => _lastTask = current, onError: (Object _) => null),
    );
    return (
      kind: TaskExecuteKind.started,
      task: task,
      promise: promise,
      background: task.configurationProperties.isBackground ?? false,
    );
  }

  /// `rerun`: the task last run, again; null when none was.
  TaskExecuteResult? rerun() {
    final last = _lastTask;
    if (last == null) return null;
    return run(last.task, last.resolver);
  }

  bool isActiveSync() => _activeTasks.values.any((v) => v.terminal != null);

  bool canAutoTerminate() => _activeTasks.values.every(
    (v) => !(v.task.configurationProperties.promptOnClose ?? false),
  );

  List<Task> getActiveTasks() => [
    for (final value in _activeTasks.values)
      if (value.terminal != null) value.task,
  ];

  List<Task> getBusyTasks() => _busyTasks.values.toList();

  /// The terminal an active [task] runs in.
  TerminalInstance? terminalOf(Task task) =>
      _activeTasks[task.getMapKey()]?.terminal;

  /// The task last run in [terminal].
  String? lastTaskIn(TerminalInstance terminal) =>
      _terminals[terminal.id]?.lastTask;

  Future<void> customExecutionComplete(Task task, int? result) async {
    final active = _activeTasks[task.getMapKey()];
    if (active?.terminal == null) {
      throw StateError(
        'Expected to have a terminal for a custom execution task',
      );
    }
  }

  List<_ActiveTerminalData> _getInstances(Task task) {
    final recentKey = task.getKey();
    return [
      for (final value in _activeTasks.values)
        if (recentKey != null && recentKey == value.task.getKey()) value,
    ];
  }

  void _removeFromActiveTasks(String key) => _activeTasks.remove(key);

  /// `terminate`: true once its terminal is gone and its run ended.
  Future<({bool success, Task? task})> terminate(Task task) async {
    final active = _activeTasks[task.getMapKey()];
    final terminal = active?.terminal;
    if (active == null || terminal == null) {
      return (success: false, task: null);
    }
    _kill(terminal);
    await active.promise.then((_) {}, onError: (Object _) {});
    return (success: true, task: active.task);
  }

  Future<List<({bool success, Task? task})>> terminateAll() async {
    final ended = <Future<void>>[];
    final result = <({bool success, Task? task})>[];
    for (final MapEntry(:key, :value) in [..._activeTasks.entries]) {
      final terminal = value.terminal;
      if (terminal == null) continue;
      _kill(terminal);
      ended.add(value.promise.then((_) {}, onError: (Object _) {}));
      if (identical(_activeTasks[key], value)) _activeTasks.remove(key);
      result.add((success: true, task: value.task));
    }
    await Future.wait(ended);
    return result;
  }

  void _kill(TerminalInstance terminal) {
    final service = terminals();
    service.kill(terminal, TerminalExitReason.user);
  }

  Future<TaskSummary> _executeTask(
    Task task,
    TaskResolver resolver,
    Set<String> liveDependencies,
    Map<String, Future<TaskSummary>> encounteredTasks, [
    Map<String, String>? alreadyResolved,
  ]) {
    _showTaskLoadErrors(task);
    final mapKey = task.getMapKey();
    final lastInstance = _getInstances(task).lastOrNull;
    final count = lastInstance?.count ?? _InstanceCount();
    count.count++;
    final activeTask = _ActiveTerminalData(task, count);
    // In the active tasks before any of the run (microsoft/vscode#180541).
    activeTask.promise =
        Future<TaskSummary>.microtask(() async {
          alreadyResolved ??= {};
          final promises = <Future<TaskSummary>>[];
          final dependsOn = task.configurationProperties.dependsOn;
          if (dependsOn != null) {
            final nextLiveDependencies = {
              ...liveDependencies,
              task.getCommonTaskId(),
            };
            for (final dependency in dependsOn) {
              final dependencyTask = await resolver(
                dependency.uri,
                dependency.task,
              );
              if (dependencyTask == null) {
                _log(
                  "Couldn't resolve dependent task '${dependency.task is String ? dependency.task : (dependency.task as KeyedTaskIdentifier).properties}' "
                  "in workspace folder '${dependency.uri}'",
                );
                continue;
              }
              _taskDependencies
                  .putIfAbsent(mapKey, () => [])
                  .add(dependencyTask.getMapKey());
              Future<TaskSummary>? taskResult;
              final commonKey = dependencyTask.getCommonTaskId();
              if (nextLiveDependencies.contains(commonKey)) {
                _log(
                  'There is a dependency cycle. See task '
                  '"${dependencyTask.label}".',
                );
                taskResult = Future.value((exitCode: null));
              } else {
                taskResult = encounteredTasks[commonKey];
                if (taskResult == null) {
                  final active =
                      _activeTasks[dependencyTask.getMapKey()] ??
                      _getInstances(dependencyTask).lastOrNull;
                  if (active != null) {
                    taskResult = _getDependencyPromise(active);
                  }
                }
              }
              if (taskResult == null) {
                _fireTaskEvent(
                  TaskEvent(TaskEventKind.dependsOnStarted, task: task),
                );
                taskResult = _executeDependencyTask(
                  dependencyTask,
                  resolver,
                  nextLiveDependencies,
                  encounteredTasks,
                  alreadyResolved,
                );
              }
              encounteredTasks[commonKey] = taskResult;
              promises.add(taskResult);
              if (task.configurationProperties.dependsOrder ==
                  DependsOrder.sequence) {
                final result = await taskResult;
                if (result.exitCode != 0) break;
              }
            }
          }
          final summaries = await Future.wait(promises);
          for (final summary in summaries) {
            if (summary.exitCode != 0) return (exitCode: summary.exitCode);
          }
          if ((task.isContributed || task.isCustom) && task.command != null) {
            return _executeCommand(task, alreadyResolved!);
          }
          return (exitCode: 0);
        }).whenComplete(() {
          // Unless a later run replaced it.
          if (identical(_activeTasks[mapKey], activeTask)) {
            _activeTasks.remove(mapKey);
          }
        });
    _activeTasks[mapKey] = activeTask;
    return activeTask.promise;
  }

  void _showTaskLoadErrors(Task task) {
    if (task.taskLoadMessages.isEmpty) return;
    for (final message in task.taskLoadMessages) {
      _log(message);
    }
  }

  Future<TaskSummary> _createInactiveDependencyPromise(Task task) {
    final completer = Completer<TaskSummary>();
    late final StreamSubscription<TaskEvent> subscription;
    subscription = onDidStateChange.listen((event) {
      if (event.kind == TaskEventKind.inactive && identical(event.task, task)) {
        unawaited(subscription.cancel());
        completer.complete((exitCode: 0));
      }
    });
    return completer.future;
  }

  bool _taskHasErrors(Task task) {
    final key = task.getMapKey();
    if (_taskErrors[key] ?? false) return true;
    for (final dependency in _taskDependencies[key] ?? const <String>[]) {
      if (_taskErrors[dependency] ?? false) return true;
    }
    return false;
  }

  void _cleanupTaskTracking(Task task) {
    final key = task.getMapKey();
    _taskErrors.remove(key);
    _taskDependencies.remove(key);
  }

  Future<TaskSummary> _getDependencyPromise(_ActiveTerminalData active) async {
    final props = active.task.configurationProperties;
    if (!(props.isBackground ?? false)) return active.promise;
    if (props.problemMatchers == null || props.problemMatchers!.isEmpty) {
      return active.promise;
    }
    if (active.state == TaskEventKind.inactive) return (exitCode: 0);
    return _createInactiveDependencyPromise(active.task);
  }

  Future<TaskSummary> _executeDependencyTask(
    Task task,
    TaskResolver resolver,
    Set<String> liveDependencies,
    Map<String, Future<TaskSummary>> encounteredTasks,
    Map<String, String>? alreadyResolved,
  ) {
    // A background task's dependents wait only for it to go inactive.
    if (!(task.configurationProperties.isBackground ?? false)) {
      return _executeTask(
        task,
        resolver,
        liveDependencies,
        encounteredTasks,
        alreadyResolved,
      );
    }
    final inactive = _createInactiveDependencyPromise(task);
    return Future.any([
      inactive,
      _executeTask(
        task,
        resolver,
        liveDependencies,
        encounteredTasks,
        alreadyResolved,
      ),
    ]);
  }

  ExtHostWorkspaceFolder? _folderOf(Task task) =>
      task.workspaceFolder ?? workspaceFolders?.call().firstOrNull;

  Future<TaskSummary> _executeCommand(
    Task task,
    Map<String, String> alreadyResolved,
  ) async {
    final folder = _folderOf(task);
    final info = taskSystemInfo?.call(folder);
    final variables = <String>{};
    _collectTaskVariables(variables, task);
    final resolved = await _resolveVariablesFromSet(
      info,
      folder,
      task,
      variables,
      alreadyResolved,
    );
    _fireTaskEvent(TaskEvent(TaskEventKind.acquiredInput, task: task));
    if (resolved != null && !_isTaskEmpty(task)) {
      return _executeInTerminal(
        task,
        _RunVariables(folder, info, resolved, variableResolver),
        folder,
      );
    }
    // The extension host's executions are updated.
    _fireTaskEvent(TaskEvent(TaskEventKind.end, task: task));
    return (exitCode: 0);
  }

  bool _isTaskEmpty(Task task) {
    final command = task.command;
    if (command == null) return true;
    final isCustomExecution = command.runtime == RuntimeType.customExecution;
    return !(command.runtime != null &&
        (isCustomExecution || command.name != null));
  }

  Future<Map<String, String>?> _resolveVariablesFromSet(
    TaskSystemInfo? info,
    ExtHostWorkspaceFolder? folder,
    Task task,
    Set<String> variables,
    Map<String, String> alreadyResolved,
  ) async {
    final command = task.command!;
    final isProcess = command.runtime == RuntimeType.process;
    final options = command.options;
    final cwd = options?.cwd;
    String? envPath;
    for (final MapEntry(:key, :value) in (options?.env ?? const {}).entries) {
      if (key.toLowerCase() == 'path') {
        envPath = value;
        break;
      }
    }
    final unresolved = alreadyResolved.isEmpty
        ? variables
        : {
            for (final variable in variables)
              if (!alreadyResolved.containsKey(
                variable.substring(2, variable.length - 1),
              ))
                variable,
          };
    if (info != null && folder != null) {
      final resolved = await info.resolveVariables(
        folder,
        unresolved,
        process: info.platform == TaskPlatform.windows && isProcess
            ? (name: commandStringValue(command.name), cwd: cwd, path: envPath)
            : null,
      );
      if (resolved == null) return null;
      for (final MapEntry(:key, :value) in resolved.variables.entries) {
        alreadyResolved.putIfAbsent(key, () => value);
      }
      final result = Map.of(alreadyResolved);
      if (isProcess) {
        var process = commandStringValue(command.name);
        if (info.platform == TaskPlatform.windows) {
          process = await _resolveAndFindExecutable(
            info,
            folder,
            task,
            cwd,
            envPath,
          );
        }
        result[_processVarName] = process;
      }
      return result;
    }
    final values = await variableResolver.resolveWithInteraction(
      folder,
      unresolved.toList(),
    );
    if (values == null) return null;
    for (final MapEntry(:key, :value) in values.entries) {
      alreadyResolved.putIfAbsent(key, () => value);
    }
    final result = Map.of(alreadyResolved);
    if (isProcess) {
      result[_processVarName] = _platform == TaskPlatform.windows
          ? await _resolveAndFindExecutable(info, folder, task, cwd, envPath)
          : await variableResolver.resolveAsync(
              folder,
              commandStringValue(command.name),
            );
    }
    return result;
  }

  Future<String> _resolveAndFindExecutable(
    TaskSystemInfo? info,
    ExtHostWorkspaceFolder? folder,
    Task task,
    String? cwd,
    String? envPath,
  ) async {
    final command = await variableResolver.resolveAsync(
      folder,
      commandStringValue(task.command!.name),
    );
    cwd = cwd == null ? null : await variableResolver.resolveAsync(folder, cwd);
    final paths = envPath == null
        ? null
        : await Future.wait([
            for (final path in envPath.split(
              _platform == TaskPlatform.windows ? ';' : ':',
            ))
              variableResolver.resolveAsync(folder, path),
          ]);
    final found = await info?.findExecutable?.call(command, cwd, paths);
    if (found != null) return found;
    if (p.isAbsolute(command)) return command;
    return p.join(cwd ?? '', command);
  }

  Future<TaskSummary> _executeInTerminal(
    Task task,
    _RunVariables resolver,
    ExtHostWorkspaceFolder? folder,
  ) async {
    final presentation = task.command!.presentation!;
    TerminalInstance? terminal;
    Future<TaskSummary> promise;
    final mapKey = task.getMapKey();
    if (task.configurationProperties.isBackground ?? false) {
      final problemMatchers = await _resolveMatchers(
        resolver,
        task.configurationProperties.problemMatchers,
      );
      final collector = WatchingProblemCollector(
        problemMatchers,
        markers,
        isOpen: isOpen,
        files: files,
      );
      if (problemMatchers.isNotEmpty && !collector.isWatching) {
        _log(
          'Task ${task.label} is a background task but uses a problem '
          'matcher without a background pattern',
        );
      }
      var eventCounter = 0;
      final stateListener = collector.onDidStateChange.listen((event) {
        if (event.kind ==
            ProblemCollectorEventKind.backgroundProcessingBegins) {
          eventCounter++;
          _busyTasks[mapKey] = task;
          _fireTaskEvent(
            TaskEvent(
              TaskEventKind.active,
              task: task,
              terminalId: terminal?.id,
            ),
          );
        } else {
          eventCounter--;
          _busyTasks.remove(mapKey);
          if (event.capturedVariables case final captured?) {
            _capturedTaskVariables.addAll(captured);
          }
          _fireTaskEvent(
            TaskEvent(
              TaskEventKind.inactive,
              task: task,
              terminalId: terminal?.id,
            ),
          );
          if (eventCounter == 0) {
            if (_hasErrors(collector)) {
              _taskErrors[mapKey] = true;
              _fireTaskEvent(
                TaskEvent(
                  TaskEventKind.problemMatcherFoundErrors,
                  task: task,
                  terminalId: terminal?.id,
                ),
              );
              if (presentation.revealProblems == RevealProblemKind.onProblem) {
                openProblems?.call();
              } else if (presentation.reveal == RevealKind.silent &&
                  terminal != null) {
                terminals().show(terminal, preserveFocus: true);
              }
            } else {
              _fireTaskEvent(
                TaskEvent(
                  TaskEventKind.problemMatcherEnded,
                  task: task,
                  hasErrors: _taskHasErrors(task),
                  terminalId: terminal?.id,
                ),
              );
            }
          }
        }
      });
      collector.aboutToStart();
      terminal = await _createTerminal(task, resolver, folder);
      var processStartedSignaled = false;
      final ready = terminal.onProcessReady.listen((pid) {
        if (processStartedSignaled) return;
        processStartedSignaled = true;
        _fireTaskEvent(
          TaskEvent(
            TaskEventKind.processStarted,
            task: task,
            terminalId: terminal!.id,
            processId: pid,
          ),
        );
      });
      _fireTaskEvent(
        TaskEvent(
          TaskEventKind.start,
          task: task,
          terminalId: terminal.id,
          resolvedVariables: resolver.values,
        ),
      );
      StreamSubscription<String>? onData;
      Timer? delayer;
      if (problemMatchers.isNotEmpty) {
        // microsoft/vscode#174511: no ProblemMatcherStarted here.
        onData = terminal.onLineData.listen((line) {
          collector.processLine(line);
          delayer?.cancel();
          delayer = Timer(const Duration(seconds: 3), collector.forceDelivery);
        });
      }
      final bound = terminal;
      promise = _whenExited(bound).then((exit) async {
        delayer?.cancel();
        unawaited(onData?.cancel());
        unawaited(ready.cancel());
        _busyTasks.remove(mapKey);
        if (identical(_activeTasks[mapKey]?.terminal, bound)) {
          _removeFromActiveTasks(mapKey);
        }
        _fireTaskEvent(const TaskEvent(TaskEventKind.changed));
        if (!exit.disposed) _keepForReuse(task, bound);
        if (presentation.reveal == RevealKind.silent &&
            (exit.code != 0 || _hasErrors(collector)) &&
            !exit.disposed) {
          terminals().show(bound, preserveFocus: true);
        }
        await collector.idle;
        collector
          ..done()
          ..dispose();
        if (!processStartedSignaled) {
          processStartedSignaled = true;
          _fireTaskEvent(
            TaskEvent(
              TaskEventKind.processStarted,
              task: task,
              terminalId: bound.id,
              processId: bound.pty?.pid ?? -1,
            ),
          );
        }
        _fireTaskEvent(
          TaskEvent(
            TaskEventKind.processEnded,
            task: task,
            terminalId: bound.id,
            exitCode: exit.code,
          ),
        );
        for (var i = 0; i < eventCounter; i++) {
          _fireTaskEvent(
            TaskEvent(TaskEventKind.inactive, task: task, terminalId: bound.id),
          );
        }
        eventCounter = 0;
        _fireTaskEvent(TaskEvent(TaskEventKind.end, task: task));
        unawaited(stateListener.cancel());
        return (exitCode: exit.code);
      });
    } else {
      terminal = await _createTerminal(task, resolver, folder);
      _fireTaskEvent(
        TaskEvent(
          TaskEventKind.start,
          task: task,
          terminalId: terminal.id,
          resolvedVariables: resolver.values,
        ),
      );
      _busyTasks[mapKey] = task;
      _fireTaskEvent(
        TaskEvent(TaskEventKind.active, task: task, terminalId: terminal.id),
      );
      final problemMatchers = await _resolveMatchers(
        resolver,
        task.configurationProperties.problemMatchers,
      );
      final collector = StartStopProblemCollector(
        problemMatchers,
        markers,
        isOpen: isOpen,
        files: files,
      );
      final bound = terminal;
      final stateListener = collector.onDidStateChange.listen((event) {
        if (event.kind ==
            ProblemCollectorEventKind.backgroundProcessingBegins) {
          _fireTaskEvent(
            TaskEvent(
              TaskEventKind.problemMatcherStarted,
              task: task,
              terminalId: bound.id,
            ),
          );
        }
      });
      var processStartedSignaled = false;
      final ready = terminal.onProcessReady.listen((pid) {
        if (processStartedSignaled) return;
        processStartedSignaled = true;
        _fireTaskEvent(
          TaskEvent(
            TaskEventKind.processStarted,
            task: task,
            terminalId: bound.id,
            processId: pid,
          ),
        );
      });
      final onData = terminal.onLineData.listen(collector.processLine);
      promise = _whenExited(bound).then((exit) async {
        if (identical(_activeTasks[mapKey]?.terminal, bound)) {
          _removeFromActiveTasks(mapKey);
        }
        _fireTaskEvent(const TaskEvent(TaskEventKind.changed));
        if (!exit.disposed) _keepForReuse(task, bound);
        // microsoft/vscode#92868: the last lines are parsed.
        await Future<void>.delayed(const Duration(milliseconds: 100));
        unawaited(onData.cancel());
        unawaited(ready.cancel());
        await collector.idle;
        collector.done();
        unawaited(stateListener.cancel());
        final hasErrors = _hasErrors(collector);
        if (presentation.revealProblems == RevealProblemKind.onProblem &&
            collector.numberOfMatches > 0) {
          openProblems?.call();
        } else if (presentation.reveal == RevealKind.silent &&
            (exit.code != 0 || hasErrors) &&
            !exit.disposed) {
          terminals().show(bound, preserveFocus: true);
        }
        collector.dispose();
        if (!processStartedSignaled) {
          processStartedSignaled = true;
          _fireTaskEvent(
            TaskEvent(
              TaskEventKind.processStarted,
              task: task,
              terminalId: bound.id,
              processId: bound.pty?.pid ?? -1,
            ),
          );
        }
        _fireTaskEvent(
          TaskEvent(
            TaskEventKind.processEnded,
            task: task,
            terminalId: bound.id,
            exitCode: exit.code,
          ),
        );
        _busyTasks.remove(mapKey);
        _fireTaskEvent(
          TaskEvent(TaskEventKind.inactive, task: task, terminalId: bound.id),
        );
        if (hasErrors) {
          _taskErrors[mapKey] = true;
          _fireTaskEvent(
            TaskEvent(
              TaskEventKind.problemMatcherFoundErrors,
              task: task,
              terminalId: bound.id,
            ),
          );
        } else {
          _fireTaskEvent(
            TaskEvent(
              TaskEventKind.problemMatcherEnded,
              task: task,
              hasErrors: _taskHasErrors(task),
              terminalId: bound.id,
            ),
          );
        }
        _fireTaskEvent(
          TaskEvent(TaskEventKind.end, task: task, terminalId: bound.id),
        );
        _cleanupTaskTracking(task);
        return (exitCode: exit.code);
      });
    }
    if (presentation.revealProblems == RevealProblemKind.always) {
      openProblems?.call();
    } else if ((presentation.focus ?? false) ||
        presentation.reveal == RevealKind.always) {
      terminals().show(terminal, preserveFocus: !(presentation.focus ?? false));
    }
    final active = _activeTasks[mapKey];
    if (active != null) active.terminal = terminal;
    _fireTaskEvent(const TaskEvent(TaskEventKind.changed));
    return promise;
  }

  static bool _hasErrors(AbstractProblemCollector collector) =>
      collector.numberOfMatches > 0 &&
      (collector.maxMarkerSeverity?.value ?? 0) >= MarkerSeverity.error.value;

  /// When [terminal]'s process exits, or the terminal goes first.
  Future<({int? code, bool disposed})> _whenExited(TerminalInstance terminal) {
    final completer = Completer<({int? code, bool disposed})>();
    late final StreamSubscription<int?> exit;
    late final StreamSubscription<TerminalInstance> disposed;
    void done(({int? code, bool disposed}) result) {
      if (completer.isCompleted) return;
      unawaited(exit.cancel());
      unawaited(disposed.cancel());
      completer.complete(result);
    }

    exit = terminal.onProcessExit.listen(
      (code) => done((code: code, disposed: false)),
    );
    disposed = terminals().onDidDispose.listen((instance) {
      if (identical(instance, terminal)) {
        done((code: terminal.exitCode, disposed: true));
      }
    });
    return completer.future;
  }

  void _keepForReuse(Task task, TerminalInstance terminal) {
    final key = task.getMapKey();
    switch (task.command!.presentation!.panel) {
      case PanelKind.dedicated:
        _sameTaskTerminals[key] = terminal.id;
      case PanelKind.shared:
        _idleTaskTerminals = {
          key: terminal.id,
          for (final MapEntry(key: k, :value) in _idleTaskTerminals.entries)
            if (k != key) k: value,
        };
      case PanelKind.newPanel || null:
        break;
    }
  }

  String _createTerminalName(Task task) =>
      task.configurationProperties.name ?? '';

  /// `getWaitOnExitValue`.
  static String? Function(int? exitCode)? _waitOnExit(
    PresentationOptions presentation,
    ConfigurationProperties props,
  ) {
    if (presentation.close == null || presentation.close == false) {
      if (presentation.reveal != RevealKind.never ||
          !(props.isBackground ?? false) ||
          presentation.close == false) {
        if (presentation.panel == PanelKind.newPanel) {
          return _waitOnExitSequence('Press any key to close the terminal.');
        } else if (presentation.showReuseMessage ?? false) {
          return _waitOnExitSequence(
            'Terminal will be reused by tasks, press any key to close it.',
          );
        }
        return (_) => null;
      }
    }
    return presentation.close ?? false ? null : (_) => null;
  }

  static String? Function(int?) _waitOnExitSequence(String message) =>
      (code) => '${_vscodeSequence('D', '${code ?? ''}')}$message';

  static String _vscodeSequence(String code, [String? data]) =>
      '\x1b]633;$code${data != null && data.isNotEmpty ? ';$data' : ''}\x07';

  /// `serializeVSCodeOscMessage`.
  static String _serialize(String message) => message.replaceAllMapped(
    RegExp(r'[\\;\x00-\x20]'),
    (m) => m[0] == r'\'
        ? r'\\'
        : '\\x${m[0]!.codeUnitAt(0).toRadixString(16).padLeft(2, '0')}',
  );

  static String _startSequence(String? cwd) =>
      _vscodeSequence('P', 'HasRichCommandDetection=True') +
      _vscodeSequence('A') +
      _vscodeSequence('P', 'Task=True') +
      (cwd != null ? _vscodeSequence('P', 'Cwd=$cwd') : '') +
      _vscodeSequence('B');

  static String _outputSequence(({String commandLine, String nonce})? info) =>
      (info != null
          ? _vscodeSequence(
              'E',
              '${_serialize(info.commandLine)};${info.nonce}',
            )
          : '') +
      _vscodeSequence('C');

  String _nonce() =>
      [for (var i = 0; i < 32; i++) _random.nextInt(16).toRadixString(16)]
          .join();

  Future<TerminalShell?> _defaultShell() async {
    final profiles = terminals().profiles;
    await profiles.refresh();
    final name = profiles.defaultProfileSetting;
    return (name == null ? null : profiles.profileNamed(name)?.shell) ??
        profiles.systemShell;
  }

  Future<TerminalLaunchConfig?> _createShellLaunchConfig(
    Task task,
    ExtHostWorkspaceFolder? folder,
    _RunVariables resolver,
    TaskPlatform platform,
    CommandOptions options,
    Object command,
    List<Object> args,
    String? Function(int?)? waitOnExit,
    PresentationOptions presentation,
  ) async {
    final isShellCommand = task.command!.runtime == RuntimeType.shell;
    final name = _createTerminalName(task);
    final originalCommand = task.command!.name;
    String? cwd;
    if (options.cwd case final optionsCwd?) {
      cwd = optionsCwd;
      if (!p.isAbsolute(cwd) && folder != null && folder.uri.scheme == 'file') {
        cwd = p.join(folder.uri.fsPath(), cwd);
      }
      cwd = p.normalize(cwd);
    }
    String executable;
    List<String> arguments;
    Map<String, String?>? env;
    String? initialText;
    var initialTextNewLine = true;
    String? nonce;
    if (isShellCommand) {
      final defaultShell = await _defaultShell();
      if (defaultShell == null) return null;
      executable = defaultShell.executable;
      List<String>? shellArgs = defaultShell.arguments;
      var shellSpecified = false;
      final shellOptions = task.command!.options?.shell;
      if (shellOptions != null) {
        if (shellOptions.executable case final shellExecutable?) {
          // Clear out the args so that we don't end up with mismatched args.
          if (shellExecutable != executable) shellArgs = null;
          executable = await resolver.resolve(shellExecutable);
          shellSpecified = true;
        }
        if (shellOptions.args case final configured?) {
          shellArgs = [
            for (final arg in configured) await resolver.resolve(arg),
          ];
        }
      }
      shellArgs ??= [];
      final toAdd = <String>[];
      final basename = p.posix
          .basename(executable.replaceAll(r'\', '/'))
          .toLowerCase();
      final commandLine = _buildShellCommandLine(
        platform,
        basename,
        shellOptions,
        command,
        originalCommand,
        args,
      );
      var windowsShellArgs = false;
      if (platform == TaskPlatform.windows) {
        windowsShellArgs = true;
        if (basename == 'powershell.exe' || basename == 'pwsh.exe') {
          if (!shellSpecified) toAdd.add('-Command');
        } else if (basename == 'bash.exe' || basename == 'zsh.exe') {
          windowsShellArgs = false;
          if (!shellSpecified) toAdd.add('-c');
        } else if (basename == 'wsl.exe') {
          if (!shellSpecified) toAdd.add('-e');
        } else if (basename == 'nu.exe') {
          if (!shellSpecified) toAdd.add('-c');
        } else if (!shellSpecified) {
          toAdd.addAll(['/d', '/c']);
        }
      } else if (!shellSpecified) {
        toAdd.add('-c');
      }
      final combined = _addAllArgument(toAdd, shellArgs)..add(commandLine);
      nonce = _nonce();
      final info = (commandLine: commandLine, nonce: nonce);
      arguments = windowsShellArgs ? [combined.join(' ')] : combined;
      if (presentation.echo ?? false) {
        initialText =
            _startSequence(cwd) +
            formatMessageForTerminal(
              'Executing task: $commandLine',
              excludeLeadingNewLine: true,
            ) +
            _outputSequence(info);
      } else {
        initialText = _startSequence(cwd) + _outputSequence(info);
        initialTextNewLine = false;
      }
    } else {
      final processName = await resolver.resolve(
        await resolver.resolve('\${$_processVarName}'),
      );
      executable = processName;
      arguments = [for (final arg in args) commandStringValue(arg)];
      if (presentation.echo ?? false) {
        initialText =
            _startSequence(cwd) +
            formatMessageForTerminal(
              'Executing task: $executable ${arguments.join(' ')}',
              excludeLeadingNewLine: true,
            ) +
            _outputSequence(null);
      } else {
        initialText = _startSequence(cwd) + _outputSequence(null);
        initialTextNewLine = false;
      }
    }
    if (options.env case final optionsEnv?) env = {...optionsEnv};
    return TerminalLaunchConfig(
      name: name,
      type: _taskTerminalType,
      executable: executable,
      arguments: arguments,
      cwd: cwd,
      env: env,
      waitOnExit: waitOnExit,
      initialText: initialText,
      initialTextNewLine: initialTextNewLine,
      isFeatureTerminal: true,
      shellIntegrationNonce: nonce,
    );
  }

  static List<String> _addAllArgument(
    List<String> shellCommandArgs,
    List<String> configuredShellArgs,
  ) {
    final combined = [...configuredShellArgs];
    for (final element in shellCommandArgs) {
      var shouldAdd = true;
      for (final (index, arg) in configuredShellArgs.indexed) {
        if (arg.toLowerCase() == element &&
            configuredShellArgs.length > index + 1) {
          // Only if not all of the following arguments begin with "-".
          if (configuredShellArgs
              .sublist(index + 1)
              .every((a) => a.startsWith('-'))) {
            shouldAdd = false;
            break;
          }
        } else if (arg.toLowerCase() == element) {
          shouldAdd = false;
          break;
        }
      }
      if (shouldAdd) combined.add(element);
    }
    return combined;
  }

  Future<TerminalInstance> _createTerminal(
    Task task,
    _RunVariables resolver,
    ExtHostWorkspaceFolder? folder,
  ) async {
    final platform = resolver.info?.platform ?? _platform;
    final options = await _resolveOptions(resolver, task.command!.options);
    final presentation = task.command!.presentation!;
    final waitOnExit = _waitOnExit(presentation, task.configurationProperties);
    TerminalLaunchConfig? launch;
    if (task.command!.runtime == RuntimeType.customExecution) {
      final start = extensionPty?.call();
      if (start == null) {
        throw const TaskError(
          'The extension host that provides this task is not running.',
        );
      }
      launch = TerminalLaunchConfig(
        name: _createTerminalName(task),
        type: _taskTerminalType,
        waitOnExit: waitOnExit,
        initialText: presentation.echo ?? false
            ? formatMessageForTerminal(
                'Executing task: ${task.label}',
                excludeLeadingNewLine: true,
              )
            : null,
        isFeatureTerminal: true,
        customPty: start,
      );
    } else {
      final args = [
        for (final arg in task.command!.args ?? const <Object>[])
          await _resolveCommandString(resolver, arg),
      ];
      final command = await _resolveCommandString(
        resolver,
        task.command!.name!,
      );
      launch = await _createShellLaunchConfig(
        task,
        folder,
        resolver,
        platform,
        options,
        command,
        args,
        waitOnExit,
        presentation,
      );
      if (launch == null) {
        throw const TaskError('There is no shell to run the task in.');
      }
    }
    final group = presentation.group;
    final taskKey = task.getMapKey();
    _TerminalData? toReuse;
    if (presentation.panel == PanelKind.dedicated) {
      final id = _sameTaskTerminals.remove(taskKey);
      if (id != null) toReuse = _terminals[id];
    } else if (presentation.panel == PanelKind.shared) {
      // Always the terminal the same task used, else one of its group.
      var id = _idleTaskTerminals.remove(taskKey);
      if (id == null) {
        for (final MapEntry(key: taskId, value: idle) in [
          ..._idleTaskTerminals.entries,
        ]) {
          if (_terminals[idle]?.group == group) {
            id = _idleTaskTerminals.remove(taskId);
            break;
          }
        }
      }
      if (id != null) toReuse = _terminals[id];
    }
    if (toReuse != null && !toReuse.terminal.waitingForKey) toReuse = null;
    if (toReuse != null) {
      // The command line reported with the reused terminal's nonce.
      final reuseNonce = toReuse.nonce;
      final launchNonce = launch.shellIntegrationNonce;
      if (reuseNonce != null &&
          launchNonce != null &&
          launch.initialText != null) {
        launch = _withInitialText(
          launch,
          launch.initialText!.replaceAll(launchNonce, reuseNonce),
          reuseNonce,
        );
      }
      toReuse.terminal.reuse(launch);
      if (presentation.clear ?? false) toReuse.terminal.clearBuffer();
      toReuse.lastTask = taskKey;
      return toReuse.terminal;
    }
    final created = Completer<TerminalInstance>();
    _terminalCreationQueue = _terminalCreationQueue.then((_) {
      final terminal = terminals().create(config: launch);
      created.complete(terminal);
    });
    final terminal = await created.future;
    final data = _TerminalData(
      terminal,
      taskKey,
      group,
      launch.shellIntegrationNonce,
    );
    _terminals[terminal.id] = data;
    late final StreamSubscription<TerminalInstance> disposed;
    disposed = terminals().onDidDispose.listen((instance) {
      if (!identical(instance, terminal)) return;
      unawaited(disposed.cancel());
      _deleteTaskAndTerminal(terminal, data);
      _fireTaskEvent(
        TaskEvent(
          TaskEventKind.terminated,
          task: task,
          terminalId: terminal.id,
        ),
      );
    });
    return terminal;
  }

  static TerminalLaunchConfig _withInitialText(
    TerminalLaunchConfig c,
    String initialText,
    String nonce,
  ) => TerminalLaunchConfig(
    name: c.name,
    executable: c.executable,
    arguments: c.arguments,
    cwd: c.cwd,
    env: c.env,
    strictEnv: c.strictEnv,
    hideFromUser: c.hideFromUser,
    initialText: initialText,
    initialTextNewLine: c.initialTextNewLine,
    waitOnExit: c.waitOnExit,
    isFeatureTerminal: c.isFeatureTerminal,
    type: c.type,
    customPty: c.customPty,
    shellIntegrationNonce: nonce,
  );

  void _deleteTaskAndTerminal(TerminalInstance terminal, _TerminalData data) {
    _terminals.remove(terminal.id);
    _sameTaskTerminals.remove(data.lastTask);
    _idleTaskTerminals.remove(data.lastTask);
    final key = data.lastTask;
    if (identical(_activeTasks[key]?.terminal, terminal)) {
      _removeFromActiveTasks(key);
    }
    _busyTasks.remove(key);
  }

  /// `_buildShellCommandLine`.
  String _buildShellCommandLine(
    TaskPlatform platform,
    String shellExecutable,
    ShellConfiguration? shellOptions,
    Object command,
    Object? originalCommand,
    List<Object> args,
  ) {
    final basename = p.basenameWithoutExtension(shellExecutable).toLowerCase();
    final quoting =
        shellOptions?.quoting ??
        _shellQuotes[basename] ??
        (platform == TaskPlatform.windows
            ? _shellQuotes['powershell']!
            : _shellQuotes['bash']!);

    bool needsQuotes(String value) {
      if (value.length >= 2) {
        final first = value[0] == quoting.strong
            ? quoting.strong
            : value[0] == quoting.weak
            ? quoting.weak
            : null;
        if (first != null && first == value[value.length - 1]) return false;
      }
      String? quote;
      for (var i = 0; i < value.length; i++) {
        final ch = value[i];
        if (ch == quote) {
          quote = null;
        } else if (quote != null) {
          continue;
        } else if (ch == quoting.escapeChar) {
          i++;
        } else if (ch == quoting.strong || ch == quoting.weak) {
          quote = ch;
        } else if (ch == ' ') {
          return true;
        }
      }
      return false;
    }

    (String, bool) quote(String value, ShellQuoting kind) {
      if (kind == ShellQuoting.strong && quoting.strong != null) {
        return ('${quoting.strong}$value${quoting.strong}', true);
      } else if (kind == ShellQuoting.weak && quoting.weak != null) {
        return ('${quoting.weak}$value${quoting.weak}', true);
      } else if (kind == ShellQuoting.escape && quoting.escapeChar != null) {
        final escape = quoting.escapeChar!;
        final chars = quoting.charsToEscape;
        if (chars == null) return (value.replaceAll(' ', '$escape '), true);
        final buffer = StringBuffer();
        for (final ch in value.split('')) {
          // Upstream's character class also matches its ',' separators.
          if (chars.contains(ch) || ch == ',') buffer.write(escape);
          buffer.write(ch);
        }
        return (buffer.toString(), true);
      }
      return (value, false);
    }

    (String, bool) quoteIfNecessary(Object value) {
      if (value is String) {
        return needsQuotes(value)
            ? quote(value, ShellQuoting.strong)
            : (value, false);
      }
      final quoted = value as QuotedString;
      return quote(quoted.value, quoted.quoting);
    }

    // No args and a string command: the command as it is, unless resolving
    // its variables made it need quotes.
    if (args.isEmpty &&
        command is String &&
        (command == originalCommand ||
            needsQuotes(commandStringValue(originalCommand)))) {
      return command;
    }
    final result = <String>[];
    var (value, commandQuoted) = quoteIfNecessary(command);
    result.add(value);
    var argQuoted = false;
    for (final arg in args) {
      final (quotedArg, quoted) = quoteIfNecessary(arg);
      result.add(quotedArg);
      argQuoted = argQuoted || quoted;
    }
    var commandLine = result.join(' ');
    if (platform == TaskPlatform.windows) {
      if (basename == 'cmd' && commandQuoted && argQuoted) {
        commandLine = '"$commandLine"';
      } else if ((basename == 'powershell' || basename == 'pwsh') &&
          commandQuoted) {
        commandLine = '& $commandLine';
      }
    }
    return commandLine;
  }

  void _collectTaskVariables(Set<String> variables, Task task) {
    final command = task.command;
    if (command?.name != null) {
      _collectCommandVariables(variables, command!, task);
    }
    _collectMatcherVariables(
      variables,
      task.configurationProperties.problemMatchers,
    );
    if (command?.runtime == RuntimeType.customExecution) {
      Object? definition;
      if (task.isCustom) {
        definition = task.source.element;
      } else {
        definition = Map.of(task.definition?.properties ?? const {})
          ..remove('type');
      }
      _collectDefinitionVariables(variables, definition);
    }
  }

  void _collectDefinitionVariables(Set<String> variables, Object? definition) {
    if (definition is String) {
      _collectVariables(variables, definition);
    } else if (definition is List) {
      for (final element in definition) {
        _collectDefinitionVariables(variables, element);
      }
    } else if (definition is Map) {
      for (final value in definition.values) {
        _collectDefinitionVariables(variables, value);
      }
    }
  }

  void _collectCommandVariables(
    Set<String> variables,
    CommandConfiguration command,
    Task task,
  ) {
    if (command.runtime == RuntimeType.customExecution) return;
    _collectVariables(variables, commandStringValue(command.name));
    for (final arg in command.args ?? const <Object>[]) {
      _collectVariables(variables, commandStringValue(arg));
    }
    if (!(task.isContributed && task.source.scope == TaskScope.global)) {
      variables.add(r'${workspaceFolder}');
    }
    if (command.options case final options?) {
      if (options.cwd case final cwd?) _collectVariables(variables, cwd);
      for (final value in options.env?.values ?? const <String>[]) {
        _collectVariables(variables, value);
      }
      if (options.shell case final shell?) {
        if (shell.executable case final executable?) {
          _collectVariables(variables, executable);
        }
        for (final arg in shell.args ?? const <String>[]) {
          _collectVariables(variables, arg);
        }
      }
    }
  }

  ProblemMatcher? _matcherFor(Object value) {
    if (value is ProblemMatcher) return value;
    final name = value as String;
    return matchers.get(name.startsWith(r'$') ? name.substring(1) : name);
  }

  void _collectMatcherVariables(Set<String> variables, List<Object>? values) {
    for (final value in values ?? const <Object>[]) {
      final matcher = _matcherFor(value);
      switch (matcher?.filePrefix) {
        case final String prefix:
          _collectVariables(variables, prefix);
        case final SearchFileLocationArgs args:
          for (final path in [...args.include, ...args.exclude]) {
            _collectVariables(variables, path);
          }
      }
    }
  }

  static final _variableRegex = RegExp(r'\$\{(.*?)\}');

  void _collectVariables(Set<String> variables, String value) {
    for (final match in _variableRegex.allMatches(value)) {
      variables.add(match.group(0)!);
    }
  }

  Future<Object> _resolveCommandString(
    _RunVariables resolver,
    Object value,
  ) async => switch (value) {
    final QuotedString quoted => QuotedString(
      await resolver.resolve(quoted.value),
      quoted.quoting,
    ),
    _ => await resolver.resolve(value as String),
  };

  Future<List<ProblemMatcher>> _resolveMatchers(
    _RunVariables resolver,
    List<Object>? values,
  ) async {
    final result = <ProblemMatcher>[];
    for (final value in values ?? const <Object>[]) {
      final matcher = _matcherFor(value);
      if (matcher == null) {
        _log(
          "Problem matcher $value can't be resolved. The matcher will be "
          'ignored',
        );
        continue;
      }
      final uriProvider = resolver.info?.uriProvider;
      if (matcher.filePrefix == null && uriProvider == null) {
        result.add(matcher);
        continue;
      }
      final copy = matcher.copy();
      if (uriProvider != null) copy.uriProvider = uriProvider;
      switch (copy.filePrefix) {
        case final String prefix:
          copy.filePrefix = await resolver.resolve(prefix);
        case final SearchFileLocationArgs args:
          copy.filePrefix = SearchFileLocationArgs(
            include: [for (final x in args.include) await resolver.resolve(x)],
            exclude: [for (final x in args.exclude) await resolver.resolve(x)],
          );
      }
      result.add(copy);
    }
    return result;
  }

  Future<CommandOptions> _resolveOptions(
    _RunVariables resolver,
    CommandOptions? options,
  ) async {
    Future<String?> workspaceFolder() async {
      try {
        final value = await resolver.resolve(r'${workspaceFolder}');
        return value == r'${workspaceFolder}' ? null : value;
      } on Object {
        return null; // No workspace.
      }
    }

    if (options == null) return CommandOptions(cwd: await workspaceFolder());
    final result = CommandOptions(
      cwd: options.cwd != null
          ? await resolver.resolve(options.cwd!)
          : await workspaceFolder(),
    );
    if (options.env case final env?) {
      result.env = {
        for (final MapEntry(:key, :value) in env.entries)
          key: await resolver.resolve(value),
      };
    }
    return result;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_onDidStateChange.close());
  }
}
