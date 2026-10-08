import 'package:flutter/material.dart';

import '../../kernel/kernel_types.dart';
import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import 'interaction_panel.dart';

/// Says why the agent's runtime cannot run (not installed, not logged in,
/// crashed), with its last words and a way to try again.
class HealthBanner extends StatefulWidget {
  const HealthBanner({
    super.key,
    required this.health,
    required this.kernelName,
    required this.onRetry,
  });

  final KernelHealth health;
  final String kernelName;
  final VoidCallback onRetry;

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
                  health.message ??
                      context.l10n.healthStopped(widget.kernelName),
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
