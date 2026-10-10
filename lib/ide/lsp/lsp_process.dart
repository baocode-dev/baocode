import 'lsp_process_stub.dart'
    if (dart.library.io) 'lsp_process_io.dart'
    as platform;

/// How to start one language server process.
class LspLaunch {
  const LspLaunch({
    required this.serverId,
    required this.executable,
    this.arguments = const [],
    required this.workingDirectory,
    this.environment = const {},
  });

  final String serverId;
  final String executable;
  final List<String> arguments;
  final String workingDirectory;

  /// Over the login shell's environment.
  final Map<String, String> environment;
}

/// A running language server: its stdin and stdout carry the protocol.
abstract interface class LspProcess {
  int get pid;
  Stream<List<int>> get stdout;
  Stream<List<int>> get stderr;
  void write(List<int> bytes);
  Future<void> closeStdin();
  Future<int> get exitCode;

  /// Whether the app asked it to stop ([kill], or [stopLspProcesses] as the
  /// app quits): its exit is then no crash.
  bool get stopRequested;

  /// Ends it: politely, or at once when [force].
  void kill({bool force = false});
}

typedef LspProcessStarter = Future<LspProcess> Function(LspLaunch launch);

/// A file or folder under a watched root that changed on disk.
class LspFileEvent {
  const LspFileEvent(this.path, this.type);

  final String path;
  final LspFileChangeType type;

  @override
  String toString() => 'LspFileEvent($path, ${type.name})';
}

/// `FileChangeType` (1-based in the protocol).
enum LspFileChangeType {
  created,
  changed,
  deleted;

  int get protocolValue => index + 1;
}

/// Recursive changes under a folder.
typedef LspDirectoryWatcher = Stream<LspFileEvent> Function(String root);

/// Starts a language server with the login shell's environment, recorded
/// so that [reapLspProcesses] ends it if the app does not; fails with
/// [LspStartException] (always on the web).
Future<LspProcess> startLspProcess(LspLaunch launch) =>
    platform.LspProcesses.start(launch);

/// Ends every language server the app started, and waits for them: for
/// when the app quits.
Future<void> stopLspProcesses() => platform.LspProcesses.stopAll();

/// Ends the language servers an earlier run of the app left running;
/// none on the web.
Future<void> reapLspProcesses() => platform.LspProcesses.reapLeftovers();

/// Watches [root] recursively; nothing on the web.
Stream<LspFileEvent> watchLspDirectory(String root) =>
    platform.LspProcesses.watch(root);

/// Whether a file or folder exists at [path]; false on the web.
bool lspPathExists(String path) => platform.LspProcesses.exists(path);

/// The names in folder [path]; none on the web or when unreadable.
List<String> lspListDirectory(String path) => platform.LspProcesses.list(path);

/// This process's id, sent to servers so they exit when the app is gone;
/// null on the web.
int? get lspClientProcessId => platform.LspProcesses.ownPid;

class LspStartException implements Exception {
  const LspStartException(this.message, {this.detail});

  final String message;
  final String? detail;

  @override
  String toString() => detail == null ? message : '$message: $detail';
}
