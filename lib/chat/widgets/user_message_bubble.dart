import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/cursor_theme.dart';
import '../composer/composer_embeds.dart';
import 'assistant_text.dart';
import 'hover_builder.dart';

/// A sent user message, echoed as text: `@mentions` and a leading
/// `/command` in it show as the same inline tags as in the composer.
/// Clicking it opens it for editing when [onEdit] is set; dragging still
/// selects text.
///
/// The click is read from raw pointer events rather than a tap recognizer:
/// a recognizer would compete with the history's text selection for the
/// same press, and win Shift+clicks meant to extend the selection.
class UserMessageBubble extends StatefulWidget {
  const UserMessageBubble({super.key, required this.text, this.onEdit});

  final String text;
  final VoidCallback? onEdit;

  @override
  State<UserMessageBubble> createState() => _UserMessageBubbleState();
}

const _messageStyle = TextStyle(
  color: CursorColors.textPrimary,
  fontSize: 13.5,
  height: 1.5,
  // Centers glyphs in the line box, which the inline tags center on.
  leadingDistribution: TextLeadingDistribution.even,
);

TextSpan _messageSpan(String text) {
  final ops = composerDeltaFromText(text).toList();
  return TextSpan(
    style: _messageStyle,
    children: [
      for (final (i, op) in ops.indexed)
        switch (op.data) {
          // The document's closing newline is not part of the message.
          final String data when i == ops.length - 1 => inlineCodeSpan(
            data.substring(0, data.length - 1),
            _messageStyle,
          ),
          final String data => inlineCodeSpan(data, _messageStyle),
          final Map<dynamic, dynamic> data => ComposerTokenChip.span(
            data[ComposerTokenEmbed.type],
            _messageStyle,
          ),
          _ => const TextSpan(),
        },
    ],
  );
}

class _UserMessageBubbleState extends State<UserMessageBubble> {
  Offset? _pressedAt;

  void _handleDown(PointerDownEvent event) {
    final primary =
        event.kind != PointerDeviceKind.mouse ||
        event.buttons == kPrimaryMouseButton;
    _pressedAt = primary && !HardwareKeyboard.instance.isShiftPressed
        ? event.position
        : null;
  }

  void _handleUp(PointerUpEvent event) {
    final pressedAt = _pressedAt;
    _pressedAt = null;
    if (pressedAt == null) return;
    // A click, not the end of a drag selection.
    if ((event.position - pressedAt).distance <= kTouchSlop) {
      widget.onEdit?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    final onEdit = widget.onEdit;
    return HoverBuilder(
      builder: (context, hovered) => Listener(
        onPointerDown: _handleDown,
        onPointerUp: _handleUp,
        onPointerCancel: (_) => _pressedAt = null,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
          decoration: BoxDecoration(
            color: CursorColors.surfaceRaised,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: hovered && onEdit != null
                  ? const Color(0xFF4D4D4D)
                  : CursorColors.borderStrong,
            ),
          ),
          child: Text.rich(_messageSpan(text)),
        ),
      ),
    );
  }
}
