// Claude Code of remote projects: run on their host, by its server, as the
// user set it up there (`~/.claude` there, its login, its sessions). A
// session on a provider of the user's takes the provider's key in its flag
// settings, which the server writes to a file only the user reads (in
// memory where the host has a place for it) and deletes as the process
// ends: never in a command line, never left on its disk. The model proxy,
// on this machine, is reached through a port forwarded from the host.

import 'dart:async';
import 'dart:convert';

import 'package:bao_remote/claude.dart';
import 'package:bao_remote/client.dart';
import 'package:bao_remote/files.dart' show IdeFileNotFoundException;

import '../kernel/agent_kernel.dart';
import '../kernel/claude_code/claude_code_transport.dart';
import '../kernel/claude_code/claude_core_setting.dart';
import '../kernel/claude_code/claude_haiku.dart';
import '../kernel/claude_code/claude_storage_io.dart';
import '../kernel/claude_code/dart_core_transport.dart';
import '../kernel/claude_code/process_transport.dart';
import '../models/launch_environment.dart';
import 'remote_claude_install.dart';
import 'remote_location.dart';
import 'ssh_host.dart';

/// What the user is told to run on the host when Claude Code could not be
/// installed there for them, as its install guidance says.
const remoteClaudeInstallCommand =
    'curl -fsSL https://claude.ai/install.sh | bash';

/// Claude Code where [launch]'s project is: on its host for a remote one.
/// BaoCode's own core only on an upstream's model ([ClaudeLaunch.env]):
/// never on what the machine's Claude Code setup names.
Future<ClaudeCodeTransport> startClaude(ClaudeLaunch launch) async {
  final host = RemoteLocation.hostOf(launch.cwd);
  if (host == null) {
    // On this machine: BaoCode's own core, unless the CLI is picked.
    return switch (ClaudeCore.current()) {
      ClaudeCore.builtin when launch.env == null => throw const ClaudeNoModel(
        ClaudeCore.noModel,
      ),
      ClaudeCore.builtin => startDartCore(launch),
      ClaudeCore.cli => startClaudeProcess(launch),
    };
  }
  return RemoteClaudeTransport.start(SshHosts.instance[host], launch);
}

/// What runs Claude Code on [host]: as its server saved in the app says;
/// as ssh reaches it otherwise (one of ~/.ssh/config, one typed), the CLI
/// where it has one, else BaoCode's own core.
SshCore remoteCoreOf(String host) =>
    SshHosts.instance.savedServers()[host]?.core ?? SshCore.auto;

/// Starts Claude Code on [host] with [start], given the core to run
/// ([RemoteClient.startClaude]'s `core`: `builtin`, or null for the CLI; a
/// server of before runs the CLI), as [remoteCoreOf] says. [model]: whether
/// it runs on an upstream's model, which BaoCode's own core needs; without
/// one, the CLI. Where the CLI is wanted and the host has none, it is
/// installed there when [install], as VS Code's extension sets itself up.
Future<RemoteProcess> startRemoteCore(
  SshHost host, {
  required bool model,
  bool install = true,
  required Future<RemoteProcess> Function(String? core) start,
}) async {
  Future<RemoteProcess> cli() async {
    try {
      return await start(null);
    } on ClaudeNotInstalled {
      if (!install) rethrow;
      await installRemoteClaude(host);
      return start(null);
    }
  }

  switch (remoteCoreOf(host.host)) {
    case SshCore.builtin:
      if (!model) throw const ClaudeNoModel(ClaudeCore.noModel);
      return start('builtin');
    case SshCore.cli:
      return cli();
    case SshCore.auto:
      if (!model) return cli();
      try {
        return await start(null);
      } on ClaudeNotInstalled {
        return start('builtin');
      }
  }
}

/// [executable] refused an option BaoCode starts it with, where [cwd]'s
/// project is: whether another, newer, may be started instead. On this
/// machine only: a remote host's is updated there.
Future<bool> rejectTooOldClaude(String cwd, String executable) async {
  if (RemoteLocation.hostOf(cwd) != null) return false;
  return rejectTooOldClaudeProcess(executable);
}

/// [session]'s conversation, read where it was kept.
Future<List<Map<String, Object?>>> readClaudeHistory(
  SessionRecord session,
) async {
  final host = RemoteLocation.hostOf(session.cwd);
  final path = session.path;
  if (host == null || path == null) return ClaudeStorage.read(session);
  final client = await SshHosts.instance[host].ready;
  return client.claudeHistory(path);
}

/// Some of [session]'s conversation, read where it was kept (see
/// ClaudeSessions.readPage): only that comes from a remote project's host.
Future<ClaudeHistoryPage> readClaudeHistoryPage(
  SessionRecord session, {
  required int turns,
  String? before,
}) async {
  final host = RemoteLocation.hostOf(session.cwd);
  final path = session.path;
  if (host == null || path == null) {
    return ClaudeStorage.readPage(session, turns: turns, before: before);
  }
  final client = await SshHosts.instance[host].ready;
  return client.claudeHistoryPage(path, turns: turns, before: before);
}

/// What the session [id], run in [cwd], kept of its goal, read where it
/// was kept (see ClaudeSessions.goal).
Future<List<Map<String, Object?>>> readClaudeGoal(String cwd, String id) async {
  final host = RemoteLocation.hostOf(cwd);
  if (host == null) return const ClaudeStorage().goal(id);
  final client = await SshHosts.instance[host].ready;
  return client.claudeGoal(id);
}

/// Copies the session [id], run in [cwd], into a new one, [into], where
/// it was kept (see ClaudeSessions.fork): its file there.
Future<String> forkClaudeSession(
  String cwd,
  String id,
  String into, {
  String? before,
  String? title,
}) async {
  final host = RemoteLocation.hostOf(cwd);
  if (host == null) {
    return const ClaudeStorage().fork(id, into, before: before, title: title);
  }
  final client = await SshHosts.instance[host].ready;
  return client.claudeFork(id, into, before: before, title: title);
}

/// The setting that keeps Claude Code from asking for the plan usage, as
/// it runs where [cwd] is.
Future<String?> claudeUsageOffByAt(String? cwd) async {
  final host = cwd == null ? null : RemoteLocation.hostOf(cwd);
  if (host == null) return claudeUsageOffBy();
  try {
    final client = await SshHosts.instance[host].ready;
    return await client.claudeUsageOffBy();
  } on Object {
    return null;
  }
}

/// Claude Code's sessions: this machine's, and those of a remote project's
/// host, listed as that project's (their folders as locations).
class ClaudeCatalog implements SessionCatalog, MovesSessions {
  const ClaudeCatalog({this.local = const ClaudeStorage()});

  final ClaudeStorage local;

  /// This machine's alone: a remote project is not moved.
  @override
  Future<int> moveSessions(String from, String to) {
    if (RemoteLocation.isRemote(from) || RemoteLocation.isRemote(to)) {
      throw UnsupportedError('Sessions are only moved on this machine');
    }
    return local.moveSessions(from, to);
  }

  /// The host each remote session listed was found on, to delete it there.
  static final Map<String, String> _hostOf = {};

  @override
  Future<List<ProjectRecord>> projects() => local.projects();

  @override
  Future<List<SessionRecord>> sessionsIn(String cwd) async {
    final host = RemoteLocation.hostOf(cwd);
    if (host == null) return local.sessionsIn(cwd);
    final client = await SshHosts.instance[host].ready;
    final path = RemoteLocation.pathOf(cwd);
    for (final project in await client.claudeProjects()) {
      if (project.path != path) continue;
      final record = ClaudeStorage.projectRecord(
        project,
        location: (path) => RemoteLocation.of(host, path),
      );
      for (final session in record.sessions) {
        _hostOf[session.id] = host;
      }
      return record.sessions;
    }
    return const [];
  }

  @override
  Future<void> delete(String id) async {
    final host = _hostOf[id];
    if (host == null) return local.delete(id);
    final client = await SshHosts.instance[host].ready;
    await client.claudeDelete(id);
  }
}

/// [env] as it is to be on [client]'s host: a model proxy of this machine
/// (`ANTHROPIC_BASE_URL` on the loopback) reached through a port of the
/// host forwarded here.
Future<Map<String, String>?> remoteModelEnvironment(
  RemoteClient client,
  Map<String, String>? env,
) async {
  final base = env?[ClaudeModelVariables.baseUrl];
  if (env == null || base == null) return env;
  final uri = Uri.tryParse(base);
  if (uri == null ||
      !const {'127.0.0.1', 'localhost', '::1'}.contains(uri.host) ||
      !uri.hasPort) {
    return env;
  }
  final forwards = _forwards[client] ??= {};
  final forward = await (forwards[uri.port] ??= client.forward(uri.port));
  return {
    ...env,
    ClaudeModelVariables.baseUrl: uri
        .replace(host: '127.0.0.1', port: forward.remotePort)
        .toString(),
  };
}

/// The ports forwarded for each connection, one per port here.
final Expando<Map<int, Future<RemoteForward>>> _forwards = Expando();

/// The host's connection, or Claude Code unavailable saying why not.
Future<RemoteClient> _clientOf(SshHost host) async {
  try {
    return await host.ready;
  } on SshConnectException catch (error) {
    throw ClaudeUnavailable(
      'Could not connect to ${RemoteLocation.hostName(host.host)}: ${error.message}',
      detail: error.detail,
    );
  } on Object catch (error) {
    throw ClaudeUnavailable(
      'Could not connect to ${RemoteLocation.hostName(host.host)}',
      detail: '$error',
    );
  }
}

/// One question to Claude Haiku on [host] (see askClaudeHaiku): its flag
/// settings, with a provider's key, given to the server to write to a file
/// only the user reads there.
Future<String> askRemoteHaiku(
  SshHost host,
  String system,
  String prompt, {
  Future<void>? cancel,
  String? model,
  Map<String, String>? env,
}) async {
  final RemoteClient client;
  final RemoteProcess process;
  try {
    client = await host.ready;
    final remoteEnv = await remoteModelEnvironment(client, env);
    process = await startRemoteCore(
      host,
      model: remoteEnv != null,
      install: false,
      start: (core) => client.startClaude(
        cwd: client.hello?.home ?? '/',
        arguments: claudeHaikuArguments(system, model: model),
        settings: remoteEnv == null ? null : {'env': remoteEnv},
        cleared: [if (remoteEnv != null) ...ClaudeModelVariables.inherited],
        core: core,
      ),
    );
  } on Object catch (error) {
    throw ClaudeHaikuException(
      'Claude Code on ${RemoteLocation.hostName(host.host)}: $error',
    );
  }
  var cancelled = false;
  unawaited(
    cancel?.then((_) {
      cancelled = true;
      process.kill();
    }),
  );
  final stdout = process.stdout
      .transform(const Utf8Decoder(allowMalformed: true))
      .join();
  final stderr = process.stderr
      .transform(const Utf8Decoder(allowMalformed: true))
      .join();
  process.write(utf8.encode(prompt));
  unawaited(process.closeStdin());
  final code = await process.exitCode.timeout(
    const Duration(minutes: 2),
    onTimeout: () {
      process.kill(force: true);
      throw const ClaudeHaikuException('Claude Code took too long to answer.');
    },
  );
  if (cancelled) throw const ClaudeHaikuCancelled();
  return claudeHaikuAnswer(await stdout, await stderr, code);
}

/// Claude Code on a remote host, over its server: the same lines as a
/// local process's ([ProcessTransport]).
class RemoteClaudeTransport implements ClaudeCodeTransport {
  RemoteClaudeTransport._(this._process) {
    _live.add(this);
    _process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(
          _line,
          onError: (Object e) => _stderrLine('$e'),
          onDone: _stdoutDone,
        );
    _process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(_stderrLine, onError: (Object e) => _stderrLine('$e'));
    unawaited(_process.exitCode.then(_exited));
  }

  /// A transport over [process], e.g. a fake under test.
  factory RemoteClaudeTransport.forProcess(RemoteProcess process) =>
      RemoteClaudeTransport._(process);

  /// Those running, for the quit confirmation's count and to end them.
  static final Set<RemoteClaudeTransport> _live = {};

  static int get running => _live.length;

  /// Ends them all: for when the app quits.
  static Future<void> stopAll() async {
    final live = [..._live];
    for (final transport in live) {
      transport.close();
    }
    await Future.wait([
      for (final transport in live)
        transport.exited.timeout(
          const Duration(seconds: 3),
          onTimeout: () => transport._process.kill(force: true),
        ),
    ]);
  }

  static Future<ClaudeCodeTransport> start(
    SshHost host,
    ClaudeLaunch launch,
  ) async {
    final client = await _clientOf(host);
    final cwd = RemoteLocation.pathOf(launch.cwd);
    final env = await remoteModelEnvironment(client, launch.env);
    final started = launch.copyWith(cwd: cwd, env: env);
    try {
      final process = await startRemoteCore(
        host,
        model: env != null,
        start: (core) => client.startClaude(
          cwd: cwd,
          // A key in its flag settings: written to a file there instead.
          arguments: started.hasSecrets
              ? started.argumentsWithoutSettings
              : started.arguments,
          settings: started.hasSecrets ? started.settings : null,
          cleared: [if (env != null) ...ClaudeModelVariables.inherited],
          environment: ClaudeLaunch.environment,
          core: core,
        ),
      );
      return RemoteClaudeTransport._(process);
    } on ClaudeDownloadFailed catch (error) {
      throw ClaudeUnavailable(
        'Claude Code could not be installed on '
        '${RemoteLocation.hostName(host.host)}',
        detail:
            '${error.message}${error.detail == null ? '' : ': ${error.detail}'}'
            '\n\nInstall it there, in a terminal of the project:\n'
            '$remoteClaudeInstallCommand',
      );
    } on ClaudeNoModel {
      // The app asks for a model to set up: not the host's to say.
      rethrow;
    } on ClaudeNotInstalled catch (error) {
      throw ClaudeUnavailable(
        'Claude Code is not installed on ${RemoteLocation.hostName(host.host)}',
        detail:
            '${error.detail ?? error.message}\n\nInstall it there, in a '
            'terminal of the project:\n$remoteClaudeInstallCommand',
      );
    } on ClaudeUnavailable catch (error) {
      throw ClaudeUnavailable(
        '${error.message} (on ${RemoteLocation.hostName(host.host)})',
        detail: error.detail,
      );
    } on IdeFileNotFoundException {
      throw ClaudeFolderGone(cwd);
    } on RpcClosed {
      throw ClaudeUnavailable(
        'The connection to ${RemoteLocation.hostName(host.host)} was lost',
      );
    }
  }

  final RemoteProcess _process;
  final StreamController<Map<String, Object?>> _messages =
      StreamController.broadcast();
  final List<String> _stderr = [];
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
      _stderrLine(line);
    }
  }

  void _stderrLine(String line) {
    _stderr.add(line);
    if (_stderr.length > 30) _stderr.removeAt(0);
  }

  void _stdoutDone() {
    _stdoutClosed = true;
    _finish();
  }

  void _exited(int code) {
    _exitCode = code;
    _live.remove(this);
    if (code == RemoteProcess.lostExitCode) {
      _stderrLine('The connection to the remote host was lost.');
      _stdoutClosed = true;
    }
    _finish();
  }

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
    _process.write(utf8.encode('${jsonEncode(message)}\n'));
  }

  @override
  Future<void> get exited => _process.exitCode.then((_) {});

  @override
  void close() {
    if (_exitCode != null) return;
    unawaited(_process.closeStdin());
    _process.kill();
  }
}
