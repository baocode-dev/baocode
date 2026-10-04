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
/// composer and in the empty workspace, the first launch's tips as tiles,
/// each turned on with a click or closed; "Hide" folds it into the
/// sidebar's entry. Not a dialog: it takes no focus, and the composer stays
/// where it is.
class FeatureTipsCard extends StatelessWidget {
  const FeatureTipsCard({super.key, required this.controller, this.orElse});

  final FeatureTipsController controller;

  /// Built while the card is not shown (folded, all done, or tips off).
  final Widget? orElse;

  /// The width two tiles a row take from.
  static const _twoColumns = 400.0;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      if (!controller.cardVisible) return orElse ?? const SizedBox.shrink();
      final l10n = context.l10n;
      final tips = controller.checklist;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 8),
            child: Row(
              children: [
                Icon(
                  Icons.auto_awesome_outlined,
                  size: 14,
                  color: AppColors.accent,
                ),
                const SizedBox(width: 6),
                Text(
                  l10n.tipsSetupTitle,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.tipsSetupCount(controller.doneCount, tips.length),
                  style: TextStyle(color: AppColors.textFaint, fontSize: 12),
                ),
                const Spacer(),
                _TextAction(
                  label: l10n.tipsHide,
                  onTap: () => unawaited(controller.collapse()),
                ),
              ],
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= _twoColumns ? 2 : 1;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < tips.length; i += columns)
                    Padding(
                      padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
                      child: IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var j = i; j < i + columns; j++) ...[
                              if (j > i) const SizedBox(width: 8),
                              Expanded(
                                child: j < tips.length
                                    ? _FeatureTipTile(
                                        key: ValueKey(tips[j].id),
                                        controller: controller,
                                        tip: tips[j],
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      );
    },
  );
}

/// One tip of the checklist: its icon, words and "Turn On", the whole tile
/// a button; once on, a tick. Closed with the X it shows hovered.
class _FeatureTipTile extends StatefulWidget {
  const _FeatureTipTile({
    super.key,
    required this.controller,
    required this.tip,
  });

  final FeatureTipsController controller;
  final FeatureTip tip;

  @override
  State<_FeatureTipTile> createState() => _FeatureTipTileState();
}

class _FeatureTipTileState extends State<_FeatureTipTile> {
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
    final enabled = !done && !_busy;
    final tint = done ? AppColors.added : AppColors.accent;
    return Semantics(
      button: enabled,
      label: tip.title(l10n),
      child: HoverBuilder(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        builder: (context, hovered) => GestureDetector(
          onTap: enabled ? () => unawaited(_accept()) : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
            decoration: BoxDecoration(
              color: hovered && enabled ? AppColors.hover : AppColors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: done
                      ? Semantics(
                          container: true,
                          label: l10n.tipsDone,
                          child: Icon(Codicons.check, size: 14, color: tint),
                        )
                      : Icon(tip.icon, size: 14, color: tint),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tip.title(l10n),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: done
                              ? AppColors.textMuted
                              : AppColors.textPrimary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        tip.body(l10n),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11.5,
                          height: 1.35,
                        ),
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          l10n.tipsFailed(tip.title(l10n), error),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: themeColors['errorForeground'],
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                      if (!done) ...[
                        const Spacer(),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Text(
                              l10n.tipsTurnOn,
                              style: TextStyle(
                                color: _busy
                                    ? AppColors.textFaint
                                    : AppColors.accent,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              Codicons.arrowRight,
                              size: 12,
                              color: _busy
                                  ? AppColors.textFaint
                                  : AppColors.accent,
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (!done)
                  // Room kept for it, the words not moving as it shows.
                  Visibility.maintain(
                    visible: hovered,
                    child: SidebarIconButton(
                      icon: Codicons.close,
                      tooltip: l10n.tipsDismiss,
                      size: 20,
                      onTap: () => unawaited(controller.dismiss(tip)),
                    ),
                  )
                else
                  const SizedBox(width: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A word to click, muted until hovered: the card's "Hide".
class _TextAction extends StatelessWidget {
  const _TextAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: HoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (context, hovered) => GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Text(
            label,
            style: TextStyle(
              color: hovered ? AppColors.text : AppColors.textMuted,
              fontSize: 12,
            ),
          ),
        ),
      ),
    ),
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
