import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:baocode/diagnostics/crash_reports.dart';

const _hour = Duration(hours: 1);

/// A Report.wer as Windows writes it: UTF-16, little-endian, with its mark.
Uint8List _utf16(String text) => Uint8List.fromList([
  0xff,
  0xfe,
  for (final unit in text.codeUnits) ...[unit & 0xff, unit >> 8],
]);

const _wer = '''Version=1
EventType=APPCRASH
Sig[0].Name=Application Name
Sig[0].Value=baocode.exe
Sig[3].Name=Fault Module Name
Sig[3].Value=flutter_windows.dll
Sig[6].Name=Exception Code
Sig[6].Value=c0000005
Sig[7].Name=Exception Offset
Sig[7].Value=00000000001a2b3c
AppPath=C:\\Users\\Ann\\AppData\\Local\\Programs\\BaoCode\\baocode.exe
''';

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('crash_reports'));
  tearDown(() => root.deleteSync(recursive: true));

  File write(String path, Object content, [DateTime? modified]) {
    final file = File(p.join(root.path, path))
      ..parent.createSync(recursive: true);
    content is String
        ? file.writeAsStringSync(content)
        : file.writeAsBytesSync(content as List<int>);
    if (modified != null) file.setLastModifiedSync(modified);
    return file;
  }

  group('listCrashReports', () {
    test("the app's, the newest first, a name in two folders once", () {
      final day = DateTime(2026, 10, 28);
      write('reports/BaoCode-2026-10-26-100000.ips', '{}', day);
      write('reports/BaoCode-2026-10-28-120616.ips', '{}', day.add(_hour * 3));
      write(
        'reports/Retired/BaoCode-2026-10-27-100000.ips',
        '{}',
        day.add(_hour),
      );
      write('reports/Retired/BaoCode-2026-10-28-120616.ips', '{}', day);
      write('reports/BaoCodeHelper-2026-10-28-130000.ips', '{}', day);
      write('reports/Safari-2026-10-28-130000.ips', '{}', day);
      write('reports/BaoCode-2026-10-28-130000.txt', '{}', day);
      write(
        'wer/AppCrash_baocode.exe_1a2b_3c4d/Report.wer',
        _utf16(_wer),
        day.add(_hour * 2),
      );
      write('wer/AppCrash_other.exe_1a2b_3c4d/Report.wer', _utf16(_wer), day);
      // A folder without its report.
      Directory(p.join(root.path, 'wer', 'AppHang_baocode.exe_5e6f'))
          .createSync(recursive: true);
      final reports = p.join(root.path, 'reports');
      final listed = listCrashReports([
        reports,
        p.join(reports, 'Retired'),
        p.join(root.path, 'wer'),
        p.join(root.path, 'gone'),
      ]);
      expect(
        [for (final report in listed) report.name],
        [
          'BaoCode-2026-10-28-120616.ips',
          'AppCrash_baocode.exe_1a2b_3c4d.wer',
          'BaoCode-2026-10-27-100000.ips',
          'BaoCode-2026-10-26-100000.ips',
        ],
      );
      expect(
        listed.first.path,
        p.join(reports, 'BaoCode-2026-10-28-120616.ips'),
      );
      expect(listed.first.size, 2);
    });

    test("spindump's reports, the computer's name left out", () {
      final day = DateTime(2026, 10, 28);
      write(
        'machine/BaoCode_2026-10-28-141700_anns-MacBook.hang',
        'Event: hang',
        day.add(_hour * 2),
      );
      write(
        'machine/BaoCode_2026-10-26-214759_anns-MacBook.cpu_resource.diag',
        'Event: cpu usage',
        day.add(_hour),
      );
      write('machine/BaoCode_2026-10-28-100000_anns-MacBook.spin', '', day);
      write('machine/BaoCodeHelper_2026-10-28-100000_a.hang', '', day);
      write('machine/Safari_2026-10-28-100000_a.hang', '', day);
      expect(
        [
          for (final report in listCrashReports([p.join(root.path, 'machine')]))
            report.name,
        ],
        [
          'BaoCode_2026-10-28-141700.hang',
          'BaoCode_2026-10-26-214759.cpu_resource.diag',
          'BaoCode_2026-10-28-100000.spin',
        ],
      );
      expect(
        macReportBundleName('BaoCode-2026-10-28-120616.ips'),
        'BaoCode-2026-10-28-120616.ips',
      );
    });

    test('no more than the newest few', () {
      for (var i = 0; i < maxCrashReports + 2; i++) {
        write(
          'reports/BaoCode-2026-10-${10 + i}-000000.ips',
          '{}',
          DateTime(2026, 10, 10 + i),
        );
      }
      final listed = listCrashReports([p.join(root.path, 'reports')]);
      expect(listed, hasLength(maxCrashReports));
      expect(
        listed.first.name,
        'BaoCode-2026-10-${10 + maxCrashReports + 1}-000000.ips',
      );
    });
  });

  test('the folders, of each system', () {
    expect(
      crashReportFolders(
        operatingSystem: 'macos',
        environment: {'HOME': '/Users/ann'},
      ),
      [
        p.join('/Users/ann', 'Library', 'Logs', 'DiagnosticReports'),
        p.join('/Users/ann', 'Library', 'Logs', 'DiagnosticReports', 'Retired'),
        '/Library/Logs/DiagnosticReports',
        p.join('/Library/Logs/DiagnosticReports', 'Retired'),
      ],
    );
    expect(
      crashReportFolders(
        operatingSystem: 'windows',
        environment: {
          'LOCALAPPDATA': r'C:\Users\Ann\AppData\Local',
          'ProgramData': r'C:\ProgramData',
        },
      ),
      [
        r'C:\Users\Ann\AppData\Local\Microsoft\Windows\WER\ReportArchive',
        r'C:\Users\Ann\AppData\Local\Microsoft\Windows\WER\ReportQueue',
        r'C:\ProgramData\Microsoft\Windows\WER\ReportArchive',
        r'C:\ProgramData\Microsoft\Windows\WER\ReportQueue',
      ],
    );
    expect(
      crashReportFolders(operatingSystem: 'linux', environment: {}),
      isEmpty,
    );
  });

  test('a report in UTF-16 or UTF-8', () {
    expect(reportText(_utf16('EventType=APPCRASH')), 'EventType=APPCRASH');
    expect(reportText(utf8.encode('{"a":"é"}')), '{"a":"é"}');
  });

  test("the machine's key goes, the rest stays", () {
    expect(
      redactCrashReport(
        '{\n  "pid" : 1980,\n'
        '  "crashReporterKey" : "742F288F-5181-E91C-D926-856AE707E206",\n'
        '  "procName" : "BaoCode"\n}',
      ),
      '{\n  "pid" : 1980,\n'
      '  "crashReporterKey" : "",\n'
      '  "procName" : "BaoCode"\n}',
    );
  });

  group('describeCrashReport', () {
    test("macOS': the exception, the signal, the termination", () {
      expect(
        describeCrashReport(
          '{"app_name":"BaoCode","bug_type":"309"}\n'
          '{\n  "exception" : {"type":"EXC_BAD_ACCESS","signal":"SIGSEGV"},\n'
          '  "termination" : {"indicator":"Segmentation fault: 11"}\n}',
        ),
        'EXC_BAD_ACCESS (SIGSEGV), Segmentation fault: 11',
      );
      expect(
        describeCrashReport('{"app_name":"BaoCode","bug_type":"288"}\n{}'),
        'bug type 288',
      );
    });

    test("Windows': the event, the module, the code, the offset", () {
      expect(
        describeCrashReport(_wer),
        'APPCRASH flutter_windows.dll c0000005 +0x00000000001a2b3c',
      );
    });

    test("spindump's: the event, and how long", () {
      expect(
        describeCrashReport(
          'Date/Time:        2026-10-28 14:17:00.000 +0800\n'
          'Command:          BaoCode\n'
          'Event:            hang\n'
          'Duration:         12.34s\n',
        ),
        'hang, 12.34s',
      );
      expect(
        describeCrashReport(
          'Event:            cpu usage\n'
          'CPU:              90 seconds cpu time over 173 seconds\n'
          'Duration:         173.36s\n',
        ),
        'cpu usage, 90 seconds cpu time over 173 seconds',
      );
    });

    test('nothing it knows', () {
      expect(describeCrashReport('hello'), isNull);
    });
  });

  test('the report written since a time, and what it says', () {
    final crash = DateTime(2026, 10, 28, 12, 47);
    write(
      'reports/BaoCode-2026-10-28-124700.ips',
      '{"bug_type":"309"}\n{"exception":{"type":"EXC_CRASH","signal":"SIGABRT"}}',
      crash,
    );
    final folders = [p.join(root.path, 'reports')];
    expect(
      crashReportSince(folders, crash.subtract(const Duration(minutes: 1))),
      'BaoCode-2026-10-28-124700.ips: EXC_CRASH (SIGABRT)',
    );
    expect(crashReportSince(folders, crash.add(_hour)), isNull);
  });

  test(
    'of the app ending only: not its CPU use, nor a hang it came out of',
    () {
      final quit = DateTime(2026, 10, 28, 14, 17);
      write(
        'reports/BaoCode_2026-10-28-141700_ann.hang',
        'Event: hang\nDuration: 21.50s\n',
        quit,
      );
      write(
        'reports/BaoCode_2026-10-28-141800_ann.cpu_resource.diag',
        'Event: cpu usage\n',
        quit.add(const Duration(minutes: 1)),
      );
      write(
        'reports/BaoCode_2026-10-28-141900_ann.spin',
        'Event: hang\n',
        quit.add(const Duration(minutes: 2)),
      );
      expect(
        crashReportSince([
          p.join(root.path, 'reports'),
        ], quit.subtract(const Duration(minutes: 1))),
        'BaoCode_2026-10-28-141700.hang: hang, 21.50s',
      );
    },
  );
}
