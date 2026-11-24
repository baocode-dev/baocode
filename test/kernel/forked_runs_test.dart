import 'dart:convert';
import 'dart:io';

import 'package:baocode/kernel/claude_code/forked_runs_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('a slash command\'s run is read from its subagent\'s transcript as it '
      'is written, the subagents it starts itself left out (#1131)', () async {
    final folder = await Directory.systemTemp.createTemp('baocode-forked');
    addTearDown(() => folder.delete(recursive: true));
    final runs = ForkedRunFiles(
      interval: const Duration(milliseconds: 20),
      folderOf: (cwd, session, env) async => folder.path,
    );
    String line(String uuid, String text) => jsonEncode({
      'type': 'assistant',
      'uuid': uuid,
      'message': {
        'role': 'assistant',
        'content': [
          {'type': 'text', 'text': text},
        ],
      },
    });
    final lines = <String>[];
    final run = runs.watch(
      cwd: '/p',
      sessionId: 's',
      onLine: (message) => lines.add(message['uuid']! as String),
    );
    addTearDown(run.cancel);

    // A subagent the run starts itself (an Agent call of its): not its own.
    File(p.join(folder.path, 'agent-b.meta.json')).writeAsStringSync(
      jsonEncode({'agentType': 'reviewer', 'toolUseId': 'toolu_1'}),
    );
    File(p.join(folder.path, 'agent-b.jsonl'))
        .writeAsStringSync('${line('b1', 'not this')}\n');
    // The run's own, written a line at a time, the last half way.
    File(p.join(folder.path, 'agent-a.meta.json')).writeAsStringSync(
      jsonEncode({
        'agentType': 'general-purpose',
        'requestShape': 'foreground',
      }),
    );
    final transcript = File(p.join(folder.path, 'agent-a.jsonl'))
      ..writeAsStringSync('${line('a1', 'Counting')}\n');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(lines, ['a1']);

    final second = line('a2', '7');
    transcript.writeAsStringSync(
      second.substring(0, 10),
      mode: FileMode.append,
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(lines, ['a1']);
    transcript.writeAsStringSync(
      '${second.substring(10)}\n',
      mode: FileMode.append,
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(lines, ['a1', 'a2']);

    // Done: what is left is read, then no more.
    transcript.writeAsStringSync(
      '${line('a3', 'done')}\n',
      mode: FileMode.append,
    );
    run.finish();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    transcript.writeAsStringSync(
      '${line('a4', 'after')}\n',
      mode: FileMode.append,
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(lines, ['a1', 'a2', 'a3']);
  });
}
