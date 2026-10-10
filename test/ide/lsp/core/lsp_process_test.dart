@TestOn('mac-os || linux')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/lsp/lsp_process.dart';
import 'package:baocode/ide/lsp/lsp_process_io.dart';
import 'package:baocode/kernel/claude_code/claude_environment.dart';
import 'package:baocode/platform/child_process_registry.dart';
import 'package:path/path.dart' as p;

import '../../../fixtures/lsp/fake_lsp.dart';

/// Language server processes are recorded while they run, end with the
/// app, and those an earlier run left are reaped: only when they still run
/// the command recorded for them.
void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('baocode-lsp-processes');
    file = File(p.join(dir.path, 'lsp-processes.json'));
    ClaudeEnvironment.use(Platform.environment);
    LspProcesses.registry = ChildProcessRegistry(file: file);
  });
  tearDown(() async {
    await stopLspProcesses();
    dir.deleteSync(recursive: true);
  });

  List<Object?> listed() => jsonDecode(file.readAsStringSync()) as List;

  test(
    'started servers are listed with their command; stopAll ends them',
    () async {
      final process = await startLspProcess(
        LspLaunch(
          serverId: 'fake',
          executable: dartExecutable,
          arguments: [fakeServerScript, '--as-a-test'],
          workingDirectory: dir.path,
        ),
      );
      await until(() => file.existsSync() && listed().isNotEmpty);
      final entry = listed().single as Map;
      expect(entry['pid'], process.pid);
      expect(entry['parent'], pid);
      expect(entry['command'], contains('fake_lsp_server.dart --as-a-test'));

      await stopLspProcesses();
      expect(process.stopRequested, isTrue);
      expect(await process.exitCode, isNot(0));
      expect(processRunning(process.pid), isFalse);
      await until(() => listed().isEmpty);
    },
  );

  test('a missing executable fails to start, saying so', () async {
    await expectLater(
      startLspProcess(
        LspLaunch(
          serverId: 'nope',
          executable: p.join(dir.path, 'no-such-server'),
          workingDirectory: dir.path,
        ),
      ),
      throwsA(
        isA<LspStartException>().having(
          (e) => e.message,
          'message',
          'nope could not start',
        ),
      ),
    );
  });

  test(
    'reaps a leftover still running its command, not a reused pid',
    () async {
      final leftover = await Process.start(dartExecutable, [fakeServerScript]);
      final reused = await Process.start(dartExecutable, [
        fakeServerScript,
        '--other',
      ]);
      addTearDown(() => reused.kill(ProcessSignal.sigkill));
      final command = (await ChildProcessRegistry.psLookup(leftover.pid))!
          .command;
      file.writeAsStringSync(
        jsonEncode([
          // A hot restart's leftover: a child of this very process.
          {'pid': leftover.pid, 'parent': pid, 'command': command},
          // The pid now runs something else than what was recorded.
          {'pid': reused.pid, 'parent': pid, 'command': '/usr/bin/vim x'},
          // Recorded without a command: never ended.
          {'pid': reused.pid, 'parent': pid},
        ]),
      );
      LspProcesses.registry = ChildProcessRegistry(file: file);
      await reapLspProcesses();
      await leftover.exitCode.timeout(const Duration(seconds: 5));
      expect(processRunning(reused.pid), isTrue);
      expect(listed(), isEmpty);
    },
  );
}
