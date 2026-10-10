/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Problem matchers: the patterns that find problems in a task's output, the
// matchers built of them (tasks.json's and the extensions'
// `problemMatchers`/`problemPatterns` contributions), the named ones by
// `$name`, and the line matchers that turn output lines into markers.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/contrib/tasks/common/problemMatcher.ts.
//
// Deviations: the registries are instances fed with the extensions'
// contributions instead of extension points; the parser's messages go to a
// list instead of an extension's message collector.

import 'dart:io' show Directory, File, FileSystemEntityType, Platform;

import 'package:bao_exthost/bao_exthost.dart';
import 'package:path/path.dart' as p;

import '../language/marker_service.dart';

/// `FileLocationKind`.
enum FileLocationKind {
  defaultKind,
  relative,
  absolute,
  autoDetect,
  search;

  static FileLocationKind? fromString(String value) =>
      switch (value.toLowerCase()) {
        'absolute' => absolute,
        'relative' => relative,
        'autodetect' => autoDetect,
        'search' => search,
        _ => null,
      };
}

/// `ProblemLocationKind`.
enum ProblemLocationKind {
  file,
  location;

  static ProblemLocationKind? fromString(String value) =>
      switch (value.toLowerCase()) {
        'file' => file,
        'location' => location,
        _ => null,
      };
}

/// `ApplyToKind`.
enum ApplyToKind {
  allDocuments,
  openDocuments,
  closedDocuments;

  static ApplyToKind? fromString(String value) => switch (value.toLowerCase()) {
    'alldocuments' => allDocuments,
    'opendocuments' => openDocuments,
    'closeddocuments' => closedDocuments,
    _ => null,
  };
}

/// `Severity` as problem matchers use it.
enum ProblemSeverity {
  ignore,
  info,
  warning,
  error;

  /// `Severity.fromValue`.
  static ProblemSeverity fromValue(String? value) =>
      switch (value?.toLowerCase()) {
        'error' => error,
        'warning' || 'warn' => warning,
        'info' => info,
        _ => ignore,
      };

  /// `MarkerSeverity.fromSeverity`.
  MarkerSeverity get marker => switch (this) {
    error => MarkerSeverity.error,
    warning => MarkerSeverity.warning,
    info => MarkerSeverity.info,
    ignore => MarkerSeverity.hint,
  };
}

/// `IProblemPattern`.
final class ProblemPattern {
  ProblemPattern(
    this.regexp, {
    this.kind,
    this.file,
    this.message,
    this.location,
    this.line,
    this.character,
    this.endLine,
    this.endCharacter,
    this.code,
    this.severity,
    this.loop,
  });

  final RegExp regexp;
  ProblemLocationKind? kind;
  int? file;
  int? message;
  int? location;
  int? line;
  int? character;
  int? endLine;
  int? endCharacter;
  int? code;
  int? severity;
  bool? loop;

  ProblemPattern copy() => ProblemPattern(
    regexp,
    kind: kind,
    file: file,
    message: message,
    location: location,
    line: line,
    character: character,
    endLine: endLine,
    endCharacter: endCharacter,
    code: code,
    severity: severity,
    loop: loop,
  );
}

/// `IWatchingPattern`.
final class WatchingPattern {
  const WatchingPattern(this.regexp, {this.file});

  final RegExp regexp;
  final int? file;
}

/// `IWatchingMatcher`.
final class WatchingMatcher {
  const WatchingMatcher({
    required this.activeOnStart,
    required this.beginsPattern,
    required this.endsPattern,
  });

  final bool activeOnStart;
  final WatchingPattern beginsPattern;
  final WatchingPattern endsPattern;
}

/// `Config.SearchFileLocationArgs`.
final class SearchFileLocationArgs {
  const SearchFileLocationArgs({
    this.include = const [],
    this.exclude = const [],
  });

  final List<String> include;
  final List<String> exclude;
}

/// `ProblemMatcher` (`INamedProblemMatcher` when [name] is set).
final class ProblemMatcher {
  ProblemMatcher({
    required this.owner,
    required this.applyTo,
    required this.fileLocation,
    required this.pattern,
    this.source,
    this.filePrefix,
    this.severity,
    this.watching,
    this.uriProvider,
    this.name,
    this.label,
    this.deprecated = false,
  });

  String owner;
  String? source;
  ApplyToKind applyTo;
  FileLocationKind fileLocation;

  /// A path (`String`) or [SearchFileLocationArgs].
  Object? filePrefix;

  /// One [ProblemPattern] or a list (`MultiLineProblemPattern`).
  Object pattern;
  ProblemSeverity? severity;
  WatchingMatcher? watching;
  VsUri Function(String path)? uriProvider;
  String? name;
  String? label;
  bool deprecated;

  /// The tsc watch matcher (`tscWatch`), for the background task's start.
  bool tscWatch = false;

  ProblemMatcher copy() => ProblemMatcher(
    owner: owner,
    applyTo: applyTo,
    fileLocation: fileLocation,
    pattern: switch (pattern) {
      final List<ProblemPattern> patterns => [
        for (final p in patterns) p.copy(),
      ],
      final ProblemPattern pattern => pattern.copy(),
      final other => other,
    },
    source: source,
    filePrefix: filePrefix,
    severity: severity,
    watching: watching,
    uriProvider: uriProvider,
    name: name,
    label: label,
    deprecated: deprecated,
  )..tscWatch = tscWatch;
}

/// `IProblemData`.
final class _ProblemData {
  ProblemLocationKind? kind;
  String? file;
  String? location;
  String? line;
  String? character;
  String? endLine;
  String? endCharacter;
  String? message;
  String? severity;
  String? code;

  _ProblemData copy() => _ProblemData()
    ..kind = kind
    ..file = file
    ..location = location
    ..line = line
    ..character = character
    ..endLine = endLine
    ..endCharacter = endCharacter
    ..message = message
    ..severity = severity
    ..code = code;
}

/// `IProblemMatch`.
final class ProblemMatch {
  const ProblemMatch({
    required this.resource,
    required this.marker,
    required this.description,
  });

  final Future<VsUri> resource;
  final MarkerData marker;
  final ProblemMatcher description;
}

/// `IHandleResult`.
typedef HandleResult = ({ProblemMatch? match, bool continues});

/// Whether a path is a file, for `autoDetect` and `search` locations.
typedef ProblemFileSystem = ({
  Future<bool> Function(VsUri uri) exists,
  Future<List<(String, bool)>> Function(VsUri dir) readDirectory,
});

/// The local disk.
final ProblemFileSystem localProblemFileSystem = (
  exists: (uri) async {
    final path = uri.fsPath();
    return File(path).existsSync() || Directory(path).existsSync();
  },
  readDirectory: (dir) async => [
    for (final entity in Directory(dir.fsPath()).listSync(followLinks: false))
      (
        p.basename(entity.path),
        entity.statSync().type == FileSystemEntityType.directory,
      ),
  ],
);

/// `getResource`.
Future<VsUri> getProblemResource(
  String filename,
  ProblemMatcher matcher, [
  ProblemFileSystem? files,
]) async {
  final kind = matcher.fileLocation;
  String? fullPath;
  if (kind == FileLocationKind.absolute) {
    fullPath = filename;
  } else if (kind == FileLocationKind.relative &&
      matcher.filePrefix is String) {
    fullPath = p.posix.join(
      (matcher.filePrefix! as String).replaceAll(r'\', '/'),
      filename,
    );
  } else if (kind == FileLocationKind.autoDetect) {
    final clone = matcher.copy()..fileLocation = FileLocationKind.relative;
    if (files != null) {
      final relative = await getProblemResource(filename, clone);
      var exists = false;
      try {
        exists = await files.exists(relative);
      } on Object {
        // Do nothing, we just need to catch file resolution errors.
      }
      if (exists) return relative;
    }
    clone.fileLocation = FileLocationKind.absolute;
    return getProblemResource(filename, clone);
  } else if (kind == FileLocationKind.search && files != null) {
    final args = matcher.filePrefix is SearchFileLocationArgs
        ? matcher.filePrefix! as SearchFileLocationArgs
        : const SearchFileLocationArgs();
    fullPath = (await _searchForFileLocation(filename, files, args))?.path;
    if (fullPath == null) {
      final absolute = matcher.copy()..fileLocation = FileLocationKind.absolute;
      return getProblemResource(filename, absolute);
    }
  }
  if (fullPath == null) {
    throw StateError(
      'FileLocationKind is not actionable. Does the matcher have a '
      'filePrefix? This should never happen.',
    );
  }
  fullPath = p.posix.normalize(fullPath.replaceAll(r'\', '/'));
  if (!fullPath.startsWith('/')) fullPath = '/$fullPath';
  if (matcher.uriProvider case final provider?) return provider(fullPath);
  return VsUri.file(fullPath);
}

Future<VsUri?> _searchForFileLocation(
  String filename,
  ProblemFileSystem files,
  SearchFileLocationArgs args,
) async {
  final exclusions = {for (final x in args.exclude) VsUri.file(x).path};
  Future<VsUri?> search(VsUri dir) async {
    if (exclusions.contains(dir.path)) return null;
    final subdirs = <VsUri>[];
    for (final (name, isDirectory) in await files.readDirectory(dir)) {
      final child = dir.joinPath([name]);
      if (isDirectory) {
        subdirs.add(child);
      } else if (child.path.endsWith(filename)) {
        // `filename` may be a relative path, not just the name.
        return child;
      }
    }
    for (final subdir in subdirs) {
      if (await search(subdir) case final hit?) return hit;
    }
    return null;
  }

  for (final dir in args.include) {
    try {
      if (await search(VsUri.file(dir)) case final hit?) return hit;
    } on Object {
      // An unreadable directory has nothing.
    }
  }
  return null;
}

/// `ILineMatcher`.
abstract base class LineMatcher {
  LineMatcher(this.matcher, this.files);

  final ProblemMatcher matcher;
  final ProblemFileSystem? files;

  int get matchLength;

  ProblemMatch? next(String line) => null;

  HandleResult handle(List<String> lines, [int start = 0]);

  static final _endOfLine = Platform.isWindows ? '\r\n' : '\n';

  static String? _group(RegExpMatch matches, int? index) =>
      index != null && index <= matches.groupCount
      ? matches.group(index)
      : null;

  bool _fillProblemData(
    _ProblemData? data,
    ProblemPattern pattern,
    RegExpMatch matches,
  ) {
    if (data == null) return false;
    data.file ??= _group(matches, pattern.file)?.trim();
    _appendMessage(data, pattern, matches);
    data.code ??= _group(matches, pattern.code)?.trim();
    data.severity ??= _group(matches, pattern.severity)?.trim();
    data.location ??= _group(matches, pattern.location)?.trim();
    data.line ??= _group(matches, pattern.line);
    data.character ??= _group(matches, pattern.character);
    data.endLine ??= _group(matches, pattern.endLine);
    data.endCharacter ??= _group(matches, pattern.endCharacter);
    return true;
  }

  void _appendMessage(
    _ProblemData data,
    ProblemPattern pattern,
    RegExpMatch matches,
  ) {
    if (data.message == null) {
      data.message = _group(matches, pattern.message)?.trim();
    } else if (pattern.message != null &&
        pattern.message! <= matches.groupCount) {
      data.message =
          '${data.message}$_endOfLine${(matches.group(pattern.message!) ?? 'undefined').trim()}';
    }
  }

  ProblemMatch? _markerMatch(_ProblemData data) {
    try {
      final location = _location(data);
      final file = data.file;
      final message = data.message;
      if (file != null && location != null && message != null) {
        return ProblemMatch(
          description: matcher,
          resource: getProblemResource(file, matcher, files),
          marker: MarkerData(
            severity: _severity(data),
            startLineNumber: location.$1,
            startColumn: location.$2,
            endLineNumber: location.$3,
            endColumn: location.$4,
            message: message,
            code: data.code == null ? null : MarkerCode(data.code!),
            source: matcher.source,
          ),
        );
      }
    } on Object {
      // Failed to convert problem data into a match.
    }
    return null;
  }

  static int _parseInt(String value) =>
      int.tryParse(RegExp(r'^\s*[-+]?\d+').stringMatch(value)?.trim() ?? '') ??
      0;

  (int, int, int, int)? _location(_ProblemData data) {
    if (data.kind == ProblemLocationKind.file) {
      return _createLocation(0, 0, 0, 0);
    }
    if (data.location case final location?) return _parseLocationInfo(location);
    final line = data.line;
    if (line == null || line.isEmpty) return null;
    return _createLocation(
      _parseInt(line),
      data.character?.isNotEmpty ?? false ? _parseInt(data.character!) : null,
      data.endLine?.isNotEmpty ?? false ? _parseInt(data.endLine!) : null,
      data.endCharacter?.isNotEmpty ?? false
          ? _parseInt(data.endCharacter!)
          : null,
    );
  }

  (int, int, int, int)? _parseLocationInfo(String value) {
    if (value.isEmpty ||
        !RegExp(r'(\d+|\d+,\d+|\d+,\d+,\d+,\d+)').hasMatch(value)) {
      return null;
    }
    final parts = value.split(',');
    final startLine = _parseInt(parts[0]);
    final startColumn = parts.length > 1 ? _parseInt(parts[1]) : null;
    if (parts.length > 3) {
      return _createLocation(
        startLine,
        startColumn,
        _parseInt(parts[2]),
        _parseInt(parts[3]),
      );
    }
    return _createLocation(startLine, startColumn, null, null);
  }

  static (int, int, int, int) _createLocation(
    int startLine,
    int? startColumn,
    int? endLine,
    int? endColumn,
  ) {
    if (startColumn != null && endColumn != null) {
      return (
        startLine,
        startColumn,
        endLine == null || endLine == 0 ? startLine : endLine,
        endColumn,
      );
    }
    if (startColumn != null) {
      return (startLine, startColumn, startLine, startColumn);
    }
    // microsoft/vscode#80288: to the end of the line.
    return (startLine, 1, startLine, 2147483647);
  }

  MarkerSeverity _severity(_ProblemData data) {
    ProblemSeverity? result;
    if (data.severity case final value? when value.isNotEmpty) {
      result = ProblemSeverity.fromValue(value);
      if (result == ProblemSeverity.ignore) {
        if (value == 'E') {
          result = ProblemSeverity.error;
        } else if (value == 'W') {
          result = ProblemSeverity.warning;
        } else if (value == 'I') {
          result = ProblemSeverity.info;
        } else if (value.toLowerCase() == 'hint' ||
            value.toLowerCase() == 'note') {
          result = ProblemSeverity.info;
        }
      }
    }
    if (result == null || result == ProblemSeverity.ignore) {
      result = matcher.severity ?? ProblemSeverity.error;
      if (result == ProblemSeverity.ignore) result = ProblemSeverity.error;
    }
    return result.marker;
  }
}

/// `createLineMatcher`.
LineMatcher createLineMatcher(
  ProblemMatcher matcher, [
  ProblemFileSystem? files,
]) => matcher.pattern is List
    ? _MultiLineMatcher(matcher, files)
    : _SingleLineMatcher(matcher, files);

final class _SingleLineMatcher extends LineMatcher {
  _SingleLineMatcher(super.matcher, super.files)
    : _pattern = matcher.pattern as ProblemPattern;

  final ProblemPattern _pattern;

  @override
  int get matchLength => 1;

  @override
  HandleResult handle(List<String> lines, [int start = 0]) {
    assert(lines.length - start == 1);
    final data = _ProblemData()..kind = _pattern.kind;
    final matches = _pattern.regexp.firstMatch(lines[start]);
    if (matches != null) {
      _fillProblemData(data, _pattern, matches);
      if (data.kind == ProblemLocationKind.location &&
          data.location == null &&
          data.line == null &&
          data.file != null) {
        data.kind = ProblemLocationKind.file;
      }
      if (_markerMatch(data) case final match?) {
        return (match: match, continues: false);
      }
    }
    return (match: null, continues: false);
  }
}

final class _MultiLineMatcher extends LineMatcher {
  _MultiLineMatcher(super.matcher, super.files)
    : _patterns = (matcher.pattern as List).cast<ProblemPattern>();

  final List<ProblemPattern> _patterns;
  _ProblemData? _data;

  @override
  int get matchLength => _patterns.length;

  @override
  HandleResult handle(List<String> lines, [int start = 0]) {
    assert(lines.length - start == _patterns.length);
    _data = _ProblemData()..kind = _patterns.first.kind;
    var data = _data!;
    for (var i = 0; i < _patterns.length; i++) {
      final pattern = _patterns[i];
      final matches = pattern.regexp.firstMatch(lines[i + start]);
      if (matches == null) return (match: null, continues: false);
      // Only the last pattern can loop.
      if ((pattern.loop ?? false) && i == _patterns.length - 1) {
        data = data.copy();
      }
      _fillProblemData(data, pattern, matches);
    }
    final loop = _patterns.last.loop ?? false;
    if (!loop) _data = null;
    return (match: _markerMatch(data), continues: loop);
  }

  @override
  ProblemMatch? next(String line) {
    final pattern = _patterns.last;
    assert((pattern.loop ?? false) && _data != null);
    final matches = pattern.regexp.firstMatch(line);
    if (matches == null) {
      _data = null;
      return null;
    }
    final data = _data?.copy();
    if (_fillProblemData(data, pattern, matches)) return _markerMatch(data!);
    return null;
  }
}

/// `IProblemReporter`, collecting the parser's messages.
final class ProblemReporter {
  final infos = <String>[];
  final warnings = <String>[];
  final errors = <String>[];

  bool get hasErrors => errors.isNotEmpty;

  void reset() {
    infos.clear();
    warnings.clear();
    errors.clear();
  }
}

RegExp? _regExp(Object? value, ProblemReporter reporter) {
  if (value is! String || value.isEmpty) return null;
  try {
    return RegExp(value);
  } on FormatException {
    reporter.errors.add(
      'Error: The string $value is not a valid regular expression.\n',
    );
    return null;
  }
}

/// `ProblemPatternParser`.
final class ProblemPatternParser {
  ProblemPatternParser(this.reporter);

  final ProblemReporter reporter;

  static bool _isChecked(Object? value) =>
      value is Map && value['regexp'] is String;

  static bool _isMultiLineChecked(Object? value) =>
      value is List && value.every(_isChecked);

  static bool isNamedMultiLine(Object? value) =>
      value is Map &&
      value['name'] is String &&
      value['patterns'] is List &&
      _isMultiLineChecked(value['patterns']);

  static bool isNamed(Object? value) => value is Map && value['name'] is String;

  /// A [ProblemPattern], a list of them, or null (the error reported).
  Object? parse(Object? value) {
    if (isNamedMultiLine(value)) {
      return _createMultiLine((value! as Map)['patterns'] as List);
    } else if (_isMultiLineChecked(value)) {
      return _createMultiLine(value! as List);
    } else if (_isChecked(value)) {
      return _createSingle(value! as Map);
    }
    reporter.errors.add('The problem pattern is missing a regular expression.');
    return null;
  }

  ProblemPattern? _createSingle(Map value) {
    final result = _doCreateSingle(value, setDefaults: true);
    if (result == null) return null;
    result.kind ??= ProblemLocationKind.location;
    return _validate([result]) ? result : null;
  }

  List<ProblemPattern>? _createMultiLine(List values) {
    final result = <ProblemPattern>[];
    for (var i = 0; i < values.length; i++) {
      final pattern = _doCreateSingle(values[i] as Map, setDefaults: false);
      if (pattern == null) return null;
      if (i < values.length - 1 && (pattern.loop ?? false)) {
        pattern.loop = false;
        reporter.errors.add(
          'The loop property is only supported on the last line matcher.',
        );
      }
      result.add(pattern);
    }
    if (result.isEmpty) {
      reporter.errors.add(
        'The problem pattern is invalid. It must contain at least one '
        'pattern.',
      );
      return null;
    }
    result.first.kind ??= ProblemLocationKind.location;
    return _validate(result) ? result : null;
  }

  ProblemPattern? _doCreateSingle(Map value, {required bool setDefaults}) {
    final regexp = _regExp(value['regexp'], reporter);
    if (regexp == null) return null;
    int? number(String key) => switch (value[key]) {
      final num n => n.toInt(),
      _ => null,
    };
    final kind = value['kind'];
    final result = ProblemPattern(
      regexp,
      kind: kind is String && kind.isNotEmpty
          ? ProblemLocationKind.fromString(kind)
          : null,
      file: number('file'),
      location: number('location'),
      line: number('line'),
      character: number('column'),
      endLine: number('endLine'),
      endCharacter: number('endColumn'),
      severity: number('severity'),
      code: number('code'),
      message: number('message'),
      loop: value['loop'] is bool ? value['loop'] as bool : null,
    );
    if (setDefaults) {
      if ((result.location ?? 0) != 0 ||
          result.kind == ProblemLocationKind.file) {
        result
          ..file ??= 1
          ..message ??= 0;
      } else {
        result
          ..file ??= 1
          ..line ??= 2
          ..character ??= 3
          ..message ??= 0;
      }
    }
    return result;
  }

  bool _validate(List<ProblemPattern> values) {
    var file = false, message = false, location = false, line = false;
    final locationKind = values.first.kind ?? ProblemLocationKind.location;
    for (final (i, pattern) in values.indexed) {
      if (i != 0 && pattern.kind != null) {
        reporter.errors.add(
          'The problem pattern is invalid. The kind property must be '
          'provided only in the first element',
        );
      }
      file = file || pattern.file != null;
      message = message || pattern.message != null;
      location = location || pattern.location != null;
      line = line || pattern.line != null;
    }
    if (!(file && message)) {
      reporter.errors.add(
        'The problem pattern is invalid. It must have at least have a file '
        'and a message.',
      );
      return false;
    }
    if (locationKind == ProblemLocationKind.location && !(location || line)) {
      reporter.errors.add(
        'The problem pattern is invalid. It must either have kind: "file" '
        'or have a line or location match group.',
      );
      return false;
    }
    return true;
  }
}

/// `ProblemPatternRegistry`: the named patterns (`$name`).
final class ProblemPatternRegistry {
  ProblemPatternRegistry() {
    _fillDefaults();
  }

  final _patterns = <String, Object>{};

  /// A [ProblemPattern] or a list of them.
  Object? get(String key) => _patterns[key];

  void add(String key, Object value) => _patterns[key] = value;

  /// The `problemPatterns` contributions of extensions, in place of those
  /// of the last call (built-in ones stay).
  void setContributions(List<Object?> contributions, {List<String>? errors}) {
    _patterns
      ..clear()
      ..addAll(_defaults);
    for (final pattern in contributions) {
      final reporter = ProblemReporter();
      final parser = ProblemPatternParser(reporter);
      if (ProblemPatternParser.isNamedMultiLine(pattern) ||
          ProblemPatternParser.isNamed(pattern)) {
        final result = parser.parse(pattern);
        if (!reporter.hasErrors && result != null) {
          add((pattern! as Map)['name'] as String, result);
        } else {
          errors?.add('Invalid problem pattern. The pattern will be ignored.');
        }
      }
    }
  }

  late final Map<String, Object> _defaults;

  void _fillDefaults() {
    add(
      'msCompile',
      ProblemPattern(
        RegExp(
          r'^\s*(?:\s*\d+>)?(\S.*?)(?:\((\d+|\d+,\d+|\d+,\d+,\d+,\d+)\))?\s*:\s+(?:(\S+)\s+)?((?:fatal +)?error|warning|info)\s+(\w+\d+)?\s*:\s*(.*)$',
        ),
        kind: ProblemLocationKind.location,
        file: 1,
        location: 2,
        severity: 4,
        code: 5,
        message: 6,
      ),
    );
    add(
      'gulp-tsc',
      ProblemPattern(
        RegExp(r'^([^\s].*)\((\d+|\d+,\d+|\d+,\d+,\d+,\d+)\):\s+(\d+)\s+(.*)$'),
        kind: ProblemLocationKind.location,
        file: 1,
        location: 2,
        code: 3,
        message: 4,
      ),
    );
    for (final (name, code) in [('cpp', 'C'), ('csc', 'CS'), ('vb', 'BC')]) {
      add(
        name,
        ProblemPattern(
          RegExp(
            '^(\\S.*)\\((\\d+|\\d+,\\d+|\\d+,\\d+,\\d+,\\d+)\\):\\s+(error|warning|info)\\s+($code\\d+)\\s*:\\s*(.*)\$',
          ),
          kind: ProblemLocationKind.location,
          file: 1,
          location: 2,
          severity: 3,
          code: 4,
          message: 5,
        ),
      );
    }
    add(
      'lessCompile',
      ProblemPattern(
        RegExp(r'^\s*(.*) in file (.*) line no. (\d+)$'),
        kind: ProblemLocationKind.location,
        message: 1,
        file: 2,
        line: 3,
      ),
    );
    add(
      'jshint',
      ProblemPattern(
        RegExp(
          r'^(.*):\s+line\s+(\d+),\s+col\s+(\d+),\s(.+?)(?:\s+\((\w)(\d+)\))?$',
        ),
        kind: ProblemLocationKind.location,
        file: 1,
        line: 2,
        character: 3,
        message: 4,
        severity: 5,
        code: 6,
      ),
    );
    add('jshint-stylish', [
      ProblemPattern(
        RegExp(r'^(.+)$'),
        kind: ProblemLocationKind.location,
        file: 1,
      ),
      ProblemPattern(
        RegExp(r'^\s+line\s+(\d+)\s+col\s+(\d+)\s+(.+?)(?:\s+\((\w)(\d+)\))?$'),
        line: 1,
        character: 2,
        message: 3,
        severity: 4,
        code: 5,
        loop: true,
      ),
    ]);
    add(
      'eslint-compact',
      ProblemPattern(
        RegExp(
          r'^(.+):\sline\s(\d+),\scol\s(\d+),\s(Error|Warning|Info)\s-\s(.+)\s\((.+)\)$',
        ),
        file: 1,
        kind: ProblemLocationKind.location,
        line: 2,
        character: 3,
        severity: 4,
        message: 5,
        code: 6,
      ),
    );
    add('eslint-stylish', [
      ProblemPattern(
        RegExp(r'^((?:[a-zA-Z]:)*[./\\]+.*?)$'),
        kind: ProblemLocationKind.location,
        file: 1,
      ),
      ProblemPattern(
        RegExp(
          r'^\s+(\d+):(\d+)\s+(error|warning|info)\s+(.+?)(?:\s\s+(.*))?$',
        ),
        line: 1,
        character: 2,
        severity: 3,
        message: 4,
        code: 5,
        loop: true,
      ),
    ]);
    add(
      'go',
      ProblemPattern(
        RegExp(r'^([^:]*: )?((.:)?[^:]*):(\d+)(:(\d+))?: (.*)$'),
        kind: ProblemLocationKind.location,
        file: 2,
        line: 4,
        character: 6,
        message: 7,
      ),
    );
    _defaults = Map.of(_patterns);
  }
}

/// `ProblemMatcherParser`.
final class ProblemMatcherParser {
  ProblemMatcherParser(this.reporter, this.patterns, this.matchers);

  final ProblemReporter reporter;
  final ProblemPatternRegistry patterns;

  /// For `base`.
  final ProblemMatcherRegistry matchers;

  static var _ownerCount = 0;

  ProblemMatcher? parse(Map json) {
    final result = _create(json);
    if (!_checkValid(json, result)) return null;
    _addWatchingMatcher(json, result!);
    return result;
  }

  bool _checkValid(Map json, ProblemMatcher? matcher) {
    if (matcher == null) {
      reporter.errors.add(
        "Error: the description can't be converted into a problem matcher",
      );
      return false;
    }
    return true;
  }

  ProblemMatcher? _create(Map description) {
    ProblemMatcher? result;
    final owner = description['owner'] is String
        ? description['owner'] as String
        : 'problemMatcher${_ownerCount++}';
    final source = description['source'] is String
        ? description['source'] as String
        : null;
    final applyTo = description['applyTo'] is String
        ? ApplyToKind.fromString(description['applyTo'] as String) ??
              ApplyToKind.allDocuments
        : ApplyToKind.allDocuments;
    FileLocationKind? fileLocation;
    Object? filePrefix;
    final location = description['fileLocation'];
    if (location == null) {
      fileLocation = FileLocationKind.relative;
      filePrefix = r'${workspaceFolder}';
    } else if (location is String) {
      final kind = FileLocationKind.fromString(location);
      if (kind != null) {
        fileLocation = kind;
        if (kind == FileLocationKind.relative ||
            kind == FileLocationKind.autoDetect) {
          filePrefix = r'${workspaceFolder}';
        } else if (kind == FileLocationKind.search) {
          filePrefix = const SearchFileLocationArgs(
            include: [r'${workspaceFolder}'],
          );
        }
      }
    } else if (location is List && location.every((e) => e is String)) {
      if (location.isNotEmpty) {
        final kind = FileLocationKind.fromString(location[0] as String);
        if (location.length == 1 && kind == FileLocationKind.absolute) {
          fileLocation = kind;
        } else if (location.length == 2 &&
            (kind == FileLocationKind.relative ||
                kind == FileLocationKind.autoDetect) &&
            (location[1] as String).isNotEmpty) {
          fileLocation = kind;
          filePrefix = location[1];
        }
      }
    } else if (location is List && location.isNotEmpty) {
      if (location[0] is String &&
          FileLocationKind.fromString(location[0] as String) ==
              FileLocationKind.search) {
        fileLocation = FileLocationKind.search;
        final args = location.length > 1 ? location[1] : null;
        filePrefix = args is Map
            ? SearchFileLocationArgs(
                include: _strings(args['include']),
                exclude: _strings(args['exclude']),
              )
            : const SearchFileLocationArgs(include: [r'${workspaceFolder}']);
      }
    }

    final pattern = description['pattern'] != null
        ? _createPattern(description['pattern'])
        : null;

    ProblemSeverity? severity;
    if (description['severity'] case final String value when value.isNotEmpty) {
      severity = ProblemSeverity.fromValue(value);
      if (severity == ProblemSeverity.ignore) {
        reporter.infos.add(
          'Info: unknown severity $value. Valid values are error, warning '
          'and info.\n',
        );
        severity = ProblemSeverity.error;
      }
    }

    if (description['base'] case final String variable) {
      if (variable.length > 1 && variable.startsWith(r'$')) {
        if (matchers.get(variable.substring(1)) case final base?) {
          result = base.copy()
            ..name = null
            ..label = null;
          if (description['owner'] != null) result.owner = owner;
          if (description['source'] != null && source != null) {
            result.source = source;
          }
          if (location != null && fileLocation != null) {
            result
              ..fileLocation = fileLocation
              ..filePrefix = filePrefix;
          }
          if (description['pattern'] != null && pattern != null) {
            result.pattern = pattern;
          }
          if (description['severity'] != null && severity != null) {
            result.severity = severity;
          }
          if (description['applyTo'] != null) result.applyTo = applyTo;
        }
      }
    } else if (fileLocation != null && pattern != null) {
      result = ProblemMatcher(
        owner: owner,
        applyTo: applyTo,
        fileLocation: fileLocation,
        pattern: pattern,
        source: source,
        filePrefix: filePrefix,
        severity: severity,
      );
    }
    if (result != null && description['name'] is String) {
      result
        ..name = description['name'] as String
        ..label = description['label'] is String
            ? description['label'] as String
            : description['name'] as String;
    }
    return result;
  }

  Object? _createPattern(Object? value) {
    if (value is String) {
      if (value.length > 1 && value.startsWith(r'$')) {
        final result = patterns.get(value.substring(1));
        if (result == null) {
          reporter.errors.add(
            "Error: the pattern with the identifier $value doesn't exist.",
          );
        }
        return switch (result) {
          final List<ProblemPattern> list => [for (final p in list) p.copy()],
          final ProblemPattern single => single.copy(),
          _ => null,
        };
      }
      reporter.errors.add(
        value.isEmpty
            ? 'Error: the pattern property refers to an empty identifier.'
            : 'Error: the pattern property $value is not a valid pattern '
                  'variable name.',
      );
      return null;
    }
    if (value != null) return ProblemPatternParser(reporter).parse(value);
    return null;
  }

  void _addWatchingMatcher(Map external, ProblemMatcher internal) {
    final oldBegins = _regExp(external['watchedTaskBeginsRegExp'], reporter);
    final oldEnds = _regExp(external['watchedTaskEndsRegExp'], reporter);
    if (oldBegins != null && oldEnds != null) {
      internal.watching = WatchingMatcher(
        activeOnStart: false,
        beginsPattern: WatchingPattern(oldBegins),
        endsPattern: WatchingPattern(oldEnds),
      );
      return;
    }
    final monitor = external['background'] ?? external['watching'];
    if (monitor is! Map) return;
    final begins = _watchingPattern(monitor['beginsPattern']);
    final ends = _watchingPattern(monitor['endsPattern']);
    if (begins != null && ends != null) {
      internal.watching = WatchingMatcher(
        activeOnStart: monitor['activeOnStart'] is bool
            ? monitor['activeOnStart'] as bool
            : false,
        beginsPattern: begins,
        endsPattern: ends,
      );
      return;
    }
    if (begins != null || ends != null) {
      reporter.errors.add(
        'A problem matcher must define both a begin pattern and an end '
        'pattern for watching.',
      );
    }
  }

  WatchingPattern? _watchingPattern(Object? external) {
    if (external == null) return null;
    RegExp? regexp;
    int? file;
    if (external is String) {
      regexp = _regExp(external, reporter);
    } else if (external is Map) {
      regexp = _regExp(external['regexp'], reporter);
      if (external['file'] case final num n) file = n.toInt();
    }
    if (regexp == null) return null;
    return WatchingPattern(regexp, file: file != null && file != 0 ? file : 1);
  }
}

List<String> _strings(Object? value) => switch (value) {
  final String s => [s],
  final List l => l.whereType<String>().toList(),
  _ => const [],
};

/// `ProblemMatcherRegistry`: the named matchers (`$name`).
final class ProblemMatcherRegistry {
  ProblemMatcherRegistry(this.patterns) {
    _fillDefaults();
  }

  final ProblemPatternRegistry patterns;
  final _matchers = <String, ProblemMatcher>{};
  late final Map<String, ProblemMatcher> _defaults;

  ProblemMatcher? get(String name) => _matchers[name];

  Iterable<String> get keys => _matchers.keys;

  void add(ProblemMatcher matcher) => _matchers[matcher.name!] = matcher;

  /// The `problemMatchers` contributions of extensions, in place of those
  /// of the last call (built-in ones stay); the patterns' contributions
  /// first.
  void setContributions(List<Object?> contributions, {List<String>? errors}) {
    _matchers
      ..clear()
      ..addAll(_defaults);
    for (final matcher in contributions) {
      if (matcher is! Map) continue;
      final reporter = ProblemReporter();
      final result = ProblemMatcherParser(
        reporter,
        patterns,
        this,
      ).parse(matcher);
      if (result != null && result.name != null) add(result);
      errors?.addAll(reporter.errors);
    }
    get('tsc-watch')?.tscWatch = true;
  }

  void _fillDefaults() {
    ProblemMatcher named(
      String name,
      String label,
      String owner,
      String source,
      ApplyToKind applyTo,
      FileLocationKind fileLocation, {
      String? filePrefix,
      ProblemSeverity? severity,
      bool deprecated = false,
    }) => ProblemMatcher(
      name: name,
      label: label,
      owner: owner,
      source: source,
      applyTo: applyTo,
      fileLocation: fileLocation,
      filePrefix: filePrefix,
      severity: severity,
      deprecated: deprecated,
      pattern: patterns.get(name)!,
    );
    const all = ApplyToKind.allDocuments;
    const absolute = FileLocationKind.absolute;
    const workspace = r'${workspaceFolder}';
    for (final matcher in [
      named(
        'msCompile',
        'Microsoft compiler problems',
        'msCompile',
        'cpp',
        all,
        absolute,
      ),
      named(
        'lessCompile',
        'Less problems',
        'lessCompile',
        'less',
        all,
        absolute,
        severity: ProblemSeverity.error,
        deprecated: true,
      ),
      named(
        'gulp-tsc',
        'Gulp TSC Problems',
        'typescript',
        'ts',
        ApplyToKind.closedDocuments,
        FileLocationKind.relative,
        filePrefix: workspace,
      ),
      named('jshint', 'JSHint problems', 'jshint', 'jshint', all, absolute),
      named(
        'jshint-stylish',
        'JSHint stylish problems',
        'jshint',
        'jshint',
        all,
        absolute,
      ),
      named(
        'eslint-compact',
        'ESLint compact problems',
        'eslint',
        'eslint',
        all,
        absolute,
        filePrefix: workspace,
      ),
      named(
        'eslint-stylish',
        'ESLint stylish problems',
        'eslint',
        'eslint',
        all,
        absolute,
      ),
      named(
        'go',
        'Go problems',
        'go',
        'go',
        all,
        FileLocationKind.relative,
        filePrefix: workspace,
      ),
    ]) {
      add(matcher);
    }
    _defaults = Map.of(_matchers);
  }
}
