// The workbench's services, one set to a window: what each part of the
// workbench reads, and what it changes (see docs/workbench-architecture.md).
//
// After VS Code's `InstantiationService` and `ServiceCollection`
// (src/vs/platform/instantiation/common/), without its decorators: a
// service is made with what it needs passed to its constructor, in the
// order the workbench adds them.

import 'package:flutter/widgets.dart';

/// What a service or a contribution lets go of as the window closes
/// (upstream `IDisposable`).
abstract interface class WorkbenchDisposable {
  void dispose();
}

/// A window's services, by their type.
class WorkbenchServices {
  final Map<Type, Object> _services = {};
  final List<Object> _order = [];
  bool _disposed = false;

  /// Adds [service] as the window's [T], and returns it: one of a type.
  T add<T extends Object>(T service) {
    assert(!_disposed, 'services added after dispose');
    if (_services.containsKey(T)) {
      throw StateError('$T is already a service');
    }
    _services[T] = service;
    _order.add(service);
    return service;
  }

  /// The window's [T]; one it has not is a mistake.
  T get<T extends Object>() => switch (_services[T]) {
    final T service => service,
    _ => throw StateError('No $T service'),
  };

  /// The window's [T], where it has one (the debugger, a language server's).
  T? find<T extends Object>() => _services[T] as T?;

  bool has<T extends Object>() => _services.containsKey(T);

  /// Removes the window's [T], disposing it where it is [owned] (a
  /// workspace's service, made again for the next one).
  void remove<T extends Object>({bool owned = true}) {
    final service = _services.remove(T);
    if (service == null) return;
    _order.remove(service);
    if (owned) _disposeOf(service);
  }

  /// The services gone with the window, the last added first.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final service in _order.reversed) {
      _disposeOf(service);
    }
    _order.clear();
    _services.clear();
  }

  static void _disposeOf(Object service) {
    switch (service) {
      case final WorkbenchDisposable disposable:
        disposable.dispose();
      case final ChangeNotifier notifier:
        notifier.dispose();
    }
  }
}

/// Hands a window's [services] to the widgets under it.
class WorkbenchScope extends InheritedWidget {
  const WorkbenchScope({
    super.key,
    required this.services,
    required super.child,
  });

  final WorkbenchServices services;

  static WorkbenchServices? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WorkbenchScope>()?.services;

  static WorkbenchServices of(BuildContext context) {
    final services = maybeOf(context);
    assert(services != null, 'No WorkbenchScope above $context');
    return services!;
  }

  @override
  bool updateShouldNotify(WorkbenchScope oldWidget) =>
      !identical(services, oldWidget.services);
}
