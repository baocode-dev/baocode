import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:bao_remote/local.dart' show AppPaths, ClaudeEnvironment;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import '../../network/network_proxy_io.dart';
import '../../platform/child_process_registry.dart';
import '../../platform/data_dir.dart';
import '../acp/acp_connection.dart';
import '../acp/mcp_endpoint.dart';
import '../acp/mcp_http_server.dart';
import '../../models/antigravity/antigravity_api.dart';
import '../agent_kernel.dart' show SessionRecord;
import '../kernel_types.dart' show RateLimitWindow;
import 'agy_runtime.dart';
import 'antigravity_translator.dart';

AgyRuntime localAgyRuntime() => LocalAgyRuntime();

/// agy on this machine.
class LocalAgyRuntime implements AgyRuntime {
  LocalAgyRuntime({
    Future<Map<String, String>> Function()? environment,
    String? installDir,
    String? dataDir,
    String? cacheDir,
    String? stateDir,
  }) : _environment = environment ?? ClaudeEnvironment.of,
       _installDirOverride = installDir,
       _dataDirOverride = dataDir,
       _cacheDirOverride = cacheDir,
       _stateDirOverride = stateDir;

  final String? _cacheDirOverride;
  final String? _stateDirOverride;

  final Future<Map<String, String>> Function() _environment;
  final String? _installDirOverride;

  /// Where BaoCode installs it: `<data>/antigravity`.
  String get installDir =>
      _installDirOverride ?? p.join(DataDirectory.current.path, 'antigravity');

  static String get _exe => Platform.isWindows ? '.exe' : '';

  /// The one BaoCode installed.
  String get _installed => p.join(installDir, 'antigravity$_exe');

  /// The processes running, kept track of across runs (see
  /// [ChildProcessRegistry]).
  static final registry = ChildProcessRegistry(
    file: File(DataDirectory.current.processRegistryFile('antigravity')),
    recognizes: (command) =>
        command.contains(' acp') &&
        (command.contains('agy') || command.contains('antigravity')),
  );

  /// The running ones, to end as the app quits.
  static final Set<Process> _live = {};

  /// Ends every agy this run started (as the app quits).
  static Future<void> stopProcesses() async {
    _spareEnds?.cancel();
    _spare = null;
    for (final process in [..._live]) {
      process.kill();
    }
    _live.clear();
    await registry.flush();
  }

  @override
  Future<String?> locate() async {
    if (File(_installed).existsSync()) return _installed;
    final environment = await _environment();
    final home = AppPaths.home(environment);
    final separator = Platform.isWindows ? ';' : ':';
    final candidates = [
      for (final dir in (environment['PATH'] ?? '').split(separator))
        if (dir.isNotEmpty) p.join(dir, 'agy$_exe'),
      p.join(home, '.local', 'bin', 'agy$_exe'),
    ];
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) return candidate;
    }
    return null;
  }

  Future<String> _located() async {
    final found = await locate();
    if (found == null) {
      throw const AgyUnavailable(
        'Antigravity is not installed',
        notInstalled: true,
      );
    }
    return found;
  }

  Future<Map<String, String>> _runEnvironment() async => {
    ...await _environment(),
    ...await NetworkProxy.instance.environment(),
  };

  @override
  Future<AcpTransport> start(String cwd) async {
    if (!Directory(cwd).existsSync()) {
      throw AgyUnavailable('The folder $cwd is gone');
    }
    if (_takeSpare() case final spare?) {
      unawaited(_warm());
      return spare;
    }
    return _launch(cwd);
  }

  /// A new agy, in [cwd] (which its conversations do not depend on: each
  /// is told its own).
  Future<AgyProcessTransport> _launch(String cwd) async {
    await registry.reaped;
    final executable = await _located();
    try {
      final process = await Process.start(
        executable,
        const ['acp', '--disable-telemetry'],
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
  /// on at once. Its backend boots on the first session asked of it,
  /// asking Google for the account and its models: seconds, which opening
  /// a conversation would otherwise wait out. What a listing leaves (which
  /// boots it), and made again once taken.
  static AgyProcessTransport? _spare;
  static Timer? _spareEnds;
  static bool _warming = false;
  static const _spareFor = Duration(minutes: 10);

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
  static void dropSpare() {
    _takeSpare()?.close();
  }

  /// Boots a spare, by a listing.
  Future<void> _warm() async {
    if (_warming) return;
    _warming = true;
    try {
      await sessions();
    } on Object {
      // None then: the next starts its own.
    } finally {
      _warming = false;
    }
  }

  // --- Installing ----------------------------------------------------------------

  /// Google's update feed: `<feed>/<os>_<arch>.json` tells the version, its
  /// download and its SHA-512 (as `agy update` reads it).
  static const feed =
      'https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests';

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

  @override
  Future<void> install({void Function(double progress)? onProgress}) async {
    dropSpare();
    final client = HttpClient();
    try {
      final manifest = await _json(client, Uri.parse('$feed/$_target.json'));
      final url = manifest['url'];
      final sha = manifest['sha512'];
      if (url is! String || sha is! String) {
        throw const AgyUnavailable('Antigravity’s update feed said nothing');
      }
      await Directory(installDir).create(recursive: true);
      final download = File(p.join(installDir, 'download.part'));
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
        await download.delete();
        throw const AgyUnavailable(
          'Antigravity’s download did not match its checksum',
        );
      }
      final target = File(_installed);
      if (url.endsWith('.tar.gz')) {
        final unpacked = Directory(p.join(installDir, 'unpacked'));
        if (unpacked.existsSync()) await unpacked.delete(recursive: true);
        await unpacked.create();
        final result = await Process.run('tar', [
          '-xzf',
          download.path,
          '-C',
          unpacked.path,
        ]);
        await download.delete();
        final binary = File(p.join(unpacked.path, 'antigravity'));
        if (result.exitCode != 0 || !binary.existsSync()) {
          throw AgyUnavailable(
            'Antigravity could not be unpacked',
            detail: '${result.stderr}',
          );
        }
        await binary.rename(target.path);
        await unpacked.delete(recursive: true);
        await Process.run('chmod', ['755', target.path]);
      } else {
        await download.rename(target.path);
      }
    } on SocketException catch (error) {
      throw AgyUnavailable(
        'Antigravity could not be downloaded',
        detail: error.message,
      );
    } finally {
      client.close();
    }
  }

  static Future<Map<String, Object?>> _json(HttpClient client, Uri url) async {
    final request = await client.getUrl(url);
    final response = await request.close();
    final text = await utf8.decodeStream(response);
    if (response.statusCode != 200) {
      throw AgyUnavailable(
        'Antigravity’s update feed answered ${response.statusCode}',
      );
    }
    return switch (jsonDecode(text)) {
      final Map<String, Object?> json => json,
      _ => const {},
    };
  }

  // --- Signing in ------------------------------------------------------------------

  @override
  Future<void> login({
    required void Function(Uri link) link,
    required Future<String?> Function() code,
  }) async {
    dropSpare();
    final executable = await _located();
    final process = await Process.start(
      executable,
      const ['acp', '--login'],
      environment: await _runEnvironment(),
      includeParentEnvironment: Platform.isWindows,
    );
    final output = StringBuffer();
    final linked = Completer<void>();
    void read(String line) {
      output.writeln(line);
      if (linked.isCompleted) return;
      final match = RegExp(r'https://\S+').firstMatch(line);
      if (match == null) return;
      final uri = Uri.tryParse(match.group(0)!);
      if (uri == null) return;
      linked.complete();
      link(uri);
      unawaited(() async {
        final answer = await code();
        if (answer == null || answer.trim().isEmpty) {
          process.kill();
          return;
        }
        process.stdin.writeln(answer.trim());
        await process.stdin.flush();
      }());
    }

    process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(read);
    process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(read);
    final exit = await process.exitCode;
    if (exit != 0) {
      throw AgyUnavailable(
        'Signing in to Antigravity did not finish',
        detail: '$output',
      );
    }
  }

  // --- MCP servers -----------------------------------------------------------------

  Future<File> _mcpConfig() async =>
      File(p.join(p.dirname(dataDir), 'config', 'mcp_config.json'));

  @override
  Future<List<AgyMcpServer>> mcpServers() async {
    final file = await _mcpConfig();
    if (!file.existsSync()) return const [];
    try {
      return parseAgyMcpConfig(await file.readAsString());
    } on Object {
      return const [];
    }
  }

  @override
  Future<void> setMcpServerEnabled(String name, bool enabled) async {
    final executable = await _located();
    await Process.run(
      executable,
      ['mcp', enabled ? 'enable' : 'disable', name],
      environment: await _runEnvironment(),
      includeParentEnvironment: Platform.isWindows,
    );
  }

  // --- Its sign-in ---------------------------------------------------------------

  @override
  Future<void> stopAll() => stopProcesses();

  // --- Its quota -----------------------------------------------------------------

  /// Its sign-in, read once (the keychain may ask the user each time), and
  /// the access token refreshed from it.
  static AgyCredentials? _signIn;
  static ({String token, DateTime until})? _access;

  static final _endpoints = const AntigravityEndpoints();

  HttpClient _client() => HttpClient()
    ..connectionTimeout = const Duration(seconds: 20)
    ..findProxy = NetworkProxy.instance.findProxy;

  Future<(int, String)> _send(
    HttpClient http,
    Uri url, {
    Object? json,
    Map<String, String>? form,
    String? token,
  }) async {
    final request = await http.postUrl(url);
    if (token != null) {
      request.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
        ..set(
          HttpHeaders.userAgentHeader,
          antigravityUserAgent(
            antigravityFallbackVersion,
            os: _target.split('_').first,
            arch: _target.split('_').last,
          ),
        );
    }
    if (form != null) {
      request.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
        charset: 'utf-8',
      );
      request.write(Uri(queryParameters: form).query);
    } else {
      request.headers.contentType = ContentType.json;
      request.add(utf8.encode(jsonEncode(json ?? const {})));
    }
    final response = await request.close().timeout(const Duration(seconds: 30));
    return (response.statusCode, await utf8.decodeStream(response));
  }

  /// An access token of its sign-in: its own while good, else refreshed
  /// (not written back: agy refreshes its own).
  Future<String?> _token(HttpClient http, {bool fresh = false}) async {
    final now = DateTime.now();
    if (_access case (:final token, :final until)
        when !fresh && until.isAfter(now)) {
      return token;
    }
    final signIn = _signIn = fresh || _signIn == null
        ? await credentials()
        : _signIn;
    if (signIn == null) return null;
    final expiry = signIn.expiry;
    if (!fresh &&
        expiry != null &&
        expiry.isAfter(now.add(const Duration(minutes: 2)))) {
      _access = (token: signIn.accessToken, until: expiry);
      return signIn.accessToken;
    }
    final refresh = signIn.refreshToken;
    if (refresh == null) return signIn.accessToken;
    final (status, text) = await _send(
      http,
      Uri.parse(_endpoints.token),
      form: antigravityRefreshForm(refresh),
    );
    if (status >= 400) throw HttpException('Sign-in refused ($status)');
    final json = jsonDecode(text);
    final token = json is Map ? json['access_token'] : null;
    if (token is! String) throw const HttpException('No access token');
    final seconds = json['expires_in'];
    _access = (
      token: token,
      until: now.add(Duration(seconds: seconds is int ? seconds - 120 : 3000)),
    );
    return token;
  }

  @override
  Future<List<RateLimitWindow>?> quota() async {
    final http = _client();
    try {
      var token = await _token(http);
      if (token == null) return null;
      Future<Object?> call(String method, Object body, {String? at}) async {
        var (status, text) = await _send(
          http,
          _endpoints.method(method, at: at),
          json: body,
          token: token,
        );
        if (status == 401) {
          // Signed in again since, or its token revoked: read anew.
          _access = null;
          token = await _token(http, fresh: true);
          if (token == null) return null;
          (status, text) = await _send(
            http,
            _endpoints.method(method, at: at),
            json: body,
            token: token,
          );
        }
        if (status >= 400) throw HttpException('$method: $status');
        return jsonDecode(text);
      }

      final load = AntigravityLoad.fromJson(
        await call('loadCodeAssist', {
          'metadata': {'ideType': 'ANTIGRAVITY'},
        }, at: _endpoints.loadBase),
      );
      final project = {'project': ?load.project};
      // Consumer accounts are metered at one host, Workspace ones at the
      // other: both asked.
      final hosts = [_endpoints.base, _endpoints.loadBase];
      List<AntigravityModel> models = const [];
      for (final host in hosts) {
        try {
          models = parseAntigravityModels(
            await call('fetchAvailableModels', project, at: host),
          );
          if (models.isNotEmpty) break;
        } on Object {
          if (host == hosts.last) rethrow;
        }
      }
      final now = DateTime.now();
      final summaries = await Future.wait([
        for (final host in hosts)
          call(
            'retrieveUserQuotaSummary',
            project,
            at: host,
          ).then<Object?>((summary) => summary, onError: (_) => null),
      ]);
      final usage = antigravityUsage(
        models: models,
        // Each model's own when neither tells.
        summary: mergeAntigravitySummaries(summaries),
        now: now,
        plan: load.plan,
      );
      return [
        for (final window in usage.windows)
          RateLimitWindow(
            switch ((window.minutes, window.name)) {
              (300, final name?) => '$name 5-hour limit',
              (300, null) => '5-hour limit',
              (10080, final name?) => 'Weekly $name limit',
              (10080, null) => 'Weekly limit',
              (_, final name) => name ?? 'Limit',
            },
            window.usedPercent / 100,
            resetsAt: window.resetsAt?.toLocal(),
          ),
      ];
    } finally {
      http.close(force: true);
    }
  }

  @override
  Future<AgyCredentials?> credentials() async {
    // Without a keychain to keep it in, agy writes it to a file.
    final file = File(p.join(dataDir, 'antigravity-oauth-token'));
    if (file.existsSync()) {
      try {
        return parseAgyCredentials(await file.readAsString());
      } on FileSystemException {
        // The keychain's then.
      }
    }
    final secret = await _keychainSecret();
    if (secret == null) return null;
    return parseAgyCredentials(secret);
  }

  /// agy's entry in the system keychain (service `gemini`, account
  /// `antigravity`, as go-keyring keeps it).
  static Future<String?> _keychainSecret() async {
    try {
      final ProcessResult result;
      if (Platform.isMacOS) {
        result = await Process.run('security', [
          'find-generic-password',
          '-s',
          'gemini',
          '-a',
          'antigravity',
          '-w',
        ]);
      } else if (Platform.isLinux) {
        result = await Process.run('secret-tool', [
          'lookup',
          'service',
          'gemini',
          'username',
          'antigravity',
        ]);
      } else if (Platform.isWindows) {
        result = await Process.run('powershell', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          _windowsCredentialScript,
        ]);
      } else {
        return null;
      }
      if (result.exitCode != 0) return null;
      final text = '${result.stdout}'.trim();
      return text.isEmpty ? null : text;
    } on ProcessException {
      return null;
    }
  }

  /// Reads the generic credential `gemini:antigravity` (go-keyring's target
  /// on Windows) through CredRead, printing its blob as UTF-8.
  static const _windowsCredentialScript = r'''
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class BaoCred {
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  public struct CREDENTIAL {
    public int Flags; public int Type; public string TargetName; public string Comment;
    public long LastWritten; public int CredentialBlobSize; public IntPtr CredentialBlob;
    public int Persist; public int AttributeCount; public IntPtr Attributes;
    public string TargetAlias; public string UserName;
  }
  [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  public static extern bool CredRead(string target, int type, int flags, out IntPtr cred);
  [DllImport("advapi32.dll")] public static extern void CredFree(IntPtr cred);
  public static byte[] Read(string target) {
    IntPtr ptr;
    if (!CredRead(target, 1, 0, out ptr)) return null;
    try {
      var c = (CREDENTIAL)Marshal.PtrToStructure(ptr, typeof(CREDENTIAL));
      var bytes = new byte[c.CredentialBlobSize];
      Marshal.Copy(c.CredentialBlob, bytes, 0, c.CredentialBlobSize);
      return bytes;
    } finally { CredFree(ptr); }
  }
}
"@
$bytes = [BaoCred]::Read('gemini:antigravity')
if ($bytes -eq $null) { exit 1 }
[Console]::Out.Write([Text.Encoding]::UTF8.GetString($bytes))
''';

  // --- Its records -----------------------------------------------------------------

  /// Where it keeps its conversations: `~/.gemini/antigravity-cli`.
  String get dataDir =>
      _dataDirOverride ??
      p.join(AppPaths.home(Platform.environment), '.gemini', 'antigravity-cli');
  final String? _dataDirOverride;

  @override
  AgyRecords records(String sessionId) => _FileRecords(dataDir, sessionId);

  /// Where [kept] is kept: the app's cache, not agy's folder.
  String get _keptFile => p.join(
    _cacheDirOverride ?? DataDirectory.current.cacheDir,
    'antigravity.json',
  );

  @override
  Map<String, Object?>? get kept {
    try {
      final file = File(_keptFile);
      if (!file.existsSync()) return null;
      return switch (jsonDecode(file.readAsStringSync())) {
        final Map<String, Object?> kept => kept,
        _ => null,
      };
    } on Object {
      return null;
    }
  }

  @override
  set kept(Map<String, Object?>? value) {
    try {
      final file = File(_keptFile);
      if (value == null) {
        if (file.existsSync()) file.deleteSync();
        return;
      }
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(jsonEncode(value));
    } on FileSystemException {
      // Asked again next run then.
    }
  }

  /// The most of a conversation's turns [timeTurn] keeps.
  static const _turnsKept = 1000;

  /// Where [sessionId]'s turns are timed: the app's own state.
  File _turnsFile(String sessionId) => File(
    p.join(
      _stateDirOverride ?? DataDirectory.current.stateDir,
      'antigravity',
      '${p.basename(sessionId)}.json',
    ),
  );

  @override
  List<Map<String, Object?>> turnsTimed(String sessionId) {
    try {
      final file = _turnsFile(sessionId);
      if (!file.existsSync()) return const [];
      return switch (jsonDecode(file.readAsStringSync())) {
        final List<Object?> turns => [
          for (final turn in turns)
            if (turn is Map<String, Object?>) turn,
        ],
        _ => const [],
      };
    } on Object {
      return const [];
    }
  }

  @override
  void timeTurn(String sessionId, Map<String, Object?> turn) {
    final turns = [...turnsTimed(sessionId), turn];
    try {
      final file = _turnsFile(sessionId);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        jsonEncode(
          turns.length > _turnsKept
              ? turns.sublist(turns.length - _turnsKept)
              : turns,
        ),
      );
    } on FileSystemException {
      // Untimed when read back then.
    }
  }

  @override
  String? fileText(String path) {
    try {
      final file = File(path);
      if (!file.existsSync() || file.lengthSync() > 8 << 20) return null;
      return file.readAsStringSync();
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  @override
  Future<McpEndpoint> serveTools(McpHandler handle) =>
      McpHttpServer.start(handle);

  @override
  Future<List<SessionRecord>> sessions() async {
    if (await locate() == null) return const [];
    final transport =
        _takeSpare() ?? await _launch(AppPaths.home(await _environment()));
    final connection = AcpConnection(
      transport,
      onRequest: (method, _) async =>
          throw AcpError(-32601, 'Method not found: $method'),
      onNotification: (_, _) {},
    );
    const wait = Duration(seconds: 20);
    var listed = false;
    try {
      await connection
          .request('initialize', {
            'protocolVersion': 1,
            'clientCapabilities': {
              'fs': {'readTextFile': false, 'writeTextFile': false},
              'terminal': false,
            },
            'clientInfo': {'name': 'baocode', 'version': '1'},
          })
          .timeout(wait);
      final children = await _subagentConversations();
      final records = <SessionRecord>[];
      String? cursor;
      do {
        final page = await connection
            .request('session/list', {'cursor': ?cursor})
            .timeout(wait);
        for (final session in page['sessions'] as List? ?? const []) {
          if (session
              case {'sessionId': final String id, 'cwd': final String cwd}
              when !children.contains(id)) {
            records.add(
              SessionRecord(
                id: id,
                title: AntigravityTranslator.withoutReminders(
                  session['title'] as String? ?? '',
                ),
                updatedAt: _updatedAt(id, session['updatedAt']),
                cwd: agyPath(cwd),
                path: p.join(dataDir, 'conversations', '$id.db'),
              ),
            );
          }
        }
        cursor = page['nextCursor'] as String?;
      } while (cursor != null && records.length < 10000);
      listed = true;
      return records;
    } finally {
      if (listed) {
        // Booted by now: kept for a conversation to start on.
        connection.detach();
        _keepSpare(transport);
      } else {
        connection.close();
      }
    }
  }

  /// The conversations of subagents, each listed by agy as one of its
  /// own: shown in their parents' cards, not apart.
  Future<Set<String>> _subagentConversations() async {
    final children = <String>{};
    final brain = Directory(p.join(dataDir, 'brain'));
    if (!brain.existsSync()) return children;
    await for (final conversation in brain.list()) {
      final dir = Directory(
        p.join(conversation.path, '.system_generated', 'subagents'),
      );
      if (!dir.existsSync()) continue;
      await for (final file in dir.list()) {
        if (file is! File || !file.path.endsWith('.json')) continue;
        try {
          if (jsonDecode(await file.readAsString()) case {
            'conversationId': final String id,
          }) {
            children.add(id);
          }
        } on Object {
          // Not one.
        }
      }
    }
    return children;
  }

  /// When [id] was last changed: as agy says, else (it says year 1 for
  /// some) as its file was.
  DateTime _updatedAt(String id, Object? said) {
    final at = said is String ? DateTime.tryParse(said) : null;
    if (at != null && at.year > 2000) return at.toLocal();
    try {
      return File(p.join(dataDir, 'conversations', '$id.db'))
          .lastModifiedSync();
    } on FileSystemException {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  @override
  Future<void> delete(String sessionId) async {
    final dir = dataDir;
    for (final path in [
      p.join(dir, 'conversations', '$sessionId.db'),
      p.join(dir, 'conversations', '$sessionId.pb'),
      p.join(dir, 'annotations', '$sessionId.pbtxt'),
    ]) {
      final file = File(path);
      if (file.existsSync()) await file.delete();
    }
    final brain = Directory(p.join(dir, 'brain', sessionId));
    if (brain.existsSync()) await brain.delete(recursive: true);
    final turns = _turnsFile(sessionId);
    if (turns.existsSync()) await turns.delete();
  }
}

/// A project's path as agy lists it: URL-encoded (`Application%20Support`).
@visibleForTesting
String agyPath(String path) {
  if (!RegExp('%[0-9A-Fa-f]{2}').hasMatch(path)) return path;
  try {
    return Uri.decodeFull(path);
  } on ArgumentError {
    return path;
  }
}

/// agy's MCP servers, from its `mcp_config.json`.
@visibleForTesting
List<AgyMcpServer> parseAgyMcpConfig(String text) {
  final servers = switch (jsonDecode(text)) {
    {'mcpServers': final Map<String, Object?> servers} => servers,
    _ => const <String, Object?>{},
  };
  return [
    for (final MapEntry(key: name, value: config) in servers.entries)
      if (config is Map)
        AgyMcpServer(
          name: name,
          enabled: config['disabled'] != true,
          target: switch (config) {
            {'serverUrl': final String url} => url,
            {'url': final String url} => url,
            {'command': final String command} => [
              command,
              for (final arg in config['args'] as List? ?? const []) '$arg',
            ].join(' '),
            _ => '',
          },
        ),
  ];
}

/// agy's sign-in from its keychain entry: JSON, which go-keyring may have
/// stored base64- or hex-encoded behind a prefix.
@visibleForTesting
AgyCredentials? parseAgyCredentials(String secret) {
  var text = secret.trim();
  try {
    if (text.startsWith('go-keyring-base64:')) {
      text = utf8.decode(base64.decode(text.substring(18)));
    } else if (text.startsWith('go-keyring-encoded:')) {
      final hex = text.substring(19);
      text = utf8.decode([
        for (var i = 0; i + 1 < hex.length; i += 2)
          int.parse(hex.substring(i, i + 2), radix: 16),
      ]);
    }
    final json = jsonDecode(text);
    if (json case {'token': final Map<String, Object?> token}) {
      final access = token['access_token'];
      if (access is! String || access.isEmpty) return null;
      return AgyCredentials(
        accessToken: access,
        refreshToken: token['refresh_token'] as String?,
        expiry: switch (token['expiry']) {
          final String at => DateTime.tryParse(at),
          _ => null,
        },
        email: json['id_token_email'] as String?,
      );
    }
  } on Object {
    return null;
  }
  return null;
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

/// A conversation's records, read from agy's folder.
class _FileRecords implements AgyRecords {
  _FileRecords(this._root, this._session);

  final String _root;
  final String _session;

  String _dir(String part) =>
      p.join(_root, 'brain', _session, '.system_generated', part);

  /// Past this, a file is not read whole: a record is never that big but
  /// for the transcript of a very long conversation, whose end matters.
  static const _maxBytes = 8 << 20;

  @override
  Future<List<Map<String, Object?>>> steps() async {
    final file = File(p.join(_dir('logs'), 'transcript.jsonl'));
    if (!file.existsSync()) return const [];
    final length = await file.length();
    final start = length > _maxBytes ? length - _maxBytes : 0;
    final text = await file
        .openRead(start)
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    final lines = const LineSplitter().convert(text);
    return [
      // A cut first line is not a whole step.
      for (final (index, line) in lines.indexed)
        if (!(start > 0 && index == 0)) ?_decode(line),
    ];
  }

  @override
  Future<List<Map<String, Object?>>> messages() =>
      _jsonFiles(_dir('messages'), skip: 'read.json');

  @override
  Future<List<Map<String, Object?>>> subagents() =>
      _jsonFiles(_dir('subagents'));

  static Future<List<Map<String, Object?>>> _jsonFiles(
    String dir, {
    String? skip,
  }) async {
    final folder = Directory(dir);
    if (!folder.existsSync()) return const [];
    final found = <Map<String, Object?>>[];
    await for (final entry in folder.list()) {
      if (entry is! File || !entry.path.endsWith('.json')) continue;
      if (p.basename(entry.path) == skip) continue;
      try {
        if (await entry.length() > _maxBytes) continue;
        if (_decode(await entry.readAsString()) case final json?) {
          found.add(json);
        }
      } on FileSystemException {
        // Gone meanwhile.
      }
    }
    return found;
  }

  static Map<String, Object?>? _decode(String text) {
    try {
      return switch (jsonDecode(text)) {
        final Map<String, Object?> json => json,
        _ => null,
      };
    } on FormatException {
      return null;
    }
  }

  /// `<session>/task-6` → its `tasks/task-6.log`.
  @override
  String taskLog(String taskId) =>
      p.join(_dir('tasks'), '${taskId.split('/').last}.log');

  @override
  AgyRecords child(String id) => _FileRecords(_root, id);
}

/// `agy acp` as a child process, over its stdin and stdout.
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
