// Copyright (c) 2024 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See
// lib/ide/terminal/xterm/addons/addon_search/LICENSE.
// Adapted from xterm.js addons/addon-search/src/SearchEngine.test.ts
// (c58ea36).
//
// Upstream runs in the browser terminal: this runs on [SearchTestTerminal],
// whose `getSelectionPositionMock` stands in for assigning
// `terminal.getSelectionPosition`. An invalid regex throws Dart's
// FormatException, not a SyntaxError reading "Invalid regular expression".

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/terminal/xterm/addons/addon_search/search_engine.dart';
import 'package:baocode/ide/terminal/xterm/addons/addon_search/search_line_cache.dart';
import 'package:baocode/ide/terminal/xterm/addons/addon_search/typings/addon_search.dart';
import 'package:baocode/ide/terminal/xterm/common/lifecycle.dart';
import 'package:baocode/ide/terminal/xterm/typings/xterm_headless.dart'
    show ITerminalOptions;

import 'search_test_terminal.dart';

Future<void> writeP(SearchTestTerminal terminal, String data) {
  final c = Completer<void>();
  terminal.write(data, c.complete);
  return c.future;
}

ISearchResult _result(String term, int col, int row, int size) =>
    ISearchResult(term: term, col: col, row: row, size: size);

void main() {
  group('SearchEngine', () {
    late DisposableStore store;
    late SearchTestTerminal terminal;
    late SearchLineCache lineCache;
    late SearchEngine searchEngine;

    setUp(() {
      store = DisposableStore();
      terminal = store.add(
        SearchTestTerminal(ITerminalOptions(cols: 80, rows: 24)),
      );
      lineCache = store.add(SearchLineCache(terminal));
      searchEngine = SearchEngine(terminal, lineCache);
    });

    tearDown(() {
      store.dispose();
    });

    group('find', () {
      test('should return undefined for empty search term', () async {
        await writeP(terminal, 'Hello World');

        expect(searchEngine.find('', 0, 0), null);
      });

      test('should find basic text in terminal content', () async {
        await writeP(terminal, 'Hello World');

        expect(searchEngine.find('World', 0, 0), _result('World', 6, 0, 5));
      });

      test('should find text starting from specified position', () async {
        await writeP(terminal, 'Hello Hello Hello');

        expect(searchEngine.find('Hello', 0, 7), _result('Hello', 12, 0, 5));
      });

      test('should search across multiple rows', () async {
        await writeP(terminal, 'Line 1\r\nLine 2 target\r\nLine 3');

        expect(searchEngine.find('target', 0, 0), _result('target', 7, 1, 6));
      });

      test('should return undefined when text is not found', () async {
        await writeP(terminal, 'Hello World');

        expect(searchEngine.find('NotFound', 0, 0), null);
      });

      test('should throw error for invalid column position', () async {
        await writeP(terminal, 'Hello World');

        expect(
          () {
            searchEngine.find('Hello', 0, 100);
          },
          throwsA(
            isA<RangeError>().having(
              (e) => e.message,
              'message',
              matches(
                RegExp('Invalid col: 100 to search in terminal of 80 cols'),
              ),
            ),
          ),
        );
      });

      test('should handle search starting from last column', () async {
        await writeP(terminal, 'Hello World');

        expect(searchEngine.find('Hello', 0, 79), null);
      });

      test('should handle search from middle of match', () async {
        await writeP(terminal, 'Hello World');

        // Should not find partial match that starts before search position
        expect(searchEngine.find('llo', 0, 3), null);
      });
    });

    group('search options', () {
      group('caseSensitive', () {
        test(
          'should find text with case-insensitive search (default)',
          () async {
            await writeP(terminal, 'Hello WORLD');

            expect(searchEngine.find('world', 0, 0), _result('world', 6, 0, 5));
          },
        );

        test(
          'should find text with case-sensitive search when enabled',
          () async {
            await writeP(terminal, 'Hello WORLD');

            expect(
              searchEngine.find(
                'WORLD',
                0,
                0,
                ISearchOptions(caseSensitive: true),
              ),
              _result('WORLD', 6, 0, 5),
            );
          },
        );

        test(
          'should not find text with case-sensitive search when case differs',
          () async {
            await writeP(terminal, 'Hello WORLD');

            expect(
              searchEngine.find(
                'world',
                0,
                0,
                ISearchOptions(caseSensitive: true),
              ),
              null,
            );
          },
        );
      });

      group('wholeWord', () {
        test('should find whole word when enabled', () async {
          await writeP(terminal, 'Hello world wonderful');

          expect(
            searchEngine.find('world', 0, 0, ISearchOptions(wholeWord: true)),
            _result('world', 6, 0, 5),
          );
        });

        test(
          'should not find partial word when wholeWord is enabled',
          () async {
            await writeP(terminal, 'Hello wonderful');

            expect(
              searchEngine.find('world', 0, 0, ISearchOptions(wholeWord: true)),
              null,
            );
          },
        );

        test('should find word at beginning of line with wholeWord', () async {
          await writeP(terminal, 'world is great');

          expect(
            searchEngine.find('world', 0, 0, ISearchOptions(wholeWord: true)),
            _result('world', 0, 0, 5),
          );
        });

        test('should find word at end of line with wholeWord', () async {
          await writeP(terminal, 'hello world');

          expect(
            searchEngine.find('world', 0, 0, ISearchOptions(wholeWord: true)),
            _result('world', 6, 0, 5),
          );
        });

        test('should handle word boundaries with punctuation', () async {
          await writeP(terminal, 'hello,world!test');

          expect(
            searchEngine.find('world', 0, 0, ISearchOptions(wholeWord: true)),
            _result('world', 6, 0, 5),
          );
        });

        test('should not match when not whole word', () async {
          await writeP(terminal, 'helloworld');

          expect(
            searchEngine.find('world', 0, 0, ISearchOptions(wholeWord: true)),
            null,
          );
        });
      });

      group('regex', () {
        test('should find text using simple regex pattern', () async {
          await writeP(terminal, 'Hello 123 World');

          expect(
            searchEngine.find('[0-9]+', 0, 0, ISearchOptions(regex: true)),
            _result('123', 6, 0, 3),
          );
        });

        test(
          'should find text using regex with case-insensitive flag',
          () async {
            await writeP(terminal, 'Hello WORLD');

            expect(
              searchEngine.find(
                'world',
                0,
                0,
                ISearchOptions(regex: true, caseSensitive: false),
              ),
              _result('WORLD', 6, 0, 5),
            );
          },
        );

        test('should find text using regex with case-sensitive flag', () async {
          await writeP(terminal, 'Hello WORLD world');

          expect(
            searchEngine.find(
              'WORLD',
              0,
              0,
              ISearchOptions(regex: true, caseSensitive: true),
            ),
            _result('WORLD', 6, 0, 5),
          );
        });

        test('should handle complex regex patterns', () async {
          await writeP(
            terminal,
            'Email: test@example.com and another@domain.org',
          );

          expect(
            searchEngine.find(
              r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}',
              0,
              0,
              ISearchOptions(regex: true),
            ),
            _result('test@example.com', 7, 0, 16),
          );
        });

        test('should return undefined for invalid regex pattern', () async {
          await writeP(terminal, 'Hello World');

          // Invalid regex should be handled gracefully
          expect(() {
            searchEngine.find('[invalid', 0, 0, ISearchOptions(regex: true));
          }, throwsFormatException);
        });

        test('should handle empty regex matches', () async {
          await writeP(terminal, 'Hello World');

          // Empty matches should be ignored
          expect(
            searchEngine.find('.*?', 0, 0, ISearchOptions(regex: true)),
            null,
          );
        });
      });

      group('combined options', () {
        test('should handle regex + caseSensitive combination', () async {
          await writeP(terminal, 'Hello WORLD world');

          expect(
            searchEngine.find(
              '[A-Z]+',
              0,
              0,
              ISearchOptions(regex: true, caseSensitive: true),
            ),
            _result('H', 0, 0, 1),
          );
        });

        test('should handle wholeWord + caseSensitive combination', () async {
          await writeP(terminal, 'Hello WORLD wonderful');

          final result1 = searchEngine.find(
            'WORLD',
            0,
            0,
            ISearchOptions(wholeWord: true, caseSensitive: true),
          );
          expect(result1, _result('WORLD', 6, 0, 5));

          final result2 = searchEngine.find(
            'world',
            0,
            0,
            ISearchOptions(wholeWord: true, caseSensitive: true),
          );
          expect(result2, null);
        });
      });
    });

    group('findNextWithSelection', () {
      test('should return undefined for empty search term', () async {
        await writeP(terminal, 'Hello World');

        expect(searchEngine.findNextWithSelection(''), null);
      });

      test('should find first occurrence when no selection exists', () async {
        await writeP(terminal, 'Hello World Hello');

        expect(
          searchEngine.findNextWithSelection('Hello'),
          _result('Hello', 0, 0, 5),
        );
      });

      test('should find next occurrence after current selection', () async {
        await writeP(terminal, 'Hello World Hello Again');

        // Mock the getSelectionPosition to return a selection at first
        // "Hello"
        terminal.getSelectionPositionMock = () => bufferRange(0, 0, 5, 0);

        expect(
          searchEngine.findNextWithSelection('Hello', null, 'Hello'),
          _result('Hello', 12, 0, 5),
        );
      });

      test('should wrap around to beginning when reaching end', () async {
        await writeP(terminal, 'Hello World Hello');

        // Mock selection at the end
        terminal.getSelectionPositionMock = () => bufferRange(12, 0, 17, 0);

        // Should wrap to first occurrence
        expect(
          searchEngine.findNextWithSelection('Hello', null, 'Hello'),
          _result('Hello', 0, 0, 5),
        );
      });

      test('should wrap across multiple rows', () async {
        await writeP(terminal, 'Line 1 test\r\nLine 2\r\nLine 3 test');

        // Mock selection at first "test"
        terminal.getSelectionPositionMock = () => bufferRange(7, 0, 11, 0);

        expect(
          searchEngine.findNextWithSelection('test', null, 'test'),
          _result('test', 7, 2, 4),
        );
      });

      test('should return same selection if only one match exists', () async {
        await writeP(terminal, 'Hello World');

        // Mock selection at "Hello"
        terminal.getSelectionPositionMock = () => bufferRange(0, 0, 5, 0);

        expect(
          searchEngine.findNextWithSelection('Hello'),
          _result('Hello', 0, 0, 5),
        );
      });

      test(
        'should clear selection and return undefined when term not found',
        () async {
          await writeP(terminal, 'Hello World');

          expect(searchEngine.findNextWithSelection('NotFound'), null);
        },
      );
    });

    group('findPreviousWithSelection', () {
      test('should return undefined for empty search term', () async {
        await writeP(terminal, 'Hello World');

        expect(searchEngine.findPreviousWithSelection(''), null);
      });

      test('should find last occurrence when no selection exists', () async {
        await writeP(terminal, 'Hello World Hello');

        expect(
          searchEngine.findPreviousWithSelection('Hello'),
          _result('Hello', 12, 0, 5),
        );
      });

      test(
        'should find previous occurrence before current selection',
        () async {
          await writeP(terminal, 'Hello World Hello Again');

          // Mock selection at second "Hello"
          terminal.getSelectionPositionMock = () => bufferRange(12, 0, 17, 0);

          final result = searchEngine.findPreviousWithSelection('Hello');
          expect(result, isNot(null));
          // It may find the same selection first due to expansion attempt
          expect(result!.col, isA<int>());
          expect(result.row, 0);
        },
      );

      test('should wrap around to end when reaching beginning', () async {
        await writeP(terminal, 'Hello World Hello');

        // Mock selection at first "Hello"
        terminal.getSelectionPositionMock = () => bufferRange(0, 0, 5, 0);

        final result = searchEngine.findPreviousWithSelection('Hello');
        expect(result, isNot(null));
        // Due to the expansion attempt, it may find the same Hello first
        expect(result!.col, isA<int>());
        expect(result.row, 0);
      });

      test('should work across multiple rows in reverse', () async {
        await writeP(terminal, 'test Line 1\r\nLine 2\r\ntest Line 3');

        // Mock selection at last "test"
        terminal.getSelectionPositionMock = () => bufferRange(0, 2, 4, 2);

        final result = searchEngine.findPreviousWithSelection('test');
        expect(result, isNot(null));
        // The algorithm will find the current selection first due to
        // expansion attempt
        expect(result!.row, isA<int>());
        expect(result.col, isA<int>());
      });

      test('should handle selection expansion correctly', () async {
        await writeP(terminal, 'Hello World Hello');

        // Mock selection at first "Hello"
        terminal.getSelectionPositionMock = () => bufferRange(0, 0, 5, 0);

        final result = searchEngine.findPreviousWithSelection('Hello');
        expect(result, isNot(null));
        // The algorithm tries expansion first, so it may find the same Hello
        expect(result!.col, isA<int>());
        expect(result.row, 0);
      });

      test(
        'should clear selection and return undefined when term not found',
        () async {
          await writeP(terminal, 'Hello World');

          expect(searchEngine.findPreviousWithSelection('NotFound'), null);
        },
      );
    });

    group('edge cases and error handling', () {
      group('unicode and special characters', () {
        test('should handle unicode characters correctly', () async {
          await writeP(terminal, 'Hello 世界 World');

          expect(searchEngine.find('世界', 0, 0), _result('世界', 6, 0, 4));
        });

        test('should handle wide characters', () async {
          await writeP(terminal, '中文测试');

          expect(searchEngine.find('测试', 0, 0), _result('测试', 4, 0, 4));
        });
      });

      group('wrapped lines', () {
        test('should handle search across wrapped lines', () async {
          final longText = '${'A' * 100}target${'B' * 50}';
          await writeP(terminal, longText);

          expect(
            searchEngine.find('target', 0, 0),
            _result('target', 20, 1, 6),
          );
        });

        test('should handle wrapped lines with unicode', () async {
          final longText = '${'中' * 50}target${'文' * 30}';
          await writeP(terminal, longText);

          expect(
            searchEngine.find('target', 0, 0),
            _result('target', 20, 1, 6),
          );
        });

        test('should skip wrapped lines correctly in findInLine', () async {
          final longText = 'A' * 200;
          await writeP(terminal, '$longText\r\nNext line with target');

          expect(
            searchEngine.find('target', 0, 0),
            _result('target', 15, 3, 6),
          );
        });
      });

      group('buffer boundaries', () {
        test('should handle empty buffer gracefully', () {
          expect(searchEngine.find('anything', 0, 0), null);
        });

        test('should handle search beyond buffer size', () {
          expect(searchEngine.find('test', 1000, 0), null);
        });
      });

      group('invalid inputs', () {
        test('should handle undefined search options gracefully', () async {
          await writeP(terminal, 'Hello World');

          expect(
            searchEngine.find('Hello', 0, 0, null),
            _result('Hello', 0, 0, 5),
          );
        });

        test('should handle negative start positions', () async {
          await writeP(terminal, 'Hello World');

          expect(searchEngine.find('Hello', -1, -1), _result('Hello', 0, 0, 5));
        });

        test(
          'should handle search options with undefined properties',
          () async {
            await writeP(terminal, 'Hello World');

            final options = ISearchOptions(
              caseSensitive: null,
              regex: null,
              wholeWord: null,
            );

            expect(
              searchEngine.find('Hello', 0, 0, options),
              _result('Hello', 0, 0, 5),
            );
          },
        );
      });
    });

    group('private method behaviors (tested indirectly)', () {
      group('_isWholeWord behavior', () {
        test(
          'should recognize word boundaries with various punctuation',
          () async {
            await writeP(
              terminal,
              'word1 word2,word3(word4)word5[word6]word7{word8}',
            );

            final tests = <({String term, bool expected})>[
              (term: 'word1', expected: true),
              (term: 'word2', expected: true),
              (term: 'word3', expected: true),
              (term: 'word4', expected: true),
              (term: 'word5', expected: true),
              (term: 'word6', expected: true),
              (term: 'word7', expected: true),
              (term: 'word8', expected: true),
            ];

            for (final test in tests) {
              final result = searchEngine.find(
                test.term,
                0,
                0,
                ISearchOptions(wholeWord: true),
              );
              if (test.expected) {
                expect(
                  result,
                  isNot(null),
                  reason: 'Should find whole word: ${test.term}',
                );
              } else {
                expect(
                  result,
                  null,
                  reason: 'Should not find non-whole word: ${test.term}',
                );
              }
            }
          },
        );

        test('should handle word boundaries at line start and end', () async {
          await writeP(terminal, 'start middle end');

          final startResult = searchEngine.find(
            'start',
            0,
            0,
            ISearchOptions(wholeWord: true),
          );
          expect(startResult, _result('start', 0, 0, 5));

          final endResult = searchEngine.find(
            'end',
            0,
            0,
            ISearchOptions(wholeWord: true),
          );
          expect(endResult, _result('end', 13, 0, 3));

          final middleResult = searchEngine.find(
            'middle',
            0,
            0,
            ISearchOptions(wholeWord: true),
          );
          expect(middleResult, _result('middle', 6, 0, 6));
        });
      });

      group('buffer offset calculations', () {
        test('should handle wide character offset calculations', () async {
          await writeP(terminal, '中文 test 测试');

          final result = searchEngine.find('test', 0, 0);
          expect(result, isNot(null));
          expect(result!.term, 'test');
          // Exact column position depends on wide character handling
          expect(result.col, isA<int>());
        });
      });

      group('string to buffer size conversions', () {
        test('should correctly calculate size for simple text', () async {
          await writeP(terminal, 'Hello World');

          expect(searchEngine.find('World', 0, 0), _result('World', 6, 0, 5));
        });

        test('should correctly calculate size for unicode text', () async {
          await writeP(terminal, 'Hello 世界');

          final result = searchEngine.find('世界', 0, 0);
          expect(result, isNot(null));
          // Size should account for wide characters
          expect(result!.size, isA<int>());
          expect(result.size >= 2, isTrue);
        });

        test('should handle size calculation across wrapped lines', () async {
          final longMatch = 'A' * 100;
          await writeP(terminal, longMatch);

          final result = searchEngine.find(longMatch, 0, 0);
          expect(result, isNot(null));
          expect(result!.size >= 100, isTrue);
        });
      });
    });

    group('integration with SearchLineCache', () {
      test('should use cache for line translation', () async {
        await writeP(terminal, 'Hello World');

        // Initialize cache
        lineCache.initLinesCache();

        final result1 = searchEngine.find('World', 0, 0);
        final result2 = searchEngine.find('World', 0, 0);

        expect(result1, isNot(null));
        expect(result2, isNot(null));
        expect(result1, result2);
      });

      test('should handle cache misses gracefully', () async {
        await writeP(terminal, 'Hello World');

        // Don't initialize cache
        expect(searchEngine.find('World', 0, 0), _result('World', 6, 0, 5));
      });

      test('should work correctly with cache invalidation', () async {
        await writeP(terminal, 'Initial text');
        lineCache.initLinesCache();

        final result1 = searchEngine.find('Initial', 0, 0);
        expect(result1, isNot(null));

        // Change terminal content which should invalidate cache
        await writeP(terminal, '\r\nNew line');

        final result2 = searchEngine.find('New', 0, 0);
        expect(result2, _result('New', 0, 1, 3));
      });
    });
  });
}
