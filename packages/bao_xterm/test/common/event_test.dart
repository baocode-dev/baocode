// Copyright (c) 2024-2026 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/LICENSE.txt.
// Adapted from xterm.js src/common/Event.test.ts (c58ea36).

import 'package:flutter_test/flutter_test.dart';
import 'package:bao_xterm/common/event.dart';
import 'package:bao_xterm/common/lifecycle.dart';

class _Handler {
  int value = 0;

  void handler(int e) {
    value = e;
  }
}

void main() {
  group('Emitter', () {
    test('should fire with 0 listeners without error', () {
      final emitter = Emitter<int>();
      emitter.fire(42);
    });

    test('should fire with 1 listener', () {
      final emitter = Emitter<int>();
      int? received;
      emitter.event((e) {
        received = e;
      });
      emitter.fire(42);
      expect(received, 42);
    });

    // Upstream passes `thisArgs`; a Dart tear-off is bound to its object.
    test('should fire with 1 listener using thisArgs', () {
      final emitter = Emitter<int>();
      final obj = _Handler();
      emitter.event(obj.handler);
      emitter.fire(42);
      expect(obj.value, 42);
    });

    test('should fire with multiple listeners', () {
      final emitter = Emitter<int>();
      final results = <int>[];
      emitter.event((e) => results.add(e * 1));
      emitter.event((e) => results.add(e * 2));
      emitter.event((e) => results.add(e * 3));
      emitter.fire(10);
      expect(results, equals([10, 20, 30]));
    });

    test('should handle listener removal during fire', () {
      final emitter = Emitter<int>();
      final results = <String>[];
      emitter.event((_) => results.add('first'));
      late final IDisposable disposable;
      disposable = emitter.event((_) {
        results.add('second');
        disposable.dispose();
      });
      emitter.event((_) => results.add('third'));
      emitter.fire(1);
      expect(results, equals(['first', 'second', 'third']));
    });

    test('should not fire after dispose', () {
      final emitter = Emitter<int>();
      var called = false;
      emitter.event((_) {
        called = true;
      });
      emitter.dispose();
      emitter.fire(42);
      expect(called, false);
    });

    test('should allow disposing a listener', () {
      final emitter = Emitter<int>();
      var count = 0;
      final disposable = emitter.event((_) {
        count++;
      });
      emitter.fire(1);
      disposable.dispose();
      emitter.fire(2);
      expect(count, 1);
    });
  });
}
