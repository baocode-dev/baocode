import 'git_service.dart';

Future<IdeGitOutput> runGit(
  List<String> arguments, {
  required String workingDirectory,
  int? limit,
}) async => throw const IdeGitException(
  'Git is unavailable in the browser. Open this project in the desktop app.',
);

Stream<void> watchRepository(String repositoryRoot) => const Stream.empty();
