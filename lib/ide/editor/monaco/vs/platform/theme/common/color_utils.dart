/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Ported from VS Code src/vs/platform/theme/common/colorUtils.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971: `ColorValue`, `ColorTransform`
// (`ColorTransformType`), `ColorDefaults`, `ColorContribution`, the color
// registry (`getColorRegistry`, `registerColor`, `resolveDefaultColor`,
// `updateDefaultColor`, `deregisterColor`), `executeTransform` and
// `resolveColorValue`, plus the part of themeService.ts `IColorTheme` they
// use.
//
// The registry starts with the registrations of the desktop workbench and the
// built-in extensions, which tool/generate_color_registry.mjs evaluates from
// the upstream sources into color_registry_data.g.dart.
//
// Deviations:
// - A ColorValue is a sealed class instead of `Color | string |
//   ColorTransform`: [ColorLiteral] stands for a `Color` or a '#' string
//   (resolved like upstream, through `Color.fromHex`), [ColorReference] for
//   any other string (a color id), and each transform kind is a class.
// - A [ColorContribution]'s defaults are a [ColorDefaults] (or null); a bare
//   ColorValue default upstream becomes the same value for every color
//   scheme, which is how `resolveDefaultColor` reads it. Descriptions,
//   `needsTransparency`, deprecation messages and the JSON schemas are not
//   ported, nor is `notifyThemeUpdate`.
// - The registry keeps ids in a [LinkedHashMap]; a JavaScript object would
//   list integer-like ids first (no registered id is one).
// - [IColorTheme.getColor] takes `useDefault` as a named parameter.
// - [resolveColors] is a Dart addition: every registered color of a theme.

import 'dart:collection';

import '../../../base/common/color.dart';
import 'color_registry_data.g.dart';
import 'theme.dart';

typedef ColorIdentifier = String;

/// The part of themeService.ts `IColorTheme` color resolution uses.
abstract interface class IColorTheme {
  ColorScheme get type;

  /// Resolves the color of the given color identifier. If the theme does not
  /// specify the color, the default color is returned unless [useDefault] is
  /// set to false.
  Color? getColor(ColorIdentifier color, {bool useDefault = true});

  /// Returns whether the theme defines a value for the color. If not, that
  /// means the default color will be used.
  bool defines(ColorIdentifier color);
}

/// A color literal, a reference to another color or a derived color.
sealed class ColorValue {
  const ColorValue();
}

/// A color literal: upstream's `Color` values and '#' strings.
final class ColorLiteral extends ColorValue {
  /// A '#' string, resolved by `Color.fromHex` (red if invalid).
  const ColorLiteral(String this.hex) : r = 0, g = 0, b = 0, a = 0;

  /// An RGBA color whose alpha a hex string cannot hold (e.g. 0.7).
  const ColorLiteral.rgba(this.r, this.g, this.b, this.a) : hex = null;

  final String? hex;
  final int r, g, b;
  final double a;

  Color get color => switch (hex) {
    final hex? => Color.fromHex(hex),
    null => Color(RGBA(r, g, b, a)),
  };
}

/// A reference to another color: the color the theme resolves for [id].
final class ColorReference extends ColorValue {
  const ColorReference(this.id);

  final ColorIdentifier id;
}

enum ColorTransformType {
  darken,
  lighten,
  transparent,
  opaque,
  oneOf,
  lessProminent,
  ifDefinedThenElse,
  mix,
}

sealed class ColorTransform extends ColorValue {
  const ColorTransform();

  ColorTransformType get op;
}

final class DarkenTransform extends ColorTransform {
  const DarkenTransform(this.value, this.factor);

  final ColorValue value;
  final double factor;

  @override
  ColorTransformType get op => ColorTransformType.darken;
}

final class LightenTransform extends ColorTransform {
  const LightenTransform(this.value, this.factor);

  final ColorValue value;
  final double factor;

  @override
  ColorTransformType get op => ColorTransformType.lighten;
}

final class TransparentTransform extends ColorTransform {
  const TransparentTransform(this.value, this.factor);

  final ColorValue value;
  final double factor;

  @override
  ColorTransformType get op => ColorTransformType.transparent;
}

final class OpaqueTransform extends ColorTransform {
  const OpaqueTransform(this.value, this.background);

  final ColorValue value;
  final ColorValue background;

  @override
  ColorTransformType get op => ColorTransformType.opaque;
}

final class OneOfTransform extends ColorTransform {
  const OneOfTransform(this.values);

  final List<ColorValue> values;

  @override
  ColorTransformType get op => ColorTransformType.oneOf;
}

final class LessProminentTransform extends ColorTransform {
  const LessProminentTransform(
    this.value,
    this.background,
    this.factor,
    this.transparency,
  );

  final ColorValue value;
  final ColorValue background;
  final double factor;
  final double transparency;

  @override
  ColorTransformType get op => ColorTransformType.lessProminent;
}

final class IfDefinedThenElseTransform extends ColorTransform {
  const IfDefinedThenElseTransform(this.ifId, this.then, this.otherwise);

  /// Upstream's `if`.
  final ColorIdentifier ifId;
  final ColorValue then;

  /// Upstream's `else`.
  final ColorValue otherwise;

  @override
  ColorTransformType get op => ColorTransformType.ifDefinedThenElse;
}

final class MixTransform extends ColorTransform {
  const MixTransform(this.color, this.withColor, [this.ratio]);

  final ColorValue color;

  /// Upstream's `with`.
  final ColorValue withColor;
  final double? ratio;

  @override
  ColorTransformType get op => ColorTransformType.mix;
}

class ColorDefaults {
  const ColorDefaults({
    required this.light,
    required this.dark,
    required this.hcDark,
    required this.hcLight,
  });

  /// The same value for every color scheme.
  const ColorDefaults.all(ColorValue? value)
    : light = value,
      dark = value,
      hcDark = value,
      hcLight = value;

  final ColorValue? light;
  final ColorValue? dark;
  final ColorValue? hcDark;
  final ColorValue? hcLight;

  ColorValue? operator [](ColorScheme scheme) => switch (scheme) {
    ColorScheme.light => light,
    ColorScheme.dark => dark,
    ColorScheme.highContrastDark => hcDark,
    ColorScheme.highContrastLight => hcLight,
  };
}

class ColorContribution {
  const ColorContribution(this.id, this.defaults);

  final ColorIdentifier id;
  final ColorDefaults? defaults;
}

/// Upstream's `DEFAULT_COLOR_CONFIG_VALUE`.
// ignore: constant_identifier_names
const String DEFAULT_COLOR_CONFIG_VALUE = 'default';

class ColorRegistry {
  ColorRegistry._() {
    for (final contribution in colorRegistryData) {
      _colorsById[contribution.id] = contribution;
    }
  }

  final LinkedHashMap<ColorIdentifier, ColorContribution> _colorsById =
      LinkedHashMap();

  /// Registers a color; an id registered before keeps its position.
  ColorIdentifier registerColor(ColorIdentifier id, ColorDefaults? defaults) {
    _colorsById[id] = ColorContribution(id, defaults);
    return id;
  }

  void updateDefaultColor(ColorIdentifier id, ColorDefaults? defaults) {
    if (_colorsById.containsKey(id)) {
      _colorsById[id] = ColorContribution(id, defaults);
    }
  }

  void deregisterColor(ColorIdentifier id) {
    _colorsById.remove(id);
  }

  /// All color contributions, in registration order.
  List<ColorContribution> getColors() => List.of(_colorsById.values);

  /// The registration of [id], if any.
  ColorContribution? getColor(ColorIdentifier id) => _colorsById[id];

  /// Gets the default color of the given id.
  Color? resolveDefaultColor(ColorIdentifier id, IColorTheme theme) {
    final defaults = _colorsById[id]?.defaults;
    if (defaults != null) {
      return resolveColorValue(defaults[theme.type], theme);
    }
    return null;
  }
}

final ColorRegistry _colorRegistry = ColorRegistry._();

ColorRegistry getColorRegistry() => _colorRegistry;

ColorIdentifier registerColor(ColorIdentifier id, ColorDefaults? defaults) =>
    _colorRegistry.registerColor(id, defaults);

// ----- color functions

Color? executeTransform(ColorTransform transform, IColorTheme theme) {
  switch (transform) {
    case DarkenTransform(:final value, :final factor):
      return resolveColorValue(value, theme)?.darken(factor);

    case LightenTransform(:final value, :final factor):
      return resolveColorValue(value, theme)?.lighten(factor);

    case TransparentTransform(:final value, :final factor):
      return resolveColorValue(value, theme)?.transparent(factor);

    case MixTransform(:final color, :final withColor, :final ratio):
      final primaryColor =
          resolveColorValue(color, theme) ?? Color.transparentColor;
      final otherColor =
          resolveColorValue(withColor, theme) ?? Color.transparentColor;
      return ratio == null
          ? primaryColor.mix(otherColor)
          : primaryColor.mix(otherColor, ratio);

    case OpaqueTransform(:final value, :final background):
      final backgroundColor = resolveColorValue(background, theme);
      if (backgroundColor == null) {
        return resolveColorValue(value, theme);
      }
      return resolveColorValue(value, theme)?.makeOpaque(backgroundColor);

    case OneOfTransform(:final values):
      for (final candidate in values) {
        final color = resolveColorValue(candidate, theme);
        if (color != null) {
          return color;
        }
      }
      return null;

    case IfDefinedThenElseTransform(:final ifId, :final then, :final otherwise):
      return resolveColorValue(theme.defines(ifId) ? then : otherwise, theme);

    case LessProminentTransform(
      :final value,
      :final background,
      :final factor,
      :final transparency,
    ):
      final from = resolveColorValue(value, theme);
      if (from == null) {
        return null;
      }

      final backgroundColor = resolveColorValue(background, theme);
      if (backgroundColor == null) {
        return from.transparent(factor * transparency);
      }

      return from.isDarkerThan(backgroundColor)
          ? Color.getLighterColor(
              from,
              backgroundColor,
              factor,
            ).transparent(transparency)
          : Color.getDarkerColor(
              from,
              backgroundColor,
              factor,
            ).transparent(transparency);
  }
}

/// Resolves a color value in the context of a theme.
Color? resolveColorValue(ColorValue? colorValue, IColorTheme theme) =>
    switch (colorValue) {
      null => null,
      ColorLiteral() => colorValue.color,
      ColorReference(:final id) => theme.getColor(id),
      ColorTransform() => executeTransform(colorValue, theme),
    };

/// Every registered color as [theme] resolves it (`theme.getColor(id)`), in
/// registration order.
Map<ColorIdentifier, Color?> resolveColors(IColorTheme theme) => {
  for (final contribution in _colorRegistry.getColors())
    contribution.id: theme.getColor(contribution.id),
};
