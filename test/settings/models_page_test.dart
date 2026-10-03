import 'package:baocode/models/model_provider.dart';
import 'package:baocode/models/model_providers.dart';
import 'package:baocode/models/secret_store.dart';
import 'package:baocode/models/upstream.dart';
import 'package:baocode/settings/pages/model_dialogs.dart';
import 'package:baocode/settings/pages/models_page.dart';
import 'package:baocode/settings/pages/settings_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ModelProviders providers;
  late MemorySecretStore secrets;
  late List<(String, String?)> listed;

  setUp(() {
    secrets = MemorySecretStore();
    providers = ModelProviders.memory(secrets: secrets);
    listed = [];
  });

  Future<List<RemoteModel>> list(ModelProvider provider, String? key) async {
    listed.add((provider.id, key));
    return const [
      RemoteModel('gpt-5', contextWindow: 400000),
      RemoteModel('gpt-5-mini'),
      RemoteModel('o3'),
    ];
  }

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModelsSettingsPage(providers: providers, listModels: list),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> type(WidgetTester tester, String field, String text) async {
    final input = find.descendant(
      of: find.bySemanticsLabel(field),
      matching: find.byType(EditableText),
    );
    await tester.tap(input.first);
    await tester.enterText(input.first, text);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
  }

  testWidgets('the built-in provider is listed, hidden but not removed', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Models'), findsWidgets);
    expect(find.text("Claude Code (this machine's setup)"), findsOneWidget);
    expect(find.text('Built-in'), findsOneWidget);
    await tester.tap(find.byType(SettingsSwitch));
    await tester.pump();
    expect(providers.builtinHidden, isTrue);
    await tester.tap(find.text("Claude Code (this machine's setup)"));
    await tester.pump();
    // No page of its own to open, nor delete.
    expect(find.text('Connection'), findsNothing);
  });

  testWidgets('an upstream is added, set up, its models fetched and its '
      'roles picked', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Add Upstream').last);
    await tester.pumpAndSettle();
    expect(find.text('Connection'), findsOneWidget);
    final id = providers.providers.single.id;
    expect(providers.providers.single.disableNonessentialTraffic, isTrue);

    await type(tester, 'Name', 'Gateway');
    expect(providers.provider(id)!.name, 'Gateway');

    // OpenAI's Chat Completions, through the proxy.
    await tester.tap(find.text('Anthropic-compatible'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OpenAI Chat Completions').last);
    await tester.pumpAndSettle();
    expect(providers.provider(id)!.protocol, ProviderProtocol.openaiChat);

    await type(tester, 'Base URL', 'https://gw.example.com/v1');
    expect(providers.provider(id)!.baseUrl, 'https://gw.example.com/v1');

    // The key goes to the keychain, not the settings.
    await type(tester, 'API Key', 'sk-secret');
    await tester.pump();
    expect(await secrets.read('provider.$id'), 'sk-secret');
    expect(
      providers.provider(id)!.toJson().toString(),
      isNot(contains('sk-secret')),
    );

    await tester.tap(find.text('Test Connection').last);
    await tester.pumpAndSettle();
    expect(listed.last, (id, 'sk-secret'));
    expect(find.text('Connected: the upstream lists 3 models.'), findsOne);

    // Fetched, two of them checked.
    await tester.tap(find.text('Fetch from Upstream…'));
    await tester.pumpAndSettle();
    expect(find.byType(FetchModelsDialog), findsOneWidget);
    expect(find.text('0 of 3 checked'), findsOneWidget);
    await tester.enterText(find.byType(EditableText).last, 'gpt');
    await tester.pumpAndSettle();
    expect(find.text('o3'), findsNothing);
    await tester.tap(find.text('Select All'));
    await tester.pumpAndSettle();
    expect(find.text('2 of 3 checked'), findsOneWidget);
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    final provider = providers.provider(id)!;
    expect(provider.models.map((m) => (m.id, m.enabled)), [
      ('gpt-5', true),
      ('gpt-5-mini', true),
      ('o3', false),
    ]);
    expect(provider.models.first.contextWindow, 400000);
    expect(find.text('400K'), findsOneWidget);

    // Haiku unset: warned.
    expect(
      find.textContaining('Unset, background work runs on the model picked'),
      findsOneWidget,
    );
    final haiku = find.ancestor(
      of: find.text('Haiku Tier'),
      matching: find.byType(Row),
    );
    await tester.tap(
      find.descendant(of: haiku.first, matching: find.text('Unset')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('gpt-5-mini').last);
    await tester.pumpAndSettle();
    expect(providers.provider(id)!.roles.haiku, 'gpt-5-mini');
    expect(
      find.textContaining('Unset, background work runs on the model picked'),
      findsNothing,
    );
  });

  testWidgets('a model is picked for commit messages', (tester) async {
    await providers.save(
      const ModelProvider(
        id: 'gw',
        name: 'Gateway',
        baseUrl: 'https://gw.example.com',
        models: [ProviderModel(id: 'flash', label: 'Flash')],
      ),
    );
    await pump(tester);
    expect(find.text('Commit Message Model'), findsOneWidget);
    await tester.tap(find.text('Same as new sessions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gateway').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Flash').last);
    await tester.pumpAndSettle();
    expect(providers.commitMessageModel, '@gw/flash');
    expect(find.text('Gateway · Flash'), findsOneWidget);
  });

  testWidgets('a model is added by hand, and edited', (tester) async {
    await providers.save(
      const ModelProvider(
        id: 'gw',
        name: 'Gateway',
        protocol: ProviderProtocol.openaiResponses,
        baseUrl: 'https://gw.example.com/v1',
      ),
    );
    await pump(tester);
    await tester.tap(find.text('Gateway'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No models yet'), findsOneWidget);

    await tester.tap(find.text('Add Model…'));
    await tester.pumpAndSettle();
    expect(find.byType(ModelEditDialog), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    // An id is needed.
    expect(find.byType(ModelEditDialog), findsOneWidget);

    final fields = find.descendant(
      of: find.byType(ModelEditDialog),
      matching: find.byType(EditableText),
    );
    await tester.enterText(fields.at(0), 'my-model');
    await tester.enterText(fields.at(1), 'Mine');
    await tester.enterText(fields.at(2), '128k');
    await tester.tap(find.text('Supports thinking (its effort can be picked)'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      providers.provider('gw')!.models.single,
      const ProviderModel(
        id: 'my-model',
        label: 'Mine',
        contextWindow: 128000,
        thinking: true,
        custom: true,
      ),
    );
    expect(find.text('Manual'), findsOneWidget);
    expect(find.text('128K'), findsOneWidget);
  });

  testWidgets('deleting an upstream asks first, and takes its key', (
    tester,
  ) async {
    await providers.save(const ModelProvider(id: 'gw', name: 'Gateway'));
    await providers.setKey('gw', 'sk');
    await pump(tester);
    await tester.tap(find.text('Gateway'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Delete Upstream').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete Upstream').last);
    await tester.pumpAndSettle();
    expect(find.text('Delete “Gateway”?'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(providers.providers, isEmpty);
    expect(await secrets.read('provider.gw'), isNull);
    expect(find.text('Add Upstream'), findsWidgets);
  });
}
