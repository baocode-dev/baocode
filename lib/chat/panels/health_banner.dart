import 'package:flutter/material.dart';

import '../../kernel/kernel_types.dart';
import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../../theme/workbench_theme.dart' show themeColors;
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
