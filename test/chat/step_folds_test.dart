import 'package:flutter_test/flutter_test.dart';
import 'package:monad/chat/chat_models.dart';
import 'package:monad/chat/step_folds.dart';

const _thought = ThinkingItem(text: 'Hm.', tokens: 3, seconds: 4);
const _read = ToolCallItem(kind: ToolKind.read, target: 'a.dart');
const _grep = ToolCallItem(kind: ToolKind.grep, target: 'foo');
const _edit = CodeDiffItem(fileName: 'a.dart', directory: 'lib', lines: []);
const _words = AssistantTextItem('Looking.');
const _answer = AssistantTextItem('Done.');

UserMessageItem _prompt([Duration? worked = const Duration(seconds: 65)]) =>
    UserMessageItem(text: 'Fix it', worked: worked);

StepFolds _fold(List<ChatItem> items, {bool live = false}) =>
    StepFolds.of(items.length, (i) => items[i], live: live);

/// The folds as `kind start-end`, each once, in order.
List<String> _folds(List<ChatItem> items, {bool live = false}) {
  final folds = _fold(items, live: live);
  return {
    for (var i = 0; i < items.length; i++) ...[
      if (folds.workAt(i) case final fold?) 'work ${fold.start}-${fold.end}',
      if (folds.stepsAt(i) case final fold?) 'steps ${fold.start}-${fold.end}',
    ],
  }.toList();
}

void main() {
  group('runs of steps', () {
    test('fold from two calls on, thoughts among them', () {
      expect(_folds([_prompt(null), _thought, _read, _thought, _grep]), [
        'steps 1-5',
      ]);
    });

    test('one call, however many thoughts, stays as it is', () {
      expect(_folds([_prompt(null), _thought, _read, _thought]), isEmpty);
    });

    test('words, edits, subagents and refused calls break a run', () {
      const denied = ToolCallItem(
        kind: ToolKind.read,
        target: 'x',
        status: ToolStatus.denied,
      );
      const agent = AgentItem(description: 'Look around');
      const background = TerminalItem(
        command: 'flutter run',
        output: '',
        background: true,
      );
      for (final breaker in <ChatItem>[
        _words,
        _edit,
        agent,
        denied,
        background,
      ]) {
        expect(
          _folds([_prompt(null), _read, breaker, _grep]),
          isEmpty,
          reason: '${breaker.runtimeType}',
        );
      }
    });
  });

  group('a turn\'s work', () {
    test('folds before its answer once timed', () {
      expect(_folds([_prompt(), _read, _grep, _words, _edit, _answer]), [
        'work 1-5',
        'steps 1-3',
      ]);
    });

    test('not while under way, nor stopped (untimed), nor short', () {
      final items = [_prompt(), _read, _grep, _words, _answer];
      expect(_folds(items, live: true), ['steps 1-3']);
      expect(_folds([_prompt(null), ...items.skip(1)]), ['steps 1-3']);
      expect(_folds([_prompt(), _read, _answer]), isEmpty);
    });

    test('not without an answer: an error ends it', () {
      const error = NoticeItem(NoticeKind.error, 'Overloaded');
      expect(_folds([_prompt(), _edit, _words, error]), isEmpty);
    });

    test('its answer is all the words after its last step', () {
      expect(_folds([_prompt(), _edit, _read, _words, _thought, _answer]), [
        'work 1-3',
      ]);
    });

    test('the turn under way is the last sent, not one queued after it', () {
      final items = [
        _prompt(),
        _edit,
        _read,
        _answer,
        _prompt(null),
        _read,
        const UserMessageItem(text: 'Then this', queued: true),
      ];
      expect(_folds(items, live: true), ['work 1-3']);
    });
  });

  group('rows', () {
    final items = <ChatItem>[
      _prompt(),
      _thought,
      _read,
      _grep,
      _words,
      _edit,
      _answer,
    ];
    final folds = _fold(items);
    StepRow row(int i, {Set<StepFoldKind> open = const {}}) =>
        folds.rowAt(i, items[i], (fold) => open.contains(fold.kind));

    test('a closed turn shows its line, then its answer', () {
      expect(row(1), (work: folds.workAt(1), steps: null, item: false));
      for (final i in [2, 3, 4, 5]) {
        expect(row(i), (work: null, steps: null, item: false));
      }
      expect(row(6), (work: null, steps: null, item: true));
    });

    test('open, its runs show as their lines until opened too', () {
      const work = {StepFoldKind.work};
      expect(row(1, open: work), (
        work: folds.workAt(1),
        steps: folds.stepsAt(1),
        item: false,
      ));
      expect(row(2, open: work).item, isFalse);
      expect(row(4, open: work).item, isTrue);
      final all = {StepFoldKind.work, StepFoldKind.steps};
      expect(
        [
          for (final i in [1, 2, 3]) row(i, open: all).item,
        ],
        [true, true, true],
      );
    });

    test('a closed run under way shows the step it is on', () {
      const running = ToolCallItem(
        kind: ToolKind.grep,
        target: 'foo',
        status: ToolStatus.running,
      );
      final live = <ChatItem>[
        _prompt(null),
        _read,
        _thought,
        running,
        const LiveStatusItem('Planning next move', visible: false),
      ];
      final folds = _fold(live, live: true);
      bool shown(int i) => folds.rowAt(i, live[i], (_) => false).item;
      expect([for (var i = 1; i < 4; i++) shown(i)], [false, false, true]);
      // Done, it folds with the rest.
      final done = [...live]..[3] = _grep;
      final settled = _fold(done, live: true);
      expect(settled.rowAt(3, done[3], (_) => false).item, isFalse);
    });
  });

  test('a run counts what its steps did; commands by their words', () {
    final tally = StepTally([
      _thought,
      _read,
      _thought,
      _grep,
      const TerminalItem(command: "sed -n '1,80p' lib/a.dart", output: ''),
      const TerminalItem(
        command: 'cd /p && grep -rn foo lib 2>/dev/null | head',
        output: '',
      ),
      const TerminalItem(command: 'ls lib', output: ''),
      const TerminalItem(
        command: 'flutter test',
        output: '',
        status: CommandStatus.failed,
      ),
      const ToolCallItem(kind: ToolKind.mcp, target: 'query', label: 'Docs'),
    ]);
    expect(tally.counts, {
      StepAction.read: 2,
      StepAction.search: 2,
      StepAction.list: 1,
      StepAction.run: 1,
      StepAction.use: 1,
    });
    expect(tally.thought, 8);
    expect(tally.failed, 1);
  });

  test('a command that writes, chains or edits in place runs', () {
    for (final command in [
      "sed -i '' 's/a/b/' lib/a.dart",
      'cat a > b',
      'grep foo lib; rm -rf build',
      'flutter analyze && flutter test',
      'python3 - <<EOF\nprint(1)\nEOF',
    ]) {
      expect(commandAction(command), StepAction.run, reason: command);
    }
  });
}
