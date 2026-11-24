import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// An image made to fit what the model takes, as the CLI makes it: its
/// bytes, its type, and its size before and after.
class FittedImage {
  const FittedImage(
    this.bytes,
    this.mediaType, {
    this.width,
    this.height,
    this.displayWidth,
    this.displayHeight,
  });

  final Uint8List bytes;
  final String mediaType;

  /// As it was; null when it could not be told.
  final int? width;
  final int? height;

  /// As it is sent.
  final int? displayWidth;
  final int? displayHeight;

  bool get resized =>
      width != null &&
      displayWidth != null &&
      (width != displayWidth || height != displayHeight);

  /// What the model is told of an image made smaller (the CLI's words):
  /// null when it was sent as it was.
  String? get note {
    if (!resized || displayWidth! <= 0) return null;
    final scale = (width! / displayWidth!).toStringAsFixed(2);
    return '[Image: original ${width}x$height, displayed at '
        '${displayWidth}x$displayHeight. Multiply coordinates by $scale to '
        'map to original image.]';
  }
}

/// An image that cannot be sent: not one the model takes, or too large and
/// not to be made smaller.
class ImageFitException implements Exception {
  const ImageFitException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The longest side an image may have.
const maxImageSide = 2000;

/// The most an image may be, before base64 (5MB once encoded).
const maxImageBytes = 3750 * 1024;

/// What [bytes] are by their first bytes: `image/png`, `image/jpeg`,
/// `image/gif`, `image/webp`; null for anything else.
String? sniffImageType(List<int> bytes) {
  bool at(int offset, List<int> magic) {
    if (bytes.length < offset + magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (bytes[offset + i] != magic[i]) return false;
    }
    return true;
  }

  if (at(0, const [0x89, 0x50, 0x4E, 0x47])) return 'image/png';
  if (at(0, const [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  if (at(0, const [0x47, 0x49, 0x46, 0x38])) return 'image/gif';
  if (at(0, const [0x52, 0x49, 0x46, 0x46]) &&
      at(8, const [0x57, 0x45, 0x42, 0x50])) {
    return 'image/webp';
  }
  return null;
}

/// [bytes] made to fit: as they are when within [maxSide] and [maxBytes];
/// else smaller, as the CLI does it (to fit inside [maxSide], kept PNG
/// where it was, then fewer colours, then JPEG of less and less quality,
/// at last 1000 wide). Decoded and encoded off this isolate. Throws an
/// [ImageFitException] when it cannot be sent.
Future<FittedImage> fitImage(
  Uint8List bytes, {
  String? fallbackType,
  int maxSide = maxImageSide,
  int maxBytes = maxImageBytes,
}) async {
  final type = sniffImageType(bytes) ?? fallbackType;
  final info = _dimensions(bytes);
  if (info != null &&
      info.$1 <= maxSide &&
      info.$2 <= maxSide &&
      bytes.length <= maxBytes &&
      type != null) {
    return FittedImage(
      bytes,
      type,
      width: info.$1,
      height: info.$2,
      displayWidth: info.$1,
      displayHeight: info.$2,
    );
  }
  if (info == null && bytes.length <= maxBytes && type != null) {
    return FittedImage(bytes, type);
  }
  return Isolate.run(() => _shrink(bytes, type, maxSide, maxBytes));
}

(int, int)? _dimensions(Uint8List bytes) {
  try {
    final info = img.findDecoderForData(bytes)?.startDecode(bytes);
    if (info == null || info.width <= 0 || info.height <= 0) return null;
    return (info.width, info.height);
  } on Object {
    return null;
  }
}

FittedImage _shrink(Uint8List bytes, String? type, int maxSide, int maxBytes) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes, frame: 0);
  } on Object {
    decoded = null;
  }
  if (decoded == null) {
    throw ImageFitException(
      bytes.length > maxBytes
          ? 'The image is ${_mb(bytes.length)}, more than the '
                '${_mb(maxBytes)} the model takes, and could not be decoded '
                'to make it smaller. Convert it to PNG or JPEG first.'
          : 'The file could not be decoded as an image.',
    );
  }
  final source = decoded;
  final width = source.width;
  final height = source.height;
  FittedImage done(Uint8List out, String mediaType, img.Image shown) =>
      FittedImage(
        out,
        mediaType,
        width: width,
        height: height,
        displayWidth: shown.width,
        displayHeight: shown.height,
      );

  var shown = source;
  if (width > maxSide || height > maxSide) {
    shown = width >= height
        ? img.copyResize(
            source,
            width: maxSide,
            interpolation: img.Interpolation.average,
          )
        : img.copyResize(
            source,
            height: maxSide,
            interpolation: img.Interpolation.average,
          );
    if (type == 'image/png') {
      final png = img.encodePng(shown, level: 9);
      if (png.length <= maxBytes) return done(png, 'image/png', shown);
      final palette = img.encodePng(img.quantize(shown), level: 9);
      if (palette.length <= maxBytes) return done(palette, 'image/png', shown);
    }
  }
  for (final quality in const [80, 60, 40, 20]) {
    final jpeg = img.encodeJpg(shown, quality: quality);
    if (jpeg.length <= maxBytes) return done(jpeg, 'image/jpeg', shown);
  }
  final last = shown.width > 1000
      ? img.copyResize(
          shown,
          width: 1000,
          interpolation: img.Interpolation.average,
        )
      : shown;
  return done(img.encodeJpg(last, quality: 20), 'image/jpeg', last);
}

String _mb(int bytes) => '${(bytes / 1024 / 1024).toStringAsFixed(1)}MB';
