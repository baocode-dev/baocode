import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../platform/data_dir.dart';
import '../telemetry/telemetry_io.dart' show abiArch;
import '../update/version.dart';
import 'crash_reports.dart';
import 'diagnostics_bundle.dart';

/// Where to upload instead, to try a server.
const diagnosticsUrlVariable = 'BAOCODE_DIAGNOSTICS_URL';

/// Why an upload did not get through.
enum DiagnosticsFailure {
  /// 413: more than the server takes.
  tooLarge,

  /// 429: too many from here just now, or from everyone today.
  rateLimited,

  /// Another 4xx: the server will not take it as it is.
  refused,

  /// A 5xx, or an answer it does not understand.
  server,

  /// It did not get there: offline, a timeout.
  network,
}

/// What an upload came to.
sealed class DiagnosticsResult {
  const DiagnosticsResult();
}

/// Uploaded: the report's [id] (`D7F3K2QX`), for the user to quote, and
/// the minidumps left out of it, too large.
final class DiagnosticsUploaded extends DiagnosticsResult {
  const DiagnosticsUploaded(this.id, {this.omittedDumps = 0});

  final String id;
  final int omittedDumps;
}

final class DiagnosticsFailed extends DiagnosticsResult {
  const DiagnosticsFailed(this.reason, {this.status, this.error});

  final DiagnosticsFailure reason;

  /// The HTTP status, where there was an answer.
  final int? status;
  final Object? error;
}

/// Uploads the logs folder's files and the system's crash reports of the
/// app ([packDiagnostics]) to stats.baocode.dev
/// when the user asks to (Settings → Updates → Diagnostic Logs): with
/// the note they typed, the app's version, the system's and the display
/// language; nothing that tells who sent it, not the usage statistics'
/// install id.
class DiagnosticsUploader {
  DiagnosticsUploader({
    required this.folder,
    Uri? url,
    String? version,
    String? os,
    String? osVersion,
    String? arch,
    this.crashFolders = const [],
    this.home,
    this.windows = false,
    this.timeout = const Duration(seconds: 15),
    this.uploadTimeout = const Duration(minutes: 3),
    HttpClient Function()? client,
  }) : url = url ?? Uri.parse(defaultUrl),
       version = version ?? '$currentAppVersion',
       os = os ?? Platform.operatingSystem,
       osVersion = osVersion ?? Platform.operatingSystemVersion,
       arch = arch ?? abiArch(Abi.current()),
       _client = client ?? HttpClient.new;

  /// The app's: the data folder's `logs`, the system's crash reports
  /// ([crashReportFolders]), [url] the one [diagnosticsUrlVariable] names,
  /// if any.
  factory DiagnosticsUploader.platform() {
    final environment = Platform.environment;
    final override = environment[diagnosticsUrlVariable]?.trim() ?? '';
    final home = Platform.isWindows
        ? environment['USERPROFILE']
        : environment['HOME'];
    return DiagnosticsUploader(
      folder: DataDirectory.current.logsDir,
      url: override.isEmpty ? null : Uri.tryParse(override),
      crashFolders: platformCrashReportFolders(),
      home: home,
      windows: Platform.isWindows,
    );
  }

  static const defaultUrl = 'https://stats.baocode.dev/v1/diagnostics';

  /// The version of the report's `meta`.
  static const schema = 1;

  /// The most of a note the server keeps, in characters (code points).
  static const maxNote = 2000;

  /// The logs folder.
  final String folder;

  /// Where the system keeps the app's crash reports ([listCrashReports]).
  final List<String> crashFolders;
  final Uri url;
  final String version;
  final String os;
  final String osVersion;
  final String arch;

  /// The user's home folder, written `~` in what is sent.
  final String? home;
  final bool windows;

  /// To connect and to read the answer; and to send the whole of it.
  final Duration timeout;
  final Duration uploadTimeout;

  final HttpClient Function() _client;

  HttpClient? _sending;

  /// What would be sent, as the logs are now.
  Future<List<DiagnosticsLog>> logs() async =>
      listDiagnosticsLogs(folder, crashFolders: crashFolders);

  /// The logs folder, made if need be (to show it).
  Future<String> ensureFolder() async {
    await Directory(folder).create(recursive: true);
    return folder;
  }

  /// Packs the logs, with the minidumps if [dumps], and sends them with
  /// [note]; [locale] the display language's (`zh`).
  Future<DiagnosticsResult> upload({
    required String note,
    required bool dumps,
    String? locale,
  }) async {
    final bundle = await packDiagnostics(
      folder,
      dumps: dumps,
      crashFolders: crashFolders,
      home: home,
      windows: windows,
    );
    final boundary = 'BaoCode${_randomToken()}';
    final body = multipartBody(boundary, {
      'v': schema,
      'version': version,
      'os': os,
      'os_version': _clip(osVersion.trim(), 200),
      'arch': arch,
      if (locale != null && RegExp(r'^[A-Za-z0-9_-]{1,35}$').hasMatch(locale))
        'locale': locale,
      if (note.trim().isNotEmpty) 'note': _clip(note.trim(), maxNote),
      'files': [for (final file in bundle.files) file.toJson()],
    }, bundle.bytes);
    final client = _sending = _client()
      ..connectionTimeout = timeout
      ..userAgent = 'BaoCode/$version ($os)';
    try {
      final request = await client.postUrl(url).timeout(timeout);
      request.headers.contentType = ContentType(
        'multipart',
        'form-data',
        parameters: {'boundary': boundary},
      );
      request.contentLength = body.length;
      request.add(body);
      final response = await request.close().timeout(uploadTimeout);
      final text = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      return answer(
        response.statusCode,
        text,
        omittedDumps: bundle.omittedDumps,
      );
    } on Object catch (error) {
      debugPrint('diagnostics: not sent: $error');
      return DiagnosticsFailed(DiagnosticsFailure.network, error: error);
    } finally {
      _sending = null;
      client.close(force: true);
    }
  }

  /// Stops the upload under way, if any: it completes as
  /// [DiagnosticsFailure.network].
  void cancel() => _sending?.close(force: true);

  /// What the server's answer, [status] with [body], tells.
  @visibleForTesting
  static DiagnosticsResult answer(
    int status,
    String body, {
    int omittedDumps = 0,
  }) {
    if (status >= 200 && status < 300) {
      final id = switch (_json(body)) {
        {'id': final String id} when RegExp(r'^[0-9A-Z]{4,32}$').hasMatch(id) =>
          id,
        _ => null,
      };
      return id == null
          ? DiagnosticsFailed(DiagnosticsFailure.server, status: status)
          : DiagnosticsUploaded(id, omittedDumps: omittedDumps);
    }
    final reason = switch (status) {
      413 => DiagnosticsFailure.tooLarge,
      429 => DiagnosticsFailure.rateLimited,
      >= 400 && < 500 => DiagnosticsFailure.refused,
      _ => DiagnosticsFailure.server,
    };
    return DiagnosticsFailed(reason, status: status);
  }

  /// `multipart/form-data` of [meta], as JSON, and [logs], the bundle.
  @visibleForTesting
  static Uint8List multipartBody(
    String boundary,
    Map<String, Object?> meta,
    Uint8List logs,
  ) =>
      (BytesBuilder(copy: false)
            ..add(
              utf8.encode(
                '--$boundary\r\n'
                'Content-Disposition: form-data; name="meta"\r\n'
                'Content-Type: application/json; charset=utf-8\r\n\r\n'
                '${jsonEncode(meta)}\r\n'
                '--$boundary\r\n'
                'Content-Disposition: form-data; name="logs"; '
                'filename="diagnostics.tar.gz"\r\n'
                'Content-Type: application/gzip\r\n\r\n',
              ),
            )
            ..add(logs)
            ..add(utf8.encode('\r\n--$boundary--\r\n')))
          .takeBytes();

  static Object? _json(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }

  /// The first [max] characters of [text].
  static String _clip(String text, int max) => text.runes.length <= max
      ? text
      : String.fromCharCodes(text.runes.take(max));

  static String _randomToken() {
    final random = Random.secure();
    return [
      for (var i = 0; i < 16; i++)
        random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
  }
}
