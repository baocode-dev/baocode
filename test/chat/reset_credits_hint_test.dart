import 'package:baocode/chat/panels/reset_credits_hint.dart';
import 'package:baocode/l10n/app_localizations.dart';
import 'package:baocode/models/codex/codex_service.dart';
import 'package:baocode/models/codex/codex_usage.dart';
import 'package:baocode/models/model_provider.dart';
import 'package:baocode/models/model_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Codex extends CodexService {
  _Codex(this.credits);

  final Map<String, List<CodexResetCredit>> credits;

  @override
  List<CodexResetCredit>? resetCredits(String providerId, String accountId) =>
      credits[accountId];

  @override
  Future<CodexLogin> login(String providerId) => throw UnimplementedError();
  @override
  Future<void> refreshUsage(
    ModelProvider provider, {
    bool force = true,
  }) async {}
  @override
  ProviderAccount? accountFor(ModelProvider provider, {String? session}) =>
      null;
  @override
  DateTime? backAt(ModelProvider provider) => null;
  @override
  CodexUsage? usage(String providerId, String accountId) => null;
  @override
  String? error(String providerId, String accountId) => null;
  @override
  DateTime? limitedUntil(String providerId, String accountId) => null;
  @override
  bool signedOut(String providerId, String accountId) => false;
  @override
  Future<void> removeAccount(String providerId, String accountId) async {}
}

void main() {
  final now = DateTime(2026, 11, 1, 10);

  group('plan', () {
    test('spread from today to the last, none after its day', () {
      final plan = resetCreditPlan([
        DateTime(2026, 11, 7, 18),
        DateTime(2026, 11, 2, 9),
        DateTime(2026, 11, 7, 20),
      ], now);
      expect(plan.map((d) => (d.day, d.count)), [
        (DateTime(2026, 11, 1), 1),
        (DateTime(2026, 11, 3), 1),
        (DateTime(2026, 11, 5), 1),
      ]);
      // The first of them that day: the one due soonest.
      expect(plan.first.deadline, DateTime(2026, 11, 2, 9));
    });

    test('more than the days left: several a day', () {
      final plan = resetCreditPlan([
        for (var i = 0; i < 3; i++) DateTime(2026, 11, 1, 20),
      ], now);
      expect(plan.single.count, 3);
    });

    test('expired ones left out', () {
      expect(resetCreditPlan([DateTime(2026, 11, 1, 9)], now), isEmpty);
    });
  });

  group('hint', () {
    late ModelProviders providers;

    setUp(() {
      ResetCreditsHint.putOff.value = false;
      providers = ModelProviders.memory(
        providers: const [
          ModelProvider(
            id: 'cx',
            name: 'ChatGPT',
            protocol: ProviderProtocol.codex,
            accounts: [ProviderAccount(id: 'a', email: 'a@x')],
            models: [ProviderModel(id: 'gpt-5')],
          ),
          ModelProvider(id: 'ds', name: 'DeepSeek', baseUrl: 'https://x.y'),
        ],
      );
    });

    Future<void> pump(
      WidgetTester tester, {
      required String model,
      required List<CodexResetCredit> credits,
    }) => tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ResetCreditsHint(
            model: model,
            providers: providers,
            codex: _Codex({'a': credits}),
            clock: () => now,
          ),
        ),
      ),
    );

    final soon = [
      CodexResetCredit(id: '1', expiresAt: DateTime(2026, 11, 3, 18)),
      CodexResetCredit(id: '2', expiresAt: DateTime(2026, 11, 3, 18)),
    ];

    testWidgets('on a Codex model with credits expiring: a plan; turning '
        'them on to be used by themselves', (tester) async {
      await pump(tester, model: '@cx/gpt-5', credits: soon);
      expect(find.textContaining('2 reset credits expire'), findsOneWidget);
      expect(find.textContaining('Today: reset once'), findsOneWidget);
      expect(find.textContaining('Tomorrow: reset once'), findsOneWidget);
      await tester.tap(find.text('Reset Automatically'));
      await tester.pumpAndSettle();
      expect(providers.provider('cx')!.autoResetCredits, isTrue);
      expect(find.text('Reset Automatically'), findsNothing);

      await tester.tap(find.text('Got It'));
      await tester.pump();
      expect(find.textContaining('reset credits expire'), findsNothing);
    });

    testWidgets('another model, or none expiring soon: nothing', (
      tester,
    ) async {
      await pump(tester, model: '@ds/chat', credits: soon);
      expect(find.textContaining('expire'), findsNothing);
      await pump(
        tester,
        model: '@cx/gpt-5',
        credits: [CodexResetCredit(id: '1', expiresAt: DateTime(2026, 11, 20))],
      );
      expect(find.textContaining('expire'), findsNothing);
    });
  });
}
