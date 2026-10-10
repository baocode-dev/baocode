import 'dart:io';

import 'package:baocode/ide/ide_hover.dart';
import 'package:baocode/models/model_provider.dart';
import 'package:baocode/models/model_providers.dart';
import 'package:baocode/models/model_test.dart';
import 'package:baocode/models/upstream.dart';
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

  testWidgets(
    'compact selection menu explicitly selects and clears all pages',
    (tester) async {
      tester.view.physicalSize = const Size(1500, 1000);
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
        name: 'All',
        baseUrl: 'https://example.com',
        models: List.generate(101, (i) => ProviderModel(id: 'm$i')),
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
      expect(find.text('Auto Width'), findsNothing);
      expect(find.text('Clear Filters'), findsNothing);
      expect(find.textContaining('Output the numbers'), findsNothing);
      Finder action(String label) => find.byWidgetPredicate(
        (w) => w is IdeActionButton && w.tooltip == label,
      );
      await tester.tap(action('Selection scope'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select all pages'));
      await tester.pumpAndSettle();
      await tester.tap(action('Next Page'));
      await tester.pump();
      final box = find.byWidgetPredicate(
        (w) => w is ModelCheckbox && w.semanticLabel == 'm100',
      );
      expect(tester.widget<ModelCheckbox>(box).checked, isTrue);
      await tester.tap(find.text('Test This Model'));
      await tester.pumpAndSettle();
      expect(tested, hasLength(101));
      await tester.tap(action('Selection scope'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select None'));
      await tester.pumpAndSettle();
      expect(tester.widget<ModelCheckbox>(box).checked, isFalse);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('model picker shares cross-page selection and compact rows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final preferences = ModelProviders.memory();
    addTearDown(preferences.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: FetchModelsDialog(
          provider: const ModelProvider(id: 'p', name: 'Picker'),
          preferences: preferences,
          keyOf: () async => null,
          list: (_, _) async => [
            for (var i = 0; i < 101; i++)
              RemoteModel('m${i.toString().padLeft(3, '0')}'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    Finder action(String label) => find.byWidgetPredicate(
      (w) => w is IdeActionButton && w.tooltip == label,
    );
    Finder checkbox(String label) => find.byWidgetPredicate(
      (w) => w is ModelCheckbox && w.semanticLabel == label,
    );
    Finder glyph(Finder box) => find.descendant(
      of: box,
      matching: find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.constraints?.minWidth == 16 &&
            w.constraints?.minHeight == 16,
      ),
    );
    expect(
      tester.getCenter(glyph(checkbox('Select All'))).dx,
      closeTo(tester.getCenter(glyph(checkbox('m000'))).dx, .01),
    );
    await tester.enterText(find.byType(EditableText).last, 'm000');
    await tester.pumpAndSettle();
    await tester.tap(checkbox('Select All'));
    await tester.pumpAndSettle();
    expect(find.text('101 of 101 checked'), findsOneWidget);
    await tester.enterText(find.byType(EditableText).last, '');
    await tester.pumpAndSettle();
    await tester.tap(action('Next Page'));
    await tester.pumpAndSettle();
    final box = find.byWidgetPredicate(
      (w) => w is ModelCheckbox && w.semanticLabel == 'm100',
    );
    expect(tester.widget<ModelCheckbox>(box).checked, isTrue);
    await tester.tap(find.text('m100'));
    await tester.pump();
    expect(tester.widget<ModelCheckbox>(box).checked, isFalse);
    await tester.tap(action('Selection scope'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select None'));
    await tester.pumpAndSettle();
    expect(find.text('0 of 101 checked'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'top-level checkbox aligns with rows and toggles all model pages',
    (tester) async {
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
      // The actual 16px boxes, not just their expanded hit targets, align.
      Finder glyph(Finder checkbox) => find.descendant(
        of: checkbox,
        matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.constraints?.minWidth == 16 &&
              w.constraints?.minHeight == 16,
        ),
      );
      expect(
        tester.getCenter(glyph(header('Select All'))).dx,
        closeTo(tester.getCenter(glyph(header('m0'))).dx, .01),
      );
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
      expect(tester.widget<ModelCheckbox>(header('m100')).checked, isTrue);
      await tester.tap(find.text('Test This Model'));
      await tester.pumpAndSettle();
      expect(tested, hasLength(101));
      expect(tested, contains('m100'));
      expect(tester.widget<Text>(find.text('OK')).maxLines, 1);
      // Compact rows keep the full selection hot area minus their divider.
      expect(tester.getRect(header('m100')).height, 31);
      await tester.tap(header('Select None'));
      await tester.pump();
      expect(tester.widget<ModelCheckbox>(header('m100')).checked, isFalse);
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is IdeActionButton && w.tooltip == 'Previous Page',
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<ModelCheckbox>(header('m0')).checked, isFalse);
      expect(
        tester.widget<ModelCheckbox>(header('Select All')).checked,
        isFalse,
      );
      expect(find.text('1 / 2 · 101'), findsOneWidget);
      expect(find.textContaining('No tools'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
