import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../workspace/window_controls.dart';
import 'app_platform.dart';

/// The app's binding: Flutter's, but for how a text field asks the clipboard
/// for its Paste on macOS.
///
/// Every text field asks as it is built, and all of them again each time the
/// app comes back in front (EditableText's ClipboardStatusNotifier). The
/// macOS engine answers by reading the clipboard's text on the main thread,
/// which waits on the app that copied it: one that hangs held BaoCode with
/// it, a page of fields (the settings) for as long (FQMFH90H). Here the
/// question goes to the window instead, which answers from the clipboard's
/// types (MainFlutterWindow.swift's `hasPasteboardText`).
class AppBinding extends WidgetsFlutterBinding {
  /// The binding, made the first time.
  static WidgetsBinding ensureInitialized() {
    if (!_made) {
      _made = true;
      AppBinding();
    }
    return WidgetsBinding.instance;
  }

  static bool _made = false;

  @override
  BinaryMessenger createBinaryMessenger() {
    final messenger = super.createBinaryMessenger();
    return AppPlatform.isMacOS ? ClipboardProbeMessenger(messenger) : messenger;
  }
}

/// [inner], but for `Clipboard.hasStrings` on the platform channel, which
/// [hasText] answers. What [hasText] cannot answer (no window yet) goes on
/// to [inner] as it came.
class ClipboardProbeMessenger extends BinaryMessenger {
  ClipboardProbeMessenger(
    this.inner, {
    this.hasText = WindowControls.hasPasteboardText,
  });

  final BinaryMessenger inner;
  final Future<bool> Function() hasText;

  static const _platform = SystemChannels.platform;

  @override
  Future<ByteData?>? send(String channel, ByteData? message) {
    if (channel == _platform.name && message != null) {
      final MethodCall call;
      try {
        call = _platform.codec.decodeMethodCall(message);
      } on Object {
        return inner.send(channel, message);
      }
      if (call.method == 'Clipboard.hasStrings') return _hasStrings(message);
    }
    return inner.send(channel, message);
  }

  Future<ByteData?> _hasStrings(ByteData message) async {
    final bool has;
    try {
      has = await hasText();
    } on MissingPluginException {
      return inner.send(_platform.name, message);
    } on PlatformException {
      return inner.send(_platform.name, message);
    }
    return _platform.codec.encodeSuccessEnvelope({'value': has});
  }

  @override
  // ignore: deprecated_member_use
  Future<void> handlePlatformMessage(
    String channel,
    ByteData? data,
    PlatformMessageResponseCallback? callback,
  ) =>
      // ignore: deprecated_member_use
      inner.handlePlatformMessage(channel, data, callback);

  @override
  void setMessageHandler(String channel, MessageHandler? handler) =>
      inner.setMessageHandler(channel, handler);
}
