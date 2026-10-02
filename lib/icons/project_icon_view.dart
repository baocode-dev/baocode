import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/workbench_theme.dart' show themeColors;
import 'emoji_sheet.dart';
import 'icon_library.dart';
import 'project_icon.dart';

/// A project's [icon] in a square of [size]: [fallback] (its folder) when
/// it has none, its picture is no longer in [library], or it is an emoji
/// and the [EmojiSheet] is not there yet.
///
/// None fills the square: a picture takes the most of it, an emoji less,
/// a glyph least, so that all three look about as large.
class ProjectIconView extends StatelessWidget {
  const ProjectIconView({
    super.key,
    required this.icon,
    required this.library,
    required this.size,
    this.color,
    this.fallback = Icons.folder_outlined,
  });

  /// How much of the square a picture takes.
  static const imageScale = 0.9;

  /// How much of the square an emoji takes.
  static const emojiScale = 0.8;

  /// How much of the square a glyph (a codicon, the folder) takes.
  static const glyphScale = 0.65;

  final ProjectIcon? icon;
  final IconLibrary library;
  final double size;

  /// The color of [fallback], and of a codicon without its own.
  final Color? color;
  final IconData fallback;

  @override
  Widget build(BuildContext context) {
    final folder = Icon(fallback, size: size * glyphScale, color: color);
    return SizedBox.square(
      dimension: size,
      child: Center(
        child: switch (icon) {
          null => folder,
          EmojiIcon(:final emoji) => _EmojiOr(
            emoji,
            size: size * emojiScale,
            otherwise: folder,
          ),
          CodiconIcon(icon: final glyph, color: final id) => Icon(
            glyph,
            size: size * glyphScale,
            color: id == null ? color : themeColors.get(id) ?? color,
          ),
          LibraryIcon(:final id) => switch (library[id]) {
            final image? => IconImageView(image, size: size * imageScale),
            null => folder,
          },
        },
      ),
    );
  }
}

/// [emoji], or [otherwise] while the [EmojiSheet] is not there (or has no
/// picture of it).
class _EmojiOr extends StatelessWidget {
  const _EmojiOr(this.emoji, {required this.size, required this.otherwise});

  final String emoji;
  final double size;
  final Widget otherwise;

  @override
  Widget build(BuildContext context) {
    unawaited(EmojiSheet.request());
    return ValueListenableBuilder(
      valueListenable: EmojiSheet.loaded,
      builder: (context, sheet, _) => sheet?.cell(emoji) == null
          ? otherwise
          : EmojiGlyph(emoji, size: size),
    );
  }
}

/// [emoji] filling a square of [size]: its picture on the [EmojiSheet],
/// the same on every system. Nothing until the sheet is there, or for an
/// emoji it has no picture of: never in the system's font.
class EmojiGlyph extends StatelessWidget {
  const EmojiGlyph(this.emoji, {super.key, required this.size});

  final String emoji;
  final double size;

  @override
  Widget build(BuildContext context) {
    unawaited(EmojiSheet.request());
    return ValueListenableBuilder(
      valueListenable: EmojiSheet.loaded,
      builder: (context, sheet, _) => switch (sheet?.cell(emoji)) {
        final cell? => CustomPaint(
          size: Size.square(size),
          painter: _SheetPainter(sheet!.image, cell),
        ),
        null => SizedBox.square(dimension: size),
      },
    );
  }
}

class _SheetPainter extends CustomPainter {
  _SheetPainter(this.image, this.cell);

  final ui.Image image;
  final Rect cell;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawImageRect(
    image,
    cell,
    Offset.zero & size,
    Paint()..filterQuality = FilterQuality.medium,
  );

  @override
  bool shouldRepaint(_SheetPainter old) =>
      old.image != image || old.cell != cell;
}

/// [image] in a square of [size]: decoded at the size it shows (a GIF
/// animates), with rounded corners.
class IconImageView extends StatelessWidget {
  const IconImageView(this.image, {super.key, required this.size});

  final IconImage image;
  final double size;

  @override
  Widget build(BuildContext context) {
    final broken = Icon(
      Icons.broken_image_outlined,
      size: size,
      color: themeColors['descriptionForeground'],
    );
    if (image.kind == IconImageKind.svg) {
      return SvgPicture.memory(
        image.bytes,
        width: size,
        height: size,
        errorBuilder: (_, _, _) => broken,
      );
    }
    final pixels = (size * MediaQuery.devicePixelRatioOf(context)).ceil();
    // A PNG is square; a GIF fits twice the size, so that its shorter side
    // still covers it unless it is very long.
    final png = image.kind == IconImageKind.png;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.18),
      child: Image(
        image: ResizeImage(
          MemoryImage(image.bytes),
          width: png ? pixels : pixels * 2,
          height: png ? pixels : pixels * 2,
          policy: ResizeImagePolicy.fit,
        ),
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) => broken,
      ),
    );
  }
}
