import 'package:flutter/material.dart';

import '../../ide/ide_hover.dart';
import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../chat_models.dart';
import '../widgets/hover_builder.dart';

/// The messages sent while the agent works, docked above the composer
/// until their turn: each to be dragged into another place, taken back to
/// edit, sent at once (the turn running stopped for it), or taken back.
class QueuePanel extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderStrong),
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
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 150),
            child: ReorderableListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
              buildDefaultDragHandles: false,
              proxyDecorator: (child, index, animation) => Material(
                color: AppColors.surface,
                elevation: 3,
                borderRadius: BorderRadius.circular(5),
                child: child,
              ),
              // The index given is where it goes, the one it came from
              // already taken out.
              onReorderItem: (oldIndex, newIndex) =>
                  onMove(messages[oldIndex].$1, newIndex),
              children: [
                for (var i = 0; i < messages.length; i++)
                  _QueuedRow(
                    key: ValueKey(messages[i].$1),
                    index: i,
                    message: messages[i].$2,
                    onEdit: () => onEdit(messages[i].$1),
                    onSendNow: () => onSendNow(messages[i].$1),
                    onRemove: () => onRemove(messages[i].$1),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QueuedRow extends StatelessWidget {
  const _QueuedRow({
    super.key,
    required this.index,
    required this.message,
    required this.onEdit,
    required this.onSendNow,
    required this.onRemove,
  });

  /// Where it is in the queue.
  final int index;
  final UserMessageItem message;
  final VoidCallback onEdit;
  final VoidCallback onSendNow;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = message.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return HoverBuilder(
      builder: (context, hovered) => _draggable(
        context,
        Container(
          padding: const EdgeInsets.fromLTRB(4, 3, 4, 3),
          decoration: BoxDecoration(
            color: hovered ? AppColors.hover : null,
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
      ),
    );
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
                color: hovered ? AppColors.hover : null,
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
