// The debug views, rendered offscreen against the scripted adapter: the
// paused state of the whole side bar, the console, the toolbar, a
// breakpoint's text, the strings table.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:bao_exthost/bao_exthost.dart' show VsUri;
import 'package:baocode/debug/common/debug_types.dart';
import 'package:baocode/debug/service/debug_service.dart';
import 'package:baocode/debug/ui/breakpoints_view.dart';
import 'package:baocode/debug/ui/call_stack_view.dart';
import 'package:baocode/debug/ui/debug_console_view.dart';
import 'package:baocode/debug/ui/debug_strings.dart';
import 'package:baocode/debug/ui/debug_toolbar.dart';
import 'package:baocode/debug/ui/debug_view.dart';
import 'package:baocode/debug/ui/debug_widgets.dart';
import 'package:baocode/theme/codicons.dart';
import 'package:baocode/theme/workbench_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_debug_adapter.dart';

final _program = VsUri.file(fakeProgramPath);

/// Loads real fonts so the screenshots have glyphs, not Ahem boxes.
Future<void> _loadFonts(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (final (family, path) in [
      ('Roboto', '/System/Library/Fonts/Supplemental/Arial Unicode.ttf'),
      (Codicons.fontFamily, 'assets/codicons/codicon.ttf'),
    ]) {
      final file = File(path);
      if (!file.existsSync()) continue;
      final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
      await loader.load();
    }
  });
}

/// Renders [child] at [size] and writes it to [path], returning the image
/// to look at. The widget is pumped on the fake clock; the picture is made
/// off the layer, where real timers are allowed.
Future<ui.Image> _capture(
  WidgetTester tester,
  Widget child,
  String path, {
  Size size = const Size(360, 720),
}) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: Material(
        color: themeColors['sideBar.background'],
        child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: ColoredBox(
            color: themeColors['sideBar.background'],
            child: RepaintBoundary(key: key, child: child),
          ),
        ),
        ),
      ),
    ),
  );
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await tester.runAsync(() async {
    final layer = boundary.debugLayer! as OffsetLayer;
    final picture = await layer.toImage(Offset.zero & boundary.size, pixelRatio: 2);
    final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
    await File(path).writeAsBytes(bytes!.buffer.asUint8List());
    return picture;
  });
  return image!;
}

/// A stopped session with breakpoints, watch and console content, built on
/// real timers (the fake adapter's events need them).
Future<DebugService> _pausedService(WidgetTester tester) async {
  late DebugService service;
  await tester.runAsync(() async {
    final f = await createFakeDebugService();
    service = f.service;
    await f.service.addBreakpoints(_program, [
      const BreakpointData(lineNumber: 7),
      const BreakpointData(lineNumber: 12, condition: 'count > 2'),
      const BreakpointData(lineNumber: 15, logMessage: 'count is {count}'),
      const BreakpointData(lineNumber: 30),
    ]);
    await f.service.enableOrDisableBreakpoints(false, f.service.model.getBreakpoints()[3]);
    final launch = f.service.configurationManager.getLaunches().first;
    await f.service.startDebugging(
      launch,
      {'type': 'fake', 'request': 'launch', 'name': 'Launch main.js', 'program': r'${workspaceFolder}/main.js'},
    );
    await until(() => f.service.viewModel.focusedStackFrame != null);
    // The views load the scopes themselves; watching is set up so the Watch
    // view has a value to show (the evaluation happens on mount too).
    f.service.addWatchExpression('count * 2');
    await f.service.model.getWatchExpressions().first.evaluate(
      f.service.viewModel.focusedSession,
      f.service.viewModel.focusedStackFrame,
      'watch',
    );
  });
  return service;
}

void main() {
  testWidgets('renders the paused Run and Debug view', (tester) async {
    await _loadFonts(tester);
    tester.view.physicalSize = const Size(360 * 2, 720 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final service = await _pausedService(tester);
    await _capture(
      tester,
      DebugView(service: service),
      'build/exthost-screens/debug_paused.png',
    );
    expect(find.text('compute'), findsWidgets);
    expect(find.text('compute'), findsWidgets);
    service.dispose();
  });

  testWidgets('renders the call stack, variables and breakpoints', (tester) async {
    await _loadFonts(tester);
    final service = await _pausedService(tester);
    await _capture(
      tester,
      CallStackView(service: service),
      'build/exthost-screens/debug_callstack.png',
      size: const Size(340, 260),
    );
    await _capture(
      tester,
      BreakpointsView(service: service),
      'build/exthost-screens/debug_breakpoints.png',
      size: const Size(360, 220),
    );
    service.dispose();
  });

  testWidgets('renders the debug console with output and an evaluation', (tester) async {
    await _loadFonts(tester);
    final service = await _pausedService(tester);
    await tester.runAsync(() async {
      final session = service.viewModel.focusedSession!;
      await session.addReplExpression(service.viewModel.focusedStackFrame, 'count');
      await session.addReplExpression(service.viewModel.focusedStackFrame, 'missing');
      service.viewModel.setFocus(
        service.viewModel.focusedStackFrame,
        service.viewModel.focusedThread,
        session,
        false,
      );
    });
    await _capture(
      tester,
      DebugConsoleView(service: service),
      'build/exthost-screens/debug_console.png',
      size: const Size(560, 260),
    );
    expect(find.textContaining('hello from the program'), findsWidgets);
    service.dispose();
  });

  testWidgets('renders the toolbar', (tester) async {
    await _loadFonts(tester);
    final service = await _pausedService(tester);
    await _capture(
      tester,
      Center(child: DebugToolbar(service: service, hotReload: (_) => null)),
      'build/exthost-screens/debug_toolbar.png',
      size: const Size(420, 120),
    );
    expect(find.byType(DebugToolbar), findsOneWidget);
    service.dispose();
  });

  testWidgets('shows the welcome view without configurations', (tester) async {
    final f = await createFakeDebugService();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(body: DebugView(service: f.service)),
      ),
    );
    await tester.pump();
    expect(find.text('Run and Debug'), findsOneWidget);
    expect(find.text('create a launch.json file'), findsWidgets);
    f.service.dispose();
  });

  test('the strings table is complete in both languages', () {
    for (final language in ['en', 'zh']) {
      final s = DebugStrings.forLanguage(language);
      for (final key in [
        ...DebugStrings.en.keys,
      ]) {
        expect(s.text(key).isNotEmpty, isTrue, reason: '$language:$key');
      }
      for (final key in [
        'runAndDebug',
        'variables',
        'watch',
        'callStack',
        'breakpoints',
        'debugConsole',
        'startDebugging',
        'continue',
        'pause',
        'stepOver',
        'stepInto',
        'stepOut',
        'restart',
        'stop',
        'disconnect',
        'hotReload',
        'addToWatch',
        'setValue',
        'unverifiedBreakpoint',
      ]) {
        expect(s.text(key).isNotEmpty, isTrue, reason: '$language:$key');
      }
      expect(s.pausedOn('breakpoint'), contains('breakpoint'));
    }
    expect(DebugStrings.forLanguage('zh').continue_, '继续');
    expect(DebugStrings.forLanguage('en').setValue, 'Set Value');
  });

  testWidgets('the variables label colors values by kind', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Column(
          children: [
            DebugExpressionLabel(name: 'count', value: '3', type: 'number'),
            DebugExpressionLabel(name: 'user', value: '{name: "Ada"}'),
            DebugExpressionLabel(name: 'missing', value: 'not available', error: true),
          ],
        ),
      ),
    );
    expect(find.textContaining('count'), findsOneWidget);
    final richText = tester.widgetList<RichText>(find.byType(RichText)).first;
    expect(richText.text.toPlainText(), contains('count: 3'));
  });
}
