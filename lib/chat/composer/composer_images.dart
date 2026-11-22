import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../images/jpeg_images.dart';
import '../chat_models.dart';

/// Images as models take them: PNG, JPEG, GIF or WebP, a few megabytes at
/// most. Past about 1568 pixels a side they are scaled down anyway, so a
/// larger one only costs upload and context: it is scaled down here. An
/// opaque PNG (a screenshot) goes as JPEG ([compactImage]). Null for what
/// does not decode as an image.
Future<ImageAttachment?> prepareImage(ImageAttachment image) async {
  const maxSide = 1568;
  const maxBytes = 3750000; // 5 MB once base64-encoded.
  final ui.Codec codec;
  try {
    codec = await ui.instantiateImageCodec(image.bytes);
  } on Object {
    return null;
  }
  final frame = await codec.getNextFrame();
  final width = frame.image.width;
  final height = frame.image.height;
  frame.image.dispose();
  codec.dispose();
  final type = _sniff(image.bytes);
  final longest = math.max(width, height);
  if (type != null && longest <= maxSide && image.bytes.length <= maxBytes) {
    return compactImage(
      ImageAttachment(bytes: image.bytes, mediaType: type, name: image.name),
    );
  }
  final scale = math.min(1.0, maxSide / longest);
  final scaled = await ui.instantiateImageCodec(
    image.bytes,
    targetWidth: math.max(1, (width * scale).round()),
    targetHeight: math.max(1, (height * scale).round()),
  );
  final picture = (await scaled.getNextFrame()).image;
  final jpeg = await imageAsJpeg(picture, quality: _jpegQuality);
  if (jpeg != null) {
    picture.dispose();
    scaled.dispose();
    return ImageAttachment(
      bytes: jpeg,
      mediaType: 'image/jpeg',
      name: image.name,
    );
  }
  final png = await picture.toByteData(format: ui.ImageByteFormat.png);
  picture.dispose();
  scaled.dispose();
  if (png == null) return null;
  return ImageAttachment(
    bytes: png.buffer.asUint8List(),
    mediaType: 'image/png',
    name: image.name,
  );
}

/// How a picture sent is made JPEG: as the phone's photos are.
const _jpegQuality = 85;

/// [image] as JPEG when it is an opaque PNG worth it ([pngAsJpeg]), else
/// as it is: sent again on every call that has it in context.
Future<ImageAttachment> compactImage(ImageAttachment image) async {
  if (image.mediaType != 'image/png') return image;
  final jpeg = await pngAsJpeg(image.bytes, quality: _jpegQuality);
  if (jpeg == null) return image;
  return ImageAttachment(
    bytes: jpeg,
    mediaType: 'image/jpeg',
    name: image.name,
    number: image.number,
  );
}

/// The media type the bytes start like, among those models take.
String? _sniff(Uint8List bytes) {
  bool startsWith(List<int> magic, [int at = 0]) {
    if (bytes.length < at + magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (bytes[at + i] != magic[i]) return false;
    }
    return true;
  }

  if (startsWith(const [0x89, 0x50, 0x4E, 0x47])) return 'image/png';
  if (startsWith(const [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  if (startsWith(const [0x47, 0x49, 0x46, 0x38])) return 'image/gif';
  if (startsWith(const [0x52, 0x49, 0x46, 0x46]) &&
      startsWith(const [0x57, 0x45, 0x42, 0x50], 8)) {
    return 'image/webp';
  }
  return null;
}
