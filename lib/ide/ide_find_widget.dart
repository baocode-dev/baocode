import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../keybindings/keybinding_service.dart';
import '../l10n/l10n.dart';
import '../theme/codicons.dart';
import '../theme/workbench_theme.dart' show themeColors;
import 'ide_commands.dart';
import 'ide_hover.dart';
import 'ide_input.dart';

/// What a key or a control of an [IdeFindWidget] does: which of its
/// callbacks runs.
enum IdeFindAction {
  next,
  previous,
  close,
  toggleMatchCase,
  toggleWholeWord,
  toggleRegex,
  replace,
  replaceAll,
}

/// The editor's find commands (VS Code's findController.ts), for
/// [IdeFindWidget.commandIds].
const Map<IdeFindAction, String> editorFindCommandIds = {
  IdeFindAction.next: 'editor.action.nextMatchFindAction',
  IdeFindAction.previous: 'editor.action.previousMatchFindAction',
  IdeFindAction.close: 'closeFindWidget',
  IdeFindAction.toggleMatchCase: 'toggleFindCaseSensitive',
  IdeFindAction.toggleWholeWord: 'toggleFindWholeWord',
  IdeFindAction.toggleRegex: 'toggleFindRegex',
  IdeFindAction.replace: 'editor.action.replaceOne',
  IdeFindAction.replaceAll: 'editor.action.replaceAll',
};

/// The terminal's find commands (VS Code's terminal.find.contribution.ts,
/// read with `terminalFindFocused` / `terminalFindVisible` /
/// `terminalFindInputFocused`), for [IdeFindWidget.commandIds].
const Map<IdeFindAction, String> terminalFindCommandIds = {
  IdeFindAction.next: 'workbench.action.terminal.findNext',
  IdeFindAction.previous: 'workbench.action.terminal.findPrevious',
  IdeFindAction.close: 'workbench.action.terminal.hideFind',
  IdeFindAction.toggleMatchCase:
      'workbench.action.terminal.toggleFindCaseSensitive',
  IdeFindAction.toggleWholeWord:
      'workbench.action.terminal.toggleFindWholeWord',
  IdeFindAction.toggleRegex: 'workbench.action.terminal.toggleFindRegex',
};

/// Monaco's find/replace widget, in the color theme's colors of VS Code's
/// (editor/contrib/find/browser/findWidget.css): a chevron that toggles the
/// replace row, a find input with inline Aa / ab / .* toggles, the "N of M"
/// counter, previous/next/close, and replace / replace all.
///
/// Stateless about search itself: the editor owns the controllers, options
/// and results and passes callbacks in. Without [onToggleReplace] it is
/// VS Code's simple find widget (the terminal's): no replace row.
///
/// Keys: without [resolveKey], VS Code's default keys of the find commands
/// (Enter, ⇧Enter, F3, Escape, ⌥C/⌥W/⌥R or Alt+C/W/R; in the replace
/// input Enter and ⌘Enter / Ctrl+Enter). With it, the host's keybindings:
/// a key in the widget whose command is one of [commandIds] runs that
/// action's callback, and every other key goes on to the host.
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
    this.commandIds,
    this.resolveKey,
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
  /// terminal, whose latest output is at the bottom (the built-in keys).
  final bool enterFindsPrevious;

  /// The commands of the widget's actions ([editorFindCommandIds],
  /// [terminalFindCommandIds]): the toggles show their keybindings (the
  /// app's), and [resolveKey]'s answers map back to the actions. Without
  /// it the toggles show VS Code's default keys.
  final Map<IdeFindAction, String>? commandIds;

  /// Which command a key pressed in the widget runs, as the host's
  /// keybindings resolve it in its context (e.g. the editor's
  /// `findInputFocussed`), or null for none. Given, it replaces the
  /// built-in keys (see the class doc); keys are left to the input method
  /// while it composes.
  final String? Function(KeyEvent event)? resolveKey;

  static const width = 419.0;
  static const rowHeight = 33.0;

  /// Monaco's `N of M` / `? of M` / `No results` label, in [l10n]'s
  /// language (English when null).
  static String matchesLabel(
    int count,
    int index, {
    int limit = 999,
    AppLocalizations? l10n,
  }) {
    final strings = l10n ?? englishLocalizations;
    if (count <= 0) return strings.findNoResults;
    final total = count >= limit ? '$count+' : '$count';
    return strings.findMatchOf(index >= 0 ? '${index + 1}' : '?', total);
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

  VoidCallback? _callback(IdeFindAction action) => switch (action) {
    IdeFindAction.next => widget.onNext,
    IdeFindAction.previous => widget.onPrevious,
    IdeFindAction.close => widget.onClose,
    IdeFindAction.toggleMatchCase => widget.onToggleMatchCase,
    IdeFindAction.toggleWholeWord => widget.onToggleWholeWord,
    IdeFindAction.toggleRegex => widget.onToggleRegex,
    IdeFindAction.replace => widget.onReplace,
    IdeFindAction.replaceAll => widget.onReplaceAll,
  };

  /// A key in the widget with [IdeFindWidget.resolveKey]: the action of the
  /// command it resolves to, or on to the host.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final resolve = widget.resolveKey;
    if (resolve == null || event is KeyUpEvent) return KeyEventResult.ignored;
    for (final controller in [
      widget.findController,
      widget.replaceController,
    ]) {
      final composing = controller?.value.composing;
      if (composing != null && composing.isValid && !composing.isCollapsed) {
        return KeyEventResult.ignored;
      }
    }
    final command = resolve(event);
    if (command == null) return KeyEventResult.ignored;
    for (final MapEntry(key: action, value: id)
        in (widget.commandIds ?? const {}).entries) {
      if (id != command) continue;
      final callback = _callback(action);
      if (callback == null) return KeyEventResult.ignored;
      callback();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// The keybinding label of [action]'s command, or [fallback] (VS Code's
  /// default key) without [IdeFindWidget.commandIds].
  String _shortcut(IdeFindAction action, String fallback) {
    final id = widget.commandIds?[action];
    if (id == null) return fallback;
    return KeybindingService.instance.labelFor(id) ?? '';
  }

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
    String shortcut(LogicalKeyboardKey key) => _shortcut(switch (key) {
      LogicalKeyboardKey.keyC => IdeFindAction.toggleMatchCase,
      LogicalKeyboardKey.keyW => IdeFindAction.toggleWholeWord,
      _ => IdeFindAction.toggleRegex,
    }, IdeKeybinding(key, alt: true, primary: mac).label());
    return LayoutBuilder(
      builder: (context, constraints) {
        // Narrow editors drop the counter's fixed width (Monaco's 69px).
        final counterWidth = constraints.maxWidth < 360 ? 0.0 : 69.0;
        return DecoratedBox(
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(4)),
            boxShadow: IdeHoverColors.shadow,
          ),
          child: _build(noResults, count, mac, shortcut, counterWidth),
        );
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
    final colors = themeColors;
    // High contrast themes' `contrastBorder` over `widget.border`.
    final border = colors.get('contrastBorder') ?? colors.get('widget.border');
    final builtInKeys = widget.resolveKey == null;
    return CallbackShortcuts(
      bindings: {if (builtInKeys) ..._builtInKeys},
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _onKey,
        child: _body(noResults, count, mac, shortcut, counterWidth, border),
      ),
    );
  }

  /// VS Code's default keys of the find commands, without
  /// [IdeFindWidget.resolveKey].
  Map<ShortcutActivator, VoidCallback> get _builtInKeys => {
    const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
    const SingleActivator(LogicalKeyboardKey.enter): widget.enterFindsPrevious
        ? widget.onPrevious
        : widget.onNext,
    const SingleActivator(LogicalKeyboardKey.enter, shift: true):
        widget.enterFindsPrevious ? widget.onNext : widget.onPrevious,
    const SingleActivator(LogicalKeyboardKey.f3): widget.onNext,
    const SingleActivator(LogicalKeyboardKey.f3, shift: true):
        widget.onPrevious,
    ..._toggleBindings,
  };

  Widget _body(
    bool noResults,
    int count,
    bool mac,
    String Function(LogicalKeyboardKey) shortcut,
    double counterWidth,
    Color? border,
  ) {
    final l10n = context.l10n;
    final colors = themeColors;
    return Material(
      color: colors['editorWidget.background'],
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(4)),
        side: border == null ? BorderSide.none : BorderSide(color: border),
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
                            hint: l10n.findFind,
                            error: noResults,
                            toggles: [
                              _InlineToggle(
                                tooltip: l10n.findMatchCase,
                                shortcut: shortcut(LogicalKeyboardKey.keyC),
                                active: widget.matchCase,
                                onTap: widget.onToggleMatchCase,
                                child: const Icon(
                                  Codicons.caseSensitive,
                                  size: 16,
                                ),
                              ),
                              _InlineToggle(
                                tooltip: l10n.findWholeWord,
                                shortcut: shortcut(LogicalKeyboardKey.keyW),
                                active: widget.wholeWord,
                                onTap: widget.onToggleWholeWord,
                                child: const Icon(Codicons.wholeWord, size: 16),
                              ),
                              _InlineToggle(
                                tooltip: l10n.findRegularExpression,
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
                            constraints: BoxConstraints(minWidth: counterWidth),
                            padding: const EdgeInsets.only(left: 6, right: 2),
                            alignment: Alignment.centerLeft,
                            child: Text(
                              IdeFindWidget.matchesLabel(
                                count,
                                widget.currentIndex,
                                limit: widget.matchLimit,
                                l10n: l10n,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: noResults
                                    ? colors['errorForeground']
                                    : colors['editorWidget.foreground'],
                              ),
                            ),
                          ),
                        ),
                        _FindButton(
                          tooltip: l10n.findPreviousMatch,
                          icon: Codicons.arrowUp,
                          onTap: count == 0 ? null : widget.onPrevious,
                        ),
                        _FindButton(
                          tooltip: l10n.findNextMatch,
                          icon: Codicons.arrowDown,
                          onTap: count == 0 ? null : widget.onNext,
                        ),
                        _FindButton(
                          tooltip: l10n.findClose,
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
                                  if (widget.resolveKey == null) ...{
                                    const SingleActivator(
                                      LogicalKeyboardKey.enter,
                                    ): widget.onReplace ?? () {},
                                    SingleActivator(
                                      LogicalKeyboardKey.enter,
                                      meta: mac,
                                      control: !mac,
                                    ): widget.onReplaceAll ?? () {},
                                  },
                                },
                                child: _FindInput(
                                  controller: widget.replaceController!,
                                  focusNode: widget.replaceFocusNode!,
                                  hint: l10n.findReplace,
                                  error: false,
                                  toggles: const [],
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            _FindButton(
                              tooltip: l10n.findReplaceMatch,
                              icon: Codicons.replace,
                              onTap: count == 0 ? null : widget.onReplace,
                            ),
                            _FindButton(
                              tooltip: l10n.findReplaceAll,
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
      message: context.l10n.findToggleReplace,
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
              color: _hover
                  ? themeColors['toolbar.hoverBackground']
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Icon(
              widget.expanded ? Codicons.chevronDown : Codicons.chevronRight,
              size: 16,
              color: themeColors['icon.foreground'],
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
    // `defaultInputBoxStyles`; no results mark it as an invalid input.
    final borderColor = error
        ? themeColors['inputValidation.errorBorder']
        : focusNode.hasFocus
        ? IdeInputColors.focusBorder
        : IdeInputColors.border;
    return Container(
      height: 26,
      margin: const EdgeInsets.only(left: 2),
      decoration: BoxDecoration(
        color: IdeInputColors.background,
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
              cursorColor: IdeInputColors.foreground,
              cursorWidth: 1.5,
              cursorHeight: ideCaretHeight(12.5),
              style: TextStyle(
                fontSize: 12.5,
                color: IdeInputColors.foreground,
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(
                  fontSize: 12.5,
                  color: IdeInputColors.placeholder,
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
    // `defaultToggleStyles`; high contrast themes outline it on hover
    // instead (dashed upstream).
    final highContrast = themeColors.highContrast;
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
                    ? IdeInputColors.optionActiveBackground
                    : _hover && !highContrast
                    ? IdeInputColors.optionHoverBackground
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: _hover && highContrast
                      ? themeColors['focusBorder']
                      : active
                      ? IdeInputColors.optionActiveBorder
                      : Colors.transparent,
                ),
              ),
              child: IconTheme.merge(
                // Unchecked, the find widget's color (`inherit`).
                data: IconThemeData(
                  color: active
                      ? IdeInputColors.optionActiveForeground
                      : themeColors['editorWidget.foreground'],
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
    // High contrast themes outline it on hover (dashed upstream).
    final outline = _hover && enabled
        ? themeColors.get('toolbar.hoverOutline')
        : null;
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
                  ? themeColors['toolbar.hoverBackground']
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(3),
            ),
            foregroundDecoration: outline == null
                ? null
                : BoxDecoration(
                    border: Border.all(color: outline),
                    borderRadius: BorderRadius.circular(3),
                  ),
            child: Icon(
              widget.icon,
              size: 15,
              color: enabled
                  ? themeColors['icon.foreground']
                  : themeColors['disabledForeground'],
            ),
          ),
        ),
      ),
    );
  }
}
