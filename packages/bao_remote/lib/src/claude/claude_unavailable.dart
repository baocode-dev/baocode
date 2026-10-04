/// Claude Code cannot start: not installed, its folder gone, or the
/// process failed to.
class ClaudeUnavailable implements Exception {
  const ClaudeUnavailable(this.message, {this.detail});

  final String message;
  final String? detail;

  @override
  String toString() => message;
}

/// Claude Code is not on the machine: neither the user's nor one BaoCode
/// installed.
class ClaudeNotInstalled extends ClaudeUnavailable {
  const ClaudeNotInstalled(super.message, {super.detail});
}

/// Claude Code could not be downloaded or installed.
class ClaudeDownloadFailed extends ClaudeUnavailable {
  const ClaudeDownloadFailed(super.message, {super.detail});
}
