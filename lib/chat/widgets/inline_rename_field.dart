import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import '../../theme/workbench_theme.dart' show themeColors;

/// Inline editor for a title, with it all selected: Enter or leaving it
/// saves, Esc cancels.
class InlineRenameField extends StatefulWidget {
  const InlineRenameField({
    super.key,
    required this.initial,
    required this.onDone,
    this.style,
  });

  final String initial;

  /// The new text, or null when cancelled.
  final ValueChanged<String?> onDone;

  /// [AppColors.textPrimary] at 12.5 when null.
  final TextStyle? style;

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
    // An input box, focused, as upstream's inline rename.
    final colors = themeColors;
    final border = OutlineInputBorder(
      borderSide: BorderSide(color: colors['focusBorder']),
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => _finish(null),
      },
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        onSubmitted: _finish,
        style:
            widget.style ??
            TextStyle(color: AppColors.textPrimary, fontSize: 12.5),
        cursorColor: AppColors.text,
        cursorHeight: 14,
        decoration: InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          filled: true,
          fillColor: colors['input.background'],
          enabledBorder: border,
          focusedBorder: border,
        ),
      ),
    );
  }
}
