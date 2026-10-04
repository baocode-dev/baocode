import 'dart:async';
import 'dart:io';

import '../claude/claude_environment.dart';
import '../protocol.dart';
import '../pty/posix_pty.dart';
import '../rpc/rpc_peer.dart';
import '../terminal/shell_integration_files.dart';
import '../terminal/shell_integration_injection.dart';
import '../terminal/terminal_shell.dart';
import 'remote_server.dart';

/// The terminals of the remote projects: the user's shell there on a
/// pseudo terminal ([PosixPty]), in the environment a terminal gives, with
/// VS Code's shell integration unless the app says not to.
class ServerPty {
  ServerPty(this._peer, {void Function(String message)? log})
    : _log = log ?? ((_) {}) {
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
  final Map<int, PosixPty> _ptys = {};
  int _nextId = 0;

  static TerminalOs get _os =>
      Platform.isMacOS ? TerminalOs.macOS : TerminalOs.linux;

  TerminalShell _defaultShell(Map<String, String> environment) =>
      defaultTerminalShell(
        _os,
        environment,
        exists: (path) => File(path).existsSync(),
        list: (directory) => const [],
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
    var nonce = '';
    if (args['shellIntegration'] != false) {
      nonce = generateShellIntegrationNonce();
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
    final pty = await PosixPty.start(
      shell.executable,
      arguments,
      workingDirectory: args['cwd'] as String,
      environment: environment,
      columns: args['columns'] as int? ?? 80,
      rows: args['rows'] as int? ?? 24,
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
