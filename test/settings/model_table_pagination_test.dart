import 'dart:io';

import 'package:baocode/ide/ide_hover.dart';
import 'package:baocode/models/model_provider.dart';
import 'package:baocode/models/model_providers.dart';
import 'package:baocode/models/model_test.dart';
import 'package:baocode/settings/pages/model_dialogs.dart';
import 'package:baocode/settings/pages/model_table_pagination.dart';
import 'package:baocode/settings/pages/model_test_dialog.dart';
import 'package:baocode/settings/user_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'page size persists in the existing settings file and clamps pages',
    () async {
      final directory = await Directory.systemTemp.createTemp('model-pages-');
      addTearDown(() => directory.delete(recursive: true));
      final file = '${directory.path}/settings.json';
      final settings = UserSettings(file);
      await settings.load();
      final providers = ModelProviders.settings(settings);
      addTearDown(providers.dispose);
      addTearDown(settings.dispose);
      expect(providers.modelPageSize, 100);
      await providers.setModelPageSize(1000);
      final reopened = UserSettings(file);
      await reopened.load();
      final restored = ModelProviders.settings(reopened);
      addTearDown(restored.dispose);
      addTearDown(reopened.dispose);
      expect(restored.modelPageSize, 1000);
      final page = ModelTablePage(restored);
      final items = List.generate(1101, (index) => index);
      expect(page.visible(items).length, 1000);
      page.index = 1;
      expect(page.visible(items).first, 1000);
      expect(page.visible(items).length, 101);
      expect(page.visible([1, 2]), [1, 2]);
      expect(page.index, 0);
      await restored.setModelPageSize(10000);
      expect(page.visible(items).length, 1101);
      await restored.setModelPageSize(0);
      expect(page.pages(items.length), 1);
      expect(page.visible(items).length, 1101);
    },
  );

  testWidgets('header select-all and test run affect current page only', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
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
    final provider = ModelProvider(
      id: 'p',
      name: 'Paged',
      baseUrl: 'https://example.com',
      models: List.generate(101, (index) => ProviderModel(id: 'm$index')),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ModelTestDialog(
          provider: provider,
          service: service,
          preferences: preferences,
        ),
      ),
    );
    await tester.pumpAndSettle();
    Finder header(String label) => find.byWidgetPredicate(
      (w) => w is ModelCheckbox && w.semanticLabel == label,
    );
    expect(find.text('1 / 2 · 101'), findsOneWidget);
    expect(
      (tester.getCenter(find.byType(ModelTablePagination)).dy -
              tester.getCenter(find.text('Test This Model')).dy)
          .abs(),
      lessThan(3),
    );
    await tester.tapAt(
      tester.getTopLeft(header('Select All')) + const Offset(3, 3),
    );
    await tester.pump();
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is IdeActionButton && w.tooltip == 'Next Page',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('m100'), findsOneWidget);
    expect(tester.widget<ModelCheckbox>(header('m100')).checked, isFalse);
    await tester.tap(header('Select All'));
    await tester.pump();
    await tester.tap(find.text('Test This Model'));
    await tester.pumpAndSettle();
    expect(tested, ['m100']);
    expect(tester.widget<Text>(find.text('OK')).maxLines, 1);
    // The cell's bottom divider occupies one pixel of the 38px row.
    expect(tester.getRect(header('m100')).height, 37);
    await tester.tap(header('Select None'));
    await tester.pump();
    expect(tester.widget<ModelCheckbox>(header('m100')).checked, isFalse);
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is IdeActionButton && w.tooltip == 'Previous Page',
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<ModelCheckbox>(header('m0')).checked, isTrue);
    expect(tester.widget<ModelCheckbox>(header('Select None')).checked, isTrue);
    expect(find.text('1 / 2 · 101'), findsOneWidget);
    expect(find.textContaining('No tools'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
