import 'package:baocode/chat/panels/health_banner.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:baocode/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    KernelHealth health, {
    VoidCallback? onSetUpModel,
  }) => tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        body: HealthBanner(
          health: health,
          kernelName: 'Claude Code',
          onRetry: () {},
          onSetUpModel: onSetUpModel,
        ),
      ),
    ),
  );

  testWidgets('a project folder that is gone is said in the user\'s '
      'language', (tester) async {
    await pump(
      tester,
      const KernelHealth(
        KernelHealthStatus.failed,
        message: 'The project folder is gone: ~/code/app',
        missingFolder: '~/code/app',
      ),
    );
    expect(find.text('项目文件夹不存在：~/code/app'), findsOneWidget);
    expect(find.textContaining('is gone'), findsNothing);
  });

  testWidgets('another failure shows its message', (tester) async {
    await pump(
      tester,
      const KernelHealth(
        KernelHealthStatus.failed,
        message: 'Claude Code is not installed',
      ),
    );
    expect(find.text('Claude Code is not installed'), findsOneWidget);
  });

  const noModel = KernelHealth(
    KernelHealthStatus.failed,
    message: 'No model to run on',
    noModel: true,
  );

  testWidgets('no model: one to set up, in the user\'s language, not a '
      'retry', (tester) async {
    var setUp = 0;
    await pump(tester, noModel, onSetUpModel: () => setUp++);
    expect(find.text('选一个模型就能开始：添加一个上游，它的模型就能直接用了。'), findsOneWidget);
    expect(find.text('重试'), findsNothing);
    await tester.tap(find.text('设置模型'));
    expect(setUp, 1);
  });

  testWidgets('no model and nowhere to set one up: its message and a '
      'retry', (tester) async {
    await pump(tester, noModel);
    expect(find.text('No model to run on'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });
}
