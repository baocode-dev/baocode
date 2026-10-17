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

/// Lucide's icons the footer uses.
const _copyIcon = 'assets/icons/lucide-copy.svg';
const _checkIcon = 'assets/icons/lucide-check.svg';
const _zapIcon = 'assets/icons/lucide-zap.svg';
const _clockIcon = 'assets/icons/lucide-clock.svg';

/// Under a finished turn: a button to copy its answer, then, faint, how
/// fast the model wrote, the tokens the turn used, how long it took and
/// what it cost, as far as known. Out of the history's selection.
class TurnFooter extends StatelessWidget {
  const TurnFooter({super.key, this.answer, this.worked, this.usage});

  /// What the copy button copies; no button when null.
  final String? answer;
  final Duration? worked;
  final TurnUsage? usage;

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
    final speed = usage?.tokensPerSecond;
    final cost = usage?.costUsd;
    final tokens = usage?.totalTokens;
    final stats = [
      if (speed != null)
        _Stat(
          icon: _zapIcon,
          text: l10n.turnSpeed(speed.round().toString()),
          hint: l10n.turnSpeedHint,
        ),
      if (tokens != null && tokens > 0)
        _Stat(
          text: l10n.turnTokens(AgentStep.formatTokens(tokens)),
          hint: l10n.turnTokensHint(
            AgentStep.formatTokens(usage?.inputTokens ?? 0),
            AgentStep.formatTokens(usage?.outputTokens ?? 0),
          ),
        ),
      if (worked case final worked?)
        _Stat(
          icon: _clockIcon,
          text: AgentStep.formatDuration(worked, l10n: l10n),
          hint: l10n.turnDurationHint,
        ),
      if (cost != null) _Stat(text: formatCost(cost), hint: l10n.turnCostHint),
    ];
    return SelectionContainer.disabled(
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (answer case final answer?) _CopyButton(text: answer),
            for (final stat in stats) ...[const SizedBox(width: 12), stat],
          ],
        ),
      ),
    );
  }
}

/// At the end of a turn under way, faint, where its [TurnFooter] will be:
/// the tokens the model has written so far, then how fast it writes now,
/// while it does.
class LiveTurnStats extends StatelessWidget {
  const LiveTurnStats({super.key, required this.output});

  final TurnOutput output;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final speed = output.tokensPerSecond;
    return SelectionContainer.disabled(
      child: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Stat(
                text: l10n.turnOutputTokens(
                  AgentStep.formatTokens(output.tokens),
                ),
                hint: l10n.turnOutputTokensHint,
              ),
              if (speed != null) ...[
                const SizedBox(width: 12),
                _Stat(
                  icon: _zapIcon,
                  text: l10n.turnSpeed(speed.round().toString()),
                  hint: l10n.turnSpeedLiveHint,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({this.icon, required this.text, required this.hint});

  final String? icon;
  final String text;
  final String hint;

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
          Text(
            text,
            // Not monospaced: its 1 would stand apart from the icon.
            style: TextStyle(color: color, fontSize: 12),
          ),
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
