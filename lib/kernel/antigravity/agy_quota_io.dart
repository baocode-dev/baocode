import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../../network/network_proxy_io.dart';
import 'agy_quota.dart';

AgyQuotaApi localAgyQuotaApi() => _LocalAgyQuota();

/// agy's sign-in on this machine, as it keeps it (go-keyring's item
/// `gemini`/`antigravity`: the macOS keychain, the Windows Credential
/// Manager, the Secret Service), asked with as Antigravity's client asks:
/// the account's project first (`loadCodeAssist`), then its quota summary.
/// The token is only read, never renewed: agy renews it as it runs.
class _LocalAgyQuota implements AgyQuotaApi {
  static const _daily = 'https://daily-cloudcode-pa.googleapis.com';
  static const _prod = 'https://cloudcode-pa.googleapis.com';

  HttpClient? _client;

  HttpClient get _http => _client ??= HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..idleTimeout = const Duration(seconds: 15)
    ..findProxy = NetworkProxy.instance.findProxy;

  @override
  Future<List<({Object? summary, DateTime askedAt})>> summaries() async {
    // Not the keychain and the network of the machine tests run on.
    if (Platform.environment.containsKey('FLUTTER_TEST')) return const [];
    final sign = await _signIn();
    if (sign == null) return const [];
    if (sign.expiry case final expiry? when expiry.isBefore(DateTime.now())) {
      throw const AgyQuotaException('The Antigravity sign-in has expired');
    }
    // A consumer's use is metered on the daily host, a business's on prod.
    final hosts = sign.business ? [_prod, _daily] : [_daily, _prod];
    final read = <({Object? summary, DateTime askedAt})>[];
    Object? failure;
    for (final host in hosts) {
      try {
        final assist = await _post(host, 'loadCodeAssist', sign.token, {
          'metadata': {
            'ideType': 'ANTIGRAVITY',
            'platform': _platform,
            'pluginType': 'GEMINI',
          },
        });
        final project = switch (assist) {
          {'cloudaicompanionProject': final String id} => id,
          {'cloudaicompanionProject': {'id': final String id}} => id,
          _ => null,
        };
        final askedAt = DateTime.now();
        final summary = await _post(
          host,
          'retrieveUserQuotaSummary',
          sign.token,
          {'project': ?project},
        );
        read.add((summary: summary, askedAt: askedAt));
      } on Object catch (error) {
        failure ??= error;
      }
    }
    if (read.isEmpty && failure != null) {
      throw AgyQuotaException('$failure');
    }
    return read;
  }

  Future<Object?> _post(
    String host,
    String operation,
    String token,
    Map<String, Object?> body,
  ) async {
    final request = await _http.postUrl(
      Uri.parse('$host/v1internal:$operation'),
    );
    request.headers
      ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
      ..set(HttpHeaders.userAgentHeader, _userAgent)
      ..contentType = ContentType.json;
    request.write(jsonEncode(body));
    final response = await request.close().timeout(const Duration(seconds: 20));
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AgyQuotaException('HTTP ${response.statusCode}');
    }
    return jsonDecode(text);
  }

  /// As Antigravity's client names itself.
  static String get _userAgent {
    final os = switch (Platform.operatingSystem) {
      'macos' => 'darwin',
      final os => os,
    };
    return 'antigravity/hub/2.24.0 (aidev_client; os_type=$os; '
        'arch=$_arch; cl=963137146)';
  }

  static String get _arch =>
      Abi.current().toString().contains('arm64') ? 'arm64' : 'amd64';

  static String get _platform =>
      '${switch (Platform.operatingSystem) {
        'macos' => 'DARWIN',
        'windows' => 'WINDOWS',
        _ => 'LINUX',
      }}_${_arch.toUpperCase()}';

  /// The access token, when it expires, and whether the account is a
  /// business's; null when agy is not signed in.
  static Future<({String token, DateTime? expiry, bool business})?>
  _signIn() async {
    final secret = await _secret();
    if (secret == null || secret.isEmpty) return null;
    try {
      if (jsonDecode(_decoded(secret))
          case {'token': {'access_token': final String token}} &&
              final Map stored
          when token.isNotEmpty) {
        final expiry = switch ((stored['token'] as Map)['expiry']) {
          final String at => DateTime.tryParse(at),
          _ => null,
        };
        final method = '${stored['auth_method'] ?? ''}';
        return (
          token: token,
          expiry: expiry,
          business: method.contains('business'),
        );
      }
    } on FormatException {
      // Not what agy keeps.
    }
    return null;
  }

  /// go-keyring's, as it stores it: base64 or hex after its prefix.
  static String _decoded(String secret) {
    const base64Prefix = 'go-keyring-base64:';
    const hexPrefix = 'go-keyring-encoded:';
    if (secret.startsWith(base64Prefix)) {
      return utf8.decode(base64.decode(secret.substring(base64Prefix.length)));
    }
    if (secret.startsWith(hexPrefix)) {
      final hex = secret.substring(hexPrefix.length);
      return utf8.decode([
        for (var i = 0; i + 1 < hex.length; i += 2)
          int.parse(hex.substring(i, i + 2), radix: 16),
      ]);
    }
    return secret;
  }

  static Future<String?> _secret() async {
    try {
      if (Platform.isWindows) return _windowsCredential('gemini:antigravity');
      final result = Platform.isMacOS
          ? await Process.run('/usr/bin/security', [
              'find-generic-password',
              '-s',
              'gemini',
              '-a',
              'antigravity',
              '-w',
            ])
          : await Process.run('secret-tool', [
              'lookup',
              'service',
              'gemini',
              'username',
              'antigravity',
            ]);
      if (result.exitCode != 0) return null;
      return '${result.stdout}'.trim();
    } on ProcessException {
      return null;
    }
  }

  /// A generic credential of the Credential Manager, its blob as UTF-8.
  static String? _windowsCredential(String target) {
    final advapi = DynamicLibrary.open('advapi32.dll');
    final read = advapi
        .lookupFunction<
          Int32 Function(
            Pointer<Utf16>,
            Uint32,
            Uint32,
            Pointer<Pointer<_Credential>>,
          ),
          int Function(Pointer<Utf16>, int, int, Pointer<Pointer<_Credential>>)
        >('CredReadW');
    final free = advapi
        .lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
        >('CredFree');
    final name = target.toNativeUtf16();
    final out = calloc<Pointer<_Credential>>();
    try {
      // CRED_TYPE_GENERIC.
      if (read(name, 1, 0, out) == 0) return null;
      final credential = out.value;
      try {
        final size = credential.ref.blobSize;
        if (size == 0) return null;
        return utf8.decode(
          credential.ref.blob.asTypedList(size),
          allowMalformed: true,
        );
      } finally {
        free(credential.cast());
      }
    } finally {
      calloc
        ..free(name)
        ..free(out);
    }
  }
}

/// `CREDENTIALW`, as far as its blob.
final class _Credential extends Struct {
  @Uint32()
  external int flags;
  @Uint32()
  external int type;
  external Pointer<Utf16> targetName;
  external Pointer<Utf16> comment;
  // FILETIME: two DWORDs.
  @Uint32()
  external int lastWrittenLow;
  @Uint32()
  external int lastWrittenHigh;
  @Uint32()
  external int blobSize;
  external Pointer<Uint8> blob;
}
