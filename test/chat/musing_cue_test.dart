import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/widgets/activity_row.dart';
import 'package:baocode/l10n/app_localizations_zh.dart';
import 'package:baocode/l10n/l10n.dart';

void main() {
  group('what a command runs, in a word or two', () {
    for (final (command, name) in [
      ('flutter test test/kernel_test.dart', 'flutter test'),
      ('cd /repo/app && flutter test 2>&1 | tail -5', 'flutter test'),
      ('git add -A && git commit -m "fix"', 'git commit'),
      ('FOO=1 sudo /usr/bin/python3 -I script.py', 'python3'),
      ('dart format lib; dart analyze lib', 'dart analyze'),
      ("cat > notes.md <<'EOF'\nhello\nEOF", 'cat'),
      ('ls -la', 'ls'),
      ('cd /repo', ''),
    ]) {
      test(command.split('\n').first, () {
        expect(MusingCue.commandName(command), name);
      });
    }
  });

  test('the cue of a step done', () {
    MusingCue? cue(ChatItem item) => MusingCue.after(item);
    expect(
      cue(
        const TerminalItem(
          command: 'flutter test',
          output: '',
          status: CommandStatus.failed,
        ),
      ),
      isA<MusingCue>()
          .having((c) => c.topic, 'topic', MusingTopic.commandFailed)
          .having((c) => c.name, 'name', 'flutter test'),
    );
    expect(
      cue(const ToolCallItem(kind: ToolKind.read, target: 'chat_session.dart'))
          ?.name,
      'chat_session.dart',
    );
    expect(
      cue(
        const ToolCallItem(
          kind: ToolKind.grep,
          target: 'TODO',
          results: ['a.dart:1', 'b.dart:2'],
        ),
      )?.name,
      '2',
    );
    expect(
      cue(
        const ToolCallItem(
          kind: ToolKind.web,
          target: 'https://www.dart.dev/language',
        ),
      )?.name,
      'dart.dev',
    );
    expect(
      cue(
        const ToolCallItem(
          kind: ToolKind.mcp,
          target: '',
          label: 'github · create_issue',
        ),
      )?.name,
      'create_issue',
    );
    expect(
      cue(
        const ToolCallItem(
          kind: ToolKind.read,
          target: 'a_file_name_far_too_long_for_the_row.dart',
        ),
      )?.name,
      hasLength(24),
    );
    expect(
      cue(const ToolCallItem(kind: ToolKind.edit, target: 'x.dart'))?.topic,
      MusingTopic.edit,
    );
    expect(
      cue(
        const ToolCallItem(
          kind: ToolKind.read,
          target: 'x.dart',
          status: ToolStatus.denied,
        ),
      )?.topic,
      MusingTopic.denied,
    );
  });

  test('none for a step under way, nor for what is not a step', () {
    expect(
      MusingCue.after(
        const TerminalItem(
          command: 'flutter test',
          output: '',
          status: CommandStatus.running,
        ),
      ),
      isNull,
    );
    expect(
      MusingCue.after(
        const ToolCallItem(
          kind: ToolKind.read,
          target: 'x.dart',
          status: ToolStatus.running,
        ),
      ),
      isNull,
    );
    // A search that found nothing has no count to muse on.
    expect(
      MusingCue.after(const ToolCallItem(kind: ToolKind.grep, target: 'x')),
      isNull,
    );
    expect(MusingCue.after(const AssistantTextItem('Done.')), isNull);
    expect(MusingCue.after(null), isNull);
  });

  test('each topic has phrases in each language, its name in them', () {
    for (final l10n in [englishLocalizations, AppLocalizationsZh()]) {
      for (final topic in MusingTopic.values) {
        final phrases = ActivityRow.cuedMusingsFor(
          MusingCue(topic, 'NAME'),
          l10n,
        );
        expect(phrases, isNotEmpty);
        for (final phrase in phrases) {
          expect(phrase.trim(), phrase);
          expect(phrase, isNot(contains('{')));
        }
      }
    }
  });
}
