import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/kernel/kernel_event.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:baocode/kernel/transcript.dart';

/// A turn as a kernel reports it: a thought and a reply streamed in parts,
/// a question asked and answered, a file changed.
List<KernelEvent> turn() => const [
  TurnStarted(1, 't1'),
  ItemUpserted(2, 'u', UserMessageItem(text: 'hi')),
  ItemUpserted(3, 'th', ThinkingItem(text: '', tokens: 0), streaming: true),
  TextDelta(4, 'th', 0, 'Let me ', tokens: 7),
  TextDelta(5, 'th', 7, 'look.', tokens: 12),
  ItemCompleted(
    6,
    'th',
    item: ThinkingItem(text: 'Let me look.', tokens: 12, seconds: 2),
  ),
  ItemUpserted(7, 'a', AssistantTextItem(''), streaming: true),
  TextDelta(8, 'a', 0, 'Hel'),
  TextDelta(9, 'a', 3, 'lo'),
  ItemCompleted(10, 'a'),
  InteractionRequested(
    11,
    QuestionRequest(
      id: 'q',
      title: 'Ask',
      questions: [
        Question(
          prompt: 'Which?',
          options: [QuestionOption('A'), QuestionOption('B')],
        ),
      ],
    ),
  ),
  InteractionResolved(12, 'q'),
  FileEdited(13, FileChange(path: 'lib/a.dart', added: 3, removed: 1)),
  UsageReported(14, ContextUsage(window: 1000, used: 400)),
  TurnEnded(15, 't1'),
];

/// What a projection or a screen would show of [transcript].
String describe(Transcript transcript) => [
  for (var i = 0; i < transcript.length; i++)
    switch (transcript.itemAt(i)) {
      UserMessageItem(:final text) => 'user:$text',
      ThinkingItem(:final text, :final tokens, :final seconds) =>
        'thought:$text/$tokens/$seconds',
      AssistantTextItem(:final text) => 'text:$text',
      final item => '$item',
    },
  'active:${transcript.activeTurn}',
  'pending:${transcript.pendingInteraction?.id}',
  'edits:${transcript.edits.map((e) => e.change.path).join(',')}',
  'used:${transcript.usage?.used}',
  'ended:${transcript.lastTurnEndSeq}',
].join('\n');

void main() {
  test('applies a turn', () {
    final transcript = Transcript();
    for (final event in turn()) {
      transcript.apply(event);
    }
    expect(
      describe(transcript),
      [
        'user:hi',
        'thought:Let me look./12/2',
        'text:Hello',
        'active:null',
        'pending:null',
        'edits:lib/a.dart',
        'used:400',
        'ended:15',
      ].join('\n'),
    );
  });

  test('applying events again changes nothing', () {
    final once = Transcript();
    final twice = Transcript();
    for (final event in turn()) {
      once.apply(event);
      twice.apply(event);
      expect(twice.apply(event), isFalse);
    }
    // Replayed whole, from the start, after the fact.
    for (final event in turn()) {
      expect(twice.apply(event), isFalse);
    }
    expect(describe(twice), describe(once));
  });

  test('a delta overlapping what is there adds only the rest', () {
    final transcript = Transcript()
      ..apply(const ItemUpserted(1, 'a', AssistantTextItem('Hel')))
      ..apply(const TextDelta(2, 'a', 0, 'Hello'))
      ..apply(const TextDelta(3, 'a', 2, 'llo!'));
    expect(describe(transcript), startsWith('text:Hello!'));

    // A gap would lose text: ignored until the item comes whole.
    expect(transcript.apply(const TextDelta(4, 'a', 10, 'x')), isFalse);
    expect(describe(transcript), startsWith('text:Hello!'));
  });

  test('an item is replaced by its id, in place', () {
    final transcript = Transcript()
      ..apply(const ItemUpserted(1, 'a', AssistantTextItem('one')))
      ..apply(const ItemUpserted(2, 'b', AssistantTextItem('two')))
      ..apply(const ItemUpserted(3, 'a', AssistantTextItem('ONE')));
    expect(describe(transcript), startsWith('text:ONE\ntext:two\n'));
  });

  test('a turn ended twice ends once; a stale start is ignored', () {
    final transcript = Transcript()
      ..apply(const TurnStarted(1, 't1'))
      ..apply(const TurnEnded(2, 't1'));
    expect(transcript.apply(const TurnEnded(3, 't1')), isFalse);
    expect(transcript.lastTurnEndSeq, 2);
    expect(transcript.apply(const TurnStarted(4, 't1')), isFalse);
    expect(transcript.activeTurn, isNull);
  });

  test('a turn that ends mid-thought settles it', () {
    final transcript = Transcript()
      ..apply(const TurnStarted(1, 't1'))
      ..apply(
        const ItemUpserted(
          2,
          'th',
          ThinkingItem(text: 'hm', tokens: 2),
          streaming: true,
        ),
      )
      ..apply(const TurnEnded(3, 't1', interrupted: true));
    expect(transcript.hasStreamingItem, isFalse);
    expect(describe(transcript), startsWith('thought:hm/2/1'));
  });

  test('rewinding into the history drops it and what followed', () {
    final transcript = Transcript(
      historyCount: 10,
      history: (index) => UserMessageItem(text: '$index'),
      changes: const [FileChange(path: 'x', added: 1, removed: 0)],
    )..apply(const ItemUpserted(1, 'a', AssistantTextItem('live')));
    expect(transcript.length, 11);
    transcript.apply(const Rewound(2, index: 4));
    expect(transcript.length, 4);
    expect(transcript.edits, isEmpty);
    expect(transcript.liveItems, isEmpty);
  });

  test('rewinding to a live item drops it and what followed', () {
    final transcript = Transcript()
      ..apply(const ItemUpserted(1, 'u1', UserMessageItem(text: 'one')))
      ..apply(const ItemUpserted(2, 'a1', AssistantTextItem('reply')))
      ..apply(const ItemUpserted(3, 'u2', UserMessageItem(text: 'two')))
      ..apply(const Rewound(4, itemId: 'u2', index: 99));
    expect(describe(transcript), startsWith('user:one\ntext:reply\nactive'));
  });

  test('a removed item is gone, and removing it again changes nothing', () {
    final transcript = Transcript()
      ..apply(const ItemUpserted(1, 'a', AssistantTextItem('one')))
      ..apply(const ItemUpserted(2, 'q', UserMessageItem(text: 'queued')))
      ..apply(const ItemUpserted(3, 'b', AssistantTextItem('two')));
    expect(transcript.apply(const ItemRemoved(4, 'q')), isTrue);
    expect(transcript.apply(const ItemRemoved(5, 'q')), isFalse);
    expect(describe(transcript), startsWith('text:one\ntext:two\n'));
    // Ids still find their items after the shift.
    transcript.apply(const ItemUpserted(6, 'b', AssistantTextItem('TWO')));
    expect(describe(transcript), startsWith('text:one\ntext:TWO\n'));
  });

  test('a turn done is timed on its message; a stopped one is not', () {
    const worked = Duration(minutes: 4, seconds: 32);
    Duration? workedOn(Transcript transcript) =>
        (transcript.itemAt(0) as UserMessageItem).worked;
    final done = Transcript()
      ..apply(const TurnStarted(1, 'u'))
      ..apply(const ItemUpserted(2, 'u', UserMessageItem(text: 'hi')))
      ..apply(const TurnEnded(3, 'u', worked: worked));
    expect(workedOn(done), worked);
    expect((done.itemAt(0) as UserMessageItem).text, 'hi');

    final stopped = Transcript()
      ..apply(const TurnStarted(1, 'u'))
      ..apply(const ItemUpserted(2, 'u', UserMessageItem(text: 'hi')))
      ..apply(const TurnEnded(3, 'u', interrupted: true, worked: worked));
    expect(workedOn(stopped), isNull);
  });

  test('tasks and todos are replaced whole', () {
    final started = DateTime(2026);
    final transcript = Transcript()
      ..apply(
        TasksReported(1, [
          KernelTask(
            id: 't',
            description: 'flutter test',
            kind: KernelTaskKind.command,
            status: CommandStatus.running,
            startedAt: started,
          ),
        ]),
      )
      ..apply(const TasksReported(2, []))
      ..apply(
        const TodosReported(3, [TodoEntry('Write tests', TodoStatus.pending)]),
      );
    expect(transcript.tasks, isEmpty);
    expect(transcript.todos.single.content, 'Write tests');
  });
}
