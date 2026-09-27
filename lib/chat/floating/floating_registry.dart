import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Keeps floating elements singular: at most one popover (menu, picker,
/// suggestion list) and at most one tooltip at a time, and no tooltip while
/// a popover is open.
///
/// Owners register when they open, from an event handler or timer (not
/// during build), and pass how to close them; opening another one calls
/// that.
///
/// It also routes keys to the open popover: the focused input asks
/// [handleKey] first. (A [HardwareKeyboard] handler cannot keep a key from
/// the focused widget: every handler sees every key, focus included.)
abstract final class FloatingRegistry {
  static ({
    Object owner,
    VoidCallback dismiss,
    KeyEventResult? Function(KeyEvent event)? onKey,
  })?
  _popover;
  static ({Object owner, VoidCallback dismiss})? _tooltip;

  static bool get isPopoverOpen => _popover != null;
  static bool get isTooltipOpen => _tooltip != null;

  /// [owner] opened a popover; any other popover and any tooltip close.
  static void openPopover(
    Object owner,
    VoidCallback dismiss, {
    KeyEventResult? Function(KeyEvent event)? onKey,
  }) {
    final previous = _popover;
    _popover = (owner: owner, dismiss: dismiss, onKey: onKey);
    if (previous != null && !identical(previous.owner, owner)) {
      previous.dismiss();
    }
    final tooltip = _tooltip;
    _tooltip = null;
    tooltip?.dismiss();
  }

  /// [owner]'s popover closed (by itself or by [dismiss]).
  static void closePopover(Object owner) {
    if (identical(_popover?.owner, owner)) _popover = null;
  }

  /// Whether [owner] may show a tooltip now: not while a popover is open.
  /// If so, any other tooltip closes.
  static bool openTooltip(Object owner, VoidCallback dismiss) {
    if (_popover != null) return false;
    final previous = _tooltip;
    _tooltip = (owner: owner, dismiss: dismiss);
    if (previous != null && !identical(previous.owner, owner)) {
      previous.dismiss();
    }
    return true;
  }

  static void closeTooltip(Object owner) {
    if (identical(_tooltip?.owner, owner)) _tooltip = null;
  }

  /// Offers [event] to the open popover (arrows, Enter, Esc in a menu), then
  /// lets Esc close a tooltip. Null when neither wants it.
  static KeyEventResult? handleKey(KeyEvent event) {
    if (_popover?.onKey?.call(event) case final result?) return result;
    final tooltip = _tooltip;
    if (tooltip != null &&
        event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _tooltip = null;
      tooltip.dismiss();
      return KeyEventResult.handled;
    }
    return null;
  }

  @visibleForTesting
  static void reset() {
    _popover = null;
    _tooltip = null;
  }
}
