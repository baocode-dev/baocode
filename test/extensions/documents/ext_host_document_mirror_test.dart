import 'dart:convert';
import 'dart:math';

import 'package:bao_editor/monaco/flutter/editor_document_model.dart';
import 'package:bao_editor/monaco/vs/editor/common/core/position.dart';
import 'package:bao_editor/monaco/vs/editor/common/core/range.dart';
import 'package:bao_exthost/bao_exthost.dart' show VsUri;
import 'package:baocode/extensions/documents/end_of_line.dart';
import 'package:baocode/extensions/documents/ext_host_document_mirror.dart';
import 'package:baocode/extensions/documents/mirror_text_model.dart';
import 'package:baocode/extensions/documents/model_changed_event.dart';
import 'package:flutter_test/flutter_test.dart';

final _uri = VsUri.file('/w/a.ts');

ExtHostDocumentMirror _mirror(String text, {String defaultEol = '\n'}) =>
    ExtHostDocumentMirror(
      uri: _uri,
      languageId: 'typescript',
      text: text,
      defaultEol: defaultEol,
    );

/// What the model must read for [raw] with model EOL [eol].
String _normalized(String raw, String eol) => normalizeEol(
  raw.startsWith(utf8BomCharacter) ? raw.substring(1) : raw,
  eol,
);

String _show(String s) => jsonEncode(s);

(int, int) _p(IPosition p) => (p.lineNumber, p.column);

(int, int, int, int) _r(IRange r) =>
    (r.startLineNumber, r.startColumn, r.endLineNumber, r.endColumn);

/// Applies [event]'s changes one at a time to [tracker], checking each
/// change's offset and length against the text it applies to.
void _applyChecked(MirrorTextModel tracker, ModelChangedEvent event) {
  for (final change in event.changes) {
    final start = tracker.offsetAt(change.range.getStartPosition());
    final end = tracker.offsetAt(change.range.getEndPosition());
    expect(change.rangeOffset, start, reason: '$change');
    expect(change.rangeLength, end - start, reason: '$change');
    expect(
      _p(tracker.positionAt(start)),
      _p(change.range.getStartPosition()),
      reason: 'range start is a valid position: $change',
    );
    tracker.onEvents(
      ModelChangedEvent(
        changes: [change],
        eol: event.eol,
        versionId: event.versionId,
      ),
    );
  }
}

MirrorTextModel _tracker(ExtHostDocumentMirror mirror) {
  final added = mirror.toModelAddedData();
  return MirrorTextModel(mirror.uri, added.lines, added.eol, added.versionId);
}

void main() {
  group('EOL choice (createTextBufferFactory)', () {
    test('no breaks take the default', () {
      expect(_mirror('').eol, '\n');
      expect(_mirror('abc', defaultEol: '\r\n').eol, '\r\n');
    });

    test('CRLF and lone CR more than half: CRLF; otherwise LF', () {
      expect(_mirror('a\nb').eol, '\n');
      expect(_mirror('a\r\nb').eol, '\r\n');
      expect(_mirror('a\rb').eol, '\r\n');
      expect(_mirror('a\r\nb\nc').eol, '\n'); // tie
      expect(_mirror('a\r\nb\r\nc\nd').eol, '\r\n');
      expect(_mirror('a\rb\nc\nd', defaultEol: '\r\n').eol, '\n');
    });

    test('the dominant raw break is what BaoCode inserts', () {
      expect(_mirror('a\rb\rc').rawInsertEol, '\r');
      expect(_mirror('a\rb\rc').eol, '\r\n');
      expect(_mirror('a\r\nb\nc').rawInsertEol, '\n');
      expect(_mirror('a\r\nb\nc', defaultEol: '\r\n').rawInsertEol, '\n');
      expect(_mirror('x').rawInsertEol, '\n');
    });
  });

  group('model view', () {
    test('BOM is not part of the model; line 1 columns shift', () {
      final mirror = _mirror('﻿ab\r\ncd\r\n');
      expect(mirror.hasBom, isTrue);
      expect(mirror.modelLines, ['ab', 'cd', '']);
      expect(mirror.eol, '\r\n');
      expect(mirror.modelText, 'ab\r\ncd\r\n');
      expect(_p(mirror.toModelPosition(const Position(1, 2))), (1, 1));
      expect(_p(mirror.toModelPosition(const Position(1, 1))), (1, 1));
      expect(_p(mirror.toEditorPosition(const Position(1, 3))), (1, 4));
      expect(_p(mirror.toEditorPosition(const Position(2, 3))), (2, 3));
      expect(mirror.getLineContent(1), 'ab');
    });

    test('raw and model offsets map both ways', () {
      final mirror = _mirror('﻿a\r\nb\rc\nd');
      expect(mirror.eol, '\r\n');
      expect(mirror.modelText, 'a\r\nb\r\nc\r\nd');
      expect(mirror.toModelOffset(1), 0); // after the BOM
      expect(mirror.toModelOffset(4), 3); // start of b
      expect(mirror.toModelOffset(6), 6); // start of c
      expect(mirror.toModelOffset(8), 9); // start of d
      expect(mirror.toRawOffset(9), 8);
      expect(mirror.toRawOffset(3), 4);
      // Between the CR and LF of a pair: the end of that line.
      expect(_p(mirror.editorPositionAt(3)), (1, 3));
      expect(_p(mirror.modelPositionAt(4)), (2, 2));
    });

    test('IModelAddedData', () {
      final mirror = _mirror('a\nb');
      expect(mirror.toModelAddedData(isDirty: true).toJson(), {
        'uri': _uri.toJson(),
        'versionId': 1,
        'lines': ['a', 'b'],
        'EOL': '\n',
        'languageId': 'typescript',
        'isDirty': true,
        'encoding': 'utf8',
      });
    });

    test('documents over 50 MB are not synchronized', () {
      expect(modelSyncLimit, 50 * 1024 * 1024);
      expect(isModelTooLargeForSyncing(modelSyncLimit), isFalse);
      expect(isModelTooLargeForSyncing(modelSyncLimit + 1), isTrue);
      final big = _mirror('a' * (modelSyncLimit + 1));
      expect(big.isTooLargeForSyncing, isTrue);
      expect(big.isSynchronized, isFalse);
      // The BOM does not count.
      final edge = _mirror('﻿${'a' * modelSyncLimit}');
      expect(edge.isTooLargeForSyncing, isFalse);
    });
  });

  group('raw edits to model changes', () {
    late EditorDocumentModel editor;
    late ExtHostDocumentMirror mirror;
    late List<ModelChangedEvent?> events;

    void open(String text) {
      editor = EditorDocumentModel(text);
      mirror = _mirror(text);
      events = [];
      editor.changes.listen((e) => events.add(mirror.acceptEditorEvent(e)));
    }

    tearDown(() => editor.dispose());

    test('typing at the end of an LF line is one insertion', () {
      open('ab\ncd');
      editor.applyOffsetEdits([const EditorOffsetEdit(2, 2, 'x')]);
      final change = events.single!.changes.single;
      expect(_r(change.range), (1, 3, 1, 3));
      expect(change.rangeOffset, 2);
      expect(change.rangeLength, 0);
      expect(change.text, 'x');
      expect(events.single!.versionId, 2);
    });

    test('typing after a lone CR is one insertion', () {
      open('ab\rcd\r');
      editor.applyOffsetEdits([const EditorOffsetEdit(3, 3, 'x')]);
      final change = events.single!.changes.single;
      expect(_r(change.range), (2, 1, 2, 1));
      expect(change.rangeOffset, 4); // model: ab\r\ncd
      expect(change.text, 'x');
    });

    test('an LF after a lone CR pairs with it: nothing changes', () {
      open('ab\rcd');
      editor.applyOffsetEdits([const EditorOffsetEdit(3, 3, '\n')]);
      expect(events.single, isNull);
      expect(mirror.versionId, 1);
      expect(mirror.modelText, 'ab\r\ncd');
    });

    test('an LF after a lone CR followed by text adds only the text', () {
      open('a\rb');
      editor.applyOffsetEdits([const EditorOffsetEdit(2, 2, '\nX')]);
      final change = events.single!.changes.single;
      expect(_r(change.range), (2, 1, 2, 1));
      expect(change.text, 'X');
      expect(mirror.modelText, 'a\r\nXb');
    });

    test('deleting between a lone CR and a lone LF joins two breaks', () {
      open('a\rx\nb\nc');
      expect(mirror.eol, '\n');
      editor.applyOffsetEdits([const EditorOffsetEdit(2, 3, '')]);
      expect(mirror.modelText, 'a\nb\nc');
      final change = events.single!.changes.single;
      expect(_r(change.range), (2, 1, 3, 1));
      expect(change.rangeLength, 2);
      expect(change.text, '');
    });

    test('touching the BOM changes nothing', () {
      open('﻿ab');
      editor.applyOffsetEdits([const EditorOffsetEdit(0, 1, '')]);
      expect(events.single, isNull);
      editor.applyOffsetEdits([const EditorOffsetEdit(0, 0, '﻿')]);
      expect(events.last, isNull);
      expect(mirror.modelText, 'ab');
    });

    test('inserting before the BOM makes it text', () {
      open('﻿ab');
      editor.applyOffsetEdits([const EditorOffsetEdit(0, 0, 'x')]);
      final change = events.single!.changes.single;
      expect(_r(change.range), (1, 1, 1, 1));
      expect(change.text, 'x﻿');
      expect(mirror.modelText, 'x﻿ab');
    });

    test('undo and redo flags pass through', () {
      open('a');
      editor.applyOffsetEdits([const EditorOffsetEdit(1, 1, 'b')]);
      final undo = mirror.acceptRawChanges(const [
        RawContentChange(
          startLine: 0,
          startCharacter: 1,
          endLine: 0,
          endCharacter: 2,
          text: '',
        ),
      ], isUndoing: true);
      expect(undo!.isUndoing, isTrue);
      expect(undo.toJson()['isUndoing'], isTrue);
    });

    test('reset is a flush and chooses the EOL again', () {
      open('a\nb');
      final event = mirror.reset('x\r\ny\r\n');
      expect(event.isFlush, isTrue);
      expect(event.eol, '\r\n');
      expect(_r(event.changes.single.range), (1, 1, 2, 2));
      expect(event.changes.single.rangeLength, 3);
      final tracker = MirrorTextModel(_uri, ['a', 'b'], '\n', 1)
        ..onEvents(event);
      expect(tracker.getText(), 'x\r\ny\r\n');
      expect(mirror.versionId, 2);
    });

    test('setEol is an EOL change; the raw edits come back as no-ops', () {
      open('a\nb\r\nc\rd');
      final tracker = _tracker(mirror);
      expect(mirror.eol, '\r\n');
      expect(mirror.setEol('\r\n'), isNull);
      final event = mirror.setEol('\n')!;
      expect(event.isEolChange, isTrue);
      tracker.onEvents(event);
      expect(tracker.getText(), 'a\nb\nc\nd');
      editor.applyEdits(mirror.rawEditsForEol('\n'));
      expect(editor.text, 'a\nb\nc\nd');
      expect(events, isNotEmpty);
      expect(events, everyElement(isNull));
      expect(mirror.modelText, 'a\nb\nc\nd');
    });

    test('event JSON', () {
      open('ab');
      editor.applyOffsetEdits([const EditorOffsetEdit(1, 2, 'Z')]);
      final json = events.single!.toJson();
      expect(json, {
        'changes': [
          {
            'range': {
              'startLineNumber': 1,
              'startColumn': 2,
              'endLineNumber': 1,
              'endColumn': 3,
            },
            'rangeOffset': 1,
            'rangeLength': 1,
            'text': 'Z',
          },
        ],
        'eol': '\n',
        'versionId': 2,
        'isUndoing': false,
        'isRedoing': false,
        'isFlush': false,
        'isEolChange': false,
      });
      final back = ModelChangedEvent.fromJson(
        (jsonDecode(jsonEncode(json)) as Map).cast(),
      );
      expect(_r(back.changes.single.range), (1, 2, 1, 3));
    });
  });

  group('model edits to raw edits', () {
    String roundTrip(String raw, List<ModelTextEdit> edits) {
      final editor = EditorDocumentModel(raw);
      final mirror = _mirror(raw);
      editor.changes.listen(mirror.acceptEditorEvent);
      editor.applyEdits(mirror.toEditorEdits(edits));
      expect(mirror.rawText, editor.text);
      final text = editor.text;
      editor.dispose();
      return text;
    }

    test('inserted breaks take the dominant raw kind', () {
      expect(
        roundTrip('a\r\nb', [ModelTextEdit(Range(1, 2, 1, 2), 'x\ny')]),
        'ax\r\ny\r\nb',
      );
      expect(
        roundTrip('a\rb\rc', [ModelTextEdit(Range(2, 2, 2, 2), '\n')]),
        'a\rb\r\rc',
      );
      expect(
        roundTrip('a\nb\r\nc\nd', [ModelTextEdit(Range(1, 2, 1, 2), '\r\n')]),
        'a\n\nb\r\nc\nd',
      );
    });

    test('untouched breaks keep their kind', () {
      expect(
        roundTrip('a\r\nb\nc\rd', [ModelTextEdit(Range(2, 1, 2, 2), 'B')]),
        'a\r\nB\nc\rd',
      );
      expect(
        roundTrip('a\r\nb\nc\rd', [ModelTextEdit(Range(1, 2, 3, 1), '')]),
        'ac\rd',
      );
    });

    test('BOM stays in front', () {
      expect(roundTrip('﻿ab', [ModelTextEdit(Range(1, 1, 1, 1), 'x')]), '﻿xab');
      expect(roundTrip('﻿ab', [ModelTextEdit(Range(1, 1, 1, 3), '')]), '﻿');
    });

    test('a CR and an LF never merge at a seam', () {
      // LF inserted right after a lone CR.
      expect(
        roundTrip('a\rb\nc\nd', [ModelTextEdit(Range(2, 1, 2, 1), '\nx')]),
        'a\r\r\nxb\nc\nd',
      );
      // CR inserted right before a lone LF.
      expect(
        roundTrip('a\rb\rc\nd', [ModelTextEdit(Range(3, 2, 3, 2), '\n')]),
        'a\rb\rc\r\n\nd',
      );
      // Deleting all between a lone CR and a lone LF.
      expect(
        roundTrip('a\rx\nb\nc', [ModelTextEdit(Range(2, 1, 2, 2), '')]),
        'a\r\n\nb\nc',
      );
    });

    test('same-position inserts keep their order', () {
      expect(
        roundTrip('ab', [
          ModelTextEdit(Range(1, 2, 1, 2), '1'),
          ModelTextEdit(Range(1, 2, 1, 2), '2'),
          ModelTextEdit(Range(1, 1, 1, 2), 'A'),
        ]),
        'A12b',
      );
    });

    test('overlapping edits throw', () {
      final mirror = _mirror('abcdef');
      expect(
        () => mirror.toEditorEdits([
          ModelTextEdit(Range(1, 1, 1, 4), ''),
          ModelTextEdit(Range(1, 3, 1, 5), ''),
        ]),
        throwsArgumentError,
      );
    });

    test('ranges inside a surrogate pair widen like TextModel', () {
      final mirror = _mirror('a😀b');
      expect(_r(mirror.validateModelRange(Range(1, 3, 1, 3))), (1, 2, 1, 2));
      expect(_r(mirror.validateModelRange(Range(1, 3, 1, 5))), (1, 2, 1, 5));
      expect(_r(mirror.validateModelRange(Range(1, 1, 1, 3))), (1, 1, 1, 4));
      expect(_r(mirror.validateModelRange(Range(0, 0, 9, 9))), (1, 1, 1, 5));
    });
  });

  group('randomized', () {
    const pieces = [
      'a',
      'b',
      'xy',
      ' ',
      'é',
      '😀',
      '\r',
      '\n',
      '\r\n',
      '\r\n',
      '\n\r',
      '',
    ];

    String randomText(Random random, int maxPieces, {bool bom = false}) {
      final buffer = StringBuffer();
      if (bom && random.nextInt(4) == 0) buffer.write(utf8BomCharacter);
      final count = random.nextInt(maxPieces + 1);
      for (var i = 0; i < count; i++) {
        buffer.write(pieces[random.nextInt(pieces.length)]);
      }
      return buffer.toString();
    }

    test('raw edits: the model and every mirror read the normalized text', () {
      var events = 0;
      var silent = 0;
      for (var seed = 0; seed < 600; seed++) {
        final random = Random(seed);
        final initial = randomText(random, 20, bom: true);
        final editor = EditorDocumentModel(initial);
        final mirror = _mirror(
          initial,
          defaultEol: random.nextBool() ? '\n' : '\r\n',
        );
        final eol = mirror.eol;
        final tracker = _tracker(mirror);
        var version = mirror.versionId;
        var undoing = false;
        var redoing = false;
        editor.changes.listen((e) {
          final event = mirror.acceptEditorEvent(
            e,
            isUndoing: undoing,
            isRedoing: redoing,
          );
          if (event == null) {
            silent++;
            return;
          }
          events++;
          expect(event.versionId, greaterThan(version));
          version = event.versionId;
          expect(event.eol, eol);
          expect(event.isUndoing, undoing);
          expect(event.isRedoing, redoing);
          _applyChecked(tracker, event);
        });
        for (var step = 0; step < 25; step++) {
          final before = editor.text;
          final kind = random.nextInt(10);
          undoing = kind == 7;
          redoing = kind == 8;
          if (kind == 7) {
            editor.undo();
          } else if (kind == 8) {
            editor.redo();
          } else if (kind == 9) {
            final length = editor.text.length;
            final start = random.nextInt(length + 1);
            final end = start + random.nextInt(length - start + 1);
            editor.replaceText(
              editor.text.substring(0, start) +
                  randomText(random, 4, bom: true) +
                  editor.text.substring(end),
            );
          } else {
            final length = editor.text.length;
            final count = 2 * (1 + random.nextInt(3));
            final offsets = [
              for (var i = 0; i < count; i++) random.nextInt(length + 1),
            ]..sort();
            editor.applyOffsetEdits([
              for (var i = 0; i < offsets.length; i += 2)
                EditorOffsetEdit(
                  offsets[i],
                  offsets[i + 1],
                  randomText(random, 3, bom: true),
                ),
            ]);
          }
          final reason =
              'seed $seed step $step: ${_show(before)} -> ${_show(editor.text)}';
          expect(mirror.rawText, editor.text, reason: reason);
          expect(mirror.eol, eol, reason: reason);
          final expected = _normalized(editor.text, eol);
          expect(mirror.modelText, expected, reason: reason);
          expect(tracker.getText(), expected, reason: reason);
          expect(tracker.version, mirror.versionId, reason: reason);
        }
        editor.dispose();
      }
      // The generator exercises both outcomes.
      expect(events, greaterThan(5000));
      expect(silent, greaterThan(100));
    });

    test('model edits: round trips read as the extension asked', () {
      var seams = 0;
      var exact = 0;
      for (var seed = 0; seed < 1500; seed++) {
        final random = Random(1000 + seed);
        final raw = randomText(random, 16, bom: true);
        final editor = EditorDocumentModel(raw);
        final mirror = _mirror(raw);
        final tracker = _tracker(mirror);
        editor.changes.listen((e) {
          final event = mirror.acceptEditorEvent(e);
          if (event != null) _applyChecked(tracker, event);
        });
        for (var step = 0; step < 4; step++) {
          final model = mirror.modelText;
          final eol = mirror.eol;
          // Random non-overlapping edits at valid positions (never inside
          // a surrogate pair), in random order.
          final count = 2 * (1 + random.nextInt(3));
          final offsets = [
            for (var i = 0; i < count; i++) random.nextInt(model.length + 1),
          ]..sort();
          final edits = <ModelTextEdit>[];
          for (var i = 0; i < offsets.length; i += 2) {
            Position at(int offset) {
              var position = mirror.modelPositionAt(offset);
              final line = mirror.getLineContent(position.lineNumber);
              final column = position.column;
              if (column > 1) {
                final code = line.codeUnitAt(column - 2);
                if (code >= 0xD800 && code <= 0xDBFF) {
                  position = Position(position.lineNumber, column - 1);
                }
              }
              return position;
            }

            final text = randomText(random, 3);
            edits.add(
              ModelTextEdit(
                Range.fromPositions(at(offsets[i]), at(offsets[i + 1])),
                text.isEmpty && random.nextBool() ? null : text,
              ),
            );
          }
          edits.shuffle(random);

          // What VS Code's model would read.
          final indexed = [
            for (var i = 0; i < edits.length; i++)
              (
                start: mirror.modelOffsetAt(edits[i].range.startPosition),
                end: mirror.modelOffsetAt(edits[i].range.endPosition),
                text: normalizeEol(edits[i].text ?? '', eol),
                index: i,
              ),
          ];
          indexed.sort((a, b) {
            final start = a.start.compareTo(b.start);
            if (start != 0) return start;
            final end = a.end.compareTo(b.end);
            return end != 0 ? end : a.index.compareTo(b.index);
          });
          var expected = model;
          for (final edit in indexed.reversed) {
            expected = expected.replaceRange(edit.start, edit.end, edit.text);
          }

          // What writing the edits naively into the raw text gives.
          final insertEol = mirror.rawInsertEol;
          var naive = editor.text;
          for (final edit in indexed.reversed) {
            final original = edits[edit.index];
            naive = naive.replaceRange(
              mirror.rawOffsetAt(
                mirror.toEditorPosition(original.range.startPosition),
              ),
              mirror.rawOffsetAt(
                mirror.toEditorPosition(original.range.endPosition),
              ),
              normalizeEol(original.text ?? '', insertEol),
            );
          }

          final before = editor.text;
          editor.applyEdits(mirror.toEditorEdits(edits));
          final reason =
              'seed $seed step $step: ${_show(before)} '
              '${[for (final e in edits) '${e.range} ${_show(e.text ?? '')}']}';
          expect(mirror.modelText, expected, reason: reason);
          expect(tracker.getText(), expected, reason: reason);
          expect(_normalized(editor.text, eol), expected, reason: reason);
          if (_normalized(naive, eol) == expected) {
            exact++;
            expect(editor.text, naive, reason: reason);
          } else {
            seams++;
          }
        }
        editor.dispose();
      }
      expect(exact, greaterThan(4000));
      expect(seams, greaterThan(20));
    });
  });
}

extension on IRange {
  Position get startPosition => Range.startPositionOf(this);
  Position get endPosition => Range.endPositionOf(this);
}
