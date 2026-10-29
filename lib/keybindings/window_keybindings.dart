// The app's windows' commands, as VS Code names them, and their keys
// (src/vs/workbench/electron-browser/actions/windowActions.ts and
// src/vs/workbench/electron-browser/desktop.contribution.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971): New Window, Close Window (⌘W
// too, where no editor is open), Switch Window… (⌃W on macOS), Toggle Full
// Screen (F11; ⌃⌘F on macOS, as its View menu has it).
//
// Zoom In, Zoom Out and Reset Zoom (⌘= / ⌘- / ⌘numpad0, Ctrl elsewhere)
// move the window's scale, the Appearance settings' Interface Size, by
// [CodeFont.uiScaleStep] at a time.
//
// Show Chat Window is BaoCode's: the chat's window back from an IDE's. It
// has no keys of its own: ⌘0 / Ctrl+0 are Focus Side Bar's.

import 'package:bao_editor/monaco/flutter/keybinding_entry.dart';

import 'default_keybindings.dart' show CommandInfo;

abstract final class WindowCommandIds {
  static const newWindow = 'workbench.action.newWindow';
  static const closeWindow = 'workbench.action.closeWindow';
  static const switchWindow = 'workbench.action.switchWindow';
  static const showChat = 'baocode.window.showChat';
  static const toggleFullScreen = 'workbench.action.toggleFullScreen';
  static const zoomIn = 'workbench.action.zoomIn';
  static const zoomOut = 'workbench.action.zoomOut';
  static const zoomReset = 'workbench.action.zoomReset';
}

final List<CommandInfo> windowCommands = [
  const CommandInfo(WindowCommandIds.newWindow, 'New Window'),
  const CommandInfo(WindowCommandIds.closeWindow, 'Close Window'),
  const CommandInfo(WindowCommandIds.switchWindow, 'Switch Window...'),
  const CommandInfo(
    WindowCommandIds.showChat,
    'Show Chat Window',
    category: 'View',
  ),
  const CommandInfo(
    WindowCommandIds.toggleFullScreen,
    'Toggle Full Screen',
    category: 'View',
  ),
  const CommandInfo(WindowCommandIds.zoomIn, 'Zoom In', category: 'View'),
  const CommandInfo(WindowCommandIds.zoomOut, 'Zoom Out', category: 'View'),
  const CommandInfo(WindowCommandIds.zoomReset, 'Reset Zoom', category: 'View'),
];

final List<KeybindingEntry> windowKeybindings = [
  const KeybindingEntry(
    key: 'ctrl+shift+n',
    mac: 'shift+cmd+n',
    command: WindowCommandIds.newWindow,
  ),
  const KeybindingEntry(
    win: 'ctrl+shift+w',
    linux: 'ctrl+shift+w',
    mac: 'shift+cmd+w',
    command: WindowCommandIds.closeWindow,
  ),
  const KeybindingEntry(
    win: 'alt+f4',
    linux: 'alt+f4',
    command: WindowCommandIds.closeWindow,
  ),
  // Where Close Editor has none to close (and not from the IDE's chat,
  // whose tabs it closes; nor the chat's window, whose panes).
  const KeybindingEntry(
    key: 'ctrl+w',
    mac: 'cmd+w',
    command: WindowCommandIds.closeWindow,
    when: '!chatMode && !editorIsOpen && !auxiliaryBarFocus',
  ),
  const KeybindingEntry(mac: 'ctrl+w', command: WindowCommandIds.switchWindow),
  const KeybindingEntry(
    key: 'f11',
    mac: 'ctrl+cmd+f',
    command: WindowCommandIds.toggleFullScreen,
  ),
  // As VS Code has them: ⌘= and ⌘+ (shifted) and the keypad's.
  const KeybindingEntry(
    key: 'ctrl+=',
    mac: 'cmd+=',
    command: WindowCommandIds.zoomIn,
  ),
  const KeybindingEntry(
    key: 'ctrl+shift+=',
    mac: 'shift+cmd+=',
    command: WindowCommandIds.zoomIn,
  ),
  const KeybindingEntry(
    key: 'ctrl+numpad_add',
    mac: 'cmd+numpad_add',
    command: WindowCommandIds.zoomIn,
  ),
  const KeybindingEntry(
    key: 'ctrl+-',
    mac: 'cmd+-',
    command: WindowCommandIds.zoomOut,
  ),
  const KeybindingEntry(
    key: 'ctrl+shift+-',
    mac: 'shift+cmd+-',
    command: WindowCommandIds.zoomOut,
  ),
  const KeybindingEntry(
    key: 'ctrl+numpad_subtract',
    mac: 'cmd+numpad_subtract',
    command: WindowCommandIds.zoomOut,
  ),
  const KeybindingEntry(
    key: 'ctrl+numpad0',
    mac: 'cmd+numpad0',
    command: WindowCommandIds.zoomReset,
  ),
];
