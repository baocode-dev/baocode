import 'dart:io';
import 'dart:ui' as ui;

import 'package:baocode/chat/widgets/code_citation.dart';
import 'package:baocode/chat/widgets/content_image.dart';
import 'package:baocode/chat/widgets/markdown_view.dart';
import 'package:baocode/chat/widgets/mermaid_code_block.dart';
import 'package:baocode/chat/widgets/mermaid_theme.dart';
import 'package:baocode/theme/codicons.dart';
import 'package:baocode/theme/workbench_theme.dart';
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

  testWidgets('tapping the diagram, or expand, shows it as a picture', (
    tester,
  ) async {
    Finder picture() => find.byWidgetPredicate(
      (widget) => widget is Image && widget.image is MemoryImage,
    );
    for (final open in ['tap', 'expand']) {
      await _pump(tester, _flow);
      if (open == 'expand') await _hover(tester);
      await tester.runAsync(() async {
        await tester.tap(
          open == 'tap' ? _paint : find.byIcon(Codicons.screenFull),
        );
        // The picture is made off the frame.
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();
      expect(picture(), findsWidgets, reason: open);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(picture(), findsNothing, reason: open);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('its picture: on the background, a margin round it, sharp', (
    tester,
  ) async {
    await _pump(tester, 'graph LR; A --> B');
    final scene = _scene(tester);
    const background = Color(0xff202124);
    final (width, height, corner) = (await tester.runAsync(() async {
      final picture = await mermaidPicture(scene, background: background);
      expect(picture.mediaType, 'image/png');
      final codec = await ui.instantiateImageCodec(picture.bytes);
      final image = (await codec.getNextFrame()).image;
      final pixels = await image.toByteData();
      final corner = Color.fromARGB(
        pixels!.getUint8(3),
        pixels.getUint8(0),
        pixels.getUint8(1),
        pixels.getUint8(2),
      );
      return (image.width, image.height, corner);
    }))!;
    expect(width, ((scene.size.width + 48) * 3).ceil());
    expect(height, ((scene.size.height + 48) * 3).ceil());
    expect(corner, background);
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

  test('a theme with its sequence colors: those changed, the rest kept', () {
    const base = mermaid.MermaidTheme.darkTheme;
    const gold = mermaid.Color(0xffd4a15a);
    final themed = base.withSequenceColors(
      actorBorder: gold,
      noteBkgColor: gold,
    );
    expect(themed.actorBorder, gold);
    expect(themed.noteBkgColor, gold);
    expect(themed.actorBkg, base.actorBkg);
    expect(themed.pie1, base.pie1);
    expect(themed.xyChartPlotColorPalette, base.xyChartPlotColorPalette);
    expect(base.withSequenceColors(), base);
  });

  test('a top-down flowchart drawn across: its header only', () {
    expect(mermaidAcross('flowchart TD\n  A --> B'), 'flowchart LR\n  A --> B');
    expect(mermaidAcross('%% c\ngraph\nA --> B'), '%% c\ngraph LR\nA --> B');
    expect(mermaidAcross('graph TB;\nA-->B'), 'graph LR;\nA-->B');
    expect(mermaidAcross('flowchart BT\nA-->B'), 'flowchart RL\nA-->B');
    expect(mermaidAcross('flowchart LR\nA-->B'), isNull);
    expect(mermaidAcross('graph TD; A-->B'), isNull);
    expect(mermaidAcross('sequenceDiagram\nA->>B: hi'), isNull);
  });

  testWidgets('a tall top-down flowchart is drawn across where the column '
      'fits it so, down where it does not', (tester) async {
    final code = [
      'flowchart TD',
      for (var i = 0; i < 4; i++) '  N$i[Step $i] --> N${i + 1}[Step ${i + 1}]',
    ].join('\n');
    await _pump(tester, code, width: 800);
    await tester.pump(const Duration(milliseconds: 200));
    var scene = _scene(tester);
    expect(scene.size.width, greaterThan(scene.size.height));

    await _pump(tester, code, width: 160);
    await tester.pump(const Duration(milliseconds: 200));
    scene = _scene(tester);
    expect(scene.size.height, greaterThan(scene.size.width));
    expect(tester.takeException(), isNull);
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

  testWidgets('a fence still being written: a placeholder, not its source; '
      'drawn at once closed, or once it goes quiet', (tester) async {
    Finder placeholder() => find.byType(ContentImagePlaceholder);
    await _pump(tester, 'graph LR; A --> B', closed: false);
    expect(placeholder(), findsOneWidget);
    expect(_paint, findsNothing);
    expect(find.textContaining('graph LR'), findsNothing);
    await _pump(tester, 'graph LR; A[Finished] --> B', closed: false);
    expect(placeholder(), findsOneWidget);
    await _pump(tester, 'graph LR; A[Finished] --> B');
    expect(placeholder(), findsNothing);
    expect(_paint, findsOneWidget);

    await _pump(tester, 'graph LR; A --> C', closed: false);
    expect(placeholder(), findsOneWidget);
    await tester.pump(MermaidCodeBlock.quietFor);
    expect(placeholder(), findsNothing);
    expect(_paint, findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a closed fence changed: debounced, never a stale scene', (
    tester,
  ) async {
    await _pump(tester, 'graph TD; A --> B');
    expect(_paint, findsOneWidget);
    final first = _scene(tester);
    // An ordinary rebuild reuses the parsed scene.
    await _pump(tester, 'graph TD; A --> B');
    expect(identical(_scene(tester), first), isTrue);
    await _pump(tester, 'graph TD; A[Finished] --> B');
    await tester.pump(const Duration(milliseconds: 100));
    expect(_paint, findsNothing);
    await tester.pump(const Duration(milliseconds: 100));
    expect(_paint, findsOneWidget);
    expect(identical(_scene(tester), first), isFalse);
    await _pump(tester, 'not mermaid');
    await tester.pump(const Duration(milliseconds: 200));
    expect(_paint, findsNothing);
    await _pump(tester, 'graph TD; A');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
  });

  test('its lines square: ELK asked for first, after any front matter', () {
    const elk = '%%{init: {"layout": "elk"}}%%\n';
    expect(mermaidSquare('graph LR\nA-->B'), '${elk}graph LR\nA-->B');
    expect(
      mermaidSquare('---\ntitle: T\n---\ngraph LR\nA-->B'),
      '---\ntitle: T\n---\n${elk}graph LR\nA-->B',
    );
  });

  testWidgets('a flowchart\'s lines are square', (tester) async {
    await _pump(tester, 'graph LR; A --> B; B --> C; A --> C; C -.-> A');
    var diagonal = 0;
    var cubic = 0;
    void visit(mermaid.SceneNode node) {
      if (node is mermaid.SceneGroup) node.children.forEach(visit);
      if (node case mermaid.SceneShape(
        geometry: mermaid.PathGeometry(:final commands),
      )) {
        mermaid.Point? at;
        for (final command in commands) {
          if (command is mermaid.CubicTo) cubic++;
          if (command is mermaid.MoveTo) at = command.p;
          if (command is mermaid.LineTo) {
            final from = at!;
            if ((command.p.x - from.x).abs() > 0.5 &&
                (command.p.y - from.y).abs() > 0.5) {
              diagonal++;
            }
            at = command.p;
          }
        }
      }
    }

    _scene(tester).nodes.forEach(visit);
    expect((cubic, diagonal), (0, 0));
  });

  test('its text\'s entities read as Mermaid\'s HTML labels show them', () {
    String read(String text) => (mermaidUnescaped(
      mermaid.SceneText(
        text: text,
        bounds: const mermaid.Rect.fromLTWH(0, 0, 10, 10),
        style: const mermaid.TextStyleSpec(fontFamily: 'x', fontSize: 13),
        color: const mermaid.Color(0xff000000),
      ),
    ) as mermaid.SceneText).text;
    expect(read('Stream&lt;KernelEvent&gt;'), 'Stream<KernelEvent>');
    expect(read('a #lt; b #35; &#60; &#x3C; &amp;'), 'a < b # < < &');
    expect(read('issue #12; &60; &bogus;'), 'issue #12; &60; &bogus;');
  });

  test('a fence still being written is told from one closed', () {
    expect(endsInOpenFence('a\n```mermaid\ngraph LR'), isTrue);
    expect(endsInOpenFence('a\n```mermaid\ngraph LR\n```'), isFalse);
    expect(endsInOpenFence('```\nx\n```\n\n~~~js\ny'), isTrue);
    expect(endsInOpenFence('see ```inline``` code'), isFalse);
  });

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
