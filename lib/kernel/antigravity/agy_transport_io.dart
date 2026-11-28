import 'dart:async';

import 'package:bao_remote/acp.dart' as acp;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import '../claude_code/claude_code_transport.dart';
import 'agy_runtime.dart';
import 'agy_runtime_io.dart' show LocalAgyRuntime;

/// Desktop adapter wrapping [acp.AgyTransportCore] as a [ClaudeCodeTransport].
class AgyTransport implements ClaudeCodeTransport {
  AgyTransport._(this.launch, this._core);

  final ClaudeLaunch launch;
  final acp.AgyTransportCore _core;

  /// How the session is noted beside the conversation.
  static const syncType = acp.AgyTransportCore.syncType;

  /// How long agy is kept once a turn is over.
  static const idleFor = acp.AgyTransportCore.idleFor;

  // ignore_for_file: invalid_use_of_visible_for_testing_member

  @visibleForTesting
  static Duration get stallAfter => acp.AgyTransportCore.stallAfter;
  @visibleForTesting
  static set stallAfter(Duration value) =>
      acp.AgyTransportCore.stallAfter = value;

  @visibleForTesting
  static Duration get checkEvery => acp.AgyTransportCore.checkEvery;
  @visibleForTesting
  static set checkEvery(Duration value) =>
      acp.AgyTransportCore.checkEvery = value;

  @visibleForTesting
  static Duration get cancelGrace => acp.AgyTransportCore.cancelGrace;
  @visibleForTesting
  static set cancelGrace(Duration value) =>
      acp.AgyTransportCore.cancelGrace = value;

  @visibleForTesting
  static Duration get subagentPollInterval =>
      acp.AgyTransportCore.subagentPollInterval;
  @visibleForTesting
  static set subagentPollInterval(Duration value) =>
      acp.AgyTransportCore.subagentPollInterval = value;

  @visibleForTesting
  static int get subagentIdlePollsToStop =>
      acp.AgyTransportCore.subagentIdlePollsToStop;
  @visibleForTesting
  static set subagentIdlePollsToStop(int value) =>
      acp.AgyTransportCore.subagentIdlePollsToStop = value;

  @visibleForTesting
  static int get subagentMissingPollsToStop =>
      acp.AgyTransportCore.subagentMissingPollsToStop;
  @visibleForTesting
  static set subagentMissingPollsToStop(int value) =>
      acp.AgyTransportCore.subagentMissingPollsToStop = value;

  @visibleForTesting
  int get activeSubagentWatchCount => _core.activeSubagentWatchCount;

  static Future<void> forget(
    String sessionId,
    String configDir, {
    acp.AgyRuntime? runtime,
  }) => acp.AgyTransportCore.forget(
    sessionId,
    configDir,
    runtime: runtime ?? AgyRuntime.local,
  );

  static Future<ClaudeCodeTransport> start(
    ClaudeLaunch launch, {
    acp.AgyRuntime? runtime,
    String? brainDir,
  }) async {
    final resolvedRuntime = runtime ?? AgyRuntime.local;
    final resolvedBrainDir =
        brainDir ??
        (resolvedRuntime is LocalAgyRuntime
            ? p.join(resolvedRuntime.home, 'antigravity-cli', 'brain')
            : null);
    final core = await acp.AgyTransportCore.start(
      acp.AgyLaunchOptions(
        cwd: launch.cwd,
        resume: launch.resume,
        model: launch.model,
        permissionMode: launch.permissionMode,
        effort: launch.effort,
        autocompact: launch.autocompact,
        persist: launch.persist,
        directories: launch.directories,
        folderInstructions: launch.folderInstructions,
        instructions: launch.instructions,
        sdkServers: launch.sdkServers,
        flagSettings: launch.settings,
        brainDir: resolvedBrainDir,
        appendedSystemPrompt: ClaudeLaunch.appendedSystemPrompt,
      ),
      runtime: resolvedRuntime,
      brainDir: resolvedBrainDir,
    );
    return AgyTransport._(launch, core);
  }

  @override
  Stream<Map<String, Object?>> get messages => _core.messages;

  @override
  Future<void> get exited => _core.exited;

  @override
  void write(Map<String, Object?> message) => _core.write(message);

  @override
  void close() => _core.close();
}
