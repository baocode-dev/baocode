import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../base/step_clock.dart';
import '../../theme/app_theme.dart';
import '../chat_models.dart';
import '../side_panel/file_link.dart';
import '../side_panel/file_link_menu.dart';
import '../side_panel/file_open.dart';
import 'hover_builder.dart';
import 'image_thumbnails.dart';
import 'step_header.dart' show StepHeader;

/// How wide a picture in the chat's content shows at most; as tall as that
/// makes it.
const contentImageMaxWidth = 480.0;

/// A picture in the chat's content (what a tool returned, an image in a
/// message), as big as it is up to [contentImageMaxWidth] wide: a click
/// shows it whole ([onOpen]), a right click offers [menu]. Its place is
/// kept from the start, as its header tells its size (see
/// [imagePixelSize]), an [ImageShimmer] in it until it is decoded.
class ContentImage extends StatelessWidget {
  const ContentImage({
    super.key,
    required this.image,
    required this.onOpen,
    required this.menu,
  });

  final ImageAttachment image;
  final VoidCallback onOpen;
  final ChatItemMenu menu;

  @override
  Widget build(BuildContext context) {
    final size = imagePixelSize(image.bytes);
    return FileLinkMenuRegion(
      menu: menu,
      // A click, not a drag selecting the text around it.
      child: PreviewClick(
        onOpen: onOpen,
        child: HoverBuilder(
          builder: (context, hovered) => _ImageBox(
            size: size,
            hovered: hovered,
            child: Image.memory(
              image.bytes,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              // Decoded as big as it shows, not as it is (a screenshot's
              // millions of pixels).
              cacheWidth: switch (size?.width) {
                final width? when width > _decodedWidth(context) =>
                  _decodedWidth(context).round(),
                _ => null,
              },
              frameBuilder: (context, child, frame, synchronous) {
                // Already decoded (shown before): at once.
                if (synchronous) return child;
                // Of a size it could not tell: in its own once there.
                if (size == null) return frame == null ? _placeholder : child;
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  layoutBuilder: (current, previous) => Stack(
                    fit: StackFit.expand,
                    children: [...previous, ?current],
                  ),
                  child: frame == null ? const ImageShimmer() : child,
                );
              },
              errorBuilder: (context, error, stack) => size == null
                  ? _broken()
                  : ColoredBox(color: AppColors.code, child: _broken()),
            ),
          ),
        ),
      ),
    );
  }
}

/// The most pixels across a picture of the content is decoded to.
double _decodedWidth(BuildContext context) =>
    contentImageMaxWidth * MediaQuery.devicePixelRatioOf(context);

/// Pictures (a screenshot) small after a line while what they are in is
/// closed: what it opens to, at a glance; the first [max] of them, a count
/// of the rest. They go as it opens ([shown] false), where the pictures
/// come whole, and the space before them with them: a [StepHeader]'s
/// `trailingGap` is none for them. With [onOpen], a click on one shows it
/// whole (by its index), not the line's: a [StepHeader]'s click heeds it
/// (see [PreviewPressScope]).
class StepThumbnails extends StatelessWidget {
  const StepThumbnails({
    super.key,
    required this.images,
    this.shown = true,
    this.max = 1,
    this.onOpen,
  });

  final List<ChatImage> images;
  final bool shown;
  final int max;
  final ValueChanged<int>? onOpen;

  static const width = 32.0;
  static const height = 18.0;

  /// Between them and the line before them.
  static const gap = 6.0;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 150),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => SizeTransition(
        axis: Axis.horizontal,
        alignment: AlignmentDirectional.centerStart,
        sizeFactor: animation,
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: shown && images.isNotEmpty
          ? _row(context)
          : const SizedBox(key: ValueKey('none'), height: height),
    );
  }

  Widget _row(BuildContext context) {
    final rest = images.length - max;
    return Padding(
      key: const ValueKey('thumbnails'),
      padding: const EdgeInsetsDirectional.only(start: gap),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, (:image, :file)) in images.take(max).indexed) ...[
            if (i > 0) const SizedBox(width: 3),
            _thumbnail(context, i, image, file),
          ],
          if (rest > 0) ...[
            const SizedBox(width: 4),
            Text(
              '+$rest',
              style: TextStyle(color: AppColors.textFaint, fontSize: 11.5),
            ),
          ],
        ],
      ),
    );
  }

  Widget _thumbnail(
    BuildContext context,
    int index,
    ImageAttachment image,
    String? file,
  ) {
    final radius = BorderRadius.circular(4);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    // Decoded as small as it shows, by its shorter side as it fills.
    final wide = switch (imagePixelSize(image.bytes)) {
      final size? => size.width / size.height > width / height,
      null => true,
    };
    Widget thumbnail(bool hovered) => Container(
      width: width,
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: AppColors.code, borderRadius: radius),
      foregroundDecoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(
          color: hovered ? AppColors.borderStrong : AppColors.partBorder,
        ),
      ),
      child: Image.memory(
        image.bytes,
        fit: BoxFit.cover,
        cacheWidth: wide ? null : (width * dpr).round(),
        cacheHeight: wide ? (height * dpr).round() : null,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        errorBuilder: (context, error, stack) => const SizedBox.shrink(),
      ),
    );
    final open = onOpen;
    return FileLinkMenuRegion(
      menu: imageMenu(context, image, file),
      child: open == null
          ? thumbnail(false)
          : PreviewClick(
              onOpen: () => open(index),
              child: HoverBuilder(
                builder: (context, hovered) => thumbnail(hovered),
              ),
            ),
    );
  }
}

/// A picture a tool returned, with the [file] it was saved to (the file
/// read, the CLI's copy) where that is known.
typedef ChatImage = ({ImageAttachment image, String? file});

/// [images], each with its file of [files] (one each, or none known).
List<ChatImage> chatImagesOf(
  List<ImageAttachment> images,
  List<String> files,
) => [
  for (final (i, image) in images.indexed)
    (image: image, file: files.length == images.length ? files[i] : null),
];

/// The pictures [item] returned, but for a failed one's.
List<ChatImage> toolImages(ToolCallItem item) =>
    item.status == ToolStatus.failed
    ? const []
    : chatImagesOf(
        item.images,
        imageFilesOf(item.kind, item.path, item.imageFiles),
      );

/// The files a tool call's pictures are: the one read, or the CLI's copies.
List<String> imageFilesOf(ToolKind kind, String? path, List<String> saved) =>
    kind == ToolKind.read && path != null ? [path] : saved;

/// What a right click on [image] offers: its [file]'s menu where the
/// chat's files open and it is one of theirs (to open it in the side
/// panel, in the IDE, to copy its path), else the picture's own.
ChatItemMenu imageMenu(
  BuildContext context,
  ImageAttachment image,
  String? file, {
  bool previewing = false,
}) {
  final files = FileOpenScope.maybeOf(context);
  final path = file == null ? null : files?.resolve(file);
  if (files == null || path == null) return ImageMenu(image);
  return files.menuFor(
    path,
    () => files.onOpen(FileOpenRequest(path)),
    context: context,
    previewing: previewing,
  );
}

/// Every picture the chat's tools returned, in order, for one shown whole
/// to go on to the others (see [showChatImages]): read when asked.
class ChatImages extends InheritedWidget {
  const ChatImages({super.key, required this.all, required super.child});

  final List<ChatImage> Function() all;

  static List<ChatImage> Function()? _of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ChatImages>()?.all;

  @override
  bool updateShouldNotify(ChatImages oldWidget) => false;
}

/// Shows the [index]th of [images] whole: ← and → go through all the
/// chat's (see [ChatImages]), else [images]; a right click offers each
/// one's file's menu.
void showChatImages(BuildContext context, List<ChatImage> images, int index) {
  final shown = images[index].image;
  final all = ChatImages._of(context)?.call() ?? const [];
  final at = all.indexWhere((entry) => identical(entry.image, shown));
  final (list, start) = at < 0 ? (images, index) : (all, at);
  showImageGallery(
    context,
    count: list.length,
    index: start,
    load: (i) => SynchronousFuture(list[i].image),
    // The file's; the gallery's own for a picture of none.
    menu: (i) => switch (list[i]) {
      (:final image, :final file?) => switch (imageMenu(
        context,
        image,
        file,
        previewing: true,
      )) {
        final FileLinkMenu menu => menu,
        _ => null,
      },
      _ => null,
    },
  );
}

/// Where a picture of a size not known yet shows (an image file still
/// being read): a 16:9 one's, as wide as they may be.
const contentImagePlaceholder = _ImageBox(child: ImageShimmer());

/// Where a picture yet to be made shows, a light sweeping across it: as
/// big as one of [aspectRatio] (width over height) shows once it is there,
/// as wide as they may be.
class ContentImagePlaceholder extends StatelessWidget {
  const ContentImagePlaceholder({super.key, this.aspectRatio = 1});

  final double aspectRatio;

  @override
  Widget build(BuildContext context) => _ImageBox(
    size: Size(contentImageMaxWidth, contentImageMaxWidth / aspectRatio),
    child: const ImageShimmer(startAfter: Duration.zero),
  );
}

const _placeholder = SizedBox(
  width: contentImageMaxWidth,
  child: AspectRatio(aspectRatio: 16 / 9, child: ImageShimmer()),
);

/// [child] framed as a picture of the content is: its corners rounded, a
/// line around. [size] (in pixels) is the picture's, kept from the start
/// down to [contentImageMaxWidth]; a 16:9 one's when null.
class _ImageBox extends StatelessWidget {
  const _ImageBox({this.size, this.hovered = false, required this.child});

  final Size? size;
  final bool hovered;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(8);
    final size = this.size;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: contentImageMaxWidth),
      child: SizedBox(
        width: size?.width ?? contentImageMaxWidth,
        child: AspectRatio(
          aspectRatio: size == null ? 16 / 9 : size.width / size.height,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(borderRadius: radius),
            // Over the picture, clipped to the same corners.
            foregroundDecoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: hovered ? AppColors.borderStrong : AppColors.partBorder,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

Widget _broken() => Center(
  child: Padding(
    padding: const EdgeInsets.all(8),
    child: Icon(
      Icons.broken_image_outlined,
      size: 16,
      color: AppColors.textFaint,
    ),
  ),
);

/// The place of a picture yet to show, as big as it is given: still at
/// first, so one quick to come only shows; past [startAfter], a skeleton's
/// wave: a soft band of light going across it, left to right, over and
/// over.
class ImageShimmer extends StatefulWidget {
  const ImageShimmer({super.key, this.startAfter = delay});

  static const delay = Duration(milliseconds: 200);

  /// Still until then: [delay], none for one known to take long (a
  /// picture being made).
  final Duration startAfter;

  /// One sweep.
  static const period = Duration(milliseconds: 1600);

  @override
  State<ImageShimmer> createState() => _ImageShimmerState();
}

class _ImageShimmerState extends State<ImageShimmer> {
  // A step each of the shared clock's frames, not every vsync: a band of
  // light that smooth is all it needs.
  final StepClock _clock = StepClock(StepClock.frame);
  late final Timer _start;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _start = Timer(widget.startAfter, () {
      _started = true;
      _clock.keepTo(context);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) _clock.keepTo(context);
  }

  @override
  void dispose() {
    _start.cancel();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = AppColors.code;
    // Lighter than what it is on, in either theme: as skeletons are.
    final dark = Theme.of(context).brightness == Brightness.dark;
    final light = Color.alphaBlend(
      Colors.white.withValues(alpha: dark ? .07 : .6),
      base,
    );
    return ColoredBox(
      color: base,
      child: AnimatedBuilder(
        animation: _clock,
        builder: (context, _) {
          if (!_clock.isRunning) return const SizedBox.expand();
          final period = ImageShimmer.period.inMicroseconds;
          final swept = _clock.time.inMicroseconds % period / period;
          return SizedBox.expand(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: const Alignment(-1, -.3),
                  end: const Alignment(1, .3),
                  colors: [
                    base.withValues(alpha: 0),
                    light,
                    base.withValues(alpha: 0),
                  ],
                  stops: const [.3, .5, .7],
                  // From wholly before it to wholly past it.
                  transform: _Sliding(swept * 2 - 1),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A gradient moved across by [fraction] of its box's width.
class _Sliding extends GradientTransform {
  const _Sliding(this.fraction);

  final double fraction;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * fraction, 0, 0);
}

/// The size in pixels of the picture in [bytes], as its header says
/// (PNG, JPEG, GIF, WebP, BMP), turned as a JPEG's orientation turns it;
/// null for another kind, or a header it cannot read.
Size? imagePixelSize(Uint8List bytes) =>
    (_sizes[bytes] ??= (_pixelSize(bytes),)).$1;

/// Each picture's size, read once.
final _sizes = Expando<(Size?,)>();

Size? _pixelSize(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  bool at(int offset, List<int> signature) {
    if (bytes.length < offset + signature.length) return false;
    for (final (i, byte) in signature.indexed) {
      if (bytes[offset + i] != byte) return false;
    }
    return true;
  }

  Size? size(int width, int height) => width > 0 && height > 0
      ? Size(width.toDouble(), height.toDouble())
      : null;
  try {
    if (at(0, const [0x89, 0x50, 0x4E, 0x47])) {
      return size(data.getUint32(16), data.getUint32(20));
    }
    if (at(0, 'GIF8'.codeUnits)) {
      return size(
        data.getUint16(6, Endian.little),
        data.getUint16(8, Endian.little),
      );
    }
    if (at(0, 'BM'.codeUnits)) {
      // Drawn from the top when its height is negative.
      return size(
        data.getInt32(18, Endian.little),
        data.getInt32(22, Endian.little).abs(),
      );
    }
    if (at(0, 'RIFF'.codeUnits) && at(8, 'WEBP'.codeUnits)) {
      int u24(int offset) =>
          bytes[offset] | bytes[offset + 1] << 8 | bytes[offset + 2] << 16;
      return switch (String.fromCharCodes(bytes, 12, 16)) {
        'VP8 ' => size(
          data.getUint16(26, Endian.little) & 0x3FFF,
          data.getUint16(28, Endian.little) & 0x3FFF,
        ),
        'VP8L' => switch (data.getUint32(21, Endian.little)) {
          final bits => size((bits & 0x3FFF) + 1, (bits >> 14 & 0x3FFF) + 1),
        },
        'VP8X' => size(u24(24) + 1, u24(27) + 1),
        _ => null,
      };
    }
    if (at(0, const [0xFF, 0xD8])) return _jpegSize(bytes, data);
  } on RangeError {
    return null;
  }
  return null;
}

/// A JPEG's size, from its frame's header (SOFn), turned a quarter when
/// its EXIF orientation (5 to 8) turns it.
Size? _jpegSize(Uint8List bytes, ByteData data) {
  var turned = false;
  var i = 2;
  while (i + 9 < bytes.length) {
    if (bytes[i] != 0xFF) return null;
    final marker = bytes[i + 1];
    // Filling.
    if (marker == 0xFF) {
      i++;
      continue;
    }
    // Markers with no length.
    if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD9)) {
      i += 2;
      continue;
    }
    final length = data.getUint16(i + 2);
    if (marker == 0xE1) turned = _exifTurned(data, i + 4, length - 2);
    if (marker >= 0xC0 &&
        marker <= 0xCF &&
        marker != 0xC4 &&
        marker != 0xC8 &&
        marker != 0xCC) {
      final height = data.getUint16(i + 5);
      final width = data.getUint16(i + 7);
      if (width == 0 || height == 0) return null;
      return turned
          ? Size(height.toDouble(), width.toDouble())
          : Size(width.toDouble(), height.toDouble());
    }
    i += 2 + length;
  }
  return null;
}

/// Whether the EXIF of an APP1 segment ([length] bytes at [start]) has the
/// picture turned a quarter (orientation 5 to 8).
bool _exifTurned(ByteData data, int start, int length) {
  // `Exif\0\0`, then a TIFF header.
  if (length < 14 || data.getUint32(start) != 0x45786966) return false;
  final tiff = start + 6;
  final endian = switch (data.getUint16(tiff)) {
    0x4949 => Endian.little,
    0x4D4D => Endian.big,
    _ => null,
  };
  if (endian == null) return false;
  final ifd = tiff + data.getUint32(tiff + 4, endian);
  final count = data.getUint16(ifd, endian);
  for (var entry = 0; entry < count; entry++) {
    final at = ifd + 2 + entry * 12;
    if (data.getUint16(at, endian) == 0x0112) {
      return data.getUint16(at + 8, endian) >= 5;
    }
  }
  return false;
}

/// What a tool returned as pictures (a screenshot, an image file read),
/// one under the other; a click shows one whole, the arrows going on to
/// the chat's others (see [showChatImages]), a right click offers its
/// file's menu.
class ToolImages extends StatelessWidget {
  const ToolImages({super.key, required this.images});

  final List<ChatImage> images;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, (:image, :file)) in images.indexed) ...[
            if (i > 0) const SizedBox(height: 6),
            ContentImage(
              key: ObjectKey(image),
              image: image,
              onOpen: () => showChatImages(context, images, i),
              menu: imageMenu(context, image, file),
            ),
          ],
        ],
      ),
    );
  }
}

/// The image file a message's markdown shows (`![alt](src)`): the path of
/// [src] on the project's host, or null for one it does not read (a web
/// address: the agent's text could have one tell a server what it read).
String? markdownImagePath(String src, FileOpenScope files) {
  final link = FileLink.parseHref(src);
  if (link == null || link.range != null) return null;
  // In the project, or one the agent saw (a screenshot saved, say).
  final path = files.resolve(link.path);
  if (path == null || !files.showsImage(path)) return null;
  return path;
}

/// An image file in a message's markdown, read as it shows; a click shows
/// it whole, the arrows going to the others of [gallery] (the message's,
/// in order), a right click offers the file's menu. Its [alt] text in
/// brackets where it cannot be read.
class MarkdownImage extends StatefulWidget {
  const MarkdownImage({
    super.key,
    required this.path,
    required this.alt,
    required this.files,
    this.gallery = const [],
  });

  final String path;
  final String alt;
  final FileOpenScope files;
  final List<String> gallery;

  /// The images read lately, by where they are read from (a project's
  /// host) and path: the history builds its rows anew as they scroll into
  /// view.
  static final _read = <(Object?, String), _Read>{};

  /// Past this an image is not read to be shown in a message.
  static const _maxBytes = 20 << 20;

  static _Read _readOf(FileOpenScope files, String path) {
    final key = (files.readBytes, path);
    if (_read.remove(key) case final read?) return _read[key] = read;
    if (_read.length >= 24) _read.remove(_read.keys.first);
    return _read[key] = _Read(files.image(path, maxBytes: _maxBytes));
  }

  @override
  State<MarkdownImage> createState() => _MarkdownImageState();
}

class _MarkdownImageState extends State<MarkdownImage> {
  late _Read _image = MarkdownImage._readOf(widget.files, widget.path);

  @override
  void didUpdateWidget(MarkdownImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.path != oldWidget.path ||
        widget.files.readBytes != oldWidget.files.readBytes) {
      _image = MarkdownImage._readOf(widget.files, widget.path);
    }
  }

  ChatItemMenu _menu(String path, {bool previewing = false}) {
    final files = widget.files;
    return files.menuFor(
      path,
      () => files.onOpen(FileOpenRequest(path)),
      context: context,
      previewing: previewing,
    );
  }

  void _open() {
    final files = widget.files;
    final gallery = widget.gallery.contains(widget.path)
        ? widget.gallery
        : [widget.path];
    showImageGallery(
      context,
      count: gallery.length,
      index: gallery.indexOf(widget.path),
      load: (i) => MarkdownImage._readOf(files, gallery[i]).future,
      menu: (i) => _menu(gallery[i], previewing: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _image.future,
      // Read before: as it was, not its placeholder for a frame.
      initialData: _image.image,
      builder: (context, snapshot) {
        if (snapshot.data case final image?) {
          return ContentImage(
            image: image,
            onOpen: _open,
            menu: _menu(widget.path),
          );
        }
        if (snapshot.connectionState != ConnectionState.done && !_image.done) {
          return contentImagePlaceholder;
        }
        final name = (widget.files.paths ?? p.context).basename(widget.path);
        return Text(
          '[${widget.alt.isEmpty ? name : widget.alt}]',
          style: TextStyle(color: AppColors.textMuted),
        );
      },
    );
  }
}

/// An image file being read, or read: [image] once it is (null where it
/// could not be).
class _Read {
  _Read(this.future) {
    future.then(
      (image) {
        this.image = image;
        done = true;
      },
      onError: (Object _) {
        done = true;
      },
    );
  }

  final Future<ImageAttachment?> future;
  ImageAttachment? image;
  bool done = false;
}
