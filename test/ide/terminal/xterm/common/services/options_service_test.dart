// Copyright (c) 2020 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Adapted from xterm.js src/common/services/OptionsService.test.ts (c58ea36).

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/terminal/xterm/common/lifecycle.dart';
import 'package:monad/ide/terminal/xterm/common/services/options_service.dart';
import 'package:monad/ide/terminal/xterm/common/services/services.dart';

void main() {
  group('OptionsService', () {
    group('constructor', () {
      // Upstream silences console.error; invalid values are printed here.
      test('uses default value if invalid constructor option values passed for cols/rows', () {
        final optionsService = OptionsService(
          ITerminalOptions(cols: null, rows: null),
        );
        expect(optionsService.options.rows, defaultOptions.rows);
        expect(optionsService.options.cols, defaultOptions.cols);
      });
      test(
        'uses values from constructor option values if correctly passed',
        () {
          final optionsService = OptionsService(
            ITerminalOptions(cols: 80, rows: 25),
          );
          expect(optionsService.options.rows, 25);
          expect(optionsService.options.cols, 80);
        },
      );
      test('uses default value if invalid constructor option value passed', () {
        expect(
          OptionsService(ITerminalOptions(tabStopWidth: 0))
              .options
              .tabStopWidth,
          defaultOptions.tabStopWidth,
        );
      });
      test('object.keys return the correct number of options', () {
        final optionsService = OptionsService(
          ITerminalOptions(cols: 80, rows: 25),
        );
        expect(optionsService.options.keys.length, isNot(0));
      });
    });
    group('setOption', () {
      late OptionsService service;
      setUp(() {
        service = OptionsService(ITerminalOptions());
      });
      test('applies valid fontWeight option values', () {
        service.options.fontWeight = 'bold';
        expect(
          service.options.fontWeight,
          'bold',
          reason: '"bold" keyword value should be applied',
        );

        service.options.fontWeight = 'normal';
        expect(
          service.options.fontWeight,
          'normal',
          reason: '"normal" keyword value should be applied',
        );

        service.options.fontWeight = '600';
        expect(
          service.options.fontWeight,
          '600',
          reason: 'String numeric values should be applied',
        );

        service.options.fontWeight = 350;
        expect(
          service.options.fontWeight,
          350,
          reason: 'Values between 1 and 1000 should be applied as is',
        );

        service.options.fontWeight = 1;
        expect(
          service.options.fontWeight,
          1,
          reason: 'Range should include minimum value: 1',
        );

        service.options.fontWeight = 1000;
        expect(
          service.options.fontWeight,
          1000,
          reason: 'Range should include maximum value: 1000',
        );
      });
      test('normalizes invalid fontWeight option values', () {
        service.options.fontWeight = 350;
        expect(
          () => service.options.fontWeight = 10000,
          returnsNormally,
          reason: 'fontWeight should be normalized instead of throwing',
        );
        expect(
          service.options.fontWeight,
          defaultOptions.fontWeight,
          reason: 'Values greater than 1000 should be reset to default',
        );

        service.options.fontWeight = 350;
        service.options.fontWeight = -10;
        expect(
          service.options.fontWeight,
          defaultOptions.fontWeight,
          reason: 'Values less than 1 should be reset to default',
        );

        service.options.fontWeight = 350;
        service.options.fontWeight = 'bold700';
        expect(
          service.options.fontWeight,
          defaultOptions.fontWeight,
          reason: 'Wrong string literals should be reset to default',
        );
      });
    });
    group('onOptionChange', () {
      late OptionsService service;
      setUp(() {
        service = OptionsService(ITerminalOptions());
      });
      test('should fire on any option change', () async {
        late IDisposable disposable;
        final first = Completer<void>();
        disposable = service.onOptionChange((e) {
          expect(e, 'cursorWidth');
          first.complete();
        });
        service.options.cursorWidth = 10;
        await first.future;
        disposable.dispose();
        final second = Completer<void>();
        service.onOptionChange((e) {
          expect(e, 'scrollback');
          second.complete();
        });
        service.options.scrollback = 20;
        await second.future;
      });
    });
    group('onSpecificOptionChange', () {
      late OptionsService service;
      setUp(() {
        service = OptionsService(ITerminalOptions());
      });
      test('should fire only on a specific option change', () async {
        final done = Completer<void>();
        service.onSpecificOptionChange<int>('scrollback', (e) {
          expect(e, 20);
          done.complete();
        });
        service.options.cursorWidth = 10;
        service.options.scrollback = 20;
        await done.future;
      });
    });
    group('onSpecificOptionChange', () {
      late OptionsService service;
      setUp(() {
        service = OptionsService(ITerminalOptions());
      });
      test('should fire only on a specific option change', () async {
        final done = Completer<void>();
        service.onSpecificOptionChange<int>('scrollback', (e) {
          expect(e, 20);
          done.complete();
        });
        service.options.cursorWidth = 10;
        service.options.scrollback = 20;
        await done.future;
      });
    });
    group('onMultipleOptionChange', () {
      late OptionsService service;
      setUp(() {
        service = OptionsService(ITerminalOptions());
      });
      test('should fire only for specific options', () async {
        var called = false;
        service.onMultipleOptionChange(['scrollback'], () {
          called = true;
        });
        service.options.cursorWidth = 10;
        expect(called, isFalse);
        service.options.scrollback = 20;
        expect(called, isTrue);
      });
    });
  });
}
