// An SVG file on this machine. flutter_svg's `SvgPicture.file` takes its own
// `File` on the web (where there are no files), not dart:io's.
export 'svg_file_stub.dart' if (dart.library.io) 'svg_file_io.dart';
