import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../ide/ide_hover.dart';
import 'floating_layer.dart';
import 'floating_placement.dart';
import 'floating_registry.dart';

/// A tooltip shown while [child] is hovered, with the usual timing:
///
/// - Shows after [showDelay]; right away while another tooltip is showing
///   or just closed (moving along a row of items).
/// - Hides [hideDelay] after the pointer leaves, unless it moves onto the
///   tooltip itself, which then stays until the pointer leaves it too (its
///   text can be selected).
/// - A press on [child], or Esc in the focused input
///   ([FloatingRegistry.handleKey]), closes it; after a press it stays closed
///   until the pointer leaves and comes back.
///
/// Placed like any [FloatingLayer] (kept on screen, flipped when there is
/// no room), and hidden while [child] is scrolled out of view. Only one
/// shows at a time, and none while a popover is open ([FloatingRegistry]).
class HoverTooltip extends StatefulWidget {
  const HoverTooltip({
    super.key,
    required this.content,
    required this.child,
    this.placement = (side: FloatingSide.top, align: FloatingAlign.start),
    this.showDelay = const Duration(milliseconds: 500),
    this.hideDelay = const Duration(milliseconds: 150),
  });

  final WidgetBuilder content;
  final Widget child;
  final FloatingPlacement placement;
  final Duration showDelay;
  final Duration hideDelay;

  /// After a tooltip closes, others show without delay for this long.
  static const warmWindow = Duration(milliseconds: 300);

  @override
  State<HoverTooltip> createState() => _HoverTooltipState();
}

class _HoverTooltipState extends State<HoverTooltip> {
  static DateTime _lastClosedAt = DateTime(0);

  bool _visible = false;
  bool _overChild = false;
  bool _overTooltip = false;
  bool _suppressed = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    if (_visible) _close(rebuild: false);
    super.dispose();
  }

  void _enterChild(PointerEnterEvent event) {
    _overChild = true;
    if (_suppressed || _visible) {
      _timer?.cancel();
      return;
    }
    final warm =
        FloatingRegistry.isTooltipOpen ||
        DateTime.now().difference(_lastClosedAt) < HoverTooltip.warmWindow;
    _timer?.cancel();
    if (warm) {
      _open();
    } else {
      _timer = Timer(widget.showDelay, _open);
    }
  }

  void _exitChild(PointerExitEvent event) {
    _overChild = false;
    _suppressed = false;
    _scheduleClose();
  }

  void _enterTooltip(PointerEnterEvent event) {
    _overTooltip = true;
    _timer?.cancel();
  }

  void _exitTooltip(PointerExitEvent event) {
    _overTooltip = false;
    _scheduleClose();
  }

  void _press(PointerDownEvent event) {
    _suppressed = true;
    _timer?.cancel();
    _close();
  }

  void _open() {
    if (!mounted || !_overChild || _visible) return;
    if (!FloatingRegistry.openTooltip(this, _close)) return;
    setState(() => _visible = true);
  }

  void _scheduleClose() {
    _timer?.cancel();
    if (!_visible) return;
    _timer = Timer(widget.hideDelay, () {
      if (!_overChild && !_overTooltip) _close();
    });
  }

  void _close({bool rebuild = true}) {
    _timer?.cancel();
    if (!_visible) return;
    _visible = false;
    _overTooltip = false;
    _lastClosedAt = DateTime.now();
    FloatingRegistry.closeTooltip(this);
    if (rebuild && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return FloatingLayer(
      visible: _visible,
      placement: widget.placement,
      enterDuration: const Duration(milliseconds: 100),
      exitDuration: const Duration(milliseconds: 80),
      builder: (context) => MouseRegion(
        onEnter: _enterTooltip,
        onExit: _exitTooltip,
        child: TooltipSurface(child: widget.content(context)),
      ),
      child: MouseRegion(
        onEnter: _enterChild,
        onExit: _exitChild,
        child: Listener(onPointerDown: _press, child: widget.child),
      ),
    );
  }
}

/// The tooltip's panel: the workbench hover's box ([IdeHoverBox]), with
/// selectable text.
class TooltipSurface extends StatelessWidget {
  const TooltipSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: IdeHoverBox(child: SelectionArea(child: child)),
  );
}
