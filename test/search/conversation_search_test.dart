import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:baocode/search/claude_conversation_search.dart';
import 'package:baocode/search/conversation_search.dart';

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('conversations'));
  tearDown(() => temp.deleteSync(recursive: true));

  String line(Map<String, Object?> entry) => jsonEncode(entry);

  void session(String id, List<Map<String, Object?>> entries) {
    File(p.join(temp.path, 'projects', '-tmp-app', '$id.jsonl'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(entries.map(line).join('\n'));
  }

  Map<String, Object?> user(Object content, {bool meta = false}) => {
    'type': 'user',
    if (meta) 'isMeta': true,
    'message': {'role': 'user', 'content': content},
  };

  Map<String, Object?> assistant(List<Object?> blocks) => {
    'type': 'assistant',
    'message': {'role': 'assistant', 'content': blocks},
  };

  test('finds what was said, not tools\' output or notes', () async {
    session('s1', [
      user('How do I rotate the signing keys?'),
      assistant([
        {'type': 'thinking', 'thinking': 'secret plan'},
        {'type': 'text', 'text': 'Run the rotation script, then redeploy.'},
        {
          'type': 'tool_use',
          'name': 'Bash',
          'input': {'command': 'grep'},
        },
      ]),
      user([
        {'type': 'tool_result', 'content': 'grep output only in a tool'},
      ]),
      user('<command-name>/clear</command-name>'),
      user('caveat only in a note', meta: true),
    ]);
    session('s2', [user('Unrelated question about CSS grids')]);

    final search = ClaudeConversationSearch(configDir: temp.path);
    final hits = await search.search('ROTATION');
    expect(hits, hasLength(1));
    final hit = hits.single;
    expect(hit.sessionId, 's1');
    expect(
      hit.snippet.substring(hit.matchStart, hit.matchStart + hit.matchLength),
      'rotation',
    );
    expect(await search.search('secret plan'), isEmpty);
    expect(await search.search('grep output'), isEmpty);
    expect(await search.search('caveat'), isEmpty);
    expect(await search.search('/clear'), isEmpty);
    expect((await search.search('css')).single.sessionId, 's2');

    // A file written since is read again; one removed, forgotten.
    session('s2', [user('Now about flexbox')]);
    File(p.join(temp.path, 'projects', '-tmp-app', 's2.jsonl'))
        .setLastModifiedSync(DateTime.now().add(const Duration(minutes: 1)));
    expect(await search.search('css'), isEmpty);
    expect((await search.search('flexbox')).single.sessionId, 's2');
    File(p.join(temp.path, 'projects', '-tmp-app', 's1.jsonl')).deleteSync();
    expect(await search.search('rotation'), isEmpty);
  });

  test('a snippet is one line around the match, cut where it was', () {
    final text = '${'a' * 50}\nThe Needle\nis here${'b' * 200}';
    final hit = findIn('id', text, 'needle')!;
    expect(hit.snippet, startsWith('…'));
    expect(hit.snippet, endsWith('…'));
    expect(hit.snippet, isNot(contains('\n')));
    expect(
      hit.snippet.substring(hit.matchStart, hit.matchStart + hit.matchLength),
      'Needle',
    );
    expect(findIn('id', 'short', 'missing'), isNull);
  });
}
