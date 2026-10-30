import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:baocode/theme/codicons.dart';
import 'package:baocode/l10n/app_localizations.dart';
import 'package:baocode/models/featured_upstreams.dart';
import 'package:baocode/models/model_icons.dart';
import 'package:baocode/models/model_provider.dart';
import 'package:baocode/models/model_providers.dart';
import 'package:baocode/models/secret_store.dart';
import 'package:baocode/models/upstream.dart';
import 'package:baocode/models/upstream_import.dart';
import 'package:baocode/settings/pages/featured_upstreams_strip.dart';
import 'package:baocode/settings/pages/models_page.dart';
import 'package:baocode/settings/pages/upstream_import_dialog.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _featured = [
  for (final (id, name) in [('alpha', 'Alpha API'), ('beta', 'Beta Relay')])
    FeaturedUpstream(
      id: id,
      name: name,
      url: Uri.parse('https://$id.example.com/register?aff=bao'),
      description: {'en': '$name, cheaply'},
      hosts: ['api.$id.example.com'],
    ),
];

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  late MemorySecretStore secrets;
  late ModelProviders providers;

  setUp(() {
    secrets = MemorySecretStore();
    providers = ModelProviders.memory(secrets: secrets);
  });

  group('the featured row', () {
    testWidgets('a card of each, a click opens its link', (tester) async {
      final opened = <Uri>[];
      await tester.pumpWidget(
        _app(
          FeaturedUpstreamsStrip(
            upstreams: Future.value(_featured),
            random: Random(1),
            open: opened.add,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Alpha API'), findsOneWidget);
      expect(find.text('Beta Relay, cheaply'), findsOneWidget);
      expect(find.text('Why am I seeing this?'), findsOneWidget);
      await tester.tap(find.text('Alpha API'));
      expect(
        opened.single.toString(),
        'https://alpha.example.com/register?aff=bao',
      );
    });

    testWidgets("a card's hover has the site in full; a click on why they "
        'show, how a site gets listed: a button to the page for it', (
      tester,
    ) async {
      final opened = <Uri>[];
      await tester.pumpWidget(
        _app(
          FeaturedUpstreamsStrip(
            upstreams: Future.value(_featured),
            random: Random(1),
            open: opened.add,
          ),
        ),
      );
      await tester.pump();
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(gesture.removePointer);
      await gesture.addPointer(location: Offset.zero);
      // As a mouse clicks: frames drawn between its press and release.
      Future<void> click(Finder finder) async {
        await gesture.moveTo(tester.getCenter(finder));
        await gesture.down(tester.getCenter(finder));
        await tester.pump(const Duration(milliseconds: 80));
        await gesture.up();
        await tester.pump();
      }

      await gesture.moveTo(tester.getCenter(find.text('Alpha API')));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Alpha API'), findsNWidgets(2));
      expect(find.text('Alpha API, cheaply'), findsNWidgets(2));
      expect(find.text('alpha.example.com'), findsOneWidget);
      // Its host, a link to it.
      await gesture.moveTo(tester.getCenter(find.text('alpha.example.com')));
      await tester.pump(const Duration(seconds: 1));
      await click(find.text('alpha.example.com'));
      expect(
        opened.single,
        Uri.parse('https://alpha.example.com/register?aff=bao'),
      );
      await tester.pump(const Duration(seconds: 1));

      await gesture.moveTo(const Offset(790, 590));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('alpha.example.com'), findsNothing);

      // Why they show, at a click, not a hover.
      const why = 'These sites are officially listed by BaoCode';
      await gesture.moveTo(
        tester.getCenter(find.text('Why am I seeing this?')),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(why), findsNothing);
      await click(find.text('Why am I seeing this?'));
      expect(find.text(why), findsOneWidget);
      // Closed by a click elsewhere; the button opens the page for it.
      await click(find.text('Beta Relay'));
      expect(find.text(why), findsNothing);
      await click(find.text('Why am I seeing this?'));
      await click(find.text('List My Site Too'));
      expect(opened.last, Uri.parse('https://baocode.dev/upstreams'));
      expect(find.text(why), findsNothing);
    });

    testWidgets('a user of a listed site sees it first, whatever the draw, '
        'held there while the rest scroll', (tester) async {
      for (final seed in [1, 2, 3, 4]) {
        await tester.pumpWidget(
          _app(
            FeaturedUpstreamsStrip(
              key: ValueKey(seed),
              upstreams: Future.value(_featured),
              hosts: const ['API.beta.example.com', 'api.anthropic.com'],
              random: Random(seed),
            ),
          ),
        );
        await tester.pump();
        expect(
          tester.getTopLeft(find.text('Beta Relay')).dx,
          lessThan(tester.getTopLeft(find.text('Alpha API')).dx),
          reason: 'seed $seed',
        );
      }
      final scrolled = find.byType(ListView);
      expect(
        find.descendant(of: scrolled, matching: find.text('Beta Relay')),
        findsNothing,
      );
      expect(
        find.descendant(of: scrolled, matching: find.text('Alpha API')),
        findsOneWidget,
      );
    });

    testWidgets('nothing, until there are some', (tester) async {
      await tester.pumpWidget(
        _app(FeaturedUpstreamsStrip(upstreams: Future.value(const []))),
      );
      await tester.pump();
      expect(find.byType(ListView), findsNothing);
      expect(find.text('Why am I seeing this?'), findsNothing);
    });

    testWidgets('the order is drawn by chance', (tester) async {
      final many = [
        for (var i = 0; i < 8; i++)
          FeaturedUpstream(
            id: 'u$i',
            name: 'Upstream $i',
            url: Uri.parse('https://u$i.example.com'),
          ),
      ];
      Future<List<String>> order(int seed) async {
        await tester.pumpWidget(
          _app(
            FeaturedUpstreamsStrip(
              key: ValueKey(seed),
              upstreams: Future.value(many),
              random: Random(seed),
            ),
          ),
        );
        await tester.pump();
        final texts = tester
            .widgetList<Text>(find.textContaining('Upstream '))
            .map((text) => text.data!)
            .toList();
        return texts;
      }

      // Those in sight first, which a draw changes.
      expect(await order(1), isNot(await order(2)));
    });

    testWidgets('Settings → Models shows it under the title', (tester) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(
          ModelsSettingsPage(
            providers: providers,
            featured: Future.value(_featured),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Alpha API'), findsOneWidget);
      expect(find.byIcon(Codicons.info), findsNothing);
    });

    testWidgets('Settings → Models shows the list kept at once, the new one '
        'as baocode.dev answers, a site of theirs then leading', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final (id, url) in [
        ('gamma', 'https://api.gamma.example.com'),
        ('beta', 'https://api.beta.example.com'),
      ]) {
        await providers.save(
          ModelProvider(id: id, name: 'Up $id', baseUrl: url),
        );
      }
      final answer = Completer<List<FeaturedUpstream>>();
      FeaturedUpstream.keptLoader = () async => [_featured.first];
      FeaturedUpstream.loader = () => answer.future;
      await tester.pumpWidget(_app(ModelsSettingsPage(providers: providers)));
      await tester.pump();
      double top(String name) => tester.getTopLeft(find.text(name)).dy;
      expect(find.text('Alpha API'), findsOneWidget);
      expect(find.text('Beta Relay'), findsNothing);
      expect(top('Up gamma'), lessThan(top('Up beta')));

      answer.complete(_featured);
      await tester.pump();
      expect(find.text('Beta Relay'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Beta Relay')).dx,
        lessThan(tester.getTopLeft(find.text('Alpha API')).dx),
      );
      expect(top('Up beta'), lessThan(top('Up gamma')));
    });

    testWidgets('the new list keeps those shown in their places', (
      tester,
    ) async {
      final many = [
        for (var i = 0; i < 8; i++)
          FeaturedUpstream(
            id: 'u$i',
            name: 'Upstream $i',
            url: Uri.parse('https://u$i.example.com'),
          ),
      ];
      await tester.pumpWidget(
        _app(
          FeaturedUpstreamsStrip(
            upstreams: Future.value(many),
            follow: true,
            random: Random(1),
          ),
        ),
      );
      await tester.pump();
      List<String> order() => tester
          .widgetList<Text>(find.textContaining('Upstream '))
          .map((text) => text.data!)
          .toList();
      final before = order();
      // The same sites, in another order: as they were.
      FeaturedUpstream.known.value = many.reversed.toList();
      await tester.pump();
      expect(order(), before);
      // None: as they were too.
      FeaturedUpstream.known.value = const [];
      await tester.pump();
      expect(order(), before);
    });
  });

  testWidgets('Settings → Models shows a user of a listed site it first, by '
      'the upstreams they have', (tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await providers.save(
      const ModelProvider(
        id: 'beta',
        name: 'Beta',
        baseUrl: 'https://api.beta.example.com',
      ),
    );
    await tester.pumpWidget(
      _app(
        ModelsSettingsPage(
          providers: providers,
          featured: Future.value(_featured),
        ),
      ),
    );
    await tester.pump();
    expect(
      tester.getTopLeft(find.text('Beta Relay')).dx,
      lessThan(tester.getTopLeft(find.text('Alpha API')).dx),
    );
  });

  testWidgets('Settings → Models lists the upstreams at a listed site first, '
      'each in its order', (tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final (id, url) in [
      ('gamma', 'https://api.gamma.example.com'),
      ('beta', 'https://api.beta.example.com'),
      ('delta', 'https://api.delta.example.com'),
    ]) {
      await providers.save(ModelProvider(id: id, name: 'Up $id', baseUrl: url));
    }
    await tester.pumpWidget(
      _app(
        ModelsSettingsPage(
          providers: providers,
          featured: Future.value(_featured),
        ),
      ),
    );
    await tester.pump();
    double top(String name) => tester.getTopLeft(find.text(name)).dy;
    // One place only, the newest such: beta, added last.
    expect(top('Up beta'), lessThan(top('Up gamma')));
    expect(top('Up gamma'), lessThan(top('Up delta')));
  });

  testWidgets('and it goes to one imported later', (tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final (id, url) in [
      ('gamma', 'https://api.gamma.example.com'),
      ('beta', 'https://api.beta.example.com'),
    ]) {
      await providers.save(ModelProvider(id: id, name: 'Up $id', baseUrl: url));
    }
    await tester.pumpWidget(
      _app(
        ModelsSettingsPage(
          providers: providers,
          featured: Future.value(_featured),
        ),
      ),
    );
    await tester.pump();
    double top(String name) => tester.getTopLeft(find.text(name)).dy;
    expect(top('Up beta'), lessThan(top('Up gamma')));
    // One added later at a listed site takes the place.
    await providers.save(
      const ModelProvider(
        id: 'zeta',
        name: 'Up zeta',
        baseUrl: 'https://api.beta.example.com',
      ),
    );
    await tester.pumpWidget(
      _app(
        ModelsSettingsPage(
          providers: providers,
          featured: Future.value(_featured),
        ),
      ),
    );
    await tester.pump();
    expect(top('Up zeta'), lessThan(top('Up beta')));
    // The rest, in their order as added: gamma before beta.
    expect(top('Up gamma'), lessThan(top('Up beta')));
  });

  testWidgets("an upstream at a listed site shows the logo it is listed with", (
    tester,
  ) async {
    FeaturedUpstream.known.value = [
      FeaturedUpstream(
        id: 'ymeng',
        name: 'YMeng CC',
        url: Uri.https('ymeng.cc'),
        logo: 'site/featured/ymeng.png',
        hosts: const ['api.ymeng.cc'],
      ),
    ];
    await tester.pumpWidget(
      _app(
        Column(
          children: [
            ProviderIconView(
              icon: null,
              site: Uri.https('api.ymeng.cc'),
              size: 16,
            ),
            ProviderIconView(
              icon: null,
              site: Uri.https('api.other.example.com'),
              size: 16,
            ),
          ],
        ),
      ),
    );
    final logos = tester.widgetList<Image>(find.byType(Image));
    expect(
      [
        for (final logo in logos)
          if (logo.image case FileImage(:final file)) file.path,
      ],
      ['site/featured/ymeng.png'],
    );
    expect(find.byIcon(Codicons.globe), findsOneWidget);
  });

  group('the import', () {
    late List<String?> listedWith;
    setUp(() => listedWith = []);

    Future<String?> run(
      WidgetTester tester,
      String link, {
      String? button,
      String? rename,
      List<String> check = const [],
      String fetchButton = 'Import',
      bool unlisted = false,
    }) async {
      String? result;
      var done = false;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showUpstreamImportDialog(
                  context,
                  UpstreamImport.parse(link)!,
                  providers: providers,
                  featured: Future.value(_featured),
                  list: (provider, key) async {
                    listedWith.add(key);
                    if (unlisted) throw const HttpException('404');
                    return const [
                      RemoteModel('claude-opus-4-1'),
                      RemoteModel('claude-sonnet-4-5'),
                    ];
                  },
                );
                done = true;
              },
              child: const Text('go'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      if (rename != null) {
        await tester.enterText(
          find.byWidgetPredicate(
            (w) => w is EditableText && w.controller.text == 'Alpha',
          ),
          rename,
        );
        await tester.pump();
      }
      await tester.tap(find.text(button ?? 'Cancel').last);
      await tester.pumpAndSettle();
      // Its models got ready for 2s at least: a timer, not a frame, which
      // pumpAndSettle does not wait for.
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      // A new upstream's models, fetched, to check.
      if (find.textContaining('Models of ').evaluate().isNotEmpty) {
        for (final model in check) {
          await tester.tap(find.text(model));
        }
        await tester.pump();
        await tester.tap(find.text(fetchButton).last);
        await tester.pumpAndSettle();
      }
      expect(done, isTrue);
      return result;
    }

    const link =
        'baocode://provider/import?v=1&name=Alpha&protocol=anthropic'
        '&url=https%3A%2F%2Fapi.alpha.example.com&key=sk-alpha-1234567890';

    testWidgets('nothing is added unless the user says yes', (tester) async {
      final id = await run(tester, link);
      expect(id, isNull);
      expect(providers.providers, isEmpty);
    });

    testWidgets('shows what it imports', (tester) async {
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showUpstreamImportDialog(
                context,
                UpstreamImport.parse(link)!,
                providers: providers,
                featured: Future.value(_featured),
              ),
              child: const Text('go'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      // As BaoCode lists the site.
      expect(find.text('Alpha API'), findsOneWidget);
      expect(find.text('Officially listed'), findsOneWidget);
      expect(find.text('Alpha API, cheaply'), findsOneWidget);
      expect(find.text('https://api.alpha.example.com'), findsOneWidget);
      expect(find.text('sk-alp…7890'), findsOneWidget);
      expect(find.textContaining('sk-alpha-1234567890'), findsNothing);
    });

    testWidgets('a click beside it leaves it open', (tester) async {
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showUpstreamImportDialog(
                context,
                UpstreamImport.parse(link)!,
                providers: providers,
                featured: Future.value(_featured),
              ),
              child: const Text('go'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.text('Import Models'), findsOneWidget);
    });

    testWidgets('from a site not listed, by its host', (tester) async {
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showUpstreamImportDialog(
                context,
                UpstreamImport.parse(
                  'baocode://provider/import?v=1&protocol=anthropic'
                  '&url=https%3A%2F%2Fapi.gamma.example.com%2Fv1&name=Gamma',
                )!,
                providers: providers,
                featured: Future.value(_featured),
              ),
              child: const Text('go'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(
        find.text('Import an upstream from api.gamma.example.com'),
        findsOneWidget,
      );
      expect(find.text('Officially listed'), findsNothing);
      expect(find.text('none, add it afterwards'), findsOneWidget);
    });

    testWidgets('added on yes, with the models checked of those it lists, '
        'its key in the keychain', (tester) async {
      final id = await run(
        tester,
        link,
        button: 'Import Models',
        rename: 'My Alpha',
        check: ['claude-sonnet-4-5'],
      );
      expect(listedWith, ['sk-alpha-1234567890']);
      final provider = providers.provider(id)!;
      expect(
        [
          for (final model in provider.models)
            if (model.enabled) model.id,
        ],
        ['claude-sonnet-4-5'],
      );
      expect(provider.name, 'My Alpha');
      expect(provider.baseUrl, 'https://api.alpha.example.com');
      expect(provider.protocol, ProviderProtocol.anthropic);
      expect(provider.disableNonessentialTraffic, isTrue);
      expect(await secrets.read(provider.keyRef), 'sk-alpha-1234567890');
      expect(provider.toJson().toString(), isNot(contains('sk-alpha')));
    });

    testWidgets('its models are got ready for 2s at least, however soon '
        'the upstream answers', (tester) async {
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showUpstreamImportDialog(
                context,
                UpstreamImport.parse(link)!,
                providers: providers,
                featured: Future.value(_featured),
                list: (_, _) async => const [RemoteModel('claude-opus-4-1')],
              ),
              child: const Text('go'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import Models'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1900));
      expect(find.text('Getting your models ready…'), findsOneWidget);
      // Under the upstream's name.
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('claude-opus-4-1'), findsNothing);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Getting your models ready…'), findsNothing);
      expect(find.text('claude-opus-4-1'), findsOneWidget);
    });

    testWidgets('one that cannot list its models is added without', (
      tester,
    ) async {
      final id = await run(
        tester,
        link,
        button: 'Import Models',
        fetchButton: 'Import Without Models',
        unlisted: true,
      );
      final provider = providers.provider(id)!;
      expect(provider.models, isEmpty);
      expect(await secrets.read(provider.keyRef), 'sk-alpha-1234567890');
    });

    testWidgets('nor when the user says no to its models', (tester) async {
      final id = await run(
        tester,
        link,
        button: 'Import Models',
        fetchButton: 'Cancel',
      );
      expect(id, isNull);
      expect(providers.providers, isEmpty);
      expect(await secrets.read('provider.alpha'), isNull);
    });

    testWidgets('one there already gets the new key', (tester) async {
      await providers.save(
        const ModelProvider(
          id: 'alpha',
          name: 'Old Alpha',
          baseUrl: 'https://api.alpha.example.com/v1',
        ),
      );
      final id = await run(tester, link, button: "Update Old Alpha's Key");
      expect(id, 'alpha');
      expect(providers.providers, hasLength(1));
      expect(await secrets.read('provider.alpha'), 'sk-alpha-1234567890');
    });

    testWidgets('or is kept, the import added beside it', (tester) async {
      await providers.save(
        const ModelProvider(
          id: 'alpha',
          name: 'Old Alpha',
          baseUrl: 'https://api.alpha.example.com',
        ),
      );
      final id = await run(tester, link, button: 'Add as New Upstream');
      expect(id, isNot('alpha'));
      expect(providers.providers, hasLength(2));
      expect(await secrets.read('provider.alpha'), isNull);
    });
  });

  testWidgets('an upstream imported opens on Settings → Models', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await providers.save(
      const ModelProvider(
        id: 'gw',
        name: 'Gateway',
        baseUrl: 'https://gw.example.com',
      ),
    );
    ModelsSettingsPage.reveal.value = 'gw';
    await tester.pumpWidget(
      _app(
        ModelsSettingsPage(
          providers: providers,
          featured: Future.value(const []),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Connection'), findsOneWidget);
    expect(ModelsSettingsPage.reveal.value, isNull);
  });
}
