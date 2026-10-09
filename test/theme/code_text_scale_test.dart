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
}
