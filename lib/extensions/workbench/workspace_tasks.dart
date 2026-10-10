// The tasks of a workspace window: the task service on the window's
// folders (their .vscode/tasks.json, read again as they change), its
// terminals, markers, Tasks output channel, dialogs and picks; the Tasks
// commands; and the debugger's pre-launch tasks.

import 'dart:async';
import 'dart:io';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:path/path.dart' as p;

import '../../debug/service/debug_host.dart';
import '../../debug/service/debug_service.dart';
import '../../ide/ide_notifications.dart' show IdeSeverity;
import '../../ide/ide_workspace.dart';
import '../../settings/jsonc_file.dart';
import '../commands/builtin_commands.dart';
import '../configuration/configuration_model.dart' show ConfigurationTarget;
import '../configuration/configuration_service.dart';
import '../host/init_data.dart';
import '../language/marker_service.dart';
import '../main_thread/main_thread_terminal_service.dart';
import '../tasks/debug_task_runner.dart';
import '../tasks/problem_matcher.dart' show ProblemFileSystem;
import '../tasks/task_configuration.dart' show TaskPlatform;
import '../tasks/task_service.dart';
import '../tasks/terminal_task_system.dart';
import '../trust/workspace_trust.dart';
import '../window/json_state_store.dart';
import '../window/output/extension_output_service.dart';
import '../window/progress_service.dart';
import '../window/window_ports.dart';
import '../workspace/workspace_context.dart';
import '../workspace/workspace_save.dart';
import 'workspace_debug_host.dart';

/// The Tasks output channel's id (upstream's).
const tasksOutputChannelId = 'tasks';

/// The tasks of one workspace window.
final class WorkspaceTasks implements TaskServiceHost, DebugTaskRunnerHost {
  WorkspaceTasks({
    required this.workspace,
    required this.configuration,
    required this.context,
    required this.trust,
    required this.output,
    required ExtensionTerminals terminals,
    required MarkerService markers,
    required this.dialogs,
    required this.debugHost,
    required this.debug,
    required this.state,
    required this.commands,
    required this._activate,
    required this._extensions,
    this.progress,
    this.storage,
    ProblemFileSystem? problemFiles,
    TaskPlatform? platform,
    void Function(String key, Object? value)? setContext,
  }) {
    _channel = output.registerWorkbenchChannel(tasksOutputChannelId, 'Tasks');
    service = TaskService(
      host: this,
      terminals: () => terminals.service,
      markers: markers,
      variableResolver: _DebugTaskVariables(debug),
      extensionPty: () => terminals.startExtensionPty,
      isOpen: (resource) =>
          resource.scheme == 'file' &&
          workspace.documents.any(
            (d) => d.isFile && d.path == resource.fsPath(),
          ),
      files: problemFiles,
      platform: platform,
      setContext: setContext,
    );
    runner = DebugTaskRunner(tasks: service, markers: markers, host: this);
    debug.taskInputs = service.inputsOf;
    debugHost
      ..taskRunner = ((root, task, checkErrors) =>
          runner.run(root?.uri, task, checkErrors: checkErrors))
      ..cancelTaskRunner = runner.cancel;
    for (final MapEntry(:key, :value) in service.commands.entries) {
      _stops.add(commands.register(key, value));
    }
    context.addListener(_foldersChanged);
    _foldersChanged();
  }

  final IdeWorkspace workspace;
  final ConfigurationService configuration;
  final WorkspaceContextService context;
  final WorkspaceTrustService trust;
  final ExtensionOutputService output;
  @override
  final ExtensionDialogs dialogs;
  final WorkspaceDebugHost debugHost;
  final DebugService debug;
  final JsonStateStore state;
  final BuiltinCommands commands;
  @override
  final ExtensionProgressService? progress;
  final Future<void> Function(String event) _activate;
  final List<Map<String, Object?>> Function() _extensions;

  /// Where the `tasks.json` files are (a remote project's host); this
  /// machine's disk when null.
  final JsoncFileStorage? storage;

  late final TaskService service;
  late final DebugTaskRunner runner;
  late final ExtensionOutputChannel _channel;
  final _files = <String, JsoncFile>{};
  final _stops = <void Function()>[];
  bool _disposed = false;

  /// Opens the Problems view; null shows nothing.
  void Function()? onOpenProblems;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    context.removeListener(_foldersChanged);
    for (final stop in _stops) {
      stop();
    }
    runner.cancel();
    if (identical(debug.taskInputs, service.inputsOf)) debug.taskInputs = null;
    debugHost
      ..taskRunner = null
      ..cancelTaskRunner = null;
    service.dispose();
    for (final file in _files.values) {
      file
        ..removeListener(service.invalidateWorkspaceTasks)
        ..dispose();
    }
    _files.clear();
  }

  /// The extensions changed: their task types and problem matchers too.
  void extensionsChanged() => service.invalidateWorkspaceTasks();

  String _tasksJsonPath(ExtHostWorkspaceFolder folder) =>
      p.join(folder.uri.fsPath(), '.vscode', 'tasks.json');

  void _foldersChanged() {
    final paths = {
      for (final folder in context.workspaceFolders)
        if (folder.uri.scheme == 'file') _tasksJsonPath(folder),
    };
    for (final path in [..._files.keys]) {
      if (!paths.contains(path)) {
        _files.remove(path)!
          ..removeListener(service.invalidateWorkspaceTasks)
          ..dispose();
      }
    }
    for (final path in paths) {
      if (_files.containsKey(path)) continue;
      _files[path] = JsoncFile(path, storage: storage)
        ..addListener(service.invalidateWorkspaceTasks)
        ..watch();
    }
    service.invalidateWorkspaceTasks();
  }

  //---- TaskServiceHost

  @override
  List<ExtHostWorkspaceFolder> get workspaceFolders => context.workspaceFolders;

  @override
  Future<({Object? value, String? error})> readTasksJson(
    ExtHostWorkspaceFolder folder,
  ) async {
    if (folder.uri.scheme != 'file') return (value: null, error: null);
    final file = _files[_tasksJsonPath(folder)];
    if (file == null) return (value: null, error: null);
    if (!file.loaded) await file.load();
    return (value: file.value, error: file.error);
  }

  @override
  List<Map<String, Object?>> get extensions => _extensions();

  @override
  Future<void> activateByEvent(String event) => _activate(event);

  @override
  Object? setting(String key, {VsUri? resource}) =>
      configuration.getValue(key, resource: resource);

  @override
  bool get workspaceTrusted => trust.isWorkspaceTrusted;

  @override
  Future<bool> requestWorkspaceTrust(String message) async =>
      await trust.requestWorkspaceTrust(message: message) == true;

  @override
  bool get hasDirtyEditors => workspace.documents.any((d) => d.dirty);

  @override
  Future<void> saveAll() async {
    await IdeWorkspaceSave(workspace).saveAll();
  }

  @override
  Future<bool> confirm(
    String message, {
    String? detail,
    required String primary,
    required String cancel,
  }) async {
    final answer = await dialogs.prompt(
      severity: ExtensionSeverity.info,
      message: message,
      detail: detail,
      buttons: [primary],
      cancel: cancel,
    );
    return answer.button == 0;
  }

  @override
  void notify(TaskNoticeSeverity severity, String message) =>
      workspace.notifications.notify(switch (severity) {
        TaskNoticeSeverity.info => IdeSeverity.info,
        TaskNoticeSeverity.warning => IdeSeverity.warning,
        TaskNoticeSeverity.error => IdeSeverity.error,
      }, message);

  @override
  Future<T?> pick<T>(List<TaskPickItem<T>> items, {String? placeholder}) =>
      debugHost.pick([
        for (final item in items)
          DebugPickItem(
            item.label,
            item.value,
            description: [?item.description, ?item.detail].join(' — '),
            separatorBefore: item.separatorBefore,
          ),
      ], placeholder: placeholder);

  @override
  void appendOutput(String text) => _channel.append(text);

  @override
  void showOutput() =>
      output.showChannel(tasksOutputChannelId, preserveFocus: true);

  @override
  void openProblems() => onOpenProblems?.call();

  @override
  Future<void> openTasksJson(
    ExtHostWorkspaceFolder folder,
    String template,
  ) async {
    final path = _tasksJsonPath(folder);
    if (storage case final storage?) {
      if (await storage.read(path) == null) await storage.write(path, template);
    } else {
      final file = File(path);
      if (!file.existsSync()) {
        await file.parent.create(recursive: true);
        await file.writeAsString(template);
      }
    }
    await workspace.open(path);
  }

  //---- DebugTaskRunnerHost

  @override
  Future<void> updateUserSetting(String key, Object? value) =>
      configuration.update(key, value, target: ConfigurationTarget.user);

  @override
  String? storedValue(String key) => state.get(key);

  @override
  void store(String key, String value) => state.set(key, value);

  @override
  Future<Object?> executeCommand(String id, [List<Object?> args = const []]) =>
      debugHost.executeCommand(id, args);
}

/// The tasks' variables as the debugger resolves a launch configuration's,
/// with tasks.json's `inputs`.
final class _DebugTaskVariables implements TaskVariableResolver {
  _DebugTaskVariables(this.debug);

  final DebugService debug;

  @override
  Future<Map<String, String>?> resolveWithInteraction(
    ExtHostWorkspaceFolder? folder,
    List<String> variables,
  ) => debug.variableResolver().resolveWithInteraction(
    folder?.uri,
    variables,
    section: 'tasks',
  );

  @override
  Future<String> resolveAsync(
    ExtHostWorkspaceFolder? folder,
    String value,
  ) async =>
      '${await debug.variableResolver().resolveAsync(folder?.uri, value)}';
}
