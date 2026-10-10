import 'dart:async';

import 'package:baocode/ide/ide_hover.dart';
import 'package:baocode/kernel/claude_code/claude_haiku.dart';
import 'package:baocode/models/codex/codex_service.dart';
import 'package:baocode/models/codex/codex_usage.dart';
import 'package:baocode/models/model_provider.dart';
import 'package:baocode/models/model_providers.dart';
import 'package:baocode/models/secret_store.dart';
import 'package:baocode/models/upstream.dart';
import 'package:baocode/settings/pages/model_dialogs.dart';
import 'package:baocode/settings/pages/models_page.dart';
import 'package:baocode/settings/pages/settings_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Accounts signed in to by hand: [finish] ends the sign-in under way.
class _FakeCodex extends CodexService {
  _FakeCodex(this.providers);

  final ModelProviders providers;
  final Map<String, CodexUsage> usages = {};
  final List<String> removed = [];
  int refreshed = 0;
  Completer<ProviderAccount>? _pending;

  /// Whether sign-in finds its port free.
  bool listening = true;
  _FakeLogin? last;

  void finish(ProviderAccount account) => _pending!.complete(account);

  @override
  Future<CodexLogin> login(String providerId) async {
    final pending = _pending = Completer();
    return last = _FakeLogin(
      pending.future.then((account) async {
        await providers.save(
          providers.provider(providerId)!.withAccount(account),
        );
        notifyListeners();
        return account;
      }),
      () {
        if (!pending.isCompleted) pending.completeError(const CodexCancelled());
      },
    )..listening = listening;
  }

  @override
  Future<void> refreshUsage(ModelProvider provider) async => refreshed++;

  @override
  CodexUsage? usage(String providerId, String accountId) => usages[accountId];

  @override
  String? error(String providerId, String accountId) =>
      accountId == 'b' ? 'Signed out: sign in again.' : null;

  @override
  DateTime? limitedUntil(String providerId, String accountId) => null;

  @override
  Future<void> removeAccount(String providerId, String accountId) async {
    removed.add(accountId);
    final provider = providers.provider(providerId)!;
    await providers.save(
      provider.copyWith(
        accounts: [
          for (final account in provider.accounts)
            if (account.id != accountId) account,
        ],
      ),
    );
  }
}

class _FakeLogin implements CodexLogin {
  _FakeLogin(this.result, this._cancel);

  @override
  final Uri url = Uri.parse('https://auth.openai.com/oauth/authorize?x=1');
  @override
  final Future<ProviderAccount> result;
  final void Function() _cancel;
  final submitted = <String>[];

  @override
  bool listening = true;

  @override
  void submit(String callback) => submitted.add(callback);

  @override
  void cancel() => _cancel();
}

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

  Future<void> pump(
    WidgetTester tester, {
    CodexService? codex,
    ModelTester testModel = testModelThroughClaudeCode,
  }) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModelsSettingsPage(
            providers: providers,
            listModels: list,
            testModel: testModel,
            codex: codex,
          ),
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

    // Only those checked are listed, unless all are shown.
    expect(find.text('o3'), findsNothing);
    await tester.tap(find.text('Show All (3)'));
    await tester.pumpAndSettle();
    expect(find.text('o3'), findsOneWidget);
    await tester.tap(find.text('Show Checked Only'));
    await tester.pumpAndSettle();
    expect(find.text('o3'), findsNothing);

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

  testWidgets('an auxiliary model is picked', (tester) async {
    await providers.save(
      const ModelProvider(
        id: 'gw',
        name: 'Gateway',
        baseUrl: 'https://gw.example.com',
        models: [ProviderModel(id: 'flash', label: 'Flash')],
      ),
    );
    await pump(tester);
    expect(find.text('Auxiliary Model'), findsOneWidget);
    await tester.tap(find.text('Automatic'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gateway').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Flash').last);
    await tester.pumpAndSettle();
    expect(providers.auxiliaryModel, '@gw/flash');
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
    // An effort taken off, a context added: its own lists.
    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is IdeActionButton && widget.tooltip == 'Remove Max',
      ),
    );
    await tester.pump();
    await tester.enterText(fields.at(4), '64k');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.ensureVisible(find.text('Does not take images'));
    await tester.tap(find.text('Does not take images'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      providers.provider('gw')!.models.single,
      const ProviderModel(
        id: 'my-model',
        label: 'Mine',
        contextWindow: 128000,
        efforts: ['none', 'low', 'medium', 'high', 'xhigh'],
        contexts: [
          64000,
          200000,
          256000,
          300000,
          400000,
          500000,
          800000,
          1000000,
        ],
        images: false,
        custom: true,
      ),
    );
    expect(find.text('Manual'), findsOneWidget);
    expect(find.text('Does not take images'), findsOneWidget);
    expect(find.text('128K'), findsOneWidget);
  });

  testWidgets('a model is tested from its menu, those listed all at once', (
    tester,
  ) async {
    await providers.save(
      const ModelProvider(
        id: 'gw',
        name: 'Gateway',
        baseUrl: 'https://gw.example.com',
        models: [
          ProviderModel(id: 'up'),
          ProviderModel(id: 'down'),
        ],
      ),
    );
    final asked = <String>[];
    final replies = <String, Completer<ClaudeTimedAnswer>>{};
    var cancelled = false;
    Future<ClaudeTimedAnswer> testModel(
      ModelProvider provider,
      ProviderModel model, {
      Future<void>? cancel,
    }) {
      asked.add('${provider.id}/${model.id}');
      unawaited(cancel?.then((_) => cancelled = true));
      return (replies[model.id] = Completer()).future;
    }

    // First text at 0.8s, the rest at 50 tokens a second.
    const answer = ClaudeTimedAnswer(
      '1 2 3',
      firstText: Duration(milliseconds: 800),
      lastText: Duration(milliseconds: 2800),
      outputTokens: 100,
    );
    final timed = find.text('First token 0.8s · 50 tok/s');
    await pump(tester, testModel: testModel);
    await tester.tap(find.text('Gateway'));
    await tester.pumpAndSettle();

    await tester.tap(
      find
          .byWidgetPredicate(
            (widget) =>
                widget is IdeActionButton && widget.tooltip == 'More Actions',
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test'));
    // Run as the menu has closed.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(asked, ['gw/up']);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    replies['up']!.complete(answer);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(timed, findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is IdeHover && w.message == 'Total 2.8s\n\n1 2 3',
      ),
      findsOneWidget,
    );

    // All of them; one fails, and says why.
    await tester.tap(find.text('Test All'));
    await tester.pump();
    expect(asked, ['gw/up', 'gw/up', 'gw/down']);
    expect(find.byType(CircularProgressIndicator), findsNWidgets(2));
    replies['up']!.complete(answer);
    replies['down']!.completeError(Exception('401 Unauthorized'));
    await tester.pump();
    expect(timed, findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is IdeHover && '${w.message}'.contains('401 Unauthorized'),
      ),
      findsOneWidget,
    );

    // A test under way stops as the page closes.
    await tester.tap(find.text('Test All'));
    await tester.pump();
    expect(cancelled, isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(cancelled, isTrue);
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

  testWidgets('a ChatGPT upstream signs in to accounts, shows their quota, '
      'and balances them', (tester) async {
    await providers.save(
      const ModelProvider(
        id: 'cx',
        name: 'ChatGPT',
        protocol: ProviderProtocol.codex,
        accounts: [
          ProviderAccount(id: 'a', email: 'a@example.com', plan: 'plus'),
        ],
      ),
    );
    final codex = _FakeCodex(providers);
    codex.usages['a'] = CodexUsage(
      at: DateTime.now(),
      primary: CodexWindow(
        usedPercent: 42,
        minutes: 300,
        resetsAt: DateTime.now().add(const Duration(minutes: 90)),
      ),
      secondary: const CodexWindow(usedPercent: 7, minutes: 10080),
    );
    await pump(tester, codex: codex);
    expect(find.textContaining('1 account'), findsOneWidget);
    await tester.tap(find.text('ChatGPT'));
    await tester.pumpAndSettle();

    // Signed in to, not a URL and a key.
    expect(find.text('Base URL'), findsNothing);
    expect(find.text('API Key'), findsNothing);
    expect(codex.refreshed, 1);
    expect(find.text('a@example.com'), findsOneWidget);
    expect(find.text('Plus'), findsOneWidget);
    expect(find.text('5h'), findsOneWidget);
    expect(find.text('Weekly'), findsOneWidget);
    expect(find.textContaining('42% used · resets in 1 h '), findsOne);
    expect(find.text('7% used'), findsOneWidget);
    // One account: nothing to balance.
    expect(find.text('Load Balancing'), findsNothing);

    await tester.tap(find.text('Add Account').last);
    await tester.pumpAndSettle();
    expect(find.text('Waiting for sign-in…'), findsOneWidget);
    expect(find.text('Copy Link'), findsOneWidget);
    codex.finish(const ProviderAccount(id: 'b', email: 'b@example.com'));
    await tester.pumpAndSettle();
    expect(find.text('Waiting for sign-in…'), findsNothing);
    expect(find.text('b@example.com'), findsOneWidget);
    expect(find.text('Signed out: sign in again.'), findsOneWidget);
    expect(find.text('Quota not known yet'), findsNothing);

    // Two: balanced, as picked.
    expect(find.text('Load Balancing'), findsOneWidget);
    expect(find.text('Round Robin'), findsOneWidget);
    await tester.tap(find.text('Round Robin'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Most Remaining').last);
    await tester.pumpAndSettle();
    expect(providers.provider('cx')!.balance, AccountBalance.mostRemaining);

    await tester.tap(find.bySemanticsLabel('Use a@example.com'));
    await tester.pumpAndSettle();
    expect(providers.provider('cx')!.account('a')!.enabled, isFalse);

    await tester.tap(find.byTooltip('Remove account').last);
    await tester.pumpAndSettle();
    expect(find.text('Remove “b@example.com”?'), findsOneWidget);
    await tester.tap(find.text('Remove account').last);
    await tester.pumpAndSettle();
    expect(codex.removed, ['b']);
    expect(providers.provider('cx')!.accounts.map((a) => a.id), ['a']);
  });

  testWidgets('signing in can be cancelled', (tester) async {
    await providers.save(
      const ModelProvider(
        id: 'cx',
        name: 'ChatGPT',
        protocol: ProviderProtocol.codex,
      ),
    );
    final codex = _FakeCodex(providers);
    await pump(tester, codex: codex);
    await tester.tap(find.text('ChatGPT'));
    await tester.pumpAndSettle();
    expect(find.text('No account yet'), findsOneWidget);
    await tester.tap(find.text('Add Account').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Waiting for sign-in…'), findsNothing);
    expect(find.textContaining('Sign-in failed'), findsNothing);
  });

  testWidgets('with the port taken, the address signed in to is pasted', (
    tester,
  ) async {
    await providers.save(
      const ModelProvider(
        id: 'cx',
        name: 'ChatGPT',
        protocol: ProviderProtocol.codex,
      ),
    );
    final codex = _FakeCodex(providers)..listening = false;
    await pump(tester, codex: codex);
    await tester.tap(find.text('ChatGPT'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Account').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Port 1455'), findsOneWidget);
    expect(find.text('Address after sign-in'), findsOneWidget);
    await tester.ensureVisible(find.text('Address after sign-in'));
    await tester.pumpAndSettle();
    // The last field: the name's, then the address's.
    final address = find.byType(EditableText).last;
    await tester.tap(address);
    await tester.enterText(
      address,
      'http://localhost:1455/auth/callback?code=c&state=s',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(codex.last!.submitted, [
      'http://localhost:1455/auth/callback?code=c&state=s',
    ]);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Address after sign-in'), findsNothing);
  });
}
