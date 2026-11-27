import 'dart:convert';
import 'dart:io';

import 'package:bao_agent/src/engine/session_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('SessionStore.resume recovers chain across missing parent pointers', () {
    final temp = Directory.systemTemp.createTempSync('session-store-test-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final file = File(p.join(temp.path, 's.jsonl'))
      ..writeAsStringSync(
        [
          {
            'type': 'user',
            'uuid': 'u1',
            'parentUuid': null,
            'message': {'role': 'user', 'content': 'Turn 1'},
          },
          {
            'type': 'assistant',
            'uuid': 'a1',
            'parentUuid': 'u1',
            'message': {'role': 'assistant', 'content': 'Answer 1'},
          },
          {
            'type': 'assistant',
            'uuid': 'side1',
            'parentUuid': 'a1',
            'isSidechain': true,
            'message': {'role': 'assistant', 'content': 'Subagent'},
          },
          {
            'type': 'system',
            'subtype': 'compact_boundary',
            'uuid': 'cb1',
            'parentUuid': null,
            'logicalParentUuid': 'missing-uuid',
          },
          {
            'type': 'user',
            'uuid': 's1',
            'parentUuid': 'cb1',
            'isCompactSummary': true,
            'message': {'role': 'user', 'content': 'Summary'},
          },
          {
            'type': 'assistant',
            'uuid': 'a2',
            'parentUuid': 's1',
            'message': {'role': 'assistant', 'content': 'Answer 2'},
          },
        ].map(jsonEncode).join('\n'),
      );

    final store = SessionStore.resume(
      sessionId: 's',
      cwd: '/p',
      file: file.path,
      persist: false,
    );
    expect(
      [for (final e in store.chain) e['uuid']],
      ['u1', 'a1', 'cb1', 's1', 'a2'],
    );
  });
}
