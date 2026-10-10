@TestOn('mac-os || linux')
library;

import 'dart:convert';
import 'dart:io';

import 'package:bao_remote/client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'remote_harness.dart' show dartExecutable;

/// The server's builds, as files; [reads] counts what was asked for.
class FakeBinaries implements RemoteServerBinaries {
  FakeBinaries(this.version, this.files);

  @override
  final String version;
  final Map<String, List<int>> files;
  final reads = <String>[];

  @override
  Future<List<int>?> read(String platform) async {
    reads.add(platform);
    return files[platform];
  }
}

/// Connecting over a stand-in `ssh` that runs each command here, in a
/// home folder of its own, with a `uname` that says Linux: the probe, the
/// upload and the server's start, without a network.
void main() {
  late Directory sandbox;
  late Directory home;
  late File log;
  late String fakeSsh;
  late String fakeBin;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('baocode-ssh-');
    home = Directory(p.join(sandbox.path, 'home'))..createSync();
    log = File(p.join(sandbox.path, 'ssh.log'));
    fakeBin = p.join(sandbox.path, 'bin');
    Directory(fakeBin).createSync();
    File(p.join(fakeBin, 'uname')).writeAsStringSync(r'''#!/bin/sh
case "$1" in
  -s) echo "${FAKE_SYSTEM:-Linux}" ;;
  -m) echo "${FAKE_MACHINE:-x86_64}" ;;
  *) /usr/bin/uname "$@" ;;
esac
''');
    fakeSsh = p.join(sandbox.path, 'ssh');
    File(fakeSsh).writeAsStringSync(r'''#!/bin/sh
while [ $# -gt 0 ]; do
  case "$1" in
    -o|-e|-p|-i|-F|-J|-l) shift 2 ;;
    -*) shift ;;
    *) break ;;
  esac
done
dest="$1"; shift
printf '%s\t%s\n' "$dest" "$*" >> "$FAKE_LOG"
case "$dest" in
  unreachable) echo "ssh: Could not resolve hostname unreachable: nodename nor servname provided, or not known" >&2; exit 255 ;;
  locked) echo "me@locked: Permission denied (publickey)." >&2; exit 255 ;;
  changed) echo "Host key verification failed." >&2; exit 255 ;;
  secret)
    # Signs in with a password, asked up to three times.
    denied="me@secret: Permission denied (publickey,password)."
    [ -n "$SSH_ASKPASS" ] || { echo "$denied" >&2; exit 255; }
    n=0
    while :; do
      n=$((n + 1))
      [ "$n" -gt 3 ] && { echo "$denied" >&2; exit 255; }
      pw=$("$SSH_ASKPASS" "me@secret's password: ") || { echo "$denied" >&2; exit 255; }
      [ "$pw" = hunter2 ] && break
    done ;;
  stranger)
    answer=$("$SSH_ASKPASS" "The authenticity of host 'stranger' can't be established.
Are you sure you want to continue connecting (yes/no/[fingerprint])? ")
    [ "$answer" = yes ] || { echo "Host key verification failed." >&2; exit 255; } ;;
esac
cd "$HOME" || exit 255
exec /bin/sh -c "$*"
''');
    for (final script in [fakeSsh, p.join(fakeBin, 'uname')]) {
      Process.runSync('chmod', ['+x', script]);
    }
  });
  tearDown(() => sandbox.deleteSync(recursive: true));

  SshProcessStarter starter({Map<String, String> extra = const {}}) =>
      (executable, arguments, {environment}) => Process.start(
        executable,
        arguments,
        environment: {
          'HOME': home.path,
          'PATH': '$fakeBin:/usr/bin:/bin',
          'FAKE_LOG': log.path,
          ...extra,
          ...?environment,
        },
        includeParentEnvironment: false,
      );

  /// A "server build" that runs the real server from source.
  List<int> serverScript() => utf8.encode('''#!/bin/sh
exec '$dartExecutable' '${p.absolute('packages', 'bao_remote', 'bin', 'baocode_server.dart')}' --data "\$HOME/server-data"
''');

  List<String> commands() => log.existsSync()
      ? [for (final line in log.readAsLinesSync()) line.split('\t').last]
      : const [];

  test('probes, installs the server once, starts it and talks to it', () async {
    final binaries = FakeBinaries('1-abc', {'linux-x64': serverScript()});
    final launcher = SshLauncher(
      ssh: fakeSsh,
      binaries: binaries,
      start: starter(),
    );
    final progress = <String>[];
    final connection = await launcher.connect(
      SshTarget.parse('dev'),
      onProgress: progress.add,
    );
    expect(connection.hello.protocol, RemoteProtocol.version);
    expect(connection.hello.home, home.path);
    expect(connection.hello.dataDir, p.join(home.path, 'server-data'));
    final installed = File(
      p.join(home.path, '.baocode-server', '1-abc', 'baocode-server'),
    );
    expect(installed.existsSync(), isTrue);
    expect(installed.readAsBytesSync(), serverScript());
    expect(binaries.reads, ['linux-x64']);
    expect(progress.any((line) => line.contains('Installing')), isTrue);
    expect(commands(), [
      'sh -s',
      startsWith("sh -c 'mkdir -p .baocode-server/1-abc && gzip -dc >"),
      '.baocode-server/1-abc/baocode-server',
    ]);

    // It answers: a file there.
    File(p.join(home.path, 'note.txt')).writeAsStringSync('hi');
    expect(
      await connection.client.read(home.path, p.join(home.path, 'note.txt')),
      'hi',
    );
    await connection.close();
    await connection.done;

    // Again: already there, so not sent again.
    log.deleteSync();
    final again = await launcher.connect(SshTarget.parse('dev'));
    expect(binaries.reads, ['linux-x64']);
    expect(commands(), ['sh -s', '.baocode-server/1-abc/baocode-server']);
    await again.close();
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('ssh failures are told apart', () async {
    final launcher = SshLauncher(
      ssh: fakeSsh,
      binaries: FakeBinaries('1', const {}),
      start: starter(),
    );
    Future<SshFailure> failure(String host) async {
      try {
        await launcher.connect(SshTarget.parse(host));
      } on SshConnectException catch (error) {
        return error.failure;
      }
      fail('$host connected');
    }

    expect(await failure('unreachable'), SshFailure.unreachable);
    expect(await failure('locked'), SshFailure.authentication);
    expect(await failure('changed'), SshFailure.hostKey);
  });

  test('a password is asked for each ssh, again when refused', () async {
    final binaries = FakeBinaries('1-abc', {'linux-x64': serverScript()});
    final asked = <SshPrompt>[];
    var answers = ['wrong', 'hunter2'];
    final launcher = SshLauncher(
      ssh: fakeSsh,
      binaries: binaries,
      start: starter(),
      prompter: (prompt) async {
        asked.add(prompt);
        if (answers.isEmpty) return 'hunter2';
        return answers.removeAt(0);
      },
    );
    expect(
      launcher.arguments(SshTarget.parse('dev'), 'cmd'),
      contains('BatchMode=no'),
    );
    final connection = await launcher.connect(SshTarget.parse('secret'));
    expect(connection.hello.home, home.path);
    // The probe twice (the first refused), the upload, the server.
    expect(
      [for (final prompt in asked) prompt.retry],
      [false, true, false, false],
    );
    expect(asked.first.text, "me@secret's password: ");
    expect(asked.first.target.text, 'secret');
    await connection.close();

    // Cancelled: said so, nothing more asked.
    asked.clear();
    answers = [];
    final cancelling = SshLauncher(
      ssh: fakeSsh,
      binaries: binaries,
      start: starter(),
      prompter: (prompt) async {
        asked.add(prompt);
        return null;
      },
    );
    await expectLater(
      cancelling.connect(SshTarget.parse('secret')),
      throwsA(
        isA<SshConnectException>()
            .having((e) => e.failure, 'failure', SshFailure.authentication)
            .having((e) => e.message, 'message', contains('cancelled')),
      ),
    );
    expect(asked, hasLength(1));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a host key it does not know is refused, not asked', () async {
    final asked = <SshPrompt>[];
    final launcher = SshLauncher(
      ssh: fakeSsh,
      binaries: FakeBinaries('1', const {}),
      start: starter(),
      prompter: (prompt) async {
        asked.add(prompt);
        return 'yes';
      },
    );
    await expectLater(
      launcher.connect(SshTarget.parse('stranger')),
      throwsA(
        isA<SshConnectException>().having(
          (e) => e.failure,
          'failure',
          SshFailure.hostKey,
        ),
      ),
    );
    expect(asked, isEmpty);
  });

  test('a Mac is given the macOS build', () async {
    final binaries = FakeBinaries('1-abc', {'darwin-arm64': serverScript()});
    final launcher = SshLauncher(
      ssh: fakeSsh,
      binaries: binaries,
      start: starter(extra: {'FAKE_SYSTEM': 'Darwin', 'FAKE_MACHINE': 'arm64'}),
    );
    final connection = await launcher.connect(SshTarget.parse('mac'));
    expect(connection.hello.home, home.path);
    expect(binaries.reads, ['darwin-arm64']);
    await connection.close();

    // An Intel one, with no build for it: said so, nothing sent.
    log.deleteSync();
    final intel = SshLauncher(
      ssh: fakeSsh,
      binaries: FakeBinaries('2', const {}),
      start: starter(
        extra: {'FAKE_SYSTEM': 'Darwin', 'FAKE_MACHINE': 'x86_64'},
      ),
    );
    await expectLater(
      intel.connect(SshTarget.parse('mac')),
      throwsA(
        isA<SshConnectException>()
            .having((e) => e.failure, 'failure', SshFailure.server)
            .having((e) => e.message, 'message', contains('macOS x64')),
      ),
    );
    expect(commands(), ['sh -s']);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('platforms as the builds are named', () {
    expect(SshLauncher.platform('Linux', 'x86_64'), 'linux-x64');
    expect(SshLauncher.platform('Linux', 'aarch64'), 'linux-arm64');
    expect(SshLauncher.platform('Darwin', 'arm64'), 'darwin-arm64');
    expect(SshLauncher.platform('Darwin', 'x86_64'), 'darwin-x64');
    expect(SshLauncher.platform('FreeBSD', 'amd64'), isNull);
    expect(SshLauncher.describe('darwin-arm64'), 'macOS arm64');
    expect(SshLauncher.describe('linux-x64'), 'Linux x64');
  });

  test('a host other than Linux or macOS on x64 or arm64 is refused', () async {
    for (final (system, machine) in [
      ('FreeBSD', 'amd64'),
      ('Linux', 'i686'),
      ('Darwin', 'i386'),
    ]) {
      final launcher = SshLauncher(
        ssh: fakeSsh,
        binaries: FakeBinaries('1', const {}),
        start: starter(extra: {'FAKE_SYSTEM': system, 'FAKE_MACHINE': machine}),
      );
      await expectLater(
        launcher.connect(SshTarget.parse('dev')),
        throwsA(
          isA<SshConnectException>().having(
            (e) => e.failure,
            'failure',
            SshFailure.unsupported,
          ),
        ),
      );
    }
  });

  test('no build for the architecture: nothing is sent', () async {
    final launcher = SshLauncher(
      ssh: fakeSsh,
      binaries: FakeBinaries('1', const {}),
      start: starter(extra: {'FAKE_MACHINE': 'aarch64'}),
    );
    await expectLater(
      launcher.connect(SshTarget.parse('dev')),
      throwsA(
        isA<SshConnectException>().having(
          (e) => e.message,
          'message',
          contains('arm64'),
        ),
      ),
    );
    expect(commands(), ['sh -s']);
  });

  test('targets: aliases, users and ports', () {
    final plain = SshTarget.parse(' dev ');
    expect(plain.text, 'dev');
    expect(plain.arguments, ['dev']);
    final ported = SshTarget.parse('me@10.0.0.2:2222');
    expect(ported.destination, 'me@10.0.0.2');
    expect(ported.arguments, ['-p', '2222', 'me@10.0.0.2']);
    expect(SshTarget.isValid('dev box'), isFalse);
    expect(SshTarget.isValid('-oProxyCommand=x'), isFalse);
    expect(SshTarget.isValid('me@dev'), isTrue);
  });

  test('ssh runs with no prompts and keepalives', () {
    final launcher = SshLauncher(
      ssh: 'ssh',
      binaries: FakeBinaries('7', const {}),
    );
    final arguments = launcher.arguments(SshTarget.parse('dev'), 'cmd');
    expect(arguments, containsAllInOrder(['-T', '-o', 'BatchMode=yes']));
    expect(arguments, contains('ServerAliveInterval=15'));
    expect(arguments.sublist(arguments.length - 2), ['dev', 'cmd']);
    expect(launcher.serverPath, '.baocode-server/7/baocode-server');
    expect(launcher.uploadCommand('n', gzip: false), contains('cat >'));
  });

  group('ssh config', () {
    test('Host lines without patterns, Includes followed', () async {
      final ssh = Directory(p.join(home.path, '.ssh'))..createSync();
      File(p.join(ssh.path, 'config')).writeAsStringSync('''
# mine
Host dev dev-* !bad
  HostName 10.0.0.2
Host=prod "with space"
Include conf.d/*
Host *
  ServerAliveInterval 30
''');
      Directory(p.join(ssh.path, 'conf.d')).createSync();
      File(p.join(ssh.path, 'conf.d', 'work'))
          .writeAsStringSync('Host work\nHost dev\n');
      expect(await sshConfigHosts(home: home.path), [
        'dev',
        'prod',
        'with space',
        'work',
      ]);
    });

    test('none without a config', () async {
      expect(await sshConfigHosts(home: home.path), isEmpty);
    });
  });
}
