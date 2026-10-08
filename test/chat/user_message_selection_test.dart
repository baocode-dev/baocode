import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_feed.dart';
import 'package:baocode/chat/chat_history_view.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/composer/composer_draft.dart';
import 'package:baocode/chat/widgets/user_message_bubble.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

class _Feed extends ChangeNotifier implements ChatFeed {
  _Feed(this.items);

  final List<ChatItem> items;

  @override
  int get itemCount => items.length;
  @override
  ChatItem itemAt(int index) => items[index];
  @override
  bool get isStreaming => false;
  @override
  bool get canEditMessages => false;
  @override
  ({int index, ComposerDraft draft})? get editing => null;
  @override
  set editing(({int index, ComposerDraft draft})? value) {}
  @override
  void editMessage(int index, ComposerMessage message) {}
  @override
  void cancelQueued(int index) {}
  @override
  VoidCallback? moveToBackgroundAt(int index) => null;
  @override
  VoidCallback? stopAt(int index) => null;
}

const _answer = 'Assistant selection stays here.';
const _code = 'final answer = 42;\n  print(answer);';
final _request = [
  'Visible request starts here.',
  for (var i = 0; i < 40; i++) 'Hidden request line $i.',
  'Hidden request ends here.',
].join('\n');

Future<void> _pump(WidgetTester tester, String response) async {
  final feed = _Feed([
    UserMessageItem(text: _request),
    AssistantTextItem(response),
  ]);
  addTearDown(feed.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: ChatHistoryView(feed: feed)),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _paragraph(String text) => find.byWidgetPredicate(
  (widget) => widget is RichText && widget.text.toPlainText() == text,
);

Future<void> _copy(
  WidgetTester tester, {
  LogicalKeyboardKey modifier = LogicalKeyboardKey.controlLeft,
}) async {
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
  await tester.sendKeyUpEvent(modifier);
  await tester.pump();
}

Future<void> _drag(
  WidgetTester tester,
  Finder text, {
  bool reverse = false,
  int inset = 0,
}) async {
  final paragraph = tester.renderObject<RenderParagraph>(text);
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(
      baseOffset: inset,
      extentOffset: paragraph.text.toPlainText().length - inset,
    ),
  );
  final first = boxes.first.toRect();
  final last = boxes.last.toRect();
  final start = paragraph.localToGlobal(
    Offset(first.left + 0.5, first.center.dy),
  );
  final end = paragraph.localToGlobal(Offset(last.right - 0.5, last.center.dy));
  final mouse = await tester.startGesture(
    reverse ? end : start,
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump();
  await mouse.moveTo(reverse ? start : end);
  await tester.pump();
  await mouse.up();
  await tester.pump();
}

void main() {
  String? copied;
  setUp(() {
    copied = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('hidden request text does not capture assistant dragging', (
    tester,
  ) async {
    await _pump(tester, _answer);
    for (final reverse in [false, true]) {
      copied = null;
      await _drag(tester, _paragraph(_answer), reverse: reverse, inset: 4);
      await _copy(tester);
      expect(copied, _answer.substring(4, _answer.length - 4));
      expect(find.byType(UserMessageViewer), findsNothing);
    }
  });

  for (final fence in ['dart', '12:13:lib/main.dart']) {
    testWidgets('code in $fence copies below a collapsed request', (
      tester,
    ) async {
      await _pump(tester, '```$fence\n$_code\n```');
      for (final reverse in [false, true]) {
        copied = null;
        await _drag(tester, _paragraph(_code), reverse: reverse);
        await _copy(
          tester,
          modifier: reverse
              ? LogicalKeyboardKey.metaLeft
              : LogicalKeyboardKey.controlLeft,
        );
        expect(copied, _code);
      }
    });
  }

  testWidgets('word selection ignores hidden request text', (tester) async {
    await _pump(tester, _answer);
    final paragraph = tester.renderObject<RenderParagraph>(_paragraph(_answer));
    final rect = paragraph
        .getBoxesForSelection(
          const TextSelection(baseOffset: 12, extentOffset: 14),
        )
        .single
        .toRect();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    final position = paragraph.localToGlobal(rect.center);
    await mouse.down(position);
    await mouse.up();
    await tester.pump(const Duration(milliseconds: 100));
    await mouse.down(position);
    await mouse.up();
    await tester.pump();
    await _copy(tester);
    expect(copied, 'selection');
  });

  testWidgets('selection across a collapsed request includes its hidden text', (
    tester,
  ) async {
    await _pump(tester, _answer);
    final request = tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.byType(SuperListView),
        matching: _paragraph(_request),
      ),
    );
    final answer = tester.renderObject<RenderParagraph>(_paragraph(_answer));
    final first = request
        .getBoxesForSelection(
          const TextSelection(baseOffset: 0, extentOffset: 4),
        )
        .first
        .toRect();
    final last = answer
        .getBoxesForSelection(
          const TextSelection(baseOffset: 0, extentOffset: _answer.length),
        )
        .last
        .toRect();
    final start = request.localToGlobal(
      Offset(first.left + 0.5, first.center.dy),
    );
    final end = answer.localToGlobal(Offset(last.right - 0.5, last.center.dy));
    for (final reverse in [false, true]) {
      final mouse = await tester.startGesture(
        reverse ? end : start,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await mouse.moveTo(reverse ? start : end);
      await tester.pump();
      await mouse.up();
      await tester.pump();
      await _copy(tester);
      expect(copied, '$_request\n$_answer');
      expect(find.byType(UserMessageViewer), findsNothing);
    }
  });

  testWidgets('assistant dragging works after scrolling and resizing', (
    tester,
  ) async {
    await _pump(
      tester,
      [
        _answer,
        for (var i = 0; i < 35; i++) 'Response paragraph $i.',
      ].join('\n\n'),
    );
    final position = tester
        .widget<SuperListView>(find.byType(SuperListView))
        .controller!
        .position;
    position.jumpTo(0);
    await tester.pumpAndSettle();
    await _drag(tester, _paragraph(_answer), inset: 4);
    await _copy(tester);
    expect(copied, _answer.substring(4, _answer.length - 4));
    position.jumpTo(400);
    await tester.pumpAndSettle();
    position.jumpTo(0);
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(500, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpAndSettle();
    await _drag(tester, _paragraph(_answer), reverse: true, inset: 4);
    await _copy(tester);
    expect(copied, _answer.substring(4, _answer.length - 4));
  });

  testWidgets('the visible request remains selectable and select all keeps '
      'its hidden text', (tester) async {
    await _pump(tester, _answer);
    final request = find.descendant(
      of: find.byType(SuperListView),
      matching: _paragraph(_request),
    );
    final paragraph = tester.renderObject<RenderParagraph>(request);
    final first = paragraph
        .getBoxesForSelection(
          const TextSelection(baseOffset: 0, extentOffset: 28),
        )
        .first
        .toRect();
    final mouse = await tester.startGesture(
      paragraph.localToGlobal(Offset(first.left, first.center.dy)),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await mouse.moveTo(
      paragraph.localToGlobal(Offset(first.right - 0.5, first.center.dy)),
    );
    await tester.pump();
    await mouse.up();
    await tester.pump();
    await _copy(tester);
    expect(copied, 'Visible request starts here.');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await _copy(tester);
    expect(copied, contains('Hidden request ends here.'));
    expect(copied, contains(_answer));

    await _drag(tester, _paragraph(_answer));
    await _copy(tester);
    expect(copied, _answer);
  });
}
