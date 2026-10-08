import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';
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

  /// The shell asked instead of the user's `SHELL`, under test.
  @visibleForTesting
  static String? shellOverride;

  /// The login shell's environment; the app's own if that fails, and the
  /// app's own on Windows, which has no login shell to ask.
  ///
  /// Asked as a terminal window does, interactive too: what the user's rc
  /// file (`~/.zshrc`) puts on the PATH, nvm's Node or `~/.local/bin`, is
  /// where the `claude` they run is, and a login shell alone does not read
  /// it. Not interactive if that fails, e.g. an rc file that will not run
  /// without a terminal.
  static Future<Map<String, String>> _login() async {
    final fallback = Map<String, String>.of(Platform.environment);
    if (Platform.isWindows) return fallback;
    final shell =
        shellOverride ??
        Platform.environment['SHELL'] ??
        (Platform.isMacOS ? '/bin/zsh' : '/bin/sh');
    final environment =
        await _ask(shell, ['-i', '-l']) ?? await _ask(shell, ['-l']);
    return environment == null ? fallback : {...fallback, ...environment};
  }

  /// The environment [shell] started with [flags] has, or null if it
  /// fails to say.
  ///
  /// In a session of its own, as VS Code asks: an interactive shell takes
  /// the terminal it finds for its jobs, and the app's, when it runs in
  /// one, is not its to take. Between two markers, as an rc file may print
  /// before or after.
  static Future<Map<String, String>?> _ask(
    String shell,
    List<String> flags,
  ) async {
    const marker = '__BAOCODE_ENV__';
    Process? process;
    try {
      process = await Process.start(shell, [
        ...flags,
        '-c',
        'echo $marker; env; echo $marker',
      ], mode: ProcessStartMode.detachedWithStdio);
      // Nothing to read: an rc file that asks something is told so at once.
      unawaited(process.stdin.close().catchError((_) {}));
      unawaited(process.stderr.drain<void>().catchError((_) {}));
      final printed = await _between(
        process.stdout,
        marker,
      ).timeout(const Duration(seconds: 8));
      if (printed == null) return null;
      final environment = <String, String>{};
      for (final line in const LineSplitter().convert(printed)) {
        final equals = line.indexOf('=');
        if (equals > 0) {
          environment[line.substring(0, equals)] = line.substring(equals + 1);
        }
      }
      return environment.containsKey('PATH') ? environment : null;
    } on Object {
      process?.kill(ProcessSignal.sigkill);
      return null;
    }
  }

  /// What [output] prints between the first two [marker]s, read up to the
  /// second rather than to its end: what an rc file starts in the
  /// background may hold it open.
  static Future<String?> _between(
    Stream<List<int>> output,
    String marker,
  ) async {
    var printed = '';
    await for (final chunk in output.transform(
      const Utf8Decoder(allowMalformed: true),
    )) {
      printed += chunk;
      final start = printed.indexOf(marker);
      if (start < 0) continue;
      final end = printed.indexOf(marker, start + marker.length);
      if (end >= 0) return printed.substring(start + marker.length, end);
    }
    return null;
  }
}
