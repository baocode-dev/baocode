import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monad/chat/chat_models.dart';
import 'package:monad/chat/widgets/chat_item_view.dart';
import 'package:monad/chat/widgets/shell_highlight.dart';
import 'package:monad/chat/widgets/wheel_latch.dart';
import 'package:monad/theme/cursor_theme.dart';

/// [item] as the history shows it, opened or not; taps toggle it.
Future<void> pumpStep(WidgetTester tester, ChatItem item) async {
  var expanded = defaultExpanded(item);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => ChatItemView(
            item: item,
            expanded: expanded,
            onToggle: () => setState(() => expanded = !expanded),
          ),
        ),
      ),
    ),
  );
}

Finder header(String text) => find.text(text, findRichText: true);

void main() {
  group('steps', () {
    testWidgets('a command: its description, opening to the command and '
        'what it printed', (tester) async {
      await pumpStep(
        tester,
        const TerminalItem(
          command: 'flutter --version',
          description: 'Check the Flutter version',
          output: 'Flutter 3.47.5\n',
        ),
      );
      expect(header('Ran Check the Flutter version'), findsOneWidget);
      expect(find.textContaining('Flutter 3.47.5'), findsNothing);
      // No mark of success or failure.
      expect(find.textContaining('Success'), findsNothing);

      await tester.tap(header('Ran Check the Flutter version'));
      await tester.pump();
      expect(find.text(r'$ flutter --version', findRichText: true), findsOne);
      expect(find.text('Flutter 3.47.5'), findsOneWidget);
      expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);

      await tester.tap(header('Ran Check the Flutter version'));
      await tester.pump();
      expect(find.text('Flutter 3.47.5'), findsNothing);
    });

    testWidgets('a running command stays closed; still coming, it has '
        'nothing to open to', (tester) async {
      await pumpStep(
        tester,
        const TerminalItem(
          command: 'sleep 30',
          output: '',
          status: CommandStatus.running,
        ),
      );
      expect(find.text('Running sleep 30'), findsOneWidget);
      expect(find.byIcon(Icons.more_horiz_rounded), findsNothing);

      // Its command not streamed in yet: no box, even opened.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ChatItemView(
              item: TerminalItem(
                command: '',
                output: '',
                status: CommandStatus.running,
              ),
              expanded: true,
            ),
          ),
        ),
      );
      expect(find.text('Running'), findsOneWidget);
      expect(find.byIcon(Icons.more_horiz_rounded), findsNothing);
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    });

    testWidgets('a running command shimmers; opened, its menu can move it '
        'to the background', (tester) async {
      var moved = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatItemView(
              item: const TerminalItem(
                command: 'sleep 30',
                output: '',
                status: CommandStatus.running,
              ),
              expanded: true,
              onMoveToBackground: () => moved = true,
            ),
          ),
        ),
      );
      expect(find.text('Running sleep 30'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Copy command'), findsOneWidget);
      await tester.tap(find.text('Move to background'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(moved, isTrue);
    });

    testWidgets('an edit: one line with its counts, opening to the diff', (
      tester,
    ) async {
      await pumpStep(
        tester,
        const CodeDiffItem(
          fileName: 'main.dart',
          directory: 'lib',
          lines: [
            DiffLine(DiffLineType.removed, 3, 'old line'),
            DiffLine(DiffLineType.added, 3, 'new line'),
          ],
          added: 12,
          removed: 1,
        ),
      );
      expect(header('Edited main.dart'), findsOneWidget);
      expect(find.text('+12 -1', findRichText: true), findsOneWidget);
      expect(find.text('new line'), findsNothing);
      await tester.tap(header('Edited main.dart'));
      await tester.pump();
      expect(find.text('new line'), findsOneWidget);
    });

    testWidgets('a search opens to its matches; a read does not open', (
      tester,
    ) async {
      await pumpStep(
        tester,
        const ToolCallItem(
          kind: ToolKind.grep,
          target: 'SuperListView',
          detail: '2 results',
          results: ['lib/a.dart:3', 'lib/b.dart:9'],
        ),
      );
      expect(header('Grepped SuperListView 2 results'), findsOneWidget);
      await tester.tap(header('Grepped SuperListView 2 results'));
      await tester.pump();
      expect(find.text('lib/a.dart:3\nlib/b.dart:9'), findsOneWidget);

      await pumpStep(
        tester,
        const ToolCallItem(
          kind: ToolKind.read,
          target: 'main.dart',
          path: 'lib/main.dart',
        ),
      );
      final hover = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await hover.addPointer(
        location: tester.getCenter(header('Read main.dart')),
      );
      addTearDown(hover.removePointer);
      await tester.pump();
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    });

    testWidgets('a thought counts its time while it streams, from 1s', (
      tester,
    ) async {
      await pumpStep(
        tester,
        ThinkingItem(text: '', tokens: 0, startedAt: DateTime.now()),
      );
      expect(find.text('Thinking 1s'), findsOneWidget);
      await pumpStep(
        tester,
        ThinkingItem(
          text: '',
          tokens: 0,
          startedAt: DateTime.now().subtract(const Duration(seconds: 3)),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining(RegExp(r'^Thinking [34]s$')), findsOneWidget);
    });

    testWidgets('a thought under a second is brief; tokens are not shown', (
      tester,
    ) async {
      await pumpStep(
        tester,
        const ThinkingItem(text: 'Quick check.', tokens: 40, seconds: 0),
      );
      expect(header('Thought briefly'), findsOneWidget);
      expect(find.textContaining('tokens', findRichText: true), findsNothing);
    });

    testWidgets('a subagent: one line, opening to its own steps', (
      tester,
    ) async {
      await pumpStep(
        tester,
        const AgentItem(
          description: 'Find the kernel files',
          agentType: 'Explore',
          status: CommandStatus.succeeded,
          toolUses: 2,
          children: [ToolCallItem(kind: ToolKind.read, target: 'kernel.dart')],
          result: 'Found them.',
        ),
      );
      expect(
        header('Delegated Find the kernel files Explore · 2 tools'),
        findsOneWidget,
      );
      expect(header('Read kernel.dart'), findsNothing);
      await tester.tap(
        header('Delegated Find the kernel files Explore · 2 tools'),
      );
      await tester.pump();
      expect(header('Read kernel.dart'), findsOneWidget);
      expect(find.text('Found them.', findRichText: true), findsOneWidget);
    });

    test('the shell highlighter colors programs, strings and options', () {
      final spans = highlightShell(
        'cd /tmp && grep -rn "metadata" .gitignore | head -5',
      );
      Color? colorOf(String text) =>
          spans.firstWhere((span) => span.text!.trim() == text).style?.color;
      expect(colorOf('cd'), CursorColors.syntaxCommand);
      expect(colorOf('grep'), CursorColors.syntaxCommand);
      expect(colorOf('head'), CursorColors.syntaxCommand);
      expect(colorOf('"metadata"'), CursorColors.syntaxString);
      expect(colorOf('-rn'), CursorColors.syntaxOption);
      expect(
        spans.map((span) => span.text).join(),
        'cd /tmp && grep -rn "metadata" .gitignore | head -5',
      );
    });
  });

  group('wheel latch', () {
    late ScrollController outer;
    late ScrollController inner;

    Future<void> pumpNested(WidgetTester tester) async {
      outer = ScrollController();
      inner = ScrollController();
      addTearDown(outer.dispose);
      addTearDown(inner.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ListView(
            controller: outer,
            children: [
              const SizedBox(height: 100),
              SizedBox(
                height: 200,
                child: SingleChildScrollView(
                  controller: inner,
                  child: const WheelLatch(child: SizedBox(height: 400)),
                ),
              ),
              const SizedBox(height: 2000),
            ],
          ),
        ),
      );
    }

    var clock = Duration.zero;
    Future<void> wheel(WidgetTester tester, Offset at, double dy) async {
      clock += const Duration(milliseconds: 50);
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(at, timeStamp: clock));
      await tester.sendEventToBinding(
        pointer.scroll(Offset(0, dy), timeStamp: clock),
      );
      await tester.pump();
    }

    void pause() => clock += const Duration(seconds: 1);

    testWidgets('a gesture over the inner view stays there past its end', (
      tester,
    ) async {
      await pumpNested(tester);
      pause();
      const over = Offset(400, 200);
      for (var i = 0; i < 6; i++) {
        await wheel(tester, over, 60);
      }
      expect(inner.offset, 200);
      expect(outer.offset, 0);

      // A new gesture, the inner view at its end: the outer view scrolls.
      pause();
      await wheel(tester, over, 60);
      expect(outer.offset, greaterThan(0));
    });

    testWidgets('a gesture begun outside keeps to the outer view over the '
        'inner one', (tester) async {
      await pumpNested(tester);
      pause();
      await wheel(tester, const Offset(400, 50), 20);
      expect(outer.offset, 20);
      // The inner view now under the pointer, in the same gesture.
      await wheel(tester, const Offset(400, 200), 30);
      expect(inner.offset, 0);
      expect(outer.offset, 50);
    });
  });
}
