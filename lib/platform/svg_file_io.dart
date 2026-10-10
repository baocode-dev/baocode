import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The SVG at [path].
Widget svgFile(
  String path, {
  double? width,
  double? height,
  BoxFit fit = BoxFit.contain,
}) => SvgPicture.file(File(path), width: width, height: height, fit: fit);
