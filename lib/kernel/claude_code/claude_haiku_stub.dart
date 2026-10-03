import 'claude_haiku.dart';

/// The web runs no Claude Code.
Future<String> askClaudeHaiku(
  String system,
  String prompt, {
  Future<void>? cancel,
  String? model,
  Map<String, String>? env,
}) async => throw const ClaudeHaikuException(
  'This needs Claude Code, which the web cannot run.',
);
