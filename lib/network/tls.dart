// TLS for the app's requests to upstreams: the certificates the machine
// itself trusts, beside the ones Dart bundles, and what a failed handshake
// was.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../platform/data_dir.dart';

/// What [error] was: Dart's own message says only that the handshake
/// failed, its reason in the OS error it carries ("CERTIFICATE_VERIFY_FAILED:
/// unable to get local issuer certificate", "UNSUPPORTED_PROTOCOL", …).
String handshakeFailure(HandshakeException error) {
  // The reason, one line, without BoringSSL's place in its source.
  final reason = error.osError?.message
      .replaceAll(RegExp(r'\([\w.]+\.cc:\d+\)'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return reason == null || reason.isEmpty ? error.message : reason;
}

/// The context the app's requests to upstreams are made in: the roots Dart
/// bundles (Mozilla's), and the machine's own beside them — a company's CA,
/// a proxy's, one Apple or Windows trusts and Mozilla does not. A browser
/// trusts those, and an upstream whose certificate chains to one answers
/// there; with the bundled roots alone it is refused, as if it had none
/// (#393).
Future<SecurityContext> upstreamSecurityContext() =>
    _context ??= _buildContext();

Future<SecurityContext>? _context;

Future<SecurityContext> _buildContext() async =>
    contextTrusting(await systemCertificatesPem());

/// Dart's bundled roots, and those [pem] holds.
@visibleForTesting
SecurityContext contextTrusting(String pem) {
  final context = SecurityContext(withTrustedRoots: true);
  for (final certificate in pemCertificates(pem)) {
    try {
      context.setTrustedCertificatesBytes(utf8.encode(certificate));
    } on TlsException {
      // Among the bundled ones already: it is trusted either way.
    }
  }
  return context;
}

/// The certificates the machine trusts, as PEM, one after another: its root
/// store's, and on macOS those the user added to a keychain of their own.
/// Empty where they cannot be read (the bundled roots still are).
Future<String> systemCertificatesPem() => _pem ??= _readSystemCertificates();

Future<String>? _pem;

Future<String> _readSystemCertificates() async {
  try {
    if (Platform.isMacOS) return await _macOsCertificates();
    if (Platform.isWindows) return await _windowsCertificates();
    return await _linuxCertificates();
  } on Object catch (error) {
    debugPrint('System certificates not read: $error');
    return '';
  }
}

/// Apple's roots, those installed for every user, and the user's own
/// (where a proxy's or a company's CA goes).
Future<String> _macOsCertificates() async {
  final home = Platform.environment['HOME'];
  final keychains = [
    '/System/Library/Keychains/SystemRootCertificates.keychain',
    '/Library/Keychains/System.keychain',
    if (home != null) ...[
      p.join(home, 'Library/Keychains/login.keychain-db'),
      p.join(home, 'Library/Keychains/login.keychain'),
    ],
  ];
  final pem = StringBuffer();
  for (final keychain in keychains) {
    if (!File(keychain).existsSync()) continue;
    try {
      final result = await Process.run('/usr/bin/security', [
        'find-certificate',
        '-a',
        '-p',
        keychain,
      ]).timeout(const Duration(seconds: 5));
      if (result.exitCode == 0) pem.write(result.stdout);
    } on Object catch (error) {
      // Locked, or slow: the others' still are.
      debugPrint('$keychain not read: $error');
    }
  }
  return pem.toString();
}

/// The Windows certificate store's roots, the machine's and the user's:
/// what Chrome and Edge trust there, and Schannel.
Future<String> _windowsCertificates() async {
  // No progress: PowerShell's first run of a session prepares its modules
  // with a progress record on stderr.
  const script =
      r'$ErrorActionPreference = "Stop"; '
      r'$ProgressPreference = "SilentlyContinue"; '
      r'Get-ChildItem Cert:\LocalMachine\Root, Cert:\CurrentUser\Root | '
      r'ForEach-Object { "-----BEGIN CERTIFICATE-----"; '
      r'[Convert]::ToBase64String($_.RawData, "InsertLineBreaks"); '
      r'"-----END CERTIFICATE-----" }';
  final result = await Process.run('powershell.exe', [
    '-NoProfile',
    '-NonInteractive',
    '-Command',
    script,
  ]).timeout(const Duration(seconds: 10));
  return result.exitCode == 0 ? '${result.stdout}' : '';
}

/// The system's bundle on Linux (Debian's and Red Hat's places for it,
/// then the BSDs'), where the CAs a machine added of its own are.
Future<String> _linuxCertificates() async {
  for (final path in const [
    '/etc/ssl/certs/ca-certificates.crt',
    '/etc/pki/tls/certs/ca-bundle.crt',
    '/etc/ssl/cert.pem',
  ]) {
    final file = File(path);
    if (file.existsSync()) return file.readAsString();
  }
  return '';
}

/// The certificates [pem] holds, each a block of its own.
List<String> pemCertificates(String pem) => [
  for (final match in _pemCertificate.allMatches(pem)) match[0]!,
];

final _pemCertificate = RegExp(
  r'-----BEGIN CERTIFICATE-----[\s\S]*?-----END CERTIFICATE-----',
);

/// What Claude Code is given to trust the machine's certificates too
/// (`NODE_EXTRA_CA_CERTS`): Node bundles Mozilla's roots, as Dart does, and
/// a session on an upstream chaining to another root would be refused where
/// the app's own requests are not. None when the machine has no
/// certificates of its own, or the user set the variable themselves: their
/// file is the one to read then.
Future<Map<String, String>> nodeCertificatesEnvironment(
  Map<String, String> environment,
) async {
  if (environment['NODE_EXTRA_CA_CERTS'] case final set? when set.isNotEmpty) {
    return const {};
  }
  final path = await systemCertificatesFile();
  return path == null ? const {} : {'NODE_EXTRA_CA_CERTS': path};
}

/// Where the machine's certificates are kept for Node to read; null when it
/// has none. Written once, in the cache: made again as it is gone.
Future<String?> systemCertificatesFile() =>
    _certificatesFile ??= _writeCertificatesFile();

Future<String?>? _certificatesFile;

Future<String?> _writeCertificatesFile() async {
  final pem = await systemCertificatesPem();
  if (pem.isEmpty) return null;
  try {
    final directory = Directory(p.join(DataDirectory.current.cacheDir, 'tls'));
    final file = File(p.join(directory.path, 'system-ca.pem'));
    if (!file.existsSync() || await file.readAsString() != pem) {
      await directory.create(recursive: true);
      await writeFileAtomically(file, pem);
    }
    return file.path;
  } on Object catch (error) {
    debugPrint('System certificates not written: $error');
    return null;
  }
}
