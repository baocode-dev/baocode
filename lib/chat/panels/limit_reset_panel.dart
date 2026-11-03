import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';

/// The agent stopped at the account's usage limit, to go on by itself once
/// it resets, first above the composer: when. Turned off in the model
/// picker, where it is turned on.
///
/// Gone once the reset is past.
class LimitResetPanel extends StatefulWidget {
  const LimitResetPanel({super.key, required this.resetsAt});

  final DateTime resetsAt;

  @override
  State<LimitResetPanel> createState() => _LimitResetPanelState();
}

class _LimitResetPanelState extends State<LimitResetPanel> {
  Timer? _over;

  bool get _past => !widget.resetsAt.isAfter(DateTime.now());

  @override
  void initState() {
    super.initState();
    _time();
  }

  @override
  void didUpdateWidget(LimitResetPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.resetsAt != oldWidget.resetsAt) _time();
  }

  /// Hides it as the limit resets.
  void _time() {
    _over?.cancel();
    final left = widget.resetsAt.difference(DateTime.now());
    if (left.isNegative) return;
    _over = Timer(left, () {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _over?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_past) return const SizedBox.shrink();
    final l10n = context.l10n;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.bubbleFill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.bubbleBorder()),
      ),
      child: Row(
        children: [
          Icon(
            Icons.schedule_send_rounded,
            size: 14,
            color: AppColors.textMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.usageLimitScheduled(resetTime(widget.resetsAt, l10n)),
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// When the limit resets, on the clock: `15:00` today, `tomorrow 15:00`,
/// else with its date (`10/23 15:00`).
String resetTime(DateTime at, AppLocalizations l10n, {DateTime? now}) {
  now ??= DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  final clock = '${two(at.hour)}:${two(at.minute)}';
  final day = DateTime(at.year, at.month, at.day);
  final today = DateTime(now.year, now.month, now.day);
  final days = day.difference(today).inHours / 24;
  if (days.round() == 0) return clock;
  if (days.round() == 1) return l10n.usageLimitTomorrow(clock);
  return '${at.month}/${at.day} $clock';
}
