import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/editor/monaco/flutter/editor_document_model.dart';
import 'package:baocode/ide/editor/monaco/flutter/editor_surface.dart';
import 'package:baocode/ide/editor/monaco/vs/editor/common/core/range.dart';
import 'package:baocode/ide/editor/monaco/vs/editor/common/diff/range_mapping.dart';
import 'package:baocode/ide/git/git_blame.dart';
import 'package:baocode/ide/git/git_model.dart';
import 'package:baocode/ide/git/git_repository.dart';
import 'package:baocode/ide/ide_editor.dart';
import 'package:baocode/ide/ide_workspace.dart';
import 'package:baocode/l10n/app_localizations_zh.dart';

import '../workbench/fake_files.dart';
import 'fake_git.dart';

final _ada = 'a' * 40;
final _grace = 'b' * 40;
final _head = 'c' * 40;

/// `one` and `two` by Ada, `three` by Grace, `four` not committed yet.
String _blameOutput() => [
  gitBlameEntry(_ada, 1, 2, author: 'Ada', summary: 'Initial commit'),
  gitBlameEntry(_grace, 3, 1, author: 'Grace', summary: 'Third line'),
  gitBlameEntry(
    ideGitUncommittedHash,
    4,
    1,
    author: 'Not Committed Yet',
    summary: 'Version of a.dart from a.dart',
  ),
].join();

void main() {
  test('parseGitBlame reads commits, all their ranges and uncommitted '
      'lines', () {
    final blame = parseGitBlame(
      [
        gitBlameEntry(_ada, 1, 2, author: 'Ada', summary: 'Initial commit'),
        gitBlameEntry(
          ideGitUncommittedHash,
          3,
          1,
          author: 'Not Committed Yet',
          summary: 'Version of a.dart from a.dart',
        ),
        // A commit seen before comes without its properties.
        gitBlameEntry(_ada, 4, 1),
      ].join(),
    );
    expect(blame, hasLength(2));
    final ada = blame.first;
    expect(ada.hash, _ada);
    expect(ada.authorName, 'Ada');
    expect(ada.authorEmail, 'ada@example.com');
    expect(ada.authorDate, DateTime.fromMillisecondsSinceEpoch(1767225600000));
    expect(ada.subject, 'Initial commit');
    expect(ada.ranges, [
      (startLineNumber: 1, endLineNumber: 2),
      (startLineNumber: 4, endLineNumber: 4),
    ]);
    expect(ada.uncommitted, isFalse);
    expect(blame.last.uncommitted, isTrue);
    expect(parseGitBlame(''), isEmpty);
  });

  test('a line maps past the unsaved changes before it', () {
    final changes = [
      // Two lines added, one changed, two deleted.
      LineRangeMapping(LineRange(3, 3), LineRange(3, 5)),
      LineRangeMapping(LineRange(8, 9), LineRange(10, 11)),
      LineRangeMapping(LineRange(13, 15), LineRange(15, 15)),
    ];
    expect(ideGitSavedLineNumber(2, changes), 2);
    expect(ideGitSavedLineNumber(3, changes), isNull);
    expect(ideGitSavedLineNumber(4, changes), isNull);
    expect(ideGitSavedLineNumber(5, changes), 3);
    expect(ideGitSavedLineNumber(9, changes), 7);
    expect(ideGitSavedLineNumber(10, changes), isNull);
    expect(ideGitSavedLineNumber(14, changes), 12);
    // Upstream compares the deletion with 13, the line as mapped so far.
    expect(ideGitSavedLineNumber(15, changes), 15);
    expect(ideGitSavedLineNumber(7, const []), 7);
  });

  test("the template takes the commit's tokens", () {
    final now = DateTime(2026, 1, 3);
    final blame = IdeGitBlameInformation(
      hash: _ada,
      ranges: const [],
      authorName: 'Ada',
      authorEmail: 'ada@example.com',
      authorDate: DateTime(2026, 1, 1),
      subject: 'x' * 60,
    );
    expect(
      formatGitBlame(ideGitBlameTemplate, blame, now: now),
      'Ada, 2 days ago • ${'x' * 50}…',
    );
    expect(
      formatGitBlame(
        ideGitBlameTemplate,
        blame,
        now: now,
        l10n: AppLocalizationsZh(),
      ),
      'Ada, 2 天前 • ${'x' * 50}…',
    );
    expect(
      formatGitBlame(r'${hashShort} <${authorEmail}> ${unknown}', blame),
      'aaaaaaa <ada@example.com> \${unknown}',
    );
  });

  group('IdeGitBlameController', () {
    const path = '/repo/a.dart';
    late FakeGit git;
    late IdeGitRepository repository;
    late EditorDocumentModel model;
    late IdeGitBlameController blame;

    setUp(() async {
      git = FakeGit('/repo')
        ..refs['HEAD'] = _head
        ..blame['a.dart'] = _blameOutput();
      repository = git.repository();
      model = EditorDocumentModel('one\ntwo\nthree\nfour\n');
      blame = IdeGitBlameController();
      await pumpEventQueue();
    });

    tearDown(() {
      blame.dispose();
      repository.dispose();
      model.dispose();
    });

    void show(List<int> carets, {bool navigated = true, String file = path}) =>
        blame.update(
          repository: repository,
          path: file,
          model: model,
          selections: [
            for (final offset in carets)
              TextSelection.collapsed(offset: offset),
          ],
          navigated: navigated,
        );

    List<(int, String?)> shown() => [
      for (final line in blame.lines)
        (line.lineNumber, line.commit?.authorName),
    ];

    int blames() => git.calls.where((call) => call.contains('blame')).length;

    test('shows the commit of each line with a caret, once read', () async {
      var notified = 0;
      blame.addListener(() => notified++);
      show([4]);
      expect(blame.lines, isEmpty);
      await pumpEventQueue();
      expect(shown(), [(2, 'Ada')]);
      expect(blame.lines.single.commit!.subject, 'Initial commit');

      // One line per caret line, in the carets' order; read once.
      show([9, 5, 10]);
      expect(shown(), [(3, 'Grace'), (2, 'Ada')]);
      expect(blames(), 1);

      // The same lines do not notify.
      final before = notified;
      show([10, 6]);
      expect(notified, before);
    });

    test('uncommitted lines and the start of the file show upon navigation '
        'only', () async {
      show([15], navigated: false);
      await pumpEventQueue();
      expect(blame.lines, isEmpty);
      show([15]);
      expect(shown(), [(4, null)]);

      show([0], navigated: false);
      expect(blame.lines, isEmpty);
      show([0]);
      expect(shown(), [(1, 'Ada')]);
    });

    test('unsaved edits are diffed before lines show again', () async {
      show([9]);
      await pumpEventQueue();
      expect(shown(), [(3, 'Grace')]);

      model.applyEdit(Range(1, 1, 1, 1), 'zero\n');
      // `three` is now line 4; until diffed, nothing shows.
      show([15], navigated: false);
      expect(blame.lines, isEmpty);
      await Future<void>.delayed(IdeGitBlameController.diffDelay * 2);
      expect(shown(), [(4, 'Grace')]);

      // The added line upon navigation only.
      show([2], navigated: false);
      expect(blame.lines, isEmpty);
      show([2]);
      expect(shown(), [(1, null)]);
      expect(blames(), 1);
    });

    test('a save or a commit blames the file again', () async {
      show([4]);
      await pumpEventQueue();
      expect(blames(), 1);

      // A status with HEAD where it was does not.
      await repository.refresh();
      await pumpEventQueue();
      expect(blames(), 1);

      model.applyEdit(Range(1, 1, 1, 1), 'zero\n');
      model.markSaved();
      git.blame['a.dart'] = [
        gitBlameEntry(ideGitUncommittedHash, 1, 1, author: 'Not Committed Yet'),
        gitBlameEntry(_ada, 2, 2, author: 'Ada', summary: 'Initial commit'),
        gitBlameEntry(_grace, 4, 1, author: 'Grace', summary: 'Third line'),
      ].join();
      show([9]);
      await pumpEventQueue();
      expect(blames(), 2);
      expect(shown(), [(3, 'Ada')]);

      git.refs['HEAD'] = 'd' * 40;
      git.blame['a.dart'] = gitBlameEntry(
        _grace,
        1,
        6,
        author: 'Grace',
        summary: 'Commit all',
      );
      await repository.refresh();
      await pumpEventQueue();
      expect(blames(), 3);
      expect(shown(), [(3, 'Grace')]);
    });

    test('files Git cannot blame and clear show nothing', () async {
      show([4], file: '/repo/new.dart');
      await pumpEventQueue();
      expect(blame.lines, isEmpty);

      show([4]);
      await pumpEventQueue();
      expect(blame.lines, isNotEmpty);
      blame.clear();
      expect(blame.lines, isEmpty);
    });
  });

  testWidgets('the editor shows the blame after the caret line', (
    tester,
  ) async {
    const root = '/repo';
    const path = '/repo/a.dart';
    final git = FakeGit(root)
      ..refs['HEAD'] = _head
      ..blame['a.dart'] = _blameOutput();
    final workspace = IdeWorkspace(
      root,
      files: TreeFiles({path: 'one\ntwo\nthree\nfour\n'}),
      git: git.repository(),
    );
    addTearDown(workspace.dispose);
    await workspace.open(path);
    final key = GlobalKey<IdeEditorState>();

    Future<void> mount({bool gitBlame = true}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IdeEditor(
              key: key,
              workspace: workspace,
              active: workspace.active!,
              nativeEditorEnabled: true,
              gitBlame: gitBlame,
              onError: (error) => fail('$error'),
              onLspStatus: (_) {},
              onPositionChanged: (_) {},
            ),
          ),
        ),
      );
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
    }

    List<(int, String?)> afterTexts() => [
      for (final decoration
          in tester
              .widget<EditorSurface>(find.byType(EditorSurface))
              .decorations)
        if (decoration.afterText case final text?) (decoration.start, text),
    ];

    await mount();
    // Opened with the caret at the start: nothing until it moves.
    expect(afterTexts(), isEmpty);
    await key.currentState!.revealLine(3);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
    final [(offset, text)] = afterTexts();
    // After `three`.
    expect(offset, 13);
    expect(text, startsWith('Grace, '));
    expect(text, endsWith(' • Third line'));

    await mount(gitBlame: false);
    expect(afterTexts(), isEmpty);
  });
}
