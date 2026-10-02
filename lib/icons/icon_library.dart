import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path/path.dart' as p;

import 'icon_storage.dart';

/// How an uploaded picture is kept and drawn.
enum IconImageKind {
  /// A PNG, JPEG or WebP, kept as a square PNG of at most
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
    for (final entry in await storage.readIndex()) {
      if (entry case {'id': final String id, 'kind': final String kind}
          when !_images.any((image) => image.id == id)) {
        final type = IconImageKind.values.asNameMap()[kind];
        if (type == null) continue;
        final bytes = await storage.read('$id.$kind');
        if (bytes == null) continue;
        _images.add(
          IconImage(
            id: id,
            kind: type,
            name: entry['name'] as String? ?? '',
            bytes: bytes,
          ),
        );
      }
    }
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
    try {
      kept = kind == IconImageKind.png ? await _square(bytes) : bytes;
    } on Object {
      throw const IconUploadException(IconUploadError.unsupported);
    }
    final image = IconImage(id: id, kind: kind, name: name, bytes: kept);
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
        {'id': image.id, 'kind': image.kind.name, 'name': image.name},
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
  /// picture: decoded at that size, never at its own.
  static Future<Uint8List> _square(Uint8List bytes) async {
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
        return data!.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    } finally {
      descriptor.dispose();
    }
  }
}

enum _Format { png, jpeg, webp, gif, svg }
