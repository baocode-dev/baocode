/// What running Git gave.
class IdeGitOutput {
  const IdeGitOutput(this.exitCode, this.stdout, [this.stderr = '']);

  final int exitCode;
  final String stdout;
  final String stderr;
}

/// Git could not run, or failed.
class IdeGitException implements Exception {
  const IdeGitException(this.message);

  final String message;

  @override
  String toString() => message;
}
