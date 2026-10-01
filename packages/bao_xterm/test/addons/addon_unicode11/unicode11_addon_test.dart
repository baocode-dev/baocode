// Copyright (c) 2019 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See
// lib/addons/addon_unicode11/LICENSE.
// Adapted from xterm.js addons/addon-unicode11/test/Unicode11Addon.test.ts
// (c58ea36).
//
// Upstream's test is a Playwright test in the browser terminal; its
// assertions run here against a UnicodeService behind a stand-in terminal.
// The 'UnicodeV11' group is new (not upstream): known widths of V11 against
// V6.

import 'package:flutter_test/flutter_test.dart';
import 'package:bao_xterm/addons/addon_unicode11/unicode11_addon.dart';
import 'package:bao_xterm/addons/addon_unicode11/unicode_v11.dart';
import 'package:bao_xterm/common/input/unicode_v6.dart';
import 'package:bao_xterm/common/services/unicode_service.dart';
import 'package:bao_xterm/typings/xterm_headless.dart';

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
  group('Unicode11Addon', () {
    late UnicodeService unicodeService;
    late _TestTerminal term;
    late Unicode11Addon unicode11;

    setUp(() {
      // CoreTerminal registers V6 first.
      unicodeService = UnicodeService()..register(UnicodeV6());
      term = _TestTerminal(_UnicodeHandling(unicodeService));
      unicode11 = Unicode11Addon();
      unicode11.activate(term);
    });

    tearDown(() {
      unicode11.dispose();
      unicodeService.dispose();
    });

    test('wcwidth V11 emoji test', () {
      // should have loaded '11'
      expect(term.unicode.versions.contains('11'), true);
      // switch should not throw
      term.unicode.activeVersion = '11';
      expect(term.unicode.activeVersion, '11');
      // v6: 10, V11: 20
      expect(unicodeService.getStringCellWidth('🤣🤣🤣🤣🤣🤣🤣🤣🤣🤣'), 20);
    });
  });

  group('UnicodeV11', () {
    final v6 = UnicodeV6();
    final v11 = UnicodeV11();

    test('version', () {
      expect(v11.version, '11');
    });

    test('control characters and ASCII', () {
      expect(v11.wcwidth(0), 0);
      expect(v11.wcwidth(0x1b), 0);
      expect(v11.wcwidth(0x7f), 0);
      expect(v11.wcwidth(0x9f), 0);
      expect(v11.wcwidth(0x20), 1);
      expect(v11.wcwidth(0x41), 1);
      expect(v11.wcwidth(0x7e), 1);
    });

    test('emoji are wide in V11, narrow in V6', () {
      for (final cp in <int>[0x1F600, 0x1F923, 0x1F680, 0x1F9FF, 0x231A]) {
        expect(v11.wcwidth(cp), 2, reason: 'U+${cp.toRadixString(16)}');
        expect(v6.wcwidth(cp), 1, reason: 'U+${cp.toRadixString(16)}');
      }
    });

    test('CJK and Hangul are wide', () {
      expect(v11.wcwidth(0x4E00), 2);
      expect(v11.wcwidth(0x9FA5), 2);
      expect(v11.wcwidth(0x3042), 2); // Hiragana a
      expect(v11.wcwidth(0xAC00), 2); // Hangul syllable ga
      expect(v11.wcwidth(0xFF21), 2); // fullwidth A
      expect(v11.wcwidth(0x20000), 2); // CJK extension B
      expect(v11.wcwidth(0x30000), 2); // CJK extension G
    });

    test('combining marks are zero width', () {
      expect(v11.wcwidth(0x0301), 0);
      expect(v11.wcwidth(0x200D), 0); // ZWJ
      expect(v11.wcwidth(0xFE0F), 0); // VS16
      expect(v11.wcwidth(0x1D167), 0);
      expect(v11.wcwidth(0xE0100), 0);
      // newer combining marks than V6 knows
      expect(v11.wcwidth(0x0C00), 0);
      expect(v6.wcwidth(0x0C00), 1);
    });

    test('other characters are narrow', () {
      expect(v11.wcwidth(0x00E9), 1);
      expect(v11.wcwidth(0x2500), 1);
      expect(v11.wcwidth(0x1F1E6), 1); // regional indicator A
      expect(v11.wcwidth(0x10000), 1);
    });

    test('charProperties joins zero width characters', () {
      final e = v11.charProperties(0x65, 0);
      expect(UnicodeService.extractWidth(e), 1);
      expect(UnicodeService.extractShouldJoin(e), false);
      final acute = v11.charProperties(0x0301, e);
      expect(UnicodeService.extractShouldJoin(acute), true);
      expect(UnicodeService.extractWidth(acute), 1);
      // nothing to join at the start
      final lone = v11.charProperties(0x0301, 0);
      expect(UnicodeService.extractShouldJoin(lone), false);
      expect(UnicodeService.extractWidth(lone), 0);
      // a wide preceding character keeps its width
      final cjk = v11.charProperties(0x4E00, 0);
      final mark = v11.charProperties(0x0301, cjk);
      expect(UnicodeService.extractShouldJoin(mark), true);
      expect(UnicodeService.extractWidth(mark), 2);
    });

    test('string widths through UnicodeService', () {
      final us = UnicodeService()..register(v11);
      expect(us.activeVersion, '11');
      expect(us.getStringCellWidth('hello'), 5);
      expect(us.getStringCellWidth('\u{E9}'), 1);
      expect(us.getStringCellWidth('e\u{301}'), 1);
      expect(us.getStringCellWidth('\u{4E00}\u{4E8C}'), 4);
      expect(us.getStringCellWidth('\u{1F600}x'), 3);
      us.dispose();
    });
  });
}
