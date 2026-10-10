import 'dart:io';

import 'package:baocode/ide/ide_hover.dart';
import 'package:baocode/models/model_provider.dart';
import 'package:baocode/models/model_providers.dart';
import 'package:baocode/models/model_test.dart';
import 'package:baocode/models/model_test_preset.dart';
import 'package:baocode/settings/pages/model_test_dialog.dart';
import 'package:baocode/settings/user_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('custom presets and selected ID survive reopening, builtins cannot be changed', () async {
    final dir = await Directory.systemTemp.createTemp('model-presets-');
    addTearDown(() => dir.delete(recursive: true));
    final settings = UserSettings('${dir.path}/settings.json');
    await settings.load();
    final store = ModelProviders.settings(settings);
    addTearDown(store.dispose);
    addTearDown(settings.dispose);
    expect(store.testPresets.length, 2);
    await store.saveTestPreset(
      const ModelTestPreset(
        id: 'custom-one',
        name: 'Greeting',
        prompt: 'Say hello',
      ),
    );
    await store.saveTestPreset(
      const ModelTestPreset(
        id: 'custom-one',
        name: 'Edited',
        prompt: 'Reply yes',
      ),
    );
    await store.deleteTestPreset(ModelTestPreset.shortId);
    await store.saveTestPreset(
      const ModelTestPreset(
        id: ModelTestPreset.numbersId,
        name: 'replace',
        prompt: 'invalid',
      ),
    );
    final reopened = UserSettings('${dir.path}/settings.json');
    await reopened.load();
    final restored = ModelProviders.settings(reopened);
    addTearDown(restored.dispose);
    addTearDown(reopened.dispose);
    expect(restored.testPresets.length, 3);
    expect(restored.selectedTestPreset.name, 'Edited');
    expect(restored.selectedTestPreset.prompt, 'Reply yes');
    expect(restored.testPresets.first.prompt, modelTestPrompt);
    await restored.deleteTestPreset('custom-one');
    expect(restored.selectedTestPreset.id, ModelTestPreset.numbersId);
    expect(restored.testPresets.length, 2);
  });

  testWidgets(
    'add/edit/delete controls and single test share selected preset',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final preferences = ModelProviders.memory();
      addTearDown(preferences.dispose);
      final prompts = <String>[];
      final service = ModelTestService(
        run: (_, _, prompt, _, emit) async {
          prompts.add(prompt);
          emit(const ModelTestEvent(text: 'OK', done: true));
        },
      );
      addTearDown(service.dispose);
      const provider = ModelProvider(
        id: 'p',
        name: 'Custom',
        baseUrl: 'https://example.com',
        models: [ProviderModel(id: 'm')],
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
      Finder action(String tooltip) => find.byWidgetPredicate(
        (w) => w is IdeActionButton && w.tooltip == tooltip,
      );
      expect(
        tester.widget<IdeActionButton>(action('Delete Test Preset')).onPressed,
        isNull,
      );
      await tester.tap(action('Add Test Preset…'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText).last)
            .controller
            .text,
        modelTestPrompt,
      );
      Finder input(String label) => find
          .descendant(
            of: find.bySemanticsLabel(label),
            matching: find.byType(EditableText),
          )
          .last;
      await tester.enterText(input('Name'), 'My prompt');
      await tester.enterText(input('Test Prompt'), 'Return custom');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(preferences.selectedTestPreset.prompt, 'Return custom');
      expect(find.text('My prompt'), findsOneWidget);
      await tester.tap(action('Edit Test Preset…'));
      await tester.pumpAndSettle();
      await tester.enterText(input('Test Prompt'), 'Return edited');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(preferences.testPresets.length, 3);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ModelTestButton(
              service: service,
              provider: provider,
              model: provider.models.first,
              preferences: preferences,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byType(IdeActionButton));
      await tester.pumpAndSettle();
      expect(prompts, ['Return edited']);
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
      expect(find.text('My prompt'), findsOneWidget);
      await tester.tap(action('Delete Test Preset'));
      await tester.pumpAndSettle();
      expect(find.text('Output Numbers 1–120'), findsOneWidget);
      expect(preferences.testPresets.length, 2);
      expect(
        tester.widget<IdeActionButton>(action('Delete Test Preset')).onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
