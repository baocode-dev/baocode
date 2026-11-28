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

  test('mergeLineRects merges runs on the same line and keeps lines separate', () {
    // Leading monospace space, taller CJK fallback run, trailing monospace space
    // on line 1, plus a wrapped run on line 2 whose top slightly touches line 1.
    final merged = RenderInlineCodeBackdrop.mergeLineRects(const [
      Rect.fromLTRB(10, 2, 18, 16),
      Rect.fromLTRB(18, 0, 44, 18),
      Rect.fromLTRB(44, 2, 52, 16),
      Rect.fromLTRB(0, 17, 30, 35),
      Rect.fromLTRB(30, 19, 38, 33),
    ]);
    expect(merged, const [
      Rect.fromLTRB(10, 0, 52, 18),
      Rect.fromLTRB(0, 17, 38, 35),
    ]);
  });

  testWidgets('mixed-size runs inside one InlineCodeSpan paint one unified '
      'rectangle with uniform height', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: key,
            child: const InlineCodeText(
              TextSpan(
                style: TextStyle(color: _hidden, fontSize: 20),
                children: [
                  InlineCodeSpan(
                    children: [
                      TextSpan(text: ' ', style: TextStyle(fontSize: 12)),
                      TextSpan(text: 'ab', style: TextStyle(fontSize: 24)),
                      TextSpan(text: ' ', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ],
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
    final height = boundary.size.height.round();
    int alphaAt(int x, int y) => data.getUint8((y * width + x) * 4 + 3);

    // Top row of the merged box (where the taller middle run reaches, well
    // above the shorter 12px leading/trailing spaces): should be painted over
    // the leading and trailing space columns too, not indented into 3 pills.
    final paintedRows = <int>[
      for (var y = 0; y < height; y++)
        if (alphaAt(width ~/ 2, y) > 0) y,
    ];
    expect(paintedRows, isNotEmpty);
    final nearTop = paintedRows.first + 4;
    expect(alphaAt(4, nearTop), greaterThan(0));
    expect(alphaAt(width - 5, nearTop), greaterThan(0));
  });
}
