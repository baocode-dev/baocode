import 'dart:ui' show PointerDeviceKind;
import 'dart:async';

import 'package:baocode/ide/ide_hover.dart';
import 'package:baocode/models/model_provider.dart';
import 'package:baocode/models/model_test.dart';
import 'package:baocode/settings/pages/model_test_dialog.dart';
import 'package:baocode/settings/pages/model_test_result_view.dart';
import 'package:baocode/theme/codicons.dart';
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

  testWidgets(
    'compact hover stays interactive and dismisses promptly after leaving',
    (tester) async {
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
      service.result('custom', 'model')!
        ..elapsed = const Duration(seconds: 2)
        ..firstText = const Duration(milliseconds: 237)
        ..firstEvent = const Duration(milliseconds: 100);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: IdeHover(
                message: 'Batch result',
                content: ModelTestHoverDetails(
                  service: service,
                  result: service.result('custom', 'model')!,
                ),
                child: const Text('Show result'),
              ),
            ),
          ),
        ),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text('Show result')));
      await tester.pump(ideHoverDelay + const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.text('237 ms'), findsOneWidget);
      expect(find.text('2.00 s'), findsOneWidget);
      expect(find.text('50.0 token/s'), findsOneWidget);
      expect(find.textContaining('100 ms'), findsOneWidget);
      expect(find.text('Passed'), findsNothing);
      expect(find.byIcon(Codicons.copy), findsNothing);
      expect(tester.getSize(find.byType(ModelTestHoverDetails)).width, 300);
      expect(
        tester.getSize(find.byType(ModelTestHoverDetails)).height,
        lessThan(220),
      );
      final output = find.byWidgetPredicate(
        (w) => w is SelectableText && w.textSpan != null,
      );
      expect(output, findsOneWidget);
      expect(
        tester.widget<SelectableText>(output).textSpan!.toPlainText(),
        'Actual response\nThinking · Reasoning',
      );
      final expand = find.byWidgetPredicate(
        (w) => w is IdeActionButton && w.tooltip == 'Expand',
      );
      await mouse.moveTo(tester.getCenter(expand));
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(ModelTestDetails), findsOneWidget);
      final box = tester.getRect(find.byType(IdeHoverBox).first);
      await mouse.moveTo(Offset(box.left + 2, box.bottom - 2));
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(ModelTestDetails), findsOneWidget);
      await mouse.moveTo(tester.getCenter(output));
      await tester.pump();
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
      final field = tester.state<EditableTextState>(
        find.descendant(of: output, matching: find.byType(EditableText)),
      );
      field.selectAll(SelectionChangedCause.keyboard);
      field.copySelection(SelectionChangedCause.keyboard);
      await tester.pump();
      expect(copied, contains('Actual response'));
      expect(copied, contains('Reasoning'));
      await mouse.moveTo(Offset.zero);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(ModelTestDetails), findsNothing);
    },
  );

  testWidgets(
    'first click tests; completed result clicks only open and refresh is explicit',
    (tester) async {
      var calls = 0;
      final gate = Completer<void>();
      final service = ModelTestService(
        run: (_, _, _, _, emit) async {
          calls++;
          if (calls == 2) await gate.future;
          emit(const ModelTestEvent(text: 'OK', outputTokens: 10, done: true));
        },
      );
      addTearDown(service.dispose);
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
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await tester.tap(find.byType(ModelTestButton));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.byType(ModelTestDetails), findsNothing);
      await mouse.moveTo(tester.getCenter(find.byType(ModelTestButton)));
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(ModelTestDetails), findsNothing);
      expect(calls, 1);
      await tester.tap(find.byType(ModelTestButton));
      await tester.pumpAndSettle();
      expect(find.byType(ModelTestDetails), findsOneWidget);
      expect(calls, 1);
      await mouse.moveTo(Offset.zero);
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(ModelTestDetails), findsOneWidget);
      final refresh = find.byWidgetPredicate(
        (w) => w is IdeActionButton && w.tooltip == 'Retest model',
      );
      await tester.tap(refresh);
      await tester.pump();
      expect(calls, 2);
      expect(tester.widget<IdeActionButton>(refresh).onPressed, isNull);
      await tester.tap(refresh);
      await tester.pump();
      expect(calls, 2);
      gate.complete();
      await tester.pumpAndSettle();
      expect(tester.widget<IdeActionButton>(refresh).onPressed, isNotNull);
      expect(find.byType(ModelTestDetails), findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.byType(ModelTestDetails), findsNothing);
      await tester.tap(find.byType(ModelTestButton));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.byType(ModelTestDetails), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(ModelTestDetails), findsNothing);
    },
  );

  testWidgets('failed result click opens error without retrying', (
    tester,
  ) async {
    var calls = 0;
    final service = ModelTestService(
      run: (_, _, _, _, _) async {
        calls++;
        throw const FormatException('Example failure');
      },
    );
    addTearDown(service.dispose);
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
    await tester.tap(find.byType(ModelTestButton));
    await tester.pumpAndSettle();
    expect(calls, 1);
    await tester.tap(find.byType(ModelTestButton));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.byType(ModelTestDetails), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'one explicit expand reveals response and thinking inside bounded hover',
    (tester) async {
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
            ..error = 'Example failure';
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
      final body = find.byWidgetPredicate(
        (w) => w is SelectableText && w.textSpan != null,
      );
      final before = tester
          .widget<SelectableText>(body)
          .textSpan!
          .toPlainText();
      expect(
        before,
        contains(modelTestOutputPreview(result.output, limit: 24)),
      );
      expect(before, isNot(contains(result.thinking)));
      expect(
        tester.getSize(find.byType(ModelTestHoverDetails)).height,
        lessThan(240),
      );
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is IdeActionButton && w.tooltip == 'Expand',
        ),
      );
      await tester.pump();
      final expanded = tester
          .widget<SelectableText>(body)
          .textSpan!
          .toPlainText();
      expect(expanded, contains(result.output));
      expect(expanded, contains(result.thinking));
      expect(
        tester.getSize(find.byType(ModelTestHoverDetails)).height,
        lessThanOrEqualTo(300),
      );
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is IdeActionButton && w.tooltip == 'Collapse',
        ),
      );
      await tester.pump();
      expect(
        tester.widget<SelectableText>(body).textSpan!.toPlainText(),
        before,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
