import 'package:baocode/chat/chat_feed.dart';
import 'package:baocode/chat/chat_history_view.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/composer/composer_draft.dart';
import 'package:baocode/chat/selection/chat_selection.dart';
import 'package:baocode/chat/widgets/command_step.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:baocode/theme/ui_zoom.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _after = 'Text after the command.';
final _lines = [
  for (var i = 0; i < 100; i++)
    'row_${i.toString().padLeft(3, '0')} abcdefghijklmnopqrstuvwxyz',
];

class _Feed extends ChangeNotifier implements ChatFeed {
  _Feed(this.items, {this.streaming = false});

  final List<ChatItem> items;
  final bool streaming;

  @override
  int get itemCount => items.length;
  @override
  ChatItem itemAt(int index) => items[index];
  @override
  bool get isStreaming => streaming;
  @override
  bool get isUnprompted => false;
  @override
  bool get canEditMessages => false;
  @override
  ({int index, ComposerDraft draft})? get editing => null;
  @override
  set editing(({int index, ComposerDraft draft})? value) {}
  @override
  void editMessage(int index, ComposerMessage message, {UserPlace? from}) {}
  @override
  VoidCallback? moveToBackgroundAt(int index) => null;
  @override
  VoidCallback? stopAt(int index) => null;
}

/// A command's output open in the conversation, scrolled [offset] down
/// in its box; its scroll position.
Future<ScrollPosition> _pumpOutput(
  WidgetTester tester, {
  double zoom = 1.1,
  double offset = 400,
  bool running = false,
}) async {
  tester.view.physicalSize = const Size(1000, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final feed = _Feed([
    const UserMessageItem(text: 'Print the rows'),
    TerminalItem(
      command: 'print rows',
      output: _lines.join('\n'),
      status: running ? CommandStatus.running : CommandStatus.succeeded,
    ),
    const AssistantTextItem(_after),
  ], streaming: running);
  addTearDown(feed.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      builder: (context, child) => MediaQuery(
        data: UiZoom.zoomed(MediaQuery.of(context), zoom),
        child: UiZoom(scale: zoom, child: child),
      ),
      home: Scaffold(body: ChatHistoryView(feed: feed)),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining('print rows', findRichText: true).first);
  await tester.pumpAndSettle();
  final position = tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byType(CommandStep),
              matching: find.byType(Scrollable),
            )
            .first,
      )
      .position;
  position.jumpTo(offset);
  await tester.pumpAndSettle();
  return position;
}

RenderParagraph _output(WidgetTester tester) => tester
    .renderObjectList<RenderParagraph>(find.byType(RichText))
    .singleWhere((p) => p.text.toPlainText().contains(_lines.first));

(Offset, Offset) _ends(RenderParagraph paragraph, String text) {
  final start = paragraph.text.toPlainText().indexOf(text);
  final box = paragraph
      .getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: start + text.length),
      )
      .single
      .toRect();
  return (
    paragraph.localToGlobal(Offset(box.left + 0.1, box.center.dy)),
    paragraph.localToGlobal(Offset(box.right - 0.1, box.center.dy)),
  );
}

Future<void> _drag(WidgetTester tester, (Offset, Offset) ends) async {
  final mouse = await tester.startGesture(
    ends.$1,
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump();
  await mouse.moveTo(ends.$2);
  await tester.pump(const Duration(milliseconds: 100));
  await mouse.up();
  await tester.pumpAndSettle();
}

String? _selected(WidgetTester tester) => tester
    .renderObject<RenderChatSelectionItem>(find.byType(ChatSelectionItem).first)
    .controller
    .selectedText();

void main() {
  for (final zoom in [0.9, 1.0, 1.1, 1.5]) {
    for (final offset in [0.0, 400.0]) {
      testWidgets('command output selects under the pointer at '
          '$zoom zoom, scrolled $offset', (tester) async {
        final position = await _pumpOutput(tester, zoom: zoom, offset: offset);
        final line = _lines[offset == 0 ? 3 : 25];
        await _drag(tester, _ends(_output(tester), line));
        expect(_selected(tester), line);
        expect(position.pixels, offset);
      }, variant: TargetPlatformVariant.desktop());
    }
  }

  testWidgets('scrolled live output selects under the pointer when zoomed', (
    tester,
  ) async {
    final position = await _pumpOutput(tester, running: true);
    final paragraph = _output(tester);
    final viewport = tester.getRect(
      find
          .descendant(
            of: find.byType(CommandStep),
            matching: find.byType(SingleChildScrollView),
          )
          .first,
    );
    final line = _lines.firstWhere((line) {
      final ends = _ends(paragraph, line);
      return (ends.$1.dy - viewport.center.dy).abs() < 12;
    });
    await _drag(tester, _ends(paragraph, line));
    expect(_selected(tester), line);
    expect(position.pixels, 400);
  }, variant: TargetPlatformVariant.desktop());

  testWidgets('a drag stays on its start while output scrolls under it', (
    tester,
  ) async {
    final position = await _pumpOutput(tester);
    final ends = _ends(_output(tester), _lines[25]);
    final mouse = await tester.startGesture(
      ends.$1,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await mouse.moveTo(ends.$2);
    await tester.pump();
    position.jumpTo(position.pixels + 36);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 16));
    await mouse.up();
    await tester.pumpAndSettle();
    expect(_selected(tester), _lines.sublist(25, 28).join('\n'));
    expect(position.pixels, 436);
  });

  testWidgets('copy returns the output line dragged over after scrolling', (
    tester,
  ) async {
    String? copied;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await _pumpOutput(tester);
    await _drag(tester, _ends(_output(tester), _lines[25]));
    final modifier =
        Theme.of(tester.element(find.byType(CommandStep))).platform ==
            TargetPlatform.macOS
        ? LogicalKeyboardKey.metaLeft
        : LogicalKeyboardKey.controlLeft;
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(modifier);
    await tester.pump();
    expect(copied, _lines[25]);
  }, variant: TargetPlatformVariant.desktop());
}
