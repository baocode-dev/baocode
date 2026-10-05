import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/panels/activity_strip.dart';
import 'package:baocode/chat/widgets/agent_step.dart';
import 'package:baocode/chat/widgets/chat_item_view.dart';
import 'package:baocode/chat/widgets/shell_highlight.dart';
import 'package:baocode/chat/widgets/shimmer_text.dart';
import 'package:baocode/chat/widgets/step_header.dart';
import 'package:baocode/chat/widgets/wheel_latch.dart';
import 'package:baocode/ide/terminal/terminal_colors.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:baocode/theme/workbench_theme.dart' show themeColors;

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

    testWidgets('a command\'s output shows as a terminal does: in color, '
        'what it wrote over as it ended; copied without escapes', (
      tester,
    ) async {
      String? copied;
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ChatItemView(
              item: TerminalItem(
                command: 'npm test',
                output:
                    '\x1b[32m✓\x1b[0m passes\n'
                    '\x1b[1;31m✗ fails\x1b[0m\n'
                    ' 10%\r 50%\r100%\n',
              ),
              expanded: true,
            ),
          ),
        ),
      );
      const shown = '✓ passes\n✗ fails\n100%';
      final output = find.text(shown, findRichText: true);
      expect(output, findsOneWidget);
      final spans = <String, TextStyle?>{};
      tester.widget<RichText>(output).text.visitChildren((span) {
        if (span is TextSpan && span.text != null) {
          spans[span.text!] = span.style;
        }
        return true;
      });
      expect(spans['✓']?.color, TerminalColors.ansi[2]);
      expect(spans[' passes\n'], isNull);
      // Bold red, brightened.
      expect(spans['✗ fails\n']?.color, TerminalColors.ansi[9]);
      expect(spans['✗ fails\n']?.fontWeight, FontWeight.bold);
      expect(spans['100%'], isNull);
      // In the step's font, as plain output.
      expect(tester.widget<Text>(find.text(shown)).style, stepMono);
      for (final text in tester.widgetList<RichText>(find.byType(RichText))) {
        expect(text.text.toPlainText(), isNot(matches('[\x1b\r]')));
      }

      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Copy output'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(copied, shown);
    });

    testWidgets('plain output shows as it is', (tester) async {
      await pumpStep(
        tester,
        const TerminalItem(command: 'ls', output: 'a.txt\tb.txt\n\n'),
      );
      await tester.tap(header('Ran ls'));
      await tester.pump();
      final text = tester.widget<Text>(find.text('a.txt\tb.txt'));
      expect(text.data, 'a.txt\tb.txt');
      expect(text.style, stepMono);
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

    testWidgets('an edit leaves out a count of none', (tester) async {
      await pumpStep(
        tester,
        const CodeDiffItem(
          fileName: 'demo.txt',
          directory: '',
          lines: [DiffLine(DiffLineType.added, 1, 'hello')],
          added: 5,
          removed: 0,
        ),
      );
      expect(find.text('+5', findRichText: true), findsOneWidget);
      expect(find.textContaining('-0', findRichText: true), findsNothing);
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

    testWidgets('a subagent: a line, how it went after its description once '
        'done, opening on a click or Enter', (tester) async {
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatItemView(
              item: const AgentItem(
                id: 'toolu_1',
                description: 'Find the kernel files',
                agentType: 'Explore',
                status: CommandStatus.succeeded,
                toolUses: 2,
                tokens: 8200,
                duration: Duration(seconds: 74),
                children: [
                  ToolCallItem(kind: ToolKind.read, target: 'kernel.dart'),
                ],
                result: '## Found\n- them.',
              ),
              onOpen: () => opened++,
            ),
          ),
        ),
      );
      expect(find.text('Find the kernel files'), findsOneWidget);
      expect(
        find.text('· Explore · 1m 14s · 2 tools · 8.2k tokens'),
        findsOneWidget,
      );
      // The rest is in its own conversation.
      expect(find.textContaining('Found'), findsNothing);
      expect(find.textContaining('Read kernel.dart'), findsNothing);

      await tester.tap(find.text('Find the kernel files'));
      expect(opened, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(opened, 2);
    });

    testWidgets('a running subagent shimmers; stopping it does not open it', (
      tester,
    ) async {
      var opened = 0;
      var stopped = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatItemView(
              item: AgentItem(
                id: 'toolu_1',
                description: 'Compare the games',
                agentType: 'Explore',
                activity: 'Reading game.js',
                startedAt: DateTime.now().subtract(const Duration(seconds: 69)),
              ),
              onOpen: () => opened++,
              onStop: () => stopped++,
            ),
          ),
        ),
      );
      expect(find.byType(ShimmerText), findsOneWidget);
      // What it is doing, before any step of its shows; how it went only
      // once done.
      expect(find.text('· Reading game.js'), findsOneWidget);
      expect(find.textContaining('Explore'), findsNothing);
      await tester.tap(find.byIcon(Icons.stop_rounded));
      expect((stopped, opened), (1, 0));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a subagent\'s card keeps its height whatever it did last', (
      tester,
    ) async {
      Future<double> height(List<ChatItem> children) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: ChatItemView(
                  item: AgentItem(
                    id: 'toolu_1',
                    description: 'Look around',
                    children: children,
                  ),
                ),
              ),
            ),
          ),
        );
        return tester.getSize(find.byType(AgentStep)).height;
      }

      final nothing = await height(const []);
      expect(
        await height(const [AssistantTextItem('Let me look 🙂')]),
        nothing,
      );
      expect(
        await height(const [TerminalItem(command: '看一下 ls', output: '')]),
        nothing,
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a subagent\'s last step flips up to the next, each staying '
        'a while', (tester) async {
      Future<void> show(List<String> commands) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatItemView(
              item: AgentItem(
                id: 'toolu_1',
                description: 'Look around',
                children: [
                  for (final command in commands)
                    TerminalItem(
                      command: command,
                      output: '',
                      status: CommandStatus.succeeded,
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      Finder line(String command) => find.text('· Ran $command');

      await show(['ls']);
      expect(line('ls'), findsOneWidget);

      // The next comes up as the last goes: both, for the flip.
      await show(['ls', 'pwd']);
      await tester.pump(const Duration(milliseconds: 100));
      expect(line('ls'), findsOneWidget);
      expect(line('pwd'), findsOneWidget);
      expect(find.byType(Transform), findsWidgets);
      await tester.pump(const Duration(milliseconds: 300));
      expect(line('ls'), findsNothing);

      // Two more while it stays: the last of them only, once it has.
      await show(['ls', 'pwd', 'cd a']);
      await show(['ls', 'pwd', 'cd a', 'cd b']);
      await tester.pump();
      expect(line('pwd'), findsOneWidget);
      expect(line('cd b'), findsNothing);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 400));
      expect(line('cd a'), findsNothing);
      expect(line('cd b'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a message to an agent: someone speaking, in amber, saying '
        'it', (tester) async {
      await pumpStep(
        tester,
        const ToolCallItem(
          kind: ToolKind.message,
          target: 'Report back',
          output: 'Report back',
        ),
      );
      final icon = tester.widget<SvgPicture>(find.byType(SvgPicture));
      expect(
        icon.colorFilter,
        ColorFilter.mode(
          themeColors['symbolIcon.eventForeground'],
          BlendMode.srcIn,
        ),
      );
      expect(header('Said Report back'), findsOneWidget);
    });

    testWidgets('a proposed goal offers to set it, once', (tester) async {
      final set = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatItemView(
              item: const ToolCallItem(
                kind: ToolKind.goal,
                target: 'tests pass and lint is clean',
                output: 'tests pass\nand lint is clean',
              ),
              onSetGoal: set.add,
            ),
          ),
        ),
      );
      expect(header('Proposed a goal tests pass and lint is clean'), findsOne);
      await tester.tap(find.text('Set as goal'));
      await tester.pump();
      expect(set, ['tests pass\nand lint is clean']);
      expect(find.text('Set as goal'), findsNothing);
      expect(find.text('Goal set'), findsOneWidget);
    });

    test('the shell highlighter colors programs, strings and options', () {
      final spans = highlightShell(
        'cd /tmp && grep -rn "metadata" .gitignore | head -5',
      );
      Color? colorOf(String text) =>
          spans.firstWhere((span) => span.text!.trim() == text).style?.color;
      expect(colorOf('cd'), AppColors.syntaxCommand);
      expect(colorOf('grep'), AppColors.syntaxCommand);
      expect(colorOf('head'), AppColors.syntaxCommand);
      expect(colorOf('"metadata"'), AppColors.syntaxString);
      expect(colorOf('-rn'), AppColors.syntaxOption);
      expect(
        spans.map((span) => span.text).join(),
        'cd /tmp && grep -rn "metadata" .gitignore | head -5',
      );
    });
  });

  testWidgets('a running task\'s stop sits at the end of its row, what it '
      'did last after its description', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            child: ActivityStrip(
              tasks: [
                KernelTask(
                  id: 't1',
                  description: '比较三份飞机大战代码',
                  kind: KernelTaskKind.agent,
                  status: CommandStatus.running,
                  startedAt: DateTime.now(),
                ),
              ],
              changes: const [],
              onStopTask: (_) {},
              onKeep: () {},
              detailOf: (_) => 'Read game.js',
            ),
          ),
        ),
      ),
    );
    final stop = tester.getRect(find.byIcon(Icons.stop_rounded));
    final strip = tester.getRect(find.byType(ActivityStrip));
    // The strip's margin and border, the row's margin and padding.
    expect(stop.right, strip.right - (10 + 1 + 3 + 7));
    final description = tester.getRect(find.text('比较三份飞机大战代码'));
    final detail = tester.getRect(find.text('· Read game.js'));
    expect(detail.left, greaterThan(description.right));
    expect(
      tester.getRect(find.textContaining('Running')).left,
      greaterThan(detail.right),
    );
    // The ticking clock stopped.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('narrow, the changes\' label gives way to their buttons', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            // Too narrow for the whole label in the test font.
            width: 440,
            child: ActivityStrip(
              tasks: const [],
              changes: const [
                FileChange(path: '/a/clauding.html', added: 119, removed: 0),
              ],
              onUndo: () {},
              onKeep: () {},
            ),
          ),
        ),
      ),
    );
    // No overflow, and the buttons still against the end.
    final keep = tester.getRect(
      find.ancestor(
        of: find.text('Keep all'),
        matching: find.byType(FittedBox),
      ),
    );
    final strip = tester.getRect(find.byType(ActivityStrip));
    expect(keep.right, strip.right - (10 + 1 + 3 + 7));
    expect(
      tester.getRect(find.text('-0')).right,
      lessThan(tester.getRect(find.text('Undo all')).left),
    );
  });

  testWidgets('many running tasks scroll within the strip', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: 600,
              child: ActivityStrip(
                tasks: [
                  for (var i = 0; i < 10; i++)
                    KernelTask(
                      id: 't$i',
                      description: 'task $i',
                      kind: KernelTaskKind.command,
                      status: CommandStatus.running,
                      startedAt: DateTime.now(),
                    ),
                ],
                changes: const [],
                onKeep: () {},
              ),
            ),
          ),
        ),
      ),
    );
    // Four rows, the strip's padding and top border.
    expect(tester.getSize(find.byType(ActivityStrip)).height, 28 * 4 + 6 + 1);
    expect(find.text('task 0').hitTestable(), findsOneWidget);
    expect(find.text('task 9').hitTestable(), findsNothing);

    await tester.drag(find.text('task 0'), const Offset(0, -400));
    await tester.pump();
    expect(find.text('task 9').hitTestable(), findsOneWidget);
    // The ticking clock stopped.
    await tester.pumpWidget(const SizedBox());
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
