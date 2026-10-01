// Reads the TextMate parity fixture bao_editor's
// tool/generate_textmate_fixtures.mjs writes from the real vscode-textmate
// and vscode-oniguruma: the app's tests read it where the package keeps it.

import 'dart:convert';
import 'dart:io';

/// The fixtures directory: samples/, themes/ and tokens.json.gz.
const String textMateFixtures = 'packages/bao_editor/test/fixtures/textmate';

/// tokens.json.gz, decoded.
Map<String, Object?> loadTextMateFixture() => jsonDecode(
  utf8.decode(
    gzip.decode(File('$textMateFixtures/tokens.json.gz').readAsBytesSync()),
  ),
) as Map<String, Object?>;
