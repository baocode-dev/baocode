import '../../l10n/app_localizations.dart';
import 'codex_usage.dart';

/// A quota window's duration, or nothing when its duration is unknown.
String quotaWindowName(AppLocalizations l10n, int? minutes) {
  if (minutes == null || minutes <= 0) return '';
  if (minutes == 10080) return l10n.modelsQuotaWeek;
  if (minutes % 1440 == 0) return l10n.modelsQuotaDays(minutes ~/ 1440);
  return l10n.modelsQuotaHours((minutes / 60).round());
}

/// [window]'s name: its duration, and of what where it is not all the
/// account's (`5 hours Gemini`); [fallback] when neither is known.
String quotaWindowLabel(
  AppLocalizations l10n,
  CodexWindow window, {
  String fallback = '',
}) {
  final label = [
    quotaWindowName(l10n, window.minutes),
    ?window.name,
  ].where((part) => part.isNotEmpty).join(' ');
  return label.isEmpty ? fallback : label;
}

/// [label] put right before Chinese ("5 小时剩"): one ending in a Latin
/// name ("5 小时 Gemini") is kept a space apart from it.
String quotaLabelBeforeText(AppLocalizations l10n, String label) =>
    l10n.localeName.startsWith('zh') && RegExp(r'[A-Za-z0-9]$').hasMatch(label)
    ? '$label '
    : label;

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
