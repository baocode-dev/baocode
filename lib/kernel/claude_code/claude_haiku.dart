// One question to Claude Haiku, through Claude Code, for the small jobs
// the app does itself: commit messages, agents' titles.

import 'dart:convert';

import '../../chat/chat_models.dart' show ImageAttachment;
import '../../models/model_providers.dart';
import '../../models/model_runtime.dart';
import '../../remote/remote_claude.dart';
import '../../remote/remote_location.dart';
import '../../remote/ssh_host.dart';
import 'claude_code_transport.dart' show ClaudeLaunch;
import 'claude_core_setting.dart';
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
/// BaoCode's own core has no Haiku of its own: on it, without one of a
/// provider's, the first upstream's is asked as automatic would.
///
/// It runs where [location] is (a project's): on its host for a remote
/// one, this machine otherwise.
///
/// [images] go with the prompt, before it, each after a line naming it
/// (see [claudeHaikuMessage]): the model sees them without tools. With
/// [tools], it may look at files (see [ClaudeHaikuTools]). Both only on
/// this machine; a remote host is asked the prompt alone.
Future<String> askClaudeHaiku(
  String system,
  String prompt, {
  Future<void>? cancel,
  String? model,
  bool exact = false,
  String? location,
  List<({String name, ImageAttachment image})> images = const [],
  ClaudeHaikuTools? tools,
}) async {
  final host = location == null ? null : RemoteLocation.hostOf(location);
  final providers = ModelProviders.current;
  var custom = providers.resolve(model);
  if (custom == null && !providers.builtinAvailable) {
    custom = providers.resolve(providers.firstModel);
    if (custom == null) throw const ClaudeHaikuException(ClaudeCore.noModel);
    exact = false;
  }
  if (custom == null) {
    if (host != null) {
      return askRemoteHaiku(
        SshHosts.instance[host],
        system,
        prompt,
        cancel: cancel,
      );
    }
    return platform.askClaudeHaiku(
      system,
      prompt,
      cancel: cancel,
      images: images,
      tools: tools,
    );
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
    images: images,
    tools: tools,
  );
}

/// What a question may look at, read only: [tools] (Claude Code's), run
/// in [directory] (a project's folder on this machine, whose files they
/// read without asking, its CLAUDE.md read too; a temporary folder when
/// null) and reading the [readable] folders besides; nothing else, and
/// nothing written. At most [maxTurns] turns, its answer the last.
class ClaudeHaikuTools {
  const ClaudeHaikuTools({
    this.tools = const ['Read'],
    this.directory,
    this.readable = const [],
    this.maxTurns = 12,
  });

  final List<String> tools;
  final String? directory;
  final List<String> readable;
  final int maxTurns;

  /// Its flag settings: the rules that let it read [readable].
  Map<String, Object?> get settings => {
    if (readable.isNotEmpty)
      'permissions': {
        'allow': [for (final folder in readable) ClaudeLaunch.readRule(folder)],
      },
  };
}

/// [prompt] with [images] before it, as the one user message Claude Code
/// reads with `--input-format stream-json` (see [claudeHaikuArguments]):
/// each picture after a line naming it.
String claudeHaikuMessage(
  String prompt,
  List<({String name, ImageAttachment image})> images,
) => jsonEncode({
  'type': 'user',
  'message': {
    'role': 'user',
    'content': [
      for (final (:name, :image) in images) ...[
        {'type': 'text', 'text': '[Picture: $name]'},
        {
          'type': 'image',
          'source': {
            'type': 'base64',
            'media_type': image.mediaType,
            'data': base64Encode(image.bytes),
          },
        },
      ],
      {'type': 'text', 'text': prompt},
    ],
  },
});

/// Asks [model] (a [modelRef]) [prompt] through Claude Code, as
/// [askClaudeHaiku] does, and times its answer as it streams: how soon
/// its first text came, how fast the rest. On this machine.
Future<ClaudeTimedAnswer> timeClaudeAnswer(
  String system,
  String prompt, {
  required String model,
  Future<void>? cancel,
}) async {
  final custom = ModelProviders.current.resolve(model);
  if (custom == null) throw ClaudeHaikuException('No model $model.');
  final (provider, info) = custom;
  final Map<String, String> env;
  try {
    env = await providerLaunchEnvironment(provider, info.id);
  } on Object catch (error) {
    throw ClaudeHaikuException('${provider.name}: $error');
  }
  return platform.timeClaudeAnswer(
    system,
    prompt,
    cancel: cancel,
    model: info.id,
    env: env,
  );
}

/// An answer, and how it came.
class ClaudeTimedAnswer {
  const ClaudeTimedAnswer(
    this.text, {
    required this.firstText,
    required this.lastText,
    this.outputTokens,
  });

  final String text;

  /// From Claude Code starting its request to the first text, and to the
  /// last.
  final Duration firstText;
  final Duration lastText;

  /// As the upstream counted them, if it did.
  final int? outputTokens;

  /// Tokens a second, while it wrote: none without a count, or with all
  /// the text at once.
  double? get tokensPerSecond {
    final writing = lastText - firstText;
    if (outputTokens == null || writing <= Duration.zero) return null;
    return outputTokens! / (writing.inMicroseconds / 1000000);
  }
}

/// Times an answer from what Claude Code prints, as stream-json, each
/// line as it comes ([add]); [answer] once it has exited.
class ClaudeAnswerTimer {
  Duration? _start;
  Duration? _firstText;
  Duration? _lastText;
  Map<String, Object?>? _result;

  /// [line], printed [at] (since Claude Code started).
  void add(String line, Duration at) {
    final Object? message;
    try {
      message = jsonDecode(line);
    } on FormatException {
      return;
    }
    switch (message) {
      // Ready, its request about to go.
      case {'type': 'system', 'subtype': 'init'}:
        _start ??= at;
      case {
            'type': 'stream_event',
            'event': {
              'type': 'content_block_delta',
              'delta': {'type': 'text_delta', 'text': final String text},
            },
          }
          when text.isNotEmpty:
        _firstText ??= at;
        _lastText = at;
      case {'type': 'result'}:
        _result = message as Map<String, Object?>;
    }
  }

  /// The answer, with what Claude Code wrote to [stderr] and exited with
  /// ([code]); throws [ClaudeHaikuException] for none.
  ClaudeTimedAnswer answer(String stderr, int code) {
    final text = claudeHaikuAnswer(jsonEncode(_result), stderr, code);
    final start = _start ?? Duration.zero;
    final first = _firstText ?? _lastText ?? start;
    final tokens = switch (_result?['usage']) {
      {'output_tokens': final int tokens} when tokens > 0 => tokens,
      _ => null,
    };
    return ClaudeTimedAnswer(
      text,
      firstText: first - start,
      lastText: (_lastText ?? first) - start,
      outputTokens: tokens,
    );
  }
}

/// The arguments of one question to Claude Haiku: [model] (`haiku` by
/// default), the flag settings in [settingsFile] if any; its answer
/// streamed when [stream]. With [message], the question is a message of
/// stream-json (see [claudeHaikuMessage]), which streams the answer too.
List<String> claudeHaikuArguments(
  String system, {
  String? model,
  String? settingsFile,
  bool stream = false,
  bool message = false,
  ClaudeHaikuTools? tools,
}) => [
  '-p',
  '--model',
  model ?? 'haiku',
  if (settingsFile != null) ...['--settings', settingsFile],
  if (tools != null) ...['--max-turns', '${tools.maxTurns}'],
  if (message) ...['--input-format', 'stream-json'],
  '--output-format',
  if (stream || message) ...[
    'stream-json',
    '--verbose',
    '--include-partial-messages',
  ] else
    'json',
  '--no-session-persistence',
  '--strict-mcp-config',
  '--disable-slash-commands',
  // Takes several: the next option ends the list.
  '--tools',
  tools?.tools.join(',') ?? '',
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
  // With "viewMode": "verbose" in the user's settings, `json` prints every
  // event as an array, the result last.
  if (result is List) {
    result = result.lastWhere(
      (event) => event is Map && event['type'] == 'result',
      orElse: () => null,
    );
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
