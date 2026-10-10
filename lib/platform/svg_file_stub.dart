import 'package:flutter/widgets.dart';

/// No files on the web: the space the SVG at [path] would take.
Widget svgFile(
  String path, {
  double? width,
  double? height,
  BoxFit fit = BoxFit.contain,
}) => SizedBox(width: width, height: height);
