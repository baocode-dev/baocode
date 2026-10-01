// The native scanner against vscode-oniguruma 1.7.0 itself: sessions of
// scanners and strings that vscode_oniguruma_parity.mjs ran through the
// WebAssembly VS Code ships, replayed call for call.

@TestOn('mac-os || linux || windows')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bao_editor/textmate/oniguruma/onig_lib_io.dart';

void main() {
  final fixture = jsonDecode(
    File('test/textmate/oniguruma/vscode_oniguruma_parity.json')
        .readAsStringSync(),
  ) as Map<String, Object?>;
  final sessions = (fixture['sessions']! as List).cast<Map<String, Object?>>();
  const lib = NativeOnigLib();

  test('replays vscode-oniguruma ${fixture['vscodeOniguruma']}', () {
    var calls = 0;
    for (final (number, session) in sessions.indexed) {
      final patterns = (session['patterns']! as List).cast<String>();
      final scanner = lib.createOnigScanner(patterns);
      final strings = [
        for (final text in (session['texts']! as List).cast<String>())
          lib.createOnigString(text),
      ];
      final results = session['results']! as List;
      for (final (i, call) in (session['calls']! as List).indexed) {
        final [which as int, start as int, options as int] = call as List;
        final match = scanner.findNextMatchSync(strings[which], start, options);
        final actual = match == null
            ? null
            : [
                match.index,
                for (final capture in match.captureIndices) ...[
                  capture.start,
                  capture.end,
                ],
              ];
        expect(
          actual,
          results[i],
          reason:
              'session $number, call $i: ${jsonEncode(patterns)} on '
              'string $which from $start with options $options',
        );
        if (match != null) {
          for (final capture in match.captureIndices) {
            expect(capture.length, capture.end - capture.start);
          }
        }
        calls++;
      }
      for (final string in strings) {
        string.dispose();
      }
      scanner.dispose();
    }
    expect(calls, greaterThan(1000));
  });
}
