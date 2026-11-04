import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:bao_conpty/bao_conpty.dart';
import 'package:path/path.dart' as p;

import '../claude/claude_environment.dart';
import '../protocol.dart';
import '../platform/process_tree.dart';
import '../pty/posix_pty.dart';
import '../rpc/rpc_peer.dart';
import '../terminal/shell_integration_files.dart';
import '../terminal/shell_integration_injection.dart';
import '../terminal/terminal_shell.dart';
import 'remote_server.dart';

/// The terminals of the remote projects: the user's shell there on a
/// pseudo terminal ([PosixPty]; on Windows a pseudo console, package
/// bao_pty's, PowerShell the shell), in the environment a terminal gives, with
/// VS Code's shell integration unless the app says not to. Where the
/// Claude Code run is the one the server installed, its `claude` is on the
/// PATH there, as VS Code puts `code` on its terminals'.
class ServerPty {
  ServerPty(
    this._peer, {
    void Function(String message)? log,
    Future<String?> Function()? claudeDirectory,
  }) : _log = log ?? ((_) {}),
       _claudeDirectory = claudeDirectory ?? (() async => null) {
    final handlers = _peer.handlers;
    handlers[RemoteProtocol.ptyStart] = (params, _) => _start(paramsOf(params));
    handlers[RemoteProtocol.ptyWrite] = (params, _) {
      final args = paramsOf(params);
      _ptys[args['id']]?.write(decodeBytes(args['data']));
      return null;
    };
    handlers[RemoteProtocol.ptyResize] = (params, _) {
      final args = paramsOf(params);
      _ptys[args['id']]?.resize(args['columns'] as int, args['rows'] as int);
      return null;
    };
    handlers[RemoteProtocol.ptyKill] = (params, _) {
      final args = paramsOf(params);
      _ptys[args['id']]?.kill(args['signal'] as int? ?? 1);
      return null;
    };
    handlers[RemoteProtocol.ptyProfiles] = (_, _) async {
      final environment = await ClaudeEnvironment.of();
      final shell = _defaultShell(environment);
      if (_os == TerminalOs.windows) {
        final comspec = environment['ComSpec'] ?? environment['COMSPEC'];
        return {
          'shell': [shell.executable, ...shell.arguments],
          'shells': {
            for (final path in windowsPowerShells(environment, list: _list))
              if (_exists(path)) path,
            if (comspec != null && comspec.isNotEmpty) comspec,
          }.toList(),
        };
      }
      String? shells;
      try {
        shells = await File('/etc/shells').readAsString();
      } on FileSystemException {
        shells = null;
      }
      return {
        'shell': [shell.executable, ...shell.arguments],
        'shells': [
          for (final line in (shells ?? '').split('\n'))
            if (line.trim().startsWith('/')) line.trim(),
        ],
      };
    };
  }

  final RpcPeer _peer;
  final void Function(String message) _log;
  final Future<String?> Function() _claudeDirectory;
  final Map<int, _Terminal> _ptys = {};
  int _nextId = 0;

  static TerminalOs get _os => Platform.isWindows
      ? TerminalOs.windows
      : Platform.isMacOS
      ? TerminalOs.macOS
      : TerminalOs.linux;

  static bool _exists(String path) => File(path).existsSync();

  static List<String> _list(String directory) {
    try {
      return [
        for (final entity in Directory(directory).listSync())
          p.basename(entity.path),
      ];
    } on FileSystemException {
      return const [];
    }
  }

  TerminalShell _defaultShell(Map<String, String> environment) =>
      defaultTerminalShell(
        _os,
        environment,
        exists: _exists,
        list: _os == TerminalOs.windows ? _list : (directory) => const [],
      );

  Future<Map<String, Object?>> _start(Map<String, Object?> args) async {
    final base = await ClaudeEnvironment.of();
    final os = _os;
    final shell = switch (args['shell']) {
      [final String executable, ...final rest] => (
        executable: executable,
        arguments: rest.cast<String>(),
      ),
      _ => _defaultShell(base),
    };
    var arguments = shell.arguments;
    final environment = terminalEnvironment(
      base,
      os: os,
      locale: args['locale'] as String?,
      version: args['version'] as String?,
    );
    // The app's for the host's terminals (where adb's server is, say).
    if (args['environment'] case final Map<Object?, Object?> extra) {
      for (final MapEntry(:key, :value) in extra.entries) {
        if ((key, value) case (final String name, final String text)) {
          environment[name] = text;
        }
      }
    }
    var nonce = '';
    if (args['shellIntegration'] != false) {
      nonce = args['nonce'] as String? ?? generateShellIntegrationNonce();
      final injection = prepareShellIntegration(
        executable: shell.executable,
        arguments: arguments,
        environment: environment,
        os: os,
        nonce: nonce,
      );
      final applied = shellIntegrationApplied(
        arguments,
        injection,
        nonce: nonce,
      );
      arguments = applied.arguments;
      environment.addAll(applied.mixin);
    }
    if (await _claudeDirectory() case final claude?) {
      // After the user's own; and again once a login shell's profile has
      // set PATH anew (/etc/profile does on Debian), by the integration.
      final separator = os == TerminalOs.windows ? ';' : ':';
      final name = os == TerminalOs.windows
          ? environment.keys.firstWhere(
              (key) => key.toUpperCase() == 'PATH',
              orElse: () => 'Path',
            )
          : 'PATH';
      final path = environment[name];
      environment[name] = path == null || path.isEmpty
          ? claude
          : '$path$separator$claude';
      if (nonce.isNotEmpty) {
        environment['VSCODE_PATH_PREFIX'] = '$claude$separator';
      }
    }
    final columns = args['columns'] as int? ?? 80;
    final rows = args['rows'] as int? ?? 24;
    final pty = os == TerminalOs.windows
        ? _WindowsTerminal(
            await WindowsPty.start(
              PtyLaunch(
                executable: shell.executable,
                arguments: arguments,
                workingDirectory: args['cwd'] as String,
                environment: environment,
                columns: columns,
                rows: rows,
              ),
              environment,
            ),
          )
        : _PosixTerminal(
            await PosixPty.start(
              shell.executable,
              arguments,
              workingDirectory: args['cwd'] as String,
              environment: environment,
              columns: columns,
              rows: rows,
            ),
          );
    final id = ++_nextId;
    _ptys[id] = pty;
    pty.output.listen(
      (data) => _peer.notify(RemoteProtocol.ptyOutput, {
        'id': id,
        'data': encodeBytes(data),
      }),
      onError: (Object error) => _log('Terminal $id: $error'),
    );
    unawaited(
      pty.exitCode.then((code) {
        _ptys.remove(id);
        _peer.notify(RemoteProtocol.ptyExit, {'id': id, 'code': code});
      }),
    );
    return {
      'id': id,
      'pid': pty.pid,
      'executable': shell.executable,
      'arguments': arguments,
      'nonce': nonce,
    };
  }

  /// Hangs up every terminal, and kills those still there after [timeout].
  Future<void> stopAll({Duration timeout = const Duration(seconds: 2)}) async {
    await Future.wait([
      for (final pty in [..._ptys.values])
        () async {
          pty.kill();
          try {
            await pty.exitCode.timeout(timeout);
          } on TimeoutException {
            pty.kill(9);
          }
        }(),
    ]);
  }
}

/// A terminal's process: on a pseudo terminal of the server's own (Linux,
/// macOS), or on Windows' pseudo console.
sealed class _Terminal {
  int get pid;
  Stream<Uint8List> get output;
  Future<int> get exitCode;
  void write(List<int> data);
  void resize(int columns, int rows);

  /// [signal] (a hangup by default); on Windows, which has none, the
  /// process ends, with every process it started.
  void kill([int signal = 1]);
}

class _PosixTerminal extends _Terminal {
  _PosixTerminal(this._pty);

  final PosixPty _pty;

  @override
  int get pid => _pty.pid;
  @override
  Stream<Uint8List> get output => _pty.output;
  @override
  Future<int> get exitCode => _pty.exitCode;
  @override
  void write(List<int> data) => _pty.write(data);
  @override
  void resize(int columns, int rows) => _pty.resize(columns, rows);
  @override
  void kill([int signal = 1]) => _pty.kill(signal);
}

class _WindowsTerminal extends _Terminal {
  _WindowsTerminal(this._pty);

  final Pty _pty;

  @override
  int get pid => _pty.pid;
  @override
  Stream<Uint8List> get output => _pty.output;
  @override
  Future<int> get exitCode => _pty.exitCode;
  @override
  void write(List<int> data) => _pty.write(Uint8List.fromList(data));
  @override
  void resize(int columns, int rows) => _pty.resize(columns, rows);
  @override
  void kill([int signal = 1]) {
    // The shell's own, as a console's close would not end those started
    // apart from it: the tree, as Windows has no process groups to signal.
    killProcessTree(_pty.pid);
    _pty.kill(PtySignal.kill);
  }
}
