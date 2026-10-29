import '../../l10n/app_localizations.dart';

/// A quota window's duration, or nothing when its duration is unknown.
String quotaWindowName(AppLocalizations l10n, int? minutes) {
  if (minutes == null || minutes <= 0) return '';
  if (minutes == 10080) return l10n.modelsQuotaWeek;
  if (minutes % 1440 == 0) return l10n.modelsQuotaDays(minutes ~/ 1440);
  return l10n.modelsQuotaHours((minutes / 60).round());
}

/// When a quota window resets: relative within a day, otherwise local time.
String quotaResets(AppLocalizations l10n, DateTime at, DateTime now) {
  final left = at.difference(now);
  if (left.inMinutes < 60) {
    return l10n.modelsQuotaResetsIn(
      l10n.modelsDurationMinutes(left.inMinutes < 1 ? 1 : left.inMinutes),
    );
  }
  if (left.inHours < 24) {
    return l10n.modelsQuotaResetsIn(
      l10n.modelsDurationHours(left.inHours, left.inMinutes % 60),
    );
  }
  final local = at.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return l10n.modelsQuotaResetsAt(
    '${local.month}/${local.day} ${two(local.hour)}:${two(local.minute)}',
  );
}
