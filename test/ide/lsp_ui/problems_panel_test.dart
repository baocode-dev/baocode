// Tests of the bottom panel's title: in a narrow panel the tabs scroll and
// the actions stay whole.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/lsp/lsp_protocol.dart';
import 'package:baocode/ide/lsp_ui/editor_language_session.dart';
import 'package:baocode/ide/lsp_ui/language_widgets.dart';
import 'package:baocode/ide/lsp_ui/problems_panel.dart';

import 'fake_language_features.dart';

void main() {
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

  testWidgets('Send to Agent in problems panel formats prompt with @problems', (
    tester,
  ) async {
    final fakeLanguages = FakeLanguageFeatures();
    fakeLanguages.diagnostics['/project/src/AuthService.java'] = [
      const LspDiagnostic(
        range: LspRange(LspPosition(24, 7), LspPosition(24, 49)),
        message: 'The import com.crb.crm.shared.constant.StatusConstant is never used',
        severity: LspDiagnosticSeverity.warning,
        source: 'Java',
        code: '268435844',
      ),
    ];

    String? sentPrompt;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 300,
            child: IdeBottomPanel(
              tab: IdePanelTab.problems,
              root: '/project',
              languages: fakeLanguages,
              references: null,
              onTab: (_) {},
              onClose: () {},
              onOpen: (_, {select = false}) {},
              textOf: (_) async => null,
              onAsk: (prompt) => sentPrompt = prompt,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final sendButton = find.text('Send to Agent');
    expect(sendButton, findsOneWidget);

    await tester.tap(sendButton);
    await tester.pump();

    expect(sentPrompt, isNotNull);
    expect(sentPrompt, contains('@problems Please fix the following problems in the workspace:'));
    expect(
      sentPrompt,
      contains(
        '- @src/AuthService.java:25:8 [Warning] The import com.crb.crm.shared.constant.StatusConstant is never used Java(268435844)',
      ),
    );
  });

  testWidgets('Fix with Agent in IdeHoverCard formats prompt with context lines', (
    tester,
  ) async {
    String? sentPrompt;
    const diagnostic = LspDiagnostic(
      range: LspRange(LspPosition(24, 7), LspPosition(24, 49)),
      message: 'The import com.crb.crm.shared.constant.StatusConstant is never used',
      severity: LspDiagnosticSeverity.warning,
      source: 'Java',
      code: '268435844',
    );

    const hoverState = IdeHoverState(
      start: 100,
      end: 150,
      markdown: null,
      diagnostics: [diagnostic],
      keyboard: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: IdeHoverCard(
              state: hoverState,
              filePath: '/project/sea-turtle-crm-service/src/main/java/com/crb/crm/access/application/AuthService.java',
              workspaceRoot: '/project',
              onAsk: (prompt) => sentPrompt = prompt,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final fixButton = find.text('Fix with Agent');
    expect(fixButton, findsOneWidget);

    await tester.tap(fixButton);
    await tester.pump();

    expect(sentPrompt, isNotNull);
    expect(sentPrompt, contains('For the code present, we get this error:'));
    expect(sentPrompt, contains('The import com.crb.crm.shared.constant.StatusConstant is never used'));
    expect(
      sentPrompt,
      contains(
        'Fix it, verify, and then give a concise explanation. @sea-turtle-crm-service/src/main/java/com/crb/crm/access/application/AuthService.java:24-27',
      ),
    );
  });
}
