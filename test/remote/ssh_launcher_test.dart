@TestOn('mac-os || linux')
library;

import 'dart:convert';
import 'dart:io';

import 'package:bao_remote/client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../fixtures/lsp/fake_lsp.dart' show dartExecutable;

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
all="$*"
config=
while [ $# -gt 0 ]; do
  case "$1" in
    -G) config=1; shift ;;
    -o|-e|-p|-i|-F|-J|-l) shift 2 ;;
    -*) shift ;;
    *) break ;;
  esac
done
dest="$1"; shift
if [ -n "$config" ]; then
  # What ssh -G says: the config, the user's strictness as FAKE_STRICT.
  printf 'hostname %s\nport %s\nstricthostkeychecking %s\nuserknownhostsfile %s %s\n' \
    "$dest" "${FAKE_PORT:-22}" "${FAKE_STRICT:-ask}" "$HOME/.ssh/known_hosts" "$HOME/.ssh/known_hosts2"
  exit 0
fi
printf '%s\n' "$all" >> "$FAKE_LOG.args"
printf '%s\t%s\n' "$dest" "$*" >> "$FAKE_LOG"
case "$dest" in
  unreachable) echo "ssh: Could not resolve hostname unreachable: nodename nor servname provided, or not known" >&2; exit 255 ;;
  locked) echo "me@locked: Permission denied (publickey)." >&2; exit 255 ;;
  changed)
    echo "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@" >&2
    echo "@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @" >&2
    echo "Host key for changed has changed and you have requested strict checking." >&2
    echo "Host key verification failed." >&2
    exit 255 ;;
  strict) echo "Host key verification failed." >&2; exit 255 ;;
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
  stubborn)
    # As OpenSSH does: a prompt not answered taken as a wrong password,
    # and asked again, up to three times.
    denied="me@stubborn: Permission denied (publickey,password)."
    n=0
    while :; do
      n=$((n + 1))
      [ "$n" -gt 3 ] && { echo "$denied" >&2; exit 255; }
      echo asked >> "$FAKE_LOG.asks"
      pw=$("$SSH_ASKPASS" "me@stubborn's password: ")
      [ "$pw" = hunter2 ] && break
    done ;;
  stranger)
    # Learned without a word where told to, else asked.
    case "$all" in
      *StrictHostKeyChecking=accept-new*) echo "Warning: Permanently added 'stranger' (ED25519) to the list of known hosts." >&2 ;;
      *)
        answer=$("$SSH_ASKPASS" "The authenticity of host 'stranger' can't be established.
Are you sure you want to continue connecting (yes/no/[fingerprint])? ")
        [ "$answer" = yes ] || { echo "Host key verification failed." >&2; exit 255; } ;;
    esac ;;
esac
cd "$HOME" || exit 255
exec /bin/sh -c "$*"
''');
    // Beside it, as OpenSSH's tools are: the arguments it ran with.
    File(p.join(sandbox.path, 'ssh-keygen')).writeAsStringSync(r'''#!/bin/sh
printf '%s\n' "$*" >> "$FAKE_LOG.keygen"
''');
    for (final script in [
      fakeSsh,
      p.join(sandbox.path, 'ssh-keygen'),
      p.join(fakeBin, 'uname'),
    ]) {
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
exec '$dartExecutable' '${p.absolute('packages', 'bao_remote', 'bin', 'baocode_server.dart')}' --data "\$HOME/server-data" "\$@"
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
      matches(
        r'^\.baocode-server/1-abc/baocode-server --session [0-9a-f]{32}$',
      ),
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
    expect(commands(), [
      'sh -s',
      startsWith('.baocode-server/1-abc/baocode-server --session '),
    ]);
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
    expect(await failure('changed'), SshFailure.hostKeyChanged);
    expect(await failure('strict'), SshFailure.hostKey);
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

  test('cancelled, ssh is ended rather than left asking again', () async {
    final asked = <SshPrompt>[];
    final launcher = SshLauncher(
      ssh: fakeSsh,
      binaries: FakeBinaries('1', const {}),
      start: starter(),
      prompter: (prompt) async {
        asked.add(prompt);
        return null;
      },
    );
    await expectLater(
      launcher.connect(SshTarget.parse('stubborn')),
      throwsA(
        isA<SshConnectException>()
            .having((e) => e.failure, 'failure', SshFailure.authentication)
            .having((e) => e.message, 'message', contains('cancelled')),
      ),
    );
    expect(asked, hasLength(1));
    // Its askpass run once: ssh did not get to ask again.
    expect(File('${log.path}.asks').readAsLinesSync(), hasLength(1));
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('a host key it does not know is learned, not asked', () async {
    final asked = <SshPrompt>[];
    SshLauncher launcher({String? strict}) => SshLauncher(
      ssh: fakeSsh,
      binaries: FakeBinaries('1', const {}),
      start: starter(extra: {'FAKE_STRICT': ?strict}),
      prompter: (prompt) async {
        asked.add(prompt);
        return 'yes';
      },
    );
    // Past the key, to the server, of which there is no build here.
    await expectLater(
      launcher().connect(SshTarget.parse('stranger')),
      throwsA(
        isA<SshConnectException>().having(
          (e) => e.failure,
          'failure',
          SshFailure.server,
        ),
      ),
    );
    expect(asked, isEmpty);
    expect(
      File('${log.path}.args').readAsLinesSync(),
      everyElement(contains('StrictHostKeyChecking=accept-new')),
    );

    // The user's config says what to do with one: as it says, so refused
    // (ssh's question is not answered yes here).
    File('${log.path}.args').deleteSync();
    await expectLater(
      launcher(strict: 'true').connect(SshTarget.parse('stranger')),
      throwsA(
        isA<SshConnectException>().having(
          (e) => e.failure,
          'failure',
          SshFailure.hostKey,
        ),
      ),
    );
    expect(asked, isEmpty);
    expect(
      File('${log.path}.args').readAsStringSync(),
      isNot(contains('StrictHostKeyChecking')),
    );
  });

  test('a changed host key is forgotten, in the known_hosts files there '
      'are', () async {
    final launcher = SshLauncher(
      ssh: fakeSsh,
      binaries: FakeBinaries('1', const {}),
      start: starter(extra: {'FAKE_PORT': '2222'}),
    );
    final known = File(p.join(home.path, '.ssh', 'known_hosts'))
      ..createSync(recursive: true);
    await launcher.forgetHostKey(SshTarget.parse('changed'));
    expect(File('${log.path}.keygen').readAsLinesSync(), [
      '-R [changed]:2222 -f ${known.path}',
    ]);
  });

  test("ssh -G's known_hosts files, a space in one's path", () {
    final spaced = Directory(p.join(sandbox.path, 'John Doe'))..createSync();
    // A file where the path's first word ends: not taken for it.
    File(p.join(sandbox.path, 'John')).createSync();
    final first = File(p.join(spaced.path, 'known_hosts'))..createSync();
    final second = File(p.join(sandbox.path, 'known_hosts2'))..createSync();
    expect(
      SshLauncher.knownHostsFiles(
        '${first.path} ${p.join(sandbox.path, 'missing')} ${second.path}',
      ),
      [first.path, second.path],
    );
  });

  test('a lost connection is made again to the same session, what runs '
      'there carrying on; a session gone ends it', () async {
    final launcher = SshLauncher(
      ssh: fakeSsh,
      binaries: FakeBinaries('1-abc', {'linux-x64': serverScript()}),
      start: starter(),
      maxBackoff: const Duration(seconds: 1),
    );
    final connection = await launcher.connect(SshTarget.parse('dev'));
    final id = RegExp(r'--session ([0-9a-f]+)')
        .firstMatch(commands().last)!
        .group(1)!;
    final process = await connection.client.start('sh', [
      '-c',
      r'i=0; while [ $i -lt 40 ]; do echo $i; i=$((i+1)); sleep 0.05; done',
    ], login: false);
    final lines = <String>[];
    process.stdout
        .transform(const Utf8Decoder())
        .transform(const LineSplitter())
        .listen(lines.add);
    final changes = <bool>[];
    connection.changes.listen((_) => changes.add(connection.linked));

    // The bridge gone (ssh's end of it), as a network cut ends it.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await Process.run('pkill', ['-f', 'session $id']);
    expect(await process.exitCode.timeout(const Duration(seconds: 30)), 0);
    expect(lines, [for (var i = 0; i < 40; i++) '$i']);
    expect(changes, containsAllInOrder([false, true]));
    expect(connection.linked, isTrue);
    expect(
      commands().last,
      '.baocode-server/1-abc/baocode-server '
      '--session $id --resume',
    );

    // The daemon gone: nothing to resume.
    await Process.run('pkill', ['-f', 'daemon $id']);
    await connection.done.timeout(const Duration(seconds: 30));
    await connection.close();
  }, timeout: const Timeout(Duration(minutes: 2)));

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

  test('a WSL distribution: wsl.exe runs each command from its home, '
      'no ssh', () async {
    final fakeWsl = p.join(sandbox.path, 'wsl.exe');
    // As wsl.exe does: in the folder it was started from, unless told.
    File(fakeWsl).writeAsStringSync(r'''#!/bin/sh
printf '%s\n' "$*" >> "$FAKE_LOG.wsl"
[ "$WSL_UTF8" = 1 ] || exit 3
[ "$1 $2 $3 $4 $5" = "--distribution Ubuntu --exec sh -c" ] || exit 4
cd /
exec /bin/sh -c "$6"
''');
    Process.runSync('chmod', ['+x', fakeWsl]);
    final binaries = FakeBinaries('1-abc', {'linux-x64': serverScript()});
    final launcher = SshLauncher(
      ssh: p.join(sandbox.path, 'no-ssh'),
      wsl: fakeWsl,
      binaries: binaries,
      start: starter(),
    );
    final target = SshTarget.parse(SshTarget.wslHost('Ubuntu'));
    expect(target.wslDistro, 'Ubuntu');
    expect(SshTarget.parse('dev').wslDistro, isNull);
    expect(await launcher.hostKeyOptions(target), isEmpty);
    final connection = await launcher.connect(target);
    expect(connection.hello.home, home.path);
    File(p.join(home.path, 'note.txt')).writeAsStringSync('hi');
    expect(
      await connection.client.read(home.path, p.join(home.path, 'note.txt')),
      'hi',
    );
    await connection.close();
    expect(log.existsSync(), isFalse, reason: 'ssh never ran');
    expect(File('${log.path}.wsl').readAsLinesSync(), [
      '--distribution Ubuntu --exec sh -c cd && sh -s',
      startsWith('--distribution Ubuntu --exec sh -c cd && sh -c '),
      startsWith('--distribution Ubuntu --exec sh -c cd && .baocode-server/'),
    ]);

    // No WSL here.
    final missing = SshLauncher(
      ssh: 'ssh',
      wsl: p.join(sandbox.path, 'missing.exe'),
      binaries: binaries,
      start: starter(),
    );
    await expectLater(
      missing.connect(target),
      throwsA(
        isA<SshConnectException>().having(
          (error) => error.failure,
          'failure',
          SshFailure.wsl,
        ),
      ),
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  test("WSL's distributions as wsl.exe --list --quiet prints them", () {
    List<int> utf16(String text) => [
      0xFF, 0xFE, // A byte order mark, as some versions print.
      for (final unit in text.codeUnits) ...[unit & 0xFF, unit >> 8],
    ];
    const listed = 'Ubuntu-24.04\r\ndocker-desktop\r\nDebian\r\n';
    expect(wslDistributions(utf16(listed)), ['Ubuntu-24.04', 'Debian']);
    expect(wslDistributions(utf8.encode(listed)), ['Ubuntu-24.04', 'Debian']);
    expect(wslDistributions(const []), isEmpty);
    expect(SshLauncher.wslArguments('Debian', 'sh -s'), [
      '--distribution',
      'Debian',
      '--exec',
      'sh',
      '-c',
      'cd && sh -s',
    ]);
  });

  test('on Windows, passwords are asked of OpenSSH 8.4 and later', () {
    bool takes(String version) => SshLauncher.takesForcedAskpass(version);
    expect(takes('OpenSSH_for_Windows_8.1p1, LibreSSL 3.0.2'), isFalse);
    expect(takes('OpenSSH_for_Windows_8.6p1, LibreSSL 3.4.3'), isTrue);
    expect(takes('OpenSSH_for_Windows_9.5p1, LibreSSL 3.8.2'), isTrue);
    expect(takes('OpenSSH_8.4p1 Debian'), isTrue);
    expect(takes('OpenSSH_7.9p1'), isFalse);
    expect(takes('OpenSSH_10.2p1, LibreSSL 3.3.6'), isTrue);
    expect(takes('something else'), isFalse);
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
