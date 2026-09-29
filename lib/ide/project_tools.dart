import 'project_tools_stub.dart'
    if (dart.library.io) 'project_tools_io.dart'
    as platform;

/// Read-only project operations, independent of the workspace and its providers.
abstract interface class IdeProjectTools {
  factory IdeProjectTools(String root) = platform.LocalIdeProjectTools;

  Future<IdeSearchResult> search(
    String query, {
    bool caseSensitive = false,
    IdeSearchCancellation? cancellation,
    IdeSearchLimits limits = const IdeSearchLimits(),
  });

  Future<IdeGitSnapshot> gitStatus({int maxEntries = 1000});
}

class IdeProjectToolsException implements Exception {
  const IdeProjectToolsException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Each request owns its cancellation token; the service retains no state.
class IdeSearchCancellation {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

class IdeSearchLimits {
  const IdeSearchLimits({
    this.maxMatches = 300,
    this.maxFiles = 5000,
    this.maxEntries = 20000,
    this.maxFileBytes = 1024 * 1024,
    this.maxTotalBytes = 32 * 1024 * 1024,
    this.maxDepth = 64,
    this.timeout = const Duration(seconds: 10),
  });

  final int maxMatches;
  final int maxFiles;
  final int maxEntries;
  final int maxFileBytes;
  final int maxTotalBytes;
  final int maxDepth;
  final Duration timeout;

  void validate() {
    if (maxMatches < 1 ||
        maxFiles < 1 ||
        maxEntries < 1 ||
        maxFileBytes < 1 ||
        maxTotalBytes < 1 ||
        maxDepth < 1 ||
        timeout <= Duration.zero) {
      throw ArgumentError('Search limits must all be positive.');
    }
  }
}

class IdeSearchMatch {
  const IdeSearchMatch({
    required this.path,
    required this.relativePath,
    required this.line,
    required this.column,
    required this.preview,
  });

  /// Absolute path; line and column are one-based.
  final String path;
  final String relativePath;
  final int line;
  final int column;

  /// A bounded excerpt of the matching line, not the entire file.
  final String preview;
}

class IdeSearchResult {
  IdeSearchResult({
    required List<IdeSearchMatch> matches,
    required this.filesSearched,
    required this.skippedFiles,
    required this.truncated,
    required this.cancelled,
  }) : matches = List.unmodifiable(matches);

  final List<IdeSearchMatch> matches;
  final int filesSearched;
  final int skippedFiles;
  final bool truncated;
  final bool cancelled;
}

class IdeGitChange {
  const IdeGitChange({
    required this.relativePath,
    required this.indexStatus,
    required this.workTreeStatus,
    this.originalRelativePath,
  });

  /// Git's repository-relative destination path, including for renames.
  final String relativePath;
  final String? originalRelativePath;
  final String indexStatus;
  final String workTreeStatus;

  bool get isDeleted => indexStatus == 'D' || workTreeStatus == 'D';
  bool get isUntracked => indexStatus == '?' && workTreeStatus == '?';

  /// The compact sidebar uses M/A/D; full XY status remains available above.
  String get label {
    if (isDeleted) return 'D';
    if (isUntracked ||
        indexStatus == 'A' ||
        workTreeStatus == 'A' ||
        indexStatus == 'C' ||
        workTreeStatus == 'C') {
      return 'A';
    }
    return 'M';
  }
}

class IdeGitSnapshot {
  IdeGitSnapshot({
    required this.repositoryRoot,
    required this.branch,
    required List<IdeGitChange> changes,
    required this.truncated,
  }) : changes = List.unmodifiable(changes);

  final String repositoryRoot;
  final String branch;
  final List<IdeGitChange> changes;
  final bool truncated;
}

/// Parse `git status --porcelain=v1 -z` without splitting/quoting filenames.
/// In this format a rename is `XY destination\0original\0` (not old -> new).
List<IdeGitChange> parseGitPorcelain(String output, {int? maxEntries}) {
  if (maxEntries != null && maxEntries < 1) {
    throw ArgumentError.value(maxEntries, 'maxEntries', 'Must be positive');
  }
  final changes = <IdeGitChange>[];
  var offset = 0;
  String field() {
    final end = output.indexOf('\x00', offset);
    if (end < 0) {
      throw const FormatException('Unterminated Git status record');
    }
    final value = output.substring(offset, end);
    offset = end + 1;
    return value;
  }

  while (offset < output.length) {
    final record = field();
    if (record.length < 4 || record[2] != ' ') {
      throw const FormatException('Invalid Git status record');
    }
    final indexStatus = record[0];
    final workTreeStatus = record[1];
    String? original;
    if (indexStatus == 'R' ||
        workTreeStatus == 'R' ||
        indexStatus == 'C' ||
        workTreeStatus == 'C') {
      original = field();
      if (original.isEmpty) {
        throw const FormatException('Missing Git rename source');
      }
    }
    if (indexStatus == '!' && workTreeStatus == '!') continue;
    changes.add(
      IdeGitChange(
        relativePath: record.substring(3),
        indexStatus: indexStatus,
        workTreeStatus: workTreeStatus,
        originalRelativePath: original,
      ),
    );
    if (changes.length == maxEntries) break;
  }
  return changes;
}
