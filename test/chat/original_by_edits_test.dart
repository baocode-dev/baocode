import 'package:baocode/chat/chat_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('edits are taken back out, the last first', () {
    const original = OriginalByEdits([
      (before: 'a', after: 'z'),
      (before: 'bc', after: 'xy'),
    ]);
    // 'abc' -> 'zbc' -> 'zxy'
    expect(original.undo('zxy'), 'abc');
  });

  test('where a text put in is not there once, what it was is not known', () {
    const twice = OriginalByEdits([(before: 'old', after: 'new')]);
    expect(twice.undo('new and new'), isNull);
    expect(twice.undo('changed since'), isNull);
    const removed = OriginalByEdits([(before: 'gone', after: '')]);
    expect(removed.undo('anything'), isNull);
  });
}
