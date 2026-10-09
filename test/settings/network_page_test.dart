import 'dart:async';
import 'dart:io';

import 'package:baocode/network/network_proxy.dart';
import 'package:baocode/settings/pages/network_page.dart';
import 'package:baocode/settings/pages/network_test_view.dart';
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

  /// How each host answers: a time, or a [ProbeFailure]; 120 ms when not
  /// said.
  late Map<String, Object> answers;

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
    answers = {};
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
              return switch (answers[url.host]) {
                final ProbeFailure failure => throw failure,
                final Duration time => time,
                _ => const Duration(milliseconds: 120),
              };
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

    expect(find.byType(NetworkTestRow), findsNWidgets(5));
    expect(find.text('—'), findsNWidgets(5));
  });

  testWidgets('tests every site at once, each by how quickly it answered', (
    tester,
  ) async {
    answers = {
      'www.google.com': const Duration(milliseconds: 180),
      'www.youtube.com': const Duration(milliseconds: 650),
      'api.anthropic.com': const Duration(milliseconds: 1400),
      'api.openai.com': const ProbeFailure(
        ProbeFailureKind.timeout,
        'timed out',
      ),
    };
    await show(tester);
    await tester.tap(find.text('Run Test'));
    await tester.pump();
    await tester.pump();
    expect(probed.map((url) => url.host).toSet(), {
      'www.google.com',
      'www.youtube.com',
      'api.anthropic.com',
      'api.openai.com',
      'www.baidu.com',
    });
    expect(find.text('180 ms'), findsOneWidget);
    expect(find.text('650 ms'), findsOneWidget);
    expect(find.text('1400 ms'), findsOneWidget);
    expect(find.text('120 ms'), findsOneWidget);
    expect(find.text('Unreachable · Timed out'), findsOneWidget);
    // The time alone: no word for how fast.
    expect(find.text('Fast'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('4 of 5 sites reachable.'), findsOneWidget);
    expect(find.text('Test Again'), findsOneWidget);
  });

  testWidgets('a site being tested shows a spinner alone', (tester) async {
    final gate = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NetworkSettingsPage(
            detect: () async => route,
            probe: (url) async {
              await gate.future;
              return const Duration(milliseconds: 90);
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('—'), findsNWidgets(5));
    await tester.tap(find.text('Run Test'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNWidgets(5));
    expect(find.text('Testing…'), findsNothing);
    gate.complete();
    await tester.pump();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('90 ms'), findsNWidgets(5));
  });

  testWidgets('says what the failures together suggest', (tester) async {
    for (final host in [
      'www.google.com',
      'www.youtube.com',
      'api.anthropic.com',
      'api.openai.com',
    ]) {
      answers[host] = const ProbeFailure(ProbeFailureKind.reset);
    }
    await show(tester);
    await tester.tap(find.text('Run Test'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Only Baidu answers'), findsOneWidget);
    expect(find.text('Unreachable · Connection reset'), findsNWidgets(4));

    answers['www.baidu.com'] = const ProbeFailure(ProbeFailureKind.refused);
    for (final host in answers.keys) {
      answers[host] = const ProbeFailure(ProbeFailureKind.refused);
    }
    await tester.tap(find.text('Test Again'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('check that Clash'), findsOneWidget);
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
  });

  testWidgets('a proxy changed drops what was tested through the last', (
    tester,
  ) async {
    await show(tester);
    await tester.tap(find.text('Run Test'));
    await tester.pump();
    await tester.pump();
    expect(find.text('120 ms'), findsNWidgets(5));
    await tester.runAsync(() => settings.update(ProxyMode.settingKey, 'off'));
    await settle(tester, () => find.text('—').evaluate().length == 5);
  });
}
