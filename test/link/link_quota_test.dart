import 'dart:convert';

import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/kernel/agent_kernel.dart' show KernelChoiceKind;
import 'package:baocode/link/link_quota.dart';
import 'package:baocode/models/antigravity/antigravity_api.dart';
import 'package:baocode/models/codex/codex_service.dart';
import 'package:baocode/models/codex/codex_usage.dart';
import 'package:baocode/models/model_provider.dart';
import 'package:baocode/models/model_providers.dart';
import 'package:flutter_test/flutter_test.dart';

class _Session extends ChatSession {
  _Session(this.model) : super(historyCount: 0);

  final String model;

  @override
  String? selected(KernelChoiceKind kind) =>
      kind == KernelChoiceKind.model ? model : super.selected(kind);
}

/// Antigravity's accounts: out of quota on a model alone.
class _Accounts extends CodexService {
  final usages = <String, CodexUsage>{};
  final limitedOn = <String, DateTime>{};

  @override
  Future<void> refreshUsage(ModelProvider provider, {bool force = true}) async {}

  @override
  ProviderAccount? accountFor(ModelProvider provider, {String? session}) =>
      provider.accounts.first;

  @override
  ProviderAccount? accountForModel(
    ModelProvider provider, {
    String? session,
    String? model,
  }) => provider.accounts.firstWhere(
    (a) => limitedOn['${a.id}/$model'] == null,
  );

  @override
  DateTime? backAt(ModelProvider provider) => null;

  @override
  CodexUsage? usage(String providerId, String accountId) => usages[accountId];

  @override
  String? error(String providerId, String accountId) => null;

  @override
  DateTime? limitedUntil(String providerId, String accountId) => null;

  @override
  DateTime? limitedUntilFor(
    String providerId,
    String accountId, {
    String? model,
  }) => limitedOn['$accountId/$model'];

  @override
  bool signedOut(String providerId, String accountId) => false;

  @override
  Future<CodexLogin> login(String providerId) => throw UnimplementedError();

  @override
  Future<void> removeAccount(String providerId, String accountId) =>
      throw UnimplementedError();
}

void main() {
  test("Antigravity's, as the phone reads it: the model's pool", () {
    const a = ProviderAccount(id: 'a@x', email: 'a@x');
    const b = ProviderAccount(id: 'b@x', email: 'b@x');
    final providers = ModelProviders.memory(
      providers: [
        const ModelProvider(
          id: 'ag',
          name: 'Antigravity',
          protocol: ProviderProtocol.antigravity,
          accounts: [a, b],
        ),
      ],
    );
    final now = DateTime.now();
    final resets = DateTime.utc(2100, 1, 1);
    final models = parseAntigravityModels({
      'models': {
        'gemini-4-neon-high': {'displayName': 'Gemini 4 Neon (High)'},
        'claude-opus-5-5-high': {'displayName': 'Claude Opus 5.5 (High)'},
      },
    });
    CodexUsage usage(double gemini) => antigravityUsage(
      models: models,
      now: now,
      plan: 'Google AI Ultra',
      summary: {
        'groups': [
          {
            'displayName': 'Gemini Models',
            'buckets': [
              {
                'window': '5h',
                'remainingFraction': gemini,
                'resetTime': resets.toIso8601String(),
              },
              {
                'window': 'weekly',
                'remainingFraction': 0.5,
                'resetTime': resets.toIso8601String(),
              },
            ],
          },
          {
            'displayName': 'Claude and GPT models',
            'buckets': [
              {'window': '5h', 'remainingFraction': 1},
            ],
          },
        ],
      },
    );
    final until = DateTime.utc(2100, 1, 1);
    final accounts = _Accounts()
      ..usages['a@x'] = usage(0)
      ..usages['b@x'] = usage(0.75)
      ..limitedOn['a@x/gemini-4-neon'] = until;
    final quota = LinkQuota(providers: providers, codex: accounts);

    final gemini = quota.of(_Session(modelRef('ag', 'gemini-4-neon')))!;
    final ms = resets.millisecondsSinceEpoch;
    expect(gemini['provider'], 'Antigravity');
    expect(gemini['accounts'], [
      {
        'name': 'a@x',
        'plan': 'Google AI Ultra',
        'until': until.millisecondsSinceEpoch,
        'at': now.millisecondsSinceEpoch,
        'windows': [
          {'minutes': 300, 'name': 'Gemini', 'left': 0, 'resets': ms},
          {'minutes': 10080, 'name': 'Gemini', 'left': 50, 'resets': ms},
        ],
      },
      {
        'name': 'b@x',
        'plan': 'Google AI Ultra',
        'current': true,
        'at': now.millisecondsSinceEpoch,
        'windows': [
          {'minutes': 300, 'name': 'Gemini', 'left': 75, 'resets': ms},
          {'minutes': 10080, 'name': 'Gemini', 'left': 50, 'resets': ms},
        ],
      },
    ]);
    // It goes over the link as JSON.
    expect(jsonDecode(jsonEncode(gemini)), gemini);

    final claude = quota.of(_Session(modelRef('ag', 'claude-opus-5-5')))!;
    final first = (claude['accounts']! as List).first as Map;
    expect(first['current'], isTrue);
    expect(first.containsKey('until'), isFalse);
    expect(first['windows'], [
      {'minutes': 300, 'name': 'Claude & GPT', 'left': 100},
    ]);
  });
}
