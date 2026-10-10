import 'package:baocode/ide/terminal/pty.dart';
import 'package:baocode/ide/terminal/terminal_instance.dart';
import 'package:baocode/ide/terminal/terminal_profiles.dart';
import 'package:baocode/ide/terminal/terminal_shell.dart';

import 'fake_pty.dart';

/// What a test's terminal runs: [shell] (a profile's), else a login zsh,
/// as on macOS, on a [FakePty].
Future<PtyLaunch> fakeTerminalLaunch(
  String root, {
  int columns = 80,
  int rows = 24,
  TerminalShell? shell,
  TerminalEnvironmentRequest? environment,
}) async => PtyLaunch(
  executable: shell?.executable ?? '/bin/zsh',
  arguments: shell?.arguments ?? const ['-l'],
  workingDirectory: root,
  // [fakeTerminalEnvironment] as asked; none unless asked.
  environment: environment?.finish(environment.merge(fakeTerminalEnvironment)),
  columns: columns,
  rows: rows,
);

/// The environment [fakeTerminalLaunch] changes as asked.
const fakeTerminalEnvironment = {'HOME': '/home/test', 'PATH': '/usr/bin'};

/// A test system's profiles: zsh (the user's shell), bash and fish, and sh
/// from /etc/shells; never the disk's.
Future<TerminalProfiles> fakeTerminalProfiles({Object? configured}) async => (
  profiles: detectTerminalProfiles(
    TerminalOs.macOS,
    const {'PATH': '/opt/homebrew/bin:/usr/bin:/bin', 'SHELL': '/bin/zsh'},
    exists: const {
      '/bin/zsh',
      '/bin/bash',
      '/bin/sh',
      '/opt/homebrew/bin/fish',
    }.contains,
    list: (_) => const [],
    etcShells: '# List of acceptable shells\n/bin/bash\n/bin/sh\n/bin/zsh\n',
    configured: configured,
  ),
  systemShell: (executable: '/bin/zsh', arguments: const ['-l']),
);

/// Terminals on fakes: each one started is added to [started]. Links'
/// paths are looked up in [files] (path to whether it is a folder), never
/// on the disk.
TerminalBackend fakeTerminalBackend(
  List<FakePty> started, {
  bool supported = true,
  Map<String, bool> files = const {},
}) => TerminalBackend(
  launch: fakeTerminalLaunch,
  start: FakePty.starter(started),
  detectProfiles: fakeTerminalProfiles,
  linkStat: (path) async => files[path],
  supported: supported,
);
