import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// How wide the conversation's column (its text, the composer) may grow in
/// a wide window: settings.json's `chat.maxWidth`, a width or `full`, as
/// Settings → Appearance's slider picks one of [steps]. Unset: [fallback].
abstract final class ChatWidth {
  static const settingKey = 'chat.maxWidth';

  /// The setting's value for as wide as the window.
  static const full = 'full';

  static const fallback = 720.0;

  /// The slider's, narrowest first; the last as wide as the window.
  static const steps = [fallback, 880.0, 1040.0, 1200.0, double.infinity];

  /// [value] as settings.json has it; a width under [fallback] is
  /// [fallback].
  static double parse(Object? value) => switch (value) {
    full => double.infinity,
    final num width when width.isFinite => math.max(fallback, width.toDouble()),
    _ => fallback,
  };

  /// [width] as settings.json keeps it; null (not written) for [fallback].
  static Object? setting(double width) => switch (width) {
    fallback => null,
    double.infinity => full,
    _ => width.round(),
  };

  /// The index in [steps] of the one nearest [width].
  static int stepOf(double width) {
    if (width.isInfinite) return steps.length - 1;
    var nearest = 0;
    for (var i = 1; i < steps.length - 1; i++) {
      if ((steps[i] - width).abs() < (steps[nearest] - width).abs()) {
        nearest = i;
      }
    }
    return nearest;
  }

  /// The width the chats follow now; main() keeps it to settings.json
  /// ([follow]).
  static final ValueNotifier<double> current = ValueNotifier(fallback);

  /// Sets [current] from [read] now and whenever [changes] notifies.
  static void follow(Listenable changes, Object? Function() read) {
    void update() => current.value = parse(read());
    update();
    changes.addListener(update);
  }
}
