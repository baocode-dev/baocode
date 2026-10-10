import 'dart:io';
import 'dart:ui' as ui;

import 'package:baocode/chat/widgets/code_citation.dart';
import 'package:baocode/chat/widgets/markdown_view.dart';
import 'package:baocode/chat/widgets/mermaid_code_block.dart';
import 'package:baocode/theme/codicons.dart';
import 'package:baocode/theme/workbench_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mermaid_core/mermaid_core.dart' as mermaid;
import 'package:mermaid_flutter/mermaid_flutter.dart';

final _fontPath = Platform.environment['BAOCODE_MERMAID_FONT'];

const _flow =
    'flowchart TD\n'
    '  A[Start] --> B{Ready?}\n'
    '  B -->|Yes| C[Run]\n'
    '  B -->|No| D[Wait]\n'
    '  D --> B';

Finder get _paint => find.byWidgetPredicate(
  (widget) => widget is CustomPaint && widget.painter is ScenePainter,
);

mermaid.RenderScene _scene(WidgetTester tester) =>
    (tester.widget<CustomPaint>(_paint).painter! as ScenePainter).scene;

Future<void> _pump(
  WidgetTester tester,
  String code, {
  String language = 'mermaid',
  double width = 600,
  bool closed = true,
}) => tester.pumpWidget(
  MaterialApp(
    theme: ThemeData(fontFamily: _fontPath == null ? null : 'MermaidSnapshot'),
    home: Scaffold(
      body: SelectionArea(
        // As the chat's list scrolls: diagrams show whole, however tall.
        child: SingleChildScrollView(
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: MarkdownView(
                '```$language\n$code${closed ? '\n```' : ''}',
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

/// A mouse over the diagram, which shows its toolbar.
Future<TestGesture> _hover(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  await mouse.moveTo(tester.getCenter(find.byType(MermaidCodeBlock)));
  await tester.pump();
  return mouse;
}

Future<void> _snapshot(WidgetTester tester, String name) async {
  final directory = Platform.environment['BAOCODE_MERMAID_SNAPSHOTS'];
  if (directory == null) return;
  await tester.runAsync(() async {
    final image = await captureImage(tester.element(find.byType(MarkdownView)));
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$directory/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    final path = _fontPath;
    if (path == null) return;
    final loader = FontLoader('MermaidSnapshot')
      ..addFont(File(path).readAsBytes().then(ByteData.sublistView));
    await loader.load();
    final icons = FontLoader(Codicons.fontFamily)
      ..addFont(
        File('assets/codicons/codicon.ttf')
            .readAsBytes()
            .then(ByteData.sublistView),
      );
    await icons.load();
  });

  testWidgets('a Mermaid fence paints nodes and edges, not source text', (
    tester,
  ) async {
    await _pump(tester, _flow, language: 'MERMAID title="Flow"');
    expect(find.byType(MermaidCodeBlock), findsOneWidget);
    expect(_paint, findsOneWidget);
    expect(find.text(_flow), findsNothing);
    final scene = _scene(tester);
    expect(scene.nodes, isNotEmpty);
    expect(scene.size.width, greaterThan(0));
    expect(scene.size.height, greaterThan(0));
    await tester.runAsync(() async {
      final image = await captureImage(tester.element(_paint));
      final pixels = (await image.toByteData())!.buffer.asUint32List();
      expect(pixels.toSet().length, greaterThan(3));
      image.dispose();
    });
    expect(tester.takeException(), isNull);
    await _snapshot(tester, 'flow_dark');
  });

  testWidgets('ordinary fences and citations keep their existing cards', (
    tester,
  ) async {
    await _pump(tester, _flow, language: 'text');
    expect(find.byType(MermaidCodeBlock), findsNothing);
    expect(find.text(_flow), findsOneWidget);
    await _pump(tester, _flow, language: '1:6:flow.mermaid');
    expect(find.byType(CodeCitationCard), findsOneWidget);
    expect(find.byType(MermaidCodeBlock), findsNothing);
  });

  testWidgets('shared MarkdownBlocks also renders a nested Mermaid fence', (
    tester,
  ) async {
    final nodes = MarkdownView.document().parse(
      '> ```mermaid\n> graph LR; A --> B\n> ```',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownBlocks(nodes: nodes, style: MarkdownView.baseStyle),
        ),
      ),
    );
    expect(_paint, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a bare diagram: no card, no fold, no background of its own', (
    tester,
  ) async {
    await _pump(tester, _flow);
    expect(find.byType(MarkdownCodeBlock), findsNothing);
    expect(find.byIcon(Codicons.chevronDown), findsNothing);
    expect(_scene(tester).background, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the diagram and its toolbar sit at the start, not centered', (
    tester,
  ) async {
    await _pump(tester, 'graph LR; A --> B');
    final block = tester.getRect(find.byType(MermaidCodeBlock));
    final diagram = tester.getRect(_paint);
    expect(diagram.width, lessThan(block.width / 2));
    expect(diagram.topLeft, block.topLeft);
    final toolbar = tester.getRect(
      find.ancestor(
        of: find.byIcon(Codicons.code),
        matching: find.byType(PositionedDirectional),
      ),
    );
    expect(toolbar.topLeft, block.topLeft);
  });

  testWidgets('hover toolbar switches to the source and back, and copies', (
    tester,
  ) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _pump(tester, _flow);
    expect(
      tester
          .widget<Visibility>(
            find.ancestor(
              of: find.byIcon(Codicons.copy),
              matching: find.byType(Visibility),
            ),
          )
          .visible,
      isFalse,
    );
    await _hover(tester);
    await tester.tap(find.byIcon(Codicons.copy));
    await tester.pump();
    expect(copied, [_flow]);
    await tester.tap(find.byIcon(Codicons.code));
    await tester.pump();
    expect(find.byType(MarkdownCodeBlock), findsOneWidget);
    expect(find.text(_flow), findsOneWidget);
    expect(_paint, findsNothing);
    await tester.tap(find.byIcon(Codicons.preview));
    await tester.pump();
    expect(find.byType(MarkdownCodeBlock), findsNothing);
    expect(_paint, findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('tapping the diagram opens it expanded', (tester) async {
    await _pump(tester, _flow);
    await tester.tap(_paint);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    await tester.tap(find.byIcon(Codicons.close));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('expand opens a pannable and zoomable diagram, close returns', (
    tester,
  ) async {
    await _pump(tester, _flow);
    await _hover(tester);
    await tester.tap(find.byIcon(Codicons.screenFull));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    expect(viewer.maxScale, greaterThan(1));
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(find.byType(InteractiveViewer)),
        scrollDelta: const Offset(0, -100),
      ),
    );
    await tester.pump();
    final transform = tester.widget<Transform>(
      find
          .descendant(
            of: find.byType(InteractiveViewer),
            matching: find.byType(Transform),
          )
          .first,
    );
    expect(transform.transform.getMaxScaleOnAxis(), greaterThan(1));
    await tester.drag(find.byType(InteractiveViewer), const Offset(40, 20));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byIcon(Codicons.close));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(_paint, findsOneWidget);
  });

  testWidgets('the expanded dialog hugs a small diagram at its own size', (
    tester,
  ) async {
    await _pump(tester, 'graph LR; A --> B');
    final scene = _scene(tester);
    await tester.tap(_paint);
    await tester.pumpAndSettle();
    final dialog = tester.getSize(
      find.descendant(of: find.byType(Dialog), matching: find.byType(Material)),
    );
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(dialog.width, lessThan(screen.width - 80));
    expect(dialog.height, lessThan(screen.height - 80));
    final painted = tester.getSize(
      find.descendant(of: find.byType(Dialog), matching: _paint),
    );
    expect(
      (painted.width, painted.height),
      (scene.size.width, scene.size.height),
    );
    final shape =
        tester.widget<Dialog>(find.byType(Dialog)).shape!
            as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(8));
    await tester.tap(find.byIcon(Codicons.close));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanded wide scenes can reach native text size', (
    tester,
  ) async {
    await _pump(tester, 'graph LR; A[${'x' * 15000}]');
    final scene = _scene(tester);
    await _hover(tester);
    await tester.tap(find.byIcon(Codicons.screenFull));
    await tester.pumpAndSettle();
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    final viewport = tester.getSize(find.byType(InteractiveViewer));
    final fit = (viewport.width - 48) / scene.size.width;
    expect(viewer.maxScale * fit, greaterThanOrEqualTo(1));
    await tester.tap(find.byIcon(Codicons.close));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide diagrams shrink to a narrow column, tall ones show whole', (
    tester,
  ) async {
    for (final direction in ['LR', 'TD']) {
      final code =
          'graph $direction; '
          '${[for (var i = 0; i < 10; i++) 'N$i[Node $i]'].join(' --> ')}';
      await _pump(tester, code, width: 220);
      await tester.pump(const Duration(milliseconds: 200));
      expect(_paint, findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(MermaidCodeBlock),
          matching: find.byType(Scrollable),
        ),
        findsNothing,
      );
      final scene = _scene(tester);
      final rect = tester.getRect(_paint);
      expect(rect.width, lessThanOrEqualTo(220.001));
      expect(
        rect.width / rect.height,
        closeTo(scene.size.width / scene.size.height, 0.01),
      );
      if (direction == 'TD') {
        expect(scene.size.height, greaterThan(344));
        expect(rect.height, closeTo(scene.size.height, 0.01));
      } else {
        expect(rect.width, lessThan(scene.size.width));
      }
      expect(tester.takeException(), isNull);
      await _snapshot(tester, 'narrow_$direction');
    }
  });

  testWidgets('bad, unsupported and oversized sources remain copyable code', (
    tester,
  ) async {
    for (final code in [
      '',
      'not a diagram',
      'flowchart TD\nA[unclosed',
      'flowchart TD\n${'a' * 16001}',
      'graph TD\n${[for (var i = 0; i < 101; i++) 'N$i'].join(';')}',
      'graph TD\n${'%% comment\n' * 201}A --> B',
      'graph TD\n${'A --> B;' * 201}',
      'packet-beta\n0-1000000000: "x"',
      '---\nconfig:\n  packet:\n    bitsPerRow: 0.1\n---\npacket-beta\n0-7: "x"',
      'graph TD; ${List.filled(1900, 'A').join(' & ')} --> '
          '${List.filled(1900, 'A').join(' & ')}',
    ]) {
      await _pump(tester, code);
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        _paint,
        findsNothing,
        reason: code.substring(0, code.length.clamp(0, 40)),
      );
      expect(find.byType(MarkdownCodeBlock), findsOneWidget);
      expect(find.text(code), findsOneWidget);
      expect(find.byIcon(Codicons.copy), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'stream updates debounce, recover and cannot leave stale scenes',
    (tester) async {
      await _pump(tester, 'graph TD; A --> B', closed: false);
      expect(_paint, findsOneWidget);
      final first = _scene(tester);
      // An ordinary rebuild reuses the parsed scene.
      await _pump(tester, 'graph TD; A --> B', closed: false);
      expect(identical(_scene(tester), first), isTrue);
      await _pump(tester, 'graph TD; A[unfinished', closed: false);
      expect(_paint, findsNothing);
      await tester.pump(const Duration(milliseconds: 100));
      await _pump(tester, 'graph TD; A[Finished] --> B', closed: false);
      await tester.pump(const Duration(milliseconds: 100));
      expect(_paint, findsNothing);
      await tester.pump(const Duration(milliseconds: 100));
      expect(_paint, findsOneWidget);
      expect(identical(_scene(tester), first), isFalse);
      await _pump(tester, 'not mermaid');
      await tester.pump(const Duration(milliseconds: 200));
      expect(_paint, findsNothing);
      await _pump(tester, _flow);
      await tester.pump(const Duration(milliseconds: 200));
      expect(_paint, findsOneWidget);
      await _pump(tester, 'graph TD; A');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('same-brightness and light theme changes repaint the diagram', (
    tester,
  ) async {
    final themes = WorkbenchThemeService.instance;
    await tester.runAsync(themes.initialize);
    await _pump(tester, _flow);
    final first = _scene(tester);
    await tester.runAsync(() => themes.setColorTheme('Red'));
    await _pump(tester, _flow);
    expect(identical(_scene(tester), first), isFalse);
    final dark = _scene(tester);
    await tester.runAsync(() => themes.setColorTheme('Solarized Light'));
    await _pump(tester, _flow);
    expect(identical(_scene(tester), dark), isFalse);
    expect(_scene(tester).background, isNull);
    expect(tester.takeException(), isNull);
    await _snapshot(tester, 'flow_light');
  });
}
