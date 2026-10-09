// Content-Length framing, as stream adapters speak it.

import 'dart:convert';

import 'package:baocode/debug/common/debug_types.dart';
import 'package:baocode/debug/session/dap_framing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('encodes with the UTF-8 byte length', () {
    final bytes = encodeDapMessage({'type': 'event', 'event': 'output', 'body': {'output': 'héllo ✓'}});
    final text = utf8.decode(bytes);
    final body = text.substring(text.indexOf('\r\n\r\n') + 4);
    expect(text, startsWith('Content-Length: ${utf8.encode(body).length}\r\n\r\n'));
    expect(jsonDecode(body)['body']['output'], 'héllo ✓');
  });

  test('reads messages split anywhere and several in one chunk', () {
    final messages = <Json>[];
    final errors = <Object>[];
    final reader = DapMessageReader(onMessage: messages.add, onError: errors.add);
    final a = encodeDapMessage({'seq': 1, 'type': 'response', 'body': {'text': '多字节'}});
    final b = encodeDapMessage({'seq': 2, 'type': 'event'});
    final all = [...a, ...b, ...a];
    // Byte by byte through the first, then the rest at once.
    for (var i = 0; i < a.length; i++) {
      reader.add([all[i]]);
    }
    expect(messages.single['seq'], 1);
    reader.add(all.sublist(a.length));
    expect(messages.map((m) => m['seq']), [1, 2, 1]);
    expect(messages.last.obj('body')!['text'], '多字节');
    expect(errors, isEmpty);
  });

  test('extra headers are ignored', () {
    final messages = <Json>[];
    final reader = DapMessageReader(onMessage: messages.add, onError: (_) {});
    const body = '{"seq":3,"type":"event"}';
    reader.add(ascii.encode('Content-Type: application/json\r\nContent-Length: ${body.length}\r\n\r\n$body'));
    expect(messages.single['seq'], 3);
  });
}
