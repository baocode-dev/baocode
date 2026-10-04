// One question to Claude Haiku, through Claude Code, for the small jobs
// the app does itself: commit messages, agents' titles.

import '../../models/model_providers.dart';
import '../../models/model_runtime.dart';
import 'claude_haiku_stub.dart'
    if (dart.library.io) 'claude_haiku_io.dart'
    as platform;

/// Asks Claude Haiku [prompt], with [system] as its system prompt (one
/// line, so that it passes through a shell unchanged): one turn, no tools,
/// no session kept. Completing [cancel] stops it, and it then throws
/// [ClaudeHaikuCancelled]; it throws [ClaudeHaikuException] when it gets
/// no answer.
///
/// With [model] a provider's ([modelRef]), the provider is asked instead:
/// its Haiku model, or [model] itself when it sets none (or when [exact]).
Future<String> askClaudeHaiku(
  String system,
  String prompt, {
  Future<void>? cancel,
  String? model,
  bool exact = false,
}) async {
  final custom = ModelProviders.current.resolve(model);
  if (custom == null) {
    return platform.askClaudeHaiku(system, prompt, cancel: cancel);
  }
  final (provider, info) = custom;
  final name = exact ? info.id : provider.roles.haiku ?? info.id;
  final Map<String, String> env;
  try {
    env = await providerLaunchEnvironment(provider, name);
  } on Object catch (error) {
    throw ClaudeHaikuException('${provider.name}: $error');
  }
  return platform.askClaudeHaiku(
    system,
    prompt,
    cancel: cancel,
    model: name,
    env: env,
  );
}

class ClaudeHaikuCancelled implements Exception {
  const ClaudeHaikuCancelled();
}

class ClaudeHaikuException implements Exception {
  const ClaudeHaikuException(this.message);

  final String message;

  @override
  String toString() => message;
}
