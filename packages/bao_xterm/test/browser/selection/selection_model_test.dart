// Copyright (c) 2017 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/LICENSE.txt.
// Adapted from xterm.js src/browser/selection/SelectionModel.test.ts
// (c58ea36).

import 'package:flutter_test/flutter_test.dart';
import 'package:bao_xterm/browser/selection/selection_model.dart';

import 'package:bao_xterm/testing/test_utils.dart';

void main() {
  group('SelectionModel', () {
    late SelectionModel model;

    setUp(() {
      final bufferService = MockBufferService(80, 2);
      model = SelectionModel(bufferService);
    });

    group('clearSelection', () {
      test('should clear the final selection', () {
        model.selectionStart = [0, 0];
        model.selectionEnd = [10, 2];
        expect(model.finalSelectionStart, equals([0, 0]));
        expect(model.finalSelectionEnd, equals([10, 2]));
        model.clearSelection();
        expect(model.finalSelectionStart, isNull);
        expect(model.finalSelectionEnd, isNull);
      });
    });

    group('areSelectionValuesReversed', () {
      test(
        'should return true when the selection end is before selection start',
        () {
          model.selectionStart = [1, 0];
          model.selectionEnd = [0, 0];
          expect(model.areSelectionValuesReversed(), true);
          model.selectionStart = [10, 2];
          model.selectionEnd = [0, 0];
          expect(model.areSelectionValuesReversed(), true);
        },
      );
      test(
        'should return false when the selection end is after selection start',
        () {
          model.selectionStart = [0, 0];
          model.selectionEnd = [1, 0];
          expect(model.areSelectionValuesReversed(), false);
          model.selectionStart = [0, 0];
          model.selectionEnd = [10, 2];
          expect(model.areSelectionValuesReversed(), false);
        },
      );
    });

    group('onTrim', () {
      test(
        'should trim a portion of the selection when a part of it is trimmed',
        () {
          model.selectionStart = [0, 0];
          model.selectionEnd = [10, 2];
          model.handleTrim(1);
          expect(model.finalSelectionStart, equals([0, 0]));
          expect(model.finalSelectionEnd, equals([10, 1]));
          model.handleTrim(1);
          expect(model.finalSelectionStart, equals([0, 0]));
          expect(model.finalSelectionEnd, equals([10, 0]));
        },
      );
      test('should clear selection when it is trimmed in its entirety', () {
        model.selectionStart = [0, 0];
        model.selectionEnd = [10, 0];
        model.handleTrim(1);
        expect(model.finalSelectionStart, isNull);
        expect(model.finalSelectionEnd, isNull);
      });
      test(
        'should reset selection start to origin when start row is trimmed',
        () {
          model.selectionStart = [50, 0];
          model.selectionEnd = [10, 2];
          expect(model.handleTrim(1), true);
          expect(model.finalSelectionStart, equals([0, 0]));
          expect(model.finalSelectionEnd, equals([10, 1]));
        },
      );
    });

    group('finalSelectionStart', () {
      test('should return the start of the buffer if select all is active', () {
        model.isSelectAllActive = true;
        expect(model.finalSelectionStart, equals([0, 0]));
      });
      test('should return selection start if there is no selection end', () {
        model.selectionStart = [2, 2];
        expect(model.finalSelectionStart, equals([2, 2]));
      });
      test('should return selection end if values are reversed', () {
        model.selectionStart = [2, 2];
        model.selectionEnd = [3, 2];
        expect(model.finalSelectionStart, equals([2, 2]));
        model.selectionEnd = [1, 2];
        expect(model.finalSelectionStart, equals([1, 2]));
      });
    });

    group('finalSelectionEnd', () {
      test('should return the end of the buffer if select all is active', () {
        model.isSelectAllActive = true;
        expect(model.finalSelectionEnd, equals([80, 1]));
      });
      test('should return null if there is no selection start', () {
        expect(model.finalSelectionEnd, isNull);
        model.selectionEnd = [1, 2];
        expect(model.finalSelectionEnd, isNull);
      });
      test(
        'should return selection start + length if there is no selection end',
        () {
          model.selectionStart = [2, 2];
          model.selectionStartLength = 2;
          expect(model.finalSelectionEnd, equals([4, 2]));
        },
      );
      test('should return selection start + length if values are reversed', () {
        model.selectionStart = [2, 2];
        model.selectionStartLength = 2;
        model.selectionEnd = [2, 1];
        expect(model.finalSelectionEnd, equals([4, 2]));
      });
      test('should return selection start + length if selection end is inside '
          'the start selection', () {
        model.selectionStart = [2, 2];
        model.selectionStartLength = 2;
        model.selectionEnd = [3, 2];
        expect(model.finalSelectionEnd, equals([4, 2]));
      });
      test('should return the end on a different row when start + length '
          'overflows onto a following row', () {
        model.selectionStart = [78, 2];
        model.selectionStartLength = 4;
        expect(model.finalSelectionEnd, equals([2, 3]));
      });
      test('should return the end on a different row when start + length '
          'overflows onto a following row with selectionEnd inbetween', () {
        model.selectionStart = [78, 2];
        model.selectionEnd = [79, 2];
        model.selectionStartLength = 4;
        expect(model.finalSelectionEnd, equals([2, 3]));
      });
      test('should return selection end if selection end is after selection '
          'start + length', () {
        model.selectionStart = [2, 2];
        model.selectionStartLength = 2;
        model.selectionEnd = [5, 2];
        expect(model.finalSelectionEnd, equals([5, 2]));
      });
      test(
        'should not include a trailing EOL when the selection ends at the end '
        'of a line',
        () {
          model.selectionStart = [0, 0];
          model.selectionStartLength = 80;
          expect(model.finalSelectionEnd, equals([80, 0]));
          model.selectionStart = [0, 0];
          model.selectionStartLength = 160;
          expect(model.finalSelectionEnd, equals([80, 1]));
        },
      );
    });
  });
}
