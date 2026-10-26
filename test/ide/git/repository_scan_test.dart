import 'dart:io';

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

    test('the submodules of the folder\'s repository and of those, deep '
        'below or not, checked out and within it (#68)', () async {
      final submodules = {
        '/w': ['/w/assets/framework', '/w/vendor/empty', '/elsewhere/x'],
        '/w/assets/framework': ['/w/assets/framework/lib/inner'],
        '/w/site': ['/w/site/theme'],
      };
      const checkedOut = {
        '/w/site',
        '/w/assets/framework',
        '/w/assets/framework/lib/inner',
        '/w/site/theme',
      };
      Future<List<String>> submodulesOf(String folder) async =>
          submodules[folder] ?? const [];
      Future<bool> isTop(String folder) async => checkedOut.contains(folder);
      expect(
        await scanRepositories(
          '/w',
          const IdeRepositoryScan(),
          list: list,
          isRepositoryTop: isTop,
          submodulesOf: submodulesOf,
          paths: p.posix,
        ),
        [
          '/w/site',
          '/w/assets/framework',
          '/w/site/theme',
          '/w/assets/framework/lib/inner',
        ],
      );
      // Off, or with subfolders not scanned.
      expect(
        await scanRepositories(
          '/w',
          const IdeRepositoryScan(detectSubmodules: false),
          list: list,
          isRepositoryTop: isTop,
          submodulesOf: submodulesOf,
          paths: p.posix,
        ),
        ['/w/site'],
      );
      expect(
        await scanRepositories(
          '/w',
          const IdeRepositoryScan(subFolders: false, submodulesLimit: 1),
          list: list,
          isRepositoryTop: isTop,
          submodulesOf: submodulesOf,
          paths: p.posix,
        ),
        ['/w/assets/framework', '/w/assets/framework/lib/inner'],
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
    expect(defaults.detectSubmodules, isTrue);
    expect(defaults.submodulesLimit, 10);
    final submodules = IdeRepositoryScan.parse(const {
      'git.detectSubmodules': false,
      'git.detectSubmodulesLimit': 3,
    });
    expect(submodules.detectSubmodules, isFalse);
    expect(submodules.submodulesLimit, 3);

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
      runner:
          (
            arguments, {
            required workingDirectory,
            limit,
            stdin,
            environment,
          }) async {
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

  test('a repository\'s submodules are read from its .gitmodules, from a '
      'folder in it too', () async {
    final dir = await Directory.systemTemp.createTemp('baocode-submodules-');
    addTearDown(() => dir.delete(recursive: true));
    final root = dir.path;
    Future<void> git(List<String> arguments) async {
      final result = await Process.run(
        'git',
        arguments,
        workingDirectory: root,
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
    }

    await git(['init', '-q']);
    await Directory(p.join(root, 'src')).create();
    expect(await IdeGitService(root).submodulePaths(), isEmpty);
    await File(p.join(root, '.gitmodules')).writeAsString(
      '[submodule "framework"]\n'
      '\tpath = assets/framework\n'
      '\turl = ../framework.git\n'
      '[submodule "a b"]\n'
      '\tpath = vendor/a b\n'
      '\turl = ../ab.git\n',
    );
    final expected = [
      p.join(root, 'assets', 'framework'),
      p.join(root, 'vendor', 'a b'),
    ];
    expect(await IdeGitService(root).submodulePaths(), expected);
    expect(await IdeGitService(p.join(root, 'src')).submodulePaths(), expected);
  });
}
