import 'package:baocode/icons/kernel_badge.dart';
import 'package:baocode/sidebar/sidebar.dart';
import 'package:baocode/chat/widgets/pixel_loader.dart';
import 'package:baocode/workspace/workspace.dart' show ThreadStatus;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget mark(ThreadStatus status, {bool antigravity = true}) => Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: KernelStatusMark(
        status: status,
        mark: antigravity ? (size) => AntigravityBadge(size: size) : null,
      ),
    ),
  );

  testWidgets('Antigravity’s mark while idle', (tester) async {
    await tester.pumpWidget(mark(ThreadStatus.idle));
    expect(find.byType(AntigravityBadge), findsOneWidget);
    expect(tester.getSize(find.byType(AntigravityBadge)), const Size(14, 14));
  });

  testWidgets('the spinner in its place while it runs', (tester) async {
    await tester.pumpWidget(mark(ThreadStatus.running));
    expect(find.byType(AntigravityBadge), findsNothing);
    expect(find.byType(PixelLoader), findsOneWidget);
  });

  testWidgets('a dot on it while it waits', (tester) async {
    await tester.pumpWidget(mark(ThreadStatus.needsInput));
    expect(find.byType(AntigravityBadge), findsOneWidget);
    expect(find.byType(Positioned), findsOneWidget);
  });

  testWidgets('no mark for a kernel without one', (tester) async {
    await tester.pumpWidget(mark(ThreadStatus.idle, antigravity: false));
    expect(find.byType(AntigravityBadge), findsNothing);
  });
}
