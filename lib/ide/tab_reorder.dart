import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../theme/workbench_theme.dart' show themeColors;

/// A strip whose tabs are dragged to order them, as VS Code's editor tabs:
/// where the one dragged would go shows (see [dropSpot]), and it goes
/// there when let go. Followed by the pointer's own events, so a tab that
/// is also dragged elsewhere (a file's, onto the chat's composer) is both:
/// off the strip, it goes nowhere among the tabs.
mixin TabReorder<W extends StatefulWidget, T extends Object> on State<W> {
  /// The strip's scrolling: near an end, the tabs scroll on.
  ScrollController get tabScroll;

  /// The tabs, in their order.
  List<T> get reorderedTabs;

  /// Where [tab] is built, to tell where the pointer is among the tabs.
  BuildContext? tabContext(T tab);

  /// [tab] dragged to [index] among the tabs (in their order without it).
  void moveTab(T tab, int index);

  /// Moved this far, a press on a tab drags it (rather than selecting it).
  static const threshold = 4.0;

  /// The tab dragged.
  T? get draggedTab => _dragged;
  T? _dragged;

  /// Where it would go: before the tab at that index, or after the last;
  /// none where it is already, or off the strip.
  int? get dropSpot => _spot;
  int? _spot;

  int? _pointer;
  T? _pressed;
  Offset _origin = Offset.zero;

  /// [child], [tab]'s, dragged among the others.
  Widget reorderable(T tab, Widget child) => Listener(
    onPointerDown: (event) {
      if (_pointer != null || event.buttons != kPrimaryButton) return;
      _pointer = event.pointer;
      _pressed = tab;
      _origin = event.position;
    },
    onPointerMove: (event) {
      if (event.pointer != _pointer) return;
      if (_dragged == null) {
        if ((event.position - _origin).distance <= threshold) return;
        if (reorderedTabs.length < 2) return;
        setState(() => _dragged = _pressed);
      }
      _moveTo(event.position);
    },
    onPointerUp: (event) {
      if (event.pointer == _pointer) _end(drop: true);
    },
    onPointerCancel: (event) {
      if (event.pointer == _pointer) _end(drop: false);
    },
    child: child,
  );

  void _moveTo(Offset position) {
    final tabs = reorderedTabs;
    final dragged = _dragged;
    if (dragged == null) return;
    int? spot;
    final viewport = tabScroll.hasClients
        ? tabScroll.position.context.storageContext.findRenderObject()
        : null;
    final local = viewport is RenderBox
        ? viewport.globalToLocal(position)
        : null;
    final strip = viewport is RenderBox ? Offset.zero & viewport.size : null;
    // A little beside the strip still is on it; further, the drag is
    // elsewhere (a file's, to the composer).
    if (local != null && strip != null && strip.inflate(12).contains(local)) {
      final step = local.dx < 24
          ? -8.0
          : (local.dx > strip.width - 24 ? 8.0 : 0.0);
      if (step != 0) {
        final scrolled = tabScroll.position;
        tabScroll.jumpTo(
          (scrolled.pixels + step).clamp(
            scrolled.minScrollExtent,
            scrolled.maxScrollExtent,
          ),
        );
      }
      var at = tabs.length;
      for (final (i, tab) in tabs.indexed) {
        final box = tabContext(tab)?.findRenderObject();
        if (box is! RenderBox || !box.attached) continue;
        final middle = box.localToGlobal(box.size.center(Offset.zero)).dx;
        if (position.dx < middle) {
          at = i;
          break;
        }
      }
      final from = tabs.indexOf(dragged);
      spot = at == from || at == from + 1 ? null : at;
    }
    if (spot != _spot) setState(() => _spot = spot);
  }

  void _end({required bool drop}) {
    final (tab, at) = (_dragged, _spot);
    _pointer = null;
    _pressed = null;
    if (tab != null) setState(() => _dragged = _spot = null);
    if (!drop || tab == null || at == null) return;
    final from = reorderedTabs.indexOf(tab);
    if (from < 0) return;
    moveTab(tab, at > from ? at - 1 : at);
  }
}

/// Where a dragged tab would go: a line between tabs, taking no room.
class TabDropLine extends StatelessWidget {
  const TabDropLine({super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 0,
    height: 22,
    child: OverflowBox(
      maxWidth: 2,
      child: Container(
        width: 2,
        decoration: BoxDecoration(
          color: themeColors['focusBorder'],
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    ),
  );
}
