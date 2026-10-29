import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../permissions/decision.dart';
import '../util/ids.dart';
import '../util/json.dart';
import 'diff.dart';
import 'file_state.dart';
import 'tool.dart';

/// What the editing tools share: the path made absolute, the permission
/// to change it, the check that it was read and has not changed since,
/// and the write with its checkpoint and record.
mixin _Editing on Tool {
  String pathKey = 'file_path';

  @override
  String? describe(Map<String, Object?> input) => asString(input[pathKey]);

  @override
  String? ruleContent(Map<String, Object?> input) => asString(input[pathKey]);

  String pathOf(Map<String, Object?> input, ToolContext context) =>
      context.session.permissions.absolute('${input[pathKey]}', context.cwd);

  @override
  Future<PermissionDecision> checkPermissions(
    Map<String, Object?> input,
    ToolContext context,
  ) async => context.session.permissions.checkEdit(
    '${input[pathKey]}',
    context.cwd,
    context.run.permissionMode,
  );

  /// Writes [content] to [path] (as [like] was, or as UTF-8 with `\n`),
  /// kept first for a rewind, and remembered as read.
  Future<void> writeFile(
    String path,
    String content,
    ToolContext context, {
    FileText? like,
  }) async {
    await context.session.checkpoints.track(path);
    final file = File(path);
    file.parent.createSync(recursive: true);
    final encoded = (like ?? const FileText('')).encode(content);
    file.writeAsBytesSync(encoded, flush: true);
    context.run.readFiles[path] = FileRecord(
      content: content,
      modified: file.lastModifiedSync(),
    );
    context.session.fileChanged(path);
  }
}

/// Writes a file whole.
class WriteTool extends Tool with _Editing {
  WriteTool();

  @override
  String get name => 'Write';

  @override
  String get description => '''Puts a whole file on disk: makes it, or puts the content given in place of all it had.

- A file that is already there must have been read with Read first in this conversation, or the write is refused.
- To change part of a file, use Edit: it sends only the change. Write is for new files, or for rewriting one whole.
- Make a new file only when the task needs one. Documentation (README, *.md) only when the user asks for it.
- No emoji in files unless the user wants them.''';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': {
      'file_path': {
        'type': 'string',
        'description': 'Absolute path of the file',
      },
      'content': {
        'type': 'string',
        'description': 'All that the file is to hold',
      },
    },
    'required': ['file_path', 'content'],
    'additionalProperties': false,
  };

  @override
  Future<String?> validate(
    Map<String, Object?> input,
    ToolContext context,
  ) async {
    final path = pathOf(input, context);
    if (FileSystemEntity.isDirectorySync(path)) {
      return '$path is a folder, not a file.';
    }
    if (!File(path).existsSync()) return null;
    return context.run.readFiles.staleness(path);
  }

  @override
  Future<ToolOutput> call(
    Map<String, Object?> input,
    ToolContext context,
  ) async {
    final path = pathOf(input, context);
    final content = '${input['content'] ?? ''}';
    final file = File(path);
    final existed = file.existsSync();
    final before = existed ? readText(file) : null;
    await writeFile(path, content, context, like: before);
    if (before == null) {
      return ToolOutput(
        'Made the file $path.',
        result: {
          'type': 'create',
          'filePath': path,
          'content': content,
          'structuredPatch': <Object?>[],
          'originalFile': null,
          'userModified': false,
        },
      );
    }
    final hunks = diffLines(before.text, content);
    return ToolOutput(
      'Wrote $path. The changed part, as Read numbers it:\n'
      '${_changedSnippet(content, hunks)}',
      result: {
        'type': 'update',
        'filePath': path,
        'content': content,
        'structuredPatch': patchJson(hunks),
        'originalFile': before.text,
        'userModified': false,
      },
    );
  }
}

/// The lines about the first change of [hunks] in [content], numbered.
String _changedSnippet(String content, List<Hunk> hunks) {
  final lines = content.split('\n');
  if (hunks.isEmpty) {
    return numberLines(lines.take(10).toList(), 1);
  }
  final first = hunks.first;
  final last = hunks.last;
  final from = (first.newStart - 1).clamp(0, lines.length);
  final to = (last.newStart - 1 + last.newLines).clamp(from, lines.length);
  // A long one shown in part.
  final end = to - from > 60 ? from + 60 : to;
  return numberLines(lines.sublist(from, end), from + 1);
}

/// One replacement of an edit.
class _Replacement {
  const _Replacement(this.oldString, this.newString, this.replaceAll);

  final String oldString;
  final String newString;
  final bool replaceAll;
}

/// [content] with [edit] made, or what is wrong with it.
(String?, String?) _apply(String content, _Replacement edit) {
  if (edit.oldString == edit.newString) {
    return (
      null,
      'Nothing would change: old_string and new_string are the same.',
    );
  }
  var old = edit.oldString;
  var replacement = edit.newString;
  var count = _count(content, old);
  if (count == 0) {
    // Typographic quotes where the model wrote straight ones, or the other
    // way round: the file's own taken.
    final actual = _findNormalized(content, old);
    if (actual != null) {
      replacement = _matchQuotes(replacement, actual, old);
      old = actual;
      count = _count(content, old);
    }
  }
  if (count == 0) {
    return (
      null,
      'old_string is not in the file. Read it again to see its text as it is now.\n'
          'old_string: ${edit.oldString}',
    );
  }
  if (count > 1 && !edit.replaceAll) {
    return (
      null,
      'old_string is in the file $count times. To change one of them, take '
          'in more of the lines around it until it is found once; to change '
          'them all, set replace_all.\nold_string: ${edit.oldString}',
    );
  }
  if (edit.replaceAll) {
    return (content.replaceAll(old, replacement), null);
  }
  // Deleting a whole line takes its line ending with it.
  if (replacement.isEmpty &&
      !old.endsWith('\n') &&
      content.contains('$old\n')) {
    return (content.replaceFirst('$old\n', ''), null);
  }
  return (content.replaceFirst(old, replacement), null);
}

int _count(String content, String needle) {
  if (needle.isEmpty) return 0;
  var count = 0;
  var at = content.indexOf(needle);
  while (at >= 0) {
    count++;
    at = content.indexOf(needle, at + needle.length);
  }
  return count;
}

String _straight(String text) =>
    text.replaceAll(RegExp('[‘’‛]'), "'").replaceAll(RegExp('[“”‟]'), '"');

/// Where [needle] is in [content] once quotes are made straight in both:
/// the text of [content] there.
String? _findNormalized(String content, String needle) {
  final straightContent = _straight(content);
  final straightNeedle = _straight(needle);
  final at = straightContent.indexOf(straightNeedle);
  if (at < 0) return null;
  // Straightening keeps lengths, so the place is the same.
  return content.substring(at, at + needle.length);
}

/// [replacement] with the typographic quotes [actual] has where [written]
/// had straight ones.
String _matchQuotes(String replacement, String actual, String written) {
  if (!RegExp('[‘’“”]').hasMatch(actual)) return replacement;
  final usesDouble = actual.contains('“') || actual.contains('”');
  final usesSingle = actual.contains('‘') || actual.contains('’');
  final out = StringBuffer();
  var openDouble = true;
  for (var i = 0; i < replacement.length; i++) {
    final c = replacement[i];
    if (c == '"' && usesDouble) {
      out.write(openDouble ? '“' : '”');
      openDouble = !openDouble;
    } else if (c == "'" && usesSingle) {
      final before = i > 0 ? replacement[i - 1] : ' ';
      out.write(RegExp(r'\s|[(\[{]').hasMatch(before) ? '‘' : '’');
    } else {
      out.write(c);
    }
  }
  return out.toString();
}

/// Replaces text in a file.
class EditTool extends Tool with _Editing {
  EditTool();

  @override
  String get name => 'Edit';

  @override
  String get description =>
      '''Changes a file by swapping one exact piece of its text for another.

- Read the file first in this conversation: an edit of a file not read is refused.
- old_string must match the file exactly, its indentation included. A line from Read comes after its number and a tab: what follows the tab is the file's text, and none of the number goes in old_string or new_string.
- old_string must be found once in the file, or the edit fails: take in more of the lines around it until it is, or set replace_all to change every place it is found (to rename something throughout the file, say).
- Change the files that are there rather than making new ones, unless the task needs one.
- No emoji in files unless the user wants them.''';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': {
      'file_path': {
        'type': 'string',
        'description': 'Absolute path of the file',
      },
      'old_string': {
        'type': 'string',
        'description': 'The text there now, exactly',
      },
      'new_string': {
        'type': 'string',
        'description':
            'The text to put in its place (not the same as old_string)',
      },
      'replace_all': {
        'type': 'boolean',
        'default': false,
        'description': 'Change every place old_string is found, not just one',
      },
    },
    'required': ['file_path', 'old_string', 'new_string'],
    'additionalProperties': false,
  };

  @override
  Future<String?> validate(
    Map<String, Object?> input,
    ToolContext context,
  ) async {
    final path = pathOf(input, context);
    final old = '${input['old_string'] ?? ''}';
    final file = File(path);
    if (p.extension(path) == '.ipynb') {
      return 'This is a Jupyter notebook: change it with NotebookEdit.';
    }
    if (!file.existsSync()) {
      // An empty old_string makes the file.
      if (old.isEmpty) return null;
      return 'No file is there. To make one, give an empty old_string.';
    }
    if (old.isEmpty) {
      if (readText(file).text.trim().isEmpty) return null;
      return 'The file is already there, and not empty: an empty old_string '
          'only makes a new file.';
    }
    return context.run.readFiles.staleness(path);
  }

  @override
  Future<ToolOutput> call(
    Map<String, Object?> input,
    ToolContext context,
  ) async {
    final path = pathOf(input, context);
    final old = '${input['old_string'] ?? ''}';
    final replacement = '${input['new_string'] ?? ''}';
    final replaceAll = input['replace_all'] == true;
    final file = File(path);
    final before = file.existsSync() ? readText(file) : null;
    final original = before?.text ?? '';
    String updated;
    if (old.isEmpty) {
      updated = replacement;
    } else {
      final (result, error) = _apply(
        original,
        _Replacement(old, replacement, replaceAll),
      );
      if (error != null) return ToolOutput.error(error);
      updated = result!;
    }
    await writeFile(path, updated, context, like: before);
    final hunks = diffLines(original, updated);
    return ToolOutput(
      'Changed $path. The part around the change, as Read numbers it:\n'
      '${replaceAll ? _changedSnippet(updated, hunks) : snippetAround(updated, replacement)}',
      result: {
        'filePath': path,
        'oldString': old,
        'newString': replacement,
        'originalFile': before == null ? null : original,
        'structuredPatch': patchJson(hunks),
        'userModified': false,
        'replaceAll': replaceAll,
      },
    );
  }
}

/// Changes a cell of a Jupyter notebook.
class NotebookEditTool extends Tool with _Editing {
  NotebookEditTool() {
    pathKey = 'notebook_path';
  }

  @override
  String get name => 'NotebookEdit';

  @override
  String get description =>
      'Changes one cell of a Jupyter notebook (.ipynb): gives it new '
      'source, adds a cell after it, or takes it out. Give the notebook by '
      'its absolute path and the cell by the ID Read shows for it. With '
      'edit_mode insert, the new cell goes after cell_id, or first when no '
      'cell_id is given; with delete, the cell is taken out.';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': {
      'notebook_path': {
        'type': 'string',
        'description': 'Absolute path of the notebook',
      },
      'cell_id': {
        'type': 'string',
        'description': 'The cell, by the ID Read shows; for insert, the cell the new one follows (none: it goes first)',
      },
      'new_source': {
        'type': 'string',
        'description': 'The cell\'s source from now on',
      },
      'cell_type': {
        'type': 'string',
        'enum': ['code', 'markdown'],
        'description':
            'code or markdown: needed for insert, else the cell keeps its own',
      },
      'edit_mode': {
        'type': 'string',
        'enum': ['replace', 'insert', 'delete'],
        'description':
            'replace (the default) its source, insert a new cell, or delete it',
      },
    },
    'required': ['notebook_path', 'new_source'],
    'additionalProperties': false,
  };

  @override
  Future<String?> validate(
    Map<String, Object?> input,
    ToolContext context,
  ) async {
    final path = pathOf(input, context);
    if (p.extension(path) != '.ipynb') {
      return 'NotebookEdit changes only Jupyter notebooks (.ipynb): change '
          'other files with Edit.';
    }
    if (!File(path).existsSync()) return 'No notebook is there.';
    final mode = asString(input['edit_mode']) ?? 'replace';
    if (mode == 'insert' && input['cell_type'] == null) {
      return 'Give cell_type for a cell to insert.';
    }
    return context.run.readFiles.staleness(path);
  }

  @override
  Future<ToolOutput> call(
    Map<String, Object?> input,
    ToolContext context,
  ) async {
    final path = pathOf(input, context);
    final file = File(path);
    final before = readText(file);
    final Map<String, Object?> notebook;
    try {
      notebook = {...asMap(jsonDecode(before.text))};
    } on FormatException {
      return ToolOutput.error('The notebook is not valid JSON.');
    }
    final cells = [
      for (final cell in asList(notebook['cells'])) {...asMap(cell)},
    ];
    final mode = asString(input['edit_mode']) ?? 'replace';
    final cellId = asString(input['cell_id']);
    final source = '${input['new_source'] ?? ''}';
    var index = cellId == null
        ? -1
        : cells.indexWhere((cell) => cell['id'] == cellId);
    if (index < 0 && cellId != null) {
      // `cell-3`, as the Read tool names cells without ids.
      final numbered = RegExp(r'^cell-(\d+)$').firstMatch(cellId);
      if (numbered != null) index = int.parse(numbered[1]!);
      if (index >= cells.length) index = -1;
    }
    if (index < 0 && (mode != 'insert' || cellId != null)) {
      return ToolOutput.error('The notebook has no cell "$cellId".');
    }
    final language =
        asString(asMap(asMap(notebook['metadata'])['language_info'])['name']) ??
        'python';
    String oldSource = '';
    String cellType = asString(input['cell_type']) ?? 'code';
    String? newId = cellId;
    List<String> lines(String text) {
      final parts = text.split('\n');
      return [
        for (final (i, part) in parts.indexed)
          i < parts.length - 1 ? '$part\n' : part,
      ]..removeWhere((line) => line.isEmpty);
    }

    switch (mode) {
      case 'delete':
        oldSource = _joined(cells[index]['source']);
        cells.removeAt(index);
      case 'insert':
        newId = _newCellId();
        final cell = <String, Object?>{
          'cell_type': cellType,
          'id': newId,
          'metadata': <String, Object?>{},
          'source': lines(source),
          if (cellType == 'code') ...{
            'execution_count': null,
            'outputs': <Object?>[],
          },
        };
        cells.insert(index + 1, cell);
      default:
        final cell = cells[index];
        oldSource = _joined(cell['source']);
        cellType =
            asString(input['cell_type']) ??
            asString(cell['cell_type']) ??
            'code';
        cell['source'] = lines(source);
        cell['cell_type'] = cellType;
        if (cellType == 'code') {
          cell['execution_count'] = null;
          cell['outputs'] = <Object?>[];
        } else {
          cell.remove('execution_count');
          cell.remove('outputs');
        }
    }
    notebook['cells'] = cells;
    final updated = '${const JsonEncoder.withIndent(' ').convert(notebook)}\n';
    await writeFile(path, updated, context, like: before);
    final said = switch (mode) {
      'delete' => 'Deleted cell $cellId',
      'insert' => 'Inserted cell $newId',
      _ => 'Updated cell $cellId with $source',
    };
    return ToolOutput(
      said,
      result: {
        'new_source': source,
        'old_source': oldSource,
        'cell_id': newId,
        'cell_type': cellType,
        'language': language,
        'edit_mode': mode,
        'error': '',
        'notebook_path': path,
        'original_file': before.text,
        'updated_file': updated,
      },
    );
  }

  static String _joined(Object? source) => switch (source) {
    final String text => text,
    final List<Object?> parts => parts.join(),
    _ => '',
  };

  static String _newCellId() => randomId(8);
}
