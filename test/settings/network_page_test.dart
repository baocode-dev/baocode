import 'dart:io';

import 'package:baocode/network/proxy_settings.dart';
import 'package:baocode/settings/pages/network_page.dart';
import 'package:baocode/settings/pages/settings_dropdown.dart';
import 'package:baocode/settings/pages/settings_widgets.dart';
import 'package:baocode/settings/user_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory data;
  late UserSettings settings;
  late ProxyRoute route;
  late List<Uri> probed;

  setUp(() async {
    data = await Directory.systemTemp.createTemp('baocode-network');
    settings = UserSettings(p.join(data.path, 'settings.json'));
    await settings.load();
    route = ProxyRoute(
      source: ProxySource.system,
      http: const ProxyServer('127.0.0.1', 7890),
      https: const ProxyServer('127.0.0.1', 7890),
    );
    probed = [];
  });

  tearDown(() async {
    settings.dispose();
    await data.delete(recursive: true);
  });

  Future<void> settle(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 100; i++) {
      if (done()) return;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    fail('timed out');
  }

  Future<void> show(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NetworkSettingsPage(
            settings: settings,
            detect: () async => route,
            probe: (url) async {
              probed.add(url);
              if (route.direct)
                throw const SocketException('Connection refused');
              return const Duration(milliseconds: 120);
            },
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> choose(WidgetTester tester, String label) async {
    await tester.tap(find.byType(SettingsDropdown));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets('follows the system proxy, and says which it is', (tester) async {
    await show(tester);
    expect(
      tester.widget<SettingsDropdown>(find.byType(SettingsDropdown)).current,
      'System Proxy',
    );
    expect(find.text('System proxy http://127.0.0.1:7890'), findsOneWidget);
    expect(find.byType(SettingsTextField), findsNothing);

    await tester.tap(find.text('Test Connection').last);
    await tester.pump();
    await tester.pump();
    expect(probed, [NetworkSettingsPage.probeUrl]);
    expect(find.text('Connected in 120 ms.'), findsOneWidget);
  });

  testWidgets('a manual proxy is kept in settings.json, a bad one is not', (
    tester,
  ) async {
    await show(tester);
    await choose(tester, 'Manual');
    await settle(tester, () => settings[ProxyMode.settingKey] == 'manual');
    await settle(
      tester,
      () => find.text('Enter the proxy\'s address.').evaluate().isNotEmpty,
    );

    final field = find.descendant(
      of: find.byType(SettingsTextField),
      matching: find.byType(TextField),
    );
    await tester.enterText(field, 'socks5://127.0.0.1:7890');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.textContaining('Not an HTTP proxy address'), findsOneWidget);
    expect(settings[ProxyMode.urlKey], isNull);

    route = ProxyRoute.manual(const ProxyServer('127.0.0.1', 7897));
    await tester.enterText(field, 'http://127.0.0.1:7897');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(
      tester,
      () => settings[ProxyMode.urlKey] == 'http://127.0.0.1:7897',
    );
    await settle(
      tester,
      () => find.text('http://127.0.0.1:7897').evaluate().length > 1,
    );

    // The default is not written.
    await choose(tester, 'System Proxy');
    await settle(
      tester,
      () => !settings.values.containsKey(ProxyMode.settingKey),
    );
  });

  testWidgets('says why it goes direct', (tester) async {
    route = const ProxyRoute.direct(ProxySource.none, true);
    await show(tester);
    expect(find.textContaining('auto-config (PAC)'), findsOneWidget);

    await tester.tap(find.text('Test Connection').last);
    await tester.pump();
    await tester.pump();
    expect(find.text("Couldn't connect: Connection refused"), findsOneWidget);
  });
}
