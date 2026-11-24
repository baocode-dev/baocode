import 'package:baocode/kernel/antigravity/agy_quota.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:flutter_test/flutter_test.dart';

/// As the daily host answers an account that used some of its Gemini
/// limit and none of the other.
Map<String, Object?> summary({
  double gemini = 0.7123616,
  String geminiResets = '2026-12-01T02:05:07Z',
  String otherResets = '2026-12-01T05:06:39Z',
}) => {
  'groups': [
    {
      'displayName': 'Gemini Models',
      'buckets': [
        {
          'bucketId': 'gemini-weekly',
          'displayName': 'Weekly Limit Remaining',
          'window': 'weekly',
          'resetTime': geminiResets,
          if (gemini < 1) 'description': 'You have used some of it.',
          'remainingFraction': gemini,
        },
      ],
    },
    {
      'displayName': 'Claude and GPT models',
      'buckets': [
        {
          'bucketId': '3p-weekly',
          'displayName': 'Weekly Limit Remaining',
          'window': 'weekly',
          'resetTime': otherResets,
          'remainingFraction': 1,
        },
      ],
    },
  ],
};

class _Api implements AgyQuotaApi {
  _Api(this.answers);

  final List<({Object? summary, DateTime askedAt})> answers;

  @override
  Future<List<({Object? summary, DateTime askedAt})>> summaries() async =>
      answers;
}

void main() {
  final asked = DateTime.utc(2026, 11, 24, 5, 6, 39);

  test('a bucket each: the share used, and when it resets', () {
    final windows = agyQuotaWindows(summary(), askedAt: asked);
    expect(windows.map((w) => w.label), [
      'Gemini Models · Weekly',
      'Claude and GPT models · Weekly',
    ]);
    expect(windows.first.utilization, closeTo(0.2876, 1e-4));
    expect(
      windows.first.resetsAt!.isAtSameMomentAs(
        DateTime.utc(2026, 12, 1, 2, 5, 7),
      ),
      isTrue,
    );
    // Untouched: its window as if starting now, no reset told.
    expect(windows.last.utilization, 0);
    expect(windows.last.resetsAt, isNull);
  });

  test('buckets outside groups; disabled ones left out', () {
    final windows = agyQuotaWindows({
      'buckets': [
        {'bucketId': 'gemini-5h', 'window': '5h', 'remainingFraction': 0.5},
        {
          'bucketId': 'off',
          'window': 'weekly',
          'remainingFraction': 0.1,
          'disabled': true,
        },
      ],
    });
    expect(windows.single.label, 'gemini-5h · 5-hour');
    expect(windows.single.utilization, 0.5);
  });

  test('the host asked first wins a bucket both tell', () async {
    final quota = AgyQuota(
      _Api([
        (summary: summary(), askedAt: asked),
        (summary: summary(gemini: 1), askedAt: asked),
      ]),
    );
    await quota.refresh();
    expect(quota.state, LimitsState.idle);
    expect(quota.windows.first.utilization, closeTo(0.2876, 1e-4));
    expect(quota.windows, hasLength(2));
  });

  test('not signed in: unavailable', () async {
    final quota = AgyQuota(_Api(const []));
    await quota.refresh();
    expect(quota.windows, isEmpty);
    expect(quota.state, LimitsState.unavailable);
  });
}
