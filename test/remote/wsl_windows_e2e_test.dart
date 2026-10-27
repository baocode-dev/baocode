// A project in a WSL distribution, as the app opens one, on a Windows
// machine with WSL: the hosts picked from (this machine's distributions,
// as wsl.exe lists them), connected over wsl.exe, a folder there browsed
// to and opened, then its files, Git and the status bar. Real WSL, real
// server: opt in with
//
//   $env:BAOCODE_REMOTE_SERVER_DIR = '<a folder with VERSION and
//       baocode-server-linux-x64>'
//   $env:BAOCODE_WSL_DISTRO = 'Ubuntu-24.04'
//   flutter test --run-skipped -t wsl-e2e test/remote/wsl_windows_e2e_test.dart
//
// The host pick is drawn to build/wsl_e2e/hosts.png too, to look at.
@TestOn('windows')
@Tags(['wsl-e2e'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:baocode/ide/ide_quick_input.dart';
import 'package:baocode/l10n/l10n.dart';
import 'package:baocode/remote/open_remote.dart';
import 'package:baocode/remote/remote_location.dart';
import 'package:baocode/remote/remote_status.dart';
import 'package:baocode/remote/ssh_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'remote_harness.dart' show until;

void main() {
  final distro = Platform.environment['BAOCODE_WSL_DISTRO'] ?? 'Ubuntu-24.04';
  final host = 'wsl+$distro';
  final previous = SshHosts.instance;
  late SshHosts hosts;

  setUpAll(() async {
    hosts = SshHosts.instance = SshHosts();
    // Text drawn in the system's font, to be read in the picture.
    final font = FontLoader('Snapshot')
      ..addFont(
        File(r'C:\Windows\Fonts\segoeui.ttf')
            .readAsBytes()
            .then(ByteData.sublistView),
      );
    await font.load();
  });
  tearDownAll(() async {
    await hosts.closeAll();
    SshHosts.instance = previous;
  });

  testWidgets('picked from the WSL hosts, opened, its files and Git there; '
      'the status bar says WSL', (tester) async {
    final shown = <IdeQuickPick>[];
    String? opened;
    String? connected;
    final flow = OpenRemoteFlow(
      show: shown.add,
      l10n: englishLocalizations,
      onOpen: (location) => opened = location,
      onConnected: (host) => connected = host,
      hosts: hosts,
      configHosts: () async => const [],
    );
    await tester.runAsync(flow.start);
    final pick = shown.single;
    final items = pick.itemsFor!('');
    final labels = [
      for (final item in items)
        switch (item) {
          IdeQuickPickSeparator(:final label) => '-- $label',
          IdeQuickPickItem(:final label) => label,
        },
    ];
    // ignore: avoid_print
    print('hosts: $labels');
    expect(labels, containsAllInOrder(['-- WSL', distro]));

    // The pick as the window shows it.
    final boundary = GlobalKey();
    await tester.binding.setSurfaceSize(const Size(900, 420));
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'Snapshot'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RepaintBoundary(
          key: boundary,
          child: Material(
            child: IdeQuickInput.pick(pick: pick, onClose: () {}),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() async {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage();
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File(p.join('build', 'wsl_e2e', 'hosts.png'));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(png!.buffer.asUint8List());
    });
    expect(find.text(distro), findsOneWidget);
    expect(find.text('WSL'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());

    // Picked: connected over wsl.exe, then its home to browse.
    final item = items.whereType<IdeQuickPickItem>().firstWhere(
      (item) => item.label == distro,
    );
    await tester.runAsync(() async {
      pick.onDidAccept!(item);
      await until(
        () => connected != null || hosts[host].state == SshHostState.failed,
        timeout: const Duration(seconds: 60),
      );
    });
    expect(hosts[host].error, isNull);
    expect(connected, host);
    final client = hosts[host].client!;
    final home = client.hello!.home;
    await tester.runAsync(() async {
      await client.run('rm', ['-rf', '$home/wsl-app-e2e']);
      await client.run('mkdir', ['-p', '$home/wsl-app-e2e/app']);
      await client.run('sh', [
        '-c',
        'cd "$home/wsl-app-e2e/app" && git init -q && echo hi > a.txt',
      ]);
    });
    // The pick shown after [after] (of those so far) that lists [label].
    // [accept] first, in real time: the next pick is shown by a timer.
    Future<IdeQuickPick> listing(
      String label,
      int after, [
      void Function()? accept,
    ]) async {
      IdeQuickPick? found;
      await tester.runAsync(() async {
        accept?.call();
        await until(() {
          for (final pick in shown.skip(after)) {
            final labels = [
              for (final item in pick.itemsFor?.call('') ?? const [])
                if (item is IdeQuickPickItem) item.label,
            ];
            if (labels.contains(label)) found = pick;
          }
          return found != null;
        }, timeout: const Duration(seconds: 30));
      });
      return found!;
    }

    // Its home first; the folder typed gone to.
    final browse = await listing(englishLocalizations.remoteOpenThisFolder, 1);
    var seen = shown.length;
    final there = browse.itemsFor!('$home/wsl-app-e2e');
    final inFolder = await listing(
      'app',
      seen,
      (there.first as IdeQuickPickItem).onAccept,
    );
    seen = shown.length;
    final inApp = await listing(
      englishLocalizations.remoteOpenThisFolder,
      seen,
      inFolder.itemsFor!('')
          .whereType<IdeQuickPickItem>()
          .firstWhere((i) => i.label == 'app')
          .onAccept,
    );
    await tester.runAsync(() async {
      inApp.itemsFor!('')
          .whereType<IdeQuickPickItem>()
          .firstWhere(
            (i) => i.label == englishLocalizations.remoteOpenThisFolder,
          )
          .onAccept!();
      await until(() => opened != null);
    });
    expect(opened, 'ssh://$host$home/wsl-app-e2e/app');
    // ignore: avoid_print
    print('opened: $opened');

    // The project's files and Git, there.
    final path = RemoteLocation.pathOf(opened!);
    await tester.runAsync(() async {
      expect(await client.read(path, '$path/a.txt'), 'hi\n');
      final status = await client.git(['status', '--porcelain'], cwd: path);
      expect(status.stdout, contains('a.txt'));
    });

    // The status bar's entry.
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: SizedBox()),
      ),
    );
    final entry = SshStatusIndicator(hosts[host])
        .item(tester.element(find.byType(SizedBox)));
    // ignore: avoid_print
    print('status bar: ${entry.text} / ${entry.tooltip}');
    expect(entry.text, 'WSL: $distro');
    expect(entry.tooltip, 'Connected to $distro over WSL');

    await tester.runAsync(() => client.run('rm', ['-rf', '$home/wsl-app-e2e']));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
