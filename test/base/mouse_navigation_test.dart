import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/base/mouse_navigation.dart';

void main() {
  testWidgets('the innermost that goes back has the press; one that does '
      'not leaves it to those around it', (tester) async {
    final went = <String>[];
    var innerGoes = true;
    await tester.pumpWidget(
      MouseNavigation(
        onBack: () {
          went.add('outer back');
          return true;
        },
        onForward: () {
          went.add('outer forward');
          return true;
        },
        child: Center(
          child: MouseNavigation(
            onBack: () {
              went.add('inner back');
              return innerGoes;
            },
            child: const SizedBox.square(dimension: 100),
          ),
        ),
      ),
    );
    Future<void> press(int buttons, {Offset? at}) => tester.tapAt(
      at ?? tester.getCenter(find.byType(SizedBox)),
      buttons: buttons,
      kind: PointerDeviceKind.mouse,
    );

    await press(kBackMouseButton);
    expect(went, ['inner back']);
    innerGoes = false;
    await press(kBackMouseButton);
    expect(went, ['inner back', 'inner back', 'outer back']);
    // Forward: the inner has none.
    went.clear();
    await press(kForwardMouseButton);
    expect(went, ['outer forward']);
    // Outside the inner, the outer alone; the primary button, neither.
    went.clear();
    await press(kBackMouseButton, at: const Offset(2, 2));
    await press(kPrimaryMouseButton);
    expect(went, ['outer back']);
  });
}
