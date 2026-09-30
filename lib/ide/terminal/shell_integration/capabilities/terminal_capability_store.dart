/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// A terminal's capabilities, told as they come and go; and a store that is
// the union of others.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/platform/terminal/common/capabilities/terminalCapabilityStore.ts.
//
// Upstream's `@memoize` getters are `late final` fields.

import '../../xterm/common/event.dart';
import '../../xterm/common/lifecycle.dart';
import 'capabilities.dart';

class TerminalCapabilityStore extends Disposable
    implements ITerminalCapabilityStore {
  final Map<TerminalCapability, Object> _map = {};

  late final _onDidAddCapability = register(
    Emitter<TerminalCapabilityChangeEvent>(),
  );
  @override
  IEvent<TerminalCapabilityChangeEvent> get onDidAddCapability =>
      _onDidAddCapability.event;
  late final _onDidRemoveCapability = register(
    Emitter<TerminalCapabilityChangeEvent>(),
  );
  @override
  IEvent<TerminalCapabilityChangeEvent> get onDidRemoveCapability =>
      _onDidRemoveCapability.event;

  @override
  late final IEvent<void> onDidChangeCapabilities = _onDidChangeCapabilities(
    _onDidAddCapability.event,
    _onDidRemoveCapability.event,
  );
  @override
  late final IEvent<ICommandDetectionCapability>
  onDidAddCommandDetectionCapability = _ofType(
    onDidAddCapability,
    TerminalCapability.commandDetection,
  );
  @override
  late final IEvent<void> onDidRemoveCommandDetectionCapability = _ofType(
    onDidRemoveCapability,
    TerminalCapability.commandDetection,
  );
  @override
  late final IEvent<ICwdDetectionCapability> onDidAddCwdDetectionCapability =
      _ofType(onDidAddCapability, TerminalCapability.cwdDetection);
  @override
  late final IEvent<void> onDidRemoveCwdDetectionCapability = _ofType(
    onDidRemoveCapability,
    TerminalCapability.cwdDetection,
  );

  @override
  Iterable<TerminalCapability> get items => _map.keys;

  @override
  IEvent<T> createOnDidRemoveCapabilityOfTypeEvent<T extends Object>(
    TerminalCapability<T> type,
  ) => _ofType(onDidRemoveCapability, type);

  @override
  IEvent<T> createOnDidAddCapabilityOfTypeEvent<T extends Object>(
    TerminalCapability<T> type,
  ) => _ofType(onDidAddCapability, type);

  void add<T extends Object>(TerminalCapability<T> capability, T impl) {
    _map[capability] = impl;
    _onDidAddCapability.fire(TerminalCapabilityChangeEvent(capability, impl));
  }

  @override
  T? get<T extends Object>(TerminalCapability<T> capability) {
    return _map[capability] as T?;
  }

  void remove(TerminalCapability capability) {
    final impl = _map[capability];
    if (impl == null) {
      return;
    }
    _map.remove(capability);
    _onDidRemoveCapability.fire(
      TerminalCapabilityChangeEvent(capability, impl),
    );
  }

  @override
  bool has(TerminalCapability capability) {
    return _map.containsKey(capability);
  }
}

class TerminalCapabilityStoreMultiplexer extends Disposable
    implements ITerminalCapabilityStore {
  final List<ITerminalCapabilityStore> stores = [];

  late final _onDidAddCapability = register(
    Emitter<TerminalCapabilityChangeEvent>(),
  );
  @override
  IEvent<TerminalCapabilityChangeEvent> get onDidAddCapability =>
      _onDidAddCapability.event;
  late final _onDidRemoveCapability = register(
    Emitter<TerminalCapabilityChangeEvent>(),
  );
  @override
  IEvent<TerminalCapabilityChangeEvent> get onDidRemoveCapability =>
      _onDidRemoveCapability.event;

  @override
  late final IEvent<void> onDidChangeCapabilities = _onDidChangeCapabilities(
    _onDidAddCapability.event,
    _onDidRemoveCapability.event,
  );
  @override
  late final IEvent<ICommandDetectionCapability>
  onDidAddCommandDetectionCapability = _ofType(
    onDidAddCapability,
    TerminalCapability.commandDetection,
  );
  @override
  late final IEvent<void> onDidRemoveCommandDetectionCapability = _ofType(
    onDidRemoveCapability,
    TerminalCapability.commandDetection,
  );
  @override
  late final IEvent<ICwdDetectionCapability> onDidAddCwdDetectionCapability =
      _ofType(onDidAddCapability, TerminalCapability.cwdDetection);
  @override
  late final IEvent<void> onDidRemoveCwdDetectionCapability = _ofType(
    onDidRemoveCapability,
    TerminalCapability.cwdDetection,
  );

  @override
  Iterable<TerminalCapability> get items sync* {
    for (final store in stores) {
      yield* store.items;
    }
  }

  @override
  IEvent<T> createOnDidRemoveCapabilityOfTypeEvent<T extends Object>(
    TerminalCapability<T> type,
  ) => _ofType(onDidRemoveCapability, type);

  @override
  IEvent<T> createOnDidAddCapabilityOfTypeEvent<T extends Object>(
    TerminalCapability<T> type,
  ) => _ofType(onDidAddCapability, type);

  @override
  bool has(TerminalCapability capability) {
    for (final store in stores) {
      for (final c in store.items) {
        if (c == capability) {
          return true;
        }
      }
    }
    return false;
  }

  @override
  T? get<T extends Object>(TerminalCapability<T> capability) {
    for (final store in stores) {
      final c = store.get(capability);
      if (c != null) {
        return c;
      }
    }
    return null;
  }

  void add(ITerminalCapabilityStore store) {
    stores.add(store);
    for (final capability in store.items) {
      _onDidAddCapability.fire(
        TerminalCapabilityChangeEvent(capability, store.get(capability)!),
      );
    }
    register(store.onDidAddCapability(_onDidAddCapability.fire));
    register(store.onDidRemoveCapability(_onDidRemoveCapability.fire));
  }
}

IEvent<void> _onDidChangeCapabilities(
  IEvent<TerminalCapabilityChangeEvent> onDidAdd,
  IEvent<TerminalCapabilityChangeEvent> onDidRemove,
) => EventUtils.map<TerminalCapabilityChangeEvent, void>(
  EventUtils.any([onDidAdd, onDidRemove]),
  (_) {},
);

/// Upstream `Event.map(Event.filter(event, e => e.id === type), e =>
/// e.capability)`.
IEvent<T> _ofType<T extends Object>(
  IEvent<TerminalCapabilityChangeEvent> event,
  TerminalCapability<T> type,
) =>
    (listener) => event((e) {
      if (e.id == type) {
        listener(e.capability as T);
      }
    });
