import 'package:monad/ide/git/git_model.dart';
import 'package:monad/ide/git/git_repository.dart';
import 'package:monad/ide/git/git_service.dart';

/// Git as widget tests need it: no processes, canned output, and the
/// commands it was asked to run.
class FakeGit {
  FakeGit(this.root);

  final String root;

  /// Whether [root] is in a repository (`rev-parse --show-toplevel`).
  bool isRepository = true;

  /// `git status -z --porcelain=v1 --branch` output.
  String status = '## main\x00';

  /// `git log` output ([ideGitLogFormat] records).
  String log = '';

  /// `git show` output: by commit for `--name-status -z`, by `ref:path`
  /// for a file's text (which, not there, fails as a missing path does).
  final Map<String, String> show = {};

  /// `git diff` output (of the index, or with `--cached` of HEAD).
  String diff = '';

  /// `git diff --no-index -- /dev/null <path>` output, by relative path.
  final Map<String, String> newFileDiffs = {};

  /// `git remote` output.
  String remotes = 'origin\n';

  /// Resolved refs (`rev-parse --verify -q <ref>`).
  final Map<String, String> refs = {};

  /// Every command run, without `git`.
  final List<List<String>> calls = [];

  /// Runs before a command answers: may change [status] as the command
  /// would have.
  void Function(List<String> arguments)? onCommand;

  /// Answers by command, over the canned ones: e.g. a push that fails.
  final Map<String, IdeGitOutput> answers = {};

  /// What a command waits for before it answers, e.g. a push under way.
  Future<void>? Function(List<String> arguments)? hold;

  List<List<String>> callsTo(String command) => [
    for (final call in calls)
      if (call.first == command) call,
  ];

  Future<IdeGitOutput> run(
    List<String> arguments, {
    required String workingDirectory,
  }) async {
    calls.add(arguments);
    await hold?.call(arguments);
    onCommand?.call(arguments);
    if (answers[arguments.first] case final answer?) return answer;
    switch (arguments) {
      case ['rev-parse', '--show-toplevel']:
        return isRepository
            ? IdeGitOutput(0, '$root\n')
            : const IdeGitOutput(128, '', 'fatal: not a git repository');
      case ['rev-parse', '--verify', '-q', final ref]:
        final resolved = refs[ref];
        return resolved == null
            ? const IdeGitOutput(1, '')
            : IdeGitOutput(0, '$resolved\n');
      case ['status', ...]:
        return IdeGitOutput(0, status);
      case ['log', ...]:
        return IdeGitOutput(0, log);
      case ['diff', ..., '--no-index', '--', '/dev/null', final path]:
        final added = newFileDiffs[path];
        return IdeGitOutput(added == null ? 0 : 1, added ?? '');
      case ['diff', ...]:
        return IdeGitOutput(0, diff);
      case ['show', ..., final object] when object.contains(':'):
        final text = show[object];
        if (text == null) {
          return IdeGitOutput(128, '', "fatal: path '$object' does not exist");
        }
        return IdeGitOutput(0, text);
      case ['show', ..., final commit]:
        return IdeGitOutput(0, show[commit] ?? '');
      case ['remote']:
        return IdeGitOutput(0, remotes);
      case ['init']:
        isRepository = true;
        return const IdeGitOutput(0, '');
    }
    return const IdeGitOutput(0, '');
  }

  IdeGitRepository repository() => IdeGitRepository(
    IdeGitService(root, runner: run, watcher: (_) => const Stream.empty()),
    refreshDelay: Duration.zero,
  );
}

/// A [ideGitLogFormat] record.
String gitLogRecord(
  String id,
  List<String> parents,
  String message, {
  String author = 'Ada',
  String refs = '',
  int time = 1767225600,
}) =>
    '$id\x1f${parents.join(' ')}\x1f$author\x1fada@example.com\x1f$time\x1f'
    '$refs\x1f$message\n\x1e';
