import 'package:baocode/l10n/app_localizations_en.dart';
import 'package:baocode/l10n/app_localizations_zh.dart';
import 'package:baocode/models/codex/codex_quota_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final en = AppLocalizationsEn();
  final zh = AppLocalizationsZh();

  test('unknown window durations have no label', () {
    for (final l10n in [en, zh]) {
      for (final minutes in [null, 0, -60]) {
        expect(quotaWindowName(l10n, minutes), '');
      }
    }
  });

  test('window names preserve weekly, daily and rounded hourly labels', () {
    for (final (minutes, english, chinese) in [
      (300, '5h', '5 小时'),
      (10080, 'Weekly', '每周'),
      (1440, '1d', '1 天'),
      (2880, '2d', '2 天'),
      (20160, '14d', '14 天'),
      (90, '2h', '2 小时'),
      (1, '0h', '0 小时'),
    ]) {
      expect(quotaWindowName(en, minutes), english);
      expect(quotaWindowName(zh, minutes), chinese);
    }
  });

  test('resets under one hour use minutes with a one-minute minimum', () {
    final now = DateTime.utc(2026, 10, 27, 12);
    for (final minutes in [-20, 0, 1, 59]) {
      final at = now.add(Duration(minutes: minutes));
      final shown = minutes < 1 ? 1 : minutes;
      expect(quotaResets(en, at, now), 'resets in $shown min');
      expect(quotaResets(zh, at, now), '$shown 分钟后重置');
    }
    final at = now.add(const Duration(seconds: 59));
    expect(quotaResets(en, at, now), 'resets in 1 min');
    expect(quotaResets(zh, at, now), '1 分钟后重置');
  });

  test('resets within one day use whole hours and remaining minutes', () {
    final now = DateTime.utc(2026, 10, 27, 12);
    for (final (minutes, english, chinese) in [
      (60, 'resets in 1 h 0 min', '1 小时 0 分钟后重置'),
      (125, 'resets in 2 h 5 min', '2 小时 5 分钟后重置'),
      (1439, 'resets in 23 h 59 min', '23 小时 59 分钟后重置'),
    ]) {
      final at = now.add(Duration(minutes: minutes));
      expect(quotaResets(en, at, now), english);
      expect(quotaResets(zh, at, now), chinese);
    }
  });

  test('resets one day or later show local date and padded clock time', () {
    final at = DateTime(2026, 10, 29, 7, 5).toUtc();
    for (final hours in [24, 25, 48]) {
      final now = at.subtract(Duration(hours: hours));
      expect(quotaResets(en, at, now), 'resets 10/29 07:05');
      expect(quotaResets(zh, at, now), '10/29 07:05 重置');
    }
  });

  test('footer labels are localized without changing settings used text', () {
    expect(en.modelsAccountDisabled, 'Disabled');
    expect(zh.modelsAccountDisabled, '已禁用');
    expect(en.quotaBarWindowLeft('5h', 75), '5h 75% left');
    expect(zh.quotaBarWindowLeft('5 小时', 75), '5 小时剩 75%');
    expect(en.quotaBarAvailable(3, 4), '3/4 available');
    expect(zh.quotaBarAvailable(3, 4), '3/4 可用');
    expect(en.modelsQuotaRemaining(75), '75% left');
    expect(zh.modelsQuotaRemaining(75), '剩余 75%');
    expect(en.modelsQuotaShortWindow, 'Short window');
    expect(zh.modelsQuotaShortWindow, '短周期');
    expect(en.modelsQuotaLongWindow, 'Long window');
    expect(zh.modelsQuotaLongWindow, '长周期');
    expect(en.modelsQuotaLastUpdated('07:05'), 'Last updated 07:05');
    expect(zh.modelsQuotaLastUpdated('07:05'), '上次更新 07:05');
    expect(en.modelsQuotaUsed(25), '25% used');
    expect(zh.modelsQuotaUsed(25), '已用 25%');
  });
}
