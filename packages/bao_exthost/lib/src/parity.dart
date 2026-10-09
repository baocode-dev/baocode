// How much of the extension host protocol's main thread side BaoCode
// implements, as the calls it could not serve show.
//
// The generated `MainThread*Unsupported` classes record every call here;
// tool/generate_exthost_parity.dart reports what is implemented statically.

import 'dart:async';

/// One call to a main thread method that is not implemented.
final class UnsupportedCall {
  const UnsupportedCall(this.shape, this.method);

  /// The `MainContext` key, e.g. `MainThreadCommands`.
  final String shape;

  /// The `$` method, e.g. `$registerCommand`.
  final String method;

  String get name => '$shape.$method';

  @override
  String toString() => name;
}

/// Counts calls to unsupported main thread methods, by `Shape.$method`.
final class ExtHostParity {
  ExtHostParity();

  /// The registry the generated fallbacks record to.
  static final instance = ExtHostParity();

  final _counts = <String, int>{};
  final _calls = StreamController<UnsupportedCall>.broadcast(sync: true);

  /// Each unsupported call, as it happens.
  Stream<UnsupportedCall> get onUnsupportedCall => _calls.stream;

  /// How many times each `Shape.$method` was called and was unsupported.
  Map<String, int> get unsupportedCalls => Map.unmodifiable(_counts);

  /// How many times [shape]'s [method] was called and was unsupported.
  int count(String shape, String method) => _counts['$shape.$method'] ?? 0;

  void recordUnsupported(String shape, String method) {
    final call = UnsupportedCall(shape, method);
    _counts.update(call.name, (n) => n + 1, ifAbsent: () => 1);
    if (_calls.hasListener) _calls.add(call);
  }

  void reset() => _counts.clear();
}
