import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../chat/chat_models.dart';

/// Controls of the native window, where there is one (the macOS app; see
/// MainFlutterWindow.swift).
abstract final class WindowControls {
  static const _channel = MethodChannel('monad/window');

  /// Whether the window can be kept on top: not in a browser tab.
  static bool get canKeepOnTop =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  /// Keeps the window above other apps' windows, or not.
  static Future<void> setAlwaysOnTop(bool onTop) async {
    if (!canKeepOnTop) return;
    try {
      await _channel.invokeMethod<void>('setAlwaysOnTop', onTop);
    } on MissingPluginException {
      // A host without the channel (e.g. tests).
    }
  }

  /// Whether there is a native folder picker: the desktop app.
  static bool get canPickDirectory => canKeepOnTop;

  /// Asks the user for a folder (the native open panel); null if they
  /// cancel or there is no such panel.
  static Future<String?> pickDirectory() async {
    if (!canKeepOnTop) return null;
    try {
      return await _channel.invokeMethod<String>('pickDirectory');
    } on MissingPluginException {
      return null;
    }
  }

  /// Carries out the Edit menu's commands (undo, cut, copy, paste, select
  /// all…) where the focus is: the composer, or the conversation's
  /// selection.
  static void handleEditCommands() {
    if (!hasNativeMenus) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'editCommand') runEditCommand('${call.arguments}');
      return null;
    });
  }

  /// Runs the Edit menu's [command] on the focused widget.
  @visibleForTesting
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
    final context = FocusManager.instance.primaryFocus?.context;
    if (intent != null && context != null) {
      Actions.maybeInvoke(context, intent);
    }
  }

  /// Whether menus can be the system's own: the desktop app.
  static bool get hasNativeMenus => canKeepOnTop;

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
    if (!canKeepOnTop) return const [];
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

  /// Its shortcut, shown with ⌘ (e.g. `c`).
  final String? key;
  final bool enabled;
  final bool separator;

  Map<String, Object?> get _encoded => separator
      ? {'separator': true}
      : {'id': id, 'label': label, 'key': key, 'enabled': enabled};
}
