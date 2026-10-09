/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The extensions' tasks: their task providers (`vscode.tasks.
// registerTaskProvider`), `fetchTasks`, `executeTask` (of a fetched task,
// by its handle, or of the extension's own), `terminate`, a custom
// execution's completion, the task system of a remote scheme, and the
// task events (`onDidStartTask`, `onDidEndTaskProcess`, …) as they
// happen.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadTask.ts.

import 'dart:async';
import 'dart:math';

import 'package:bao_exthost/bao_exthost.dart';

import '../host/init_data.dart';
import '../tasks/task_configuration.dart';
import '../tasks/task_service.dart';
import '../tasks/tasks.dart';
import '../tasks/terminal_task_system.dart';
import '../workspace/workspace_context.dart';
import 'main_thread_context.dart';

/// `MainThreadTask`.
final class MainThreadTask extends MainThreadTaskUnsupported {
  MainThreadTask(this._tasks, this._workspace, RpcProtocol rpc)
    : _proxy = ExtHostTaskProxy(rpc) {
    _events = _tasks.onDidStateChange.listen(_onDidStateChange);
  }

  static RpcActor customer(MainThreadContext context) {
    final service = MainThreadTask(
      context.service<TaskService>(),
      context.service<WorkspaceContextService>(),
      context.rpc,
    );
    context.onDispose(service.dispose);
    return MainThreadTaskActor(service);
  }

  final TaskService _tasks;
  final WorkspaceContextService _workspace;
  final ExtHostTaskProxy _proxy;
  late final StreamSubscription<TaskEvent> _events;
  final _providers = <int, void Function()>{};
  final _random = Random();

  void dispose() {
    unawaited(_events.cancel());
    for (final remove in _providers.values) {
      remove();
    }
    _providers.clear();
  }

  void _send(Future<void> call) => unawaited(call.catchError((Object _) {}));

  void _onDidStateChange(TaskEvent event) {
    if (event.kind == TaskEventKind.changed) return;
    final task = event.task!;
    switch (event.kind) {
      case TaskEventKind.start:
        final execution = task.executionDto();
        unawaited(() async {
          var definition =
              task.getDefinition(useSource: true)?.toDto() ??
              <String, Object?>{'type': task.type};
          final resolved = event.resolvedVariables;
          if (task.command?.runtime == RuntimeType.customExecution &&
              resolved != null) {
            definition = await _resolveDefinition(task, definition, resolved);
          }
          _send(
            _proxy.$onDidStartTask(
              execution,
              event.terminalId ?? 0,
              definition,
            ),
          );
        }());
      case TaskEventKind.processStarted:
        _send(
          _proxy.$onDidStartTaskProcess({
            'id': task.id,
            'processId': event.processId,
          }),
        );
      case TaskEventKind.processEnded:
        _send(
          _proxy.$onDidEndTaskProcess({
            'id': task.id,
            'exitCode': event.exitCode,
          }),
        );
      case TaskEventKind.end:
        _send(_proxy.$OnDidEndTask(task.executionDto()));
      case TaskEventKind.problemMatcherStarted:
        _send(
          _proxy.$onDidStartTaskProblemMatchers({
            'execution': task.executionDto(),
          }),
        );
      case TaskEventKind.problemMatcherEnded:
        _send(
          _proxy.$onDidEndTaskProblemMatchers({
            'execution': task.executionDto(),
            'hasErrors': false,
          }),
        );
      case TaskEventKind.problemMatcherFoundErrors:
        _send(
          _proxy.$onDidEndTaskProblemMatchers({
            'execution': task.executionDto(),
            'hasErrors': true,
          }),
        );
      default:
        break;
    }
  }

  /// A custom execution's definition with the run's variables in it, the
  /// rest resolved as they can be without asking.
  Future<Map<String, Object?>> _resolveDefinition(
    Task task,
    Map<String, Object?> definition,
    Map<String, String> resolved,
  ) async {
    final resolver = _tasks.variableResolver;
    final folder = task.workspaceFolder;
    final pattern = RegExp(r'\$\{(.*?)\}');
    Future<Object?> walk(Object? value) async {
      if (value is String) {
        final replaced = value.replaceAllMapped(
          pattern,
          (m) => resolved[m.group(1)] ?? m.group(0)!,
        );
        return resolver.resolveAsync(folder, replaced);
      }
      if (value is List) return [for (final v in value) await walk(v)];
      if (value is Map) {
        return {
          for (final MapEntry(:key, :value) in value.entries)
            '$key': await walk(value),
        };
      }
      return value;
    }

    return (await walk(definition) as Map).cast<String, Object?>();
  }

  //---- DTOs

  /// `TaskSourceDTO.to`.
  TaskSource _sourceFrom(Object? value) {
    final dto = value is Map ? value : const {};
    final scope = dto['scope'];
    var taskScope = TaskScope.folder;
    ExtHostWorkspaceFolder? folder;
    final folders = _workspace.workspaceFolders;
    if (scope == null || (scope is num && scope != TaskScope.global.wire)) {
      if (folders.isEmpty) {
        taskScope = TaskScope.global;
      } else {
        folder = folders.first;
      }
    } else if (scope is num) {
      taskScope = TaskScope.values.firstWhere(
        (s) => s.wire == scope,
        orElse: () => TaskScope.global,
      );
    } else if (VsUri.tryRevive(scope) case final uri?) {
      folder = _workspace.getWorkspaceFolder(uri);
    }
    return TaskSource(
      kind: TaskSourceKind.extension,
      label: dto['label'] as String? ?? '',
      extension: dto['extensionId'] as String?,
      scope: taskScope,
      workspaceFolder: folder,
    );
  }

  /// `TaskDefinitionDTO.to`.
  KeyedTaskIdentifier? _definitionFrom(Object? value, bool executeOnly) {
    final result = value is Map
        ? _tasks.definitions.createTaskIdentifier(value.cast())
        : null;
    if (result == null && executeOnly) {
      return KeyedTaskIdentifier.raw(_uuid(), {'type': r'$executeOnly'});
    }
    return result;
  }

  String _uuid() {
    String hex(int n) =>
        [for (var i = 0; i < n; i++) _random.nextInt(16).toRadixString(16)]
            .join();
    return '${hex(8)}-${hex(4)}-4${hex(3)}-a${hex(3)}-${hex(12)}';
  }

  static CommandOptions _processOptionsFrom(Object? value) {
    if (value is! Map) return CommandOptions(cwd: r'${workspaceFolder}');
    final cwd = value['cwd'];
    return CommandOptions(
      cwd: cwd is String && cwd.isNotEmpty ? cwd : r'${workspaceFolder}',
      env: (value['env'] as Map?)?.cast<String, String>(),
    );
  }

  static CommandOptions? _shellOptionsFrom(Object? value) {
    if (value is! Map) return null;
    final result = CommandOptions(
      cwd: value['cwd'] as String?,
      env: (value['env'] as Map?)?.cast<String, String>(),
    );
    final executable = value['executable'];
    if (executable is String && executable.isNotEmpty) {
      result.shell = ShellConfiguration(
        executable: executable,
        args: (value['shellArgs'] as List?)?.cast<String>(),
        quoting: ShellQuotingOptions.fromJson(value['shellQuoting']),
      );
    }
    return result;
  }

  /// The execution's command (`ShellExecutionDTO.to`, `ProcessExecutionDTO.
  /// to`, `CustomExecutionDTO.to`).
  static CommandConfiguration? _commandFrom(Object? execution) {
    if (execution is! Map) return null;
    final commandLine = execution['commandLine'];
    final command = execution['command'];
    if ((commandLine is String && commandLine.isNotEmpty) || command != null) {
      return CommandConfiguration(
        runtime: RuntimeType.shell,
        name: commandLine is String && commandLine.isNotEmpty
            ? commandLine
            : commandStringFrom(command),
        args: [
          for (final arg in execution['args'] as List? ?? const [])
            ?commandStringFrom(arg),
        ],
        options: _shellOptionsFrom(execution['options']),
      );
    }
    final process = execution['process'];
    if (process is String && process.isNotEmpty) {
      return CommandConfiguration(
        runtime: RuntimeType.process,
        name: process,
        args: [
          for (final arg in execution['args'] as List? ?? const [])
            if (arg is String) arg,
        ],
        options: _processOptionsFrom(execution['options']),
      );
    }
    if (execution['customExecution'] == 'customExecution') {
      return CommandConfiguration(runtime: RuntimeType.customExecution);
    }
    return null;
  }

  static bool _isCustomExecution(Object? execution) =>
      execution is Map && execution['customExecution'] == 'customExecution';

  /// `TaskDTO.to`: an extension's task.
  Task? taskFrom(
    Object? value, {
    required bool executeOnly,
    Map<String, Object?>? icon,
    bool? hide,
  }) {
    if (value is! Map || value['name'] is! String) return null;
    final command = _commandFrom(value['execution']);
    if (command == null) return null;
    command.presentation = PresentationOptions.fromDto(
      value['presentationOptions'],
    );
    final source = _sourceFrom(value['source']);
    final name = value['name'] as String;
    final label = '${source.label}: $name';
    final definition = _definitionFrom(value['definition'], executeOnly);
    if (definition == null) return null;
    final dtoId = value['_id'];
    final extensionId = (value['source'] as Map?)?['extensionId'];
    final id = _isCustomExecution(value['execution']) && dtoId is String
        ? dtoId
        : '$extensionId.${definition.key}';
    final group = value['group'];
    return Task(
      kind: TaskKind.contributed,
      id: id,
      source: source,
      label: label,
      type: definition.type,
      definition: definition,
      command: command,
      hasDefinedMatchers: value['hasDefinedMatchers'] == true,
      runOptions: RunOptions.from(value['runOptions']),
      configurationProperties: ConfigurationProperties(
        name: name,
        identifier: label,
        group: group is Map && group['_id'] is String
            ? TaskGroup(
                group['_id'] as String,
                isDefault: group['isDefault'] as Object? ?? false,
              )
            : null,
        isBackground: value['isBackground'] == true,
        problemMatchers: [
          for (final matcher in value['problemMatchers'] as List? ?? const [])
            if (matcher is String) matcher,
        ],
        detail: value['detail'] as String?,
        icon: icon,
        hide: hide,
      ),
    );
  }

  static bool _isHandle(Object? value) =>
      value is Map && value['id'] is String && value['workspaceFolder'] != null;

  /// `getWorkspace`: a folder, or a string as is.
  Object? _workspaceOf(Object? value) {
    if (value is String) return value;
    final uri = VsUri.tryRevive(value);
    if (uri == null) return null;
    final configuration = _workspace.workspace?.configuration;
    if (configuration != null && configuration.toString() == uri.toString()) {
      return uri;
    }
    return _workspace.getWorkspaceFolder(uri);
  }

  //---- MainThreadTaskShape

  @override
  Future<String> $createTaskId(Map<String, Object?> task) async {
    final result = taskFrom(task, executeOnly: true);
    if (result == null) throw StateError('Task could not be created from DTO');
    return result.id;
  }

  @override
  void $registerTaskProvider(num handle, String type) {
    final provider = _ExtHostTaskProvider(this, handle.toInt());
    _providers[handle.toInt()] = _tasks.registerTaskProvider(provider, type);
  }

  @override
  void $unregisterTaskProvider(num handle) {
    _providers.remove(handle.toInt())?.call();
  }

  @override
  Future<List<Map<String, Object?>>> $fetchTasks(
    Map<String, Object?>? filter,
  ) async {
    final tasks = await _tasks.tasks(type: filter?['type'] as String?);
    return [for (final task in tasks) ?task.toDto()];
  }

  @override
  Future<Map<String, Object?>> $getTaskExecution(
    Map<String, Object?> value,
  ) async {
    if (_isHandle(value)) {
      final workspace = _workspaceOf(value['workspaceFolder']);
      if (workspace == null) throw StateError('No workspace folder');
      final task = await _tasks.getTask(
        workspace,
        value['id']! as String,
        compareId: true,
      );
      if (task == null) throw StateError('Task not found');
      return {'id': task.id, 'task': task.toDto()};
    }
    final task = taskFrom(value, executeOnly: true);
    if (task == null) throw StateError('Task could not be created from DTO');
    return {'id': task.id, 'task': task.toDto()};
  }

  @override
  Future<Map<String, Object?>> $executeTask(Map<String, Object?> task) async {
    if (_isHandle(task)) {
      final workspace = _workspaceOf(task['workspaceFolder']);
      if (workspace == null) throw StateError('No workspace folder');
      final Task? found;
      try {
        found = await _tasks.getTask(
          workspace,
          task['id']! as String,
          compareId: true,
        );
      } on Object {
        throw StateError('Task not found');
      }
      if (found == null) throw StateError('Task not found');
      final result = {'id': task['id'], 'task': found.toDto()};
      unawaited(
        _tasks.run(found).then(
          (summary) {
            // The execution ends even when a dependency failed.
            if (summary?.exitCode == null || summary!.exitCode != 0) {
              _send(_proxy.$OnDidEndTask(result));
            }
          },
          // Surfaced to the user already.
          onError: (Object _) {},
        ),
      );
      return result;
    }
    final contributed = taskFrom(task, executeOnly: true);
    if (contributed == null) {
      throw StateError('Task could not be created from DTO');
    }
    unawaited(_tasks.run(contributed).then((_) {}, onError: (Object _) {}));
    return {'id': contributed.id, 'task': contributed.toDto()};
  }

  @override
  Future<void> $customExecutionComplete(String id, num? result) async {
    for (final task in _tasks.getActiveTasks()) {
      if (task.id == id) {
        await _tasks.extensionCallbackTaskComplete(task, result?.toInt());
        return;
      }
    }
    throw StateError('Task to mark as complete not found');
  }

  @override
  Future<void> $terminateTask(String id) async {
    for (final task in _tasks.getActiveTasks()) {
      if (task.id == id) {
        await _tasks.terminate(task);
        return;
      }
    }
    throw StateError('Task to terminate not found');
  }

  @override
  void $registerTaskSystem(String scheme, Map<String, Object?> info) {
    final platform = switch (info['platform']) {
      'win32' => TaskPlatform.windows,
      'darwin' => TaskPlatform.mac,
      'linux' => TaskPlatform.linux,
      _ => TaskPlatform.current,
    };
    final infoScheme = info['scheme'] as String? ?? scheme;
    final authority = info['authority'] as String? ?? '';
    _tasks.registerTaskSystem(
      scheme,
      TaskSystemInfo(
        platform: platform,
        uriProvider: (path) =>
            VsUri(infoScheme, authority: authority, path: path),
        resolveVariables: (folder, variables, {process}) =>
            _resolveVariables(folder, variables.toList(), process),
        findExecutable: (command, cwd, paths) =>
            _proxy.$findExecutable(command, cwd, paths),
      ),
    );
  }

  Future<({String? process, Map<String, String> variables})?> _resolveVariables(
    ExtHostWorkspaceFolder folder,
    List<String> variables,
    ({String name, String? cwd, String? path})? process,
  ) async {
    final values = await _proxy.$resolveVariables(folder.uri, {
      if (process != null)
        'process': {'name': process.name, 'cwd': ?process.cwd},
      'variables': variables,
    });
    final resolvedByHost = (values['variables'] as Map? ?? const {})
        .cast<String, Object?>();
    final partially = [
      for (final variable in variables)
        '${resolvedByHost[variable] ?? variable}',
    ];
    final interactive = await _tasks.variableResolver.resolveWithInteraction(
      folder,
      partially,
    );
    final result = <String, String>{};
    for (final (i, variable) in variables.indexed) {
      final name = variable.substring(2, variable.length - 1);
      if (interactive != null && resolvedByHost[variable] == variable) {
        final value = interactive[name];
        if (value != null) result[name] = value;
      } else {
        result[name] = partially[i];
      }
    }
    if (interactive == null) return null;
    return (process: values['process'] as String?, variables: result);
  }

  @override
  void $registerSupportedExecutions(bool? custom, bool? shell, bool? process) {
    _tasks.registerSupportedExecutions(
      custom: custom,
      shell: shell,
      process: process,
    );
  }
}

/// `ITaskProvider` of an extension host's provider (`$provideTasks`,
/// `$resolveTask`).
final class _ExtHostTaskProvider implements TaskProvider {
  _ExtHostTaskProvider(this._main, this._handle);

  final MainThreadTask _main;
  final int _handle;

  @override
  Future<TaskSet> provideTasks(Map<String, bool> validTypes) async {
    final value = await _main._proxy.$provideTasks(_handle, validTypes);
    final tasks = <Task>[];
    for (final dto in value['tasks'] as List? ?? const []) {
      final task = _main.taskFrom(dto, executeOnly: true);
      if (task != null) tasks.add(task);
    }
    return (
      tasks: tasks,
      extension: (value['extension'] as Map?)?.cast<String, Object?>(),
    );
  }

  @override
  Future<Task?> resolveTask(Task task) async {
    final dto = task.toDto();
    if (dto == null) return null;
    // An empty name is the provider's name.
    dto['name'] ??= '';
    final resolved = await _main._proxy.$resolveTask(_handle, dto);
    if (resolved == null) return null;
    return _main.taskFrom(
      resolved,
      executeOnly: true,
      icon: task.configurationProperties.icon,
      hide: task.configurationProperties.hide,
    );
  }
}
