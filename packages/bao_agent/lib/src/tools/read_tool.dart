import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../permissions/decision.dart';
import '../util/json.dart';
import 'file_state.dart';
import 'image_fit.dart';
import 'pdf_info.dart';
import 'tool.dart';

/// Reads a file: text numbered by line, an image as an image, a PDF as a
/// document, a notebook as its cells.
class ReadTool extends Tool {
  const ReadTool();

  static const maxLines = 2000;
  static const maxLineLength = 2000;

  /// The most a file read whole may be.
  static const maxBytes = 256 * 1024;

  /// The most a read's text may come to, in tokens (about 4 characters).
  static const maxTokens = 25000;

  /// The most pages a PDF read whole may have.
  static const pdfPagesWhole = 10;

  /// The most pages that may be asked for at once.
  static const pdfPagesAtOnce = 20;

  /// The most a PDF read whole may be.
  static const pdfMaxBytes = 20 * 1024 * 1024;

  /// What a file the user mentioned was shown by ([FileRecord.shownBy]).
  static const mentioned = '@mention';

  /// What the model is told of a read the same as one it has in its
  /// conversation, of a file not changed since (the CLI's words).
  static const unchanged =
      'Wasted call — file unchanged since your last Read. Refer to that '
      'earlier tool_result instead.';

  static const imageTypes = {
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.gif': 'image/gif',
    '.webp': 'image/webp',
  };

  @override
  String get name => 'Read';

  @override
  String get description =>
      '''Gives you the contents of a file on this machine: text, an image, a PDF or a Jupyter notebook. Any path on the machine can be read, and a path the user gives can be taken as it is; one that is not there just comes back as an error.

- Give an absolute path.
- Without offset and limit you get the first $maxLines lines, which is usually best. Use them only for a file too long to take at once.
- Every line comes back after its number and a tab, the first line 1. A line longer than $maxLineLength characters is cut short.
- An image (PNG, JPG, GIF, WebP) comes back as the picture itself, made smaller when it is large.
- A PDF of up to $pdfPagesWhole pages comes back as the document. For a larger one you MUST give the pages parameter (pages: "1-5"): reading it without will fail. At most $pdfPagesAtOnce pages a request; they come back as pictures of the pages.
- A notebook comes back cell by cell, each with what it printed.
- A folder cannot be read: list it with `ls` through Bash.
- Several files that may matter can be read at once, in calls side by side in one reply.
- An empty file comes back as a note saying so.''';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': {
      'file_path': {
        'type': 'string',
        'description': 'Absolute path of the file',
      },
      'offset': {
        'type': 'integer',
        'minimum': 0,
        'maximum': 9007199254740991,
        'description': 'The first line to give, counting from 1: only for a file too long to take whole',
      },
      'limit': {
        'type': 'integer',
        'exclusiveMinimum': 0,
        'maximum': 9007199254740991,
        'description':
            'How many lines to give: only for a file too long to take whole',
      },
      'pages': {
        'type': 'string',
        'description': 'For a PDF only: the pages to give, one ("3") or a range ("1-5"), 20 at most',
      },
    },
    'required': ['file_path'],
    'additionalProperties': false,
  };

  @override
  bool isReadOnly(Map<String, Object?> input) => true;

  @override
  String? describe(Map<String, Object?> input) => asString(input['file_path']);

  @override
  String? ruleContent(Map<String, Object?> input) =>
      asString(input['file_path']);

  @override
  Future<PermissionDecision> checkPermissions(
    Map<String, Object?> input,
    ToolContext context,
  ) async => context.session.permissions.checkRead(
    '${input['file_path']}',
    context.cwd,
  );

  @override
  Future<String?> validate(
    Map<String, Object?> input,
    ToolContext context,
  ) async {
    if (input['offset'] case final int offset when offset < 0) {
      return 'offset must not be negative';
    }
    if (input['limit'] case final int limit when limit <= 0) {
      return 'limit must be positive';
    }
    return null;
  }

  @override
  Future<ToolOutput> call(
    Map<String, Object?> input,
    ToolContext context,
  ) async {
    final path = context.session.permissions.absolute(
      '${input['file_path']}',
      context.cwd,
    );
    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.directory) {
      return ToolOutput.error(
        'EISDIR: $path is a directory, not a file. Use `ls` through the '
        'Bash tool to see what is in it.',
      );
    }
    if (type == FileSystemEntityType.notFound) {
      return ToolOutput.error(_notFound(path, context.cwd));
    }
    final file = File(path);
    final extension = p.extension(path).toLowerCase();
    if (imageTypes[extension] case final mediaType?) {
      return _image(file, mediaType, context);
    }
    if (extension == '.pdf') return _pdf(file, asString(input['pages']));
    final offset = asInt(input['offset']);
    final limit = asInt(input['limit']);
    // Read just as before, and not changed since: the model has it.
    if (context.run.readFiles[path] case final previous?
        when previous.shownBy != null &&
            previous.offset == offset &&
            previous.limit == limit &&
            file.lastModifiedSync() == previous.modified) {
      return ToolOutput(
        previous.shownBy == mentioned
            ? '<system-reminder>This file is already in your context (see '
                  '"The user mentioned $path" above) and has not changed on '
                  'disk. Use that content instead of re-reading.'
                  '</system-reminder>'
            : unchanged,
        result: {
          'type': 'file_unchanged',
          'file': {'filePath': path},
        },
      );
    }
    if (extension == '.ipynb') return _notebook(file, context);
    final length = file.lengthSync();
    if (length > maxBytes && offset == null && limit == null) {
      return ToolOutput.error(
        'The file is ${(length / 1024).round()}KB, over the '
        '${maxBytes ~/ 1024}KB that can be read at once. Read a part of it '
        'with offset and limit, or find what you need in it with rg through Bash.',
      );
    }
    final bytes = file.readAsBytesSync();
    if (looksBinary(bytes)) {
      return ToolOutput.error(
        'The file looks binary (a $extension file), not text, and Read only '
        'gives text, images, PDFs and notebooks. Look into it some other '
        'way, with a tool made for its kind.',
      );
    }
    final decoded = decodeText(bytes);
    final text = decoded.text;
    final modified = file.lastModifiedSync();
    // A final newline is followed by an empty last line, shown as such.
    final lines = text.isEmpty ? <String>[] : text.split('\n');
    final total = lines.length;
    // `offset` is a line number, 1 the first: 0 is taken as 1.
    final start = offset == null || offset <= 1 ? 0 : offset - 1;
    final count = limit ?? maxLines;
    FileRecord record({String? shownBy}) => FileRecord(
      content: text,
      modified: modified,
      offset: offset,
      limit: limit,
      shownBy: shownBy,
    );
    context.run.readFiles[path] = record();
    // Shown: a read the same again, the file as it was, is not repeated.
    void markShown() =>
        context.run.readFiles[path] = record(shownBy: context.toolUseId);
    final reminders = context.session.memoryFor(path, context.run);
    String withReminders(String body) => [
      body,
      for (final reminder in reminders)
        '<system-reminder>\n$reminder\n</system-reminder>',
    ].join('\n\n');
    if (text.isEmpty) {
      markShown();
      return ToolOutput(
        withReminders(
          '<system-reminder>The file is there, but empty.</system-reminder>',
        ),
        result: _textResult(path, '', 0, 1, 0),
      );
    }
    if (start >= total) {
      markShown();
      return ToolOutput(
        withReminders(
          '<system-reminder>The file has only $total lines, so nothing '
          'starts at line ${start + 1}.</system-reminder>',
        ),
        result: _textResult(path, '', 0, start + 1, total),
      );
    }
    final end = (start + count).clamp(0, total);
    final shown = [
      for (final line in lines.sublist(start, end))
        line.length > maxLineLength
            ? '${line.substring(0, maxLineLength)}… [line truncated]'
            : line,
    ];
    final body = numberLines(shown, start + 1);
    if (body.length ~/ 4 > maxTokens) {
      return ToolOutput.error(
        'Those lines come to about ${body.length ~/ 4} tokens, over the '
        '$maxTokens that can be read at once. Read fewer with offset and '
        'limit, or find what you need with rg through Bash.',
      );
    }
    final note = end < total && limit == null
        ? '\n\n<system-reminder>The file has $total lines; lines '
              '${start + 1}-$end are shown. Use offset and limit to read '
              'the rest.</system-reminder>'
        : '';
    markShown();
    return ToolOutput(
      withReminders('$body$note'),
      result: _textResult(
        path,
        shown.join('\n'),
        shown.length,
        start + 1,
        total,
      ),
    );
  }

  static Map<String, Object?> _textResult(
    String path,
    String content,
    int lines,
    int start,
    int total,
  ) => {
    'type': 'text',
    'file': {
      'filePath': path,
      'content': content,
      'numLines': lines,
      'startLine': start,
      'totalLines': total,
    },
  };

  /// What is said of a file not there: where else it might be.
  static String _notFound(String path, String cwd) {
    final buffer = StringBuffer('No file is there.');
    final folder = Directory(p.dirname(path));
    if (folder.existsSync()) {
      final base = p.basenameWithoutExtension(path).toLowerCase();
      try {
        final similar = folder
            .listSync()
            .whereType<File>()
            .map((f) => f.path)
            .where(
              (other) =>
                  p.basenameWithoutExtension(other).toLowerCase() == base,
            )
            .take(3)
            .toList();
        if (similar.isNotEmpty) {
          buffer.write(' Perhaps ${similar.join(' or ')}?');
        }
      } on FileSystemException {
        // Nothing to suggest.
      }
    }
    buffer.write(' (The working directory is $cwd.)');
    return buffer.toString();
  }

  Future<ToolOutput> _image(
    File file,
    String mediaType,
    ToolContext context,
  ) async {
    final bytes = file.readAsBytesSync();
    final FittedImage image;
    try {
      image = await fitImage(bytes, fallbackType: mediaType);
    } on ImageFitException catch (error) {
      return ToolOutput.error(error.message);
    }
    final data = base64Encode(image.bytes);
    context.run.readFiles[file.path] = FileRecord(
      content: '',
      modified: file.lastModifiedSync(),
      offset: 0,
    );
    return ToolOutput(
      [
        {
          'type': 'image',
          'source': {
            'type': 'base64',
            'media_type': image.mediaType,
            'data': data,
          },
        },
        if (image.note case final note?) {'type': 'text', 'text': note},
      ],
      result: {
        'type': 'image',
        'file': {
          'base64': data,
          'type': image.mediaType,
          'originalSize': bytes.length,
          if (image.width != null)
            'dimensions': {
              'originalWidth': image.width,
              'originalHeight': image.height,
              'displayWidth': image.displayWidth,
              'displayHeight': image.displayHeight,
            },
        },
      },
    );
  }

  Future<ToolOutput> _pdf(File file, String? pages) async {
    final length = file.lengthSync();
    if (length == 0) return ToolOutput.error('The PDF is empty.');
    if (pages != null) return _pdfPages(file, pages);
    if (length > pdfMaxBytes) {
      return ToolOutput.error(
        'PDF file exceeds maximum allowed size of '
        '${pdfMaxBytes ~/ 1024 ~/ 1024}MB. Use the pages parameter to read '
        'specific page ranges (e.g., pages: "1-5").',
      );
    }
    final bytes = file.readAsBytesSync();
    if (!looksLikePdf(bytes)) {
      return ToolOutput.error('File is not a valid PDF (missing %PDF- header)');
    }
    final count = pdfPageCount(bytes, path: file.path);
    if (count != null && count > pdfPagesWhole) {
      return ToolOutput.error(
        'This PDF has $count pages, which is too many to read at once. Use '
        'the pages parameter to read specific page ranges (e.g., pages: '
        '"1-5"). Maximum $pdfPagesAtOnce pages per request.',
      );
    }
    if (count == null && length > 3 * 1024 * 1024) {
      return ToolOutput.error(
        'How many pages this PDF has could not be told, and at '
        '${_mb(length)} it may be too many to read at once. Use the pages '
        'parameter to read specific page ranges (e.g., pages: "1-5"). '
        'Maximum $pdfPagesAtOnce pages per request.',
      );
    }
    return ToolOutput(
      [
        {
          'type': 'document',
          'source': {
            'type': 'base64',
            'media_type': 'application/pdf',
            'data': base64Encode(bytes),
          },
        },
      ],
      result: {
        'type': 'pdf',
        'file': {'filePath': file.path, 'originalSize': bytes.length},
      },
    );
  }

  /// [pages] of the PDF [file], as pictures of the pages by `pdftoppm`;
  /// as their text by `pdftotext` where only that is installed. Never the
  /// whole document.
  Future<ToolOutput> _pdfPages(File file, String pages) async {
    final match = RegExp(r'^\s*(\d+)\s*(?:-\s*(\d*)\s*)?$').firstMatch(pages);
    final first = match == null ? 0 : int.parse(match[1]!);
    final open = match?[2]?.isEmpty ?? false;
    final last = match == null
        ? 0
        : open
        ? first + pdfPagesAtOnce - 1
        : int.parse(match[2] ?? match[1]!);
    if (match == null || first < 1 || last < first) {
      return ToolOutput.error(
        'pages must be one page ("3") or a range ("1-5"), counting from 1.',
      );
    }
    if (last - first >= pdfPagesAtOnce) {
      return ToolOutput.error(
        'That is ${last - first + 1} pages: at most $pdfPagesAtOnce can be '
        'read at once. Ask for a smaller range.',
      );
    }
    final header = await file
        .openRead(0, 1024)
        .fold(<int>[], (a, b) => a..addAll(b));
    if (!looksLikePdf(Uint8List.fromList(header))) {
      return ToolOutput.error('File is not a valid PDF (missing %PDF- header)');
    }
    final size = _mb(file.lengthSync());
    final folder = Directory.systemTemp.createTempSync('bao-pdf-');
    try {
      final ProcessResult result;
      try {
        result = await _run('pdftoppm', [
          '-jpeg',
          '-r',
          '100',
          '-f',
          '$first',
          '-l',
          '$last',
          file.path,
          p.join(folder.path, 'page'),
        ]);
      } on ProcessException {
        return await _pdfText(file.path, first, last, size);
      }
      if (result.exitCode != 0) {
        final error = '${result.stderr}'.trim();
        if (error.toLowerCase().contains('password')) {
          return ToolOutput.error(
            'PDF is password-protected. Please provide an unprotected '
            'version of the file.',
          );
        }
        return ToolOutput.error(
          'The pages could not be rendered: '
          '${error.isEmpty ? 'pdftoppm exited ${result.exitCode}' : error}',
        );
      }
      final images = folder.listSync().whereType<File>().toList()
        ..sort((a, b) => _pageOf(a.path).compareTo(_pageOf(b.path)));
      if (images.isEmpty) {
        return ToolOutput.error(
          'No pages were rendered: the PDF has fewer than $first pages.',
        );
      }
      final blocks = <Map<String, Object?>>[
        {
          'type': 'text',
          'text':
              'PDF pages extracted: ${images.length} page(s) from '
              '${file.path} ($size)',
        },
      ];
      for (final image in images) {
        try {
          final fitted = await fitImage(
            image.readAsBytesSync(),
            fallbackType: 'image/jpeg',
          );
          blocks.add({
            'type': 'image',
            'source': {
              'type': 'base64',
              'media_type': fitted.mediaType,
              'data': base64Encode(fitted.bytes),
            },
          });
        } on ImageFitException catch (error) {
          blocks.add({
            'type': 'text',
            'text':
                '[Page ${_pageOf(image.path)} could not be processed as '
                'an image: ${error.message}]',
          });
        }
      }
      return ToolOutput(
        blocks,
        result: {
          'type': 'parts',
          'file': {
            'filePath': file.path,
            'originalSize': file.lengthSync(),
            'count': images.length,
            'outputDir': folder.path,
          },
        },
      );
    } finally {
      try {
        folder.deleteSync(recursive: true);
      } on FileSystemException {
        // Left to the system's own clearing of its temporary files.
      }
    }
  }

  /// The page number in a name `pdftoppm` gave (`page-07.jpg`).
  static int _pageOf(String path) =>
      int.tryParse(
        RegExp(r'(\d+)\.\w+$').firstMatch(p.basename(path))?[1] ?? '',
      ) ??
      0;

  /// The text of pages [first] to [last] of the PDF at [path], by
  /// `pdftotext`, where `pdftoppm` is not installed.
  static Future<ToolOutput> _pdfText(
    String path,
    int first,
    int last,
    String size,
  ) async {
    final ProcessResult result;
    try {
      result = await _run('pdftotext', [
        '-f',
        '$first',
        '-l',
        '$last',
        '-layout',
        path,
        '-',
      ]);
    } on ProcessException {
      return ToolOutput.error(
        'pdftoppm is not installed. Install poppler-utils (e.g. `brew install '
        'poppler` or `apt-get install poppler-utils`) to enable PDF page '
        'rendering.',
      );
    }
    final error = '${result.stderr}'.trim();
    if (result.exitCode != 0) {
      if (error.toLowerCase().contains('password')) {
        return ToolOutput.error(
          'PDF is password-protected. Please provide an unprotected version '
          'of the file.',
        );
      }
      return ToolOutput.error(
        'The pages could not be read: '
        '${error.isEmpty ? 'pdftotext exited ${result.exitCode}' : error}',
      );
    }
    final text = '${result.stdout}';
    final body = text.trim().isEmpty
        ? '<system-reminder>These pages have no text to extract (they may '
              'be scans); install poppler-utils for pdftoppm to see them as '
              'pictures.</system-reminder>'
        : text;
    return ToolOutput(
      'Text of pages $first-$last of $path ($size):\n\n$body',
      result: {
        'type': 'text',
        'file': {'filePath': path, 'content': text, 'pages': '$first-$last'},
      },
    );
  }

  /// [executable] with [arguments], stopped after two minutes.
  static Future<ProcessResult> _run(
    String executable,
    List<String> arguments,
  ) async {
    final process = await Process.start(executable, arguments);
    final out = process.stdout.transform(utf8.decoder).join();
    final err = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    final code = await process.exitCode.timeout(
      const Duration(seconds: 120),
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    return ProcessResult(process.pid, code, await out, await err);
  }

  static String _mb(int bytes) =>
      '${(bytes / 1024 / 1024).toStringAsFixed(1)}MB';

  ToolOutput _notebook(File file, ToolContext context) {
    final text = readText(file).text;
    Map<String, Object?> notebook;
    try {
      notebook = asMap(jsonDecode(text));
    } on FormatException catch (error) {
      return ToolOutput.error('The notebook is not valid JSON: $error');
    }
    context.run.readFiles[file.path] = FileRecord(
      content: text,
      modified: file.lastModifiedSync(),
      shownBy: context.toolUseId,
    );
    final language =
        asString(asMap(asMap(notebook['metadata'])['language_info'])['name']) ??
        'python';
    final blocks = <Map<String, Object?>>[];
    final cells = <Map<String, Object?>>[];
    for (final (index, raw) in asList(notebook['cells']).indexed) {
      final cell = asMap(raw);
      final id = asString(cell['id']) ?? 'cell-$index';
      final type = asString(cell['cell_type']) ?? 'code';
      final source = _joined(cell['source']);
      final out = StringBuffer('<cell id="$id">');
      if (type != 'code') out.write('<cell_type>$type</cell_type>');
      if (type == 'code' && language != 'python') {
        out.write('<language>$language</language>');
      }
      out.write('$source</cell id="$id">');
      blocks.add({'type': 'text', 'text': out.toString()});
      for (final output in asList(cell['outputs'])) {
        final o = asMap(output);
        final data = asMap(o['data']);
        final textOut = _joined(o['text'] ?? data['text/plain']);
        if (textOut.isNotEmpty) {
          blocks.add({'type': 'text', 'text': textOut});
        }
        if (o['output_type'] == 'error') {
          blocks.add({
            'type': 'text',
            'text': '${o['ename']}: ${o['evalue']}\n${_joined(o['traceback'])}',
          });
        }
        for (final mime in const ['image/png', 'image/jpeg']) {
          if (data[mime] case final String image) {
            blocks.add({
              'type': 'image',
              'source': {
                'type': 'base64',
                'media_type': mime,
                'data': image.replaceAll('\n', ''),
              },
            });
          }
        }
      }
      cells.add({'cellType': type, 'source': source, 'cell_id': id});
    }
    return ToolOutput(
      blocks.isEmpty ? 'The notebook has no cells.' : blocks,
      result: {
        'type': 'notebook',
        'file': {'filePath': file.path, 'cells': cells},
      },
    );
  }

  static String _joined(Object? source) => switch (source) {
    final String text => text,
    final List<Object?> parts => parts.join(),
    _ => '',
  };
}
