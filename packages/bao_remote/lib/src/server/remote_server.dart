import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:path/path.dart' as p;

import '../claude/claude_environment.dart';
import '../claude/claude_sessions.dart';
import '../claude/claude_settings_file.dart';
import '../claude/claude_release.dart';
import '../files/ide_file.dart';
import '../files/local_files.dart';
import '../files/recursive_watch.dart';
import '../git/git_runner.dart';
import '../platform/app_paths.dart';
import '../protocol.dart';
import '../rpc/rpc_peer.dart';
import '../search/local_search.dart';
import 'server_lsp.dart';
import 'server_claude.dart';
import 'server_pty.dart';
import 'server_review.dart';
import 'server_streams.dart';
import 'server_tcp.dart';

/// Params as a map, whatever came.
Map<String, Object?> paramsOf(Object? params) => switch (params) {
  final Map map => map.cast<String, Object?>(),
  _ => const {},
};

/// The server's side of a connection: everything a remote project needs
/// of this machine, answered over [peer]. Each process it starts (Claude
/// Code, language servers, terminals, commands) is its own to end: all of
/// them go with [shutdown], which the connection ending calls.
class RemoteServer {
  RemoteServer(
    this.peer, {
    required this.dataDir,
    this.version = '',
    void Function(String message)? log,
  }) : _log = log ?? ((_) {}) {
    _streams = ServerStreams(peer);
    ServerReview(peer, checkpoints: p.join(dataDir, 'checkpoints'));
    _pty = ServerPty(peer, log: _log);
    _tcp = ServerTcp(peer);
    _lsp = ServerLsp(
      peer,
      _streams,
      installRoot: p.join(dataDir, 'lsp', 'servers'),
    );
    _claude = ServerClaude(
      peer,
      _streams,
      managed: ManagedClaude(p.join(dataDir, 'claude')),
      platform: ClaudeRelease.platformOf(currentPlatform()),
    );
    _register();
    unawaited(peer.done.then((_) => shutdown()));
  }

  final RpcPeer peer;

  /// Where the server keeps its state: `~/.baocode-server/data`.
  final String dataDir;

  /// The build of the server, said in [RemoteHello.version].
  final String version;
  final void Function(String message) _log;
  late final ServerStreams _streams;
  late final ServerPty _pty;
  late final ServerTcp _tcp;
  late final ServerLsp _lsp;
  late final ServerClaude _claude;
  final Map<String, LocalFiles> _files = {};
  final Map<int, _ServerProcess> _processes = {};
  int _nextProcess = 0;
  Future<void>? _shutdown;

  void _register() {
    final handlers = peer.handlers;
    handlers[RemoteProtocol.initialize] = (_, _) => hello().toJson();
    handlers[RemoteProtocol.shutdown] = (_, _) async {
      // Answered first, then gone.
      Timer.run(() => unawaited(shutdown()));
      return null;
    };

    // Files.
    handlers[RemoteProtocol.fsList] = (params, _) async {
      final args = paramsOf(params);
      final files = await _filesOf(args).list(args['path'] as String);
      return [
        for (final file in files) [file.path, file.name, file.isDirectory],
      ];
    };
    handlers[RemoteProtocol.fsRead] = (params, _) {
      final args = paramsOf(params);
      return _filesOf(args)
          .read(args['path'] as String, force: args['force'] == true);
    };
    handlers[RemoteProtocol.fsWrite] = (params, _) async {
      final args = paramsOf(params);
      await _filesOf(args).write(
        args['path'] as String,
        args['text'] as String,
        expectedText: args['expectedText'] as String?,
      );
      return null;
    };
    handlers[RemoteProtocol.fsCreate] = (params, _) async {
      final args = paramsOf(params);
      await _filesOf(args)
          .create(args['path'] as String, directory: args['directory'] == true);
      return null;
    };
    handlers[RemoteProtocol.fsRename] = (params, _) async {
      final args = paramsOf(params);
      await _filesOf(args).rename(args['from'] as String, args['to'] as String);
      return null;
    };
    handlers[RemoteProtocol.fsCopy] = (params, _) async {
      final args = paramsOf(params);
      await _filesOf(args).copy(args['from'] as String, args['to'] as String);
      return null;
    };
    handlers[RemoteProtocol.fsDelete] = (params, _) async {
      final args = paramsOf(params);
      await _filesOf(args).delete(args['path'] as String);
      return null;
    };
    handlers[RemoteProtocol.fsWriteBytes] = (params, _) async {
      final args = paramsOf(params);
      await _filesOf(args)
          .writeBytes(args['path'] as String, decodeBytes(args['data']));
      return null;
    };
    handlers[RemoteProtocol.fsReadBytes] = (params, _) async =>
        encodeBytes(await readFileBytes(paramsOf(params)['path'] as String));
    handlers[RemoteProtocol.fsWalk] = (params, _) async {
      final args = paramsOf(params);
      final listing = await walkProjectFiles(args['root'] as String, {
        ...?(args['excluded'] as List?)?.cast<String>(),
      }, args['limit'] as int? ?? 50000);
      return {'paths': listing.paths, 'truncated': listing.truncated};
    };
    handlers[RemoteProtocol.fsWatch] = (params, _) {
      final args = paramsOf(params);
      final path = args['path'] as String;
      if (args['recursive'] != true) {
        return _streams.open(watchDirectory(path).map((_) => null));
      }
      final excluded = {...?(args['excluded'] as List?)?.cast<String>()};
      return _streams.open(
        watchRecursively(
          path,
          skip: (dir) => excluded.contains(p.basename(dir)),
          onLimit: _log,
        ).map((event) => [event.path, event.change.index]),
      );
    };
    handlers[RemoteProtocol.fsStat] = (params, _) async {
      final path = paramsOf(params)['path'] as String;
      return switch (await FileSystemEntity.type(path)) {
        FileSystemEntityType.file => 'file',
        FileSystemEntityType.directory => 'directory',
        FileSystemEntityType.notFound => null,
        _ => 'other',
      };
    };
    handlers[RemoteProtocol.fsEntries] = (params, _) async {
      final path = paramsOf(params)['path'] as String;
      try {
        return [
          await for (final entity in Directory(path).list())
            p.basename(entity.path),
        ];
      } on FileSystemException {
        return const <String>[];
      }
    };
    handlers[RemoteProtocol.fsRealPath] = (params, _) async {
      final path = AppPaths.expandHome(paramsOf(params)['path'] as String);
      final absolute = p.normalize(p.absolute(path));
      try {
        return await Directory(absolute).resolveSymbolicLinks();
      } on FileSystemException {
        throw IdeFileNotFoundException(absolute);
      }
    };

    // Search and Git.
    handlers[RemoteProtocol.searchText] = (params, _) {
      final args = paramsOf(params);
      return _streams.open(
        searchText(
          args['root'] as String,
          textQueryFromJson(paramsOf(args['query'])),
        ).map(searchItemToJson),
      );
    };
    handlers[RemoteProtocol.gitRun] = (params, _) async {
      final args = paramsOf(params);
      final output = await runGit(
        (args['arguments'] as List).cast<String>(),
        workingDirectory: args['cwd'] as String,
      );
      return {
        'exitCode': output.exitCode,
        'stdout': output.stdout,
        'stderr': output.stderr,
      };
    };
    handlers[RemoteProtocol.gitWatch] = (params, _) => _streams.open(
      watchRepositoryRecursively(paramsOf(params)['root'] as String),
    );

    // Processes.
    handlers[RemoteProtocol.processStart] = (params, _) async {
      final args = paramsOf(params);
      final environment = await _environment(args);
      final process = await Process.start(
        args['executable'] as String,
        (args['arguments'] as List? ?? const []).cast<String>(),
        workingDirectory: args['cwd'] as String?,
        environment: environment,
        includeParentEnvironment: args['login'] != true,
      );
      return _track(process);
    };
    handlers[RemoteProtocol.processRun] = (params, call) async {
      final args = paramsOf(params);
      final process = await Process.start(
        args['executable'] as String,
        (args['arguments'] as List? ?? const []).cast<String>(),
        workingDirectory: args['cwd'] as String?,
        environment: await _environment(args),
        includeParentEnvironment: args['login'] != true,
      );
      unawaited(call.cancelled.then((_) => process.kill()));
      final stdout = process.stdout.transform(utf8.decoder).join();
      final stderr = process.stderr.transform(utf8.decoder).join();
      if (args['stdin'] case final String input) {
        process.stdin.add(utf8.encode(input));
      }
      unawaited(process.stdin.close().catchError((Object _) {}));
      return {
        'exitCode': await process.exitCode,
        'stdout': await stdout,
        'stderr': await stderr,
      };
    };
    handlers[RemoteProtocol.processWrite] = (params, _) {
      final args = paramsOf(params);
      _processes[args['id']]?.write(decodeBytes(args['data']));
      return null;
    };
    handlers[RemoteProtocol.processCloseStdin] = (params, _) async {
      await _processes[paramsOf(params)['id']]?.closeStdin();
      return null;
    };
    handlers[RemoteProtocol.processKill] = (params, _) {
      final args = paramsOf(params);
      _processes[args['id']]?.kill(force: args['force'] == true);
      return null;
    };

    // Claude Code.
    handlers[RemoteProtocol.claudeLocate] = (_, _) async =>
        (await _claude.locate()).executable;
    handlers[RemoteProtocol.claudeStart] = (params, _) async {
      final args = paramsOf(params);
      final cli = await _claude.locate();
      final cwd = args['cwd'] as String;
      if (!Directory(cwd).existsSync()) {
        throw IdeFileNotFoundException(cwd);
      }
      // A key goes in a file only the user reads (in memory where there is
      // a place for it), never the command line.
      final settings = switch (args['settings']) {
        final Map settings => await ClaudeSettingsFile.write(
          settings.cast<String, Object?>(),
        ),
        _ => null,
      };
      final Process process;
      try {
        process = await Process.start(
          cli.executable,
          [
            ...(args['arguments'] as List).cast<String>(),
            if (settings != null) ...['--settings', settings],
          ],
          workingDirectory: cwd,
          environment: {
            ...cli.environment,
            for (final name in (args['cleared'] as List? ?? const []))
              name as String: '',
            ...?(args['environment'] as Map?)?.cast<String, String>(),
            ...ClaudeEnvironment.stateDirectory(cli.environment),
          },
          includeParentEnvironment: false,
        );
      } on Object {
        if (settings != null) await ClaudeSettingsFile.delete(settings);
        rethrow;
      }
      if (settings != null) {
        unawaited(
          process.exitCode.then((_) => ClaudeSettingsFile.delete(settings)),
        );
      }
      return _track(process);
    };
    handlers[RemoteProtocol.claudeProjects] = (_, _) async => [
      for (final project in await _sessions.projects()) project.toJson(),
    ];
    handlers[RemoteProtocol.claudeRead] = (params, _) =>
        ClaudeSessions.read(paramsOf(params)['path'] as String);
    handlers[RemoteProtocol.claudeDelete] = (params, _) async {
      await _sessions.delete(paramsOf(params)['id'] as String);
      return null;
    };
    handlers[RemoteProtocol.claudeUsageOffBy] = (_, _) async {
      const setting = ClaudeEnvironment.essentialTrafficVariable;
      final value = (await ClaudeEnvironment.of())[setting];
      return value == null || value.isEmpty ? null : setting;
    };
  }

  ClaudeSessions get _sessions =>
      ClaudeSessions(cacheFile: p.join(dataDir, 'claude-sessions.json'));

  LocalFiles _filesOf(Map<String, Object?> args) {
    final root = args['root'] as String;
    return _files[root] ??= LocalFiles(root);
  }

  /// A process's environment: the login shell's under [args]' own when it
  /// asks for it (`login`), else the server's with them.
  Future<Map<String, String>?> _environment(Map<String, Object?> args) async {
    final overlay = (args['environment'] as Map?)?.cast<String, String>();
    if (args['login'] != true) return overlay;
    return {...await ClaudeEnvironment.of(), ...?overlay};
  }

  Map<String, Object?> _track(Process process) {
    final id = ++_nextProcess;
    _processes[id] = _ServerProcess(peer, id, process, () {
      _processes.remove(id);
    });
    return {'id': id, 'pid': process.pid};
  }

  RemoteHello hello() => RemoteHello(
    protocol: RemoteProtocol.version,
    version: version,
    platform: currentPlatform(),
    pid: pid,
    home: AppPaths.home(Platform.environment),
    dataDir: dataDir,
  );

  /// This machine, as mason names it.
  static RemotePlatform currentPlatform() {
    final (os, arch) = switch (Abi.current()) {
      Abi.macosArm64 => ('darwin', 'arm64'),
      Abi.macosX64 => ('darwin', 'x64'),
      Abi.linuxArm64 => ('linux', 'arm64'),
      Abi.linuxX64 => ('linux', 'x64'),
      Abi.linuxArm => ('linux', 'arm'),
      Abi.windowsX64 => ('win', 'x64'),
      Abi.windowsArm64 => ('win', 'arm64'),
      final abi => (Platform.operatingSystem, '$abi'),
    };
    String? libc;
    if (os == 'linux') {
      try {
        libc =
            Directory('/lib')
                .listSync()
                .any((entry) => p.basename(entry.path).startsWith('ld-musl-'))
            ? 'musl'
            : 'gnu';
      } on FileSystemException {
        libc = 'gnu';
      }
    }
    return RemotePlatform(os, arch, libc: libc);
  }

  /// Ends every process the server started (politely, then killed),
  /// closes its streams and listeners: once, however often asked.
  Future<void> shutdown() => _shutdown ??= () async {
    await Future.wait([
      for (final process in [..._processes.values]) process.stop(),
      _pty.stopAll(),
      _streams.closeAll(),
      _tcp.closeAll(),
      _lsp.cancelAll(),
    ]);
    peer.close();
  }();
}

/// A process the server started for the app: its output as
/// [RemoteProtocol.processOutput], its end as [RemoteProtocol.processExit].
class _ServerProcess {
  _ServerProcess(this._peer, this.id, this._process, this._gone) {
    _process.stdin.done.then<void>((_) {}, onError: (Object _) {});
    // Their ends, known from the start: a stream may close before the
    // exit is seen.
    final out = _process.stdout
        .listen((data) => _send(1, data))
        .asFuture<void>()
        .catchError((Object _) {});
    final err = _process.stderr
        .listen((data) => _send(2, data))
        .asFuture<void>()
        .catchError((Object _) {});
    unawaited(() async {
      final code = await _process.exitCode;
      // Its last output first.
      await Future.wait([out, err])
          .timeout(const Duration(seconds: 2), onTimeout: () => const []);
      _gone();
      _exited.complete();
      _peer.notify(RemoteProtocol.processExit, {'id': id, 'code': code});
    }());
  }

  final RpcPeer _peer;
  final int id;
  final Process _process;
  final void Function() _gone;
  final Completer<void> _exited = Completer();
  bool _stdinClosed = false;

  void _send(int fd, List<int> data) => _peer.notify(
    RemoteProtocol.processOutput,
    {'id': id, 'fd': fd, 'data': encodeBytes(data)},
  );

  void write(List<int> data) {
    if (_stdinClosed) return;
    try {
      _process.stdin.add(data);
    } on StateError {
      // Closed: its exit follows.
    }
  }

  Future<void> closeStdin() async {
    if (_stdinClosed) return;
    _stdinClosed = true;
    try {
      await _process.stdin.close();
    } on Object {
      // Gone already.
    }
  }

  void kill({bool force = false}) {
    unawaited(closeStdin());
    _process.kill(force ? ProcessSignal.sigkill : ProcessSignal.sigterm);
  }

  Future<void> stop({Duration timeout = const Duration(seconds: 2)}) async {
    if (_exited.isCompleted) return;
    kill();
    try {
      await _exited.future.timeout(timeout);
    } on TimeoutException {
      _process.kill(ProcessSignal.sigkill);
      await _exited.future.timeout(timeout, onTimeout: () {});
    }
  }
}
