import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../platform/app_paths.dart';

/// The environment Claude Code runs in, as the user's shell has it: what
/// the CLI is found by, and where it keeps its state.
///
/// An app opened from the Finder gets a bare PATH, so the login shell is
/// asked once (the commands Claude runs need it too); the app's own
/// environment stands in when that fails, and is all there is on Windows,
/// whose window already carries the user's environment.
abstract final class ClaudeEnvironment {
  /// Names the directory Claude Code keeps its state in (`projects`,
  /// `file-history`, …), e.g. a build's own; the installed `~/.claude`
  /// when unset.
  static const dataPathVariable = 'BAOCODE_CLAUDE_DATA_PATH';

  /// Keeps Claude Code to essential traffic: no request for the plan
  /// usage either.
  static const essentialTrafficVariable =
      'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC';

  static Future<Map<String, String>>? _environment;

  /// The login shell's environment over the app's own.
  static Future<Map<String, String>> of() => _environment ??= _login();

  /// Where Claude Code keeps its state: [dataPathVariable], else
  /// `CLAUDE_CONFIG_DIR`, else `<home>/.claude`.
  static Future<String> configDir() async {
    final environment = await of();
    for (final name in const [dataPathVariable, 'CLAUDE_CONFIG_DIR']) {
      if (environment[name] case final dir? when dir.isNotEmpty) return dir;
    }
    final home = AppPaths.home(environment);
    return home.isEmpty ? '' : p.join(home, '.claude');
  }

  /// The state directory for the CLI to run with, from [environment]:
  /// pointed at one, it keeps its sessions there; else where it would.
  static Map<String, String> stateDirectory(Map<String, String> environment) {
    final dir = environment[dataPathVariable];
    return dir == null || dir.isEmpty ? const {} : {'CLAUDE_CONFIG_DIR': dir};
  }

  /// Replaces the environment looked up, e.g. with one set up under test.
  /// Null asks the login shell again.
  static void use(Map<String, String>? environment) =>
      _environment = environment == null ? null : Future.value(environment);

  /// The login shell's environment; the app's own if that fails, and the
  /// app's own on Windows, which has no login shell to ask.
  static Future<Map<String, String>> _login() async {
    final fallback = Map<String, String>.of(Platform.environment);
    if (Platform.isWindows) return fallback;
    final shell =
        Platform.environment['SHELL'] ??
        (Platform.isMacOS ? '/bin/zsh' : '/bin/sh');
    try {
      const marker = '__BAOCODE_ENV__';
      final result = await Process.run(shell, [
        '-l',
        '-c',
        'echo $marker; env',
      ], stdoutEncoding: utf8).timeout(const Duration(seconds: 8));
      final output = result.stdout as String;
      final start = output.indexOf(marker);
      if (result.exitCode != 0 || start < 0) return fallback;
      final environment = <String, String>{};
      for (final line in const LineSplitter().convert(
        output.substring(start + marker.length),
      )) {
        final equals = line.indexOf('=');
        if (equals > 0) {
          environment[line.substring(0, equals)] = line.substring(equals + 1);
        }
      }
      return environment.containsKey('PATH')
          ? {...fallback, ...environment}
          : fallback;
    } on Object {
      return fallback;
    }
  }
}
