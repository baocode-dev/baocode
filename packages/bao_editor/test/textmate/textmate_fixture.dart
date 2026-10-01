// Reads the TextMate parity fixture tool/generate_textmate_fixtures.mjs writes
// from the real vscode-textmate and vscode-oniguruma.

import 'dart:convert';
import 'dart:io';

/// The fixtures directory: samples/, themes/ and tokens.json.gz.
const String textMateFixtures = 'test/fixtures/textmate';

/// tokens.json.gz, decoded.
Map<String, Object?> loadTextMateFixture() => jsonDecode(
  utf8.decode(
    gzip.decode(File('$textMateFixtures/tokens.json.gz').readAsBytesSync()),
  ),
) as Map<String, Object?>;
