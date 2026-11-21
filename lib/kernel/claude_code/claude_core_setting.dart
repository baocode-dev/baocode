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

/// How Settings → Built-in Core customizes the built-in core's system prompt
/// (`claudeCode.core.systemPromptMode` in settings.json).
enum CoreSystemPromptMode {
  /// Use BaoCode's built-in core instructions as-is.
  defaultPrompt('default'),

  /// Keep the default core instructions and append custom text after them.
  append('append'),

  /// Replace the default core instructions (identity + core instructions)
  /// while keeping memory, output style, CLAUDE.md, and formatting rules.
  replace('replace');

  const CoreSystemPromptMode(this.setting);

  /// The value kept in settings.json (`default` is omitted when saving).
  final String setting;

  static CoreSystemPromptMode parse(Object? value) =>
      values.where((mode) => mode.setting == value).firstOrNull ??
      defaultPrompt;
}

/// The built-in core's custom system prompt setting, read as each session on
/// BaoCode's own core starts.
class CoreSystemPrompt {
  const CoreSystemPrompt({
    this.mode = CoreSystemPromptMode.defaultPrompt,
    this.text = '',
  });

  static const modeKey = 'claudeCode.core.systemPromptMode';
  static const textKey = 'claudeCode.core.systemPrompt';

  final CoreSystemPromptMode mode;
  final String text;

  static CoreSystemPrompt parse(Object? mode, Object? text) => CoreSystemPrompt(
    mode: CoreSystemPromptMode.parse(mode),
    text: text is String ? text : '',
  );

  /// The setting as it is now, read as each built-in core session starts;
  /// main() points it at settings.json.
  static CoreSystemPrompt Function() current = () => const CoreSystemPrompt();

  /// Non-null when [mode] is [CoreSystemPromptMode.replace] and [text] is
  /// non-empty: replaces the default core instructions.
  String? get coreOverride =>
      mode == CoreSystemPromptMode.replace && text.trim().isNotEmpty
      ? text.trim()
      : null;

  /// Non-null when [mode] is [CoreSystemPromptMode.append] and [text] is
  /// non-empty: appended after the default instructions.
  String? get appended =>
      mode == CoreSystemPromptMode.append && text.trim().isNotEmpty
      ? text.trim()
      : null;
}

/// Tells nothing: no settings file to follow.
class _Never implements Listenable {
  const _Never();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
