import 'package:flutter/services.dart';

import '../window/code_args.dart';

/// Files and folders the system asks the app to open, from outside it: the
/// `code` command (see shell_command.dart), Finder's Open With, an item of
/// the macOS File menu's Open Recent, or the Windows app started again
/// with paths (it hands them to the one already running).
///
/// The window keeps what comes before the app is ready for it — the paths
/// it was started with among them — until [listen] takes them (see
/// AppDelegate.swift and windows/runner/open_requests.cpp).
abstract final class OpenRequests {
  static const _channel = MethodChannel('baocode/open');

  /// Starts delivering paths the system asks the app to open (the `code`
  /// command, Finder's Open With, a recent item of the macOS File menu):
  /// first those that came before (at launch), then each as it comes.
  ///
  /// The paths are absolute, or a request of the `code` command
  /// ([CodeArgs.isRequest]); there is one listener, the last to listen.
  static void listen(void Function(List<String> paths) onOpen) {
    _onOpen = onOpen;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'open') _deliver(call.arguments);
      return null;
    });
    _takePending();
  }

  /// Stops delivering them; the window keeps what comes meanwhile for the
  /// next [listen].
  static void stop() {
    _onOpen = null;
    _channel.setMethodCallHandler(null);
    _tell('stop');
  }

  static void Function(List<String> paths)? _onOpen;

  static const codeRequestMarker = CodeArgs.requestMarker;

  /// Asks for what the window kept, which also tells it the app now takes
  /// each as it comes.
  static Future<void> _takePending() async {
    try {
      _deliver(await _channel.invokeMethod<Object?>('takePending'));
    } on MissingPluginException {
      // A host without the channel (the web, tests).
    } on PlatformException {
      // A window that has none to give.
    }
  }

  static Future<void> _tell(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } on MissingPluginException {
      // A host without the channel (the web, tests).
    }
  }

  static void _deliver(Object? arguments) {
    if (arguments is! List) return;
    final all = [
      for (final argument in arguments)
        if (argument is String) argument,
    ];
    final first = all.indexOf(codeRequestMarker);
    final paths = [
      for (final path in first < 0 ? all : all.sublist(0, first))
        if (_isAbsolute(path)) path,
    ];
    if (paths.isNotEmpty) _onOpen?.call(paths);
    if (first < 0) return;
    // Requests of the `code` command (each its marker, the working
    // directory, the arguments as typed), one after another, each going as
    // it came (see CodeArgs); the window keeps them after the paths.
    var start = first;
    for (var index = first + 1; index <= all.length; index++) {
      if (index < all.length && all[index] != codeRequestMarker) continue;
      _onOpen?.call(all.sublist(start, index));
      start = index;
    }
  }

  /// `/…` on macOS; `C:\…` or `\\server\…` on Windows.
  static bool _isAbsolute(String path) =>
      path.startsWith('/') ||
      path.startsWith(r'\\') ||
      RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);
}
