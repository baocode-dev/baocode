import 'package:baocode/chat/widgets/inline_code.dart';
import 'package:baocode/chat/widgets/markdown_view.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _selection = Color(0xFF00FF00);
const _hidden = Color(0x00000000);

void main() {
  test('finds where each code span is', () {
    const span = TextSpan(
      text: 'ab',
      children: [
        InlineCodeSpan(text: ' cd '),
        WidgetSpan(child: SizedBox()),
        TextSpan(children: [InlineCodeSpan(text: 'e')]),
      ],
    );
    expect(RenderInlineCodeBackdrop.codeRanges(span), const [
      TextSelection(baseOffset: 2, extentOffset: 6),
      TextSelection(baseOffset: 7, extentOffset: 8),
    ]);
  });

  testWidgets('a selection shows over inline code, whatever its background', (
    tester,
  ) async {
    // The default theme's is opaque, as Dark Modern's.
    expect(AppColors.inlineCodeBackground.a, 1);
    expect(MarkdownView.codeStyle.backgroundColor, isNull);
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: DefaultSelectionStyle(
          selectionColor: _selection,
          child: SelectionArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(
                key: key,
                child: const InlineCodeText(
                  TextSpan(
                    // Glyphs not drawn: only what is under them.
                    style: TextStyle(color: _hidden, fontSize: 20),
                    children: [
                      TextSpan(text: 'ab'),
                      InlineCodeSpan(text: ' code '),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    Future<Color> inCode() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final data = (await tester.runAsync(() async {
        final image = await boundary.toImage();
        return image.toByteData();
      }))!;
      // In the middle of " code ", which follows 2 glyphs of 20.
      final width = boundary.size.width.round();
      final at = (10 * width + 2 * 20 + 3 * 20) * 4;
      return Color.fromARGB(
        data.getUint8(at + 3),
        data.getUint8(at),
        data.getUint8(at + 1),
        data.getUint8(at + 2),
      );
    }

    expect(
      (await inCode()).toARGB32(),
      AppColors.inlineCodeBackground.toARGB32(),
    );
    tester
        .state<SelectableRegionState>(find.byType(SelectableRegion))
        .selectAll();
    await tester.pump();
    expect((await inCode()).toARGB32(), _selection.toARGB32());
  });

  testWidgets('code put on the next line leaves no background behind for '
      'its leading space', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: key,
            // "abcd " fills the first line; the code goes on the second.
            child: const SizedBox(
              width: 100,
              child: InlineCodeText(
                TextSpan(
                  style: TextStyle(color: _hidden, fontSize: 20),
                  children: [
                    TextSpan(text: 'abcd'),
                    InlineCodeSpan(text: ' code '),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final data = (await tester.runAsync(() async {
      final image = await boundary.toImage();
      return image.toByteData();
    }))!;
    final width = boundary.size.width.round();
    int at(int x, int y) => data.getUint32((y * width + x) * 4);

    // The leading space, at the end of the first line.
    expect(at(4 * 20 + 10, 10), 0);
    // The code, on the second.
    expect(at(30, 30), isNot(0));
  });
}
