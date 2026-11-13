import 'package:baocode/l10n/app_localizations.dart';
import 'package:baocode/link/link_host.dart';
import 'package:baocode/settings/pages/about_page.dart';
import 'package:baocode/update/version.dart';
import 'package:baocode/workspace/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../link/fake_link_platform.dart';

void main() {
  Future<void> show(
    WidgetTester tester,
    Locale locale, {
    LinkHost? host,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: AboutSettingsPage(host: host)),
      ),
    );
    await tester.pump();
  }

  testWidgets('says what BaoCode is, which build, and where it is made', (
    tester,
  ) async {
    await show(tester, const Locale('zh'));
    expect(find.text('关于'), findsOneWidget);
    expect(find.text('BaoCode'), findsOneWidget);
    expect(
      find.text(
        '版本 ${currentAppVersion.marketing}（${currentAppVersion.build}）',
      ),
      findsOneWidget,
    );
    expect(
      find.text('github.com/baocode-dev/baocode · 免费开源，GPL-3.0 许可证'),
      findsOneWidget,
    );
    expect(find.text('去 GitHub 点 Star'), findsOneWidget);
    expect(find.text('baocode.dev'), findsOneWidget);
    expect(find.text('更新日志'), findsOneWidget);
    expect(find.text('反馈问题'), findsOneWidget);
    expect(find.text('设备 ID'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('this computer\'s device id, copied for a relay\'s list', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final host = LinkHost(
      workspace: Workspace.mock(),
      platform: FakeLinkPlatform(),
    );
    addTearDown(host.dispose);
    await host.load();
    await show(tester, const Locale('zh'), host: host);
    expect(host.id, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(find.text('设备 ID'), findsOneWidget);
    expect(find.text(host.id), findsOneWidget);
    await tester.tap(find.text('复制'));
    await tester.pump();
    expect(copied, host.id);
    expect(find.text('已复制'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('复制'), findsOneWidget);
  });

  test('its links', () {
    expect(
      AboutSettingsPage.issues,
      Uri.parse('https://github.com/baocode-dev/baocode/issues'),
    );
  });
}
