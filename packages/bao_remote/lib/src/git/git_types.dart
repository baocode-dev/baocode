/// What running Git gave.
class IdeGitOutput {
  const IdeGitOutput(this.exitCode, this.stdout, [this.stderr = ''])
    : truncated = false;

  /// The output of a command stopped at its limit of records: [stdout] its
  /// first ones, and more were coming.
  const IdeGitOutput.truncated(this.stdout, [this.stderr = ''])
    : exitCode = 0,
      truncated = true;

  final int exitCode;
  final String stdout;
  final String stderr;

  /// Whether the command was stopped at its limit, with more to come.
  final bool truncated;
}

/// Git could not run, or failed.
class IdeGitException implements Exception {
  const IdeGitException(this.message);

  final String message;

  @override
  String toString() => message;
}
