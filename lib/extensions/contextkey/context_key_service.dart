/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The context keys `when` clauses read: a global context with the
// settings (`config.*`), scoped child contexts (an editor's, a view's) and
// overlays (one menu's item: `viewItem`, `scmResourceState`…), with change
// events for menus and keybindings to refresh on.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/platform/contextkey/browser/contextKeyService.ts (`Context`,
// `ConfigAwareContextValuesContainer`, `ContextKey`, the change events,
// `AbstractContextKeyService`, `ContextKeyService`,
// `ScopedContextKeyService`, `OverlayContextKeyService`, `setContext`
// with `stringifyURIs`) and src/vs/platform/contextkey/common/contextkey.ts
// (`RawContextKey`, `IContextKey`).
//
// The well-known keys the workbench feeds are in workbench_context_keys.dart;
// `config.*` over the settings in configuration_context.dart.
//
// Deviations:
// - No DOM: a scoped service is made by [AbstractContextKeyService.createScoped]
//   and handed to what it belongs to; `getContext(element)` is
//   [AbstractContextKeyService.lookup].
// - The root may read keys it does not hold from a [fallback] (the
//   workbench's own lookup of its UI state), after its own values and
//   before `config.*`; changes to those are announced with
//   [ContextKeyService.notifyExternalChange].
// - `inputFocus` is not tracked here (the workbench feeds it).
// - Listeners are plain callbacks (`onDidChangeContext` returns the
//   function that removes one); the root is also a [ChangeNotifier].

import 'dart:convert';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:flutter/foundation.dart';

import 'contextkey.dart';

/// `IContextKeyChangeEvent`.
abstract interface class ContextKeyChangeEvent {
  bool affectsSome(Set<String> keys);
  bool allKeysContainedIn(Set<String> keys);
}

final class _SimpleChangeEvent implements ContextKeyChangeEvent {
  const _SimpleChangeEvent(this.key);
  final String key;
  @override
  bool affectsSome(Set<String> keys) => keys.contains(key);
  @override
  bool allKeysContainedIn(Set<String> keys) => affectsSome(keys);
}

final class _ArrayChangeEvent implements ContextKeyChangeEvent {
  const _ArrayChangeEvent(this.keys);
  final List<String> keys;
  @override
  bool affectsSome(Set<String> keys) => this.keys.any(keys.contains);
  @override
  bool allKeysContainedIn(Set<String> keys) => this.keys.every(keys.contains);
}

final class _CompositeChangeEvent implements ContextKeyChangeEvent {
  const _CompositeChangeEvent(this.events);
  final List<ContextKeyChangeEvent> events;
  @override
  bool affectsSome(Set<String> keys) => events.any((e) => e.affectsSome(keys));
  @override
  bool allKeysContainedIn(Set<String> keys) =>
      events.every((e) => e.allKeysContainedIn(keys));
}

/// Any key may have changed (the [ContextKeyService.fallback]'s).
final class _AnyChangeEvent implements ContextKeyChangeEvent {
  const _AnyChangeEvent();
  @override
  bool affectsSome(Set<String> keys) => true;
  @override
  bool allKeysContainedIn(Set<String> keys) => false;
}

/// Deep equality of context key values (`objects.equals`).
bool _valueEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_valueEquals(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_valueEquals(a[key], b[key])) return false;
    }
    return true;
  }
  return a == b;
}

/// `Context`: one context's values, over its parent's.
class Context {
  Context(this.id, this._parent);

  final int id;
  Context? _parent;
  final Map<String, Object?> _value = {};

  Map<String, Object?> get value => Map.of(_value);

  bool setValue(String key, Object? value) {
    if (!_value.containsKey(key) || !_valueEquals(_value[key], value)) {
      _value[key] = value;
      return true;
    }
    return false;
  }

  bool removeValue(String key) {
    if (_value.containsKey(key)) {
      _value.remove(key);
      return true;
    }
    return false;
  }

  Object? getValue(String key) {
    final ret = _value[key];
    if (ret == null && !_value.containsKey(key) && _parent != null) {
      return _parent!.getValue(key);
    }
    return ret;
  }

  void updateParent(Context parent) => _parent = parent;

  Map<String, Object?> collectAllValues() => {
    ...?_parent?.collectAllValues(),
    ..._value,
  };
}

final class _NullContext extends Context {
  _NullContext() : super(-1, null);
  static final instance = _NullContext();
  @override
  bool setValue(String key, Object? value) => false;
  @override
  bool removeValue(String key) => false;
  @override
  Object? getValue(String key) => null;
  @override
  Map<String, Object?> collectAllValues() => {};
}

/// Reads settings for `config.*` keys, and tells when some change.
abstract interface class ContextKeyConfiguration {
  Object? getValue(String key);

  /// Calls [listener] with the changed setting keys, or null for "all"
  /// (new defaults); returns what stops it.
  void Function() onDidChange(void Function(List<String>? keys) listener);
}

/// `ConfigAwareContextValuesContainer`: the root context, with
/// `config.<setting>` keys read from the settings (arrays as JSON text),
/// and the workbench's [fallback].
final class _RootContext extends Context {
  _RootContext(int id, this._configuration, this._fire) : super(id, null) {
    _stop = _configuration?.onDidChange((keys) {
      if (keys == null) {
        final all = _cache.keys.toList();
        _cache.clear();
        _fire(_ArrayChangeEvent(all));
        return;
      }
      final changed = <String>[];
      for (final configKey in keys) {
        final contextKey = 'config.$configKey';
        for (final cached in _cache.keys.toList()) {
          if (cached == contextKey || cached.startsWith('$contextKey.')) {
            changed.add(cached);
            _cache.remove(cached);
          }
        }
      }
      _fire(_ArrayChangeEvent(changed));
    });
  }

  static const _keyPrefix = 'config.';

  final ContextKeyConfiguration? _configuration;
  final void Function(ContextKeyChangeEvent) _fire;
  final Map<String, Object?> _cache = {};
  void Function()? _stop;
  ContextKeyLookup? fallback;

  void dispose() => _stop?.call();

  @override
  Object? getValue(String key) {
    if (_value.containsKey(key)) return _value[key];
    if (!key.startsWith(_keyPrefix)) return fallback?.call(key);
    if (_cache.containsKey(key)) return _cache[key];
    final configValue = _configuration?.getValue(
      key.substring(_keyPrefix.length),
    );
    final Object? value = switch (configValue) {
      final List<Object?> list => jsonEncodeList(list),
      _ => configValue,
    };
    _cache[key] = value;
    return value;
  }

  @override
  Map<String, Object?> collectAllValues() => {..._cache, ...super.collectAllValues()};
}

/// `JSON.stringify` of an array setting, as upstream puts it in a key.
String jsonEncodeList(List<Object?> list) => jsonEncode(list);

/// `IContextKey`: one key, bound to a service.
final class ContextKey<T> {
  ContextKey._(this._service, this.key, this._defaultValue) {
    reset();
  }

  final AbstractContextKeyService _service;
  final String key;
  final T? _defaultValue;

  void set(T? value) => _service.setContext(key, value);

  void reset() {
    if (_defaultValue == null) {
      _service.removeContext(key);
    } else {
      _service.setContext(key, _defaultValue);
    }
  }

  T? get() => _service.getContextKeyValue(key) as T?;
}

/// One entry of `getContextKeyInfo` (`ContextKeyInfo`).
typedef ContextKeyInfo = ({String key, String? type, String? description});

/// `RawContextKey`: a key's name and default, to bind to a service.
final class RawContextKey<T> {
  RawContextKey(this.key, this.defaultValue, [this.description]) {
    _info.add((
      key: key,
      type: defaultValue == null ? null : _typeName(defaultValue!),
      description: description,
    ));
  }

  static final _info = <ContextKeyInfo>[];

  /// `RawContextKey.all()`: every key declared.
  static List<ContextKeyInfo> all() => List.unmodifiable(_info);

  static String _typeName(Object value) => switch (value) {
    final bool _ => 'boolean',
    final num _ => 'number',
    final String _ => 'string',
    _ => value.runtimeType.toString().toLowerCase(),
  };

  final String key;
  final T? defaultValue;
  final String? description;

  ContextKey<T> bindTo(AbstractContextKeyService target) =>
      target.createKey<T>(key, defaultValue);

  T? getValue(AbstractContextKeyService target) =>
      target.getContextKeyValue(key) as T?;

  ContextKeyExpression toExpression() => ContextKeyExpr.has(key);
  ContextKeyExpression toNegated() => ContextKeyExpr.not(key);
  ContextKeyExpression isEqualTo(Object? value) =>
      ContextKeyExpr.equals(key, value);
  ContextKeyExpression notEqualsTo(Object? value) =>
      ContextKeyExpr.notEquals(key, value);
}

/// What the workbench tells the context keys: the UI state it owns
/// (focus, the active editor, visible parts…). [ContextKeyService]
/// implements it; [WorkbenchContextKeys] writes the well-known keys through
/// one.
abstract interface class ContextKeyFeed {
  /// Sets [key] to [value] (null keeps the key, as `null`).
  void setContext(String key, Object? value);

  /// Removes [key]: it reads as unset (`undefined`).
  void removeContext(String key);

  /// Runs [callback], announcing its changes as one event.
  void bufferChangeEvents(void Function() callback);
}

/// The values [AbstractContextKeyService.contextMatchesRules] evaluates
/// against.
abstract interface class ContextKeyValues {
  Object? getContextKeyValue(String key);
  bool contextMatchesRules(ContextKeyExpression? rules);
  ContextKeyLookup get lookup;
}

/// `AbstractContextKeyService`.
abstract class AbstractContextKeyService
    implements ContextKeyFeed, ContextKeyValues {
  AbstractContextKeyService(this._myContextId);

  bool _isDisposed = false;
  final int _myContextId;

  int get contextId => _myContextId;
  bool get isDisposed => _isDisposed;

  final _listeners = <void Function(ContextKeyChangeEvent)>[];
  int _paused = 0;
  final _buffered = <ContextKeyChangeEvent>[];

  /// `onDidChangeContext`: returns what removes [listener].
  void Function() onDidChangeContext(
    void Function(ContextKeyChangeEvent event) listener,
  ) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  @protected
  void fire(ContextKeyChangeEvent event) {
    if (_paused > 0) {
      _buffered.add(event);
      return;
    }
    for (final l in List.of(_listeners)) {
      l(event);
    }
    didFire(event);
  }

  /// After an event reached the listeners.
  @protected
  void didFire(ContextKeyChangeEvent event) {}

  @override
  void bufferChangeEvents(void Function() callback) {
    _paused++;
    try {
      callback();
    } finally {
      _paused--;
      if (_paused == 0 && _buffered.isNotEmpty) {
        final events = List.of(_buffered);
        _buffered.clear();
        fire(
          events.length == 1 ? events.single : _CompositeChangeEvent(events),
        );
      }
    }
  }

  ContextKey<T> createKey<T>(String key, T? defaultValue) {
    if (_isDisposed) {
      throw StateError('AbstractContextKeyService has been disposed');
    }
    return ContextKey<T>._(this, key, defaultValue);
  }

  /// A child context over this one (an editor's, a view's).
  ScopedContextKeyService createScoped() {
    if (_isDisposed) {
      throw StateError('AbstractContextKeyService has been disposed');
    }
    return ScopedContextKeyService._(this);
  }

  /// This one's values with [overlay]'s over them (one menu item's).
  OverlayContextKeyService createOverlay([
    Map<String, Object?> overlay = const {},
  ]) {
    if (_isDisposed) {
      throw StateError('AbstractContextKeyService has been disposed');
    }
    return OverlayContextKeyService._(this, overlay);
  }

  @override
  bool contextMatchesRules(ContextKeyExpression? rules) {
    if (_isDisposed) {
      throw StateError('AbstractContextKeyService has been disposed');
    }
    final context = getContextValuesContainer(_myContextId);
    return rules == null || rules.evaluate(context.getValue);
  }

  @override
  Object? getContextKeyValue(String key) {
    if (_isDisposed) return null;
    return getContextValuesContainer(_myContextId).getValue(key);
  }

  @override
  ContextKeyLookup get lookup => getContextKeyValue;

  @override
  void setContext(String key, Object? value) {
    if (_isDisposed) return;
    final myContext = getContextValuesContainer(_myContextId);
    if (myContext.setValue(key, value)) fire(_SimpleChangeEvent(key));
  }

  @override
  void removeContext(String key) {
    if (_isDisposed) return;
    if (getContextValuesContainer(_myContextId).removeValue(key)) {
      fire(_SimpleChangeEvent(key));
    }
  }

  Context getContextValuesContainer(int contextId);
  int createChildContext([int? parentContextId]);
  void disposeContext(int contextId);

  void dispose() {
    _isDisposed = true;
    _listeners.clear();
  }
}

/// `ContextKeyService`: the window's root context keys.
final class ContextKeyService extends AbstractContextKeyService
    with ChangeNotifier {
  ContextKeyService({ContextKeyConfiguration? configuration}) : super(0) {
    final root = _RootContext(0, configuration, fire);
    _root = root;
    _contexts[0] = root;
    for (final MapEntry(:key, :value) in contextKeyConstants.entries) {
      if (key != 'true' && key != 'false') root.setValue(key, value);
    }
  }

  late final _RootContext _root;
  int _lastContextId = 0;
  final _contexts = <int, Context>{};

  /// Reads the keys this service does not hold: the workbench's own lookup
  /// of its UI state (focus, visible parts…), after the values set here.
  ContextKeyLookup? get fallback => _root.fallback;
  set fallback(ContextKeyLookup? value) {
    _root.fallback = value;
    notifyExternalChange();
  }

  /// Something the [fallback] reads changed: menus and enablement
  /// re-evaluate.
  void notifyExternalChange() => fire(const _AnyChangeEvent());

  @override
  void didFire(ContextKeyChangeEvent event) => notifyListeners();

  @override
  Context getContextValuesContainer(int contextId) {
    if (_isDisposed) return _NullContext.instance;
    return _contexts[contextId] ?? _NullContext.instance;
  }

  @override
  int createChildContext([int? parentContextId]) {
    if (_isDisposed) throw StateError('ContextKeyService has been disposed');
    final id = ++_lastContextId;
    _contexts[id] = Context(
      id,
      getContextValuesContainer(parentContextId ?? _myContextId),
    );
    return id;
  }

  @override
  void disposeContext(int contextId) {
    if (!_isDisposed) _contexts.remove(contextId);
  }

  @override
  void dispose() {
    _root.dispose();
    super.dispose();
  }
}

/// `ScopedContextKeyService`: a child context (an editor's, a view's);
/// its own values hide its parent's.
final class ScopedContextKeyService extends AbstractContextKeyService {
  ScopedContextKeyService._(AbstractContextKeyService parent)
    : _parent = parent,
      super(parent.createChildContext()) {
    _updateParentChangeListener();
  }

  AbstractContextKeyService _parent;
  void Function()? _parentListener;

  void _updateParentChangeListener() {
    _parentListener?.call();
    _parentListener = _parent.onDidChangeContext((e) {
      final values = _parent.getContextValuesContainer(_myContextId).value;
      if (!e.allKeysContainedIn(values.keys.toSet())) fire(e);
    });
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _parentListener?.call();
    _parentListener = null;
    _parent.disposeContext(_myContextId);
    super.dispose();
  }

  @override
  Context getContextValuesContainer(int contextId) {
    if (_isDisposed) return _NullContext.instance;
    return _parent.getContextValuesContainer(contextId);
  }

  @override
  int createChildContext([int? parentContextId]) {
    if (_isDisposed) {
      throw StateError('ScopedContextKeyService has been disposed');
    }
    return _parent.createChildContext(parentContextId ?? _myContextId);
  }

  @override
  void disposeContext(int contextId) => _parent.disposeContext(contextId);

  /// Moves it under [parentContextKeyService].
  void updateParent(AbstractContextKeyService parentContextKeyService) {
    if (identical(_parent, parentContextKeyService)) return;
    final thisContainer = _parent.getContextValuesContainer(_myContextId);
    final oldAllValues = thisContainer.collectAllValues();
    _parent = parentContextKeyService;
    _updateParentChangeListener();
    final newParentContainer = _parent.getContextValuesContainer(
      _parent.contextId,
    );
    thisContainer.updateParent(newParentContainer);
    final newAllValues = thisContainer.collectAllValues();
    final changedKeys = {
      for (final k in {...oldAllValues.keys, ...newAllValues.keys})
        if (!_valueEquals(oldAllValues[k], newAllValues[k])) k,
    };
    fire(_ArrayChangeEvent(changedKeys.toList()));
  }
}

/// `OverlayContextKeyService`: a service's values with some replaced.
final class OverlayContextKeyService implements ContextKeyValues {
  OverlayContextKeyService._(this._parent, Map<String, Object?> overlay)
    : _overlay = Map.of(overlay);

  final ContextKeyValues _parent;
  final Map<String, Object?> _overlay;

  void Function() onDidChangeContext(
    void Function(ContextKeyChangeEvent event) listener,
  ) => switch (_parent) {
    final AbstractContextKeyService p => p.onDidChangeContext(listener),
    final OverlayContextKeyService p => p.onDidChangeContext(listener),
    _ => () {},
  };

  @override
  Object? getContextKeyValue(String key) => _overlay.containsKey(key)
      ? _overlay[key]
      : _parent.getContextKeyValue(key);

  @override
  ContextKeyLookup get lookup => getContextKeyValue;

  @override
  bool contextMatchesRules(ContextKeyExpression? rules) =>
      rules == null || rules.evaluate(getContextKeyValue);

  OverlayContextKeyService createOverlay([
    Map<String, Object?> overlay = const {},
  ]) => OverlayContextKeyService._(this, overlay);
}

/// A [ContextKeyValues] over a plain lookup (tests, one-off evaluation).
final class LookupContextKeyValues implements ContextKeyValues {
  const LookupContextKeyValues(this.lookup);

  @override
  final ContextKeyLookup lookup;

  @override
  Object? getContextKeyValue(String key) => lookup(key);

  @override
  bool contextMatchesRules(ContextKeyExpression? rules) =>
      rules == null || rules.evaluate(lookup);
}

/// `setContext` (`_setContext`): an extension's key, URIs as strings.
void setContextFromCommand(
  ContextKeyFeed service,
  Object? contextKey,
  Object? contextValue,
) => service.setContext('$contextKey', stringifyUris(contextValue));

/// `stringifyURIs`: URIs (marshalled or revived) as their string form.
Object? stringifyUris(Object? value) {
  if (value is VsUri) return value.toString();
  if (value is Map) {
    if (value[r'$mid'] == uriMarshalledId) {
      return VsUri.revive(value.cast<String, Object?>()).toString();
    }
    return {
      for (final MapEntry(:key, value: v) in value.entries)
        '$key': stringifyUris(v),
    };
  }
  if (value is List) return [for (final v in value) stringifyUris(v)];
  return value;
}
