import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../engine/engine.dart';
import '../engine/session.dart';
import '../util/json.dart';

/// Claude Code's command line, as far as BaoCode starts it (`claude -p`,
/// with its flags): what a session is started with, read as the engine's
/// options. So that the engine runs where a `claude` would, e.g. on a
/// remote host, started with the same arguments.
class AgentCommandLine {
  AgentCommandLine._({
    required this.options,
    required this.inputFormat,
    required this.outputFormat,
  });

  /// Reads [arguments] for a session in [cwd], with [environment] (the
  /// user's shell's).
  factory AgentCommandLine.parse(
    List<String> arguments, {
    required String cwd,
    required Map<String, String> environment,
  }) {
    final rest = [...arguments];
    String? value(String flag) {
      if (rest.isEmpty) throw FormatException('$flag takes a value');
      return rest.removeAt(0);
    }

    String? resume;
    String? sessionId;
    String? model;
    String? permissionMode;
    String? effort;
    String? thinkingDisplay;
    int? autocompact;
    var persist = true;
    final directories = <String>[];
    final flagSettings = <String, Object?>{};
    final sdkServers = <String>[];
    final allowed = <String>[];
    String? appendSystemPrompt;
    String? systemPrompt;
    var promptSuggestions = false;
    List<String>? tools;
    int? maxTurns;
    var strict = false;
    var slashCommands = true;
    var canAsk = false;
    var inputFormat = 'text';
    var outputFormat = 'text';
    while (rest.isNotEmpty) {
      final flag = rest.removeAt(0);
      switch (flag) {
        case '-p' || '--print' || '--verbose' || '--include-partial-messages':
        case '--replay-user-messages' || '--allow-dangerously-skip-permissions':
          break;
        case '--permission-prompt-tool':
          canAsk = value(flag) != null;
        case '--thinking-display':
          thinkingDisplay = value(flag);
        case '--input-format':
          inputFormat = value(flag)!;
        case '--output-format':
          outputFormat = value(flag)!;
        case '--prompt-suggestions':
          promptSuggestions = true;
        case '--permission-mode':
          permissionMode = value(flag);
        case '--dangerously-skip-permissions':
          permissionMode = 'bypassPermissions';
        case '--model':
          model = value(flag);
        case '--effort':
          effort = value(flag);
        case '--autocompact':
          autocompact = int.tryParse(value(flag)!);
        case '--resume' || '-r':
          resume = value(flag);
        case '--session-id':
          sessionId = value(flag);
        case '--add-dir':
          directories.add(value(flag)!);
        case '--settings':
          _merge(flagSettings, _jsonOrFile(value(flag)!, flag));
        case '--no-session-persistence':
          persist = false;
        case '--mcp-config':
          final servers = asMap(_jsonOrFile(value(flag)!, flag)['mcpServers']);
          // The host's own by name; others as settings given.
          final given = {
            for (final MapEntry(:key, :value) in servers.entries)
              if (asMap(value)['type'] != 'sdk') key: value,
          };
          sdkServers.addAll(servers.keys.where((k) => !given.containsKey(k)));
          if (given.isNotEmpty) {
            _merge(flagSettings, {'mcpServers': given});
          }
        case '--strict-mcp-config':
          strict = true;
        case '--allowedTools' || '--allowed-tools':
          allowed.addAll(_list(value(flag)!));
        case '--append-system-prompt':
          appendSystemPrompt = value(flag);
        case '--system-prompt':
          systemPrompt = value(flag);
        case '--max-turns':
          maxTurns = int.tryParse(value(flag)!);
        case '--disable-slash-commands':
          slashCommands = false;
        case '--tools':
          // Takes several: the next option ends the list.
          tools = [];
          while (rest.isNotEmpty && !rest.first.startsWith('-')) {
            tools.addAll(_list(rest.removeAt(0)));
          }
        default:
          throw FormatException('Unknown option: $flag');
      }
    }
    if (allowed.isNotEmpty) {
      final permissions = flagSettings['permissions'] = {
        ...asMap(flagSettings['permissions']),
      };
      permissions['allow'] = [...asList(permissions['allow']), ...allowed];
    }
    return AgentCommandLine._(
      inputFormat: inputFormat,
      outputFormat: outputFormat,
      options: EngineOptions(
        cwd: cwd,
        resume: resume,
        sessionId: sessionId,
        model: model,
        permissionMode: permissionMode,
        effort: effort,
        thinkingDisplay: thinkingDisplay,
        autocompact: autocompact,
        persist: persist,
        directories: directories,
        flagSettings: flagSettings,
        sdkServers: sdkServers,
        appendSystemPrompt: appendSystemPrompt,
        promptSuggestions: promptSuggestions,
        environment: environment,
        systemPrompt: systemPrompt,
        tools: tools,
        maxTurns: maxTurns,
        strictMcpConfig: strict,
        slashCommands: slashCommands,
        canAsk: canAsk,
      ),
    );
  }

  final EngineOptions options;

  /// `text` (the prompt, whole, on stdin) or `stream-json` (the protocol's
  /// messages, a line each).
  final String inputFormat;

  /// `text` (the answer), `json` (the result message) or `stream-json`
  /// (every message, a line each).
  final String outputFormat;

  static List<String> _list(String value) => [
    for (final part in value.split(RegExp(r'[,\s]+')))
      if (part.isNotEmpty) part,
  ];

  /// `--settings` and `--mcp-config` take JSON, or a file of it.
  static Map<String, Object?> _jsonOrFile(String value, String flag) {
    final text = value.trimLeft().startsWith('{')
        ? value
        : File(value).readAsStringSync();
    final json = jsonDecode(text);
    if (json is! Map) throw FormatException('$flag is not a JSON object');
    return json.cast<String, Object?>();
  }

  static void _merge(Map<String, Object?> into, Map<String, Object?> from) {
    for (final MapEntry(:key, :value) in from.entries) {
      if (value is Map && into[key] is Map) {
        final merged = {...asMap(into[key])};
        _merge(merged, value.cast<String, Object?>());
        into[key] = merged;
      } else {
        into[key] = value;
      }
    }
  }
}

/// Runs the engine as `claude` [arguments] would run: messages from
/// [input] and to [output], a line each, with `--input-format stream-json`;
/// else one prompt, the whole of [input], answered on [output]. What the
/// process exits with.
Future<int> runAgentCommandLine(
  List<String> arguments, {
  required Stream<List<int>> input,
  required IOSink output,
  required IOSink errors,
  required String cwd,
  required Map<String, String> environment,
}) async {
  final AgentCommandLine line;
  try {
    line = AgentCommandLine.parse(
      arguments,
      cwd: cwd,
      environment: environment,
    );
  } on Object catch (error) {
    errors.writeln('$error');
    return 2;
  }
  void say(Map<String, Object?> message) => output.writeln(jsonEncode(message));

  if (line.inputFormat == 'stream-json') {
    final engine = AgentEngine(line.options, send: say);
    final reading = input
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen((text) {
          if (text.trim().isEmpty) return;
          try {
            final message = jsonDecode(text);
            if (message is Map) {
              engine.receive(message.cast<String, Object?>());
            }
          } on FormatException {
            errors.writeln('Not a message: $text');
          }
        }, onDone: () => unawaited(engine.close()));
    await engine.done;
    await reading.cancel();
    await output.flush();
    return 0;
  }

  // One prompt, answered.
  final prompt = await input
      .transform(const Utf8Decoder(allowMalformed: true))
      .join();
  if (prompt.trim().isEmpty) {
    errors.writeln('No prompt given on stdin.');
    return 2;
  }
  final result = Completer<Map<String, Object?>>();
  final engine = AgentEngine(
    line.options,
    send: (message) {
      // Its result is the last said, as the CLI's is.
      if (result.isCompleted) return;
      if (line.outputFormat == 'stream-json') say(message);
      if (message['type'] == 'result') {
        result.complete(message);
      }
    },
  );
  engine.receive({
    'type': 'user',
    'message': {'role': 'user', 'content': prompt},
  });
  final answer = await Future.any([
    result.future,
    engine.done.then((_) => <String, Object?>{'is_error': true}),
  ]);
  await engine.close();
  switch (line.outputFormat) {
    case 'json':
      say(answer);
    case 'text':
      if (answer['result'] case final String text) output.writeln(text);
  }
  await output.flush();
  return answer['is_error'] == true ? 1 : 0;
}
