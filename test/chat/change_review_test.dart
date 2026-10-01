@TestOn('vm')
library;

import 'dart:io';

import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/review/change_review.dart';
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
    await reopened.undoAll();
    expect(read('a.txt'), '1\n2\n3\n4\n5\n');
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
}
