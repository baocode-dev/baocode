import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Below this a PNG is kept: too little to gain.
const _jpegFrom = 64 * 1024;

/// [png], an opaque picture (a screenshot), as JPEG at [quality]: a
/// fraction of the bytes, which go to the model again on every call that
/// has it in its context. Null to keep it as it is: not a PNG, small, any
/// pixel not opaque (JPEG has no transparency), not decoded, or no smaller
/// as JPEG.
///
/// Decoded by Flutter, as it is shown; only encoded by `package:image`,
/// from the pixels decoded, and the JPEG checked to decode at the same size.
Future<Uint8List?> pngAsJpeg(Uint8List png, {int quality = 80}) async {
  if (png.length < _jpegFrom || !_isPng(png)) return null;
  try {
    final codec = await ui.instantiateImageCodec(png);
    if (codec.frameCount != 1) {
      codec.dispose();
      return null;
    }
    final image = (await codec.getNextFrame()).image;
    codec.dispose();
    try {
      final jpeg = await imageAsJpeg(image, quality: quality);
      return jpeg != null && jpeg.length < png.length ? jpeg : null;
    } finally {
      image.dispose();
    }
  } on Object catch (error) {
    debugPrint('PNG kept, not made JPEG: $error');
    return null;
  }
}

/// [image] as JPEG at [quality], encoded off the UI isolate; null when any
/// pixel is not opaque, or the JPEG does not decode back at its size.
Future<Uint8List?> imageAsJpeg(ui.Image image, {int quality = 80}) async {
  final rgba = await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  );
  if (rgba == null) return null;
  final width = image.width;
  final height = image.height;
  try {
    final jpeg = await compute(_encode, (
      pixels: rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes),
      width: width,
      height: height,
      quality: quality,
    ));
    if (jpeg == null) return null;
    final check = await ui.instantiateImageCodec(jpeg);
    final frame = (await check.getNextFrame()).image;
    check.dispose();
    final same = frame.width == width && frame.height == height;
    frame.dispose();
    return same ? jpeg : null;
  } on Object catch (error) {
    debugPrint('Not made JPEG: $error');
    return null;
  }
}

Uint8List? _encode(
  ({Uint8List pixels, int width, int height, int quality}) job,
) {
  final pixels = job.pixels;
  if (pixels.length != job.width * job.height * 4) return null;
  for (var i = 3; i < pixels.length; i += 4) {
    if (pixels[i] != 0xFF) return null;
  }
  final image = img.Image.fromBytes(
    width: job.width,
    height: job.height,
    bytes: pixels.buffer,
    bytesOffset: pixels.offsetInBytes,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return img.encodeJpg(image, quality: job.quality);
}

bool _isPng(Uint8List bytes) =>
    bytes.length > 8 &&
    bytes[0] == 0x89 &&
    bytes[1] == 0x50 &&
    bytes[2] == 0x4E &&
    bytes[3] == 0x47;
