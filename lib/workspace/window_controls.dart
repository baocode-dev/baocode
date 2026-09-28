import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../chat/chat_models.dart';

/// One of the window's own buttons, over a header the app draws itself: the
/// system hit-tests and acts on those pixels, so the header only paints them
/// (see [WindowControls.hoveredWindowButton]).
enum WindowButton { minimize, maximize, close }

/// Controls of the native window, where there is one (the desktop app; see
/// MainFlutterWindow.swift and windows/runner/window_channel.cpp).
abstract final class WindowControls {
  static const _channel = MethodChannel('monad/window');

  /// Whether the app runs in a window to command: the desktop app, not a
  /// browser tab.
  static bool get isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows);

  /// Whether the window is the app's own to draw: Windows, where the header
  /// carries the menus, the session's tools and the window buttons (see
  /// workspace/window_header/). Elsewhere the system draws the caption —
  /// macOS with its traffic lights over a title bar Flutter paints under
  /// them.
  static bool get drawsHeader =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  /// Whether the window can be kept on top.
  static bool get canKeepOnTop => isDesktop;

  /// Keeps the window above other apps' windows, or not.
  static Future<void> setAlwaysOnTop(bool onTop) async {
    if (!canKeepOnTop) return;
    try {
      await _channel.invokeMethod<void>('setAlwaysOnTop', onTop);
    } on MissingPluginException {
      // A host without the channel (e.g. tests).
    }
  }

  /// Which of them the pointer is over, or null; the window reports it.
  static final ValueNotifier<WindowButton?> hoveredWindowButton =
      ValueNotifier(null);

  /// Whether the window fills the screen, so its button offers the way back
  /// down; the window reports it.
  static final ValueNotifier<bool> maximized = ValueNotifier(false);

  /// Starts taking what the window reports back: which button the pointer is
  /// over, whether it is maximized. The channel takes one handler, so this
  /// and [handleEditCommands] are for different platforms.
  static void handleWindowEvents() {
    if (!drawsHeader) return;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'captionHover':
          hoveredWindowButton.value = _buttonNamed('${call.arguments}');
        case 'maximized':
          maximized.value = call.arguments == true;
      }
      return null;
    });
  }

  static WindowButton? _buttonNamed(String name) => switch (name) {
    'minimize' => WindowButton.minimize,
    'maximize' => WindowButton.maximize,
    'close' => WindowButton.close,
    _ => null,
  };

  /// Tells the window where the header the app draws keeps its controls, so
  /// the system drags the rest of the strip and runs the window buttons
  /// itself (with its own animations and Snap Layouts).
  ///
  /// The rectangles are in the app's own pixels, from the top left of the
  /// window: [controls] are the ones Flutter keeps for itself (the menu bar
  /// and the buttons beside it), the other three are the window buttons.
  static Future<void> setHitTestAreas({
    required double height,
    required List<Rect> controls,
    required Rect minimize,
    required Rect maximize,
    required Rect close,
  }) async {
    if (!drawsHeader) return;
    try {
      await _channel.invokeMethod<void>('setHitTestAreas', {
        'height': height,
        'controls': [for (final rect in controls) _encoded(rect)],
        'buttons': {
          'minimize': _encoded(minimize),
          'maximize': _encoded(maximize),
          'close': _encoded(close),
        },
      });
    } on MissingPluginException {
      // A host without the channel (e.g. tests).
    }
  }

  static Map<String, double> _encoded(Rect rect) => {
    'left': rect.left,
    'top': rect.top,
    'width': rect.width,
    'height': rect.height,
  };

  /// Runs one of the window's own commands: `minimize`, `maximize` (which
  /// gives the way back while it is maximized) or `close`.
  static Future<void> windowCommand(String command) async {
    if (!drawsHeader) return;
    try {
      await _channel.invokeMethod<void>('windowCommand', command);
    } on MissingPluginException {
      // A host without the channel (e.g. tests).
    }
  }

  /// Hands [target] to the system to open in its default app (the browser,
  /// for a URL; whatever opens a file or folder), or in [app] when given,
  /// with [arguments] passed to it.
  ///
  /// Only where the window can do it: the Windows app, which has no
  /// command of its own to hand a target to (the macOS launcher runs
  /// `open`) — see windows/runner/window_channel.cpp. False elsewhere, and
  /// when the app is not there.
  static Future<bool> openExternal(
    String target, {
    String? app,
    List<String> arguments = const [],
  }) async {
    if (!isDesktop) return false;
    try {
      return await _channel.invokeMethod<bool>('open', {
        'target': target,
        'app': ?app,
        if (arguments.isNotEmpty) 'arguments': arguments,
      }) ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Whether there is a native folder picker: the desktop app.
  static bool get canPickDirectory => isDesktop;

  /// Asks the user for a folder (the native open panel); null if they
  /// cancel or there is no such panel.
  static Future<String?> pickDirectory() async {
    if (!canPickDirectory) return null;
    try {
      return await _channel.invokeMethod<String>('pickDirectory');
    } on MissingPluginException {
      return null;
    }
  }

  /// Carries out the Edit menu's commands (undo, cut, copy, paste, select
  /// all…) where the focus is: the composer, or the conversation's
  /// selection. The menu is the system's own on macOS only; on Windows the
  /// framework handles those shortcuts itself.
  static void handleEditCommands() {
    if (!hasEditMenu) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'editCommand') runEditCommand('${call.arguments}');
      return null;
    });
  }

  /// Whether the OS has a menu bar of its own to carry the Edit commands
  /// (macOS), where the engine's own handling of them falls short.
  static bool get hasEditMenu =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  /// Runs the Edit menu's [command] on the focused widget: what the macOS
  /// menu bar and the Windows header's Edit menu both ask for.
  static void runEditCommand(String command) {
    const cause = SelectionChangedCause.keyboard;
    final Intent? intent = switch (command) {
      'undo' => const UndoTextIntent(cause),
      'redo' => const RedoTextIntent(cause),
      'cut' => const CopySelectionTextIntent.cut(cause),
      'copy' => CopySelectionTextIntent.copy,
      'paste' => const PasteTextIntent(cause),
      'selectAll' => const SelectAllTextIntent(cause),
      _ => null,
    };
    if (intent != null) runIntent(intent);
  }

  /// Runs [intent] where the focus is: what a menu asks of whatever has it
  /// (the composer, the conversation's selection, the chat it sits in).
  static void runIntent(Intent intent) {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context != null) Actions.maybeInvoke(context, intent);
  }

  /// Whether menus can be the system's own: the desktop app.
  static bool get hasNativeMenus => isDesktop;

  /// Shows a context menu of [items] at [position] (in the window, from
  /// its top left); the id of the item chosen, null for none (or no such
  /// menu).
  static Future<String?> showContextMenu(
    Offset position,
    List<NativeMenuItem> items,
  ) async {
    if (!hasNativeMenus) return null;
    try {
      return await _channel.invokeMethod<String>('showContextMenu', {
        'x': position.dx,
        'y': position.dy,
        'items': [for (final item in items) item._encoded],
      });
    } on MissingPluginException {
      return null;
    }
  }

  /// Whether the clipboard holds anything to paste: text, files or images.
  static Future<bool> canPaste() async {
    if (!hasNativeMenus) return false;
    try {
      return await _channel.invokeMethod<bool>('canPaste') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Images on the clipboard, when what it holds is images rather than
  /// text.
  static Future<List<ImageAttachment>> readPasteboardImages() =>
      _images('readPasteboardImages');

  static Future<List<ImageAttachment>> _images(String method) async {
    if (!isDesktop) return const [];
    try {
      final images = await _channel.invokeListMethod<Map<Object?, Object?>>(
        method,
      );
      return [
        for (final image in images ?? const <Map<Object?, Object?>>[])
          if (image['bytes'] case final Uint8List bytes)
            ImageAttachment(
              bytes: bytes,
              mediaType: image['type'] as String? ?? 'image/png',
              name: image['name'] as String?,
            ),
      ];
    } on MissingPluginException {
      return const [];
    }
  }
}

/// An item of a [WindowControls.showContextMenu] menu.
class NativeMenuItem {
  const NativeMenuItem(this.id, this.label, {this.key, this.enabled = true})
    : separator = false;

  const NativeMenuItem.separator()
    : id = '',
      label = '',
      key = null,
      enabled = false,
      separator = true;

  final String id;
  final String label;

  /// Its shortcut, shown as the platform writes one (e.g. `c` for ⌘C on
  /// macOS, Ctrl+C on Windows).
  final String? key;
  final bool enabled;
  final bool separator;

  Map<String, Object?> get _encoded => separator
      ? {'separator': true}
      : {'id': id, 'label': label, 'key': key, 'enabled': enabled};
}
