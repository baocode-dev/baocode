import 'dart:async';
import 'dart:io';

import 'package:bao_agent/bao_agent.dart';

import '../../models/launch_environment.dart';
import '../../network/network_proxy_io.dart';
import 'claude_code_transport.dart';
import 'claude_environment.dart';

/// A session on BaoCode's own core: package:bao_agent's engine in an
/// isolate of its own, speaking what the CLI speaks on its stdin and
/// stdout, started as [ClaudeLaunch] would start the CLI.
class DartCoreTransport implements ClaudeCodeTransport {
  DartCoreTransport._(this._agent) {
    _agent.messages.listen(
      _messages.add,
      onDone: () {
        if (_messages.isClosed) return;
        _messages
          ..add(ClaudeExit.message(0, _agent.errors.join('\n')))
          ..close();
      },
    );
  }

  final AgentIsolate _agent;
  final StreamController<Map<String, Object?>> _messages =
      StreamController.broadcast();

  static Future<ClaudeCodeTransport> start(ClaudeLaunch launch) async {
    if (!Directory(launch.cwd).existsSync()) {
      throw ClaudeFolderGone(launch.cwd);
    }
    final options = await engineOptions(launch);
    try {
      return DartCoreTransport._(await AgentIsolate.spawn(options));
    } on Object catch (error) {
      throw ClaudeUnavailable(
        'The built-in Claude Code core could not start',
        detail: '$error',
      );
    }
  }

  /// [launch] as the engine's options: the environment the CLI would run
  /// in, its command line's flags as options.
  static Future<EngineOptions> engineOptions(ClaudeLaunch launch) async {
    final base = await ClaudeEnvironment.of();
    // The proxy as it is now: Clash may have been turned on since.
    final proxy = await NetworkProxy.instance.environment();
    final environment = <String, String>{...base, ...proxy};
    // A provider's session: none of the user's own model setup.
    if (launch.env != null) {
      for (final name in ClaudeModelVariables.inherited) {
        environment.remove(name);
      }
    }
    environment
      ..addAll(ClaudeLaunch.environment)
      ..addAll(ClaudeEnvironment.stateDirectory(base));
    final instructions = launch.instructions;
    return EngineOptions(
      cwd: launch.cwd,
      resume: launch.resume,
      model: launch.model,
      permissionMode: launch.permissionMode,
      effort: launch.effort,
      thinkingDisplay: ClaudeLaunch.thinkingDisplay,
      autocompact: launch.autocompact,
      persist: launch.persist,
      directories: launch.directories,
      flagSettings: launch.settings,
      sdkServers: launch.sdkServers,
      // The app's servers' tools offered as well.
      tools: switch (launch.tools) {
        final tools? => [
          ...tools,
          for (final server in launch.sdkServers) 'mcp__$server',
        ],
        null => null,
      },
      // Only the app's servers then, as the CLI's --strict-mcp-config.
      strictMcpConfig: launch.tools != null,
      systemPrompt: launch.ownPrompt ? instructions ?? '' : null,
      appendSystemPrompt: launch.ownPrompt
          ? null
          : instructions == null || instructions.isEmpty
          ? ClaudeLaunch.appendedSystemPrompt
          : '${ClaudeLaunch.appendedSystemPrompt}\n\n$instructions',
      promptSuggestions: launch.promptSuggestions,
      environment: environment,
    );
  }

  @override
  Stream<Map<String, Object?>> get messages => _messages.stream;

  @override
  void write(Map<String, Object?> message) => _agent.write(message);

  @override
  void close() => _agent.close();

  @override
  Future<void> get exited => _agent.exited;
}
