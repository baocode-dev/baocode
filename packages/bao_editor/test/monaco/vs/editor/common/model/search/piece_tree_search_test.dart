/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Expected ranges adapted from VS Code 6a598d4a textModelSearch.test.ts and
// pieceTreeTextBuffer.test.ts; directional search also covers PieceTreeBase
// edits, CRLF normalization, and UTF-16 / zero-width positions.
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/editor/monaco/vs/editor/common/core/position.dart';
import 'package:baocode/ide/editor/monaco/vs/editor/common/core/range.dart';
import 'package:baocode/ide/editor/monaco/vs/editor/common/model/piece_tree_text_buffer/piece_tree_base.dart'
    as tree;
import 'package:baocode/ide/editor/monaco/vs/editor/common/model/search/piece_tree_search.dart';

const separators = r'.,:;()-[]{}';

tree.PieceTreeBase buffer(String value, [String eol = '\n']) =>
    tree.PieceTreeBase(
      [tree.StringBuffer(value, tree.createLineStartsFast(value))],
      eol,
      true,
    );

Range full(tree.PieceTreeBase value) => Range(
  1,
  1,
  value.getLineCount(),
  value.getLineLength(value.getLineCount()) + 1,
);

List<(int, int, int, int)> coordinates(List<FindMatch> matches) => [
  for (final m in matches)
    (
      m.range.startLineNumber,
      m.range.startColumn,
      m.range.endLineNumber,
      m.range.endColumn,
    ),
];

(int, int, int, int)? coordinate(FindMatch? match) => match == null
    ? null
    : (
        match.range.startLineNumber,
        match.range.startColumn,
        match.range.endLineNumber,
        match.range.endColumn,
      );

void main() {
  final regularText = [
    'This is some foo - bar text which contains foo and bar - as in Barcelona.',
    "Now it begins a word fooBar and now it is caps Foo-isn't this great?",
    "And here's a dull line with nothing interesting in it",
    "It is also interesting if it's part of a word like amazingFooBar",
    'Again nothing interesting here',
  ];

  group('pinned textModelSearch.findMatches cases (LF and CRLF)', () {
    for (final eol in ['\n', '\r\n']) {
      test('literal, case, whole words ($eol)', () {
        final b = buffer(regularText.join(eol), eol);
        expect(
          coordinates(
            PieceTreeSearch.findMatches(b, const SearchParams('foo'), full(b)),
          ),
          [
            (1, 14, 1, 17),
            (1, 44, 1, 47),
            (2, 22, 2, 25),
            (2, 48, 2, 51),
            (4, 59, 4, 62),
          ],
        );
        expect(
          coordinates(
            PieceTreeSearch.findMatches(
              b,
              const SearchParams('foo', matchCase: true),
              full(b),
            ),
          ),
          [(1, 14, 1, 17), (1, 44, 1, 47), (2, 22, 2, 25)],
        );
        expect(
          coordinates(
            PieceTreeSearch.findMatches(
              b,
              const SearchParams('foo', wordSeparators: separators),
              full(b),
            ),
          ),
          [(1, 14, 1, 17), (1, 44, 1, 47), (2, 48, 2, 51)],
        );
      });

      test('anchors and empty lines ($eol)', () {
        final b = buffer('hi$eol${eol}bye', eol);
        expect(
          coordinates(
            PieceTreeSearch.findMatches(
              b,
              const SearchParams('^', isRegex: true),
              full(b),
            ),
          ),
          [(1, 1, 1, 1), (2, 1, 2, 1), (3, 1, 3, 1)],
        );
        expect(
          coordinates(
            PieceTreeSearch.findMatches(
              b,
              const SearchParams(r'^$', isRegex: true),
              full(b),
            ),
          ),
          [(2, 1, 2, 1)],
        );
        expect(
          coordinates(
            PieceTreeSearch.findMatches(
              b,
              const SearchParams(r'$', isRegex: true),
              full(b),
            ),
          ),
          [(1, 3, 1, 3), (2, 1, 2, 1), (3, 4, 3, 4)],
        );
      });

      test('multiline literal and regexp ($eol)', () {
        final b = buffer(
          [
            'Just some text text',
            'some text text',
            'some text again',
            'again some text',
            'but not some',
          ].join(eol),
          eol,
        );
        expect(
          coordinates(
            PieceTreeSearch.findMatches(
              b,
              const SearchParams('text\nsome'),
              full(b),
            ),
          ),
          [(1, 16, 2, 5), (2, 11, 3, 5)],
        );
        final regexFixture = buffer(
          [
            'Just some text text',
            'Just some text text',
            'some text again',
            'again some text',
          ].join(eol),
          eol,
        );
        expect(
          coordinates(
            PieceTreeSearch.findMatches(
              regexFixture,
              const SearchParams(r'text\n', isRegex: true),
              full(regexFixture),
            ),
          ),
          [(1, 16, 2, 1), (2, 16, 3, 1)],
        );
        expect(
          coordinates(
            PieceTreeSearch.findMatches(
              regexFixture,
              const SearchParams(r'text\nJust', isRegex: true),
              full(regexFixture),
            ),
          ),
          [(1, 16, 2, 5)],
        );
        expect(
          coordinates(
            PieceTreeSearch.findMatches(
              b,
              const SearchParams(r'\r\n', isRegex: true),
              full(b),
            ),
          ),
          isEmpty,
        );
      });
    }

    test('Unicode whole word #3623 and punctuation #27459/#27594', () {
      final b = buffer('я\nкомпилятор\nобфускация\n:я-я');
      expect(
        coordinates(
          PieceTreeSearch.findMatches(
            b,
            const SearchParams('я', wordSeparators: separators),
            full(b),
          ),
        ),
        [(1, 1, 1, 2), (4, 2, 4, 3), (4, 4, 4, 5)],
      );
      final punctuation = buffer(
        'this._register(this._textAreaInput.onKeyDown((e: IKeyboardEvent) => {',
      );
      expect(
        coordinates(
          PieceTreeSearch.findMatches(
            punctuation,
            const SearchParams('((e: ', wordSeparators: separators),
            full(punctuation),
          ),
        ),
        [(1, 45, 1, 50)],
      );
      final listen = buffer('this.server.listen(0);');
      expect(
        coordinates(
          PieceTreeSearch.findMatches(
            listen,
            const SearchParams('listen(', wordSeparators: separators),
            full(listen),
          ),
        ),
        [(1, 13, 1, 20)],
      );
    });

    test('captures #486/#501 and optional capture group', () {
      final b = buffer('one line line\ntwo line\nthree');
      final matches = PieceTreeSearch.findMatches(
        b,
        const SearchParams(r'(l(in)e)', isRegex: true),
        full(b),
        captureMatches: true,
      );
      expect(coordinates(matches), [
        (1, 5, 1, 9),
        (1, 10, 1, 14),
        (2, 5, 2, 9),
      ]);
      expect(matches.map((match) => match.matches).toList(), [
        ['line', 'line', 'in'],
        ['line', 'line', 'in'],
        ['line', 'line', 'in'],
      ]);
      final multi = PieceTreeSearch.findMatches(
        b,
        const SearchParams(r'(l(in)e)\n', isRegex: true),
        full(b),
        captureMatches: true,
      );
      expect(coordinates(multi), [(1, 10, 2, 1), (2, 5, 3, 1)]);
      expect(multi.first.matches, ['line\n', 'line', 'in']);
      expect(
        PieceTreeSearch.findMatches(
          buffer('b'),
          const SearchParams(r'(a)?b', isRegex: true),
          Range(1, 1, 1, 2),
          captureMatches: true,
        ).single.matches,
        ['b', null],
      );
    });

    test('zero-length regexp skips surrogate interiors #100134', () {
      final b = buffer('1😀1');
      expect(
        coordinates(
          PieceTreeSearch.findMatches(
            b,
            const SearchParams('()', isRegex: true),
            full(b),
          ),
        ),
        [(1, 1, 1, 1), (1, 2, 1, 2), (1, 4, 1, 4), (1, 5, 1, 5)],
      );
      final zwj = buffer('1🐱‍💻1');
      expect(
        coordinates(
          PieceTreeSearch.findMatches(
            zwj,
            const SearchParams('()', isRegex: true),
            full(zwj),
          ),
        ),
        [
          (1, 1, 1, 1),
          (1, 2, 1, 2),
          (1, 4, 1, 4),
          (1, 5, 1, 5),
          (1, 7, 1, 7),
          (1, 8, 1, 8),
        ],
      );
    });
  });

  group('pinned pieceTreeTextBuffer search regressions', () {
    test('empty buffer #45892, invalid and empty query', () {
      final b = buffer('');
      expect(
        PieceTreeSearch.findMatches(b, const SearchParams('abc'), full(b)),
        isEmpty,
      );
      expect(const SearchParams('').parseSearchRequest(), isNull);
      expect(
        const SearchParams('[', isRegex: true).parseSearchRequest(),
        isNull,
      );
    });

    test('edited nodes do not split results #45770', () {
      final b = buffer(
        [
          'balabalababalabalababalabalaba',
          'balabalababalabalababalabalaba',
          '',
          '* [ ] task1',
          '* [x] task2 balabalaba',
          '* [ ] task 3',
        ].join('\n'),
      );
      b.delete(0, 62);
      b.delete(16, 1);
      b.insert(16, ' ');
      expect(
        coordinates(
          PieceTreeSearch.findMatches(
            b,
            const SearchParams('[', wordSeparators: ',./'),
            Range(1, 1, 4, 13),
            captureMatches: true,
          ),
        ),
        [(2, 3, 2, 4), (3, 3, 3, 4), (4, 3, 4, 4)],
      );
    });

    test('search from middle of edited line #2105', () {
      final b = buffer('def\ndbcabc');
      b.delete(4, 1);
      expect(
        coordinates(
          PieceTreeSearch.findMatches(
            b,
            const SearchParams('a'),
            Range(2, 3, 2, 6),
            captureMatches: true,
          ),
        ),
        [(2, 3, 2, 4)],
      );
      b.delete(4, 1);
      expect(
        coordinates(
          PieceTreeSearch.findMatches(
            b,
            const SearchParams('a'),
            Range(2, 2, 2, 5),
            captureMatches: true,
          ),
        ),
        [(2, 2, 2, 3)],
      );
    });

    test('match crossing piece boundary, bounded ranges, limit', () {
      final b = buffer('a');
      b.insert(1, 'bc abc');
      expect(
        coordinates(
          PieceTreeSearch.findMatches(
            b,
            const SearchParams('abc', matchCase: true),
            full(b),
            limitResultCount: 1,
          ),
        ),
        [(1, 1, 1, 4)],
      );
      expect(
        coordinates(
          PieceTreeSearch.findMatches(
            b,
            const SearchParams('abc'),
            Range(1, 3, 1, 8),
          ),
        ),
        [(1, 5, 1, 8)],
      );
      expect(
        PieceTreeSearch.findMatches(
          b,
          const SearchParams('abc'),
          full(b),
          limitResultCount: 0,
        ),
        isEmpty,
      );
    });

    test('bounded multiline match across inserted CRLF pieces', () {
      final b = buffer('xxab', '\r\n');
      b.insert(4, 'c\r\nabc');
      expect(
        coordinates(
          PieceTreeSearch.findMatches(
            b,
            const SearchParams('abc\nabc'),
            Range(1, 3, 2, 4),
          ),
        ),
        [(1, 3, 2, 4)],
      );
      expect(
        PieceTreeSearch.findMatches(
          b,
          const SearchParams('abc\nabc'),
          Range(1, 4, 2, 4),
        ),
        isEmpty,
      );
    });
  });

  group('pinned textModelSearch directional search', () {
    test(
      'next and previous wrap, skip an enclosing literal, and find nothing',
      () {
        final b = buffer('line line one\nline two\nthree');
        const query = SearchParams('line');
        expect(
          coordinate(
            PieceTreeSearch.findNextMatch(
              b,
              query,
              const Position(1, 1),
              false,
            ),
          ),
          (1, 1, 1, 5),
        );
        expect(
          coordinate(
            PieceTreeSearch.findNextMatch(
              b,
              query,
              const Position(1, 3),
              false,
            ),
          ),
          (1, 6, 1, 10),
        );
        expect(
          coordinate(
            PieceTreeSearch.findNextMatch(
              b,
              query,
              const Position(1, 10),
              false,
            ),
          ),
          (2, 1, 2, 5),
        );
        expect(
          coordinate(
            PieceTreeSearch.findNextMatch(
              b,
              query,
              const Position(3, 6),
              false,
            ),
          ),
          (1, 1, 1, 5),
        );
        expect(
          coordinate(
            PieceTreeSearch.findPreviousMatch(
              b,
              query,
              const Position(1, 1),
              false,
            ),
          ),
          (2, 1, 2, 5),
        );
        expect(
          coordinate(
            PieceTreeSearch.findPreviousMatch(
              b,
              query,
              const Position(1, 8),
              false,
            ),
          ),
          (1, 1, 1, 5),
        );
        expect(
          coordinate(
            PieceTreeSearch.findPreviousMatch(
              b,
              query,
              const Position(1, 3),
              false,
            ),
          ),
          (2, 1, 2, 5),
        );
        expect(
          coordinate(
            PieceTreeSearch.findPreviousMatch(
              b,
              query,
              const Position(2, 5),
              false,
            ),
          ),
          (2, 1, 2, 5),
        );
        for (final find in [
          PieceTreeSearch.findNextMatch,
          PieceTreeSearch.findPreviousMatch,
        ]) {
          expect(
            find(b, const SearchParams('absent'), const Position(1, 1), false),
            isNull,
          );
          expect(
            find(b, const SearchParams(''), const Position(1, 1), true),
            isNull,
          );
          expect(
            find(
              b,
              const SearchParams('[', isRegex: true),
              const Position(1, 1),
              true,
            ),
            isNull,
          );
          expect(
            () => find(b, query, const Position(0, 1), false),
            throwsRangeError,
          );
          expect(
            () => find(b, query, const Position(1, 100), false),
            throwsRangeError,
          );
        }
      },
    );

    test(
      'line anchors retain full-line context and previous truncates at cursor',
      () {
        final b = buffer('line line one\nline two\nthree');
        const start = SearchParams('^line', isRegex: true);
        const end = SearchParams(r'line$', isRegex: true);
        final ends = buffer('one line line\ntwo line\nthree');
        expect(
          coordinate(
            PieceTreeSearch.findNextMatch(
              b,
              start,
              const Position(1, 3),
              false,
            ),
          ),
          (2, 1, 2, 5),
        );
        expect(
          coordinate(
            PieceTreeSearch.findPreviousMatch(
              b,
              start,
              const Position(2, 1),
              false,
            ),
          ),
          (1, 1, 1, 5),
        );
        expect(
          coordinate(
            PieceTreeSearch.findNextMatch(
              ends,
              end,
              const Position(1, 4),
              false,
            ),
          ),
          (1, 10, 1, 14),
        );
        expect(
          coordinate(
            PieceTreeSearch.findPreviousMatch(
              ends,
              end,
              const Position(1, 8),
              false,
            ),
          ),
          (2, 5, 2, 9),
        );
      },
    );

    test(
      'captures, optional groups, whole words, and edited piece boundaries',
      () {
        final b = buffer('one line line\ntwo line\nthree');
        final next = PieceTreeSearch.findNextMatch(
          b,
          const SearchParams(r'(l(in)e)', isRegex: true),
          const Position(1, 1),
          true,
        );
        expect(coordinate(next), (1, 5, 1, 9));
        expect(next!.matches, ['line', 'line', 'in']);
        final previous = PieceTreeSearch.findPreviousMatch(
          b,
          const SearchParams(r'(l(in)e)', isRegex: true),
          const Position(1, 1),
          true,
        );
        expect(coordinate(previous), (2, 5, 2, 9));
        expect(previous!.matches, ['line', 'line', 'in']);
        expect(
          PieceTreeSearch.findNextMatch(
            b,
            const SearchParams('line'),
            const Position(1, 1),
            false,
          )!.matches,
          isNull,
        );
        final optional = buffer('b');
        expect(
          PieceTreeSearch.findPreviousMatch(
            optional,
            const SearchParams(r'(a)?b', isRegex: true),
            const Position(1, 2),
            true,
          )!.matches,
          ['b', null],
        );
        final edited = buffer('foo foo');
        edited.delete(0, 7);
        edited.insert(0, 'foo bar foo');
        expect(
          coordinate(
            PieceTreeSearch.findNextMatch(
              edited,
              const SearchParams('foo', wordSeparators: separators),
              const Position(1, 3),
              false,
            ),
          ),
          (1, 9, 1, 12),
        );
        expect(
          coordinate(
            PieceTreeSearch.findPreviousMatch(
              edited,
              const SearchParams('foo', wordSeparators: separators),
              const Position(1, 9),
              false,
            ),
          ),
          (1, 1, 1, 4),
        );
        final split = buffer('li');
        split.insert(2, 'ne');
        expect(
          coordinate(
            PieceTreeSearch.findNextMatch(
              split,
              const SearchParams('line'),
              const Position(1, 1),
              false,
            ),
          ),
          (1, 1, 1, 5),
        );
        expect(
          coordinate(
            PieceTreeSearch.findPreviousMatch(
              split,
              const SearchParams('line'),
              const Position(1, 5),
              false,
            ),
          ),
          (1, 1, 1, 5),
        );
        final word = buffer('fooBar foo');
        expect(
          coordinate(
            PieceTreeSearch.findNextMatch(
              word,
              const SearchParams('foo', wordSeparators: separators),
              const Position(1, 1),
              false,
            ),
          ),
          (1, 8, 1, 11),
        );
      },
    );

    for (final eol in ['\n', '\r\n']) {
      test(
        'multiline search, start inside match, wrap and captures ($eol)',
        () {
          final b = buffer('one line line${eol}two line${eol}three', eol);
          const query = SearchParams(r'(l(in)e)\n', isRegex: true);
          final first = PieceTreeSearch.findNextMatch(
            b,
            query,
            const Position(1, 1),
            true,
          );
          expect(coordinate(first), (1, 10, 2, 1));
          expect(first!.matches, ['line\n', 'line', 'in']);
          final second = PieceTreeSearch.findNextMatch(
            b,
            query,
            const Position(1, 11),
            true,
          );
          expect(coordinate(second), (2, 5, 3, 1));
          expect(second!.matches, ['line\n', 'line', 'in']);
          expect(
            coordinate(
              PieceTreeSearch.findNextMatch(
                b,
                query,
                const Position(3, 6),
                false,
              ),
            ),
            (1, 10, 2, 1),
          );
          expect(
            coordinate(
              PieceTreeSearch.findPreviousMatch(
                b,
                query,
                const Position(2, 1),
                true,
              ),
            ),
            (1, 10, 2, 1),
          );
          final wrapped = PieceTreeSearch.findPreviousMatch(
            b,
            query,
            const Position(1, 11),
            true,
          );
          expect(coordinate(wrapped), (2, 5, 3, 1));
          expect(wrapped!.matches, ['line\n', 'line', 'in']);
          expect(
            coordinate(
              PieceTreeSearch.findPreviousMatch(
                b,
                query,
                const Position(3, 1),
                false,
              ),
            ),
            (2, 5, 3, 1),
          );
          expect(
            PieceTreeSearch.findNextMatch(
              b,
              const SearchParams(r'\r\n', isRegex: true),
              const Position(1, 1),
              true,
            ),
            isNull,
          );
        },
      );
    }

    test('multiline ^ is anchored to the line, not the cursor', () {
      final b = buffer('line line one\nline two\nline three\nline four');
      const query = SearchParams(r'^line.*\nline', isRegex: true);
      expect(
        coordinate(
          PieceTreeSearch.findNextMatch(b, query, const Position(1, 3), false),
        ),
        (2, 1, 3, 5),
      );
      expect(
        coordinate(
          PieceTreeSearch.findNextMatch(b, query, const Position(4, 5), false),
        ),
        (1, 1, 2, 5),
      );
    });

    test('multiline UTF-16 mapping and zero-width CRLF boundary', () {
      final b = buffer('😀\r\n😀', '\r\n');
      const text = SearchParams(r'(😀)\n', isRegex: true);
      final match = PieceTreeSearch.findNextMatch(
        b,
        text,
        const Position(1, 1),
        true,
      );
      expect(coordinate(match), (1, 1, 2, 1));
      expect(match!.matches, ['😀\n', '😀']);
      expect(
        coordinate(
          PieceTreeSearch.findPreviousMatch(
            b,
            text,
            const Position(2, 1),
            false,
          ),
        ),
        (1, 1, 2, 1),
      );
      const boundary = SearchParams(r'(?=\n)', isRegex: true);
      expect(
        coordinate(
          PieceTreeSearch.findNextMatch(
            b,
            boundary,
            const Position(1, 3),
            false,
          ),
        ),
        (1, 3, 1, 3),
      );
      expect(
        coordinate(
          PieceTreeSearch.findPreviousMatch(
            b,
            boundary,
            const Position(1, 1),
            false,
          ),
        ),
        (1, 3, 1, 3),
      );
    });

    test('UTF-16 columns and zero-width matches skip surrogate interiors', () {
      final b = buffer('😀 foo 😀 foo');
      const query = SearchParams('foo');
      expect(
        coordinate(
          PieceTreeSearch.findNextMatch(b, query, const Position(1, 5), false),
        ),
        (1, 11, 1, 14),
      );
      expect(
        coordinate(
          PieceTreeSearch.findPreviousMatch(
            b,
            query,
            const Position(1, 11),
            false,
          ),
        ),
        (1, 4, 1, 7),
      );
      final zero = buffer('1😀1');
      const empty = SearchParams('()', isRegex: true);
      expect(
        coordinate(
          PieceTreeSearch.findNextMatch(
            zero,
            empty,
            const Position(1, 2),
            false,
          ),
        ),
        (1, 2, 1, 2),
      );
      expect(
        coordinate(
          PieceTreeSearch.findNextMatch(
            zero,
            empty,
            const Position(1, 4),
            false,
          ),
        ),
        (1, 4, 1, 4),
      );
      expect(
        coordinate(
          PieceTreeSearch.findPreviousMatch(
            zero,
            empty,
            const Position(1, 4),
            false,
          ),
        ),
        (1, 4, 1, 4),
      );
      expect(
        coordinate(
          PieceTreeSearch.findPreviousMatch(
            zero,
            empty,
            const Position(1, 1),
            false,
          ),
        ),
        (1, 1, 1, 1),
      );
      expect(
        PieceTreeSearch.findNextMatch(
          zero,
          empty,
          const Position(1, 5),
          true,
        )!.matches,
        ['', ''],
      );
    });
  });
}
