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
/// window: the cards lifted (and what is on them, as far above them), and,
/// where they are as light as they go, the window sunk.
class IslandTones {
  IslandTones._(this._card, this._base, this._lift, this._sink);

  /// For a theme whose cards are [card] (`editor.background`) on a window
  /// of [base] (`sideBar.background`). Nothing moved where they are [step]
  /// apart already, or the window is the lighter.
  factory IslandTones(Color card, Color base) {
    final cardL = lightness(card);
    final baseL = lightness(base);
    final need = step - (cardL - baseL);
    if (card.a < 1 || base.a < 1 || cardL < baseL || need <= 0) {
      return IslandTones._(cardL, baseL, 0, 0);
    }
    final lift = math.min(need, math.max(0.0, _lightest - cardL));
    return IslandTones._(cardL, baseL, lift, need - lift);
  }

  /// Leaves every color as it is.
  static final none = IslandTones._(0, 0, 0, 0);

  /// The least lightness (OKLab L) between the cards and the window: over
  /// the island prototype's (#222221 on #181817, 0.043).
  static const step = 0.06;

  /// As light as a card is lifted: the rest of [step], the window sunk.
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

  final double _card;
  final double _base;
  final double _lift;
  final double _sink;

  /// [color], read for [id], moved: lifted if it is of a card's tone, sunk
  /// if the window's. Text, and what is see-through, as it is.
  Color apply(String id, Color color) {
    if ((_lift == 0 && _sink == 0) || color.a < 1) return color;
    if (id.endsWith('oreground')) return color;
    final l = lightness(color);
    if (_lift > 0 && l >= _card - _same && l <= _card + _onCard) {
      return shift(color, _lift);
    }
    if (_sink > 0 &&
        (l - _base).abs() <= _same &&
        !_popups.any(id.startsWith)) {
      return shift(color, -_sink);
    }
    return color;
  }

  /// Perceived lightness, OKLab's L for a gray: the cube root of the
  /// luminance.
  static double lightness(Color color) =>
      math.pow(color.withValues(alpha: 1).computeLuminance(), 1 / 3) * 1.0;

  /// [color] towards white (or black, [by] negative) till its [lightness]
  /// is [by] more.
  static Color shift(Color color, double by) {
    final target = lightness(color) + by;
    final towards = (by > 0 ? const Color(0xFFFFFFFF) : const Color(0xFF000000))
        .withValues(alpha: color.a);
    var (low, high) = (0.0, 1.0);
    for (var i = 0; i < 20; i++) {
      final mid = (low + high) / 2;
      final l = lightness(Color.lerp(color, towards, mid)!);
      if (by > 0 ? l < target : l > target) {
        low = mid;
      } else {
        high = mid;
      }
    }
    return Color.lerp(color, towards, high)!;
  }
}
