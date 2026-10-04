/// Claude Code cannot start: not installed, its folder gone, or the
/// process failed to.
class ClaudeUnavailable implements Exception {
  const ClaudeUnavailable(this.message, {this.detail});

  final String message;
  final String? detail;

  @override
  String toString() => message;
}
