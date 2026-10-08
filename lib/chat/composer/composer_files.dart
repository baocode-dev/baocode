import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// A file or folder put into the composer from outside it: dropped on it
/// (from another app, or from the IDE), pasted after a copy, or picked.
@immutable
class ComposerFile {
  const ComposerFile(this.path, {this.directory = false});

  /// Absolute.
  final String path;
  final bool directory;

  String get name => p.basename(path);

  /// Whether it may be a picture to show the agent, by its name (the
  /// window reads it, see [WindowControls.readImageFile]).
  bool get maybeImage =>
      !directory && _imageExtensions.contains(p.extension(path).toLowerCase());

  static const _imageExtensions = {
    '.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', //
    '.tif', '.tiff', '.heic', '.heif',
  };

  @override
  bool operator ==(Object other) =>
      other is ComposerFile &&
      other.path == path &&
      other.directory == directory;

  @override
  int get hashCode => Object.hash(path, directory);

  @override
  String toString() => 'ComposerFile($path${directory ? '/' : ''})';
}

/// What a drag inside the app carries to the composer (from the IDE's
/// explorer, its tabs…): files, as the system's drags from other apps do.
@immutable
class FileDragData {
  const FileDragData(this.files);

  final List<ComposerFile> files;
}

/// [path] as the composer shows and sends it: from the project's [root]
/// when it is in the project, else as it is.
String displayPath(String path, String? root) {
  if (root == null || !p.isWithin(root, path)) return path;
  return p.relative(path, from: root);
}

/// A file or folder as a message's text refers to it: `@lib/main.dart`, a
/// folder with a separator after it (`@lib/chat/`), and, with characters
/// that would end it early (a space, CJK…), quoted: `@"My Docs/notes.md"`.
/// See [parseFileReference].
String fileReferenceText(String path, {bool directory = false}) {
  if (directory && !_endsInSeparator(path)) {
    path += path.contains('/') || !path.contains(r'\') ? '/' : r'\';
  }
  return _unquoted.hasMatch(path) && !_trailing.hasMatch(path)
      ? '@$path'
      : '@"$path"';
}

bool _endsInSeparator(String path) => path.endsWith('/') || path.endsWith(r'\');

/// What a path in a message's text is written with, unquoted.
final _unquoted = RegExp(r'^[A-Za-z0-9_./\\:~+\-]+$');

/// Ends of a sentence after a path rather than part of it.
final _trailing = RegExp(r'[.:]$');

/// The file or folder an `@` at [at] of [text] refers to (see
/// [fileReferenceText]), and where its reference ends; null when what
/// follows is no path: a word (`@override`, a handle) has neither a slash
/// nor a dot.
({String path, bool directory, int end})? parseFileReference(
  String text,
  int at,
) {
  if (at >= text.length || text[at] != '@') return null;
  final start = at + 1;
  String path;
  int end;
  if (start < text.length && text[start] == '"') {
    final close = text.indexOf('"', start + 1);
    if (close < 0) return null;
    path = text.substring(start + 1, close);
    if (path.contains('\n')) return null;
    end = close + 1;
  } else {
    end = start;
    while (end < text.length && _unquoted.hasMatch(text[end])) {
      end++;
    }
    // `see @lib/main.dart.` ends the sentence, not the name.
    while (end > start && _trailing.hasMatch(text[end - 1])) {
      end--;
    }
    path = text.substring(start, end);
    if (!path.contains('/') && !path.contains(r'\') && !path.contains('.')) {
      return null;
    }
  }
  final directory = _endsInSeparator(path);
  if (directory) path = path.substring(0, path.length - 1);
  if (path.isEmpty) return null;
  return (path: path, directory: directory, end: end);
}

/// What a message carries after its text (see [codeAppendix]), its text
/// referring to it by [reference]: lines of a file, or a long paste.
sealed class AppendedText {
  const AppendedText();

  /// How the message's text refers to it, in brackets.
  String get reference;

  /// What goes after the message's text.
  String get content;
}

/// Lines of a file, copied from the IDE's editor and pasted into the
/// composer: the message refers to them as `[lib/main.dart:12-30]`, and
/// carries them after its text (see [codeAppendix]).
@immutable
class CodeReference extends AppendedText {
  const CodeReference({
    required this.path,
    required this.start,
    required this.end,
    required this.code,
  });

  /// As shown and sent (see [displayPath]).
  final String path;

  /// The first and last line, from 1.
  final int start;
  final int end;
  final String code;

  /// `lib/main.dart:12-30`, or `lib/main.dart:12` for one line.
  String get label => start == end ? '$path:$start' : '$path:$start-$end';

  /// How the message's text refers to it: `[lib/main.dart:12-30]`.
  @override
  String get reference => '[$label]';

  @override
  String get content => code;

  Map<String, Object> toJson() => {
    'path': path,
    'start': start,
    'end': end,
    'code': code,
  };

  static CodeReference fromJson(Map<String, Object?> json) => CodeReference(
    path: json['path'] as String,
    start: json['start'] as int,
    end: json['end'] as int,
    code: json['code'] as String,
  );

  CodeReference withPath(String path) =>
      CodeReference(path: path, start: start, end: end, code: code);

  @override
  bool operator ==(Object other) =>
      other is CodeReference &&
      other.path == path &&
      other.start == start &&
      other.end == end &&
      other.code == code;

  @override
  int get hashCode => Object.hash(path, start, end, code);
}

/// Text too long to paste into the composer as it is (laying it out there
/// would hang the window, see [isLong]): the message refers to it as
/// `[Pasted text #1 +120 lines]`, as Claude Code's own input does, and
/// carries it after its text (see [codeAppendix]).
@immutable
class PastedText extends AppendedText {
  const PastedText({required this.number, required this.text});

  /// Of the pastes in the message, from 1.
  final int number;
  final String text;

  /// Pasted as a tag past this many characters…
  static const maxLength = 1000;

  /// …or line breaks.
  static const maxLineBreaks = 20;

  /// Whether pasting [text] puts it in as a tag rather than as text.
  static bool isLong(String text) =>
      text.length > maxLength || '\n'.allMatches(text).length > maxLineBreaks;

  /// Its line breaks, the last one aside: the lines past the first.
  int get extraLines {
    final trimmed = text.endsWith('\n')
        ? text.substring(0, text.length - 1)
        : text;
    return '\n'.allMatches(trimmed).length;
  }

  /// `[Pasted text #1 +120 lines]`, or `[Pasted text #1]` for one line.
  @override
  String get reference => switch (extraLines) {
    0 => '[Pasted text #$number]',
    1 => '[Pasted text #$number +1 line]',
    final lines => '[Pasted text #$number +$lines lines]',
  };

  @override
  String get content => text;

  Map<String, Object> toJson() => {'number': number, 'text': text};

  static PastedText fromJson(Map<String, Object?> json) =>
      PastedText(number: json['number'] as int, text: json['text'] as String);

  @override
  bool operator ==(Object other) =>
      other is PastedText && other.number == number && other.text == text;

  @override
  int get hashCode => Object.hash(number, text);
}

/// What the IDE's editor copied last, with where it is from: pasted into the
/// composer while the clipboard still holds it, it goes in as a reference
/// to those lines rather than as their text.
abstract final class CopiedCode {
  static CodeReference? _last;

  /// The editor copied [code], lines [start] to [end] of [path] (absolute).
  static void record({
    required String path,
    required int start,
    required int end,
    required String code,
  }) => _last = CodeReference(path: path, start: start, end: end, code: code);

  /// The copy [text] is, if the editor made it: a copy from elsewhere since
  /// has replaced it on the clipboard otherwise.
  static CodeReference? matching(String text) {
    final last = _last;
    if (last == null || text.isEmpty) return null;
    String normalized(String text) => text.replaceAll('\r\n', '\n');
    return normalized(last.code) == normalized(text) ? last : null;
  }

  @visibleForTesting
  static void clear() => _last = null;
}

/// The code (and long pastes) a message refers to, as it is sent after the
/// message's text: after an empty line, each reference in brackets on a
/// line of its own, then its lines between fences of backticks.
String codeAppendix(Iterable<AppendedText> references) {
  final buffer = StringBuffer();
  for (final reference in references) {
    final fence = _fenceFor(reference.content);
    var code = reference.content.replaceAll('\r\n', '\n');
    if (code.endsWith('\n')) code = code.substring(0, code.length - 1);
    buffer
      ..write('\n\n')
      ..write(reference.reference)
      ..write('\n')
      ..write(fence)
      ..write('\n')
      ..write(code)
      ..write('\n')
      ..write(fence);
  }
  return buffer.toString();
}

/// Three backticks, or one more than the longest run of them in [code], so
/// that no line of it closes the fence.
String _fenceFor(String code) {
  var longest = 0;
  for (final run in RegExp('`+').allMatches(code)) {
    if (run.end - run.start > longest) longest = run.end - run.start;
  }
  return '`' * (longest < 3 ? 3 : longest + 1);
}

/// [text] without the [codeAppendix] at its end, and the references in it
/// by their [CodeReference.reference]. Only blocks whose reference the text
/// before them makes are taken: anything else is the message's own.
({String body, Map<String, AppendedText> references}) splitCodeAppendix(
  String text,
) {
  final found = <AppendedText>[];
  var body = text;
  while (true) {
    final block = _lastBlock(body);
    if (block == null || !block.body.contains(block.reference.reference)) {
      break;
    }
    found.insert(0, block.reference);
    body = block.body;
  }
  return (body: body, references: {for (final r in found) r.reference: r});
}

final _referenceLine = RegExp(r'^\[(.+):(\d+)(?:-(\d+))?\]$');
final _pastedLine = RegExp(r'^\[Pasted text #(\d+)(?: \+\d+ lines?)?\]$');

/// The last block of a [codeAppendix] at the end of [text], and the text
/// before it; null when it does not end in one.
({String body, AppendedText reference})? _lastBlock(String text) {
  final lines = text.split('\n');
  final fence = lines.last;
  if (fence.length < 3 || fence.replaceAll('`', '').isNotEmpty) return null;
  // No line of the code is the fence (see [_fenceFor]).
  final open = lines.lastIndexOf(fence, lines.length - 2);
  // An empty line, the reference, the opening fence.
  if (open < 3 || lines[open - 2].isNotEmpty) return null;
  final header = lines[open - 1];
  final content = lines.sublist(open + 1, lines.length - 1).join('\n');
  final AppendedText reference;
  if (_pastedLine.firstMatch(header) case final match?) {
    reference = PastedText(number: int.parse(match[1]!), text: content);
    // Its count of lines is the text's own.
    if (reference.reference != header) return null;
  } else if (_referenceLine.firstMatch(header) case final match?) {
    final start = int.parse(match[2]!);
    reference = CodeReference(
      path: match[1]!,
      start: start,
      end: match[3] == null ? start : int.parse(match[3]!),
      code: content,
    );
  } else {
    return null;
  }
  return (body: lines.sublist(0, open - 2).join('\n'), reference: reference);
}
