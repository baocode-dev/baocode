import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../ide/ide_hover.dart';
import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../../theme/ui_zoom.dart';
import '../chat_models.dart';
import '../widgets/hover_builder.dart';

/// The messages sent while the agent works, docked above the composer
/// until their turn: each to be clicked to preview in full, dragged into
/// another place, taken back to edit, sent at once (the turn running stopped
/// for it), or taken back.
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
  final Set<String> _expanded = {};

  @override
  void didUpdateWidget(QueuePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_expanded.isNotEmpty) {
      final ids = {for (final (id, _) in widget.messages) id};
      _expanded.removeWhere((id) => !ids.contains(id));
    }
  }

  void _toggle(String id) {
    setState(() {
      if (!_expanded.remove(id)) _expanded.add(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final messages = widget.messages;
    // UiZoom.zoomed multiplies the media ratio by the window's UI scale.
    final viewRatio = View.of(context).devicePixelRatio;
    final zoom = MediaQuery.devicePixelRatioOf(context) / viewRatio;
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
                  l10n.queuedMessages(messages.length),
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          _QueueViewport(
            zoom: zoom,
            maxHeight: _expanded.isEmpty ? 150 : 280,
            child: ReorderableListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 4) * zoom,
              buildDefaultDragHandles: false,
              proxyDecorator: (child, index, animation) {
                final proxy = Material(
                  color: AppColors.surface,
                  elevation: 3,
                  borderRadius: BorderRadius.circular(5 * zoom),
                  child: child,
                );
                return zoom == 1
                    ? proxy
                    : ExcludeSemantics(
                        child: _QueueDragProxy(zoom: zoom, child: proxy),
                      );
              },
              // The index given is where it goes, the one it came from
              // already taken out.
              onReorderItem: (oldIndex, newIndex) =>
                  widget.onMove(messages[oldIndex].$1, newIndex),
              children: [
                for (var i = 0; i < messages.length; i++)
                  _QueuedRow(
                    key: ValueKey(messages[i].$1),
                    index: i,
                    zoom: zoom,
                    message: messages[i].$2,
                    expanded: _expanded.contains(messages[i].$1),
                    onToggle: () => _toggle(messages[i].$1),
                    onEdit: () => widget.onEdit(messages[i].$1),
                    onSendNow: () => widget.onSendNow(messages[i].$1),
                    onRemove: () => widget.onRemove(messages[i].$1),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QueueViewport extends StatelessWidget {
  const _QueueViewport({
    required this.zoom,
    required this.maxHeight,
    required this.child,
  });

  final double zoom;
  final double maxHeight;
  final Widget child;

  // Flutter compares window pointer positions with the rows' local sizes.
  // Lay out the list in window units, but draw its rows at the UI zoom.
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(maxHeight: maxHeight),
    child: UiZoom(scale: 1 / zoom, child: child),
  );
}

class _QueueDragProxy extends SingleChildRenderObjectWidget {
  const _QueueDragProxy({required this.zoom, required super.child});

  final double zoom;

  @override
  _RenderQueueDragProxy createRenderObject(BuildContext context) =>
      _RenderQueueDragProxy(
        Overlay.of(context).context.findRenderObject()! as RenderBox,
        zoom,
      );

  @override
  void updateRenderObject(BuildContext context, _RenderQueueDragProxy proxy) {
    proxy.zoom = zoom;
    proxy.markNeedsPaint();
  }
}

class _RenderQueueDragProxy extends RenderProxyBox {
  _RenderQueueDragProxy(this.overlay, this.zoom);

  final RenderBox overlay;
  double zoom;

  // Flutter lays out the proxy in window units, but the overlay treats them
  // as zoomed units. Undo that zoom around the overlay's origin, not the row's.
  Matrix4 get _correction {
    final origin = localToGlobal(Offset.zero, ancestor: overlay);
    final shift = origin / zoom - origin;
    return Matrix4.diagonal3Values(1 / zoom, 1 / zoom, 1)
      ..setTranslationRaw(shift.dx, shift.dy, 0);
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      context.pushTransform(needsCompositing, offset, _correction, super.paint);

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) =>
      transform.multiply(_correction);

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) => false;
}

class _QueuedRow extends StatelessWidget {
  const _QueuedRow({
    super.key,
    required this.index,
    required this.zoom,
    required this.message,
    required this.expanded,
    required this.onToggle,
    required this.onEdit,
    required this.onSendNow,
    required this.onRemove,
  });

  /// Where it is in the queue.
  final int index;
  final double zoom;
  final UserMessageItem message;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onSendNow;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final fullText = message.text.trim();
    final summary = fullText.replaceAll(RegExp(r'\s+'), ' ');
    final imagesLabel = message.images.isNotEmpty
        ? l10n.queuedImages(message.images.length)
        : null;
    final collapsedLabel = [
      if (summary.isNotEmpty) summary,
      ?imagesLabel,
    ].join(' · ');
    final row = HoverBuilder(
      builder: (context, hovered) => _draggable(
        context,
        Container(
          padding: const EdgeInsets.fromLTRB(4, 3, 4, 3),
          decoration: BoxDecoration(
            color: hovered || expanded ? AppColors.bubbleHover : null,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Row(
            crossAxisAlignment: expanded
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: [
              // The handle says the row drags; the whole row does.
              Padding(
                padding: EdgeInsets.only(top: expanded ? 3 : 0),
                child: MouseRegion(
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
              ),
              const SizedBox(width: 4),
              Expanded(
                // A click previews the full message in place; editing is via
                // the pencil button so tapping never pulls it out of order.
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onToggle,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: expanded
                        ? ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 160),
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (fullText.isNotEmpty)
                                    Text(
                                      fullText,
                                      style: TextStyle(
                                        color: AppColors.text,
                                        fontSize: 12.5,
                                        height: 1.4,
                                      ),
                                    ),
                                  if (imagesLabel != null) ...[
                                    if (fullText.isNotEmpty)
                                      const SizedBox(height: 4),
                                    Text(
                                      imagesLabel,
                                      style: TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 11.5,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          )
                        : Text(
                            collapsedLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.text,
                              fontSize: 12.5,
                            ),
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
      ),
    );
    return UiZoom(scale: zoom, child: row);
  }

  /// Drags the row at once with a mouse; after a long press with a finger,
  /// where dragging would otherwise scroll the list.
  Widget _draggable(BuildContext context, Widget child) => switch (Theme.of(
    context,
  ).platform) {
    TargetPlatform.iOS || TargetPlatform.android || TargetPlatform.fuchsia =>
      ReorderableDelayedDragStartListener(index: index, child: child),
    _ => ReorderableDragStartListener(index: index, child: child),
  };
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
