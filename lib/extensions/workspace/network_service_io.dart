/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// What extensions' HTTP asks the main thread through the extension
// host's proxy agent: the system's proxy for a URL (the agent handles
// `http.proxy` and the proxy environment variables itself), credentials
// for a proxy that asks, and the system's certificate authorities
// (`http.systemCertificates`).
//
// Follows VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/platform/request/common/request.ts (`AuthInfo`, `Credentials`),
// src/vs/platform/request/electron-utility/requestService.ts and
// src/vs/platform/native/electron-main/auth.ts (`ProxyAuthHandler`:
// asking for, and remembering, proxy credentials), @vscode/proxy-agent's
// `loadSystemCertificates` (macOS keychains, Linux CA bundles, Windows'
// root store).
//
// Deviations:
// - Electron's `session.resolveProxy` is replaced by reading the system's
//   settings: `scutil --proxy` on macOS, the Internet Settings registry
//   key on Windows, the proxy environment variables elsewhere. A proxy
//   auto-config (PAC) script is not evaluated: such URLs resolve to none
//   (the agent then connects directly).
// - No Kerberos (`$lookupKerberosAuthorization` answers none).
// - Remembered credentials last for the app's run.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// `AuthInfo`.
typedef ProxyAuthInfo = ({
  bool isProxy,
  String scheme,
  String host,
  int port,
  String realm,
  int attempt,
});

/// Asks for a proxy's user name and password; null when cancelled.
typedef ProxyCredentialsPrompt =
    Future<({String username, String password})?> Function(ProxyAuthInfo info);

/// The system's proxies as `scutil --proxy` or the registry lists them.
typedef SystemProxySettings = ({
  String? http,
  String? https,
  String? socks,
  List<String> exceptions,
  bool excludeSimpleHostnames,
});

final class NetworkService {
  NetworkService({
    this.prompt,
    Map<String, String>? environment,
    Future<ProcessResult> Function(String executable, List<String> arguments)?
    run,
    this.cacheFor = const Duration(seconds: 30),
  }) : _environment = environment ?? Platform.environment,
       _run = run ?? Process.run;

  /// Asks for proxy credentials; none answers none.
  ProxyCredentialsPrompt? prompt;
  final Map<String, String> _environment;
  final Future<ProcessResult> Function(String, List<String>) _run;
  final Duration cacheFor;

  SystemProxySettings? _settings;
  DateTime? _settingsAt;
  List<String>? _certificates;
  final _credentials = <String, ({String username, String password})>{};

  // --- proxies

  /// `$resolveProxy`: `PROXY host:port`, `SOCKS5 host:port` or `DIRECT`;
  /// null when unknown.
  Future<String?> resolveProxy(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return null;
    final settings = await systemProxySettings();
    if (settings == null) return null;
    if (_bypassed(uri.host, settings)) return 'DIRECT';
    final proxy = uri.scheme == 'https'
        ? settings.https ?? settings.http
        : settings.http;
    if (proxy != null) return 'PROXY $proxy';
    if (settings.socks != null) return 'SOCKS5 ${settings.socks}';
    return 'DIRECT';
  }

  bool _bypassed(String host, SystemProxySettings settings) {
    final h = host.toLowerCase();
    if (settings.excludeSimpleHostnames && !h.contains('.')) return true;
    for (var rule in settings.exceptions) {
      rule = rule.trim().toLowerCase();
      if (rule.isEmpty) continue;
      if (rule == '<local>') {
        if (!h.contains('.')) return true;
        continue;
      }
      if (rule.startsWith('*.')) rule = rule.substring(1);
      if (rule.startsWith('*')) rule = rule.substring(1);
      if (rule.startsWith('.')) {
        if (h.endsWith(rule) || h == rule.substring(1)) return true;
      } else if (h == rule || h.endsWith('.$rule')) {
        return true;
      }
    }
    return false;
  }

  /// The system's proxy settings, read at most every [cacheFor].
  Future<SystemProxySettings?> systemProxySettings() async {
    final at = _settingsAt;
    if (at != null && DateTime.now().difference(at) < cacheFor) {
      return _settings;
    }
    try {
      _settings = Platform.isMacOS
          ? await _macProxies()
          : Platform.isWindows
          ? await _windowsProxies()
          : environmentProxies(_environment);
    } on Object {
      _settings = environmentProxies(_environment);
    }
    _settingsAt = DateTime.now();
    return _settings;
  }

  Future<SystemProxySettings?> _macProxies() async {
    final result = await _run('scutil', ['--proxy']);
    if (result.exitCode != 0) return environmentProxies(_environment);
    return parseScutilProxy('${result.stdout}');
  }

  Future<SystemProxySettings?> _windowsProxies() async {
    final result = await _run('reg', [
      'query',
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
    ]);
    if (result.exitCode != 0) return environmentProxies(_environment);
    return parseWindowsProxy('${result.stdout}');
  }

  /// `http_proxy`, `https_proxy`, `all_proxy` and `no_proxy`.
  static SystemProxySettings? environmentProxies(Map<String, String> env) {
    String? get(String name) {
      final v = env[name] ?? env[name.toUpperCase()];
      if (v == null || v.trim().isEmpty) return null;
      final uri = Uri.tryParse(v.contains('://') ? v : 'http://$v');
      if (uri == null || uri.host.isEmpty) return null;
      return '${uri.host}:${uri.hasPort ? uri.port : 80}';
    }

    final http = get('http_proxy');
    final https = get('https_proxy');
    final all = get('all_proxy');
    if (http == null && https == null && all == null) return null;
    return (
      http: http ?? all,
      https: https ?? all,
      socks: null,
      exceptions: (env['no_proxy'] ?? env['NO_PROXY'] ?? '').split(','),
      excludeSimpleHostnames: false,
    );
  }

  /// `scutil --proxy`'s dictionary.
  static SystemProxySettings parseScutilProxy(String output) {
    final values = <String, String>{};
    final exceptions = <String>[];
    var inExceptions = false;
    for (final raw in const LineSplitter().convert(output)) {
      final line = raw.trim();
      if (line.startsWith('ExceptionsList')) {
        inExceptions = true;
        continue;
      }
      if (inExceptions) {
        if (line == '}') {
          inExceptions = false;
          continue;
        }
        final m = RegExp(r'^\d+\s*:\s*(.+)$').firstMatch(line);
        if (m != null) exceptions.add(m[1]!);
        continue;
      }
      final m = RegExp(r'^(\w+)\s*:\s*(.+)$').firstMatch(line);
      if (m != null) values[m[1]!] = m[2]!;
    }
    String? proxy(String kind) {
      if (values['${kind}Enable'] != '1') return null;
      final host = values['${kind}Proxy'];
      if (host == null || host.isEmpty) return null;
      final port = values['${kind}Port'];
      return port == null ? host : '$host:$port';
    }

    return (
      http: proxy('HTTP'),
      https: proxy('HTTPS'),
      socks: proxy('SOCKS'),
      exceptions: exceptions,
      excludeSimpleHostnames: values['ExcludeSimpleHostnames'] == '1',
    );
  }

  /// `reg query …\Internet Settings`'s `ProxyEnable`, `ProxyServer`
  /// (`host:port` or `http=…;https=…;socks=…`) and `ProxyOverride`.
  static SystemProxySettings? parseWindowsProxy(String output) {
    final values = <String, String>{};
    for (final line in const LineSplitter().convert(output)) {
      final m = RegExp(r'^\s*(\w+)\s+REG_\w+\s+(.*)$').firstMatch(line);
      if (m != null) values[m[1]!] = m[2]!.trim();
    }
    final enabled = values['ProxyEnable'];
    if (enabled == null || !(enabled == '0x1' || enabled == '1')) return null;
    final server = values['ProxyServer'] ?? '';
    String? http;
    String? https;
    String? socks;
    if (server.contains('=')) {
      for (final part in server.split(';')) {
        final kv = part.split('=');
        if (kv.length != 2) continue;
        switch (kv[0].trim().toLowerCase()) {
          case 'http':
            http = kv[1].trim();
          case 'https':
            https = kv[1].trim();
          case 'socks':
            socks = kv[1].trim();
        }
      }
    } else if (server.isNotEmpty) {
      http = https = server;
    }
    return (
      http: http,
      https: https,
      socks: socks,
      exceptions: (values['ProxyOverride'] ?? '').split(';'),
      excludeSimpleHostnames: false,
    );
  }

  // --- proxy authentication

  /// `$lookupAuthorization`: the credentials remembered for the proxy, or
  /// asked for (again when they failed: [ProxyAuthInfo.attempt] > 1).
  Future<Map<String, Object?>?> lookupAuthorization(
    Map<String, Object?> authInfo,
  ) async {
    final info = (
      isProxy: authInfo['isProxy'] == true,
      scheme: '${authInfo['scheme'] ?? ''}',
      host: '${authInfo['host'] ?? ''}',
      port: (authInfo['port'] as num?)?.toInt() ?? 0,
      realm: '${authInfo['realm'] ?? ''}',
      attempt: (authInfo['attempt'] as num?)?.toInt() ?? 1,
    );
    final key = '${info.scheme}:${info.host}:${info.port}:${info.realm}';
    final remembered = _credentials[key];
    if (remembered != null && info.attempt <= 1) {
      return {'username': remembered.username, 'password': remembered.password};
    }
    final asked = await prompt?.call(info);
    if (asked == null) return null;
    _credentials[key] = asked;
    return {'username': asked.username, 'password': asked.password};
  }

  // --- certificates

  /// `$loadCertificates`: the system's certificate authorities, as PEM.
  Future<List<String>> loadCertificates() async =>
      _certificates ??= await _loadCertificates();

  Future<List<String>> _loadCertificates() async {
    try {
      if (Platform.isMacOS) {
        final pems = <String>{};
        for (final keychains in const [
          <String>[],
          ['/Library/Keychains/System.keychain'],
          ['/System/Library/Keychains/SystemRootCertificates.keychain'],
        ]) {
          final result = await _run('security', [
            'find-certificate',
            '-a',
            '-p',
            ...keychains,
          ]);
          if (result.exitCode == 0) pems.addAll(splitPem('${result.stdout}'));
        }
        return pems.toList();
      }
      if (Platform.isWindows) {
        final result = await _run('powershell', [
          '-NoProfile',
          '-Command',
          r'Get-ChildItem Cert:\LocalMachine\Root,Cert:\CurrentUser\Root | '
              r'ForEach-Object { "-----BEGIN CERTIFICATE-----"; '
              r'[Convert]::ToBase64String($_.RawData, "InsertLineBreaks"); '
              r'"-----END CERTIFICATE-----" }',
        ]);
        return result.exitCode == 0
            ? splitPem('${result.stdout}').toSet().toList()
            : const [];
      }
      for (final path in const [
        '/etc/ssl/certs/ca-certificates.crt',
        '/etc/pki/tls/certs/ca-bundle.crt',
        '/etc/ssl/ca-bundle.pem',
        '/etc/pki/tls/cacert.pem',
        '/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem',
        '/etc/ssl/cert.pem',
      ]) {
        final file = File(path);
        if (await file.exists()) {
          return splitPem(await file.readAsString()).toSet().toList();
        }
      }
    } on Object {
      // None found.
    }
    return const [];
  }

  /// The PEM blocks of [text].
  static List<String> splitPem(String text) => [
    for (final m in RegExp(
      r'-----BEGIN CERTIFICATE-----[\s\S]+?-----END CERTIFICATE-----',
    ).allMatches(text))
      m[0]!.replaceAll('\r\n', '\n'),
  ];
}
