import 'package:flutter/foundation.dart';

/// Settings → General → Claude Code: what runs a Claude Code session
/// (`claudeCode.core` in settings.json).
enum ClaudeCore {
  /// BaoCode's own core, written in Dart (package:bao_agent): the same
  /// protocol, files and settings as the CLI, in the app itself. It runs
  /// on the upstreams of Settings → Models alone, never on a model the
  /// machine's Claude Code setup names.
  builtin,

  /// The Claude Code CLI, as a process: downloaded the first time where
  /// the machine has none (see LocalClaude), once picked.
  cli;

  static const settingKey = 'claudeCode.core';

  /// When the setting is unset, or not one of these: the CLI where Claude
  /// Code is on this machine, else the built-in core. Nothing is downloaded
  /// unasked, nor the CLI suggested.
  static ClaudeCore get fallback => cliInstalled() ? cli : builtin;

  /// Whether Claude Code is on this machine, as last looked; main() points
  /// it at `LocalClaude.installed`.
  static bool Function() cliInstalled = () => false;

  static ClaudeCore parse(Object? setting) =>
      values.where((value) => value.name == setting).firstOrNull ?? fallback;

  /// The setting as it is now, read as each session starts; main() points
  /// it at settings.json.
  static ClaudeCore Function() current = () => fallback;

  /// Told as the setting may have changed; main() points it at
  /// settings.json.
  static Listenable changes = const _Never();

  /// Why [builtin] has nothing to run on: no upstream turned on.
  static const noModel =
      'No model to run on: BaoCode\'s own core runs on the upstreams of '
      'Settings → Models. Add one there, or switch the core to the Claude '
      'Code CLI in Settings → General.';
}

/// Tells nothing: no settings file to follow.
class _Never implements Listenable {
  const _Never();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
