// Document colors in the real editor: a provider's swatch is painted before
// its color, a click opens the picker, a drag on the picker writes the
// provider's presentation of the picked color and the header switches
// presentations (goal 五.3 colors; screenshot for 第十节 验证方式 2:
// build/exthost-screens/editor_color_picker.png).

import 'dart:io';
import 'dart:ui' as ui;

import 'package:bao_editor/monaco/flutter/editor_document_model.dart';
import 'package:bao_editor/monaco/flutter/editor_surface.dart';
import 'package:bao_editor/monaco/flutter/editor_view_painters.dart';
import 'package:baocode/ide/file_service.dart';
import 'package:baocode/ide/ide_editor.dart';
import 'package:baocode/ide/ide_editor_colors.dart';
import 'package:baocode/ide/ide_workspace.dart';
import 'package:baocode/theme/code_font.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'workbench/fake_files.dart';

class _MemoryFiles with ReadWriteOnlyFiles implements IdeFileService {
  _MemoryFiles(this.contents);

  final Map<String, String> contents;

  @override
  Future<List<IdeFile>> list(String directory) async => [];

  @override
  Future<String> read(String path, {bool force = false}) async =>
      contents[path]!;

  @override
  Future<void> write(String path, String text, {String? expectedText}) async {
    contents[path] = text;
  }
}

final _root = p.join(p.separator, 'colors-project');
final _file = p.join(_root, 'style.css');

Future<void> _loadFonts(WidgetTester tester) async {
  await tester.runAsync(() async {
    final root = Platform.environment['FLUTTER_ROOT'];
    for (final (family, path) in [
      ('ScreenMono', '/System/Library/Fonts/Monaco.ttf'),
      if (root != null)
        (
          'Roboto',
          '$root/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
        ),
    ]) {
      if (!File(path).existsSync()) continue;
      await (FontLoader(
        family,
      )..addFont(File(path).readAsBytes().then(ByteData.sublistView))).load();
    }
  });
}

String _hex(Color color) {
  String byte(double value) =>
      (value * 255).round().toRadixString(16).padLeft(2, '0');
  return '#${byte(color.r)}${byte(color.g)}${byte(color.b)}';
}

void main() {
  testWidgets('a swatch click opens the picker; a drag writes the provider '
      'presentation; the header switches presentations', (tester) async {
    await _loadFonts(tester);
    final families = CodeFont.families.value;
    CodeFont.families.value = ['ScreenMono'];
    addTearDown(() => CodeFont.families.value = families);
    tester.view.physicalSize = const Size(640 * 2, 360 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final workspace = IdeWorkspace(
      _root,
      files: _MemoryFiles({_file: 'body {\n  color: #0000ff;\n}\n'}),
    );
    addTearDown(workspace.dispose);
    await workspace.open(_file);
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(brightness: Brightness.dark, fontFamily: 'Roboto'),
          home: Scaffold(
            body: IdeEditor(
              workspace: workspace,
              active: workspace.active!,
              nativeEditorEnabled: true,
              onError: (error) => fail('$error'),
              onLspStatus: (_) {},
              onPositionChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final view = workspace.editorViews.active!;
    final colors = view.features.colors;
    final snapshot = view.controller.document.snapshot;
    final start = snapshot.text.indexOf('#0000ff');
    final asked = <(int, int, Color)>[];
    colors
      ..onPresentations = (color, from, to, value) async {
        asked.add((from, to, value));
        final current = view.controller.document.snapshot;
        return [
          for (final label in [
            _hex(value),
            'rgb(${(value.r * 255).round()}, ${(value.g * 255).round()}, '
                '${(value.b * 255).round()})',
          ])
            EditorColorPresentation(
              label,
              snapshot: current,
              edit: EditorOffsetEdit(from, to, label),
            ),
        ];
      }
      ..setColors(snapshot, [
        EditorDocumentColor(start, start + 7, const Color(0xff0000ff)),
      ]);
    await tester.pump();
    expect(colors.decorations.items.single.before?.backgroundColor,
        const Color(0xff0000ff));

    // The swatch sits before the color's text: after the caret there,
    // 3px apart, 10px wide.
    final gutter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<EditorGutterPainter>()
        .first;
    final caret = gutter.layout.caretRect(start);
    final swatchPoint =
        tester.getTopLeft(find.byType(EditorSurface)) +
        Offset(gutter.geometry.contentLeft + caret.left + 8, caret.center.dy);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: swatchPoint);
    await mouse.down(swatchPoint);
    await mouse.up();
    await tester.pump();
    expect(colors.picker, isNotNull, reason: 'the swatch was not hit');
    await tester.pump();
    expect(find.byKey(const ValueKey('color-picker')), findsOneWidget);
    expect(find.text('#0000ff'), findsOneWidget);
    expect(asked.single, (start, start + 7, const Color(0xff0000ff)));

    // Drag to the box's top-right corner: pure hue (red at the top of the
    // hue strip is 0°, the picker's hue is blue's 240°).
    final box = find.byKey(const ValueKey('color-picker-saturation'));
    final drag = await tester.startGesture(tester.getCenter(box));
    await tester.pump();
    await drag.moveTo(tester.getTopRight(box) + const Offset(-1, 1));
    await tester.pump();
    // Previewing writes nothing.
    expect(view.controller.document.text, contains('#0000ff'));
    await drag.up();
    await tester.pumpAndSettle();
    final picked = colors.picker!.value;
    expect(view.controller.document.text, contains(_hex(picked)));
    expect(picked.b, greaterThan(0.95));
    expect(picked.r, lessThan(0.05));

    if (Platform.environment['BAOCODE_EXTHOST_SCREENS'] case final dir?) {
      await tester.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 2);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        File(p.join(dir, 'editor_color_picker.png'))
          ..createSync(recursive: true)
          ..writeAsBytesSync(png!.buffer.asUint8List());
        image.dispose();
      });
    }

    // The header's label: the next presentation, written in place.
    await tester.tap(find.byKey(const ValueKey('color-picker-presentation')));
    await tester.pumpAndSettle();
    expect(view.controller.document.text, contains('color: rgb('));
    // One undo step per write.
    view.controller.undo();
    expect(view.controller.document.text, contains(_hex(picked)));
    await tester.pump();
    expect(find.byKey(const ValueKey('color-picker')), findsNothing);
    await mouse.removePointer();
  });
}
