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

  test('lists sessions started with agent-message, angle-bracket text, '
      'custom titles, or argument-less commands with replies', () async {
    final cwd = Directory(p.join(temp.path, 'workspace'))..createSync();
    final cachePath = p.join(temp.path, 'cache.json');

    Map<String, Object?> userAt(
      String uuid,
      Object content, {
      String? parent,
    }) => {
      'type': 'user',
      'uuid': uuid,
      'parentUuid': parent,
      'cwd': cwd.path,
      'timestamp': '2026-11-27T08:00:00.000Z',
      'message': {'role': 'user', 'content': content},
    };
    Map<String, Object?> assistantAt(
      String uuid,
      String text, {
      String? parent,
      String model = 'claude-sonnet-4-6',
    }) => {
      'type': 'assistant',
      'uuid': uuid,
      'parentUuid': parent,
      'cwd': cwd.path,
      'timestamp': '2026-11-27T08:01:00.000Z',
      'message': {
        'role': 'assistant',
        'model': model,
        'content': [
          {'type': 'text', 'text': text},
        ],
      },
    };

    // 1. Handed from another conversation with <agent-message> + reminder.
    final handedFile = writeSession('handed', [
      userAt('u1', [
        {
          'type': 'text',
          'text':
              '<system-reminder>This message comes from another conversation.'
              '</system-reminder>',
        },
        {
          'type': 'text',
          'text':
              '<agent-message from="Coordinator" session="s0">\n'
              'Audit the cache layer\nDetails follow\n'
              '</agent-message>',
        },
      ]),
      assistantAt('a1', 'Starting audit.', parent: 'u1'),
      userAt(
        'u2',
        '<agent-message from="Coordinator">Follow up</agent-message>',
        parent: 'a1',
      ),
      assistantAt('a2', 'Done.', parent: 'u2'),
    ]);

    // 2. Plain user text starting with angle brackets (not a CLI wrapper).
    writeSession('xml-text', [userAt('u1', '<task>Check the build</task>')]);

    // 3. Command caveat / argument-less command with a manual custom-title.
    writeSession('named-caveat', [
      userAt('u1', '<local-command-caveat>Caveat</local-command-caveat>'),
      userAt(
        'u2',
        '<command-message>review</command-message>\n'
            '<command-name>/review</command-name>\n'
            '<command-args></command-args>',
      ),
      {'type': 'custom-title', 'customTitle': 'My renamed session'},
    ]);

    // 4. Argument-less slash command with a real assistant reply, no title.
    final cmdFile = writeSession('cmd-replied', [
      userAt(
        'u1',
        '<command-message>review</command-message>\n'
            '<command-name>/review</command-name>\n'
            '<command-args></command-args>',
      ),
    ]);

    // 5. Isolated local command with only a synthetic reply: still omitted.
    writeSession('local-only', [
      userAt(
        'u1',
        '<command-name>/context</command-name>\n<command-args></command-args>',
      ),
      assistantAt('a1', 'Context usage', model: '<synthetic>'),
    ]);

    // Pre-populate a stale v5 cache where handed had prompt: null to verify
    // the version bump forces a rescan.
    final stat = handedFile.statSync();
    File(cachePath).writeAsStringSync(
      jsonEncode({
        'version': 5,
        'root': p.join(temp.path, 'projects'),
        'files': {
          handedFile.path: {
            'size': stat.size,
            'modified': stat.modified.microsecondsSinceEpoch,
            'scanned': stat.size,
            'mark': '',
            'cwd': cwd.path,
            'prompt': null,
            'named': null,
            'generated': null,
            'said': null,
          },
        },
      }),
    );

    final sessions = ClaudeSessions(cacheFile: cachePath, configDir: temp.path);

    Future<Map<String, String>> titles() async {
      final projects = await sessions.projects();
      return {for (final s in projects.single.sessions) s.id: s.title};
    }

    // Before cmd-replied receives an assistant reply, it is not listed yet.
    expect(await titles(), {
      'handed': 'Audit the cache layer',
      'xml-text': '<task>Check the build</task>',
      'named-caveat': 'My renamed session',
    });

    // Once an assistant reply is appended, incremental readOn surfaces it.
    cmdFile.writeAsStringSync(
      '\n${jsonEncode(assistantAt('a1', 'Looks good.'))}',
      mode: FileMode.append,
    );
    expect(await titles(), {
      'handed': 'Audit the cache layer',
      'xml-text': '<task>Check the build</task>',
      'named-caveat': 'My renamed session',
      'cmd-replied': '/review',
    });

    // <agent-message> turns count as turn boundaries when paging.
    final lastTurn = await ClaudeSessions.readPage(handedFile.path, turns: 1);
    expect([for (final e in lastTurn.entries) e['uuid']], ['u2', 'a2']);
    expect(lastTurn.earlier, 'u2');
  });
}
