import 'package:flutter/material.dart';

import '../../icons/brand_logos.dart';
import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../chat_models.dart';

/// Describes one side (origin or destination) of a [KernelSwitchBlock].
///
/// Built-in endpoints are provided for the current kernels; new kernels or
/// custom ACP agents can be added with [KernelSwitchEndpoint.brand],
/// [KernelSwitchEndpoint.asset], or [KernelSwitchEndpoint.custom].
class KernelSwitchEndpoint {
  const KernelSwitchEndpoint.custom({
    required this.id,
    required this.name,
    required this.color,
    required this.iconBuilder,
  });

  /// Creates an endpoint using a bundled monochrome [BrandLogo] tinted in
  /// [color] (e.g. `'claude'`, `'openai'`, `'gemini'`).
  factory KernelSwitchEndpoint.brand({
    required String id,
    required String name,
    required String brand,
    required Color color,
  }) => KernelSwitchEndpoint.custom(
    id: id,
    name: name,
    color: color,
    iconBuilder: (_, size) => BrandLogo(brand, size: size, color: color),
  );

  /// Creates an endpoint using a full-color raster image asset (e.g.
  /// `'assets/provider_logos/antigravity.png'`).
  factory KernelSwitchEndpoint.asset({
    required String id,
    required String name,
    required String assetPath,
    required Color color,
    double sizeOffset = 1,
  }) => KernelSwitchEndpoint.custom(
    id: id,
    name: name,
    color: color,
    iconBuilder: (_, size) => Image(
      image: AssetImage(assetPath),
      width: size + sizeOffset,
      height: size + sizeOffset,
      filterQuality: FilterQuality.medium,
    ),
  );

  /// Stable identifier for serialization / transcript lookup.
  final String id;

  /// Human-readable display name.
  final String name;

  /// Brand accent color used on this side of the bridge (and arrowhead when on
  /// the destination side).
  final Color color;

  /// Builds the bare icon for this endpoint at the given logical [size].
  final Widget Function(BuildContext context, double size) iconBuilder;

  Widget buildIcon(BuildContext context, {double size = 15}) =>
      iconBuilder(context, size);

  static const _antigravityBlue = Color(0xFF4285F4);

  /// Claude Code (Anthropic Claude starburst mark).
  static final KernelSwitchEndpoint claudeCode = KernelSwitchEndpoint.brand(
    id: 'claude-code',
    name: 'Claude Code',
    brand: 'claude',
    color: AppColors.claude,
  );

  /// Antigravity ACP (`agy` multicolor mark).
  static final KernelSwitchEndpoint antigravity = KernelSwitchEndpoint.asset(
    id: 'antigravity-acp',
    name: 'Antigravity ACP',
    assetPath: 'assets/provider_logos/antigravity.png',
    color: _antigravityBlue,
  );

  /// Built-in endpoints indexed by [id].
  static final Map<String, KernelSwitchEndpoint> known = {
    claudeCode.id: claudeCode,
    antigravity.id: antigravity,
  };

  /// Looks up a known endpoint by [id], falling back to a neutral generic
  /// endpoint when an unknown future kernel id is encountered.
  static KernelSwitchEndpoint resolve(String id, {String? name}) =>
      known[id] ??
      KernelSwitchEndpoint.custom(
        id: id,
        name: name ?? id,
        color: AppColors.accent,
        iconBuilder: (_, size) => Icon(
          Icons.hub_outlined,
          size: size,
          color: AppColors.textMuted,
        ),
      );
}

/// A restrained inline handoff line shown when a conversation switches
/// between two kernels:
/// `[from icon] --- label ---> [to icon]`, with no card or badge.
class KernelSwitchBlock extends StatelessWidget {
  const KernelSwitchBlock({
    super.key,
    required this.from,
    required this.to,
    this.label,
  });

  /// Builds a [KernelSwitchBlock] from a [KernelSwitchItem] by resolving its
  /// serialized kernel ids through [KernelSwitchEndpoint.resolve].
  factory KernelSwitchBlock.fromItem(KernelSwitchItem item, {Key? key}) =>
      KernelSwitchBlock(
        key: key,
        from: KernelSwitchEndpoint.resolve(
          item.fromKernel,
          name: item.fromName,
        ),
        to: KernelSwitchEndpoint.resolve(item.toKernel, name: item.toName),
      );

  /// Plain text rendered for [item], matching what copying the widget yields.
  static String plainText(KernelSwitchItem item, {AppLocalizations? l10n}) {
    final target = KernelSwitchEndpoint.resolve(
      item.toKernel,
      name: item.toName,
    );
    return (l10n ?? englishLocalizations).noticeKernelSwitch(target.name);
  }

  /// Kernel handing off the conversation.
  final KernelSwitchEndpoint from;

  /// Kernel taking over the conversation.
  final KernelSwitchEndpoint to;

  /// Optional custom message centered on the bridge.
  /// Defaults to the localized `noticeKernelSwitch` string for [to.name].
  final String? label;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final neutral = AppColors.textFaint.withValues(alpha: isDark ? 0.45 : 0.50);
    final text = label ?? context.l10n.noticeKernelSwitch(to.name);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            from.buildIcon(context, size: 15),
            const SizedBox(width: 8),
            SizedBox(
              width: 36,
              height: 12,
              child: CustomPaint(
                painter: _BridgePainter(
                  startColor: from.color.withValues(
                    alpha: isDark ? 0.58 : 0.62,
                  ),
                  endColor: neutral,
                  arrow: false,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.3,
                  color: AppColors.textMuted,
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 40,
              height: 12,
              child: CustomPaint(
                painter: _BridgePainter(
                  startColor: neutral,
                  endColor: to.color.withValues(
                    alpha: isDark ? 0.68 : 0.72,
                  ),
                  arrow: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            to.buildIcon(context, size: 15),
          ],
        ),
      ),
    );
  }
}

/// Thin dashed gradient bridge segment, with an optional arrowhead at its end.
class _BridgePainter extends CustomPainter {
  const _BridgePainter({
    required this.startColor,
    required this.endColor,
    required this.arrow,
  });

  final Color startColor;
  final Color endColor;
  final bool arrow;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    const startX = 0.0;
    final endX = arrow ? size.width - 1.5 : size.width;
    final lineEndX = arrow ? endX - 1.5 : endX;

    final rect = Rect.fromLTRB(startX, y - 1, endX, y + 1);
    final shader = LinearGradient(
      colors: [startColor, endColor],
    ).createShader(rect);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15
      ..strokeCap = StrokeCap.round
      ..shader = shader;

    const dash = 3.0;
    const gap = 3.0;
    var x = startX;
    while (x < lineEndX) {
      final next = (x + dash).clamp(startX, lineEndX);
      canvas.drawLine(Offset(x, y), Offset(next, y), paint);
      x += dash + gap;
    }

    if (arrow) {
      final chevron = Path()
        ..moveTo(endX - 4.0, y - 3.2)
        ..lineTo(endX, y)
        ..lineTo(endX - 4.0, y + 3.2);
      canvas.drawPath(
        chevron,
        Paint()
          ..color = endColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(_BridgePainter old) =>
      old.startColor != startColor ||
      old.endColor != endColor ||
      old.arrow != arrow;
}
