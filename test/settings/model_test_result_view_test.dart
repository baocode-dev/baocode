import 'dart:ui' show PointerDeviceKind;

import 'package:baocode/ide/ide_hover.dart';
import 'package:baocode/models/model_provider.dart';
import 'package:baocode/models/model_test.dart';
import 'package:baocode/settings/pages/model_test_dialog.dart';
import 'package:baocode/settings/pages/model_test_result_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const provider = ModelProvider(
  id: 'custom',
  name: 'Custom',
  baseUrl: 'https://example.com',
  models: [ProviderModel(id: 'model')],
);

void main() {
  test('all metric values retain units, precision and estimate markers', () {
    expect(modelTestDuration(null), '—');
    expect(modelTestDuration(Duration.zero), '0.00 ms');
    expect(modelTestDuration(const Duration(microseconds: 320)), '0.32 ms');
    expect(modelTestDuration(const Duration(milliseconds: 237)), '237 ms');
    expect(modelTestDuration(const Duration(milliseconds: 999)), '999 ms');
    expect(modelTestDuration(const Duration(seconds: 1)), '1.00 s');
    expect(modelTestDuration(const Duration(milliseconds: 2345)), '2.35 s');
    final result =
        ModelTestResult(provider, provider.models.first, modelTestPrompt)
          ..output = 'actual response'
          ..elapsed = const Duration(seconds: 2)
          ..reportedOutputTokens = 100;
    expect(modelTestSpeed(result), '50.0 token/s');
    expect(modelTestOutputTokens(result), '100 token');
    result.reportedOutputTokens = null;
    expect(modelTestSpeed(result), startsWith('~'));
    expect(modelTestOutputTokens(result), endsWith(' token'));
    expect(modelTestTokens(12), '12 token');
    expect(modelTestSpeed(null), '—');
    expect(modelTestOutputPreview(''), '—');
    expect(modelTestOutputPreview('OK'), 'OK');
    expect(modelTestOutputPreview('你好世界后续'), '你好世界…');
    expect(modelTestOutputPreview('👨‍👩‍👧‍👦abcd'), '👨‍👩‍👧‍👦abc…');
    expect(modelTestOutputPreview('a\n  bcdef'), 'a bc…');
  });

  testWidgets('successful action shows speed and a single rich hover', (
    tester,
  ) async {
    final service = ModelTestService(
      run: (_, _, _, _, emit) async => emit(
        const ModelTestEvent(
          text: 'Actual response',
          thinking: 'Reasoning',
          inputTokens: 12,
          outputTokens: 100,
          done: true,
        ),
      ),
    );
    addTearDown(service.dispose);
    service.start(provider, provider.models);
    await tester.pump();
    final result = service.result('custom', 'model')!
      ..elapsed = const Duration(seconds: 2)
      ..firstText = const Duration(milliseconds: 237)
      ..firstEvent = const Duration(milliseconds: 100);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ModelTestButton(
              service: service,
              provider: provider,
              model: provider.models.first,
            ),
          ),
        ),
      ),
    );
    expect(find.text('50.0 token/s'), findsOneWidget);
    expect(find.byType(IdeHover), findsOneWidget);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byType(IdeActionButton)));
    await tester.pump(ideHoverDelay + const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('237 ms'), findsOneWidget);
    expect(find.text('100 ms'), findsOneWidget);
    expect(find.text('2.00 s'), findsOneWidget);
    expect(find.text('100 token'), findsOneWidget);
    expect(find.text('12 token'), findsOneWidget);
    expect(find.text('Actual response'), findsOneWidget);
    expect(find.text('Reasoning'), findsOneWidget);
    // Nested action tooltips must not dismiss the containing result panel.
    for (final tooltip in [
      'Expand',
      'Copy: Response',
      'Copy: Reasoning Returned',
    ]) {
      final action = find
          .byWidgetPredicate(
            (w) => w is IdeActionButton && w.tooltip == tooltip,
          )
          .first;
      await mouse.moveTo(tester.getCenter(action));
      await tester.pump(const Duration(seconds: 2));
      expect(
        find.text('Actual response'),
        findsOneWidget,
        reason: 'result panel stays open over $tooltip',
      );
      expect(find.text('Reasoning'), findsOneWidget);
    }
    final panel = tester.getRect(find.byType(IdeHoverBox).first);
    await mouse.moveTo(Offset(panel.left + 2, panel.bottom - 2));
    await tester.pump(const Duration(seconds: 2));
    expect(
      find.text('Actual response'),
      findsOneWidget,
      reason: 'result panel padding also keeps the panel open',
    );
    await mouse.moveTo(tester.getCenter(find.text('Actual response')));
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('Actual response'), findsOneWidget);
    await mouse.down(tester.getCenter(find.text('Actual response')));
    await mouse.up();
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('Actual response'), findsOneWidget);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
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
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is IdeActionButton && w.tooltip == 'Copy: Response',
      ),
    );
    await tester.pump(const Duration(milliseconds: 800));
    expect(copied, 'Actual response');
    final metricsField = tester.state<EditableTextState>(
      find.descendant(
        of: find.byWidgetPredicate(
          (w) => w is SelectableText && w.data == '237 ms',
        ),
        matching: find.byType(EditableText),
      ),
    );
    metricsField.selectAll(SelectionChangedCause.keyboard);
    metricsField.copySelection(SelectionChangedCause.keyboard);
    await tester.pump();
    expect(copied, '237 ms');
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is IdeActionButton && w.tooltip == 'Copy All Results',
      ),
    );
    await tester.pump();
    expect(copied, contains('Speed: 50.0 token/s'));
    expect(copied, contains('First Text: 237 ms'));
    expect(copied, contains('Reasoning'));
    expect(find.text('Actual response'), findsOneWidget);
    expect(find.text('First Text'), findsOneWidget);
    expect(find.text('50.0 token/s'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    // Retesting remains the same action, including the speed text hit target.
    expect(
      tester
          .widget<IdeActionButton>(
            find.byWidgetPredicate(
              (w) =>
                  w is IdeActionButton && w.tooltip.startsWith('Test Model:'),
            ),
          )
          .onPressed,
      isNotNull,
    );
    expect(result.status, ModelTestStatus.passed);
    await mouse.moveTo(Offset.zero);
    await tester.pumpAndSettle();
  });

  testWidgets('long output and reasoning stay inside compact hover bounds', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final service = ModelTestService(run: (_, _, _, _, _) async {});
    addTearDown(service.dispose);
    final result =
        ModelTestResult(provider, provider.models.first, modelTestPrompt)
          ..status = ModelTestStatus.failed
          ..output = 'Long response\n' * 200
          ..thinking = 'Long reasoning\n' * 200
          ..error = 'Error\n' * 100;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: IdeHoverBox(
              child: ModelTestHoverDetails(service: service, result: result),
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getSize(find.byType(ModelTestHoverDetails)).height,
      lessThanOrEqualTo(420),
    );
    final output = find.byWidgetPredicate(
      (w) => w is SelectableText && (w.data ?? '').startsWith('Long response'),
    );
    expect(
      tester.widget<SelectableText>(output).data,
      modelTestOutputPreview(result.output, limit: 16),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byType(ModelTestHoverDetails)));
    await tester.pump();
    expect(tester.widget<SelectableText>(output).data, isNot(result.output));
    await tester.tap(
      find
          .byWidgetPredicate(
            (w) => w is IdeActionButton && w.tooltip == 'Expand',
          )
          .at(1),
    );
    await tester.pump();
    expect(tester.widget<SelectableText>(output).data, result.output);
    expect(find.text(result.thinking), findsNothing);
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is IdeActionButton && w.tooltip == 'Collapse',
      ),
    );
    await tester.pump();
    expect(
      tester.widget<SelectableText>(output).data,
      modelTestOutputPreview(result.output, limit: 16),
    );
    await tester.ensureVisible(
      find.byWidgetPredicate(
        (w) => w is SelectableText && w.data == 'Reasoning Returned',
      ),
    );
    await tester.pump();
    await tester.tap(
      find
          .byWidgetPredicate(
            (w) => w is IdeActionButton && w.tooltip == 'Expand',
          )
          .last,
    );
    await tester.pump();
    expect(find.text(result.thinking), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
