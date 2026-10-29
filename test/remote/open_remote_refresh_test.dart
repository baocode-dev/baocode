@TestOn('mac-os || linux')
library;

import 'dart:io';

import 'package:baocode/ide/ide_quick_input.dart';
import 'package:baocode/l10n/l10n.dart';
import 'package:baocode/remote/open_remote.dart';
import 'package:baocode/remote/ssh_host.dart';
import 'package:baocode/theme/codicons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'remote_harness.dart';

/// Open Remote Project…: the folders of a host, and reading them again
/// once one is made elsewhere.
void main() {
  late Directory dataDir;
  late Directory home;
  late SshHosts hosts;

  setUp(() {
    dataDir = Directory.systemTemp.createTempSync('baocode-remote-data-');
    home = Directory.systemTemp.createTempSync('baocode-remote-home-');
    hosts = SshHosts(connect: MemoryConnector(dataDir.path).call);
  });
  tearDown(() async {
    await hosts.closeAll();
    dataDir.deleteSync(recursive: true);
    home.deleteSync(recursive: true);
  });

  testWidgets('the folder pick reads the host again at its refresh', (
    tester,
  ) async {
    Directory(p.join(home.path, 'app')).createSync();
    final picks = <IdeQuickPick>[];
    final flow = OpenRemoteFlow(
      show: picks.add,
      l10n: lookupAppLocalizations(const Locale('en')),
      onOpen: (_) {},
      hosts: hosts,
      configHosts: () async => const ['dev'],
    );
    await tester.runAsync(() async {
      flow.startAt('dev');
      await until(() => picks.length > 1);
    });
    // Typed, the host's home (this machine's) is gone to: the temp folder
    // stands in for it, the folders in it listed.
    final atHome = picks.last;
    final goTo = atHome.itemsFor!(home.path).whereType<IdeQuickPickItem>().first;
    await tester.runAsync(() async {
      goTo.onAccept!();
      await until(() => picks.length > 2);
    });
    final pick = picks.last;
    expect(pick.buttons.single.tooltip, 'Read the folders again');
    expect(pick.buttons.single.icon, Codicons.refresh);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: IdeQuickInput.pick(pick: pick, onClose: () {})),
      ),
    );
    await tester.pump();
    expect(find.text('app'), findsOneWidget);
    expect(find.text('api'), findsNothing);

    // A folder made in a terminal since: the button reads the host again,
    // and the pick lists it.
    Directory(p.join(home.path, 'api')).createSync();
    await tester.tap(find.byTooltip('Read the folders again'));
    await tester.runAsync(() => Future<void>.delayed(
      const Duration(milliseconds: 100),
    ));
    await tester.pump();
    expect(find.text('api'), findsOneWidget);
    expect(find.text('app'), findsOneWidget);
  });
}
