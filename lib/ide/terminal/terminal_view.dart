/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// A terminal's screen in the panel, as VS Code attaches an instance's xterm
// to its view: the renderer, with the instance's keyboard, mouse and
// selection wired to it, a text input connection for input methods (as
// the editor's), the multi-line paste warning, the context menu, the
// find widget, links, and the shell integration's command marks.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/contrib/terminal/browser/terminalInstance.ts (the custom
// key event handler and `terminal.integrated.commandsToSkipShell`),
// terminalMenus.ts (`MenuId.TerminalInstanceContext`),
// src/vs/workbench/contrib/terminalContrib/links/browser/terminalLink.ts
// (when a link is underlined and opens),
// src/vs/workbench/contrib/terminal/browser/xterm/decorationAddon.ts (the
// command marks in the gutter, their hover and actions),
// src/vs/workbench/contrib/terminalContrib/find/browser/
// terminal.find.contribution.ts (the find keybindings),
// src/vs/workbench/contrib/codeEditor/browser/find/simpleFindWidget.css
// (where the find widget sits) and
// src/vs/workbench/contrib/modernUI/browser/media/padding.css (the 8px
// above and below); xterm.js' CoreBrowserTerminal (focus reports) and
// CompositionHelper (composition, here in the text input connection).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../ide_commands.dart';
import '../ide_dialog.dart';
import '../ide_find_widget.dart';
import '../ide_hover.dart';
import '../ide_menu.dart';
import 'links/terminal_links.dart';
import 'shell_integration/decoration_addon.dart';
import 'shell_integration/decoration_styles.dart';
import 'shell_integration/shell_integration.dart';
import 'terminal_clipboard.dart';
import 'terminal_find.dart';
import 'terminal_instance.dart';
import 'terminal_keyboard.dart';
import 'terminal_renderer.dart';
import 'terminal_widget.dart';
import 'xterm/common/data/escape_sequences.dart';
import 'xterm/common/lifecycle.dart';

/// A terminal's screen, and the keyboard's way into it
/// ([TerminalInstance.focusNode]).
class TerminalView extends StatefulWidget {
  const TerminalView(
    this.instance, {
    super.key,
    this.skipShell = const [],
    this.onKill,
    this.onOpenLink,
  });

  final TerminalInstance instance;

  /// Keys the workbench keeps while the terminal has focus: the
  /// keybindings of VS Code's `terminal.integrated.commandsToSkipShell`.
  final List<ShortcutActivator> skipShell;

  /// Kill Terminal, from the context menu.
  final VoidCallback? onKill;

  /// Opens a link ⌘-clicked (Ctrl-clicked off macOS).
  final ValueChanged<TerminalLink>? onOpenLink;

  /// `.xterm { padding-left: 20px }`, and Modern UI's 8px above and below;
  /// the scrollbar is at the right edge.
  static const padding = EdgeInsets.fromLTRB(20, 8, 0, 8);

  @override
  State<TerminalView> createState() => _TerminalViewState();
}

class _TerminalViewState extends State<TerminalView> with TextInputClient {
  final _render = TerminalRenderController();
  final _subscriptions = DisposableStore();
  final _findText = TextEditingController();
  final _findFocus = FocusNode(debugLabel: 'terminal find');
  TextInputConnection? _input;
  TextEditingValue _value = TextEditingValue.empty;
  MouseCursor _cursor = SystemMouseCursors.text;

  // The key being handled, for the skip-shell check.
  KeyEvent? _key;

  // Bumped when the command marks move or change.
  final _gutter = ValueNotifier(0);
  ShellIntegration? _integration;
  final _integrationSubscriptions = DisposableStore();

  // The link under the pointer, where the pointer is on the grid, the
  // latest look-up, and the link a press began on.
  TerminalLink? _link;
  Offset? _hover;
  int _lookUp = 0;
  TerminalLink? _linkPressed;

  TerminalInstance get _instance => widget.instance;

  @override
  void initState() {
    super.initState();
    _attach();
    _render.addListener(_renderChanged);
    HardwareKeyboard.instance.addHandler(_modifiersChanged);
    _findText.addListener(_findTextChanged);
    _findFocus.addListener(_findFocusChanged);
  }

  @override
  void didUpdateWidget(TerminalView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.instance != widget.instance) {
      _detach(oldWidget.instance);
      _attach();
    }
  }

  void _attach() {
    final instance = _instance;
    final selection = instance.selection;
    _subscriptions.add(
      selection.onRequestRedraw(
        (e) => _render.setSelection(
          e.start,
          e.end,
          columnSelectMode: e.columnSelectMode,
        ),
      ),
    );
    _subscriptions.add(
      selection.onRequestScrollLines(
        (e) => instance.terminal.scrollLines(e.amount, e.suppressScrollEvent),
      ),
    );
    _subscriptions.add(
      instance.terminal.mouseStateService.onProtocolChange(
        (_) => _cursorChanged(),
      ),
    );
    _subscriptions.add(
      instance.terminal.onScroll((_) {
        _gutterChanged();
        unawaited(_lookUpLink(_hover));
      }),
    );
    _subscriptions.add(instance.terminal.onResize((_) => _gutterChanged()));
    _subscriptions.add(
      instance.terminal.buffers.onBufferActivate((_) => _gutterChanged()),
    );
    instance.addListener(_instanceChanged);
    _attachShellIntegration();
    selection.currentLinkRange = () => _link?.range;
    _subscriptions.add(
      instance.find.onDidChange((_) {
        if (mounted) setState(() {});
      }),
    );
    _findText.text = instance.find.inputValue;
    _render.setSelection(
      selection.selectionStart,
      selection.selectionEnd,
      columnSelectMode: selection.isColumnSelectMode,
    );
    instance.keyboard.customKeyEventHandler = _allowKey;
    instance.clipboard.confirmPaste = _confirmPaste;
    instance.focusNode.addListener(_focusChanged);
    if (instance.focusNode.hasFocus) _focusChanged();
  }

  void _detach(TerminalInstance instance) {
    _subscriptions.clear();
    instance.removeListener(_instanceChanged);
    _integrationSubscriptions.clear();
    _integration = null;
    instance.selection.currentLinkRange = null;
    _lookUp++;
    _link = null;
    _hover = null;
    instance.focusNode.removeListener(_focusChanged);
    if (instance.keyboard.customKeyEventHandler == _allowKey) {
      instance.keyboard.customKeyEventHandler = null;
    }
    if (instance.clipboard.confirmPaste == _confirmPaste) {
      instance.clipboard.confirmPaste = null;
    }
    _closeInput(instance);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_modifiersChanged);
    _detach(_instance);
    _subscriptions.dispose();
    _integrationSubscriptions.dispose();
    _gutter.dispose();
    _render.removeListener(_renderChanged);
    _render.dispose();
    _findText.dispose();
    _findFocus.dispose();
    super.dispose();
  }

  void _renderChanged() {
    if (_render.hasValidSize) _instance.mouse.cellSize = _render.cellSize;
    _updateInputGeometry();
    _gutterChanged();
  }

  // --- Keyboard ---------------------------------------------------------

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    _key = event;
    try {
      final result = _instance.keyboard.handleKeyEvent(event);
      if (result.scrollLines != 0) {
        _instance.terminal.scrollLines(result.scrollLines);
      }
      return result.keyEventResult;
    } finally {
      _key = null;
    }
  }

  /// VS Code's custom key event handler: the workbench's keys and find's
  /// skip the shell.
  bool _allowKey(TerminalKeyboardEvent event) {
    final key = _key;
    if (key == null || key is KeyUpEvent) return true;
    final keyboard = HardwareKeyboard.instance;
    return ![
      ...widget.skipShell,
      ..._findKeys.keys,
    ].any((a) => a.accepts(key, keyboard));
  }

  bool _modifiersChanged(KeyEvent event) {
    _showLink();
    return false;
  }

  // --- Focus and input methods -----------------------------------------

  void _focusChanged() {
    final instance = _instance;
    final focused = instance.focusNode.hasFocus;
    // Focus reports (DECSET 1004), as xterm.js' focus and blur.
    if (instance.terminal.coreService.decPrivateModes.sendFocus &&
        !instance.exited) {
      instance.terminal.coreService.triggerDataEvent(
        '${C0.esc}[${focused ? 'I' : 'O'}',
      );
    }
    if (focused) {
      instance.showCursor();
      _openInput();
    } else {
      _closeInput(instance);
    }
  }

  void _openInput() {
    if (_input?.attached != true) {
      _input = TextInput.attach(
        this,
        TextInputConfiguration(
          viewId: View.of(context).viewId,
          inputType: TextInputType.multiline,
          inputAction: TextInputAction.newline,
          autocorrect: false,
          smartDashesType: SmartDashesType.disabled,
          smartQuotesType: SmartQuotesType.disabled,
          enableSuggestions: false,
          enableInteractiveSelection: false,
          enableIMEPersonalizedLearning: false,
        ),
      );
    }
    _value = TextEditingValue.empty;
    _input!.setEditingState(_value);
    _input!.show();
    _instance.keyboard.textInputAttached = true;
    _updateInputGeometry();
  }

  void _closeInput(TerminalInstance instance) {
    _input?.close();
    _input = null;
    instance.keyboard
      ..textInputAttached = false
      ..isComposing = false;
    _render.composition = null;
  }

  void _updateInputGeometry() {
    final input = _input;
    final box = _render.renderBox;
    final cursor = _render.cursorRect;
    if (input == null || !input.attached || box == null || !box.attached) {
      return;
    }
    input.setEditableSizeAndTransform(box.size, box.getTransformTo(null));
    if (cursor != null) {
      input.setCaretRect(cursor);
      input.setComposingRect(cursor);
    }
  }

  @override
  TextEditingValue get currentTextEditingValue => _value;

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  void updateEditingValue(TextEditingValue value) {
    if (_input?.attached != true) return;
    final keyboard = _instance.keyboard;
    final composing = value.composing;
    if (composing.isValid && !composing.isCollapsed) {
      // Composing: shown over the cursor until the input method commits.
      _value = value;
      keyboard.isComposing = true;
      _render.composition = composing.textInside(value.text);
      _updateInputGeometry();
      return;
    }
    keyboard.isComposing = false;
    _render.composition = null;
    if (value.text.isNotEmpty) keyboard.handleTextInput(value.text);
    // Nothing stays in the input: the terminal has it.
    _value = TextEditingValue.empty;
    _input!.setEditingState(_value);
  }

  @override
  void performAction(TextInputAction action) {}

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}

  @override
  void showAutocorrectionPromptRect(int start, int end) {}

  @override
  void connectionClosed() {
    _input = null;
    _instance.keyboard
      ..textInputAttached = false
      ..isComposing = false;
    _render.composition = null;
  }

  // --- Find -------------------------------------------------------------

  /// Find's keybindings while the terminal or its find has focus: Focus
  /// Find, Find Next and Previous, and Hide Find while it shows.
  Map<ShortcutActivator, VoidCallback> get _findKeys {
    final mac = ideUsesMacKeys;
    return {
      SingleActivator(LogicalKeyboardKey.keyF, meta: mac, control: !mac):
          _revealFind,
      const SingleActivator(LogicalKeyboardKey.f3): _findNext,
      const SingleActivator(LogicalKeyboardKey.f3, shift: true): _findPrevious,
      if (mac) ...{
        const SingleActivator(LogicalKeyboardKey.keyG, meta: true): _findNext,
        const SingleActivator(LogicalKeyboardKey.keyG, meta: true, shift: true):
            _findPrevious,
      },
      if (_instance.find.isVisible) ...{
        const SingleActivator(LogicalKeyboardKey.escape): _hideFind,
        const SingleActivator(LogicalKeyboardKey.escape, shift: true):
            _hideFind,
      },
    };
  }

  void _revealFind() {
    final find = _instance.find..reveal();
    _findText.value = TextEditingValue(
      text: find.inputValue,
      selection: TextSelection(
        baseOffset: 0,
        extentOffset: find.inputValue.length,
      ),
    );
    _findFocus.requestFocus();
  }

  void _hideFind() {
    _instance.find.hide();
    _instance.focus();
  }

  void _findNext() => (_instance.find..show()).findNext();

  void _findPrevious() => (_instance.find..show()).findPrevious();

  /// Searches as the query is typed; not while an input method composes it.
  void _findTextChanged() {
    final value = _findText.value;
    if (value.composing.isValid && !value.composing.isCollapsed) return;
    _instance.find.inputValue = value.text;
  }

  void _findFocusChanged() {
    if (!_findFocus.hasFocus) _instance.find.clearActiveDecoration();
    if (mounted) setState(() {});
  }

  Widget _findWidget(BoxConstraints constraints) {
    final find = _instance.find;
    return Positioned(
      top: 0,
      right: 28,
      width: (constraints.maxWidth - 64).clamp(0, IdeFindWidget.width),
      child: IdeFindWidget(
        findController: _findText,
        findFocusNode: _findFocus,
        matchCase: find.caseSensitive,
        wholeWord: find.wholeWord,
        regex: find.regex,
        matchCount: find.resultCount,
        currentIndex: find.resultIndex,
        matchLimit: TerminalFind.searchHighlightLimit,
        enterFindsPrevious: true,
        onToggleMatchCase: find.toggleCaseSensitive,
        onToggleWholeWord: find.toggleWholeWord,
        onToggleRegex: find.toggleRegex,
        onPrevious: find.findPrevious,
        onNext: find.findNext,
        onClose: _hideFind,
      ),
    );
  }

  // --- Command marks ----------------------------------------------------

  /// The shell integration comes with the launch.
  void _instanceChanged() {
    if (_instance.shellIntegration != _integration) _attachShellIntegration();
  }

  void _attachShellIntegration() {
    _integrationSubscriptions.clear();
    final integration = _integration = _instance.shellIntegration;
    if (integration == null) return;
    _integrationSubscriptions.add(
      integration.onDidChangeDecorations((_) => _gutterChanged()),
    );
    _gutterChanged();
  }

  void _gutterChanged() => _gutter.value++;

  /// The commands' marks, as VS Code's decoration addon places them: in the
  /// padding left of their command's first line, not on the alternate
  /// screen.
  Widget _commandMarks(TerminalInstance instance) =>
      ValueListenableBuilder<int>(
        valueListenable: _gutter,
        builder: (context, _, _) {
          final integration = instance.shellIntegration;
          if (integration == null ||
              !_render.hasValidSize ||
              instance.source.isAlternateBuffer) {
            return const SizedBox.shrink();
          }
          final terminal = instance.terminal;
          final options = terminal.optionsService.rawOptions;
          final layout = decorationLayout(
            fontSize: options.fontSize,
            defaultFontSize: defaultTargetPlatform == TargetPlatform.macOS
                ? 12
                : 14,
            lineHeight: options.lineHeight,
          );
          final top = terminal.buffer.ydisp;
          final origin = _render.gridOrigin;
          final cellHeight = _render.cellSize.height;
          return Stack(
            children: [
              for (final decoration in integration.decorations)
                if (decoration.isVisible &&
                    decoration.marker.line - top >= 0 &&
                    decoration.marker.line - top < terminal.rows)
                  Positioned(
                    left: origin.dx + layout.marginLeft,
                    top:
                        origin.dy + (decoration.marker.line - top) * cellHeight,
                    width: layout.width,
                    height: cellHeight,
                    child: _commandMark(decoration, layout.fontSize),
                  ),
            ],
          );
        },
      );

  Widget _commandMark(TerminalCommandDecoration decoration, double size) {
    final hover = decoration.hoverMessage;
    final command = decoration.command;
    if (!decoration.isInteractive || hover == null || command == null) {
      return Center(
        child: Icon(decoration.icon, size: size, color: decoration.color),
      );
    }
    return Builder(
      builder: (context) => IdeActionButton(
        icon: decoration.icon,
        // The hover's markdown, its rule as a blank line.
        tooltip: hover.replaceAll('\n\n---\n\n', '\n\n'),
        size: size,
        iconSize: size,
        color: decoration.color,
        hoverPosition: IdeHoverPosition.right,
        onPressed: () {
          final box = context.findRenderObject()! as RenderBox;
          final rect = box.localToGlobal(Offset.zero) & box.size;
          unawaited(_commandMenu(rect, command.command, command.getOutput()));
        },
      ),
    );
  }

  /// A command mark's actions (VS Code's `_getCommandActions`): run it
  /// again, copy it or its output.
  Future<void> _commandMenu(Rect anchor, String command, String? output) {
    final instance = _instance;
    return showIdeMenu(
      context,
      anchor: anchor,
      entries: ideMenuGroups([
        [
          IdeMenuAction(
            'Rerun Command',
            onSelected: () {
              instance.writeText('$command\r');
              instance.focus();
            },
          ),
        ],
        [
          IdeMenuAction(
            'Copy Command',
            onSelected: () =>
                unawaited(Clipboard.setData(ClipboardData(text: command))),
          ),
          if (output != null && output.isNotEmpty)
            IdeMenuAction(
              'Copy Output',
              onSelected: () =>
                  unawaited(Clipboard.setData(ClipboardData(text: output))),
            ),
        ],
      ]),
    );
  }

  // --- Mouse ------------------------------------------------------------

  /// The hand over a link while the modifier is down, else the mouse's.
  void _cursorChanged() {
    final cursor = _link != null && _linkModifier
        ? SystemMouseCursors.click
        : _instance.mouse.mouseCursor;
    if (cursor != _cursor && mounted) setState(() => _cursor = cursor);
  }

  void _pointerDown(PointerDownEvent event, Offset position) {
    _linkPressed = event.buttons == kPrimaryButton && _linkModifier
        ? _link
        : null;
    if (_instance.mouse.handlePointerDown(event, position)) {
      unawaited(_menu(event.position));
    }
    _cursorChanged();
  }

  void _pointerMove(PointerMoveEvent event, Offset position) {
    if (_instance.mouse.handlePointerMove(event, position)) {
      unawaited(_menu(event.position));
    }
    unawaited(_lookUpLink(position));
  }

  void _pointerHover(PointerHoverEvent event, Offset position) {
    _instance.mouse.handlePointerHover(event, position);
    unawaited(_lookUpLink(position));
    _cursorChanged();
  }

  /// A click on a link with the modifier down opens it, as xterm.js'
  /// linkifier activates a link pressed and released on.
  void _pointerUp(PointerUpEvent event, Offset position) {
    _instance.mouse.handlePointerUp(event, position);
    final pressed = _linkPressed;
    final link = _link;
    _linkPressed = null;
    if (pressed != null &&
        link != null &&
        pressed.range == link.range &&
        pressed.text == link.text) {
      widget.onOpenLink?.call(link);
    }
  }

  // --- Links ------------------------------------------------------------

  /// VS Code's link modifier with `editor.multiCursorModifier` at its
  /// default (alt): ⌘ on macOS, Ctrl elsewhere.
  bool get _linkModifier {
    final keyboard = HardwareKeyboard.instance;
    return defaultTargetPlatform == TargetPlatform.macOS
        ? keyboard.isMetaPressed
        : keyboard.isControlPressed;
  }

  /// Finds the link at [position] on the grid (none: null).
  Future<void> _lookUpLink(Offset? position) async {
    _hover = position;
    final lookUp = ++_lookUp;
    final coords = position == null
        ? null
        : _render.getMouseReportCoords(position);
    final instance = _instance;
    final link = coords == null
        ? null
        : await instance.links.linkAt(
            coords.col,
            coords.row + instance.terminal.buffer.ydisp,
          );
    if (lookUp != _lookUp || !mounted) return;
    _link = link;
    _showLink();
  }

  /// Underlines the link under the pointer: a sure one (a URL, a path that
  /// is there) always, a word only with the modifier down, as VS Code's
  /// link decorations.
  void _showLink() {
    final link = _link;
    final terminal = _instance.terminal;
    if (link == null || !(link.isHighConfidence || _linkModifier)) {
      _render.linkUnderline = null;
    } else {
      final top = terminal.buffer.ydisp;
      _render.linkUnderline = TerminalLinkUnderline(
        x1: link.range.start.x - 1,
        y1: link.range.start.y - 1 - top,
        x2: link.range.end.x,
        y2: link.range.end.y - 1 - top,
        cols: terminal.cols,
      );
    }
    _cursorChanged();
  }

  /// Whether the wheel is the terminal's even with nothing to scroll: the
  /// app gets it, or (on the alternate screen) it becomes arrow keys.
  bool _capturesWheel() =>
      _instance.mouse.mouseEventsEnabled || _instance.source.isAlternateBuffer;

  /// `MenuId.TerminalInstanceContext`: edit, clear, kill.
  Future<void> _menu(Offset position) {
    final instance = _instance;
    final mac = defaultTargetPlatform == TargetPlatform.macOS;
    final windows = defaultTargetPlatform == TargetPlatform.windows;
    return showIdeMenu(
      context,
      position: position,
      entries: ideMenuGroups([
        [
          IdeMenuAction(
            'Copy',
            keybinding: mac
                ? '⌘C'
                : windows
                ? 'Ctrl+C'
                : 'Ctrl+Shift+C',
            enabled: instance.selection.hasSelection,
            onSelected: () => unawaited(instance.clipboard.copySelection()),
          ),
          IdeMenuAction(
            'Paste',
            keybinding: mac
                ? '⌘V'
                : windows
                ? 'Ctrl+V'
                : 'Ctrl+Shift+V',
            onSelected: () => unawaited(instance.clipboard.paste()),
          ),
          IdeMenuAction(
            'Select All',
            keybinding: mac ? '⌘A' : null,
            onSelected: instance.selection.selectAll,
          ),
        ],
        [IdeMenuAction('Clear', onSelected: instance.terminal.clear)],
        [
          if (widget.onKill case final kill?)
            IdeMenuAction('Kill Terminal', onSelected: kill),
        ],
      ]),
    );
  }

  /// VS Code's multi-line paste warning (without its "Do not ask me again"
  /// checkbox).
  Future<({TerminalPasteChoice choice, bool doNotAskAgain})> _confirmPaste(
    TerminalPastePrompt prompt,
  ) async {
    final choice = mounted
        ? await showIdeDialog(
            context,
            message: prompt.message,
            detail: prompt.detail,
            buttons: const ['Paste', 'Paste as one line'],
          )
        : null;
    _instance.focus();
    return (
      choice: switch (choice) {
        0 => TerminalPasteChoice.paste,
        1 => TerminalPasteChoice.pasteAsOneLine,
        _ => TerminalPasteChoice.cancel,
      },
      doNotAskAgain: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final instance = _instance;
    return CallbackShortcuts(
      bindings: _findKeys,
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [
            Positioned.fill(child: _terminal(instance)),
            Positioned.fill(child: _commandMarks(instance)),
            if (instance.find.isVisible) _findWidget(constraints),
          ],
        ),
      ),
    );
  }

  Widget _terminal(TerminalInstance instance) {
    return Focus(
      focusNode: instance.focusNode,
      onKeyEvent: _handleKey,
      child: MouseRegion(
        onExit: (_) => unawaited(_lookUpLink(null)),
        child: TerminalWidget(
          source: instance.source,
          controller: _render,
          focusNode: instance.focusNode,
          padding: TerminalView.padding,
          alignBottom: false,
          onResize: instance.resize,
          onPointerDown: _pointerDown,
          onPointerMove: _pointerMove,
          onPointerHover: _pointerHover,
          onPointerUp: _pointerUp,
          onPointerCancel: instance.mouse.handlePointerCancel,
          onWheel: instance.mouse.handlePointerScroll,
          onPanZoomUpdate: instance.mouse.handlePointerPanZoomUpdate,
          capturesWheel: _capturesWheel,
          mouseCursor: _cursor,
        ),
      ),
    );
  }
}
