import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../platform/data_dir.dart';
import '../../platform/child_process_registry.dart';
import 'claude_code_transport.dart';
import 'claude_environment.dart';
import 'cli_locator.dart';

/// Claude Code as a child process, over its stdin and stdout.
class ProcessTransport implements ClaudeCodeTransport {
  ProcessTransport._(this._process) {
    _live.add(this);
    unawaited(registry.add(_process.pid));
    _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_line, onDone: _stdoutDone);
    _process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_stderrLine);
    unawaited(_process.exitCode.then(_exited));
  }

  /// A transport over [process], e.g. a stand-in process under test.
  @visibleForTesting
  factory ProcessTransport.forProcess(Process process) =>
      ProcessTransport._(process);

  /// Where the running processes are kept track of across runs.
  @visibleForTesting
  static ClaudeProcessRegistry registry = ClaudeProcessRegistry(
    file: File(DataDirectory.current.processRegistryFile('claude')),
  );

  /// The processes this run of the app started and that still run.
  static final Set<ProcessTransport> _live = {};

  /// Ends every Claude Code process this run started, and waits (up to
  /// [timeout] each) for them to go: done as the app quits, so a turn under
  /// way does not go on unseen, spending tokens, after the app is gone.
  static Future<void> stopAll({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    await Future.wait([
      for (final transport in [..._live]) transport._stop(timeout),
    ]);
    // Their entries gone from the list before the app is.
    await registry.flush();
  }

  /// Ends the processes an earlier run left behind; see
  /// [ClaudeProcessRegistry].
  static Future<void> reapLeftovers() => registry.reaped;

  Future<void> _stop(Duration timeout) async {
    close();
    try {
      await _process.exitCode.timeout(timeout);
    } on TimeoutException {
      _process.kill(ProcessSignal.sigkill);
    }
  }

  static Future<ClaudeCodeTransport> start(ClaudeLaunch launch) async {
    // Left over from a run that ended without stopping them: gone first, so
    // two processes never go on with one session.
    await registry.reaped;
    final cli = await CliLocator.locate();
    if (!Directory(launch.cwd).existsSync()) {
      throw ClaudeUnavailable('The project folder is gone: ${launch.cwd}');
    }
    try {
      final process = await Process.start(
        cli.executable,
        launch.arguments,
        workingDirectory: launch.cwd,
        environment: {
          ...cli.environment,
          ...ClaudeLaunch.environment,
          ...ClaudeEnvironment.stateDirectory(cli.environment),
        },
        // The login shell's environment is the whole of it; on Windows it
        // is the app's own, and the child needs the parent's beside it for
        // what `cmd.exe` itself runs on (COMSPEC, PATHEXT, …).
        includeParentEnvironment: Platform.isWindows,
        // An npm shim is a `.cmd`, which only the shell can run.
        runInShell: cli.throughShell,
      );
      return ProcessTransport._(process);
    } on ProcessException catch (error) {
      throw ClaudeUnavailable(
        'Claude Code could not start',
        detail: error.message,
      );
    }
  }

  /// [ClaudeEnvironment.essentialTrafficVariable], if the CLI runs with it
  /// set: it then sends no request for the plan usage.
  static Future<String?> usageOffBy() async {
    const setting = ClaudeEnvironment.essentialTrafficVariable;
    final value = (await ClaudeEnvironment.of())[setting];
    return value == null || value.isEmpty ? null : setting;
  }

  final Process _process;
  final StreamController<Map<String, Object?>> _messages =
      StreamController.broadcast();

  /// The last lines it printed on stderr, to say why it failed.
  final List<String> _stderr = [];
  static const _stderrLines = 30;

  int? _exitCode;
  bool _stdoutClosed = false;

  @override
  Stream<Map<String, Object?>> get messages => _messages.stream;

  void _line(String line) {
    if (line.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(line);
      if (decoded is Map<String, Object?>) _messages.add(decoded);
    } on FormatException {
      // Not protocol (e.g. a warning printed to stdout): keep it for the
      // failure report.
      _stderrLine(line);
    }
  }

  void _stderrLine(String line) {
    _stderr.add(line);
    if (_stderr.length > _stderrLines) _stderr.removeAt(0);
  }

  void _stdoutDone() {
    _stdoutClosed = true;
    _finish();
  }

  void _exited(int code) {
    _exitCode = code;
    _live.remove(this);
    unawaited(registry.remove(_process.pid));
    _finish();
  }

  /// Ends the stream once both the output is read and the process gone,
  /// so its last messages come before the exit.
  void _finish() {
    final code = _exitCode;
    if (code == null || !_stdoutClosed || _messages.isClosed) return;
    _messages
      ..add(ClaudeExit.message(code, _stderr.join('\n')))
      ..close();
  }

  @override
  void write(Map<String, Object?> message) {
    if (_exitCode != null) return;
    try {
      _process.stdin.writeln(jsonEncode(message));
    } on StateError {
      // Closed under us: the exit message follows.
    }
  }

  @override
  Future<void> get exited => _process.exitCode.then((_) {});

  @override
  void close() {
    if (_exitCode != null) return;
    unawaited(_process.stdin.close().catchError((_) {}));
    _process.kill();
  }
}

/// The Claude Code processes the app has running (`claude-processes.json`);
/// see [ChildProcessRegistry]. Entries a run recorded without a command
/// line are ended only when they run Claude Code with stream-json.
class ClaudeProcessRegistry extends ChildProcessRegistry {
  ClaudeProcessRegistry({
    required super.file,
    super.ownPid,
    super.lookup,
    super.signal,
  }) : super(recognizes: _isClaude);

  static bool _isClaude(String command) =>
      command.contains('claude') && command.contains('stream-json');
}
