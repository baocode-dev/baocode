import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/selection/chat_selection.dart';
import 'package:baocode/chat/widgets/thinking_section.dart';
import 'package:baocode/theme/app_theme.dart';

void main() {
  group('a summarized thought', () {
    test('is headed by its title, the rest its body', () {
      expect(thoughtSummary('**Planning the fix**\nLooking at a.dart.'), (
        title: 'Planning the fix',
        body: 'Looking at a.dart.',
      ));
    });

    test('of many parts, by its latest part\'s title, all titles in it', () {
      expect(
        thoughtSummary('**Reading**\n\nThe driver.\n\n**Planning**\n\nFour.'),
        (
          title: 'Planning',
          body: 'Reading\n\nThe driver.\n\nPlanning\n\nFour.',
        ),
      );
    });

    test('is none without a bold first line', () {
      expect(thoughtSummary('Just thinking.'), isNull);
    });
  });

  testWidgets('a thought coming in holds still under a press that selects, '
      'and follows its end again once let go', (tester) async {
    addTearDown(() => ChatSelectionHold.held.value = false);
    String lines(int count) =>
        [for (var i = 0; i < count; i++) 'Line $i of the thought.'].join('\n');
    Future<void> show(String text) => tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: ThinkingSection(
            text: text,
            seconds: null,
            expanded: true,
            onToggle: () {},
          ),
        ),
      ),
    );
    // Short, then growing past its height: following its end.
    await show(lines(3));
    await show(lines(20));
    await tester.pump();
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    expect(position.pixels, position.maxScrollExtent);
    final at = position.pixels;
    ChatSelectionHold.held.value = true;
    await show(lines(30));
    await tester.pump();
    await tester.pump();
    expect(position.pixels, at);
    ChatSelectionHold.held.value = false;
    await tester.pump();
    expect(position.pixels, position.maxScrollExtent);
    expect(position.pixels, greaterThan(at));
  });

  test('a long thought tells its minutes', () {
    expect(thinkingParts(185), ('Thought', '3m 5s'));
    expect(thinkingParts(12), ('Thought', '12s'));
  });
}
