import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../platform/app_paths.dart';
import '../platform/machine_platform.dart';
import '../server/server_agy.dart' show ServerAgyRuntime;
import 'agy_release.dart';
import 'agy_runtime.dart';
import 'agy_transport_core.dart';

/// Claude Code's command line (`ClaudeLaunch` arguments) parsed into
/// [AgyLaunchOptions] for the headless `baocode-server agy` subcommand.
class AgyCommandLine {
  AgyCommandLine._({
    required this.options,
    required this.agyRoot,
    required this.inputFormat,
    required this.outputFormat,
  });

  /// Parses [arguments] for a session in [cwd] running with [environment].
  factory AgyCommandLine.parse(
    List<String> arguments, {
    required String cwd,
    required Map<String, String> environment,
  }) {
    final rest = [...arguments];
    String value(String flag) {
      if (rest.isEmpty) throw FormatException('$flag takes a value');
      return rest.removeAt(0);
    }

    String? agyRoot;
    String? resume;
    String? model;
    String? permissionMode;
    String? effort;
    int? autocompact;
    var persist = true;
    final directories = <String>[];
    final flagSettings = <String, Object?>{};
    final sdkServers = <String>[];
    final allowed = <String>[];
    String? appendSystemPrompt;
    String? systemPrompt;
    var inputFormat = 'stream-json';
    var outputFormat = 'stream-json';

    while (rest.isNotEmpty) {
      final flag = rest.removeAt(0);
      switch (flag) {
        case '-p' ||
            '--print' ||
            '--verbose' ||
            '--include-partial-messages' ||
            '--replay-user-messages' ||
            '--allow-dangerously-skip-permissions' ||
            '--strict-mcp-config' ||
            '--prompt-suggestions' ||
            '--disable-slash-commands':
          break;
        case '--permission-prompt-tool' ||
            '--thinking-display' ||
            '--session-id' ||
            '--max-turns':
          value(flag);
        case '--input-format':
          inputFormat = value(flag);
        case '--output-format':
          outputFormat = value(flag);
        case '--permission-mode':
          permissionMode = value(flag);
        case '--dangerously-skip-permissions':
          permissionMode = 'bypassPermissions';
        case '--model':
          model = value(flag);
        case '--effort':
          effort = value(flag);
        case '--autocompact':
          autocompact = int.tryParse(value(flag));
        case '--resume' || '-r':
          resume = value(flag);
        case '--add-dir':
          directories.add(value(flag));
        case '--settings':
          _merge(flagSettings, _jsonOrFile(value(flag), flag));
        case '--no-session-persistence':
          persist = false;
        case '--mcp-config':
          final servers = _asMap(_jsonOrFile(value(flag), flag)['mcpServers']);
          final nonSdk = <String, Object?>{};
          for (final MapEntry(:key, :value) in servers.entries) {
            final server = _asMap(value);
            if (server['type'] == 'sdk') {
              sdkServers.add(key);
            } else {
              nonSdk[key] = value;
            }
          }
          if (nonSdk.isNotEmpty) {
            _merge(flagSettings, {'mcpServers': nonSdk});
          }
        case '--allowedTools' || '--allowed-tools':
          allowed.addAll(_list(value(flag)));
        case '--tools':
          while (rest.isNotEmpty && !rest.first.startsWith('-')) {
            rest.removeAt(0);
          }
        case '--append-system-prompt':
          appendSystemPrompt = value(flag);
        case '--append-system-prompt-file':
          appendSystemPrompt = File(value(flag)).readAsStringSync();
        case '--system-prompt':
          systemPrompt = value(flag);
        case '--system-prompt-file':
          systemPrompt = File(value(flag)).readAsStringSync();
        case '--agy-root':
          agyRoot = value(flag);
        default:
          throw FormatException('Unknown option: $flag');
      }
    }

    if (allowed.isNotEmpty) {
      final permissions = flagSettings['permissions'] = {
        ..._asMap(flagSettings['permissions']),
      };
      permissions['allow'] = [..._asList(permissions['allow']), ...allowed];
    }

    var folderInstructions = true;
    final settingsEnv = _asMap(flagSettings['env']);
    final extraDirsFlag =
        settingsEnv['CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD'];
    if (extraDirsFlag is String &&
        (extraDirsFlag == '0' || extraDirsFlag.toLowerCase() == 'false')) {
      folderInstructions = false;
    }

    final instructionParts = <String>[];
    String? resolvedAppendedSystemPrompt;
    if (appendSystemPrompt != null) {
      const defaultPrompt = AgyLaunchOptions.defaultAppendedSystemPrompt;
      resolvedAppendedSystemPrompt = defaultPrompt;
      if (appendSystemPrompt.startsWith(defaultPrompt)) {
        final tail = appendSystemPrompt.substring(defaultPrompt.length).trim();
        if (tail.isNotEmpty) instructionParts.add(tail);
      } else {
        final trimmed = appendSystemPrompt.trim();
        if (trimmed.isNotEmpty) instructionParts.add(trimmed);
      }
    }
    if (systemPrompt != null) {
      final trimmed = systemPrompt.trim();
      if (trimmed.isNotEmpty) instructionParts.add(trimmed);
    }

    return AgyCommandLine._(
      agyRoot: agyRoot,
      inputFormat: inputFormat,
      outputFormat: outputFormat,
      options: AgyLaunchOptions(
        cwd: cwd,
        resume: resume,
        model: model,
        permissionMode: permissionMode,
        effort: effort,
        autocompact: autocompact,
        persist: persist,
        directories: directories,
        folderInstructions: folderInstructions,
        instructions: instructionParts.isEmpty
            ? null
            : instructionParts.join('\n\n'),
        sdkServers: sdkServers,
        flagSettings: flagSettings,
        baseEnvironment: environment,
        appendedSystemPrompt: resolvedAppendedSystemPrompt,
      ),
    );
  }

  final AgyLaunchOptions options;
  final String? agyRoot;
  final String inputFormat;
  final String outputFormat;

  static List<String> _list(String value) => [
    for (final part in value.split(RegExp(r'[,\s]+')))
      if (part.isNotEmpty) part,
  ];

  static Map<String, Object?> _asMap(Object? value) => switch (value) {
    final Map map => map.cast<String, Object?>(),
    _ => const {},
  };

  static List<Object?> _asList(Object? value) =>
      value is List ? value : const [];

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
        final merged = {..._asMap(into[key])};
        _merge(merged, value.cast<String, Object?>());
        into[key] = merged;
      } else {
        into[key] = value;
      }
    }
  }
}

/// Runs [AgyTransportCore] over [input]/[output] using NDJSON Claude
/// `stream-json` messages (for `baocode-server agy`). Returns the process exit
/// code.
Future<int> runAgyCommandLine(
  List<String> arguments, {
  required Stream<List<int>> input,
  required IOSink output,
  required IOSink errors,
  required String cwd,
  required Map<String, String> environment,
  AgyRuntime? runtime,
  String? brainDir,
  bool handleSignals = true,
}) async {
  final AgyCommandLine line;
  try {
    line = AgyCommandLine.parse(
      arguments,
      cwd: cwd,
      environment: environment,
    );
  } on Object catch (error) {
    errors.writeln('$error');
    await _flushQuietly(errors);
    return 2;
  }

  final ownedRuntime = runtime == null;
  final managed = ManagedAgy(
    line.agyRoot ??
        p.join(AppPaths.home(environment), '.baocode-server', 'data', 'antigravity'),
  );
  final agyRuntime =
      runtime ??
      ServerAgyRuntime(
        managed: managed,
        platform: machinePlatform(),
        baseEnvironment: () async => environment,
      );
  final resolvedBrainDir = brainDir ?? managed.brainDir;

  final AgyTransportCore transport;
  try {
    transport = await AgyTransportCore.start(
      line.options,
      runtime: agyRuntime,
      brainDir: resolvedBrainDir,
    );
  } on Object catch (error) {
    errors.writeln('$error');
    if (ownedRuntime) await agyRuntime.stopAll();
    await _flushQuietly(errors);
    return 1;
  }

  final outputSub = transport.messages.listen((message) {
    if (message['type'] == 'transport_exit') return;
    try {
      output.writeln(jsonEncode(message));
    } on Object {
      // Output closed by parent.
    }
  });

  final signalSubs = <StreamSubscription<ProcessSignal>>[];
  if (handleSignals) {
    final signals = Platform.isWindows
        ? const [ProcessSignal.sigint]
        : const [ProcessSignal.sigterm, ProcessSignal.sigint];
    for (final signal in signals) {
      try {
        signalSubs.add(signal.watch().listen((_) => transport.close()));
      } on SignalException {
        // Unsupported in this environment.
      }
    }
  }

  final inputSub = input
      .transform(const Utf8Decoder(allowMalformed: true))
      .transform(const LineSplitter())
      .listen(
        (text) {
          if (text.trim().isEmpty) return;
          try {
            final message = jsonDecode(text);
            if (message is Map) {
              transport.write(message.cast<String, Object?>());
            }
          } on FormatException {
            errors.writeln('Not a message: $text');
          }
        },
        onDone: transport.close,
        onError: (Object _) => transport.close(),
      );

  try {
    await transport.exited;
  } finally {
    for (final sub in signalSubs) {
      await sub.cancel();
    }
    await inputSub.cancel();
    await outputSub.cancel();
    if (ownedRuntime) await agyRuntime.stopAll();
    await _flushQuietly(output);
    await _flushQuietly(errors);
  }
  return 0;
}

Future<void> _flushQuietly(IOSink sink) async {
  try {
    await sink.flush();
  } on Object {
    // Closed already.
  }
}
