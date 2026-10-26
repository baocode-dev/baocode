// Part of a file's changes committed (JetBrains IDEs' check box by each
// change): the text a commit takes, and the commit through an index of its
// own, in a real repository, what is staged left alone.

import 'dart:io';

import 'package:bao_editor/monaco/flutter/document_snapshot.dart';
import 'package:bao_editor/monaco/vs/editor/common/diff/default_lines_diff_computer/default_lines_diff_computer.dart';
import 'package:baocode/ide/git/git_partial.dart';
import 'package:baocode/ide/git/git_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _original = 'a\nb\nc\nd\ne\n';
const _modified = 'a\nB\nc\nd\nE\nf\n';

List<String> _keys(String original, String modified) {
  List<String> lines(String text) => text.split('\n');
  final diff = DefaultLinesDiffComputer().computeDiff(
    lines(original),
    lines(modified),
    ideGitHunkOptions,
  );
  return ideGitHunkKeys(
    DocumentSnapshot(original),
    DocumentSnapshot(modified),
    diff.changes,
  );
}

void main() {
  test('the changes left unchecked stay out', () async {
    final keys = _keys(_original, _modified);
    expect(keys, hasLength(2));
    expect(
      await ideGitPartialText(_original, _modified, {keys.last}),
      'a\nB\nc\nd\ne\n',
    );
    expect(
      await ideGitPartialText(_original, _modified, {keys.first}),
      'a\nb\nc\nd\nE\nf\n',
    );
    expect(await ideGitPartialText(_original, _modified, {}), _modified);
  });

  test("a change's lines left unchecked stay out", () async {
    final hunk = _keys(_original, _modified).last;
    String line(int n, {bool removed = false}) =>
        ideGitLineKey(hunk, n, removed: removed);
    // e → E, f: f left out.
    expect(
      await ideGitPartialText(_original, _modified, {line(1)}),
      'a\nB\nc\nd\nE\n',
    );
    // e kept, E left out: f put in after it.
    expect(
      await ideGitPartialText(_original, _modified, {
        line(0, removed: true),
        line(0),
      }),
      'a\nB\nc\nd\ne\nf\n',
    );
    // At the end of a text with no line break after it.
    final last = _keys('a\nb', 'a\nX\nY').single;
    expect(
      await ideGitPartialText('a\nb', 'a\nX\nY', {
        ideGitLineKey(last, 1, removed: false),
      }),
      'a\nX',
    );
    expect(
      await ideGitPartialText('a\nb', 'a\nX\nY', {
        ideGitLineKey(last, 0, removed: true),
        ideGitLineKey(last, 0, removed: false),
      }),
      'a\nb\nY',
    );
  });

  test("a change's own check box takes its lines along", () {
    final selection = IdeGitHunkSelection()
      ..setIncluded('a', ideGitLineKey('k', 0, removed: false), false);
    expect(selection.isPartial('a'), isTrue);
    selection.setIncluded('a', 'k', true);
    expect(selection.isPartial('a'), isFalse);
  });

  test("what of a file goes, as git diff writes it", () async {
    final lines = [for (var i = 1; i <= 12; i++) 'l$i'];
    final changed = [...lines]
      ..[1] = 'L2'
      ..[10] = 'L11';
    expect(
      await ideGitUnifiedDiff(
        'a.txt',
        '${lines.join('\n')}\n',
        '${changed.join('\n')}\n',
      ),
      'diff --git a/a.txt b/a.txt\n'
      '--- a/a.txt\n'
      '+++ b/a.txt\n'
      '@@ -1,5 +1,5 @@\n'
      ' l1\n-l2\n+L2\n l3\n l4\n l5\n'
      '@@ -8,5 +8,5 @@\n'
      ' l8\n l9\n l10\n-l11\n+L11\n l12\n',
    );
  });

  test('a change keeps its key as lines come above it', () {
    final before = _keys(_original, _modified);
    final after = _keys('0\n$_original', '0\n$_modified');
    expect(after, before);
  });

  test('a real commit of part of a file', () async {
    if ((await Process.run('git', ['--version'])).exitCode != 0) return;
    final folder = await Directory.systemTemp.createTemp('partial');
    addTearDown(() => folder.delete(recursive: true));
    final root = folder.resolveSymbolicLinksSync();
    Future<String> git(List<String> arguments) async {
      final result = await Process.run(
        'git',
        arguments,
        workingDirectory: root,
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
      return result.stdout as String;
    }

    await git(['init', '-q']);
    await git(['config', 'user.email', 'a@b.c']);
    await git(['config', 'user.name', 'A']);
    final a = p.join(root, 'a.txt');
    final b = p.join(root, 'b.txt');
    final c = p.join(root, 'c.txt');
    File(a).writeAsStringSync(_original);
    File(b).writeAsStringSync('b\n');
    File(c).writeAsStringSync('c\n');
    await git(['add', '.']);
    await git(['commit', '-q', '-m', 'first']);
    File(a).writeAsStringSync(_modified);
    File(b).writeAsStringSync('b2\n');
    // Staged, not to be committed.
    File(c).writeAsStringSync('c2\n');
    await git(['add', 'c.txt']);

    final keys = _keys(_original, _modified);
    final partial = await ideGitPartialText(_original, _modified, {keys.last});
    await IdeGitService(root).commitPartial('second', [b], {a: partial});

    expect(await git(['show', 'HEAD:a.txt']), 'a\nB\nc\nd\ne\n');
    expect(await git(['show', 'HEAD:b.txt']), 'b2\n');
    expect(await git(['show', 'HEAD:c.txt']), 'c\n');
    expect(File(a).readAsStringSync(), _modified);
    expect(await git(['status', '--porcelain']), ' M a.txt\nM  c.txt\n');
  });
}
