import 'dart:async';

import 'package:flutter/material.dart';

import '../../kernel/kernel_types.dart';
import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../../settings/pages/settings_widgets.dart' show SettingsTextField;
import '../../workspace/editor_launcher.dart';
import 'interaction_panel.dart';

/// Says why the agent's runtime cannot run (not installed, not logged in,
/// crashed), with its last words and a way to try again. With no model to
/// run on, not an error: a model to set up ([onSetUpModel]).
class HealthBanner extends StatefulWidget {
  const HealthBanner({
    super.key,
    required this.health,
    required this.kernelName,
    required this.onRetry,
    this.onSetUpModel,
  });

  final KernelHealth health;
  final String kernelName;
  final VoidCallback onRetry;
  final VoidCallback? onSetUpModel;

  /// Opens a page in the browser (where to sign in).
  static Future<bool> Function(String url) openLink = openExternal;

  static bool shows(KernelHealth health) =>
      health.status == KernelHealthStatus.failed;

  @override
  State<HealthBanner> createState() => _HealthBannerState();
}

class _HealthBannerState extends State<HealthBanner> {
  bool _details = false;

  @override
  Widget build(BuildContext context) {
    final health = widget.health;
    if ((health.noModel, widget.onSetUpModel) case (true, final setUp?)) {
      return _NoModel(onSetUp: setUp);
    }
    if (health.setup case final setup?) {
      return _Setup(setup: setup, kernelName: widget.kernelName);
    }
    final detail = health.detail?.trim();
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
      decoration: BoxDecoration(
        color: themeColors['inputValidation.errorBackground'],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: themeColors['inputValidation.errorBorder']),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 15,
                color: themeColors['errorForeground'],
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  switch (health.missingFolder) {
                    final folder? => context.l10n.healthFolderGone(folder),
                    null =>
                      health.message ??
                          context.l10n.healthStopped(widget.kernelName),
                  },
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12.5,
                  ),
                ),
              ),
              if (detail != null && detail.isNotEmpty) ...[
                PanelButton(
                  label: _details
                      ? context.l10n.healthHideDetails
                      : context.l10n.healthDetails,
                  onTap: () => setState(() => _details = !_details),
                ),
                const SizedBox(width: 6),
              ],
              PanelButton(
                label: context.l10n.healthRetry,
                primary: true,
                onTap: widget.onRetry,
              ),
            ],
          ),
          if (_details && detail != null)
            Container(
              margin: const EdgeInsets.only(top: 8),
              constraints: const BoxConstraints(maxHeight: 160),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.code,
                borderRadius: BorderRadius.circular(6),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  detail,
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontFamily: AppFonts.mono,
                    fontFamilyFallback: AppFonts.monoFallbacks,
                    fontSize: 11.5,
                    height: 1.45,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// No model to run on yet: a model to set up, in the accent's colors.
class _NoModel extends StatelessWidget {
  const _NoModel({required this.onSetUp});

  final VoidCallback onSetUp;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accent;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: .35)),
      ),
      child: Row(
        children: [
          Icon(Codicons.sparkle, size: 15, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.l10n.healthNoModel,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 12.5),
            ),
          ),
          PanelButton(
            label: context.l10n.modelSetUp,
            primary: true,
            onTap: onSetUp,
          ),
        ],
      ),
    );
  }
}

/// What to set up for the agent to run: install it, sign in, or (a
/// remote project) nothing to do; and how that goes.
class _Setup extends StatefulWidget {
  const _Setup({required this.setup, required this.kernelName});

  final KernelSetup setup;
  final String kernelName;

  @override
  State<_Setup> createState() => _SetupState();
}

class _SetupState extends State<_Setup> {
  /// The code given last: given once (the field gives it again as it
  /// loses focus).
  String? _given;

  @override
  void initState() {
    super.initState();
    _open(null);
  }

  @override
  void didUpdateWidget(_Setup old) {
    super.didUpdateWidget(old);
    _open(old.setup.link);
  }

  /// The sign-in page, opened once known.
  void _open(Uri? before) {
    final link = widget.setup.link;
    if (link != null && link != before) {
      unawaited(HealthBanner.openLink('$link'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final setup = widget.setup;
    final name = widget.kernelName;
    final accent = AppColors.accent;
    final progress = setup.progress;
    final text = switch (setup.kind) {
      KernelSetupKind.install when progress != null =>
        l10n.kernelSetupInstalling(name, (progress * 100).floor()),
      KernelSetupKind.install => l10n.kernelSetupInstall(name),
      KernelSetupKind.login when setup.submitCode != null =>
        l10n.kernelSetupLoginCode,
      KernelSetupKind.login when setup.signingIn =>
        l10n.kernelSetupLoginOpening,
      KernelSetupKind.login => l10n.kernelSetupLogin(name),
      KernelSetupKind.localOnly => l10n.kernelSetupLocalOnly(name),
    };
    final error = setup.error?.trim();
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: .35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                switch (setup.kind) {
                  KernelSetupKind.install => Codicons.cloudDownload,
                  KernelSetupKind.login => Codicons.account,
                  KernelSetupKind.localOnly => Codicons.remote,
                },
                size: 15,
                color: accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12.5,
                  ),
                ),
              ),
              if (setup.link case final link?) ...[
                PanelButton(
                  label: l10n.kernelSetupOpenPage,
                  onTap: () => unawaited(HealthBanner.openLink('$link')),
                ),
                const SizedBox(width: 6),
              ],
              if (setup.cancel case final cancel?)
                PanelButton(label: l10n.kernelSetupCancel, onTap: cancel),
              if (setup.start case final start?)
                PanelButton(
                  label: switch (setup.kind) {
                    KernelSetupKind.install => l10n.kernelSetupInstallAction,
                    _ => l10n.kernelSetupLoginAction,
                  },
                  primary: true,
                  onTap: start,
                ),
            ],
          ),
          if (progress != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: SizedBox(
                  height: 4,
                  child: LinearProgressIndicator(
                    value: progress,
                    color: accent,
                    backgroundColor: themeColors['editorWidget.border'],
                  ),
                ),
              ),
            ),
          if (setup.submitCode case final submit?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SettingsTextField(
                  value: '',
                  width: 320,
                  autofocus: true,
                  hint: l10n.kernelSetupCodeHint,
                  semanticLabel: l10n.kernelSetupCodeHint,
                  onSubmitted: (code) {
                    final given = code.trim();
                    if (given.isEmpty || given == _given) return;
                    _given = given;
                    submit(given);
                  },
                ),
              ),
            ),
          if (error != null && error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: SelectableText(
                error,
                style: TextStyle(
                  color: themeColors['errorForeground'],
                  fontSize: 11.5,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
