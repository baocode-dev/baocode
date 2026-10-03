import 'dart:async';
import 'dart:ui' show FlutterView, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../platform/app_platform.dart';
import 'window_frame.dart';

/// What a window reports, for [AppWindows].
abstract interface class WindowHostEvents {
  /// Its close button, or the system (Alt+F4, the Dock's menu), asks it
  /// to close: the app decides, then closes it ([WindowHost.close]).
  void windowCloseRequested(int viewId);

  /// It came in front, the keyboard's.
  void windowFocused(int viewId);

  /// It moved, was resized, maximized or made full screen.
  void windowFrameChanged(int viewId, WindowFrame frame);

  /// New Window, from the Dock's menu or the tray's.
  void newWindowRequested();

  /// Quit, from the tray's menu (Windows: the close buttons are the app's
  /// then, and would only hide the chat's window).
  void quitRequested();

  /// The app's icon (the Dock's, the tray's) clicked with none of its
  /// windows shown: the app shows one.
  void reopenRequested();
}

/// One of the app's windows, as a menu lists it (the macOS Window menu,
/// the Dock's menu, the tray's).
class WindowMenuEntry {
  const WindowMenuEntry({
    required this.viewId,
    required this.title,
    this.edited = false,
  });

  final int viewId;
  final String title;
  final bool edited;

  Map<String, Object?> get encoded => {
    'viewId': viewId,
    'title': title,
    'edited': edited,
  };

  @override
  bool operator ==(Object other) =>
      other is WindowMenuEntry &&
      other.viewId == viewId &&
      other.title == title &&
      other.edited == edited;

  @override
  int get hashCode => Object.hash(viewId, title, edited);
}

/// The system's side of the app's windows: the main one (the chat's, the
/// implicit view the app starts with) and those it opens beside it, each a
/// view of the one engine.
abstract class WindowHost {
  /// The main window's view.
  int get mainViewId => 0;

  /// Whether the app can open windows of its own; without (the web, a host
  /// without the channel), everything shows in the main one.
  Future<bool> start(WindowHostEvents events);

  /// The view of [viewId], once the engine has it.
  FlutterView? viewOf(int viewId);

  /// A new window, shown at [frame] (where the system puts one, without,
  /// [width] wide if given: logical pixels), titled [title]: its view's
  /// id; null if none could be made.
  Future<int?> create({
    WindowFrame? frame,
    required String title,
    double? width,
  });

  /// Waits until the engine has [viewId]'s view.
  Future<FlutterView?> waitForView(int viewId);

  /// Closes [viewId]'s window, its view gone with it; the main one is
  /// only hidden.
  Future<void> close(int viewId);

  /// Shows [viewId]'s window in front of the others, the keyboard's.
  Future<void> focus(int viewId);

  /// Hides [viewId]'s window (the main one, closed).
  Future<void> hide(int viewId);

  /// Whether the main window shows when the app next starts (macOS reads
  /// it before Dart runs).
  Future<void> setMainShownAtLaunch(bool shown);

  /// Ends the app, which has agreed to it: Windows' way out (see
  /// AppWindows' quit).
  Future<void> quit();

  /// The title the system shows (the Window menu, Mission Control, the
  /// taskbar); [path], the folder it shows (the macOS proxy icon).
  Future<void> setTitle(int viewId, String title, {String? path});

  /// Whether the window has unsaved files (the dot in macOS' close button).
  Future<void> setEdited(int viewId, bool edited);

  /// Where the window is.
  Future<WindowFrame?> frame(int viewId);

  /// The screens' usable areas.
  Future<List<ScreenArea>> screens();

  /// What the Window menu, the Dock's menu and the tray's list: [windows],
  /// in order, the one in front [focused]; their labels in the app's
  /// language.
  Future<void> setWindowList(
    List<WindowMenuEntry> windows, {
    required Map<String, String> labels,
  });
}

/// [WindowHost] over `baocode/windows` (MainFlutterWindow.swift,
/// windows/runner/app_windows.cpp).
///
///   start                        whether windows can be opened (the
///                                engine's multiple views)
///   create {frame?, title, width?, engineId}
///                                a window: its view's id
///   close viewId, focus viewId, hide viewId
///   setTitle {viewId, title, path?}, setEdited {viewId, edited}
///   frame viewId                 {x, y, width, height, maximized,
///                                fullscreen, screen}
///   screens                      [{id, x, y, width, height}]
///   setWindowList {windows: [{viewId, title, edited}], labels}
///   setMainShownAtLaunch bool
///   quit                         (Windows) the app goes, agreed to
///
/// and back:
///
///   closeRequested viewId, focused viewId, frameChanged {viewId, frame…},
///   newWindow, quit
class ChannelWindowHost extends WindowHost {
  ChannelWindowHost({PlatformDispatcher? dispatcher})
    : _dispatcher = dispatcher ?? PlatformDispatcher.instance;

  static const channel = MethodChannel('baocode/windows');

  final PlatformDispatcher _dispatcher;

  @override
  Future<bool> start(WindowHostEvents events) async {
    if (kIsWeb || !(AppPlatform.isMacOS || AppPlatform.isWindows)) {
      return false;
    }
    try {
      final available = await channel.invokeMethod<bool>('start') ?? false;
      if (!available) return false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (error) {
      debugPrint('windows.start: $error');
      return false;
    }
    channel.setMethodCallHandler((call) async {
      final arguments = call.arguments;
      switch (call.method) {
        case 'closeRequested':
          events.windowCloseRequested(_id(arguments));
        case 'focused':
          events.windowFocused(_id(arguments));
        case 'frameChanged':
          if (arguments case final Map<Object?, Object?> map) {
            if (WindowFrame.fromJson(map) case final frame?) {
              events.windowFrameChanged(_id(map['viewId']), frame);
            }
          }
        case 'newWindow':
          events.newWindowRequested();
        case 'quit':
          events.quitRequested();
        case 'reopen':
          events.reopenRequested();
      }
      return null;
    });
    return true;
  }

  static int _id(Object? value) => (value as num?)?.toInt() ?? -1;

  @override
  FlutterView? viewOf(int viewId) => _dispatcher.view(id: viewId);

  @override
  Future<FlutterView?> waitForView(int viewId) async {
    final view = viewOf(viewId);
    if (view != null) return view;
    // The engine adds it on the UI thread, maybe after the answer came.
    final found = Completer<FlutterView?>();
    final watcher = _ViewWatcher(() {
      if (viewOf(viewId) case final view? when !found.isCompleted) {
        found.complete(view);
      }
    });
    WidgetsBinding.instance.addObserver(watcher);
    try {
      return await found.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => viewOf(viewId),
      );
    } finally {
      WidgetsBinding.instance.removeObserver(watcher);
    }
  }

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    try {
      return await channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (error) {
      debugPrint('windows.$method: $error');
      return null;
    }
  }

  @override
  Future<int?> create({
    WindowFrame? frame,
    required String title,
    double? width,
  }) async {
    final id = await _invoke<int>('create', {
      'frame': ?frame?.toJson(),
      'title': title,
      'width': ?width,
      'engineId': _dispatcher.engineId,
    });
    return id;
  }

  @override
  Future<void> close(int viewId) => _invoke('close', viewId);

  @override
  Future<void> focus(int viewId) => _invoke('focus', viewId);

  @override
  Future<void> hide(int viewId) => _invoke('hide', viewId);

  @override
  Future<void> setMainShownAtLaunch(bool shown) =>
      _invoke('setMainShownAtLaunch', shown);

  @override
  Future<void> quit() => _invoke('quit');

  @override
  Future<void> setTitle(int viewId, String title, {String? path}) =>
      _invoke('setTitle', {'viewId': viewId, 'title': title, 'path': ?path});

  @override
  Future<void> setEdited(int viewId, bool edited) =>
      _invoke('setEdited', {'viewId': viewId, 'edited': edited});

  @override
  Future<WindowFrame?> frame(int viewId) async =>
      WindowFrame.fromJson(await _invoke<Object?>('frame', viewId));

  @override
  Future<List<ScreenArea>> screens() async {
    final screens = await _invoke<List<Object?>>('screens');
    return [
      for (final screen in screens ?? const <Object?>[])
        ?ScreenArea.fromJson(screen),
    ];
  }

  @override
  Future<void> setWindowList(
    List<WindowMenuEntry> windows, {
    required Map<String, String> labels,
  }) => _invoke('setWindowList', {
    'windows': [for (final window in windows) window.encoded],
    'labels': labels,
  });
}

class _ViewWatcher with WidgetsBindingObserver {
  _ViewWatcher(this._changed);

  final VoidCallback _changed;

  @override
  void didChangeMetrics() => _changed();
}
