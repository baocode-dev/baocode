import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/codicons.dart';
import '../theme/cursor_theme.dart';
import 'ide_commands.dart';
import 'ide_hover.dart';
import 'ide_input.dart';

/// Monaco's find/replace widget, drawn in the app's palette: a chevron that
/// toggles the replace row, a find input with inline Aa / ab / .* toggles,
/// the "N of M" counter, previous/next/close, and replace / replace all.
///
/// Stateless about search itself: the editor owns the controllers, options
/// and results and passes callbacks in. Without [onToggleReplace] it is
/// VS Code's simple find widget (the terminal's): no replace row.
class IdeFindWidget extends StatefulWidget {
  const IdeFindWidget({
    super.key,
    required this.findController,
    this.replaceController,
    required this.findFocusNode,
    this.replaceFocusNode,
    this.replaceVisible = false,
    required this.matchCase,
    required this.wholeWord,
    required this.regex,
    required this.matchCount,
    required this.currentIndex,
    this.onToggleReplace,
    required this.onToggleMatchCase,
    required this.onToggleWholeWord,
    required this.onToggleRegex,
    required this.onPrevious,
    required this.onNext,
    required this.onClose,
    this.onReplace,
    this.onReplaceAll,
    this.matchLimit = 999,
    this.enterFindsPrevious = false,
  });

  final TextEditingController findController;
  final TextEditingController? replaceController;
  final FocusNode findFocusNode;
  final FocusNode? replaceFocusNode;
  final bool replaceVisible;
  final bool matchCase;
  final bool wholeWord;
  final bool regex;
  final int matchCount;

  /// Zero-based index of the current match, or -1 when none is selected.
  final int currentIndex;

  /// Counts at or above this are shown as `N+` (results are capped).
  final int matchLimit;
  final VoidCallback? onToggleReplace;
  final VoidCallback onToggleMatchCase;
  final VoidCallback onToggleWholeWord;
  final VoidCallback onToggleRegex;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onClose;
  final VoidCallback? onReplace;
  final VoidCallback? onReplaceAll;

  /// Enter finds the previous match and ⇧Enter the next, as in VS Code's
  /// terminal, whose latest output is at the bottom.
  final bool enterFindsPrevious;

  static const width = 419.0;
  static const rowHeight = 33.0;

  /// Monaco's `N of M` / `? of M` / `No results` label.
  static String matchesLabel(int count, int index, {int limit = 999}) {
    if (count <= 0) return 'No results';
    final total = count >= limit ? '$count+' : '$count';
    return '${index >= 0 ? index + 1 : '?'} of $total';
  }

  @override
  State<IdeFindWidget> createState() => _IdeFindWidgetState();
}

class _IdeFindWidgetState extends State<IdeFindWidget> {
  @override
  void initState() {
    super.initState();
    widget.findFocusNode.addListener(_changed);
    widget.replaceFocusNode?.addListener(_changed);
  }

  @override
  void didUpdateWidget(IdeFindWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.findFocusNode != widget.findFocusNode) {
      oldWidget.findFocusNode.removeListener(_changed);
      widget.findFocusNode.addListener(_changed);
    }
    if (oldWidget.replaceFocusNode != widget.replaceFocusNode) {
      oldWidget.replaceFocusNode?.removeListener(_changed);
      widget.replaceFocusNode?.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.findFocusNode.removeListener(_changed);
    widget.replaceFocusNode?.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  bool get _replaceShown =>
      widget.replaceVisible &&
      widget.replaceController != null &&
      widget.replaceFocusNode != null;

  Map<ShortcutActivator, VoidCallback> get _toggleBindings {
    final mac = ideUsesMacKeys;
    SingleActivator option(LogicalKeyboardKey key) =>
        SingleActivator(key, alt: true, meta: mac);
    return {
      option(LogicalKeyboardKey.keyC): widget.onToggleMatchCase,
      option(LogicalKeyboardKey.keyW): widget.onToggleWholeWord,
      option(LogicalKeyboardKey.keyR): widget.onToggleRegex,
    };
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.matchCount;
    final noResults = count == 0 && widget.findController.text.isNotEmpty;
    final mac = ideUsesMacKeys;
    String shortcut(LogicalKeyboardKey key) =>
        IdeKeybinding(key, alt: true, primary: mac).label();
    return LayoutBuilder(
      builder: (context, constraints) {
        // Narrow editors drop the counter's fixed width (Monaco's 69px).
        final counterWidth = constraints.maxWidth < 360 ? 0.0 : 69.0;
        return _build(noResults, count, mac, shortcut, counterWidth);
      },
    );
  }

  Widget _build(
    bool noResults,
    int count,
    bool mac,
    String Function(LogicalKeyboardKey) shortcut,
    double counterWidth,
  ) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
        const SingleActivator(LogicalKeyboardKey.enter):
            widget.enterFindsPrevious ? widget.onPrevious : widget.onNext,
        const SingleActivator(LogicalKeyboardKey.enter, shift: true):
            widget.enterFindsPrevious ? widget.onNext : widget.onPrevious,
        const SingleActivator(LogicalKeyboardKey.f3): widget.onNext,
        const SingleActivator(LogicalKeyboardKey.f3, shift: true):
            widget.onPrevious,
        ..._toggleBindings,
      },
      child: Material(
        color: CursorColors.surfaceRaised,
        elevation: 8,
        shadowColor: Colors.black,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(4)),
          side: BorderSide(color: CursorColors.border),
        ),
        child: SizedBox(
          height: _replaceShown
              ? IdeFindWidget.rowHeight * 2 - 4
              : IdeFindWidget.rowHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.onToggleReplace case final onToggleReplace?)
                _ReplaceToggle(
                  expanded: widget.replaceVisible,
                  onTap: onToggleReplace,
                )
              else
                const SizedBox(width: 2),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: IdeFindWidget.rowHeight,
                      child: Row(
                        children: [
                          Expanded(
                            child: _FindInput(
                              controller: widget.findController,
                              focusNode: widget.findFocusNode,
                              hint: 'Find',
                              error: noResults,
                              toggles: [
                                _InlineToggle(
                                  tooltip: 'Match case',
                                  shortcut: shortcut(LogicalKeyboardKey.keyC),
                                  active: widget.matchCase,
                                  onTap: widget.onToggleMatchCase,
                                  child: const Icon(
                                    Codicons.caseSensitive,
                                    size: 16,
                                  ),
                                ),
                                _InlineToggle(
                                  tooltip: 'Whole word',
                                  shortcut: shortcut(LogicalKeyboardKey.keyW),
                                  active: widget.wholeWord,
                                  onTap: widget.onToggleWholeWord,
                                  child: const Icon(
                                    Codicons.wholeWord,
                                    size: 16,
                                  ),
                                ),
                                _InlineToggle(
                                  tooltip: 'Regular expression',
                                  shortcut: shortcut(LogicalKeyboardKey.keyR),
                                  active: widget.regex,
                                  onTap: widget.onToggleRegex,
                                  child: const Icon(Codicons.regex, size: 16),
                                ),
                              ],
                            ),
                          ),
                          Flexible(
                            child: Container(
                              constraints: BoxConstraints(
                                minWidth: counterWidth,
                              ),
                              padding: const EdgeInsets.only(left: 6, right: 2),
                              alignment: Alignment.centerLeft,
                              child: Text(
                                IdeFindWidget.matchesLabel(
                                  count,
                                  widget.currentIndex,
                                  limit: widget.matchLimit,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: noResults
                                      ? CursorColors.removed
                                      : CursorColors.text,
                                ),
                              ),
                            ),
                          ),
                          _FindButton(
                            tooltip: 'Previous match',
                            icon: Codicons.arrowUp,
                            onTap: count == 0 ? null : widget.onPrevious,
                          ),
                          _FindButton(
                            tooltip: 'Next match',
                            icon: Codicons.arrowDown,
                            onTap: count == 0 ? null : widget.onNext,
                          ),
                          _FindButton(
                            tooltip: 'Close find',
                            icon: Codicons.close,
                            onTap: widget.onClose,
                          ),
                          const SizedBox(width: 4),
                        ],
                      ),
                    ),
                    if (_replaceShown)
                      SizedBox(
                        height: IdeFindWidget.rowHeight - 4,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: CallbackShortcuts(
                                  bindings: {
                                    const SingleActivator(
                                      LogicalKeyboardKey.enter,
                                    ): widget.onReplace ?? () {},
                                    SingleActivator(
                                      LogicalKeyboardKey.enter,
                                      meta: mac,
                                      control: !mac,
                                    ): widget.onReplaceAll ?? () {},
                                  },
                                  child: _FindInput(
                                    controller: widget.replaceController!,
                                    focusNode: widget.replaceFocusNode!,
                                    hint: 'Replace',
                                    error: false,
                                    toggles: const [],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              _FindButton(
                                tooltip: 'Replace match',
                                icon: Codicons.replace,
                                onTap: count == 0 ? null : widget.onReplace,
                              ),
                              _FindButton(
                                tooltip: 'Replace all',
                                icon: Codicons.replaceAll,
                                onTap: count == 0 ? null : widget.onReplaceAll,
                              ),
                              // Keeps the replace input as wide as the find one.
                              SizedBox(width: counterWidth + 22 - 6 + 4),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReplaceToggle extends StatefulWidget {
  const _ReplaceToggle({required this.expanded, required this.onTap});

  final bool expanded;
  final VoidCallback onTap;

  @override
  State<_ReplaceToggle> createState() => _ReplaceToggleState();
}

class _ReplaceToggleState extends State<_ReplaceToggle> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return IdeHover(
      message: 'Toggle replace',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            width: 18,
            margin: const EdgeInsets.fromLTRB(2, 4, 2, 4),
            decoration: BoxDecoration(
              color: _hover ? const Color(0x1FFFFFFF) : Colors.transparent,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Icon(
              widget.expanded ? Codicons.chevronDown : Codicons.chevronRight,
              size: 16,
              color: CursorColors.text,
            ),
          ),
        ),
      ),
    );
  }
}

class _FindInput extends StatelessWidget {
  const _FindInput({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.error,
    required this.toggles,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final bool error;
  final List<Widget> toggles;

  @override
  Widget build(BuildContext context) {
    final borderColor = error
        ? CursorColors.removed
        : focusNode.hasFocus
        ? CursorColors.accent
        : CursorColors.borderStrong;
    return Container(
      height: 26,
      margin: const EdgeInsets.only(left: 2),
      decoration: BoxDecoration(
        color: CursorColors.background,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              autocorrect: false,
              enableSuggestions: false,
              cursorColor: CursorColors.accent,
              cursorWidth: 1.5,
              cursorHeight: ideCaretHeight(12.5),
              style: const TextStyle(
                fontSize: 12.5,
                color: CursorColors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(
                  fontSize: 12.5,
                  color: CursorColors.textFaint,
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 5,
                ),
                border: InputBorder.none,
              ),
            ),
          ),
          ...toggles,
          if (toggles.isNotEmpty) const SizedBox(width: 2),
        ],
      ),
    );
  }
}

class _InlineToggle extends StatefulWidget {
  const _InlineToggle({
    required this.tooltip,
    required this.shortcut,
    required this.active,
    required this.onTap,
    required this.child,
  });

  final String tooltip;
  final String shortcut;
  final bool active;
  final VoidCallback onTap;
  final Widget child;

  @override
  State<_InlineToggle> createState() => _InlineToggleState();
}

class _InlineToggleState extends State<_InlineToggle> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    return IdeHover(
      message: widget.tooltip,
      child: Semantics(
        toggled: active,
        button: true,
        label: '${widget.tooltip} (${widget.shortcut})',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: Container(
              width: 20,
              height: 20,
              margin: const EdgeInsets.only(left: 1),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active
                    ? const Color(0x664C9DFF)
                    : _hover
                    ? const Color(0x1FFFFFFF)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: active ? CursorColors.accent : Colors.transparent,
                ),
              ),
              child: IconTheme.merge(
                data: IconThemeData(
                  color: active
                      ? CursorColors.textPrimary
                      : CursorColors.textMuted,
                ),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FindButton extends StatefulWidget {
  const _FindButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  State<_FindButton> createState() => _FindButtonState();
}

class _FindButtonState extends State<_FindButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return IdeHover(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            width: 22,
            height: 22,
            margin: const EdgeInsets.only(left: 1),
            decoration: BoxDecoration(
              color: _hover && enabled
                  ? const Color(0x1FFFFFFF)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Icon(
              widget.icon,
              size: 15,
              color: enabled ? CursorColors.text : CursorColors.textFaint,
            ),
          ),
        ),
      ),
    );
  }
}
