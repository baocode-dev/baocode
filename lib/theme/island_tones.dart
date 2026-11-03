// The cards (Islands) and the window under them, set apart.
//
// A theme's editor is its cards' color and its side bar the window's (see
// AppColors). Many themes' are a shade apart, as the parts sat side by side
// with a line between them: Bao Dark's #222221 on #181817, Bao Light's
// #FCFBFA on #F3F3F1, the cards hardly told from the window. Their colors
// are moved apart as WorkbenchColors reads them, every color of a card's
// tone with it, so what reads `editor.background` (the editor, the
// terminal, a tab on a card) or a color the registry makes of it stays the
// card's.

import 'dart:math' as math;
import 'dart:ui';

/// How a theme's colors are moved so its cards stand apart from the
/// window. A dark theme's window as it is, its cards (and what is on them,
/// as far above them) lifted [darkStep] over it; a light theme's cards
/// lifted, and where they are as light as they go, the window sunk.
class IslandTones {
  IslandTones._(
    this._card,
    this._base,
    this._lift,
    this._window, [
    this._cards = true,
  ]);

  /// For a theme whose cards are [card] (`editor.background`) on a window
  /// of [base] (`sideBar.background`). Nothing moved where the window is
  /// the lighter.
  factory IslandTones(Color card, Color base) {
    final cardL = lightness(card);
    final baseL = lightness(base);
    if (card.a < 1 || base.a < 1 || cardL < baseL) return _asTheyAre;
    if (baseL < 0.5) {
      final lift = baseL + darkStep - cardL;
      return lift <= 0 ? _asTheyAre : IslandTones._(cardL, baseL, lift, 0);
    }
    final need = lightStep - (cardL - baseL);
    if (need <= 0) return _asTheyAre;
    final lift = math.min(need, math.max(0.0, _lightest - cardL));
    return IslandTones._(cardL, baseL, lift, lift - need);
  }

  /// Leaves every color as it is (a high contrast theme's, its lines
  /// kept).
  static final none = IslandTones._(0, 0, 0, 0, false);

  /// Moves none, the lines a card has no need of gone.
  static final _asTheyAre = IslandTones._(0, 0, 0, 0);

  /// Lines on a card setting a part of it apart, of no use there, the
  /// card's edges doing it: the overview rulers' left edges (a dark
  /// theme's near black, a hard line down a lifted card).
  static const _apartOnCard = [
    'editorOverviewRuler.border',
    'terminalOverviewRuler.border',
  ];

  /// The least lightness (OKLab L) between a dark theme's cards and its
  /// window: further than the island prototype's (#222221 on #181817,
  /// 0.043), the cards lighter (#2B2B2B on #181818).
  static const darkStep = 0.08;

  /// A light theme's: further, light grays being harder to tell apart.
  static const lightStep = 0.06;

  /// As light as a card is lifted: the rest of [lightStep], the window
  /// sunk.
  static const _lightest = 0.97;

  /// How far above the card a color lifts with it: what is on a card
  /// (its inputs, menus, lines, selections), not its text.
  static const _onCard = 0.13;

  /// How near a color is to be taken for the card's or the window's.
  static const _same = 0.004;

  /// Popups over everything, of the window's color in some themes (Bao
  /// Light's menus): not sunk with it.
  static const _popups = [
    'menu.',
    'editorWidget.',
    'editorHoverWidget.',
    'editorSuggestWidget.',
    'quickInput.',
    'notifications.',
    'notificationCenterHeader.',
    'dropdown.',
    'widget.',
    'peekView',
    'debugToolBar.',
    'breadcrumbPicker.',
  ];

  final bool _cards;
  final double _card;
  final double _base;
  final double _lift;

  /// How much darker a light theme's window is (negative): sunk.
  final double _window;

  /// [color], read for [id], moved: lifted if it is of a card's tone, sunk
  /// with the window if of the window's. Text,
  /// popups' backgrounds when sunk, and what is see-through, as they are;
  /// [_apartOnCard], gone.
  Color apply(String id, Color color) {
    if (_cards && _apartOnCard.contains(id)) return const Color(0x00000000);
    if ((_lift == 0 && _window == 0) || color.a < 1) return color;
    if (id.endsWith('oreground')) return color;
    final l = lightness(color);
    if (_lift > 0 && l >= _card - _same && l <= _card + _onCard) {
      return shift(color, _lift);
    }
    if (_window < 0 &&
        (l - _base).abs() <= _same &&
        !_popups.any(id.startsWith)) {
      return shift(color, _window);
    }
    return color;
  }

  /// Perceived lightness, OKLab's L for a gray: the cube root of the
  /// luminance.
  static double lightness(Color color) =>
      math.pow(color.withValues(alpha: 1).computeLuminance(), 1 / 3) * 1.0;

  /// [color] [by] lighter (darker, [by] negative) in OKLab, its hue and
  /// chroma kept: a warm gray as warm, a tinted selection as tinted, not
  /// washed out as mixing in white would.
  static Color shift(Color color, double by) {
    final (l, a, b) = _toOklab(color);
    return _fromOklab(l + by, a, b, color.a);
  }

  static double _linear(double c) =>
      c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4) * 1.0;

  static double _gamma(double c) {
    final v = c <= 0.0031308 ? c * 12.92 : 1.055 * math.pow(c, 1 / 2.4) - 0.055;
    return v.clamp(0.0, 1.0);
  }

  static double _cbrt(double v) =>
      v < 0 ? -math.pow(-v, 1 / 3) * 1.0 : math.pow(v, 1 / 3) * 1.0;

  static (double, double, double) _toOklab(Color color) {
    final r = _linear(color.r), g = _linear(color.g), b = _linear(color.b);
    final l = _cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
    final m = _cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
    final s = _cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
    return (
      0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
      1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
      0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
    );
  }

  static Color _fromOklab(double lightness, double a, double b, double alpha) {
    final l = math.pow(lightness + 0.3963377774 * a + 0.2158037573 * b, 3);
    final m = math.pow(lightness - 0.1055613458 * a - 0.0638541728 * b, 3);
    final s = math.pow(lightness - 0.0894841775 * a - 1.2914855480 * b, 3);
    return Color.from(
      alpha: alpha,
      red: _gamma(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
      green: _gamma(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
      blue: _gamma(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s),
    );
  }
}
