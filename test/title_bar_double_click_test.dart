import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_screen.dart';
import 'package:baocode/chat/widgets/inline_rename_field.dart';
import 'package:baocode/main.dart';
import 'package:baocode/sidebar/sidebar.dart';
import 'package:baocode/workspace/open_in_editor_button.dart';
import 'package:baocode/workspace/pin_window_button.dart';
import 'package:baocode/workspace/title_bar_double_click.dart';
import 'package:baocode/workspace/window_controls.dart';
import 'package:baocode/workspace/workspace.dart';

import 'sidebar_test.dart' show pumpApp;

const _window = MethodChannel('baocode/window');

final _macOS = TargetPlatformVariant.only(TargetPlatform.macOS);

/// What the app asks of the window, as it asks.
List<MethodCall> recordWindowCalls(WidgetTester tester) {
  final calls = <MethodCall>[];
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_window, (call) async {
    calls.add(call);
    return null;
  });
  addTearDown(() => messenger.setMockMethodCallHandler(_window, null));
  return calls;
}

/// The double clicks on the title bar the window was told of.
int titleDoubleClicks(List<MethodCall> calls) =>
    calls.where((call) => call.method == 'handleTitleDoubleClick').length;

Future<void> doubleClickAt(WidgetTester tester, Offset position) async {
  await tester.tapAt(position, kind: PointerDeviceKind.mouse);
  await tester.pump(const Duration(milliseconds: 80));
  await tester.tapAt(position, kind: PointerDeviceKind.mouse);
  await tester.pump();
}

const _bar = Key('bar');
const _button = Key('button');
const _controls = Key('controls');

/// A bar of 600 by 30: empty on the left, then a text field, a button and
/// two controls side by side.
Widget titleBar({VoidCallback? onButton}) => MaterialApp(
  home: Material(
    child: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 600,
        child: TitleBarDoubleClick(
          child: SizedBox(
            key: _bar,
            height: 30,
            child: Row(
              children: [
                const Spacer(),
                const SizedBox(width: 120, child: TextField()),
                GestureDetector(
                  key: _button,
                  onTap: onButton,
                  child: const ColoredBox(
                    color: Color(0xFF808080),
                    child: SizedBox.square(dimension: 24),
                  ),
                ),
                const SizedBox(width: 20),
                TitleBarControls(
                  key: _controls,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () {},
                        child: const SizedBox.square(dimension: 24),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: () {},
                        child: const SizedBox.square(dimension: 24),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('the window hears of a double click on the title bar on '
      'macOS', (tester) async {
    final calls = recordWindowCalls(tester);
    await WindowControls.handleTitleDoubleClick();
    expect(calls.single.method, 'handleTitleDoubleClick');
    expect(calls.single.arguments, isNull);
  }, variant: _macOS);

  testWidgets('elsewhere the system handles its title bar (or there is '
      'none)', (tester) async {
    final calls = recordWindowCalls(tester);
    await WindowControls.handleTitleDoubleClick();
    expect(calls, isEmpty);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('a double click on the bar\'s empty part is the window\'s; a '
      'click, or two too slow, is not', (tester) async {
    final calls = recordWindowCalls(tester);
    await tester.pumpWidget(titleBar());
    const empty = Offset(100, 15);

    await doubleClickAt(tester, empty);
    expect(titleDoubleClicks(calls), 1);

    await tester.tapAt(empty, kind: PointerDeviceKind.mouse);
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
    await tester.tapAt(empty, kind: PointerDeviceKind.mouse);
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
    expect(titleDoubleClicks(calls), 1);

    // Held as long as the user likes, the second press still counts.
    await tester.tapAt(empty, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 80));
    final press = await tester.startGesture(
      empty,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(seconds: 1));
    await press.up();
    await tester.pump();
    expect(titleDoubleClicks(calls), 2);
  }, variant: _macOS);

  testWidgets('clicks apart, or a press dragged, are no double click', (
    tester,
  ) async {
    final calls = recordWindowCalls(tester);
    await tester.pumpWidget(titleBar());

    await tester.tapAt(const Offset(20, 15), kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(const Offset(200, 15), kind: PointerDeviceKind.mouse);
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));

    final drag = await tester.startGesture(
      const Offset(100, 15),
      kind: PointerDeviceKind.mouse,
    );
    await drag.moveBy(const Offset(60, 0));
    await drag.up();
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(const Offset(100, 15), kind: PointerDeviceKind.mouse);
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
    expect(titleDoubleClicks(calls), 0);
  }, variant: _macOS);

  testWidgets('the bar\'s controls keep their double clicks, and their '
      'clicks come at once', (tester) async {
    final calls = recordWindowCalls(tester);
    var taps = 0;
    await tester.pumpWidget(titleBar(onButton: () => taps++));

    final button = tester.getCenter(find.byKey(_button));
    await tester.tapAt(button, kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(taps, 1);
    await tester.tapAt(button, kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(taps, 2);

    // A word selected, not the window zoomed.
    await doubleClickAt(tester, tester.getCenter(find.byType(TextField)));
    // Between two controls side by side: missed by a little.
    await doubleClickAt(tester, tester.getCenter(find.byKey(_controls)));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
    expect(titleDoubleClicks(calls), 0);
  }, variant: _macOS);

  testWidgets('elsewhere the bar is only what it holds', (tester) async {
    final calls = recordWindowCalls(tester);
    await tester.pumpWidget(titleBar());
    expect(
      tester.renderObject(find.byType(TitleBarDoubleClick)),
      same(tester.renderObject(find.byKey(_bar))),
    );
    await doubleClickAt(tester, const Offset(100, 15));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
    expect(calls, isEmpty);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('the sidebar\'s and the chat\'s title bars zoom the window '
      'where they are empty', (tester) async {
    final calls = recordWindowCalls(tester);
    await pumpApp(tester);

    // Right of the traffic lights, over the sidebar.
    final sidebar = tester.getTopLeft(find.byType(Sidebar));
    await doubleClickAt(tester, sidebar + const Offset(120, 15));
    expect(titleDoubleClicks(calls), 1);

    // Between the chat's title and its buttons.
    final chat = find.byType(ChatScreen);
    final title = find.descendant(
      of: chat,
      matching: find.text(tester.widget<ChatScreen>(chat).title),
    );
    final pin = tester.getRect(find.byType(PinWindowButton));
    final empty = Offset(
      (tester.getTopRight(title).dx + pin.left) / 2,
      tester.getCenter(title).dy,
    );
    await doubleClickAt(tester, empty);
    expect(titleDoubleClicks(calls), 2);

    // Its title renames the agent; the gap between its buttons is theirs.
    await doubleClickAt(tester, tester.getCenter(title));
    expect(find.byType(InlineRenameField), findsOneWidget);
    final editor = tester.getRect(find.byType(OpenInEditorButton));
    await doubleClickAt(
      tester,
      Offset((pin.right + editor.left) / 2, pin.center.dy),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(titleDoubleClicks(calls), 2);
  }, variant: _macOS);

  testWidgets('so does the row left for the sidebar\'s button with no '
      'project open', (tester) async {
    final calls = recordWindowCalls(tester);
    tester.view.physicalSize = const Size(600, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(BaoCodeApp(workspace: Workspace()));
    await tester.pump();
    expect(find.text('Open a project folder'), findsOneWidget);

    await doubleClickAt(tester, const Offset(300, 15));
    expect(titleDoubleClicks(calls), 1);
  }, variant: _macOS);
}
