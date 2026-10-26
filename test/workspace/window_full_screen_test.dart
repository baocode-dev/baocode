import 'package:bao_editor/monaco/flutter/keybinding_entry.dart';
import 'package:baocode/keybindings/default_keybindings.dart';
import 'package:baocode/keybindings/window_keybindings.dart';
import 'package:baocode/workspace/window_controls.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Full screen, from the View menu or its keys, on every desktop (#299).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Toggle Full Screen is F11, and ⌃⌘F on macOS', () {
    final bound = [
      for (final entry in defaultKeybindings)
        if (entry.command == WindowCommandIds.toggleFullScreen) entry,
    ];
    expect(bound, hasLength(1));
    expect(bound.single.keyFor(KeybindingPlatform.windows), 'f11');
    expect(bound.single.keyFor(KeybindingPlatform.linux), 'f11');
    expect(bound.single.keyFor(KeybindingPlatform.mac), 'ctrl+cmd+f');
    expect(
      commandCatalog[WindowCommandIds.toggleFullScreen]?.title,
      'Toggle Full Screen',
    );
  });

  test('the window is asked, and says whether it is full screen now', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final asked = <String>[];
    var full = false;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('baocode/window'), (
      call,
    ) async {
      asked.add(call.method);
      return full = !full;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        const MethodChannel('baocode/window'),
        null,
      ),
    );

    expect(await WindowControls.toggleFullScreen(viewId: 0), isTrue);
    expect(await WindowControls.toggleFullScreen(viewId: 0), isFalse);
    expect(asked, ['toggleFullScreen', 'toggleFullScreen']);
  });

  test('where there is no window, nothing is asked', () async {
    expect(WindowControls.canFullScreen, isFalse);
    expect(await WindowControls.toggleFullScreen(), isNull);
  });
}
