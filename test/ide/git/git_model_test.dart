import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/editor/monaco/vs/workbench/services/themes/common/color_theme_data.dart';
import 'package:baocode/ide/git/git_model.dart';
import 'package:baocode/theme/workbench_theme.dart';
import 'package:path/path.dart' as p;

final _root = p.join(p.separator, 'repo');
String _in(String relative) => p.joinAll([_root, ...relative.split('/')]);

IdeGitCommit _commit(
  String id,
  List<String> parents, {
  List<IdeGitRef> refs = const [],
}) => IdeGitCommit(
  id: id,
  parentIds: parents,
  subject: id,
  message: id,
  author: 'Ada',
  authorEmail: 'ada@example.com',
  date: DateTime.utc(2026),
  references: refs,
);

void main() {
  group('status', () {
    test('groups resources as VS Code does', () {
      final state = parseGitStatus(
        _root,
        '## main...origin/main [ahead 2, behind 1]\x00'
        'M  lib/staged.dart\x00'
        'MM lib/both.dart\x00'
        ' D gone.txt\x00'
        'R  new.dart\x00old.dart\x00'
        'UU conflict.dart\x00'
        '?? notes/todo.md\x00'
        '!! build/\x00'
        '!! debug.log\x00',
      );
      expect(state.head.branch, 'main');
      expect(state.head.upstream, 'origin/main');
      expect((state.head.ahead, state.head.behind), (2, 1));

      final staged = state.group(IdeGitGroup.staged);
      expect(
        [for (final r in staged) (r.path, r.status)],
        [
          (_in('lib/staged.dart'), IdeGitStatus.indexModified),
          (_in('lib/both.dart'), IdeGitStatus.indexModified),
          (_in('new.dart'), IdeGitStatus.indexRenamed),
        ],
      );
      expect(staged.last.originalPath, _in('old.dart'));
      expect(
        [for (final r in state.group(IdeGitGroup.workingTree)) r.status],
        [IdeGitStatus.modified, IdeGitStatus.deleted, IdeGitStatus.untracked],
      );
      expect(
        state.group(IdeGitGroup.merge).single.status,
        IdeGitStatus.bothModified,
      );
      // Both groups count, as `git.countBadge: all` does.
      expect(state.count, 7);
      expect(state.ignored, [_in('build'), _in('debug.log')]);
    });

    test('branch lines: unborn, detached, gone upstream', () {
      expect(
        parseGitStatus(_root, '## No commits yet on main\x00').head.unborn,
        isTrue,
      );
      expect(
        parseGitStatus(_root, '## HEAD (no branch)\x00').head.branch,
        isNull,
      );
      final gone = parseGitStatus(_root, '## topic...origin/topic [gone]\x00');
      expect((gone.head.branch, gone.head.upstream), ('topic', 'origin/topic'));
    });

    test('letters, colors and strike-through follow the Git extension', () {
      expect(IdeGitStatus.untracked.letter, 'U');
      expect(
        IdeGitStatus.untracked.colorId,
        'gitDecoration.untrackedResourceForeground',
      );
      expect(
        IdeGitStatus.untracked.color,
        themeColors['gitDecoration.untrackedResourceForeground'],
      );
      expect(IdeGitStatus.indexAdded.letter, 'A');
      expect(IdeGitStatus.bothModified.letter, '!');
      expect(IdeGitStatus.deleted.strikeThrough, isTrue);
      expect(IdeGitStatus.modified.strikeThrough, isFalse);
      expect(IdeGitStatus.bothAdded.label, 'Conflict: Both Added');
    });
  });

  group('decorations', () {
    test('files take the working tree over the index; folders a dot in their '
        'most important change', () {
      final decorations = parseGitStatus(
        _root,
        'MM lib/both.dart\x00'
        '?? lib/src/new.dart\x00'
        ' D lib/old/gone.dart\x00'
        'UU lib/src/merge.dart\x00'
        '!! build/\x00',
      ).decorations;
      final both = decorations.file(_in('lib/both.dart'))!;
      expect(both.letter, 'M');
      expect(both.colorId, 'gitDecoration.modifiedResourceForeground');
      expect(decorations.file(_in('lib/src/new.dart'))!.letter, 'U');
      expect(decorations.file(_in('lib/old/gone.dart'))!.strikeThrough, isTrue);
      expect(decorations.file(_in('lib/clean.dart')), isNull);

      final src = decorations.folder(_in('lib/src'))!;
      expect(src.letter, '•');
      expect(src.colorId, 'gitDecoration.conflictingResourceForeground');
      expect(
        decorations.folder(_in('lib'))!.colorId,
        'gitDecoration.conflictingResourceForeground',
      );
      // Deletions do not propagate.
      expect(decorations.folder(_in('lib/old')), isNull);

      // Ignored folders dim themselves and everything in them, unlettered.
      final build = decorations.folder(_in('build'))!;
      expect(build.colorId, 'gitDecoration.ignoredResourceForeground');
      expect(build.letter, isNull);
      expect(
        decorations.file(_in('build/app/out.js'))!.colorId,
        'gitDecoration.ignoredResourceForeground',
      );
    });

    test('a decoration takes its color from the current color theme', () {
      final decorations = parseGitStatus(_root, '?? new.dart\x00').decorations;
      final decoration = decorations.file(_in('new.dart'))!;
      expect(
        decoration.color,
        themeColors['gitDecoration.untrackedResourceForeground'],
      );
      WorkbenchThemeService.instance = WorkbenchThemeService(
        initial: ColorThemeData.createUnloadedThemeForThemeType(
          ColorScheme.light,
          {'gitDecoration.untrackedResourceForeground': '#007100'},
        ),
      );
      expect(decoration.color, const Color(0xFF007100));
    });
  });

  group('log', () {
    test('parses commits, messages and references', () {
      final commits = parseGitLog(
        'aaaa\x1fbbbb cccc\x1fAda\x1fada@example.com\x1f1767225600\x1f'
        'HEAD -> refs/heads/main, tag: refs/tags/v1, refs/remotes/origin/main,'
        ' refs/remotes/origin/HEAD\x1fMerge topic\n\nDetails\n\x1e\n'
        'bbbb\x1f\x1fGrace\x1fg@example.com\x1f1767139200\x1f\x1fFirst\n\x1e',
      );
      expect(commits, hasLength(2));
      final merge = commits.first;
      expect(merge.parentIds, ['bbbb', 'cccc']);
      expect(merge.subject, 'Merge topic');
      expect(merge.message, 'Merge topic\n\nDetails');
      expect(merge.date, DateTime.fromMillisecondsSinceEpoch(1767225600000));
      expect(
        [for (final r in merge.references) (r.name, r.kind)],
        [
          ('main', IdeGitRefKind.head),
          ('origin/main', IdeGitRefKind.remote),
          ('v1', IdeGitRefKind.tag),
        ],
      );
      expect(commits.last.parentIds, isEmpty);
    });
  });

  group('graph', () {
    const blue = IdeGraphColors.ref;
    final first = IdeGraphColors.lanes.first;

    test('a merge opens a lane in the next color and closes it', () {
      const main = IdeGitRef('refs/heads/main', 'main', IdeGitRefKind.head);
      final rows = ideGraphRows(
        [
          _commit('M', ['A2', 'B1'], refs: [main]),
          _commit('A2', ['A1']),
          _commit('B1', ['A1']),
          _commit('A1', []),
        ],
        headRef: 'refs/heads/main',
        headRevision: 'M',
      );
      expect(rows.first.kind, IdeGraphRowKind.head);
      expect(rows.first.outputLanes, [
        const IdeGraphLane('A2', blue),
        IdeGraphLane('B1', first),
      ]);
      expect(rows.first.referenceColors, {'refs/heads/main': blue});
      expect(rows[1].outputLanes, [
        const IdeGraphLane('A1', blue),
        IdeGraphLane('B1', first),
      ]);
      expect(rows[2].circleIndex, 1);
      expect(rows[2].outputLanes, [
        const IdeGraphLane('A1', blue),
        IdeGraphLane('A1', first),
      ]);
      expect(rows[3].circleIndex, 0);
      expect(rows[3].outputLanes, isEmpty);
    });

    test('ahead and behind add outgoing and incoming changes', () {
      final rows = ideGraphRows(
        [
          _commit(
            'L',
            ['B'],
            refs: [
              const IdeGitRef('refs/heads/main', 'main', IdeGitRefKind.head),
            ],
          ),
          _commit(
            'R',
            ['B'],
            refs: [
              const IdeGitRef(
                'refs/remotes/origin/main',
                'origin/main',
                IdeGitRefKind.remote,
              ),
            ],
          ),
          _commit('B', []),
        ],
        headRef: 'refs/heads/main',
        headRevision: 'L',
        remoteRef: 'refs/remotes/origin/main',
        remoteRevision: 'R',
        mergeBase: 'B',
      );
      expect(
        [for (final row in rows) row.commit.id],
        [ideOutgoingChangesId, 'L', 'R', ideIncomingChangesId, 'B'],
      );
      expect(rows.first.commit.subject, 'Outgoing Changes');
      expect(rows.first.kind, IdeGraphRowKind.outgoingChanges);
      expect(rows[1].inputLanes, [const IdeGraphLane('L', blue)]);
      expect(rows[3].commit.subject, 'Incoming Changes');
      expect(rows[3].circleIndex, 1);
      expect(rows[3].circleColor, IdeGraphColors.remoteRef);
      expect(rows[2].outputLanes.last.id, ideIncomingChangesId);
    });
  });
}
