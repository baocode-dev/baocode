/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/contrib/terminal/test/browser/capabilities/
// terminalCapabilityStore.test.ts. Upstream adds `{}` as each capability;
// here a real CwdDetectionCapability, or fakes for the others.

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/terminal/shell_integration/capabilities/capabilities.dart';
import 'package:baocode/ide/terminal/shell_integration/capabilities/cwd_detection_capability.dart';
import 'package:baocode/ide/terminal/shell_integration/capabilities/terminal_capability_store.dart';
import 'package:bao_xterm/common/event.dart';

class _FakeNaiveCwdDetection implements INaiveCwdDetectionCapability {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCommandDetection implements ICommandDetectionCapability {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('TerminalCapabilityStore', () {
    late TerminalCapabilityStore capabilityStore;
    late List<TerminalCapability> addEvents;
    late List<TerminalCapability> removeEvents;

    setUp(() {
      capabilityStore = TerminalCapabilityStore();
      addTearDown(capabilityStore.dispose);
      addEvents = [];
      removeEvents = [];
      capabilityStore.onDidAddCapability((e) => addEvents.add(e.id));
      capabilityStore.onDidRemoveCapability((e) => removeEvents.add(e.id));
    });

    test('should fire events when capabilities are added', () {
      _assertEvents(addEvents, []);
      capabilityStore.add(
        TerminalCapability.cwdDetection,
        CwdDetectionCapability(),
      );
      _assertEvents(addEvents, [TerminalCapability.cwdDetection]);
    });
    test('should fire events when capabilities are removed', () {
      _assertEvents(removeEvents, []);
      capabilityStore.add(
        TerminalCapability.cwdDetection,
        CwdDetectionCapability(),
      );
      _assertEvents(removeEvents, []);
      capabilityStore.remove(TerminalCapability.cwdDetection);
      _assertEvents(removeEvents, [TerminalCapability.cwdDetection]);
    });
    test('has should return whether a capability is present', () {
      expect(capabilityStore.has(TerminalCapability.cwdDetection), false);
      capabilityStore.add(
        TerminalCapability.cwdDetection,
        CwdDetectionCapability(),
      );
      expect(capabilityStore.has(TerminalCapability.cwdDetection), true);
      capabilityStore.remove(TerminalCapability.cwdDetection);
      expect(capabilityStore.has(TerminalCapability.cwdDetection), false);
    });
    test('items should reflect current state', () {
      expect(capabilityStore.items.toList(), <TerminalCapability>[]);
      capabilityStore.add(
        TerminalCapability.cwdDetection,
        CwdDetectionCapability(),
      );
      expect(capabilityStore.items.toList(), [TerminalCapability.cwdDetection]);
      capabilityStore.add(
        TerminalCapability.naiveCwdDetection,
        _FakeNaiveCwdDetection(),
      );
      expect(capabilityStore.items.toList(), [
        TerminalCapability.cwdDetection,
        TerminalCapability.naiveCwdDetection,
      ]);
      capabilityStore.remove(TerminalCapability.cwdDetection);
      expect(capabilityStore.items.toList(), [
        TerminalCapability.naiveCwdDetection,
      ]);
    });
    test('ensure events are memoized', () {
      for (final getEvent in _getDerivedEventGetters(capabilityStore)) {
        expect(identical(getEvent(), getEvent()), isTrue);
      }
    });
    test('ensure events are cleaned up', () {
      for (final getEvent in _getDerivedEventGetters(capabilityStore)) {
        getEvent()((_) {}).dispose();
      }
    });

    // New: not upstream.
    test('get is typed by the capability', () {
      final cwdDetection = CwdDetectionCapability();
      capabilityStore.add(TerminalCapability.cwdDetection, cwdDetection);
      final ICwdDetectionCapability? got = capabilityStore.get(
        TerminalCapability.cwdDetection,
      );
      expect(got, same(cwdDetection));
      expect(capabilityStore.get(TerminalCapability.commandDetection), isNull);
      final added = <ICwdDetectionCapability>[];
      capabilityStore.onDidAddCwdDetectionCapability(added.add);
      final typed = <ICwdDetectionCapability>[];
      capabilityStore.createOnDidAddCapabilityOfTypeEvent(
        TerminalCapability.cwdDetection,
      )(typed.add);
      capabilityStore.add(
        TerminalCapability.naiveCwdDetection,
        _FakeNaiveCwdDetection(),
      );
      capabilityStore.add(TerminalCapability.cwdDetection, cwdDetection);
      expect(added, [cwdDetection]);
      expect(typed, [cwdDetection]);
    });
  });

  group('TerminalCapabilityStoreMultiplexer', () {
    late TerminalCapabilityStoreMultiplexer multiplexer;
    late TerminalCapabilityStore store1;
    late TerminalCapabilityStore store2;
    late List<TerminalCapability> addEvents;
    late List<TerminalCapability> removeEvents;

    setUp(() {
      multiplexer = TerminalCapabilityStoreMultiplexer();
      addTearDown(multiplexer.dispose);
      multiplexer.onDidAddCapability((e) => addEvents.add(e.id));
      multiplexer.onDidRemoveCapability((e) => removeEvents.add(e.id));
      store1 = TerminalCapabilityStore();
      store2 = TerminalCapabilityStore();
      addTearDown(store1.dispose);
      addTearDown(store2.dispose);
      addEvents = [];
      removeEvents = [];
    });

    test('should fire events when capabilities are enabled', () {
      _assertEvents(addEvents, []);
      multiplexer.add(store1);
      multiplexer.add(store2);
      store1.add(TerminalCapability.cwdDetection, CwdDetectionCapability());
      _assertEvents(addEvents, [TerminalCapability.cwdDetection]);
      store2.add(
        TerminalCapability.naiveCwdDetection,
        _FakeNaiveCwdDetection(),
      );
      _assertEvents(addEvents, [TerminalCapability.naiveCwdDetection]);
    });
    test('should fire events when capabilities are disabled', () {
      _assertEvents(removeEvents, []);
      multiplexer.add(store1);
      multiplexer.add(store2);
      store1.add(TerminalCapability.cwdDetection, CwdDetectionCapability());
      store2.add(
        TerminalCapability.naiveCwdDetection,
        _FakeNaiveCwdDetection(),
      );
      _assertEvents(removeEvents, []);
      store1.remove(TerminalCapability.cwdDetection);
      _assertEvents(removeEvents, [TerminalCapability.cwdDetection]);
      store2.remove(TerminalCapability.naiveCwdDetection);
      _assertEvents(removeEvents, [TerminalCapability.naiveCwdDetection]);
    });
    test('should fire events when stores are added', () {
      _assertEvents(addEvents, []);
      store1.add(TerminalCapability.cwdDetection, CwdDetectionCapability());
      _assertEvents(addEvents, []);
      store2.add(
        TerminalCapability.naiveCwdDetection,
        _FakeNaiveCwdDetection(),
      );
      multiplexer.add(store1);
      multiplexer.add(store2);
      _assertEvents(addEvents, [
        TerminalCapability.cwdDetection,
        TerminalCapability.naiveCwdDetection,
      ]);
    });
    test('items should return items from all stores', () {
      Set<TerminalCapability> items() => multiplexer.items.toSet();
      expect(items(), <TerminalCapability>{});
      multiplexer.add(store1);
      multiplexer.add(store2);
      store1.add(TerminalCapability.cwdDetection, CwdDetectionCapability());
      expect(items(), {TerminalCapability.cwdDetection});
      store1.add(TerminalCapability.commandDetection, _FakeCommandDetection());
      store2.add(
        TerminalCapability.naiveCwdDetection,
        _FakeNaiveCwdDetection(),
      );
      expect(items(), {
        TerminalCapability.cwdDetection,
        TerminalCapability.commandDetection,
        TerminalCapability.naiveCwdDetection,
      });
      store2.remove(TerminalCapability.naiveCwdDetection);
      expect(items(), {
        TerminalCapability.cwdDetection,
        TerminalCapability.commandDetection,
      });
    });
    test('has should return whether a capability is present', () {
      expect(multiplexer.has(TerminalCapability.cwdDetection), false);
      multiplexer.add(store1);
      store1.add(TerminalCapability.cwdDetection, CwdDetectionCapability());
      expect(multiplexer.has(TerminalCapability.cwdDetection), true);
      store1.remove(TerminalCapability.cwdDetection);
      expect(multiplexer.has(TerminalCapability.cwdDetection), false);
    });
    test('ensure events are memoized', () {
      for (final getEvent in _getDerivedEventGetters(multiplexer)) {
        expect(identical(getEvent(), getEvent()), isTrue);
      }
    });
    test('ensure events are cleaned up', () {
      for (final getEvent in _getDerivedEventGetters(multiplexer)) {
        getEvent()((_) {}).dispose();
      }
    });
  });
}

void _assertEvents(
  List<TerminalCapability> actual,
  List<TerminalCapability> expected,
) {
  expect(actual, expected);
  actual.clear();
}

List<IEvent<Object?> Function()> _getDerivedEventGetters(
  ITerminalCapabilityStore capabilityStore,
) {
  return [
    () => capabilityStore.onDidChangeCapabilities,
    () => capabilityStore.onDidAddCommandDetectionCapability,
    () => capabilityStore.onDidRemoveCommandDetectionCapability,
    () => capabilityStore.onDidAddCwdDetectionCapability,
    () => capabilityStore.onDidRemoveCwdDetectionCapability,
  ];
}
