import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'json_rpc.dart';
import 'language_features.dart';
import 'lsp_client.dart';
import 'lsp_glob.dart';
import 'lsp_process.dart';
import 'lsp_protocol.dart';
import 'lsp_server_definition.dart';

class _Document {
  _Document(this.path, this.uri, this.language, this.text, this.version);

  final String path;
  final String uri;
  final LspLanguage? language;
  String text;
  int version;

  /// The language's servers in order: those that serve it, and the ids
  /// with no definition (null).
  final List<(String, _Server?)> entries = [];

  Iterable<_Server> get servers => entries.map((e) => e.$2).nonNulls;

  String get languageId => language?.languageId ?? language?.id ?? 'plaintext';
}

/// One server definition running for one workspace folder.
class _Server {
  _Server(this.definition, this.root);

  final LspServerDefinition definition;
  final String root;

  String get id => definition.id;

  LanguageServerState state = LanguageServerState.idle;
  LspClient? client;
  Future<LspClient?>? starting;

  /// Bumped to abandon a start or restart under way.
  int generation = 0;
  String? message;
  String? package;
  bool installable = false;
  String? missingRuntime;
  DateTime? retryAt;
  final Set<_Document> documents = {};
  final List<DateTime> crashes = [];
  Timer? idleTimer;
  Timer? retryTimer;
}

/// The language servers of one project: starts the servers a document's
/// language names when it opens (sharing one per server and workspace
/// folder), keeps them in sync with the editor, merges their answers, and
/// restarts them when they crash.
///
/// Workspace folders are the nearest ancestor of a document holding one of
/// the server's (else the language's) root markers, searched up to
/// [root]; [root] itself when there is none, unless the server requires
/// one.
///
/// Hand it to the workspace, which then drives it and shuts it down:
/// `IdeWorkspace(root, languages: LspManager(root, catalog, provider))`.
class LspManager extends ChangeNotifier
    implements LanguageFeatures, LanguageDocumentSync {
  LspManager(
    String root,
    this.catalog,
    this.provider, {
    LspProcessStarter? startProcess,
    LspDirectoryWatcher? watchDirectory,
    FutureOr<bool> Function(String path)? pathExists,
    FutureOr<List<String>> Function(String directory)? listDirectory,
    p.Context? paths,
    this._processId,
    this.idleTimeout = const Duration(minutes: 5),
    DateTime Function()? clock,
    this.requestTimeout = const Duration(seconds: 30),
    this.initializeTimeout = const Duration(seconds: 60),
    this.shutdownTimeout = const Duration(seconds: 3),
    this.initialBackoff = const Duration(seconds: 1),
    this.maxBackoff = const Duration(seconds: 30),
    this.maxCrashes = 5,
    this.crashWindow = const Duration(minutes: 3),
    this.watchDebounce = const Duration(milliseconds: 200),
  }) : root = (paths ?? p.context).normalize(
         (paths ?? p.context).absolute(root),
       ),
       _paths = paths ?? p.context,
       _startProcess = startProcess ?? startLspProcess,
       _watchDirectory = watchDirectory ?? watchLspDirectory,
       _pathExists = pathExists ?? lspPathExists,
       _listDirectory = listDirectory ?? lspListDirectory,
       _clock = clock ?? DateTime.now;

  /// The project folder.
  final String root;
  final LspCatalog catalog;
  final LspServerProvider provider;

  /// How long a server with no open document keeps running.
  final Duration idleTimeout;
  final Duration requestTimeout;
  final Duration initializeTimeout;
  final Duration shutdownTimeout;

  /// The first restart's delay after a crash; each further crash within
  /// [crashWindow] doubles it, up to [maxBackoff]. The [maxCrashes]th
  /// crash within [crashWindow] gives up ([LanguageServerState.failed]).
  final Duration initialBackoff;
  final Duration maxBackoff;
  final int maxCrashes;
  final Duration crashWindow;

  /// How long file changes on disk are gathered before servers hear of them.
  final Duration watchDebounce;

  final LspProcessStarter _startProcess;
  final LspDirectoryWatcher _watchDirectory;

  /// Whether a path is there, and the names in a folder: for the
  /// workspace folders' root markers. On another machine they answer
  /// later, and documents are matched to servers once they have.
  final FutureOr<bool> Function(String path) _pathExists;
  final FutureOr<List<String>> Function(String directory) _listDirectory;

  /// How the servers' machine spells paths: POSIX on a remote host.
  final p.Context _paths;

  /// The process the servers are told to outlive no longer than: the
  /// app's here, the server's on a remote host.
  final int? Function()? _processId;

  bool get _windowsPaths => _paths.style == p.Style.windows;
  final DateTime Function() _clock;

  final _documents = <String, _Document>{};
  final _servers = <String, _Server>{};

  /// Diagnostics by document path, then by server.
  final _diagnostics = <String, Map<_Server, List<LspDiagnostic>>>{};
  final _edits = StreamController<LspApplyEditRequest>.broadcast();
  final _installs = <String, Future<void>>{};
  StreamSubscription<LspFileEvent>? _watch;
  final _fileEvents = <String, LspFileChangeType>{};
  Timer? _fileEventTimer;
  bool _shutDown = false;
  bool _disposed = false;

  String _normalize(String path) => _paths.normalize(_paths.absolute(path));

  String _uriOf(String path) =>
      Uri.file(path, windows: _windowsPaths).toString();

  String? _pathOf(String uri) {
    try {
      final parsed = Uri.parse(uri);
      return parsed.scheme == 'file'
          ? _normalize(parsed.toFilePath(windows: _windowsPaths))
          : null;
    } on Object {
      return null;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // Documents.

  @override
  void openDocument(String path, String text, {int version = 0}) {
    if (_shutDown) return;
    path = _normalize(path);
    if (_documents.containsKey(path)) {
      changeDocument(path, text, version: version);
      return;
    }
    final newline = text.indexOf(RegExp('[\r\n]'));
    final language = catalog.languageFor(
      path,
      firstLine: newline < 0 ? text : text.substring(0, newline),
    );
    final doc = _Document(path, _uriOf(path), language, text, version);
    _documents[path] = doc;
    for (final id in language?.servers ?? const <String>[]) {
      final definition = catalog.server(id);
      if (definition == null) {
        doc.entries.add((id, null));
        continue;
      }
      final folder = _workspaceFolder(path, definition, language!);
      if (folder is Future<String?>) {
        // Its markers looked for on another machine: matched once found.
        unawaited(
          folder.then((folder) {
            if (_shutDown || !identical(_documents[path], doc)) return;
            _attach(doc, id, definition, folder);
            _notify();
          }, onError: (Object _) {}),
        );
      } else {
        _attach(doc, id, definition, folder);
      }
    }
    _notify();
  }

  /// Has [doc] served by [definition]'s server for [folder] (none for
  /// null), started if need be.
  void _attach(
    _Document doc,
    String id,
    LspServerDefinition definition,
    String? folder,
  ) {
    if (folder == null) return;
    final server = _servers.putIfAbsent(
      '$id\u0000$folder',
      () => _Server(definition, folder),
    );
    doc.entries.add((id, server));
    server.documents.add(doc);
    server.idleTimer?.cancel();
    final client = server.client;
    if (server.state == LanguageServerState.running && client != null) {
      client.didOpen(doc.uri, doc.languageId, doc.version, doc.text);
    } else {
      unawaited(_ensure(server));
    }
  }

  @override
  void changeDocument(
    String path,
    String text, {
    required int version,
    List<LspTextDocumentContentChange>? changes,
  }) {
    final doc = _documents[_normalize(path)];
    if (doc == null || _shutDown) return;
    doc
      ..text = text
      ..version = version;
    for (final server in doc.servers) {
      final client = server.client;
      if (server.state != LanguageServerState.running || client == null) {
        continue;
      }
      client.didChange(doc.uri, version, text, changes: changes);
    }
  }

  @override
  void saveDocument(String path, String text) {
    final doc = _documents[_normalize(path)];
    if (doc == null || _shutDown) return;
    for (final server in doc.servers) {
      server.client?.didSave(doc.uri, text);
    }
  }

  @override
  void closeDocument(String path) {
    final doc = _documents.remove(_normalize(path));
    if (doc == null) return;
    for (final server in doc.servers) {
      server.documents.remove(doc);
      server.client?.didClose(doc.uri);
      _scheduleIdle(server);
    }
    _notify();
  }

  /// Matches the open documents to servers again, after [catalog] changed
  /// (it finished loading, or the user's settings were edited).
  void reloadCatalog() {
    if (_shutDown) return;
    for (final doc in [..._documents.values]) {
      closeDocument(doc.path);
      openDocument(doc.path, doc.text, version: doc.version);
    }
  }

  /// The workspace folder of [path] for [definition]; later where the
  /// markers are looked for on another machine.
  FutureOr<String?> _workspaceFolder(
    String path,
    LspServerDefinition definition,
    LspLanguage language,
  ) {
    final paths = _paths;
    final markers = definition.rootMarkers.isNotEmpty
        ? definition.rootMarkers
        : language.rootMarkers;
    final inside = paths.isWithin(root, path);
    if (markers.isNotEmpty) {
      var dir = paths.dirname(path);
      while (true) {
        for (final marker in markers) {
          final found = _hasMarker(dir, marker);
          if (found is Future<bool>) {
            return _workspaceFolderLater(path, definition, markers, inside);
          }
          if (found) return dir;
        }
        if (inside && paths.equals(dir, root)) break;
        final parent = paths.dirname(dir);
        if (parent == dir) break;
        dir = parent;
      }
    }
    return _noMarker(path, definition, inside: inside);
  }

  /// [_workspaceFolder], waiting for each marker's answer.
  Future<String?> _workspaceFolderLater(
    String path,
    LspServerDefinition definition,
    List<String> markers,
    bool inside,
  ) async {
    final paths = _paths;
    var dir = paths.dirname(path);
    while (true) {
      for (final marker in markers) {
        if (await _hasMarker(dir, marker)) return dir;
      }
      if (inside && paths.equals(dir, root)) break;
      final parent = paths.dirname(dir);
      if (parent == dir) break;
      dir = parent;
    }
    return _noMarker(path, definition, inside: inside);
  }

  String? _noMarker(
    String path,
    LspServerDefinition definition, {
    required bool inside,
  }) {
    if (definition.requiredRoot) return null;
    final paths = _paths;
    return inside || paths.equals(paths.dirname(path), root)
        ? root
        : paths.dirname(path);
  }

  FutureOr<bool> _hasMarker(String dir, String marker) {
    if (!marker.contains(RegExp(r'[*?\[{]'))) {
      return _pathExists(_paths.join(dir, marker));
    }
    final glob = LspGlob(marker);
    final names = _listDirectory(dir);
    if (names is Future<List<String>>) {
      return names.then((names) => names.any(glob.matches));
    }
    return names.any(glob.matches);
  }

  // Server lifecycle.

  Future<LspClient?> _ensure(_Server server) {
    if (_shutDown) return Future.value();
    switch (server.state) {
      case LanguageServerState.running:
        return Future.value(server.client);
      case LanguageServerState.starting:
        return server.starting ?? Future.value();
      case LanguageServerState.idle || LanguageServerState.stopped:
        return server.starting = _start(server);
      case LanguageServerState.restarting ||
          LanguageServerState.failed ||
          LanguageServerState.missing ||
          LanguageServerState.installing:
        return Future.value();
    }
  }

  Future<LspClient?> _start(_Server server) async {
    final generation = ++server.generation;
    bool stale() => generation != server.generation || _shutDown;
    server
      ..idleTimer?.cancel()
      ..state = LanguageServerState.starting
      ..retryAt = null;
    _notify();
    LspClient? client;
    try {
      final location = await provider.locate(server.definition);
      if (stale()) return null;
      final String executable;
      switch (location) {
        case LspServerMissing(:final package, :final missingRuntime):
          server
            ..package = package ?? server.definition.masonPackage
            ..missingRuntime = missingRuntime
            ..installable = (package ?? server.definition.masonPackage) != null
            ..state = LanguageServerState.missing;
          _notify();
          return null;
        case LspServerFound():
          executable = location.executable;
      }
      final process = await _startProcess(
        LspLaunch(
          serverId: server.id,
          executable: executable,
          arguments: server.definition.args,
          workingDirectory: server.root,
          environment: server.definition.environment,
        ),
      );
      if (stale()) {
        process.kill();
        return null;
      }
      late final LspClient started;
      started = client = LspClient(
        definition: server.definition,
        rootPath: server.root,
        processId: _processId?.call(),
        windowsPaths: _windowsPaths,
        process: process,
        requestTimeout: requestTimeout,
        onDiagnostics: (uri, diagnostics) =>
            _publish(server, started, uri, diagnostics),
        onChanged: () => _clientChanged(server, started),
        onApplyEdit: _applyEdit,
        onExit: (code, {required crashed}) =>
            _exited(server, started, code, crashed: crashed),
      );
      server.client = started;
      await started.initialize(timeout: initializeTimeout);
      if (stale() || !identical(server.client, started)) return null;
      server
        ..state = LanguageServerState.running
        ..message = null;
      for (final doc in server.documents) {
        started.didOpen(doc.uri, doc.languageId, doc.version, doc.text);
      }
      _updateWatching();
      _notify();
      if (server.documents.isEmpty) _scheduleIdle(server);
      return started;
    } on JsonRpcClosed {
      // It exited while starting: its exit says whether it crashed.
      return null;
    } on Object catch (error) {
      if (stale()) return null;
      server
        ..state = LanguageServerState.failed
        ..message = _describe(error, client);
      if (client != null) {
        server.client = null;
        client.kill();
      }
      _notify();
      return null;
    } finally {
      if (generation == server.generation) server.starting = null;
    }
  }

  static String _describe(Object error, LspClient? client) {
    final reason = switch (error) {
      LspStartException() => error.toString(),
      TimeoutException() => 'The server did not answer initialize in time',
      JsonRpcError(:final message) => message,
      _ => '$error',
    };
    final tail = client?.stderrTail ?? '';
    return tail.isEmpty ? reason : '$reason\n$tail';
  }

  void _exited(
    _Server server,
    LspClient client,
    int code, {
    required bool crashed,
  }) {
    _clearDiagnostics(server);
    if (!identical(server.client, client)) {
      _notify();
      return;
    }
    server.client = null;
    _updateWatching();
    if (_shutDown) return;
    if (!crashed) {
      if (server.state == LanguageServerState.running ||
          server.state == LanguageServerState.starting) {
        server.state = LanguageServerState.stopped;
      }
      _notify();
      return;
    }
    server
      ..generation += 1
      ..starting = null;
    final now = _clock();
    server.crashes
      ..add(now)
      ..removeWhere((time) => now.difference(time) > crashWindow);
    final tail = client.stderrTail;
    final exit = 'Exited with code $code';
    if (server.crashes.length >= maxCrashes) {
      server
        ..state = LanguageServerState.failed
        ..retryAt = null
        ..message =
            '${server.id} crashed ${server.crashes.length} times: '
            '${tail.isEmpty ? exit : '$exit\n$tail'}';
      _notify();
      return;
    }
    final factor = math.pow(2, server.crashes.length - 1).toInt();
    final delay = initialBackoff * factor > maxBackoff
        ? maxBackoff
        : initialBackoff * factor;
    final generation = server.generation;
    server
      ..state = LanguageServerState.restarting
      ..retryAt = now.add(delay)
      ..message = tail.isEmpty ? exit : '$exit\n$tail'
      ..retryTimer?.cancel()
      ..retryTimer = Timer(delay, () {
        server.retryTimer = null;
        if (generation != server.generation ||
            server.state != LanguageServerState.restarting) {
          return;
        }
        server.state = server.documents.isEmpty
            ? LanguageServerState.stopped
            : LanguageServerState.idle;
        if (server.documents.isEmpty) {
          _notify();
        } else {
          unawaited(_ensure(server));
        }
      });
    _notify();
  }

  void _scheduleIdle(_Server server) {
    server.idleTimer?.cancel();
    if (server.documents.isNotEmpty || server.client == null) return;
    server.idleTimer = Timer(idleTimeout, () {
      server.idleTimer = null;
      if (server.documents.isEmpty) unawaited(_stop(server));
    });
  }

  Future<void> _stop(
    _Server server, {
    LanguageServerState state = LanguageServerState.stopped,
  }) async {
    server
      ..idleTimer?.cancel()
      ..retryTimer?.cancel()
      ..generation += 1
      ..starting = null
      ..state = state;
    final client = server.client;
    _notify();
    if (client != null) await client.shutdown(timeout: shutdownTimeout);
  }

  Iterable<_Server> _serversNamed(String serverId, String? path) {
    final doc = path == null ? null : _documents[_normalize(path)];
    return _servers.values.where(
      (s) => s.id == serverId && (doc == null || s.documents.contains(doc)),
    );
  }

  @override
  void retry(String serverId, {String? path}) {
    if (_shutDown) return;
    for (final server in [..._serversNamed(serverId, path)]) {
      if (server.state == LanguageServerState.running ||
          server.state == LanguageServerState.starting ||
          server.state == LanguageServerState.installing) {
        continue;
      }
      server
        ..retryTimer?.cancel()
        ..retryTimer = null
        ..crashes.clear()
        ..retryAt = null
        ..message = null
        ..state = LanguageServerState.idle;
      if (server.documents.isNotEmpty) unawaited(_ensure(server));
    }
    _notify();
  }

  @override
  Future<void> install(String serverId, {String? path}) =>
      _installs[serverId] ??= _install(serverId, path).whenComplete(() {
        // Not `=>`: whenComplete would wait for the future it returns.
        _installs.remove(serverId);
      });

  Future<void> _install(String serverId, String? path) async {
    final targets = [
      for (final server in _serversNamed(serverId, path))
        if (server.state == LanguageServerState.missing ||
            server.state == LanguageServerState.failed)
          server,
    ];
    if (targets.isEmpty || _shutDown) return;
    final package =
        targets.map((s) => s.package).nonNulls.firstOrNull ??
        catalog.server(serverId)?.masonPackage;
    if (package == null) {
      for (final server in targets) {
        server.message = 'Nothing installs $serverId';
      }
      _notify();
      return;
    }
    for (final server in targets) {
      server
        ..state = LanguageServerState.installing
        ..message = 'Installing $package…';
    }
    _notify();
    try {
      await provider.install(
        package,
        onProgress: (message) {
          for (final server in targets) {
            if (server.state == LanguageServerState.installing) {
              server.message = message;
            }
          }
          _notify();
        },
      );
    } on Object catch (error) {
      for (final server in targets) {
        server
          ..state = LanguageServerState.missing
          ..message = error is LspInstallException
              ? error.toString()
              : 'Installing $package failed: $error';
      }
      _notify();
      return;
    }
    for (final server in targets) {
      if (server.state != LanguageServerState.installing) continue;
      server
        ..state = LanguageServerState.idle
        ..message = null
        ..crashes.clear();
      if (server.documents.isNotEmpty) unawaited(_ensure(server));
    }
    _notify();
  }

  /// Starts the servers again, their processes lost with the connection
  /// to their host: each is given its documents again, as they are now
  /// (unsaved changes and all).
  void restartServers() {
    if (_shutDown) return;
    for (final server in _servers.values) {
      final client = server.client;
      server
        ..idleTimer?.cancel()
        ..retryTimer?.cancel()
        ..generation += 1
        ..starting = null
        ..client = null
        ..crashes.clear()
        ..retryAt = null
        ..message = null;
      client?.kill();
      _clearDiagnostics(server);
      if (server.state == LanguageServerState.installing) continue;
      server.state = server.documents.isEmpty
          ? LanguageServerState.stopped
          : LanguageServerState.idle;
      if (server.documents.isNotEmpty) unawaited(_ensure(server));
    }
    _updateWatching();
    _notify();
  }

  @override
  Future<void> shutdown() => _shutdown ??= _stopAll();

  Future<void>? _shutdown;

  Future<void> _stopAll() async {
    _shutDown = true;
    _fileEventTimer?.cancel();
    unawaited(_watch?.cancel());
    _watch = null;
    final stopping = <Future<void>>[];
    for (final server in _servers.values) {
      server
        ..idleTimer?.cancel()
        ..retryTimer?.cancel()
        ..generation += 1
        ..state = LanguageServerState.stopped;
      if (server.client case final client?) {
        stopping.add(client.shutdown(timeout: shutdownTimeout));
      }
    }
    _documents.clear();
    _diagnostics.clear();
    _notify();
    await Future.wait(stopping);
  }

  @override
  void dispose() {
    unawaited(shutdown());
    _disposed = true;
    unawaited(_edits.close());
    super.dispose();
  }

  // Server traffic.

  void _clientChanged(_Server server, LspClient client) {
    if (!identical(server.client, client)) return;
    _updateWatching();
    _notify();
  }

  void _publish(
    _Server server,
    LspClient client,
    String uri,
    List<LspDiagnostic> diagnostics,
  ) {
    if (!identical(server.client, client) ||
        !server.definition.provides(LspFeature.diagnostics)) {
      return;
    }
    final path = _pathOf(uri) ?? uri;
    if (diagnostics.isEmpty) {
      final byServer = _diagnostics[path];
      if (byServer == null || byServer.remove(server) == null) return;
      if (byServer.isEmpty) _diagnostics.remove(path);
    } else {
      (_diagnostics[path] ??= {})[server] = diagnostics;
    }
    _notify();
  }

  void _clearDiagnostics(_Server server) {
    var changed = false;
    _diagnostics.removeWhere((_, byServer) {
      changed |= byServer.remove(server) != null;
      return byServer.isEmpty;
    });
    if (changed) _notify();
  }

  Future<bool> _applyEdit(LspWorkspaceEdit edit, String? label) {
    if (_disposed || !_edits.hasListener) return Future.value(false);
    final request = LspApplyEditRequest(edit, label: label);
    final answer = Completer<bool>();
    request.onComplete(answer.complete);
    _edits.add(request);
    return answer.future;
  }

  void _updateWatching() {
    final needed =
        !_shutDown &&
        _servers.values.any((s) => s.client?.fileWatchers.isNotEmpty ?? false);
    if (needed && _watch == null) {
      _watch = _watchDirectory(root).listen(_fileChanged, onError: (_) {});
    } else if (!needed && _watch != null) {
      unawaited(_watch!.cancel());
      _watch = null;
      _fileEventTimer?.cancel();
      _fileEvents.clear();
    }
  }

  /// How many file changes wait to be told at most, and how many are told
  /// at once (VS Code's watcher's throttle: `maxBufferedWork` and
  /// `maxWorkChunkSize`): a folder whose files keep changing (a home folder
  /// opened, a build) drops what is past it rather than holding up the
  /// window matching them.
  static const maxBufferedFileEvents = 30000;
  static const fileEventChunk = 500;

  /// Whether a change at [path] is in a folder VS Code does not watch
  /// (`files.watcherExclude`'s defaults): Git's objects and subtree cache,
  /// the files of a package in `node_modules`, Mercurial's store.
  bool _watchExcluded(String path) {
    final separator = _paths.separator;
    bool under(String folder, {bool deeper = false}) {
      final marker = '$separator$folder$separator';
      final at = path.indexOf(marker);
      if (at < 0) return false;
      return !deeper || path.indexOf(separator, at + marker.length) >= 0;
    }

    return under('node_modules', deeper: true) ||
        under('.git${separator}objects') ||
        under('.git${separator}subtree-cache') ||
        under('.hg${separator}store');
  }

  void _fileChanged(LspFileEvent event) {
    if (_watchExcluded(event.path)) return;
    final path = _normalize(event.path);
    final previous = _fileEvents[path];
    if (previous == null && _fileEvents.length >= maxBufferedFileEvents) {
      return;
    }
    final type = switch ((previous, event.type)) {
      (LspFileChangeType.created, LspFileChangeType.changed) =>
        LspFileChangeType.created,
      (LspFileChangeType.created, LspFileChangeType.deleted) => null,
      (LspFileChangeType.deleted, LspFileChangeType.created) =>
        LspFileChangeType.changed,
      (_, final type) => type,
    };
    if (type == null) {
      _fileEvents.remove(path);
    } else {
      _fileEvents[path] = type;
    }
    _fileEventTimer ??= Timer(watchDebounce, _flushFileEvents);
  }

  /// Tells the servers the first [fileEventChunk] changes waiting; the
  /// rest after another [watchDebounce].
  void _flushFileEvents() {
    _fileEventTimer = null;
    final events = [
      for (final MapEntry(:key, :value) in _fileEvents.entries.take(
        fileEventChunk,
      ))
        LspFileEvent(key, value),
    ];
    for (final event in events) {
      _fileEvents.remove(event.path);
    }
    if (_fileEvents.isNotEmpty) {
      _fileEventTimer = Timer(watchDebounce, _flushFileEvents);
    }
    for (final server in _servers.values) {
      final client = server.client;
      if (client == null || !client.isInitialized) continue;
      final watchers = client.fileWatchers;
      if (watchers.isEmpty) continue;
      client.didChangeWatchedFiles([
        for (final event in events)
          if (_watched(watchers, server.root, event)) event,
      ]);
    }
  }

  /// Whether one of [watchers] (of a server at [root]) watches [event]: by
  /// its path, or one without a base by the path under [root] (worked out
  /// once, not for each watcher).
  bool _watched(
    List<LspFileWatcher> watchers,
    String root,
    LspFileEvent event,
  ) {
    String? relative;
    var inRoot = false;
    var known = false;
    for (final watcher in watchers) {
      if (watcher.matches(event.path, event.type)) return true;
      if (watcher.basePath != null) continue;
      if (!known) {
        known = true;
        inRoot = _paths.isWithin(root, event.path);
        if (inRoot) relative = _paths.relative(event.path, from: root);
      }
      if (inRoot && watcher.matches(relative!, event.type)) return true;
    }
    return false;
  }

  // Answers.

  static LspFeature _featureOf(LanguageRequest request) => switch (request) {
    LanguageRequest.hover => LspFeature.hover,
    LanguageRequest.definition ||
    LanguageRequest.typeDefinition ||
    LanguageRequest.implementation => LspFeature.gotoDefinition,
    LanguageRequest.references => LspFeature.gotoReference,
    LanguageRequest.completion => LspFeature.completion,
    LanguageRequest.signatureHelp => LspFeature.signatureHelp,
    LanguageRequest.rename => LspFeature.rename,
    LanguageRequest.format || LanguageRequest.rangeFormat => LspFeature.format,
    LanguageRequest.documentSymbols => LspFeature.documentSymbols,
    LanguageRequest.codeActions => LspFeature.codeAction,
    LanguageRequest.semanticTokens => LspFeature.semanticTokens,
  };

  /// The running clients attached to [doc] that can answer [request], in
  /// the language's order.
  Iterable<LspClient> _runningFor(
    _Document doc,
    LanguageRequest request,
  ) sync* {
    for (final server in doc.servers) {
      final client = server.client;
      if (server.state != LanguageServerState.running || client == null) {
        continue;
      }
      if (!server.definition.provides(_featureOf(request))) continue;
      if (client.supports(
        request,
        path: doc.path,
        languageId: doc.languageId,
      )) {
        yield client;
      }
    }
  }

  /// Like [_runningFor], after waiting for servers that are starting (or
  /// starting stopped ones).
  Future<(_Document, List<LspClient>)?> _clients(
    String path,
    LanguageRequest request,
  ) async {
    final doc = _documents[_normalize(path)];
    if (doc == null) return null;
    await Future.wait([
      for (final server in doc.servers)
        if (server.definition.provides(_featureOf(request))) _ensure(server),
    ]);
    if (!identical(_documents[doc.path], doc)) return null;
    return (doc, _runningFor(doc, request).toList());
  }

  Future<Object?> _ask(
    LspClient client,
    String method,
    Object? params, {
    Duration? timeout,
  }) async {
    try {
      return await client.request(method, params, timeout: timeout);
    } on Object {
      // An error, a timeout or a crash: no answer from this server.
      return null;
    }
  }

  /// Asks every client able to answer [request], in order.
  Future<List<(LspClient, Object?)>> _askAll(
    String path,
    LanguageRequest request,
    String method,
    Object? Function(_Document doc) params,
  ) async {
    final found = await _clients(path, request);
    if (found == null) return const [];
    final (doc, clients) = found;
    final answers = await Future.wait([
      for (final client in clients) _ask(client, method, params(doc)),
    ]);
    return [for (var i = 0; i < clients.length; i++) (clients[i], answers[i])];
  }

  /// Asks the first client able to answer [request].
  Future<(LspClient, Object?)?> _askFirst(
    String path,
    LanguageRequest request,
    String method,
    Object? Function(_Document doc) params,
  ) async {
    final found = await _clients(path, request);
    if (found == null || found.$2.isEmpty) return null;
    final client = found.$2.first;
    return (client, await _ask(client, method, params(found.$1)));
  }

  static JsonMap _position(_Document doc, LspPosition position) => {
    'textDocument': {'uri': doc.uri},
    'position': position.toJson(),
  };

  @override
  List<LspDiagnostic> diagnosticsFor(String path) {
    path = _normalize(path);
    final byServer = _diagnostics[path];
    if (byServer == null) return const [];
    final order = [...?_documents[path]?.servers];
    return [
      for (final server in order) ...?byServer[server],
      for (final MapEntry(:key, :value) in byServer.entries)
        if (!order.contains(key)) ...value,
    ];
  }

  @override
  Map<String, List<LspDiagnostic>> get allDiagnostics => {
    for (final path in _diagnostics.keys) path: diagnosticsFor(path),
  };

  @override
  bool supports(String path, LanguageRequest request) {
    final doc = _documents[_normalize(path)];
    return doc != null && _runningFor(doc, request).isNotEmpty;
  }

  Set<String> _characters(String path, LanguageRequest request, String key) {
    final doc = _documents[_normalize(path)];
    if (doc == null) return const {};
    return {
      for (final client in _runningFor(doc, request))
        ...client.characters(
          request,
          key,
          path: doc.path,
          languageId: doc.languageId,
        ),
    };
  }

  @override
  Set<String> completionTriggerCharacters(String path) =>
      _characters(path, LanguageRequest.completion, 'triggerCharacters');

  @override
  Set<String> signatureHelpTriggerCharacters(String path) =>
      _characters(path, LanguageRequest.signatureHelp, 'triggerCharacters');

  @override
  Set<String> signatureHelpRetriggerCharacters(String path) =>
      _characters(path, LanguageRequest.signatureHelp, 'retriggerCharacters');

  @override
  Future<LspHover?> hover(String path, LspPosition position) async {
    final answers = await _askAll(
      path,
      LanguageRequest.hover,
      'textDocument/hover',
      (doc) => _position(doc, position),
    );
    final hovers = [
      for (final (_, answer) in answers) ?LspHover.fromJson(answer),
    ];
    if (hovers.isEmpty) return null;
    return LspHover(
      hovers.map((h) => h.markdown).join('\n\n---\n\n'),
      range: hovers.map((h) => h.range).nonNulls.firstOrNull,
    );
  }

  Future<List<LspLocation>> _locations(
    String path,
    LanguageRequest request,
    String method,
    Object? Function(_Document doc) params,
  ) async {
    final answers = await _askAll(path, request, method, params);
    final seen = <String>{};
    return [
      for (final (_, answer) in answers)
        for (final location in LspLocation.listFromJson(answer))
          if (seen.add(
            '${_pathOf(location.uri) ?? location.uri}|${location.range}',
          ))
            location,
    ];
  }

  @override
  Future<List<LspLocation>> definition(String path, LspPosition position) =>
      _locations(
        path,
        LanguageRequest.definition,
        'textDocument/definition',
        (doc) => _position(doc, position),
      );

  @override
  Future<List<LspLocation>> typeDefinition(String path, LspPosition position) =>
      _locations(
        path,
        LanguageRequest.typeDefinition,
        'textDocument/typeDefinition',
        (doc) => _position(doc, position),
      );

  @override
  Future<List<LspLocation>> implementation(String path, LspPosition position) =>
      _locations(
        path,
        LanguageRequest.implementation,
        'textDocument/implementation',
        (doc) => _position(doc, position),
      );

  @override
  Future<List<LspLocation>> references(
    String path,
    LspPosition position, {
    bool includeDeclaration = true,
  }) => _locations(
    path,
    LanguageRequest.references,
    'textDocument/references',
    (doc) => {
      ..._position(doc, position),
      'context': {'includeDeclaration': includeDeclaration},
    },
  );

  @override
  Future<LspCompletionList> completion(
    String path,
    LspPosition position, {
    String? triggerCharacter,
    bool retrigger = false,
  }) async {
    final found = await _clients(path, LanguageRequest.completion);
    if (found == null) return LspCompletionList.empty;
    final (doc, clients) = found;
    final lists = await Future.wait([
      for (final client in clients)
        _ask(client, 'textDocument/completion', {
          ..._position(doc, position),
          'context':
              triggerCharacter != null &&
                  client
                      .characters(
                        LanguageRequest.completion,
                        'triggerCharacters',
                        path: doc.path,
                        languageId: doc.languageId,
                      )
                      .contains(triggerCharacter)
              ? {'triggerKind': 2, 'triggerCharacter': triggerCharacter}
              : {'triggerKind': retrigger ? 3 : 1},
        }).then(
          (answer) =>
              LspCompletionList.fromJson(answer, serverId: client.serverId),
        ),
    ]);
    return LspCompletionList([
      for (final list in lists) ...list.items,
    ], isIncomplete: lists.any((list) => list.isIncomplete));
  }

  LspClient? _clientOf(_Document doc, String? serverId) {
    for (final server in doc.servers) {
      if (server.id == serverId &&
          server.state == LanguageServerState.running) {
        return server.client;
      }
    }
    return null;
  }

  @override
  Future<LspCompletionItem> resolveCompletion(
    String path,
    LspCompletionItem item,
  ) async {
    final doc = _documents[_normalize(path)];
    final client = doc == null ? null : _clientOf(doc, item.serverId);
    if (doc == null || client == null) return item;
    final options = client.optionsFor(
      LanguageRequest.completion,
      path: doc.path,
      languageId: doc.languageId,
    );
    if (options?['resolveProvider'] != true) return item;
    final answer = await _ask(client, 'completionItem/resolve', item.json);
    if (answer is! Map) return item;
    final resolved = answer.cast<String, Object?>();
    return LspCompletionItem.fromJson(
      resolved,
      serverId: item.serverId,
      // Defaults the list gave it are not in what the server sends back.
      defaultRange: resolved['textEdit'] == null ? item.textEdit?.range : null,
      defaultSnippet: item.isSnippet,
    );
  }

  @override
  Future<LspSignatureHelp?> signatureHelp(
    String path,
    LspPosition position, {
    String? triggerCharacter,
    bool retrigger = false,
  }) async {
    final answers = await _askAll(
      path,
      LanguageRequest.signatureHelp,
      'textDocument/signatureHelp',
      (doc) => {
        ..._position(doc, position),
        'context': {
          'triggerKind': triggerCharacter != null ? 2 : (retrigger ? 3 : 1),
          'triggerCharacter': ?triggerCharacter,
          'isRetrigger': retrigger,
        },
      },
    );
    for (final (_, answer) in answers) {
      if (LspSignatureHelp.fromJson(answer) case final help?) return help;
    }
    return null;
  }

  @override
  Future<({LspRange range, String placeholder})?> prepareRename(
    String path,
    LspPosition position,
  ) async {
    final found = await _clients(path, LanguageRequest.rename);
    if (found == null || found.$2.isEmpty) return null;
    final (doc, clients) = found;
    final client = clients.first;
    final options = client.optionsFor(
      LanguageRequest.rename,
      path: doc.path,
      languageId: doc.languageId,
    );
    if (options?['prepareProvider'] != true) {
      return _wordAt(doc.text, position);
    }
    final answer = await _ask(
      client,
      'textDocument/prepareRename',
      _position(doc, position),
    );
    if (answer is! Map) return null;
    final map = answer.cast<String, Object?>();
    if (map['defaultBehavior'] == true) return _wordAt(doc.text, position);
    if (map['range'] case final Map range) {
      final parsed = LspRange.fromJson(range.cast());
      return (
        range: parsed,
        placeholder: map['placeholder'] as String? ?? _textIn(doc.text, parsed),
      );
    }
    if (map.containsKey('start')) {
      final parsed = LspRange.fromJson(map);
      return (range: parsed, placeholder: _textIn(doc.text, parsed));
    }
    return null;
  }

  @override
  Future<LspWorkspaceEdit?> rename(
    String path,
    LspPosition position,
    String newName,
  ) async {
    final answer = await _askFirst(
      path,
      LanguageRequest.rename,
      'textDocument/rename',
      (doc) => {..._position(doc, position), 'newName': newName},
    );
    final edit = answer?.$2;
    return edit is Map
        ? LspWorkspaceEdit.fromJson(edit.cast<String, Object?>())
        : null;
  }

  @override
  Future<List<LspTextEdit>> format(
    String path, {
    LspRange? range,
    required int tabSize,
    required bool insertSpaces,
  }) async {
    final options = {'tabSize': tabSize, 'insertSpaces': insertSpaces};
    final answer = range == null
        ? await _askFirst(
            path,
            LanguageRequest.format,
            'textDocument/formatting',
            (doc) => {
              'textDocument': {'uri': doc.uri},
              'options': options,
            },
          )
        : await _askFirst(
            path,
            LanguageRequest.rangeFormat,
            'textDocument/rangeFormatting',
            (doc) => {
              'textDocument': {'uri': doc.uri},
              'range': range.toJson(),
              'options': options,
            },
          );
    return LspTextEdit.listFromJson(answer?.$2);
  }

  @override
  Future<List<LspDocumentSymbol>> documentSymbols(String path) async {
    final answer = await _askFirst(
      path,
      LanguageRequest.documentSymbols,
      'textDocument/documentSymbol',
      (doc) => {
        'textDocument': {'uri': doc.uri},
      },
    );
    return LspDocumentSymbol.listFromJson(answer?.$2);
  }

  @override
  Future<List<LspCodeAction>> codeActions(
    String path,
    LspRange range, {
    List<LspDiagnostic> diagnostics = const [],
    List<String>? only,
  }) async {
    final answers = await _askAll(
      path,
      LanguageRequest.codeActions,
      'textDocument/codeAction',
      (doc) => {
        'textDocument': {'uri': doc.uri},
        'range': range.toJson(),
        'context': {
          'diagnostics': [for (final d in diagnostics) d.json],
          'only': ?only,
          'triggerKind': 1,
        },
      },
    );
    return [
      for (final (client, answer) in answers)
        if (answer is List)
          for (final action in answer)
            if (action is Map)
              LspCodeAction.fromJson(
                action.cast<String, Object?>(),
                serverId: client.serverId,
              ),
    ];
  }

  @override
  Future<LspCodeAction> resolveCodeAction(
    String path,
    LspCodeAction action,
  ) async {
    final doc = _documents[_normalize(path)];
    final client = doc == null ? null : _clientOf(doc, action.serverId);
    if (doc == null || client == null || action.edit != null) return action;
    final options = client.optionsFor(
      LanguageRequest.codeActions,
      path: doc.path,
      languageId: doc.languageId,
    );
    if (options?['resolveProvider'] != true) return action;
    final answer = await _ask(client, 'codeAction/resolve', action.json);
    return answer is Map
        ? LspCodeAction.fromJson(
            answer.cast<String, Object?>(),
            serverId: action.serverId,
          )
        : action;
  }

  @override
  Future<void> executeCommand(
    String path,
    LspCommand command, {
    String? serverId,
  }) async {
    final doc = _documents[_normalize(path)];
    if (doc == null) return;
    LspClient? client;
    if (serverId != null) {
      client = _clientOf(doc, serverId);
    } else {
      for (final server in doc.servers) {
        final candidate = server.client;
        if (server.state == LanguageServerState.running &&
            candidate != null &&
            candidate.commands.contains(command.command)) {
          client = candidate;
          break;
        }
      }
    }
    if (client == null) return;
    await _ask(client, 'workspace/executeCommand', {
      'command': command.command,
      'arguments': ?command.arguments,
    }, timeout: requestTimeout * 2);
  }

  @override
  Future<List<LspSemanticToken>?> semanticTokens(String path) async {
    final found = await _clients(path, LanguageRequest.semanticTokens);
    if (found == null) return null;
    final (doc, clients) = found;
    for (final client in clients) {
      final legend = client.semanticTokensLegend(
        path: doc.path,
        languageId: doc.languageId,
      );
      if (legend == null) continue;
      final answer = await _ask(client, 'textDocument/semanticTokens/full', {
        'textDocument': {'uri': doc.uri},
      });
      if (answer is! Map || answer['data'] is! List) return null;
      return legend.decode([
        for (final n in answer['data']! as List)
          if (n is num) n.toInt(),
      ]);
    }
    return null;
  }

  @override
  Stream<LspApplyEditRequest> get workspaceEdits => _edits.stream;

  @override
  List<LanguageServerStatus> statusFor(String path) {
    final doc = _documents[_normalize(path)];
    if (doc == null) return const [];
    return [
      for (final (id, server) in doc.entries)
        if (server == null)
          LanguageServerStatus(
            serverId: id,
            state: LanguageServerState.failed,
            message: 'No language server is defined as $id',
          )
        else
          LanguageServerStatus(
            serverId: server.id,
            state: server.state,
            message: server.message,
            progress: server.state == LanguageServerState.running
                ? server.client?.progress
                : null,
            installable:
                server.installable &&
                server.missingRuntime == null &&
                server.state == LanguageServerState.missing,
            missingRuntime: server.missingRuntime,
            retryAt: server.state == LanguageServerState.restarting
                ? server.retryAt
                : null,
          ),
    ];
  }

  /// What a server attached to [path] (or any server named [serverId])
  /// logged and printed, newest last, for an output view.
  List<String> logFor(String serverId, {String? path}) => [
    for (final server in _serversNamed(serverId, path)) ...?server.client?.log,
  ];

  /// The running client of [serverId] for [path] (or any), for tests and
  /// diagnostics.
  @visibleForTesting
  LspClient? clientFor(String serverId, {String? path}) =>
      _serversNamed(serverId, path).map((s) => s.client).nonNulls.firstOrNull;
}

/// The UTF-16 offset of [position] in [text], lines broken at CRLF, CR and
/// LF; characters past a line's end clamp to it.
int _offsetAt(String text, LspPosition position) {
  var offset = 0;
  for (var line = 0; line < position.line; line++) {
    final next = text.indexOf(RegExp('\r\n|\r|\n'), offset);
    if (next < 0) return text.length;
    offset = next + (text.startsWith('\r\n', next) ? 2 : 1);
  }
  var end = offset;
  while (end < text.length &&
      text.codeUnitAt(end) != 0x0A &&
      text.codeUnitAt(end) != 0x0D) {
    end++;
  }
  return math.min(offset + position.character, end);
}

String _textIn(String text, LspRange range) {
  final start = _offsetAt(text, range.start);
  final end = _offsetAt(text, range.end);
  return end > start ? text.substring(start, end) : '';
}

final _word = RegExp(r'[\p{L}\p{N}_$]', unicode: true);

/// The identifier at [position], for rename without a server's prepare.
({LspRange range, String placeholder})? _wordAt(
  String text,
  LspPosition position,
) {
  final offset = _offsetAt(text, position);
  bool word(int i) => i >= 0 && i < text.length && _word.hasMatch(text[i]);
  var start = offset;
  while (word(start - 1)) {
    start--;
  }
  var end = offset;
  while (word(end)) {
    end++;
  }
  if (start == end) return null;
  final lineStart = _offsetAt(text, LspPosition(position.line, 0));
  return (
    range: LspRange(
      LspPosition(position.line, start - lineStart),
      LspPosition(position.line, end - lineStart),
    ),
    placeholder: text.substring(start, end),
  );
}
