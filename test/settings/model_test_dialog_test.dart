import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:baocode/ide/ide_hover.dart';
import 'package:baocode/l10n/l10n.dart';
import 'package:baocode/models/model_provider.dart';
import 'package:baocode/models/model_test.dart';
import 'package:baocode/models/model_providers.dart';
import 'package:baocode/models/model_test_preset.dart';
import 'package:baocode/settings/pages/model_test_dialog.dart';
import 'package:baocode/settings/pages/model_dialogs.dart';
import 'package:baocode/settings/pages/settings_widgets.dart';
import 'package:baocode/settings/pages/model_test_result_view.dart';
import 'package:baocode/theme/codicons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const provider = ModelProvider(
  id: 'p',
  name: 'Gateway',
  baseUrl: 'https://example.com',
  models: [
    ProviderModel(id: 'a'),
    ProviderModel(id: 'b', enabled: false),
  ],
);

void main() {
  testWidgets('batch checkbox stroke and select-all toggle agree', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final service = ModelTestService(run: (_, _, _, _, _) async {});
    addTearDown(service.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ModelTestDialog(provider: provider, service: service),
      ),
    );
    await tester.pump();
    Finder box(String label) => find.byWidgetPredicate(
      (widget) => widget is ModelCheckbox && widget.semanticLabel == label,
    );
    bool checked(String label) =>
        tester.widget<ModelCheckbox>(box(label)).checked;
    expect(checked('a'), isFalse);
    expect(checked('b'), isFalse);
    // Click the selection cell's empty edge, outside the visible 16px box.
    await tester.tapAt(tester.getTopLeft(box('a')) + const Offset(3, 3));
    await tester.pump();
    expect(checked('a'), isTrue);
    final gesture = await tester.startGesture(
      tester.getTopLeft(box('a')) + const Offset(3, 3),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveTo(tester.getTopLeft(box('b')) + const Offset(3, 3));
    await gesture.up();
    await tester.pump();
    expect(checked('a'), isFalse);
    expect(checked('b'), isFalse);
    await tester.tapAt(
      tester.getTopLeft(box('Select All')) + const Offset(3, 3),
    );
    await tester.pump();
    expect(checked('a'), isTrue);
    expect(checked('b'), isTrue);
    await tester.tapAt(
      tester.getTopLeft(box('Select None')) + const Offset(3, 3),
    );
    await tester.pump();
    expect(checked('a'), isFalse);
    expect(checked('b'), isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'batch dialog uses selected models and custom prompt; closing keeps runs',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final preferences = ModelProviders.memory();
      addTearDown(preferences.dispose);
      final gate = Completer<void>();
      final requested = <(String, String)>[];
      final service = ModelTestService(
        run: (_, model, prompt, cancellation, emit) async {
          requested.add((model.id, prompt));
          await gate.future;
          emit(
            const ModelTestEvent(text: '1 2 3', outputTokens: 5, done: true),
          );
        },
      );
      addTearDown(service.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  TextButton(
                    onPressed: () => unawaited(
                      showModelTestDialog(
                        context,
                        provider: provider,
                        service: service,
                        preferences: preferences,
                      ),
                    ),
                    child: const Text('Open'),
                  ),
                  ModelTestButton(
                    service: service,
                    provider: provider,
                    model: provider.models.first,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('First Text'), findsOneWidget);
      expect(find.text('Output Numbers 1–120'), findsOneWidget);
      expect(find.textContaining('cursor-byok'), findsNothing);
      await preferences.saveTestPreset(
        const ModelTestPreset(
          id: 'custom-test',
          name: 'Custom text',
          prompt: 'custom text',
        ),
      );
      await tester.pump();
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is ModelCheckbox && w.semanticLabel == 'a',
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Test This Model'));
      await tester.pump();
      expect(requested, [('a', 'custom text')]);
      await tester.tap(find.text('Close'));
      // The visible run icon spins; settling it advances fake time to timeout.
      await tester.pump();
      expect(service.result('p', 'a')!.status, ModelTestStatus.running);
      gate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(service.result('p', 'a')!.status, ModelTestStatus.passed);
      final action = tester.widget<IdeActionButton>(
        find.byWidgetPredicate(
          (w) => w is IdeActionButton && w.tooltip.startsWith('Test Model:'),
        ),
      );
      expect(action.icon, Codicons.check);
      expect(action.color, SettingsSwitch.onColor);
      expect(action.label, endsWith(' token/s'));
      final result = service.result('p', 'a')!
        ..elapsed = const Duration(seconds: 2)
        ..firstText = const Duration(milliseconds: 237)
        ..firstEvent = const Duration(milliseconds: 100);
      expect(result.outputTokens, 5);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Passed'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (w) => w is ModelTestStatusIcon && w.status == ModelTestStatus.passed,
        ),
        findsOneWidget,
      );
      expect(find.text('237 ms'), findsOneWidget);
      expect(find.text('100 ms'), findsOneWidget);
      expect(find.text('2.00 s'), findsOneWidget);
      expect(find.text('5 token'), findsOneWidget);
      expect(find.text('2.5 token/s'), findsWidgets);
      expect(find.text('1 2 …'), findsOneWidget);
      expect(find.byIcon(Codicons.eye), findsNothing);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await tester.drag(
        find.byWidgetPredicate(
          (w) =>
              w is SingleChildScrollView &&
              w.scrollDirection == Axis.horizontal,
        ),
        const Offset(-700, 0),
      );
      await tester.pumpAndSettle();
      await mouse.moveTo(tester.getCenter(find.text('1 2 …')));
      await tester.pump(ideHoverDelay + const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.text('1 2 3'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'showing result hover');
      await mouse.moveTo(Offset.zero);
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('Chinese labels and table fit a compact desktop dialog', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final service = ModelTestService(
      run: (_, _, _, _, emit) async =>
          emit(const ModelTestEvent(text: 'OK', done: true)),
    );
    addTearDown(service.dispose);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => unawaited(
                showModelTestDialog(
                  context,
                  provider: provider,
                  service: service,
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('测试文本'), findsNothing);
    expect(find.text('输出数字 1–120'), findsOneWidget);
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is ModelCheckbox && w.semanticLabel == 'a',
      ),
    );
    await tester.pump();
    await tester.tap(find.text('测试该模型'));
    await tester.pumpAndSettle();
    expect(find.text('通过'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (w) => w is ModelTestStatusIcon && w.status == ModelTestStatus.passed,
      ),
      findsOneWidget,
    );
    await tester.drag(
      find.byWidgetPredicate(
        (widget) =>
            widget is SingleChildScrollView &&
            widget.scrollDirection == Axis.horizontal,
      ),
      const Offset(-600, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('OK'), findsOneWidget);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('OK')));
    await tester.pump(ideHoverDelay + const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 150));
    expect(
      find.byWidgetPredicate((w) => w is SelectableText && w.data == 'a'),
      findsOneWidget,
    );
    await mouse.moveTo(Offset.zero);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
  });
}
