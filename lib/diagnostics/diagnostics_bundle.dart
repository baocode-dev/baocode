import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'crash_reports.dart';

/// A file that a diagnostics upload sends: its [name] in the bundle,
/// `/`-separated, and its size. One of the logs folder
/// (`DataDirectory.logsDir`), its name under it; or a crash report of the
/// system's, read from [source].
class DiagnosticsLog {
  const DiagnosticsLog(this.name, this.size, {this.source});

  /// `errors.log`, `hangs/hang-20261011-013600-1234.dmp`,
  /// `crashes/BaoCode-2026-10-28-120616.ips`.
  final String name;
  final int size;

  /// Where a file from outside the logs folder is read: a crash report.
  final String? source;

  /// A crash report of the system's ([listCrashReports]).
  bool get isCrash => source != null;

  /// A minidump of a hang or a crash (Windows: windows/runner/
  /// hang_watchdog.h): sent
  /// only when asked, as it may hold what the app had in memory.
  bool get isDump => name.endsWith('.dmp');

  Map<String, Object> toJson() => {'name': name, 'size': size};
}

/// What a diagnostics upload sends: [bytes], a `tar.gz` of [files]; the
/// minidumps left out as they would not fit, [omittedDumps].
class DiagnosticsBundle {
  const DiagnosticsBundle(this.bytes, this.files, {this.omittedDumps = 0});

  final Uint8List bytes;
  final List<DiagnosticsLog> files;
  final int omittedDumps;
}

/// The most the server takes of a bundle (stats.baocode.dev's
/// `/v1/diagnostics`).
const maxDiagnosticsBytes = 10 * 1024 * 1024;

/// The logs of [folder]: its own `*.log` (errors.log and the run before's,
/// Windows' window.log), by name, then the system's crash reports of the
/// app in [crashFolders] ([listCrashReports]), then the hang and crash
/// reports of `hangs/`, the newest first. None where there is no folder.
List<DiagnosticsLog> listDiagnosticsLogs(
  String folder, {
  List<String> crashFolders = const [],
}) {
  List<DiagnosticsLog> filesOf(String directory, bool Function(String) take) {
    final dir = Directory(directory);
    if (!dir.existsSync()) return [];
    return [
      for (final entity in dir.listSync(followLinks: false))
        if (entity is File && take(p.basename(entity.path)))
          DiagnosticsLog(
            p.relative(entity.path, from: folder).replaceAll(r'\', '/'),
            entity.lengthSync(),
          ),
    ];
  }

  final logs = filesOf(folder, (name) => name.endsWith('.log'))
    ..sort((a, b) => a.name.compareTo(b.name));
  // hang-YYYYMMDD-HHMMSS-pid, crash-…, jank-…: sorted as the times, the
  // kind after.
  String time(DiagnosticsLog log) {
    final name = p.posix.basename(log.name);
    final dash = name.indexOf('-');
    return '${name.substring(dash + 1)} ${name.substring(0, dash + 1)}';
  }

  final hangs = filesOf(
    p.join(folder, 'hangs'),
    (name) => name.endsWith('.txt') || name.endsWith('.dmp'),
  )..sort((a, b) => time(b).compareTo(time(a)));
  return [
    ...logs,
    for (final report in listCrashReports(crashFolders))
      DiagnosticsLog(
        'crashes/${report.name}',
        report.size,
        source: report.path,
      ),
    ...hangs,
  ];
}

/// [listDiagnosticsLogs]'s files of [folder] packed, in another isolate:
/// see [packDiagnosticsSync].
Future<DiagnosticsBundle> packDiagnostics(
  String folder, {
  required bool dumps,
  List<String> crashFolders = const [],
  String? home,
  bool windows = false,
  int maxBytes = maxDiagnosticsBytes,
}) => Isolate.run(
  () => packDiagnosticsSync(
    folder,
    dumps: dumps,
    crashFolders: crashFolders,
    home: home,
    windows: windows,
    maxBytes: maxBytes,
  ),
);

/// The logs of [folder] and the crash reports of [crashFolders] as a
/// `tar.gz` of at most [maxBytes]: the text ones with [home] written `~`
/// ([redactHome]), the crash reports in UTF-8 ([reportText]) without the
/// machine's key ([redactCrashReport]); then, with [dumps], the minidumps as they are,
/// the newest first. What would make it too large is left out, and a file
/// gone or unreadable since it was listed.
///
/// Each file is a gzip member of its own, so that what it adds is known
/// as it is added; gzip and tar read the members as one stream.
DiagnosticsBundle packDiagnosticsSync(
  String folder, {
  required bool dumps,
  List<String> crashFolders = const [],
  String? home,
  bool windows = false,
  int maxBytes = maxDiagnosticsBytes,
}) {
  final listed = listDiagnosticsLogs(folder, crashFolders: crashFolders);
  final ordered = [
    ...listed.where((log) => !log.isDump),
    if (dumps) ...listed.where((log) => log.isDump),
  ];
  final codec = GZipCodec();
  final end = codec.encode(Uint8List(1024));
  final out = BytesBuilder(copy: false);
  final files = <DiagnosticsLog>[];
  var omitted = 0;
  for (final log in ordered) {
    final file = File(log.source ?? p.join(folder, log.name));
    Uint8List bytes;
    DateTime modified;
    try {
      bytes = file.readAsBytesSync();
      modified = file.lastModifiedSync();
    } on FileSystemException {
      continue;
    }
    if (!log.isDump && (home != null || log.isCrash)) {
      var text = log.isCrash
          ? reportText(bytes)
          : utf8.decode(bytes, allowMalformed: true);
      if (home != null) text = redactHome(text, home, windows: windows);
      if (log.isCrash) text = redactCrashReport(text);
      bytes = utf8.encode(text);
    }
    final member = codec.encode(tarEntry(log.name, bytes, modified));
    if (out.length + member.length + end.length > maxBytes) {
      if (log.isDump) omitted++;
      continue;
    }
    out.add(member);
    files.add(DiagnosticsLog(log.name, bytes.length));
  }
  out.add(end);
  return DiagnosticsBundle(out.takeBytes(), files, omittedDumps: omitted);
}

/// [text] with the user's [home] folder written `~`: in paths and in
/// JSON's escaped ones (`\/Users\/ann`, as macOS' crash reports have
/// them). On Windows, also with `/` between its parts, and in any case.
/// Not where it begins a longer name (`/Users/ann` in `/Users/anna`).
String redactHome(String text, String home, {bool windows = false}) {
  final trimmed = home.replaceFirst(RegExp(r'[\\/]+$'), '');
  // A root, or nothing: every path would go.
  if (trimmed.length < 2 || !trimmed.contains(RegExp(r'[\\/]'))) return text;
  final parts = trimmed.split(RegExp(r'[\\/]'));
  final variants = {
    trimmed,
    parts.join(r'\/'),
    if (windows) ...[parts.join('/'), parts.join(r'\'), parts.join(r'\\')],
  }.toList()..sort((a, b) => b.length.compareTo(a.length));
  final pattern = RegExp(
    '(?:${variants.map(RegExp.escape).join('|')})(?![A-Za-z0-9._-])',
    caseSensitive: !windows,
  );
  return text.replaceAll(pattern, '~');
}

/// [bytes] as a file of a tar (`ustar`): its header, then its content to
/// a whole number of blocks.
Uint8List tarEntry(String name, List<int> bytes, DateTime modified) {
  final header = Uint8List(512);
  void put(int offset, int length, String value) {
    final encoded = utf8.encode(value);
    header.setRange(
      offset,
      offset + (encoded.length < length ? encoded.length : length),
      encoded,
    );
  }

  String octal(int value, int digits) =>
      '${value.toRadixString(8).padLeft(digits, '0')}\u0000';

  var path = name;
  // The name field holds 100 bytes; the logs' names are far shorter.
  while (utf8.encode(path).length > 100) {
    path = path.substring(1);
  }
  put(0, 100, path);
  put(100, 8, octal(420, 7)); // 0644
  put(108, 8, octal(0, 7));
  put(116, 8, octal(0, 7));
  put(124, 12, octal(bytes.length, 11));
  put(136, 12, octal(modified.millisecondsSinceEpoch ~/ 1000, 11));
  put(148, 8, '        ');
  put(156, 1, '0');
  put(257, 6, 'ustar\u0000');
  put(263, 2, '00');
  var sum = 0;
  for (final byte in header) {
    sum += byte;
  }
  put(148, 8, '${sum.toRadixString(8).padLeft(6, '0')}\u0000 ');
  final padded = (bytes.length + 511) ~/ 512 * 512;
  return (BytesBuilder(copy: false)
        ..add(header)
        ..add(bytes)
        ..add(Uint8List(padded - bytes.length)))
      .takeBytes();
}
