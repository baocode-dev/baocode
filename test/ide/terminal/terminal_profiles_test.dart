import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/terminal/terminal_profiles.dart';
import 'package:monad/ide/terminal/terminal_shell.dart';

void main() {
  const macEnvironment = {
    'PATH': '/opt/homebrew/bin:/usr/bin:/bin',
    'SHELL': '/bin/zsh',
  };
  const macFiles = {
    '/bin/zsh',
    '/bin/bash',
    '/bin/sh',
    '/opt/homebrew/bin/fish',
    '/usr/local/bin/bash',
  };
  const etcShells =
      '# List of acceptable shells\n'
      '/bin/bash\n'
      '/bin/sh   # the POSIX one\n'
      '\n'
      '/bin/zsh\n'
      '/usr/local/bin/bash\n';

  List<TerminalProfile> mac({
    Object? configured,
    Set<String> files = macFiles,
  }) => detectTerminalProfiles(
    TerminalOs.macOS,
    macEnvironment,
    exists: files.contains,
    list: (_) => const [],
    etcShells: etcShells,
    configured: configured,
  );

  group('detectTerminalProfiles on macOS and Linux', () {
    test("lists /etc/shells' shells, detected, then the default profiles "
        "found on the PATH, as login shells on macOS", () {
      expect(mac(), const [
        TerminalProfile(name: 'bash', path: '/bin/bash', args: ['-l']),
        TerminalProfile(name: 'sh', path: '/bin/sh', isAutoDetected: true),
        TerminalProfile(name: 'zsh', path: '/bin/zsh', args: ['-l']),
        // A second bash of /etc/shells is named apart.
        TerminalProfile(
          name: 'bash (2)',
          path: '/usr/local/bin/bash',
          isAutoDetected: true,
        ),
        TerminalProfile(
          name: 'fish',
          path: '/opt/homebrew/bin/fish',
          args: ['-l'],
        ),
      ]);
    });

    test('a default profile whose shell is not there is left out; '
        'Linux starts none as a login shell', () {
      final linux = detectTerminalProfiles(
        TerminalOs.linux,
        const {'PATH': '/usr/bin:/bin'},
        exists: {'/usr/bin/zsh', '/usr/bin/tmux'}.contains,
        list: (_) => const [],
        etcShells: '/usr/bin/zsh\n',
      );
      expect(linux, const [
        TerminalProfile(name: 'zsh', path: '/usr/bin/zsh'),
        TerminalProfile(name: 'tmux', path: '/usr/bin/tmux'),
      ]);
    });

    test("the user's profiles: null takes one away, one with a path is "
        r'added or set, with ${env:…} resolved', () {
      final profiles = mac(
        configured: {
          'sh': null,
          'fish': null,
          'zsh': {
            'path': 'zsh',
            'args': ['-l', '-i'],
          },
          'Home bash': {r'path': r'${env:SHELL}', 'args': 'not a list'},
          'Nowhere': {'path': '/opt/none'},
          'No path': {'args': <Object?>[]},
        },
      );
      expect(profiles.map((profile) => profile.name), [
        'bash',
        'zsh',
        'bash (2)',
        'Home bash',
      ]);
      expect(
        profiles[1],
        const TerminalProfile(
          name: 'zsh',
          path: '/bin/zsh',
          args: ['-l', '-i'],
        ),
      );
      expect(
        profiles.last,
        const TerminalProfile(name: 'Home bash', path: '/bin/zsh'),
      );
    });

    test('the first of several paths that is there', () {
      final profiles = mac(
        configured: {
          'Brew zsh': {
            'path': ['/opt/homebrew/bin/zsh', '/bin/zsh'],
          },
        },
      );
      expect(profiles.last.path, '/bin/zsh');
    });
  });

  group('detectTerminalProfiles on Windows', () {
    const environment = {
      'Path': r'C:\Windows\System32;C:\Windows',
      'PATHEXT': '.COM;.EXE;.BAT;.CMD',
      'windir': r'C:\Windows',
      'ProgramFiles': r'C:\Program Files',
      'HOMEDRIVE': 'C:',
    };

    test('PowerShell, Command Prompt and Git Bash of the settings; the '
        'other detected ones apart', () {
      final profiles = detectTerminalProfiles(
        TerminalOs.windows,
        environment,
        exists: {
          r'C:\Program Files\PowerShell\7\pwsh.exe',
          r'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe',
          r'C:\Windows\System32\cmd.exe',
          r'C:\Program Files\Git\bin\bash.exe',
          r'C:\msys64\usr\bin\bash.exe',
        }.contains,
        list: (directory) => directory == r'C:\Program Files\PowerShell'
            ? const ['7', 'Modules']
            : const [],
      );
      expect(profiles, const [
        TerminalProfile(
          name: 'PowerShell',
          path: r'C:\Program Files\PowerShell\7\pwsh.exe',
        ),
        TerminalProfile(
          name: 'Windows PowerShell',
          path: r'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe',
          isAutoDetected: true,
        ),
        TerminalProfile(
          name: 'Git Bash',
          path: r'C:\Program Files\Git\bin\bash.exe',
          args: ['--login', '-i'],
        ),
        TerminalProfile(
          name: 'Command Prompt',
          path: r'C:\Windows\System32\cmd.exe',
        ),
        TerminalProfile(
          name: 'bash (MSYS2)',
          path: r'C:\msys64\usr\bin\bash.exe',
          args: ['--login', '-i'],
          isAutoDetected: true,
        ),
      ]);
    });

    test("a user's profile is found on the PATH, with its extensions; its "
        'args may be one string', () {
      final profiles = detectTerminalProfiles(
        TerminalOs.windows,
        environment,
        exists: {r'C:\Windows\System32\nu.exe'}.contains,
        list: (_) => const [],
        configured: {
          'Nushell': {'path': 'nu', 'args': '-l  --no-history'},
          'Git Bash': null,
        },
      );
      expect(profiles, const [
        TerminalProfile(
          name: 'Nushell',
          path: r'C:\Windows\System32\nu.exe',
          args: ['-l', '--no-history'],
        ),
      ]);
    });
  });

  group('terminalDefaultProfileName', () {
    final profiles = mac();
    const zsh = (executable: '/bin/zsh', arguments: ['-l']);

    test("the setting's profile when there is one", () {
      expect(
        terminalDefaultProfileName(profiles, setting: 'fish', systemShell: zsh),
        'fish',
      );
    });

    test("else the user's shell's, a profile of the settings first", () {
      expect(
        terminalDefaultProfileName(profiles, setting: 'nu', systemShell: zsh),
        'zsh',
      );
      expect(
        terminalDefaultProfileName(
          profiles,
          systemShell: (executable: '/usr/local/bin/bash', arguments: const []),
        ),
        'bash (2)',
      );
    });

    test("else the profile named as the user's shell; none without one", () {
      expect(
        terminalDefaultProfileName(
          profiles,
          systemShell: (executable: '/usr/bin/fish', arguments: const []),
        ),
        'fish',
      );
      expect(
        terminalDefaultProfileName(
          profiles,
          systemShell: (executable: '/bin/nu', arguments: const []),
        ),
        isNull,
      );
      expect(terminalDefaultProfileName(profiles), isNull);
    });
  });

  test('the settings name the system as VS Code does', () {
    expect(
      terminalDefaultProfileKey(TerminalOs.macOS),
      'terminal.integrated.defaultProfile.osx',
    );
    expect(
      terminalProfilesKey(TerminalOs.windows),
      'terminal.integrated.profiles.windows',
    );
    expect(terminalOsOf(TargetPlatform.linux), TerminalOs.linux);
    expect(terminalOsOf(TargetPlatform.macOS), TerminalOs.macOS);
    expect(terminalOsOf(TargetPlatform.windows), TerminalOs.windows);
  });

  test("a profile's shell is its path and arguments", () {
    const profile = TerminalProfile(
      name: 'zsh',
      path: '/bin/zsh',
      args: ['-l'],
    );
    expect(profile.shell.executable, '/bin/zsh');
    expect(profile.shell.arguments, ['-l']);
  });
}
