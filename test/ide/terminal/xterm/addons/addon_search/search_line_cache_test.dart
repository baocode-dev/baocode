// Copyright (c) 2024 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See
// lib/ide/terminal/xterm/addons/addon_search/LICENSE.
// Adapted from xterm.js addons/addon-search/src/SearchLineCache.test.ts
// (c58ea36).
//
// Upstream runs in the browser terminal; the cache uses only the headless
// API, so this runs on the headless public terminal. Entries are records,
// whose lists compare by identity: `deepEqual` with a literal entry is
// [_isEntry].

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/terminal/xterm/addons/addon_search/search_line_cache.dart';
import 'package:monad/ide/terminal/xterm/common/async.dart';
import 'package:monad/ide/terminal/xterm/headless/public/terminal.dart';
import 'package:monad/ide/terminal/xterm/typings/xterm_headless.dart'
    show ITerminalOptions;

Future<void> writeP(Terminal terminal, String data) {
  final c = Completer<void>();
  terminal.write(data, c.complete);
  return c.future;
}

/// `assert.deepEqual(entry, [lineAsString, lineOffsets])`.
Matcher _isEntry(String lineAsString, List<int> lineOffsets) =>
    isA<LineCacheEntry>()
        .having((e) => e.$1, 'lineAsString', lineAsString)
        .having((e) => e.$2, 'lineOffsets', equals(lineOffsets));

void main() {
  group('SearchLineCache', () {
    late Terminal terminal;
    late SearchLineCache cache;

    setUp(() {
      terminal = Terminal(ITerminalOptions(cols: 80, rows: 24));
      cache = SearchLineCache(terminal);
    });

    tearDown(() {
      cache.dispose();
      terminal.dispose();
    });

    group('constructor', () {
      test('should create a SearchLineCache instance', () {
        expect(cache, isA<SearchLineCache>());
      });

      test('should start with no cache initialized', () {
        expect(cache.getLineFromCache(0), null);
      });
    });

    group('initLinesCache', () {
      test('should initialize the lines cache array', () {
        cache.initLinesCache();
        expect(
          cache.getLineFromCache(0),
          null,
          reason: 'cache should be initialized but empty',
        );
      });

      test('should not reinitialize if cache already exists', () {
        cache.initLinesCache();
        cache.setLineInCache(0, ('test', [0]));

        cache.initLinesCache();

        final entry = cache.getLineFromCache(0);
        expect(
          entry,
          _isEntry('test', [0]),
          reason: 'cache should still contain the previously set entry',
        );
      });

      test('should set up TTL timeout', () {
        cache.initLinesCache();
        cache.setLineInCache(0, ('test', [0]));

        expect(
          cache.getLineFromCache(0),
          _isEntry('test', [0]),
          reason: 'entry should exist after initialization',
        );
      });
    });

    group('getLineFromCache', () {
      test('should return undefined when cache is not initialized', () {
        expect(cache.getLineFromCache(0), null);
        expect(cache.getLineFromCache(10), null);
      });

      test(
        'should return undefined for unset entries when cache is initialized',
        () {
          cache.initLinesCache();
          expect(cache.getLineFromCache(0), null);
          expect(cache.getLineFromCache(50), null);
        },
      );

      test('should return cached entries', () {
        cache.initLinesCache();
        const LineCacheEntry entry = ('test content', [0]);
        cache.setLineInCache(5, entry);

        expect(cache.getLineFromCache(5), entry);
      });
    });

    group('setLineInCache', () {
      test('should not set entries when cache is not initialized', () {
        const LineCacheEntry entry = ('test content', [0]);
        cache.setLineInCache(0, entry);

        expect(cache.getLineFromCache(0), null);
      });

      test('should set entries when cache is initialized', () {
        cache.initLinesCache();
        const LineCacheEntry entry = ('test content', [0]);
        cache.setLineInCache(10, entry);

        expect(cache.getLineFromCache(10), entry);
      });

      test('should overwrite existing entries', () {
        cache.initLinesCache();
        const LineCacheEntry entry1 = ('first content', [0]);
        const LineCacheEntry entry2 = ('second content', [0]);

        cache.setLineInCache(0, entry1);
        expect(cache.getLineFromCache(0), entry1);

        cache.setLineInCache(0, entry2);
        expect(cache.getLineFromCache(0), entry2);
      });
    });

    group('translateBufferLineToStringWithWrap', () {
      test('should translate a single line without wrapping', () async {
        await writeP(terminal, 'Hello World');
        final result = cache.translateBufferLineToStringWithWrap(0, true);
        expect(result.$1, 'Hello World');
        expect(result.$2, equals([0]));
      });

      test('should handle trimRight parameter', () async {
        await writeP(terminal, 'Hello World   ');
        final resultTrimmed = cache.translateBufferLineToStringWithWrap(
          0,
          true,
        );
        final resultNotTrimmed = cache.translateBufferLineToStringWithWrap(
          0,
          false,
        );

        expect(resultTrimmed.$1.trimRight(), 'Hello World');
        expect(resultNotTrimmed.$1.startsWith('Hello World   '), isTrue);
        expect(
          resultNotTrimmed.$1.length > resultTrimmed.$1.length,
          isTrue,
          reason: 'non-trimmed result should be longer',
        );
      });

      test('should handle wrapped lines', () async {
        final longText = 'A' * 200;
        await writeP(terminal, longText);
        final result = cache.translateBufferLineToStringWithWrap(0, true);
        expect(result.$1, longText);
        expect(
          result.$2.length > 1,
          isTrue,
          reason: 'should have multiple offsets due to wrapping',
        );
        expect(result.$2[0], 0, reason: 'first offset should be 0');
      });

      test('should handle wide characters', () async {
        await writeP(terminal, 'Hello 世界');
        final result = cache.translateBufferLineToStringWithWrap(0, true);
        expect(result.$1, 'Hello 世界');
        expect(result.$2, equals([0]));
      });

      test('should handle empty lines', () {
        final result = cache.translateBufferLineToStringWithWrap(0, true);
        expect(result.$1, '');
        expect(result.$2, equals([0]));
      });

      test('should handle lines beyond buffer', () {
        final result = cache.translateBufferLineToStringWithWrap(1000, true);
        expect(result.$1, '');
        expect(result.$2, equals([0]));
      });

      // New: not upstream.
      test('should drop the empty cell before a wide character wrapped to the '
          'next line', () async {
        await writeP(terminal, '${'a' * 79}中');
        final result = cache.translateBufferLineToStringWithWrap(0, true);
        expect(result.$1, '${'a' * 79}中');
        expect(result.$2, equals([0, 79]));
      });

      test('should handle complex wrapped content', () async {
        await writeP(terminal, 'Line 1\r\n');
        await writeP(
          terminal,
          'Line 2 with some longer content that might wrap\r\n',
        );
        await writeP(terminal, 'Line 3');

        final result1 = cache.translateBufferLineToStringWithWrap(0, true);
        final result2 = cache.translateBufferLineToStringWithWrap(1, true);
        final result3 = cache.translateBufferLineToStringWithWrap(2, true);

        expect(result1.$1, 'Line 1');
        expect(result2.$1, 'Line 2 with some longer content that might wrap');
        expect(result3.$1, 'Line 3');
      });
    });

    group('cache invalidation', () {
      test('should invalidate cache on line feed', () async {
        cache.initLinesCache();
        cache.setLineInCache(0, ('test', [0]));

        expect(cache.getLineFromCache(0), _isEntry('test', [0]));

        terminal.write('test\r\n');

        await timeout(10);
        expect(cache.getLineFromCache(0), null);
      });

      test('should invalidate cache on cursor move', () async {
        cache.initLinesCache();
        cache.setLineInCache(0, ('test', [0]));

        expect(cache.getLineFromCache(0), _isEntry('test', [0]));

        await writeP(terminal, 'some text');
        await timeout(10);
        expect(cache.getLineFromCache(0), null);
      });

      test('should invalidate cache on resize', () async {
        cache.initLinesCache();
        cache.setLineInCache(0, ('test', [0]));

        expect(cache.getLineFromCache(0), _isEntry('test', [0]));

        terminal.resize(100, 30);

        await timeout(10);
        expect(cache.getLineFromCache(0), null);
      });
    });

    group('disposal', () {
      test('should clean up resources on dispose', () {
        cache.initLinesCache();
        cache.setLineInCache(0, ('test', [0]));

        expect(cache.getLineFromCache(0), _isEntry('test', [0]));

        cache.dispose();

        expect(
          cache.getLineFromCache(0),
          null,
          reason: 'cache should be destroyed after disposal',
        );
      });

      test('should be safe to dispose multiple times', () {
        cache.initLinesCache();
        cache.dispose();
        cache.dispose();

        expect(cache.getLineFromCache(0), null);
      });
    });

    group('LineCacheEntry type', () {
      test('should handle complex line offsets', () {
        const LineCacheEntry entry = (
          'A very long line that wraps multiple times across several terminal '
              'lines',
          [0, 20, 40, 60],
        );

        cache.initLinesCache();
        cache.setLineInCache(0, entry);

        final retrieved = cache.getLineFromCache(0);
        expect(retrieved, entry);
        expect(retrieved!.$1.length, 72);
        expect(retrieved.$2.length, 4);
      });

      test('should handle unicode characters in cache entries', () {
        const LineCacheEntry entry = ('Hello 世界 🌍 测试', [0]);

        cache.initLinesCache();
        cache.setLineInCache(0, entry);

        final retrieved = cache.getLineFromCache(0);
        expect(retrieved, entry);
        expect(retrieved!.$1, 'Hello 世界 🌍 测试');
      });
    });

    group('integration with real terminal content', () {
      test('should correctly translate real buffer content', () async {
        await writeP(terminal, 'Hello World');
        final cached = cache.translateBufferLineToStringWithWrap(0, true);
        final directTranslation =
            terminal.buffer.active.getLine(0)?.translateToString(true) ?? '';

        expect(cached.$1, directTranslation);
      });

      test('should handle real wrapped content correctly', () async {
        const longContent =
            'This is a very long line that will definitely wrap around in an '
            '80 column terminal and should be handled correctly by the cache';
        await writeP(terminal, longContent);
        final result = cache.translateBufferLineToStringWithWrap(0, true);
        expect(result.$1, longContent);
        expect(result.$2.length > 1, isTrue, reason: 'should have wrapped');
      });

      test('should work with real escape sequences', () async {
        await writeP(terminal, 'Before\x1b[31mRed Text\x1b[0mAfter');
        final result = cache.translateBufferLineToStringWithWrap(0, true);
        expect(result.$1, contains('Before'));
        expect(result.$1, contains('Red Text'));
        expect(result.$1, contains('After'));
      });
    });
  });
}
