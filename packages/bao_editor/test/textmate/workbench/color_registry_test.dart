// The color registry and ColorThemeData.getColor against VS Code: replays
// test/fixtures/theme/color_registry.json.gz, which
// tool/generate_color_registry.mjs records from the real upstream
// registrations and colorThemeData.ts. For the bundled color themes and an
// empty theme of each color scheme, every registered id's `getColor(id)`,
// `getColor(id, false)` and `defines(id)` must match, including the HSLA/HSVA
// a color answers with.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bao_editor/monaco/vs/base/common/color.dart';
import 'package:bao_editor/monaco/vs/platform/theme/common/color_registry_data.g.dart';
import 'package:bao_editor/monaco/vs/platform/theme/common/color_utils.dart';
import 'package:bao_editor/monaco/vs/platform/theme/common/theme.dart';
import 'package:bao_editor/monaco/vs/workbench/services/themes/common/color_theme_data.dart';
import 'package:bao_editor/textmate/textmate_manifest.dart';

Future<String> readAsset(String path) =>
    File('$textMateAssetDirectory/$path').readAsString();

/// How JavaScript prints a number.
String _js(double value) {
  if (value.isNaN) return 'NaN';
  if (value == value.truncateToDouble()) return value.toInt().toString();
  return value.toString();
}

String _hsla(HSLA v) => 'hsla:${v.h},${_js(v.s)},${_js(v.l)},${_js(v.a)}';
String _hsva(HSVA v) => 'hsva:${v.h},${_js(v.s)},${_js(v.v)},${_js(v.a)}';

/// A color as `rgba|hsla|hsva`.
String? _describe(Color? color) => color == null
    ? null
    : '${color.rgba.r},${color.rgba.g},${color.rgba.b},${_js(color.rgba.a)}'
          '|${_hsla(color.hsla)}|${_hsva(color.hsva)}';

/// A fixture value as `rgba|hsla|hsva`: the generator writes the HSLA/HSVA
/// only for a color made from one; any other color converts its RGBA.
String _expected(String value) {
  final parts = value.split('|');
  final channels = parts[0].split(',');
  double channel(int i) =>
      channels[i] == 'NaN' ? double.nan : double.parse(channels[i]);
  final rgba = RGBA(channel(0), channel(1), channel(2), channel(3));
  final hsla = parts.firstWhere(
    (p) => p.startsWith('hsla:'),
    orElse: () => _hsla(HSLA.fromRGBA(rgba)),
  );
  final hsva = parts.firstWhere(
    (p) => p.startsWith('hsva:'),
    orElse: () => _hsva(HSVA.fromRGBA(rgba)),
  );
  return '${parts[0]}|$hsla|$hsva';
}

String _selector(ColorScheme type) => switch (type) {
  ColorScheme.light => ThemeTypeSelector.vs.value,
  ColorScheme.dark => ThemeTypeSelector.vsDark.value,
  ColorScheme.highContrastDark => ThemeTypeSelector.hcBlack.value,
  ColorScheme.highContrastLight => ThemeTypeSelector.hcLight.value,
};

/// A theme for the transform tests: [colors] as defined colors.
class _Theme implements IColorTheme {
  _Theme(this.colors);

  final Map<String, Color> colors;

  @override
  ColorScheme get type => ColorScheme.dark;

  @override
  Color? getColor(String color, {bool useDefault = true}) => colors[color];

  @override
  bool defines(String color) => colors.containsKey(color);
}

void main() {
  final fixture = jsonDecode(
    utf8.decode(
      gzip.decode(
        File('test/fixtures/theme/color_registry.json.gz').readAsBytesSync(),
      ),
    ),
  ) as Map<String, Object?>;
  final manifest = TextMateManifest.parse(
    File('$textMateAssetDirectory/manifest.json').readAsStringSync(),
  );
  final ids = (fixture['ids'] as List<Object?>).cast<String>();
  final values = [
    for (final value in fixture['values'] as List<Object?>)
      _expected(value as String),
  ];

  test('the registry holds the upstream ids in registration order', () {
    expect(fixture['revision'], manifest.revision);
    expect(getColorRegistry().getColors().map((c) => c.id).toList(), ids);
    expect(colorRegistryData.map((c) => c.id).toList(), ids);
    final extensionIds = (fixture['extensionIds'] as List<Object?>)
        .cast<String>();
    expect(extensionIds, isNotEmpty);
    expect(ids.sublist(ids.length - extensionIds.length), extensionIds);
  });

  final themes = (fixture['themes'] as List<Object?>)
      .cast<Map<String, Object?>>();
  test('the fixture covers every bundled theme and color scheme', () {
    expect(
      themes.map((t) => t['name']).whereType<String>().toSet(),
      // VS Code's themes, not BaoCode's own.
      manifest.themes
          .where((t) => t.extension != 'theme-bao')
          .map((t) => t.id)
          .toSet(),
    );
    expect(
      themes.where((t) => t['name'] == null).map((t) => t['type']).toSet(),
      ColorScheme.values.map((s) => s.value).toSet(),
    );
  });

  for (final entry in themes) {
    final name = entry['name'] as String?;
    test(name ?? 'no theme (${entry['type']})', () async {
      final ColorThemeData theme;
      if (name != null) {
        final contribution = manifest.themeById(name)!;
        theme = ColorThemeData.fromExtensionTheme(
          contribution,
          contribution.assetPath,
          extensionId: contribution.extensionId,
        );
        await theme.ensureLoaded(readAsset);
      } else {
        final type = ColorScheme.values.firstWhere(
          (s) => s.value == entry['type'],
        );
        theme = ColorThemeData.createLoadedEmptyTheme(
          _selector(type),
          _selector(type),
        );
      }
      expect(theme.type.value, entry['type']);

      final getColor = entry['getColor'] as List<Object?>;
      final getColorNoDefault = entry['getColorNoDefault'] as List<Object?>;
      final defines = entry['defines'] as String;
      final resolved = resolveColors(theme);
      expect(resolved.keys.toList(), ids);

      final differences = <String>[];
      void check(String what, Color? actual, Object? index) {
        final expected = index == null ? null : values[index as int];
        final description = _describe(actual);
        if (description != expected) {
          differences.add('$what: $description, expected $expected');
        }
      }

      for (var i = 0; i < ids.length; i++) {
        final id = ids[i];
        check('getColor($id)', theme.getColor(id), getColor[i]);
        check(
          'getColor($id, false)',
          theme.getColor(id, useDefault: false),
          getColorNoDefault[i],
        );
        check('resolveColors[$id]', resolved[id], getColor[i]);
        if (theme.defines(id) != (defines[i] == '1')) {
          differences.add('defines($id): ${theme.defines(id)}');
        }
      }
      expect(differences, isEmpty, reason: '${differences.length} differ');
    });
  }

  group('transforms', () {
    final red = Color.fromHex('#ff0000');
    final black = Color.fromHex('#000000');
    Color? resolve(ColorValue? value, [Map<String, Color> colors = const {}]) =>
        resolveColorValue(value, _Theme(colors));

    test('literals and references', () {
      expect(resolve(null), isNull);
      expect(resolve(const ColorLiteral('#12345'))!.equals(Color.red), isTrue);
      expect(
        ColorFormatCSS.formatRGBA(
          resolve(const ColorLiteral.rgba(100, 100, 100, 0.7))!,
        ),
        'rgba(100, 100, 100, 0.7)',
      );
      expect(resolve(const ColorReference('a')), isNull);
      expect(resolve(const ColorReference('a'), {'a': red}), same(red));
    });

    test('missing operands', () {
      const missing = ColorReference('missing');
      expect(resolve(const DarkenTransform(missing, 0.1)), isNull);
      expect(resolve(const OneOfTransform([missing, missing])), isNull);
      expect(
        resolve(const OneOfTransform([missing, ColorReference('a')]), {
          'a': red,
        }),
        same(red),
      );
      // Opaque without a background is the value itself.
      final translucent = red.transparent(0.5);
      expect(
        resolve(const OpaqueTransform(ColorReference('a'), missing), {
          'a': translucent,
        }),
        same(translucent),
      );
      // Mix treats a missing color as transparent.
      expect(
        ColorFormatCSS.formatRGBA(
          resolve(const MixTransform(missing, missing))!,
        ),
        'rgba(0, 0, 0, 0)',
      );
      // LessProminent without a background only fades.
      expect(
        ColorFormatCSS.formatRGBA(
          resolve(
            const LessProminentTransform(
              ColorReference('a'),
              missing,
              0.5,
              0.4,
            ),
            {'a': red},
          )!,
        ),
        'rgba(255, 0, 0, 0.2)',
      );
    });

    test('ifDefinedThenElse', () {
      const transform = IfDefinedThenElseTransform(
        'a',
        ColorLiteral('#ffffff'),
        ColorLiteral('#000000'),
      );
      expect(resolve(transform, {'a': red})!.equals(Color.white), isTrue);
      expect(resolve(transform)!.equals(black), isTrue);
    });
  });

  test('registerColor keeps the position of an id, deregister removes it', () {
    final registry = getColorRegistry();
    final count = registry.getColors().length;
    const defaults = ColorDefaults.all(ColorLiteral('#010203'));
    registerColor('baocode.test', defaults);
    registerColor(ids.first, defaults);
    try {
      expect(registry.getColors().length, count + 1);
      expect(registry.getColors().first.id, ids.first);
      expect(registry.getColors().last.id, 'baocode.test');
      final theme = ColorThemeData.createLoadedEmptyTheme('vs', 'vs');
      expect(ColorFormatCSS.formatHex(theme.getColor(ids.first)!), '#010203');
      registry.updateDefaultColor('baocode.missing', defaults);
      expect(registry.getColor('baocode.missing'), isNull);
    } finally {
      registry.deregisterColor('baocode.test');
      registry.registerColor(ids.first, colorRegistryData.first.defaults);
    }
    expect(registry.getColors().map((c) => c.id).toList(), ids);
  });
}
