@TestOn('mac-os || linux')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:baocode/ide/terminal/pty.dart';
import 'package:baocode/ide/terminal/shell_integration/shell_integration_files.dart';
import 'package:baocode/ide/terminal/terminal_shell.dart';
import 'package:baocode/kernel/claude_code/claude_environment.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;
  late Map<String, String> cached;
  late Set<String> integrationFolders;
  const timeout = Duration(seconds: 10);

  setUp(() {
    dir = Directory.systemTemp.createTempSync('baocode-terminal-environment-');
    integrationFolders = {};
    // 框架会继续执行其他清理，即使某一项失败；缓存最后重置。
    addTearDown(() => ClaudeEnvironment.use(null));
    addTearDown(() => dir.deleteSync(recursive: true));
    cached = {
      ...Platform.environment,
      'SHELL': '/bin/sh',
      'PATH': '${dir.path}/tools/old/bin:${Platform.environment['PATH'] ?? ''}',
      'BAOCODE_TEST_CACHE_ONLY': 'cached',
      'BAOCODE_TEST_KEEP': 'old',
      'BAOCODE_TEST_REMOVED': 'old',
      'BAOCODE_TEST_PROFILE': dir.path,
    };
    // 只替换当前测试 isolate 的解析缓存，不运行用户启动配置。
    ClaudeEnvironment.use(cached);
  });

  Future<PtyLaunch> prepare({
    TerminalShell? shell,
    TerminalEnvironmentRequest? environment,
    bool integration = false,
  }) async {
    if (integration) {
      // 先登记当前测试 isolate 创建的目录，启动或后续断言失败也能回收。
      final folder = ShellIntegrationFolder.app.path;
      if (integrationFolders.add(folder)) {
        addTearDown(() => Directory(folder).deleteSync(recursive: true));
      }
      expect(
        p.dirname(folder),
        Directory.systemTemp.resolveSymbolicLinksSync(),
      );
    }
    final launch = await terminalLaunch(
      dir.path,
      shell: shell,
      environment: environment,
      shellIntegration: integration,
    );
    if (integration) {
      expect(launch.environment!['VSCODE_INJECTION'], '1');
      if (p.basename(launch.executable) == 'zsh') {
        expect(
          launch.environment!['ZDOTDIR'],
          ShellIntegrationFolder.zdotdir(integrationFolders.single),
        );
      }
    }
    return launch;
  }

  Future<(Pty, StringBuffer)> start(
    TerminalShell shell, {
    bool integration = false,
  }) async {
    final launch = await prepare(
      shell: shell,
      environment: TerminalEnvironmentRequest(
        env: {
          'HOME': dir.path,
          'ZDOTDIR': dir.path,
          for (final name in ['ASSIGN', 'KEEP', 'REMOVED', 'ADDED'])
            'BAOCODE_TEST_$name': null,
        },
      ),
      integration: integration,
    );
    // 直接使用原生 PTY，不读写应用的进程登记表。
    final terminal = await spawnPty(launch);
    addTearDown(() async {
      terminal.writeText('exit\n');
      try {
        await terminal.exitCode.timeout(timeout);
      } on TimeoutException {
        terminal.kill(PtySignal.kill);
        await terminal.exitCode.timeout(timeout);
      }
    });
    final output = StringBuffer();
    final subscription = const Utf8Decoder(allowMalformed: true)
        .bind(terminal.output)
        .listen(output.write);
    addTearDown(subscription.cancel);
    return (terminal, output);
  }

  Future<List<String>> observe(
    (Pty, StringBuffer) terminal, {
    int index = 0,
  }) async {
    terminal.$1.writeText('bao_environment_state\n');
    final clock = Stopwatch()..start();
    final pattern = RegExp(r'__BAO_TEST_STATE__\|([^\r\n]+)');
    while (clock.elapsed < timeout) {
      final states = pattern.allMatches(terminal.$2.toString()).toList();
      if (states.length > index) {
        return states[index].group(1)!.split('|');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    throw TimeoutException('isolated shell did not report its state');
  }

  test(
    'known interactive login shells do not inherit the CLI snapshot',
    () async {
      for (final name in ['bash', 'zsh', 'fish']) {
        for (final args in const [
          ['-l'],
          ['--login'],
          ['-i', '-l'],
          ['-l', '-i'],
          ['-il'],
          ['-li'],
        ]) {
          final launch = await prepare(
            shell: (executable: '/bin/$name', arguments: args),
          );
          // 比较布尔值，失败时不把进程的真实环境值打印到日志。
          expect(
            launch.environment!['PATH'] == Platform.environment['PATH'],
            isTrue,
            reason: '$name $args',
          );
          expect(
            launch.environment!['BAOCODE_TEST_CACHE_ONLY'] ==
                Platform.environment['BAOCODE_TEST_CACHE_ONLY'],
            isTrue,
          );
          expect(launch.executable, '/bin/$name');
          expect(launch.arguments, args);
        }
      }
      expect(identical(await ClaudeEnvironment.of(), cached), isTrue);
    },
  );

  test(
    'non-login and special launches retain the resolved environment',
    () async {
      for (final shell in const <TerminalShell>[
        (executable: '/bin/bash', arguments: []),
        (executable: '/bin/bash', arguments: ['-i']),
        (executable: '/bin/bash', arguments: ['--noprofile', '-l']),
        (executable: '/bin/zsh', arguments: ['-f', '-l']),
        (executable: '/bin/fish', arguments: ['--no-config', '--login']),
        (executable: '/bin/bash', arguments: ['-c', 'echo', '--login']),
        (executable: '/bin/bash', arguments: ['-L']),
        (executable: '/custom/shell', arguments: ['--login']),
      ]) {
        final launch = await prepare(shell: shell);
        expect(launch.environment!['PATH'] == cached['PATH'], isTrue);
        expect(launch.environment!['BAOCODE_TEST_CACHE_ONLY'], 'cached');
        expect(launch.executable, shell.executable);
        expect(launch.arguments, shell.arguments);
      }
      expect(identical(await ClaudeEnvironment.of(), cached), isTrue);
    },
  );

  test('default shell retains its startup environment contract', () async {
    final os = Platform.isMacOS ? TerminalOs.macOS : TerminalOs.linux;
    TerminalShell from(Map<String, String> env) => defaultTerminalShell(
      os,
      env,
      exists: (path) => File(path).existsSync(),
      list: (_) => const [],
    );
    final original = from(Platform.environment);
    final login =
        Platform.isMacOS &&
        const {
          'bash',
          'zsh',
          'fish',
        }.contains(p.basename(original.executable)) &&
        original.arguments.contains('-l');
    final expected = login ? original : from(cached);
    final launch = await prepare();
    expect(launch.executable, expected.executable);
    expect(launch.arguments, expected.arguments);
    expect(
      launch.environment!['PATH'] ==
          (login ? Platform.environment['PATH'] : cached['PATH']),
      isTrue,
    );
    if (Platform.isMacOS) {
      // 解析结果可能把非登录候选改为登录 shell，环境须服从最终选择。
      cached['SHELL'] = '/bin/zsh';
      final selected = await prepare();
      expect(
        selected.environment!['PATH'] == Platform.environment['PATH'],
        isTrue,
      );
      expect(selected.arguments, contains('-l'));
    }
  });

  test(
    'explicit shell, environment and extension order are preserved',
    () async {
      final launch = await prepare(
        shell: (executable: '/bin/sh', arguments: const ['-c', 'exit']),
        environment: TerminalEnvironmentRequest(
          env: const {
            'PATH': '/chosen/bin',
            'BAOCODE_TEST_KEEP': 'chosen',
            'BAOCODE_TEST_REMOVED': null,
          },
          mutate: (environment) {
            expect(environment['TERM_PROGRAM'], terminalProgram);
            expect(environment['BAOCODE_TEST_KEEP'], 'chosen');
            environment['BAOCODE_TEST_KEEP'] = 'mutated';
          },
        ),
      );
      expect(launch.executable, '/bin/sh');
      expect(launch.arguments, ['-c', 'exit']);
      expect(launch.environment!['PATH'], '/chosen/bin');
      expect(launch.environment!['BAOCODE_TEST_KEEP'], 'mutated');
      expect(launch.environment!.containsKey('BAOCODE_TEST_REMOVED'), isFalse);
      expect(launch.environment!['BAOCODE_TEST_CACHE_ONLY'], 'cached');
    },
  );

  test(
    'strict environment inherits neither base nor extension changes',
    () async {
      final launch = await prepare(
        environment: TerminalEnvironmentRequest(
          strict: true,
          env: const {'BAOCODE_TEST_KEEP': 'strict'},
          mutate: (_) => fail('strict environment must not run mutators'),
        ),
      );
      expect(launch.environment!['BAOCODE_TEST_KEEP'], 'strict');
      expect(launch.environment!.containsKey('PATH'), isFalse);
      expect(launch.environment!.containsKey('HOME'), isFalse);
      expect(
        launch.environment!.containsKey('BAOCODE_TEST_CACHE_ONLY'),
        isFalse,
      );
      expect(launch.environment!['TERM_PROGRAM'], terminalProgram);
    },
  );

  test(
    'custom profile lookup and launch retain shell-resolved values',
    () async {
      File(p.join(dir.path, 'profile-shell')).writeAsStringSync('');
      final detected = await terminalProfiles(
        configured: const {
          'test-profile': {
            'path': r'${env:BAOCODE_TEST_PROFILE}/profile-shell',
            'args': ['--custom'],
          },
        },
      );
      final profile = detected.profiles.singleWhere(
        (p) => p.name == 'test-profile',
      );
      final launch = await prepare(shell: profile.shell);
      expect(launch.executable, p.join(dir.path, 'profile-shell'));
      expect(launch.arguments, ['--custom']);
      expect(launch.environment!['BAOCODE_TEST_PROFILE'], dir.path);
      expect(identical(await ClaudeEnvironment.of(), cached), isTrue);
    },
  );

  // 使用真正的交互 shell，不加 -c；输入只有函数名，不解析命令回显。
  for (final integration in [false, true]) {
    test('new PTYs read updated startup files; old PTY stays unchanged '
        '(shell integration: $integration)', () async {
      final release = File(p.join(dir.path, 'release'))
        ..writeAsStringSync('old');
      for (final version in ['old', 'new']) {
        final bin = Directory(p.join(dir.path, 'tools', version, 'bin'))
          ..createSync(recursive: true);
        final tool = File(p.join(bin.path, 'bao_environment_tool'))
          ..writeAsStringSync('#!/bin/sh\nprintf "$version\\n"\n');
        final chmod = await Process.run('/bin/chmod', ['700', tool.path]);
        expect(chmod.exitCode, 0);
      }
      File(p.join(dir.path, '.zshrc')).writeAsStringSync(r'''
unsetopt zle
PROMPT=''
RPROMPT=''
desired=$(<"$HOME/release")
export BAOCODE_TEST_ASSIGN="$desired"
if (( ! ${+BAOCODE_TEST_KEEP} )); then export BAOCODE_TEST_KEEP="$desired"; fi
if [[ "$desired" == old ]]; then export BAOCODE_TEST_REMOVED=old; fi
if [[ "$desired" == new ]]; then export BAOCODE_TEST_ADDED=new; fi
if [[ ":$PATH:" != *":$HOME/tools/"* ]]; then
  export PATH="$HOME/tools/$desired/bin:$PATH"
fi
bao_environment_state() {
  local tty=no
  [[ -t 0 && -t 1 ]] && tty=yes
  print -r -- "__BAO_TEST_STATE__|$BAOCODE_TEST_ASSIGN|${BAOCODE_TEST_KEEP-unset}|${BAOCODE_TEST_REMOVED-unset}|${BAOCODE_TEST_ADDED-unset}|$(bao_environment_tool)|${options[interactive]}|${options[login]}|$tty"
}
''');

      const shell = (executable: '/bin/zsh', arguments: ['-il']);
      const old = ['old', 'old', 'old', 'unset', 'old', 'on', 'on', 'yes'];
      final first = await start(shell, integration: integration);
      expect(await observe(first), old);
      release.writeAsStringSync('new');
      final second = await start(shell, integration: integration);
      expect(await observe(second), [
        'new',
        'new',
        'unset',
        'new',
        'new',
        'on',
        'on',
        'yes',
      ]);
      expect(await observe(first, index: 1), old);
      expect(identical(await ClaudeEnvironment.of(), cached), isTrue);
    }, skip: !File('/bin/zsh').existsSync());

    test('non-login Bash retains login-resolved values '
        '(shell integration: $integration)', () async {
      File(p.join(dir.path, '.bashrc')).writeAsStringSync(r'''
bao_environment_state() {
  local mode=non-login tty=no
  shopt -q login_shell && mode=login
  [[ -t 0 && -t 1 ]] && tty=yes
  printf '__BAO_TEST_STATE__|%s|%s|%s\n' "${BAOCODE_TEST_CACHE_ONLY-unset}" "$mode" "$tty"
}
''');
      final terminal = await start((
        executable: '/bin/bash',
        arguments: const [],
      ), integration: integration);
      expect(await observe(terminal), ['cached', 'non-login', 'yes']);
      expect(identical(await ClaudeEnvironment.of(), cached), isTrue);
    }, skip: !File('/bin/bash').existsSync());
  }
}
