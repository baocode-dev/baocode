// Copyright (c) 2026 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Adapted from xterm.js src/common/StringBuilder.test.ts (c58ea36).

import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/terminal/xterm/common/string_builder.dart';

void main() {
  group('StringBuilder', () {
    test('should start empty', () {
      final builder = StringBuilder();
      expect(builder.length, 0);
      expect(builder.toString(), '');
    });

    test('should append a single chunk', () {
      final builder = StringBuilder();
      builder.append('hello');
      expect(builder.length, 5);
      expect(builder.toString(), 'hello');
    });

    test('should join multiple chunks in order', () {
      final builder = StringBuilder();
      builder.append('foo');
      builder.append('bar');
      builder.append('baz');
      expect(builder.length, 9);
      expect(builder.toString(), 'foobarbaz');
    });

    test('should handle empty chunks', () {
      final builder = StringBuilder();
      builder.append('');
      builder.append('a');
      builder.append('');
      expect(builder.length, 1);
      expect(builder.toString(), 'a');
    });

    test('should reset accumulated data', () {
      final builder = StringBuilder();
      builder.append('hello');
      builder.reset();
      expect(builder.length, 0);
      expect(builder.toString(), '');
    });

    test('should allow appending after reset', () {
      final builder = StringBuilder();
      builder.append('old');
      builder.reset();
      builder.append('new');
      expect(builder.toString(), 'new');
    });

    test(
      'should accumulate many small chunks without quadratic concatenation',
      () {
        final builder = StringBuilder();
        final chunk = 'x';
        final count = 10000;
        for (var i = 0; i < count; i++) {
          builder.append(chunk);
        }
        expect(builder.length, count);
        expect(builder.toString(), 'x' * count);
      },
    );
  });

  group('LimitedStringBuilder', () {
    test('should expose the configured limit', () {
      final builder = LimitedStringBuilder(42);
      expect(builder.limit, 42);
    });

    test('should start empty', () {
      final builder = LimitedStringBuilder(10);
      expect(builder.length, 0);
      expect(builder.toString(), '');
    });

    test('should accept data up to the limit', () {
      final builder = LimitedStringBuilder(10);
      expect(builder.append('12345'), false);
      expect(builder.append('67890'), false);
      expect(builder.length, 10);
      expect(builder.toString(), '1234567890');
    });

    test('should accept a single chunk exactly at the limit', () {
      final builder = LimitedStringBuilder(5);
      expect(builder.append('abcde'), false);
      expect(builder.length, 5);
      expect(builder.toString(), 'abcde');
    });

    test('should reject data exceeding the limit and clear the buffer', () {
      final builder = LimitedStringBuilder(5);
      builder.append('abc');
      expect(builder.append('def'), true);
      expect(builder.length, 0);
      expect(builder.toString(), '');
    });

    test('should reject a single chunk larger than the limit', () {
      final builder = LimitedStringBuilder(3);
      expect(builder.append('toolong'), true);
      expect(builder.length, 0);
      expect(builder.toString(), '');
    });

    test(
      'should allow appending again after reset following a limit breach',
      () {
        final builder = LimitedStringBuilder(3);
        expect(builder.append('abcd'), true);
        builder.reset();
        expect(builder.append('ab'), false);
        expect(builder.toString(), 'ab');
      },
    );

    test('should accumulate many chunks before hitting the limit', () {
      final limit = 100;
      final builder = LimitedStringBuilder(limit);
      final chunk = 'A';
      for (var i = 0; i < limit; i++) {
        expect(builder.append(chunk), false);
      }
      expect(builder.toString(), 'A' * limit);
      expect(builder.append('B'), true);
      expect(builder.toString(), '');
    });

    test('should reject when limit is zero and any data is appended', () {
      final builder = LimitedStringBuilder(0);
      expect(builder.append('a'), true);
      expect(builder.length, 0);
    });

    test('should allow zero-length appends at the limit', () {
      final builder = LimitedStringBuilder(0);
      expect(builder.append(''), false);
      expect(builder.length, 0);
      expect(builder.toString(), '');
    });
  });
}
