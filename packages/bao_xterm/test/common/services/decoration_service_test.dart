// Copyright (c) 2019 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/LICENSE.txt.
// Adapted from xterm.js src/common/services/DecorationService.test.ts
// (c58ea36).

import 'package:flutter_test/flutter_test.dart';
import 'package:bao_xterm/common/buffer/buffer.dart';
import 'package:bao_xterm/common/buffer/buffer_line.dart';
import 'package:bao_xterm/common/services/decoration_service.dart';
import 'package:bao_xterm/common/services/services.dart';
import 'package:bao_xterm/typings/xterm.dart' show IDecorationOptions;

import 'package:bao_xterm/testing/test_utils.dart';

void main() {
  group('DecorationService', () {
    late MockBufferService bufferService;
    late DecorationService service;

    setUp(() {
      bufferService = MockBufferService(80, 24, MockOptionsService());
      service = DecorationService(MockLogService(), bufferService);
    });

    test('should set isDisposed to true after dispose', () {
      final decoration = service.registerDecoration(
        IDecorationOptions(marker: bufferService.buffer.addMarker(1)),
      );
      expect(decoration, isNotNull);
      expect(decoration!.isDisposed, isFalse);
      decoration.dispose();
      expect(decoration.isDisposed, isTrue);
    });

    group('forEachDecorationAtCell', () {
      test('should find decoration at its marker line', () {
        final decoration = service.registerDecoration(
          IDecorationOptions(
            marker: bufferService.buffer.addMarker(5),
            width: 10,
          ),
        );
        expect(decoration, isNotNull);
        final found = <IInternalDecoration>[];
        service.forEachDecorationAtCell(0, 5, null, found.add);
        expect(found.length, 1);
      });

      test('should find decoration with height > 1 on subsequent lines', () {
        final decoration = service.registerDecoration(
          IDecorationOptions(
            marker: bufferService.buffer.addMarker(5),
            width: 10,
            height: 3,
          ),
        );
        expect(decoration, isNotNull);

        final foundAt5 = <IInternalDecoration>[];
        service.forEachDecorationAtCell(0, 5, null, foundAt5.add);
        expect(foundAt5.length, 1);

        final foundAt6 = <IInternalDecoration>[];
        service.forEachDecorationAtCell(0, 6, null, foundAt6.add);
        expect(foundAt6.length, 1);

        final foundAt7 = <IInternalDecoration>[];
        service.forEachDecorationAtCell(0, 7, null, foundAt7.add);
        expect(foundAt7.length, 1);

        final foundAt8 = <IInternalDecoration>[];
        service.forEachDecorationAtCell(0, 8, null, foundAt8.add);
        expect(foundAt8.length, 0);
      });

      test('should not find decoration outside its x range', () {
        final decoration = service.registerDecoration(
          IDecorationOptions(
            marker: bufferService.buffer.addMarker(5),
            x: 5,
            width: 3,
            height: 2,
          ),
        );
        expect(decoration, isNotNull);
        final foundAtX4 = <IInternalDecoration>[];
        service.forEachDecorationAtCell(4, 5, null, foundAtX4.add);
        expect(foundAtX4.length, 0);

        final foundAtX5 = <IInternalDecoration>[];
        service.forEachDecorationAtCell(5, 5, null, foundAtX5.add);
        expect(foundAtX5.length, 1);

        final foundAtX7 = <IInternalDecoration>[];
        service.forEachDecorationAtCell(7, 6, null, foundAtX7.add);
        expect(foundAtX7.length, 1);

        final foundAtX8 = <IInternalDecoration>[];
        service.forEachDecorationAtCell(8, 5, null, foundAtX8.add);
        expect(foundAtX8.length, 0);
      });

      test('should find multi-line decoration when single-line decorations exist on other lines', () {
        final buffer = bufferService.buffer;
        (buffer as Buffer).fillViewportRows();

        for (var i = 0; i < buffer.lines.length; i++) {
          service.registerDecoration(
            IDecorationOptions(marker: buffer.addMarker(i), width: 5),
          );
        }
        final multiLine = service.registerDecoration(
          IDecorationOptions(
            marker: buffer.addMarker(10),
            width: 10,
            height: 3,
          ),
        );
        expect(multiLine, isNotNull);

        final found = <IInternalDecoration>[];
        service.forEachDecorationAtCell(0, 11, null, found.add);
        expect(found, contains(multiLine));
      });
    });

    group('getDecorationsAtCell', () {
      test('should find decoration with height > 1 on subsequent lines', () {
        final decoration = service.registerDecoration(
          IDecorationOptions(
            marker: bufferService.buffer.addMarker(5),
            width: 10,
            height: 3,
          ),
        );
        expect(decoration, isNotNull);

        expect(service.getDecorationsAtCell(0, 5).toList().length, 1);
        expect(service.getDecorationsAtCell(0, 6).toList().length, 1);
        expect(service.getDecorationsAtCell(0, 7).toList().length, 1);
        expect(service.getDecorationsAtCell(0, 8).toList().length, 0);
      });
    });

    group('DecorationLineCache', () {
      test('should return undefined for lines with no indexed decorations', () {
        final cache = DecorationLineCache();
        expect(cache.getDecorationsOnLine(0), isNull);
      });
    });

    group('line index maintenance', () {
      test('should keep lookups correct after buffer trim', () {
        final buffer = bufferService.buffer;
        (buffer as Buffer).fillViewportRows();

        final marker = buffer.addMarker(buffer.lines.length - 1);
        final decoration = service.registerDecoration(
          IDecorationOptions(marker: marker, width: 10),
        );
        expect(decoration, isNotNull);

        buffer.lines.onTrimEmitter.fire(1);

        final found = <IInternalDecoration>[];
        service.forEachDecorationAtCell(0, marker.line, null, found.add);
        expect(found.length, 1);
      });

      test('should remove decoration from line index when marker is trimmed off buffer', () {
        final buffer = bufferService.buffer;
        (buffer as Buffer).fillViewportRows();

        final marker = buffer.addMarker(0);
        final decoration = service.registerDecoration(
          IDecorationOptions(marker: marker, width: 10),
        );
        expect(decoration, isNotNull);

        buffer.lines.onTrimEmitter.fire(1);
        expect(marker.isDisposed, isTrue);
        expect(decoration!.isDisposed, isTrue);

        final found = <IInternalDecoration>[];
        service.forEachDecorationAtCell(0, 0, null, found.add);
        expect(found.length, 0);
      });

      test(
        'should keep multi-line decoration indexed after line insert',
        () async {
          final buffer = bufferService.buffer;
          (buffer as Buffer).fillViewportRows();

          final marker = buffer.addMarker(3);
          final decoration = service.registerDecoration(
            IDecorationOptions(marker: marker, width: 10, height: 3),
          );
          expect(decoration, isNotNull);

          buffer.lines.splice(5, 0, [buffer.getBlankLine(defaultAttrData)]);
          // Upstream: `await new Promise(resolve => queueMicrotask(resolve))`.
          await Future<void>.microtask(() {});

          final foundOnSpan = <IInternalDecoration>[];
          for (var line = marker.line; line < marker.line + 3; line++) {
            service.forEachDecorationAtCell(0, line, null, foundOnSpan.add);
          }
          expect(foundOnSpan, contains(decoration));

          final foundOutsideSpan = <IInternalDecoration>[];
          service.forEachDecorationAtCell(
            0,
            marker.line + 3,
            null,
            foundOutsideSpan.add,
          );
          expect(foundOutsideSpan.length, 0);
        },
      );
    });
  });
}
