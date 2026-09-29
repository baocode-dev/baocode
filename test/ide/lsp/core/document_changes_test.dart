import 'dart:math';

import 'package:flutter/services.dart' show TextSelection;
import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/editor/monaco/flutter/editor_document_model.dart';
import 'package:monad/ide/editor/monaco/vs/editor/common/core/range.dart';

import 'lsp_text.dart';

/// The model's change events, applied as a language server would, give
/// back its text: through CRLF pairs, lone CRs, surrogate pairs, batches,
/// undo and redo.
void main() {
  const pieces = [
    'a',
    'b',
    'xyz',
    '\r',
    '\n',
    '\r\n',
    '😀',
    '\u{1F600}\u{1F601}',
    ' ',
    'é',
    '\t',
    '\uD83D',
    '\uDE00',
    '',
  ];

  String randomText(Random random, int length) =>
      [for (var i = 0; i < length; i++) pieces[random.nextInt(pieces.length)]]
          .join();

  /// Follows [model]'s events like a server, checking every version.
  (List<EditorContentChangeEvent>, String Function()) follow(
    EditorDocumentModel model,
  ) {
    var mirror = model.text;
    final events = <EditorContentChangeEvent>[];
    model.changes.listen((event) {
      events.add(event);
      mirror = applyLspChanges(mirror, event.changes);
      expect(mirror, event.text, reason: 'after ${event.changes}');
      expect(event.text, model.text);
      expect(event.version, model.version);
    });
    return (events, () => mirror);
  }

  test('a single edit splitting a CRLF widens over the pair', () {
    final model = EditorDocumentModel('a\r\nb');
    final (events, mirror) = follow(model);
    model.applyOffsetEdits([const EditorOffsetEdit(2, 2, 'x')]);
    expect(model.text, 'a\rx\nb');
    expect(mirror(), model.text);
    final change = events.single.changes.single;
    expect(
      (change.startLine, change.startCharacter),
      (0, 1),
      reason: 'from the CR',
    );
    expect((change.endLine, change.endCharacter), (1, 0));
    expect(change.text, '\rx\n');
  });

  test('adjacent edits around a CRLF apply in order', () {
    final model = EditorDocumentModel('ab\r\ncd\re\nf');
    follow(model);
    model.applyOffsetEdits([
      const EditorOffsetEdit(1, 3, 'Q'),
      const EditorOffsetEdit(3, 4, '\r'),
      const EditorOffsetEdit(4, 4, '\n'),
      const EditorOffsetEdit(6, 7, ''),
    ]);
    expect(model.text, 'aQ\r\ncde\nf');
  });

  test('undo, redo and replaceText report their changes', () {
    final model = EditorDocumentModel('one\r\ntwo\nthree');
    final (events, mirror) = follow(model);
    model.applyEdits([
      EditorDocumentEdit(Range(1, 4, 2, 1), '\n'),
      EditorDocumentEdit(Range(3, 1, 3, 6), '3'),
    ]);
    model.applyOffsetEdits([const EditorOffsetEdit(0, 0, 'x')], coalesce: true);
    model.applyOffsetEdits([const EditorOffsetEdit(1, 1, 'y')], coalesce: true);
    expect(model.undo(), isTrue);
    expect(model.text, 'one\r\ntwo\nthree');
    expect(model.redo(), isTrue);
    model.replaceText('fresh\r');
    expect(mirror(), 'fresh\r');
    expect(events, hasLength(6));
  });

  test('no listener, no work; no change, no event', () {
    final model = EditorDocumentModel('abc');
    model.applyOffsetEdits([const EditorOffsetEdit(0, 1, 'z')]);
    final (events, _) = follow(model);
    model.applyOffsetEdits([const EditorOffsetEdit(0, 1, 'z')]);
    model.replaceText('zbc');
    expect(events, isEmpty);
  });

  test('randomized edits, undo and redo stay in sync', () {
    for (var seed = 0; seed < 150; seed++) {
      final random = Random(seed);
      final model = EditorDocumentModel(randomText(random, 30));
      final (events, mirror) = follow(model);
      for (var step = 0; step < 40; step++) {
        final roll = random.nextInt(10);
        if (roll == 0) {
          model.undo();
        } else if (roll == 1) {
          model.redo();
        } else if (roll == 2) {
          final text = model.text;
          final start = random.nextInt(text.length + 1);
          model.replaceText(
            text.replaceRange(
              start,
              start + random.nextInt(text.length - start + 1),
              randomText(random, 3),
            ),
          );
        } else {
          final length = model.text.length;
          final cuts = {
            for (var i = random.nextInt(8); i >= 0; i--)
              random.nextInt(length + 1),
          }.toList()..sort();
          final edits = <EditorOffsetEdit>[];
          for (var i = 0; i + 1 < cuts.length; i += 2) {
            edits.add(
              EditorOffsetEdit(cuts[i], cuts[i + 1], randomText(random, 2)),
            );
          }
          if (cuts.length.isOdd) {
            edits.add(
              EditorOffsetEdit(cuts.last, cuts.last, randomText(random, 2)),
            );
          }
          model.applyOffsetEdits(
            edits,
            coalesce: random.nextBool(),
            selectionsAfter: const [TextSelection.collapsed(offset: 0)],
          );
        }
        expect(mirror(), model.text, reason: 'seed $seed step $step');
      }
      expect(events, isNotEmpty);
    }
  });
}
