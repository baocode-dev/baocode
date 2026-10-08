import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../platform/app_platform.dart';

/// The font code is drawn in, its size, its ligatures, and how large the
/// window's text is: settings.json's `editor.fontFamily`, `editor.fontSize`,
/// `editor.fontLigatures` and `window.uiScale`, as Settings → Appearance
/// picks them and VS Code keeps them. Unset: the defaults. A value is kept
/// only when it differs from its default (see the `…Setting` functions).
abstract final class CodeFont {
  static const familySettingKey = 'editor.fontFamily';
  static const sizeSettingKey = 'editor.fontSize';
  static const ligaturesSettingKey = 'editor.fontLigatures';
  static const uiScaleSettingKey = 'window.uiScale';

  /// The stack code is drawn in unless the setting names one. The first
  /// family installed is used, and the rest are what it falls back on (see
  /// `AppFonts.monoFallbacks`). Menlo keeps macOS as it was; Windows has
  /// none of these but Consolas and Cascadia Mono, which follow.
  static const defaultFamilies = <String>[
    'JetBrains Mono',
    'Fira Code',
    'Menlo',
    'Consolas',
    'Cascadia Mono',
  ];

  /// The size the editor draws code at on macOS. Code is drawn from it:
  /// every other code size is moved by the same amount the user moves this
  /// one (see [sized]).
  static const _macSize = 13.0;

  /// The size the editor draws code at unless the setting names one: 14 on
  /// Windows, which draws the same size smaller, 13 elsewhere.
  static double get defaultSize => _macSize + (AppPlatform.isWindows ? 1 : 0);

  static const minSize = 8.0;
  static const maxSize = 32.0;

  /// The slider's sizes, smallest first.
  static const sizeSteps = <double>[
    10,
    11,
    12,
    13,
    14,
    15,
    16,
    17,
    18,
    19,
    20,
    21,
    22,
    23,
    24,
  ];

  /// The window's text scales, as percentages; 100 is the system's.
  static const uiScaleSteps = <int>[90, 100, 110, 125, 150];
  static const defaultUiScale = 100;

  /// The families code is drawn in, the first one used.
  static final ValueNotifier<List<String>> families = ValueNotifier(
    defaultFamilies,
  );

  /// The size code is drawn at (see [sized]).
  static final ValueNotifier<double> size = ValueNotifier(defaultSize);

  /// Whether code draws its ligatures (`=>` as one glyph where the font has
  /// one). The terminal never does: it draws a cell at a time.
  static final ValueNotifier<bool> ligatures = ValueNotifier(true);

  /// The window's text scale, a percentage of the system's.
  static final ValueNotifier<int> uiScale = ValueNotifier(defaultUiScale);

  /// [value] as settings.json has it: a family list, comma-separated or as
  /// an array; quotes and blanks are dropped, and none left is the default.
  static List<String> parseFamilies(Object? value) {
    final Iterable<String> names = switch (value) {
      final String text => text.split(','),
      final List<Object?> list => list.whereType<String>(),
      _ => const <String>[],
    };
    final cleaned = [
      for (final name in names) name.replaceAll(RegExp(r'''["']'''), '').trim(),
    ].where((name) => name.isNotEmpty).toList();
    return cleaned.isEmpty ? defaultFamilies : cleaned;
  }

  /// [families] as settings.json keeps it; null (not written) for the
  /// default.
  static String? familiesSetting(List<String> families) =>
      listEquals(families, defaultFamilies) ? null : families.join(', ');

  /// [value] as settings.json has it, clamped to [minSize]..[maxSize].
  static double parseSize(Object? value) => switch (value) {
    final num size when size.isFinite => size.toDouble().clamp(
      minSize,
      maxSize,
    ),
    _ => defaultSize,
  };

  /// [size] as settings.json keeps it; null (not written) for [defaultSize].
  static int? sizeSetting(double size) =>
      size == defaultSize ? null : size.round();

  /// [value] as settings.json has it; ligatures are on unless it says not.
  static bool parseLigatures(Object? value) => value is bool ? value : true;

  /// [on] as settings.json keeps it; null (not written) for on.
  static bool? ligaturesSetting(bool on) => on ? null : false;

  /// [value] as settings.json has it: one of [uiScaleSteps], else the
  /// default.
  static int parseUiScale(Object? value) => switch (value) {
    final num percent when uiScaleSteps.contains(percent.round()) =>
      percent.round(),
    _ => defaultUiScale,
  };

  /// [percent] as settings.json keeps it; null (not written) for the
  /// default.
  static int? uiScaleSetting(int percent) =>
      percent == defaultUiScale ? null : percent;

  /// [base], a size code is drawn at on macOS, moved by the user's choice:
  /// at the default it is [base] there, and one point more on Windows.
  static double sized(double base) => base + size.value - _macSize;

  /// The features code is drawn with: none (the font's own, ligatures on),
  /// or the two that make ligatures, `liga` and `calt`, switched off.
  static List<ui.FontFeature>? get features => ligatures.value
      ? null
      : const [ui.FontFeature.disable('liga'), ui.FontFeature.disable('calt')];

  /// Sets the notifiers from [read] now and whenever [changes] notifies.
  static void follow(Listenable changes, Object? Function(String key) read) {
    void update() {
      final next = parseFamilies(read(familySettingKey));
      if (!listEquals(next, families.value)) families.value = next;
      size.value = parseSize(read(sizeSettingKey));
      ligatures.value = parseLigatures(read(ligaturesSettingKey));
      uiScale.value = parseUiScale(read(uiScaleSettingKey));
    }

    update();
    changes.addListener(update);
  }
}
