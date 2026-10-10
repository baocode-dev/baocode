// The window area's adapters: its port interfaces (window_ports.dart) on
// BaoCode's own widgets and services, so the lead wires the area in with
// a handful of objects instead of writing glue.

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../ide/ide_dialog.dart';
import '../commands/extension_command_registry.dart' as commands;
import 'window_ports.dart';

/// [ExtensionCommandExecutor] on the workbench's commands (the extension
/// commands and the built-in ones), one per app.
final class WorkbenchCommandExecutor implements ExtensionCommandExecutor {
  const WorkbenchCommandExecutor(this.registry);

  final commands.ExtensionCommandRegistry registry;

  @override
  Future<Object?> executeCommand(String id, [List<Object?> args = const []]) =>
      registry.executeCommand(id, args);
}

/// [ExtensionCommandExecutor] that forwards to a function (the workbench
/// keeps its command service behind one).
final class FunctionCommandExecutor implements ExtensionCommandExecutor {
  const FunctionCommandExecutor(this.run);

  final Future<Object?> Function(String id, List<Object?> args) run;

  @override
  Future<Object?> executeCommand(String id, [List<Object?> args = const []]) =>
      run(id, args);
}

/// [ExtensionDialogs] on the app's modal dialogs. A dialog needs a
/// [BuildContext]; the workbench gives one that is under its navigator
/// (`dialogContext`), and the adapter reads it when a dialog shows.
final class WorkbenchDialogs implements ExtensionDialogs {
  WorkbenchDialogs({required this.context});

  /// The context dialogs show in (the workbench's root or its window's).
  final BuildContext Function() context;

  @override
  Future<ExtensionDialogAnswer> prompt({
    required ExtensionSeverity severity,
    required String message,
    String? detail,
    required List<String> buttons,
    String? cancel,
    String? checkbox,
  }) async {
    final result = await showIdeInputDialog(
      context(),
      message: message,
      detail: detail,
      buttons: buttons,
      checkbox: checkbox,
      // An empty string means "no cancel", null lets the default stand.
      cancel: cancel ?? '',
      type: switch (severity) {
        ExtensionSeverity.info => IdeDialogType.info,
        ExtensionSeverity.warning => IdeDialogType.warning,
        ExtensionSeverity.error => IdeDialogType.error,
        _ => IdeDialogType.question,
      },
    );
    if (result == null) return (button: null, checked: false);
    return (
      button: result.button == buttons.length ? null : result.button,
      checked: result.checked,
    );
  }
}

/// [ExtensionFilePickers] on the app's native panels
/// (lib/workspace/window_controls.dart): the ones the IDE's Open… and Save
/// As… use.
final class WorkbenchFilePickers implements ExtensionFilePickers {
  const WorkbenchFilePickers({
    required this.openPanel,
    required this.savePanel,
  });

  /// The app's open panel: paths, or null when cancelled.
  final Future<List<String>?> Function({
    required bool files,
    required bool folders,
    required bool many,
    String? directory,
  })
  openPanel;
  final Future<String?> Function({String? directory, String? name})
  savePanel;

  @override
  Future<List<String>?> pickOpen({
    required bool files,
    required bool folders,
    required bool many,
    String? directory,
    String? title,
    String? openLabel,
    Map<String, List<String>> filters = const {},
  }) => openPanel(
    files: files,
    folders: folders,
    many: many,
    directory: directory,
  );

  @override
  Future<String?> pickSave({
    String? directory,
    String? name,
    String? title,
    String? saveLabel,
    Map<String, List<String>> filters = const {},
  }) => savePanel(directory: directory, name: name);
}

/// [ExtensionExternalOpener] on the app's URL launcher
/// (`openExternal` in lib/workspace/editor_launcher.dart): the system's
/// browser for a URL, its default app for a file.
final class WorkbenchExternalOpener implements ExtensionExternalOpener {
  const WorkbenchExternalOpener(this.open);

  final Future<bool> Function(String target) open;

  @override
  Future<bool> openExternal(Uri uri) => open(uri.toString());
}

/// [ExtensionWindowFocus] as the app knows it: whether a window is in
/// front (the lifecycle's resumed state) and whether the user touched it
/// recently (upstream's `UserActivityService`, three minutes).
final class WorkbenchWindowFocus
    with WidgetsBindingObserver
    implements ExtensionWindowFocus {
  WorkbenchWindowFocus({this.activeWindow = const Duration(minutes: 3)}) {
    WidgetsBinding.instance.addObserver(this);
    _focused = _inFront();
  }

  /// How long the window stays "active" after the user touched it.
  final Duration activeWindow;

  bool _focused = false;
  bool _active = false;
  Timer? _activeTimer;
  final _changes = StreamController<void>.broadcast(sync: true);

  /// Starts taking the app's lifecycle events; the workbench calls this
  /// once it is built.
  void start() {
    _focused = _inFront();
    _active = _focused;
    if (_focused) _markActive();
  }

  static bool _inFront() =>
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState ==
          AppLifecycleState.resumed ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.inactive;

  @override
  bool get isFocused => _focused;

  @override
  bool get isActive => _active;

  @override
  Stream<void> get changes => _changes.stream;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final focused = state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    if (focused == _focused) return;
    _focused = focused;
    if (focused) _markActive();
    _changed();
  }

  /// The user did something (`UserActivityService.notifyUserActivity`).
  void markActive() => _markActive();

  void _markActive() {
    final was = _active;
    _active = true;
    _activeTimer?.cancel();
    _activeTimer = Timer(activeWindow, () {
      _active = false;
      _changed();
    });
    if (!was) _changed();
  }

  void _changed() {
    if (!_changes.isClosed) _changes.add(null);
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _activeTimer?.cancel();
    unawaited(_changes.close());
  }
}

/// [ExtensionFilePickers] on the app's native panels
/// (lib/workspace/window_controls.dart). The app's panels take no filters,
/// title or button label: a deviation the goal accepts, since the native
/// panel shows every file and the title is the item's.
ExtensionFilePickers systemFilePickers({
  required Future<List<String>> Function({String? directory, bool multiple})
  pickOpenFiles,
  required Future<String?> Function({String? directory, String? name})
  pickSaveFile,
  required Future<String?> Function() pickDirectory,
}) => WorkbenchFilePickers(
  openPanel: ({
    required bool files,
    required bool folders,
    required bool many,
    String? directory,
  }) async {
    if (folders && !files) {
      final folder = await pickDirectory();
      return folder == null ? null : [folder];
    }
    final paths = await pickOpenFiles(
      directory: directory,
      multiple: many,
    );
    return paths.isEmpty ? null : paths;
  },
  savePanel: ({String? directory, String? name}) =>
      pickSaveFile(directory: directory, name: name),
);
