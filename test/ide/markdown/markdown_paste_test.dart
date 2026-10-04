import 'dart:typed_data';

import 'package:bao_editor/monaco/flutter/editor_document_model.dart';
import 'package:bao_editor/monaco/flutter/editor_surface_controller.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/composer/composer_files.dart';
import 'package:baocode/ide/file_service.dart';
import 'package:baocode/ide/markdown/markdown_paste.dart';
import 'package:baocode/l10n/l10n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../workbench/fake_files.dart';

class FakeClipboard implements MarkdownClipboard {
  FakeClipboard({
    this.copied = const [],
    this.pictures = const [],
    this.text = false,
  });

  List<ComposerFile> copied;
  List<ImageAttachment> pictures;
  bool text;

  @override
  Future<List<ComposerFile>> files() async => copied;

  @override
  Future<List<ImageAttachment>> images() async => pictures;

  @override
  Future<bool> hasText() async => text;
}

/// [TreeFiles] whose writes may fail, or find a name taken as they write
/// (another app made the file meanwhile).
class RacingFiles extends TreeFiles {
  RacingFiles(super.contents);

  final Set<String> takenOnWrite = {};
  Object? failure;

  @override
  Future<void> writeBytes(String path, Uint8List bytes) async {
    if (failure case final error?) throw error;
    if (takenOnWrite.remove(path)) {
      contents[path] = 'theirs';
      throw IdeFileExistsException(path);
    }
    return super.writeBytes(path, bytes);
  }

  @override
  Future<void> copy(String from, String to) async {
    if (failure case final error?) throw error;
    return super.copy(from, to);
  }
}

final _picture = ImageAttachment(
  bytes: Uint8List.fromList([137, 80, 78, 71]),
  mediaType: 'image/png',
);

const _doc = '/project/docs/guide.md';

void main() {
  late RacingFiles files;
  late FakeClipboard clipboard;
  late List<String> reports;
  late List<String> asked;
  var confirm = false;

  MarkdownPaste paste({bool remote = false}) => MarkdownPaste(
    files: files,
    l10n: englishLocalizations,
    root: '/project',
    context: p.posix,
    remote: remote,
    clipboard: clipboard,
    readLocal: (path) async => Uint8List.fromList(path.codeUnits),
    sizeOf: (path) async => path.contains('huge') ? 60 * 1024 * 1024 : 10,
    confirmLarge: (name, size) async {
      asked.add(name);
      return confirm;
    },
    report: reports.add,
  );

  String? links(MarkdownPasteOutcome outcome) => switch (outcome) {
    MarkdownPasteLinks(:final text) => text,
    _ => null,
  };

  setUp(() {
    files = RacingFiles({
      '/project/docs/guide.md': '# Guide',
      '/project/docs/image.png': 'x',
      '/project/lib/a.dart': 'code',
      '/elsewhere/shot.png': 'png',
      '/elsewhere/notes (draft).pdf': 'pdf',
      '/elsewhere/huge.zip': 'zip',
    });
    clipboard = FakeClipboard();
    reports = [];
    asked = [];
    confirm = false;
  });

  group('what the clipboard holds', () {
    test('files come first, even with text and pictures', () async {
      clipboard
        ..copied = [const ComposerFile('/elsewhere/shot.png')]
        ..pictures = [_picture]
        ..text = true;
      expect(links(await paste().paste(_doc)), '![](shot.png)');
    });

    test('pictures, only without text', () async {
      clipboard.pictures = [_picture];
      expect(links(await paste().paste(_doc)), '![](image-1.png)');
      clipboard.text = true;
      expect(await paste().paste(_doc), isA<MarkdownPasteText>());
    });

    test('text, as usual', () async {
      clipboard.text = true;
      expect(await paste().paste(_doc), isA<MarkdownPasteText>());
      clipboard.text = false;
      expect(await paste().paste(_doc), isA<MarkdownPasteText>());
    });
  });

  test('files are copied beside the document under names not taken', () async {
    clipboard.copied = const [
      ComposerFile('/elsewhere/shot.png'),
      ComposerFile('/elsewhere/notes (draft).pdf'),
    ];
    expect(
      links(await paste().paste(_doc)),
      '![](shot.png)\n[notes (draft).pdf](<notes (draft).pdf>)',
    );
    expect(files.contents['/project/docs/shot.png'], 'png');
    // Again: the names are taken now.
    expect(
      links(await paste().paste(_doc)),
      '![](shot-1.png)\n[notes (draft)-1.pdf](<notes (draft)-1.pdf>)',
    );
    expect(files.contents['/project/docs/shot.png'], 'png');
  });

  test('a name found taken only as it is written is passed over', () async {
    clipboard.pictures = [
      _picture,
      ImageAttachment(
        bytes: Uint8List(2),
        mediaType: 'image/jpeg',
        name: 'Photo.HEIC',
      ),
    ];
    files.takenOnWrite.addAll([
      '/project/docs/image-1.png',
      '/project/docs/Photo.jpg',
    ]);
    expect(
      links(await paste().paste(_doc)),
      '![](image-2.png)\n![](Photo-1.jpg)',
    );
    expect(files.contents['/project/docs/image-1.png'], 'theirs');
    expect(files.bytes.keys, [
      '/project/docs/image-2.png',
      '/project/docs/Photo-1.jpg',
    ]);
  });

  test('the project\'s files are linked to, not copied', () async {
    clipboard.copied = const [
      ComposerFile('/project/lib/a.dart'),
      ComposerFile('/project/docs/image.png'),
    ];
    expect(
      links(await paste().paste(_doc)),
      '[a.dart](../lib/a.dart)\n![](image.png)',
    );
    expect(files.contents.keys, isNot(contains('/project/docs/a.dart')));
  });

  test('a remote project\'s are this machine\'s files, uploaded', () async {
    clipboard.copied = const [ComposerFile('/project/lib/a.dart')];
    expect(links(await paste(remote: true).paste(_doc)), '[a.dart](a.dart)');
    expect(
      files.bytes['/project/docs/a.dart'],
      '/project/lib/a.dart'.codeUnits,
    );
  });

  test('folders are not pasted; large files only when confirmed', () async {
    clipboard.copied = const [
      ComposerFile('/elsewhere/folder', directory: true),
      ComposerFile('/elsewhere/huge.zip'),
    ];
    expect(await paste().paste(_doc), isA<MarkdownPasteNothing>());
    expect(reports, ['Folders cannot be pasted into a document: folder']);
    expect(asked, ['huge.zip']);
    confirm = true;
    expect(links(await paste().paste(_doc)), '[huge.zip](huge.zip)');
  });

  test('a write that fails is said, and links nothing', () async {
    clipboard.pictures = [_picture];
    files.failure = const IdeFileNotFoundException('/project/docs');
    expect(await paste().paste(_doc), isA<MarkdownPasteNothing>());
    expect(reports.single, startsWith('Could not paste image.png: '));
  });

  test('a drop is a paste of the files dropped', () async {
    expect(
      links(
        await paste().drop(_doc, const [ComposerFile('/elsewhere/shot.png')]),
      ),
      '![](shot.png)',
    );
  });

  group('in the source', () {
    EditorSurfaceController editor(String text, int caret) =>
        EditorSurfaceController(document: EditorDocumentModel(text))
          ..select(caret, caret);

    test('the links go where the caret is, then after them', () async {
      final c = editor('ab', 1);
      final pasted = await pasteMarkdownLinks(
        c,
        () async => const MarkdownPasteLinks('![](x.png)'),
      );
      expect(pasted, isTrue);
      expect(c.document.text, 'a![](x.png)b');
      expect(c.value.selection.baseOffset, 11);
    });

    test('text is pasted as usual; nothing pasted is nothing', () async {
      final c = editor('ab', 1);
      expect(
        await pasteMarkdownLinks(c, () async => const MarkdownPasteText()),
        isFalse,
      );
      expect(
        await pasteMarkdownLinks(c, () async => const MarkdownPasteNothing()),
        isTrue,
      );
      expect(c.document.text, 'ab');
    });

    test('the text changed elsewhere meanwhile: still where it was', () async {
      final c = editor('one\n\ntwo', 5);
      await pasteMarkdownLinks(c, () async {
        c.document.applyOffsetEdits([const EditorOffsetEdit(0, 3, 'ONE!')]);
        return const MarkdownPasteLinks('[l](l)');
      });
      expect(c.document.text, 'ONE!\n\n[l](l)two');
    });

    test('changed there meanwhile: at the end, and said', () async {
      final c = editor('one\n\ntwo', 5);
      var moved = 0;
      await pasteMarkdownLinks(c, () async {
        c.document.applyOffsetEdits([const EditorOffsetEdit(5, 8, 'TWO')]);
        return const MarkdownPasteLinks('[l](l)');
      }, onMoved: () => moved++);
      expect(c.document.text, 'one\n\nTWO\n\n[l](l)');
      expect(moved, 1);
    });
  });
}
