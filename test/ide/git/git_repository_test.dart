import 'dart:async';

import 'package:baocode/ide/git/git_repository.dart';
import 'package:baocode/ide/git/git_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_git.dart';

void main() {
  late FakeGit git;
  late StreamController<void> changes;
  late IdeGitRepository repository;

  setUp(() async {
    git = FakeGit('/project');
    changes = StreamController<void>();
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
      (_) => changes.add(null),
    );
    addTearDown(ticker.cancel);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(statusReads(), greaterThanOrEqualTo(1));
  });

  test('a burst of changes reads the status once', () async {
    for (var i = 0; i < 20; i++) {
      changes.add(null);
    }
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
}
