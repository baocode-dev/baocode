import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_feed.dart';
import 'package:baocode/chat/chat_find.dart';
import 'package:baocode/chat/chat_history_view.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/composer/composer_draft.dart';
import 'package:baocode/chat/side_panel/file_open.dart';
import 'package:baocode/theme/material_file_icons.dart';
import 'package:baocode/chat/widgets/markdown_view.dart';
import 'package:baocode/theme/app_theme.dart';

class _Feed extends ChangeNotifier implements ChatFeed {
  _Feed(this.items);

  List<ChatItem> items;

  @override
  int get itemCount => items.length;

  @override
  ChatItem itemAt(int index) => items[index];

  @override
  bool get isStreaming => false;

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

void main() {
  testWidgets('a long conversation rebuilt builds its shown rows, not the '
      'hundreds folded away', (tester) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // Long turns: each folds its steps away into one row.
    List<ChatItem> turn(int n) => [
      UserMessageItem(text: 'Question $n', worked: const Duration(seconds: 65)),
      for (var i = 0; i < 40; i++) ...[
        ToolCallItem(kind: ToolKind.read, target: 't${n}_$i.dart'),
        AssistantTextItem('Turn $n step $i.'),
      ],
      AssistantTextItem('Answer $n.'),
    ];
    final feed = _Feed([for (var n = 0; n < 20; n++) ...turn(n)]);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: ChatHistoryView(feed: feed)),
      ),
    );
    await tester.pumpAndSettle();
    final alive = find
        .byType(ChatFindRow, skipOffstage: false)
        .evaluate()
        .length;

    var rebuilt = 0;
    var markdown = 0;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      if (element.widget is ChatFindRow) rebuilt++;
      if (element.widget is MarkdownBlocks) markdown++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);
    feed.notifyListeners();
    await tester.pump();

    expect(alive, greaterThan(200));
    expect(rebuilt, lessThan(40));
    // What the shown rows say is as it was: not parsed nor laid out anew.
    expect(markdown, 0);
  });

  testWidgets('a right click on a file the conversation names opens the '
      "file's menu", (tester) async {
    // A desktop's: a right click brings up the selection's menu.
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final existence = FileExistence((_) async => true);
    addTearDown(existence.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: FileOpenScope(
            root: '/p',
            onOpen: (_) {},
            existence: existence,
            child: ChatHistoryView(
              feed: _Feed([
                UserMessageItem(text: 'Where is it?'),
                AssistantTextItem('See [the report](out/report.html).'),
              ]),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tapAt(
      // The link's text, after its icon.
      tester.getCenter(find.byType(FileIcon)) + const Offset(30, 0),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Copy Relative Path'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
}
