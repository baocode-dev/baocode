import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../workspace/window_controls.dart';
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
          Listener(
            onPointerDown: (_) => ImagePressScope._press(context),
            child: GestureDetector(
              onTap: () => showImagePreview(context, image),
              child: IdeHover(
                message: image.name ?? '',
                child: Container(
                  width: size,
                  height: size,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  // Over the picture, which is clipped to the same corners:
                  // under it, the picture's corners would cover its curve.
                  foregroundDecoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: hovered
                          ? AppColors.textFaint
                          : AppColors.borderStrong,
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
                      color: AppColors.textFaint,
                    ),
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
                    color: AppColors.surfaceRaised,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.borderStrong),
                  ),
                  child: Icon(
                    Icons.close_rounded,
                    size: 11,
                    color: AppColors.text,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Shows [image] whole, over the window. A click closes it; a right click
/// offers to copy it, as do ⌘C and Ctrl+C.
void showImagePreview(BuildContext context, ImageAttachment image) {
  showDialog<void>(
    context: context,
    // Black, not the theme's: as upstream's modal backdrops.
    barrierColor: Colors.black87,
    builder: (context) => _ImagePreview(image: image),
  );
}

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.image});

  final ImageAttachment image;

  void _copy() => WindowControls.writePasteboardImage(image);

  Future<void> _showMenu(BuildContext context, Offset position) async {
    final chosen = await WindowControls.showContextMenu(position, [
      NativeMenuItem('copyImage', context.l10n.imageCopy, key: 'c'),
    ]);
    if (chosen == 'copyImage') _copy();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyC, meta: true): _copy,
        const SingleActivator(LogicalKeyboardKey.keyC, control: true): _copy,
      },
      child: Focus(
        autofocus: true,
        child: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Center(
              child: InteractiveViewer(
                maxScale: 6,
                child: GestureDetector(
                  onSecondaryTapUp: (details) =>
                      _showMenu(context, details.globalPosition),
                  child: Image.memory(image.bytes, fit: BoxFit.contain),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// [child], which a click shows [image] whole from (see [showImagePreview]).
/// Hears the click itself rather than through a gesture, so a selection of
/// the text around it (in an editor, a message) goes on as it would.
class ImagePreviewClick extends StatefulWidget {
  const ImagePreviewClick({
    super.key,
    required this.image,
    required this.child,
  });

  final ImageAttachment image;
  final Widget child;

  @override
  State<ImagePreviewClick> createState() => _ImagePreviewClickState();
}

class _ImagePreviewClickState extends State<ImagePreviewClick> {
  /// Where a primary press went down; null for other presses.
  Offset? _pressedAt;

  void _handleDown(PointerDownEvent event) {
    final primary =
        event.kind != PointerDeviceKind.mouse ||
        event.buttons == kPrimaryMouseButton;
    // Shift extends a selection.
    if (!primary || HardwareKeyboard.instance.isShiftPressed) return;
    _pressedAt = event.position;
    ImagePressScope._press(context);
  }

  void _handleUp(PointerUpEvent event) {
    final pressedAt = _pressedAt;
    _pressedAt = null;
    // A click, not the end of a drag selection.
    if (pressedAt == null ||
        (event.position - pressedAt).distance > kTouchSlop) {
      return;
    }
    showImagePreview(context, widget.image);
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: Listener(
      onPointerDown: _handleDown,
      onPointerUp: _handleUp,
      onPointerCancel: (_) => _pressedAt = null,
      child: widget.child,
    ),
  );
}

/// Tells what is around images a press on one of them (which opens its
/// preview) from a press on the rest of it: [onPress] hears it first.
class ImagePressScope extends InheritedWidget {
  const ImagePressScope({
    super.key,
    required this.onPress,
    required super.child,
  });

  final VoidCallback onPress;

  static void _press(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ImagePressScope>()?.onPress();

  @override
  bool updateShouldNotify(ImagePressScope oldWidget) => false;
}
