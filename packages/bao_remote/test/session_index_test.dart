import 'dart:convert';
import 'dart:io';

import 'package:bao_remote/local.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory temp;
  late String indexDir;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('session_index_test');
    indexDir = p.join(temp.path, 'idx');
  });

  tearDown(() => temp.deleteSync(recursive: true));

  Map<String, Object?> userLine(String uuid, String? parent, String text) => {
    'type': 'user',
    'uuid': uuid,
    'parentUuid': parent,
    'timestamp': '2026-11-28T10:00:00.000Z',
    'message': {'role': 'user', 'content': text},
  };

  Map<String, Object?> assistantLine(
    String uuid,
    String parent,
    String text, {
    String? messageId,
  }) => {
    'type': 'assistant',
    'uuid': uuid,
    'parentUuid': parent,
    'timestamp': '2026-11-28T10:00:05.000Z',
    'message': {
      'id': messageId ?? 'm_$uuid',
      'role': 'assistant',
      'content': [
        {'type': 'text', 'text': text},
      ],
    },
  };

  Map<String, Object?> toolUseLine(
    String uuid,
    String parent,
    String toolId, {
    String? messageId,
  }) => {
    'type': 'assistant',
    'uuid': uuid,
    'parentUuid': parent,
    'timestamp': '2026-11-28T10:00:02.000Z',
    'message': {
      'id': messageId ?? 'm_$uuid',
      'role': 'assistant',
      'content': [
        {
          'type': 'tool_use',
          'id': toolId,
          'name': 'Bash',
          'input': {'command': 'echo hi'},
        },
      ],
    },
  };

  Map<String, Object?> toolResultLine(
    String uuid,
    String parent,
    String toolId,
    String output,
  ) => {
    'type': 'user',
    'uuid': uuid,
    'parentUuid': parent,
    'timestamp': '2026-11-28T10:00:03.000Z',
    'message': {
      'role': 'user',
      'content': [
        {'type': 'tool_result', 'tool_use_id': toolId, 'content': output},
      ],
    },
  };

  File writeSession(String name, List<Map<String, Object?>> entries) {
    final file = File(p.join(temp.path, '$name.jsonl'))
      ..writeAsStringSync('${entries.map(jsonEncode).join('\n')}\n');
    return file;
  }

  group('SessionIndex persistence and incremental updates', () {
    test('persists gzipped index, incrementally appends, and detects rewrite', () {
      final file = writeSession('inc', [
        userLine('u1', null, 'First question about nebula'),
        assistantLine('a1', 'u1', 'First answer about nebula'),
      ]);
      final store = SessionIndexStore(cacheDir: indexDir);

      final first = store.openSync(file.path);
      expect(first.starts, hasLength(2));
      expect(first.searchableText(), contains('nebula'));

      // Reload from disk without touching .jsonl (unchanged stat).
      final reloaded = store.loadDisk(file.path);
      expect(reloaded, isNotNull);
      final (unchanged, didScan) = SessionIndex.readOn(file, reloaded);
      expect(didScan, isFalse);
      expect(unchanged.starts, hasLength(2));

      // Append a new turn -> incremental tail scan from previous `scanned`.
      final prevScanned = unchanged.scanned;
      file.writeAsStringSync(
        '${jsonEncode(userLine('u2', 'a1', 'Second question about quasar'))}\n'
        '${jsonEncode(assistantLine('a2', 'u2', 'Second answer about quasar'))}\n',
        mode: FileMode.append,
      );
      final updated = store.openSync(file.path);
      expect(updated.scanned, greaterThan(prevScanned));
      expect(updated.starts, hasLength(4));
      expect(updated.searchableText(), contains('nebula'));
      expect(updated.searchableText(), contains('quasar'));

      // Rewrite file in-place with different content -> mark mismatch forces rebuild.
      file.writeAsStringSync(
        '${jsonEncode(userLine('u9', null, 'Rewritten pulsar'))}\n',
      );
      final rebuilt = store.openSync(file.path);
      expect(rebuilt.starts, hasLength(1));
      expect(rebuilt.searchableText(), contains('pulsar'));
      expect(rebuilt.searchableText(), isNot(contains('nebula')));
    });

    test('excludes dead rewound branches from branch() and searchableText()', () {
      final file = writeSession('branch', [
        userLine('u1', null, 'Root prompt'),
        assistantLine('a1', 'u1', 'Root answer'),
        // Dead branch:
        userLine('u2_dead', 'a1', 'Dead branch secret'),
        assistantLine('a2_dead', 'u2_dead', 'Dead branch reply'),
        // Live branch forked from a1:
        userLine('u2_live', 'a1', 'Live branch prompt'),
        assistantLine('a2_live', 'u2_live', 'Live branch reply'),
      ]);
      final store = SessionIndexStore(cacheDir: indexDir);
      final idx = store.openSync(file.path);
      final branchIds = [for (final r in idx.branch()) idx.ids[r]];
      expect(branchIds, ['u1', 'a1', 'u2_live', 'a2_live']);
      final text = idx.searchableText();
      expect(text, contains('Live branch prompt'));
      expect(text, isNot(contains('Dead branch secret')));
    });
  });

  group('ClaudeSessions.readPage whole-turn alignment & until', () {
    test('keeps a turn whole when over bytes but under maxSingleTurnBytes, '
        'and cuts cleanly at previous turn boundary when seen > 0', () async {
      final pad = 'x' * 600;
      final file = writeSession('whole_turn', [
        userLine('u1', null, 'Turn 1'),
        toolUseLine('tu1', 'u1', 't1'),
        toolResultLine('tr1', 'tu1', 't1', pad),
        assistantLine('a1', 'tr1', 'Answer 1'),
        userLine('u2', 'a1', 'Turn 2'),
        toolUseLine('tu2', 'u2', 't2'),
        toolResultLine('tr2', 'tu2', 't2', pad),
        assistantLine('a2', 'tr2', 'Answer 2'),
        userLine('u3', 'a2', 'Turn 3'),
        toolUseLine('tu3', 'u3', 't3'),
        toolResultLine('tr3', 'tu3', 't3', pad),
        assistantLine('a3', 'tr3', 'Answer 3'),
      ]);

      // bytes = 500 is smaller than a single turn (~1 KB), but maxSingleTurnBytes
      // is 10 KB -> Turn 3 must still arrive 100% WHOLE (starting at u3)!
      final page1 = await ClaudeSessions.readPage(
        file.path,
        turns: 10,
        bytes: 500,
        maxSingleTurnBytes: 10000,
        indexDir: indexDir,
      );
      expect([for (final e in page1.entries) e['uuid']], [
        'u3',
        'tu3',
        'tr3',
        'a3',
      ]);
      expect(page1.earlier, 'u3');

      // Loading earlier gets Turn 2 whole (starting at u2), never splitting Turn 1.
      final page2 = await ClaudeSessions.readPage(
        file.path,
        turns: 10,
        before: page1.earlier,
        bytes: 500,
        maxSingleTurnBytes: 10000,
        indexDir: indexDir,
      );
      expect([for (final e in page2.entries) e['uuid']], [
        'u2',
        'tu2',
        'tr2',
        'a2',
      ]);
      expect(page2.earlier, 'u2');

      // bytes large enough for 1.5 turns stops cleanly at Turn 2 boundary, never
      // cutting Turn 1 in half.
      final pageMulti = await ClaudeSessions.readPage(
        file.path,
        turns: 10,
        bytes: 1600,
        maxSingleTurnBytes: 10000,
        indexDir: indexDir,
      );
      final firstId = pageMulti.entries.first['uuid'];
      expect(firstId, anyOf('u2', 'u3'));
    });

    test('safety-cuts an astronomical single turn exceeding maxSingleTurnBytes', () async {
      final huge = 'z' * 800;
      final file = writeSession('astro', [
        userLine('u1', null, 'Huge turn'),
        assistantLine('a1', 'u1', huge, messageId: 'm1'),
        assistantLine('a2', 'a1', huge, messageId: 'm2'),
        assistantLine('a3', 'a2', huge, messageId: 'm3'),
      ]);

      final page = await ClaudeSessions.readPage(
        file.path,
        turns: 10,
        bytes: 500,
        maxSingleTurnBytes: 1200,
        indexDir: indexDir,
      );
      expect(page.earlier, isNotNull);
      expect(page.entries.first['uuid'], isNot('u1'));
    });

    test('until loads directly back to target prompt and searchEarlier finds unloaded turns', () async {
      final entries = <Map<String, Object?>>[];
      String? parent;
      for (var n = 1; n <= 15; n++) {
        final u = 'u$n';
        final a = 'a$n';
        final marker = n == 3 || n == 7 ? ' SPECIAL_TOKEN' : '';
        entries.add(userLine(u, parent, 'Prompt $n$marker'));
        entries.add(assistantLine(a, u, 'Reply $n$marker'));
        parent = a;
      }
      final file = writeSession('search_until', entries);

      // Load only the last 3 turns (13..15).
      final first = await ClaudeSessions.readPage(
        file.path,
        turns: 3,
        indexDir: indexDir,
      );
      expect(first.earlier, 'u13');

      // Search unloaded earlier turns via persisted index.
      final hits = await ClaudeSessions.searchEarlier(
        file.path,
        'special_token',
        caseSensitive: false,
        before: first.earlier,
        indexDir: indexDir,
      );
      expect(hits.map((h) => (h.promptUuid, h.occurrences)).toList(), [
        ('u3', 2),
        ('u7', 2),
      ]);

      // Jump directly to u3 in a single readPage(..., until: 'u3').
      final jumped = await ClaudeSessions.readPage(
        file.path,
        turns: 3,
        before: first.earlier,
        until: 'u3',
        indexDir: indexDir,
      );
      expect(jumped.entries.first['uuid'], 'u3');
      expect(jumped.entries.last['uuid'], 'a12');
      expect(jumped.earlier, 'u3');
    });
  });

  group('Performance on large sessions', () {
    test('cached index readPage and searchEarlier stay fast on a multi-MB session', () async {
      final entries = <Map<String, Object?>>[];
      String? parent;
      // 120 turns with ~40 KB tool output each (~5 MB total).
      final bigToolOutput = 'line of tool output 0123456789\n' * 1200;
      for (var n = 1; n <= 120; n++) {
        final u = 'u$n';
        final tu = 'tu$n';
        final tr = 'tr$n';
        final a = 'a$n';
        entries.add(
          userLine(u, parent, n == 5 ? 'Find the golden needle' : 'Task $n'),
        );
        entries.add(toolUseLine(tu, u, 'call_$n'));
        entries.add(toolResultLine(tr, tu, 'call_$n', bigToolOutput));
        entries.add(assistantLine(a, tr, 'Completed task $n.'));
        parent = a;
      }
      final file = writeSession('perf_5mb', entries);
      expect(file.lengthSync(), greaterThan(4 * 1024 * 1024));

      // Warm up persisted index once.
      final page = await ClaudeSessions.readPage(
        file.path,
        turns: 10,
        indexDir: indexDir,
      );
      expect(page.earlier, isNotNull);

      // Measure cached searchEarlier & incremental append.
      final sw = Stopwatch()..start();
      final hits = await ClaudeSessions.searchEarlier(
        file.path,
        'golden needle',
        caseSensitive: false,
        before: page.earlier,
        indexDir: indexDir,
      );
      sw.stop();
      expect(hits.single.promptUuid, 'u5');
      expect(hits.single.occurrences, 1);
      // Even in debug/test VM, searching the cached index must be fast.
      expect(sw.elapsedMilliseconds, lessThan(500));

      // Disk index should be tiny compared to the 5 MB .jsonl (tool outputs stripped).
      final store = SessionIndexStore(cacheDir: indexDir);
      final idxFile = File(store.indexFilePath(file.path)!);
      expect(idxFile.existsSync(), isTrue);
      expect(idxFile.lengthSync(), lessThan(100 * 1024));
    });
  });
}
