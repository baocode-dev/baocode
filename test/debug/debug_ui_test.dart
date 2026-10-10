// The debug views, rendered offscreen against the scripted adapter: the
// paused state of the whole side bar, the console, the toolbar, a
// breakpoint's text, the strings table.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:bao_exthost/bao_exthost.dart' show VsUri;
import 'package:baocode/debug/common/debug_source.dart';
import 'package:baocode/debug/common/debug_types.dart';
import 'package:baocode/debug/common/repl_model.dart';
import 'package:baocode/debug/service/debug_service.dart';
import 'package:baocode/debug/ui/breakpoints_view.dart';
import 'package:baocode/debug/ui/call_stack_view.dart';
import 'package:baocode/debug/ui/debug_console_view.dart';
import 'package:baocode/debug/ui/debug_icons.dart';
import 'package:baocode/debug/ui/debug_strings.dart';
import 'package:baocode/debug/ui/debug_toolbar.dart';
import 'package:baocode/debug/ui/debug_view.dart';
import 'package:baocode/debug/ui/debug_widgets.dart';
import 'package:baocode/ide/ide_list.dart';
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
      final loader = FontLoader(family)
        ..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
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
  GlobalKey? key,
}) async {
  // The same key again keeps the tree (and its state) of the last capture.
  key ??= GlobalKey();
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
            // The background inside the boundary, so the image has it.
            child: RepaintBoundary(
              key: key,
              child: ColoredBox(
                color: themeColors['sideBar.background'],
                child: child,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await tester.runAsync(() async {
    final layer = boundary.debugLayer! as OffsetLayer;
    final picture = await layer.toImage(
      Offset.zero & boundary.size,
      pixelRatio: 2,
    );
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
    await f.service.enableOrDisableBreakpoints(
      false,
      f.service.model.getBreakpoints()[3],
    );
    final launch = f.service.configurationManager.getLaunches().first;
    await f.service.startDebugging(launch, {
      'type': 'fake',
      'request': 'launch',
      'name': 'Launch main.js',
      'program': r'${workspaceFolder}/main.js',
    });
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

  testWidgets('renders the call stack, variables and breakpoints', (
    tester,
  ) async {
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

  testWidgets('renders the debug console with output and an evaluation', (
    tester,
  ) async {
    await _loadFonts(tester);
    final service = await _pausedService(tester);
    await tester.runAsync(() async {
      final session = service.viewModel.focusedSession!;
      // Output logged three times at the same place (collapsed, counted,
      // with its source), and output with ANSI styles.
      final logged = ReplElementSource(
        source: Source({
          'name': 'main.js',
          'path': fakeProgramPath,
        }, session.getId()),
        lineNumber: 4,
        column: 3,
      );
      for (var i = 0; i < 3; i++) {
        session.appendToRepl(
          NewReplElementData(
            output: 'tick\n',
            sev: ReplSeverity.info,
            source: logged,
          ),
        );
      }
      session.appendToRepl(
        const NewReplElementData(
          output: '\x1b[31merror:\x1b[0m \x1b[1mboom\x1b[0m\n',
          sev: ReplSeverity.error,
        ),
      );
      await session.addReplExpression(
        service.viewModel.focusedStackFrame,
        'count',
      );
      await session.addReplExpression(
        service.viewModel.focusedStackFrame,
        'missing',
      );
      await session.addReplExpression(
        service.viewModel.focusedStackFrame,
        'user',
      );
      service.viewModel.setFocus(
        service.viewModel.focusedStackFrame,
        service.viewModel.focusedThread,
        session,
        false,
      );
    });
    final console = DebugConsoleView(service: service);
    final key = GlobalKey();
    await _capture(
      tester,
      console,
      'build/exthost-screens/debug_console.png',
      size: const Size(560, 420),
      key: key,
    );
    expect(find.textContaining('hello from the program'), findsWidgets);

    // Output as upstream's renderer: no empty line for the last line break,
    // identical lines once with their count, where they were logged on the
    // right (a link to it), ANSI styles applied and their codes hidden.
    final hello = tester.widget<SelectableText>(
      find.widgetWithText(SelectableText, 'hello from the program'),
    );
    expect(hello.data, isNot(endsWith('\n')));
    expect(find.widgetWithText(SelectableText, 'tick'), findsOneWidget);
    expect(tester.widget<IdeCountBadge>(find.byType(IdeCountBadge)).count, 3);
    expect(find.textContaining('\x1b', findRichText: true), findsNothing);
    final ansi = tester.widget<SelectableText>(
      find.widgetWithText(SelectableText, 'error: boom'),
    );
    final runs = ansi.textSpan!.children!.cast<TextSpan>();
    expect([for (final r in runs) r.text], ['error:', ' ', 'boom']);
    expect(runs[0].style!.color, isNot(runs[1].style!.color));
    expect(runs[2].style!.fontWeight, FontWeight.bold);
    final host = service.host as FakeDebugHost;
    await tester.tap(find.text('main.js:4'));
    await tester.pump();
    expect(host.opened.last.$1, _program);
    expect(host.opened.last.$2, const DebugRange(4, 3, 4, 3));
    // Inputs with their marker; their text lines up with the results'.
    expect(find.byIcon(Codicons.arrowSmallRight), findsNWidgets(3));
    expect(
      tester.getTopLeft(find.widgetWithText(SelectableText, 'count')).dx,
      tester.getTopLeft(find.widgetWithText(SelectableText, '3')).dx,
    );

    // Results like upstream's renderer: a number colored as one, a failure
    // an italic error, an object expandable to its variables.
    TextStyle styleOf(String text) => tester
        .widget<SelectableText>(find.widgetWithText(SelectableText, text))
        .style!;
    expect(styleOf('3').color, debugColor('debugTokenExpression.number'));
    expect(styleOf('3').fontStyle, isNot(FontStyle.italic));
    final error = styleOf('missing is not defined');
    expect(error.color, debugColor('debugTokenExpression.error'));
    expect(error.fontStyle, FontStyle.italic);
    final object = find.widgetWithText(
      SelectableText,
      '{name: "Ada", age: 36}',
    );
    expect(
      styleOf('{name: "Ada", age: 36}').fontStyle,
      isNot(FontStyle.italic),
    );
    expect(find.byType(DebugExpressionLabel), findsNothing);
    // The chevron left of the text.
    await tester.runAsync(() async {
      await tester.tapAt(tester.getTopLeft(object) + const Offset(-8, 8));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await _capture(
      tester,
      console,
      'build/exthost-screens/debug_console_expanded.png',
      size: const Size(560, 420),
      key: key,
    );
    expect(find.byType(DebugExpressionLabel), findsNWidgets(2));
    expect(find.textContaining('age: 36', findRichText: true), findsWidgets);
    service.dispose();
  });

  testWidgets('renders the toolbar', (tester) async {
    await _loadFonts(tester);
    final service = await _pausedService(tester);
    await _capture(
      tester,
      Center(
        child: DebugToolbar(service: service, hotReload: (_) => null),
      ),
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
      for (final key in [...DebugStrings.en.keys]) {
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
            DebugExpressionLabel(
              name: 'missing',
              value: 'not available',
              error: true,
            ),
          ],
        ),
      ),
    );
    expect(find.textContaining('count'), findsOneWidget);
    final richText = tester.widgetList<RichText>(find.byType(RichText)).first;
    expect(richText.text.toPlainText(), contains('count: 3'));
  });
}
