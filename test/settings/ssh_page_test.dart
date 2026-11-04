import 'dart:async';
import 'dart:io';

import 'package:bao_remote/client.dart';
import 'package:baocode/ide/ide_input.dart';
import 'package:baocode/l10n/l10n.dart';
import 'package:baocode/models/secret_store.dart';
import 'package:baocode/remote/remote_host_settings.dart';
import 'package:baocode/remote/ssh_host.dart';
import 'package:baocode/remote/ssh_passwords.dart';
import 'package:baocode/settings/pages/ssh_page.dart';
import 'package:baocode/workspace/preference_store.dart';
import 'package:baocode/workspace/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Settings → SSH Servers: the servers the app's form edits, added,
/// edited and removed there; ~/.ssh/config's listed as they are; and
/// whether each one's agents may act on this machine.
void main() {
  final previous = (SshHosts.instance, RemoteHostSettings.instance);
  late Workspace workspace;
  late MemorySecretStore secrets;
  late Directory dir;
  late RemoteHostSettings settings;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('baocode-ssh-page-');
    settings = RemoteHostSettings.instance = RemoteHostSettings(
      file: p.join(dir.path, 'remote-hosts.json'),
    );
    secrets = MemorySecretStore();
    SshHosts.instance = SshHosts(
      passwords: SshPasswords(secrets: secrets),
      // Never connected here.
      connect: (target, {onProgress}) => Completer<SshConnection>().future,
    );
    workspace = Workspace(preferences: MemoryPreferenceStore())
      ..saveSshServer(
        'prod',
        const SshServer(
          hostName: '10.0.0.5',
          user: 'deploy',
          auth: SshAuth.password,
          jump: 'bastion',
          core: SshCore.builtin,
        ),
        name: 'Production',
      )
      ..addSshHost('me@typed')
      ..addSshHost('bastion');
    SshHosts.instance.savedServers = () => workspace.sshServers;
  });
  tearDown(() {
    SshHosts.instance = previous.$1;
    RemoteHostSettings.instance = previous.$2;
    dir.deleteSync(recursive: true);
  });

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        home: Scaffold(
          body: SshSettingsPage(
            workspace: workspace,
            configHosts: () async => ['bastion', 'gpu'],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the servers as saved; ~/.ssh/config\'s apart, not edited '
      'here', (tester) async {
    await pumpPage(tester);
    // Each host is named again under whether it may act on this machine.
    expect(find.text('Production'), findsNWidgets(2));
    expect(
      find.text(
        'Not connected · deploy@10.0.0.5 · Password · through bastion · '
        'Core: Built-in',
      ),
      findsOneWidget,
    );
    expect(find.text('Not connected · As typed'), findsOneWidget);
    expect(find.text('Hosts of ~/.ssh/config'), findsOneWidget);
    // bastion is ~/.ssh/config's: listed there alone, with no Edit.
    expect(find.text('bastion'), findsNWidgets(2));
    expect(find.text('gpu'), findsNWidgets(2));
    expect(find.text('Edit…'), findsNWidgets(2));
  });

  testWidgets('edited with the form: what it saves is kept', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('Edit…').first);
    await tester.pumpAndSettle();
    expect(find.text('Edit Production'), findsOneWidget);
    await tester.tap(find.text('Automatic').last);
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(workspace.sshServers['prod']!.core, SshCore.auto);
    expect(find.textContaining('Core: Automatic'), findsOneWidget);
  });

  testWidgets('added from the page', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('Add Server…'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) => widget is IdeInputBox && widget.semanticsLabel == 'Host',
      ),
      'root@new.example',
    );
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is IdeInputBox && widget.semanticsLabel == 'Password',
      ),
      'hunter2',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(workspace.sshServers['root@new.example']!.hostName, 'new.example');
    expect(
      await secrets.read(SshPasswords.serverId('root@new.example')),
      'hunter2',
    );
    expect(find.text('root@new.example'), findsNWidgets(2));
  });

  testWidgets('removed, once asked: its password with it', (tester) async {
    await secrets.write(SshPasswords.serverId('prod'), 'secret');
    await pumpPage(tester);
    await tester.tap(find.text('Remove').first);
    await tester.pumpAndSettle();
    expect(find.text('Remove Production?'), findsOneWidget);
    await tester.tap(find.text('Remove').last);
    await tester.pumpAndSettle();
    expect(workspace.sshServers, isNot(contains('prod')));
    expect(find.text('Production'), findsNothing);
    expect(await secrets.read(SshPasswords.serverId('prod')), isNull);
  });

  testWidgets('each host\'s agents may act on this machine until turned '
      'off; one always allowed asked again', (tester) async {
    await pumpPage(tester);
    expect(find.text('Allow Remote Agents to Act on This Computer'), findsOne);
    expect(settings.localAccess('gpu'), isTrue);
    await tester.tap(find.text('gpu').last);
    await tester.pump();
    expect(settings.localAccess('gpu'), isFalse);
    expect(settings.localAccess('prod'), isTrue);

    settings.setRunsWithoutAsking('prod', true);
    await tester.pump();
    expect(find.text('Runs commands without asking'), findsOneWidget);
    await tester.tap(find.text('Ask Each Time'));
    await tester.pump();
    expect(settings.runsWithoutAsking('prod'), isFalse);
    expect(settings.localAccess('prod'), isTrue);
    expect(find.text('Ask Each Time'), findsNothing);
  });
}
