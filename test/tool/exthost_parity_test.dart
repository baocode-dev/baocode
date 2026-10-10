// 九.9: docs/extensions/EXTHOST_PARITY.md is what the generator makes of
// lib/extensions now, and every implementation fits its shape.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/generate_exthost_parity.dart';

void main() {
  test('九.9: EXTHOST_PARITY.md is generated from the current sources', () {
    final (:report, :warnings) = exthostParityReport();
    expect(
      File(exthostParityOutput).readAsStringSync(),
      report,
      reason: 'run dart run tool/generate_exthost_parity.dart',
    );
    expect(warnings, isEmpty);
    expect(report, contains('**Total: '));
  });

  test("九.9: every `@override` of a `\$` method in a shape's implementation "
      'counts, past strings with interpolated quotes', () {
    final (:report, warnings: _) = exthostParityReport();
    // Each shape's unsupported methods.
    final unsupported = <String, String>{};
    String? shape;
    for (final line in report.split('\n')) {
      if (line.startsWith('### ')) shape = line.substring(4);
      if (line.startsWith('- Unsupported') && shape != null) {
        unsupported[shape] = line;
      }
    }
    // Read line by line, apart from the generator: a `$` method declared
    // right under `@override` in a class extending a shape's fallback.
    final classPattern = RegExp(r'^(?:\w+ )*class \w+');
    final fallback = RegExp(r'extends (MainThread\w+)Unsupported\b');
    final declared = RegExp(r'^\s+[\w<>?, ]+?\s(\$\w+)\s*[(<]');
    var checked = 0;
    for (final file in Directory('lib/extensions').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final lines = file.readAsStringSync().split('\n');
      String? current;
      for (var i = 0; i < lines.length; i++) {
        if (classPattern.hasMatch(lines[i])) {
          // The `extends` may be on the next line.
          current = fallback.firstMatch(
            '${lines[i]} ${i + 1 < lines.length ? lines[i + 1] : ''}',
          )?[1];
        }
        if (current == null || i == 0 || lines[i - 1].trim() != '@override') {
          continue;
        }
        final method = declared.firstMatch(lines[i])?[1];
        if (method == null) continue;
        checked++;
        expect(
          unsupported[current],
          isNot(contains('`$method`')),
          reason: '${file.path}:${i + 1} implements $current.$method',
        );
      }
    }
    expect(checked, greaterThan(300));
    // Those the generator once lost after a `'${…['kind'] ?? ''}'`.
    for (final method in [
      r'$registerDocumentFormattingSupport',
      r'$registerInlayHintsProvider',
      r'$registerFoldingRangeProvider',
      r'$registerSignatureHelpProvider',
    ]) {
      expect(
        unsupported['MainThreadLanguageFeatures'],
        isNot(contains('`$method`')),
        reason: method,
      );
    }
  });
}
