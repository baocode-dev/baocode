import 'dart:convert';
import 'dart:io';

import 'package:bao_remote/local.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('claude-sessions-test-');
  });

  tearDown(() => temp.deleteSync(recursive: true));

  File writeSession(String name, List<Map<String, Object?>> lines) {
    final file = File(p.join(temp.path, 'projects', '-p', '$name.jsonl'))
      ..createSync(recursive: true)
      ..writeAsStringSync(lines.map(jsonEncode).join('\n'));
    return file;
  }

  Map<String, Object?> user(
    String uuid,
    String? parent,
    String text, {
    bool sidechain = false,
  }) => {
    'type': 'user',
    'uuid': uuid,
    'parentUuid': parent,
    if (sidechain) 'isSidechain': true,
    'cwd': '/p',
    'message': {'role': 'user', 'content': text},
  };

  Map<String, Object?> assistant(
    String uuid,
    String? parent,
    String text, {
    bool sidechain = false,
  }) => {
    'type': 'assistant',
    'uuid': uuid,
    'parentUuid': parent,
    if (sidechain) 'isSidechain': true,
    'message': {'role': 'assistant', 'content': text},
  };

  Map<String, Object?> compactBoundary(String uuid, String? logicalParent) => {
    'type': 'system',
    'subtype': 'compact_boundary',
    'uuid': uuid,
    'parentUuid': null,
    'logicalParentUuid': logicalParent,
    'content': 'Conversation compacted',
  };

  test('falls back to the nearest earlier kept main-chain line when '
      'logicalParentUuid or parentUuid is missing from the file', () async {
    final file = writeSession('broken-compaction', [
      user('u1', null, 'Turn 1'),
      assistant('a1', 'u1', 'Answer 1'),
      // Rewound branch that must stay excluded when walking back from a2.
      user('old-u', 'a1', 'Abandoned'),
      assistant('old-a', 'old-u', 'Abandoned answer'),
      user('u2', 'a1', 'Turn 2'),
      assistant('a2', 'u2', 'Answer 2'),
      // Non-kept and sidechain records right before the broken boundary.
      {'type': 'attachment', 'uuid': 'att1', 'parentUuid': 'a2'},
      {'type': 'progress', 'uuid': 'prog1'},
      assistant('side1', 'a2', 'Subagent reply', sidechain: true),
      compactBoundary('cb1', 'missing-parent-1'),
      user('s1', 'cb1', 'Summary 1'),
      assistant('a3', 's1', 'Answer 3'),
      {'type': 'custom-title', 'customTitle': 'Long session'},
      compactBoundary('cb2', 'missing-parent-2'),
      user('s2', 'cb2', 'Summary 2'),
      assistant('a4', 's2', 'Answer 4'),
      // Dangling regular parentUuid as well.
      user('u5', 'missing-parent-3', 'Turn 5'),
      assistant('a5', 'u5', 'Answer 5'),
    ]);

    const expected = [
      'u1',
      'a1',
      'u2',
      'a2',
      'cb1',
      's1',
      'a3',
      'cb2',
      's2',
      'a4',
      'u5',
      'a5',
    ];

    final full = await ClaudeSessions.read(file.path);
    expect([for (final e in full) e['uuid']], expected);

    final page = await ClaudeSessions.readPage(file.path, turns: 100);
    expect([for (final e in page.entries) e['uuid']], expected);
    expect(page.earlier, isNull);

    // Paging backwards across the broken boundaries still reaches the start.
    final lastPage = await ClaudeSessions.readPage(file.path, turns: 2);
    expect(lastPage.earlier, isNotNull);
    final collected = <Object?>[for (final e in lastPage.entries) e['uuid']];
    var cursor = lastPage.earlier;
    while (cursor != null) {
      final earlier = await ClaudeSessions.readPage(
        file.path,
        turns: 2,
        before: cursor,
      );
      collected.insertAll(0, [for (final e in earlier.entries) e['uuid']]);
      cursor = earlier.earlier;
    }
    expect(collected, expected);

    // Forking also preserves the full recovered branch.
    final sessions = ClaudeSessions(
      cacheFile: p.join(temp.path, 'cache.json'),
      configDir: temp.path,
    );
    final forkedPath = await sessions.fork(
      'broken-compaction',
      'forked-session',
    );
    final forked = await ClaudeSessions.read(forkedPath);
    expect([for (final e in forked) e['uuid']], expected);

    final cutPath = await sessions.fork(
      'broken-compaction',
      'forked-before-boundary',
      before: 'cb2',
    );
    final cut = await ClaudeSessions.read(cutPath);
    expect(
      [for (final e in cut) e['uuid']],
      ['u1', 'a1', 'u2', 'a2', 'cb1', 's1', 'a3'],
    );
  });

  test('stops at an explicit null parentUuid instead of crossing into an '
      'earlier branch', () async {
    final file = writeSession('second-root', [
      user('u1', null, 'Old root'),
      assistant('a1', 'u1', 'Old answer'),
      user('u2', null, 'New root'),
      assistant('a2', 'u2', 'New answer'),
    ]);

    final full = await ClaudeSessions.read(file.path);
    expect([for (final e in full) e['uuid']], ['u2', 'a2']);

    final page = await ClaudeSessions.readPage(file.path, turns: 10);
    expect([for (final e in page.entries) e['uuid']], ['u2', 'a2']);
  });
}
