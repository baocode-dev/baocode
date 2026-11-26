import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Icons not among the codicons, drawn from SVGs in assets/icons/ (each
/// says where it is from), as [IconData] for where an icon is one: [AppIcon]
/// draws them, [Icon] does not.
abstract final class SvgIcons {
  static const fontFamily = 'bao-svg';

  /// Usage: a conversation's, and Settings → Usage (Lucide's chart-pie).
  static const usage = IconData(0xe000, fontFamily: fontFamily);

  /// The conversation's selection bar's Copy, Quote and By the Way (Remix
  /// Icon's file-copy-line, double-quotes-l and chat-3-line).
  static const copy = IconData(0xe001, fontFamily: fontFamily);
  static const quote = IconData(0xe002, fontFamily: fontFamily);
  static const aside = IconData(0xe003, fontFamily: fontFamily);

  static const _assets = {
    0xe000: 'assets/icons/lucide-chart-pie.svg',
    0xe001: 'assets/icons/file-copy-line.svg',
    0xe002: 'assets/icons/double-quotes-l.svg',
    0xe003: 'assets/icons/chat-3-line.svg',
  };

  /// [icon]'s SVG, where it is one of these.
  static String? assetOf(IconData icon) =>
      icon.fontFamily == fontFamily ? _assets[icon.codePoint] : null;
}

/// [icon] as [Icon] draws it, or its SVG for one of [SvgIcons].
class AppIcon extends StatelessWidget {
  const AppIcon(this.icon, {super.key, this.size, this.color});

  final IconData icon;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final asset = SvgIcons.assetOf(icon);
    if (asset == null) return Icon(icon, size: size, color: color);
    final theme = IconTheme.of(context);
    final side = size ?? theme.size ?? 24;
    final tint = color ?? theme.color;
    // As [Icon]'s glyph: its size in a box made larger (a button's), in
    // the middle, not stretched to fill it.
    return SizedBox.square(
      dimension: side,
      child: Center(
        child: SvgPicture.asset(
          asset,
          width: side,
          height: side,
          colorFilter: tint == null
              ? null
              : ColorFilter.mode(tint, BlendMode.srcIn),
        ),
      ),
    );
  }
}
