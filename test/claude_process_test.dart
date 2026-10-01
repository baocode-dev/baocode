@TestOn('mac-os || linux')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/kernel/claude_code/process_transport_io.dart';
import 'package:path/path.dart' as p;

/// The app's Claude Code processes end with it, and leftovers of an earlier
/// run are ended. A plain `sleep` stands in for Claude Code: no CLI runs.
void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('baocode-processes');
    file = File(p.join(dir.path, 'claude-processes.json'));
    // Never the user's own list, nor their processes.
    ProcessTransport.registry = ClaudeProcessRegistry(
      file: File(p.join(dir.path, 'transport-processes.json')),
      lookup: (_) async => null,
      signal: (_) => false,
    );
  });
  tearDown(() => dir.deleteSync(recursive: true));

  const claude =
      '/usr/local/bin/claude -p --input-format stream-json '
      '--output-format stream-json';

  test('stopAll ends every running process and waits for it', () async {
    final process = await Process.start('sleep', ['30']);
    final transport = ProcessTransport.forProcess(process);
    var exited = false;
    unawaited(transport.exited.then((_) => exited = true));

    await ProcessTransport.registry.reaped;
    final listed = File(p.join(dir.path, 'transport-processes.json'));
    await expectListed(listed, [
      {'pid': process.pid, 'parent': pid},
    ]);

    await ProcessTransport.stopAll();
    await transport.exited.timeout(const Duration(seconds: 5));
    expect(exited, isTrue);
    await expectListed(listed, isEmpty);
    expect(await process.exitCode, isNot(0));
  });

  test('stopAll kills a process that ignores the polite stop', () async {
    // A shell that ignores SIGTERM and keeps its stdin open.
    final process = await Process.start('sh', ['-c', 'trap "" TERM; sleep 30']);
    final transport = ProcessTransport.forProcess(process);
    await ProcessTransport.stopAll(timeout: const Duration(milliseconds: 300));
    await transport.exited.timeout(const Duration(seconds: 5));
  });

  test('reaps orphans and hot-restart children, never other apps', () async {
    const ownPid = 500;
    file.writeAsStringSync(
      jsonEncode([
        {'pid': 11, 'parent': 400}, // Orphaned: its app is gone.
        {'pid': 12, 'parent': ownPid}, // An earlier isolate of this process.
        {'pid': 13, 'parent': 600}, // Another copy of the app, still running.
        {'pid': 14, 'parent': 400}, // Gone already.
        {'pid': 15, 'parent': 400}, // The pid now runs something else.
      ]),
    );
    final running = <int, ({int parent, String command})>{
      11: (parent: 1, command: claude),
      12: (parent: ownPid, command: claude),
      13: (parent: 600, command: claude),
      15: (parent: 1, command: '/usr/bin/vim notes.txt'),
    };
    final signalled = <int>[];
    final registry = ClaudeProcessRegistry(
      file: file,
      ownPid: ownPid,
      lookup: (pid) async => running[pid],
      signal: (pid) {
        signalled.add(pid);
        return true;
      },
    );

    await registry.reaped;
    expect(signalled, [11, 12]);
    // What another app still runs stays listed; the rest is forgotten.
    expect(jsonDecode(file.readAsStringSync()), [
      {'pid': 13, 'parent': 600},
    ]);

    await registry.add(21);
    await registry.add(22);
    await registry.remove(21);
    expect(jsonDecode(file.readAsStringSync()), [
      {'pid': 13, 'parent': 600},
      {'pid': 22, 'parent': ownPid},
    ]);
  });

  test('a missing or unreadable file reaps nothing', () async {
    final signalled = <int>[];
    ClaudeProcessRegistry registry(File file) => ClaudeProcessRegistry(
      file: file,
      ownPid: 500,
      lookup: (_) async => (parent: 1, command: claude),
      signal: (pid) {
        signalled.add(pid);
        return true;
      },
    );
    await registry(file).reaped;
    file.writeAsStringSync('not json');
    await registry(file).reaped;
    expect(signalled, isEmpty);
  });
}

/// Waits (a while) for [file], written in the background, to list what
/// [matcher] matches.
Future<void> expectListed(File file, Object? matcher) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (true) {
    final text = file.existsSync() ? file.readAsStringSync() : '';
    final found = text.isEmpty ? null : jsonDecode(text);
    if (wrapMatcher(matcher).matches(found, {}) ||
        DateTime.now().isAfter(deadline)) {
      expect(found, matcher);
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
