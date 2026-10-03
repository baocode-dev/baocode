import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'git_service.dart';

/// Runs the local `git` without a shell, prompts or an editor, and without
/// optional index refreshes or a configured fsmonitor hook.
Future<IdeGitOutput> runGit(
  List<String> arguments, {
  required String workingDirectory,
}) async {
  try {
    final result = await Process.run(
      'git',
      ['--no-optional-locks', '-c', 'core.fsmonitor=false', ...arguments],
      workingDirectory: workingDirectory,
      environment: const {
        'GIT_TERMINAL_PROMPT': '0',
        'GIT_EDITOR': 'true',
        'GIT_OPTIONAL_LOCKS': '0',
      },
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    ).timeout(const Duration(seconds: 60));
    return IdeGitOutput(
      result.exitCode,
      result.stdout as String,
      result.stderr as String,
    );
  } on ProcessException catch (error) {
    throw IdeGitException(
      'Git is not installed or could not be started: ${error.message}',
    );
  } on TimeoutException {
    throw const IdeGitException('Git did not respond within 60 seconds.');
  } on FormatException {
    throw const IdeGitException('Git returned text that is not UTF-8.');
  }
}

/// File changes under [repositoryRoot] that can change the status: the
/// working tree, and the index, HEAD and refs of `.git` (not its objects
/// or logs). An error (changes lost) is passed on.
Stream<void> watchRepository(String repositoryRoot) {
  final gitDir = p.join(repositoryRoot, '.git');
  bool relevant(String path) {
    if (!p.isWithin(gitDir, path)) return true;
    final inside = p.split(p.relative(path, from: gitDir));
    return switch (inside.first) {
      'index' || 'HEAD' || 'refs' || 'packed-refs' || 'MERGE_HEAD' => true,
      _ => false,
    };
  }

  try {
    return Directory(repositoryRoot)
        .watch(recursive: true)
        .where(
          (event) =>
              relevant(event.path) ||
              // `index.lock` renamed to `index`, as Git writes it.
              (event is FileSystemMoveEvent &&
                  event.destination != null &&
                  relevant(event.destination!)),
        )
        .map((_) {});
  } on FileSystemException {
    return const Stream.empty();
  } on UnsupportedError {
    return const Stream.empty();
  }
}
