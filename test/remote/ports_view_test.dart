@TestOn('mac-os || linux')
library;

import 'dart:io';

import 'package:baocode/l10n/app_localizations.dart';
import 'package:baocode/remote/port_forwards.dart';
import 'package:baocode/remote/ports_view.dart';
import 'package:baocode/remote/remote_host_settings.dart';
import 'package:baocode/remote/ssh_host.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'remote_harness.dart';

/// The side panel's ports page, over a host's server in memory: the ports
/// forwarded, each opened, copied and stopped; one forwarded by hand; the
/// host allowed to act here.
void main() {
  late Directory dir;
  late SshHosts hosts;
  late RemoteHostSettings settings;
  late PortForwards forwards;
  late ServerSocket server;
  final previous = RemoteHostSettings.instance;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('baocode-ports-view-');
    hosts = SshHosts(connect: MemoryConnector(dir.path).call);
    settings = RemoteHostSettings.instance = RemoteHostSettings(
      file: p.join(dir.path, 'remote-hosts.json'),
    );
    forwards = PortForwards(hosts: hosts, settings: settings, adbPort: null);
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  });

  tearDown(() async {
    forwards.dispose();
    await server.close();
    await hosts.closeAll();
    RemoteHostSettings.instance = previous;
    dir.deleteSync(recursive: true);
  });

  /// Lets the forwards' sockets work, in real time, until [done] (what the
  /// page started carrying on as it is pumped).
  Future<void> settle(WidgetTester tester, bool Function() done) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!done() && DateTime.now().isBefore(deadline)) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pump();
  }

  testWidgets('lists, opens, stops and adds forwards', (tester) async {
    final opened = <String>[];
    await tester.runAsync(() async {
      await hosts['dev'].ready;
      await forwards.open(
        'dev',
        PortForwardSpec(
          direction: ForwardDirection.toLocal,
          port: server.port,
          auto: true,
        ),
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Material(
          child: PortsView(
            host: 'dev',
            forwards: forwards,
            open: (url) async => opened.add(url),
          ),
        ),
      ),
    );
    await tester.pump();

    final [forward] = forwards.of('dev');
    expect(find.text('${server.port}'), findsOneWidget);
    expect(find.text(forward.localUrl!), findsOneWidget);
    expect(find.text('自动'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey(('port-open', server.port))));
    expect(opened, [forward.localUrl]);

    await tester.tap(find.byKey(ValueKey(('port-stop', server.port))));
    await settle(tester, () => forwards.of('dev').isEmpty);
    expect(find.text('${server.port}'), findsNothing);

    // By hand: this machine's port, to the host.
    await tester.tap(find.byKey(const ValueKey('ports-add')));
    await tester.pump();
    await tester.tap(find.text('本机 → dev'));
    await tester.enterText(
      find.byKey(const ValueKey('ports-port')),
      '${server.port}',
    );
    await tester.tap(find.byKey(const ValueKey('ports-forward')));
    await settle(tester, () => forwards.of('dev').isNotEmpty);
    final [added] = forwards.of('dev');
    expect(added.direction, ForwardDirection.toRemote);
    expect(added.remotePort, isNotNull);
    expect(find.byKey(const ValueKey('ports-form')), findsNothing);
    expect(find.text('127.0.0.1:${added.remotePort}'), findsOneWidget);
    expect(settings.forwards('dev'), [added.spec]);

    await tester.runAsync(() => forwards.close(added));
  });
}
