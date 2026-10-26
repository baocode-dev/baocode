@TestOn('vm')
library;

import 'dart:io';

import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/review/change_review.dart';
import 'package:baocode/chat/review/change_reviews.dart';
import 'package:baocode/chat/review/review_store_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Runs local Git (no network) on a project in a temporary folder, its
/// snapshots in another.
void main() {
  final hasGit = () {
    try {
      return Process.runSync('git', ['--version']).exitCode == 0;
    } on ProcessException {
      return false;
    }
  }();

  late Directory temp;
  late String root;
  late String checkpoints;

  String path(String relative) => p.joinAll([root, ...relative.split('/')]);

  void write(String relative, String text) {
    final file = File(path(relative));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(text);
  }

  String read(String relative) => File(path(relative)).readAsStringSync();

  Future<ChangeReview> open({String? session}) async {
    final store = await GitReviewStore.open(root, checkpoints: checkpoints);
    final review = ChangeReview(store!);
    addTearDown(review.dispose);
    if (session != null) review.session = session;
    return review;
  }

  /// The pending changes, by path relative to the project.
  Map<String, FileChange> changesOf(ChangeReview review) => {
    for (final change in review.changes)
      p.split(p.relative(change.path, from: root)).join('/'): change,
  };

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('baocode_review_');
    final resolved = await temp.resolveSymbolicLinks();
    root = p.join(resolved, 'project');
    checkpoints = p.join(resolved, 'checkpoints');
    write('a.txt', '1\n2\n3\n4\n5\n');
    write('lib/b.txt', 'b\n');
  });

  tearDown(() => temp.delete(recursive: true));

  test(
    'lists what the agent changed in a turn, not what changed before',
    () async {
      final review = await open();
      await review.begin();
      // Before the turn: not the agent's.
      write('notes.txt', 'mine\n');
      await review.begin();

      write('a.txt', 'one\n2\n3\n4\n5\n6\n');
      write('lib/c.txt', 'c\nc\n');
      File(path('lib/b.txt')).deleteSync();
      await review.observe();

      final changes = changesOf(review);
      expect(
        changes.keys,
        unorderedEquals(['a.txt', 'lib/b.txt', 'lib/c.txt']),
      );
      expect(changes['a.txt']!.kind, FileChangeKind.modified);
      expect((changes['a.txt']!.added, changes['a.txt']!.removed), (2, 1));
      expect(changes['lib/c.txt']!.kind, FileChangeKind.added);
      expect(changes['lib/c.txt']!.added, 2);
      expect(changes['lib/b.txt']!.kind, FileChangeKind.deleted);
      expect(changes['lib/b.txt']!.removed, 1);

      // Changed back by the agent: nothing pending.
      write('lib/c.txt', 'c\n');
      File(path('lib/c.txt')).deleteSync();
      await review.observe();
      expect(changesOf(review).keys, unorderedEquals(['a.txt', 'lib/b.txt']));
    },
    skip: !hasGit,
  );

  test('keeps a change without touching the file', () async {
    final review = await open();
    await review.begin();
    write('a.txt', 'one\n');
    write('lib/b.txt', 'bee\n');
    await review.observe();

    await review.keep([path('a.txt')]);
    expect(changesOf(review).keys, ['lib/b.txt']);
    expect(read('a.txt'), 'one\n');

    // Changed again by the agent: listed against what was kept.
    write('a.txt', 'one\ntwo\n');
    await review.observe();
    expect(changesOf(review)['a.txt']!.added, 1);
    expect(changesOf(review)['a.txt']!.removed, 0);

    await review.keepAll();
    expect(review.changes, isEmpty);
  }, skip: !hasGit);

  test('undoes edits, creations and deletions', () async {
    final review = await open();
    await review.begin();
    write('a.txt', 'one\n');
    write('new/deep/c.txt', 'c\n');
    File(path('lib/b.txt')).deleteSync();
    await review.observe();
    expect(review.changes, hasLength(3));

    await review.undoAll();
    expect(review.changes, isEmpty);
    expect(read('a.txt'), '1\n2\n3\n4\n5\n');
    expect(read('lib/b.txt'), 'b\n');
    // The folders it made go with the file.
    expect(Directory(path('new')).existsSync(), isFalse);

    // Undone, it is not the agent's change.
    await review.observe();
    expect(review.changes, isEmpty);
  }, skip: !hasGit);

  test('undo keeps what changed since the agent, or leaves the file', () async {
    final review = await open();
    await review.begin();
    write('a.txt', 'one\n2\n3\n4\n5\n');
    write('lib/b.txt', 'bee\n');
    await review.observe();

    // The user, after the turn.
    write('a.txt', 'one\n2\n3\n4\nfive\n');
    write('lib/b.txt', 'B\n');
    await review.begin();

    await review.undo([path('a.txt')]);
    expect(read('a.txt'), '1\n2\n3\n4\nfive\n');
    expect(changesOf(review).keys, ['lib/b.txt']);

    // The same line: left as it is, and marked.
    await review.undo([path('lib/b.txt')]);
    expect(read('lib/b.txt'), 'B\n');
    expect(changesOf(review)['lib/b.txt']!.conflict, isTrue);
  }, skip: !hasGit);

  test('keeps and undoes a change part by part', () async {
    final review = await open();
    await review.begin();
    write('a.txt', 'one\n2\n3\n4\nfive\n');
    await review.observe();
    final a = path('a.txt');
    final created = review.baseOf(a);
    expect(created, isNotNull);
    expect(await review.original(a)!(), '1\n2\n3\n4\n5\n');

    // The first line kept: held against what was there with it in.
    await review.keepPart(a, 'one\n2\n3\n4\n5\n');
    expect(review.baseOf(a), isNot(created));
    expect(await review.original(a)!(), 'one\n2\n3\n4\n5\n');
    expect(
      (changesOf(review)['a.txt']!.added, changesOf(review)['a.txt']!.removed),
      (1, 1),
    );
    expect(read('a.txt'), 'one\n2\n3\n4\nfive\n');

    // The last undone in the file, as the editor does it: nothing left.
    write('a.txt', 'one\n2\n3\n4\n5\n');
    await review.settle([a]);
    expect(review.changes, isEmpty);
    expect(review.baseOf(a), isNull);

    // Not the agent's at the next look.
    await review.observe();
    expect(review.changes, isEmpty);
  }, skip: !hasGit);

  test('keeping every part of a change keeps it', () async {
    final review = await open(session: 's');
    await review.begin();
    write('a.txt', '1\n2\nthree\n4\n5\n');
    await review.observe();
    await review.keepPart(path('a.txt'), '1\n2\nthree\n4\n5\n');
    expect(review.changes, isEmpty);
    expect(read('a.txt'), '1\n2\nthree\n4\n5\n');
  }, skip: !hasGit);

  test('puts back line endings and bytes as they were', () async {
    write('.gitattributes', '* text=auto\n');
    File(path('crlf.txt')).writeAsBytesSync('x\r\ny\r\n'.codeUnits);
    final review = await open();
    await review.begin();
    File(path('crlf.txt')).writeAsBytesSync('x\r\nz\r\n'.codeUnits);
    await review.observe();
    await review.undoAll();
    expect(File(path('crlf.txt')).readAsBytesSync(), 'x\r\ny\r\n'.codeUnits);
  }, skip: !hasGit);

  test('lists reported edits it cannot see, to keep and not undo', () async {
    write('.gitignore', 'out/\n');
    final review = await open();
    await review.begin();
    write('out/gen.txt', 'g\n');
    File(p.join(temp.path, 'elsewhere.txt')).writeAsStringSync('e\ne\n');
    review.report(FileChange(path: path('out/gen.txt'), added: 1, removed: 0));
    review.report(
      FileChange(
        path: p.join(temp.path, 'elsewhere.txt'),
        added: 2,
        removed: 0,
      ),
    );
    await review.observe(full: false);

    final changes = changesOf(review);
    expect(changes.keys, contains('out/gen.txt'));
    expect(changes['out/gen.txt']!.tracked, isFalse);
    expect(review.changes.where((c) => !c.tracked), hasLength(2));

    await review.undoAll();
    expect(File(path('out/gen.txt')).existsSync(), isTrue);
    await review.keepAll();
    expect(review.changes, isEmpty);
  }, skip: !hasGit);

  test('undoes reported edits outside the project (a worktree beside it), '
      'as the agent told what they were', () async {
    String beside(String name) => p.join(p.dirname(root), 'project-wt', name);
    File(beside('a.txt'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('1\n2\n3\n');
    final review = await open(session: 's');
    await review.begin();
    File(beside('a.txt')).writeAsStringSync('1\nTWO\n3\nfour\n');
    review.report(
      FileChange(path: beside('a.txt'), added: 2, removed: 1),
      original: const OriginalText('1\n2\n3\n'),
    );
    File(beside('new.txt')).writeAsStringSync('n\n');
    review.report(
      FileChange(path: beside('new.txt'), added: 1, removed: 0),
      original: const OriginalText(null),
    );
    await review.observe(full: false);

    final changes = {for (final c in review.changes) c.path: c};
    expect(changes.keys, unorderedEquals([beside('a.txt'), beside('new.txt')]));
    expect(changes.values.every((change) => change.tracked), isTrue);
    expect(
      (changes[beside('a.txt')]!.added, changes[beside('a.txt')]!.removed),
      (2, 1),
    );
    expect(changes[beside('new.txt')]!.kind, FileChangeKind.added);
    expect(await review.original(beside('a.txt'))!(), '1\n2\n3\n');

    // A full look (a command ran) leaves them as they are.
    await review.observe();
    expect(review.changes, hasLength(2));

    await review.undo([beside('a.txt')]);
    expect(File(beside('a.txt')).readAsStringSync(), '1\n2\n3\n');
    await review.undoAll();
    expect(review.changes, isEmpty);
    expect(File(beside('new.txt')).existsSync(), isFalse);
  }, skip: !hasGit);

  test("a subagent's edit outside the project, told only by its input, is "
      'undone by putting its texts back (#162)', () async {
    String beside(String name) => p.join(p.dirname(root), 'elsewhere', name);
    File(beside('o.txt'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('keep\nold line\nkeep\n');
    final review = await open(session: 's');
    await review.begin();
    File(beside('o.txt')).writeAsStringSync('keep\nnew line\nkeep\n');
    review.report(
      FileChange(path: beside('o.txt'), added: 1, removed: 1),
      original: const OriginalByEdits([(before: 'old', after: 'new')]),
    );
    await review.observe(full: false);
    final change = review.changes.single;
    expect(change.tracked, isTrue);
    expect(await review.original(beside('o.txt'))!(), 'keep\nold line\nkeep\n');
    await review.undo([beside('o.txt')]);
    expect(File(beside('o.txt')).readAsStringSync(), 'keep\nold line\nkeep\n');
  }, skip: !hasGit);

  test('a project opened through a link: its files told by their real '
      'path are its own, in its snapshots', () async {
    final link = p.join(temp.path, 'linked');
    Link(link).createSync(root);
    final store = await GitReviewStore.open(link, checkpoints: checkpoints);
    final review = ChangeReview(store!, realRoot: root);
    addTearDown(review.dispose);
    await review.begin();
    write('a.txt', 'changed\n');
    // As the agent tells it: by the real path.
    review.report(
      FileChange(path: path('a.txt'), added: 1, removed: 5),
      original: const OriginalText('1\n2\n3\n4\n5\n'),
    );
    await review.observe(full: false);
    expect([for (final c in review.changes) c.path], [p.join(link, 'a.txt')]);
    expect(review.changes.single.tracked, isTrue);
    expect(review.holds(path('lib/b.txt')), isTrue);
  }, skip: !hasGit);

  test('undoes reported edits to files the snapshots leave out, as the agent '
      'told what they were', () async {
    write('.gitignore', '.env\nout/\n');
    write('.env', 'KEY=1\n');
    write('out/notes.txt', 'a\nb\nc\n');
    final review = await open(session: 's');
    await review.begin();
    // Claude Code tells the file's text; Codex, its diff; a new file.
    write('.env', 'KEY=2\nMORE=1\n');
    review.report(
      FileChange(path: path('.env'), added: 2, removed: 1),
      original: const OriginalText('KEY=1\n'),
    );
    write('out/notes.txt', 'a\nB\nc\n');
    review.report(
      FileChange(path: path('out/notes.txt'), added: 1, removed: 1),
      original: const OriginalByPatch('@@ -1,3 +1,3 @@\n a\n-b\n+B\n c\n'),
    );
    write('out/new.txt', 'n\n');
    review.report(
      FileChange(path: path('out/new.txt'), added: 1, removed: 0),
      original: const OriginalText(null),
    );
    await review.observe(full: false);

    var changes = changesOf(review);
    expect(
      changes.keys,
      unorderedEquals(['.env', 'out/notes.txt', 'out/new.txt']),
    );
    expect(changes.values.every((change) => change.tracked), isTrue);
    expect((changes['.env']!.added, changes['.env']!.removed), (2, 1));
    expect(changes['out/new.txt']!.kind, FileChangeKind.added);
    expect(await review.original(path('out/notes.txt'))!(), 'a\nb\nc\n');

    // Edited again, by a command this time: still the agent's.
    write('.env', 'KEY=3\n');
    await review.observe();
    changes = changesOf(review);
    expect((changes['.env']!.added, changes['.env']!.removed), (1, 1));

    // The user, after the turn: carried over by Undo.
    write('out/notes.txt', 'a\nB\nc\nmine\n');
    await review.begin();
    await review.undoAll();
    expect(review.changes, isEmpty);
    expect(read('.env'), 'KEY=1\n');
    expect(read('out/notes.txt'), 'a\nb\nc\nmine\n');
    expect(File(path('out/new.txt')).existsSync(), isFalse);
  }, skip: !hasGit);

  test(
    'in a project too large to snapshot, reviews the edits reported',
    () async {
      final limit = GitReviewStore.maxFiles;
      GitReviewStore.maxFiles = 1;
      addTearDown(() => GitReviewStore.maxFiles = limit);
      // Its own folder: too large in this process.
      root = p.join(temp.path, 'large');
      write('a.txt', '1\n2\n');
      write('b.txt', 'b\n');
      final review = await open(session: 's');
      await review.begin();
      expect(review.failure, isNull);
      write('a.txt', '1\ntwo\n');
      write('b.txt', 'bee\n');
      review.report(
        FileChange(path: path('a.txt'), added: 1, removed: 1),
        original: const OriginalText('1\n2\n'),
      );
      await review.observe();
      // Not by a command: none seen.
      expect(changesOf(review).keys, ['a.txt']);
      expect(changesOf(review)['a.txt']!.tracked, isTrue);
      expect(changesOf(review)['a.txt']!.added, 1);

      final reopened = await ChangeReview.resume(
        (await GitReviewStore.open(root, checkpoints: checkpoints))!,
        's',
      );
      addTearDown(reopened.dispose);
      await reopened.begin();
      expect(changesOf(reopened).keys, ['a.txt']);
      await reopened.undoAll();
      expect(read('a.txt'), '1\n2\n');
      expect(read('b.txt'), 'bee\n');
    },
    skip: !hasGit,
  );

  test('drops the edits it cannot see once their files are gone', () async {
    final review = await open();
    await review.begin();
    final elsewhere = File(p.join(temp.path, 'cleanup.ps1'))
      ..writeAsStringSync('x\n');
    review.report(FileChange(path: elsewhere.path, added: 1, removed: 0));
    await review.observe();
    expect(review.changes.where((c) => !c.tracked), hasLength(1));

    elsewhere.deleteSync();
    await review.observe();
    expect(review.changes, isEmpty);
  }, skip: !hasGit);

  test('reported edits are looked at alone until the turn ends', () async {
    final review = await open();
    await review.begin();
    write('a.txt', 'one\n');
    write('lib/b.txt', 'bee\n');
    review.report(FileChange(path: path('a.txt'), added: 1, removed: 1));
    await review.observe(full: false);
    expect(changesOf(review).keys, ['a.txt']);
    await review.observe();
    expect(changesOf(review).keys, unorderedEquals(['a.txt', 'lib/b.txt']));
  }, skip: !hasGit);

  test('marks what changed while another agent worked there', () async {
    final mine = await open();
    final theirs = await open();
    await mine.begin();
    mine.working = true;
    theirs.working = true;
    write('a.txt', 'one\n');
    write('lib/b.txt', 'bee\n');
    mine.report(FileChange(path: path('a.txt'), added: 1, removed: 1));
    await mine.observe();
    final changes = changesOf(mine);
    expect(changes['a.txt']!.shared, isFalse);
    expect(changes['lib/b.txt']!.shared, isTrue);
  }, skip: !hasGit);

  test('carries on where the session left off', () async {
    final review = await open(session: 'session-1');
    await review.begin();
    write('a.txt', 'one\n');
    await review.observe();

    final reopened = await ChangeReview.resume(
      (await GitReviewStore.open(root, checkpoints: checkpoints))!,
      'session-1',
    );
    addTearDown(reopened.dispose);
    expect(changesOf(reopened).keys, ['a.txt']);
    // Put back by the user while the app was closed.
    write('lib/b.txt', 'mine\n');
    await reopened.begin();
    await reopened.observe();
    expect(changesOf(reopened).keys, ['a.txt']);
    // The agent, in the next turn.
    write('lib/b.txt', 'agent\n');
    await reopened.observe();
    expect(changesOf(reopened).keys, unorderedEquals(['a.txt', 'lib/b.txt']));
    await reopened.undo([path('a.txt')]);
    expect(read('a.txt'), '1\n2\n3\n4\n5\n');
  }, skip: !hasGit);

  test('leaves out its checkpoints where the project holds them', () async {
    // A home folder opened as the project, the data folder in it.
    checkpoints = path('.baocode-server/data/checkpoints');
    final review = await open();
    await review.begin();
    await review.begin();
    write('a.txt', 'one\n');
    await review.observe();
    expect(changesOf(review).keys, ['a.txt']);

    // Snapshots of an earlier build that took them in are let go.
    final store = (await GitReviewStore.open(root, checkpoints: checkpoints))!;
    final repository = p.relative(store.gitDir, from: root);
    await Process.run('git', [
      '--git-dir=${store.gitDir}',
      '--work-tree=$root',
      'add',
      '-f',
      '--',
      repository,
    ], workingDirectory: root);
    final reopened = (await GitReviewStore.open(
      root,
      checkpoints: checkpoints,
    ))!;
    final before = (await reopened.snapshot())!;
    write('lib/b.txt', 'two\n');
    final after = (await reopened.snapshot())!;
    expect((await reopened.diff(before, after)).map((change) => change.path), [
      'lib/b.txt',
    ]);
  }, skip: !hasGit);

  test("leaves the project's own repository alone", () async {
    Future<String> git(List<String> arguments) async {
      final result = await Process.run(
        'git',
        arguments,
        workingDirectory: root,
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
      return '${result.stdout}';
    }

    await git(['init', '-q']);
    await git(['add', '-A']);
    final status = await git(['status', '--porcelain']);
    final review = await open(session: 's');
    await review.begin();
    write('a.txt', 'one\n');
    await review.observe();
    await review.undoAll();

    expect(await git(['status', '--porcelain']), status);
    expect(await git(['for-each-ref']), isEmpty);
    expect(await git(['stash', 'list']), isEmpty);
  }, skip: !hasGit);

  test(
    'looks into repositories inside the project, leaving them alone',
    () async {
      // A folder of projects opened as one, each its own repository; one in
      // another.
      write('web/pages/a.vue', 'one\n');
      write('web/.gitignore', 'dist/\n');
      write('web/vendor/lib/c.js', 'c\n');
      Future<String> git(String repo, List<String> arguments) async {
        final result = await Process.run(
          'git',
          arguments,
          workingDirectory: path(repo),
        );
        expect(result.exitCode, 0, reason: '${result.stderr}');
        return '${result.stdout}';
      }

      for (final repo in ['web/vendor/lib', 'web']) {
        await git(repo, ['init', '-q']);
        await git(repo, ['add', '-A']);
        await git(repo, [
          '-c',
          'user.name=t',
          '-c',
          'user.email=t@t',
          'commit',
          '-qm',
          'i',
        ]);
      }
      final status = await git('web', ['status', '--porcelain']);

      final review = await open();
      await review.begin();
      write('a.txt', 'one\n');
      write('web/pages/a.vue', 'one\ntwo\n');
      write('web/vendor/lib/c.js', 'see\n');
      write('web/dist/out.js', 'built\n');
      for (final file in ['a.txt', 'web/pages/a.vue', 'web/vendor/lib/c.js']) {
        review.report(FileChange(path: path(file), added: 1, removed: 0));
      }
      // Only the files reported, then all.
      await review.observe(full: false);
      expect(review.failure, isNull);
      expect(
        changesOf(review).keys,
        unorderedEquals(['a.txt', 'web/pages/a.vue', 'web/vendor/lib/c.js']),
      );
      await review.observe();
      expect(review.failure, isNull);
      final changes = changesOf(review);
      expect(
        changes.keys,
        unorderedEquals(['a.txt', 'web/pages/a.vue', 'web/vendor/lib/c.js']),
      );
      expect(changes['web/pages/a.vue']!.tracked, isTrue);
      expect(
        (
          changes['web/pages/a.vue']!.added,
          changes['web/pages/a.vue']!.removed,
        ),
        (1, 0),
      );
      expect(await review.original(path('web/pages/a.vue'))!(), 'one\n');
      expect(await review.original(path('web/vendor/lib/c.js'))!(), 'c\n');

      await review.undo([path('web/pages/a.vue'), path('web/vendor/lib/c.js')]);
      expect(read('web/pages/a.vue'), 'one\n');
      expect(read('web/vendor/lib/c.js'), 'c\n');
      expect(changesOf(review).keys, ['a.txt']);
      File(path('web/dist/out.js')).deleteSync();
      expect(await git('web', ['status', '--porcelain']), status);
    },
    skip: !hasGit,
  );

  test(
    'leaves large files out of a whole snapshot, in repositories inside too',
    () async {
      final limit = GitReviewStore.maxFileBytes;
      GitReviewStore.maxFileBytes = 20;
      addTearDown(() => GitReviewStore.maxFileBytes = limit);
      write('big.bin', 'x' * 21);
      write('web/small.txt', 's\n');
      write('web/big.bin', 'x' * 21);
      for (final arguments in [
        ['init', '-q'],
        ['add', 'small.txt'],
        ['-c', 'user.name=t', '-c', 'user.email=t@t', 'commit', '-qm', 'i'],
      ]) {
        final result = await Process.run(
          'git',
          arguments,
          workingDirectory: path('web'),
        );
        expect(result.exitCode, 0, reason: '${result.stderr}');
      }

      final store = await GitReviewStore.open(root, checkpoints: checkpoints);
      final tree = (await store!.snapshot())!;
      expect(await store.contains(tree, 'a.txt'), isTrue);
      expect(await store.contains(tree, 'web/small.txt'), isTrue);
      expect(await store.contains(tree, 'big.bin'), isFalse);
      expect(await store.contains(tree, 'web/big.bin'), isFalse);
    },
    skip: !hasGit,
  );

  test('a workspace of several folders: each snapshotted, one inside '
      "another the other's", () async {
    final other = p.join(temp.path, 'other');
    File(p.join(other, 'x.txt'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('x\n');
    final reviews = (await ChangeReviews.open(
      [root, other, path('lib')],
      open: (folder, {session}) async {
        final store = await GitReviewStore.open(
          folder,
          checkpoints: checkpoints,
        );
        return ChangeReview(store!);
      },
    ))!;
    addTearDown(reviews.dispose);
    await reviews.begin();
    write('lib/b.txt', 'bee\n');
    File(p.join(other, 'x.txt')).writeAsStringSync('ex\n');
    await reviews.observe();
    expect([
      for (final change in reviews.changes) change.path,
    ], unorderedEquals([path('lib/b.txt'), p.join(other, 'x.txt')]));
    await reviews.undoAll();
    expect(read('lib/b.txt'), 'b\n');
    expect(File(p.join(other, 'x.txt')).readAsStringSync(), 'x\n');
  }, skip: !hasGit);
}
