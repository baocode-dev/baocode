// Copyright (c) 2019 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Adapted from xterm.js src/common/services/MouseStateService.test.ts
// (c58ea36).

import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/terminal/xterm/common/services/mouse_state_service.dart';
import 'package:monad/ide/terminal/xterm/common/types.dart';

List<int> toBytes(String? s) {
  if (s == null || s.isEmpty) {
    return <int>[];
  }
  final res = <int>[];
  for (var i = 0; i < s.length; ++i) {
    res.add(s.codeUnitAt(i));
  }
  return res;
}

/// chai's `assert.throws(fn, msg)`: the thrown error's message contains [msg].
Matcher throwsWithMessage(String msg) => throwsA(
  predicate<Object>(
    (e) => e.toString().contains(msg),
    'an error whose message contains \'$msg\'',
  ),
);

void main() {
  group('MouseStateService', () {
    test('init', () {
      final cms = MouseStateService();
      expect(cms.activeEncoding, 'DEFAULT');
      expect(cms.activeProtocol, 'NONE');
    });
    test('default protocols - NONE, X10, VT200, DRAG, ANY', () {
      final cms = MouseStateService();
      expect(
        cms.protocols.keys.toList(),
        equals(['NONE', 'X10', 'VT200', 'DRAG', 'ANY']),
      );
    });
    test('default encodings - DEFAULT, SGR', () {
      final cms = MouseStateService();
      expect(
        cms.encodings.keys.toList(),
        equals(['DEFAULT', 'SGR', 'SGR_PIXELS']),
      );
    });
    test('protocol/encoding setter, reset', () {
      final cms = MouseStateService();
      cms.activeEncoding = 'SGR';
      cms.activeProtocol = 'ANY';
      expect(cms.activeEncoding, 'SGR');
      expect(cms.activeProtocol, 'ANY');
      cms.reset();
      expect(cms.activeEncoding, 'DEFAULT');
      expect(cms.activeProtocol, 'NONE');
      expect(() {
        cms.activeEncoding = 'xyz';
      }, throwsWithMessage('unknown encoding "xyz"'));
      expect(() {
        cms.activeProtocol = 'xyz';
      }, throwsWithMessage('unknown protocol "xyz"'));
    });
    test('addEncoding', () {
      final cms = MouseStateService();
      cms.addEncoding('XYZ', (ICoreMouseEvent e) => '');
      cms.activeEncoding = 'XYZ';
      expect(cms.activeEncoding, 'XYZ');
    });
    test('addProtocol', () {
      final cms = MouseStateService();
      cms.addProtocol(
        'XYZ',
        ICoreMouseProtocol(
          events: CoreMouseEventType.none,
          restrict: (ICoreMouseEvent e) => false,
        ),
      );
      cms.activeProtocol = 'XYZ';
      expect(cms.activeProtocol, 'XYZ');
    });
    test('onProtocolChange', () {
      final cms = MouseStateService();
      final wantedEvents = <int>[];
      cms.onProtocolChange(wantedEvents.add);
      cms.activeProtocol = 'NONE';
      expect(wantedEvents, equals([CoreMouseEventType.none]));
      cms.activeProtocol = 'ANY';
      expect(
        wantedEvents,
        equals([
          CoreMouseEventType.none,
          CoreMouseEventType.down |
              CoreMouseEventType.up |
              CoreMouseEventType.wheel |
              CoreMouseEventType.drag |
              CoreMouseEventType.move,
        ]),
      );
    });
    test('restrictMouseEvent/encodeMouseEvent', () {
      final cms = MouseStateService();
      final event = ICoreMouseEvent(
        col: 1,
        row: 1,
        x: 0,
        y: 0,
        button: 0,
        action: 1,
        ctrl: false,
        alt: false,
        shift: false,
      );
      cms.activeProtocol = 'ANY';
      cms.activeEncoding = 'DEFAULT';
      expect(cms.restrictMouseEvent(event), true);
      expect(
        toBytes(cms.encodeMouseEvent(event)),
        equals([0x1b, 0x5b, 0x4d, 0x20, 0x21, 0x21]),
      );
    });
  });
}
