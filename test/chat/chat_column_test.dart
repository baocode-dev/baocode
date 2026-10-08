import 'package:baocode/chat/chat_column.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the column stays in the middle, narrower at its right where it '
      'would come within the inset', () {
    ({double left, double width}) place(double width, double right) =>
        RenderChatColumn.place(width, maxWidth: 720, right: right);

    // Room enough: in the middle, as without.
    expect(place(1000, 66), (left: 140.0, width: 720.0));
    expect(place(1000, 0), (left: 140.0, width: 720.0));
    // Less: the same left, short of the inset.
    expect(place(800, 66), (left: 40.0, width: 694.0));
    expect(place(500, 50), (left: 0.0, width: 450.0));
    // None at all.
    expect(place(40, 66), (left: 0.0, width: 0.0));
  });

  testWidgets('laid out, a narrower child is in the column\'s middle', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 800,
            child: ChatColumn(
              maxWidth: 720,
              right: 66,
              child: SizedBox(key: ValueKey('child'), width: 600, height: 10),
            ),
          ),
        ),
      ),
    );
    final child = tester.getRect(find.byKey(const ValueKey('child')));
    expect(child.left, 40 + (694 - 600) / 2);
    expect(tester.getSize(find.byType(ChatColumn)), const Size(800, 10));
  });
}
