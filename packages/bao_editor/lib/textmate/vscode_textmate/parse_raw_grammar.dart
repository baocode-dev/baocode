// Adapted from vscode-textmate 9.3.2 (25b68dad91920b1ed79d357534b8c4582f62d80d):
// src/parseRawGrammar.ts (MIT, see LICENSE.md).

import 'dart:convert';

import 'debug.dart';
import 'json.dart';
import 'plist.dart' as plist;
import 'raw_grammar.dart';

/// Parses a grammar file: JSON when [filePath] ends in `.json`, otherwise a
/// plist. Throws a [FormatException] when the file's root is not an object.
IRawGrammar parseRawGrammar(String content, [String? filePath]) {
  if (filePath != null && filePath.endsWith('.json')) {
    return _parseJSONGrammar(content, filePath);
  }
  return _parsePLISTGrammar(content, filePath);
}

IRawGrammar _parseJSONGrammar(String contents, String? filename) {
  if (DebugFlags.inDebugMode) {
    return _asRawGrammar(parseJSON(contents, filename, true));
  }
  return _asRawGrammar(jsonDecode(contents));
}

IRawGrammar _parsePLISTGrammar(String contents, String? filename) {
  if (DebugFlags.inDebugMode) {
    return _asRawGrammar(
      plist.parseWithLocation(contents, filename, r'$vscodeTextmateLocation'),
    );
  }
  return _asRawGrammar(plist.parsePLIST(contents));
}

IRawGrammar _asRawGrammar(Object? value) {
  if (value is Map<String, Object?>) {
    return IRawGrammar(value);
  }
  throw FormatException('Grammar root is not an object: $value');
}
