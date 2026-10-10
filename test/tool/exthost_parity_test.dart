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
}
