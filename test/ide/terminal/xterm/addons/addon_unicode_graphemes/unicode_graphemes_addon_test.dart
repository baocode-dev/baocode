// Copyright (c) 2019 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See
// lib/ide/terminal/xterm/addons/addon_unicode_graphemes/LICENSE.
// Adapted from xterm.js
// addons/addon-unicode-graphemes/test/UnicodeGraphemesAddon.test.ts (c58ea36).
//
// Upstream's test is a Playwright test in the browser terminal; its
// assertions run here against a UnicodeService behind a stand-in terminal.
// The other groups are new (not upstream): the addon's dispose, the
// provider without grapheme handling, the trie properties, and tiny-inflate.

import 'dart:convert';
import 'dart:io' show ZLibEncoder;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/terminal/xterm/addons/addon_unicode_graphemes/third_party/tiny_inflate.dart';
import 'package:monad/ide/terminal/xterm/addons/addon_unicode_graphemes/third_party/unicode_properties.dart'
    as uc;
import 'package:monad/ide/terminal/xterm/addons/addon_unicode_graphemes/unicode_grapheme_provider.dart';
import 'package:monad/ide/terminal/xterm/addons/addon_unicode_graphemes/unicode_graphemes_addon.dart';
import 'package:monad/ide/terminal/xterm/common/input/unicode_v6.dart';
import 'package:monad/ide/terminal/xterm/common/services/unicode_service.dart';
import 'package:monad/ide/terminal/xterm/typings/xterm_headless.dart';

/// `Terminal.unicode` over the core's UnicodeService, as the public terminal
/// hands it out.
class _UnicodeHandling implements IUnicodeHandling {
  _UnicodeHandling(this._service);

  final UnicodeService _service;

  @override
  void register(IUnicodeVersionProvider provider) =>
      _service.register(provider);

  @override
  List<String> get versions => _service.versions;

  @override
  String get activeVersion => _service.activeVersion;

  @override
  set activeVersion(String version) => _service.activeVersion = version;
}

/// A terminal with only [unicode]; the addon uses nothing else.
class _TestTerminal implements Terminal {
  _TestTerminal(this.unicode);

  @override
  final IUnicodeHandling unicode;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late UnicodeService unicodeService;
  late _TestTerminal term;

  setUp(() {
    // CoreTerminal registers V6 first.
    unicodeService = UnicodeService()..register(UnicodeV6());
    term = _TestTerminal(_UnicodeHandling(unicodeService));
  });

  tearDown(() {
    unicodeService.dispose();
  });

  group('UnicodeGraphemesAddon', () {
    late UnicodeGraphemesAddon unicode;

    setUp(() {
      unicode = UnicodeGraphemesAddon();
      unicode.activate(term);
    });

    tearDown(() {
      unicode.dispose();
    });

    int evalWidth(String str) => unicodeService.getStringCellWidth(str);
    const ourVersion = '15-graphemes';
    test('wcwidth V15 emoji test', () {
      // should have loaded '15-graphemes'
      expect(term.unicode.versions, equals(['6', '15', '15-graphemes']));
      // switch should not throw
      term.unicode.activeVersion = ourVersion;
      expect(term.unicode.activeVersion, ourVersion);
      expect(
        evalWidth(
          '\u{1F923}\u{1F923}\u{1F923}\u{1F923}\u{1F923}\u{1F923}\u{1F923}\u{1F923}\u{1F923}\u{1F923}',
        ),
        20,
        reason: '10 emoji - width 10 in V6; 20 in V11 or later',
      );
      expect(
        evalWidth('\u{1F476}\u{1F3FF}\u{1F476}'),
        4,
        reason: 'baby with emoji modifier fitzpatrick type-6; baby',
      );
      expect(
        evalWidth('\u{1F469}\u{200d}\u{1f469}\u{200d}\u{1f466}'),
        2,
        reason: 'woman+zwj+woman+zwj+boy',
      );
      expect(
        evalWidth('=\u{1F3CB}\u{FE0F}=\u{F3CB}\u{1F3FE}\u{200D}\u{2640}='),
        7,
        reason: 'person lifting weights (plain, emoji); woman lighting weights, medium dark',
      );
      expect(
        evalWidth(
          '\u{1F469}\u{1F469}\u{200D}\u{1F393}\u{1F468}\u{1F3FF}\u{200D}\u{1F393}',
        ),
        6,
        reason: 'woman; woman student; man student dark',
      );
      expect(
        evalWidth('\u{1f1f3}\u{1f1f4}/'),
        3,
        reason: 'regional indicator symbol letters N and O, cluster',
      );
      expect(
        evalWidth('\u{1f1f3}/\u{1f1f4}'),
        3,
        reason: 'regional indicator symbol letters N and O, separated',
      );
      expect(
        evalWidth('\u{0061}\u{0301}'),
        1,
        reason: 'letter a with acute accent',
      );
      expect(
        evalWidth('{\u{1100}\u{1161}\u{11a8}\u{1100}\u{1161}}'),
        6,
        reason: 'Korean Jamo',
      );
      expect(
        evalWidth('\u{AC00}=\u{D685}='),
        6,
        reason: 'Hangul syllables (pre-composed)',
      );
      expect(
        evalWidth('(\u{26b0}\u{fe0e})'),
        3,
        reason: 'coffin with text presentation',
      );
      expect(
        evalWidth('(\u{26b0}\u{fe0f})'),
        4,
        reason: 'coffin with emoji presentation',
      );
      expect(
        evalWidth(
          '<E\u{0301}\u{fe0f}g\u{fe0f}a\u{fe0f}l\u{fe0f}i\u{fe0f}\u{fe0f}t\u{fe0f}e\u{0301}\u{fe0f}>',
        ),
        16,
        reason: 'Égalité (using separate acute) emoij_presentation',
      );
    });

    // New: not upstream.
    test('dispose restores the previous version', () {
      expect(term.unicode.activeVersion, '15-graphemes');
      unicode.dispose();
      expect(term.unicode.activeVersion, '6');
    });

    // New: not upstream.
    test('flag and ZWJ sequences are single wide graphemes', () {
      // flag of Japan: two regional indicators
      expect(evalWidth('\u{1F1EF}\u{1F1F5}'), 2);
      // three regional indicators: a pair and a single one
      expect(evalWidth('\u{1F1EF}\u{1F1F5}\u{1F1EF}'), 3);
      // family: man, woman, girl, boy joined by ZWJ
      expect(
        evalWidth(
          '\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}',
        ),
        2,
      );
      // rainbow flag: white flag, VS16, ZWJ, rainbow
      expect(evalWidth('\u{1F3F3}\u{FE0F}\u{200D}\u{1F308}'), 2);
      // combining sequences stay one column
      expect(evalWidth('e\u{301}\u{302}'), 1);
      // Devanagari k.ssa: two clusters (no GB9c conjunct rule)
      expect(evalWidth('\u{915}\u{94D}\u{937}'), 2);
    });
  });

  // New: not upstream.
  group('UnicodeGraphemeProvider', () {
    test('versions', () {
      expect(UnicodeGraphemeProvider().version, '15-graphemes');
      expect(UnicodeGraphemeProvider(false).version, '15');
    });

    test('wcwidth', () {
      final p = UnicodeGraphemeProvider();
      expect(p.wcwidth(0x41), 1);
      expect(p.wcwidth(0x0301), 0); // Extend
      expect(p.wcwidth(0x0600), 0); // Prepend
      expect(p.wcwidth(0x4E00), 2);
      expect(p.wcwidth(0x1F600), 2);
      expect(p.wcwidth(0x00A1), 1); // East Asian ambiguous
      p.ambiguousCharsAreWide = true;
      expect(p.wcwidth(0x00A1), 2);
    });

    test('charProperties of a flag pair', () {
      final p = UnicodeGraphemeProvider();
      final first = p.charProperties(0x1F1EF, 0);
      expect(UnicodeService.extractShouldJoin(first), false);
      final second = p.charProperties(0x1F1F5, first);
      expect(UnicodeService.extractShouldJoin(second), true);
      expect(UnicodeService.extractWidth(second), 2);
    });

    test('without grapheme handling nothing joins', () {
      unicodeService.register(UnicodeGraphemeProvider(false));
      unicodeService.activeVersion = '15';
      expect(unicodeService.getStringCellWidth('\u{1F1EF}\u{1F1F5}'), 2);
      // As upstream: charProperties gives every character at least one
      // column (only wcwidth has zero widths), so ZWJ and marks take one.
      expect(
        unicodeService.getStringCellWidth(
          '\u{1F469}\u{200D}\u{1F469}\u{200D}\u{1F466}',
        ),
        8,
      );
      expect(unicodeService.getStringCellWidth('a\u{301}'), 2);
    });
  });

  // New: not upstream.
  group('UnicodeProperties', () {
    int kind(int cp) =>
        (uc.getInfo(cp) & uc.graphemeBreakMask) >> uc.graphemeBreakShift;

    test('Grapheme_Cluster_Break values', () {
      expect(kind(0x61), uc.graphemeBreakOther);
      expect(kind(0x0600), uc.graphemeBreakPrepend);
      expect(kind(0x0301), uc.graphemeBreakExtend);
      expect(kind(0x1F1E6), uc.graphemeBreakRegionalIndicator);
      expect(kind(0x0903), uc.graphemeBreakSpacingMark);
      expect(kind(0x1100), uc.graphemeBreakHangulL);
      expect(kind(0x1161), uc.graphemeBreakHangulV);
      expect(kind(0x11A8), uc.graphemeBreakHangulT);
      expect(kind(0xAC00), uc.graphemeBreakHangulLV);
      expect(kind(0xAC01), uc.graphemeBreakHangulLVT);
      expect(kind(0x200D), uc.graphemeBreakZWJ);
      expect(kind(0x1F600), uc.graphemeBreakExtPic);
    });

    test('width info', () {
      expect(uc.infoToWidthInfo(uc.getInfo(0x61)), uc.charwidthNormal);
      expect(uc.infoToWidthInfo(uc.getInfo(0x4E00)), uc.charwidthWide);
      expect(uc.infoToWidthInfo(uc.getInfo(0x00A1)), uc.charwidthEaAmbiguous);
      expect(uc.infoToWidth(uc.getInfo(0x00A1)), 1);
      expect(uc.infoToWidth(uc.getInfo(0x00A1), true), 2);
      expect(uc.strWidth('a\u{4E00}\u{1F600}', false), 5);
      // index of the character that reaches past the column
      expect(uc.columnToIndexInContext('a\u{1F600}b', 0, 2, false), 1);
      expect(uc.columnToIndexInContext('a\u{1F600}b', 0, 3, false), 3);
    });

    test('out of range code points', () {
      // the trie's error value, the same for both ends
      expect(uc.getInfo(-1), uc.getInfo(0x110000));
    });
  });

  // New: not upstream.
  group('tinfUncompress', () {
    Uint8List deflate(List<int> data, int level) =>
        Uint8List.fromList(ZLibEncoder(raw: true, level: level).convert(data));

    final text = utf8.encode(
      List<String>.generate(
        200,
        (i) => 'line $i of some repetitive text ${i * i % 17}\n',
      ).join(),
    );

    test('stored, fixed and dynamic Huffman blocks', () {
      for (final level in <int>[0, 1, 6, 9]) {
        final out = tinfUncompress(
          deflate(text, level),
          Uint8List(text.length),
        );
        expect(out, equals(text), reason: 'level $level');
      }
      final short = utf8.encode('hello');
      expect(tinfUncompress(deflate(short, 6), Uint8List(5)), equals(short));
    });

    test('a larger destination gives the written part', () {
      final out = tinfUncompress(deflate(text, 6), Uint8List(text.length + 10));
      expect(out, equals(text));
    });

    test('a bad block type throws', () {
      // BFINAL 1, BTYPE 3 (reserved)
      expect(
        () => tinfUncompress(Uint8List.fromList(<int>[0x07]), Uint8List(1)),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
