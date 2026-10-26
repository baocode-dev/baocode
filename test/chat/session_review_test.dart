import 'dart:async';

import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_screen.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/review/change_review.dart';
import 'package:baocode/chat/review/change_reviews.dart';
import 'package:baocode/chat/review/review_store.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/kernel_event.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:baocode/kernel/mock/mock_kernels.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoStore implements ReviewStore {
  _NoStore([this.root = '/p']);

  @override
  final String root;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// A review that records what the session asks of it.
class _Review extends ChangeReview {
  _Review([String root = '/p']) : super(_NoStore(root));

  final calls = <String>[];
  final reported = <String>[];
  Completer<void>? holdBegin;
  List<FileChange> listed = const [];

  @override
  List<FileChange> get changes => listed;

  void list(List<FileChange> changes) {
    listed = changes;
    notifyListeners();
  }

  @override
  Future<void> begin() async {
    calls.add('begin');
    await holdBegin?.future;
  }

  @override
  Future<void> observe({bool full = true}) async =>
      calls.add(full ? 'observe' : 'observe reported');

  @override
  void report(FileChange change, {FileOriginal? original}) =>
      reported.add(change.path);

  @override
  Future<void> keep(Iterable<String> paths) async =>
      calls.add('keep ${paths.join(',')}');

  @override
  Future<void> keepAll() async => calls.add('keepAll');

  @override
  Future<void> undo(Iterable<String> paths) async =>
      calls.add('undo ${paths.join(',')}');

  @override
  Future<void> undoAll() async => calls.add('undoAll');
}

/// A kernel whose events the test sends.
class _Kernel implements AgentKernel {
  _Kernel(this.descriptor, this.events);

  @override
  final KernelDescriptor descriptor;

  @override
  final Stream<KernelEvent> events;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  late _Review review;

  Future<ChatSession> pump(WidgetTester tester) async {
    review = _Review();
    final session = ChatSession(
      kernel: MockKernels.claudeCode,
      kernelContext: const KernelContext(cwd: '/p'),
      historyCount: 0,
      openReview: (root, {session}) async => review,
    );
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ChatScreen(session: session),
      ),
    );
    await tester.pump();
    return session;
  }

  Future<void> finish(WidgetTester tester, ChatSession session) async {
    // The message goes once the snapshot before it is taken.
    await tester.pump(const Duration(milliseconds: 100));
    for (var i = 0; i < 400 && session.isStreaming; i++) {
      switch (session.pendingInteraction) {
        case QuestionRequest():
          session.answer(const QuestionAnswer([], skipped: true));
        case ApprovalRequest():
          session.answer(const ApprovalAnswer(ApprovalDecision.allowOnce));
        default:
      }
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('a message goes without waiting for the snapshot before it', (
    tester,
  ) async {
    final session = await pump(tester);
    // The project was snapshotted as the conversation showed.
    expect(review.calls, ['begin']);

    review.holdBegin = Completer();
    session.send(const ComposerMessage(text: '把输入框改成随内容增高'));
    // Shown at once, the snapshot taken as it goes.
    expect(review.calls, ['begin', 'begin']);
    expect(session.itemCount, greaterThan(0));

    review.holdBegin!.complete();
    await finish(tester, session);

    // The edits it reported were looked at, and all at the turn's end.
    expect(review.reported, isNotEmpty);
    expect(review.calls, contains('observe reported'));
    expect(review.calls.last, 'observe');
    // Its background tests settle.
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('the changes, and Keep and Undo, are the review\'s', (
    tester,
  ) async {
    final session = await pump(tester);
    session.send(const ComposerMessage(text: '把输入框改成随内容增高'));
    await finish(tester, session);

    const change = FileChange(path: '/p/lib/a.dart', added: 2, removed: 1);
    review.list(const [change]);
    await tester.pump();
    expect(session.fileChanges, [change]);
    expect(find.text('1 file changed'), findsOneWidget);

    session.keepChanges(const [change]);
    session.undoChanges!(const [change]);
    session.undoAllChanges!();
    await tester.tap(find.text('Keep all'));
    expect(
      review.calls,
      containsAllInOrder([
        'keep /p/lib/a.dart',
        'undo /p/lib/a.dart',
        'undoAll',
        'keepAll',
      ]),
    );

    // Failed, it gives way to what the kernel reported.
    review.abandon('gone');
    await tester.pump();
    expect(session.fileChanges, isNot([change]));
    expect(session.undoChanges, isNull);
    await tester.pump(const Duration(seconds: 5));
  });

  test('in a workspace, each folder\'s files are its review\'s', () async {
    final reviews = <String, _Review>{};
    final opened = <String>[];
    final session = ChatSession(
      kernel: MockKernels.claudeCode,
      kernelContext: KernelContext(
        cwd: '/w',
        workspace: () =>
            const KernelWorkspace(folders: ['/a', '/b', '/a/inner']),
      ),
      historyCount: 0,
      openReview: (root, {session}) async {
        opened.add(root);
        return reviews[root] = _Review(root);
      },
    );
    addTearDown(session.dispose);
    session.attach();
    await pumpEventQueue();
    // A folder inside another is the other's.
    expect(opened, ['/w', '/a', '/b']);

    const inA = FileChange(path: '/a/lib/x.dart', added: 1, removed: 0);
    const inB = FileChange(path: '/b/y.dart', added: 1, removed: 0);
    reviews['/a']!.list(const [inA]);
    reviews['/b']!.list(const [inB]);
    expect(session.fileChanges, [inA, inB]);

    session.keepChanges(const [inA]);
    session.undoChanges!(const [inB]);
    await pumpEventQueue();
    expect(reviews['/a']!.calls, contains('keep /a/lib/x.dart'));
    expect(reviews['/b']!.calls, contains('undo /b/y.dart'));
    expect(reviews['/w']!.calls, isNot(contains(startsWith('keep'))));

    // A file in none of them is the agent's directory's.
    final parts = <String, _Review>{};
    final both = await ChangeReviews.open([
      '/w',
      '/a',
    ], open: (root, {session}) async => parts[root] = _Review(root));
    addTearDown(both!.dispose);
    both
      ..report(const FileChange(path: 'notes.md', added: 1, removed: 0))
      ..report(const FileChange(path: '/a/z.dart', added: 1, removed: 0))
      ..report(const FileChange(path: '/elsewhere.txt', added: 1, removed: 0));
    expect(parts['/w']!.reported, ['notes.md', '/elsewhere.txt']);
    expect(parts['/a']!.reported, ['/a/z.dart']);
  });

  testWidgets('what a command or a subagent may have written is looked for '
      'as the agent works, a little later and not too often', (tester) async {
    final live = StreamController<KernelEvent>.broadcast(sync: true);
    addTearDown(live.close);
    late final KernelDescriptor descriptor;
    descriptor = KernelDescriptor(
      id: 'test',
      label: 'Test',
      icon: Icons.abc,
      description: '',
      create: (context) => _Kernel(descriptor, live.stream),
    );
    review = _Review();
    final session = ChatSession(
      kernel: descriptor,
      kernels: [descriptor],
      kernelContext: const KernelContext(cwd: '/p'),
      historyCount: 0,
      openReview: (root, {session}) async => review,
    );
    addTearDown(session.dispose);
    session.attach();
    await tester.pump();
    expect(review.calls, ['begin']);
    var seq = 0;
    int looks() => review.calls.where((call) => call == 'observe').length;

    // Between turns, what changes is not the agent's.
    live.add(FilesMayHaveChanged(++seq));
    await tester.pump(const Duration(seconds: 2));
    expect(looks(), 0);

    live.add(TurnStarted(++seq, 't1'));
    live.add(FilesMayHaveChanged(++seq));
    await tester.pump(const Duration(milliseconds: 500));
    expect(looks(), 0);
    await tester.pump(const Duration(milliseconds: 600));
    expect(looks(), 1);

    // Many commands right after: one look, once the last has rested.
    for (var i = 0; i < 5; i++) {
      live.add(FilesMayHaveChanged(++seq));
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(looks(), 1);
    await tester.pump(const Duration(seconds: 5));
    expect(looks(), 2);
    await tester.pump(const Duration(seconds: 10));
    expect(looks(), 2);

    // The turn's end looks at everything; none waits on after it.
    live.add(FilesMayHaveChanged(++seq));
    live.add(TurnEnded(++seq, 't1'));
    expect(looks(), 3);
    await tester.pump(const Duration(seconds: 10));
    expect(looks(), 3);
  });
}
