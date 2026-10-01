import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/panels/interaction_panel.dart';
import 'package:baocode/main.dart';
import 'package:baocode/workspace/workspace.dart';

void main() {
  testWidgets('with no project open, the window has its text style, and '
      'its button is as wide as its label', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(BaoCodeApp(workspace: Workspace()));
    await tester.pump();

    // Not the error style text falls back to with no Material above it
    // (yellow, underlined twice).
    final title = find.text('Open a project folder');
    final style = DefaultTextStyle.of(tester.element(title)).style;
    expect(style.decoration, isNot(TextDecoration.underline));

    final button = find.widgetWithText(PanelButton, 'Open folder…');
    expect(tester.getSize(button).width, lessThan(200));
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
