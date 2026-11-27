// Connecting for real: the system's ssh to sshd containers, the server built
// from the sources and put there. tool/ssh_e2e.sh starts them and runs this,
// BAOCODE_SSH_E2E naming its folder (the test key) and
// BAOCODE_REMOTE_SERVER_DIR the server it built. None of the user's
// known_hosts is touched: the hosts' keys go to a file of each test's.
// From another machine (Windows, say): BAOCODE_SSH_E2E_HOST the address of
// the one the containers are on (`tool/ssh_e2e.sh --up`).
@Tags(['ssh-e2e'])
library;

import 'dart:io';

import 'package:bao_remote/client.dart';
import 'package:baocode/models/secret_store.dart';
import 'package:baocode/remote/remote_binaries.dart';
import 'package:baocode/remote/ssh_host.dart';
import 'package:baocode/remote/ssh_passwords.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  final setup = Platform.environment['BAOCODE_SSH_E2E'];
  if (setup == null) {
    test('ssh end to end', () {}, skip: 'BAOCODE_SSH_E2E is not set');
    return;
  }
  final key = p.join(setup, 'testkey');
  final address = Platform.environment['BAOCODE_SSH_E2E_HOST'] ?? '127.0.0.1';
  final noFile = Platform.isWindows ? 'NUL' : '/dev/null';

  late Directory dir;
  late File knownHosts;
  late SshHosts hosts;
  late MemorySecretStore secrets;
  late List<SshPrompt> asked;
  late Map<String, String> answers;

  setUp(() async {
    // A space in it: the ProxyCommand's paths quoted.
    dir = await Directory.systemTemp.createTemp('bao e2e ');
    // Windows' ssh refuses an included file others may write to, which one
    // in TEMP can be (a sandbox's group given it, say): the user's.
    if (Platform.isWindows) {
      await Process.run('icacls', [
        dir.path,
        '/inheritance:r',
        '/grant:r',
        '${Platform.environment['USERNAME']}:(OI)(CI)F',
      ]);
    }
    knownHosts = File(p.join(dir.path, 'known_hosts'));
    // Of these hosts only, not the user's own.
    final isolated = File(p.join(dir.path, 'isolated.conf'))
      ..writeAsStringSync(
        'Host *\n'
        '  UserKnownHostsFile "${knownHosts.path}"\n'
        '  GlobalKnownHostsFile $noFile\n',
      );
    secrets = MemorySecretStore();
    asked = [];
    answers = {};
    hosts = SshHosts(
      passwords: SshPasswords(secrets: secrets),
      configFile: p.join(dir.path, 'ssh config'),
      configIncludes: [isolated.path],
    );
    hosts.passwords.ask = (prompt, {required keepable}) async {
      asked.add(prompt);
      final answer = answers.entries
          .where((entry) => prompt.text.contains(entry.key))
          .firstOrNull;
      return answer == null ? null : (answer: answer.value, remember: true);
    };
    hosts.savedServers = () => {
      'pw': SshServer(
        hostName: address,
        port: 2221,
        user: 'tester',
        auth: SshAuth.password,
      ),
      'key': SshServer(
        hostName: address,
        port: 2222,
        user: 'tester',
        auth: SshAuth.key,
        identityFile: key,
      ),
      'bastion': SshServer(
        hostName: address,
        port: 2223,
        user: 'ops',
        auth: SshAuth.password,
      ),
      'inner': SshServer(
        hostName: 'inner',
        user: 'tester',
        auth: SshAuth.key,
        identityFile: key,
        jump: 'bastion',
      ),
      'otp-bastion': SshServer(
        hostName: address,
        port: 2225,
        user: 'ops',
        auth: SshAuth.password,
      ),
      'mid-bastion': SshServer(
        hostName: 'bao-e2e-bastion',
        user: 'ops',
        auth: SshAuth.password,
        jump: 'otp-bastion',
      ),
      'inner-otp': SshServer(
        hostName: 'inner',
        user: 'fresh',
        auth: SshAuth.key,
        identityFile: key,
        jump: 'otp-bastion',
      ),
      'inner-3hop': SshServer(
        hostName: 'inner',
        user: 'tester',
        auth: SshAuth.key,
        identityFile: key,
        jump: 'mid-bastion',
      ),
    };
  });

  tearDown(() async {
    await hosts.closeAll();
    await dir.delete(recursive: true);
  });

  Future<String?> home(String host) async =>
      (await hosts[host].reconnect()).hello?.home;

  test('a password saved with the form signs in, nothing asked; the '
      'host key learned', () async {
    await hosts.passwords.keep(SshPasswords.serverId('pw'), 'pw-secret');
    expect(await home('pw'), '/home/tester');
    expect(asked, isEmpty);
    expect(knownHosts.readAsStringSync(), contains('[$address]:2221'));
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('a wrong one is asked again, and the answer kept', () async {
    await hosts.passwords.keep(SshPasswords.serverId('pw'), 'wrong');
    answers = {'tester@$address': 'pw-secret'};
    expect(await home('pw'), '/home/tester');
    expect(asked.first.retry, isTrue);
    expect(await secrets.read(SshPasswords.serverId('pw')), 'pw-secret');
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('a key file', () async {
    expect(await home('key'), '/home/tester');
    expect(asked, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 5)));

  test("through a jump host, its password the jump's own", () async {
    await hosts.passwords.keep(
      SshPasswords.serverId('bastion'),
      'bastion-secret',
    );
    expect(await home('inner'), '/home/tester');
    expect(asked, isEmpty);
    final known = knownHosts.readAsStringSync();
    expect(known, contains('[$address]:2223'));
    expect(known, contains('inner'));
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('through a jump host with password + single-use OTP taking over 20s: '
      'probe, install and launch ask for the code once', () async {
    await hosts.passwords.keep(
      SshPasswords.serverId('otp-bastion'),
      'bastion-secret',
    );
    var nextCode = 100001;
    var otpAsks = 0;
    hosts.passwords.ask = (prompt, {required keepable}) async {
      asked.add(prompt);
      if (prompt.text.toLowerCase().contains('verification code')) {
        expect(keepable, isFalse);
        otpAsks++;
        // Exceeds the old ConnectTimeout=20 on the outer ssh.
        if (otpAsks == 1) {
          await Future<void>.delayed(const Duration(seconds: 23));
        }
        return (answer: '${nextCode++}', remember: false);
      }
      return null;
    };
    // First connect: fresh user has no server installed yet; probe + upload +
    // start must all share one ssh connection and ask for OTP exactly once.
    expect(await home('inner-otp'), '/home/fresh');
    expect(otpAsks, 1);

    // Close and connect again: on POSIX, otp-bastion's ControlMaster is reused
    // so no second OTP is asked; on Windows (no ControlMaster), one OTP.
    await hosts['inner-otp'].close();
    expect(await home('inner-otp'), '/home/fresh');
    expect(otpAsks, Platform.isWindows ? 2 : 1);
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('3-hop chain (OTP jump -> server -> container): inner disconnect '
      'resumes without re-entering jump-host OTP', () async {
    if (Platform.isWindows) {
      markTestSkipped('OpenSSH ControlMaster is POSIX-only');
      return;
    }
    await hosts.passwords.keep(
      SshPasswords.serverId('otp-bastion'),
      'bastion-secret',
    );
    await hosts.passwords.keep(
      SshPasswords.serverId('mid-bastion'),
      'bastion-secret',
    );
    var otpAsks = 0;
    hosts.passwords.ask = (prompt, {required keepable}) async {
      asked.add(prompt);
      if (prompt.text.toLowerCase().contains('verification code')) {
        expect(keepable, isFalse);
        otpAsks++;
        // Read current expected OTP sequence from the container so the test
        // does not depend on previous test ordering.
        final seq = await Process.run('docker', [
          'exec',
          'bao-e2e-otp-bastion',
          'cat',
          '/run/otp_seq',
        ]);
        return (answer: '${seq.stdout}'.trim(), remember: false);
      }
      return null;
    };

    final client = await hosts['inner-3hop'].reconnect();
    expect(client.hello?.home, '/home/tester');
    expect(otpAsks, 1);

    // Kill the inner container's SSH session bridge (simulating a drop on
    // container c while jump host a stays alive): must reconnect seamlessly
    // over jump-host ControlMaster without asking OTP again.
    await Process.run('docker', [
      'exec',
      'bao-e2e-inner',
      'pkill',
      '-f',
      'baocode-server --session',
    ]);
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (hosts['inner-3hop'].state == SshHostState.connected &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    while (hosts['inner-3hop'].state != SshHostState.connected &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(hosts['inner-3hop'].state, SshHostState.connected);
    expect(identical(hosts['inner-3hop'].client, client), isTrue);
    expect(
      await client.read('/home/tester', '/etc/hostname'),
      isNotEmpty,
    );
    expect(otpAsks, 1);
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('a changed host key refused; forgotten, connected again', () async {
    // What another server had at that address.
    await knownHosts.writeAsString(
      '[$address]:2222 ssh-ed25519 '
      'AAAAC3NzaC1lZDI1NTE5AAAAIIFetdDxUXXO7WNv9DqQSQuQpNonyVg4CGLLkSRXFEyU\n',
    );
    await expectLater(
      hosts['key'].reconnect(),
      throwsA(
        isA<SshConnectException>().having(
          (e) => e.failure,
          'failure',
          SshFailure.hostKeyChanged,
        ),
      ),
    );
    await hosts.forgetHostKey('key');
    expect(knownHosts.readAsStringSync(), isNot(contains('IIFetdDx')));
    expect(await home('key'), '/home/tester');
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('a host typed, not saved: as before, its password asked', () async {
    final ssh = findSsh(Platform.environment)!;
    final binaries = bundledServerBinaries()!;
    final launcher = SshLauncher(
      ssh: ssh,
      binaries: binaries,
      options: [
        ...SshLauncher.defaultOptions,
        '-o',
        'UserKnownHostsFile="${knownHosts.path}"',
        '-o',
        'GlobalKnownHostsFile=$noFile',
      ],
      prompter: (prompt) async {
        asked.add(prompt);
        return 'pw-secret';
      },
    );
    final connection = await launcher.connect(
      SshTarget.parse('tester@$address:2221'),
    );
    expect(connection.hello.home, '/home/tester');
    expect(asked.first.text, contains("tester@$address's password"));
    await connection.close();
  }, timeout: const Timeout(Duration(minutes: 5)));
}
