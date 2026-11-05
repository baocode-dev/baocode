import 'package:baocode/models/upstream_quota.dart';
import 'package:baocode/models/upstream_quota_minimax.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 11, 5, 12);

  /// The answer of a plan whose five hours are 70% left and whose week is
  /// whole, with a video model's entry beside it.
  final answer = {
    'model_remains': [
      {
        'model_name': 'general',
        'current_interval_total_count': 0,
        'current_interval_usage_count': 0,
        'current_weekly_total_count': 0,
        'current_weekly_usage_count': 0,
        'current_interval_remaining_percent': 70,
        'current_weekly_remaining_percent': 100,
        'current_interval_status': 1,
        'current_weekly_status': 3,
        'end_time': 1793880000000,
        'weekly_end_time': 1794153600000,
      },
      {
        'model_name': 'video',
        'current_interval_remaining_percent': 100,
        'current_weekly_remaining_percent': 100,
        'end_time': 1793894400000,
        'weekly_end_time': 1794153600000,
      },
    ],
    'base_resp': {'status_code': 0, 'status_msg': 'success'},
  };

  test('a plan\'s quota is what is left of each of its windows', () {
    final quota = parseMiniMaxQuota(answer, now);
    expect(quota, isNotNull);
    expect(quota!.windows.length, 2);
    expect(quota.windows[0].type, 'five_hour');
    expect(quota.windows[0].leftPercent, 70);
    expect(quota.windows[0].usedPercent, 30);
    expect(
      quota.windows[0].resetsAt,
      DateTime.fromMillisecondsSinceEpoch(1793880000000),
    );
    expect(quota.windows[1].type, 'seven_day');
    expect(quota.windows[1].leftPercent, 100);
    expect(
      quota.windows[1].resetsAt,
      DateTime.fromMillisecondsSinceEpoch(1794153600000),
    );
    expect(quota.at, now);
    expect(quota.leastLeft, 70);
  });

  test('the entries of other things are not the plan\'s', () {
    final quota = parseMiniMaxQuota({
      'model_remains': [
        {
          'model_name': 'video',
          'current_interval_remaining_percent': 100,
          'current_weekly_remaining_percent': 100,
        },
      ],
    }, now);
    expect(quota, isNull);
  });

  test('the counts of the older answers are not read', () {
    // What they counted changed, and the shares are what the service
    // answers with now.
    final quota = parseMiniMaxQuota({
      'model_remains': [
        {
          'model_name': 'general',
          'current_interval_total_count': 1500,
          'current_interval_usage_count': 255,
          'current_weekly_total_count': 0,
          'current_weekly_usage_count': 0,
        },
      ],
    }, now);
    expect(quota, isNull);
  });

  test('an answer of no plan is no quota', () {
    expect(
      parseMiniMaxQuota({
        'base_resp': {'status_code': 0},
      }, now),
      isNull,
    );
    expect(parseMiniMaxQuota({'model_remains': []}, now), isNull);
    expect(parseMiniMaxQuota(null, now), isNull);
    expect(parseMiniMaxQuota('not an answer', now), isNull);
  });

  test('a share of none is no window', () {
    final quota = parseMiniMaxQuota({
      'model_remains': [
        {'model_name': 'general', 'end_time': 1793880000000},
      ],
    }, now);
    expect(quota, isNull);
  });

  test('a window\'s end is read in milliseconds or in seconds', () {
    final quota = parseMiniMaxQuota({
      'model_remains': [
        {
          'model_name': 'general',
          'current_interval_remaining_percent': 50,
          'current_weekly_remaining_percent': 50,
          'end_time': 1793880000,
          'weekly_end_time': 1794153600000,
        },
      ],
    }, now);
    expect(
      quota!.windows[0].resetsAt,
      DateTime.fromMillisecondsSinceEpoch(1793880000000),
    );
    expect(
      quota.windows[1].resetsAt,
      DateTime.fromMillisecondsSinceEpoch(1794153600000),
    );
  });

  test('a share out of the scale is held to it', () {
    final quota = parseMiniMaxQuota({
      'model_remains': [
        {
          'model_name': 'general',
          'current_interval_remaining_percent': 140,
          'current_weekly_remaining_percent': -20,
        },
      ],
    }, now);
    expect(quota!.windows[0].leftPercent, 100);
    expect(quota.windows[1].leftPercent, 0);
  });

  test('MiniMax\'s hosts are told apart from others', () {
    expect(isMiniMaxHost('api.minimaxi.com'), isTrue);
    expect(isMiniMaxHost('API.MiniMax.io'), isTrue);
    expect(isMiniMaxHost('api.openai.com'), isFalse);
    expect(isMiniMaxHost('minimaxi.com.example.net'), isFalse);
  });

  test('the quota is asked for at the host\'s own path', () {
    expect(
      miniMaxQuotaUrl('api.minimaxi.com').toString(),
      'https://api.minimaxi.com/v1/api/openplatform/coding_plan/remains',
    );
    expect(
      miniMaxQuotaUrl('api.minimax.io').toString(),
      'https://api.minimax.io/v1/api/openplatform/coding_plan/remains',
    );
  });

  test('the least of the windows is what is left of the plan', () {
    final quota = UpstreamQuota(
      at: now,
      windows: const [
        UpstreamQuotaWindow(type: 'five_hour', leftPercent: 70),
        UpstreamQuotaWindow(type: 'seven_day', leftPercent: 100),
      ],
    );
    expect(quota.leastLeft, 70);
  });
}
