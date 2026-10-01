import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import 'package:baocode/main.dart';
import 'package:baocode/workspace/workspace.dart';

void main() {
  testWidgets('a press stops a trackpad fling, so what is dragged over is '
      'what gets selected', (tester) async {
    String? copied;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await tester.pumpWidget(BaoCodeApp(workspace: Workspace.mock()));
    await tester.pump();
    final list = find.byType(SuperListView);
    final position = tester.widget<SuperListView>(list).controller!.position;

    // A quick two-finger swipe up: the list flings on after it.
    final at = tester.getCenter(list);
    final trackpad = TestPointer(1, PointerDeviceKind.trackpad);
    await tester.sendEventToBinding(trackpad.panZoomStart(at));
    var pan = Offset.zero;
    var time = Duration.zero;
    for (var i = 0; i < 8; i++) {
      pan += const Offset(0, 30);
      time += const Duration(milliseconds: 16);
      await tester.sendEventToBinding(
        trackpad.panZoomUpdate(at, pan: pan, timeStamp: time),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.sendEventToBinding(trackpad.panZoomEnd(timeStamp: time));
    await tester.pump(const Duration(milliseconds: 16));
    expect(position.isScrollingNotifier.value, isTrue);

    // Pressed on a line while it moves: it stops there.
    final view = tester.getRect(list);
    final line = find
        .descendant(of: list, matching: find.byType(RichText))
        .evaluate()
        .map((element) {
          final box = element.renderObject! as RenderBox;
          return (
            text: (element.widget as RichText).text.toPlainText(),
            rect: box.localToGlobal(Offset.zero) & box.size,
          );
        })
        .firstWhere(
          (line) =>
              line.rect.height < 40 &&
              line.rect.width > 60 &&
              line.rect.top > view.top + 150 &&
              line.rect.bottom < view.bottom - 60,
        );
    final mouse = await tester.startGesture(
      Offset(line.rect.left + 1, line.rect.center.dy),
      kind: PointerDeviceKind.mouse,
    );
    final pressedAt = position.pixels;
    await tester.pump(const Duration(milliseconds: 100));
    expect(position.pixels, pressedAt);
    expect(position.isScrollingNotifier.value, isFalse);

    // Dragged across it, that line is what is copied (with any tag on it).
    await mouse.moveTo(Offset(line.rect.right - 1, line.rect.center.dy));
    await tester.pump();
    await mouse.up();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(copied, contains(line.text.trim()));
    expect(copied!.length, lessThan(line.text.length + 12));
  });
}
