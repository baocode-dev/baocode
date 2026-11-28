import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bao_remote/acp.dart'
    show AcpProcessTransport, AgyRelease, ManagedAgy;
import 'package:bao_remote/local.dart' show ClaudeEnvironment;
import 'package:path/path.dart' as p;

import '../../network/network_proxy_io.dart';
import '../../platform/child_process_registry.dart';
import '../../platform/data_dir.dart';
import '../acp/acp_connection.dart';
import 'agy_runtime.dart';

AgyRuntime localAgyRuntime() => LocalAgyRuntime();

String? localAgyBrainDir() => LocalAgyRuntime()._managed.brainDir;

/// agy on this machine, kept under `<data>/antigravity`: its builds in
/// `bin/<version>`, its conversations and settings in `home` (agy's
/// `--gemini-dir`).
class LocalAgyRuntime implements AgyRuntime {
  LocalAgyRuntime({
    String? root,
    Future<Map<String, String>> Function()? environment,
  }) : _rootOverride = root,
       _environment = environment ?? ClaudeEnvironment.of;

  final String? _rootOverride;
  final Future<Map<String, String>> Function() _environment;

  String get root =>
      _rootOverride ?? p.join(DataDirectory.current.path, 'antigravity');

  ManagedAgy get _managed => ManagedAgy(root);

  /// agy's `--gemini-dir`: what it keeps, apart from the terminal's.
  String get home => _managed.home;

  /// The processes running, kept track of across runs (see
  /// [ChildProcessRegistry]).
  static final registry = ChildProcessRegistry(
    file: File(DataDirectory.current.processRegistryFile('antigravity')),
    recognizes: (command) =>
        command.contains(' acp') && command.contains('antigravity'),
  );

  /// The running ones, to end as the app quits.
  static final Set<Process> _live = {};

  @override
  Future<String?> version() => _managed.version();

  Future<String> _executable() => _managed.executable();

  Future<Map<String, String>> _runEnvironment() async => {
    ...await _environment(),
    ...await NetworkProxy.instance.environment(),
    // BaoCode updates it (see [install]): agy's own updater would swap the
    // build under the sessions running on it.
    'AGY_CLI_DISABLE_AUTO_UPDATE': '1',
  };

  /// `agy acp` as each conversation runs it: its conversations in [home].
  List<String> get _acpArguments => [
    'acp',
    '--disable-telemetry',
    '--gemini-dir',
    home,
  ];

  @override
  Future<AcpTransport> start(String cwd) async {
    if (!Directory(cwd).existsSync()) {
      throw AgyUnavailable('The folder $cwd is gone');
    }
    if (_takeSpare() case final spare?) {
      warm();
      return spare;
    }
    final transport = await _launch(cwd);
    warm();
    return transport;
  }

  Future<AgyProcessTransport> _launch(String cwd) async {
    await registry.reaped;
    final executable = await _executable();
    await Directory(home).create(recursive: true);
    try {
      final process = await Process.start(
        executable,
        _acpArguments,
        workingDirectory: cwd,
        environment: await _runEnvironment(),
        includeParentEnvironment: Platform.isWindows,
      );
      return AgyProcessTransport(process);
    } on ProcessException catch (error) {
      throw AgyUnavailable(
        'Antigravity could not start',
        detail: '$executable\n${error.message}',
      );
    }
  }

  // --- A spare -------------------------------------------------------------------

  /// An agy up and booted, kept a while for the next conversation to start
  /// on at once: its backend boots on the first session asked of it,
  /// asking Google for the account and its models (seconds). Made as one
  /// is started, and on [warm].
  static AgyProcessTransport? _spare;
  static Timer? _spareEnds;
  static bool _warming = false;
  static const _spareFor = Duration(minutes: 10);
  static const _wait = Duration(seconds: 60);

  static AgyProcessTransport? _takeSpare() {
    _spareEnds?.cancel();
    final spare = _spare;
    _spare = null;
    return spare == null || spare.ended ? null : spare;
  }

  static void _keepSpare(AgyProcessTransport transport) {
    if (_spare case final kept? when !kept.ended) {
      transport.close();
      return;
    }
    _spare = transport;
    _spareEnds?.cancel();
    _spareEnds = Timer(_spareFor, dropSpare);
  }

  /// Ends the spare: one booted before a sign-in has the account before.
  static void dropSpare() => _takeSpare()?.close();

  @override
  void warm() => unawaited(_warm());

  Future<void> _warm() async {
    if (_warming || (_spare?.ended == false)) return;
    _warming = true;
    try {
      if (await version() == null) return;
      await Directory(home).create(recursive: true);
      final transport = await _launch(home);
      final connection = _query(transport);
      try {
        await connection.request('initialize', agyHello).timeout(_wait);
        // Its backend boots on the first session asked of it.
        await connection.request('session/list', {}).timeout(_wait);
      } on Object {
        connection.close();
        return;
      }
      connection.detach();
      _keepSpare(transport);
    } on Object {
      // None then: the next starts its own.
    } finally {
      _warming = false;
    }
  }

  /// A connection that answers nothing agy asks.
  static AcpConnection _query(AcpTransport transport) => AcpConnection(
    transport,
    onRequest: (method, _) async =>
        throw AcpError(-32601, 'Method not found: $method'),
    onNotification: (_, _) {},
  );

  // --- Installing ----------------------------------------------------------------

  /// Google's release feed: `<feed>/<os>_<arch>.json` tells the version,
  /// its download and its SHA-512 (as `agy update` reads it).
  static const feed = AgyRelease.defaultFeed;

  @override
  Future<String> latestVersion() async =>
      (await AgyRelease().latest(AgyRelease.currentTarget())).version;

  @override
  Future<void> install({void Function(double progress)? onProgress}) async {
    final release = AgyRelease();
    final build = await release.latest(AgyRelease.currentTarget());
    final managed = _managed;
    final target = File(managed.executableOf(build.version));
    final part = managed.partOf(build);
    if (!target.existsSync()) {
      await release.download(
        build,
        part,
        onProgress: onProgress == null
            ? null
            : (received, total) {
                if (total > 0) onProgress(received / total);
              },
      );
    }
    await managed.installArchive(build, part, prunePrevious: _live.isEmpty);
    dropSpare();
  }

  // --- The account -----------------------------------------------------------------

  @override
  Future<List<AgyModel>> models() async {
    final executable = await _executable();
    final ProcessResult result;
    try {
      result = await Process.run(
        executable,
        const ['models'],
        environment: await _runEnvironment(),
        includeParentEnvironment: Platform.isWindows,
        stdoutEncoding: const Utf8Codec(allowMalformed: true),
        stderrEncoding: const Utf8Codec(allowMalformed: true),
      ).timeout(_wait);
    } on TimeoutException {
      throw const AgyUnavailable('Antigravity did not list its models');
    } on ProcessException catch (error) {
      throw AgyUnavailable(
        'Antigravity could not start',
        detail: error.message,
      );
    }
    final output = '${result.stdout}';
    final models = parseAgyModels(output);
    if (models.isNotEmpty) return models;
    final said = '$output\n${result.stderr}'.trim();
    if (RegExp(
      r'log ?in|sign ?in|logged',
      caseSensitive: false,
    ).hasMatch(said)) {
      throw AgyUnavailable(
        'Sign in to Antigravity',
        signIn: true,
        detail: said,
      );
    }
    throw AgyUnavailable('Antigravity listed no models', detail: said);
  }

  /// Runs [use] on an agy of its own, initialized, and ends it.
  Future<T> _session<T>(
    Future<T> Function(AcpConnection connection) use,
  ) async {
    dropSpare();
    await Directory(home).create(recursive: true);
    final transport = await _launch(home);
    final connection = _query(transport);
    try {
      await connection.request('initialize', agyHello).timeout(_wait);
      return await use(connection);
    } finally {
      connection.close();
    }
  }

  @override
  Future<void> signIn({Future<void>? cancel}) => _session((connection) async {
    // Given up: its agy ended, the browser's sign-in with it.
    unawaited(cancel?.then((_) => connection.close()));
    try {
      await connection
          .request('authenticate', {'methodId': 'oauth-personal'})
          .timeout(const Duration(minutes: 10));
    } on TimeoutException {
      throw const AgyUnavailable('Signing in to Antigravity timed out');
    } on AcpError catch (error) {
      throw AgyUnavailable(
        'Signing in to Antigravity did not finish',
        detail: error.message,
      );
    }
  });

  @override
  Future<void> signOut() => _session((connection) async {
    try {
      await connection.request('logout', {}).timeout(_wait);
    } on AcpError catch (error) {
      throw AgyUnavailable(
        'Signing out of Antigravity did not finish',
        detail: error.message,
      );
    }
  });

  @override
  Future<void> deleteSession(String sessionId) =>
      _managed.deleteSession(sessionId);

  @override
  Future<void> stopAll() async {
    _spareEnds?.cancel();
    _spare = null;
    for (final process in [..._live]) {
      process.kill();
    }
    _live.clear();
    await registry.flush();
  }
}

/// An `agy acp` process registered in [LocalAgyRuntime.registry], wrapping
/// [AcpProcessTransport].
class AgyProcessTransport extends AcpProcessTransport {
  AgyProcessTransport(Process process)
    : super(
        process,
        onExit: (_) {
          LocalAgyRuntime._live.remove(process);
          unawaited(LocalAgyRuntime.registry.remove(process.pid));
        },
      ) {
    LocalAgyRuntime._live.add(process);
    unawaited(LocalAgyRuntime.registry.add(process.pid));
  }
}
