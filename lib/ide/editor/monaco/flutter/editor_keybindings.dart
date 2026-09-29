import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'editor_surface_controller.dart';

/// View services that keyboard commands need from the painted surface.
/// The surface implements this; commands never reach into its layout directly.
abstract interface class EditorViewHost {
  /// Whether user-originated text mutations are currently allowed.
  bool get canEdit;

  /// The offset [rows] visual rows above (negative) or below (positive)
  /// [offset], keeping the horizontal position [preferredX] when given (in
  /// unscrolled document coordinates). Returns the target and the x used, so
  /// repeated vertical moves can keep a sticky column.
  ({int offset, double x}) verticalTarget(
    int offset,
    int rows, {
    double? preferredX,
  });

  /// Number of fully visible rows, for page up/down.
  int get pageRowCount;

  /// Dispatches clipboard/select-all intents through the surface's Actions.
  void invokeTextAction(Intent intent);
}

/// Editor commands for a command palette: Monaco command id to label.
/// Run them with [runEditorCommand]; [editorCommandKeybindingLabel] gives
/// their shortcut text.
const Map<String, String> editorCommandLabels = {
  'undo': 'Undo',
  'redo': 'Redo',
  'editor.action.clipboardCutAction': 'Cut',
  'editor.action.clipboardCopyAction': 'Copy',
  'editor.action.clipboardPasteAction': 'Paste',
  'editor.action.selectAll': 'Select All',
  'editor.action.commentLine': 'Toggle Line Comment',
  'editor.action.blockComment': 'Toggle Block Comment',
  'editor.action.moveLinesUpAction': 'Move Line Up',
  'editor.action.moveLinesDownAction': 'Move Line Down',
  'editor.action.copyLinesUpAction': 'Copy Line Up',
  'editor.action.copyLinesDownAction': 'Copy Line Down',
  'editor.action.deleteLines': 'Delete Line',
  'editor.action.insertLineAfter': 'Insert Line Below',
  'editor.action.insertLineBefore': 'Insert Line Above',
  'editor.action.indentLines': 'Indent Line',
  'editor.action.outdentLines': 'Outdent Line',
  'expandLineSelection': 'Expand Line Selection',
  'deleteAllLeft': 'Delete All Left',
  'deleteAllRight': 'Delete All Right',
  'editor.action.addSelectionToNextFindMatch':
      'Add Selection to Next Find Match',
  'editor.action.moveSelectionToNextFindMatch':
      'Move Last Selection to Next Find Match',
  'editor.action.selectHighlights': 'Select All Occurrences of Find Match',
  'editor.action.changeAll': 'Change All Occurrences',
  'editor.action.insertCursorAbove': 'Add Cursor Above',
  'editor.action.insertCursorBelow': 'Add Cursor Below',
  'removeSecondaryCursors': 'Remove Secondary Cursors',
  'cursorUndo': 'Cursor Undo',
  'editor.action.transformToUppercase': 'Transform to Uppercase',
  'editor.action.transformToLowercase': 'Transform to Lowercase',
  'editor.action.detectIndentation': 'Detect Indentation from Content',
};

/// Runs the palette command [id]. Returns false for unknown ids, for edits
/// while [EditorViewHost.canEdit] is false, and when the command did not
/// apply (e.g. comments in a language without comment tokens).
bool runEditorCommand(
  String id,
  EditorSurfaceController c,
  EditorViewHost host,
) {
  final command = _commands[id];
  if (command == null) return false;
  if (command.edits && !host.canEdit) return false;
  return command.run(c, host);
}

/// The shortcut for [id] on [platform] (default: the current platform), in
/// VS Code's style (`⇧⌥↓` on macOS, `Shift+Alt+DownArrow` elsewhere), or null
/// when the command has no default keybinding.
String? editorCommandKeybindingLabel(String id, {TargetPlatform? platform}) {
  final command = _commands[id];
  if (command == null) return null;
  final mac = _isApple(platform ?? defaultTargetPlatform);
  final chord = mac ? command.mac : command.other;
  return chord?.label(mac: mac);
}

bool _isApple(TargetPlatform platform) =>
    platform == TargetPlatform.macOS || platform == TargetPlatform.iOS;

/// Handles a hardware key for the painted editor. Returns ignored for keys
/// the editor does not bind, including the workbench's shortcuts (save, find,
/// quick open, Cmd+K chords, tab switching, ...).
KeyEventResult handleEditorKeyEvent(
  EditorSurfaceController controller,
  EditorViewHost host,
  KeyEvent event,
) {
  if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
    return KeyEventResult.ignored;
  }
  final keyboard = HardwareKeyboard.instance;
  final mac = _isApple(defaultTargetPlatform);
  final pressed = EditorKeyChord(
    event.logicalKey,
    primary: mac ? keyboard.isMetaPressed : keyboard.isControlPressed,
    shift: keyboard.isShiftPressed,
    alt: keyboard.isAltPressed,
    macCtrl: mac && keyboard.isControlPressed,
  );
  if (!mac && keyboard.isMetaPressed) return KeyEventResult.ignored;
  // Let the input method handle keys while it is composing.
  final composing = controller.value.composing;
  if (composing.isValid && !composing.isCollapsed) {
    return KeyEventResult.ignored;
  }
  for (final entry in _commands.entries) {
    final chord = mac ? entry.value.mac : entry.value.other;
    if (chord == null || chord != pressed) continue;
    final command = entry.value;
    if (command.edits && !host.canEdit) return KeyEventResult.handled;
    command.run(controller, host);
    return KeyEventResult.handled;
  }
  return _handleCursorKey(controller, host, pressed, mac: mac)
      ? KeyEventResult.handled
      : KeyEventResult.ignored;
}

/// Navigation and basic editing keys that are not palette commands.
bool _handleCursorKey(
  EditorSurfaceController c,
  EditorViewHost host,
  EditorKeyChord k, {
  required bool mac,
}) {
  final key = k.key;
  final shift = k.shift;
  bool mods({bool primary = false, bool alt = false, bool macCtrl = false}) =>
      k.primary == primary && k.alt == alt && k.macCtrl == macCtrl;
  // The word modifier: Option on macOS, Ctrl elsewhere.
  final word = mac ? mods(alt: true) : mods(primary: true);
  final plain = mods();

  if (key == LogicalKeyboardKey.arrowLeft ||
      key == LogicalKeyboardKey.arrowRight) {
    final left = key == LogicalKeyboardKey.arrowLeft;
    if (plain) {
      c.moveHorizontal(left ? -1 : 1, extend: shift);
    } else if (word) {
      left ? c.moveWordLeft(extend: shift) : c.moveWordRight(extend: shift);
    } else if (mac && mods(primary: true)) {
      left ? c.moveToLineStart(extend: shift) : c.moveToLineEnd(extend: shift);
    } else if (shift && mods(primary: true, alt: true)) {
      c.columnSelectMove(columns: left ? -1 : 1);
    } else {
      return false;
    }
    return true;
  }
  if (key == LogicalKeyboardKey.arrowUp ||
      key == LogicalKeyboardKey.arrowDown) {
    final up = key == LogicalKeyboardKey.arrowUp;
    if (plain) {
      c.moveVertical(up ? -1 : 1, host.verticalTarget, extend: shift);
    } else if (mac && mods(primary: true)) {
      up
          ? c.moveToDocumentStart(extend: shift)
          : c.moveToDocumentEnd(extend: shift);
    } else if (shift && mods(primary: true, alt: true)) {
      c.columnSelectMove(lines: up ? -1 : 1);
    } else {
      return false;
    }
    return true;
  }
  if (key == LogicalKeyboardKey.pageUp || key == LogicalKeyboardKey.pageDown) {
    if (!plain) return false;
    final rows = host.pageRowCount;
    c.moveVertical(
      key == LogicalKeyboardKey.pageUp ? -rows : rows,
      host.verticalTarget,
      extend: shift,
    );
    return true;
  }
  if (key == LogicalKeyboardKey.home || key == LogicalKeyboardKey.end) {
    final home = key == LogicalKeyboardKey.home;
    if (plain) {
      home ? c.moveToLineStart(extend: shift) : c.moveToLineEnd(extend: shift);
    } else if (mods(primary: true)) {
      home
          ? c.moveToDocumentStart(extend: shift)
          : c.moveToDocumentEnd(extend: shift);
    } else {
      return false;
    }
    return true;
  }
  if (key == LogicalKeyboardKey.escape) {
    // leaveSnippet outranks cancelSelection (EditorContrib + 30).
    return plain && (c.cancelSnippet() || (!shift && c.cancelSelection()));
  }
  if (key == LogicalKeyboardKey.backspace || key == LogicalKeyboardKey.delete) {
    final back = key == LogicalKeyboardKey.backspace;
    final void Function() action;
    if (plain) {
      // Shift+Backspace behaves as Backspace, like Monaco.
      action = back ? c.deleteBackward : c.deleteForward;
    } else if (word && !shift) {
      action = back ? c.deleteWordLeft : c.deleteWordRight;
    } else if (mac && mods(primary: true) && !shift) {
      action = back ? c.deleteAllLeft : c.deleteAllRight;
    } else {
      return false;
    }
    if (host.canEdit) action();
    return true;
  }
  if (key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter) {
    if (!plain) return false;
    if (host.canEdit) c.newline();
    return true;
  }
  if (key == LogicalKeyboardKey.tab) {
    if (!plain || !host.canEdit) return false;
    // jumpToNext/PrevSnippetPlaceholder in snippet mode.
    if (shift ? c.prevSnippetPlaceholder() : c.nextSnippetPlaceholder()) {
      return true;
    }
    shift ? c.outdentLines() : c.tab();
    return true;
  }
  if (k.primary && !k.alt && !k.macCtrl) {
    if (key == LogicalKeyboardKey.keyZ) {
      if (host.canEdit) shift ? c.redo() : c.undo();
      return true;
    }
    if (key == LogicalKeyboardKey.keyY && !mac && !shift) {
      if (host.canEdit) c.redo();
      return true;
    }
  }
  return false;
}

/// macOS can deliver editing keys as native selectors instead of key events.
/// Unknown selectors are deliberately left alone rather than guessed.
void handleEditorSelector(
  EditorSurfaceController controller,
  EditorViewHost host,
  String selectorName,
) {
  final c = controller;
  void edit(void Function() action) {
    if (host.canEdit) action();
  }

  void vertical(int rows, {bool extend = false}) =>
      c.moveVertical(rows, host.verticalTarget, extend: extend);

  switch (selectorName) {
    case 'deleteBackward:':
    case 'deleteBackwardByDecomposingPreviousCharacter:':
      edit(c.deleteBackward);
    case 'deleteForward:':
      edit(c.deleteForward);
    case 'deleteWordBackward:':
      edit(c.deleteWordLeft);
    case 'deleteWordForward:':
      edit(c.deleteWordRight);
    case 'deleteToBeginningOfLine:':
    case 'deleteToBeginningOfParagraph:':
      edit(c.deleteAllLeft);
    case 'deleteToEndOfLine:':
    case 'deleteToEndOfParagraph:':
      edit(c.deleteAllRight);
    case 'insertNewline:':
    case 'insertLineBreak:':
    case 'insertNewlineIgnoringFieldEditor:':
      edit(c.newline);
    case 'insertTab:':
    case 'insertTabIgnoringFieldEditor:':
      edit(() => c.nextSnippetPlaceholder() || _done(c.tab));
    case 'insertBacktab:':
      edit(() => c.prevSnippetPlaceholder() || _done(c.outdentLines));
    case 'cancelOperation:':
      if (!c.cancelSnippet()) c.cancelSelection();
    case 'moveLeft:':
    case 'moveBackward:':
      c.moveHorizontal(-1);
    case 'moveRight:':
    case 'moveForward:':
      c.moveHorizontal(1);
    case 'moveLeftAndModifySelection:':
    case 'moveBackwardAndModifySelection:':
      c.moveHorizontal(-1, extend: true);
    case 'moveRightAndModifySelection:':
    case 'moveForwardAndModifySelection:':
      c.moveHorizontal(1, extend: true);
    case 'moveWordLeft:':
    case 'moveWordBackward:':
      c.moveWordLeft();
    case 'moveWordRight:':
    case 'moveWordForward:':
      c.moveWordRight();
    case 'moveWordLeftAndModifySelection:':
    case 'moveWordBackwardAndModifySelection:':
      c.moveWordLeft(extend: true);
    case 'moveWordRightAndModifySelection:':
    case 'moveWordForwardAndModifySelection:':
      c.moveWordRight(extend: true);
    case 'moveToBeginningOfLine:':
    case 'moveToLeftEndOfLine:':
    case 'moveToBeginningOfParagraph:':
      c.moveToLineStart();
    case 'moveToEndOfLine:':
    case 'moveToRightEndOfLine:':
    case 'moveToEndOfParagraph:':
      c.moveToLineEnd();
    case 'moveToBeginningOfLineAndModifySelection:':
    case 'moveToLeftEndOfLineAndModifySelection:':
    case 'moveToBeginningOfParagraphAndModifySelection:':
    case 'moveParagraphBackwardAndModifySelection:':
      c.moveToLineStart(extend: true);
    case 'moveToEndOfLineAndModifySelection:':
    case 'moveToRightEndOfLineAndModifySelection:':
    case 'moveToEndOfParagraphAndModifySelection:':
    case 'moveParagraphForwardAndModifySelection:':
      c.moveToLineEnd(extend: true);
    case 'moveToBeginningOfDocument:':
      c.moveToDocumentStart();
    case 'moveToEndOfDocument:':
      c.moveToDocumentEnd();
    case 'moveToBeginningOfDocumentAndModifySelection:':
      c.moveToDocumentStart(extend: true);
    case 'moveToEndOfDocumentAndModifySelection:':
      c.moveToDocumentEnd(extend: true);
    case 'moveUp:':
      vertical(-1);
    case 'moveDown:':
      vertical(1);
    case 'moveUpAndModifySelection:':
      vertical(-1, extend: true);
    case 'moveDownAndModifySelection:':
      vertical(1, extend: true);
    case 'pageUp:':
    case 'scrollPageUp:':
      vertical(-host.pageRowCount);
    case 'pageDown:':
    case 'scrollPageDown:':
      vertical(host.pageRowCount);
    case 'pageUpAndModifySelection:':
      vertical(-host.pageRowCount, extend: true);
    case 'pageDownAndModifySelection:':
      vertical(host.pageRowCount, extend: true);
    case 'copy:':
      c.copy();
    case 'cut:':
      c.cut(canEdit: () => host.canEdit);
    case 'paste:':
      c.paste(canEdit: () => host.canEdit);
    case 'selectAll:':
      host.invokeTextAction(
        const SelectAllTextIntent(SelectionChangedCause.keyboard),
      );
    case 'undo:':
      edit(c.undo);
    case 'redo:':
      edit(c.redo);
    default:
      break;
  }
}

/// Language-feature commands (Monaco command id to label). The IDE editor,
/// which owns the language services, dispatches them: match keys with
/// [matchEditorLanguageKey]; [editorLanguageKeybindingLabel] gives labels.
const Map<String, String> editorLanguageCommandLabels = {
  'editor.action.revealDefinition': 'Go to Definition',
  'editor.action.goToTypeDefinition': 'Go to Type Definition',
  'editor.action.goToImplementation': 'Go to Implementations',
  'editor.action.goToReferences': 'Go to References',
  'editor.action.rename': 'Rename Symbol',
  'editor.action.formatDocument': 'Format Document',
  'editor.action.formatSelection': 'Format Selection',
  'editor.action.quickFix': 'Quick Fix...',
  'editor.action.refactor': 'Refactor...',
  'editor.action.sourceAction': 'Source Action...',
  'editor.action.triggerSuggest': 'Trigger Suggest',
  'editor.action.triggerParameterHints': 'Trigger Parameter Hints',
  'editor.action.showHover': 'Show or Focus Hover',
  'editor.action.marker.nextInFiles':
      'Go to Next Problem in Files (Error, Warning, Info)',
  'editor.action.marker.prevInFiles':
      'Go to Previous Problem in Files (Error, Warning, Info)',
};

/// One keybinding: a chord, or a two-chord sequence such as ⌘K ⌘I.
@immutable
class EditorKeybinding {
  const EditorKeybinding(this.first, [this.second]);

  final EditorKeyChord first;
  final EditorKeyChord? second;

  String label({required bool mac}) => second == null
      ? first.label(mac: mac)
      : '${first.label(mac: mac)} ${second!.label(mac: mac)}';
}

/// Upstream default keybindings of [editorLanguageCommandLabels]
/// (`(mac, other)`); commands without a default are absent.
const Map<String, (EditorKeybinding, EditorKeybinding)>
editorLanguageKeybindings = {
  'editor.action.revealDefinition': (
    EditorKeybinding(EditorKeyChord(LogicalKeyboardKey.f12)),
    EditorKeybinding(EditorKeyChord(LogicalKeyboardKey.f12)),
  ),
  'editor.action.goToImplementation': (
    EditorKeybinding(EditorKeyChord(LogicalKeyboardKey.f12, primary: true)),
    EditorKeybinding(EditorKeyChord(LogicalKeyboardKey.f12, primary: true)),
  ),
  'editor.action.goToReferences': (
    EditorKeybinding(EditorKeyChord(LogicalKeyboardKey.f12, shift: true)),
    EditorKeybinding(EditorKeyChord(LogicalKeyboardKey.f12, shift: true)),
  ),
  'editor.action.rename': (
    EditorKeybinding(EditorKeyChord(LogicalKeyboardKey.f2)),
    EditorKeybinding(EditorKeyChord(LogicalKeyboardKey.f2)),
  ),
  'editor.action.formatDocument': (
    EditorKeybinding(
      EditorKeyChord(LogicalKeyboardKey.keyF, shift: true, alt: true),
    ),
    EditorKeybinding(
      EditorKeyChord(LogicalKeyboardKey.keyF, shift: true, alt: true),
    ),
  ),
  'editor.action.formatSelection': (
    EditorKeybinding(
      EditorKeyChord(LogicalKeyboardKey.keyK, primary: true),
      EditorKeyChord(LogicalKeyboardKey.keyF, primary: true),
    ),
    EditorKeybinding(
      EditorKeyChord(LogicalKeyboardKey.keyK, primary: true),
      EditorKeyChord(LogicalKeyboardKey.keyF, primary: true),
    ),
  ),
  'editor.action.quickFix': (
    EditorKeybinding(EditorKeyChord(LogicalKeyboardKey.period, primary: true)),
    EditorKeybinding(EditorKeyChord(LogicalKeyboardKey.period, primary: true)),
  ),
  'editor.action.refactor': (
    EditorKeybinding(
      EditorKeyChord(LogicalKeyboardKey.keyR, macCtrl: true, shift: true),
    ),
    EditorKeybinding(
      EditorKeyChord(LogicalKeyboardKey.keyR, primary: true, shift: true),
    ),
  ),
  'editor.action.triggerSuggest': (
    EditorKeybinding(EditorKeyChord(LogicalKeyboardKey.space, macCtrl: true)),
    EditorKeybinding(EditorKeyChord(LogicalKeyboardKey.space, primary: true)),
  ),
  'editor.action.triggerParameterHints': (
    EditorKeybinding(
      EditorKeyChord(LogicalKeyboardKey.space, primary: true, shift: true),
    ),
    EditorKeybinding(
      EditorKeyChord(LogicalKeyboardKey.space, primary: true, shift: true),
    ),
  ),
  'editor.action.showHover': (
    EditorKeybinding(
      EditorKeyChord(LogicalKeyboardKey.keyK, primary: true),
      EditorKeyChord(LogicalKeyboardKey.keyI, primary: true),
    ),
    EditorKeybinding(
      EditorKeyChord(LogicalKeyboardKey.keyK, primary: true),
      EditorKeyChord(LogicalKeyboardKey.keyI, primary: true),
    ),
  ),
  'editor.action.marker.nextInFiles': (
    EditorKeybinding(EditorKeyChord(LogicalKeyboardKey.f8)),
    EditorKeybinding(EditorKeyChord(LogicalKeyboardKey.f8)),
  ),
  'editor.action.marker.prevInFiles': (
    EditorKeybinding(EditorKeyChord(LogicalKeyboardKey.f8, shift: true)),
    EditorKeybinding(EditorKeyChord(LogicalKeyboardKey.f8, shift: true)),
  ),
};

/// The label of a language command's keybinding (`⌘K ⌘I`), or null.
String? editorLanguageKeybindingLabel(String id, {TargetPlatform? platform}) {
  final binding = editorLanguageKeybindings[id];
  if (binding == null) return null;
  final mac = _isApple(platform ?? defaultTargetPlatform);
  return (mac ? binding.$1 : binding.$2).label(mac: mac);
}

/// The chord [event] presses on the current platform (null for key-ups).
EditorKeyChord? editorKeyChordOf(KeyEvent event) {
  if (event is! KeyDownEvent && event is! KeyRepeatEvent) return null;
  final keyboard = HardwareKeyboard.instance;
  final mac = _isApple(defaultTargetPlatform);
  return EditorKeyChord(
    event.logicalKey,
    primary: mac ? keyboard.isMetaPressed : keyboard.isControlPressed,
    shift: keyboard.isShiftPressed,
    alt: keyboard.isAltPressed,
    macCtrl: mac && keyboard.isControlPressed,
  );
}

/// Matches [chord] against [editorLanguageKeybindings]: a command id, or
/// [editorChordPrefix] when it starts a two-chord binding. With [pending]
/// (the first chord already pressed) only second chords match.
String? matchEditorLanguageKey(
  EditorKeyChord chord, {
  EditorKeyChord? pending,
}) {
  final mac = _isApple(defaultTargetPlatform);
  var prefix = false;
  for (final MapEntry(key: id, value: bindings)
      in editorLanguageKeybindings.entries) {
    final binding = mac ? bindings.$1 : bindings.$2;
    if (pending != null) {
      if (binding.first == pending && binding.second == chord) return id;
    } else if (binding.first == chord) {
      if (binding.second == null) return id;
      prefix = true;
    }
  }
  return prefix ? editorChordPrefix : null;
}

/// Returned by [matchEditorLanguageKey] for the first chord of a sequence.
const String editorChordPrefix = '<chord>';

/// A key with modifiers. [primary] is Cmd on macOS and Ctrl elsewhere;
/// [macCtrl] is the Control key on macOS.
@immutable
class EditorKeyChord {
  const EditorKeyChord(
    this.key, {
    this.primary = false,
    this.shift = false,
    this.alt = false,
    this.macCtrl = false,
  });

  final LogicalKeyboardKey key;
  final bool primary;
  final bool shift;
  final bool alt;
  final bool macCtrl;

  @override
  bool operator ==(Object other) =>
      other is EditorKeyChord &&
      other.key == key &&
      other.primary == primary &&
      other.shift == shift &&
      other.alt == alt &&
      other.macCtrl == macCtrl;

  @override
  int get hashCode => Object.hash(key, primary, shift, alt, macCtrl);

  String label({required bool mac}) {
    final name = _keyNames[key] ?? key.keyLabel.toUpperCase();
    if (mac) {
      return '${macCtrl ? '⌃' : ''}${alt ? '⌥' : ''}${shift ? '⇧' : ''}'
          '${primary ? '⌘' : ''}${_macKeyNames[key] ?? name}';
    }
    return [
      if (primary) 'Ctrl',
      if (shift) 'Shift',
      if (alt) 'Alt',
      name,
    ].join('+');
  }

  static final Map<LogicalKeyboardKey, String> _keyNames = {
    LogicalKeyboardKey.arrowUp: 'UpArrow',
    LogicalKeyboardKey.arrowDown: 'DownArrow',
    LogicalKeyboardKey.arrowLeft: 'LeftArrow',
    LogicalKeyboardKey.arrowRight: 'RightArrow',
    LogicalKeyboardKey.enter: 'Enter',
    LogicalKeyboardKey.backspace: 'Backspace',
    LogicalKeyboardKey.delete: 'Delete',
    LogicalKeyboardKey.escape: 'Escape',
    LogicalKeyboardKey.slash: '/',
    LogicalKeyboardKey.bracketLeft: '[',
    LogicalKeyboardKey.bracketRight: ']',
    LogicalKeyboardKey.period: '.',
    LogicalKeyboardKey.space: 'Space',
    LogicalKeyboardKey.f2: 'F2',
    LogicalKeyboardKey.f8: 'F8',
    LogicalKeyboardKey.f12: 'F12',
  };

  static final Map<LogicalKeyboardKey, String> _macKeyNames = {
    LogicalKeyboardKey.arrowUp: '↑',
    LogicalKeyboardKey.arrowDown: '↓',
    LogicalKeyboardKey.arrowLeft: '←',
    LogicalKeyboardKey.arrowRight: '→',
  };
}

class _Command {
  const _Command(this.run, {this.mac, this.other, this.edits = false});

  final bool Function(EditorSurfaceController c, EditorViewHost host) run;
  final EditorKeyChord? mac;
  final EditorKeyChord? other;

  /// Whether the command changes text (disabled when the host cannot edit).
  final bool edits;
}

bool _done(void Function() action) {
  action();
  return true;
}

// Default keybindings from upstream (primary = CtrlCmd). Cmd/Ctrl+K chords
// are left to the workbench.
final Map<String, _Command> _commands = {
  'undo': _Command((c, _) => c.undo(), edits: true),
  'redo': _Command((c, _) => c.redo(), edits: true),
  'editor.action.clipboardCutAction': _Command(
    (c, h) => _done(() => c.cut(canEdit: () => h.canEdit)),
    mac: const EditorKeyChord(LogicalKeyboardKey.keyX, primary: true),
    other: const EditorKeyChord(LogicalKeyboardKey.keyX, primary: true),
    edits: true,
  ),
  'editor.action.clipboardCopyAction': _Command(
    (c, _) => _done(c.copy),
    mac: const EditorKeyChord(LogicalKeyboardKey.keyC, primary: true),
    other: const EditorKeyChord(LogicalKeyboardKey.keyC, primary: true),
  ),
  'editor.action.clipboardPasteAction': _Command(
    (c, h) => _done(() => c.paste(canEdit: () => h.canEdit)),
    mac: const EditorKeyChord(LogicalKeyboardKey.keyV, primary: true),
    other: const EditorKeyChord(LogicalKeyboardKey.keyV, primary: true),
    edits: true,
  ),
  'editor.action.selectAll': _Command(
    (c, _) => _done(c.selectAll),
    mac: const EditorKeyChord(LogicalKeyboardKey.keyA, primary: true),
    other: const EditorKeyChord(LogicalKeyboardKey.keyA, primary: true),
  ),
  'editor.action.commentLine': _Command(
    (c, _) => c.toggleLineComment(),
    mac: const EditorKeyChord(LogicalKeyboardKey.slash, primary: true),
    other: const EditorKeyChord(LogicalKeyboardKey.slash, primary: true),
    edits: true,
  ),
  'editor.action.blockComment': _Command(
    (c, _) => c.toggleBlockComment(),
    mac: const EditorKeyChord(LogicalKeyboardKey.keyA, shift: true, alt: true),
    other: const EditorKeyChord(
      LogicalKeyboardKey.keyA,
      shift: true,
      alt: true,
    ),
    edits: true,
  ),
  'editor.action.moveLinesUpAction': _Command(
    (c, _) => _done(() => c.moveLines(down: false)),
    mac: const EditorKeyChord(LogicalKeyboardKey.arrowUp, alt: true),
    other: const EditorKeyChord(LogicalKeyboardKey.arrowUp, alt: true),
    edits: true,
  ),
  'editor.action.moveLinesDownAction': _Command(
    (c, _) => _done(() => c.moveLines(down: true)),
    mac: const EditorKeyChord(LogicalKeyboardKey.arrowDown, alt: true),
    other: const EditorKeyChord(LogicalKeyboardKey.arrowDown, alt: true),
    edits: true,
  ),
  'editor.action.copyLinesUpAction': _Command(
    (c, _) => _done(() => c.copyLines(down: false)),
    mac: const EditorKeyChord(
      LogicalKeyboardKey.arrowUp,
      shift: true,
      alt: true,
    ),
    other: const EditorKeyChord(
      LogicalKeyboardKey.arrowUp,
      shift: true,
      alt: true,
    ),
    edits: true,
  ),
  'editor.action.copyLinesDownAction': _Command(
    (c, _) => _done(() => c.copyLines(down: true)),
    mac: const EditorKeyChord(
      LogicalKeyboardKey.arrowDown,
      shift: true,
      alt: true,
    ),
    other: const EditorKeyChord(
      LogicalKeyboardKey.arrowDown,
      shift: true,
      alt: true,
    ),
    edits: true,
  ),
  'editor.action.deleteLines': _Command(
    (c, _) => _done(c.deleteLines),
    mac: const EditorKeyChord(
      LogicalKeyboardKey.keyK,
      primary: true,
      shift: true,
    ),
    other: const EditorKeyChord(
      LogicalKeyboardKey.keyK,
      primary: true,
      shift: true,
    ),
    edits: true,
  ),
  'editor.action.insertLineAfter': _Command(
    (c, _) => _done(c.insertLineAfter),
    mac: const EditorKeyChord(LogicalKeyboardKey.enter, primary: true),
    other: const EditorKeyChord(LogicalKeyboardKey.enter, primary: true),
    edits: true,
  ),
  'editor.action.insertLineBefore': _Command(
    (c, _) => _done(c.insertLineBefore),
    mac: const EditorKeyChord(
      LogicalKeyboardKey.enter,
      primary: true,
      shift: true,
    ),
    other: const EditorKeyChord(
      LogicalKeyboardKey.enter,
      primary: true,
      shift: true,
    ),
    edits: true,
  ),
  'editor.action.indentLines': _Command(
    (c, _) => _done(c.indentLines),
    mac: const EditorKeyChord(LogicalKeyboardKey.bracketRight, primary: true),
    other: const EditorKeyChord(LogicalKeyboardKey.bracketRight, primary: true),
    edits: true,
  ),
  'editor.action.outdentLines': _Command(
    (c, _) => _done(c.outdentLines),
    mac: const EditorKeyChord(LogicalKeyboardKey.bracketLeft, primary: true),
    other: const EditorKeyChord(LogicalKeyboardKey.bracketLeft, primary: true),
    edits: true,
  ),
  'expandLineSelection': _Command(
    (c, _) => _done(c.expandLineSelection),
    mac: const EditorKeyChord(LogicalKeyboardKey.keyL, primary: true),
    other: const EditorKeyChord(LogicalKeyboardKey.keyL, primary: true),
  ),
  'deleteAllLeft': _Command(
    (c, _) => _done(c.deleteAllLeft),
    mac: const EditorKeyChord(LogicalKeyboardKey.backspace, primary: true),
    edits: true,
  ),
  'deleteAllRight': _Command(
    (c, _) => _done(c.deleteAllRight),
    mac: const EditorKeyChord(LogicalKeyboardKey.keyK, macCtrl: true),
    edits: true,
  ),
  'editor.action.addSelectionToNextFindMatch': _Command(
    (c, _) => c.addSelectionToNextFindMatch(),
    mac: const EditorKeyChord(LogicalKeyboardKey.keyD, primary: true),
    other: const EditorKeyChord(LogicalKeyboardKey.keyD, primary: true),
  ),
  'editor.action.moveSelectionToNextFindMatch': _Command(
    (c, _) => c.moveSelectionToNextFindMatch(),
  ),
  'editor.action.selectHighlights': _Command(
    (c, _) => c.selectAllOccurrences(),
    mac: const EditorKeyChord(
      LogicalKeyboardKey.keyL,
      primary: true,
      shift: true,
    ),
    other: const EditorKeyChord(
      LogicalKeyboardKey.keyL,
      primary: true,
      shift: true,
    ),
  ),
  'editor.action.changeAll': _Command(
    (c, _) => c.selectAllOccurrences(),
    mac: const EditorKeyChord(LogicalKeyboardKey.f2, primary: true),
    other: const EditorKeyChord(LogicalKeyboardKey.f2, primary: true),
    edits: true,
  ),
  'editor.action.insertCursorAbove': _Command(
    (c, h) => _done(() => c.addCursorsVertically(-1, h.verticalTarget)),
    mac: const EditorKeyChord(
      LogicalKeyboardKey.arrowUp,
      primary: true,
      alt: true,
    ),
    other: const EditorKeyChord(
      LogicalKeyboardKey.arrowUp,
      primary: true,
      alt: true,
    ),
  ),
  'editor.action.insertCursorBelow': _Command(
    (c, h) => _done(() => c.addCursorsVertically(1, h.verticalTarget)),
    mac: const EditorKeyChord(
      LogicalKeyboardKey.arrowDown,
      primary: true,
      alt: true,
    ),
    other: const EditorKeyChord(
      LogicalKeyboardKey.arrowDown,
      primary: true,
      alt: true,
    ),
  ),
  'removeSecondaryCursors': _Command(
    (c, _) => c.hasMultipleSelections && c.cancelSelection(),
  ),
  'cursorUndo': _Command(
    (c, _) => c.cursorUndo(),
    mac: const EditorKeyChord(LogicalKeyboardKey.keyU, primary: true),
    other: const EditorKeyChord(LogicalKeyboardKey.keyU, primary: true),
  ),
  'editor.action.transformToUppercase': _Command(
    (c, _) => _done(() => c.transformCase(upper: true)),
    edits: true,
  ),
  'editor.action.transformToLowercase': _Command(
    (c, _) => _done(() => c.transformCase(upper: false)),
    edits: true,
  ),
  'editor.action.detectIndentation': _Command(
    (c, _) => _done(c.detectIndentation),
  ),
};
