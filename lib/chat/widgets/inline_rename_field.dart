import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ide/ide_hover.dart';
import '../../ide/ide_menu.dart' show IdeMenuColors;
import '../../ide/ide_spinning.dart';
import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../../theme/workbench_theme.dart' show themeColors;

/// Inline editor for a title, with it all selected: Enter or leaving it
/// saves, Esc cancels.
///
/// Given [suggestions], ↓ opens a list of them under it, filtered by what
/// is typed: ↑ and ↓ go through it, Enter or a click puts the one picked in
/// the field, to be saved as any text is. Given [onSummarize], a button at
/// the field's end puts a title summing it up there the same way.
class InlineRenameField extends StatefulWidget {
  const InlineRenameField({
    super.key,
    required this.initial,
    required this.onDone,
    this.style,
    this.suggestions = const [],
    this.onSummarize,
  });

  final String initial;

  /// The new text, or null when cancelled.
  final ValueChanged<String?> onDone;

  /// [AppColors.textPrimary] at 12.5 when null.
  final TextStyle? style;

  /// Titles to pick from, in order (e.g. what the user asked, latest
  /// first).
  final List<String> suggestions;

  /// A new title summing it up, by the button at the field's end; null
  /// when none could be had.
  final Future<String?> Function()? onSummarize;

  @override
  State<InlineRenameField> createState() => _InlineRenameFieldState();
}

class _InlineRenameFieldState extends State<InlineRenameField> {
  /// The most suggestions the list shows.
  static const _shown = 10;

  late final TextEditingController _controller =
      TextEditingController(text: widget.initial)
        ..selection = TextSelection(
          baseOffset: 0,
          extentOffset: widget.initial.length,
        );
  final FocusNode _focus = FocusNode();
  final LayerLink _link = LayerLink();
  final OverlayPortalController _portal = OverlayPortalController();
  bool _done = false;

  /// Whether the list is wanted: once ↓ is pressed, until one of it is
  /// picked. Not at first: a rename does not pop it up by itself.
  bool _open = false;

  /// What filters the suggestions: none until the text is edited (the
  /// title it starts with would leave none).
  String? _query;

  /// The entry ↑ and ↓ went to, or the pointer is over.
  int? _highlight;

  bool _summarizing = false;
  bool _summaryFailed = false;

  bool get _hasList => widget.suggestions.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _finish(_controller.text);
      _syncList();
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

  /// The suggestions shown: those with the text typed, the current title
  /// aside.
  List<String> get _matches {
    final query = _query?.trim().toLowerCase() ?? '';
    return widget.suggestions
        .where(
          (title) =>
              title != widget.initial &&
              (query.isEmpty || title.toLowerCase().contains(query)),
        )
        .take(_shown)
        .toList();
  }

  /// Shows the list while it is wanted and has entries, else hides it.
  void _syncList() {
    final wanted =
        _hasList && !_done && _focus.hasFocus && _open && _matches.isNotEmpty;
    if (wanted == _portal.isShowing) return;
    wanted ? _portal.show() : _portal.hide();
  }

  void _edited(String text) {
    setState(() {
      _query = text;
      _highlight = null;
    });
    _syncList();
  }

  /// ↑ or ↓: through the list, ↓ opening it; false for ↑ while it is
  /// closed, the key left to the field.
  bool _move(int by) {
    final count = _matches.length;
    if (count == 0 || (!_open && by < 0)) return false;
    setState(() {
      if (!_open) {
        _open = true;
        _highlight = 0;
      } else {
        final at = _highlight;
        _highlight = at == null ? (by > 0 ? 0 : count - 1) : (at + by) % count;
      }
    });
    _syncList();
    return true;
  }

  void _pick(int index) {
    final matches = _matches;
    if (index >= matches.length) return;
    _fill(matches[index]);
  }

  /// [title] in the field, all selected, the list put away.
  void _fill(String title) {
    _controller.value = TextEditingValue(
      text: title,
      selection: TextSelection(baseOffset: 0, extentOffset: title.length),
    );
    setState(() {
      _open = false;
      _query = null;
      _highlight = null;
    });
    _syncList();
  }

  Future<void> _summarize() async {
    final summarize = widget.onSummarize;
    if (summarize == null || _summarizing) return;
    setState(() {
      _summarizing = true;
      _summaryFailed = false;
    });
    String? title;
    try {
      title = await summarize();
    } on Object {
      title = null;
    }
    // Saved or cancelled meanwhile: nothing to put it in.
    if (!mounted || _done) return;
    setState(() {
      _summarizing = false;
      _summaryFailed = title == null;
    });
    if (title != null) _fill(title);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      _finish(null);
      return KeyEventResult.handled;
    }
    // An input method's keys while it composes.
    if (!_hasList || _controller.value.composing.isValid) {
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp) {
      return _move(key == LogicalKeyboardKey.arrowDown ? 1 : -1)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if ((key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter) &&
        _open &&
        _highlight != null &&
        event is KeyDownEvent) {
      _pick(_highlight!);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    // An input box, focused, as upstream's inline rename.
    final colors = themeColors;
    final border = OutlineInputBorder(
      borderSide: BorderSide(color: colors['focusBorder']),
    );
    final style =
        widget.style ?? TextStyle(color: AppColors.textPrimary, fontSize: 12.5);
    final field = Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        onSubmitted: _finish,
        onChanged: _hasList ? _edited : null,
        style: style,
        cursorColor: AppColors.text,
        cursorHeight: 14,
        decoration: InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          suffixIcon: widget.onSummarize == null
              ? null
              : _buildSummarize(context),
          suffixIconConstraints: const BoxConstraints(
            minWidth: 22,
            minHeight: 20,
          ),
          filled: true,
          fillColor: colors['input.background'],
          enabledBorder: border,
          focusedBorder: border,
        ),
      ),
    );
    if (!_hasList) return field;
    return LayoutBuilder(
      builder: (context, constraints) => CompositedTransformTarget(
        link: _link,
        child: OverlayPortal(
          controller: _portal,
          overlayChildBuilder: (context) => CompositedTransformFollower(
            link: _link,
            targetAnchor: Alignment.bottomLeft,
            offset: const Offset(0, 2),
            showWhenUnlinked: false,
            child: Align(
              alignment: Alignment.topLeft,
              // Clicked, still the field's: it keeps its focus.
              child: TextFieldTapRegion(
                child: SizedBox(
                  width: constraints.maxWidth.isFinite
                      ? constraints.maxWidth.clamp(240.0, 480.0)
                      : 320,
                  child: _buildList(context, style.fontSize ?? 12.5),
                ),
              ),
            ),
          ),
          child: field,
        ),
      ),
    );
  }

  /// The button at the field's end that sums it up: a spinner while it
  /// does, a warning when it could not.
  Widget _buildSummarize(BuildContext context) {
    final l10n = context.l10n;
    final colors = themeColors;
    final (icon, color, tooltip) = _summarizing
        ? (Codicons.loading, AppColors.textMuted, l10n.chatTitleSummarizing)
        : _summaryFailed
        ? (
            Codicons.warning,
            colors['problemsWarningIcon.foreground'],
            l10n.chatTitleSummarizeFailed,
          )
        : (Codicons.sparkle, AppColors.textMuted, l10n.chatTitleSummarize);
    return IdeHover(
      message: tooltip,
      child: MouseRegion(
        cursor: _summarizing
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _summarizing ? null : _summarize,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _summarizing
                ? IdeSpinning(Icon(icon, size: 14, color: color))
                : Icon(icon, size: 14, color: color),
          ),
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context, double fontSize) {
    final shadow = themeColors.get('widget.shadow');
    final rows = <Widget>[
      for (final (i, title) in _matches.indexed)
        _row(i, icon: Codicons.history, label: title, fontSize: fontSize),
    ];
    return Material(
      type: MaterialType.transparency,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: IdeMenuColors.background,
          border: Border.all(color: IdeMenuColors.border),
          borderRadius: BorderRadius.circular(5),
          boxShadow: [
            if (shadow != null) BoxShadow(color: shadow, blurRadius: 8),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        ),
      ),
    );
  }

  Widget _row(
    int index, {
    required IconData icon,
    required String label,
    required double fontSize,
  }) {
    final highlighted = index == _highlight;
    final foreground = highlighted
        ? IdeMenuColors.selectionForeground
        : IdeMenuColors.foreground;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _highlight = index),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _pick(index),
        child: Container(
          height: 24,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: highlighted ? IdeMenuColors.selectionBackground : null,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Row(
            children: [
              Icon(icon, size: 14, color: foreground),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: foreground, fontSize: fontSize),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
