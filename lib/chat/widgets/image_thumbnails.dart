import 'package:flutter/material.dart';

import '../../theme/cursor_theme.dart';
import '../chat_models.dart';
import 'hover_builder.dart';
import '../../ide/ide_hover.dart';

/// Pictures attached to a message, small; a click shows one whole. With
/// [onRemove], each has a button to take it off (as in the composer).
/// One size in a message and in its editor, so editing does not resize
/// them.
class ImageThumbnails extends StatelessWidget {
  const ImageThumbnails({
    super.key,
    required this.images,
    this.onRemove,
    this.size = 48,
  });

  final List<ImageAttachment> images;
  final ValueChanged<int>? onRemove;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final (i, image) in images.indexed)
          _Thumbnail(
            // A new image at this position is a new thumbnail.
            key: ObjectKey(image),
            image: image,
            size: size,
            onRemove: onRemove == null ? null : () => onRemove!(i),
          ),
      ],
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({
    super.key,
    required this.image,
    required this.size,
    this.onRemove,
  });

  final ImageAttachment image;
  final double size;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return HoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (context, hovered) => Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            onTap: () => _preview(context),
            child: IdeHover(
              message: image.name ?? '',
              child: Container(
                width: size,
                height: size,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: CursorColors.surface,
                  borderRadius: BorderRadius.circular(6),
                ),
                // Over the picture, which is clipped to the same corners:
                // under it, the picture's corners would cover its curve.
                foregroundDecoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: hovered
                        ? CursorColors.textFaint
                        : CursorColors.borderStrong,
                  ),
                ),
                child: Image.memory(
                  image.bytes,
                  fit: BoxFit.cover,
                  cacheWidth: (size * 3).round(),
                  gaplessPlayback: true,
                  errorBuilder: (context, error, stack) => Icon(
                    Icons.broken_image_outlined,
                    size: 16,
                    color: CursorColors.textFaint,
                  ),
                ),
              ),
            ),
          ),
          if (onRemove case final remove? when hovered)
            Positioned(
              top: -5,
              right: -5,
              child: GestureDetector(
                onTap: remove,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: CursorColors.surfaceRaised,
                    shape: BoxShape.circle,
                    border: Border.all(color: CursorColors.borderStrong),
                  ),
                  child: Icon(
                    Icons.close_rounded,
                    size: 11,
                    color: CursorColors.text,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _preview(BuildContext context) {
    showDialog<void>(
      context: context,
      // Black, not the theme's: as upstream's modal backdrops.
      barrierColor: Colors.black87,
      builder: (context) => GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Center(
            child: InteractiveViewer(
              maxScale: 6,
              child: Image.memory(image.bytes, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }
}
