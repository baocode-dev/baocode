import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_svg/svg.dart';
import 'package:path/path.dart' as p;

import 'icon_storage.dart';

/// How an uploaded picture is kept and drawn.
enum IconImageKind {
  /// A PNG, JPEG, WebP or ICO, kept as a square PNG of at most
  /// [IconLibrary.side] pixels.
  png,

  /// Kept as given, animation and all.
  gif,

  /// Kept as given, drawn at any size.
  svg,
}

/// A picture in the [IconLibrary].
@immutable
class IconImage {
  const IconImage({
    required this.id,
    required this.kind,
    required this.name,
    required this.bytes,
    this.luminance,
  });

  /// From the content as uploaded: the same picture uploaded again is the
  /// same one.
  final String id;
  final IconImageKind kind;

  /// The name of the file it came from (without the extension), to search
  /// by; empty for one pasted.
  final String name;

  /// As kept, the same list for as long as it is: drawn from the image
  /// cache after the first time.
  final Uint8List bytes;

  /// The mean brightness of its visible pixels, 0 (black) to 1 (white):
  /// what draws it stands it on a plate picked by this, so a dark mark
  /// (GitHub's) stays visible on a dark surface. Null while not worked out
  /// (a GIF's, or one that could not be read).
  final double? luminance;

  String get file => '$id.${kind.name}';
}

/// Why an upload was not taken.
enum IconUploadError {
  /// Larger than [IconLibrary.maxBytes].
  tooLarge,

  /// Not a PNG, JPEG, WebP, GIF or SVG, or one that cannot be read.
  unsupported,

  /// The file could not be read.
  unreadable,
}

class IconUploadException implements Exception {
  const IconUploadException(this.error);

  final IconUploadError error;

  @override
  String toString() => 'IconUploadException(${error.name})';
}

/// The pictures the user uploaded as icons, shared by all projects, the
/// last uploaded first: in [storage], `<id>.<kind>` each and `index.json`
/// listing them.
class IconLibrary extends ChangeNotifier {
  IconLibrary({IconStorage? storage})
    : storage = storage ?? MemoryIconStorage();

  final IconStorage storage;

  /// The app's, the workspace's; main() sets it. What draws an upstream of
  /// models' picture takes it from here.
  static IconLibrary current = IconLibrary();

  /// The largest file taken.
  static const maxBytes = 5 * 1024 * 1024;

  /// The side of the square a PNG, JPEG or WebP is kept as, at most.
  static const side = 128;

  List<IconImage> get images => List.unmodifiable(_images);
  final List<IconImage> _images = [];

  IconImage? operator [](String id) {
    for (final image in _images) {
      if (image.id == id) return image;
    }
    return null;
  }

  /// Told of each picture removed, by id (the projects that showed it go
  /// back to their folder).
  void Function(String id)? onRemoved;

  /// Reads what was kept: the pictures whose file is there.
  Future<void> load() => _loading ??= _load();
  Future<void>? _loading;

  Future<void> _load() async {
    var workedOut = false;
    for (final entry in await storage.readIndex()) {
      if (entry case {'id': final String id, 'kind': final String kind}
          when !_images.any((image) => image.id == id)) {
        final type = IconImageKind.values.asNameMap()[kind];
        if (type == null) continue;
        final bytes = await storage.read('$id.$kind');
        if (bytes == null) continue;
        var luminance = (entry['luminance'] as num?)?.toDouble();
        // Kept before its brightness was worked out: done once, now.
        if (luminance == null) {
          luminance = switch (type) {
            IconImageKind.png => await _pictureLuminance(bytes),
            IconImageKind.svg => await _svgLuminance(bytes),
            IconImageKind.gif => null,
          };
          if (luminance != null) workedOut = true;
        }
        _images.add(
          IconImage(
            id: id,
            kind: type,
            name: entry['name'] as String? ?? '',
            bytes: bytes,
            luminance: luminance,
          ),
        );
      }
    }
    if (workedOut) _writeIndex();
    notifyListeners();
  }

  /// Uploads the file at [path].
  Future<IconImage> addFile(String path) async {
    final size = await storage.userFileSize(path);
    if (size == null) {
      throw const IconUploadException(IconUploadError.unreadable);
    }
    // Not read at all when too large.
    if (size > maxBytes) {
      throw const IconUploadException(IconUploadError.tooLarge);
    }
    final bytes = await storage.readUserFile(path);
    if (bytes == null) {
      throw const IconUploadException(IconUploadError.unreadable);
    }
    return add(bytes, name: p.basenameWithoutExtension(path));
  }

  /// Uploads [bytes]: the picture as kept, the one there already when it
  /// was uploaded before (to the front again).
  Future<IconImage> add(Uint8List bytes, {String name = ''}) async {
    await load();
    if (bytes.length > maxBytes) {
      throw const IconUploadException(IconUploadError.tooLarge);
    }
    final format = _sniff(bytes);
    if (format == null) {
      throw const IconUploadException(IconUploadError.unsupported);
    }
    final id = sha256.convert(bytes).toString().substring(0, 20);
    if (this[id] case final kept?) {
      _images
        ..remove(kept)
        ..insert(0, kept);
      _writeIndex();
      notifyListeners();
      return kept;
    }
    final kind = switch (format) {
      _Format.gif => IconImageKind.gif,
      _Format.svg => IconImageKind.svg,
      _ => IconImageKind.png,
    };
    final Uint8List kept;
    final double? luminance;
    try {
      if (kind == IconImageKind.png) {
        final square = await _square(bytes);
        kept = square.bytes;
        luminance = square.luminance;
      } else {
        kept = bytes;
        luminance = kind == IconImageKind.svg
            ? await _svgLuminance(bytes)
            : null;
      }
    } on Object {
      throw const IconUploadException(IconUploadError.unsupported);
    }
    final image = IconImage(
      id: id,
      kind: kind,
      name: name,
      bytes: kept,
      luminance: luminance,
    );
    await storage.write(image.file, kept);
    _images.insert(0, image);
    _writeIndex();
    notifyListeners();
    return image;
  }

  /// Takes [id] out of the library, and its file away.
  Future<void> remove(String id) async {
    final image = this[id];
    if (image == null) return;
    _images.remove(image);
    _writeIndex();
    notifyListeners();
    onRemoved?.call(id);
    await storage.delete(image.file);
  }

  void _writeIndex() => unawaited(
    storage.writeIndex([
      for (final image in _images)
        {
          'id': image.id,
          'kind': image.kind.name,
          'name': image.name,
          if (image.luminance != null) 'luminance': image.luminance,
        },
    ]),
  );

  /// What [bytes] are, by how they begin; null for none taken.
  static _Format? _sniff(Uint8List bytes) {
    bool starts(List<int> magic, [int at = 0]) {
      if (bytes.length < at + magic.length) return false;
      for (var i = 0; i < magic.length; i++) {
        if (bytes[at + i] != magic[i]) return false;
      }
      return true;
    }

    if (starts(const [0x89, 0x50, 0x4E, 0x47])) return _Format.png;
    if (starts(const [0xFF, 0xD8, 0xFF])) return _Format.jpeg;
    if (starts(ascii.encode('RIFF')) && starts(ascii.encode('WEBP'), 8)) {
      return _Format.webp;
    }
    if (starts(ascii.encode('GIF8'))) return _Format.gif;
    // A site's favicon.ico: decoded as the others, its largest picture.
    if (starts(const [0, 0, 1, 0])) return _Format.ico;
    // Text with an <svg> element near its start (after an XML declaration,
    // comments, a doctype).
    final head = utf8.decode(
      bytes.sublist(0, math.min(bytes.length, 4096)),
      allowMalformed: true,
    );
    if (RegExp(r'<svg[\s>]').hasMatch(head)) return _Format.svg;
    return null;
  }

  /// [bytes] as a square PNG of at most [side] pixels, the middle of the
  /// picture: decoded at that size, never at its own; and the brightness
  /// of what it shows.
  static Future<({Uint8List bytes, double? luminance})> _square(
    Uint8List bytes,
  ) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final ui.ImageDescriptor descriptor;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
    } finally {
      buffer.dispose();
    }
    try {
      final shorter = math.min(descriptor.width, descriptor.height);
      final square = math.min(side, shorter);
      final scale = square / shorter;
      final codec = await descriptor.instantiateCodec(
        targetWidth: math.max(square, (descriptor.width * scale).round()),
        targetHeight: math.max(square, (descriptor.height * scale).round()),
      );
      final ui.Image decoded;
      try {
        decoded = (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawImageRect(
        decoded,
        Rect.fromCenter(
          center: Offset(decoded.width / 2, decoded.height / 2),
          width: square.toDouble(),
          height: square.toDouble(),
        ),
        Rect.fromLTWH(0, 0, square.toDouble(), square.toDouble()),
        Paint()..filterQuality = FilterQuality.medium,
      );
      decoded.dispose();
      final picture = recorder.endRecording();
      final image = await picture.toImage(square, square);
      picture.dispose();
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final luminance = await _meanLuminance(image);
        return (bytes: data!.buffer.asUint8List(), luminance: luminance);
      } finally {
        image.dispose();
      }
    } finally {
      descriptor.dispose();
    }
  }

  /// The brightness of [bytes] (a picture kept before its brightness was
  /// worked out), decoded small; null when it cannot be read.
  static Future<double?> _pictureLuminance(Uint8List bytes) async {
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final ui.ImageDescriptor descriptor;
      try {
        descriptor = await ui.ImageDescriptor.encoded(buffer);
      } finally {
        buffer.dispose();
      }
      try {
        final longest = math.max(descriptor.width, descriptor.height);
        if (longest == 0) return null;
        final scale = math.min(1.0, 32 / longest);
        final codec = await descriptor.instantiateCodec(
          targetWidth: math.max(1, (descriptor.width * scale).round()),
          targetHeight: math.max(1, (descriptor.height * scale).round()),
        );
        try {
          final image = (await codec.getNextFrame()).image;
          try {
            return await _meanLuminance(image);
          } finally {
            image.dispose();
          }
        } finally {
          codec.dispose();
        }
      } finally {
        descriptor.dispose();
      }
    } on Object {
      return null;
    }
  }

  /// The brightness of [bytes] (an SVG icon) drawn onto a transparent
  /// square; null when it cannot be read or drawn.
  static Future<double?> _svgLuminance(Uint8List bytes) async {
    try {
      final info = await vg.loadPicture(SvgBytesLoader(bytes), null);
      try {
        final size = info.size;
        if (size.isEmpty) return null;
        const side = 32.0;
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        final scale = math.min(side / size.width, side / size.height);
        canvas
          ..translate(
            (side - size.width * scale) / 2,
            (side - size.height * scale) / 2,
          )
          ..scale(scale)
          ..drawPicture(info.picture);
        final picture = recorder.endRecording();
        try {
          final image = await picture.toImage(side.round(), side.round());
          try {
            return await _meanLuminance(image);
          } finally {
            image.dispose();
          }
        } finally {
          picture.dispose();
        }
      } finally {
        info.picture.dispose();
      }
    } on Object {
      return null;
    }
  }

  /// The mean brightness of [image]'s visible pixels, each weighted by its
  /// alpha; null for one with nothing visible.
  static Future<double?> _meanLuminance(ui.Image image) async {
    final data = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    if (data == null) return null;
    final pixels = data.buffer.asUint8List();
    var sum = 0.0;
    var weight = 0.0;
    for (var i = 0; i + 3 < pixels.length; i += 4) {
      final alpha = pixels[i + 3] / 255;
      if (alpha == 0) continue;
      final brightness =
          (0.2126 * pixels[i] +
              0.7152 * pixels[i + 1] +
              0.0722 * pixels[i + 2]) /
          255;
      sum += brightness * alpha;
      weight += alpha;
    }
    return weight == 0 ? null : sum / weight;
  }
}

enum _Format { png, jpeg, webp, gif, svg, ico }
