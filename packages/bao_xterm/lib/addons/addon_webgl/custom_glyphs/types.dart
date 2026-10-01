// Copyright (c) 2021 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/LICENSE.txt.
// Ported from xterm.js addons/addon-webgl/src/customGlyphs/Types.ts (c58ea36).
//
// Upstream's object-literal interfaces are `final class`es with const
// constructors, so the definitions table reads as upstream's literals do.

/// A rectangle in eighths of the cell: `x`, `y`, `w` and `h` in 0-8.
final class ICustomGlyphSolidOctantBlockVector {
  const ICustomGlyphSolidOctantBlockVector({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });

  final int x;
  final int y;
  final int w;
  final int h;
}

/// [xp] is the percentage of 15% of the x axis; [yp] the percentage of 15% of
/// the x axis on the y axis.
typedef CustomGlyphPathDrawFunctionDefinition = String Function(
  double xp,
  double yp,
);

final class ICustomGlyphVectorShape {
  const ICustomGlyphVectorShape({
    required this.d,
    required this.type,
    this.leftPadding,
    this.rightPadding,
  });

  final String d;
  final CustomGlyphVectorType type;
  final double? leftPadding;
  final double? rightPadding;
}

enum CustomGlyphVectorType { fill, stroke }

typedef CustomGlyphPatternDefinition = List<List<int>>;

enum CustomGlyphDefinitionType {
  solidOctantBlockVector,
  blockPattern,
  pathFunction,
  path,
  pathNegative,
  vectorShape,
  braille,
}

enum CustomGlyphScaleType {
  /// Scale to the entire cell, including letter spacing and line height.
  cell,

  /// Scale to only the character area, excluding letter spacing and line
  /// height.
  char,
}

abstract interface class ICustomGlyphDefinitionCommon {
  /// A custom clip path for the draw definition, restricting the area it can
  /// draw to.
  String? get clipPath;

  /// The stroke width to use when drawing the path. Defaults to 1.
  double? get strokeWidth;

  /// Defines how to scale the draw. Defaults to scaling to the full cell
  /// including letter spacing and line height.
  CustomGlyphScaleType? get scaleType;
}

/// Upstream's `CustomGlyphDefinitionPartRaw & ICustomGlyphDefinitionCommon`.
///
/// [data] is the union upstream's [type] selects:
///
/// | [type] | [data] |
/// | --- | --- |
/// | `solidOctantBlockVector` | `List<ICustomGlyphSolidOctantBlockVector>` |
/// | `blockPattern` | [CustomGlyphPatternDefinition] |
/// | `pathFunction` | [CustomGlyphPathDrawFunctionDefinition] or `String` |
/// | `path` | `String` |
/// | `pathNegative` | [ICustomGlyphVectorShape] |
/// | `vectorShape` | [ICustomGlyphVectorShape] |
/// | `braille` | `int` |
final class CustomGlyphDefinitionPart implements ICustomGlyphDefinitionCommon {
  const CustomGlyphDefinitionPart({
    required this.type,
    required this.data,
    this.clipPath,
    this.strokeWidth,
    this.scaleType,
  });

  final CustomGlyphDefinitionType type;
  final Object data;
  @override
  final String? clipPath;
  @override
  final double? strokeWidth;
  @override
  final CustomGlyphScaleType? scaleType;
}

/// A character definition: the parts drawn in sequence. Upstream also allows
/// a single part; here it is always a list.
typedef CustomGlyphCharacterDefinition = List<CustomGlyphDefinitionPart>;
