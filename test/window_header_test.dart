import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_screen.dart';
import 'package:baocode/chat/composer/composer.dart';
import 'package:baocode/chat/panels/context_usage_panel.dart';
import 'package:baocode/ide/ide_layout.dart';
import 'package:baocode/ide/ide_workbench.dart';
import 'package:baocode/ide/lsp_ui/problems_panel.dart';
import 'package:baocode/ide/terminal/terminal_instance.dart';
import 'package:baocode/main.dart';
import 'package:baocode/sidebar/sidebar.dart';
import 'package:baocode/theme/codicons.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:baocode/workspace/back_to_chat_button.dart';
import 'package:baocode/workspace/editor_launcher.dart';
import 'package:baocode/workspace/open_in_editor_button.dart';
import 'package:baocode/workspace/pin_window_button.dart';
import 'package:baocode/workspace/window_header/about_dialog.dart';
import 'package:baocode/workspace/window_header/header_menu_bar.dart';
import 'package:baocode/workspace/window_header/window_header.dart';
import 'package:baocode/workspace/workspace.dart';

import 'ide/terminal/fake_pty.dart';
import 'ide/terminal/fake_terminal.dart';

const _window = MethodChannel('baocode/window');

/// The app with the header Windows draws, and what it tells the window.
Future<(Workspace, List<MethodCall>)> pumpWindowsApp(
  WidgetTester tester, {
  TerminalBackend? terminalBackend,
}) async {
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
  await tester.pumpWidget(
    BaoCodeApp(workspace: workspace, terminalBackend: terminalBackend),
  );
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

  testWidgets('the sidebar toggle comes after the menus, in the IDE\'s '
      'layout icons', (tester) async {
    await pumpWindowsApp(tester);
    final header = find.byType(WindowHeader);
    final menus = find.descendant(
      of: header,
      matching: find.byType(HeaderMenuBar),
    );
    final toggle = find.descendant(
      of: header,
      matching: find.byType(SidebarIconButton),
    );
    IconData icon() => tester.widget<SidebarIconButton>(toggle).icon;
    expect(
      tester.getRect(toggle).left,
      greaterThan(tester.getRect(menus).right),
    );
    expect(icon(), Codicons.layoutSidebarLeft);
    await tester.tap(toggle);
    await tester.pump();
    expect(icon(), Codicons.layoutSidebarLeftOff);
  }, variant: _windows);

  testWidgets('over the IDE, the IDE\'s layout toggles as on its own title '
      'bar: the side bar\'s after the menus, the panel\'s and the chat\'s on '
      'the right; no editor to open the project in', (tester) async {
    final (workspace, calls) = await pumpWindowsApp(tester);
    workspace.layout = WorkspaceLayout.ide;
    await tester.pump();
    await tester.pump();
    final header = find.byType(WindowHeader);
    final layout = tester
        .widget<IdeWorkbench>(find.byType(IdeWorkbench))
        .workspace
        .layout;
    Finder toggle(String tooltip) =>
        find.descendant(of: header, matching: find.byTooltip(tooltip));
    final sidebar = toggle('Toggle Primary Side Bar (Ctrl+B)');
    final panel = toggle('Toggle Panel (Ctrl+`)');
    final chat = toggle('Toggle Chat (Ctrl+J)');
    List<IconData> icons() => [
      for (final toggle in [sidebar, panel, chat])
        tester
            .widget<Icon>(
              find.descendant(of: toggle, matching: find.byType(Icon)),
            )
            .icon!,
    ];

    final menus = find.descendant(
      of: header,
      matching: find.byType(HeaderMenuBar),
    );
    final pin = find.descendant(
      of: header,
      matching: find.byType(PinWindowButton),
    );
    expect(
      tester.getRect(sidebar).left,
      greaterThan(tester.getRect(menus).right),
    );
    expect(
      tester.getRect(panel).right,
      lessThanOrEqualTo(tester.getRect(chat).left),
    );
    expect(tester.getRect(chat).right, lessThan(tester.getRect(pin).left));
    expect(
      find.descendant(of: header, matching: find.byType(OpenInEditorButton)),
      findsNothing,
    );
    expect(icons(), [
      Codicons.layoutSidebarLeft,
      Codicons.layoutPanelOff,
      Codicons.layoutSidebarRight,
    ]);
    expect(find.text('Explorer'), findsOneWidget);
    expect(find.text('PROBLEMS'), findsNothing);

    // The IDE follows them.
    for (final toggle in [sidebar, panel, chat]) {
      await tester.tap(toggle);
      await tester.pump();
    }
    expect(layout.sidebar, isFalse);
    expect(layout.panel, IdePanelTab.problems);
    expect(layout.chat, isFalse);
    expect(icons(), [
      Codicons.layoutSidebarLeftOff,
      Codicons.layoutPanel,
      Codicons.layoutSidebarRightOff,
    ]);
    expect(find.text('Explorer'), findsNothing);
    expect(find.text('PROBLEMS'), findsOneWidget);

    // The window leaves them to Flutter, rather than dragging by them.
    await tester.pump();
    final report = calls.lastWhere((call) => call.method == 'setHitTestAreas');
    for (final toggle in [sidebar, panel, chat]) {
      final rect = tester.getRect(
        find.ancestor(of: toggle, matching: find.byType(IdeLayoutToggle)),
      );
      expect(
        (report.arguments as Map)['controls'],
        contains(
          equals({
            'left': rect.left,
            'top': rect.top,
            'width': rect.width,
            'height': rect.height,
          }),
        ),
      );
    }
  }, variant: _windows);

  testWidgets('with terminals, the panel toggles open on TERMINAL, a '
      'terminal of its own made; the app has none unless given them', (
    tester,
  ) async {
    final ptys = <FakePty>[];
    final (workspace, _) = await pumpWindowsApp(
      tester,
      terminalBackend: fakeTerminalBackend(ptys),
    );
    workspace.layout = WorkspaceLayout.ide;
    await tester.pump();
    await tester.pump();
    final layout = tester
        .widget<IdeWorkbench>(find.byType(IdeWorkbench))
        .workspace
        .layout;
    await tester.tap(
      find.descendant(
        of: find.byType(WindowHeader),
        matching: find.byTooltip('Toggle Panel (Ctrl+`)'),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(layout.panel, IdePanelTab.terminal);
    expect(find.text('TERMINAL'), findsOneWidget);
    expect(ptys, hasLength(1));
    expect(ptys.single.launch!.executable, '/bin/zsh');
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
        theme: buildAppTheme(),
        home: const Scaffold(
          body: Text('x', style: TextStyle(fontFamily: AppFonts.mono)),
        ),
      ),
    );
    final style = tester
        .renderObject<RenderParagraph>(find.text('x'))
        .text
        .style!;
    expect(style.fontFamily, AppFonts.mono);
    expect(style.fontFamilyFallback, contains('Consolas'));
  }, variant: _windows);

  testWidgets('Chinese falls back to the font Windows itself links to', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
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

  testWidgets('on macOS the chat\'s own buttons keep to its column\'s right '
      'edge', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(BaoCodeApp(workspace: Workspace.mock()));
    await tester.pump();
    final button = tester.getRect(
      find.descendant(
        of: find.byType(ChatScreen),
        matching: find.byType(OpenInEditorButton),
      ),
    );
    // Level with the composer's, as the title is with its left.
    expect(button.right, tester.getRect(find.byType(ChatComposer)).right);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  test('About shows the version pubspec.yaml gives the build', () {
    final version = RegExp(
      r'^version: ([^+\s]+)',
      multiLine: true,
    ).firstMatch(File('pubspec.yaml').readAsStringSync())!.group(1);
    expect(baocodeVersion, version);
  });
}
