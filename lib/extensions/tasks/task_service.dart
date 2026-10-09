/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The workspace's tasks: each folder's .vscode/tasks.json and the
// extensions' (their task providers, activated by `onTaskType:`), an
// extension's task merged with the tasks.json entry that customizes it;
// which task a label or a definition means; running one in the terminal
// task system (saving first as `task.saveBeforeRun` says, and as its
// `instancePolicy` says when it runs already), terminating, restarting and
// rerunning; and the Tasks commands (`workbench.action.tasks.*`).
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/contrib/tasks/browser/abstractTaskService.ts and
// src/vs/workbench/contrib/tasks/common/taskService.ts.
//
// Deviations:
// - Tasks are the folders' tasks.json only: no user tasks and no tasks of
//   a .code-workspace file; the 0.1.0 schema's tasks run in the terminal
//   as the 2.0.0 ones do (no legacy process engine).
// - Tasks are listed without waiting for the extension host to say which
//   executions it supports.
// - The task pick is one level (configured tasks, then detected ones), as
//   upstream's `task.quickOpen` slow picker; no recently used tasks, no
//   attach-a-problem-matcher prompt, no glob default build tasks, and
//   "Configure a Task" opens the folder's tasks.json (made from the
//   "Others" template when there is none) instead of offering templates.

import 'dart:async';
import 'dart:convert';

import 'package:bao_exthost/bao_exthost.dart';

import '../../ide/terminal/pty.dart';
import '../../ide/terminal/terminal_instance.dart';
import '../../ide/terminal/terminal_service.dart';
import '../host/init_data.dart';
import '../language/marker_service.dart';
import 'problem_matcher.dart';
import 'task_configuration.dart';
import 'tasks.dart';
import 'terminal_task_system.dart';

/// `ITaskSet`: what a provider gave, and its extension.
typedef TaskSet = ({List<Task> tasks, Map<String, Object?>? extension});

/// `ITaskProvider`: an extension host's task provider for one type.
abstract interface class TaskProvider {
  Future<TaskSet> provideTasks(Map<String, bool> validTypes);

  /// The extension's task [task] (a configuring one) customizes.
  Future<Task?> resolveTask(Task task);
}

/// `TaskRunSource`.
enum TaskRunSource { system, user, folderOpen, configurationChange, reconnect }

/// What the notifications say a task did.
enum TaskNoticeSeverity { info, warning, error }

/// A choice in a task pick.
final class TaskPickItem<T> {
  const TaskPickItem(
    this.label,
    this.value, {
    this.description,
    this.detail,
    this.separatorBefore,
  });

  final String label;
  final T value;
  final String? description;
  final String? detail;

  /// A separator's label before it.
  final String? separatorBefore;
}

/// What the task service needs of the window.
abstract interface class TaskServiceHost {
  List<ExtHostWorkspaceFolder> get workspaceFolders;

  /// [folder]'s .vscode/tasks.json: its value (null when there is none),
  /// or why it could not be read.
  Future<({Object? value, String? error})> readTasksJson(
    ExtHostWorkspaceFolder folder,
  );

  /// The extensions' descriptions, as the extension host scanned them.
  List<Map<String, Object?>> get extensions;
  Future<void> activateByEvent(String event);
  Object? setting(String key, {VsUri? resource});
  bool get workspaceTrusted;
  Future<bool> requestWorkspaceTrust(String message);
  bool get hasDirtyEditors;
  Future<void> saveAll();
  Future<bool> confirm(
    String message, {
    String? detail,
    required String primary,
    required String cancel,
  });
  void notify(TaskNoticeSeverity severity, String message);
  Future<T?> pick<T>(List<TaskPickItem<T>> items, {String? placeholder});

  /// The Tasks output channel.
  void appendOutput(String text);
  void showOutput();
  void openProblems();

  /// Opens [folder]'s tasks.json, made of [template] when there is none.
  Future<void> openTasksJson(ExtHostWorkspaceFolder folder, String template);
}

/// `IWorkspaceFolderTaskResult`.
final class WorkspaceFolderTasks {
  const WorkspaceFolderTasks(
    this.folder, {
    this.tasks,
    this.configurations,
    this.hasErrors = false,
  });

  final ExtHostWorkspaceFolder folder;

  /// tasks.json's own tasks (`set.tasks`).
  final List<Task>? tasks;

  /// tasks.json's customizations of extensions' tasks, by the `_key` of
  /// the task they customize (`configurations.byIdentifier`).
  final Map<String, Task>? configurations;
  final bool hasErrors;
}

/// `ITaskService` of the terminal task system.
final class TaskService {
  TaskService({
    required this.host,
    required TerminalService Function() terminals,
    required MarkerService markers,
    required this.variableResolver,
    Future<Pty> Function(TerminalInstance instance)? Function()? extensionPty,
    bool Function(VsUri resource)? isOpen,
    ProblemFileSystem? files,
    TaskPlatform? platform,
  }) {
    _system = TerminalTaskSystem(
      terminals: terminals,
      markers: markers,
      matchers: matchers,
      variableResolver: variableResolver,
      taskSystemInfo: _taskSystemInfo,
      extensionPty: extensionPty,
      workspaceFolders: () => host.workspaceFolders,
      isOpen: isOpen,
      files: files,
      log: host.appendOutput,
      openProblems: host.openProblems,
      platform: platform,
    );
    _systemEvents = _system.onDidStateChange.listen(_onDidStateChange.add);
  }

  final TaskServiceHost host;

  /// Resolves the tasks' variables (`IConfigurationResolverService`).
  final TaskVariableResolver variableResolver;
  final patterns = ProblemPatternRegistry();
  late final matchers = ProblemMatcherRegistry(patterns);
  final definitions = TaskDefinitionRegistry();
  late final TerminalTaskSystem _system;
  late final StreamSubscription<TaskEvent> _systemEvents;
  final _onDidStateChange = StreamController<TaskEvent>.broadcast(sync: true);

  final _providers = <int, TaskProvider>{};
  final _providerTypes = <int, String>{};
  var _handle = 0;
  final _taskSystemInfos = <String, TaskSystemInfo>{};
  final _ids = <String, TaskIdMap>{};

  Future<Map<String, WorkspaceFolderTasks>>? _workspaceTasks;
  final _inputs = <String, List<Map<String, Object?>>>{};
  List<Map<String, Object?>>? _registeredExtensions;
  bool _disposed = false;

  ({bool custom, bool shell, bool process}) _supportedExecutions = (
    custom: false,
    shell: false,
    process: false,
  );

  static const _runTaskActivation = 'onCommand:workbench.action.tasks.runTask';
  static const _providerTimeout = Duration(seconds: 5);

  /// `onDidStateChange`.
  Stream<TaskEvent> get onDidStateChange => _onDidStateChange.stream;

  /// The terminal task system, for what only it knows.
  TerminalTaskSystem get taskSystem => _system;

  /// Which executions the extension host supports
  /// (`registerSupportedExecutions`).
  ({bool custom, bool shell, bool process}) get supportedExecutions =>
      _supportedExecutions;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_systemEvents.cancel());
    _system.dispose();
    unawaited(_onDidStateChange.close());
  }

  //---- providers and task systems

  /// `registerTaskProvider`: returns what removes it.
  void Function() registerTaskProvider(TaskProvider provider, String type) {
    final handle = _handle++;
    _providers[handle] = provider;
    _providerTypes[handle] = type;
    return () {
      _providers.remove(handle);
      _providerTypes.remove(handle);
    };
  }

  /// `registerTaskSystem`: how [scheme]'s folders resolve variables.
  void registerTaskSystem(String scheme, TaskSystemInfo info) {
    _taskSystemInfos[scheme] = info;
  }

  void registerSupportedExecutions({bool? custom, bool? shell, bool? process}) {
    _supportedExecutions = (
      custom: custom ?? _supportedExecutions.custom,
      shell: shell ?? _supportedExecutions.shell,
      process: process ?? _supportedExecutions.process,
    );
  }

  TaskSystemInfo? _taskSystemInfo(ExtHostWorkspaceFolder? folder) =>
      _taskSystemInfos[folder?.uri.scheme ?? 'file'];

  //---- workspace tasks

  /// Reads tasks.json again when next asked (it, the folders or the
  /// extensions changed).
  void invalidateWorkspaceTasks() => _workspaceTasks = null;

  /// tasks.json's `inputs` of [folder] (for `${input:…}`), as last read.
  List<Map<String, Object?>>? inputsOf(VsUri? folder) {
    if (folder != null) return _inputs[folder.toString()];
    final first = host.workspaceFolders.firstOrNull;
    return first == null ? null : _inputs[first.uri.toString()];
  }

  /// The extensions' `problemPatterns`, `problemMatchers` and
  /// `taskDefinitions`, when they changed.
  void _updateRegistries() {
    final extensions = host.extensions;
    if (identical(extensions, _registeredExtensions)) return;
    _registeredExtensions = extensions;
    final errors = <String>[];
    List<Object?> contributions(String point) => [
      for (final extension in extensions)
        if (extension['contributes'] case final Map contributes)
          if (contributes[point] case final List list) ...list,
    ];
    patterns.setContributions(contributions('problemPatterns'), errors: errors);
    matchers.setContributions(contributions('problemMatchers'), errors: errors);
    definitions.setExtensions(extensions);
    for (final error in errors) {
      host.appendOutput('$error\n');
    }
  }

  /// `getWorkspaceTasks`: each folder's, by its uri.
  Future<Map<String, WorkspaceFolderTasks>> getWorkspaceTasks() =>
      _workspaceTasks ??= _computeWorkspaceTasks();

  Future<Map<String, WorkspaceFolderTasks>> _computeWorkspaceTasks() async {
    _updateRegistries();
    final folders = host.workspaceFolders;
    final results = await Future.wait([
      for (final folder in folders) _computeWorkspaceFolderTasks(folder),
    ]);
    return {for (final result in results) result.folder.uri.toString(): result};
  }

  Future<WorkspaceFolderTasks> _computeWorkspaceFolderTasks(
    ExtHostWorkspaceFolder folder,
  ) async {
    final key = folder.uri.toString();
    final read = await host.readTasksJson(folder);
    if (read.error != null) {
      _inputs.remove(key);
      _log(
        'Error: The content of the tasks json in ${folder.name} has syntax '
        'errors. Please correct them before executing a task.',
      );
      host.showOutput();
      return WorkspaceFolderTasks(folder, hasErrors: true);
    }
    final config = read.value;
    if (config is! Map) {
      _inputs.remove(key);
      return WorkspaceFolderTasks(folder);
    }
    final configuration = config.cast<String, Object?>();
    _inputs[key] = [
      for (final input in configuration['inputs'] as List? ?? const [])
        if (input is Map) input.cast<String, Object?>(),
    ];
    final info = _taskSystemInfo(folder);
    final result = parseTaskConfiguration(
      configuration,
      TaskParseContext(
        workspaceFolder: folder,
        patterns: patterns,
        matchers: matchers,
        definitions: definitions,
        ids: _ids.putIfAbsent(key, TaskIdMap.new),
        platform: info?.platform,
        schemaVersion2: configuration['version'] != '0.1.0',
      ),
    );
    for (final message in [...result.errors, ...result.warnings]) {
      _log(message);
    }
    if (result.errors.isNotEmpty) host.showOutput();
    return WorkspaceFolderTasks(
      folder,
      tasks: result.custom,
      configurations: result.configured.isEmpty
          ? null
          : {for (final task in result.configured) task.definition!.key: task},
      hasErrors: result.errors.isNotEmpty,
    );
  }

  /// `_findWorkspaceTasks`: tasks.json's tasks and customizations
  /// [predicate] takes.
  Future<List<Task>> _findWorkspaceTasks(
    bool Function(Task task, ExtHostWorkspaceFolder folder) predicate,
  ) async {
    final result = <Task>[];
    for (final folderTasks in (await getWorkspaceTasks()).values) {
      for (final task in folderTasks.configurations?.values ?? const <Task>[]) {
        if (predicate(task, folderTasks.folder)) result.add(task);
      }
      for (final task in folderTasks.tasks ?? const <Task>[]) {
        if (predicate(task, folderTasks.folder)) result.add(task);
      }
    }
    return result;
  }

  Future<List<Task>> _findWorkspaceTasksInGroup(
    TaskGroup group, {
    required bool isDefault,
  }) => _findWorkspaceTasks((task, _) {
    final taskGroup = task.configurationProperties.group;
    if (taskGroup == null) return false;
    return taskGroup.id == group.id && (!isDefault || taskGroup.isDefaultTask);
  });

  //---- all tasks

  Future<bool> _trust() async {
    if (host.workspaceTrusted) return true;
    return host.requestWorkspaceTrust(
      'Listing and running tasks requires that some of the files in this '
      'workspace be executed as code.',
    );
  }

  bool get _isProvideTasksEnabled => host.setting('task.autoDetect') == 'on';

  Future<void> _activateTaskProviders(String? type) async {
    _updateRegistries();
    final events = [
      _runTaskActivation,
      if (type != null)
        'onTaskType:$type'
      else
        for (final definition in definitions.all)
          'onTaskType:${definition.taskType}',
    ];
    await Future.wait([
      for (final event in events)
        host.activateByEvent(event).catchError((Object _) {}),
    ]).timeout(_providerTimeout, onTimeout: () => const []);
  }

  /// `_getGroupedTasks`: every task, by its folder's uri.
  Future<Map<String, List<Task>>> getGroupedTasks({
    String? type,
    bool waitToActivate = false,
  }) async {
    if (!waitToActivate) await _activateTaskProviders(type);
    _updateRegistries();
    final validTypes = <String, bool>{
      for (final definition in definitions.all) definition.taskType: true,
      'shell': true,
      'process': true,
    };
    final contributedSets = <TaskSet>[];
    if (_isProvideTasksEnabled && _providers.isNotEmpty) {
      await Future.wait(<Future<void>>[
        for (final MapEntry(key: handle, value: provider) in [
          ..._providers.entries,
        ])
          if (type == null || type == _providerTypes[handle])
            provider
                .provideTasks(validTypes)
                .then<void>(
                  (set) {
                    final providerType = _providerTypes[handle];
                    for (final task in set.tasks) {
                      if (task.type != providerType) {
                        _log(
                          'The task provider for "$providerType" tasks '
                          'unexpectedly provided a task of type '
                          '"${task.type}".',
                        );
                        if (task.type != 'shell' && task.type != 'process') {
                          host.showOutput();
                        }
                        break;
                      }
                    }
                    contributedSets.add(set);
                  },
                  onError: (Object error) {
                    final message = _messageOf(error);
                    if (message != null) {
                      _log('Error: $message');
                    } else {
                      _log(
                        'Unknown error received while collecting tasks '
                        'from providers.',
                      );
                    }
                    host.showOutput();
                  },
                )
                .timeout(_providerTimeout, onTimeout: () {}),
      ]);
    }

    final result = <String, List<Task>>{};
    final contributed = <String, List<Task>>{};
    for (final set in contributedSets) {
      for (final task in set.tasks) {
        final folder = task.workspaceFolder;
        if (folder != null) {
          contributed.putIfAbsent(folder.uri.toString(), () => []).add(task);
        }
      }
    }
    final Map<String, WorkspaceFolderTasks> workspaceTasks;
    try {
      workspaceTasks = await getWorkspaceTasks();
    } on Object {
      // Without tasks.json, the contributed tasks at least.
      return contributed;
    }
    await Future.wait([
      for (final MapEntry(:key, value: folderTasks) in workspaceTasks.entries)
        _addCustomTasks(
          key,
          folderTasks,
          type,
          result,
          contributed[key] ?? const [],
          waitToActivate,
        ),
    ]);
    // Folders without tasks.json still have the extensions' tasks.
    for (final MapEntry(:key, :value) in contributed.entries) {
      if (!workspaceTasks.containsKey(key)) {
        result.putIfAbsent(key, () => []).addAll(value);
      }
    }
    return result;
  }

  /// `_getCustomTaskPromises` for one folder.
  Future<void> _addCustomTasks(
    String key,
    WorkspaceFolderTasks folderTasks,
    String? type,
    Map<String, List<Task>> result,
    List<Task> contributed,
    bool waitToActivate,
  ) async {
    final tasks = result.putIfAbsent(key, () => []);
    final custom = folderTasks.tasks;
    if (custom == null) {
      tasks.addAll(contributed);
      return;
    }
    final configurations = folderTasks.configurations;
    if (configurations == null) {
      tasks
        ..addAll(custom)
        ..addAll(contributed);
      return;
    }
    final unused = {...configurations.keys};
    for (final task in contributed) {
      if (!task.isContributed) continue;
      final configuring = configurations[task.definition!.key];
      if (configuring != null) {
        unused.remove(task.definition!.key);
        tasks.add(createCustomTask(task, configuring));
      } else {
        tasks.add(task);
      }
    }
    tasks.addAll(custom);
    await Future.wait([
      for (final value in unused)
        _resolveUnused(configurations[value]!, type, tasks, waitToActivate),
    ]);
  }

  Future<void> _resolveUnused(
    Task configuring,
    String? type,
    List<Task> tasks,
    bool waitToActivate,
  ) async {
    if (type != null && type != configuring.definition!.type) return;
    for (final MapEntry(key: handle, value: provider) in [
      ..._providers.entries,
    ]) {
      if (configuring.type != _providerTypes[handle]) continue;
      try {
        final resolved = await provider.resolveTask(configuring);
        if (resolved != null && resolved.id == configuring.id) {
          tasks.add(createCustomTask(resolved, configuring));
          return;
        }
      } on Object {
        // The task could not be provided by any of the providers.
      }
    }
    if (!waitToActivate) {
      _log(
        "Error: The ${configuring.definition!.type} task detection didn't "
        'contribute a task for the following configuration:\n'
        '${const JsonEncoder.withIndent('    ').convert(configuring.source.element)}\n'
        'The task will be ignored.',
      );
    }
  }

  /// `tasks`: every task, or those of [type].
  Future<List<Task>> tasks({String? type}) async {
    if (!await _trust()) return const [];
    return _applyFilter(type, await getGroupedTasks(type: type));
  }

  static List<Task> _applyFilter(String? type, Map<String, List<Task>> map) {
    final all = [for (final tasks in map.values) ...tasks];
    if (type == null) return all;
    return [
      for (final task in all)
        if (task.isContributed &&
            (task.definition?.type == type || task.source.label == type))
          task
        else if (task.isCustom &&
            (task.type == type || task.source.customizes?.type == type))
          task,
    ];
  }

  /// The key of a folder in the maps (`TaskMap.getKey`): a
  /// [ExtHostWorkspaceFolder]'s or [VsUri]'s string, or a string as is.
  static String folderKey(Object folder) => switch (folder) {
    final ExtHostWorkspaceFolder f => f.uri.toString(),
    final VsUri uri => uri.toString(),
    _ => '$folder',
  };

  /// `getTask`: the task [identifier] (a label, an identifier or a
  /// definition) means in [folder].
  Future<Task?> getTask(
    Object folder,
    Object identifier, {
    bool compareId = false,
    String? type,
  }) async {
    if (!await _trust()) return null;
    final key = _keyOf(identifier);
    if (key == null) return null;
    final requested = folderKey(folder);
    final matched = await _findWorkspaceTasks((task, workspaceFolder) {
      final taskFolder = workspaceFolder.uri.toString();
      if (taskFolder != requested && taskFolder != userTasksGroupKey) {
        return false;
      }
      return task.matches(key, compareId: compareId);
    });
    _sortExtensionLast(matched);
    if (matched.isNotEmpty) {
      final task = matched.first;
      return task.isConfiguring ? tryResolveTask(task) : task;
    }
    final map = await getGroupedTasks(type: type);
    final values = [
      ...?map[requested],
      ...?map[userTasksGroupKey],
    ].where((task) => task.matches(key, compareId: compareId)).toList();
    _sortExtensionLast(values);
    return values.firstOrNull;
  }

  static void _sortExtensionLast(List<Task> tasks) {
    final extension = [
      for (final t in tasks)
        if (t.source.kind == TaskSourceKind.extension) t,
    ];
    tasks
      ..removeWhere((t) => t.source.kind == TaskSourceKind.extension)
      ..addAll(extension);
  }

  /// A label as is, or a task identifier's [KeyedTaskIdentifier].
  Object? _keyOf(Object? identifier) => switch (identifier) {
    final String label => label,
    final KeyedTaskIdentifier keyed => keyed,
    final Map map when map['type'] is String =>
      definitions.createTaskIdentifier(
        map.cast<String, Object?>(),
        error: _log,
      ),
    _ => null,
  };

  /// `tryResolveTask`: the extension's task [configuring] customizes,
  /// with the customization.
  Future<Task?> tryResolveTask(Task configuring) async {
    if (!await _trust()) return null;
    await _activateTaskProviders(configuring.type);
    TaskProvider? matching;
    for (final MapEntry(key: handle, value: provider) in _providers.entries) {
      if (configuring.type == _providerTypes[handle]) {
        matching = provider;
        break;
      }
    }
    if (matching == null) return null;
    try {
      final resolved = await matching.resolveTask(configuring);
      if (resolved != null && resolved.id == configuring.id) {
        return createCustomTask(resolved, configuring);
      }
    } on Object {
      // Ignore errors. The task could not be provided by any of the
      // providers.
    }
    // Less efficient: all the provider's tasks.
    for (final task in await tasks(type: configuring.type)) {
      if (task.id == configuring.id) return createCustomTask(task, configuring);
    }
    return null;
  }

  /// `_createResolver`: a dependency's task, by its folder and label or
  /// definition.
  TaskResolver _createResolver([Map<String, List<Task>>? grouped]) {
    Map<
      String,
      ({
        Map<String, Task> label,
        Map<String, Task> identifier,
        Map<String, Task> taskIdentifier,
      })
    >?
    data;

    Future<Task?> quickResolve(String uri, Object identifier) async {
      final found = await _findWorkspaceTasks((task, _) {
        final taskUri = (task.isConfiguring || task.isCustom)
            ? task.workspaceFolder?.uri.toString()
            : null;
        if (taskUri != uri) return false;
        if (identifier is String) {
          return task.label == identifier ||
              task.configurationProperties.identifier == identifier;
        }
        final keyed = task.getDefinition(useSource: true);
        final search = _keyOf(identifier);
        return search is KeyedTaskIdentifier &&
            keyed != null &&
            search.key == keyed.key;
      });
      if (found.isEmpty) return null;
      final task = found.first;
      return task.isConfiguring ? tryResolveTask(task) : task;
    }

    Future<Task?> fullResolve(String uri, Object identifier) async {
      data ??= {
        for (final MapEntry(:key, value: tasks)
            in (grouped ?? await getGroupedTasks()).entries)
          key: (
            label: {for (final task in tasks) task.label: task},
            identifier: {
              for (final task in tasks)
                ?task.configurationProperties.identifier: task,
            },
            taskIdentifier: {
              for (final task in tasks)
                if (task.getDefinition(useSource: true) case final keyed?)
                  keyed.key: task,
            },
          ),
      };
      final folder = data![uri];
      if (folder == null) return null;
      if (identifier is String) {
        return folder.label[identifier] ?? folder.identifier[identifier];
      }
      final key = _keyOf(identifier);
      return key is KeyedTaskIdentifier ? folder.taskIdentifier[key.key] : null;
    }

    return (uri, identifier) async {
      final key = uri?.toString() ?? userTasksGroupKey;
      if (data == null && grouped == null) {
        return await quickResolve(key, identifier) ??
            await fullResolve(key, identifier);
      }
      return fullResolve(key, identifier);
    };
  }

  //---- running

  /// `getActiveTasks`.
  List<Task> getActiveTasks() => _system.getActiveTasks();

  /// `getBusyTasks`.
  List<Task> getBusyTasks() => _system.getBusyTasks();

  /// `extensionCallbackTaskComplete`.
  Future<void> extensionCallbackTaskComplete(Task task, int? result) =>
      _system.customExecutionComplete(task, result);

  /// `run`: null when the workspace is not trusted.
  Future<TaskSummary?> run(
    Task? task, {
    TaskRunSource source = TaskRunSource.system,
  }) async {
    if (!await _trust()) return null;
    if (task == null) {
      throw const TaskError(
        'Task to execute is undefined',
        code: 'taskNotFound',
      );
    }
    try {
      return await _executeTask(task, _createResolver(), source);
    } catch (error) {
      _handleError(error);
      rethrow;
    }
  }

  Future<bool> _saveBeforeRun() async {
    final setting = host.setting('task.saveBeforeRun');
    if (setting == 'never') return false;
    if (setting == 'prompt' && host.hasDirtyEditors) {
      final confirmed = await host.confirm(
        'Save all editors?',
        detail: 'Do you want to save all editors before running the task?',
        primary: 'Save',
        cancel: "Don't Save",
      );
      if (!confirmed) return false;
    }
    await host.saveAll();
    return true;
  }

  Future<TaskSummary> _executeTask(
    Task task,
    TaskResolver resolver,
    TaskRunSource source,
  ) async {
    var toRun = task;
    if (await _saveBeforeRun()) {
      invalidateWorkspaceTasks();
      final folder = task.workspaceFolder;
      final identifier = task.configurationProperties.identifier;
      final type = task.isCustom
          ? task.source.customizes?.type
          : task.isContributed
          ? task.type
          : null;
      // The save may have changed it; only a user's run finds it again.
      if (folder != null &&
          identifier != null &&
          source == TaskRunSource.user) {
        toRun = await getTask(folder, identifier, type: type) ?? task;
      }
    }
    return _handleExecuteResult(_system.run(toRun, resolver), source);
  }

  Future<TaskSummary> _handleExecuteResult(
    TaskExecuteResult result, [
    TaskRunSource? source,
  ]) async {
    if (result.kind == TaskExecuteKind.active) {
      if (source == TaskRunSource.folderOpen ||
          source == TaskRunSource.reconnect) {
        return result.promise;
      }
      _handleInstancePolicy(result.task, result.task.runOptions.instancePolicy);
    }
    return result.promise;
  }

  void _handleInstancePolicy(Task task, String? policy) {
    final terminal = _system.terminalOf(task);
    if (terminal != null) _system.terminals().show(terminal);
    final instances = [
      for (final t in getActiveTasks())
        if (t.id == task.id) t,
    ];
    switch (policy) {
      case 'terminateNewest':
        unawaited(_restart(instances.lastOrNull ?? task));
      case 'terminateOldest':
        unawaited(_restart(instances.firstOrNull ?? task));
      case 'silent':
        break;
      case 'warn':
        host.notify(
          TaskNoticeSeverity.warning,
          'The instance limit for this task has been reached.',
        );
      default:
        unawaited(() async {
          final entry = await _showQuickPick(
            instances,
            'Select an instance to terminate',
            defaultEntry: const TaskPickItem<Task?>(
              'No instance is currently running',
              null,
            ),
            sort: true,
          );
          if (entry != null) await _restart(entry);
        }());
    }
  }

  void _handleError(Object error) {
    var showOutput = true;
    if (error is TaskError) {
      host.notify(
        error.code == 'runningTask'
            ? TaskNoticeSeverity.warning
            : TaskNoticeSeverity.error,
        error.message,
      );
    } else if (error is String) {
      host.notify(TaskNoticeSeverity.error, error);
    } else {
      final message = _messageOf(error);
      host.notify(
        TaskNoticeSeverity.error,
        message ??
            'An error has occurred while running a task. See task log for '
                'details.',
      );
      showOutput = message == null;
    }
    if (showOutput) host.showOutput();
  }

  /// `terminate`.
  Future<({bool success, Task? task})> terminate(Task task) async {
    if (!await _trust()) return (success: true, task: null);
    return _system.terminate(task);
  }

  Future<List<({bool success, Task? task})>> terminateAll() =>
      _system.terminateAll();

  Future<void> _restart(Task task) async {
    final running = getActiveTasks().any(
      (t) => t.getMapKey() == task.getMapKey(),
    );
    if (running) {
      final response = await _system.terminate(task);
      if (!response.success) {
        host.notify(
          TaskNoticeSeverity.warning,
          'Failed to terminate and restart task '
          '${task.configurationProperties.name}',
        );
        return;
      }
    }
    try {
      final updated = await _findUpdatedTask(task);
      if (updated != null) {
        await run(updated);
      } else {
        final summary = await run(task);
        if (summary == null ||
            (summary.exitCode != null && summary.exitCode != 0)) {
          host.notify(
            TaskNoticeSeverity.warning,
            'Task ${task.configurationProperties.name} no longer exists or '
            'has been modified. Cannot restart.',
          );
        }
      }
    } on Object {
      // Surfaced already.
    }
  }

  Future<Task?> _findUpdatedTask(Task original) async {
    invalidateWorkspaceTasks();
    for (final folderTasks in (await getWorkspaceTasks()).values) {
      for (final task in folderTasks.tasks ?? const <Task>[]) {
        if (task.id == original.id) return task;
      }
      for (final task in folderTasks.configurations?.values ?? const <Task>[]) {
        if (task.id == original.id) return tryResolveTask(task);
      }
    }
    if (original.isContributed) {
      for (final task in await tasks(type: original.type)) {
        if (task.id == original.id) return task;
      }
    }
    return null;
  }

  //---- commands

  /// The Tasks commands, as `workbench.action.tasks.*` ids to handlers.
  Map<String, Future<Object?> Function(List<Object?> args)> get commands => {
    'workbench.action.tasks.runTask': (args) async {
      await runTaskCommand(args.firstOrNull);
      return null;
    },
    'workbench.action.tasks.reRunTask': (_) async {
      await reRunTaskCommand();
      return null;
    },
    'workbench.action.tasks.restartTask': (args) async {
      await restartTaskCommand(args.firstOrNull);
      return null;
    },
    'workbench.action.tasks.terminate': (args) async {
      await terminateCommand(args.firstOrNull);
      return null;
    },
    'workbench.action.tasks.build': (_) async {
      await runGroupCommand(TaskGroup.build);
      return null;
    },
    'workbench.action.tasks.test': (_) async {
      await runGroupCommand(TaskGroup.test);
      return null;
    },
    'workbench.action.tasks.showLog': (_) async {
      host.showOutput();
      return null;
    },
    'workbench.action.tasks.configureTaskRunner': (_) async {
      await configureTasks();
      return null;
    },
  };

  /// `_runTaskCommand`: [filter] a label, a task identifier, or nothing
  /// (pick one).
  Future<void> runTaskCommand([Object? filter]) async {
    if (filter == null) return _doRunTaskCommand();
    final type = filter is Map ? filter['type'] as String? : null;
    final taskName = filter is String
        ? filter
        : filter is Map
        ? filter['task'] as String?
        : null;
    final grouped = await getGroupedTasks(type: type);
    final identifier = _taskIdentifier(filter);
    final all = [for (final tasks in grouped.values) ...tasks];
    final resolver = _createResolver(grouped);
    final folders = [
      for (final folder in host.workspaceFolders) folder.uri,
      null,
    ];
    if (identifier != null) {
      for (final uri in folders) {
        final task = await resolver(uri, identifier);
        if (task != null) {
          unawaited(_runQuietly(task));
          return;
        }
      }
    }
    final exact = taskName == null
        ? null
        : all.where((t) => t.configurationProperties.identifier == taskName);
    if (exact == null || exact.isEmpty) {
      return _doRunTaskCommand(all, taskName);
    }
    for (final uri in folders) {
      final task = await resolver(uri, taskName!);
      if (task != null) {
        await _runQuietly(task, TaskRunSource.user);
        return;
      }
    }
  }

  Object? _taskIdentifier(Object? filter) => switch (filter) {
    final String label => label,
    final Map map when map['type'] is String => _keyOf(map),
    _ => null,
  };

  Future<void> _runQuietly(
    Task task, [
    TaskRunSource source = TaskRunSource.system,
  ]) async {
    try {
      await run(task, source: source);
    } on Object {
      // Surfaced already.
    }
  }

  Future<void> _doRunTaskCommand([List<Task>? tasks, String? name]) async {
    final entry = await _showQuickPick(
      tasks ?? await this.tasks(),
      'Select the task to run',
      defaultEntry: const TaskPickItem<Task?>('Configure a Task', null),
      group: true,
      configure: true,
    );
    if (entry == _configureEntry) return configureTasks();
    if (entry != null) await _runQuietly(entry, TaskRunSource.user);
  }

  static final _configureEntry = Task(
    kind: TaskKind.configuring,
    id: r'$configure',
    source: TaskSource(kind: TaskSourceKind.inMemory, label: ''),
    label: '',
    configurationProperties: ConfigurationProperties(),
    runOptions: RunOptions.defaults(),
  );

  /// `rerun` and `_reRunTaskCommand`: the task last run, else a pick.
  Future<void> reRunTaskCommand({bool onlyRerun = false}) async {
    await host.saveAll();
    final result = _system.rerun();
    if (result != null) {
      try {
        await _handleExecuteResult(result);
      } on Object {
        // Surfaced already.
      }
    } else if (!onlyRerun && getActiveTasks().isEmpty) {
      await _doRunTaskCommand();
    }
  }

  /// `_runTaskGroupCommand`: the group's default task, else a pick.
  Future<void> runGroupCommand(TaskGroup group) async {
    var groupTasks = await _findWorkspaceTasksInGroup(group, isDefault: true);
    if (groupTasks.length == 1) {
      final task = groupTasks.single;
      final resolved = task.isConfiguring ? await tryResolveTask(task) : task;
      if (resolved != null) {
        await _runQuietly(resolved, TaskRunSource.user);
      }
      return;
    }
    var tasks = [
      for (final task in await this.tasks())
        if (task.configurationProperties.group?.id == group.id) task,
    ];
    if (tasks.isNotEmpty) {
      final defaults = [
        for (final task in tasks)
          if (task.configurationProperties.group!.isDefault == true) task,
      ];
      if (defaults.length == 1) {
        await _runQuietly(defaults.single);
        return;
      } else if (defaults.isNotEmpty) {
        tasks = defaults;
      }
    }
    groupTasks = tasks;
    final isBuild = group.id == TaskGroup.build.id;
    final entry = await _showQuickPick(
      groupTasks,
      isBuild ? 'Select the build task to run' : 'Select the test task to run',
      defaultEntry: TaskPickItem<Task?>(
        isBuild
            ? 'No build task to run found. Configure Build Task...'
            : 'No test task to run found. Configure Tasks...',
        null,
      ),
      group: true,
      configure: true,
    );
    if (entry == _configureEntry) return configureTasks();
    if (entry != null) await _runQuietly(entry, TaskRunSource.user);
  }

  /// `_runTerminateCommand`.
  Future<void> terminateCommand([Object? arg]) async {
    if (arg == 'terminateAll') {
      await terminateAll();
      return;
    }
    final identifier = _taskIdentifier(arg);
    final active = getActiveTasks();
    if (identifier != null) {
      for (final task in active) {
        if (task.matches(identifier)) {
          await terminate(task);
          return;
        }
      }
    }
    final entry = await _showQuickPick(
      active,
      'Select a task to terminate',
      defaultEntry: const TaskPickItem<Task?>(
        'No task is currently running',
        null,
      ),
      sort: true,
      terminateAll: true,
    );
    if (entry == _terminateAllEntry) {
      await terminateAll();
    } else if (entry != null) {
      await terminate(entry);
    }
  }

  static final _terminateAllEntry = Task(
    kind: TaskKind.configuring,
    id: r'$terminateAll',
    source: TaskSource(kind: TaskSourceKind.inMemory, label: ''),
    label: '',
    configurationProperties: ConfigurationProperties(),
    runOptions: RunOptions.defaults(),
  );

  /// `_runRestartTaskCommand`.
  Future<void> restartTaskCommand([Object? arg]) async {
    final active = getActiveTasks();
    if (active.length == 1) return _restart(active.single);
    final identifier = _taskIdentifier(arg);
    if (identifier != null) {
      for (final task in active) {
        if (task.matches(identifier)) return _restart(task);
      }
    }
    final entry = await _showQuickPick(
      active,
      'Select the task to restart',
      defaultEntry: const TaskPickItem<Task?>('No task to restart', null),
      sort: true,
    );
    if (entry != null) await _restart(entry);
  }

  /// `_runConfigureTasks`: the folder's tasks.json, made of the "Others"
  /// template when there is none.
  Future<void> configureTasks() async {
    final folders = host.workspaceFolders;
    if (folders.isEmpty) return;
    final folder = folders.length == 1
        ? folders.single
        : await host.pick([
            for (final folder in folders) TaskPickItem(folder.name, folder),
          ], placeholder: 'Select a workspace folder to create a tasks.json');
    if (folder == null) return;
    await host.openTasksJson(folder, othersTemplate);
  }

  /// The "Others" template (`taskTemplates.ts`).
  static const othersTemplate = '''
{
	// See https://go.microsoft.com/fwlink/?LinkId=733558
	// for the documentation about the tasks.json format
	"version": "2.0.0",
	"tasks": [
		{
			"label": "echo",
			"type": "shell",
			"command": "echo Hello"
		}
	]
}
''';

  /// `_showQuickPick`: one of [tasks], the configure entry, the
  /// terminate-all entry, or null.
  Future<Task?> _showQuickPick(
    List<Task> tasks,
    String placeholder, {
    TaskPickItem<Task?>? defaultEntry,
    bool group = false,
    bool sort = false,
    bool configure = false,
    bool terminateAll = false,
  }) async {
    final entries = <TaskPickItem<Task?>>[];
    final sorter = _sorter();
    if (group && tasks.length > 1) {
      final configured = [
        for (final task in tasks)
          if (task.source.kind == TaskSourceKind.workspace ||
              task.source.kind == TaskSourceKind.user)
            task,
      ]..sort(sorter);
      final detected = [
        for (final task in tasks)
          if (task.source.kind != TaskSourceKind.workspace &&
              task.source.kind != TaskSourceKind.user)
            task,
      ]..sort(sorter);
      for (final (label, list) in [
        ('configured tasks', configured),
        ('detected tasks', detected),
      ]) {
        for (final (i, task) in list.indexed) {
          entries.add(_entry(task, separator: i == 0 ? label : null));
        }
      }
    } else {
      final list = sort ? ([...tasks]..sort(sorter)) : tasks;
      entries.addAll([for (final task in list) _entry(task)]);
    }
    if (entries.length == 1 && host.setting('task.quickOpen.skip') == true) {
      return entries.single.value;
    } else if (entries.isEmpty && defaultEntry != null) {
      entries.add(
        TaskPickItem(
          defaultEntry.label,
          configure ? _configureEntry : defaultEntry.value,
        ),
      );
    } else if (entries.length > 1 && terminateAll) {
      entries.add(
        TaskPickItem<Task?>(
          'All Running Tasks',
          _terminateAllEntry,
          separatorBefore: '',
        ),
      );
    }
    return host.pick<Task?>(entries, placeholder: placeholder);
  }

  TaskPickItem<Task?> _entry(Task task, {String? separator}) =>
      TaskPickItem<Task?>(
        task.label,
        task,
        description: host.workspaceFolders.length > 1
            ? task.workspaceFolder?.name
            : null,
        detail: host.setting('task.quickOpen.detail') == false
            ? null
            : task.configurationProperties.detail,
        separatorBefore: separator,
      );

  /// `TaskSorter.compare`.
  int Function(Task a, Task b) _sorter() {
    final order = {
      for (final (i, folder) in host.workspaceFolders.indexed)
        folder.uri.toString(): i,
    };
    return (a, b) {
      final aw = a.workspaceFolder;
      final bw = b.workspaceFolder;
      if (aw != null && bw != null) {
        final ai = (order[aw.uri.toString()] ?? -1) + 1;
        final bi = (order[bw.uri.toString()] ?? -1) + 1;
        return ai == bi ? a.label.compareTo(b.label) : ai - bi;
      }
      if (aw == null && bw != null) return -1;
      if (aw != null && bw == null) return 1;
      return 0;
    };
  }

  void _log(String message) => host.appendOutput('$message\n');

  static String? _messageOf(Object error) {
    try {
      final message = (error as dynamic).message;
      if (message is String) return message;
    } on Object {
      // No message.
    }
    return null;
  }
}
