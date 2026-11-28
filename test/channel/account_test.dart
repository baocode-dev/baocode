import 'package:baocode/channel/account/account_api.dart';
import 'package:baocode/channel/account/channel_account.dart';
import 'package:baocode/channel/account/newapi_adapter.dart';
import 'package:baocode/channel/account/sub2api_adapter.dart';
import 'package:baocode/channel/channel_gate.dart';
import 'package:baocode/channel/channel_setup.dart';
import 'package:baocode/models/model_provider.dart';
import 'package:baocode/models/model_providers.dart';
import 'package:baocode/models/upstream.dart';
import 'package:baocode/l10n/l10n.dart';
import 'package:baocode/settings/pages/channel_account_page.dart';
import 'package:baocode/settings/pages/settings_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'account_fakes.dart';

final _newApi = ChannelAccountSite.parse({
  'type': 'newapi',
  'url': 'https://panel.example/console',
  'apiUrl': 'https://api.example',
})!;

final _sub2api = ChannelAccountSite.parse({
  'type': 'sub2api',
  'url': 'https://sub.example',
})!;

void main() {
  group('NewApiAdapter', () {
    late FakeSite site;
    late List<String?> kept;
    late NewApiAdapter adapter;

    setUp(() {
      site = newApiSite();
      kept = [];
      adapter = NewApiAdapter(
        site: _newApi,
        send: site.send,
        credential: 'r0',
        onCredential: kept.add,
      );
    });

    test('is signed in once the window has its session cookie', () async {
      final window = FakeLoginWindow();
      expect(await adapter.signedIn(window), isNull);
      window.cookieJar = {'session': 'x', 'new_api_refresh': 'r0'};
      expect(await adapter.signedIn(window), 'r0');
    });

    test('trades its session as the pages do, keeping the next', () async {
      final profile = await adapter.profile();
      final refresh = site.sent.first;
      expect(
        refresh.url,
        Uri.parse('https://panel.example/api/user/auth/refresh'),
      );
      expect(refresh.headers, {
        'Cookie': 'new_api_refresh=r0',
        'Origin': 'https://panel.example',
      });
      expect(kept, ['r1']);
      expect(adapter.credential, 'r1');
      final self = site.sent.firstWhere((s) => s.url.path == '/api/user/self');
      expect(self.headers['Authorization'], 'Bearer jwt1');
      expect(profile.email, 'leo@example.com');
      // 1 250 000 quota at 500 000 a dollar.
      expect(profile.balance, 2.5);
      // The access token kept while good.
      await adapter.keys();
      expect(site.paths.where((p) => p.endsWith('/refresh')), hasLength(1));
    });

    test(
      'lists keys masked, each revealed with the sk- the pages show',
      () async {
        final keys = await adapter.keys();
        expect(keys.single.id, '7');
        expect(keys.single.name, 'main');
        expect(keys.single.masked, 'sk-abcd**********wxyz');
        expect(await adapter.reveal(keys.single), 'sk-abcdWHOLEwxyz');
        expect(adapter.protocolFor(keys.single), ProviderProtocol.anthropic);
      },
    );

    test('lists the groups, and makes a key in the one picked', () async {
      final groups = await adapter.groups();
      expect([for (final g in groups) g.id], ['default', 'vip', 'auto']);
      expect(groups.first.description, 'Default');
      expect(groups[1].rate, .5);
      expect(groups[1].description, isNull);
      expect(groups.last.rate, isNull);
      await adapter.create('Cheap', group: groups[1]);
      final create = site.sent.firstWhere(
        (s) => s.method == 'POST' && s.url.path == '/api/token/',
      );
      expect(create.json, containsPair('group', 'vip'));
    });

    test('makes a key, unlimited and never ending', () async {
      final made = await adapter.create('BaoCode');
      expect(made.id, '8');
      final create = site.sent.firstWhere(
        (s) => s.method == 'POST' && s.url.path == '/api/token/',
      );
      expect(create.json, containsPair('unlimited_quota', true));
      expect(create.json, containsPair('expired_time', -1));
    });

    test('signs out on the site too, and forgets', () async {
      await adapter.profile();
      await adapter.signOut();
      final logout = site.sent.last;
      expect(logout.url.path, '/api/user/auth/logout');
      expect(logout.headers['Cookie'], 'new_api_refresh=r1');
      expect(logout.headers['Authorization'], 'Bearer jwt1');
      expect(adapter.credential, isNull);
      expect(kept.last, isNull);
    });

    test('a session ended on the site is signed out', () async {
      adapter.credential = 'revoked';
      await expectLater(adapter.profile(), throwsA(isA<AccountSignedOut>()));
      expect(adapter.credential, isNull);
      expect(kept, [null]);
    });
  });

  group('Sub2ApiAdapter', () {
    late FakeSite site;
    late Sub2ApiAdapter adapter;

    setUp(() {
      site = sub2apiSite();
      adapter = Sub2ApiAdapter(
        site: _sub2api,
        send: site.send,
        credential: 'rt0',
      );
    });

    test('is signed in once its page keeps a refresh token', () async {
      final window = FakeLoginWindow();
      expect(await adapter.signedIn(window), isNull);
      window.storage['refresh_token'] = 'rt0';
      expect(await adapter.signedIn(window), 'rt0');
    });

    test('trades the refresh token for the next, and reads the user', () async {
      final profile = await adapter.profile();
      expect(site.sent.first.json, {'refresh_token': 'rt0'});
      expect(adapter.credential, 'rt1');
      expect(site.sent.last.headers['Authorization'], 'Bearer a1');
      expect(profile.balance, 12.5);
      expect(profile.name, 'sub@example.com');
    });

    test('speaks to a key as its group\'s platform does', () async {
      final key = (await adapter.keys()).single;
      expect(key.platform, 'openai');
      expect(key.masked, isNot(contains('0123456789abcdef')));
      expect(adapter.protocolFor(key), ProviderProtocol.openaiResponses);
      expect(
        adapter.protocolFor(
          const AccountKey(
            id: 'g',
            name: 'G',
            masked: '***',
            platform: 'gemini',
          ),
        ),
        ProviderProtocol.gemini,
      );
      expect(await adapter.reveal(key), 'sk-0123456789abcdef0123');
    });

    test(
      'makes a key in an Anthropic group, with an idempotency key',
      () async {
        await adapter.create('BaoCode');
        final create = site.sent.firstWhere(
          (s) => s.method == 'POST' && s.url.path == '/api/v1/keys',
        );
        expect(create.json, {'name': 'BaoCode', 'group_id': 5});
        expect(create.headers['Idempotency-Key'], hasLength(32));
      },
    );

    test('lists the groups at their prices, and makes a key in the one '
        'picked', () async {
      final groups = await adapter.groups();
      expect([for (final g in groups) g.name], ['Codex', 'Claude']);
      expect(groups.last.rate, 1.5);
      expect(groups.last.description, 'Claude models');
      expect(groups.last.platform, 'anthropic');
      await adapter.create('Codex', group: groups.first);
      final create = site.sent.firstWhere(
        (s) => s.method == 'POST' && s.url.path == '/api/v1/keys',
      );
      expect(create.json, {'name': 'Codex', 'group_id': 2});
    });

    test('signs out with the refresh token', () async {
      await adapter.signOut();
      expect(site.sent.last.json, {'refresh_token': 'rt0'});
      expect(adapter.credential, isNull);
    });
  });

  group('ChannelAccount', () {
    late FakeSite site;
    late MemoryChannelAccountStore store;
    late ModelProviders providers;
    late List<FakeLoginWindow> windows;

    ChannelAccount accountOf(ChannelAccountSite on) => ChannelAccount(
      site: on,
      channelName: 'Example',
      store: store,
      send: site.send,
      listModels: (provider, key) async {
        expect(key, startsWith('sk-'));
        return const [
          RemoteModel('claude-haiku-4-5'),
          RemoteModel('claude-sonnet-4-5'),
          RemoteModel('gpt-image-1'),
        ];
      },
      providers: () => providers,
      openWindow: () {
        final window = FakeLoginWindow();
        windows.add(window);
        return window;
      },
      pollInterval: const Duration(milliseconds: 5),
    );

    setUp(() {
      site = newApiSite();
      store = MemoryChannelAccountStore();
      providers = ModelProviders.memory();
      windows = [];
    });

    test('signs in in the window, then calls the models with a key', () async {
      final account = accountOf(_newApi);
      await account.load();
      expect(account.signedIn, isFalse);
      final signingIn = account.signIn(title: 'Example');
      await pumpEventQueue();
      final window = windows.single;
      expect(window.opened, Uri.parse('https://panel.example/login'));
      window.cookieJar = {'new_api_refresh': 'r0'};
      expect(await signingIn, isTrue);
      expect(window.shut, isTrue);

      expect(account.signedIn, isTrue);
      expect(store.credential, 'r1');
      expect(account.profile!.email, 'leo@example.com');
      expect(account.inUse!.id, '7');
      final upstream = providers.provider(ChannelAccount.providerId)!;
      expect(upstream.baseUrl, 'https://api.example');
      expect(upstream.protocol, ProviderProtocol.anthropic);
      expect(
        await providers.key(ChannelAccount.providerId),
        'sk-abcdWHOLEwxyz',
      );
      expect(
        [for (final m in upstream.enabledModels) m.id],
        ['claude-haiku-4-5', 'claude-sonnet-4-5'],
      );
      expect(providers.defaultModel, '@channel/claude-sonnet-4-5');
      expect(providers.builtinHidden, isTrue);

      // Read back the next run.
      final again = accountOf(_newApi);
      await again.load();
      expect(again.signedIn, isTrue);
      expect(again.inUse!.id, '7');
      expect(again.profile!.balance, 2.5);
    });

    test('closed before signing in, is not', () async {
      final account = accountOf(_newApi);
      await account.load();
      final signingIn = account.signIn(title: 'Example');
      await pumpEventQueue();
      windows.single.dismiss();
      expect(await signingIn, isFalse);
      expect(account.signedIn, isFalse);
      expect(account.signingIn, isFalse);
    });

    test('makes a key for a user with none', () async {
      site = newApiSite(tokens: []);
      final account = accountOf(_newApi);
      await account.load();
      final signingIn = account.signIn(title: 'Example');
      await pumpEventQueue();
      windows.single.cookieJar = {'new_api_refresh': 'r0'};
      await signingIn;
      expect(account.inUse!.id, '8');
      expect(account.inUse!.name, ChannelAccount.keyName);
    });

    test('another key put to use, and new conversations\' model', () async {
      final account = accountOf(_newApi);
      await account.load();
      final signingIn = account.signIn(title: 'Example');
      await pumpEventQueue();
      windows.single.cookieJar = {'new_api_refresh': 'r0'};
      await signingIn;
      final made = await account.create('second');
      await account.use(made!);
      expect(account.inUse!.id, '8');
      expect(await providers.key(ChannelAccount.providerId), 'sk-newWHOLEkey0');
      await account.setDefaultModel('claude-haiku-4-5');
      expect(account.defaultModel, 'claude-haiku-4-5');
      expect(providers.defaultModel, '@channel/claude-haiku-4-5');
    });

    test('signs out: the session ended, the upstream gone', () async {
      final account = accountOf(_newApi);
      await account.load();
      final signingIn = account.signIn(title: 'Example');
      await pumpEventQueue();
      windows.single.cookieJar = {'new_api_refresh': 'r0'};
      await signingIn;
      await account.signOut();
      expect(site.paths.last, 'POST /api/user/auth/logout');
      expect(account.signedIn, isFalse);
      expect(store.credential, isNull);
      expect(store.state, isNull);
      expect(providers.provider(ChannelAccount.providerId), isNull);
    });

    test('forgets what was kept for another site', () async {
      store
        ..credential = 'r0'
        ..state = {'site': 'https://old.example'};
      final account = accountOf(_newApi);
      await account.load();
      expect(account.signedIn, isFalse);
      expect(store.credential, isNull);
    });

    test('speaks OpenAI\'s Responses to a sub2api key for OpenAI', () async {
      site = sub2apiSite();
      final account = accountOf(_sub2api);
      await account.load();
      final signingIn = account.signIn(title: 'Example');
      await pumpEventQueue();
      windows.single.storage['refresh_token'] = 'rt0';
      await signingIn;
      final upstream = providers.provider(ChannelAccount.providerId)!;
      expect(upstream.protocol, ProviderProtocol.openaiResponses);
      expect(upstream.baseUrl, 'https://sub.example');
    });
  });

  group('ChannelGate', () {
    late MemoryChannelSetupStore setupStore;
    late MemoryChannelAccountStore accountStore;
    late Map<String, Object?> listed;
    late bool offline;
    late FakeSite site;
    final providers = ModelProviders.memory();

    ChannelGate gateOf() => ChannelGate(
      setup: null,
      setupStore: setupStore,
      accountStore: accountStore,
      fetch: (id) async {
        if (offline) throw StateError('offline');
        final json = listed[id];
        return json == null ? null : (id: id, json: json, logo: null);
      },
      makeAccount: (channel) => ChannelAccount(
        site: channel.info.account!,
        channelName: channel.info.name,
        store: accountStore,
        send: site.send,
        listModels: (_, _) async => const [RemoteModel('claude-sonnet-4-5')],
        providers: () => providers,
      ),
    );

    setUp(() {
      setupStore = MemoryChannelSetupStore()
        ..state = ChannelSetup.doneState
        ..attribution = const ChannelAttribution('channel', 'example');
      accountStore = MemoryChannelAccountStore();
      offline = false;
      site = newApiSite();
      listed = {
        'example': {
          'name': {'en': 'Example'},
          'account': {'type': 'newapi', 'url': 'https://panel.example'},
        },
      };
    });

    test(
      'asks for the sign-in once the channel is read, and keeps it',
      () async {
        final gate = gateOf();
        addTearDown(gate.dispose);
        await gate.find('en');
        await gate.fetched;
        expect(gate.stage, ChannelStage.signIn);
        expect(gate.channel!.info.name, 'Example');
        expect(accountStore.entry!.id, 'example');
        expect(ChannelAccount.current, gate.account);
      },
    );

    test('goes by what was kept when the site cannot be read', () async {
      accountStore.entry = (id: 'example', json: listed['example'], logo: null);
      offline = true;
      final gate = gateOf();
      addTearDown(gate.dispose);
      await gate.find('en');
      expect(gate.stage, ChannelStage.signIn);
      await gate.fetched;
      expect(gate.stage, ChannelStage.signIn);
    });

    test('says when there is nothing to go by offline', () async {
      offline = true;
      final gate = gateOf();
      addTearDown(gate.dispose);
      await gate.find('en');
      await gate.fetched;
      expect(gate.stage, ChannelStage.offline);
      offline = false;
      await gate.retry();
      await gate.fetched;
      expect(gate.stage, ChannelStage.signIn);
    });

    test('cannot be used without a channel with an account site', () async {
      for (final (told, entry) in [
        (const ChannelAttribution('direct', null), listed['example']),
        (const ChannelAttribution('channel', 'unknown'), listed['example']),
        (
          const ChannelAttribution('channel', 'example'),
          {
            'name': {'en': 'Example'},
          },
        ),
      ]) {
        setupStore.attribution = told;
        listed = {'example': entry};
        final gate = gateOf();
        await gate.find('en');
        await gate.fetched;
        expect(gate.stage, ChannelStage.unavailable, reason: '$told $entry');
        gate.dispose();
      }
    });

    test('is not set up before its setup is', () {
      setupStore.state = ChannelSetup.pendingState;
      final gate = gateOf();
      addTearDown(gate.dispose);
      expect(gate.stage, ChannelStage.setup);
    });
  });

  testWidgets('Settings → Account shows the user, the model and the keys', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final site = newApiSite();
    final store = MemoryChannelAccountStore();
    final providers = ModelProviders.memory();
    final windows = <FakeLoginWindow>[];
    final gate = ChannelGate(
      setup: null,
      setupStore: MemoryChannelSetupStore()
        ..state = ChannelSetup.doneState
        ..attribution = const ChannelAttribution('channel', 'example'),
      accountStore: store,
      fetch: (id) async => (
        id: id,
        json: {
          'name': {'en': 'Example'},
          'account': {'type': 'newapi', 'url': 'https://panel.example'},
        },
        logo: null,
      ),
      makeAccount: (channel) => ChannelAccount(
        site: channel.info.account!,
        channelName: channel.info.name,
        store: store,
        send: site.send,
        listModels: (_, _) async => const [
          RemoteModel('claude-sonnet-4-5'),
          RemoteModel('claude-haiku-4-5'),
        ],
        providers: () => providers,
        openWindow: () {
          final window = FakeLoginWindow()
            ..cookieJar = {'new_api_refresh': 'r0'};
          windows.add(window);
          return window;
        },
        pollInterval: const Duration(milliseconds: 10),
      ),
    );
    addTearDown(gate.dispose);
    addTearDown(() => ChannelAccount.current = null);
    await tester.runAsync(() async {
      await gate.find('zh');
      await gate.fetched;
      await gate.account!.signIn(title: 'Example');
    });
    expect(gate.ready, isTrue);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: ChannelAccountPage(gate: gate)),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(find.text('账号管理'), findsOneWidget);
    expect(find.text('leo@example.com'), findsOneWidget);
    expect(find.textContaining(r'$2.50', findRichText: true), findsOneWidget);
    expect(find.text('刷新账户'), findsOneWidget);
    expect(find.text('退出登录'), findsOneWidget);
    expect(find.text('新对话默认模型'), findsWidgets);
    expect(find.text('我的 API Key'), findsOneWidget);
    expect(find.text('使用中'), findsOneWidget);
    expect(find.text('创建 Key'), findsOneWidget);

    // A key made in the group picked.
    await tester.tap(find.text('创建 Key'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(find.text('分组'), findsOneWidget);
    expect(find.text('default'), findsOneWidget);
    expect(find.text('Default'), findsOneWidget);
    await tester.tap(find.byType(SettingsDropdown).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('vip  ×0.5').last);
    await tester.pumpAndSettle();
    expect(find.text('vip  ×0.5'), findsOneWidget);
    await tester.tap(find.text('创建 Key').last);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    final create = site.sent.lastWhere(
      (s) => s.method == 'POST' && s.url.path == '/api/token/',
    );
    expect(create.json, containsPair('group', 'vip'));
    expect(create.json, containsPair('name', 'BaoCode'));
    expect(find.text('分组'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
