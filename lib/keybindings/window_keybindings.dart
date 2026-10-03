// The app's windows' commands, as VS Code names them, and their keys
// (src/vs/workbench/electron-browser/actions/windowActions.ts and
// src/vs/workbench/electron-browser/desktop.contribution.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971): New Window, Close Window (⌘W
// too, where no editor is open), Switch Window… (⌃W on macOS).
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
];
