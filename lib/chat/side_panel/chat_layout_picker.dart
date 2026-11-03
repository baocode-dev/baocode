// Layout: where the agent window's sidebar, conversations and side panel
// are (see ChatLayout), picked from a little window of their pictures.

import 'package:flutter/material.dart';

import '../../ide/ide_menu.dart' show IdeMenuColors;
import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../workspace/islands.dart';
import 'side_panel_controller.dart';

extension ChatLayoutLabel on ChatLayout {
  /// Its parts from the left, named.
  String label(BuildContext context) {
    final l10n = context.l10n;
    return switch (this) {
      ChatLayout.sidebarChatPanel => l10n.chatLayoutSidebarChatPanel,
      ChatLayout.sidebarPanelChat => l10n.chatLayoutSidebarPanelChat,
      ChatLayout.panelChatSidebar => l10n.chatLayoutPanelChatSidebar,
      ChatLayout.chatPanelSidebar => l10n.chatLayoutChatPanelSidebar,
    };
  }

  /// Its parts from the left.
  List<ChatLayoutPart> get parts => switch (this) {
    ChatLayout.sidebarChatPanel => const [
      ChatLayoutPart.sidebar,
      ChatLayoutPart.chat,
      ChatLayoutPart.panel,
    ],
    ChatLayout.sidebarPanelChat => const [
      ChatLayoutPart.sidebar,
      ChatLayoutPart.panel,
      ChatLayoutPart.chat,
    ],
    ChatLayout.panelChatSidebar => const [
      ChatLayoutPart.panel,
      ChatLayoutPart.chat,
      ChatLayoutPart.sidebar,
    ],
    ChatLayout.chatPanelSidebar => const [
      ChatLayoutPart.chat,
      ChatLayoutPart.panel,
      ChatLayoutPart.sidebar,
    ],
  };
}

enum ChatLayoutPart { sidebar, chat, panel }

/// Shows the layouts below [anchor] (global), its right edge on the
/// anchor's; the one picked is [panel]'s at once.
Future<void> showChatLayoutPicker(
  BuildContext context, {
  required Rect anchor,
  required AgentSidePanel panel,
}) {
  final navigator = Navigator.of(context);
  final overlay = navigator.overlay!.context.findRenderObject()! as RenderBox;
  final origin = Rect.fromPoints(
    overlay.globalToLocal(anchor.topLeft),
    overlay.globalToLocal(anchor.bottomRight),
  );
  return navigator.push(
    _PickerRoute(
      origin: origin,
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      barrierLabel: context.l10n.commonDismiss,
      panel: panel,
    ),
  );
}

class _PickerRoute extends PopupRoute<void> {
  _PickerRoute({
    required this.origin,
    required this.capturedThemes,
    required this.barrierLabel,
    required this.panel,
  });

  final Rect origin;
  final CapturedThemes capturedThemes;
  final AgentSidePanel panel;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  final String barrierLabel;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 83);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => capturedThemes.wrap(
    FadeTransition(
      opacity: animation,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const margin = 8.0;
          final right = (constraints.maxWidth - origin.right).clamp(
            margin,
            constraints.maxWidth - margin - ChatLayoutPicker.width,
          );
          return Stack(
            children: [
              Positioned(
                right: right,
                top: origin.bottom + 4,
                width: ChatLayoutPicker.width,
                child: ChatLayoutPicker(
                  panel: panel,
                  onPicked: () {
                    if (isCurrent) Navigator.of(context).pop();
                  },
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

/// The layouts, two by two: each its picture and its parts' names, the
/// one in use selected.
class ChatLayoutPicker extends StatelessWidget {
  const ChatLayoutPicker({super.key, required this.panel, this.onPicked});

  final AgentSidePanel panel;
  final VoidCallback? onPicked;

  static const width = 280.0;

  @override
  Widget build(BuildContext context) {
    final layouts = ChatLayout.values;
    Widget tile(ChatLayout layout) => Expanded(
      child: _LayoutTile(
        layout: layout,
        selected: panel.layout == layout,
        onTap: () {
          panel.layout = layout;
          onPicked?.call();
        },
      ),
    );
    return Material(
      type: MaterialType.transparency,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        decoration: BoxDecoration(
          color: IdeMenuColors.background,
          borderRadius: BorderRadius.circular(Islands.controlRadius + 2),
          border: Border.all(color: IdeMenuColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Text(
                context.l10n.chatLayout,
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ),
            for (var row = 0; row < layouts.length; row += 2) ...[
              if (row > 0) const SizedBox(height: 6),
              Row(
                children: [
                  tile(layouts[row]),
                  const SizedBox(width: 6),
                  tile(layouts[row + 1]),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LayoutTile extends StatefulWidget {
  const _LayoutTile({
    required this.layout,
    required this.selected,
    required this.onTap,
  });

  final ChatLayout layout;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_LayoutTile> createState() => _LayoutTileState();
}

class _LayoutTileState extends State<_LayoutTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final foreground = selected || _hover
        ? IdeMenuColors.foreground
        : AppColors.textMuted;
    return Semantics(
      button: true,
      selected: selected,
      label: widget.layout.label(context),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
            decoration: BoxDecoration(
              color: Islands.segmentFill(selected: selected, hovered: _hover),
              borderRadius: BorderRadius.circular(Islands.controlRadius),
              border: Border.all(
                color: selected ? AppColors.accent : Colors.transparent,
              ),
            ),
            child: Column(
              children: [
                ChatLayoutIcon(
                  widget.layout,
                  size: const Size(56, 34),
                  color: foreground,
                ),
                const SizedBox(height: 6),
                Text(
                  widget.layout.label(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: foreground),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// [layout]'s picture: its parts from the left, the sidebar solid and
/// narrow, the side panel shaded, the conversations outlined and widest.
class ChatLayoutIcon extends StatelessWidget {
  const ChatLayoutIcon(
    this.layout, {
    super.key,
    this.size = const Size(16, 16),
    required this.color,
  });

  final ChatLayout layout;
  final Size size;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: size, painter: _LayoutPainter(layout.parts, color));
}

class _LayoutPainter extends CustomPainter {
  _LayoutPainter(this.parts, this.color);

  final List<ChatLayoutPart> parts;
  final Color color;

  /// Of the width, each part's: the conversations take what is left.
  static const _sidebar = .22;
  static const _panel = .3;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width >= 32 ? 1.5 : 1.0;
    final gap = size.width >= 32 ? 3.0 : 1.5;
    final radius = Radius.circular(size.width >= 32 ? 3 : 1.5);
    final room = size.width - stroke - 2 * gap;
    final widths = {
      ChatLayoutPart.sidebar: room * _sidebar,
      ChatLayoutPart.panel: room * _panel,
      ChatLayoutPart.chat: room * (1 - _sidebar - _panel),
    };
    var x = stroke / 2;
    for (final part in parts) {
      final width = widths[part]!;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, stroke / 2, width, size.height - stroke),
        radius,
      );
      switch (part) {
        case ChatLayoutPart.sidebar:
          canvas.drawRRect(
            rect,
            Paint()..color = color.withValues(alpha: color.a * .85),
          );
        case ChatLayoutPart.panel:
          canvas.drawRRect(
            rect,
            Paint()..color = color.withValues(alpha: color.a * .3),
          );
          canvas.drawRRect(
            rect,
            Paint()
              ..color = color
              ..style = PaintingStyle.stroke
              ..strokeWidth = stroke,
          );
        case ChatLayoutPart.chat:
          canvas.drawRRect(
            rect,
            Paint()
              ..color = color
              ..style = PaintingStyle.stroke
              ..strokeWidth = stroke,
          );
      }
      x += width + gap;
    }
  }

  @override
  bool shouldRepaint(_LayoutPainter old) =>
      old.color != color || old.parts != parts;
}
