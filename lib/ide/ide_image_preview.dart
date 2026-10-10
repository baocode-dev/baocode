/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The editor of an image: VS Code's image preview.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// extensions/media-preview (src/imagePreview, media/imagePreview.css).
//
// Deviations: zooming is the wheel's or the trackpad's pinch (no click to
// zoom, no zoom status bar entry), and the size shows in the preview's
// corner rather than the status bar.

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path/path.dart' as p;

import '../platform/svg_text_transform.dart';
import '../theme/workbench_theme.dart' show themeColors;
import 'file_service.dart';
import 'ide_editor_placeholder.dart';

/// [path]'s image, centered at its own size or scaled down to fit, on a
/// checkerboard where it is transparent; the wheel or a pinch zooms it and
/// dragging pans it.
class IdeImagePreview extends StatefulWidget {
  const IdeImagePreview({
    super.key,
    required this.path,
    this.read,
    this.onOpenInDefaultApp,
  });

  final String path;

  /// Offered when the image cannot be shown.
  final VoidCallback? onOpenInDefaultApp;

  /// Reads the file; [readFileBytes] when null.
  final Future<Uint8List> Function(String path)? read;

  @override
  State<IdeImagePreview> createState() => _IdeImagePreviewState();
}

class _IdeImagePreviewState extends State<IdeImagePreview> {
  final TransformationController _transform = TransformationController();
  _Loaded? _loaded;
  Object? _error;
  int _load = 0;

  bool get _svg => p.extension(widget.path).toLowerCase() == '.svg';

  @override
  void initState() {
    super.initState();
    unawaited(_read());
  }

  @override
  void didUpdateWidget(IdeImagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) unawaited(_read());
  }

  @override
  void dispose() {
    _load++;
    _transform.dispose();
    super.dispose();
  }

  Future<void> _read() async {
    final load = ++_load;
    setState(() {
      _loaded = null;
      _error = null;
    });
    try {
      final bytes = await (widget.read ?? readFileBytes)(widget.path);
      final size = _svg ? null : await _imageSize(bytes);
      if (!mounted || load != _load) return;
      _transform.value = Matrix4.identity();
      setState(() => _loaded = _Loaded(bytes, size));
    } catch (error) {
      if (!mounted || load != _load) return;
      setState(() => _error = error);
    }
  }

  /// The image's size in pixels, read from its header without decoding it.
  static Future<Size> _imageSize(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final size = Size(
        descriptor.width.toDouble(),
        descriptor.height.toDouble(),
      );
      descriptor.dispose();
      return size;
    } finally {
      buffer.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error case final error?) {
      return IdeEditorPlaceholder(
        error: error,
        onOpenAnyway: () => unawaited(_read()),
        onRetry: () => unawaited(_read()),
        onOpenInDefaultApp: widget.onOpenInDefaultApp,
      );
    }
    final loaded = _loaded;
    if (loaded == null) return const SizedBox.expand();
    final dark = themeColors.dark;
    return ColoredBox(
      color: themeColors['editor.background'],
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewport = constraints.biggest;
          final Widget image;
          if (loaded.size case final size?) {
            // `.container.image img.scale-to-fit`: its own size, unless
            // that is larger than the editor.
            final fitted = applyBoxFit(
              BoxFit.scaleDown,
              size,
              viewport,
            ).destination;
            image = RepaintBoundary(
              child: SizedBox.fromSize(
                size: fitted,
                child: CustomPaint(
                  painter: _CheckerboardPainter(dark: dark),
                  child: Image.memory(
                    loaded.bytes,
                    width: fitted.width,
                    height: fitted.height,
                    fit: BoxFit.fill,
                    gaplessPlayback: true,
                    // Pixels stay sharp when zoomed in on a small image.
                    filterQuality: fitted.width < size.width
                        ? FilterQuality.medium
                        : FilterQuality.none,
                    errorBuilder: (context, error, _) => IdeEditorPlaceholder(
                      error: error,
                      onOpenAnyway: () => unawaited(_read()),
                      onRetry: () => unawaited(_read()),
                      onOpenInDefaultApp: widget.onOpenInDefaultApp,
                    ),
                  ),
                ),
              ),
            );
          } else {
            image = SvgPicture(
              SvgTextBytesLoader(loaded.bytes),
              width: viewport.width,
              height: viewport.height,
              fit: BoxFit.scaleDown,
              errorBuilder: (context, error, _) => IdeEditorPlaceholder(
                error: error,
                onOpenAnyway: () => unawaited(_read()),
                onRetry: () => unawaited(_read()),
                onOpenInDefaultApp: widget.onOpenInDefaultApp,
              ),
            );
          }
          return Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  transformationController: _transform,
                  minScale: .1,
                  maxScale: 32,
                  boundaryMargin: const EdgeInsets.all(double.infinity),
                  child: SizedBox.fromSize(
                    size: viewport,
                    child: Center(child: image),
                  ),
                ),
              ),
              if (loaded.size case final size?)
                Positioned(
                  right: 8,
                  bottom: 6,
                  child: Text(
                    '${size.width.toInt()}×${size.height.toInt()}  '
                    '${ideFormatSize(loaded.bytes.length)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: themeColors['descriptionForeground'],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Loaded {
  const _Loaded(this.bytes, this.size);

  final Uint8List bytes;

  /// In pixels; null for an SVG.
  final Size? size;
}

/// `.container.image img.transparent`'s background: a checkerboard.
class _CheckerboardPainter extends CustomPainter {
  const _CheckerboardPainter({required this.dark});

  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    const square = 8.0;
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = dark ? const Color(0xff141414) : const Color(0xffffffff),
    );
    final paint = Paint()
      ..color = dark ? const Color(0xff1e1e1e) : const Color(0xffe6e6e6);
    for (var y = 0; y * square < size.height; y++) {
      for (var x = y.isEven ? 0 : 1; x * square < size.width; x += 2) {
        canvas.drawRect(
          Rect.fromLTWH(x * square, y * square, square, square),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerboardPainter oldDelegate) =>
      oldDelegate.dark != dark;
}
