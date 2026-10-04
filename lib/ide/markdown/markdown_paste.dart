// A paste (or a drop) of files and pictures into a markdown document, as
// VS Code's markdown editor takes one (`markdown.editor.filePaste`): the
// files are put beside the document and linked to.

import 'dart:async';
import 'dart:io' show File;

import 'package:bao_editor/monaco/flutter/editor_document_model.dart';
import 'package:bao_editor/monaco/flutter/editor_surface_controller.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../chat/chat_models.dart' show ImageAttachment;
import '../../chat/composer/composer_files.dart' show ComposerFile;
import '../../l10n/l10n.dart';
import '../../workspace/window_controls.dart';
import '../file_service.dart';
import 'markdown_block_editor.dart';

/// What a paste in a markdown document does (see [MarkdownPaste]).
sealed class MarkdownPasteOutcome {
  const MarkdownPasteOutcome();
}

/// The clipboard holds text: pasted as usual.
class MarkdownPasteText extends MarkdownPasteOutcome {
  const MarkdownPasteText();
}

/// Files were put beside the document (or are the project's already):
/// [text] links to them, to insert where the paste goes.
class MarkdownPasteLinks extends MarkdownPasteOutcome {
  const MarkdownPasteLinks(this.text);

  final String text;
}

/// Nothing to insert: the paste failed (and said why) or was called off.
class MarkdownPasteNothing extends MarkdownPasteOutcome {
  const MarkdownPasteNothing();
}

/// What the clipboard holds, as a markdown paste reads it: the window's
/// (see [WindowControls]); a fake under test.
abstract interface class MarkdownClipboard {
  /// Files and folders copied (in Finder, Explorer, the IDE's explorer).
  Future<List<ComposerFile>> files();

  /// Pictures (a screenshot); none when the clipboard holds text.
  Future<List<ImageAttachment>> images();

  Future<bool> hasText();
}

class SystemMarkdownClipboard implements MarkdownClipboard {
  const SystemMarkdownClipboard();

  @override
  Future<List<ComposerFile>> files() => WindowControls.readPasteboardFiles();

  @override
  Future<List<ImageAttachment>> images() =>
      WindowControls.readPasteboardImages();

  @override
  Future<bool> hasText() => Clipboard.hasStrings();
}

/// Pastes and drops of files into the project's markdown documents: each
/// file copied beside the document (uploaded, in a remote project), under
/// a name not taken (`image-1.png`), and linked to.
class MarkdownPaste {
  MarkdownPaste({
    required this.files,
    required this.l10n,
    this.root,
    p.Context? context,
    this.remote = false,
    this.clipboard = const SystemMarkdownClipboard(),
    Future<Uint8List> Function(String path)? readLocal,
    Future<int> Function(String path)? sizeOf,
    this.confirmLarge,
    this.report,
  }) : context = context ?? p.context,
       readLocal = readLocal ?? readFileBytes,
       sizeOf = sizeOf ?? ((path) => File(path).length());

  /// The project's files, where the copies go.
  final IdeFileService files;
  final AppLocalizations l10n;

  /// The project's folder: files in it are linked to, not copied. None
  /// for a window without one.
  final String? root;

  /// How the project's host writes paths (POSIX for a remote one).
  final p.Context context;

  /// Whether the project is another machine's: the clipboard's files, this
  /// machine's, are uploaded there.
  final bool remote;

  final MarkdownClipboard clipboard;

  /// Reads a file of this machine (to upload it).
  final Future<Uint8List> Function(String path) readLocal;
  final Future<int> Function(String path) sizeOf;

  /// Asked before a file over [largeFile] is copied: whether to.
  final Future<bool> Function(String name, int size)? confirmLarge;

  /// Says why a file was not pasted.
  final void Function(String message)? report;

  static const largeFile = 50 * 1024 * 1024;

  /// A paste in the document at [document]: the clipboard's files, or its
  /// pictures when it holds no text, else its text as usual.
  Future<MarkdownPasteOutcome> paste(String document) async {
    final files = await clipboard.files();
    if (files.isNotEmpty) return _paste(document, files);
    final images = await clipboard.images();
    if (images.isNotEmpty && !await clipboard.hasText()) {
      return _pictures(document, images);
    }
    return const MarkdownPasteText();
  }

  /// [dropped] on the document at [document].
  Future<MarkdownPasteOutcome> drop(
    String document,
    List<ComposerFile> dropped,
  ) => _paste(document, dropped);

  Future<MarkdownPasteOutcome> _paste(
    String document,
    List<ComposerFile> pasted,
  ) async {
    final folder = context.dirname(document);
    final links = <String>[];
    for (final file in pasted) {
      final name = p.basename(file.path);
      if (file.directory) {
        report?.call(l10n.markdownPasteFolder(name));
        continue;
      }
      final root = this.root;
      if (!remote && root != null && _within(root, file.path)) {
        links.add(_link(context.relative(file.path, from: folder), name));
        continue;
      }
      try {
        final size = await sizeOf(file.path);
        if (size > largeFile &&
            !(await confirmLarge?.call(name, size) ?? false)) {
          continue;
        }
      } catch (_) {
        // Its size unknown: copying it says what is wrong.
      }
      final written = await _write(folder, name, (target) async {
        if (remote) {
          await files.writeBytes(target, await readLocal(file.path));
        } else {
          await files.copy(file.path, target);
        }
      });
      if (written != null) links.add(_link(written, written));
    }
    return _links(links);
  }

  Future<MarkdownPasteOutcome> _pictures(
    String document,
    List<ImageAttachment> images,
  ) async {
    final folder = context.dirname(document);
    final links = <String>[];
    for (final image in images) {
      final extension = _extensions[image.mediaType] ?? '.png';
      final name = switch (image.name) {
        final name? when name.isNotEmpty => p.setExtension(
          p.basename(name),
          extension,
        ),
        _ => 'image$extension',
      };
      final written = await _write(
        folder,
        name,
        (target) => files.writeBytes(target, image.bytes),
      );
      if (written != null) links.add(_link(written, written));
    }
    return _links(links);
  }

  static MarkdownPasteOutcome _links(List<String> links) => links.isEmpty
      ? const MarkdownPasteNothing()
      : MarkdownPasteLinks(links.join('\n'));

  /// Writes [name] in [folder] with [write], as `name-1.ext`, `name-2.ext`…
  /// while the name is taken; the name written, or null when it failed
  /// (said).
  Future<String?> _write(
    String folder,
    String name,
    Future<void> Function(String target) write,
  ) async {
    final extension = p.extension(name);
    final stem = p.basenameWithoutExtension(name);
    for (var n = 0; n < 1000; n++) {
      final candidate = n == 0 ? name : '$stem-$n$extension';
      try {
        await write(context.join(folder, candidate));
        return candidate;
      } on IdeFileExistsException {
        continue;
      } catch (error) {
        report?.call(
          l10n.markdownPasteFailed(name, localizedFileError(l10n, error)),
        );
        return null;
      }
    }
    report?.call(l10n.markdownPasteFailed(name, l10n.fileErrorExists(name)));
    return null;
  }

  bool _within(String root, String path) =>
      context.isWithin(root, path) || context.equals(root, path);

  /// A link to [path] (relative to the document): a picture's shown.
  String _link(String path, String name) {
    final target = path.replaceAll(r'\', '/');
    final written = RegExp(r'[\s()<>]').hasMatch(target) ? '<$target>' : target;
    if (_pictureExtensions.contains(p.extension(target).toLowerCase())) {
      return '![]($written)';
    }
    final text = p
        .basename(name)
        .replaceAllMapped(RegExp(r'[\[\]\\]'), (match) => '\\${match[0]}');
    return '[$text]($written)';
  }

  static const _extensions = {
    'image/png': '.png',
    'image/jpeg': '.jpg',
    'image/gif': '.gif',
    'image/webp': '.webp',
  };

  static const _pictureExtensions = {
    '.png',
    '.jpg',
    '.jpeg',
    '.gif',
    '.webp',
    '.svg',
    '.bmp',
  };
}

/// A paste in [controller]'s markdown document taken by [paste]: its links
/// where the caret was, or, the text having changed there meanwhile, at
/// the end ([onMoved]). Whether it pasted (the clipboard's text is not).
Future<bool> pasteMarkdownLinks(
  EditorSurfaceController controller,
  Future<MarkdownPasteOutcome> Function() paste, {
  VoidCallback? onMoved,
}) async {
  final model = controller.document;
  final version = model.version;
  final selection = controller.value.selection;
  final start = selection.isValid ? selection.start : model.text.length;
  final end = selection.isValid ? selection.end : start;
  // Where the paste goes, followed through the edits made meanwhile.
  final spot = MarkdownBlockEdit(model, start: start, end: end);
  final MarkdownPasteOutcome outcome;
  try {
    outcome = await paste();
  } catch (_) {
    spot.cancel();
    rethrow;
  }
  switch (outcome) {
    case MarkdownPasteText():
      spot.cancel();
      return false;
    case MarkdownPasteNothing():
      spot.cancel();
      return true;
    case MarkdownPasteLinks(:final text):
      if (model.version == version) {
        spot.cancel();
        controller.pasteText(text);
      } else if (!spot.conflicted) {
        // Over what was selected then.
        spot.commit(text);
      } else {
        spot.cancel();
        insertMarkdownAtEnd(model, text);
        onMoved?.call();
      }
      return true;
  }
}

/// [text] as a block of its own at the end of [model]'s text.
void insertMarkdownAtEnd(EditorDocumentModel model, String text) {
  final end = model.text.length;
  final edit = MarkdownBlockEdit(
    model,
    start: end,
    end: end,
    prefix: MarkdownBlockEdit.newBlockPrefix(model.text),
  );
  edit.commit(text);
}
