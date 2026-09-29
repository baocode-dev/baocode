/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../../../../../lib/ide/editor/monaco/LICENSE.txt.
 *--------------------------------------------------------------------------------------------*/
// The upstream group mirrors every case in VS Code
// src/vs/editor/test/common/core/lineTokens.test.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971. Additional cases exercise APIs not
// covered there, immutable ownership, logical bidi spans and UTF-16 editing.

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/editor/monaco/vs/editor/common/tokens/line_tokens.dart';
import 'package:monad/ide/editor/monaco/vs/editor/common/encoded_token_attributes.dart';

final class _Codec implements ILanguageIdCodec {
  const _Codec();

  static const languages = [
    'vs.editor.nullLanguage',
    'plaintext',
    'dart',
    'html',
  ];

  @override
  int encodeLanguageId(String languageId) {
    final index = languages.indexOf(languageId);
    return index < 0 ? 0 : index;
  }

  @override
  String decodeLanguageId(int languageId) =>
      languageId >= 0 && languageId < languages.length
      ? languages[languageId]
      : languages[0];
}

const _codec = _Codec();
const _text = 'Hello world, this is a lovely day';
const _ends = [6, 13, 18, 21, 23, 30, 33];

LineTokens _example() => LineTokens(
  [
    for (var i = 0; i < _ends.length; i++) ...[
      _ends[i],
      (i + 1) << MetadataConsts.foregroundOffset,
    ],
  ],
  _text,
  _codec,
);

String _render(LineTokens tokens) {
  final result = StringBuffer();
  tokens.forEach(
    (i) => result.write('${tokens.getTokenText(i)}(${tokens.getMetadata(i)})'),
  );
  return result.toString();
}

List<(int, int)> _view(IViewLineTokens tokens) => [
  for (var i = 0; i < tokens.getCount(); i++)
    (tokens.getEndOffset(i), tokens.getForeground(i)),
];

List<(int, int)> _lengths(TokenArray tokens) =>
    tokens.map((range, token) => (token.length, token.metadata));

List<String> _texts(IViewLineTokens tokens) => [
  for (var i = 0; i < tokens.getCount(); i++) tokens.getTokenText(i),
];

void main() {
  group('upstream LineTokens tests', () {
    const rendered =
        'Hello (32768)world, (65536)this (98304)is (131072)a (163840)lovely (196608)day(229376)';

    test('withInserted 1', () {
      final tokens = _example();
      expect(_render(tokens), rendered);
      final updated = tokens.withInserted([
        (offset: 0, text: '1', tokenMetadata: 0),
        (offset: 6, text: '2', tokenMetadata: 0),
        (offset: 9, text: '3', tokenMetadata: 0),
      ]);
      expect(
        _render(updated),
        '1(0)Hello (32768)2(0)wor(65536)3(0)ld, (65536)this (98304)is (131072)a (163840)lovely (196608)day(229376)',
      );
      expect(_render(tokens), rendered);
    });

    test('withInserted (tokens at the same position)', () {
      final tokens = _example();
      expect(_render(tokens), rendered);
      expect(
        _render(
          tokens.withInserted([
            (offset: 0, text: '1', tokenMetadata: 0),
            (offset: 0, text: '2', tokenMetadata: 0),
            (offset: 0, text: '3', tokenMetadata: 0),
          ]),
        ),
        '1(0)2(0)3(0)Hello (32768)world, (65536)this (98304)is (131072)a (163840)lovely (196608)day(229376)',
      );
    });

    test('withInserted (tokens at the end)', () {
      final tokens = _example();
      expect(_render(tokens), rendered);
      expect(
        _render(
          tokens.withInserted([
            (offset: _text.length - 1, text: '1', tokenMetadata: 0),
            (offset: _text.length, text: '2', tokenMetadata: 0),
          ]),
        ),
        'Hello (32768)world, (65536)this (98304)is (131072)a (163840)lovely (196608)da(229376)1(0)y(229376)2(0)',
      );
    });

    test('basics', () {
      final tokens = _example();
      expect(tokens.getLineContent(), _text);
      expect(tokens.getLineContent().length, 33);
      expect(tokens.getTextLength(), 33);
      expect(tokens.getCount(), 7);
      for (var i = 0; i < _ends.length; i++) {
        expect(tokens.getStartOffset(i), i == 0 ? 0 : _ends[i - 1]);
        expect(tokens.getEndOffset(i), _ends[i]);
      }
    });

    test('findToken', () {
      final tokens = _example();
      for (var offset = 0; offset <= 34; offset++) {
        final found = _ends.indexWhere((end) => end > offset);
        expect(
          tokens.findTokenIndexAtOffset(offset),
          found < 0 ? 6 : found,
          reason: 'offset $offset',
        );
      }
    });

    test('inflate', () {
      final tokens = _example();
      expect(tokens.inflate(), same(tokens));
      expect(_view(tokens.inflate()), [
        (6, 1),
        (13, 2),
        (18, 3),
        (21, 4),
        (23, 5),
        (30, 6),
        (33, 7),
      ]);
    });

    test('sliceAndInflate', () {
      final tokens = _example();
      final cases = <(int, int, int, List<(int, int)>)>[
        (
          0,
          33,
          0,
          [(6, 1), (13, 2), (18, 3), (21, 4), (23, 5), (30, 6), (33, 7)],
        ),
        (
          0,
          32,
          0,
          [(6, 1), (13, 2), (18, 3), (21, 4), (23, 5), (30, 6), (32, 7)],
        ),
        (0, 30, 0, [(6, 1), (13, 2), (18, 3), (21, 4), (23, 5), (30, 6)]),
        (0, 30, 1, [(7, 1), (14, 2), (19, 3), (22, 4), (24, 5), (31, 6)]),
        (6, 18, 0, [(7, 2), (12, 3)]),
        (7, 18, 0, [(6, 2), (11, 3)]),
        (6, 17, 0, [(7, 2), (11, 3)]),
        (6, 19, 0, [(7, 2), (12, 3), (13, 4)]),
      ];
      for (final (start, end, delta, expected) in cases) {
        expect(_view(tokens.sliceAndInflate(start, end, delta)), expected);
      }
    });
  });

  group('construction, metadata and immutable ownership', () {
    test('default token for nonempty and empty lines', () {
      expect(LineTokens.defaultTokenMetadata, 0x02008000);
      for (final text in ['', '😀a']) {
        final tokens = LineTokens.createEmpty(text, _codec);
        expect(tokens.getCount(), 1);
        expect(tokens.getEndOffset(0), text.length);
        expect(tokens.getTokenText(0), text);
        expect(tokens.getStandardTokenType(0), StandardTokenType.other);
        expect(tokens.getForeground(0), ColorId.defaultForeground);
        expect(
          TokenMetadata.getBackground(tokens.getMetadata(0)),
          ColorId.defaultBackground,
        );
        expect(tokens.getLanguageId(0), 'vs.editor.nullLanguage');
        expect(tokens.findTokenIndexAtOffset(100), 0);
      }
    });

    test('copies input buffers and normalizes unsigned metadata', () {
      final buffer = Uint32List.fromList([1, 0xffffffff, 3, 2]);
      final tokens = LineTokens(buffer, 'a😀', _codec);
      final slice = tokens.sliceZeroCopy((start: 0, endExclusive: 1));
      buffer[0] = 0;
      buffer[1] = 0;
      expect(tokens.getEndOffset(0), 1);
      expect(tokens.getMetadata(0), 0xffffffff);
      expect(tokens.getForeground(0), 511);
      expect(slice.getMetadata(0), 0xffffffff);
      expect(LineTokens([1, -1], 'x', _codec).getMetadata(0), 0xffffffff);
      expect(LineTokens([1, 0x100000001], 'x', _codec).getMetadata(0), 1);
    });

    test('creates text/metadata without merging empty or equal tokens', () {
      final data = <TokenText>[
        (text: 'a', metadata: 7),
        (text: '', metadata: 7),
        (text: '😀', metadata: 7),
      ];
      final tokens = LineTokens.createFromTextAndMetadata(data, _codec);
      data.clear();
      expect(tokens.getLineContent(), 'a😀');
      expect(tokens.getCount(), 3);
      expect([for (var i = 0; i < 3; i++) tokens.getEndOffset(i)], [1, 1, 3]);
      expect(_texts(tokens), ['a', '', '😀']);
      final noTokens = LineTokens.createFromTextAndMetadata([], _codec);
      expect(noTokens.getCount(), 0);
      expect(noTokens.findTokenIndexAtOffset(0), 0);
      expect(
        _lengths(noTokens.getTokensInRange((start: 0, endExclusive: 0))),
        isEmpty,
      );
      expect(
        noTokens
            .withInserted([(offset: 0, text: 'x', tokenMetadata: 7)])
            .getTokenText(0),
        'x',
      );
    });

    test('converts tokenizer start offsets in place, retaining metadata', () {
      final tokens = Uint32List.fromList([0, 0xffffffff, 1, 2, 3, 3]);
      LineTokens.convertToEndOffset(tokens, 6);
      expect(tokens, [1, 0xffffffff, 3, 2, 6, 3]);
      final single = Uint32List.fromList([0, 99]);
      LineTokens.convertToEndOffset(single, 0);
      expect(single, [0, 99]);
      LineTokens.convertToEndOffset(Uint32List(0), 0);
      expect(
        () => LineTokens.convertToEndOffset(Uint32List(1), 0),
        throwsArgumentError,
      );
      expect(
        () => LineTokens.convertToEndOffset(Uint32List(2), -1),
        throwsRangeError,
      );
    });

    test('delegates language, rendering and token iteration in slices too', () {
      final metadata =
          2 |
          (StandardTokenType.comment << 8) |
          (15 << 11) |
          (3 << 15) |
          (240 << 24);
      final tokens = LineTokens.createFromTextAndMetadata([
        (text: 'x', metadata: 1),
        (text: 'comment', metadata: metadata),
      ], _codec);
      final slice = tokens.sliceAndInflate(2, 5, 4);
      for (final (view, index) in <(IViewLineTokens, int)>[
        (tokens, 1),
        (slice, 0),
      ]) {
        expect(view.languageIdCodec, same(_codec));
        expect(view.getLanguageId(index), 'dart');
        expect(view.getStandardTokenType(index), StandardTokenType.comment);
        expect(view.getMetadata(index), metadata);
        expect(view.getForeground(index), 3);
        expect(view.getClassName(index), 'mtk3 mtki mtkb mtku mtks');
        expect(
          view.getInlineStyle(index, ['', '#111', '#222', '#333']),
          'color: #333;font-style: italic;font-weight: bold;text-decoration: underline line-through;',
        );
        final presentation = view.getPresentation(index);
        expect(presentation.foreground, 3);
        expect([
          presentation.italic,
          presentation.bold,
          presentation.underline,
          presentation.strikethrough,
        ], everyElement(isTrue));
        final indices = <int>[];
        view.forEach(indices.add);
        expect(indices, List.generate(view.getCount(), (i) => i));
      }
      expect(slice.getLineContent(), 'omm');
      expect(slice.getTokenText(0), 'omm');
      expect(slice.getEndOffset(0), 7);
      expect(tokens.toString(), '[x]{mtk0}[comment]{mtk3 mtki mtkb mtku mtks}');
    });

    test('rejects malformed packed input', () {
      for (final (pairs, text) in <(List<int>, String)>[
        ([1], 'a'),
        ([], 'a'),
        ([2, 0], 'a'),
        ([-1, 0, 1, 0], 'a'),
        ([2, 0, 1, 0, 3, 0], 'abc'),
        ([1, 0], 'ab'),
      ]) {
        expect(() => LineTokens(pairs, text, _codec), throwsArgumentError);
      }
    });
  });

  group('lookup, slices and equality', () {
    test('retains boundary affinity, including repeated and empty ends', () {
      final tokens = _example();
      expect(tokens.findTokenIndexAtOffset(-1), 0);
      expect(tokens.findTokenIndexAtOffset(1000), 6);
      expect(LineTokens.findIndexInTokensArray([], 0), 0);
      expect(LineTokens.findIndexInTokensArray([0, 1, 0, 2, 0, 3, 1, 4], 0), 2);
      final slice = tokens.sliceAndInflate(6, 18, 3);
      expect(slice.getLineContent(), 'world, this ');
      expect(slice.findTokenIndexAtOffset(3), 0);
      expect(slice.findTokenIndexAtOffset(9), 0);
      expect(slice.findTokenIndexAtOffset(10), 1);
      expect(
        slice.findTokenIndexAtOffset(15),
        2,
      ); // Not clamped to slice count.
      expect(slice.findTokenIndexAtOffset(2), -1);
      expect(_texts(slice), ['world, ', 'this ']);
      expect(_view(tokens.sliceAndInflate(6, 18, -2)), [(5, 2), (10, 3)]);
    });

    test('preserves upstream empty-slice token counts', () {
      final tokens = _example();
      expect(tokens.sliceAndInflate(0, 0, 0).getCount(), 0);
      expect(tokens.sliceAndInflate(6, 6, 0).getCount(), 0);
      final inside = tokens.sliceAndInflate(7, 7, 2);
      expect(inside.getCount(), 1);
      expect(inside.getTokenText(0), '');
      expect(inside.getEndOffset(0), 2);
      expect(tokens.sliceAndInflate(33, 33, 0).getCount(), 1);
      expect(
        LineTokens.createEmpty('', _codec).sliceAndInflate(0, 0, 0).getCount(),
        0,
      );
    });

    test(
      'equals compares source text/count, selected pairs, and slice geometry',
      () {
        final a = LineTokens([2, 1, 4, 2], 'abcd', _codec);
        final b = LineTokens([2, 9, 4, 2], 'abcd', _codec);
        final c = LineTokens([2, 1, 4, 2], 'xbcd', _codec);
        expect(a.equals(LineTokens([2, 1, 4, 2], 'abcd', _codec)), isTrue);
        expect(a.equals(b), isFalse);
        expect(a.equals(c), isFalse);
        expect(a.equals(LineTokens([4, 2], 'abcd', _codec)), isFalse);
        expect(a.slicedEquals(b, 1, 1), isTrue);
        expect(a.slicedEquals(c, 1, 1), isFalse);
        final slice = a.sliceAndInflate(2, 4, 0);
        expect(slice.equals(b.sliceAndInflate(2, 4, 0)), isTrue);
        expect(slice.equals(c.sliceAndInflate(2, 4, 0)), isFalse);
        expect(slice.equals(a.sliceAndInflate(2, 4, 1)), isFalse);
        expect(slice.equals(a.sliceAndInflate(2, 3, 0)), isFalse);
        expect(slice.equals(a.sliceAndInflate(1, 4, 0)), isFalse);
        expect(a.equals(a.sliceAndInflate(0, 4, 0)), isFalse);
        expect(a.sliceAndInflate(0, 4, 0).equals(a), isFalse);
      },
    );

    test('rejects invalid slice geometry without changing text', () {
      final tokens = _example();
      for (final (start, end) in [(-1, 3), (4, 3), (0, 34)]) {
        expect(() => tokens.sliceAndInflate(start, end, 0), throwsRangeError);
      }
      expect(tokens.getLineContent(), _text);
    });
  });

  group('logical bidi and UTF-16 updates', () {
    test('preserves Hebrew, Arabic, isolates and emoji token order', () {
      final tokens = LineTokens.createFromTextAndMetadata([
        (text: 'ab ', metadata: 1 << 15),
        (text: '\u{2067}אב', metadata: 2 << 15),
        (text: '😀ع\u{2069}', metadata: 3 << 15),
        (text: ' cd', metadata: 4 << 15),
      ], _codec);
      expect(tokens.getTextLength(), 13);
      expect(_view(tokens), [(3, 1), (6, 2), (10, 3), (13, 4)]);
      expect(_texts(tokens), ['ab ', '\u{2067}אב', '😀ع\u{2069}', ' cd']);
      expect(tokens.findTokenIndexAtOffset(5), 1);
      expect(tokens.findTokenIndexAtOffset(6), 2);
      expect(tokens.findTokenIndexAtOffset(7), 2);
      final slice = tokens.sliceZeroCopy((start: 4, endExclusive: 9));
      expect(slice.getLineContent(), 'אב😀ع');
      expect(_texts(slice), ['אב', '😀ع']);
      expect(_view(slice), [(2, 2), (5, 3)]);
      final updated = tokens.withInserted([
        (offset: 6, text: 'Z', tokenMetadata: 5 << 15),
        (offset: 8, text: '\u{200f}', tokenMetadata: 6 << 15),
      ]);
      expect(updated.getLineContent(), 'ab \u{2067}אבZ😀\u{200f}ع\u{2069} cd');
      expect(_texts(updated), [
        'ab ',
        '\u{2067}אב',
        'Z',
        '😀',
        '\u{200f}',
        'ع\u{2069}',
        ' cd',
      ]);
      expect(_view(updated), [
        (3, 1),
        (6, 2),
        (7, 5),
        (9, 3),
        (10, 6),
        (12, 3),
        (15, 4),
      ]);
      expect(tokens.getTextLength(), 13);
    });

    test('offsets can split surrogate pairs and combining sequences', () {
      final tokens = LineTokens([4, 10], '😀é', _codec);
      expect(tokens.getTextLength(), 4);
      final slice = tokens.sliceZeroCopy((start: 1, endExclusive: 3));
      expect(slice.getTokenText(0).codeUnits, [0xde00, 0x65]);
      final updated = tokens.withInserted([
        (offset: 1, text: 'x', tokenMetadata: 11),
      ]);
      expect(updated.getLineContent().codeUnits, [
        0xd83d,
        0x78,
        0xde00,
        0x65,
        0x301,
      ]);
      expect(
        [for (var i = 0; i < updated.getCount(); i++) updated.getEndOffset(i)],
        [1, 2, 5],
      );
      expect(updated.getMetadata(2), 10);
    });

    test('empty inserts and repeated offsets retain segmentation', () {
      final tokens = LineTokens([2, 1], 'ab', _codec);
      expect(tokens.withInserted([]), same(tokens));
      final updated = tokens.withInserted([
        (offset: 1, text: '', tokenMetadata: 2),
        (offset: 1, text: 'x', tokenMetadata: 1),
        (offset: 1, text: 'y', tokenMetadata: 1),
        (offset: 2, text: '', tokenMetadata: 3),
      ]);
      expect(_render(updated), 'a(1)(2)x(1)y(1)b(1)(3)');
      final empty = LineTokens.createEmpty(
        '',
        _codec,
      ).withInserted([(offset: 0, text: '😀', tokenMetadata: 9)]);
      expect(_render(empty), '(33587200)😀(9)');
      expect(empty.getEndOffset(1), 2);
    });

    test('insertion validation is atomic', () {
      final tokens = LineTokens([2, 1], 'ab', _codec);
      for (final insertions in <List<InsertedToken>>[
        [(offset: -1, text: 'x', tokenMetadata: 0)],
        [(offset: 3, text: 'x', tokenMetadata: 0)],
        [
          (offset: 2, text: 'x', tokenMetadata: 0),
          (offset: 1, text: 'y', tokenMetadata: 0),
        ],
      ]) {
        expect(() => tokens.withInserted(insertions), throwsArgumentError);
        expect(tokens.getLineContent(), 'ab');
      }
    });

    test(
      'seeded insertions and slices agree with a UTF-16 per-unit oracle',
      () {
        final random = Random(598);
        const pieces = ['a', '😀', 'אב', '\u{2067}ع\u{2069}', 'é', '\t'];
        for (var trial = 0; trial < 200; trial++) {
          final data = <TokenText>[
            for (var i = 0, n = random.nextInt(5) + 1; i < n; i++)
              (text: pieces[random.nextInt(pieces.length)], metadata: i + 1),
          ];
          final tokens = LineTokens.createFromTextAndMetadata(data, _codec);
          final originalText = tokens.getLineContent();
          final originalUnits = originalText.codeUnits;
          final originalMetadata = [
            for (final part in data)
              ...List.filled(part.text.length, part.metadata),
          ];
          // Sorting offsets before creating inserts keeps same-offset input order.
          final offsets = List.generate(
            random.nextInt(5),
            (_) => random.nextInt(originalText.length + 1),
          )..sort();
          final inserts = <InsertedToken>[
            for (var i = 0; i < offsets.length; i++)
              (
                offset: offsets[i],
                text: pieces[random.nextInt(pieces.length)],
                tokenMetadata: 100 + i,
              ),
          ];
          final expectedUnits = <int>[];
          final expectedMetadata = <int>[];
          var insertionIndex = 0;
          for (var offset = 0; offset <= originalText.length; offset++) {
            while (insertionIndex < inserts.length &&
                inserts[insertionIndex].offset == offset) {
              final insert = inserts[insertionIndex++];
              expectedUnits.addAll(insert.text.codeUnits);
              expectedMetadata.addAll(
                List.filled(insert.text.length, insert.tokenMetadata),
              );
            }
            if (offset < originalText.length) {
              expectedUnits.add(originalUnits[offset]);
              expectedMetadata.add(originalMetadata[offset]);
            }
          }
          final updated = tokens.withInserted(inserts);
          expect(
            updated.getLineContent().codeUnits,
            expectedUnits,
            reason: 'trial $trial',
          );
          final actualMetadata = [
            for (var i = 0; i < updated.getCount(); i++)
              ...List.filled(
                updated.getEndOffset(i) - updated.getStartOffset(i),
                updated.getMetadata(i),
              ),
          ];
          expect(actualMetadata, expectedMetadata, reason: 'trial $trial');
          expect(tokens.getLineContent(), originalText);
          final start = random.nextInt(updated.getTextLength() + 1);
          final end =
              start + random.nextInt(updated.getTextLength() - start + 1);
          final slice = updated.sliceAndInflate(start, end, 3);
          expect(
            slice.getLineContent().codeUnits,
            expectedUnits.sublist(start, end),
          );
          expect(
            _texts(slice).join().codeUnits,
            expectedUnits.sublist(start, end),
          );
          expect(
            slice.getCount() == 0
                ? 0
                : slice.getEndOffset(slice.getCount() - 1) - 3,
            end - start,
          );
          final extracted = updated.getTokensInRange((
            start: start,
            endExclusive: end,
          ));
          expect(
            extracted
                .map(
                  (range, token) => List.filled(token.length, token.metadata),
                )
                .expand((items) => items),
            expectedMetadata.sublist(start, end),
          );
        }
      },
    );
  });

  group('TokenArray and builder', () {
    test('snapshots caller arrays and builder state', () {
      final input = [TokenInfo(2, 1)];
      final array = TokenArray.create(input);
      input.add(TokenInfo(3, 2));
      expect(_lengths(array), [(2, 1)]);
      final builder = TokenArrayBuilder()..add(2, 1);
      final built = builder.build();
      builder.add(3, 2);
      expect(_lengths(built), [(2, 1)]);
      expect(_lengths(builder.build()), [(2, 1), (3, 2)]);
      final mapped = built.map((range, token) => token);
      mapped.clear();
      expect(_lengths(built), [(2, 1)]);
      expect(() => TokenInfo(-1, 0), throwsRangeError);
    });

    test('round-trips lengths, empty tokens and UTF-16 text', () {
      final tokens = LineTokens.createFromTextAndMetadata([
        (text: 'אב', metadata: 1),
        (text: '', metadata: 2),
        (text: '😀x', metadata: 3),
      ], _codec);
      final array = TokenArray.fromLineTokens(tokens);
      expect(_lengths(array), [(2, 1), (0, 2), (3, 3)]);
      expect(array.map((range, token) => range), [
        (start: 0, endExclusive: 2),
        (start: 2, endExclusive: 2),
        (start: 2, endExclusive: 5),
      ]);
      final ranges = <TokenOffsetRange>[];
      array.forEach((range, token) => ranges.add(range));
      expect(ranges, array.map((range, token) => range));
      expect(
        array.toLineTokens(tokens.getLineContent(), _codec).equals(tokens),
        isTrue,
      );
      expect(() => array.toLineTokens('abcd', _codec), throwsArgumentError);
      expect(() => array.toLineTokens('abcdef', _codec), throwsArgumentError);
      expect(TokenArray.create([]).toLineTokens('', _codec).getCount(), 0);
    });

    test('slice and range extraction clip boundaries without coalescing', () {
      final tokens = LineTokens([2, 1, 5, 2, 7, 2], 'ab😀xyz', _codec);
      final array = TokenArray.fromLineTokens(tokens);
      for (final (start, end, expected) in <(int, int, List<(int, int)>)>[
        (0, 7, [(2, 1), (3, 2), (2, 2)]),
        (1, 6, [(1, 1), (3, 2), (1, 2)]),
        (2, 5, [(3, 2)]),
        (-10, 20, [(2, 1), (3, 2), (2, 2)]),
        (7, 8, []),
        (-5, 0, []),
      ]) {
        final range = (start: start, endExclusive: end);
        expect(_lengths(array.slice(range)), expected);
        expect(_lengths(tokens.getTokensInRange(range)), expected);
      }
      expect(_lengths(array.slice((start: 3, endExclusive: 3))), [(0, 2)]);
      expect(
        _lengths(tokens.getTokensInRange((start: 3, endExclusive: 3))),
        isEmpty,
      );
      expect(_lengths(array.slice((start: 2, endExclusive: 2))), isEmpty);
      expect(
        () => array.slice((start: 4, endExclusive: 3)),
        throwsArgumentError,
      );
      expect(
        () => tokens.getTokensInRange((start: 4, endExclusive: 3)),
        throwsArgumentError,
      );
    });

    test(
      'append returns an independent sequence without merging boundaries',
      () {
        final first = TokenArray.create([TokenInfo(1, 1)]);
        final second = TokenArray.create([TokenInfo(0, 1), TokenInfo(2, 1)]);
        expect(_lengths(first.append(second)), [(1, 1), (0, 1), (2, 1)]);
        expect(_lengths(first), [(1, 1)]);
        expect(_lengths(second), [(0, 1), (2, 1)]);
        expect(_lengths(first.append(TokenArray.create([]))), [(1, 1)]);
      },
    );
  });
}
