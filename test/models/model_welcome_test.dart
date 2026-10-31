import 'package:baocode/l10n/l10n.dart';
import 'package:baocode/models/model_provider.dart';
import 'package:baocode/models/model_providers.dart';
import 'package:baocode/models/model_welcome.dart';
import 'package:baocode/settings/pages/models_page.dart';
import 'package:baocode/settings/settings_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ModelProviders providers;
  late List<SettingsSection> opened;

  setUp(() {
    providers = ModelProviders.memory();
    opened = [];
    ModelWelcome.welcomed = false;
  });

  tearDown(() => ModelsSettingsPage.reveal.value = null);

  Future<({Future<void> closed})> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        home: SettingsOpener(
          open: opened.add,
          child: Builder(
            builder: (value) {
              context = value;
              return const Scaffold();
            },
          ),
        ),
      ),
    );
    final closed = showModelWelcome(context, providers: providers);
    await tester.pump();
    // In, the logos then the lines.
    await tester.pump(const Duration(milliseconds: 1500));
    // In, what goes on moves on the shared clock's frames, not every vsync.
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.hasRunningAnimations, isFalse);
    return (closed: closed);
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('says what an upstream is; Add Upstream adds one and opens '
      'its page in Settings → Models', (tester) async {
    final (closed: _) = await open(tester);
    expect(ModelWelcome.welcomed, isTrue);
    expect(find.text('Pick a Model to Start'), findsOneWidget);
    expect(find.text('Any upstream'), findsOneWidget);
    expect(find.text('Your keys stay with you'), findsOneWidget);
    expect(find.text('Switch any time'), findsOneWidget);
    expect(find.text('Add your first upstream'), findsOneWidget);
    expect(find.textContaining('add one later in Settings'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Add Upstream'));
    await tester.tap(find.text('Add Upstream'));
    await settle(tester);
    final added = providers.providers.single;
    expect(added.name, 'New Upstream');
    expect(ModelsSettingsPage.reveal.value, added.id);
    expect(opened, [SettingsSection.models]);
    // Left under the settings, as it was: no model yet.
    expect(find.text('Add your first upstream'), findsOneWidget);
  });

  testWidgets('an upstream with models: the step done, the model new '
      'conversations start on; Start Chatting closes it', (tester) async {
    final (:closed) = await open(tester);
    expect(find.text('Later'), findsOneWidget);
    await providers.save(
      const ModelProvider(
        id: 'up',
        name: 'Upstream',
        baseUrl: 'https://api.example.com',
        models: [ProviderModel(id: 'model-1')],
      ),
    );
    await settle(tester);
    expect(find.text('Ready to go'), findsOneWidget);
    expect(find.textContaining('Upstream · model-1'), findsOneWidget);
    expect(find.text('Add Upstream'), findsNothing);
    expect(find.textContaining('add one later in Settings'), findsNothing);

    await tester.tap(find.text('Start Chatting'));
    await settle(tester);
    await closed;
    expect(find.text('Pick a Model to Start'), findsNothing);
  });

  testWidgets('Later closes it with no model', (tester) async {
    final (:closed) = await open(tester);
    await tester.tap(find.text('Later'));
    await settle(tester);
    await closed;
    expect(find.text('Pick a Model to Start'), findsNothing);
    expect(providers.providers, isEmpty);
  });
}
