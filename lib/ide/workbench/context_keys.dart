// The workbench's context keys, which keybindings' `when` clauses read: each
// service sets its own (upstream `IContextKeyService.createKey`), and those
// that depend on where the keyboard is are worked out as a key is pressed
// (a provider, as the workbench's `keyContext` did).
//
// After VS Code's src/vs/platform/contextkey/common/contextkey.ts, without
// its scopes: the workbench is one, its views telling by focus.

import 'package:flutter/foundation.dart';

import '../../keybindings/when_expression.dart';

/// A key a service keeps current (upstream `IContextKey`).
class ContextKey<T> {
  ContextKey._(this._service, this.name, this._defaultValue)
    : _value = _defaultValue;

  final ContextKeyService _service;
  final String name;
  final T _defaultValue;
  T _value;

  T get() => _value;

  void set(T value) {
    if (value == _value) return;
    _value = value;
    _service._changed();
  }

  /// Back to the value it was made with.
  void reset() => set(_defaultValue);
}

class ContextKeyService extends ChangeNotifier {
  final Map<String, ContextKey<Object?>> _keys = {};
  final List<ContextLookup> _providers = [];

  /// A key named [name], [defaultValue] until set; one made again is the
  /// same key, keeping its value.
  ContextKey<T> createKey<T>(String name, T defaultValue) {
    final existing = _keys[name];
    if (existing != null) return existing as ContextKey<T>;
    final key = ContextKey<T>._(this, name, defaultValue);
    _keys[name] = key;
    return key;
  }

  /// Keeps the key [name] as [listenable] is, until the returned callback
  /// runs.
  VoidCallback bind<T>(String name, ValueListenable<T> listenable) {
    final key = createKey<T>(name, listenable.value);
    void update() => key.set(listenable.value);
    update();
    listenable.addListener(update);
    return () => listenable.removeListener(update);
  }

  /// Answers the keys [provider] knows (null for those it does not), after
  /// the keys made here and those added before it, until the returned
  /// callback runs.
  VoidCallback addProvider(ContextLookup provider) {
    _providers.add(provider);
    return () => _providers.remove(provider);
  }

  /// [key]'s value: a key's made here, else the first provider's that
  /// knows it; null where none does.
  Object? getValue(String key) {
    if (_keys[key] case final made?) return made.get();
    for (final provider in _providers) {
      if (provider(key) case final value?) return value;
    }
    return null;
  }

  ContextLookup get lookup => getValue;

  void _changed() => notifyListeners();
}
