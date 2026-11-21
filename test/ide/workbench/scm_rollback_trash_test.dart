// The Source Control side bar's Rollback, and whose Trash it moves untracked
// files to: a remote workspace's are deleted on its host, not here (see
// IdeGitRepository.rollback).

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/file_service.dart';
import 'package:baocode/ide/git/ide_git_commit_panel.dart';
import 'package:baocode/ide/ide_workbench.dart';
import 'package:baocode/ide/search/text_search.dart';
import 'package:baocode/ide/services/layout.dart';
import 'package:baocode/ide/workbench/views.dart';

import '../git/fake_git.dart';
import 'fake_files.dart';

void main() {
  late FakeGit git;

  setUp(() {
    git = FakeGit(testRoot);
    git.status = '## main...origin/main\x00?? notes.md\x00';
  });

  /// The commit panel of the Source Control view, its workbench on [files].
  Future<IdeGitCommitPanel> commitPanel(
    WidgetTester tester, {
    Map<String, String> files = const {'notes.md': 'n'},
    IdeFileService? fileService,
  }) async {
    await pumpWorkbench(
      tester,
      files,
      git: git.repository(),
      fileService: fileService,
    );
    tester
        .state<IdeWorkbenchState>(find.byType(IdeWorkbench))
        .services
        .get<LayoutService>()
        .showView(IdeSideView.sourceControl);
    await tester.pumpAndSettle();
    return tester.widget<IdeGitCommitPanel>(find.byType(IdeGitCommitPanel));
  }

  // The Trash is macOS's: the runner's own has none (see
  // WindowControls.canMoveToTrash), so the test picks it, and the debug
  // variable is put back before the test ends (the framework checks it).
  Future<void> onMacOS(Future<void> Function() body) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  testWidgets('a remote workspace rolls back without this machine\'s Trash', (
    tester,
  ) async {
    await onMacOS(() async {
      expect(
        (await commitPanel(
          tester,
          fileService: _HostFiles(const {'notes.md': 'n'}),
        )).trash,
        isNull,
      );
    });
  });

  testWidgets('a local workspace still moves untracked files to the Trash', (
    tester,
  ) async {
    await onMacOS(() async {
      expect((await commitPanel(tester)).trash, isNotNull);
    });
  });
}

/// A remote project's files, on its host.
class _HostFiles extends TreeFiles implements IdeHostFiles {
  _HostFiles(super.contents);

  @override
  Future<Uint8List> readBytes(String path) async =>
      utf8.encode(contents[path] ?? '');

  @override
  Stream<void> watchDirectory(String directory) => const Stream.empty();

  @override
  Future<IdeFileListing> listProject(String root, {int limit = 50000}) =>
      throw UnimplementedError();

  @override
  Stream<Object> searchText(String root, IdeTextQuery query) =>
      throw UnimplementedError();
}
