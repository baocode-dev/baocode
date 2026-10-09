import 'package:bao_editor/monaco/flutter/editor_surface.dart';
import 'package:bao_editor/monaco/flutter/editor_surface_controller.dart';
import 'package:baocode/ide/ide_code_editor.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:baocode/theme/code_font.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => CodeFont.size.value = CodeFont.defaultSize);

  test('the code size moves code in an editor, not code among the '
      "interface's text", () {
    final chat = AppFonts.uiCodeStyle(12).fontSize;
    final editor = AppFonts.codeStyle(13).fontSize;
    CodeFont.size.value = CodeFont.defaultSize + 4;
    expect(AppFonts.uiCodeStyle(12).fontSize, chat);
    expect(AppFonts.codeStyle(13).fontSize, editor! + 4);
  });

  testWidgets('the interface text scale stops at code: CodeTextScale puts '
      "back the system's", (tester) async {
    late TextScaler interface;
    late TextScaler code;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.1)),
        child: SystemTextScale(
          scaler: const TextScaler.linear(1.1),
          child: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.65)),
            child: Builder(
              builder: (context) {
                interface = MediaQuery.textScalerOf(context);
                return CodeTextScale(
                  child: Builder(
                    builder: (context) {
                      code = MediaQuery.textScalerOf(context);
                      return const SizedBox();
                    },
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    expect(interface.scale(10), closeTo(16.5, 1e-9));
    expect(code.scale(10), closeTo(11, 1e-9));
  });

  testWidgets('the IDE editor keeps to the code size; one sized as the '
      "interface (the side panel's) to the interface's text", (tester) async {
    Future<(double, double)> pump({required bool interfaceSized}) async {
      final controller = EditorSurfaceController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: SystemTextScale(
            scaler: TextScaler.noScaling,
            child: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
              child: IdeCodeEditor(
                controller: controller,
                path: 'a.dart',
                interfaceSized: interfaceSized,
              ),
            ),
          ),
        ),
      );
      final surface = find.byType(EditorSurface);
      final scale = MediaQuery.textScalerOf(tester.element(surface)).scale(1);
      final size = tester.widget<EditorSurface>(surface).style.fontSize!;
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 20));
      return (scale, size);
    }

    CodeFont.size.value = CodeFont.defaultSize + 4;
    final (editorScale, editorSize) = await pump(interfaceSized: false);
    expect(editorScale, 1);
    expect(editorSize, AppFonts.codeStyle(13).fontSize);
    final (panelScale, panelSize) = await pump(interfaceSized: true);
    expect(panelScale, 1.5);
    expect(panelSize, AppFonts.uiCodeStyle(13).fontSize);
  });

  testWidgets('side panel code follows code size, not interface scale', (
    tester,
  ) async {
    final scale = ValueNotifier(1.0);
    final controller = EditorSurfaceController();
    addTearDown(scale.dispose);
    addTearDown(controller.dispose);
    controller.value = const TextEditingValue(
      text: 'description: example\ndocumentation: example',
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) {
          final media = MediaQuery.of(context);
          return SystemTextScale(
            scaler: media.textScaler,
            child: ValueListenableBuilder<double>(
              valueListenable: scale,
              child: child,
              builder: (context, value, child) => MediaQuery(
                data: media.copyWith(textScaler: TextScaler.linear(value)),
                child: child!,
              ),
            ),
          );
        },
        home: ValueListenableBuilder<double>(
          valueListenable: CodeFont.size,
          builder: (_, _, _) =>
              IdeCodeEditor(controller: controller, path: 'example.yaml'),
        ),
      ),
    );
    final surface = find.byType(EditorSurface);
    final state = tester.state(surface);
    final view = state as EditorSurfaceView;
    final height = view.lineHeight;
    final width = view.caretRectAt(12)!.left - view.caretRectAt(0)!.left;
    scale.value = 1.5;
    await tester.pump();
    expect(tester.state(surface), same(state));
    expect(view.lineHeight, closeTo(height, 1e-9));
    expect(
      view.caretRectAt(12)!.left - view.caretRectAt(0)!.left,
      closeTo(width, 1e-9),
    );
    CodeFont.size.value = CodeFont.defaultSize + 6;
    await tester.pump();
    expect(view.lineHeight, greaterThan(height * 1.4));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 20));
  });
}
