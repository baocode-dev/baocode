/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Ported from VS Code src/vs/editor/common/core/wordCharacterClassifier.ts
// (and USUAL_WORD_SEPARATORS from core/wordHelper.ts) at
// 6a598d4a13031703d483d103c1d934a36ad27971.
// Deviation: Intl.Segmenter word segmentation (`wordSegmenterLocales`) is not
// available in Dart; the Intl hooks always report no segment, which matches
// upstream's default empty locale list. The upstream CharacterClassifier's
// ASCII table + sparse map is folded into this class.

import 'dart:typed_data';

/// The editor's default `wordSeparators` option.
const String usualWordSeparators = r'''`~!@#$%^&*()-=+[{]}\|;:'",.<>/?''';

abstract final class WordCharacterClass {
  static const int regular = 0;
  static const int whitespace = 1;
  static const int wordSeparator = 2;
}

class WordCharacterClassifier {
  WordCharacterClassifier(String wordSeparators) {
    for (var i = 0; i < wordSeparators.length; i++) {
      _set(wordSeparators.codeUnitAt(i), WordCharacterClass.wordSeparator);
    }
    _set(0x20, WordCharacterClass.whitespace);
    _set(0x09, WordCharacterClass.whitespace);
  }

  final Uint8List _asciiMap = Uint8List(256);
  final Map<int, int> _map = {};

  void _set(int charCode, int value) {
    if (charCode >= 0 && charCode < 256) {
      _asciiMap[charCode] = value;
    } else {
      _map[charCode] = value;
    }
  }

  /// The [WordCharacterClass] of a UTF-16 code unit.
  int get(int charCode) => charCode >= 0 && charCode < 256
      ? _asciiMap[charCode]
      : (_map[charCode] ?? WordCharacterClass.regular);
}

final Map<String, WordCharacterClassifier> _cache = {};

/// Upstream caches the ten most recent classifiers; separators rarely change.
WordCharacterClassifier getMapForWordSeparators(String wordSeparators) {
  final cached = _cache.remove(wordSeparators);
  final result = cached ?? WordCharacterClassifier(wordSeparators);
  _cache[wordSeparators] = result;
  if (_cache.length > 10) _cache.remove(_cache.keys.first);
  return result;
}
