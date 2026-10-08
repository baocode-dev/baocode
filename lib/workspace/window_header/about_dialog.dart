import 'package:flutter/material.dart';

import '../../chat/panels/interaction_panel.dart';
import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../../update/version.dart';

/// The app's icon, as the Dock and the taskbar show it.
const aboutIconAsset = 'assets/branding/app_icon.png';

/// Help → About: what the app is, and which build this is.
Future<void> showAboutBaoCode(BuildContext context) => showDialog<void>(
  context: context,
  // Black, not the theme's: as upstream's dialogs dim the window.
  barrierColor: const Color(0x88000000),
  builder: (context) => const _AboutBaoCodeDialog(),
);

class _AboutBaoCodeDialog extends StatelessWidget {
  const _AboutBaoCodeDialog();

  @override
  Widget build(BuildContext context) {
    // As upstream's dialog: a widget's colors, bordered in high contrast.
    final colors = themeColors;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        width: 360,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: switch (colors.get('contrastBorder')) {
            final border? => Border.all(color: border),
            null => null,
          },
          boxShadow: [
            BoxShadow(
              color: colors['widget.shadow'],
              blurRadius: 32,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Image.asset(
                  aboutIconAsset,
                  width: 28,
                  height: 28,
                  filterQuality: FilterQuality.medium,
                ),
                SizedBox(width: 10),
                Text(
                  'BaoCode',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(width: 10),
                Text(
                  currentAppVersion.marketing,
                  style: TextStyle(
                    color: AppColors.textFaint,
                    fontSize: 12,
                    fontFamily: AppFonts.mono,
                    fontFamilyFallback: AppFonts.monoFallbacks,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              context.l10n.aboutDescription,
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerRight,
              child: PanelButton(
                label: context.l10n.commonClose,
                primary: true,
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
