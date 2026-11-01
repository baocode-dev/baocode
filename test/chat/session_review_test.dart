import 'dart:async';

import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_screen.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/review/change_review.dart';
import 'package:baocode/chat/review/review_store.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:baocode/kernel/mock/mock_kernels.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoStore implements ReviewStore {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// A review that records what the session asks of it.
class _Review extends ChangeReview {
  _Review() : super(_NoStore(), root: '/p');

  final calls = <String>[];
  Completer<void>? holdBefore;
  List<FileChange> listed = const [];

  @override
  List<FileChange> get changes => listed;

  void list(List<FileChange> changes) {
    listed = changes;
    notifyListeners();
  }

  @override
  Future<void> before(String path) async {
    calls.add('before $path');
    await holdBefore?.future;
  }

  @override
  Future<void> after(String path) async => calls.add('after $path');

  @override
  void report(FileChange change, {FileOriginal? original}) =>
      calls.add('report ${change.path}');

  @override
  Future<void> look() async => calls.add('look');

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

  testWidgets('each edit waits on the review keeping what its file was, '
      'and is told it once made', (tester) async {
    final session = await pump(tester);
    review.holdBefore = Completer();
    session.send(const ComposerMessage(text: '把输入框改成随内容增高'));
    for (var i = 0; i < 400 && review.calls.isEmpty; i++) {
      switch (session.pendingInteraction) {
        case QuestionRequest():
          session.answer(const QuestionAnswer([], skipped: true));
        case ApprovalRequest():
          session.answer(const ApprovalAnswer(ApprovalDecision.allowOnce));
        default:
      }
      await tester.pump(const Duration(milliseconds: 100));
    }
    // As the CLI tells it (the mock's, relative).
    const first = 'lib/chat/composer/composer.dart';
    expect(review.calls, ['before $first']);
    // The edit waits.
    await tester.pump(const Duration(seconds: 1));
    expect(review.calls, ['before $first']);
    expect(session.fileChanges, isEmpty);

    review.holdBefore!.complete();
    await finish(tester, session);
    expect(
      review.calls,
      containsAllInOrder([
        'before $first',
        'after $first',
        'report $first',
        'before lib/chat/chat_screen.dart',
        'after lib/chat/chat_screen.dart',
      ]),
    );
    // Its files looked at again as the turn ended.
    expect(review.calls.last, 'look');
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
}
