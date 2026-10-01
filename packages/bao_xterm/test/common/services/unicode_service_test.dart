// Copyright (c) 2019 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/LICENSE.txt.
// Adapted from xterm.js src/common/services/UnicodeService.test.ts (c58ea36).

import 'package:flutter_test/flutter_test.dart';
import 'package:bao_xterm/common/input/unicode_v6.dart';
import 'package:bao_xterm/common/services/services.dart';
import 'package:bao_xterm/common/services/unicode_service.dart';

class DummyProvider implements IUnicodeVersionProvider {
  @override
  String version = '123';
  @override
  int wcwidth(int codepoint) {
    return 2;
  }

  @override
  int charProperties(int codepoint, int preceding) {
    return UnicodeService.createPropertyValue(0, wcwidth(codepoint));
  }
}

void main() {
  group('unicode provider', () {
    late UnicodeService us;
    setUp(() {
      us = UnicodeService();
      us.register(UnicodeV6());
    });
    test('default to V6', () {
      expect(us.activeVersion, '6');
      expect(us.versions, equals(['6']));
      expect(() {
        us.activeVersion = '6';
      }, returnsNormally);
      expect(us.getStringCellWidth('hello'), 5);
    });
    test('activate should throw for unknown version', () {
      expect(
        () {
          us.activeVersion = '55';
        },
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            'unknown Unicode version "55"',
          ),
        ),
      );
    });
    test('should notify about version change', () {
      final notes = <String>[];
      us.onChange((version) => notes.add(version));
      final dummyProvider = DummyProvider();
      us.register(dummyProvider);
      us.activeVersion = dummyProvider.version;
      expect(notes, equals([dummyProvider.version]));
    });
    test('correctly changes provider impl', () {
      expect(us.getStringCellWidth('hello'), 5);
      final dummyProvider = DummyProvider();
      us.register(dummyProvider);
      us.activeVersion = dummyProvider.version;
      expect(us.getStringCellWidth('hello'), 2 * 5);
    });
    test('wcwidth V6 emoji test', () {
      final widthV6 = us.getStringCellWidth('🤣🤣🤣🤣🤣🤣🤣🤣🤣🤣');
      expect(widthV6, 10);
    });
  });
}
