import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../permissions/decision.dart';
import '../util/json.dart';
import 'file_state.dart';
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

  /// The most an image may be as the API takes it.
  static const maxImageBytes = 3750 * 1024;

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
- An image (PNG, JPG, GIF, WebP) comes back as the picture itself.
- A PDF comes back as the document; for a long one, ask for some pages, at most 20 at a time (pages: "1-5").
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
    if (extension == '.ipynb') return _notebook(file, context);
    final length = file.lengthSync();
    final offset = asInt(input['offset']);
    final limit = asInt(input['limit']);
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
    context.run.readFiles[path] = FileRecord(
      content: text,
      modified: modified,
      offset: offset,
      limit: limit,
    );
    final reminders = context.session.memoryFor(path, context.run);
    String withReminders(String body) => [
      body,
      for (final reminder in reminders)
        '<system-reminder>\n$reminder\n</system-reminder>',
    ].join('\n\n');
    if (text.isEmpty) {
      return ToolOutput(
        withReminders(
          '<system-reminder>The file is there, but empty.</system-reminder>',
        ),
        result: _textResult(path, '', 0, 1, 0),
      );
    }
    if (start >= total) {
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

  ToolOutput _image(File file, String mediaType, ToolContext context) {
    final bytes = file.readAsBytesSync();
    if (bytes.length > maxImageBytes) {
      return ToolOutput.error(
        'The image is ${(bytes.length / 1024 / 1024).toStringAsFixed(1)}MB, '
        'more than the ${(maxImageBytes / 1024 / 1024).toStringAsFixed(1)}MB '
        'the model takes. Resize it first (for example with `sips -Z 1568` '
        'on macOS or ImageMagick `convert -resize`), then read the smaller '
        'copy.',
      );
    }
    final data = base64Encode(bytes);
    context.run.readFiles[file.path] = FileRecord(
      content: '',
      modified: file.lastModifiedSync(),
      offset: 0,
    );
    return ToolOutput(
      [
        {
          'type': 'image',
          'source': {'type': 'base64', 'media_type': mediaType, 'data': data},
        },
      ],
      result: {
        'type': 'image',
        'file': {
          'base64': data,
          'type': mediaType,
          'originalSize': bytes.length,
        },
      },
    );
  }

  ToolOutput _pdf(File file, String? pages) {
    final bytes = file.readAsBytesSync();
    if (pages != null) {
      final text = _pdfText(file.path, pages);
      if (text != null) {
        return ToolOutput(
          text,
          result: {
            'type': 'text',
            'file': {'filePath': file.path, 'content': text, 'pages': pages},
          },
        );
      }
    }
    if (bytes.length > 20 * 1024 * 1024) {
      return ToolOutput.error(
        'The PDF is too large to read whole '
        '(${(bytes.length / 1024 / 1024).toStringAsFixed(1)}MB). Give the '
        'pages parameter to read part of it.',
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

  /// The text of [pages] of the PDF at [path], by `pdftotext` where it is
  /// installed.
  static String? _pdfText(String path, String pages) {
    final match = RegExp(r'^\s*(\d+)\s*(?:-\s*(\d+))?\s*$').firstMatch(pages);
    if (match == null) return null;
    final first = int.parse(match[1]!);
    final last = int.parse(match[2] ?? match[1]!);
    if (last < first || last - first >= 20) return null;
    try {
      final result = Process.runSync('pdftotext', [
        '-f',
        '$first',
        '-l',
        '$last',
        '-layout',
        path,
        '-',
      ]);
      if (result.exitCode != 0) return null;
      return '${result.stdout}';
    } on ProcessException {
      return null;
    }
  }

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
