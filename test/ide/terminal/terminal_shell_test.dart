import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/terminal/terminal_shell.dart';

/// The shell and environment of a new terminal, as VS Code picks them.
void main() {
  void expectShell(
    TerminalShell shell,
    String executable,
    List<String> arguments,
  ) {
    expect(shell.executable, executable);
    expect(shell.arguments, arguments);
  }

  group('defaultTerminalShell on macOS and Linux', () {
    TerminalShell shell(
      TerminalOs os,
      Map<String, String> environment, {
      Set<String> files = const {'/bin/zsh', '/bin/sh', '/bin/bash'},
    }) => defaultTerminalShell(
      os,
      environment,
      exists: files.contains,
      list: (_) => const [],
    );

    test(r'is $SHELL, a login shell on macOS', () {
      expectShell(shell(TerminalOs.macOS, {'SHELL': '/bin/zsh'}), '/bin/zsh', [
        '-l',
      ]);
      expectShell(
        shell(TerminalOs.macOS, {'SHELL': '/opt/homebrew/bin/fish'}),
        '/opt/homebrew/bin/fish',
        ['-l'],
      );
      expectShell(
        shell(TerminalOs.linux, {'SHELL': '/bin/bash'}),
        '/bin/bash',
        [],
      );
    });

    test(r'without $SHELL, is zsh on macOS and sh on Linux', () {
      expectShell(shell(TerminalOs.macOS, {}), '/bin/zsh', ['-l']);
      expectShell(
        shell(TerminalOs.macOS, {'SHELL': ''}, files: {'/bin/sh'}),
        '/bin/sh',
        [],
      );
      expectShell(shell(TerminalOs.linux, {}), '/bin/sh', []);
    });

    test(r'is bash when $SHELL is /bin/false', () {
      expect(
        shell(TerminalOs.linux, {'SHELL': '/bin/false'}).executable,
        '/bin/bash',
      );
    });
  });

  test('terminalShellArguments follows the macOS profiles and fallback', () {
    List<String> arguments(String shell) =>
        terminalShellArguments(TerminalOs.macOS, shell);
    expect(arguments('/bin/bash'), ['-l']);
    expect(arguments('/bin/zsh'), ['-l']);
    expect(arguments('/usr/local/bin/fish'), ['-l']);
    expect(arguments('/usr/local/bin/tmux'), isEmpty);
    expect(arguments('/usr/local/bin/pwsh'), isEmpty);
    expect(arguments('/bin/sh'), isEmpty);
    expect(arguments('/usr/local/bin/nu'), isEmpty);
    // Not a profile of VS Code's, but named like one: its fallback.
    expect(arguments('/opt/bin/zsh5'), ['--login']);
    expect(terminalShellArguments(TerminalOs.linux, '/bin/zsh'), isEmpty);
  });

  group('defaultTerminalShell on Windows', () {
    const environment = {
      'ProgramFiles': r'C:\Program Files',
      'ProgramFiles(x86)': r'C:\Program Files (x86)',
      'LOCALAPPDATA': r'C:\Users\me\AppData\Local',
      'USERPROFILE': r'C:\Users\me',
      'windir': r'C:\Windows',
      'ComSpec': r'C:\Windows\system32\cmd.exe',
    };
    const windowsPowerShell =
        r'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe';

    TerminalShell shell(
      Set<String> files, {
      Map<String, List<String>> folders = const {},
      Map<String, String> environment = environment,
    }) => defaultTerminalShell(
      TerminalOs.windows,
      environment,
      exists: files.contains,
      list: (directory) => folders[directory] ?? const [],
    );

    test('is the newest PowerShell 7 in Program Files', () {
      expectShell(
        shell(
          {
            r'C:\Program Files\PowerShell\6\pwsh.exe',
            r'C:\Program Files\PowerShell\7\pwsh.exe',
            r'C:\Program Files\PowerShell\8-preview\pwsh.exe',
            windowsPowerShell,
          },
          folders: {
            r'C:\Program Files\PowerShell': ['6', '7', '8-preview', 'Modules'],
          },
        ),
        r'C:\Program Files\PowerShell\7\pwsh.exe',
        [],
      );
    });

    test('takes the Store PowerShell before a preview', () {
      const store =
          r'C:\Users\me\AppData\Local\Microsoft\WindowsApps'
          r'\Microsoft.PowerShell_8wekyb3d8bbwe\pwsh.exe';
      expect(
        shell(
          {
            store,
            r'C:\Program Files\PowerShell\7-preview\pwsh.exe',
            windowsPowerShell,
          },
          folders: {
            r'C:\Program Files\PowerShell': ['7-preview'],
            r'C:\Users\me\AppData\Local\Microsoft\WindowsApps': [
              'Microsoft.PowerShellPreview_8wekyb3d8bbwe',
              'Microsoft.PowerShell_8wekyb3d8bbwe',
            ],
          },
        ).executable,
        store,
      );
    });

    test('falls back to Windows PowerShell, then ComSpec', () {
      expect(shell({windowsPowerShell}).executable, windowsPowerShell);
      expect(shell({}).executable, r'C:\Windows\system32\cmd.exe');
      expect(shell({}, environment: const {}).executable, 'cmd.exe');
    });

    test('reads the environment in any case', () {
      expect(
        shell(
          {r'D:\Apps\PowerShell\7\pwsh.exe'},
          folders: {
            r'D:\Apps\PowerShell': ['7'],
          },
          environment: const {'PROGRAMFILES': r'D:\Apps'},
        ).executable,
        r'D:\Apps\PowerShell\7\pwsh.exe',
      );
    });
  });

  group('terminalEnvironment', () {
    test('adds what a terminal says about itself', () {
      final environment = terminalEnvironment(
        const {'PATH': '/usr/bin:/bin', 'HOME': '/Users/me'},
        os: TerminalOs.macOS,
        locale: 'en_US',
      );
      expect(environment, {
        'PATH': '/usr/bin:/bin',
        'HOME': '/Users/me',
        'TERM': 'xterm-256color',
        'TERM_PROGRAM': 'monad',
        'LANG': 'en_US.UTF-8',
        'COLORTERM': 'truecolor',
      });
    });

    test('does not claim to be VS Code, nor keep another terminal', () {
      final environment = terminalEnvironment(const {
        'TERM': 'dumb',
        'TERM_PROGRAM': 'vscode',
        'TERM_PROGRAM_VERSION': '1.99.0',
      }, os: TerminalOs.linux);
      expect(environment['TERM'], 'xterm-256color');
      expect(environment['TERM_PROGRAM'], 'monad');
      expect(environment, isNot(contains('TERM_PROGRAM_VERSION')));
      expect(
        terminalEnvironment(
          const {},
          os: TerminalOs.linux,
          version: '1.0.0',
        )['TERM_PROGRAM_VERSION'],
        '1.0.0',
      );
    });

    test('keeps a UTF-8 LANG and replaces any other', () {
      String? lang(String? lang) => terminalEnvironment(
        {'LANG': ?lang},
        os: TerminalOs.macOS,
        locale: 'zh-Hans-CN',
      )['LANG'];
      expect(lang('de_DE.UTF-8'), 'de_DE.UTF-8');
      expect(lang('en_GB.utf8'), 'en_GB.utf8');
      expect(lang('ja_JP.eucJP'), 'ja_JP.eucJP');
      expect(lang('C'), 'zh_CN.UTF-8');
      expect(lang(''), 'zh_CN.UTF-8');
      expect(lang(null), 'zh_CN.UTF-8');
    });

    test("leaves out Electron's and VS Code's own variables", () {
      final environment = terminalEnvironment(const {
        'ELECTRON_RUN_AS_NODE': '1',
        'VSCODE_IPC_HOOK_CLI': '/tmp/vscode.sock',
        'VSCODE_PORTABLE': '/portable',
        'SNAP': '/snap/code/1',
        'SNAP_NAME': 'code',
        'SNAPSHOT': 'kept',
        'GDK_PIXBUF_MODULE_FILE': '/snap/loaders.cache',
        'KEEP': 'me',
      }, os: TerminalOs.linux);
      expect(environment.keys, containsAll(['VSCODE_PORTABLE', 'SNAPSHOT']));
      expect(environment['KEEP'], 'me');
      for (final name in [
        'ELECTRON_RUN_AS_NODE',
        'VSCODE_IPC_HOOK_CLI',
        'SNAP',
        'SNAP_NAME',
        'GDK_PIXBUF_MODULE_FILE',
      ]) {
        expect(environment, isNot(contains(name)));
      }
    });

    test('on Windows sets no TERM, and keeps the case of names', () {
      final environment = terminalEnvironment(
        const {'Path': r'C:\Windows', 'Lang': 'C', 'Term_Program': 'x'},
        os: TerminalOs.windows,
        locale: 'fr',
      );
      expect(environment, {
        'Path': r'C:\Windows',
        'Lang': 'fr_FR.UTF-8',
        'Term_Program': 'monad',
        'COLORTERM': 'truecolor',
      });
    });

    test('leaves the base alone', () {
      final base = {'TERM': 'dumb'};
      terminalEnvironment(base, os: TerminalOs.linux);
      expect(base, {'TERM': 'dumb'});
    });
  });

  test('terminalLang makes LANG as VS Code does', () {
    expect(terminalLang(null), 'en_US.UTF-8');
    expect(terminalLang(''), 'en_US.UTF-8');
    expect(terminalLang('C'), 'en_US.UTF-8');
    expect(terminalLang('en'), 'en_US.UTF-8');
    expect(terminalLang('de'), 'de_DE.UTF-8');
    expect(terminalLang('pt'), 'pt_BR.UTF-8');
    expect(terminalLang('zh-cn'), 'zh_CN.UTF-8');
    expect(terminalLang('zh-tw'), 'zh_TW.UTF-8');
    expect(terminalLang('en_GB'), 'en_GB.UTF-8');
    expect(terminalLang('zh-Hans-CN'), 'zh_CN.UTF-8');
    expect(terminalLang('zh-Hant'), 'zh_TW.UTF-8');
    expect(terminalLang('es-419'), 'es_419.UTF-8');
    expect(terminalLang('en_US.UTF-8'), 'en_US.UTF-8');
    expect(terminalLang('de_DE@euro'), 'de_DE.UTF-8');
    expect(terminalLang('tlh'), 'tlh.UTF-8');
  });
}
