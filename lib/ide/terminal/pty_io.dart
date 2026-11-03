import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import '../../kernel/claude_code/claude_environment.dart';
import '../../platform/data_dir.dart';
import '../../platform/child_process_registry.dart';
import 'pty.dart';
import 'shell_integration/shell_integration_files.dart';
import 'terminal_profiles.dart';
import 'terminal_shell.dart';

abstract final class PtyProcesses {
  /// Where the running terminal processes are kept track of across runs. A
  /// leftover is hung up, as closing its terminal would have.
  @visibleForTesting
  static ChildProcessRegistry registry = ChildProcessRegistry(
    file: File(DataDirectory.current.processRegistryFile('pty')),
    signal: (pid) => Process.killPid(pid, ProcessSignal.sighup),
  );

  static final Set<Pty> _live = {};

  static Future<Pty> start(PtyLaunch launch) async {
    await registry.reaped;
    final pty = await spawnPty(launch);
    _live.add(pty);
    unawaited(registry.add(pty.pid));
    unawaited(
      pty.exitCode.then((_) {
        _live.remove(pty);
        unawaited(registry.remove(pty.pid));
      }),
    );
    return pty;
  }

  static TerminalOs get _os => Platform.isWindows
      ? TerminalOs.windows
      : Platform.isMacOS
      ? TerminalOs.macOS
      : TerminalOs.linux;

  static bool _exists(String path) => File(path).existsSync();

  static List<String> _list(String directory) {
    try {
      return [
        for (final entity in Directory(directory).listSync())
          p.basename(entity.path),
      ];
    } on FileSystemException {
      return const [];
    }
  }

  /// [shell] 是已知会读取登录配置的交互启动形式时返回 true。
  /// 特殊参数或未知 shell 保留既有解析环境，不猜测其初始化行为。
  static bool _readsLoginFiles(TerminalShell shell) {
    if (!const {'bash', 'zsh', 'fish'}.contains(p.basename(shell.executable))) {
      return false;
    }
    final args = shell.arguments
        .where((arg) => arg != '-i' && arg != '--interactive')
        .toList();
    return args.length == 1 &&
        const {'-l', '--login', '-il', '-li'}.contains(args.single);
  }

  static Future<PtyLaunch> terminalLaunch(
    String root, {
    required int columns,
    required int rows,
    required bool shellIntegration,
    TerminalShell? shell,
    TerminalEnvironmentRequest? environment,
  }) async {
    final os = _os;
    final inherited = Platform.environment;
    final candidate =
        shell ??
        defaultTerminalShell(os, inherited, exists: _exists, list: _list);
    // 已知登录启动由新 shell 读取当前配置；其他启动仍可能依赖解析环境。
    final login = os != TerminalOs.windows && _readsLoginFiles(candidate);
    final resolved = login ? inherited : await ClaudeEnvironment.of();
    shell ??= login
        ? candidate
        : defaultTerminalShell(os, resolved, exists: _exists, list: _list);
    // 解析后默认 shell 可能变化，基础环境以最终选定的启动形式为准。
    final base = os != TerminalOs.windows && _readsLoginFiles(shell)
        ? inherited
        : resolved;
    final launch = PtyLaunch(
      executable: shell.executable,
      arguments: shell.arguments,
      workingDirectory: root,
      // VS Code adds the terminal's variables to a strict environment
      // too (`addTerminalEnvironmentKeys`).
      environment: _finish(
        environment,
        terminalEnvironment(
          environment?.merge(base) ?? base,
          os: os,
          locale: Platform.localeName,
        ),
      ),
      columns: columns,
      rows: rows,
    );
    return shellIntegration ? injectShellIntegration(launch, os: os) : launch;
  }

  static Map<String, String> _finish(
    TerminalEnvironmentRequest? request,
    Map<String, String> environment,
  ) => request?.finish(environment) ?? environment;

  static Future<TerminalProfiles> terminalProfiles({Object? configured}) async {
    final os = _os;
    final base = await ClaudeEnvironment.of();
    String? shells;
    if (os != TerminalOs.windows) {
      try {
        shells = await File('/etc/shells').readAsString();
      } on FileSystemException {
        shells = null;
      }
    }
    return (
      profiles: detectTerminalProfiles(
        os,
        base,
        exists: _exists,
        list: _list,
        etcShells: shells,
        configured: configured,
      ),
      systemShell: defaultTerminalShell(os, base, exists: _exists, list: _list),
    );
  }

  /// Hangs up every terminal this run started, and waits (up to [timeout]
  /// each) for its process to end: killed if it does not.
  static Future<void> stopAll({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    await Future.wait([
      for (final pty in [..._live]) _stop(pty, timeout),
    ]);
    // Their entries gone from the list before the app is.
    await registry.flush();
  }

  static Future<void> _stop(Pty pty, Duration timeout) async {
    pty.kill();
    try {
      await pty.exitCode.timeout(timeout);
    } on TimeoutException {
      pty.kill(PtySignal.kill);
      await pty.exitCode.timeout(timeout, onTimeout: () => 0);
    }
  }

  static Future<void> reapLeftovers() => registry.reaped;
}
