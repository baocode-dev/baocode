// Connects to a WSL distribution as the app does (SshLauncher over
// wsl.exe), and goes through what a project there uses: the server put
// there and started, files, Git, a process, a terminal, a connection lost
// and made again, the session ended. On Windows, with WSL:
//
//   dart run packages/bao_remote/tool/wsl_e2e.dart <distribution> <server>
//
// <server> is the Linux build of the server for the distribution's
// processor (tool/build_remote_server.dart's baocode-server-linux-x64).
// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bao_remote/client.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln('Usage: wsl_e2e.dart <distribution> <server binary>');
    exit(64);
  }
  final [distro, server] = arguments;
  final binary = await File(server).readAsBytes();
  // A version of its own each run: the server is put there every time.
  final version = 'e2e-${DateTime.now().millisecondsSinceEpoch}';
  final launcher = SshLauncher(
    ssh: 'ssh',
    binaries: _Binaries(version, binary),
  );
  final target = SshTarget.parse(SshTarget.wslHost(distro));
  check(target.wslDistro == distro, 'the target names the distribution');
  final listed = await wslHosts();
  print('distributions: $listed');
  check(listed.contains(target.text), 'wsl --list has it');

  // One there is not: WSL's failure, said as such.
  try {
    await launcher.connect(SshTarget.parse(SshTarget.wslHost('no-such-e2e')));
    check(false, 'a missing distribution connected');
  } on SshConnectException catch (error) {
    print('missing: ${error.failure}: $error');
    check(error.failure == SshFailure.wsl, 'a missing one is WSL\'s failure');
  }

  final watch = Stopwatch()..start();
  final connection = await launcher.connect(
    target,
    onProgress: (message) => print('  … $message'),
  );
  final hello = connection.hello;
  print('connected in ${watch.elapsedMilliseconds} ms: ${hello.platform.os} '
      '${hello.platform.arch}, home ${hello.home}');
  check(hello.platform.os == 'linux', 'a Linux host');
  final client = connection.client;

  // Files.
  final root = '${hello.home}/wsl-e2e';
  await client.run('rm', ['-rf', root]);
  await client.create(root, root, directory: true);
  await client.writeBytes(root, '$root/a.txt', utf8.encode('héllo\nwsl\n'));
  check(await client.read(root, '$root/a.txt') == 'héllo\nwsl\n', 'read back');
  final listing = await client.walk(root);
  print('walk: ${listing.paths}');
  check(listing.paths.any((f) => f.endsWith('a.txt')), 'walk finds it');
  await client.rename(root, '$root/a.txt', '$root/b.txt');
  check(await client.stat('$root/b.txt') != null, 'renamed');

  // A process, its output and exit code.
  final uname = await client.run('uname', ['-a'], cwd: root);
  print('uname: ${uname.stdout.trim()}');
  check(uname.exitCode == 0, 'uname ran');

  // Git, where the distribution has it.
  final git = await client.run('sh', ['-c', 'command -v git'], cwd: root);
  if (git.exitCode == 0) {
    final init = await client.git(['init', '-q'], cwd: root);
    check(init.exitCode == 0, 'git init: ${init.stderr}');
    final status = await client.git(['status', '--porcelain'], cwd: root);
    print('git status: ${status.stdout.trim()}');
    check(status.stdout.contains('b.txt'), 'git sees the file');
  } else {
    print('git: not installed in $distro, skipped');
  }

  // A terminal.
  final pty = await client.startPty(cwd: root, shellIntegration: false);
  final said = StringBuffer();
  final output = pty.output.listen((bytes) {
    said.write(utf8.decode(bytes, allowMalformed: true));
  });
  pty.write(utf8.encode('echo "pty-$version" && pwd\n'));
  await _until(() => said.toString().contains(root), 'the terminal answers');
  pty.write(utf8.encode('exit\n'));
  print('pty exited: ${await pty.exitCode.timeout(const Duration(seconds: 10))}');
  await output.cancel();

  // The link cut (wsl.exe ended): made again, the session kept.
  final pid = hello.pid;
  print('cutting the link…');
  final lost = connection.changes.firstWhere((_) => !connection.linked);
  await _killWslBridge();
  await lost.timeout(const Duration(seconds: 40));
  print('lost; waiting for it to come back');
  await _until(() => connection.linked, 'linked again', seconds: 60);
  final again = await client.run('sh', ['-c', 'echo \$PPID']);
  print('linked again; the server is still $pid: ${again.exitCode == 0}');
  check(await client.read(root, '$root/b.txt') == 'héllo\nwsl\n',
      'the session kept its files');

  await client.run('rm', ['-rf', root]);
  await connection.close();
  print('closed. All checks passed in ${watch.elapsedMilliseconds} ms.');
  exit(0);
}

void check(bool ok, String what) {
  if (ok) return;
  stderr.writeln('FAILED: $what');
  exit(1);
}

Future<void> _until(
  bool Function() done,
  String what, {
  int seconds = 15,
}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (!done()) {
    if (DateTime.now().isAfter(end)) check(false, what);
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

/// Ends the wsl.exe the bridge runs in (this process's child), as a lost
/// link would.
Future<void> _killWslBridge() async {
  final result = await Process.run('powershell', [
    '-NoProfile',
    '-Command',
    "Get-CimInstance Win32_Process -Filter \"ParentProcessId=$pid and "
        "Name='wsl.exe'\" | ForEach-Object { Stop-Process -Id "
        r'$_.ProcessId -Force }',
  ]);
  if (result.exitCode != 0) print('kill: ${result.stderr}');
}

class _Binaries implements RemoteServerBinaries {
  _Binaries(this.version, this.binary);

  @override
  final String version;
  final List<int> binary;

  @override
  Future<List<int>?> read(String platform) async =>
      platform == 'linux-x64' || platform == 'linux-arm64' ? binary : null;
}
