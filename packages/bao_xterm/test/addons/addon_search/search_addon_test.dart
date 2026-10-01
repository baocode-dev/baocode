// Copyright (c) 2019 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See
// lib/addons/addon_search/LICENSE.
// Adapted from xterm.js addons/addon-search/test/SearchAddon.test.ts
// (c58ea36).
//
// Upstream's test is a Playwright test in the browser terminal; its
// assertions run here against [SearchTestTerminal], a new one (80x24) per
// test instead of `reset()`. The decoration options omit
// `matchOverviewRuler` as upstream's do, though the typings require it: it
// is ''. `\\n\\r` in upstream's data is a literal backslash, `n`, backslash,
// `r` (the proxy writes the string as it is), as here. The #2444 fixture is
// read with dart:io (VM only).

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:bao_xterm/addons/addon_search/search_addon.dart';
import 'package:bao_xterm/addons/addon_search/typings/addon_search.dart'
    hide SearchAddon;
import 'package:bao_xterm/common/async.dart';
import 'package:bao_xterm/typings/xterm.dart' show ITerminalOptions;

import 'package:bao_xterm/testing/search_test_terminal.dart';

late SearchTestTerminal term;
late SearchAddon search;

Future<void> write(String data) {
  final c = Completer<void>();
  term.write(data, c.complete);
  return c.future;
}

Future<void> writeln(String data) {
  final c = Completer<void>();
  term.writeln(data, c.complete);
  return c.future;
}

/// `{ decorations: { activeMatchColorOverviewRuler, matchOverviewRuler } }`.
ISearchOptions _decorations({String matchOverviewRuler = ''}) {
  return ISearchOptions(
    decorations: ISearchDecorationOptions(
      activeMatchColorOverviewRuler: '#ff0000',
      matchOverviewRuler: matchOverviewRuler,
    ),
  );
}

ISearchResultChangeEvent _e(int resultCount, int resultIndex) =>
    ISearchResultChangeEvent(
      resultCount: resultCount,
      resultIndex: resultIndex,
    );

/// `line.substring(start, end)`, which JavaScript clamps to the line.
String _lineSubstring(String line, int start, int end) =>
    line.substring(start, math.min(end, line.length));

void main() {
  group('Search Tests', () {
    setUp(() {
      term = SearchTestTerminal(ITerminalOptions(cols: 80, rows: 24));
      search = SearchAddon();
      term.loadAddon(search);
    });

    tearDown(() {
      term.dispose();
    });

    test('Simple Search', () async {
      await write(
        'dafhdjfldshafhldsahfkjhldhjkftestlhfdsakjfhdjhlfdsjkafhjdlk',
      );
      expect(search.findNext('test'), true);
      expect(term.getSelection(), 'test');
    });

    test('Scrolling Search', () async {
      var dataString = '';
      for (var i = 0; i < 100; i++) {
        if (i == 52) {
          dataString += r'$^1_3{}test$#';
        }
        dataString += makeData(50);
      }
      await write(dataString);
      expect(search.findNext(r'$^1_3{}test$#'), true);
      expect(term.getSelection(), r'$^1_3{}test$#');
    });

    test('Incremental Find Previous', () async {
      await writeln('package.jsonc\n');
      await write('package.json pack package.lock');
      search.findPrevious('pack', ISearchOptions(incremental: true));
      var selectionPosition = term.getSelectionPosition()!;
      var line = term.buffer.active
          .getLine(selectionPosition.start.y)!
          .translateToString();
      // We look further ahead in the line to ensure that pack was selected
      // from package.lock
      expect(
        _lineSubstring(
          line,
          selectionPosition.start.x,
          selectionPosition.end.x + 8,
        ),
        'package.lock',
      );
      search.findPrevious('package.j', ISearchOptions(incremental: true));
      selectionPosition = term.getSelectionPosition()!;
      expect(
        _lineSubstring(
          line,
          selectionPosition.start.x,
          selectionPosition.end.x + 3,
        ),
        'package.json',
      );
      search.findPrevious('package.jsonc', ISearchOptions(incremental: true));
      // We have to reevaluate line because it should have switched starting
      // rows at this point
      selectionPosition = term.getSelectionPosition()!;
      line = term.buffer.active
          .getLine(selectionPosition.start.y)!
          .translateToString();
      expect(
        _lineSubstring(
          line,
          selectionPosition.start.x,
          selectionPosition.end.x,
        ),
        'package.jsonc',
      );
    });

    test('Incremental Find Next', () async {
      await writeln('package.lock pack package.json package.ups\n');
      await write('package.jsonc');
      search.findNext('pack', ISearchOptions(incremental: true));
      var selectionPosition = term.getSelectionPosition()!;
      var line = term.buffer.active
          .getLine(selectionPosition.start.y)!
          .translateToString();
      // We look further ahead in the line to ensure that pack was selected
      // from package.lock
      expect(
        _lineSubstring(
          line,
          selectionPosition.start.x,
          selectionPosition.end.x + 8,
        ),
        'package.lock',
      );
      search.findNext('package.j', ISearchOptions(incremental: true));
      selectionPosition = term.getSelectionPosition()!;
      expect(
        _lineSubstring(
          line,
          selectionPosition.start.x,
          selectionPosition.end.x + 3,
        ),
        'package.json',
      );
      search.findNext('package.jsonc', ISearchOptions(incremental: true));
      // We have to reevaluate line because it should have switched starting
      // rows at this point
      selectionPosition = term.getSelectionPosition()!;
      line = term.buffer.active
          .getLine(selectionPosition.start.y)!
          .translateToString();
      expect(
        _lineSubstring(
          line,
          selectionPosition.start.x,
          selectionPosition.end.x,
        ),
        'package.jsonc',
      );
    });

    test('Simple Regex', () async {
      await write('abc123defABCD');
      search.findNext('[a-z]+', ISearchOptions(regex: true));
      expect(term.getSelection(), 'abc');
      search.findNext(
        '[A-Z]+',
        ISearchOptions(regex: true, caseSensitive: true),
      );
      expect(term.getSelection(), 'ABCD');
    });

    test('Search for single result twice should not unselect it', () async {
      await write('abc def');
      expect(search.findNext('abc'), true);
      expect(term.getSelection(), 'abc');
      expect(search.findNext('abc'), true);
      expect(term.getSelection(), 'abc');
    });

    test('Search for result bounding with wide unicode chars', () async {
      await write('中文xx𝄞𝄞');
      expect(search.findNext('中'), true);
      expect(term.getSelection(), '中');
      expect(search.findNext('xx'), true);
      expect(term.getSelection(), 'xx');
      expect(search.findNext('𝄞'), true);
      expect(term.getSelection(), '𝄞');
      expect(search.findNext('𝄞'), true);
      expect(term.getSelectionPosition(), bufferRange(7, 0, 8, 0));
    });

    group('onDidChangeResults', () {
      late List<ISearchResultChangeEvent> calls;

      setUp(() {
        calls = <ISearchResultChangeEvent>[];
        search.onDidChangeResults(calls.add);
      });

      group('findNext', () {
        test('should not fire unless the decorations option is set', () async {
          await write('abc');
          expect(search.findNext('a'), true);
          expect(calls.length, 0);
          expect(search.findNext('b', _decorations()), true);
          expect(calls.length, 1);
        });

        test('should fire with correct event values', () async {
          await write('abc bc c');
          expect(search.findNext('a', _decorations()), true);
          expect(calls, [_e(1, 0)]);
          expect(search.findNext('b', _decorations()), true);
          expect(calls, [_e(1, 0), _e(2, 0)]);
          expect(search.findNext('d', _decorations()), false);
          expect(calls, [_e(1, 0), _e(2, 0), _e(0, -1)]);
          expect(search.findNext('c', _decorations()), true);
          expect(search.findNext('c', _decorations()), true);
          expect(search.findNext('c', _decorations()), true);
          expect(calls, [
            _e(1, 0),
            _e(2, 0),
            _e(0, -1),
            _e(3, 0),
            _e(3, 1),
            _e(3, 2),
          ]);
        });

        test('should fire with correct event values (incremental)', () async {
          await write('d abc aabc d');
          ISearchOptions incremental() => _decorations()..incremental = true;
          expect(search.findNext('a', incremental()), true);
          expect(calls, [_e(3, 0)]);
          expect(search.findNext('ab', incremental()), true);
          expect(calls, [_e(3, 0), _e(2, 0)]);
          expect(search.findNext('abc', incremental()), true);
          expect(calls, [_e(3, 0), _e(2, 0), _e(2, 0)]);
          expect(search.findNext('abc', incremental()), true);
          expect(calls, [_e(3, 0), _e(2, 0), _e(2, 0), _e(2, 1)]);
          expect(search.findNext('d', incremental()), true);
          expect(calls, [_e(3, 0), _e(2, 0), _e(2, 0), _e(2, 1), _e(2, 1)]);
          expect(search.findNext('abcd', incremental()), false);
          expect(calls, [
            _e(3, 0),
            _e(2, 0),
            _e(2, 0),
            _e(2, 1),
            _e(2, 1),
            _e(0, -1),
          ]);
        });

        test('should fire with more than 1k matches', () async {
          final data = ('a bc' * 10 + r'\n\r') * 150;
          await write(data);
          expect(search.findNext('a', _decorations()), true);
          expect(calls, [_e(1000, 0)]);
          expect(search.findNext('a', _decorations()), true);
          expect(calls, [_e(1000, 0), _e(1000, 1)]);
          expect(search.findNext('bc', _decorations()), true);
          expect(calls, [_e(1000, 0), _e(1000, 1), _e(1000, 1)]);
        });

        test('should fire when writing to terminal', () async {
          await write(r'abc bc c\n\r' * 2);
          expect(search.findNext('abc', _decorations()), true);
          expect(calls, [_e(2, 0)]);
          await write(r'abc bc c\n\r');
          await timeout(300);
          expect(calls, [_e(2, 0), _e(3, 0)]);
        });
      });

      group('findPrevious', () {
        test('should not fire unless the decorations option is set', () async {
          await write('abc');
          expect(search.findPrevious('a'), true);
          expect(calls.length, 0);
          expect(search.findPrevious('b', _decorations()), true);
          expect(calls.length, 1);
        });

        test('should fire with correct event values', () async {
          await write('abc bc c');
          expect(search.findPrevious('a', _decorations()), true);
          expect(calls, [_e(1, 0)]);
          term.clearSelection();
          expect(search.findPrevious('b', _decorations()), true);
          expect(calls, [_e(1, 0), _e(2, 1)]);
          await timeout(2000);
          expect(search.findPrevious('d', _decorations()), false);
          expect(calls, [_e(1, 0), _e(2, 1), _e(0, -1)]);
          expect(search.findPrevious('c', _decorations()), true);
          expect(search.findPrevious('c', _decorations()), true);
          expect(search.findPrevious('c', _decorations()), true);
          expect(calls, [
            _e(1, 0),
            _e(2, 1),
            _e(0, -1),
            _e(3, 2),
            _e(3, 1),
            _e(3, 0),
          ]);
        });

        test('should fire with correct event values (incremental)', () async {
          await write('d abc aabc d');
          ISearchOptions incremental() => _decorations()..incremental = true;
          expect(search.findPrevious('a', incremental()), true);
          expect(calls, [_e(3, 2)]);
          expect(search.findPrevious('ab', incremental()), true);
          expect(calls, [_e(3, 2), _e(2, 1)]);
          expect(search.findPrevious('abc', incremental()), true);
          expect(calls, [_e(3, 2), _e(2, 1), _e(2, 1)]);
          expect(search.findPrevious('abc', incremental()), true);
          expect(calls, [_e(3, 2), _e(2, 1), _e(2, 1), _e(2, 0)]);
          expect(search.findPrevious('d', incremental()), true);
          expect(calls, [_e(3, 2), _e(2, 1), _e(2, 1), _e(2, 0), _e(2, 1)]);
          expect(search.findPrevious('abcd', incremental()), false);
          expect(calls, [
            _e(3, 2),
            _e(2, 1),
            _e(2, 1),
            _e(2, 0),
            _e(2, 1),
            _e(0, -1),
          ]);
        });

        test('should fire with more than 1k matches', () async {
          final data = ('a bc' * 10 + r'\n\r') * 150;
          await write(data);
          expect(search.findPrevious('a', _decorations()), true);
          expect(calls, [_e(1000, -1)]);
          expect(search.findPrevious('a', _decorations()), true);
          expect(calls, [_e(1000, -1), _e(1000, -1)]);
          expect(search.findPrevious('bc', _decorations()), true);
          expect(calls, [_e(1000, -1), _e(1000, -1), _e(1000, -1)]);
        });

        test('should fire when writing to terminal', () async {
          await write(r'abc bc c\n\r' * 2);
          expect(search.findPrevious('abc', _decorations()), true);
          expect(calls, [_e(2, 1)]);
          await write(r'abc bc c\n\r');
          await timeout(300);
          expect(calls, [_e(2, 1), _e(3, 1)]);
        });
      });
    });

    group('onBeforeSearch and onAfterSearch', () {
      late List<String> events;

      setUp(() {
        events = <String>[];
        search.onBeforeSearch((_) => events.add('before'));
        search.onAfterSearch((_) => events.add('after'));
      });

      test('should fire before and after findNext', () async {
        await write('abc');
        search.findNext('a');
        expect(events, ['before', 'after']);
      });

      test('should fire before and after findPrevious', () async {
        await write('abc');
        search.findPrevious('a');
        expect(events, ['before', 'after']);
      });

      test('should fire for each search call', () async {
        await write('abc abc');
        search.findNext('abc');
        search.findNext('abc');
        expect(events, ['before', 'after', 'before', 'after']);
      });
    });

    group('Regression tests', () {
      test('should advance highlight-all scan by buffer match size for wide '
          'characters', () async {
        final calls = <ISearchResultChangeEvent>[];
        search.onDidChangeResults(calls.add);
        term.resize(3, 5);
        await write('𝄞𝄞𝄞');
        expect(
          search.findNext('𝄞', _decorations(matchOverviewRuler: '#ffff00')),
          true,
        );
        expect(calls, [_e(3, 0)]);
        term.resize(80, 24);
      });

      group('#2444 wrapped line content not being found', () {
        late String fixture;

        setUpAll(() {
          fixture = File('test/addons/addon_search/fixtures/issue-2444')
              .readAsStringSync();
          if (!Platform.isWindows) {
            fixture = fixture.replaceAll('\n', '\n\r');
          }
        });

        test('should find all occurrences using findNext', () async {
          await write(fixture);
          expect(search.findNext('opencv'), true);
          var selectionPosition = term.getSelectionPosition();
          expect(selectionPosition, bufferRange(24, 53, 30, 53));
          expect(search.findNext('opencv'), true);
          selectionPosition = term.getSelectionPosition();
          expect(selectionPosition, bufferRange(24, 76, 30, 76));
          expect(search.findNext('opencv'), true);
          selectionPosition = term.getSelectionPosition();
          expect(selectionPosition, bufferRange(24, 96, 30, 96));
          expect(search.findNext('opencv'), true);
          selectionPosition = term.getSelectionPosition();
          expect(selectionPosition, bufferRange(1, 114, 7, 114));
          expect(search.findNext('opencv'), true);
          selectionPosition = term.getSelectionPosition();
          expect(selectionPosition, bufferRange(11, 115, 17, 115));
          expect(search.findNext('opencv'), true);
          selectionPosition = term.getSelectionPosition();
          expect(selectionPosition, bufferRange(1, 126, 7, 126));
          expect(search.findNext('opencv'), true);
          selectionPosition = term.getSelectionPosition();
          expect(selectionPosition, bufferRange(11, 127, 17, 127));
          expect(search.findNext('opencv'), true);
          selectionPosition = term.getSelectionPosition();
          expect(selectionPosition, bufferRange(1, 135, 7, 135));
          expect(search.findNext('opencv'), true);
          selectionPosition = term.getSelectionPosition();
          expect(selectionPosition, bufferRange(11, 136, 17, 136));
          // Wrap around to first result
          expect(search.findNext('opencv'), true);
          selectionPosition = term.getSelectionPosition();
          expect(selectionPosition, bufferRange(24, 53, 30, 53));
        });

        test('should y all occurrences using findPrevious', () async {
          await write(fixture);
          expect(search.findPrevious('opencv'), true);
          var selectionPosition = term.getSelectionPosition();
          expect(selectionPosition, bufferRange(11, 136, 17, 136));
          expect(search.findPrevious('opencv'), true);
          selectionPosition = term.getSelectionPosition();
          expect(selectionPosition, bufferRange(1, 135, 7, 135));
          expect(search.findPrevious('opencv'), true);
          selectionPosition = term.getSelectionPosition();
          expect(selectionPosition, bufferRange(11, 127, 17, 127));
          expect(search.findPrevious('opencv'), true);
          selectionPosition = term.getSelectionPosition();
          expect(selectionPosition, bufferRange(1, 126, 7, 126));
          expect(search.findPrevious('opencv'), true);
          selectionPosition = term.getSelectionPosition();
          expect(selectionPosition, bufferRange(11, 115, 17, 115));
          expect(search.findPrevious('opencv'), true);
          selectionPosition = term.getSelectionPosition();
          expect(selectionPosition, bufferRange(1, 114, 7, 114));
          expect(search.findPrevious('opencv'), true);
          selectionPosition = term.getSelectionPosition();
          expect(selectionPosition, bufferRange(24, 96, 30, 96));
          expect(search.findPrevious('opencv'), true);
          selectionPosition = term.getSelectionPosition();
          expect(selectionPosition, bufferRange(24, 76, 30, 76));
          expect(search.findPrevious('opencv'), true);
          selectionPosition = term.getSelectionPosition();
          expect(selectionPosition, bufferRange(24, 53, 30, 53));
          // Wrap around to first result
          expect(search.findPrevious('opencv'), true);
          selectionPosition = term.getSelectionPosition();
          expect(selectionPosition, bufferRange(11, 136, 17, 136));
        });
      });
    });

    group('#3834 lines with null characters before search terms', () {
      // This case can be triggered by the prompt when using starship under
      // conpty
      test(
        'should find all matches on a line containing null characters',
        () async {
          final calls = <ISearchResultChangeEvent>[];
          search.onDidChangeResults(calls.add);
          // Move cursor forward 1 time to create a null character, as opposed
          // to regular whitespace
          await write('\x1b[CHi Hi');
          expect(search.findPrevious('h', _decorations()), true);
          expect(calls, [_e(2, 1)]);
        },
      );
    });

    group('Wrapped line search functionality', () {
      test(
        'should correctly count matches across multiple wrapped lines',
        () async {
          final calls = <ISearchResultChangeEvent>[];
          search.onDidChangeResults(calls.add);

          final content = 'a' * 300;
          await write(content);
          expect(
            search.findNext(
              content,
              _decorations(matchOverviewRuler: '#ffff00'),
            ),
            true,
          );
          expect(calls, [_e(1, 0)]);
        },
      );

      test('should handle reverse search across wrapped lines', () async {
        final calls = <ISearchResultChangeEvent>[];
        search.onDidChangeResults(calls.add);

        final content = 'x' * 300;
        await write(content);
        expect(
          search.findPrevious(
            content,
            _decorations(matchOverviewRuler: '#ffff00'),
          ),
          true,
        );
        expect(calls, [_e(1, 0)]);
      });

      test(
        'should update counts when content changes across wrapped lines',
        () async {
          final calls = <ISearchResultChangeEvent>[];
          search.onDidChangeResults(calls.add);

          final content = 'z' * 300;
          await write(content);
          expect(
            search.findNext(
              content,
              _decorations(matchOverviewRuler: '#ffff00'),
            ),
            true,
          );
          expect(calls, [_e(1, 0)]);

          await write(r'\n\r' + content);
          await timeout(300);
          expect(calls, [_e(1, 0), _e(2, 0)]);
        },
      );
    });
  });
}

final math.Random _random = math.Random();

String makeData(int length) {
  var result = '';
  const characters =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  for (var i = 0; i < length; i++) {
    result += characters[_random.nextInt(characters.length)];
  }
  return result;
}
