import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/cursor_theme.dart';

/// Inline editor for a title, with it all selected: Enter or leaving it
/// saves, Esc cancels.
class InlineRenameField extends StatefulWidget {
  const InlineRenameField({
    super.key,
    required this.initial,
    required this.onDone,
    this.style = const TextStyle(
      color: CursorColors.textPrimary,
      fontSize: 12.5,
    ),
  });

  final String initial;

  /// The new text, or null when cancelled.
  final ValueChanged<String?> onDone;
  final TextStyle style;

  @override
  State<InlineRenameField> createState() => _InlineRenameFieldState();
}

class _InlineRenameFieldState extends State<InlineRenameField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial)
        ..selection = TextSelection(
          baseOffset: 0,
          extentOffset: widget.initial.length,
        );
  final FocusNode _focus = FocusNode();
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _finish(_controller.text);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _finish(String? title) {
    if (_done) return;
    _done = true;
    widget.onDone(title);
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => _finish(null),
      },
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        onSubmitted: _finish,
        style: widget.style,
        cursorColor: CursorColors.text,
        cursorHeight: 14,
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          filled: true,
          fillColor: CursorColors.code,
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: CursorColors.accent),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: CursorColors.accent),
          ),
        ),
      ),
    );
  }
}
