import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import '../files/git_ignore.dart';
import 'text_query.dart';

/// Searches in a background isolate, killed when the subscription is
/// cancelled.
Stream<Object> searchText(String root, IdeTextQuery query) {
  Isolate? isolate;
  final port = ReceivePort();
  var cancelled = false;
  late final StreamController<Object> controller;
  void finish() {
    port.close();
    isolate?.kill(priority: Isolate.immediate);
    unawaited(controller.close());
  }

  controller = StreamController<Object>(
    onListen: () {
      port.listen((message) {
        switch (message) {
          case IdeFileMatches():
            controller.add(message);
          case IdeTextSearchComplete():
            controller.add(message);
            finish();
          case _SearchError(:final message):
            controller.addError(FileSystemException(message, root));
            finish();
          // An uncaught error: [error, stack trace].
          case [final Object? error, _]:
            controller.addError('$error');
            finish();
        }
      });
      unawaited(
        Isolate.spawn(
          _search,
          (port.sendPort, root, query),
          onError: port.sendPort,
          errorsAreFatal: true,
        ).then(
          (spawned) {
            if (cancelled) {
              spawned.kill(priority: Isolate.immediate);
            } else {
              isolate = spawned;
            }
          },
          onError: (Object error) {
            if (cancelled) return;
            controller.addError(error);
            finish();
          },
        ),
      );
    },
    onCancel: () {
      cancelled = true;
      port.close();
      isolate?.kill(priority: Isolate.immediate);
    },
  );
  return controller.stream;
}

class _SearchError {
  const _SearchError(this.message);

  final String message;
}

/// Files over this are not searched (ripgrep reads anything; the editor
/// would not open them either).
const _maxFileBytes = 50 * 1024 * 1024;

/// What a file's start is looked at for a NUL, as ripgrep's first buffer.
const _headBytes = 64 * 1024;

/// Files handed to a worker at once, and batches each has in hand.
const _batchSize = 32;
const _batchesAhead = 2;

/// The isolates reading and matching files, as ripgrep's threads, while
/// this one walks the folders and hands them out.
int get _workerCount => (Platform.numberOfProcessors - 1).clamp(1, 8);

Future<void> _search((SendPort, String, IdeTextQuery) arguments) async {
  final (port, root, query) = arguments;
  try {
    query.toRegExp();
  } on FormatException catch (error) {
    port.send(_SearchError(error.message));
    return;
  }
  final accept = query.pathFilter();
  final excluded = IdePathGlobs(query.excludeGlobs);
  // Walked as ripgrep walks for upstream, `.gitignore` files at every level
  // and in repositories inside honored, ignored folders not gone into; Git's
  // own list would miss those inside, and fails without Git or outside a
  // repository. As VS Code runs it: no global ignore file, links followed.
  final files = walkUnignored(
    root,
    ignoreFiles: query.useExcludesAndIgnoreFiles,
    globalIgnoreFile: false,
    followLinks: true,
    skipDirectory: (relative, _) => excluded.hasMatch(relative),
  ).iterator;
  var walked = false;
  List<String>? nextBatch() {
    if (walked) return null;
    final batch = <String>[];
    while (batch.length < _batchSize) {
      if (!files.moveNext()) {
        walked = true;
        break;
      }
      final (:relative, :path) = files.current;
      if (accept(relative)) batch.add(path);
    }
    return batch.isEmpty ? null : batch;
  }

  final replies = ReceivePort();
  final workers = <int, SendPort>{};
  var pending = 0;
  var count = 0;
  var done = false;
  void finish({required bool limitHit}) {
    if (done) return;
    done = true;
    port.send(IdeTextSearchComplete(limitHit: limitHit));
    for (final worker in workers.values) {
      worker.send(null);
    }
    replies.close();
  }

  void feed(int worker) {
    if (nextBatch() case final batch?) {
      workers[worker]!.send(batch);
      pending++;
    } else if (pending == 0) {
      finish(limitHit: false);
    }
  }

  replies.listen((message) {
    if (done) return;
    switch (message) {
      case (final int worker, final SendPort commands):
        workers[worker] = commands;
        for (var i = 0; i < _batchesAhead && !walked; i++) {
          feed(worker);
        }
        if (walked && pending == 0) finish(limitHit: false);
      case (final int worker, final List<IdeFileMatches> found):
        pending--;
        for (final file in found) {
          final left = query.maxResults - count;
          final matches = file.matches.length > left
              ? file.matches.sublist(0, left)
              : file.matches;
          port.send(IdeFileMatches(file.path, matches));
          count += matches.length;
          if (count >= query.maxResults) {
            finish(limitHit: true);
            return;
          }
        }
        feed(worker);
      // A worker's uncaught error: [error, stack trace].
      case [final Object? error, _]:
        done = true;
        port.send(_SearchError('$error'));
        replies.close();
    }
  });
  final workerCount = _workerCount;
  for (var i = 0; i < workerCount && !done; i++) {
    await Isolate.spawn(_work, (
      i,
      Isolate.current,
      replies.sendPort,
      query,
    ), onError: replies.sendPort);
  }
}

/// A worker: reads and matches each batch of files it is handed, and
/// sends back their matches; ends on null, and with the [_search] that
/// started it (killed when the search is cancelled).
void _work((int, Isolate, SendPort, IdeTextQuery) arguments) {
  final (index, search, replies, query) = arguments;
  final commands = ReceivePort();
  search.addOnExitListener(commands.sendPort);
  // Gone already (and so never to tell its end): no answer.
  search.ping(commands.sendPort, response: true);
  final orphaned = Timer(const Duration(seconds: 5), commands.close);
  final regExp = query.toRegExp();
  // A quick look at the whole file first; `$` would miss before `\r\n`.
  final quick = query.pattern.contains(r'$') && query.isRegExp
      ? null
      : RegExp(
          regExp.pattern,
          caseSensitive: regExp.isCaseSensitive,
          multiLine: true,
          unicode: true,
        );
  final reader = _Reader();
  commands.listen((paths) {
    if (paths == true) {
      orphaned.cancel();
      return;
    }
    if (paths is! List<String>) {
      commands.close();
      return;
    }
    final found = <IdeFileMatches>[];
    for (final path in paths) {
      final text = reader.read(path);
      if (text == null) continue;
      if (quick != null && !quick.hasMatch(text)) continue;
      final matches = ideMatchLines(
        text,
        regExp,
        limit: query.maxResults,
        multiline: query.isMultiline,
      );
      if (matches.isNotEmpty) found.add(IdeFileMatches(path, matches));
    }
    replies.send((index, found));
  });
  replies.send((index, commands.sendPort));
}

/// Reads files as text for searching, into one buffer kept between them
/// (up to 8 MB; a larger file gets one of its own).
class _Reader {
  static const _keptBytes = 8 << 20;

  var _buffer = Uint8List(1 << 20);

  /// [path]'s text: UTF-8, or UTF-16 by its byte order mark, as ripgrep
  /// takes them. Null for a binary file (a NUL in its first 64 KB), one too
  /// large or not read; a NUL later ends the text, as ripgrep stops there.
  String? read(String path) {
    final RandomAccessFile file;
    try {
      file = File(path).openSync();
    } on FileSystemException {
      return null;
    }
    try {
      final length = file.lengthSync();
      if (length > _maxFileBytes) return null;
      if (_buffer.length < length && length <= _keptBytes) {
        _buffer = Uint8List(min(max(length, _buffer.length * 2), _keptBytes));
      }
      final buffer = _buffer.length < length ? Uint8List(length) : _buffer;
      var end = _readInto(file, buffer, 0, min(length, _headBytes));
      if (_utf16(buffer, end) case final bigEndian?) {
        end += _readInto(file, buffer, end, length);
        return _decodeUtf16(buffer, end, bigEndian: bigEndian);
      }
      if (_indexOfNul(buffer, 0, end) >= 0) return null;
      final head = end;
      end += _readInto(file, buffer, end, length);
      final nul = _indexOfNul(buffer, head, end);
      if (nul >= 0) end = nul;
      return utf8.decode(
        Uint8List.sublistView(buffer, 0, end),
        allowMalformed: true,
      );
    } on FileSystemException {
      return null;
    } finally {
      file.closeSync();
    }
  }

  /// Reads into [buffer] from [start] up to [end]; how much was read.
  static int _readInto(
    RandomAccessFile file,
    Uint8List buffer,
    int start,
    int end,
  ) {
    var at = start;
    while (at < end) {
      final read = file.readIntoSync(buffer, at, end);
      if (read == 0) break;
      at += read;
    }
    return at - start;
  }

  static int _indexOfNul(Uint8List bytes, int start, int end) {
    for (var i = start; i < end; i++) {
      if (bytes[i] == 0) return i;
    }
    return -1;
  }

  /// Whether the text starts with a UTF-16 byte order mark: big endian
  /// or not; null for none.
  static bool? _utf16(Uint8List bytes, int length) {
    if (length < 2) return null;
    if (bytes[0] == 0xFF && bytes[1] == 0xFE) return false;
    if (bytes[0] == 0xFE && bytes[1] == 0xFF) return true;
    return null;
  }

  static String _decodeUtf16(
    Uint8List bytes,
    int length, {
    required bool bigEndian,
  }) {
    final units = Uint16List((length - 2) >> 1);
    for (var i = 0; i < units.length; i++) {
      final a = bytes[2 + 2 * i];
      final b = bytes[3 + 2 * i];
      units[i] = bigEndian ? a << 8 | b : b << 8 | a;
    }
    return String.fromCharCodes(units);
  }
}
