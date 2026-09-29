import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'project_tools.dart';

class LocalIdeProjectTools implements IdeProjectTools {
  LocalIdeProjectTools(String root) : root = p.normalize(p.absolute(root));

  final String root;
  static const _excludedDirectories = <String>{
    '.git',
    'node_modules',
    'build',
    '.dart_tool',
  };

  @override
  Future<IdeSearchResult> search(
    String query, {
    bool caseSensitive = false,
    IdeSearchCancellation? cancellation,
    IdeSearchLimits limits = const IdeSearchLimits(),
  }) async {
    limits.validate();
    final matches = <IdeSearchMatch>[];
    var filesSearched = 0;
    var skippedFiles = 0;
    var bytesRead = 0;
    var visitedEntries = 0;
    var truncated = false;
    var stopped = false;
    final clock = Stopwatch()..start();
    final needle = caseSensitive ? query : query.toLowerCase();

    bool shouldStop() {
      if (cancellation?.isCancelled ?? false) return true;
      if (clock.elapsed >= limits.timeout) {
        truncated = true;
        stopped = true;
      }
      return stopped;
    }

    Duration getRemainingTime() => limits.timeout - clock.elapsed;

    void limitReached() {
      truncated = true;
      stopped = true;
    }

    Future<void> searchFile(File file) async {
      if (filesSearched >= limits.maxFiles) {
        limitReached();
        return;
      }
      filesSearched++;
      try {
        // Recheck the type before opening; never intentionally open a link,
        // socket, device or named pipe, even if the directory entry changed.
        final type = await FileSystemEntity.type(
          file.path,
          followLinks: false,
        ).timeout(getRemainingTime());
        if (shouldStop()) return;
        if (type != FileSystemEntityType.file) {
          skippedFiles++;
          return;
        }
        final size = await file.length().timeout(getRemainingTime());
        if (shouldStop()) return;
        if (size > limits.maxFileBytes) {
          skippedFiles++;
          return;
        }
        if (bytesRead + size > limits.maxTotalBytes) {
          limitReached();
          return;
        }
        final buffer = BytesBuilder(copy: false);
        // Bound the actual read too: files may grow after the length check.
        await for (final chunk
            in file
                .openRead(0, limits.maxFileBytes + 1)
                .timeout(getRemainingTime())) {
          if (shouldStop()) return;
          bytesRead += chunk.length;
          if (bytesRead > limits.maxTotalBytes) {
            limitReached();
            return;
          }
          if (buffer.length + chunk.length > limits.maxFileBytes) {
            skippedFiles++;
            return;
          }
          buffer.add(chunk);
        }
        if (shouldStop()) return;
        final bytes = buffer.takeBytes();
        if (bytes.contains(0)) {
          skippedFiles++;
          return;
        }
        final text = utf8.decode(
          bytes,
        ); // Malformed UTF-8 is not searchable text.
        var lineNumber = 0;
        for (final line in LineSplitter.split(text)) {
          lineNumber++;
          // Long files must allow pending keystrokes/cancellation to run.
          if (lineNumber % 256 == 0) {
            await Future<void>.delayed(Duration.zero);
          }
          if (shouldStop()) return;
          final haystack = caseSensitive ? line : line.toLowerCase();
          final column = haystack.indexOf(needle);
          if (column < 0) continue;
          matches.add(
            IdeSearchMatch(
              path: file.path,
              relativePath: p.relative(file.path, from: root),
              line: lineNumber,
              column: column + 1,
              preview: _preview(line, column),
            ),
          );
          // A result represents a matching line, not each occurrence on it.
          if (matches.length >= limits.maxMatches) {
            limitReached();
            return;
          }
        }
      } on FileSystemException {
        skippedFiles++;
      } on FormatException {
        skippedFiles++;
      } on TimeoutException {
        limitReached();
      }
    }

    Future<void> visit(Directory directory, int depth) async {
      if (shouldStop()) return;
      if (depth > limits.maxDepth) {
        truncated = true;
        return;
      }
      try {
        final type = await FileSystemEntity.type(
          directory.path,
          followLinks: false,
        ).timeout(getRemainingTime());
        if (shouldStop()) return;
        if (type != FileSystemEntityType.directory) return;
        // Stream rather than materialize a potentially enormous directory.
        await for (final entity
            in directory.list(followLinks: false).timeout(getRemainingTime())) {
          if (shouldStop()) return;
          if (visitedEntries >= limits.maxEntries) {
            limitReached();
            return;
          }
          visitedEntries++;
          if (visitedEntries % 128 == 0) {
            await Future<void>.delayed(Duration.zero);
            if (shouldStop()) return;
          }
          if (_excludedDirectories.contains(p.basename(entity.path))) continue;
          if (entity is Directory) {
            await visit(entity, depth + 1);
          } else if (entity is File) {
            await searchFile(entity);
          }
        }
      } on FileSystemException catch (error) {
        if (depth == 0) {
          throw IdeProjectToolsException(
            'Cannot read project directory: ${error.message}',
          );
        }
        skippedFiles++;
      } on TimeoutException {
        limitReached();
      }
    }

    if (query.isNotEmpty && !shouldStop()) {
      try {
        final type = await FileSystemEntity.type(
          root,
          followLinks: false,
        ).timeout(getRemainingTime());
        if (type != FileSystemEntityType.directory) {
          throw const IdeProjectToolsException(
            'The project directory is missing or is a symbolic link.',
          );
        }
        await visit(Directory(root), 0);
      } on FileSystemException catch (error) {
        throw IdeProjectToolsException(
          'Cannot read project directory: ${error.message}',
        );
      } on TimeoutException {
        limitReached();
      }
    }
    return IdeSearchResult(
      matches: matches,
      filesSearched: filesSearched,
      skippedFiles: skippedFiles,
      truncated: truncated,
      cancelled: cancellation?.isCancelled ?? false,
    );
  }

  static String _preview(String line, int column) {
    const limit = 240;
    final start = (column - 60).clamp(0, line.length);
    final end = (start + limit).clamp(0, line.length);
    return '${start > 0 ? '…' : ''}'
        '${line.substring(start, end).replaceAll('\t', '  ')}'
        '${end < line.length ? '…' : ''}';
  }

  Future<ProcessResult> _git(List<String> arguments) async {
    try {
      // No shell interpolation or optional index refresh writes. Disable a
      // configured fsmonitor hook, which need not itself be read-only.
      return await Process.run(
        'git',
        ['--no-optional-locks', '-c', 'core.fsmonitor=false', ...arguments],
        workingDirectory: root,
        environment: const {'GIT_TERMINAL_PROMPT': '0'},
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(const Duration(seconds: 15));
    } on ProcessException catch (error) {
      throw IdeProjectToolsException(
        'Git is not installed or could not be started: ${error.message}',
      );
    } on TimeoutException {
      throw const IdeProjectToolsException(
        'Git did not respond within 15 seconds.',
      );
    } on FormatException {
      throw const IdeProjectToolsException(
        'Git returned text that is not UTF-8.',
      );
    }
  }

  static String _stdoutLine(ProcessResult result) {
    final text = result.stdout as String;
    return text.endsWith('\n') ? text.substring(0, text.length - 1) : text;
  }

  static void _requireSuccess(ProcessResult result, String message) {
    if (result.exitCode == 0) return;
    final error = (result.stderr as String).trim();
    // Keep error labels bounded even if an external command is very noisy.
    final detail = error.length > 500 ? '${error.substring(0, 500)}…' : error;
    throw IdeProjectToolsException(
      '$message${detail.isEmpty ? '' : '\n$detail'}',
    );
  }

  @override
  Future<IdeGitSnapshot> gitStatus({int maxEntries = 1000}) async {
    if (maxEntries < 1) throw ArgumentError.value(maxEntries, 'maxEntries');
    if (!await Directory(root).exists()) {
      throw const IdeProjectToolsException(
        'The project directory does not exist.',
      );
    }
    final repository = await _git(['rev-parse', '--show-toplevel']);
    _requireSuccess(repository, 'Cannot read Git repository for this project.');
    final repositoryRoot = _stdoutLine(repository);
    final status = await _git([
      'status',
      '--porcelain=v1',
      '-z',
      '--untracked-files=all',
      '--',
      '.',
    ]);
    _requireSuccess(status, 'Cannot read Git status.');
    final branchResult = await _git([
      'symbolic-ref',
      '--quiet',
      '--short',
      'HEAD',
    ]);
    String branch;
    if (branchResult.exitCode == 1) {
      final head = await _git(['rev-parse', '--short', 'HEAD']);
      _requireSuccess(head, 'Cannot read detached Git HEAD.');
      branch = 'HEAD (${_stdoutLine(head)})';
    } else {
      _requireSuccess(branchResult, 'Cannot read Git branch.');
      branch = _stdoutLine(branchResult);
    }
    List<IdeGitChange> changes;
    try {
      changes = parseGitPorcelain(
        status.stdout as String,
        maxEntries: maxEntries + 1,
      );
    } on FormatException {
      throw const IdeProjectToolsException(
        'Git returned an invalid status response.',
      );
    }
    return IdeGitSnapshot(
      repositoryRoot: repositoryRoot,
      branch: branch,
      changes: changes.take(maxEntries).toList(),
      truncated: changes.length > maxEntries,
    );
  }
}

Future<String?> readGitBranch(String root) async {
  try {
    var directory = p.normalize(p.absolute(root));
    while (true) {
      final dotGit = p.join(directory, '.git');
      final type = await FileSystemEntity.type(dotGit);
      if (type == FileSystemEntityType.directory) {
        return parseGitHead(await File(p.join(dotGit, 'HEAD')).readAsString());
      }
      if (type == FileSystemEntityType.file) {
        // A worktree or submodule: `gitdir: <path>`.
        final pointer = (await File(dotGit).readAsString()).trim();
        if (!pointer.startsWith('gitdir:')) return null;
        final gitDir = p.normalize(
          p.join(directory, pointer.substring('gitdir:'.length).trim()),
        );
        return parseGitHead(await File(p.join(gitDir, 'HEAD')).readAsString());
      }
      final parent = p.dirname(directory);
      if (parent == directory) return null;
      directory = parent;
    }
  } on FileSystemException {
    return null;
  }
}
