import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderFlex;
import 'package:flutter/semantics.dart' show CustomSemanticsAction;

import '../../ide/ide_hover.dart';
import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../chat_models.dart';
import '../widgets/hover_builder.dart';

/// The messages sent while the agent works, docked above the composer
/// until their turn: each to be dragged into another place, taken back to
/// edit, sent at once (the turn running stopped for it), or taken back.
class QueuePanel extends StatefulWidget {
  const QueuePanel({
    super.key,
    required this.messages,
    required this.onMove,
    required this.onEdit,
    required this.onSendNow,
    required this.onRemove,
  });

  /// With their ids, the next first.
  final List<(String, UserMessageItem)> messages;

  /// Puts the message [id] at [index] among those queued.
  final void Function(String id, int index) onMove;
  final ValueChanged<String> onEdit;
  final ValueChanged<String> onSendNow;
  final ValueChanged<String> onRemove;

  @override
  State<QueuePanel> createState() => _QueuePanelState();
}

class _QueuePanelState extends State<QueuePanel> {
  final _viewportKey = GlobalKey();
  final _rowsKey = GlobalKey();
  final _scroll = ScrollController();
  final _proxy = OverlayPortalController()..show();
  Timer? _autoScroll;
  _QueueDrag? _drag;

  RenderBox get _viewport =>
      _viewportKey.currentContext!.findRenderObject()! as RenderBox;
  List<RenderBox> get _rows =>
      (_rowsKey.currentContext!.findRenderObject()! as RenderFlex)
          .getChildrenAsList();

  @override
  void didUpdateWidget(QueuePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The agent can take messages off the queue mid-drag. Don't apply an
    // index picked against a different order.
    if (_drag != null &&
        (oldWidget.messages.length != widget.messages.length ||
            widget.messages.indexed.any(
              (entry) => entry.$2.$1 != oldWidget.messages[entry.$1].$1,
            ))) {
      _clearDrag();
    }
  }

  @override
  void dispose() {
    _clearDrag();
    _scroll.dispose();
    super.dispose();
  }

  void _clearDrag() {
    _autoScroll?.cancel();
    _autoScroll = null;
    _drag = null;
  }

  Drag? _startDrag(int index, Offset position) {
    if (_drag != null) return null;
    final viewport = _viewport;
    final row = _rows[index];
    final rect = row.localToGlobal(Offset.zero, ancestor: viewport) & row.size;
    final anchor = viewport.globalToLocal(position).dy - rect.top;
    final drag = _QueueDrag(this, index, rect, position, anchor);
    setState(() => _drag = drag);
    return drag;
  }

  void _updateDrag(_QueueDrag drag) {
    if (_drag != drag) return;
    final viewport = _viewport;
    // Keep both the proxy and the drop geometry in viewport units. Flutter's
    // reorderable list mixes global pointer offsets with local row bounds.
    final top = viewport.globalToLocal(drag.position).dy - drag.anchor;
    final bottom = top + drag.rect.height;
    final rows = _rows;
    var destination = 0;
    for (var i = 0; i < rows.length; i++) {
      if (i == drag.from) continue;
      final row = rows[i];
      final middle = row
          .localToGlobal(row.size.center(Offset.zero), ancestor: viewport)
          .dy;
      // The leading edge crosses the neighbor's midpoint. Measure the
      // unshifted slots so the gap animation can't change the result.
      if ((i < drag.from ? top : bottom) < middle) break;
      destination++;
    }
    setState(() {
      drag.top = top;
      drag.to = destination;
    });
    if (_scrollStep(drag) != 0) {
      _autoScroll ??= Timer.periodic(
        const Duration(milliseconds: 16),
        (_) => _scrollDrag(drag),
      );
    }
  }

  double _scrollStep(_QueueDrag drag) {
    final position = _scroll.position;
    const edge = 8.0;
    if (drag.top < edge && position.pixels > position.minScrollExtent) {
      return -6;
    }
    if (drag.top + drag.rect.height > position.viewportDimension - edge &&
        position.pixels < position.maxScrollExtent) {
      return 6;
    }
    return 0;
  }

  void _scrollDrag(_QueueDrag drag) {
    final step = _scrollStep(drag);
    if (step == 0) {
      _autoScroll?.cancel();
      _autoScroll = null;
      return;
    }
    final position = _scroll.position;
    _scroll.jumpTo(
      (_scroll.offset + step).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
    _updateDrag(drag);
  }

  void _finishDrag(_QueueDrag drag, {required bool drop}) {
    if (_drag != drag) return;
    setState(_clearDrag);
    if (drop && drag.from != drag.to) {
      widget.onMove(widget.messages[drag.from].$1, drag.to);
    }
  }

  Widget _queuedRow(int index) {
    final (id, message) = widget.messages[index];
    return _QueuedRow(
      message: message,
      onEdit: () => widget.onEdit(id),
      onSendNow: () => widget.onSendNow(id),
      onRemove: () => widget.onRemove(id),
    );
  }

  Widget _buildRow(int index) {
    final id = widget.messages[index].$1;
    final last = widget.messages.length - 1;
    final labels = WidgetsLocalizations.of(context);
    final drag = _drag;
    var shift = 0.0;
    if (drag != null) {
      if (index > drag.from && index <= drag.to) shift = -drag.rect.height;
      if (index < drag.from && index >= drag.to) shift = drag.rect.height;
    }
    final child = AnimatedContainer(
      duration: drag == null
          ? Duration.zero
          : const Duration(milliseconds: 150),
      transform: Matrix4.translationValues(0, shift, 0),
      child: Visibility(
        visible: drag?.from != index,
        maintainSize: true,
        maintainAnimation: true,
        maintainState: true,
        child: _queuedRow(index),
      ),
    );
    final delayed = switch (Theme.of(context).platform) {
      TargetPlatform.iOS ||
      TargetPlatform.android ||
      TargetPlatform.fuchsia => true,
      _ => false,
    };
    void configure(MultiDragGestureRecognizer recognizer) {
      recognizer
        ..gestureSettings = MediaQuery.maybeGestureSettingsOf(context)
        ..onStart = (position) => _startDrag(index, position);
    }

    return Semantics(
      key: ValueKey(id),
      customSemanticsActions: {
        if (index > 0) ...{
          CustomSemanticsAction(label: labels.reorderItemToStart): () =>
              widget.onMove(id, 0),
          CustomSemanticsAction(label: labels.reorderItemUp): () =>
              widget.onMove(id, index - 1),
        },
        if (index < last) ...{
          CustomSemanticsAction(label: labels.reorderItemDown): () =>
              widget.onMove(id, index + 1),
          CustomSemanticsAction(label: labels.reorderItemToEnd): () =>
              widget.onMove(id, last),
        },
      },
      child: RawGestureDetector(
        gestures: {
          if (last > 0)
            if (delayed)
              DelayedMultiDragGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    DelayedMultiDragGestureRecognizer
                  >(DelayedMultiDragGestureRecognizer.new, configure)
            else
              ImmediateMultiDragGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    ImmediateMultiDragGestureRecognizer
                  >(ImmediateMultiDragGestureRecognizer.new, configure),
        },
        child: child,
      ),
    );
  }

  Widget _buildProxy(BuildContext context, OverlayChildLayoutInfo info) {
    final drag = _drag;
    if (drag == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: ExcludeSemantics(
        child: Transform(
          transform: info.childPaintTransform,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fromRect(
                rect: drag.rect.translate(0, drag.top - drag.rect.top),
                child: Material(
                  color: AppColors.surface,
                  elevation: 3,
                  borderRadius: BorderRadius.circular(5),
                  child: _queuedRow(drag.from),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.bubbleFill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.bubbleBorder()),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 2),
            child: Row(
              children: [
                Icon(
                  Icons.schedule_rounded,
                  size: 13,
                  color: AppColors.textMuted,
                ),
                const SizedBox(width: 6),
                Text(
                  l10n.queuedMessages(widget.messages.length),
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 150),
            child: OverlayPortal.overlayChildLayoutBuilder(
              controller: _proxy,
              overlayChildBuilder: _buildProxy,
              child: SingleChildScrollView(
                key: _viewportKey,
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                child: Column(
                  key: _rowsKey,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: List.generate(widget.messages.length, _buildRow),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QueuedRow extends StatelessWidget {
  const _QueuedRow({
    required this.message,
    required this.onEdit,
    required this.onSendNow,
    required this.onRemove,
  });

  final UserMessageItem message;
  final VoidCallback onEdit;
  final VoidCallback onSendNow;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = message.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return HoverBuilder(
      builder: (context, hovered) => Container(
        padding: const EdgeInsets.fromLTRB(4, 3, 4, 3),
        decoration: BoxDecoration(
          color: hovered ? AppColors.bubbleHover : null,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          children: [
            // The handle says the row drags; the whole row does.
            MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: Opacity(
                opacity: hovered ? 0.9 : 0.45,
                child: Icon(
                  Codicons.gripper,
                  size: 13,
                  color: AppColors.textMuted,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              // A click takes it back to edit, as the pencil does.
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onEdit,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Text(
                    [
                      if (text.isNotEmpty) text,
                      if (message.images.isNotEmpty)
                        l10n.queuedImages(message.images.length),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.text, fontSize: 12.5),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            _Action(
              icon: Codicons.edit,
              tooltip: l10n.queuedEdit,
              onTap: onEdit,
            ),
            _Action(
              icon: Codicons.arrowUp,
              tooltip: l10n.queuedSendNow,
              onTap: onSendNow,
            ),
            _Action(
              icon: Codicons.trash,
              tooltip: l10n.queuedRemove,
              onTap: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}

class _QueueDrag extends Drag {
  _QueueDrag(this.panel, this.from, this.rect, this.position, this.anchor)
    : top = rect.top,
      to = from;

  final _QueuePanelState panel;
  final int from;
  final Rect rect;
  final double anchor;
  Offset position;
  double top;
  int to;

  @override
  void update(DragUpdateDetails details) {
    position += details.delta;
    panel._updateDrag(this);
  }

  @override
  void end(DragEndDetails details) => panel._finishDrag(this, drop: true);

  @override
  void cancel() => panel._finishDrag(this, drop: false);
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.tooltip, this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IdeHover(
      message: tooltip,
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => Semantics(
          button: true,
          label: tooltip,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.all(3),
              margin: const EdgeInsets.only(left: 2),
              decoration: BoxDecoration(
                color: hovered ? AppColors.bubbleHover : null,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(icon, size: 14, color: AppColors.textMuted),
            ),
          ),
        ),
      ),
    );
  }
}
