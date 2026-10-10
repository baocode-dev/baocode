// BaoCode's workspace services behind the ported debug service. DAP and
// session behavior stay in lib/debug; this adapter supplies the real IDE
// effects (activation, trust, save, launch files, quick input and editors).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bao_editor/monaco/vs/editor/common/core/position.dart';
import 'package:bao_exthost/bao_exthost.dart';

import '../../debug/common/debug_model.dart';
import '../../debug/common/debug_storage.dart';
import '../../debug/common/debug_types.dart';
import '../../debug/common/debug_utils.dart';
import '../../debug/service/debug_configuration_manager.dart';
import '../../debug/service/debug_host.dart';
import '../../debug/service/debugger.dart';
import '../../debug/session/debug_session.dart';
import '../../ide/ide_editor_views.dart';
import '../../ide/ide_notifications.dart';
import '../../ide/ide_workspace.dart';
import '../../ide/lsp/lsp_protocol.dart';
import '../commands/extension_command_registry.dart';
import '../configuration/configuration_service.dart';
import '../contextkey/context_key_service.dart';
import '../contextkey/contextkey.dart';
import '../files/file_service.dart';
import '../files/file_types.dart';
import '../trust/workspace_trust.dart';
import '../window/json_state_store.dart';
import '../window/quick_input/quick_input_model.dart';
import '../window/quick_input/quick_input_service.dart';
import '../window/window_ports.dart';
import '../workspace/workspace_context.dart';
import '../workspace/workspace_save.dart';

final class WorkspaceDebugStorage implements DebugStorageBackend {
  WorkspaceDebugStorage(this.state);

  final JsonStateStore state;

  @override
  String? get(String key) => state.get(key);

  @override
  void store(String key, String value) => state.set(key, value);

  @override
  void remove(String key) => state.remove(key);
}

final class WorkspaceLaunchFiles implements LaunchFileStore {
  WorkspaceLaunchFiles(this.files);

  final FileService files;

  @override
  Future<String?> read(VsUri uri) async {
    try {
      return utf8.decode(await files.readFile(uri));
    } on FileOperationException catch (error) {
      if (error.result == FileOperationResult.fileNotFound) return null;
      rethrow;
    }
  }

  @override
  Future<void> write(VsUri uri, String content) =>
      files.writeFile(uri, Uint8List.fromList(utf8.encode(content)));
}

/// Debugger and breakpoint contributions from scanned extension descriptions.
List<DebuggerExtension> debuggerExtensions(List<Json> descriptions) => [
  for (final extension in descriptions)
    if (extension.obj('contributes') case final contributes?)
      DebuggerExtension(
        id:
            extension.obj('identifier')?.str('value') ??
            '${extension['publisher']}.${extension['name']}',
        isBuiltin: extension.flag('isBuiltin'),
        debuggers: contributes.objects('debuggers'),
        breakpoints: contributes.objects('breakpoints'),
        activationEvents:
            extension.list('activationEvents')?.whereType<String>().toList() ??
            const [],
      ),
];

/// The machine a remote project's debugging runs on.
final class DebugMachine {
  const DebugMachine({
    required this.os,
    this.home,
    this.environment = const {},
  });

  final DebugTargetOs os;
  final String? home;

  /// For `${env:…}`: what is known of it.
  final Map<String, String> environment;
}

final class WorkspaceDebugHost extends DebugServiceHost {
  WorkspaceDebugHost({
    required this.workspace,
    required this.configuration,
    required this.context,
    required this.keys,
    required this.commands,
    required this.inputs,
    required this.dialogs,
    required this.trust,
    required this.activate,
    required this.extensions,
    this.language = 'en',
    this.machine,
  });

  /// A remote project's host (its OS, home and environment); this
  /// machine when null.
  final DebugMachine? Function()? machine;

  final IdeWorkspace workspace;
  final ConfigurationService configuration;
  final WorkspaceContextService context;
  final ContextKeyService keys;
  final ExtensionCommandRegistry commands;
  final ExtensionQuickInputService inputs;
  final ExtensionDialogs dialogs;
  final WorkspaceTrustService trust;
  final Future<void> Function(String event) activate;
  final List<Json> Function() extensions;
  final String language;
  final Set<ExtensionQuickInput> _pendingInputs = {};
  final Set<void Function()> _pendingViews = {};
  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final input in _pendingInputs.toList()) {
      input.dispose();
    }
    for (final stop in _pendingViews.toList()) {
      stop();
    }
  }

  void Function()? onOpenDebugView;
  void Function()? onOpenRepl;
  Future<TaskRunResult> Function(
    DebugWorkspaceFolder? root,
    Object task,
    bool checkErrors,
  )?
  taskRunner;
  void Function()? cancelTaskRunner;
  Future<int?> Function(Json args, String sessionId)? terminalRunner;

  @override
  String get locale => language;

  @override
  DebugTargetOs get targetOs =>
      machine?.call()?.os ??
      (Platform.isWindows
          ? DebugTargetOs.windows
          : Platform.isLinux
          ? DebugTargetOs.linux
          : DebugTargetOs.macintosh);

  @override
  List<DebugWorkspaceFolder> get workspaceFolders => [
    for (final folder in context.workspaceFolders)
      DebugWorkspaceFolder(
        uri: folder.uri,
        name: folder.name,
        index: folder.index,
      ),
  ];

  @override
  Map<String, String> get environment =>
      machine?.call()?.environment ?? Platform.environment;

  @override
  String? get userHome => switch (machine?.call()) {
    final machine? => machine.home,
    null => Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'],
  };

  @override
  String get execPath => Platform.resolvedExecutable;

  @override
  Object? configurationValue(String section, {VsUri? folder}) =>
      configuration.getValue(section, resource: folder);

  @override
  DebugSettings settings() =>
      DebugSettings.fromJson(_map(configuration.getValue('debug')));

  @override
  Json? get userLaunchConfiguration =>
      _map(configuration.user.values['launch']);

  @override
  String? extensionInstallFolder(String extensionId) {
    for (final extension in extensions()) {
      if (extension.obj('identifier')?.str('value')?.toLowerCase() ==
          extensionId.toLowerCase()) {
        return VsUri.tryRevive(extension['extensionLocation'])
            ?.fsPath(windows: isWindows);
      }
    }
    return null;
  }

  @override
  DebugActiveEditor? get activeEditor {
    final doc = workspace.active;
    if (doc == null || !doc.isFile || doc.readOnly || doc.openError != null) {
      return null;
    }
    final view = workspace.editorViews.active;
    final primary = view?.document == doc
        ? view?.controller.selections.firstOrNull
        : null;
    final selection =
        primary != null && primary.isValid && primary.end <= doc.text.length
        ? primary
        : null;
    final snapshot = doc.model.snapshot;
    final position = selection == null
        ? null
        : snapshot.positionAtOffset(selection.extentOffset);
    return DebugActiveEditor(
      uri: VsUri.file(doc.path, windows: isWindows),
      languageId: workspace.extensionLanguageId?.call(doc.path),
      lineNumber: position?.lineNumber,
      column: position?.column,
      selectedText: selection == null
          ? null
          : doc.text.substring(selection.start, selection.end),
    );
  }

  @override
  bool isDirty(VsUri uri) =>
      uri.scheme == 'file' &&
      (workspace.modelOf(uri.fsPath(windows: isWindows))?.isDirty ?? false);

  @override
  VsUri? get lastActiveWorkspaceRoot => activeEditor == null
      ? workspaceFolders.firstOrNull?.uri
      : workspaceFolderOf(activeEditor!.uri)?.uri;

  @override
  bool evaluateWhen(String when) =>
      keys.contextMatchesRules(ContextKeyExpr.deserialize(when));

  @override
  Future<bool> requestWorkspaceTrust(String message) async =>
      await trust.requestWorkspaceTrust(message: message) == true;

  @override
  Future<void> activateByEvent(String event) => activate(event);

  @override
  Future<void> saveAll() async {
    if (!await IdeWorkspaceSave(workspace).saveAll(includeUntitled: true)) {
      throw const DebugCancelledError();
    }
  }

  @override
  Future<TaskRunResult> runTask(
    DebugWorkspaceFolder? root,
    Object? task, {
    bool checkErrors = true,
  }) async {
    if (task == null) return TaskRunResult.success;
    final runner = taskRunner;
    if (runner == null) throw UnsupportedError('Debug tasks are not connected');
    return runner(root, task, checkErrors);
  }

  @override
  void cancelTasks() => cancelTaskRunner?.call();

  @override
  Future<Object?> executeCommand(String id, [List<Object?> args = const []]) =>
      commands.executeCommand(id, args);

  Future<T?> _answer<T>(ExtensionQuickInput input, T? Function() answer) async {
    if (_disposed) {
      input.dispose();
      return null;
    }
    _pendingInputs.add(input);
    final result = Completer<T?>();
    void complete(T? value) {
      if (!result.isCompleted) result.complete(value);
    }

    final subscriptions = <StreamSubscription<Object?>>[
      input.onDidAccept.listen((_) => complete(answer())),
      input.onDidHide.listen((_) => complete(null)),
      input.onDispose.listen((_) => complete(null)),
    ];
    try {
      input.show();
      return await result.future;
    } finally {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      _pendingInputs.remove(input);
      input.dispose();
    }
  }

  @override
  Future<String?> showInputBox({
    String? prompt,
    String? value,
    bool password = false,
  }) {
    final box = ExtensionInputBox(inputs)
      ..prompt = prompt
      ..value = value ?? ''
      ..password = password;
    return _answer(box, () => box.value);
  }

  @override
  Future<T?> pick<T>(List<DebugPickItem<T>> items, {String? placeholder}) {
    final pick = ExtensionQuickPick(inputs)
      ..placeholder = placeholder
      ..sortByLabel = false
      ..matchOnDescription = true
      ..items = [
        for (final (i, item) in items.indexed) ...[
          if (item.separatorBefore != null)
            ExtensionQuickPickSeparator(item.separatorBefore),
          ExtensionQuickPickItem(
            handle: i,
            label: item.label,
            description: item.description,
          ),
        ],
      ];
    return _answer(pick, () {
      final selected = pick.selectedItems.firstOrNull;
      return selected == null ? null : items[selected.handle].value;
    });
  }

  @override
  Future<void> openEditor(
    VsUri uri, {
    DebugRange? selection,
    bool preserveFocus = true,
    bool pinned = false,
    bool sideBySide = false,
  }) async {
    if (uri.scheme != 'file') {
      throw UnsupportedError('Cannot open debug resource $uri');
    }
    if (selection == null) {
      await workspace.open(uri.fsPath(windows: isWindows));
    } else {
      await workspace.openAt(
        uri.fsPath(windows: isWindows),
        _lspRange(selection),
      );
    }
    final doc = workspace.active;
    if (!preserveFocus &&
        doc != null &&
        doc.path == uri.fsPath(windows: isWindows)) {
      _whenShown(doc, (view) => view.focus());
    }
  }

  @override
  Future<void> openDebugSource(
    DebugSession session,
    VsUri uri, {
    DebugRange? selection,
    bool preserveFocus = true,
  }) async {
    Future<String> read() async {
      final response = await session.loadSource(uri);
      final content = response?.obj('body')?.str('content');
      if (content == null) {
        throw StateError('Debug source has no content: $uri');
      }
      return content;
    }

    // Check errors before openRevision, which treats a failed read as empty text.
    final content = await read();
    var initialRead = true;
    final label = 'Debug ${session.getId()} ${uri.query}';
    await workspace.openRevision(
      uri.path,
      label: label,
      read: () async {
        if (initialRead) {
          initialRead = false;
          return content;
        }
        return read();
      },
    );
    final doc = workspace.active;
    if (doc == null || doc.label != label) return;
    _whenShown(doc, (view) {
      if (selection != null) {
        final snapshot = doc.model.snapshot;
        view.reveal(
          snapshot.offsetAtPosition(
            Position(selection.startLineNumber, selection.startColumn),
          ),
          snapshot.offsetAtPosition(
            Position(selection.endLineNumber, selection.endColumn),
          ),
          center: true,
        );
      }
      if (!preserveFocus) view.focus();
    });
  }

  void _whenShown(IdeDocument doc, void Function(IdeEditorView view) action) {
    if (_disposed) return;
    late final void Function() check;
    void stop() {
      workspace.editorViews.removeListener(check);
      workspace.removeListener(check);
      _pendingViews.remove(stop);
    }

    check = () {
      if (!identical(workspace.active, doc)) {
        stop();
      } else if (workspace.editorViews.active case final view?
          when identical(view.document, doc)) {
        stop();
        action(view);
      }
    };
    _pendingViews.add(stop);
    workspace.editorViews.addListener(check);
    workspace.addListener(check);
    check();
  }

  @override
  void showError(String message) =>
      workspace.notifications.notify(IdeSeverity.error, message);

  @override
  void notify(String message, {String? source}) =>
      workspace.notifications.notify(IdeSeverity.info, message, source: source);

  @override
  Future<bool> confirm(String message) async =>
      (await dialogs.prompt(
        severity: ExtensionSeverity.warning,
        message: message,
        buttons: ['Continue'],
        cancel: 'Cancel',
      )).button ==
      0;

  @override
  void onBreak(DebugSession session, Thread thread) {
    if (settings().openDebug == 'openOnDebugBreak' &&
        !session.suppressDebugView) {
      openDebugView();
    }
  }

  @override
  void openDebugView() => onOpenDebugView?.call();

  @override
  void openRepl() => onOpenRepl?.call();

  @override
  Future<int?> runInTerminal(Json args, String sessionId) {
    final runner = terminalRunner;
    if (runner == null) {
      throw UnsupportedError('Debug terminal is not connected');
    }
    return runner(args, sessionId);
  }

  @override
  Future<void> installAdditionalDebuggers(String? query) async =>
      commands.executeCommand('workbench.extensions.search', [
        query ?? '@category:debuggers',
      ]);
}

Json? _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : null;

LspRange _lspRange(DebugRange range) => LspRange(
  LspPosition(range.startLineNumber - 1, range.startColumn - 1),
  LspPosition(range.endLineNumber - 1, range.endColumn - 1),
);
