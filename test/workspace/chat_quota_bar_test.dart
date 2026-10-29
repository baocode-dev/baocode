import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/kernel/agent_kernel.dart' show KernelChoiceKind;
import 'package:baocode/l10n/app_localizations.dart';
import 'package:baocode/models/codex/codex_service.dart';
import 'package:baocode/models/codex/codex_usage.dart';
import 'package:baocode/models/model_provider.dart';
import 'package:baocode/models/model_providers.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:baocode/theme/codicons.dart';
import 'package:baocode/workspace/chat_branch_bar.dart';
import 'package:baocode/workspace/chat_quota_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Session extends ChatSession {
  _Session(this.model) : super(historyCount: 0);

  String? model;

  @override
  String? selected(KernelChoiceKind kind) =>
      kind == KernelChoiceKind.model ? model : super.selected(kind);

  void select(String? value) {
    model = value;
    notifyListeners();
  }
}

class _Codex extends CodexService {
  final usages = <String, CodexUsage>{};
  final errors = <String, String>{};
  final limited = <String, DateTime>{};
  final refreshed = <bool>[];
  ProviderAccount? current;
  DateTime? back;

  void changed() => notifyListeners();

  @override
  Future<void> refreshUsage(ModelProvider provider, {bool force = true}) async {
    refreshed.add(force);
  }

  @override
  ProviderAccount? accountFor(ModelProvider provider, {String? session}) =>
      current;

  @override
  DateTime? backAt(ModelProvider provider) => back;

  @override
  CodexUsage? usage(String providerId, String accountId) => usages[accountId];

  @override
  String? error(String providerId, String accountId) => errors[accountId];

  @override
  DateTime? limitedUntil(String providerId, String accountId) =>
      limited[accountId];

  @override
  bool signedOut(String providerId, String accountId) => false;

  @override
  Future<CodexLogin> login(String providerId) => throw UnimplementedError();

  @override
  Future<void> removeAccount(String providerId, String accountId) =>
      throw UnimplementedError();
}

const _alice = ProviderAccount(
  id: 'a',
  email: 'alice@example.com',
  plan: 'team',
);
const _bob = ProviderAccount(id: 'b', email: 'bob@example.com');
const _provider = ModelProvider(
  id: 'codex',
  name: 'ChatGPT',
  protocol: ProviderProtocol.codex,
  accounts: [_alice, _bob],
);
const _gateway = ModelProvider(
  id: 'gw',
  name: 'Gateway',
  protocol: ProviderProtocol.openaiChat,
  baseUrl: 'https://gw.example.com/v1',
);

CodexUsage _usage(double short, double long, {DateTime? resets}) => CodexUsage(
  at: DateTime.now(),
  primary: CodexWindow(
    usedPercent: short,
    minutes: 300,
    resetsAt: resets ?? DateTime.now().add(const Duration(hours: 3)),
  ),
  secondary: CodexWindow(usedPercent: long, minutes: 10080),
);

Future<void> _pump(
  WidgetTester tester, {
  required _Session session,
  required ModelProviders providers,
  required _Codex codex,
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomLeft,
          child: SizedBox(
            width: 720,
            child: ChatQuotaBar(
              session: session,
              providers: providers,
              codex: codex,
              branch: ChatBranchBar(session: session, name: 'main'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Its timers stopped with it.
Future<void> _unmount(WidgetTester tester) =>
    tester.pumpWidget(const SizedBox());

void main() {
  late _Session session;
  late ModelProviders providers;
  late _Codex codex;

  setUp(() {
    session = _Session(modelRef('codex', 'gpt'));
    providers = ModelProviders.memory(providers: [_provider, _gateway]);
    codex = _Codex()
      ..current = _bob
      ..usages['a'] = _usage(10, 20)
      ..usages['b'] = _usage(20, 40);
  });

  testWidgets('one pill: the conversation\'s account, and how many can go', (
    tester,
  ) async {
    await _pump(tester, session: session, providers: providers, codex: codex);
    expect(find.text('main'), findsOneWidget);
    expect(
      find.text('bob · 5h 80% left · Weekly 60% left · 2/2 available'),
      findsOneWidget,
    );
    // The others only once opened.
    expect(find.textContaining('alice'), findsNothing);

    codex
      ..limited['a'] = DateTime.now().add(const Duration(hours: 1))
      ..changed();
    await tester.pump();
    expect(find.textContaining('1/2 available'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('nothing beside the branch on another provider\'s model', (
    tester,
  ) async {
    await _pump(tester, session: session, providers: providers, codex: codex);
    expect(find.byIcon(Codicons.dashboard), findsOneWidget);
    session.select(modelRef('gw', 'gpt'));
    await tester.pump();
    expect(find.byIcon(Codicons.dashboard), findsNothing);
    expect(find.text('main'), findsOneWidget);
    session.select('default');
    await tester.pump();
    expect(find.byIcon(Codicons.dashboard), findsNothing);
    await _unmount(tester);
  });

  testWidgets('every account out: when the first is back', (tester) async {
    final back = DateTime.now().add(const Duration(hours: 1));
    codex
      ..current = null
      ..back = back;
    await _pump(tester, session: session, providers: providers, codex: codex);
    String two(int n) => n.toString().padLeft(2, '0');
    final clock = '${two(back.hour)}:${two(back.minute)}';
    expect(
      find.textContaining('All accounts out of quota · back '),
      findsOneWidget,
    );
    expect(find.textContaining(clock), findsOneWidget);
    expect(find.byIcon(Codicons.warning), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('a click lists every account, the conversation\'s marked', (
    tester,
  ) async {
    await providers.save(
      _provider.copyWith(accounts: [_alice, _bob.copyWith(enabled: false)]),
    );
    codex
      ..current = _alice
      ..errors['a'] = 'upstream unavailable'
      ..limited['b'] = DateTime.now().add(const Duration(hours: 1));
    await _pump(tester, session: session, providers: providers, codex: codex);
    await tester.tap(find.byIcon(Codicons.dashboard));
    await tester.pumpAndSettle();
    expect(find.text('alice@example.com'), findsOneWidget);
    expect(find.text('bob@example.com'), findsOneWidget);
    expect(find.text('This chat'), findsOneWidget);
    expect(find.text('team'), findsOneWidget);
    // In the pill too: Alice's is the conversation's.
    expect(find.textContaining('90% left'), findsNWidgets(2));
    expect(find.textContaining('Disabled · Out of quota'), findsOneWidget);
    expect(find.text('upstream unavailable'), findsOneWidget);

    // As the quota comes, while open.
    codex
      ..usages['a'] = _usage(50, 20)
      ..changed();
    await tester.pump();
    expect(find.textContaining('50% left'), findsWidgets);

    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();
    expect(find.text('bob@example.com'), findsNothing);
    await _unmount(tester);
  });

  testWidgets('kept fresh: on showing, each five minutes, and as a window '
      'starts over', (tester) async {
    codex.usages['b'] = _usage(
      100,
      40,
      resets: DateTime.now().add(const Duration(minutes: 1)),
    );
    await _pump(tester, session: session, providers: providers, codex: codex);
    expect(codex.refreshed, [false]);
    // A streamed word asks for nothing.
    session.notifyListeners();
    await tester.pump();
    expect(codex.refreshed, [false]);

    const reset = Duration(minutes: 1, seconds: 3);
    await tester.pump(reset);
    expect(codex.refreshed, [false, false]);
    // Its answer: started over, the next reset hours on.
    codex
      ..usages['b'] = _usage(0, 40)
      ..changed();
    await tester.pump();
    expect(codex.refreshed, [false, false]);
    await tester.pump(CodexService.usageMaxAge - reset);
    expect(codex.refreshed, [false, false, false]);

    // Hidden, not asked; back, asked again.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump(CodexService.usageMaxAge * 2);
    expect(codex.refreshed, hasLength(3));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(codex.refreshed, hasLength(4));

    // The panel's refresh asks for all, forced.
    await tester.tap(find.byIcon(Codicons.dashboard));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Codicons.refresh));
    await tester.pump();
    expect(codex.refreshed.last, isTrue);
    await _unmount(tester);
  });

  testWidgets('in Chinese', (tester) async {
    await _pump(
      tester,
      session: session,
      providers: providers,
      codex: codex,
      locale: const Locale('zh'),
    );
    expect(find.text('bob · 5 小时剩 80% · 每周剩 60% · 2/2 可用'), findsOneWidget);
    await _unmount(tester);
  });
}
