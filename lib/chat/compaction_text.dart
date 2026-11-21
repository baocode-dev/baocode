import '../l10n/l10n.dart';
import 'chat_models.dart';

extension CompactionNoteText on CompactionNote {
  /// The divider's line, in [l10n]'s language.
  String describe(AppLocalizations l10n) {
    final window = this.window;
    final before = this.before;
    final after = this.after;
    return [
      tooLong
          ? window == null
                ? l10n.noticeCompactedTooLong
                : l10n.noticeCompactedTooLongWindow(compactTokens(window))
          : auto
          ? l10n.noticeCompactedAuto
          : l10n.noticeCompacted,
      if (before != null)
        after == null
            ? l10n.noticeCompactedTokens(compactTokens(before))
            : l10n.noticeCompactedFromTo(
                compactTokens(before),
                compactTokens(after),
              ),
    ].join(' · ');
  }

  /// 253.0k, 900.
  static String compactTokens(int tokens) =>
      tokens >= 1000 ? '${(tokens / 1000).toStringAsFixed(1)}k' : '$tokens';
}
