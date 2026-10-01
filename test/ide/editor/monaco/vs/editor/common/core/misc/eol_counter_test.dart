import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/editor/monaco/vs/editor/common/core/misc/eol_counter.dart';

void main() {
  test('StringEOL preserves upstream bit flags', () {
    expect(StringEOL.unknown.value, 0);
    expect(StringEOL.lf.value, 1);
    expect(StringEOL.crlf.value, 2);
    expect(StringEOL.invalid.value, 3);
  });

  test('counts empty and unterminated lines', () {
    expect(countEOL(''), (0, 0, 0, StringEOL.unknown));
    expect(countEOL('abc'), (0, 3, 3, StringEOL.unknown));
    expect(countEOL('😀x'), (0, 3, 3, StringEOL.unknown));
  });

  test('recognizes LF and CRLF, counting the pair only once', () {
    expect(countEOL('ab\ncd\n'), (2, 2, 0, StringEOL.lf));
    expect(countEOL('ab\r\ncd\r\n'), (2, 2, 0, StringEOL.crlf));
    expect(countEOL('\r\n'), (1, 0, 0, StringEOL.crlf));
    expect(countEOL('a\n\nlast'), (2, 1, 4, StringEOL.lf));
  });

  test('bare CR and mixed line endings are invalid', () {
    expect(countEOL('a\rb'), (1, 1, 1, StringEOL.invalid));
    expect(countEOL('a\rb\rc'), (2, 1, 1, StringEOL.invalid));
    expect(countEOL('a\r\nb\nc'), (2, 1, 1, StringEOL.invalid));
    expect(countEOL('a\nb\r\nc'), (2, 1, 1, StringEOL.invalid));
    expect(countEOL('\r\r\n'), (2, 0, 0, StringEOL.invalid));
    expect(countEOL('a\r'), (1, 1, 0, StringEOL.invalid));
  });

  test('line lengths are UTF-16 units rather than Unicode scalar values', () {
    expect(countEOL('😀\r\n🐱'), (1, 2, 2, StringEOL.crlf));
    expect(countEOL('😀\n🐱\n😀'), (2, 2, 2, StringEOL.lf));
  });
}
