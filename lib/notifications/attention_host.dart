import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../platform/app_platform.dart';

/// The menu bar / system tray icon as it should be.
@immutable
class TrayState {
  const TrayState({
    required this.dot,
    required this.waiting,
    required this.tooltip,
    required this.labels,
  });

  /// Whether an agent needs the user: a dot on the icon.
  final bool dot;

  /// The agents waiting on the user, by id, their menu's items.
  final List<({String id, String title})> waiting;

  final String tooltip;

  /// The menu's own words: `show`, `waiting`, `quit`, and `running` (how
  /// many run) when any do.
  final Map<String, String> labels;

  Map<String, Object?> get encoded => {
    'dot': dot,
    'waiting': [
      for (final agent in waiting) {'id': agent.id, 'title': agent.title},
    ],
    'tooltip': tooltip,
    'labels': labels,
  };

  @override
  bool operator ==(Object other) =>
      other is TrayState &&
      other.dot == dot &&
      listEquals(other.waiting, waiting) &&
      other.tooltip == tooltip &&
      mapEquals(other.labels, labels);

  @override
  int get hashCode =>
      Object.hash(dot, Object.hashAll(waiting), tooltip, labels.length);
}

/// The system's side of notifying: what the native window does over
/// `baocode/attention` (macos/Runner/Attention.swift,
/// windows/runner/attention.cpp).
abstract interface class AttentionHost {
  /// A notification of the system's, without a sound; [id] is the agent's,
  /// handed back to [onOpen] when it is clicked.
  Future<void> notify({
    required String id,
    required String title,
    required String body,
  });

  /// Plays a sound file at [path], or one's [bytes].
  Future<void> playSound({String? path, Uint8List? bytes});

  /// Has the app's Dock or taskbar icon ask for the user: a bounce, a
  /// flash.
  Future<void> requestAttention();

  /// The count on the app's icon; 0 for none.
  Future<void> setBadge(int count);

  /// The tray icon; null for none (and the window's close button closes).
  Future<void> setTray(TrayState? state);

  /// A sound file the user picks; null if they cancel.
  Future<String?> pickSound();

  /// Quits as the tray's Quit does: the app asks first. (On Windows the
  /// close button only hides the window while the tray icon is up.)
  Future<void> quit();

  /// What a click on a notification or the tray's menu opens: the agent
  /// [id] names, or (null) just the window, which the host has brought
  /// back already.
  set onOpen(void Function(String? id)? handler);
}

/// [AttentionHost] over the desktop app's channel; nothing elsewhere (the
/// web, tests).
class ChannelAttentionHost implements AttentionHost {
  ChannelAttentionHost._() {
    if (_available) _channel.setMethodCallHandler(_handle);
  }

  /// The one host: the channel has one handler.
  static final instance = ChannelAttentionHost._();

  static const _channel = MethodChannel('baocode/attention');

  static bool get _available => AppPlatform.isMacOS || AppPlatform.isWindows;

  void Function(String? id)? _onOpen;

  @override
  set onOpen(void Function(String? id)? handler) => _onOpen = handler;

  Future<Object?> _handle(MethodCall call) async {
    if (call.method == 'open') _onOpen?.call(call.arguments as String?);
    return null;
  }

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    if (!_available) return null;
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      // A host without the channel.
      return null;
    } on PlatformException catch (error) {
      debugPrint('attention.$method: $error');
      return null;
    }
  }

  @override
  Future<void> notify({
    required String id,
    required String title,
    required String body,
  }) => _invoke('notify', {'id': id, 'title': title, 'body': body});

  @override
  Future<void> playSound({String? path, Uint8List? bytes}) =>
      _invoke('playSound', {'path': ?path, 'bytes': ?bytes});

  @override
  Future<void> requestAttention() => _invoke('requestAttention');

  @override
  Future<void> setBadge(int count) => _invoke('setBadge', count);

  @override
  Future<void> setTray(TrayState? state) => _invoke('setTray', state?.encoded);

  @override
  Future<String?> pickSound() => _invoke<String>('pickSound');

  @override
  Future<void> quit() => _invoke('quit');
}
