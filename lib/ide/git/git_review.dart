// BaoCode's own commit check, in the place of JetBrains IDEs' before-commit
// inspections: the model reads what the commit takes and lists what looks
// wrong in it (a bug, a secret, debugging left in), each at its file and
// line, before it goes.

import 'commit_message.dart';

enum IdeGitReviewSeverity { error, warning, info }

/// A problem the review found: in [path] (from the repository's top), at
/// [line] of the file as it will be committed where it says.
class IdeGitReviewProblem {
  const IdeGitReviewProblem(
    this.severity,
    this.path,
    this.message, {
    this.line,
  });

  final IdeGitReviewSeverity severity;
  final String path;
  final int? line;
  final String message;

  /// Whether the commit should wait for it: an error's or a warning's.
  bool get blocks => severity != IdeGitReviewSeverity.info;
}

/// What the model is asked: [diff] reviewed, [message] the commit's.
IdeCommitMessagePrompt ideGitReviewPrompt(String diff, {String? message}) {
  const system =
      'You review a change just before it is committed. Report only real '
      'problems a careful reviewer would stop the commit for: bugs, wrong '
      'logic, crashes, security holes, secrets or credentials, debugging '
      'code or temporary hacks left in, unfinished work (TODO added for '
      'something this change should have done), and a commit message that '
      'misdescribes the change. No style, naming or formatting remarks, and '
      'nothing about code the diff does not touch. Answer with one line per '
      'problem: its severity (error, warning or info), a space, the file\'s '
      'path as the diff writes it, a colon and the line number in the new '
      'file, a space and what is wrong in one sentence, in the language of '
      'the commit message if there is one, else English. For example:\n'
      'error src/app.dart:42 The list is read after it is disposed.\n'
      'With nothing to report, answer exactly NO PROBLEMS.';
  final user = StringBuffer();
  if (message != null && message.trim().isNotEmpty) {
    user
      ..writeln('Commit message:')
      ..writeln(message.trim())
      ..writeln();
  }
  user
    ..writeln('Diff:')
    ..write(diff);
  return IdeCommitMessagePrompt(system, user.toString());
}

/// The problems in the model's [reply]; none for NO PROBLEMS or what does
/// not read as one.
List<IdeGitReviewProblem> ideGitReviewProblems(String reply) {
  final line = RegExp(
    r'^\s*(?:[-*]\s*)?(error|warning|info)\b[:\s]+(\S+?)(?::(\d+))?[:\s]+(.+)$',
    caseSensitive: false,
  );
  return [
    for (final text in reply.split('\n'))
      if (line.firstMatch(text.trim()) case final match?)
        IdeGitReviewProblem(
          IdeGitReviewSeverity.values.byName(match[1]!.toLowerCase()),
          match[2]!.replaceFirst(RegExp(r'^[ab]/'), ''),
          match[4]!.trim(),
          line: int.tryParse(match[3] ?? ''),
        ),
  ];
}
