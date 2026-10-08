import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_screen.dart';
import 'package:baocode/chat/side_panel/side_panel_view.dart';
import 'package:baocode/chat/composer/composer.dart';
import 'package:baocode/chat/panels/context_usage_panel.dart';
import 'package:baocode/ide/ide_layout.dart';
import 'package:baocode/ide/ide_workbench.dart';
import 'package:baocode/ide/lsp_ui/problems_panel.dart';
import 'package:baocode/ide/terminal/terminal_instance.dart';
import 'package:baocode/main.dart';
import 'package:baocode/settings/settings_dialog.dart';
import 'package:baocode/sidebar/sidebar.dart';
import 'package:baocode/theme/codicons.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:baocode/workspace/back_to_chat_button.dart';
import 'package:baocode/workspace/editor_launcher.dart';
import 'package:baocode/workspace/open_in_editor_button.dart';
import 'package:baocode/workspace/pin_window_button.dart';
import 'package:baocode/workspace/window_header/about_dialog.dart';
import 'package:baocode/workspace/title_bar_double_click.dart';
import 'package:baocode/workspace/window_header/header_menu_bar.dart';
import 'package:baocode/workspace/window_header/window_buttons.dart';
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
  testWidgets('the chat\'s title bar opens the current session\'s project, '
      'as the session changes', (tester) async {
    final (workspace, _) = await pumpWindowsApp(tester);
    final other = workspace.threads.firstWhere(
      (thread) => thread.project != workspace.current!.project,
    );
    workspace.select(other);
    await tester.pump();
    final button = tester.widget<OpenInEditorButton>(
      find.descendant(
        of: find.byType(ChatScreen),
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

  testWidgets('over the IDE it is the IDE\'s title bar, with the menus and '
      'the way back to the chat on the right; over the chat there is none', (
    tester,
  ) async {
    final (workspace, calls) = await pumpWindowsApp(tester);
    final header = find.byType(WindowHeader);
    final back = find.descendant(
      of: header,
      matching: find.byType(BackToChatButton),
    );
    expect(header, findsNothing);

    workspace.layout = WorkspaceLayout.ide;
    await tester.pump();
    await tester.pump();
    expect(header, findsOneWidget);
    expect(
      find.descendant(of: header, matching: find.byType(HeaderMenuBar)),
      findsOneWidget,
    );
    expect(back, findsOneWidget);
    final button = tester.getRect(back);
    expect(button.height, 22);
    expect(button.center.dy, tester.getRect(header).center.dy);
    // The window leaves it to Flutter, rather than dragging by it.
    final report = calls.lastWhere((call) => call.method == 'setHitTestAreas');
    expect((report.arguments as Map)['height'], AppMetrics.headerHeight);
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
    expect(header, findsNothing);
  }, variant: _windows);

  testWidgets('over the chat, the sidebar\'s and the conversation\'s title '
      'bars reach the window\'s top, as on macOS: no menus, the window\'s '
      'buttons over its top right, their controls left to Flutter', (
    tester,
  ) async {
    final (workspace, calls) = await pumpWindowsApp(tester);
    await tester.pump();
    Map<Object?, Object?> report() =>
        calls.lastWhere((call) => call.method == 'setHitTestAreas').arguments
            as Map;
    Map<String, double> encoded(Rect rect) => {
      'left': rect.left,
      'top': rect.top,
      'width': rect.width,
      'height': rect.height,
    };
    Rect controlsOf(Finder finder) => tester.getRect(
      find.ancestor(of: finder, matching: find.byType(TitleBarControls)).first,
    );
    expect(find.byType(HeaderMenuBar), findsNothing);
    expect(find.text('File'), findsNothing);
    expect(tester.getRect(find.byType(Sidebar)).top, 0);
    final chat = find.byType(ChatScreen);
    final title = find.descendant(
      of: chat,
      matching: find.text(workspace.current!.title),
    );
    expect(tester.getRect(title).center.dy, AppMetrics.titleBarHeight / 2);

    final buttons = tester.getRect(find.byType(WindowButtons));
    expect(buttons.topRight, const Offset(1400, 0));
    expect(buttons.height, AppMetrics.titleBarHeight);
    final panelToggle = find.descendant(
      of: chat,
      matching: find.byType(SidePanelToggle),
    );
    expect(tester.getRect(panelToggle).right, lessThan(buttons.left));

    // The sidebar's toggle at its top right, as under macOS's traffic
    // lights; the window drags itself by the rest of the strip.
    bool isToggle(Widget widget) =>
        widget is SidebarIconButton &&
        widget.command == 'workbench.action.toggleSidebarVisibility';
    final collapse = find.descendant(
      of: find.byType(Sidebar),
      matching: find.byWidgetPredicate(isToggle),
    );
    expect(report()['height'], AppMetrics.titleBarHeight);
    expect(
      report()['controls'],
      containsAll([
        equals(encoded(controlsOf(collapse))),
        equals(encoded(controlsOf(panelToggle))),
      ]),
    );

    // Hidden, its toggle is the chat's, first in its title bar.
    await tester.tap(collapse);
    await tester.pumpAndSettle();
    final expand = find.descendant(
      of: chat,
      matching: find.byWidgetPredicate(isToggle),
    );
    expect(
      tester.widget<SidebarIconButton>(expand).icon,
      Codicons.layoutSidebarLeftOff,
    );
    expect(tester.getRect(expand).left, lessThan(tester.getRect(title).left));
    expect(report()['controls'], contains(equals(encoded(controlsOf(expand)))));

    // Narrow, the same: the title in the chat's own title bar.
    tester.view.physicalSize = const Size(520, 760);
    await tester.pumpAndSettle();
    expect(title, findsOneWidget);
    expect(
      tester.getRect(panelToggle).right,
      lessThan(tester.getRect(find.byType(WindowButtons)).left),
    );
  }, variant: _windows);

  testWidgets('the settings leave the window\'s caption above them', (
    tester,
  ) async {
    await pumpWindowsApp(tester);
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(Sidebar),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is SidebarIconButton &&
              widget.icon == Codicons.settingsGear,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final page = find
        .descendant(
          of: find.byType(SettingsDialog),
          matching: find.byType(Material),
        )
        .first;
    expect(tester.getRect(page).top, AppMetrics.titleBarHeight);
    // The window's buttons stay in sight.
    expect(
      tester.getRect(find.byType(WindowButtons)).bottom,
      AppMetrics.titleBarHeight,
    );
  }, variant: _windows);

  testWidgets('where the window has not the room for the sidebar and the '
      'side panel, the one asked for last stays: the other gives way to the '
      'window until it widens, to the one asked for until asked again', (
    tester,
  ) async {
    await pumpWindowsApp(tester);
    // The sidebar's own, or the chat's while it is hidden.
    final sidebarToggle = find
        .byWidgetPredicate(
          (widget) =>
              widget is SidebarIconButton &&
              widget.command == 'workbench.action.toggleSidebarVisibility',
        )
        .hitTestable();
    final panelToggle = find.descendant(
      of: find.byType(ChatScreen),
      matching: find.byType(SidePanelToggle),
    );
    final sash = find.byKey(const ValueKey('side-panel-sash'));
    Future<void> resize(double width) async {
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpAndSettle();
    }

    Future<void> tap(Finder toggle) async {
      await tester.tap(toggle);
      await tester.pumpAndSettle();
    }

    /// Whether the sidebar is docked and the panel shows, as the toggles
    /// have them and as laid out.
    (bool, bool) shown() {
      final sidebar =
          tester.widget<SidebarIconButton>(sidebarToggle).icon ==
          Codicons.layoutSidebarLeft;
      final panel = tester.widget<SidePanelToggle>(panelToggle).shown;
      expect(sash.evaluate().isNotEmpty, panel);
      // The conversation at the sidebar's right, or at the window's left.
      expect(tester.getRect(find.byType(ChatScreen)).left > 100, sidebar);
      return (sidebar, panel);
    }

    await tap(panelToggle);
    expect(shown(), (true, true));

    // The panel asked for last, the sidebar gives way to a narrow window,
    // and is back as it widens.
    await resize(800);
    expect(shown(), (false, true));
    await resize(1400);
    expect(shown(), (true, true));

    // Asked for, the sidebar stays and the panel closes, until asked again.
    await resize(800);
    await tap(sidebarToggle);
    expect(shown(), (true, false));
    await resize(1400);
    expect(shown(), (true, false));

    // As the panel, asked for again: the sidebar closes.
    await resize(800);
    await tap(panelToggle);
    expect(shown(), (false, true));
    await resize(1400);
    expect(shown(), (false, true));

    // The sidebar asked for last, the panel gives way to a narrow window.
    await tap(sidebarToggle);
    expect(shown(), (true, true));
    await resize(800);
    expect(shown(), (true, false));
    await resize(1400);
    expect(shown(), (true, true));
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
        matching: find.byType(SidePanelToggle),
      ),
    );
    expect(
      button.left,
      greaterThan(tester.getRect(find.byType(OpenInEditorButton)).right),
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
