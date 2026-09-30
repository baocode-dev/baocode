import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/git/git_change_editor.dart';
import 'package:monad/ide/git/git_model.dart';

/// Which texts a change's editor compares, and its title, as the Git
/// extension's `ResourceCommandResolver` has them.
void main() {
  const path = '/repo/lib/a.dart';

  IdeGitChangeEditor of(
    IdeGitStatus status, {
    IdeGitGroup group = IdeGitGroup.workingTree,
    String? originalPath,
    List<IdeGitResource> staged = const [],
  }) => IdeGitChangeEditor.of(
    IdeGitResource(
      path: path,
      status: status,
      group: group,
      originalPath: originalPath,
    ),
    staged: staged,
  );

  test('a working tree change compares HEAD, or the index where it is '
      'staged too, with the file', () {
    final change = of(IdeGitStatus.modified);
    expect(change.label, 'Working Tree');
    expect(change.left, const IdeGitSide(path, 'HEAD'));
    expect(change.right, const IdeGitSide(path));
    expect(change.right!.isFile, isTrue);

    final staged = of(
      IdeGitStatus.modified,
      staged: const [
        IdeGitResource(
          path: path,
          status: IdeGitStatus.indexModified,
          group: IdeGitGroup.staged,
        ),
      ],
    );
    expect(staged.left, const IdeGitSide(path, ''));
  });

  test('a staged change compares HEAD with the index; a rename, the old '
      'path\'s', () {
    final modified = of(IdeGitStatus.indexModified, group: IdeGitGroup.staged);
    expect(modified.label, 'Index');
    expect(modified.left, const IdeGitSide(path, 'HEAD'));
    expect(modified.right, const IdeGitSide(path, ''));

    final renamed = of(
      IdeGitStatus.indexRenamed,
      group: IdeGitGroup.staged,
      originalPath: '/repo/lib/old.dart',
    );
    expect(renamed.left, const IdeGitSide('/repo/lib/old.dart', 'HEAD'));
    expect(renamed.right, const IdeGitSide(path, ''));
  });

  test('an added or deleted file has one side', () {
    final added = of(IdeGitStatus.indexAdded, group: IdeGitGroup.staged);
    expect(added.label, 'Index');
    expect(added.left, isNull);
    expect(added.right, const IdeGitSide(path, ''));

    final deleted = of(IdeGitStatus.deleted);
    expect(deleted.label, 'Deleted');
    expect(deleted.left, isNull);
    expect(deleted.right, const IdeGitSide(path, 'HEAD'));

    final untracked = of(IdeGitStatus.untracked);
    expect(untracked.label, 'Untracked');
    expect(untracked.left, isNull);
    expect(untracked.right, const IdeGitSide(path));
  });

  test('a merge conflict compares its stages', () {
    final byUs = of(IdeGitStatus.deletedByUs, group: IdeGitGroup.merge);
    expect(byUs.label, 'Theirs');
    expect(byUs.left, const IdeGitSide(path, ':1'));
    expect(byUs.right, const IdeGitSide(path, ':3'));

    final byThem = of(IdeGitStatus.deletedByThem, group: IdeGitGroup.merge);
    expect(byThem.label, 'Ours');
    expect(byThem.right, const IdeGitSide(path, ':2'));

    final both = of(IdeGitStatus.bothModified, group: IdeGitGroup.merge);
    expect(both.label, 'Working Tree');
    expect(both.left, isNull);
    expect(both.right, const IdeGitSide(path));

    final bothDeleted = of(IdeGitStatus.bothDeleted, group: IdeGitGroup.merge);
    expect(bothDeleted.label, isEmpty);
    expect(bothDeleted.left, isNull);
    expect(bothDeleted.right, isNull);
  });
}
