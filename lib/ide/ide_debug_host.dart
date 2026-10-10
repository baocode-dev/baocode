// The IDE behind the ported debug service (lib/debug): its folders,
// settings, editors, quick input and notifications. The adapters are
// BaoCode's own (registered on the service's registry); no extension runs.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show md5;
import 'package:path/path.dart' as p;

import '../base/uri.dart' show VsUri;
import '../debug/common/debug_model.dart';
import '../debug/common/debug_storage.dart';
import '../debug/common/debug_types.dart';
import '../debug/common/debug_utils.dart';
import '../debug/service/debug_configuration_manager.dart';
import '../debug/service/debug_host.dart';
import '../debug/service/debug_service.dart';
import '../debug/session/debug_session.dart';
import '../extensions/window/json_state_store.dart';
import '../settings/user_settings.dart';
import 'file_service.dart' show IdeFileService;
import 'ide_notifications.dart';
import 'ide_quick_input.dart';
import 'ide_workspace.dart';
import 'lsp/catalog/standard_lsp.dart';
import 'lsp/lsp_protocol.dart';

/// The debug service's state (breakpoints, watches, the configuration
/// chosen) in a workspace's `debug.json`.
final class IdeDebugStorage implements DebugStorageBackend {
  IdeDebugStorage(this.state);

  final JsonStateStore state;

  @override
  String? get(String key) => state.get(key);

  @override
  void store(String key, String value) => state.set(key, value);

  @override
  void remove(String key) => state.remove(key);
}

/// `launch.json` read and written through the workspace's files (a remote
/// project's on its host).
final class IdeLaunchFiles implements LaunchFileStore {
  IdeLaunchFiles(this.files, {this.windows = false});

  final IdeFileService files;
  final bool windows;

  @override
  Future<String?> read(VsUri uri) async {
    if (uri.scheme != 'file') return null;
    try {
      return await files.read(uri.fsPath(windows: windows));
    } on Object {
      // Not there (yet).
      return null;
    }
  }

  @override
  Future<void> write(VsUri uri, String content) async {
    final path = uri.fsPath(windows: windows);
    try {
      await files.create(p.dirname(path), directory: true);
    } on Object {
      // There already.
    }
    try {
      await files.create(path);
    } on Object {
      // There already: written over.
    }
    await files.write(path, content);
  }
}

/// The IDE, as the debug service sees it.
final class IdeDebugHost extends DebugServiceHost {
  IdeDebugHost({
    required this.workspace,
    this.settingsFile,
    this.language = 'en',
    this.pickHost,
    this.confirmHost,
    this.selectionHost,
    this.revealHost,
  });

  final IdeWorkspace workspace;

  /// `settings.json`, for the `debug.*` settings and `launch`.
  final UserSettings? settingsFile;
  final String language;

  /// Shows a quick pick or an input box (the workbench's quick input);
  /// nothing is asked without it.
  final void Function(IdeQuickInputModel model)? pickHost;

  /// Asks to go on (a dialog); yes without it.
  final Future<bool> Function(String message)? confirmHost;

  /// The active editor's selection (offsets in its text), when it has one.
  final ({int start, int end})? Function()? selectionHost;

  /// Shows [doc] (the active document) once its editor is up: [range]
  /// revealed and selected, the keyboard in it when [focus].
  final void Function(IdeDocument doc, LspRange? range, {required bool focus})?
  revealHost;

  void Function()? onOpenDebugView;
  void Function()? onOpenRepl;

  bool _disposed = false;

  /// The language catalog, for the active editor's language id; loaded
  /// when first asked.
  StandardLsp? _lsp;
  bool _loadingLsp = false;

  void dispose() {
    _disposed = true;
  }

  @override
  String get locale => language;

  @override
  DebugTargetOs get targetOs => Platform.isWindows
      ? DebugTargetOs.windows
      : Platform.isLinux
      ? DebugTargetOs.linux
      : DebugTargetOs.macintosh;

  /// A multi-folder workspace's folders, else the project's folder.
  @override
  List<DebugWorkspaceFolder> get workspaceFolders => !workspace.hasFolder
      ? const []
      : [
          for (final (index, root)
              in (workspace.isMultiRoot ? workspace.roots : [workspace.root])
                  .indexed)
            DebugWorkspaceFolder(
              uri: VsUri.file(root, windows: isWindows),
              name: p.basename(root),
              index: index,
            ),
        ];

  @override
  Map<String, String> get environment => Platform.environment;

  @override
  String? get userHome =>
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];

  @override
  String get execPath => Platform.resolvedExecutable;

  Map<String, Object?> get _values => settingsFile?.values ?? const {};

  /// [section]'s value: its key's, else an object of the dotted keys
  /// under it (`debug.console.maximumLines` in `debug`'s `console`).
  Object? _setting(String section) {
    final values = _values;
    if (values.containsKey(section)) return values[section];
    final prefix = '$section.';
    Map<String, Object?>? nested;
    for (final MapEntry(:key, :value) in values.entries) {
      if (!key.startsWith(prefix)) continue;
      final parts = key.substring(prefix.length).split('.');
      var map = nested ??= {};
      for (final part in parts.take(parts.length - 1)) {
        map = switch (map[part]) {
          final Map<String, Object?> inner => inner,
          _ => map[part] = <String, Object?>{},
        };
      }
      map[parts.last] = value;
    }
    return nested;
  }

  @override
  Object? configurationValue(String section, {VsUri? folder}) =>
      _setting(section);

  @override
  DebugSettings settings() => DebugSettings.fromJson(_map(_setting('debug')));

  @override
  Json? get userLaunchConfiguration => _map(_setting('launch'));

  @override
  DebugActiveEditor? get activeEditor {
    final doc = workspace.active;
    if (doc == null || !doc.isFile || doc.readOnly || doc.openError != null) {
      return null;
    }
    final primary = selectionHost?.call();
    final selection =
        primary != null &&
            primary.start >= 0 &&
            primary.start <= primary.end &&
            primary.end <= doc.text.length
        ? primary
        : null;
    final snapshot = doc.model.snapshot;
    final position = selection == null
        ? null
        : snapshot.positionAtOffset(selection.end);
    return DebugActiveEditor(
      uri: VsUri.file(doc.path, windows: isWindows),
      languageId: _languageId(doc.path),
      lineNumber: position?.lineNumber,
      column: position?.column,
      selectedText: selection == null
          ? null
          : doc.text.substring(selection.start, selection.end),
    );
  }

  String? _languageId(String path) {
    final lsp = _lsp;
    if (lsp == null) {
      if (!_loadingLsp) {
        _loadingLsp = true;
        unawaited(
          standardLsp().then(
            (lsp) => _lsp = lsp,
            onError: (Object _) => _loadingLsp = false,
          ),
        );
      }
      return null;
    }
    final language = lsp.catalog.languageFor(path);
    return language?.languageId ?? language?.id;
  }

  @override
  bool isDirty(VsUri uri) =>
      uri.scheme == 'file' &&
      (workspace.modelOf(uri.fsPath(windows: isWindows))?.isDirty ?? false);

  @override
  VsUri? get lastActiveWorkspaceRoot => switch (activeEditor) {
    final editor? => workspaceFolderOf(editor.uri)?.uri,
    null => workspaceFolders.firstOrNull?.uri,
  };

  @override
  Future<void> saveAll() async {
    for (final doc in workspace.documents) {
      if (doc.isFile && doc.dirty) await workspace.save(doc);
    }
  }

  @override
  Future<String?> showInputBox({
    String? prompt,
    String? value,
    bool password = false,
  }) {
    final show = pickHost;
    if (show == null || _disposed) return Future.value();
    final answer = Completer<String?>();
    show(
      IdeQuickInputBox(
        value: value ?? '',
        prompt: prompt,
        onDidAccept: (value) {
          if (!answer.isCompleted) answer.complete(value);
        },
        onDidHide: () {
          if (!answer.isCompleted) answer.complete(null);
        },
      ),
    );
    return answer.future;
  }

  @override
  Future<T?> pick<T>(List<DebugPickItem<T>> items, {String? placeholder}) {
    final show = pickHost;
    if (show == null || _disposed) return Future.value();
    final values = Map<IdeQuickPickItem, T>.identity();
    final answer = Completer<T?>();
    show(
      IdeQuickPick(
        placeholder: placeholder,
        sortByLabel: false,
        matchOnDescription: true,
        items: [
          for (final item in items) ...[
            if (item.separatorBefore case final label?)
              IdeQuickPickSeparator(label),
            values.keyFor(
              IdeQuickPickItem(
                label: item.label,
                description: item.description,
              ),
              item.value,
            ),
          ],
        ],
        onDidAccept: (item) {
          if (!answer.isCompleted) {
            answer.complete(item == null ? null : values[item]);
          }
        },
        onDidHide: () {
          if (!answer.isCompleted) answer.complete(null);
        },
      ),
    );
    return answer.future;
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
    final path = uri.fsPath(windows: isWindows);
    if (selection == null) {
      await workspace.open(path);
    } else {
      await workspace.openAt(path, _lspRange(selection));
    }
    final doc = workspace.active;
    if (!preserveFocus && !_disposed && doc != null && doc.path == path) {
      revealHost?.call(doc, null, focus: true);
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

    // Errors first: openRevision takes a failed read as empty text.
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
    if (_disposed || doc == null || doc.label != label) return;
    revealHost?.call(
      doc,
      selection == null ? null : _lspRange(selection),
      focus: !preserveFocus,
    );
  }

  @override
  void showError(String message) =>
      workspace.notifications.notify(IdeSeverity.error, message);

  @override
  void notify(String message, {String? source}) =>
      workspace.notifications.notify(IdeSeverity.info, message, source: source);

  @override
  Future<bool> confirm(String message) async =>
      await confirmHost?.call(message) ?? true;

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
}

/// The debug service of [workspace], its state kept in
/// `<userDirectory>/workspaceStorage/<folder's hash>/debug.json`; ended by
/// [IdeDebug.dispose].
final class IdeDebug {
  IdeDebug._(this.host, this.service, this._state);

  final IdeDebugHost host;
  final DebugService service;
  final JsonStateStore? _state;

  /// Makes it once its saved state has loaded; the launch configurations
  /// load after.
  static Future<IdeDebug> open({
    required IdeWorkspace workspace,
    required String? userDirectory,
    UserSettings? settings,
    String language = 'en',
    void Function(IdeQuickInputModel model)? pick,
    Future<bool> Function(String message)? confirm,
    ({int start, int end})? Function()? selection,
    void Function(IdeDocument doc, LspRange? range, {required bool focus})?
    reveal,
  }) async {
    final host = IdeDebugHost(
      workspace: workspace,
      settingsFile: settings,
      language: language,
      pickHost: pick,
      confirmHost: confirm,
      selectionHost: selection,
      revealHost: reveal,
    );
    final state = userDirectory == null || !workspace.hasFolder
        ? null
        : JsonStateStore(
            p.join(
              userDirectory,
              'workspaceStorage',
              md5.convert(utf8.encode(workspace.root)).toString(),
              'debug.json',
            ),
          );
    try {
      await state?.load();
    } on Object {
      // Unreadable: starts empty.
    }
    final service = DebugService(
      host: host,
      storage: state == null
          ? MemoryDebugStorageBackend()
          : IdeDebugStorage(state),
      fileStore: IdeLaunchFiles(workspace.files, windows: host.isWindows),
    );
    final debug = IdeDebug._(host, service, state);
    unawaited(debug._initialize());
    return debug;
  }

  bool _disposed = false;

  Future<void> _initialize() async {
    try {
      await service.configurationManager.initialize();
    } on Object catch (error) {
      if (!_disposed) host.showError('$error');
    }
  }

  /// A file saved: its breakpoints verify again, and `launch.json`'s
  /// configurations load again.
  void saved(String path) {
    if (_disposed) return;
    final uri = VsUri.file(path, windows: host.isWindows);
    service.onFilesSaved([uri]);
    if (p.basename(path) == 'launch.json' &&
        p.basename(p.dirname(path)) == '.vscode') {
      unawaited(
        service.configurationManager.reload().catchError(
          (Object error) => host.showError('$error'),
        ),
      );
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    host.dispose();
    service.dispose();
    await _state?.dispose();
  }
}

Json? _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : null;

LspRange _lspRange(DebugRange range) => LspRange(
  LspPosition(range.startLineNumber - 1, range.startColumn - 1),
  LspPosition(range.endLineNumber - 1, range.endColumn - 1),
);

extension<K, V> on Map<K, V> {
  /// Puts [key] with [value], and gives [key].
  K keyFor(K key, V value) {
    this[key] = value;
    return key;
  }
}
