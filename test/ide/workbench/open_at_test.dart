import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/lsp/lsp_protocol.dart';

import 'fake_files.dart';

String _status(WidgetTester tester) {
  final text = tester.widget<Text>(
    find.textContaining(RegExp(r'^Ln \d+, Col')),
  );
  return text.data ?? text.textSpan!.toPlainText();
}

void main() {
  final long = [for (var i = 1; i <= 60; i++) 'line $i'].join('\n');
  final files = {'a.dart': long, 'b.dart': 'b'};
  // Lines 20 to 22, as code the agent cited opens.
  const cited = LspRange(LspPosition(19, 0), LspPosition(21, 1 << 30));

  testWidgets('a file opened at a range shows it selected', (tester) async {
    final workspace = await pumpWorkbench(
      tester,
      files,
      open: ['b.dart'],
      nativeEditor: true,
    );
    await tester.pumpAndSettle();

    await workspace.openAt(inRoot('a.dart'), cited);
    await tester.pumpAndSettle();
    expect(workspace.active!.path, inRoot('a.dart'));
    expect(_status(tester), 'Ln 22, Col 8 (23 selected)');

    // The file open already, and in front.
    await workspace.openAt(
      inRoot('a.dart'),
      const LspRange(LspPosition(2, 0), LspPosition(2, 1 << 30)),
    );
    await tester.pumpAndSettle();
    expect(_status(tester), 'Ln 3, Col 7 (6 selected)');
  });
}
