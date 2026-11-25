import 'dart:async';

import 'package:baocode/ide/git/git_repository.dart';
import 'package:baocode/ide/git/git_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_git.dart';

void main() {
  late FakeGit git;
  late StreamController<String> changes;
  late IdeGitRepository repository;

  setUp(() async {
    git = FakeGit('/project');
    changes = StreamController<String>();
    repository = IdeGitRepository(
      IdeGitService(git.root, runner: git.run, watcher: (_) => changes.stream),
      refreshDelay: const Duration(milliseconds: 50),
    );
    await repository.refresh();
    git.calls.clear();
  });

  tearDown(() async {
    repository.dispose();
    await changes.close();
  });

  int statusReads() => git.callsTo('status').length;

  test('files that keep changing do not hold the status back', () async {
    final ticker = Timer.periodic(
      const Duration(milliseconds: 10),
      (_) => changes.add(''),
    );
    addTearDown(ticker.cancel);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(statusReads(), greaterThanOrEqualTo(1));
  });

  test('a burst of changes reads the status once', () async {
    for (var i = 0; i < 20; i++) {
      changes.add('');
    }
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(statusReads(), 1);
  });

  test('what changes in an ignored folder does not read the status; '
      'what changes beside it does', () async {
    git.status = '## main\x00!! build/\x00';
    await repository.refresh();
    git.calls.clear();
    for (var i = 0; i < 20; i++) {
      changes.add('/project/build/out/$i.o');
    }
    changes.add('/project/build');
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(statusReads(), 0);

    changes.add('/project/lib/a.dart');
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(statusReads(), 1);
  });

  test('refreshes asked while one waits to start are that one', () async {
    final release = Completer<void>();
    git.hold = (arguments) =>
        arguments.first == 'status' ? release.future : null;
    final running = repository.refresh();
    await Future<void>.delayed(Duration.zero);
    final waiting = [repository.refresh(), repository.refresh()];
    expect(identical(waiting[0], waiting[1]), isTrue);
    git.hold = null;
    release.complete();
    await running;
    await Future.wait(waiting);
    expect(statusReads(), 2);
  });

  test('a watch error reads the status again', () async {
    changes.addError(Exception('overflow'));
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(statusReads(), 1);
  });

  test(
    'an operation forces a fresh status after a queued watcher refresh',
    () async {
      git.status = '## main...origin/main [behind 1]\x00';
      await repository.refresh();
      final statusRelease = Completer<void>();
      final pullRelease = Completer<void>();
      git.hold = (arguments) {
        if (arguments.first == 'status') return statusRelease.future;
        if (arguments.first == 'pull') return pullRelease.future;
        return null;
      };

      changes.add('');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final syncing = repository.sync();
      await Future<void>.delayed(Duration.zero);
      statusRelease.complete();
      await Future<void>.delayed(Duration.zero);
      git.status = '## main...origin/main\x00';
      pullRelease.complete();
      await syncing;

      expect(repository.state!.head.behind, 0);
    },
  );

  group('a push refused because the remote moved on', () {
    test('is recognized from Git\'s rejection text', () {
      expect(
        isGitPushRejected(
          'Cannot push.\n! [rejected] main -> main (fetch first)\n'
          'error: failed to push some refs',
        ),
        isTrue,
      );
      expect(
        isGitPushRejected(
          'Cannot push.\nerror: non-fast-forward updates were rejected',
        ),
        isTrue,
      );
      expect(
        isGitPushRejected('Cannot push.\n! [rejected] main -> main (先获取)'),
        isTrue,
      );
      expect(
        isGitPushRejected('Cannot push.\n提示：更新被拒绝，因为您当前分支的最新提交落后于其对应的远程分支。'),
        isTrue,
      );
      expect(isGitPushRejected('Cannot push. No such remote.'), isFalse);
    });
  });

  group('automatic fetch', () {
    tearDown(() {
      GitAutoFetchSetting.current = () => Duration.zero;
      GitAutoFetchSetting.changes = null;
    });

    test('fetches a tracking branch on the interval and refreshes behind',
        () async {
      GitAutoFetchSetting.current = () => const Duration(milliseconds: 40);
      git.status = '## main...origin/main\x00';
      final auto = IdeGitRepository(
        IdeGitService(
          git.root,
          runner: git.run,
          watcher: (_) => changes.stream,
        ),
        refreshDelay: const Duration(milliseconds: 10),
      );
      addTearDown(auto.dispose);
      await auto.refresh();
      git.calls.clear();

      git.status = '## main...origin/main [behind 1]\x00';
      await Future<void>.delayed(const Duration(milliseconds: 140));

      expect(git.callsTo('fetch'), isNotEmpty);
      expect(auto.state!.head.behind, 1);
    });

    test('a branch with no upstream is not fetched', () async {
      GitAutoFetchSetting.current = () => const Duration(milliseconds: 40);
      git.status = '## main\x00';
      final auto = IdeGitRepository(
        IdeGitService(git.root, runner: git.run),
        refreshDelay: const Duration(milliseconds: 10),
      );
      addTearDown(auto.dispose);
      await auto.refresh();
      git.calls.clear();

      await Future<void>.delayed(const Duration(milliseconds: 140));
      expect(git.callsTo('fetch'), isEmpty);
    });
  });

  group('past the status limit', () {
    String huge() => [
      '## main\x00',
      for (var i = 0; i <= IdeGitService.statusLimit; i++) '?? many/f$i\x00',
    ].join();

    test('only its first changes are kept, and file changes no longer read '
        'it until a refresh finds fewer', () async {
      final changes = StreamController<String>.broadcast();
      addTearDown(changes.close);
      final repository = IdeGitRepository(
        IdeGitService(
          git.root,
          runner: git.run,
          watcher: (_) => changes.stream,
        ),
        refreshDelay: const Duration(milliseconds: 20),
      );
      addTearDown(repository.dispose);
      git.status = huge();
      await repository.refresh();
      expect(repository.state!.didHitLimit, isTrue);
      expect(repository.state!.count, IdeGitService.statusLimit);
      expect(changes.hasListener, isFalse);

      git.calls.clear();
      changes.add('');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(statusReads(), 0);

      git.status = '## main\x00?? one\x00';
      await repository.refresh();
      expect(repository.state!.didHitLimit, isFalse);
      expect(changes.hasListener, isTrue);
      changes.add('');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(statusReads(), 2);
    });

    test(
      'Commit everything stages the whole tree, not the changes known',
      () async {
        git.status = huge();
        await repository.refresh();
        await repository.commitEverything('All');
        expect(git.callsTo('add'), [
          ['add', '-A', '--', '.'],
        ]);
      },
    );
  });
}
