import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../kernel/kernel_types.dart';
import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../widgets/agent_step.dart';
import '../widgets/hover_builder.dart';
import '../widgets/shimmer_text.dart';

/// What the session's goal is up to, for [GoalPanel].
enum GoalActivity {
  /// The agent works on it.
  working,

  /// The agent asks the user something.
  needsYou,

  /// Nothing runs: the next message takes it up again.
  waiting,
}

/// The goal the agent works toward (`/goal`), first above the composer:
/// whether it is still being worked on, and, opened, all of it, why it is
/// not met yet, and ways to edit or clear it.
///
/// Met, it says so and, once seen a while, goes; one that cannot be met
/// stays until dismissed.
class GoalPanel extends StatefulWidget {
  const GoalPanel({
    super.key,
    required this.goal,
    required this.activity,
    this.onSet,
    this.onClear,
    required this.onDismiss,
    this.metShownFor = const Duration(seconds: 6),
  });

  final KernelGoal goal;
  final GoalActivity activity;

  /// Sets the condition as the goal instead; null when it cannot be now.
  final ValueChanged<String>? onSet;

  /// Clears the goal; null when it cannot be now.
  final VoidCallback? onClear;

  /// Hides a goal that is over.
  final VoidCallback onDismiss;

  /// How long a met goal shows before it goes.
  final Duration metShownFor;

  /// The longest condition Claude Code takes.
  static const maxLength = 4000;

  @override
  State<GoalPanel> createState() => _GoalPanelState();
}

class _GoalPanelState extends State<GoalPanel> {
  bool _open = false;
  bool _editing = false;
  bool _confirmingClear = false;

  /// Going, once met and seen.
  bool _leaving = false;
  Timer? _metTimer;

  final TextEditingController _text = TextEditingController();
  final FocusNode _textFocus = FocusNode();

  static const _leave = Duration(milliseconds: 220);

  @override
  void didUpdateWidget(GoalPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.goal.condition != oldWidget.goal.condition ||
        widget.goal.setAt != oldWidget.goal.setAt) {
      _editing = false;
      _confirmingClear = false;
      _leaving = false;
    }
    if (widget.goal.state != GoalState.active) {
      _editing = false;
      _confirmingClear = false;
    }
    _scheduleLeave();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleLeave();
  }

  /// Once met, it goes after showing a while; only while shown (its tab in
  /// front, ticking), so that it is seen.
  void _scheduleLeave() {
    final met = widget.goal.state == GoalState.met;
    if (!met || !TickerMode.valuesOf(context).enabled || _leaving) {
      _metTimer?.cancel();
      _metTimer = null;
      return;
    }
    _metTimer ??= Timer(widget.metShownFor, () {
      _metTimer = null;
      // Read through, open: it stays until closed.
      if (!mounted || _open) return;
      setState(() => _leaving = true);
      Timer(_leave, () {
        if (mounted) widget.onDismiss();
      });
    });
  }

  @override
  void dispose() {
    _metTimer?.cancel();
    _text.dispose();
    _textFocus.dispose();
    super.dispose();
  }

  void _startEditing() {
    _text.text = widget.goal.condition;
    _text.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _text.text.length,
    );
    setState(() {
      _open = true;
      _editing = true;
      _confirmingClear = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _textFocus.requestFocus();
    });
  }

  void _save() {
    final condition = _text.text.trim();
    final set = widget.onSet;
    if (condition.isEmpty || set == null) return;
    if (condition != widget.goal.condition) set(condition);
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final goal = widget.goal;
    return AnimatedSize(
      duration: _leave,
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomCenter,
      child: _leaving
          ? const SizedBox(width: double.infinity)
          : Container(
              margin: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: switch (goal.state) {
                    GoalState.active
                        when widget.activity == GoalActivity.working =>
                      _amber.withValues(alpha: 0.55),
                    _ => AppColors.borderStrong,
                  },
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [_buildHeader(context), if (_open) _buildBody()],
              ),
            ),
    );
  }

  static Color get _amber => themeColors['symbolIcon.eventForeground'];

  Widget _buildHeader(BuildContext context) {
    final l10n = context.l10n;
    final goal = widget.goal;
    final over = goal.state != GoalState.active;
    return GestureDetector(
      onTap: () {
        setState(() {
          _open = !_open;
          if (!_open) _confirmingClear = false;
        });
        // Closed after being read: a met one goes in a while still.
        if (!_open) _scheduleLeave();
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
          child: Row(
            children: [
              Icon(
                switch (goal.state) {
                  GoalState.active => Icons.flag_rounded,
                  GoalState.met => Icons.check_circle_rounded,
                  GoalState.failed => Icons.error_outline_rounded,
                },
                size: 14,
                color: switch (goal.state) {
                  GoalState.active => _amber,
                  GoalState.met => themeColors['charts.green'],
                  GoalState.failed => AppColors.removed,
                },
              ),
              const SizedBox(width: 8),
              Text(
                l10n.goalLabel,
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  // All of it shows below, opened.
                  _open ? '' : goal.condition.replaceAll(RegExp(r'\s+'), ' '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              _buildState(context),
              if (over)
                _IconAction(
                  icon: Icons.close_rounded,
                  tooltip: l10n.goalDismiss,
                  onTap: widget.onDismiss,
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    _open
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_up_rounded,
                    size: 16,
                    color: AppColors.textFaint,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildState(BuildContext context) {
    final l10n = context.l10n;
    final goal = widget.goal;
    final style = TextStyle(color: AppColors.textMuted, fontSize: 12);
    return switch (goal.state) {
      GoalState.met => Text(
        [
          l10n.goalMet,
          if (goal.duration case final duration?)
            AgentStep.formatDuration(duration, l10n: l10n),
        ].join(' · '),
        style: style.copyWith(color: themeColors['charts.green']),
      ),
      GoalState.failed => Text(
        l10n.goalFailed,
        style: style.copyWith(color: AppColors.removed),
      ),
      GoalState.active => switch (widget.activity) {
        GoalActivity.working => ShimmerText(
          l10n.goalWorking,
          ellipsis: false,
          padding: EdgeInsets.zero,
          style: const TextStyle(fontSize: 12),
        ),
        GoalActivity.needsYou => Text(
          l10n.goalNeedsYou,
          style: style.copyWith(color: _amber),
        ),
        GoalActivity.waiting => Text(l10n.goalWaiting, style: style),
      },
    };
  }

  Widget _buildBody() {
    final l10n = context.l10n;
    final goal = widget.goal;
    final muted = TextStyle(color: AppColors.textMuted, fontSize: 12);
    final active = goal.state == GoalState.active;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 0, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_editing)
            _buildEditor()
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: SingleChildScrollView(
                child: SelectableText(
                  goal.condition,
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 12.5,
                    height: 1.45,
                  ),
                ),
              ),
            ),
          if (goal.lastReason case final reason? when reason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${l10n.goalLastCheck}  ',
                    style: TextStyle(color: AppColors.textFaint),
                  ),
                  TextSpan(text: reason),
                ],
              ),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: muted,
            ),
          ],
          if (active && !_editing) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                if (goal.checks > 0)
                  Text(
                    l10n.goalChecks(goal.checks),
                    style: muted.copyWith(color: AppColors.textFaint),
                  ),
                const Spacer(),
                if (_confirmingClear) ...[
                  Text(l10n.goalClearConfirm, style: muted),
                  const SizedBox(width: 8),
                  _TextAction(
                    label: l10n.goalClear,
                    danger: true,
                    onTap: () {
                      setState(() => _confirmingClear = false);
                      widget.onClear?.call();
                    },
                  ),
                  _TextAction(
                    label: l10n.commonCancel,
                    onTap: () => setState(() => _confirmingClear = false),
                  ),
                ] else ...[
                  _TextAction(
                    label: l10n.goalEdit,
                    onTap: widget.onSet == null ? null : _startEditing,
                  ),
                  _TextAction(
                    label: l10n.goalClear,
                    onTap: widget.onClear == null
                        ? null
                        : () => setState(() => _confirmingClear = true),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEditor() {
    final l10n = context.l10n;
    final colors = themeColors;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: BorderSide(color: AppColors.borderStrong),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                setState(() => _editing = false),
            const SingleActivator(LogicalKeyboardKey.enter): _save,
          },
          child: TextField(
            controller: _text,
            focusNode: _textFocus,
            minLines: 1,
            maxLines: 6,
            maxLength: GoalPanel.maxLength,
            maxLengthEnforcement: MaxLengthEnforcement.enforced,
            // Shift-Enter for a new line; Enter sets it.
            keyboardType: TextInputType.multiline,
            style: TextStyle(color: colors['input.foreground'], fontSize: 12.5),
            decoration: InputDecoration(
              isDense: true,
              counterText: '',
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 7,
              ),
              filled: true,
              fillColor: colors['input.background'],
              border: border,
              enabledBorder: border,
              focusedBorder: border.copyWith(
                borderSide: BorderSide(color: colors['focusBorder']),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            if (widget.activity == GoalActivity.working)
              Flexible(
                child: Text(
                  l10n.goalAfterTurn,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.textFaint, fontSize: 12),
                ),
              ),
            const Spacer(),
            _TextAction(
              label: l10n.commonCancel,
              onTap: () => setState(() => _editing = false),
            ),
            ListenableBuilder(
              listenable: _text,
              builder: (context, _) => _TextAction(
                label: l10n.goalSet,
                strong: true,
                onTap: _text.text.trim().isEmpty ? null : _save,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A small worded button in the panel; greyed out without [onTap].
class _TextAction extends StatelessWidget {
  const _TextAction({
    required this.label,
    this.onTap,
    this.danger = false,
    this.strong = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool danger;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final tap = onTap;
    return Semantics(
      button: true,
      enabled: tap != null,
      child: HoverBuilder(
        cursor: tap == null ? MouseCursor.defer : SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          onTap: tap,
          child: Container(
            margin: const EdgeInsets.only(left: 4),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: hovered && tap != null ? AppColors.hover : null,
              borderRadius: BorderRadius.circular(5),
              border: strong ? Border.all(color: AppColors.borderStrong) : null,
            ),
            child: Text(
              label,
              style: TextStyle(
                color: tap == null
                    ? AppColors.textFaint
                    : danger
                    ? AppColors.removed
                    : AppColors.text,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({required this.icon, required this.tooltip, this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(2),
            margin: const EdgeInsets.only(left: 2),
            decoration: BoxDecoration(
              color: hovered ? AppColors.hover : null,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(icon, size: 14, color: AppColors.textMuted),
          ),
        ),
      ),
    );
  }
}
