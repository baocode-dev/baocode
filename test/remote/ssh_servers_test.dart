import 'dart:io';

import 'package:bao_remote/client.dart';
import 'package:baocode/models/secret_store.dart';
import 'package:baocode/remote/ssh_host.dart';
import 'package:baocode/remote/ssh_passwords.dart';
import 'package:baocode/remote/ssh_server_form.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  const prod = SshServer(
    hostName: '10.0.0.5',
    port: 2222,
    user: 'deploy',
    auth: SshAuth.key,
    identityFile: '/keys/my key',
    jump: 'bastion',
  );
  const bastion = SshServer(
    hostName: 'bastion.example.com',
    user: 'ops',
    auth: SshAuth.password,
  );

  group('sshServersConfig', () {
    test('a Host each, a jump through another as a ProxyCommand to its '
        'Host, the includes last', () {
      final config = sshServersConfig(
        {'prod': prod, 'bastion': bastion},
        ssh: '/usr/bin/ssh',
        configFile: '/data/state/ssh config',
        includes: ['/home/me/.ssh/config'],
      );
      final prodAlias = sshServerAlias('prod');
      final bastionAlias = sshServerAlias('bastion');
      expect(config, contains('Host $prodAlias\n  HostName 10.0.0.5\n'));
      expect(config, contains('  Port 2222\n  User deploy\n'));
      expect(config, contains('  IdentityFile "/keys/my key"\n'));
      expect(config, contains('  IdentitiesOnly yes\n'));
      expect(
        config,
        contains(
          "  ProxyCommand exec '/usr/bin/ssh' -F '/data/state/ssh config' "
          "-W '[%h]:%p' '$bastionAlias'\n",
        ),
      );
      expect(
        config,
        contains('  PreferredAuthentications password,keyboard-interactive\n'),
      );
      expect(config.trim(), endsWith('Host *\nInclude /home/me/.ssh/config'));
    });

    test('a jump typed, with its port; one that goes round left out', () {
      final config = sshServersConfig(
        {
          'a': const SshServer(hostName: 'a.example', jump: 'me@gate:2200'),
          'b': const SshServer(hostName: 'b.example', jump: 'c'),
          'c': const SshServer(hostName: 'c.example', jump: 'b'),
        },
        ssh: 'ssh',
        configFile: '/cfg',
      );
      expect(config, contains("-W '[%h]:%p' '-p' '2200' 'me@gate'"));
      expect(RegExp('ProxyCommand').allMatches(config), hasLength(1));
    });

    test('on Windows: double quotes, forward slashes, % doubled', () {
      final config = sshServersConfig(
        {
          'w': const SshServer(
            hostName: 'w.example',
            auth: SshAuth.key,
            identityFile: r'C:\Users\Me\.ssh\id_ed25519',
            jump: 'j',
          ),
          'j': const SshServer(hostName: 'j.example'),
        },
        ssh: r'C:\Program Files\BaoCode\openssh\ssh.exe',
        configFile: r'C:\Users\Me\AppData\Roaming\baocode%\state\ssh_config',
        windows: true,
      );
      expect(config, contains('IdentityFile C:/Users/Me/.ssh/id_ed25519'));
      expect(
        config,
        contains(
          r'ProxyCommand "C:\Program Files\BaoCode\openssh\ssh.exe" -F '
          r'"C:\Users\Me\AppData\Roaming\baocode%%\state\ssh_config" '
          '-W [%h]:%p ${sshServerAlias('j')}',
        ),
      );
    });

    test('aliases: what ssh takes, one per host', () {
      final alias = sshServerAlias('root@1.2.3.4:22');
      expect(alias, matches(RegExp(r'^baocode-[A-Za-z0-9.-]+$')));
      expect(sshServerAlias('root@1.2.3.4:22'), alias);
      expect(sshServerAlias('root_1.2.3.4:22'), isNot(alias));
    });

    test('as ssh reads it', () async {
      final ssh = findSsh(Platform.environment);
      if (ssh == null) {
        markTestSkipped('no ssh here');
        return;
      }
      final dir = Directory.systemTemp.createTempSync('baocode ssh ');
      addTearDown(() => dir.deleteSync(recursive: true));
      // Windows' ssh refuses an included file others may write to, which
      // one in TEMP can be (a sandbox's group given it, say): the user's.
      if (Platform.isWindows) {
        Process.runSync('icacls', [
          dir.path,
          '/inheritance:r',
          '/grant:r',
          '${Platform.environment['USERNAME']}:(OI)(CI)F',
        ]);
      }
      final file = File(p.join(dir.path, 'ssh config'));
      // The user's config, for every server: not the last one's alone.
      final included = File(p.join(dir.path, 'user config'))
        ..writeAsStringSync('Host *\n  ServerAliveInterval 42\n');
      file.writeAsStringSync(
        sshServersConfig(
          {'prod': prod, 'bastion': bastion},
          ssh: ssh,
          configFile: file.path,
          includes: [p.join(dir.path, 'missing'), included.path],
          windows: Platform.isWindows,
        ),
      );
      final result = await Process.run(ssh, [
        '-G',
        '-F',
        file.path,
        sshServerAlias('prod'),
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      final out = '${result.stdout}'.replaceAll('\r\n', '\n');
      expect(out, contains('hostname 10.0.0.5\n'));
      expect(out, contains('port 2222\n'));
      expect(out, contains('user deploy\n'));
      expect(out, contains(RegExp(r'identityfile \S*/keys/my key\n')));
      expect(out, contains('stricthostkeychecking accept-new\n'));
      expect(out, contains('proxycommand '));
      expect(out, contains('serveraliveinterval 42\n'));
      expect(out, contains(sshServerAlias('bastion')));
    });
  });

  test('SshServer as JSON and back', () {
    expect(SshServer.fromJson(prod.toJson()), prod);
    expect(SshServer.fromJson(bastion.toJson()), bastion);
    expect(SshServer.fromJson({'hostName': ''}), isNull);
    expect(SshServer.fromJson('x'), isNull);
    expect(prod.address, 'deploy@10.0.0.5:2222');
    expect(bastion.address, 'ops@bastion.example.com');
  });

  test('an address typed is split up', () {
    expect(splitAddress('root@1.2.3.4:2222'), (
      user: 'root',
      host: '1.2.3.4',
      port: 2222,
    ));
    expect(splitAddress(' example.com '), (
      user: null,
      host: 'example.com',
      port: null,
    ));
    expect(splitAddress('fe80::1'), (user: null, host: 'fe80::1', port: null));
  });

  group('saved passwords', () {
    late MemorySecretStore secrets;
    late SshHosts hosts;

    setUp(() {
      secrets = MemorySecretStore();
      hosts = SshHosts(passwords: SshPasswords(secrets: secrets))
        ..savedServers = () => {'prod': prod, 'bastion': bastion};
    });

    String? idFor(String host, String text) =>
        hosts.passwords.savedIdOf!(SshPrompt(SshTarget.parse(host), text));

    test("the jump's password by the prompt's user@host; a key's own "
        'prompts left alone', () {
      expect(
        idFor('prod', "ops@bastion.example.com's password: "),
        SshPasswords.serverId('bastion'),
      );
      expect(
        idFor('prod', '(ops@bastion.example.com) Password: '),
        SshPasswords.serverId('bastion'),
      );
      // prod signs in with a key: its passphrase is asked as before.
      expect(idFor('prod', "Enter passphrase for key '/keys/my key': "), null);
      expect(idFor('prod', "deploy@10.0.0.5's password: "), null);
      expect(idFor('bastion', 'Password: '), SshPasswords.serverId('bastion'));
      expect(idFor('elsewhere', 'Password: '), null);
    });

    test('the form\'s password answers; refused, it is asked for', () async {
      final asked = <SshPrompt>[];
      hosts.passwords.ask = (prompt, {required keepable}) async {
        asked.add(prompt);
        return (answer: 'new', remember: true);
      };
      await hosts.passwords.keep(SshPasswords.serverId('bastion'), 'hunter2');
      final prompt = SshPrompt(SshTarget.parse('bastion'), 'Password: ');
      expect(await hosts.passwords.answer(prompt), 'hunter2');
      expect(asked, isEmpty);
      final again = SshPrompt(
        SshTarget.parse('bastion'),
        'Password: ',
        retry: true,
      );
      expect(await hosts.passwords.answer(again), 'new');
      expect(asked, hasLength(1));
      await hosts.passwords.signedIn('bastion');
      expect(await secrets.read(SshPasswords.serverId('bastion')), 'new');
    });
  });
}
