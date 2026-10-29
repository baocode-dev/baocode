import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// A file as the agent last read or wrote it: what it held, and when it
/// was last changed then. An edit is refused when the file changed since.
class FileRecord {
  const FileRecord({
    required this.content,
    required this.modified,
    this.offset,
    this.limit,
  });

  final String content;
  final DateTime modified;

  /// The part read, when not all of it was.
  final int? offset;
  final int? limit;

  bool get partial => offset != null || limit != null;
}

/// The files an agent has read, by path.
class ReadFileState {
  final Map<String, FileRecord> _records = {};

  FileRecord? operator [](String path) => _records[path];

  void operator []=(String path, FileRecord record) => _records[path] = record;

  void remove(String path) => _records.remove(path);

  Iterable<String> get paths => _records.keys;

  void clear() => _records.clear();

  /// A state of its own that starts with what this one has read (a
  /// subagent's, which may change what its caller read).
  ReadFileState copy() => ReadFileState().._records.addAll(_records);

  /// What is wrong with changing [path] now: not read, or changed since.
  /// Null when it may be changed.
  String? staleness(String path) {
    final record = _records[path];
    if (record == null) {
      return 'This file has not been read in this conversation: read it before '
          'changing it.';
    }
    final file = File(path);
    if (!file.existsSync()) return null;
    final modified = file.lastModifiedSync();
    if (modified.isAfter(record.modified)) {
      // Touched, not changed (a formatter that left it as it was): fine.
      if (!record.partial) {
        try {
          if (readText(file).text == record.content) return null;
        } on FileSystemException {
          // Said below.
        }
      }
      return 'The file has changed since it was read (the user, or a tool '
          'such as a formatter, touched it): read it again, then make the '
          'change.';
    }
    return null;
  }
}

/// A text file's content, its line endings made `\n`, and what it had.
class FileText {
  const FileText(this.text, {this.crlf = false, this.encoding = 'utf8'});

  final String text;

  /// Whether its lines ended `\r\n`: written back so.
  final bool crlf;

  /// `utf8` or `utf16le`.
  final String encoding;

  /// [content] as it is to be written to a file read as this one was.
  List<int> encode(String content) {
    final text = crlf
        ? content.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n')
        : content;
    if (encoding == 'utf16le') {
      final units = text.codeUnits;
      final bytes = Uint8List(2 + units.length * 2);
      bytes[0] = 0xFF;
      bytes[1] = 0xFE;
      for (var i = 0; i < units.length; i++) {
        bytes[2 + i * 2] = units[i] & 0xFF;
        bytes[3 + i * 2] = units[i] >> 8;
      }
      return bytes;
    }
    return utf8.encode(text);
  }
}

/// [file]'s text: UTF-8 (or UTF-16 with its mark), its line endings made
/// `\n`.
FileText readText(File file) => decodeText(file.readAsBytesSync());

FileText decodeText(List<int> bytes) {
  var encoding = 'utf8';
  String text;
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    encoding = 'utf16le';
    final units = <int>[
      for (var i = 2; i + 1 < bytes.length; i += 2)
        bytes[i] | (bytes[i + 1] << 8),
    ];
    text = String.fromCharCodes(units);
  } else {
    var start = 0;
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      start = 3;
    }
    text = utf8.decode(bytes.sublist(start), allowMalformed: true);
  }
  final crlf = text.contains('\r\n');
  return FileText(
    crlf ? text.replaceAll('\r\n', '\n') : text,
    crlf: crlf,
    encoding: encoding,
  );
}

/// Whether [bytes] (the start of a file) look like anything but text.
bool looksBinary(List<int> bytes) {
  final sample = bytes.length > 8192 ? bytes.sublist(0, 8192) : bytes;
  if (sample.length >= 2 && sample[0] == 0xFF && sample[1] == 0xFE) {
    return false;
  }
  var control = 0;
  for (final byte in sample) {
    if (byte == 0) return true;
    if (byte < 7 || (byte > 13 && byte < 32 && byte != 27)) control++;
  }
  return sample.isNotEmpty && control / sample.length > 0.1;
}

/// [lines] numbered from [first]: each its number, a tab, the line.
String numberLines(List<String> lines, int first) {
  final out = StringBuffer();
  for (final (i, line) in lines.indexed) {
    if (i > 0) out.write('\n');
    out.write('${first + i}\t$line');
  }
  return out.toString();
}

/// The lines around [newText]'s place in [content] (where an edit put
/// it), numbered: what the model is shown of its edit.
String snippetAround(String content, String newText, {int context = 4}) {
  final lines = content.split('\n');
  var at = newText.isEmpty ? -1 : content.indexOf(newText);
  if (at < 0) at = 0;
  final startLine = '\n'.allMatches(content.substring(0, at)).length;
  final spanned = '\n'.allMatches(newText).length;
  final from = (startLine - context).clamp(0, lines.length);
  final to = (startLine + spanned + context + 1).clamp(0, lines.length);
  return numberLines(lines.sublist(from, to), from + 1);
}
