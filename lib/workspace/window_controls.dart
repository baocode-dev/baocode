import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../chat/chat_models.dart';
import '../chat/composer/composer_files.dart';
import '../chat/composer/file_drop.dart';
import '../platform/app_platform.dart';

/// One of the window's own buttons, over a header the app draws itself: the
/// system hit-tests and acts on those pixels, so the header only paints them
/// (see [WindowControls.hoveredWindowButton]).
enum WindowButton { minimize, maximize, close }

/// Controls of the native window, where there is one (the desktop app; see
/// MainFlutterWindow.swift and windows/runner/window_channel.cpp).
abstract final class WindowControls {
  static const _channel = MethodChannel('baocode/window');

  /// Whether the app runs in a window to command: the desktop app, not a
  /// browser tab.
  static bool get isDesktop => AppPlatform.isMacOS || AppPlatform.isWindows;

  /// Whether the window is the app's own to draw: Windows, where the header
  /// carries the menus, the session's tools and the window buttons (see
  /// workspace/window_header/). Elsewhere the system draws the caption —
  /// macOS with its traffic lights over a title bar Flutter paints under
  /// them.
  static bool get drawsHeader => AppPlatform.isWindows;

  /// Whether the window can be kept on top.
  static bool get canKeepOnTop => isDesktop;

  /// Makes the window's own parts light or dark as the color theme is: on
  /// macOS the material under the sidebar, the traffic lights and the
  /// system's menus (MainFlutterWindow.swift keeps it for the next start).
  static Future<void> setDarkAppearance(bool dark) async {
    if (!AppPlatform.isMacOS) return;
    try {
      await _channel.invokeMethod<void>('setAppearance', dark);
    } on MissingPluginException {
      // A host without the channel (e.g. tests).
    }
  }

  /// Keeps the window above other apps' windows, or not.
  static Future<void> setAlwaysOnTop(bool onTop) async {
    if (!canKeepOnTop) return;
    try {
      await _channel.invokeMethod<void>('setAlwaysOnTop', onTop);
    } on MissingPluginException {
      // A host without the channel (e.g. tests).
    }
  }

  /// Whether the window can be made larger for what it shows: the desktop
  /// app.
  static bool get canGrow => isDesktop;

  /// How much wider and taller the window can get on its screen: none while
  /// it fills it (full screen, maximized); null where there is no window to
  /// ask (the web, a host without the channel).
  static Future<Size?> growRoom() async {
    if (!canGrow) return null;
    try {
      final room = await _channel.invokeMapMethod<String, Object?>(
        'windowRoom',
      );
      if (room == null) return null;
      double size(String key) => (room[key] as num?)?.toDouble() ?? 0;
      return Size(size('width'), size('height'));
    } on MissingPluginException {
      return null;
    }
  }

  /// Makes the window [by] wider and taller, as far as its screen goes: its
  /// top left stays, unless that would take it past the screen's edge,
  /// where it moves back onto it.
  static Future<void> grow(Size by) async {
    if (!canGrow) return;
    try {
      await _channel.invokeMethod<void>('growWindow', {
        'width': by.width,
        'height': by.height,
      });
    } on MissingPluginException {
      // A host without the channel (e.g. tests).
    }
  }

  /// Whether a double click on the title bar is the app's to handle: macOS,
  /// where Flutter draws the title bar and so gets its clicks. On Windows
  /// the system handles its caption's own (HTCAPTION, see
  /// windows/runner/flutter_window.cpp).
  static bool get handlesTitleDoubleClick => AppPlatform.isMacOS;

  /// Does what the system's settings say a double click on the title bar
  /// does: zoom (by default), fill, minimize or nothing (see
  /// MainFlutterWindow.swift).
  static Future<void> handleTitleDoubleClick() async {
    if (!handlesTitleDoubleClick) return;
    try {
      await _channel.invokeMethod<void>('handleTitleDoubleClick');
    } on MissingPluginException {
      // A host without the channel (e.g. tests).
    }
  }

  /// Which of them the pointer is over, or null; the window reports it.
  static final ValueNotifier<WindowButton?> hoveredWindowButton = ValueNotifier(
    null,
  );

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

  /// Whether a file can be handed to its default app (editor_launcher's
  /// `openExternal`: `open` on macOS, [openExternal] on Windows).
  static bool get canOpenInDefaultApp => isDesktop;

  /// Hands [target] to the system to open in its default app (the browser,
  /// for a URL; whatever opens a file or folder), or in [app] when given,
  /// with [arguments] passed to it.
  ///
  /// Only the Windows app's window does it, having no command of its own
  /// to hand a target to (the macOS launcher runs `open`) — see
  /// windows/runner/window_channel.cpp. False elsewhere, and when the app
  /// is not there.
  static Future<bool> openExternal(
    String target, {
    String? app,
    List<String> arguments = const [],
  }) async {
    if (!AppPlatform.isWindows) return false;
    try {
      return await _channel.invokeMethod<bool>('open', {
            'target': target,
            'app': ?app,
            if (arguments.isNotEmpty) 'arguments': arguments,
          }) ??
          false;
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

  /// Whether [moveToTrash] can move files to a Trash.
  static bool get canMoveToTrash => AppPlatform.isMacOS;

  /// Moves [path] to the system's Trash (macOS); false where there is no
  /// Trash to move to. Throws a [PlatformException] when moving fails.
  static Future<bool> moveToTrash(String path) async {
    if (!canMoveToTrash) return false;
    try {
      return await _channel.invokeMethod<bool>('trashItem', path) ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Whether [revealInFileManager] can show a file (Finder, or File
  /// Explorer on Windows).
  static bool get canRevealInFileManager => isDesktop;

  /// Opens a Finder (or File Explorer) window with [path] selected.
  static Future<void> revealInFileManager(String path) async {
    if (!canRevealInFileManager) return;
    try {
      await _channel.invokeMethod<void>('revealInFinder', path);
    } on MissingPluginException {
      // A host without the channel (e.g. tests).
    }
  }

  /// Carries out the Edit menu's commands (undo, cut, copy, paste, select
  /// all…) where the focus is: the composer, or the conversation's
  /// selection. The menu is the system's own on macOS only; on Windows the
  /// framework handles those shortcuts itself.
  static void handleEditCommands() {
    if (!hasEditMenu) return;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'editCommand':
          runEditCommand('${call.arguments}');
        case 'menuCommand':
          onMenuCommand?.call('${call.arguments}');
      }
      return null;
    });
  }

  /// Runs a command the system's menu bar picked (the app menu's
  /// Preferences…: `workbench.action.openSettings`; the File menu's, see
  /// [setFileMenuTitles]); set by the workbench.
  static void Function(String command)? onMenuCommand;

  /// Whether the OS has a menu bar of its own to carry the Edit commands
  /// (macOS), where the engine's own handling of them falls short.
  static bool get hasEditMenu => AppPlatform.isMacOS;

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
    final context = FocusManager.instance.primaryFocus?.context;
    if (intent != null && context != null) {
      Actions.maybeInvoke(context, intent);
    }
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

  /// Files and folders copied to the clipboard (in Finder, Explorer, the
  /// IDE's explorer…).
  static Future<List<ComposerFile>> readPasteboardFiles() =>
      _files('readPasteboardFiles');

  /// Puts [paths] on the clipboard as files, as Finder and Explorer copy
  /// them: pasted there, they are copied; pasted in the composer, they are
  /// referred to. Whether it could.
  static Future<bool> writePasteboardFiles(List<String> paths) async {
    if (!isDesktop || paths.isEmpty) return false;
    try {
      return await _channel.invokeMethod<bool>('writePasteboardFiles', paths) ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  /// The image file at [path] as the composer takes one (the formats it
  /// does not send as they are converted to PNG); null when it is no image
  /// the system reads.
  static Future<ImageAttachment?> readImageFile(String path) async {
    if (!isDesktop) return null;
    try {
      final image = await _channel.invokeMapMethod<Object?, Object?>(
        'readImageFile',
        path,
      );
      if (image?['bytes'] case final Uint8List bytes) {
        return ImageAttachment(
          bytes: bytes,
          mediaType: image!['type'] as String? ?? 'image/png',
          name: image['name'] as String?,
        );
      }
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Whether there is a native file picker: the desktop app.
  static bool get canPickFiles => isDesktop;

  /// Asks the user for files (the native open panel); none if they cancel.
  static Future<List<ComposerFile>> pickFiles() => _files('pickFiles');

  /// Asks the user for files to open (the native open panel, in
  /// [directory] when given): their absolute paths, one at most unless
  /// [multiple]; none if they cancel or there is no such panel. Files
  /// only, as the IDE's Open File… takes them.
  static Future<List<String>> pickOpenFiles({
    String? directory,
    bool multiple = true,
  }) async {
    if (!canPickFiles) return const [];
    try {
      final paths = await _channel.invokeListMethod<Object?>('pickOpenFiles', {
        'directory': ?directory,
        'multiple': multiple,
      });
      return [
        for (final path in paths ?? const <Object?>[])
          if (path is String && path.isNotEmpty) path,
      ];
    } on MissingPluginException {
      return const [];
    }
  }

  /// Asks the user where to save a file (the native save panel, in
  /// [directory] and under [name] when given; it asks before replacing a
  /// file): the absolute path chosen, or null if they cancel or there is
  /// no such panel.
  static Future<String?> pickSaveFile({String? directory, String? name}) async {
    if (!canPickFiles) return null;
    try {
      final path = await _channel.invokeMethod<String>('pickSaveFile', {
        'directory': ?directory,
        'name': ?name,
      });
      return path == null || path.isEmpty ? null : path;
    } on MissingPluginException {
      return null;
    }
  }

  /// Names the macOS menu bar's File menu and its items in the app's
  /// language: [titles] by key — `file` (the menu), `newUntitledFile`,
  /// `openFile`, `openFolder`, `openRecent`, `save`, `saveAs`,
  /// `closeFolder`, `clearRecent` and `more` (Open Recent's empty state).
  /// Keys left out keep their English. Its items come back through
  /// [onMenuCommand], as the workbench's command ids. Nothing elsewhere:
  /// Windows' menus are the header's own.
  static Future<void> setFileMenuTitles(Map<String, String> titles) async {
    if (!hasEditMenu) return;
    try {
      await _channel.invokeMethod<void>('setFileMenuTitles', titles);
    } on MissingPluginException {
      // A host without the channel (e.g. tests).
    }
  }

  /// What the macOS File menu's Open Recent lists: [paths], the latest
  /// first, then Clear Recently Opened (`workbench.action.clearRecentlyOpened`
  /// through [onMenuCommand]). A path picked there comes back as one the
  /// system asks to open (see OpenRequests), as `code <path>` does.
  static Future<void> setRecentItems(List<String> paths) async {
    if (!hasEditMenu) return;
    try {
      await _channel.invokeMethod<void>('setRecentItems', paths);
    } on MissingPluginException {
      // A host without the channel (e.g. tests).
    }
  }

  static Future<List<ComposerFile>> _files(String method) async {
    if (!isDesktop) return const [];
    try {
      final files = await _channel.invokeListMethod<Object?>(method);
      return FileDrops.decode(files ?? const []);
    } on MissingPluginException {
      return const [];
    }
  }

  /// Puts [image] on the clipboard, as other apps paste a picture; whether
  /// it could.
  static Future<bool> writePasteboardImage(ImageAttachment image) async {
    if (!isDesktop) return false;
    try {
      return await _channel.invokeMethod<bool>('writePasteboardImage', {
            'bytes': image.bytes,
            'type': image.mediaType,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

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
