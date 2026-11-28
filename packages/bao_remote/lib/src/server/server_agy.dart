import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

import '../acp/acp_connection.dart';
import '../acp/acp_process_transport.dart';
import '../acp/agy_release.dart';
import '../acp/agy_runtime.dart';
import '../acp/swarm_watcher.dart';
import '../claude/claude_environment.dart';
import '../claude/claude_settings_file.dart';
import '../files/ide_file.dart';
import '../platform/process_tree.dart';
import '../protocol.dart';
import '../rpc/rpc_peer.dart';
import 'remote_server.dart' show paramsOf;
import 'server_claude.dart' show ServerClaude;
import 'server_streams.dart';

/// Parsed OAuth authorization URL extracted from headless `antigravity acp --login`
/// output.
typedef AgyOAuthUrl = ({String url, int? callbackPort, bool needsCode});

final _ansiEscapes = RegExp(
  r'\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)',
);
final _httpsUrlPattern = RegExp(r'''https://[^\s<>"'`]+''');
final _trailingPunctuation = RegExp(r'''[.,;:!?)\]}>'"]+$''');

/// Extracts a Google or generic OAuth URL from [line] (stripping terminal ANSI
/// escapes and trailing punctuation), along with any loopback callback port
/// from `redirect_uri`.
AgyOAuthUrl? parseAgyOAuthUrl(String line) {
  final plain = line.replaceAll(_ansiEscapes, '');
  for (final match in _httpsUrlPattern.allMatches(plain)) {
    final cleaned = match.group(0)!.replaceFirst(_trailingPunctuation, '');
    final uri = Uri.tryParse(cleaned);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) continue;
    final params = uri.queryParameters;
    final isOAuth =
        uri.host.toLowerCase() == 'accounts.google.com' ||
        params.containsKey('redirect_uri') ||
        params.containsKey('client_id');
    if (!isOAuth) continue;

    final callbackPort = _extractCallbackPort(uri);
    return (
      url: uri.toString(),
      callbackPort: callbackPort,
      needsCode: callbackPort == null,
    );
  }
  return null;
}

int? _extractCallbackPort(Uri oauthUri) {
  final raw = oauthUri.queryParameters['redirect_uri'];
  if (raw == null || raw.isEmpty) return null;
  final redirect = Uri.tryParse(raw);
  if (redirect == null || redirect.scheme != 'http') return null;
  var host = redirect.host.trim().toLowerCase();
  if (host.startsWith('[') && host.endsWith(']')) {
    host = host.substring(1, host.length - 1);
  }
  if (host != '127.0.0.1' && host != 'localhost' && host != '::1') return null;
  if (!redirect.hasPort) return null;
  final port = redirect.port;
  if (port <= 0 || port > 65535) return null;
  return port;
}

/// Pure-Dart [AgyRuntime] for `baocode-server`: runs `antigravity` from
/// [managed] on the remote host with headless-safe environment settings and
/// optional proxy forwarding from [extraEnvironment].
class ServerAgyRuntime implements AgyRuntime {
  ServerAgyRuntime({
    required this.managed,
    required this.platform,
    this.extraEnvironment = const {},
    Future<Map<String, String>> Function()? baseEnvironment,
    AgyRelease? release,
  }) : _baseEnvironment = baseEnvironment ?? ClaudeEnvironment.of,
       _releaseOverride = release;

  final ManagedAgy managed;
  final RemotePlatform platform;
  final Map<String, String> extraEnvironment;
  final Future<Map<String, String>> Function() _baseEnvironment;
  final AgyRelease? _releaseOverride;

  final Set<Process> _live = {};
  AcpProcessTransport? _spare;
  Timer? _spareEnds;
  bool _warming = false;

  static const _spareFor = Duration(minutes: 10);
  static const _wait = Duration(seconds: 60);

  String get home => managed.home;

  String get target => AgyRelease.targetOf(platform);

  List<String> get _acpArguments => [
    'acp',
    '--disable-telemetry',
    '--gemini-dir',
    home,
  ];

  /// Merges the host's login environment [base] with [extra], disables agy's
  /// self-updater, and forces file token storage on headless Linux so D-Bus
  /// keyring probes do not hang.
  @visibleForTesting
  static Map<String, String> buildProcessEnvironment(
    Map<String, String> base,
    Map<String, String> extra, {
    bool? isLinux,
  }) {
    final merged = <String, String>{
      ...base,
      ...extra,
      'AGY_CLI_DISABLE_AUTO_UPDATE': '1',
    };
    final linux = isLinux ?? Platform.isLinux;
    if (linux &&
        (merged['AGY_CLI_FORCE_FILE_TOKEN_STORAGE'] ?? '').isEmpty &&
        (merged['DISPLAY'] ?? '').isEmpty &&
        (merged['WAYLAND_DISPLAY'] ?? '').isEmpty) {
      merged['AGY_CLI_FORCE_FILE_TOKEN_STORAGE'] = '1';
    }
    return merged;
  }

  /// Builds an [HttpClient.findProxy] callback from proxy variables in
  /// [environment] (`HTTP_PROXY`, `HTTPS_PROXY`, `ALL_PROXY`, `NO_PROXY`,
  /// case-insensitive), or `null` when no proxy is configured.
  @visibleForTesting
  static String Function(Uri url)? findProxyForEnvironment(
    Map<String, String> environment,
  ) {
    String? first(List<String> keys) {
      for (final key in keys) {
        final value = environment[key]?.trim();
        if (value != null && value.isNotEmpty) return value;
      }
      return null;
    }

    final httpProxy = first(const ['HTTP_PROXY', 'http_proxy']);
    final httpsProxy = first(const ['HTTPS_PROXY', 'https_proxy']);
    final allProxy = first(const ['ALL_PROXY', 'all_proxy']);
    if (httpProxy == null && httpsProxy == null && allProxy == null) {
      return null;
    }

    String? httpFallback(String? value) {
      if (value == null) return null;
      final candidate = value.contains('://') ? value : 'http://$value';
      final uri = Uri.tryParse(candidate);
      if (uri == null || uri.host.isEmpty) return null;
      if (uri.scheme != 'http' && uri.scheme != 'https') return null;
      return value;
    }

    final allHttp = httpFallback(allProxy);
    final proxyEnv = <String, String>{};
    if ((httpProxy ?? allHttp) case final value?) {
      proxyEnv['http_proxy'] = value;
    }
    if ((httpsProxy ?? allHttp) case final value?) {
      proxyEnv['https_proxy'] = value;
    }
    if (first(const ['NO_PROXY', 'no_proxy']) case final noProxy?) {
      proxyEnv['no_proxy'] = noProxy;
    }
    if (!proxyEnv.containsKey('http_proxy') &&
        !proxyEnv.containsKey('https_proxy')) {
      return null;
    }
    return (uri) =>
        HttpClient.findProxyFromEnvironment(uri, environment: proxyEnv);
  }

  Future<Map<String, String>> runEnvironment() async => buildProcessEnvironment(
    await _baseEnvironment(),
    extraEnvironment,
  );

  AgyRelease _agyRelease({Duration? probeTimeout}) {
    if (_releaseOverride case final release?) return release;
    final findProxy = findProxyForEnvironment(extraEnvironment);
    if (findProxy == null && probeTimeout == null) return AgyRelease();
    return AgyRelease(
      clientFactory: findProxy == null
          ? null
          : () => HttpClient()..findProxy = findProxy,
      probeTimeout: probeTimeout,
    );
  }

  /// Resolves the `antigravity` executable to run on this host: prefers a
  /// user-installed system binary on PATH, falling back to BaoCode's managed
  /// installation.
  Future<String> resolveExecutable([Map<String, String>? env]) async {
    final resolvedEnv = env ?? await runEnvironment();
    return managed.resolveExecutable(resolvedEnv);
  }

  @override
  Future<String?> version() async =>
      managed.resolvedVersion(await runEnvironment());

  @override
  Future<String> latestVersion() async =>
      (await _agyRelease().latest(target)).version;

  /// Downloads (when not already present) and installs the latest build for
  /// [platform], reporting raw `(received, total)` bytes to [onProgress].
  Future<AgyBuild> installBuild({
    void Function(int received, int total)? onProgress,
    Duration? probeTimeout,
    Future<void>? cancel,
  }) async {
    final release = _agyRelease(probeTimeout: probeTimeout);
    final build = await release.latest(target, cancel: cancel);
    final targetFile = File(managed.executableOf(build.version));
    final part = managed.partOf(build);
    if (!targetFile.existsSync()) {
      await release.download(
        build,
        part,
        onProgress: onProgress,
        cancel: cancel,
      );
    }
    await managed.installArchive(
      build,
      part,
      prunePrevious: _live.isEmpty,
    );
    dropSpare();
    return build;
  }

  @override
  Future<void> install({void Function(double progress)? onProgress}) async {
    await installBuild(
      onProgress: onProgress == null
          ? null
          : (received, total) {
              if (total > 0) onProgress(received / total);
            },
    );
  }

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

  Future<AcpProcessTransport> _launch(String cwd) async {
    final env = await runEnvironment();
    final executable = await resolveExecutable(env);
    await Directory(home).create(recursive: true);
    try {
      final process = await Process.start(
        executable,
        _acpArguments,
        workingDirectory: cwd,
        environment: env,
        includeParentEnvironment: Platform.isWindows,
      );
      _live.add(process);
      return AcpProcessTransport(
        process,
        onExit: (_) => _live.remove(process),
      );
    } on ProcessException catch (error) {
      throw AgyUnavailable(
        'Antigravity could not start',
        detail: '$executable\n${error.message}',
      );
    }
  }

  AcpProcessTransport? _takeSpare() {
    _spareEnds?.cancel();
    _spareEnds = null;
    final spare = _spare;
    _spare = null;
    return spare == null || spare.ended ? null : spare;
  }

  void _keepSpare(AcpProcessTransport transport) {
    if (_spare case final kept? when !kept.ended) {
      transport.close();
      return;
    }
    _spare = transport;
    _spareEnds?.cancel();
    _spareEnds = Timer(_spareFor, dropSpare);
  }

  /// Drops any pre-warmed spare `antigravity acp` process (e.g. after sign-in,
  /// sign-out, or upgrade).
  void dropSpare() => _takeSpare()?.close();

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
        await connection.request('session/list', {}).timeout(_wait);
      } on Object {
        connection.close();
        return;
      }
      connection.detach();
      _keepSpare(transport);
    } on Object {
      // Next start will launch its own process.
    } finally {
      _warming = false;
    }
  }

  static AcpConnection _query(AcpTransport transport) => AcpConnection(
    transport,
    onRequest: (method, _) async =>
        throw AcpError(-32601, 'Method not found: $method'),
    onNotification: (_, _) {},
  );

  @override
  Future<List<AgyModel>> models() async {
    final env = await runEnvironment();
    final executable = await resolveExecutable(env);
    final ProcessResult result;
    try {
      result = await Process.run(
        executable,
        const ['models'],
        environment: env,
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
    final parsed = parseAgyModels(output);
    if (parsed.isNotEmpty) return parsed;
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
      managed.deleteSession(sessionId);

  @override
  Future<void> stopAll() async {
    _spareEnds?.cancel();
    _spareEnds = null;
    final spare = _spare;
    _spare = null;
    spare?.close();
    for (final process in [..._live]) {
      if (Platform.isWindows) {
        killProcessTree(process.pid);
      } else {
        process.kill();
      }
    }
    _live.clear();
  }
}

/// The remote server's Antigravity ACP service: binary lifecycle (version,
/// install, upload), model listing, headless OAuth sign-in, sign-out, session
/// cleanup, swarm snapshot/transcript reads, and launching `baocode-server agy`
/// subprocesses for remote conversations.
class ServerAgy {
  ServerAgy(
    RpcPeer peer,
    this._streams, {
    required this.managed,
    required this.platform,
    Future<Map<String, String>> Function()? baseEnvironment,
  }) : _baseEnvironment = baseEnvironment ?? ClaudeEnvironment.of,
       defaultRuntime = ServerAgyRuntime(
         managed: managed,
         platform: platform,
         baseEnvironment: baseEnvironment,
       ) {
    final handlers = peer.handlers;
    handlers[RemoteProtocol.agyVersion] = (_, _) => defaultRuntime.version();
    handlers[RemoteProtocol.agyLatestVersion] = (params, _) =>
        _runtimeFor(paramsOf(params)).latestVersion();
    handlers[RemoteProtocol.agyModels] = (params, _) async => [
      for (final model in await _runtimeFor(paramsOf(params)).models())
        model.toJson(),
    ];
    handlers[RemoteProtocol.agyInstall] = (params, _) =>
        _install(paramsOf(params));
    handlers[RemoteProtocol.agyUpload] = (params, _) =>
        _upload(paramsOf(params));
    handlers[RemoteProtocol.agySignIn] = (params, _) =>
        _signIn(paramsOf(params));
    handlers[RemoteProtocol.agyAuthCode] = (params, _) =>
        _submitAuthCode(paramsOf(params));
    handlers[RemoteProtocol.agySignOut] = (params, _) async {
      await _runtimeFor(paramsOf(params)).signOut();
      defaultRuntime.dropSpare();
      return null;
    };
    handlers[RemoteProtocol.agyDeleteSession] = (params, _) async {
      await managed.deleteSession(paramsOf(params)['sessionId'] as String);
      return null;
    };
    handlers[RemoteProtocol.agySwarmSnapshot] = (params, _) {
      final swarmId = paramsOf(params)['swarmId'] as String;
      return readSwarmSnapshotSync(managed.brainDir, swarmId)?.toJson();
    };
    handlers[RemoteProtocol.agySwarmTranscript] = (params, _) async {
      final convId = paramsOf(params)['conversationId'] as String;
      final steps = await readSwarmWorkerTranscript(managed.brainDir, convId);
      return [for (final step in steps) step.toJson()];
    };
  }

  /// The server's argument that runs Antigravity ACP as a Claude stream-json
  /// bridge (`bin/baocode_server.dart`): `agy`, then the CLI arguments.
  static const agyCommand = 'agy';

  /// Override for how the server spawns itself (defaults to
  /// [ServerClaude.selfCommand]).
  static List<String> Function()? selfCommand;

  final ServerStreams _streams;
  final ManagedAgy managed;
  final RemotePlatform platform;
  final Future<Map<String, String>> Function() _baseEnvironment;
  final ServerAgyRuntime defaultRuntime;

  Process? _signInProcess;

  static Map<String, String> _environmentOf(Map<String, Object?> args) =>
      switch (args['environment']) {
        final Map env => {
          for (final entry in env.entries) '${entry.key}': '${entry.value}',
        },
        _ => const {},
      };

  ServerAgyRuntime _runtimeFor(Map<String, Object?> args) {
    final extra = _environmentOf(args);
    if (extra.isEmpty) return defaultRuntime;
    return ServerAgyRuntime(
      managed: managed,
      platform: platform,
      extraEnvironment: extra,
      baseEnvironment: _baseEnvironment,
    );
  }

  /// Launches `baocode-server agy --agy-root <managed.root> ...` in [cwd] with
  /// [arguments] and optional [settings] (written to a private temp file and
  /// removed once the process exits).
  Future<Process> startAgy({
    required String cwd,
    required List<String> arguments,
    Map<String, Object?>? settings,
    List<String> cleared = const [],
    Map<String, String> environment = const {},
  }) async {
    if (!Directory(cwd).existsSync()) {
      throw IdeFileNotFoundException(cwd);
    }
    final user = await _baseEnvironment();
    final env = {
      ...user,
      for (final name in cleared) name: '',
      ...environment,
      ...ClaudeEnvironment.stateDirectory(user),
    };
    await managed.resolveExecutable(env);
    final file = settings == null
        ? null
        : await ClaudeSettingsFile.write(settings);
    final [executable, ...self] = (selfCommand ?? ServerClaude.selfCommand)();
    final Process process;
    try {
      process = await Process.start(
        executable,
        [
          ...self,
          agyCommand,
          '--agy-root',
          managed.root,
          ...arguments,
          if (file != null) ...['--settings', file],
        ],
        workingDirectory: cwd,
        environment: env,
        includeParentEnvironment: false,
      );
    } on Object {
      if (file != null) await ClaudeSettingsFile.delete(file);
      rethrow;
    }
    if (file != null) {
      unawaited(process.exitCode.then((_) => ClaudeSettingsFile.delete(file)));
    }
    return process;
  }

  /// Downloads and installs the latest Antigravity release on the remote host,
  /// streaming `{received, total}` progress updates. Supports optional
  /// `probeTimeoutMs` for fast direct-connectivity probing and stream
  /// cancellation.
  int _install(Map<String, Object?> args) {
    final cancel = Completer<void>();
    late final StreamController<Object?> progress;
    progress = StreamController<Object?>(
      onCancel: () {
        if (!cancel.isCompleted) cancel.complete();
      },
    );
    final probeTimeoutMs = args['probeTimeoutMs'];
    final probeTimeout = probeTimeoutMs is int && probeTimeoutMs > 0
        ? Duration(milliseconds: probeTimeoutMs)
        : null;
    unawaited(() async {
      final runtime = _runtimeFor(args);
      try {
        var reported = -1;
        await runtime.installBuild(
          probeTimeout: probeTimeout,
          cancel: cancel.future,
          onProgress: (received, total) {
            if (reported >= 0 &&
                received - reported < 1 << 20 &&
                (total <= 0 || received < total)) {
              return;
            }
            reported = received;
            if (!progress.isClosed) {
              progress.add({'received': received, 'total': total});
            }
          },
        );
        defaultRuntime.dropSpare();
      } on Object catch (error, stack) {
        if (!cancel.isCompleted && !progress.isClosed) {
          progress.addError(error, stack);
        }
      } finally {
        if (!progress.isClosed) await progress.close();
      }
    }());
    return _streams.open(progress.stream);
  }

  /// Receives a chunk `{build, offset, data, size}` of an Antigravity binary
  /// or `.tar.gz` archive uploaded by the client; once all `size` bytes arrive,
  /// verifies SHA-512, installs via [ManagedAgy.installArchive], and returns
  /// `build.version`.
  Future<String?> _upload(Map<String, Object?> args) async {
    final build = AgyBuild.fromJson(
      (args['build'] as Map).cast<String, Object?>(),
    );
    final expectedTarget = AgyRelease.targetOf(platform);
    if (!RegExp(r'^[0-9A-Za-z.+-]+$').hasMatch(build.version) ||
        build.target != expectedTarget) {
      throw AgyUnavailable(
        'Not a build of Antigravity for this host',
        detail:
            '${build.version} for ${build.target}; this is $expectedTarget.',
      );
    }
    final offset = args['offset'] as int;
    final size = args['size'] as int;
    final data = decodeBytes(args['data']);
    final part = managed.partOf(build);
    if (offset == 0) {
      part.parent.createSync(recursive: true);
      part.writeAsBytesSync(const []);
    } else if (!part.existsSync() || part.lengthSync() != offset) {
      throw const AgyUnavailable(
        'Antigravity was not uploaded whole',
        detail: 'A piece of it is missing.',
      );
    }
    part.writeAsBytesSync(data, mode: FileMode.append, flush: true);
    if (offset + data.length < size) return null;
    if (part.lengthSync() != size ||
        !await AgyRelease.verifySha512(part, build.sha512)) {
      if (part.existsSync()) part.deleteSync();
      throw const AgyUnavailable(
        'Antigravity was not uploaded whole',
        detail: 'Its size or checksum is not the one in the manifest.',
      );
    }
    await managed.installArchive(build, part);
    defaultRuntime.dropSpare();
    return build.version;
  }

  /// Starts headless OAuth login (`antigravity acp --login ...`) and streams
  /// `{type: 'line', text}`, `{type: 'url', url, callbackPort, needsCode}`,
  /// and `{type: 'done'}` events. Cancelling the stream kills the login
  /// process.
  int _signIn(Map<String, Object?> args) {
    late final StreamController<Object?> controller;
    Process? process;
    var cancelled = false;

    void killRunning(Process? target) {
      if (target == null) return;
      if (identical(_signInProcess, target)) _signInProcess = null;
      if (Platform.isWindows) {
        killProcessTree(target.pid);
      } else {
        target.kill(ProcessSignal.sigterm);
      }
    }

    controller = StreamController<Object?>(
      onCancel: () {
        cancelled = true;
        final running = process;
        process = null;
        killRunning(running);
      },
    );

    unawaited(() async {
      try {
        final runtime = _runtimeFor(args);
        final env = await runtime.runEnvironment();
        final executable = await runtime.resolveExecutable(env);
        if (cancelled) return;
        await Directory(managed.home).create(recursive: true);
        if (cancelled) return;

        // Replace any stale sign-in process.
        killRunning(_signInProcess);

        final started = await Process.start(
          executable,
          [
            'acp',
            '--login',
            '--disable-telemetry',
            '--gemini-dir',
            managed.home,
          ],
          environment: env,
          includeParentEnvironment: Platform.isWindows,
        );
        if (cancelled) {
          killRunning(started);
          return;
        }
        process = started;
        _signInProcess = started;
        unawaited(started.stdin.done.then<void>((_) {}, onError: (Object _) {}));

        final recentLines = <String>[];
        void handleLine(String line) {
          if (cancelled || controller.isClosed) return;
          recentLines.add(line);
          if (recentLines.length > 30) recentLines.removeAt(0);
          controller.add({'type': 'line', 'text': line});
          final urlInfo = parseAgyOAuthUrl(line);
          if (urlInfo != null) {
            controller.add({
              'type': 'url',
              'url': urlInfo.url,
              'callbackPort': urlInfo.callbackPort,
              'needsCode': urlInfo.needsCode,
            });
          }
        }

        final outDone = started.stdout
            .transform(const Utf8Decoder(allowMalformed: true))
            .transform(const LineSplitter())
            .listen(handleLine, onError: (Object _) {})
            .asFuture<void>()
            .catchError((Object _) {});
        final errDone = started.stderr
            .transform(const Utf8Decoder(allowMalformed: true))
            .transform(const LineSplitter())
            .listen(handleLine, onError: (Object _) {})
            .asFuture<void>()
            .catchError((Object _) {});

        final code = await started.exitCode;
        await Future.wait([outDone, errDone])
            .timeout(const Duration(seconds: 2), onTimeout: () => const []);
        if (identical(_signInProcess, started)) _signInProcess = null;
        process = null;
        if (cancelled || controller.isClosed) return;
        if (code == 0) {
          defaultRuntime.dropSpare();
          controller.add({'type': 'done'});
        } else {
          final detail = recentLines.join('\n').trim();
          controller.addError(
            AgyUnavailable(
              'Signing in to Antigravity did not finish',
              detail: detail.isEmpty ? 'Exit code $code' : detail,
            ),
          );
        }
      } on Object catch (error, stack) {
        if (!cancelled && !controller.isClosed) {
          controller.addError(error, stack);
        }
      } finally {
        if (!controller.isClosed) await controller.close();
      }
    }());
    return _streams.open(controller.stream);
  }

  Future<void> _submitAuthCode(Map<String, Object?> args) async {
    final active = _signInProcess;
    if (active == null) {
      throw const AgyUnavailable('No Antigravity sign-in is in progress');
    }
    final code = (args['code'] as String? ?? '').trim();
    try {
      active.stdin.write('$code\n');
      await active.stdin.flush();
    } on Object catch (error) {
      throw AgyUnavailable(
        'Could not send authorization code to Antigravity',
        detail: '$error',
      );
    }
  }

  /// Stops any active sign-in process and all runtime processes/spares.
  Future<void> stopAll() async {
    final signingIn = _signInProcess;
    _signInProcess = null;
    if (signingIn != null) {
      if (Platform.isWindows) {
        killProcessTree(signingIn.pid);
      } else {
        signingIn.kill(ProcessSignal.sigterm);
      }
    }
    await defaultRuntime.stopAll();
  }
}
