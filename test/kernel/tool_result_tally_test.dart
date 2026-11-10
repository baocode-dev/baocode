import 'package:baocode/kernel/claude_code/tool_result_tally.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> call(String id, String name, {String? uuid}) => {
  'type': 'assistant',
  'uuid': ?uuid,
  'message': {
    'content': [
      {'type': 'tool_use', 'id': id, 'name': name, 'input': const {}},
    ],
  },
};

Map<String, Object?> result(String id, Object? content, {String? uuid}) => {
  'type': 'user',
  'uuid': ?uuid,
  'message': {
    'content': [
      {'type': 'tool_result', 'tool_use_id': id, 'content': content},
    ],
  },
};

List<Object?> screenshot(int bytes) => [
  {
    'type': 'image',
    'source': {
      'type': 'base64',
      'media_type': 'image/png',
      'data': 'A' * bytes,
    },
  },
];

void main() {
  test('an image is one, whatever its base64 comes to', () {
    final tally = ToolResultTally()
      ..add(call('t1', 'Screenshot'))
      ..add(result('t1', screenshot(4)))
      ..add(call('t2', 'Screenshot'))
      ..add(result('t2', screenshot(400000)))
      ..add(call('t3', 'Read'))
      ..add(result('t3', 'x' * 400));
    final tools = tally.byTool;
    expect(tools['Screenshot'], inInclusiveRange(2000, 4000));
    expect(tools['Read'], 100);
  });

  test("a subagent's results are not the conversation's", () {
    final tally = ToolResultTally()
      ..add({...call('t1', 'Read'), 'parent_tool_use_id': 'task'})
      ..add({...result('t1', 'x' * 400), 'parent_tool_use_id': 'task'})
      ..add({...result('t2', 'x' * 400), 'isSidechain': true});
    expect(tally.byTool, isEmpty);
  });

  test('a compaction leaves none before it', () {
    final tally = ToolResultTally()
      ..add(call('t1', 'Read'))
      ..add(result('t1', 'x' * 400))
      ..add({'type': 'system', 'subtype': 'compact_boundary'})
      ..add(call('t2', 'Bash'))
      ..add(result('t2', 'x' * 40));
    expect(tally.byTool, {'Bash': 10});
  });

  test('a rewind to a message drops the results from it on', () {
    final tally = ToolResultTally()
      ..mark('u1')
      ..add(call('t1', 'Read'))
      ..add(result('t1', 'x' * 400))
      ..mark('u2')
      ..add(call('t2', 'Bash'))
      ..add(result('t2', 'x' * 40));
    expect(tally.rewind('u2'), isTrue);
    expect(tally.byTool, {'Read': 100});
    expect(tally.rewind('unseen'), isFalse);
    expect(tally.rewind('u1'), isTrue);
    expect(tally.byTool, isEmpty);
  });

  test('takes in the results that came while the session was read', () {
    final live = ToolResultTally()
      ..add(call('t2', 'Bash'))
      ..add(result('t2', 'x' * 40));
    final read = ToolResultTally()
      ..add(call('t1', 'Read'))
      ..add(result('t1', 'x' * 400))
      ..add(call('t2', 'Bash'))
      ..add(result('t2', 'x' * 40))
      ..takeNewer(live);
    expect(read.byTool, {'Read': 100, 'Bash': 10});
  });
}
