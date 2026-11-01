import 'dart:async';

import 'package:flutter/material.dart';

import '../../channel/channel_setup.dart' show ChannelSetup;
import '../../ide/ide_dialog.dart';
import '../../kernel/agent_kernel.dart';
import '../../kernel/kernel_types.dart';
import '../../l10n/l10n.dart';
import '../../models/model_provider.dart' show parseModelRef;
import '../../models/model_providers.dart';
import '../../models/model_runtime.dart' show codexService;
import '../../models/model_welcome.dart';
import '../../settings/settings_dialog.dart'
    show SettingsOpener, SettingsSection;
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../chat_session.dart';
import '../resume_after_reset.dart';
import '../widgets/hover_builder.dart';
import 'composer_picker.dart';

/// The pill that picks [session]'s model, each model's settings (its
/// effort, its context) beside it: the composer's, and the one a plan is
/// started with. With no model to run on, one that sets a model up
/// ([showModelWelcome]); nothing where the kernel picks no model.
class SessionModelPicker extends StatelessWidget {
  const SessionModelPicker({
    super.key,
    required this.session,
    this.pickerKey,
    this.tooltip,
    this.tapRegionGroupId,
    this.focusNode,
  });

  final ChatSession session;

  /// The picker's own, to open it from a keybinding.
  final GlobalKey<ComposerPickerState>? pickerKey;

  /// See [ComposerPicker.tooltip], [ComposerPicker.tapRegionGroupId] and
  /// [ComposerPicker.focusNode].
  final String? tooltip;
  final Object? tapRegionGroupId;
  final FocusNode? focusNode;

  /// The model with its settings, e.g. "Opus · 1M · High": the context
  /// only when it is not the standard one; its upstream before it only
  /// when another upstream has a model of its name.
  String _label(KernelOption model, List<KernelOption> options) => [
    if (model.group case final group?
        when options.any(
          (other) => other.label == model.label && other.group?.id != group.id,
        ))
      group.label,
    model.label,
    for (final setting in session.modelSettings(model.id))
      if (setting.selected case final selected?
          when setting.kind != KernelChoiceKind.context ||
              selected != setting.options.first)
        selected.label,
  ].join(' · ');

  /// Runs [pick], which switches to [option]: once confirmed, if that
  /// restarts the agent on another upstream mid-conversation.
  Future<void> _switch(
    BuildContext context,
    KernelOption option,
    VoidCallback pick,
  ) async {
    if (!session.switchRestarts(option.id)) return pick();
    final l10n = context.l10n;
    final choice = await showIdeDialog(
      context,
      message: l10n.modelsSwitchTitle(option.group?.label ?? option.label),
      detail: l10n.modelsSwitchDetail,
      buttons: [l10n.modelsSwitchConfirm],
      type: IdeDialogType.question,
    );
    if (choice == 0 && context.mounted) pick();
  }

  /// Beside a model of the account's plan, last: whether an agent stopped
  /// at its usage limit goes on by itself once it resets. Not where it
  /// cannot be set.
  ModelSettingChoice? _resumeAfterLimit(BuildContext context, String model) {
    final write = ResumeAfterResetSetting.write;
    if (write == null || !session.continuesAfterLimit(model)) return null;
    final on = KernelOption(
      'on',
      context.l10n.resumeAfterLimitToggle,
      Icons.schedule_send_rounded,
      '',
    );
    final enabled = ResumeAfterResetSetting.current();
    return ModelSettingChoice(
      kind: null,
      options: [on],
      selected: enabled ? on : null,
      toggle: true,
      onSelected: (_) => write(!enabled),
    );
  }

  /// Beside a model of ChatGPT accounts, last: whether an account out of
  /// quota uses up a reset credit of its own by itself.
  ModelSettingChoice? _autoResetCredits(BuildContext context, String model) {
    final providers = ModelProviders.current;
    final provider = providers.provider(parseModelRef(model)?.provider);
    if (provider == null || !provider.protocol.usesAccounts) return null;
    final on = KernelOption(
      'on',
      context.l10n.autoResetCreditsToggle,
      Icons.restart_alt_rounded,
      '',
    );
    final enabled = provider.autoResetCredits;
    return ModelSettingChoice(
      kind: null,
      options: [on],
      selected: enabled ? on : null,
      toggle: true,
      onSelected: (_) => unawaited(() async {
        final now = providers.provider(provider.id) ?? provider;
        await providers.save(now.copyWith(autoResetCredits: !enabled));
        // Turned on: one out of quota already uses its credit now.
        if (!enabled) {
          await codexService.refreshUsage(
            providers.provider(provider.id) ?? now,
          );
        }
      }()),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    // Its switches turned, as settings.json says.
    listenable: Listenable.merge([
      ?ResumeAfterResetSetting.changes,
      ModelProviders.current,
    ]),
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final model = session.models;
    final l10n = context.l10n;
    if (model == null) {
      if (!session.health.noModel) return const SizedBox.shrink();
      return _SetUpPill(
        label: l10n.modelSetUp,
        onTap: () => unawaited(showModelWelcome(context)),
      );
    }
    return ComposerPicker(
      key: pickerKey,
      options: model.options,
      selected: model.selected,
      label: _label(model.selected, model.options),
      // Each its name alone, one line; its maker's logo and its upstream's
      // heading tell the rest.
      describes: false,
      settingsOf: (option) => [
        for (final setting in session.modelSettings(option.id))
          ModelSettingChoice(
            kind: setting.kind,
            options: setting.options,
            selected: setting.selected,
            toggle: setting.toggle,
            onSelected: (choice) => unawaited(
              _switch(context, option, () => setting.onSelected(choice)),
            ),
          ),
        ?_resumeAfterLimit(context, option.id),
        ?_autoResetCredits(context, option.id),
      ],
      tooltip: tooltip,
      menuWidth: 260,
      searchPlaceholder: l10n.modelsSearch,
      footers: [
        if (SettingsOpener.maybeOf(context) case final open?)
          (
            label: ChannelSetup.channelBuild
                ? l10n.channelAccountTitle
                : l10n.modelsManage,
            icon: Icons.tune_rounded,
            onTap: () => open(SettingsSection.models),
          ),
      ],
      tapRegionGroupId: tapRegionGroupId,
      focusNode: focusNode,
      onSelected: (option) =>
          unawaited(_switch(context, option, () => model.onSelected(option))),
    );
  }
}

/// In the model's place while there is none: as its pill, in the accent,
/// a click away from setting one up.
class _SetUpPill extends StatelessWidget {
  const _SetUpPill({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accent;
    return HoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (context, hovered) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: hovered ? .2 : .12),
            border: Border.all(color: accent.withValues(alpha: .4)),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Codicons.sparkle, size: 13, color: accent),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(color: accent, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
