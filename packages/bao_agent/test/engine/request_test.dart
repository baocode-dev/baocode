import 'dart:convert';

import 'package:bao_agent/bao_agent.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

void main() {
  late Harness h;

  tearDown(() => h.dispose());

  /// The agent's first request in a session on [model].
  Future<ModelRequest> asked(
    String model, {
    String? effort,
    String? thinkingDisplay,
    Map<String, Object?> settings = const {},
    Map<String, String> environment = const {},
    bool firstParty = true,
  }) async {
    h = await Harness.start(
      firstParty: firstParty,
      model: model,
      effort: effort,
      thinkingDisplay: thinkingDisplay,
      settings: settings,
      environment: environment,
      script: [Reply.text('ok')],
    );
    await h.turn('hi');
    return h.model.turns.first;
  }

  test('a model of the newest: its own output, effort and thinking, '
      'and the betas for them', () async {
    final request = await asked('claude-sonnet-5-5');
    expect(request.body['max_tokens'], 128000);
    expect(request.body['output_config'], {'effort': 'medium'});
    expect(request.body['thinking'], {'type': 'adaptive'});
    expect(request.body['context_management'], {
      'edits': [
        {'type': 'clear_thinking_20251015', 'keep': 'all'},
      ],
    });
    // Anthropic's own API: the betas of the conversation's layout too.
    expect(request.betas, [
      'interleaved-thinking-2025-05-14',
      'thinking-token-count-2026-05-13',
      'context-management-2025-06-27',
      'prompt-caching-scope-2026-01-05',
      'mid-conversation-system-2026-04-07',
      'per-turn-control-2026-07-01',
      'mid-conversation-tool-changes-2026-07-01',
      'effort-2025-11-24',
    ]);
    // Nothing of Claude Code's own.
    expect(request.betas.where((b) => b.startsWith('claude-code')), isEmpty);
    await h.dispose();

    // A provider's: only those the request uses.
    final provider = await asked('claude-sonnet-5-5', firstParty: false);
    expect(provider.betas, [
      'interleaved-thinking-2025-05-14',
      'context-management-2025-06-27',
      'effort-2025-11-24',
    ]);
  });

  test("a provider's API: the context in the system prompt, the tools "
      'cached, no system messages', () async {
    final request = await asked('claude-sonnet-5-5', firstParty: false);
    final system = request.body['system']! as List;
    expect(system, hasLength(3));
    expect(jsonEncode(system.last), contains('Today is'));
    expect(jsonEncode(system.last), contains('cache_control'));
    expect(jsonEncode(system.first), isNot(contains('cache_control')));
    expect(
      jsonEncode((request.body['tools']! as List).last),
      contains('cache_control'),
    );
    final roles = [
      for (final m in request.body['messages']! as List) (m as Map)['role'],
    ];
    expect(roles, isNot(contains('system')));
    expect(request.body['metadata'], isNull);
  });

  test('the effort chosen, and thinking shown as the host asks', () async {
    final request = await asked(
      'claude-opus-5-5',
      effort: 'max',
      thinkingDisplay: 'summarized',
    );
    expect(request.body['output_config'], {'effort': 'max'});
    expect(request.body['thinking'], {
      'type': 'adaptive',
      'display': 'summarized',
    });
  });

  test('a model that thinks on a budget: thinking on unless turned off, '
      'all the output can spare', () async {
    final request = await asked(
      'claude-sonnet-4-5-20250929',
      firstParty: false,
    );
    expect(request.body['max_tokens'], 32000);
    expect(request.body['thinking'], {
      'type': 'enabled',
      'budget_tokens': 31999,
    });
    expect(request.body['output_config'], isNull);
    await h.dispose();

    final off = await asked(
      'claude-haiku-4-5-20251001',
      settings: {'alwaysThinkingEnabled': false},
      firstParty: false,
    );
    expect(off.body['thinking'], isNull);
    expect(off.body['context_management'], isNull);
    expect(off.betas, isEmpty);
  });

  test("a provider's model: nothing it may not take", () async {
    final request = await asked('some-provider-model', firstParty: false);
    expect(request.body['max_tokens'], 32000);
    expect(request.body['thinking'], isNull);
    expect(request.body['output_config'], isNull);
    expect(request.body['context_management'], isNull);
    expect(request.betas, isEmpty);
    await h.dispose();

    // Unless told it takes an effort.
    final told = await asked(
      'some-provider-model',
      effort: 'low',
      environment: {'CLAUDE_CODE_ALWAYS_ENABLE_EFFORT': '1'},
      firstParty: false,
    );
    expect(told.body['output_config'], {'effort': 'low'});
    expect(told.betas, isEmpty);
  });

  test('what the provider refuses is left out, the rest kept', () async {
    h = await Harness.start(
      model: 'claude-opus-4-8',
      thinkingDisplay: 'summarized',
      script: [
        Reply.failing(
          const ApiError(
            'Unexpected value(s) for the anthropic-beta header',
            status: 400,
          ),
        ),
        Reply.failing(
          const ApiError(
            'thinking.display: Extra inputs are not permitted',
            status: 400,
          ),
        ),
        Reply.text('fine'),
      ],
    );
    await h.turn('hi');
    expect(h.lastResult['result'], 'fine');
    final [first, second, third] = h.model.turns;
    expect(first.betas, contains('context-management-2025-06-27'));
    expect(second.betas, isEmpty);
    expect(second.body['context_management'], isNull);
    expect(second.body['thinking'], containsPair('display', 'summarized'));
    expect(third.body['thinking'], {'type': 'adaptive'});
    expect(jsonEncode(third.body['output_config']), contains('high'));
  });
}
