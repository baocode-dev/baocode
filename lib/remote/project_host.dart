import 'package:path/path.dart' as p;

import '../ide/file_service.dart';
import '../ide/git/git_repository.dart';
import '../ide/git/git_service.dart';
import '../ide/git/repository_scan.dart';
import '../ide/lsp/catalog/standard_lsp.dart';
import '../ide/lsp/language_features.dart';
import '../ide/terminal/terminal_instance.dart';
import 'remote_location.dart';
import 'ssh_host.dart';

/// The machine a project is on, and the IDE's services there: [LocalHost]
/// for this one, an [SshHost] for one reached over SSH. Claude Code, its
/// sessions and the review's checkpoints follow the project's location as
/// well (see remote_claude.dart, review_store.dart).
abstract interface class ProjectHost {
  /// The host of [location]: the remote one it names, else this machine.
  static ProjectHost of(String location) =>
      switch (RemoteLocation.hostOf(location)) {
        final host? => SshHosts.instance[host],
        null => const LocalHost(),
      };

  /// Its name as the user gave it; null for this machine.
  String? get name;

  /// How paths are spelled there.
  p.Context get paths;

  /// [location]'s path there.
  String pathOf(String location);

  /// The files of the project at [root] (a path there).
  IdeFileService files(String root);

  /// The Git repository of the project at [root].
  IdeGitRepository git(String root);

  /// The repositories [scan] finds in [root]'s subfolders, by path there.
  Future<List<String>> repositoriesIn(String root, IdeRepositoryScan scan);

  /// The language servers of the project at [root].
  LanguageFeatures languages(String root);

  /// What the terminals of its projects run on; [local] is this machine's.
  TerminalBackend terminals(TerminalBackend local);
}

/// This machine.
class LocalHost implements ProjectHost {
  const LocalHost();

  @override
  String? get name => null;

  @override
  p.Context get paths => p.context;

  @override
  String pathOf(String location) => location;

  @override
  IdeFileService files(String root) => IdeFileService(root);

  @override
  IdeGitRepository git(String root) => IdeGitRepository(IdeGitService(root));

  @override
  Future<List<String>> repositoriesIn(String root, IdeRepositoryScan scan) =>
      scanRepositories(
        root,
        scan,
        list: files(root).list,
        isRepositoryTop: (folder) => IdeGitService(folder).isRepositoryTop(),
      );

  @override
  LanguageFeatures languages(String root) => standardLspManager(root);

  @override
  TerminalBackend terminals(TerminalBackend local) => local;
}
