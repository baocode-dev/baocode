import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../kernel/claude_code/claude_environment.dart';
import '../kernel/claude_code/claude_path_setting.dart';
import '../kernel/claude_code/local_claude_io.dart';
import '../network/network_proxy_io.dart';
import 'claude_resets.dart';

/// Claude Code's sign-in on this machine, as its CLI keeps it: the macOS
/// keychain, else `.credentials.json` in its config folder. Asked with
/// it as the CLI asks; the token is never renewed here (a refresh token
/// works once, and the CLI's would be spent), only read.
class LocalClaudeResetsApi implements ClaudeResetsApi {
  static const _base = 'https://api.anthropic.com';

  /// What the CLI names itself when none is known.
  static const _fallbackVersion = '2.1.293';

  HttpClient? _client;
  String? _version;

  HttpClient get _http => _client ??= HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..idleTimeout = const Duration(seconds: 15)
    ..findProxy = NetworkProxy.instance.findProxy;

  @override
  Future<Map<String, Object?>?> usage() async {
    // Not the keychain and the network of the machine tests run on.
    if (Platform.environment.containsKey('FLUTTER_TEST')) return null;
    // Asked as the user opens the page, whatever keeps the CLI's own
    // traffic down (`CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`).
    final environment = await ClaudeEnvironment.of();
    final sign = await _signIn(environment);
    if (sign == null) return null;
    final answer = await _send(
      'GET',
      '/api/oauth/usage?cedar_ember=1&skip_spend=1',
      sign.token,
    );
    return answer is Map<String, Object?> ? answer : null;
  }

  @override
  Future<Map<String, Object?>> claim(String grantId, String requestId) async {
    final environment = await ClaudeEnvironment.of();
    final sign = await _signIn(environment);
    if (sign == null) {
      throw const ClaudeResetsException('Not signed in to Claude.ai here.');
    }
    final organization = sign.organization ?? await _organization(sign.token);
    final answer = await _send(
      'POST',
      '/api/organizations/${Uri.encodeComponent(organization)}'
          '/reset_rate_limits',
      sign.token,
      body: {
        'program': 'cedar_ember',
        'grant_id': grantId,
        'request_id': requestId,
      },
    );
    if (answer is! Map<String, Object?>) {
      throw const ClaudeResetsException('Unreadable answer.');
    }
    return answer;
  }

  Future<String> _organization(String token) async {
    final profile = await _send('GET', '/api/oauth/profile', token);
    if (profile case {'organization': {'uuid': final String id}}
        when id.isNotEmpty) {
      return id;
    }
    throw const ClaudeResetsException('No organization for this sign-in.');
  }

  Future<Object?> _send(
    String method,
    String path,
    String token, {
    Map<String, Object?>? body,
  }) async {
    try {
      final request = await _http.openUrl(method, Uri.parse('$_base$path'));
      request.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
        ..set('anthropic-beta', 'oauth-2025-04-20')
        ..set(HttpHeaders.acceptHeader, 'application/json')
        ..set(
          HttpHeaders.userAgentHeader,
          'claude-cli/${await _cliVersion()} (external, cli)',
        );
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode == 401) {
        throw const ClaudeResetsException(
          'The Claude.ai sign-in has expired.',
          signedOut: true,
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ClaudeResetsException(
          'HTTP ${response.statusCode}${_message(text)}',
        );
      }
      return jsonDecode(text);
    } on ClaudeResetsException {
      rethrow;
    } on FormatException {
      throw const ClaudeResetsException('Unreadable answer.');
    } on Object catch (error) {
      throw ClaudeResetsException('$error');
    }
  }

  /// The error's message in an answer, if it has one.
  static String _message(String text) {
    try {
      if (jsonDecode(text) case {'error': {'message': final String message}}) {
        return ': $message';
      }
    } on FormatException {
      // Not JSON.
    }
    return '';
  }

  Future<String> _cliVersion() async {
    if (_version case final version?) return version;
    final found = switch (await LocalClaude.status()) {
      LocalClaudeFound(:final version?) => version,
      _ => null,
    };
    return _version = found ?? _fallbackVersion;
  }

  /// The access token, and the organization if the config names it; null
  /// with no Claude.ai sign-in.
  static Future<({String token, String? organization})?> _signIn(
    Map<String, String> environment,
  ) async {
    final dir = await ClaudeEnvironment.configDir();
    final oauth = await _credentials(environment, dir);
    if (oauth == null) return null;
    final token = oauth['accessToken'];
    if (token is! String || token.isEmpty) return null;
    if (oauth['expiresAt'] case final num at
        when DateTime.fromMillisecondsSinceEpoch(at.toInt())
            .isBefore(DateTime.now())) {
      throw const ClaudeResetsException(
        'The Claude.ai sign-in has expired.',
        signedOut: true,
      );
    }
    return (token: token, organization: await _configOrganization(dir));
  }

  /// `claudeAiOauth` of the sign-in kept.
  static Future<Map<Object?, Object?>?> _credentials(
    Map<String, String> environment,
    String dir,
  ) async {
    final texts = <String?>[
      if (Platform.isMacOS)
        for (final service in _keychainServices(environment))
          await _keychain(service),
      if (dir.isNotEmpty) await _read(p.join(dir, '.credentials.json')),
    ];
    for (final text in texts) {
      if (text == null || text.isEmpty) continue;
      try {
        if (jsonDecode(text) case {'claudeAiOauth': final Map oauth}) {
          return oauth;
        }
      } on FormatException {
        // Not what the CLI writes: the next.
      }
    }
    return null;
  }

  /// As the CLI names its keychain item: with a config folder set, a hash
  /// of it after the name.
  static List<String> _keychainServices(Map<String, String> environment) {
    const name = 'Claude Code-credentials';
    final dir = [
      environment[ClaudeEnvironment.dataPathVariable],
      environment['CLAUDE_CONFIG_DIR'],
    ].whereType<String>().where((dir) => dir.isNotEmpty).firstOrNull;
    if (dir == null) return const [name];
    final hash = sha256.convert(utf8.encode(dir)).toString().substring(0, 8);
    return ['$name-$hash', name];
  }

  static Future<String?> _keychain(String service) async {
    try {
      final result = await Process.run('/usr/bin/security', [
        'find-generic-password',
        '-s',
        service,
        '-w',
      ]);
      if (result.exitCode != 0) return null;
      return '${result.stdout}'.trim();
    } on ProcessException {
      return null;
    }
  }

  static Future<String?> _read(String path) async {
    try {
      return await File(path).readAsString();
    } on FileSystemException {
      return null;
    }
  }

  /// `oauthAccount.organizationUuid` in the CLI's `.claude.json`.
  static Future<String?> _configOrganization(String dir) async {
    final home = p.dirname(dir);
    for (final path in [
      p.join(dir, '.claude.json'),
      if (p.basename(dir) == '.claude') p.join(home, '.claude.json'),
    ]) {
      final text = await _read(path);
      if (text == null) continue;
      try {
        if (jsonDecode(text)
            case {'oauthAccount': {'organizationUuid': final String id}}
            when id.isNotEmpty) {
          return id;
        }
      } on FormatException {
        // Being written: asked of the server instead.
      }
    }
    return null;
  }
}

/// The app's: Claude Code's sign-in on this machine.
final claudeResetsService = ClaudeResetsService(LocalClaudeResetsApi());
