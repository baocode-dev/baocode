import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../ide/ide_hover.dart';
import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../chat_models.dart';
import 'agent_step.dart';
import 'hover_builder.dart';
import 'rolling_text.dart';

/// Lucide's icons the footer uses.
const _copyIcon = 'assets/icons/lucide-copy.svg';
const _checkIcon = 'assets/icons/lucide-check.svg';
const _zapIcon = 'assets/icons/lucide-zap.svg';
const _clockIcon = 'assets/icons/lucide-clock.svg';
const _arrowDownIcon = 'assets/icons/lucide-arrow-down.svg';

/// Whether the turn under way has its line of figures (`chat.liveTurnStats`),
/// on unless set to false. A finished turn's figures always show.
abstract final class LiveTurnStatsSetting {
  static const settingKey = 'chat.liveTurnStats';

  /// Written when off; on, the setting is left out.
  static const off = false;

  /// On unless set to false.
  static bool enabled(Object? setting) => setting != false;

  /// The setting as it is now, and what tells it changed; main() points
  /// them at settings.json.
  static bool Function() current = () => true;
  static Listenable? changes;
}

/// Under a finished turn: a button to copy its answer, then, faint, how
/// long the turn took, how fast the model wrote, what it cost and the
/// tokens it used, as far as known. Out of the history's selection.
///
/// Under a turn under way ([live]), the last of all: how long the turn has
/// taken ([since] its start), how fast the model writes (as last sampled)
/// and the tokens it has written so far, from the line's start, its
/// figures rolling as they change.
///
/// The time first and the tokens last, either way.
class TurnFooter extends StatelessWidget {
  const TurnFooter({
    super.key,
    this.answer,
    this.worked,
    this.usage,
    this.live,
    this.since,
  });

  /// What the copy button copies; no button when null.
  final String? answer;
  final Duration? worked;
  final TurnUsage? usage;

  /// What the turn under way has written so far, and how fast.
  final TurnOutput? live;

  /// When the turn under way began.
  final DateTime? since;

  /// "$0.42", "$0.0031": two figures past the first that is not 0, at
  /// least two decimals.
  static String formatCost(double usd) {
    if (usd >= 1 || usd == 0) return '\$${usd.toStringAsFixed(2)}';
    var digits = 2;
    while (digits < 6 && usd < math.pow(10, 1 - digits)) {
      digits++;
    }
    return '\$${usd.toStringAsFixed(digits)}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final live = this.live;
    if (live == null) {
      return _padded(
        _line([
          if (answer case final answer?) _CopyButton(text: answer),
          ..._stats(l10n),
        ]),
      );
    }
    // Turned off in settings: no line at all.
    return ListenableBuilder(
      listenable: LiveTurnStatsSetting.changes ?? Listenable.merge(const []),
      builder: (context, _) => LiveTurnStatsSetting.current()
          ? _padded(_LiveStats(output: live, since: since))
          : const SizedBox.shrink(),
    );
  }

  static Widget _padded(Widget line) => SelectionContainer.disabled(
    child: Padding(padding: const EdgeInsets.only(top: 6), child: line),
  );

  /// [items] in a line, going on to the next where a narrow conversation
  /// (beside the side panel) has not the room.
  static Widget _line(List<Widget> items) => Wrap(
    spacing: 12,
    runSpacing: 4,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: items,
  );

  List<Widget> _stats(AppLocalizations l10n) {
    final speed = usage?.tokensPerSecond;
    final cost = usage?.costUsd;
    final tokens = usage?.totalTokens;
    return [
      if (worked case final worked?)
        _Stat(
          icon: _clockIcon,
          text: AgentStep.formatDuration(worked, l10n: l10n),
          hint: l10n.turnDurationHint,
        ),
      if (speed != null)
        _Stat(
          icon: _zapIcon,
          text: l10n.turnSpeed(speed.toStringAsFixed(2)),
          hint: l10n.turnSpeedHint,
        ),
      if (cost != null) _Stat(text: formatCost(cost), hint: l10n.turnCostHint),
      if (tokens != null && tokens > 0)
        _Stat(
          text: l10n.turnTokens(AgentStep.formatTokens(tokens, decimals: 2)),
          hint: l10n.turnTokensHint(
            AgentStep.formatTokens(usage?.inputTokens ?? 0),
            AgentStep.formatTokens(usage?.outputTokens ?? 0),
          ),
        ),
    ];
  }
}

/// The turn under way's figures, changing as it goes, all as wide and
/// rolling: the line keeps still. The speed to two decimals; the time
/// counted on each second.
class _LiveStats extends StatefulWidget {
  const _LiveStats({required this.output, this.since});

  final TurnOutput output;
  final DateTime? since;

  @override
  State<_LiveStats> createState() => _LiveStatsState();
}

class _LiveStatsState extends State<_LiveStats> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _follow();
  }

  @override
  void didUpdateWidget(_LiveStats oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.since != oldWidget.since) _follow();
  }

  /// Rebuilt as each second of the turn's comes.
  void _follow() {
    _ticker?.cancel();
    _ticker = null;
    final since = widget.since;
    if (since == null) return;
    final past = DateTime.now().difference(since).inMilliseconds % 1000;
    _ticker = Timer(Duration(milliseconds: 1000 - past), () {
      if (!mounted) return;
      setState(() {});
      _follow();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final output = widget.output;
    final speed = output.tokensPerSecond;
    final since = widget.since;
    final tokens = output.tokens;
    return TurnFooter._line([
      if (since != null)
        _Stat(
          icon: _clockIcon,
          text: AgentStep.formatDuration(
            _nonNegative(DateTime.now().difference(since)),
            l10n: l10n,
          ),
          hint: l10n.turnDurationHint,
          live: true,
        ),
      if (speed != null)
        _Stat(
          icon: _zapIcon,
          text: l10n.turnSpeed(speed.toStringAsFixed(2)),
          hint: l10n.turnSpeedLiveHint,
          live: true,
        ),
      if (tokens > 0)
        _Stat(
          icon: _arrowDownIcon,
          text: l10n.turnTokens(AgentStep.formatTokens(tokens, decimals: 2)),
          hint: l10n.turnOutputTokensHint,
          live: true,
        ),
    ]);
  }

  static Duration _nonNegative(Duration time) =>
      time.isNegative ? Duration.zero : time;
}

class _Stat extends StatelessWidget {
  const _Stat({
    this.icon,
    required this.text,
    required this.hint,
    this.live = false,
  });

  final String? icon;
  final String text;
  final String hint;

  /// Changing as one looks: its figures as wide, and rolling.
  final bool live;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.textFaint;
    return IdeHover(
      message: hint,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon case final icon?) ...[
            SvgPicture.asset(
              icon,
              width: 12,
              height: 12,
              colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
            ),
            const SizedBox(width: 4),
          ],
          // Not monospaced: its 1 would stand apart from the icon.
          if (live)
            RollingText(
              text,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            )
          else
            Text(text, style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }
}

class _CopyButton extends StatefulWidget {
  const _CopyButton({required this.text});

  final String text;

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;
  Timer? _copiedTimer;

  void _copy() {
    unawaited(Clipboard.setData(ClipboardData(text: widget.text)));
    _copiedTimer?.cancel();
    setState(() => _copied = true);
    _copiedTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return IdeHover(
      message: _copied ? l10n.turnCopied : l10n.turnCopy,
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          onTap: _copy,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: hovered ? AppColors.hover : null,
              borderRadius: BorderRadius.circular(4),
            ),
            child: SvgPicture.asset(
              _copied ? _checkIcon : _copyIcon,
              width: 13,
              height: 13,
              colorFilter: ColorFilter.mode(
                hovered || _copied ? AppColors.text : AppColors.textFaint,
                BlendMode.srcIn,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
