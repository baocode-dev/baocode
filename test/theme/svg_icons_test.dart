import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/theme/svg_icons.dart';

void main() {
  testWidgets('an SVG icon is its size in a larger box, as a glyph is, '
      'not stretched to fill it', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox.square(
            dimension: 40,
            child: AppIcon(SvgIcons.usage, size: 16),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(SvgPicture)), const Size(16, 16));
  });
}
