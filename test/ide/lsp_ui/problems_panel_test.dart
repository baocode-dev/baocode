// Tests of the bottom panel's title: in a narrow panel the tabs scroll and
// the actions stay whole.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/lsp_ui/lsp_convert.dart';
import 'package:baocode/ide/lsp_ui/problems_panel.dart';

import 'fake_language_features.dart';

void main() {
  testWidgets('virtual reference names are URI names without host folders', (
    tester,
  ) async {
    const path = 'baocode-lsp://jdtls/library/Foo%20Bar.java';
    final opened = <IdeLocation>[];
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 600,
          height: 200,
          child: IdeBottomPanel(
            tab: IdePanelTab.references,
            root: r'C:\project',
            languages: null,
            references: IdeReferences('Foo', [
              IdeLocation(path, lspRange(0, 6, 9)),
            ]),
            onTab: (_) {},
            onClose: () {},
            onOpen: (location, {select = false}) => opened.add(location),
            textOf: (path) async => 'class Foo {}',
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Foo Bar.java'), findsOneWidget);
    expect(find.textContaining('baocode-lsp:'), findsNothing);
    expect(find.textContaining('library'), findsNothing);
    await tester.tap(find.textContaining('class Foo'));
    expect(opened.single.path, path);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow, its tabs scroll and its actions stay whole', (
    tester,
  ) async {
    final tabs = <IdePanelTab>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 318,
            height: 200,
            child: IdeBottomPanel(
              tab: IdePanelTab.terminal,
              root: '/project',
              languages: null,
              references: null,
              onTab: tabs.add,
              onClose: () {},
              onOpen: (location, {select = false}) {},
              textOf: (path) async => null,
              terminal: const SizedBox(),
              // As wide as a single terminal's title, New and Kill.
              terminalActions: const SizedBox(
                key: ValueKey('actions'),
                width: 150,
                height: 22,
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);

    final panel = tester.getRect(find.byType(IdeBottomPanel));
    final actions = tester.getRect(find.byKey(const ValueKey('actions')));
    expect(actions.right, lessThanOrEqualTo(panel.right));

    // The last tab, cut off, is scrolled to.
    await tester.drag(find.text('PROBLEMS'), const Offset(-1000, 0));
    await tester.pump();
    expect(
      tester.getRect(find.text('TERMINAL')).right,
      lessThanOrEqualTo(actions.left),
    );
    await tester.tap(find.text('TERMINAL'));
    expect(tabs, [IdePanelTab.terminal]);
  });
}
