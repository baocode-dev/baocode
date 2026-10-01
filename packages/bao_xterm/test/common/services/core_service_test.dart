// Copyright (c) 2019 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/LICENSE.txt.
// Adapted from xterm.js src/common/services/CoreService.test.ts (c58ea36).

import 'package:flutter_test/flutter_test.dart';
import 'package:bao_xterm/common/services/core_service.dart';
import 'package:bao_xterm/common/services/services.dart';

import 'package:bao_xterm/testing/test_utils.dart';

void main() {
  group('CoreService', () {
    late ICoreService coreService;

    setUp(() {
      coreService = CoreService(
        MockBufferService(80, 30),
        MockLogService(),
        MockOptionsService(),
      );
    });

    group('isCursorInitialized', () {
      test('should be false by default', () {
        expect(coreService.isCursorInitialized, false);
      });
      test('should be true when showCursorImmediately is true', () {
        final coreServiceWithOption = CoreService(
          MockBufferService(80, 30),
          MockLogService(),
          MockOptionsService(ITerminalOptions(showCursorImmediately: true)),
        );
        expect(coreServiceWithOption.isCursorInitialized, true);
      });
    });

    group('reset', () {
      test('should not affect isCursorInitialized', () {
        coreService.isCursorInitialized = true;
        coreService.reset();
        expect(coreService.isCursorInitialized, true);
        coreService.isCursorInitialized = false;
        coreService.reset();
        expect(coreService.isCursorInitialized, false);
      });
    });
  });
}
