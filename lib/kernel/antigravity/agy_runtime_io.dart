import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:bao_remote/local.dart' show ClaudeEnvironment;
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../network/network_proxy_io.dart';
import '../../platform/child_process_registry.dart';
import '../../platform/data_dir.dart';
import '../acp/acp_connection.dart';
import 'agy_runtime.dart';

AgyRuntime localAgyRuntime() => LocalAgyRuntime();

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

  /// agy's `--gemini-dir`: what it keeps, apart from the terminal's.
  String get home => p.join(root, 'home');

  String get _bin => p.join(root, 'bin');

  /// Which build is in use, by its version.
  File get _current => File(p.join(_bin, 'current'));

  static String get _exe => Platform.isWindows ? '.exe' : '';

  String _executableOf(String version) =>
      p.join(_bin, version, 'antigravity$_exe');

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
  Future<String?> version() async {
    try {
      final version = (await _current.readAsString()).trim();
      if (version.isEmpty || !File(_executableOf(version)).existsSync()) {
        return null;
      }
      return version;
    } on FileSystemException {
      return null;
    }
  }

  Future<String> _executable() async {
    final version = await this.version();
    if (version == null) {
      throw const AgyUnavailable(
        'Antigravity is not installed',
        notInstalled: true,
      );
    }
    return _executableOf(version);
  }

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
  static const feed =
      'https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests';

  /// Where its builds are, the only place a download is taken from.
  static const _downloads =
      'https://storage.googleapis.com/antigravity-public/antigravity-cli/';

  static String get _target {
    final os = switch (Platform.operatingSystem) {
      'macos' => 'darwin',
      final os => os,
    };
    final arch = switch (Abi.current()) {
      Abi.macosArm64 || Abi.linuxArm64 || Abi.windowsArm64 => 'arm64',
      _ => 'amd64',
    };
    return '${os}_$arch';
  }

  Future<Map<String, Object?>> _manifest(HttpClient client) async {
    final request = await client.getUrl(Uri.parse('$feed/$_target.json'));
    final response = await request.close();
    final text = await utf8.decodeStream(response);
    if (response.statusCode != 200) {
      throw AgyUnavailable(
        'Antigravity’s release feed answered ${response.statusCode}',
      );
    }
    return switch (jsonDecode(text)) {
      final Map<String, Object?> json => json,
      _ => const {},
    };
  }

  Future<T> _feed<T>(Future<T> Function(HttpClient client) use) async {
    final client = HttpClient();
    try {
      return await use(client);
    } on SocketException catch (error) {
      throw AgyUnavailable(
        'Antigravity’s release feed could not be reached',
        detail: error.message,
      );
    } on HandshakeException catch (error) {
      throw AgyUnavailable(
        'Antigravity’s release feed could not be reached',
        detail: error.message,
      );
    } finally {
      client.close();
    }
  }

  @override
  Future<String> latestVersion() => _feed((client) async {
    final version = (await _manifest(client))['version'];
    if (version is! String || !_versionPattern.hasMatch(version)) {
      throw const AgyUnavailable('Antigravity’s release feed said nothing');
    }
    return version;
  });

  static final _versionPattern = RegExp(r'^\d+\.\d+\.\d+$');

  @override
  Future<void> install({void Function(double progress)? onProgress}) =>
      _feed((client) async {
        final manifest = await _manifest(client);
        final (version, url, sha) = (
          manifest['version'],
          manifest['url'],
          manifest['sha512'],
        );
        if (version is! String ||
            !_versionPattern.hasMatch(version) ||
            url is! String ||
            !url.startsWith(_downloads) ||
            sha is! String) {
          throw const AgyUnavailable('Antigravity’s release feed said nothing');
        }
        final folder = Directory(p.join(_bin, version));
        final target = File(_executableOf(version));
        if (!target.existsSync()) {
          await _download(client, url, sha, folder, target, onProgress);
        }
        final before = await this.version();
        await _current.writeAsString(version, flush: true);
        dropSpare();
        // The build before, unless sessions still run on it: then the
        // next install takes it.
        if (before != null && before != version && _live.isEmpty) {
          await Directory(p.join(_bin, before))
              .delete(recursive: true)
              .catchError((_) => Directory(''));
        }
      });

  Future<void> _download(
    HttpClient client,
    String url,
    String sha,
    Directory folder,
    File target,
    void Function(double progress)? onProgress,
  ) async {
    if (folder.existsSync()) await folder.delete(recursive: true);
    await folder.create(recursive: true);
    final download = File(p.join(folder.path, 'download.part'));
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw AgyUnavailable(
          'Antigravity could not be downloaded (${response.statusCode})',
        );
      }
      final total = response.contentLength;
      var received = 0;
      final sink = download.openWrite();
      final digest = _DigestSink();
      final hasher = sha512.startChunkedConversion(digest);
      await for (final chunk in response) {
        sink.add(chunk);
        hasher.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
      await sink.close();
      hasher.close();
      if ('${digest.value}' != sha.toLowerCase()) {
        throw const AgyUnavailable(
          'Antigravity’s download did not match its checksum',
        );
      }
      if (url.endsWith('.tar.gz')) {
        final result = await Process.run('tar', [
          '-xzf',
          download.path,
          '-C',
          folder.path,
        ]);
        await download.delete();
        final binary = File(p.join(folder.path, 'antigravity'));
        if (result.exitCode != 0 || !binary.existsSync()) {
          throw AgyUnavailable(
            'Antigravity could not be unpacked',
            detail: '${result.stderr}',
          );
        }
        if (binary.path != target.path) await binary.rename(target.path);
        await Process.run('chmod', ['755', target.path]);
      } else {
        await download.rename(target.path);
      }
    } on Object {
      if (folder.existsSync()) {
        await folder.delete(recursive: true).catchError((_) => folder);
      }
      rethrow;
    }
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
  Future<void> signIn() => _session((connection) async {
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
  Future<void> deleteSession(String sessionId) async {
    if (sessionId.length < 8 || sessionId.contains(RegExp(r'[/\\.]'))) return;
    final data = Directory(p.join(home, 'antigravity-cli'));
    if (!data.existsSync()) return;
    // Wherever agy keeps it, by its id: `conversations/<id>.db` and its
    // journal, `brain/<id>`, `annotations/<id>.pbtxt`.
    await for (final entity in data.list(recursive: true, followLinks: false)) {
      if (!p.basename(entity.path).startsWith(sessionId)) continue;
      try {
        await entity.delete(recursive: true);
      } on FileSystemException {
        // Gone already (a folder's, with it), or held: left.
      }
    }
  }

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

/// An `agy acp` process, its stdio as an [AcpTransport].
class AgyProcessTransport implements AcpTransport {
  AgyProcessTransport(this._process) {
    LocalAgyRuntime._live.add(_process);
    unawaited(LocalAgyRuntime.registry.add(_process.pid));
    _process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(_line, onDone: _stdoutDone);
    _process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(_stderrLine);
    unawaited(
      _process.exitCode.then((code) {
        _code = code;
        LocalAgyRuntime._live.remove(_process);
        unawaited(LocalAgyRuntime.registry.remove(_process.pid));
        _finish();
      }),
    );
  }

  final Process _process;
  final StreamController<Map<String, Object?>> _messages =
      StreamController.broadcast();
  final List<String> _stderr = [];
  final Completer<AcpExit> _exit = Completer();
  int? _code;
  bool _stdoutClosed = false;

  @override
  Stream<Map<String, Object?>> get messages => _messages.stream;

  @override
  Future<AcpExit> get exited => _exit.future;

  void _line(String line) {
    if (line.trim().isEmpty) return;
    try {
      if (jsonDecode(line) case final Map<String, Object?> message) {
        _messages.add(message);
        return;
      }
    } on FormatException {
      // Not protocol: kept to say why it failed.
    }
    _stderrLine(line);
  }

  void _stderrLine(String line) {
    _stderr.add(line);
    if (_stderr.length > 30) _stderr.removeAt(0);
  }

  void _stdoutDone() {
    _stdoutClosed = true;
    _finish();
  }

  /// Whether it is gone, or going.
  bool get ended => _code != null || _closing;
  bool _closing = false;

  void _finish() {
    final code = _code;
    if (code == null || !_stdoutClosed || _exit.isCompleted) return;
    _exit.complete(AcpExit(code, _stderr.join('\n')));
    unawaited(_messages.close());
  }

  @override
  void write(Map<String, Object?> message) {
    if (_code != null) return;
    try {
      _process.stdin.writeln(jsonEncode(message));
    } on StateError {
      // Closed under us: the exit follows.
    }
  }

  @override
  void close() {
    if (_code != null) return;
    _closing = true;
    unawaited(_process.stdin.close().catchError((_) {}));
    if (Platform.isWindows) {
      unawaited(
        Process.run('taskkill', [
          '/pid',
          '${_process.pid}',
          '/T',
          '/F',
        ]).then<void>((_) {}, onError: (Object _) => _process.kill()),
      );
    } else {
      _process.kill();
    }
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
