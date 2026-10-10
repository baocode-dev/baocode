import 'package:baocode/ide/ide_hover.dart';
import 'package:baocode/ide/ide_input.dart';
import 'package:baocode/l10n/app_localizations_en.dart';
import 'package:baocode/models/model_provider.dart';
import 'package:baocode/models/model_providers.dart';
import 'package:baocode/models/model_test.dart';
import 'package:baocode/settings/pages/model_dialogs.dart';
import 'package:baocode/settings/pages/model_test_dialog.dart';
import 'package:baocode/settings/pages/model_test_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final l10n = AppLocalizationsEn();
  const provider = ModelProvider(
    id: 'p',
    name: 'Table',
    baseUrl: 'https://example.com',
  );
  ModelTestTableRow row(
    String id, {
    int? milliseconds,
    int tokens = 1,
    String output = 'OK',
  }) {
    final model = ProviderModel(id: id);
    final result = milliseconds == null
        ? null
        : (ModelTestResult(provider, model, 'test')
            ..status = ModelTestStatus.passed
            ..firstEvent = Duration(milliseconds: milliseconds)
            ..firstText = Duration(milliseconds: milliseconds)
            ..elapsed = Duration(milliseconds: milliseconds)
            ..reportedOutputTokens = tokens
            ..output = output);
    return ModelTestTableRow(model, result, l10n);
  }

  test('numeric sorting uses raw values and missing results stay last in both directions', () {
    final rows = [
      row('slow', milliseconds: 2000, tokens: 100),
      row('missing'),
      row('fast', milliseconds: 99, tokens: 2),
      row('medium', milliseconds: 900, tokens: 10),
    ];
    final state = ModelTestTableState();
    for (final column in [
      ModelTestColumn.firstEvent,
      ModelTestColumn.firstText,
      ModelTestColumn.duration,
    ]) {
      state.sortColumn = column;
      state.ascending = true;
      expect(state.apply(rows).map((r) => r.model.id), [
        'fast',
        'medium',
        'slow',
        'missing',
      ]);
      state.ascending = false;
      expect(state.apply(rows).map((r) => r.model.id), [
        'slow',
        'medium',
        'fast',
        'missing',
      ]);
    }
    state.sortColumn = ModelTestColumn.tokens;
    state.ascending = true;
    expect(state.apply(rows).map((r) => r.model.id), [
      'fast',
      'medium',
      'slow',
      'missing',
    ]);
    state.sortColumn = ModelTestColumn.speed;
    expect(state.apply(rows).map((r) => r.model.id), [
      'medium',
      'fast',
      'slow',
      'missing',
    ]);
  });

  test('every column is sortable and column/global filters include complete output', () {
    final rows = [
      row('beta', milliseconds: 100, output: 'prefix secret-ending'),
      row('alpha', milliseconds: 100, output: 'prefix different-ending'),
    ];
    final state = ModelTestTableState();
    for (final column in ModelTestColumn.values) {
      state.sortColumn = null;
      state.toggleSort(column);
      expect(state.apply(rows), hasLength(2));
      expect(state.ascending, isTrue);
      state.toggleSort(column);
      expect(state.ascending, isFalse);
    }
    state.query = 'secret-ending';
    expect(state.apply(rows).single.model.id, 'beta');
    state.query = '';
    state.filters[ModelTestColumn.output] = const ModelTestColumnFilter(
      text: 'secret-ending',
    );
    state.filters[ModelTestColumn.firstText] = const ModelTestColumnFilter(
      minimum: .05,
      maximum: .2,
    );
    expect(state.apply(rows).single.model.id, 'beta');
    state.filters[ModelTestColumn.tokens] = const ModelTestColumnFilter(
      minimum: 2,
    );
    expect(state.apply(rows), isEmpty);
    expect(
      ModelTestColumnFilter.parseNumber('150 ms', ModelTestColumn.firstText),
      .15,
    );
    expect(
      ModelTestColumnFilter.parseNumber('1.5 s', ModelTestColumn.duration),
      1.5,
    );
    expect(
      ModelTestColumnFilter.parseNumber('52.5 token/s', ModelTestColumn.speed),
      52.5,
    );
    expect(
      ModelTestColumnFilter.parseNumber('100 token', ModelTestColumn.tokens),
      100,
    );
    expect(
      ModelTestColumnFilter.parseNumber('1 token/s', ModelTestColumn.duration),
      isNull,
    );
    expect(
      ModelTestColumnFilter.parseNumber('NaN', ModelTestColumn.tokens),
      isNull,
    );
  });

  testWidgets(
    'auto width measures all rows, caps outliers, and ignores full response length',
    (tester) async {
      final state = ModelTestTableState();
      final longName = 'long-model-' * 70;
      final rows = [
        row(
          longName,
          milliseconds: 100,
          tokens: 999999999,
          output: 'long response ' * 1000,
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              final widths = state.autoWidths(context, rows);
              final fit = state.autoWidths(
                context,
                rows,
                fitColumn: ModelTestColumn.model,
              );
              expect(widths[ModelTestColumn.model.index], 420);
              expect(fit[ModelTestColumn.model.index], greaterThan(420));
              expect(widths[ModelTestColumn.tokens.index], greaterThan(100));
              expect(widths[ModelTestColumn.output.index], lessThan(300));
              final inherited = DefaultTextStyle.of(context).style;
              final measured = TextPainter(
                textDirection: TextDirection.ltr,
                text: TextSpan(
                  text: rows.first.cells[ModelTestColumn.speed.index],
                  style: inherited.merge(
                    const TextStyle(fontSize: 12, fontFamily: 'JetBrains Mono'),
                  ),
                ),
              )..layout();
              expect(
                widths[ModelTestColumn.speed.index],
                greaterThan(measured.width + 20),
              );
              measured.dispose();
              return const SizedBox();
            },
          ),
        ),
      );
    },
  );

  testWidgets(
    'search and sorting happen before pages, header selects filtered page only',
    (tester) async {
      tester.view.physicalSize = const Size(1800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final preferences = ModelProviders.memory();
      addTearDown(preferences.dispose);
      final tested = <String>[];
      final service = ModelTestService(
        run: (_, model, _, _, emit) async {
          tested.add(model.id);
          emit(const ModelTestEvent(text: 'OK', done: true));
        },
      );
      addTearDown(service.dispose);
      final models = List.generate(
        105,
        (i) => ProviderModel(id: 'm${i.toString().padLeft(3, '0')}'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ModelTestDialog(
            provider: provider.copyWith(models: models),
            service: service,
            preferences: preferences,
          ),
        ),
      );
      await tester.pumpAndSettle();
      Finder box(String label) => find.byWidgetPredicate(
        (w) => w is ModelCheckbox && w.semanticLabel == label,
      );
      await tester.tap(find.byKey(const ValueKey('model-test-sort-model')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('model-test-sort-model')));
      await tester.pump();
      expect(find.text('m104'), findsOneWidget);
      expect(find.text('m000'), findsNothing);
      await tester.enterText(
        find.descendant(
          of: find.byWidgetPredicate(
            (w) =>
                w is IdeInputBox &&
                w.semanticsLabel == 'Search all model results…',
          ),
          matching: find.byType(EditableText),
        ),
        'm104',
      );
      await tester.pump();
      expect(find.text('1 / 1 · 1'), findsOneWidget);
      await tester.tap(box('Select All'));
      await tester.pump();
      await tester.tap(find.text('Test This Model'));
      await tester.pumpAndSettle();
      expect(tested, ['m104']);
      await tester.tap(find.text('Clear Filters'));
      await tester.pump();
      expect(find.text('1 / 2 · 105'), findsOneWidget);
      expect(tester.widget<ModelCheckbox>(box('m000')).checked, isFalse);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'header filters accept numeric limits and column handles resize without sorting',
    (tester) async {
      tester.view.physicalSize = const Size(1800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final preferences = ModelProviders.memory();
      addTearDown(preferences.dispose);
      final service = ModelTestService(
        run: (_, _, _, _, emit) async =>
            emit(const ModelTestEvent(text: 'OK', done: true)),
      );
      addTearDown(service.dispose);
      const models = [ProviderModel(id: 'beta'), ProviderModel(id: 'alpha')];
      service.start(provider, models);
      await tester.pump();
      service.result('p', 'alpha')!
        ..elapsed = const Duration(seconds: 2)
        ..reportedOutputTokens = 200;
      service.result('p', 'beta')!
        ..elapsed = const Duration(seconds: 2)
        ..reportedOutputTokens = 20;
      await tester.pumpWidget(
        MaterialApp(
          home: ModelTestDialog(
            provider: provider.copyWith(models: models),
            service: service,
            preferences: preferences,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final handle = find.byKey(const ValueKey('model-test-resize-1'));
      final initial = tester.getCenter(handle).dx;
      await tester.drag(handle, const Offset(100, 0));
      await tester.pump();
      expect(tester.getCenter(handle).dx - initial, closeTo(100, 2));
      expect(
        tester.getTopLeft(find.text('beta')).dy,
        lessThan(tester.getTopLeft(find.text('alpha')).dy),
      );
      await tester.drag(
        find.byWidgetPredicate(
          (w) =>
              w is SingleChildScrollView &&
              w.scrollDirection == Axis.horizontal,
        ),
        const Offset(-500, 0),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is IdeActionButton && w.tooltip == 'Filter: Speed',
        ),
      );
      await tester.pumpAndSettle();
      final minimum = find.descendant(
        of: find.byWidgetPredicate(
          (w) => w is IdeInputBox && w.semanticsLabel == 'Minimum',
        ),
        matching: find.byType(EditableText),
      );
      await tester.enterText(minimum, '50 token/s');
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(find.text('alpha'), findsOneWidget);
      expect(find.text('beta'), findsNothing);
      await tester.tap(find.text('Clear Filters'));
      await tester.pump();
      expect(find.text('beta'), findsOneWidget);
      await tester.tap(find.text('Auto Width'));
      await tester.pump();
      expect(tester.getCenter(handle).dx, closeTo(initial, 2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
