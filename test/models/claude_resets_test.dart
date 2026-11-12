import 'package:baocode/models/claude_resets.dart';
import 'package:flutter_test/flutter_test.dart';

/// `/api/oauth/usage?cedar_ember=1` as a Max account had it (Nov 2026).
Map<String, Object?> claudeUsageWithResets({
  String? next = 'full-reset-2611',
  bool eligible = true,
  String? cooldownUntil,
}) => {
  'five_hour': {'utilization': 6.0, 'resets_at': '2026-11-11T06:10:00+00:00'},
  'cedar_ember': {
    'eligible': eligible,
    'ineligible_reason': eligible ? null : 'surface',
    'at_limit': false,
    'grants': [
      {
        'id': 'launch-2610-fable',
        'label': 'New model launch: one Fable reset',
        'resets_total': 1,
        'resets_left': 1,
        'starts_at': '2026-11-09T18:00:00+00:00',
        'ends_at': '2027-03-09T07:59:00+00:00',
        'clears': ['five_hour', 'seven_day_overage_included'],
        'paused': false,
        'usable_now': true,
        'percent_used': {'five_hour': 6, 'seven_day_overage_included': 0},
      },
      {
        'id': 'full-reset-2611',
        'label': 'One full limit reset (November 2026)',
        'resets_total': 1,
        'resets_left': 1,
        'starts_at': '2026-11-10T21:30:00+00:00',
        'ends_at': '2026-12-10T22:00:00+00:00',
        'clears': ['five_hour', 'seven_day', 'seven_day_overage_included'],
        'paused': false,
        'usable_now': true,
        'percent_used': {
          'five_hour': 6,
          'seven_day': 43,
          'seven_day_overage_included': 0,
        },
      },
      {
        'id': 'old-2609',
        'resets_left': 1,
        'ends_at': '2026-10-01T00:00:00+00:00',
        'clears': ['seven_day'],
      },
    ],
    'next_grant_id': next,
    'cooldown_until': cooldownUntil,
  },
  'limits': [
    {
      'kind': 'weekly_scoped',
      'scope': {
        'model': {'id': null, 'display_name': 'Fable'},
      },
    },
  ],
};

class FakeClaudeResetsApi implements ClaudeResetsApi {
  FakeClaudeResetsApi(this.answer);

  Map<String, Object?>? answer;
  Map<String, Object?> claimAnswer = {
    'result': 'reset',
    'cleared': ['five_hour', 'seven_day'],
  };
  final claims = <(String, String)>[];
  int asked = 0;

  @override
  Future<Map<String, Object?>?> usage() async {
    asked++;
    return answer;
  }

  @override
  Future<Map<String, Object?>> claim(String grantId, String requestId) async {
    claims.add((grantId, requestId));
    return claimAnswer;
  }
}

void main() {
  final now = DateTime.utc(2026, 11, 11, 2);

  test('reads the grants: live ones by expiry, the next, the model', () {
    final resets = ClaudeResets.fromUsage(claudeUsageWithResets(), now)!;
    expect(resets.eligible, isTrue);
    expect(resets.grants, hasLength(3));
    // The expired one is not counted.
    expect(resets.live.map((g) => g.id), [
      'full-reset-2611',
      'launch-2610-fable',
    ]);
    expect(resets.count, 2);
    expect(resets.next?.id, 'full-reset-2611');
    expect(resets.scopedModel, 'Fable');
    final full = resets.live.first;
    expect(full.clears, [
      'five_hour',
      'seven_day',
      'seven_day_overage_included',
    ]);
    expect(full.used['seven_day'], 43);
    expect(full.label, 'One full limit reset (November 2026)');
  });

  test('none to use while ineligible, cooling down, or none named next', () {
    expect(
      ClaudeResets.fromUsage(claudeUsageWithResets(eligible: false), now)!.next,
      isNull,
    );
    expect(
      ClaudeResets.fromUsage(
        claudeUsageWithResets(cooldownUntil: '2026-11-11T03:00:00Z'),
        now,
      )!.next,
      isNull,
    );
    expect(
      ClaudeResets.fromUsage(claudeUsageWithResets(next: null), now)!.next,
      isNull,
    );
    // No block: not offered to this account.
    expect(ClaudeResets.fromUsage({'five_hour': null}, now), isNull);
  });

  test('a reset is used once, of the grant still next', () async {
    final api = FakeClaudeResetsApi(claudeUsageWithResets());
    final service = ClaudeResetsService(api, now: () => now);
    await service.refresh();
    final grant = service.resets!.next!;
    final outcome = await service.use(grant);
    expect(outcome.reset, isTrue);
    expect(outcome.cleared, ['five_hour', 'seven_day']);
    expect(api.claims.single.$1, 'full-reset-2611');
    expect(
      api.claims.single.$2,
      matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab]')),
    );
  });

  test('not used when the grant is no longer the next', () async {
    final api = FakeClaudeResetsApi(claudeUsageWithResets());
    final service = ClaudeResetsService(api, now: () => now);
    await service.refresh();
    final grant = service.resets!.next!;
    api.answer = claudeUsageWithResets(next: 'launch-2610-fable');
    final outcome = await service.use(grant);
    expect(outcome.reset, isFalse);
    // As the server would have refused it.
    expect(outcome.reason, ClaudeResetOutcome.notNext);
    expect(api.claims, isEmpty);
  });

  test('the server saying no is told as it is', () async {
    final api = FakeClaudeResetsApi(claudeUsageWithResets())
      ..claimAnswer = {'result': 'not_limited', 'reason': 'under the limit'};
    final service = ClaudeResetsService(api, now: () => now);
    await service.refresh();
    final outcome = await service.use(service.resets!.next!);
    expect(outcome.reset, isFalse);
    expect(outcome.result, 'not_limited');
    expect(outcome.reason, 'under the limit');
    expect(api.claims, hasLength(1));
  });

  test('asked again only after a while, unless forced', () async {
    var at = now;
    final api = FakeClaudeResetsApi(claudeUsageWithResets());
    final service = ClaudeResetsService(api, now: () => at);
    await service.refresh();
    await service.refresh();
    expect(api.asked, 1);
    await service.refresh(force: true);
    expect(api.asked, 2);
    at = at.add(ClaudeResetsService.fresh);
    await service.refresh();
    expect(api.asked, 3);
  });
}
