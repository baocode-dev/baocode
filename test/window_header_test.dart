import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monad/chat/chat_screen.dart';
import 'package:monad/chat/panels/context_usage_panel.dart';
import 'package:monad/main.dart';
import 'package:monad/theme/cursor_theme.dart';
import 'package:monad/workspace/back_to_chat_button.dart';
import 'package:monad/workspace/editor_launcher.dart';
import 'package:monad/workspace/open_in_editor_button.dart';
import 'package:monad/workspace/window_header/about_dialog.dart';
import 'package:monad/workspace/window_header/window_header.dart';
import 'package:monad/workspace/workspace.dart';

const _window = MethodChannel('monad/window');

/// The app with the header Windows draws, and what it tells the window.
Future<(Workspace, List<MethodCall>)> pumpWindowsApp(
  WidgetTester tester,
) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final calls = <MethodCall>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_window, (
    call,
  ) async {
    calls.add(call);
    return null;
  });
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _window,
      null,
    ),
  );
  final workspace = Workspace.mock();
  await tester.pumpWidget(MonadApp(workspace: workspace));
  await tester.pump();
  return (workspace, calls);
}

final _windows = TargetPlatformVariant.only(TargetPlatform.windows);

void main() {
  testWidgets('the header opens the current session\'s project, as the '
      'session changes', (tester) async {
    final (workspace, _) = await pumpWindowsApp(tester);
    final other = workspace.threads.firstWhere(
      (thread) => thread.project != workspace.current!.project,
    );
    workspace.select(other);
    await tester.pump();
    final button = tester.widget<OpenInEditorButton>(
      find.descendant(
        of: find.byType(WindowHeader),
        matching: find.byType(OpenInEditorButton),
      ),
    );
    expect(button.project, other.project);
  }, variant: _windows);

  testWidgets('the window hears where the header\'s controls are whenever '
      'they move, and only then', (tester) async {
    final (workspace, calls) = await pumpWindowsApp(tester);
    List<MethodCall> reports() =>
        calls.where((call) => call.method == 'setHitTestAreas').toList();
    expect(reports(), hasLength(1));
    await tester.pump();
    await tester.pump();
    expect(reports(), hasLength(1));

    // A longer label: the editor button, and the pin beside it, move left.
    workspace.preferredEditor = Editor.terminal;
    await tester.pump();
    await tester.pump();
    expect(reports(), hasLength(2));
    List<Object?> controls(MethodCall call) =>
        (call.arguments as Map)['controls'] as List<Object?>;
    expect(controls(reports().last), isNot(controls(reports().first)));
  }, variant: _windows);

  testWidgets('over the IDE it is the IDE\'s title bar: no line under it, '
      'and the way back to the chat on the right', (tester) async {
    final (workspace, calls) = await pumpWindowsApp(tester);
    final header = find.byType(WindowHeader);
    BoxBorder? line() =>
        (tester
                    .widget<DecoratedBox>(
                      find
                          .descendant(
                            of: header,
                            matching: find.byType(DecoratedBox),
                          )
                          .first,
                    )
                    .decoration
                as BoxDecoration)
            .border;
    final back = find.descendant(
      of: header,
      matching: find.byType(BackToChatButton),
    );
    expect(line(), isNotNull);
    expect(back, findsNothing);

    workspace.layout = WorkspaceLayout.ide;
    await tester.pump();
    await tester.pump();
    expect(line(), isNull);
    expect(back, findsOneWidget);
    final button = tester.getRect(back);
    expect(button.height, 22);
    expect(button.center.dy, tester.getRect(header).center.dy);
    // The window leaves it to Flutter, rather than dragging by it.
    final report = calls.lastWhere((call) => call.method == 'setHitTestAreas');
    expect(
      (report.arguments as Map)['controls'],
      contains(
        equals({
          'left': button.left,
          'top': button.top,
          'width': button.width,
          'height': button.height,
        }),
      ),
    );

    await tester.tap(back);
    await tester.pump();
    expect(workspace.layout, WorkspaceLayout.chat);
    await tester.pump();
    expect(back, findsNothing);
  }, variant: _windows);

  testWidgets('View → Context Panel opens the chat\'s, wherever the focus '
      'is', (tester) async {
    await pumpWindowsApp(tester);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(find.byType(ContextUsagePanel), findsNothing);
    await tester.tap(find.text('View'));
    await tester.pump();
    await tester.tap(find.text('Context Panel'));
    await tester.pump();
    expect(find.byType(ContextUsagePanel), findsOneWidget);
  }, variant: _windows);

  testWidgets('code falls back to a monospaced font Windows has', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildCursorTheme(),
        home: const Scaffold(
          body: Text('x', style: TextStyle(fontFamily: CursorFonts.mono)),
        ),
      ),
    );
    final style = tester
        .renderObject<RenderParagraph>(find.text('x'))
        .text
        .style!;
    expect(style.fontFamily, CursorFonts.mono);
    expect(style.fontFamilyFallback, contains('Consolas'));
  }, variant: _windows);

  testWidgets('Chinese falls back to the font Windows itself links to', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildCursorTheme(),
        home: const Scaffold(body: Text('x')),
      ),
    );
    final style = tester
        .renderObject<RenderParagraph>(find.text('x'))
        .text
        .style!;
    // The monospaced families carry no Han glyphs, so YaHei has to be in the
    // chain and reachable — i.e. after them, not before.
    final fallbacks = style.fontFamilyFallback!;
    expect(fallbacks, contains('Microsoft YaHei UI'));
    expect(
      fallbacks.indexOf('Microsoft YaHei UI'),
      greaterThan(fallbacks.indexOf('Consolas')),
    );
  }, variant: _windows);

  testWidgets('on macOS the chat\'s own buttons keep to its right edge', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MonadApp(workspace: Workspace.mock()));
    await tester.pump();
    final chat = tester.getRect(find.byType(ChatScreen));
    final button = tester.getRect(
      find.descendant(
        of: find.byType(ChatScreen),
        matching: find.byType(OpenInEditorButton),
      ),
    );
    expect(button.right, chat.right - 8);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  test('About shows the version pubspec.yaml gives the build', () {
    final version = RegExp(
      r'^version: ([^+\s]+)',
      multiLine: true,
    ).firstMatch(File('pubspec.yaml').readAsStringSync())!.group(1);
    expect(monadVersion, version);
  });
}
