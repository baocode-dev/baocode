import 'commit_message.dart';

/// The web runs no Claude Code.
Future<String> claudeCommitMessage(
  IdeCommitMessagePrompt prompt, {
  Future<void>? cancel,
}) async => throw const IdeCommitMessageException(
  'Generating commit messages needs Claude Code, which the web cannot run.',
);
