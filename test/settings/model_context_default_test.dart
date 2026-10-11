import 'package:baocode/models/model_provider.dart';
import 'package:baocode/models/model_providers.dart';
import 'package:baocode/models/upstream.dart';
import 'package:baocode/settings/pages/model_dialogs.dart';
import 'package:baocode/settings/pages/models_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const provider = ModelProvider(id: 'p', name: 'Contexts');
  for (final example in <(String, ProviderModel?, String, int?)>[
    ('new model', null, '200K', null),
    ('inherited default', const ProviderModel(id: 'model'), '200K', null),
    (
      'reported context',
      const ProviderModel(id: 'model', contextWindow: 128000),
      '128K',
      128000,
    ),
    (
      'offered context',
      const ProviderModel(id: 'model', contexts: [64000, 128000]),
      '64K',
      null,
    ),
  ]) {
    testWidgets(
      '${example.$1} is prefilled without pinning inherited defaults',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        ProviderModel? saved;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    saved = await showModelEditDialog(
                      context,
                      provider: provider,
                      model: example.$2,
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        final contextField = find.descendant(
          of: find.bySemanticsLabel('Default Context'),
          matching: find.byType(EditableText),
        );
        expect(
          tester.widget<EditableText>(contextField).controller.text,
          example.$3,
        );
        if (example.$2 == null) {
          await tester.enterText(
            find.descendant(
              of: find.bySemanticsLabel('Model ID'),
              matching: find.byType(EditableText),
            ),
            'new-model',
          );
        }
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(saved, isNotNull);
        expect(saved!.contextWindow, example.$4);
        expect(
          saved!.initialContext,
          example.$2?.initialContext ?? ProviderModel.defaultContext,
        );
        if (example.$2 == null) {
          final discovered = mergeModelList(
            [saved!],
            const [RemoteModel('new-model', contextWindow: 400000)],
          );
          expect(discovered.single.contextWindow, 400000);
        }
      },
    );
  }

  testWidgets(
    'context can be explicitly changed and cleared back to automatic',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var model = const ProviderModel(id: 'model');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  model =
                      await showModelEditDialog(
                        context,
                        provider: provider,
                        model: model,
                      ) ??
                      model;
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      Finder input() => find.descendant(
        of: find.bySemanticsLabel('Default Context'),
        matching: find.byType(EditableText),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(input(), '128K');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(model.contextWindow, 128000);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(tester.widget<EditableText>(input()).controller.text, '128K');
      await tester.enterText(input(), '');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(model.contextWindow, isNull);
      expect(model.initialContext, 200000);
    },
  );

  testWidgets(
    'model list shows the effective context instead of an unknown dash',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final providers = ModelProviders.memory(
        providers: [
          provider.copyWith(
            models: const [
              ProviderModel(id: 'default'),
              ProviderModel(id: 'reported', contextWindow: 400000),
              ProviderModel(id: 'offered', contexts: [64000]),
            ],
          ),
        ],
      );
      addTearDown(providers.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ModelsSettingsPage(providers: providers)),
        ),
      );
      await tester.tap(find.text('Contexts'));
      await tester.pumpAndSettle();
      expect(find.text('200K'), findsOneWidget);
      expect(find.text('400K'), findsOneWidget);
      expect(find.text('64K'), findsOneWidget);
    },
  );
}
