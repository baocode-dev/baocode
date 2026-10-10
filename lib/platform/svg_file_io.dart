import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'svg_color_scheme.dart';

/// The SVG at [path]; drawn for the [dark] or light color scheme when its
/// style tells them apart ([svgForColorScheme]).
Widget svgFile(
  String path, {
  double? width,
  double? height,
  BoxFit fit = BoxFit.contain,
  bool? dark,
}) => dark == null
    ? SvgPicture.file(File(path), width: width, height: height, fit: fit)
    : SvgPicture(
        _SchemeSvgFileLoader(File(path), dark: dark),
        width: width,
        height: height,
        fit: fit,
      );

/// [SvgFileLoader] with [svgForColorScheme] applied.
class _SchemeSvgFileLoader extends SvgFileLoader {
  const _SchemeSvgFileLoader(super.file, {required this.dark});

  final bool dark;

  @override
  String provideSvg(void message) =>
      svgForColorScheme(super.provideSvg(message), dark: dark);

  @override
  int get hashCode => Object.hash(super.hashCode, dark);

  @override
  bool operator ==(Object other) =>
      other is _SchemeSvgFileLoader && other.dark == dark && super == other;
}
