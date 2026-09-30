// Generate Commit Message, as the sparkle in VS Code's Source Control input
// does it (with Copilot): the diff of what the commit would take, cut to
// fit, and the repository's recent messages for its conventions, to a small
// model: Claude Haiku, through Claude Code.

import 'package:path/path.dart' as p;

import 'commit_message_stub.dart'
    if (dart.library.io) 'commit_message_io.dart'
    as platform;

/// The most diff the model is given, in characters.
const ideCommitDiffBudget = 40000;

/// What the model is told ([system]) and asked ([user]).
class IdeCommitMessagePrompt {
  const IdeCommitMessagePrompt(this.system, this.user);

  final String system;
  final String user;
}

/// Asks a model for a commit message; completing [cancel] stops it, and it
/// then throws [IdeCommitMessageCancelled].
typedef IdeCommitMessageModel = Future<String> Function(
  IdeCommitMessagePrompt prompt, {
  Future<void>? cancel,
});

class IdeCommitMessageCancelled implements Exception {
  const IdeCommitMessageCancelled();
}

class IdeCommitMessageException implements Exception {
  const IdeCommitMessageException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Claude Haiku through the `claude` CLI: one turn, no tools, no session
/// kept.
Future<String> ideClaudeCommitMessage(
  IdeCommitMessagePrompt prompt, {
  Future<void>? cancel,
}) => platform.claudeCommitMessage(prompt, cancel: cancel);

/// One line, so that it passes through a shell unchanged.
const _system =
    'You write Git commit messages. You are given the changes about to be '
    'committed; reply with the commit message only, with no preamble, '
    'quotes or code fences. The first line summarizes the change in the '
    'imperative mood ("Add", "Fix", "Refactor"), in at most 72 characters, '
    'without a trailing period. When the change needs explaining, add a '
    'blank line and a short body saying what changed and why, wrapped at '
    '72 characters; bullet points suit several separate changes. Leave the '
    'body out for small, self-explanatory changes. Describe what the diff '
    'does; do not invent motives, issue numbers or co-authors. Follow the '
    "conventions of the repository's recent commit messages (prefixes such "
    'as "feat:" or "fix(scope):", capitalization, language) when there are '
    'any; otherwise write in English. Parts of the diff may be left out or '
    'cut short to fit: judge the change as a whole from what is shown and '
    'from the list of changed files.';

/// The prompt for [diff] (`git diff` output), cut to [budget] characters
/// of diff, with the [recentMessages]' subjects and the [branch].
IdeCommitMessagePrompt ideCommitMessagePrompt(
  String diff, {
  List<String> recentMessages = const [],
  String? branch,
  int budget = ideCommitDiffBudget,
}) {
  final files = ideSplitDiff(diff);
  final out = StringBuffer();
  if (branch != null) out.writeln('Branch: $branch\n');
  final subjects = [
    for (final message in recentMessages)
      if (message.split('\n').first.trim() case final subject
          when subject.isNotEmpty)
        subject,
  ];
  if (subjects.isNotEmpty) {
    out.writeln('Recent commit messages in this repository:');
    for (final subject in subjects) {
      out.writeln('- $subject');
    }
    out.writeln();
  }
  out.writeln('Changed files:');
  const listed = 300;
  for (final file in files.take(listed)) {
    out.writeln(file.summary);
  }
  if (files.length > listed) {
    out.writeln('… and ${files.length - listed} more files');
  }
  out
    ..writeln()
    ..writeln('Diff:')
    ..write(ideTrimDiff(files, budget));
  return IdeCommitMessagePrompt(_system, out.toString());
}

/// One file's part of a diff.
class IdeFileDiff {
  IdeFileDiff(this.text) {
    for (final line in text.split('\n')) {
      if (line.startsWith('@@')) _hunks = true;
      if (!_hunks) {
        if (line.startsWith('diff --git ')) {
          path = _pathOf(line) ?? path;
        } else if (line.startsWith('new file mode')) {
          status = 'A';
        } else if (line.startsWith('deleted file mode')) {
          status = 'D';
        } else if (line.startsWith('rename from ')) {
          status = 'R';
          originalPath = line.substring('rename from '.length);
        } else if (line.startsWith('rename to ')) {
          path = line.substring('rename to '.length);
        } else if (line.startsWith('Binary files ')) {
          binary = true;
        }
      } else if (line.startsWith('+')) {
        added++;
      } else if (line.startsWith('-')) {
        removed++;
      }
    }
  }

  final String text;
  String path = '';
  String? originalPath;

  /// `A`, `D`, `R` or `M`.
  String status = 'M';
  bool binary = false;
  int added = 0;
  int removed = 0;
  bool _hunks = false;

  /// `M lib/a.dart (+3 -1)`.
  String get summary {
    final name = originalPath == null ? path : '$originalPath → $path';
    if (binary) return '$status $name (binary)';
    final counts = [if (added > 0) '+$added', if (removed > 0) '-$removed'];
    return counts.isEmpty
        ? '$status $name'
        : '$status $name (${counts.join(' ')})';
  }

  /// A lock file or generated one: its lines tell the model nothing.
  bool get generated {
    final name = p.posix.basename(path);
    return _lockFiles.contains(name) ||
        name.endsWith('.lock') ||
        name.endsWith('.min.js') ||
        name.endsWith('.min.css') ||
        name.endsWith('.map') ||
        name.endsWith('.g.dart') ||
        name.endsWith('.freezed.dart') ||
        name.endsWith('.pb.go');
  }

  /// The lines before the first hunk.
  String get header {
    final hunk = text.indexOf('\n@@');
    return hunk < 0 ? text : text.substring(0, hunk + 1);
  }

  static String? _pathOf(String line) {
    // `diff --git a/x b/x`: the new side's path.
    final b = line.lastIndexOf(' b/');
    return b < 0 ? null : line.substring(b + 3);
  }
}

const _lockFiles = {
  'package-lock.json',
  'npm-shrinkwrap.json',
  'pnpm-lock.yaml',
  'go.sum',
};

/// [diff] as its files, each starting at `diff --git`.
List<IdeFileDiff> ideSplitDiff(String diff) {
  final files = <IdeFileDiff>[];
  var start = diff.indexOf('diff --git ');
  while (start >= 0) {
    final next = diff.indexOf('\ndiff --git ', start);
    final end = next < 0 ? diff.length : next + 1;
    files.add(IdeFileDiff(diff.substring(start, end)));
    start = next < 0 ? -1 : next + 1;
  }
  return files;
}

/// [files] within [budget] characters: a lock or generated file by its
/// header alone; the rest whole while they fit, smallest first, the larger
/// ones then sharing what is left equally, cut at a line's end and saying
/// how much is not shown. In the diff's order.
String ideTrimDiff(List<IdeFileDiff> files, int budget) {
  final texts = [
    for (final file in files)
      file.generated && !file.binary
          ? '${file.header}[${file.added + file.removed} changed lines of a '
                'lock or generated file not shown]\n'
          : file.text,
  ];
  final order = [for (var i = 0; i < texts.length; i++) i]
    ..sort((a, b) => texts[a].length.compareTo(texts[b].length));
  var remaining = budget;
  for (final (done, index) in order.indexed) {
    final share = remaining ~/ (order.length - done);
    final text = texts[index];
    if (text.length > share) texts[index] = _cut(text, share);
    remaining -= texts[index].length;
  }
  return texts.join();
}

/// [text] cut at a line's end to within [length] characters, saying how
/// many lines are left out (the note counts against [length] too).
String _cut(String text, int length) {
  const note = 32;
  final limit = length - note;
  final end = limit <= 0 ? -1 : text.lastIndexOf('\n', limit - 1);
  final kept = end < 0 ? '' : text.substring(0, end + 1);
  final left = '\n'.allMatches(text, kept.length).length;
  return '$kept[$left more lines not shown]\n';
}

/// A reply as a message: without code fences, quotes around it, or blank
/// lines at its ends.
String ideCleanCommitMessage(String reply) {
  var text = reply.trim();
  final fence = RegExp(r'^```[\w-]*\n([\s\S]*?)\n```$');
  if (fence.firstMatch(text) case final match?) text = match[1]!.trim();
  if (text.length > 1 &&
      (text.startsWith('"') && text.endsWith('"') ||
          text.startsWith("'") && text.endsWith("'"))) {
    text = text.substring(1, text.length - 1).trim();
  }
  return text;
}
