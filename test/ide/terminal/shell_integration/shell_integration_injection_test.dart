/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/platform/terminal/test/node/terminalEnvironment.test.ts
// (`getShellIntegrationInjection`; `sanitizeEnvForLogging` is not ported).
//
// Upstream runs the pwsh suites on Windows only and the zsh and bash suites
// off it, on the machine's own paths; here the platform, the scripts folder,
// the zsh folder and the home folder are passed in, so every suite runs
// everywhere, on fixed paths. Cases marked "New: not upstream" cover the
// fish, Windows and launch parts the upstream suites leave out.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/terminal/pty.dart';
import 'package:monad/ide/terminal/shell_integration/shell_integration_injection.dart';
import 'package:monad/ide/terminal/terminal_shell.dart';

const _root = '/app/shell-integration';
const _zdotdir = '/tmp/monad-shell-integration-x/zsh';
const _home = '/home/me';

ShellIntegrationInjectionResult _inject(
  String executable,
  Object? args, {
  bool enabled = true,
  bool isFeatureTerminal = false,
  bool? forceShellIntegration,
  String nonce = '',
  Map<String, String>? env = const {},
  TerminalOs os = TerminalOs.linux,
  int windowsBuildNumber = 22631,
}) => getShellIntegrationInjection(
  executable: executable,
  args: args,
  enabled: enabled,
  isFeatureTerminal: isFeatureTerminal,
  forceShellIntegration: forceShellIntegration ?? false,
  nonce: nonce,
  env: env,
  os: os,
  scriptRoot: os == TerminalOs.windows ? r'C:\app\scripts' : _root,
  zdotdir: _zdotdir,
  home: _home,
  windowsBuildNumber: windowsBuildNumber,
);

/// Upstream `deepStrictEqualIgnoreStableVar`: the result, without
/// `VSCODE_STABLE`.
void _expectInjection(
  ShellIntegrationInjectionResult actual,
  List<String> newArgs,
  Map<String, String> envMixin,
) {
  expect(actual, isA<ShellIntegrationConfigInjection>());
  final injection = actual as ShellIntegrationConfigInjection;
  expect(injection.newArgs, newArgs);
  expect({...?injection.envMixin}..remove('VSCODE_STABLE'), envMixin);
  expect(injection.filesToCopy, isNull);
}

void _expectFailure(
  ShellIntegrationInjectionResult actual, [
  ShellIntegrationInjectionFailureReason? reason,
]) {
  expect(actual, isA<ShellIntegrationInjectionFailure>());
  if (reason != null) {
    expect((actual as ShellIntegrationInjectionFailure).reason, reason);
  }
}

void main() {
  group('getShellIntegrationInjection', () {
    group('should not enable', () {
      test('when isFeatureTerminal or when no executable is provided', () {
        _expectFailure(
          _inject('pwsh', ['-l', '-NoLogo'], isFeatureTerminal: true),
          ShellIntegrationInjectionFailureReason.featureTerminal,
        );
        expect(
          _inject('pwsh', ['-l', '-NoLogo']),
          isA<ShellIntegrationConfigInjection>(),
        );
        _expectFailure(
          _inject('', null),
          ShellIntegrationInjectionFailureReason.noExecutable,
        );
      });
    });

    for (final os in [TerminalOs.linux, TerminalOs.windows]) {
      final windows = os == TerminalOs.windows;
      final pwshExe = windows ? 'pwsh.exe' : 'pwsh';
      final expectedPs1 = windows
          ? r'try { . "C:\app\scripts\shellIntegration.ps1" } catch {}'
          : '. "$_root/shellIntegration.ps1"';
      ShellIntegrationInjectionResult pwsh(
        Object? args, {
        bool enabled = true,
      }) => _inject(pwshExe, args, enabled: enabled, os: os);

      group('pwsh (${os.name})', () {
        group('should override args', () {
          final expectedArgs = ['-noexit', '-command', expectedPs1];
          final expectedEnv = {
            'VSCODE_INJECTION': '1',
            if (windows) 'VSCODE_A11Y_MODE': '0',
          };
          test('when undefined, []', () {
            _expectInjection(pwsh(<String>[]), expectedArgs, expectedEnv);
            _expectInjection(pwsh(null), expectedArgs, expectedEnv);
          });
          group('when no logo', () {
            test('array - case insensitive', () {
              for (final arg in ['-NoLogo', '-NOLOGO', '-nol', '-NOL']) {
                _expectInjection(pwsh([arg]), expectedArgs, expectedEnv);
              }
            });
            test('string - case insensitive', () {
              for (final arg in ['-NoLogo', '-NOLOGO', '-nol', '-NOL']) {
                _expectInjection(pwsh(arg), expectedArgs, expectedEnv);
              }
            });
          });
        });
        group('should incorporate login arg', () {
          final expectedArgs = ['-l', '-noexit', '-command', expectedPs1];
          final expectedEnv = {
            'VSCODE_INJECTION': '1',
            if (windows) 'VSCODE_A11Y_MODE': '0',
          };
          test('when array contains no logo and login', () {
            _expectInjection(
              pwsh(['-l', '-NoLogo']),
              expectedArgs,
              expectedEnv,
            );
          });
          test('when string', () {
            _expectInjection(pwsh('-l'), expectedArgs, expectedEnv);
          });
        });
        group('should not modify args', () {
          test('when shell integration is disabled', () {
            _expectFailure(pwsh(['-l'], enabled: false));
            _expectFailure(pwsh('-l', enabled: false));
            _expectFailure(pwsh(null, enabled: false));
          });
          test('when using unrecognized arg', () {
            _expectFailure(pwsh(['-l', '-NoLogo', '-i'], enabled: false));
            // New: not upstream (upstream passes the disabled options here).
            _expectFailure(
              pwsh(['-l', '-NoLogo', '-i']),
              ShellIntegrationInjectionFailureReason.unsupportedArgs,
            );
          });
          test('when using unrecognized arg (string)', () {
            _expectFailure(pwsh('-i', enabled: false));
            // New: not upstream.
            _expectFailure(
              pwsh('-i'),
              ShellIntegrationInjectionFailureReason.unsupportedArgs,
            );
          });
        });
      });
    }

    group('zsh', () {
      group('should override args', () {
        const customZdotdir = '/custom/zsh/dotdir';
        const expectedDests = [
          '$_zdotdir/.zshrc',
          '$_zdotdir/.zprofile',
          '$_zdotdir/.zshenv',
          '$_zdotdir/.zlogin',
        ];
        const expectedSources = [
          '$_root/shellIntegration-rc.zsh',
          '$_root/shellIntegration-profile.zsh',
          '$_root/shellIntegration-env.zsh',
          '$_root/shellIntegration-login.zsh',
        ];
        void assertIsEnabled(
          ShellIntegrationInjectionResult result, [
          String globalZdotdir = _home,
        ]) {
          final injection = result as ShellIntegrationConfigInjection;
          expect(injection.envMixin!.length, 3);
          expect(injection.envMixin!['ZDOTDIR'], _zdotdir);
          expect(injection.envMixin!['USER_ZDOTDIR'], globalZdotdir);
          expect(injection.envMixin!['VSCODE_INJECTION'], '1');
          expect(injection.filesToCopy!.length, 4);
          expect(injection.filesToCopy!.map((f) => f.dest), expectedDests);
          expect(injection.filesToCopy!.map((f) => f.source), expectedSources);
        }

        test('when undefined, []', () {
          final result1 = _inject('zsh', <String>[]);
          expect((result1 as ShellIntegrationConfigInjection).newArgs, ['-i']);
          assertIsEnabled(result1);
          final result2 = _inject('zsh', null);
          expect((result2 as ShellIntegrationConfigInjection).newArgs, ['-i']);
          assertIsEnabled(result2);
        });
        group('should incorporate login arg', () {
          test('when array', () {
            final result = _inject('zsh', ['-l']);
            expect((result as ShellIntegrationConfigInjection).newArgs, [
              '-il',
            ]);
            assertIsEnabled(result);
          });
          // New: not upstream.
          test('when --login, and alongside -i', () {
            for (final args in [
              ['--login'],
              ['-i', '-l'],
              ['-l', '--interactive'],
            ]) {
              final result = _inject('/bin/zsh', args);
              expect((result as ShellIntegrationConfigInjection).newArgs, [
                '-il',
              ]);
            }
          });
        });
        group('should not modify args', () {
          test('when shell integration is disabled', () {
            _expectFailure(_inject('zsh', ['-l'], enabled: false));
            _expectFailure(_inject('zsh', null, enabled: false));
          });
          test('when using unrecognized arg', () {
            _expectFailure(_inject('zsh', ['-l', '-fake'], enabled: false));
            // New: not upstream.
            _expectFailure(
              _inject('zsh', ['-l', '-fake']),
              ShellIntegrationInjectionFailureReason.unsupportedArgs,
            );
            _expectFailure(
              _inject('zsh', ['-c', 'echo hi']),
              ShellIntegrationInjectionFailureReason.unsupportedArgs,
            );
          });
        });
        group('should incorporate global ZDOTDIR env variable', () {
          test('when custom ZDOTDIR', () {
            final result1 = _inject(
              'zsh',
              <String>[],
              env: {'ZDOTDIR': customZdotdir},
            );
            expect((result1 as ShellIntegrationConfigInjection).newArgs, [
              '-i',
            ]);
            assertIsEnabled(result1, customZdotdir);
          });
          test('when undefined', () {
            final result1 = _inject('zsh', <String>[], env: null);
            expect((result1 as ShellIntegrationConfigInjection).newArgs, [
              '-i',
            ]);
            assertIsEnabled(result1);
          });
        });
      });
    });

    group('bash', () {
      group('forceShellIntegration', () {
        test('should inject when isFeatureTerminal is true but '
            'forceShellIntegration overrides it', () {
          expect(
            _inject(
              'bash',
              <String>[],
              isFeatureTerminal: true,
              forceShellIntegration: true,
            ),
            isA<ShellIntegrationConfigInjection>(),
          );
        });
        test('should not inject when isFeatureTerminal is true and '
            'forceShellIntegration is false', () {
          _expectFailure(
            _inject(
              'bash',
              <String>[],
              isFeatureTerminal: true,
              forceShellIntegration: false,
            ),
          );
        });
        test('should not inject when isFeatureTerminal is true and '
            'forceShellIntegration is not set', () {
          _expectFailure(_inject('bash', <String>[], isFeatureTerminal: true));
        });
      });
      group('should override args', () {
        test('when undefined, [], empty string', () {
          const expectedArgs = [
            '--init-file',
            '$_root/shellIntegration-bash.sh',
          ];
          const expectedEnv = {'VSCODE_INJECTION': '1'};
          _expectInjection(
            _inject('bash', <String>[]),
            expectedArgs,
            expectedEnv,
          );
          _expectInjection(_inject('bash', ''), expectedArgs, expectedEnv);
          _expectInjection(_inject('bash', null), expectedArgs, expectedEnv);
        });
        group('should set login env variable and not modify args', () {
          test('when array', () {
            _expectInjection(
              _inject('bash', ['-l']),
              ['--init-file', '$_root/shellIntegration-bash.sh'],
              {'VSCODE_INJECTION': '1', 'VSCODE_SHELL_LOGIN': '1'},
            );
          });
        });
        group('should not modify args', () {
          test('when shell integration is disabled', () {
            _expectFailure(_inject('bash', ['-l'], enabled: false));
            _expectFailure(_inject('bash', null, enabled: false));
          });
          test('when custom array entry', () {
            _expectFailure(_inject('bash', ['-l', '-i'], enabled: false));
            // New: not upstream.
            _expectFailure(
              _inject('bash', ['-c', 'ls']),
              ShellIntegrationInjectionFailureReason.unsupportedArgs,
            );
            _expectFailure(
              _inject('bash', ['--norc']),
              ShellIntegrationInjectionFailureReason.unsupportedArgs,
            );
          });
        });
      });
    });

    group('custom shell integration nonce', () {
      test('should fail for unsupported shell but nonce should still be '
          'available', () {
        final result = _inject('julia', ['-i'], nonce: 'custom-nonce-12345');
        _expectFailure(
          result,
          ShellIntegrationInjectionFailureReason.unsupportedShell,
        );
        // New: not upstream. The launch still gets the nonce, as
        // TerminalProcess.start gives it.
        final launch = applyShellIntegrationInjection(
          const PtyLaunch(
            executable: 'julia',
            arguments: ['-i'],
            workingDirectory: '/p',
            environment: {'PATH': '/bin'},
          ),
          result,
          nonce: 'custom-nonce-12345',
        );
        expect(launch.arguments, ['-i']);
        expect(launch.environment, {
          'PATH': '/bin',
          'VSCODE_NONCE': 'custom-nonce-12345',
        });
        expect(shellIntegrationNonce(launch), 'custom-nonce-12345');
      });
    });

    // New: not upstream.
    group('fish', () {
      const source =
          r'set -g __monad_term_program $TERM_PROGRAM; '
          r'set -gx TERM_PROGRAM vscode; '
          'source "$_root/shellIntegration.fish"; '
          r'set -gx TERM_PROGRAM $__monad_term_program; '
          'set -e __monad_term_program';
      test('sources the script with TERM_PROGRAM=vscode, login or not', () {
        _expectInjection(
          _inject('/opt/homebrew/bin/fish', null),
          ['--init-command', source],
          {'VSCODE_INJECTION': '1'},
        );
        _expectInjection(
          _inject('fish', ['-l'], os: TerminalOs.macOS),
          ['-l', '--init-command', source],
          {'VSCODE_INJECTION': '1'},
        );
      });
      test('does not take other arguments', () {
        _expectFailure(
          _inject('fish', ['--no-config']),
          ShellIntegrationInjectionFailureReason.unsupportedArgs,
        );
      });
    });

    // New: not upstream.
    group('Windows', () {
      test('needs ConPTY (build 18309)', () {
        _expectFailure(
          _inject(
            'pwsh.exe',
            null,
            os: TerminalOs.windows,
            windowsBuildNumber: 17763,
          ),
          ShellIntegrationInjectionFailureReason.unsupportedWindowsBuild,
        );
      });
      test('names shells in any case, and takes Windows PowerShell', () {
        expect(
          _inject(
            r'C:\WINDOWS\System32\WindowsPowerShell\v1.0\PowerShell.EXE',
            null,
            os: TerminalOs.windows,
          ),
          isA<ShellIntegrationConfigInjection>(),
        );
      });
      test('injects Git Bash as bash', () {
        _expectInjection(
          _inject(r'C:\Program Files\Git\bin\bash.exe', [
            '--login',
          ], os: TerminalOs.windows),
          ['--init-file', r'C:\app\scripts/shellIntegration-bash.sh'],
          {'VSCODE_INJECTION': '1', 'VSCODE_SHELL_LOGIN': '1'},
        );
      });
      test('has nothing for cmd, nor for zsh', () {
        for (final shell in ['cmd.exe', 'zsh.exe']) {
          _expectFailure(
            _inject(shell, null, os: TerminalOs.windows),
            ShellIntegrationInjectionFailureReason.unsupportedShell,
          );
        }
      });
    });

    // New: not upstream.
    test('sets VSCODE_STABLE and the nonce where upstream does', () {
      final bash =
          _inject('bash', null, nonce: 'n') as ShellIntegrationConfigInjection;
      expect(bash.envMixin, {
        'VSCODE_INJECTION': '1',
        'VSCODE_NONCE': 'n',
        'VSCODE_STABLE': '1',
      });
      final zsh =
          _inject('zsh', null, nonce: 'n') as ShellIntegrationConfigInjection;
      expect(zsh.envMixin, isNot(contains('VSCODE_STABLE')));
      expect(zsh.envMixin!['VSCODE_NONCE'], 'n');
    });
  });

  // New: not upstream.
  group('applyShellIntegrationInjection', () {
    const launch = PtyLaunch(
      executable: '/bin/zsh',
      arguments: ['-l'],
      workingDirectory: '/project',
      environment: {'PATH': '/usr/bin', 'TERM': 'xterm-256color'},
      columns: 100,
      rows: 30,
    );

    test('gives the new arguments and mixes the environment in', () {
      final injected = applyShellIntegrationInjection(
        launch,
        _inject('/bin/zsh', launch.arguments, nonce: 'abc'),
      );
      expect(injected.executable, '/bin/zsh');
      expect(injected.arguments, ['-il']);
      expect(injected.workingDirectory, '/project');
      expect(injected.columns, 100);
      expect(injected.rows, 30);
      expect(injected.environment, {
        'PATH': '/usr/bin',
        'TERM': 'xterm-256color',
        'VSCODE_INJECTION': '1',
        'VSCODE_NONCE': 'abc',
        'ZDOTDIR': _zdotdir,
        'USER_ZDOTDIR': _home,
      });
      expect(shellIntegrationNonce(injected), 'abc');
      // The launch it came from is left alone.
      expect(launch.environment, hasLength(2));
    });

    test('leaves a launch without a nonce alone after a failure', () {
      expect(
        identical(
          applyShellIntegrationInjection(
            launch,
            const ShellIntegrationInjectionFailure(
              ShellIntegrationInjectionFailureReason.unsupportedShell,
            ),
          ),
          launch,
        ),
        isTrue,
      );
      expect(shellIntegrationNonce(launch), '');
    });
  });

  // New: not upstream.
  test('generateShellIntegrationNonce makes version 4 UUIDs', () {
    final pattern = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    final random = Random(1);
    final nonces = {
      for (var i = 0; i < 100; i++) generateShellIntegrationNonce(random),
    };
    expect(nonces, hasLength(100));
    expect(nonces.every(pattern.hasMatch), isTrue);
    expect(pattern.hasMatch(generateShellIntegrationNonce()), isTrue);
  });
}
