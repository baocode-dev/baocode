import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

/// Antigravity's mark in its colors (devicon's, MIT), on a round ground a
/// shade off the theme's: what tells its conversations apart.
class AntigravityBadge extends StatelessWidget {
  const AntigravityBadge({super.key, required this.size});

  /// Drawn from the SVG with its blurs (`flutter_svg` draws none).
  static const asset = 'assets/model_icons/antigravity.png';

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Color.alphaBlend(
          AppColors.text.withValues(alpha: .1),
          AppColors.background,
        ),
        border: Border.all(
          color: AppColors.text.withValues(alpha: .14),
          width: .5,
        ),
      ),
      child: Image.asset(
        asset,
        width: size * .68,
        height: size * .68,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}
