import 'package:flutter/widgets.dart';

/// Antigravity's mark in its colors (devicon's, MIT), on a round light
/// ground in any theme, so its colors show: what tells its conversations
/// apart.
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
        color: const Color(0xFFF3F3F4),
        border: Border.all(color: const Color(0x1F000000), width: .5),
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
