import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// A crash report the system kept of the app, outside the logs folder:
/// macOS' `BaoCode-<time>.ips` (a crash, a hang it caught, a kill for
/// memory), and its spindump's `BaoCode_<time>_<host>.hang` (the app
/// quit by force while it hung), `.spin` (a hang it came out of) and
/// `.cpu_resource.diag` (the CPU kept busy for minutes); Windows Error Reporting's `Report.wer` of an
/// `AppCrash_baocode.exe_…` or `AppHang_…` folder. Linux keeps none the
/// app can read: its own (see packages/bao_sampler's crash handler) are
/// in the logs folder's `hangs/`.
class CrashReport {
  const CrashReport(this.name, this.path, this.modified, this.size);

  /// Its name in a diagnostics bundle: `BaoCode-2026-10-28-120616.ips`,
  /// `BaoCode_2026-10-28-141700.hang` (the computer's name left out),
  /// `AppCrash_baocode.exe_1a2b_3c4d.wer`.
  final String name;

  /// The file.
  final String path;
  final DateTime modified;
  final int size;
}

/// The most crash reports a bundle takes: the newest.
const maxCrashReports = 8;

/// Where the system keeps the app's crash reports, on this platform: see
/// [CrashReport]. [environment] the process', where the folders are
/// found.
List<String> crashReportFolders({
  required String operatingSystem,
  required Map<String, String> environment,
}) {
  switch (operatingSystem) {
    case 'macos':
      // The user's (crashes), then the machine's (spindump's hangs, the
      // CPU kept busy), which an administrator can read; Retired: those
      // already sent to Apple.
      final home = environment['HOME'];
      return [
        for (final reports in [
          if (home != null && home.isNotEmpty)
            p.join(home, 'Library', 'Logs', 'DiagnosticReports'),
          '/Library/Logs/DiagnosticReports',
        ]) ...[reports, p.join(reports, 'Retired')],
      ];
    case 'windows':
      // The user's own, and the machine's (where an app's crash may go).
      return [
        for (final root in [
          environment['LOCALAPPDATA'],
          environment['ProgramData'] ?? environment['PROGRAMDATA'],
        ])
          if (root != null && root.isNotEmpty)
            for (final kind in const ['ReportArchive', 'ReportQueue'])
              p.windows.join(root, 'Microsoft', 'Windows', 'WER', kind),
      ];
    default:
      return const [];
  }
}

/// [crashReportFolders] of this app's platform.
List<String> platformCrashReportFolders() => crashReportFolders(
  operatingSystem: Platform.operatingSystem,
  environment: Platform.environment,
);

/// The names macOS gives the app's reports: its process's name first. Not
/// `BaoCodeHelper` and the like.
final macReportName = RegExp(r'^BaoCode[-_.].*\.(?:ips|hang|spin|diag)$');

/// A report's [name] without the computer's, which spindump's have after
/// the time: `BaoCode_2026-10-28-141700_anns-MacBook.hang` is
/// `BaoCode_2026-10-28-141700.hang`.
String macReportBundleName(String name) => name.replaceFirstMapped(
  RegExp(r'^(BaoCode_\d{4}-\d\d-\d\d-\d{6})_[^.]+(\..+)$'),
  (match) => '${match[1]}${match[2]}',
);

/// Whether a macOS report of [name] tells of the app ending: a crash, a
/// kill, a hang it was quit at; not a hang it came out of nor its CPU use.
bool macReportEnds(String name) =>
    name.endsWith('.ips') || name.endsWith('.hang');

/// The folders Windows Error Reporting keeps a report of the app in, its
/// `Report.wer` inside: `AppCrash_baocode.exe_<hash>_<id>`.
final werFolderName = RegExp(
  r'^App(?:Crash|Hang)_baocode\.exe_',
  caseSensitive: false,
);

/// The app's crash reports in [folders], the [max] newest first; a name
/// in two folders once.
List<CrashReport> listCrashReports(
  List<String> folders, {
  int max = maxCrashReports,
}) {
  final found = <String, CrashReport>{};
  void add(String name, File file) {
    if (found.containsKey(name)) return;
    try {
      final stat = file.statSync();
      if (stat.type != FileSystemEntityType.file) return;
      found[name] = CrashReport(name, file.path, stat.modified, stat.size);
    } on FileSystemException {
      // Gone, or not to be read.
    }
  }

  for (final folder in folders) {
    try {
      final dir = Directory(folder);
      if (!dir.existsSync()) continue;
      for (final entity in dir.listSync(followLinks: false)) {
        final name = p.basename(entity.path);
        if (entity is File && macReportName.hasMatch(name)) {
          add(macReportBundleName(name), entity);
        } else if (entity is Directory && werFolderName.hasMatch(name)) {
          add('$name.wer', File(p.join(entity.path, 'Report.wer')));
        }
      }
    } on FileSystemException {
      // Not to be read: none from there.
    }
  }
  final newest = found.values.toList()
    ..sort((a, b) => b.modified.compareTo(a.modified));
  return newest.take(max).toList();
}

/// The text of a report's [bytes]: UTF-8, or UTF-16 with its byte order
/// mark (Windows' Report.wer).
String reportText(Uint8List bytes) {
  if (bytes.length >= 2) {
    final little = bytes[0] == 0xff && bytes[1] == 0xfe;
    final big = bytes[0] == 0xfe && bytes[1] == 0xff;
    if (little || big) {
      final units = <int>[
        for (var i = 2; i + 1 < bytes.length; i += 2)
          little ? bytes[i] | bytes[i + 1] << 8 : bytes[i] << 8 | bytes[i + 1],
      ];
      return String.fromCharCodes(units);
    }
  }
  return utf8.decode(bytes, allowMalformed: true);
}

/// A crash report without what is the same in every report of the
/// machine, and so would tell one user's reports: macOS'
/// `crashReporterKey`; Windows' `ReportIdentifier`-like ids are not of
/// the machine.
String redactCrashReport(String text) => text.replaceAllMapped(
  RegExp(r'("crashReporterKey"\s*:\s*")[^"]*"'),
  (match) => '${match[1]}"',
);

/// What a report says went wrong, in a line: macOS' exception and signal
/// (`EXC_BAD_ACCESS (SIGSEGV)`), Windows' event, module, code and offset
/// (`APPCRASH flutter_windows.dll c0000005 +0x1234`). Null when it says
/// nothing of that.
String? describeCrashReport(String text) {
  final trimmed = text.trimLeft();
  if (trimmed.startsWith('{')) return _describeIps(trimmed);
  if (trimmed.contains('EventType=')) return _describeWer(trimmed);
  return _describeSpindump(trimmed);
}

/// A spindump's `.hang`, `.spin` or `.diag`: lines of `Name: value` first,
/// its event (`hang`, `cpu usage`) and how long among them.
String? _describeSpindump(String text) {
  String? field(String name) => RegExp(
    '^$name:[ \\t]+(.+)\$',
    multiLine: true,
  ).firstMatch(text)?.group(1)?.trim();
  final event = field('Event');
  if (event == null) return null;
  return [event, ?(field('CPU') ?? field('Duration'))].join(', ');
}

/// An `.ips`: a line of JSON (what the report is), then the report's.
String? _describeIps(String text) {
  final newline = text.indexOf('\n');
  final header = _json(newline < 0 ? text : text.substring(0, newline));
  final body = newline < 0 ? null : _json(text.substring(newline + 1));
  final parts = <String>[];
  if (body case {'exception': final Map<String, Object?> exception}) {
    final type = exception['type'];
    final signal = exception['signal'];
    if (type is String) parts.add(signal is String ? '$type ($signal)' : type);
  }
  if (body case {'termination': {'indicator': final String indicator}}) {
    parts.add(indicator);
  }
  if (parts.isEmpty) {
    // Not a crash: a hang, a kill for memory.
    if (header case {'bug_type': final String type}) return 'bug type $type';
    return null;
  }
  return parts.join(', ');
}

String? _describeWer(String text) {
  final values = <String, String>{};
  final names = <String, String>{};
  for (final line in const LineSplitter().convert(text)) {
    final equals = line.indexOf('=');
    if (equals < 0) continue;
    final key = line.substring(0, equals).trim();
    final value = line.substring(equals + 1).trim();
    if (key.endsWith('.Name')) {
      names[key.substring(0, key.length - 5)] = value;
    } else if (key.endsWith('.Value')) {
      values[key.substring(0, key.length - 6)] = value;
    } else {
      values[key] = value;
    }
  }
  String? named(String name) {
    for (final MapEntry(key: key, value: label) in names.entries) {
      if (label == name) return values[key];
    }
    return null;
  }

  final parts = [
    ?values['EventType'],
    ?named('Fault Module Name'),
    ?named('Exception Code'),
    if (named('Exception Offset') case final offset?) '+0x$offset',
  ];
  return parts.isEmpty ? null : parts.join(' ');
}

Object? _json(String text) {
  try {
    return jsonDecode(text);
  } on FormatException {
    return null;
  }
}

/// The newest of the app's crash reports in [folders] written after
/// [since] (less a little: the report may be stamped as the crash began),
/// as `<name>: <what it says>`. Null when there is none.
String? crashReportSince(List<String> folders, DateTime since) {
  final after = since.subtract(const Duration(seconds: 5));
  for (final report in listCrashReports(folders)) {
    if (report.modified.isBefore(after)) return null;
    if (report.name.startsWith('BaoCode') && !macReportEnds(report.name)) {
      continue;
    }
    try {
      final text = reportText(File(report.path).readAsBytesSync());
      final what = describeCrashReport(text);
      return what == null ? report.name : '${report.name}: $what';
    } on FileSystemException {
      continue;
    }
  }
  return null;
}
