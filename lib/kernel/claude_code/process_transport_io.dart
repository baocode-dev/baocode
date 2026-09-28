import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'claude_code_transport.dart';
import 'claude_environment.dart';
import 'cli_locator.dart';

/// Claude Code as a child process, over its stdin and stdout.
class ProcessTransport implements ClaudeCodeTransport {
  ProcessTransport._(this._process) {
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

  static Future<ClaudeCodeTransport> start(ClaudeLaunch launch) async {
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
        includeParentEnvironment: false,
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
