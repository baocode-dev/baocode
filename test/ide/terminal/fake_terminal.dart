import 'package:monad/ide/terminal/pty.dart';
import 'package:monad/ide/terminal/terminal_instance.dart';

import 'fake_pty.dart';

/// What a test's terminal runs: a login zsh, as on macOS, on a [FakePty].
Future<PtyLaunch> fakeTerminalLaunch(
  String root, {
  int columns = 80,
  int rows = 24,
}) async => PtyLaunch(
  executable: '/bin/zsh',
  arguments: const ['-l'],
  workingDirectory: root,
  columns: columns,
  rows: rows,
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
  linkStat: (path) async => files[path],
  supported: supported,
);
