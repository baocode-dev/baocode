import 'package:bao_editor/monaco/flutter/keybinding_entry.dart';
import 'package:baocode/keybindings/default_keybindings.dart';
import 'package:baocode/keybindings/window_keybindings.dart';
import 'package:baocode/theme/code_font.dart';
import 'package:flutter_test/flutter_test.dart';

/// Zoom In / Zoom Out: the Interface Size setting, from the keys VS Code
/// has for them.
void main() {
  List<String> keysOf(String command, KeybindingPlatform platform) => [
    for (final entry in defaultKeybindings)
      if (entry.command == command) ?entry.keyFor(platform),
  ];

  test('⌘= / ⌘- on macOS, Ctrl elsewhere, the keypad\'s too', () {
    expect(keysOf(WindowCommandIds.zoomIn, KeybindingPlatform.mac), [
      'cmd+=',
      'shift+cmd+=',
      'cmd+numpad_add',
    ]);
    expect(keysOf(WindowCommandIds.zoomOut, KeybindingPlatform.mac), [
      'cmd+-',
      'shift+cmd+-',
      'cmd+numpad_subtract',
    ]);
    expect(keysOf(WindowCommandIds.zoomIn, KeybindingPlatform.windows), [
      'ctrl+=',
      'ctrl+shift+=',
      'ctrl+numpad_add',
    ]);
    expect(keysOf(WindowCommandIds.zoomOut, KeybindingPlatform.linux), [
      'ctrl+-',
      'ctrl+shift+-',
      'ctrl+numpad_subtract',
    ]);
    expect(keysOf(WindowCommandIds.zoomReset, KeybindingPlatform.mac), [
      'cmd+numpad0',
    ]);
    expect(commandCatalog[WindowCommandIds.zoomIn]?.title, 'Zoom In');
    expect(commandCatalog[WindowCommandIds.zoomOut]?.title, 'Zoom Out');
  });

  test('each press moves the scale by 2, within the slider\'s range', () {
    expect(CodeFont.zoomedUiScale(100, 1), 102);
    expect(CodeFont.zoomedUiScale(100, -1), 98);
    expect(CodeFont.zoomedUiScale(CodeFont.maxUiScale - 1, 1), 150);
    expect(CodeFont.zoomedUiScale(CodeFont.minUiScale, -1), 90);
  });
}
