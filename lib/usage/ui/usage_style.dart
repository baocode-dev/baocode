import 'package:flutter/widgets.dart';

import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../usage_record.dart';

/// The usage charts' colors: a categorical order checked for color vision
/// (the dataviz validator: lightness band, chroma, adjacent CVD ΔE ≥ 8,
/// normal ΔE ≥ 15, 3:1 on the surface), a step each for the dark and the
/// light themes, warm as the Bao themes are.
abstract final class UsagePalette {
  static const _dark = [
    Color(0xFF2E9E72), // green
    Color(0xFF3F86D8), // blue
    Color(0xFFB0679E), // rose
    Color(0xFFBD8128), // sand
    Color(0xFF8A79D8), // violet
    Color(0xFFD2654F), // coral
  ];
  static const _light = [
    Color(0xFF1F9A6B),
    Color(0xFF2F74C8),
    Color(0xFFA8558F),
    Color(0xFFC08020),
    Color(0xFF6B55C0),
    Color(0xFFC4503A),
  ];

  static List<Color> get _slots => themeColors.dark ? _dark : _light;

  /// The [i]th series' color, in the fixed order; past the last, "other".
  static Color series(int i) => i < _slots.length ? _slots[i] : other;

  static int get count => _slots.length;

  /// What is folded into "Other", and the de-emphasized.
  static Color get other => AppColors.textFaint;

  /// The token kinds, as stacked: read from the cache, not cached,
  /// written to it, and the output.
  static Color get cacheRead => _slots[0];
  static Color get input => _slots[1];
  static Color get cacheWrite => _slots[2];
  static Color get output => _slots[3];

  /// Failures: the theme's error color (a status, not a series).
  static Color get error => themeColors['errorForeground'];

  /// Events on a time (compactions): ink, not a series' color, which
  /// the lines beside them already take.
  static Color get marker => AppColors.textMuted;

  /// The grid and axes: a hairline a step off the surface.
  static Color get grid => AppColors.partBorder;

  /// The cards the charts are on.
  static Color get surface => AppColors.code;

  /// What filled the context, by part (see UsageContext.parts): those
  /// the same request after request in the colors, the conversation's own
  /// words in ink, the tools' results after them. (Validated in this
  /// order too; its one pair in the 6–8 band has the ink between it.)
  static Color part(String key) => switch (key) {
    'system' => _slots[4],
    'memory' => _slots[3],
    'skills' => _slots[2],
    'tools' => _slots[1],
    'mcp' => _slots[5],
    'messages' => AppColors.textMuted,
    'toolResult' => _slots[0],
    _ => other,
  };

  /// A kind of request.
  static Color ofClass(UsageClass kind) => switch (kind) {
    UsageClass.main => _slots[1],
    UsageClass.subagent => _slots[0],
    UsageClass.workflow => _slots[4],
    UsageClass.compaction => _slots[2],
    UsageClass.auxiliary => _slots[3],
    UsageClass.sideReply => _slots[5],
  };
}

/// How numbers, times and sizes read on the usage views.
abstract final class UsageFormat {
  /// 1,284 · 12.9K · 4.2M.
  static String tokens(num value) {
    final n = value.abs();
    String trim(double v) {
      final text = v.toStringAsFixed(v >= 100 ? 0 : 1);
      return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
    }

    final sign = value < 0 ? '-' : '';
    if (n >= 1e9) return '$sign${trim(n / 1e9)}B';
    if (n >= 1e6) return '$sign${trim(n / 1e6)}M';
    if (n >= 1e4) return '$sign${trim(n / 1e3)}K';
    return '$sign${_grouped(n.round())}';
  }

  static String _grouped(int n) {
    final text = '$n';
    final buffer = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      if (i > 0 && (text.length - i) % 3 == 0) buffer.write(',');
      buffer.write(text[i]);
    }
    return buffer.toString();
  }

  /// A count in full, grouped: 12,840.
  static String count(int n) => _grouped(n);

  /// Output tokens a second: 48.2 tok/s; [unit] false, the number alone.
  static String speed(double? speed, {bool unit = true}) {
    if (speed == null) return '—';
    final text = speed.toStringAsFixed(speed >= 100 ? 0 : 1);
    return unit ? '$text tok/s' : text;
  }

  static String percent(double ratio, {int digits = 0}) =>
      '${(ratio * 100).toStringAsFixed(digits)}%';

  /// 840ms · 3.2s · 4m 12s · 2h 5m.
  static String duration(Duration? duration) {
    if (duration == null) return '—';
    final ms = duration.inMilliseconds;
    if (ms < 1000) return '${ms}ms';
    if (ms < 60000) {
      return '${(ms / 1000).toStringAsFixed(ms < 10000 ? 1 : 0)}s';
    }
    final minutes = duration.inMinutes;
    if (minutes < 60) return '${minutes}m ${duration.inSeconds % 60}s';
    return '${duration.inHours}h ${minutes % 60}m';
  }

  static String bytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// 14:05.
  static String clock(DateTime time) =>
      '${_two(time.hour)}:${_two(time.minute)}';

  /// 14:05:09.
  static String clockSeconds(DateTime time) =>
      '${clock(time)}:${_two(time.second)}';

  /// 11-01.
  static String day(DateTime time) => '${_two(time.month)}-${_two(time.day)}';

  /// 11-01 14:05, or 14:05 today.
  static String when(DateTime time, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final same =
        time.year == today.year &&
        time.month == today.month &&
        time.day == today.day;
    return same ? clockSeconds(time) : '${day(time)} ${clock(time)}';
  }

  /// A kind of request, as shown.
  static String ofClass(BuildContext context, UsageClass kind) {
    final l10n = context.l10n;
    return switch (kind) {
      UsageClass.main => l10n.ustatClassMain,
      UsageClass.subagent => l10n.ustatClassSubagent,
      UsageClass.workflow => l10n.ustatClassWorkflow,
      UsageClass.compaction => l10n.ustatClassCompaction,
      UsageClass.auxiliary => l10n.ustatClassAuxiliary,
      UsageClass.sideReply => l10n.ustatClassSideReply,
    };
  }

  /// A part of the context, as shown.
  static String part(BuildContext context, String key) {
    final l10n = context.l10n;
    return switch (key) {
      'system' => l10n.ustatPartSystem,
      'memory' => l10n.ustatPartMemory,
      'skills' => l10n.ustatPartSkills,
      'tools' => l10n.ustatPartTools,
      'mcp' => l10n.ustatPartMcp,
      'messages' => l10n.ustatPartMessages,
      'user' => l10n.ustatPartUser,
      'assistant' => l10n.ustatPartAssistant,
      'thinking' => l10n.ustatPartThinking,
      'toolUse' => l10n.ustatPartToolUse,
      'toolResult' => l10n.ustatPartToolResult,
      'media' => l10n.ustatPartMedia,
      _ => key,
    };
  }
}

/// The usage views' text: sizes and strengths of the settings pages'.
abstract final class UsageText {
  static TextStyle get label =>
      TextStyle(color: AppColors.textMuted, fontSize: 11.5, height: 1.3);

  static TextStyle get value => TextStyle(
    color: AppColors.text,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.15,
  );

  static TextStyle get body =>
      TextStyle(color: AppColors.text, fontSize: 12, height: 1.4);

  static TextStyle get muted =>
      TextStyle(color: AppColors.textMuted, fontSize: 11.5, height: 1.4);

  static TextStyle get faint =>
      TextStyle(color: AppColors.textFaint, fontSize: 11, height: 1.3);

  static TextStyle get heading => TextStyle(
    color: AppColors.text,
    fontSize: 12.5,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  /// Numbers in columns: each digit as wide.
  static TextStyle get tabular => TextStyle(
    color: AppColors.text,
    fontSize: 11.5,
    height: 1.3,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}
