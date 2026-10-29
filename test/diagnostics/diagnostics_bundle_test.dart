import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:baocode/diagnostics/diagnostics_bundle.dart';

/// The files of a tar: name → content.
Map<String, Uint8List> untar(List<int> tar) {
  final files = <String, Uint8List>{};
  var at = 0;
  while (at + 512 <= tar.length) {
    final header = tar.sublist(at, at + 512);
    if (header.every((byte) => byte == 0)) break;
    String field(int offset, int length) => utf8
        .decode(header.sublist(offset, offset + length))
        .split('\u0000')
        .first
        .trim();
    final size = int.parse(field(124, 12), radix: 8);
    var sum = 0;
    for (final (i, byte) in header.indexed) {
      sum += i >= 148 && i < 156 ? 32 : byte;
    }
    expect(int.parse(field(148, 8), radix: 8), sum, reason: 'checksum');
    expect(field(257, 6), 'ustar');
    files[field(0, 100)] = Uint8List.fromList(
      tar.sublist(at + 512, at + 512 + size),
    );
    at += 512 + (size + 511) ~/ 512 * 512;
  }
  return files;
}

void main() {
  late Directory logs;

  setUp(() async {
    logs = await Directory.systemTemp.createTemp('baocode-diagnostics');
  });

  tearDown(() => logs.delete(recursive: true));

  void write(String name, Object content) {
    final file = File(p.join(logs.path, name))
      ..parent.createSync(recursive: true);
    content is String
        ? file.writeAsStringSync(content)
        : file.writeAsBytesSync(content as List<int>);
  }

  /// Bytes gzip cannot make smaller.
  Uint8List noise(int length, int seed) {
    final random = Random(seed);
    return Uint8List.fromList([
      for (var i = 0; i < length; i++) random.nextInt(256),
    ]);
  }

  group('listDiagnosticsLogs', () {
    test('the logs by name, then the hang reports newest first', () {
      write('errors.log', 'a');
      write('errors.1.log', 'bb');
      write('window.log', 'c');
      write('notes.md', 'not a log');
      write('hangs/hang-20261010-120000-1.txt', 't1');
      write('hangs/hang-20261010-120000-1.dmp', 'd1');
      write('hangs/hang-20261011-090000-2.txt', 't2');
      write('hangs/hang-20261011-090000-2.dmp', 'd2');
      write('hangs/other.bin', 'x');
      final listed = listDiagnosticsLogs(logs.path);
      expect(
        [for (final log in listed) log.name],
        [
          'errors.1.log',
          'errors.log',
          'window.log',
          'hangs/hang-20261011-090000-2.txt',
          'hangs/hang-20261011-090000-2.dmp',
          'hangs/hang-20261010-120000-1.txt',
          'hangs/hang-20261010-120000-1.dmp',
        ],
      );
      expect(listed[0].size, 2);
      expect(
        [for (final log in listed) log.isDump],
        [false, false, false, false, true, false, true],
      );
    });

    test('none without the folder', () {
      expect(listDiagnosticsLogs(p.join(logs.path, 'gone')), isEmpty);
    });

    test('the crash reports between the logs and the hang reports', () {
      write('errors.log', 'a');
      write('hangs/hang-20261011-090000-2.txt', 't');
      write('reports/BaoCode-2026-10-28-120616.ips', '{}');
      final listed = listDiagnosticsLogs(
        logs.path,
        crashFolders: [p.join(logs.path, 'reports')],
      );
      expect(
        [for (final log in listed) log.name],
        [
          'errors.log',
          'crashes/BaoCode-2026-10-28-120616.ips',
          'hangs/hang-20261011-090000-2.txt',
        ],
      );
      expect([for (final log in listed) log.isCrash], [false, true, false]);
    });
  });

  test('the hang and crash reports of hangs/ sorted as their times', () {
    write('hangs/hang-20261010-120000-1.txt', 'h');
    write('hangs/crash-20261011-090000-2.txt', 'c');
    write('hangs/crash-20261011-090000-2.dmp', 'd');
    write('hangs/jank-20261009-000000-3.txt', 'j');
    expect(
      [for (final log in listDiagnosticsLogs(logs.path)) log.name],
      [
        'hangs/crash-20261011-090000-2.txt',
        'hangs/crash-20261011-090000-2.dmp',
        'hangs/hang-20261010-120000-1.txt',
        'hangs/jank-20261009-000000-3.txt',
      ],
    );
  });

  group('redactHome', () {
    test('the home folder becomes ~, not a longer name', () {
      expect(
        redactHome(
          'at /Users/ann/src/a.dart and /Users/anna/b, /Users/ann',
          '/Users/ann/',
        ),
        'at ~/src/a.dart and /Users/anna/b, ~',
      );
    });

    test('on Windows: either slash, escaped, in any case', () {
      expect(
        redactHome(
          r'C:\Users\Ann\a; c:/users/ann/b; {"p":"C:\\Users\\Ann\\c"}; '
              r'C:\Users\Anna',
          r'C:\Users\Ann',
          windows: true,
        ),
        r'~\a; ~/b; {"p":"~\\c"}; C:\Users\Anna',
      );
    });

    test("in JSON's escaped slashes, as macOS' crash reports have them", () {
      expect(
        redactHome(r'"procPath" : "\/Users\/ann\/a\/BaoCode"', '/Users/ann'),
        r'"procPath" : "~\/a\/BaoCode"',
      );
    });

    test('not a root, nor nothing', () {
      expect(redactHome('/etc/hosts', '/'), '/etc/hosts');
      expect(redactHome('/etc/hosts', ''), '/etc/hosts');
    });
  });

  group('packDiagnosticsSync', () {
    test('a tar.gz of the logs, the home folder written ~', () async {
      write('errors.log', 'boom at /Users/ann/project/main.dart\n');
      write('errors.1.log', 'older\n');
      write('hangs/hang-20261011-090000-2.txt', 'thread 1 /Users/ann/x\n');
      write('hangs/hang-20261011-090000-2.dmp', [0, 1, 2, 3]);
      final bundle = packDiagnosticsSync(
        logs.path,
        dumps: false,
        home: '/Users/ann',
      );
      expect(bundle.bytes.sublist(0, 2), [0x1f, 0x8b]);
      final files = untar(gzip.decode(bundle.bytes));
      expect(files.keys, [
        'errors.1.log',
        'errors.log',
        'hangs/hang-20261011-090000-2.txt',
      ]);
      expect(
        utf8.decode(files['errors.log']!),
        'boom at ~/project/main.dart\n',
      );
      expect(
        utf8.decode(files['hangs/hang-20261011-090000-2.txt']!),
        'thread 1 ~/x\n',
      );
      expect([for (final file in bundle.files) file.name], files.keys);
      expect(bundle.files[1].size, files['errors.log']!.length);
      expect(bundle.omittedDumps, 0);

      // As the system's tar reads it, its members one stream.
      if (!Platform.isWindows) {
        final path = p.join(logs.path, 'bundle.tar.gz');
        File(path).writeAsBytesSync(bundle.bytes);
        final listed = await Process.run('tar', ['-tzf', path]);
        expect(listed.exitCode, 0, reason: '${listed.stderr}');
        expect(
          const LineSplitter().convert('${listed.stdout}'),
          files.keys.toList(),
        );
      }
    });

    test('the minidumps as they are, when asked', () {
      final dump = [0x4d, 0x44, 0x4d, 0x50, 0xff, 0xfe, 0x00];
      write('hangs/hang-20261011-090000-2.dmp', dump);
      final bundle = packDiagnosticsSync(
        logs.path,
        dumps: true,
        home: '/Users/ann',
      );
      expect(untar(gzip.decode(bundle.bytes)), {
        'hangs/hang-20261011-090000-2.dmp': dump,
      });
    });

    test('the dumps that would not fit are left out, the newest kept', () {
      write('errors.log', 'boom\n');
      write('hangs/hang-20261009-000000-1.dmp', noise(40 * 1024, 1));
      write('hangs/hang-20261010-000000-1.dmp', noise(40 * 1024, 2));
      write('hangs/hang-20261011-000000-1.dmp', noise(40 * 1024, 3));
      final bundle = packDiagnosticsSync(
        logs.path,
        dumps: true,
        maxBytes: 100 * 1024,
      );
      expect(bundle.bytes.length, lessThanOrEqualTo(100 * 1024));
      expect(untar(gzip.decode(bundle.bytes)).keys, [
        'errors.log',
        'hangs/hang-20261011-000000-1.dmp',
        'hangs/hang-20261010-000000-1.dmp',
      ]);
      expect(bundle.omittedDumps, 1);
    });

    test('the crash reports, without the home folder and the key', () {
      write('errors.log', 'boom\n');
      write(
        'reports/BaoCode-2026-10-28-120616.ips',
        '{"procPath" : "\\/Users\\/ann\\/BaoCode.app",'
            ' "crashReporterKey" : "742F288F"}',
      );
      final bundle = packDiagnosticsSync(
        logs.path,
        dumps: false,
        crashFolders: [p.join(logs.path, 'reports')],
        home: '/Users/ann',
      );
      final files = untar(gzip.decode(bundle.bytes));
      expect(files.keys, [
        'errors.log',
        'crashes/BaoCode-2026-10-28-120616.ips',
      ]);
      expect(
        utf8.decode(files['crashes/BaoCode-2026-10-28-120616.ips']!),
        '{"procPath" : "~\\/BaoCode.app", "crashReporterKey" : ""}',
      );
      expect(
        bundle.files.last.size,
        files['crashes/BaoCode-2026-10-28-120616.ips']!.length,
      );
    });

    test("Windows' reports, in UTF-8, the home folder written ~", () {
      final wer = 'EventType=APPCRASH\r\nAppPath=C:\\Users\\Ann\\b.exe\r\n';
      write('wer/AppCrash_baocode.exe_1a_2b/Report.wer', [
        0xff,
        0xfe,
        for (final unit in wer.codeUnits) ...[unit & 0xff, unit >> 8],
      ]);
      final bundle = packDiagnosticsSync(
        logs.path,
        dumps: false,
        crashFolders: [p.join(logs.path, 'wer')],
        home: r'C:\Users\Ann',
        windows: true,
      );
      expect(
        utf8.decode(
          untar(
            gzip.decode(bundle.bytes),
          )['crashes/AppCrash_baocode.exe_1a_2b.wer']!,
        ),
        'EventType=APPCRASH\r\nAppPath=~\\b.exe\r\n',
      );
    });

    test('nothing to send: an empty tar', () {
      final bundle = packDiagnosticsSync(logs.path, dumps: true);
      expect(untar(gzip.decode(bundle.bytes)), isEmpty);
      expect(bundle.files, isEmpty);
    });
  });
}
