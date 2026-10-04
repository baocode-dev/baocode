import 'dart:async';

import 'package:flutter/material.dart';

import '../chat/widgets/hover_builder.dart';
import '../ide/ide_button.dart';
import '../l10n/l10n.dart';
import '../sidebar/sidebar.dart' show SidebarIconButton;
import '../theme/app_theme.dart';
import '../theme/codicons.dart';
import '../theme/workbench_theme.dart' show themeColors;
import 'feature_tip.dart';
import 'feature_tips_controller.dart';

/// The setup checklist (see FeatureTipsController): over the new agent's
/// input and in the empty workspace, a card of the first launch's tips,
/// each turned on with a button or closed; "Hide" folds it into the
/// sidebar's entry. Not a dialog: it takes no focus, and the input stays
/// where it is.
class FeatureTipsCard extends StatelessWidget {
  const FeatureTipsCard({super.key, required this.controller});

  final FeatureTipsController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      if (!controller.cardVisible) return const SizedBox.shrink();
      final l10n = context.l10n;
      final tips = controller.checklist;
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 6),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Codicons.rocket, size: 14, color: AppColors.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.tipsSetupTitle,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  l10n.tipsSetupCount(controller.doneCount, tips.length),
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
                const SizedBox(width: 4),
                IdeButton(
                  label: l10n.tipsHide,
                  secondary: true,
                  onPressed: () => unawaited(controller.collapse()),
                ),
              ],
            ),
            const SizedBox(height: 4),
            for (final tip in tips)
              FeatureTipRow(
                key: ValueKey(tip.id),
                controller: controller,
                tip: tip,
              ),
          ],
        ),
      );
    },
  );
}

/// One tip of the checklist (or of Settings → General's list): its words,
/// and Turn On and close, or a tick once it is on.
class FeatureTipRow extends StatefulWidget {
  const FeatureTipRow({
    super.key,
    required this.controller,
    required this.tip,
    this.dismissible = true,
  });

  final FeatureTipsController controller;
  final FeatureTip tip;

  /// With the close button (the checklist's; settings list them all).
  final bool dismissible;

  @override
  State<FeatureTipRow> createState() => _FeatureTipRowState();
}

class _FeatureTipRowState extends State<FeatureTipRow> {
  bool _busy = false;

  Future<void> _accept() async {
    setState(() => _busy = true);
    await widget.controller.accept(widget.tip, TipContext.of(context));
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tip = widget.tip;
    final controller = widget.controller;
    final done = controller.isDone(tip);
    final error = controller.errors[tip.id];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(tip.icon, size: 14, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tip.title(l10n),
                  style: TextStyle(color: AppColors.text, fontSize: 12.5),
                ),
                Text(
                  tip.body(l10n),
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                ),
                if (error != null)
                  SelectableText(
                    l10n.tipsFailed(tip.title(l10n), error),
                    style: TextStyle(
                      color: themeColors['errorForeground'],
                      fontSize: 11.5,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (done)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Semantics(
                label: l10n.tipsDone,
                child: Icon(Codicons.check, size: 16, color: AppColors.added),
              ),
            )
          else ...[
            IdeButton(
              label: l10n.tipsTurnOn,
              onPressed: _busy ? null : () => unawaited(_accept()),
            ),
            if (widget.dismissible)
              SidebarIconButton(
                icon: Codicons.close,
                tooltip: l10n.tipsDismiss,
                size: 22,
                onTap: () => unawaited(controller.dismiss(tip)),
              ),
          ],
        ],
      ),
    );
  }
}

/// The checklist folded: "Setup n/m" at the foot of the sidebar, which
/// brings the card back.
class FeatureTipsEntry extends StatelessWidget {
  const FeatureTipsEntry({super.key, required this.controller});

  final FeatureTipsController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      if (!controller.entryVisible) return const SizedBox.shrink();
      final label = context.l10n.tipsSetupEntry(
        controller.doneCount,
        controller.checklist.length,
      );
      return Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        onTap: () => unawaited(controller.restore()),
        child: HoverBuilder(
          cursor: SystemMouseCursors.click,
          builder: (context, hovered) => GestureDetector(
            onTap: () => unawaited(controller.restore()),
            child: Container(
              height: 26,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: hovered ? AppColors.hover : Colors.transparent,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Row(
                children: [
                  Icon(Codicons.rocket, size: 13, color: AppColors.textMuted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Settings → General's list of the tips not on yet, each with Turn On;
/// nothing when tips are off or all is on.
class FeatureTipsSettingsList extends StatefulWidget {
  const FeatureTipsSettingsList({
    super.key,
    required this.controller,
    required this.builder,
  });

  final FeatureTipsController controller;

  /// Lays out the rows (a settings card), when there are any.
  final Widget Function(BuildContext context, List<Widget> rows) builder;

  @override
  State<FeatureTipsSettingsList> createState() =>
      _FeatureTipsSettingsListState();
}

class _FeatureTipsSettingsListState extends State<FeatureTipsSettingsList> {
  List<FeatureTip>? _pending;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_read);
    _read();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_read);
    super.dispose();
  }

  Future<void> _read() async {
    final pending = await widget.controller.pending();
    if (mounted) setState(() => _pending = pending);
  }

  @override
  Widget build(BuildContext context) {
    final pending = _pending;
    if (!widget.controller.enabled || pending == null || pending.isEmpty) {
      return const SizedBox.shrink();
    }
    return widget.builder(context, [
      for (final tip in pending)
        FeatureTipRow(
          key: ValueKey(tip.id),
          controller: widget.controller,
          tip: tip,
          dismissible: false,
        ),
    ]);
  }
}
