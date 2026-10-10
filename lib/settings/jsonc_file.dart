import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../platform/data_dir.dart' show writeFileAtomically;
import 'jsonc.dart';

/// Why a [JsoncFile] could not be changed: it does not parse now (the user
/// is to fix it first, as VS Code asks), or the change does not fit it.
class JsoncFileException implements Exception {
  const JsoncFileException(this.path, this.message);

  final String path;
  final String message;

  @override
  String toString() => '$path: $message';
}

/// Where a [JsoncFile] is when it is not on this machine's disk (a remote
/// project's `.vscode/` files).
abstract interface class JsoncFileStorage {
  /// The file's text; null when it is missing. Throws a
  /// [FileSystemException] when it cannot be read.
  Future<String?> read(String path);

  /// Writes [text] whole, making the folders it needs.
  Future<void> write(String path, String text);

  /// An event whenever the file may have changed.
  Stream<void> changes(String path);
}

/// A JSON-with-comments file the user may edit while the app runs
/// (settings.json, keybindings.json, argv.json): its last good [value], kept
/// up to date as the file changes on disk ([watch]), and changed in place
/// ([edit]) so that the user's comments and layout stay. Listeners hear of
/// a change of [value] or [error].
class JsoncFile extends ChangeNotifier {
  JsoncFile(
    this.path, {
    this.debounce = const Duration(milliseconds: 100),
    this.storage,
  });

  final String path;

  /// Where the file is; this machine's disk when null.
  final JsoncFileStorage? storage;

  /// How long changes on disk settle before the file is read again.
  final Duration debounce;

  /// What the file held when it last parsed; null while it is missing,
  /// empty or only comments.
  Object? get value => _value;
  Object? _value;

  /// Why the file does not parse (or cannot be read) now, the first
  /// problem and where it is; [value] keeps the last good one meanwhile.
  /// Null when it parses, or is missing.
  String? get error => _error;
  String? _error;

  /// Whether it was read once ([load]).
  bool get loaded => _loaded;
  bool _loaded = false;

  /// The text last read or written: a change on disk that leaves it as
  /// it is (our own write, seen by the watcher) changes nothing.
  String? _text;

  bool _disposed = false;
  final List<StreamSubscription<Object?>> _watchers = [];
  Timer? _settling;

  /// Reads the file (again).
  Future<void> load() => _queue(() async => _apply(await _read()));

  /// [load], at once: for what must be known before the first frame.
  void loadSync() {
    try {
      _apply((text: File(path).readAsStringSync(), failure: null));
    } on PathNotFoundException {
      _apply((text: null, failure: null));
    } on FileSystemException catch (error) {
      _apply((text: _text, failure: error.message));
    }
  }

  /// Reads the file again whenever it changes on disk, until [dispose]:
  /// its folder is watched (made if missing), as the file may come and go.
  /// A file linked elsewhere is watched there too.
  void watch() {
    if (_disposed || _watchers.isNotEmpty) return;
    if (storage case final storage?) {
      _watchers.add(
        storage
            .changes(path)
            .listen(
              (_) {
                _settling?.cancel();
                _settling = Timer(debounce, () => unawaited(load()));
              },
              onError: (Object _) {
                // Not watched any more: read when asked only.
              },
            ),
      );
      return;
    }
    final places = {(p.dirname(path), p.basename(path))};
    try {
      if (FileSystemEntity.isLinkSync(path)) {
        final target = File(path).resolveSymbolicLinksSync();
        places.add((p.dirname(target), p.basename(target)));
      }
    } on FileSystemException {
      // A broken link: only its own folder.
    }
    for (final (folder, name) in places) {
      try {
        Directory(folder).createSync(recursive: true);
        _watchers.add(
          Directory(folder).watch().listen(
            (event) {
              if (!_concerns(event, name)) return;
              _settling?.cancel();
              _settling = Timer(debounce, () => unawaited(load()));
            },
            onError: (Object _) {
              // The folder is gone: nothing more to hear.
            },
          ),
        );
      } on FileSystemException {
        // Cannot be watched: read when asked only.
      }
    }
  }

  static bool _concerns(FileSystemEvent event, String name) {
    bool same(String? path) {
      if (path == null) return false;
      final base = p.basename(path);
      // Names are case-insensitive on macOS and Windows.
      return Platform.isLinux
          ? base == name
          : base.toLowerCase() == name.toLowerCase();
    }

    return same(event.path) ||
        (event is FileSystemMoveEvent && same(event.destination));
  }

  /// Sets [jsonPath] (keys and array indexes) to [value] in the file, or
  /// removes it, or inserts it into an array: see [modifyJsonc]. The file is
  /// read afresh, changed in place and written whole; one missing is made.
  /// Throws a [JsoncFileException] while the file does not parse (the change
  /// could make it worse) or when the change does not fit it.
  Future<void> edit(
    List<Object> jsonPath,
    Object? value, {
    bool remove = false,
    bool insert = false,
  }) => _queue(() async {
    final read = await _read();
    if (read.failure case final failure?) {
      throw JsoncFileException(path, failure);
    }
    final text = read.text ?? '';
    final errors = <JsoncParseError>[];
    parseJsonc(text, errors: errors);
    if (errors.isNotEmpty) {
      _apply(read);
      throw JsoncFileException(path, errors.first.describe(text));
    }
    final List<JsoncEdit> edits;
    try {
      edits = modifyJsonc(
        text,
        jsonPath,
        value,
        remove: remove,
        insert: insert,
        formatting: _formatting(text),
      );
    } on FormatException catch (error) {
      throw JsoncFileException(path, error.message);
    }
    if (edits.isEmpty) {
      _apply(read);
      return;
    }
    final next = applyJsoncEdits(text, edits);
    await _write(next);
    _apply((text: next, failure: null));
  });

  /// The file's text; null when it is missing.
  Future<String?> readText() async => (await _read()).text;

  /// Changes the file's text in one step, no other read or write of it
  /// coming between: [change] gets its text (null when it is missing) and
  /// returns the new one, or null to leave it. Throws a
  /// [JsoncFileException] when the file cannot be read.
  Future<void> transform(String? Function(String? text) change) =>
      _queue(() async {
        final read = await _read();
        if (read.failure case final failure?) {
          throw JsoncFileException(path, failure);
        }
        final next = change(read.text);
        if (next == null || next == read.text) {
          _apply(read);
          return;
        }
        await _write(next);
        _apply((text: next, failure: null));
      });

  /// Replaces the file's text with [text], as it is.
  Future<void> writeText(String text) => _queue(() async {
    await _write(text);
    _apply((text: text, failure: null));
  });

  /// How [text] is laid out; a new file's lines end as the platform's do.
  static JsoncFormatting _formatting(String text) {
    final detected = JsoncFormatting.detect(text);
    if (!Platform.isWindows || text.contains(RegExp('[\r\n]'))) {
      return detected;
    }
    return JsoncFormatting(
      insertSpaces: detected.insertSpaces,
      tabSize: detected.tabSize,
      eol: '\r\n',
    );
  }

  Future<({String? text, String? failure})> _read() async {
    if (storage case final storage?) {
      try {
        return (text: await storage.read(path), failure: null);
      } on Object catch (error) {
        return (text: _text, failure: 'Cannot read the file: $error');
      }
    }
    try {
      return (text: await File(path).readAsString(), failure: null);
    } on PathNotFoundException {
      return (text: null, failure: null);
    } on FileSystemException catch (error) {
      // Unreadable (or not UTF-8): what was read before stays.
      return (text: _text, failure: 'Cannot read the file: ${error.message}');
    }
  }

  /// Writes [text] whole or not at all; into the file a link points to,
  /// so the link stays.
  Future<void> _write(String text) async {
    if (storage case final storage?) return storage.write(path, text);
    var file = File(path);
    if (await FileSystemEntity.isLink(path)) {
      file = File(await file.resolveSymbolicLinks());
    }
    await file.parent.create(recursive: true);
    await writeFileAtomically(file, text);
  }

  void _apply(({String? text, String? failure}) read) {
    if (_disposed) return;
    final (:text, :failure) = read;
    if (_loaded && text == _text && failure == null && _error == null) return;
    final (value, error) = (_value, _error);
    _loaded = true;
    _text = text;
    if (failure != null) {
      _error = failure;
    } else if (text == null) {
      _value = null;
      _error = null;
    } else {
      final errors = <JsoncParseError>[];
      final parsed = parseJsonc(text, errors: errors);
      if (errors.isEmpty) {
        _value = parsed;
        _error = null;
      } else {
        _error = errors.first.describe(text);
      }
    }
    if (_error != error || !jsonEquals(_value, value)) notifyListeners();
  }

  Future<void> _pending = Future.value();

  /// One read or write at a time, in order.
  Future<T> _queue<T>(Future<T> Function() task) {
    final result = _pending.then((_) => task());
    _pending = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  @override
  void dispose() {
    _disposed = true;
    _settling?.cancel();
    for (final watcher in _watchers) {
      unawaited(watcher.cancel());
    }
    _watchers.clear();
    super.dispose();
  }
}

/// Whether two JSON values are the same: maps by their entries, lists by
/// their elements.
bool jsonEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final MapEntry(:key, :value) in a.entries) {
      if (!b.containsKey(key) || !jsonEquals(value, b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!jsonEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}
