// One question to Claude Haiku, through Claude Code, for the small jobs
// the app does itself: commit messages, agents' titles.

import 'dart:convert';

import '../../models/model_providers.dart';
import '../../models/model_runtime.dart';
import '../../remote/remote_claude.dart';
import '../../remote/remote_location.dart';
import '../../remote/ssh_host.dart';
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
///
/// It runs where [location] is (a project's): on its host for a remote
/// one, this machine otherwise.
Future<String> askClaudeHaiku(
  String system,
  String prompt, {
  Future<void>? cancel,
  String? model,
  bool exact = false,
  String? location,
}) async {
  final host = location == null ? null : RemoteLocation.hostOf(location);
  final custom = ModelProviders.current.resolve(model);
  if (custom == null) {
    if (host != null) {
      return askRemoteHaiku(
        SshHosts.instance[host],
        system,
        prompt,
        cancel: cancel,
      );
    }
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
  if (host != null) {
    return askRemoteHaiku(
      SshHosts.instance[host],
      system,
      prompt,
      cancel: cancel,
      model: name,
      env: env,
    );
  }
  return platform.askClaudeHaiku(
    system,
    prompt,
    cancel: cancel,
    model: name,
    env: env,
  );
}

/// The arguments of one question to Claude Haiku: [model] (`haiku` by
/// default), the flag settings in [settingsFile] if any.
List<String> claudeHaikuArguments(
  String system, {
  String? model,
  String? settingsFile,
}) => [
  '-p',
  '--model',
  model ?? 'haiku',
  if (settingsFile != null) ...['--settings', settingsFile],
  '--output-format',
  'json',
  '--no-session-persistence',
  '--strict-mcp-config',
  '--disable-slash-commands',
  // Takes several: the next option ends the list.
  '--tools',
  '',
  '--system-prompt',
  system,
];

/// The answer in what Claude Code printed ([output], [stderr]) and exited
/// with ([code]); throws [ClaudeHaikuException] for none.
String claudeHaikuAnswer(String output, String stderr, int code) {
  Object? result;
  try {
    result = jsonDecode(output);
  } on FormatException {
    result = null;
  }
  if (result case {'is_error': false, 'result': final String text}
      when text.trim().isNotEmpty) {
    return text;
  }
  final reason = switch (result) {
    {'result': final String text} when text.trim().isNotEmpty => text.trim(),
    _ => stderr.trim(),
  };
  throw ClaudeHaikuException(
    reason.isEmpty ? 'Claude Code gave no answer (exit $code).' : reason,
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
