import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/file_service.dart';
import 'package:baocode/ide/git/git_service.dart';
import 'package:baocode/ide/git/repository_scan.dart';
import 'package:path/path.dart' as p;

/// Lists the folders of [tree] (every path's folders, by `/`).
Future<List<IdeFile>> Function(String) _lister(List<String> tree) {
  final folders = <String>{
    for (final path in tree)
      for (var i = 1; i <= path.split('/').length; i++)
        p.posix.joinAll(['/w', ...path.split('/').take(i)]),
  };
  return (directory) async => [
    for (final folder in folders)
      if (p.posix.dirname(folder) == directory)
        IdeFile(folder, p.posix.basename(folder), isDirectory: true),
  ];
}

void main() {
  group('scanRepositories', () {
    final list = _lister([
      'site/src',
      'api/cmd',
      'node_modules/lib',
      'tools/gen/deep',
      '.git/objects',
    ]);
    const repositories = {'/w/site', '/w/node_modules/lib', '/w/tools/gen'};
    final asked = <String>[];
    Future<bool> isTop(String folder) async {
      asked.add(folder);
      return repositories.contains(folder);
    }

    setUp(asked.clear);

    test('finds the children that are repositories, not looking in '
        '.git or the ignored folders', () async {
      final found = await scanRepositories(
        '/w',
        const IdeRepositoryScan(),
        list: list,
        isRepositoryTop: isTop,
        paths: p.posix,
      );
      expect(found, ['/w/site']);
      expect(asked, unorderedEquals(['/w/site', '/w/api', '/w/tools']));
    });

    test('goes as deep as the depth says, -1 without a limit', () async {
      expect(
        await scanRepositories(
          '/w',
          const IdeRepositoryScan(maxDepth: 2),
          list: list,
          isRepositoryTop: isTop,
          paths: p.posix,
        ),
        ['/w/site', '/w/tools/gen'],
      );
      expect(
        await scanRepositories(
          '/w',
          const IdeRepositoryScan(maxDepth: -1, ignoredFolders: []),
          list: list,
          isRepositoryTop: isTop,
          paths: p.posix,
        ),
        ['/w/site', '/w/node_modules/lib', '/w/tools/gen'],
      );
    });

    test('scans nothing when detection is off', () async {
      expect(
        await scanRepositories(
          '/w',
          const IdeRepositoryScan(subFolders: false),
          list: list,
          isRepositoryTop: isTop,
          paths: p.posix,
        ),
        isEmpty,
      );
      expect(asked, isEmpty);
    });
  });

  test('settings.json\'s choices, the defaults for others', () {
    final defaults = IdeRepositoryScan.parse(const {});
    expect(defaults.subFolders, isTrue);
    expect(defaults.maxDepth, 1);
    expect(defaults.ignoredFolders, ['node_modules']);

    final set = IdeRepositoryScan.parse(const {
      'git.autoRepositoryDetection': 'openEditors',
      'git.repositoryScanMaxDepth': 3,
      'git.repositoryScanIgnoredFolders': ['vendor', 1],
    });
    expect(set.subFolders, isFalse);
    expect(set.maxDepth, 3);
    expect(set.ignoredFolders, ['vendor']);

    expect(
      IdeRepositoryScan.parse(const {
        'git.autoRepositoryDetection': 'subFolders',
      }).subFolders,
      isTrue,
    );
    expect(
      IdeRepositoryScan.parse(const {'git.autoRepositoryDetection': false})
          .subFolders,
      isFalse,
    );
  });

  test('a folder is a repository at its working tree\'s top level', () async {
    Future<bool> isTop(IdeGitOutput output) => IdeGitService(
      '/w/site',
      runner: (arguments, {required workingDirectory, limit}) async {
        expect(arguments, [
          'rev-parse',
          '--is-inside-work-tree',
          '--show-prefix',
        ]);
        expect(workingDirectory, p.normalize('/w/site'));
        return output;
      },
    ).isRepositoryTop();

    expect(await isTop(const IdeGitOutput(0, 'true\n\n')), isTrue);
    // A folder in one.
    expect(await isTop(const IdeGitOutput(0, 'true\nsite/\n')), isFalse);
    // A bare repository.
    expect(await isTop(const IdeGitOutput(0, 'false\n\n')), isFalse);
    expect(
      await isTop(const IdeGitOutput(128, '', 'fatal: not a git repository')),
      isFalse,
    );
  });
}
