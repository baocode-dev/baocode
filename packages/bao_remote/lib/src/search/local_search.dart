import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

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

Future<void> _search((SendPort, String, IdeTextQuery) arguments) async {
  final (port, root, query) = arguments;
  final RegExp regExp;
  try {
    regExp = query.toRegExp();
  } on FormatException catch (error) {
    port.send(_SearchError(error.message));
    return;
  }
  // A quick look at the whole file first; `$` would miss before `\r\n`.
  final quick = query.pattern.contains(r'$') && query.isRegExp
      ? null
      : RegExp(
          regExp.pattern,
          caseSensitive: regExp.isCaseSensitive,
          multiLine: true,
          unicode: true,
        );
  final accept = query.pathFilter();
  final files = query.useExcludesAndIgnoreFiles
      ? await _gitFiles(root) ?? _walk(root, query)
      : _walk(root, query);
  var count = 0;
  for (final relative in files) {
    if (!accept(relative)) continue;
    final path = p.joinAll([root, ...relative.split('/')]);
    final List<int> bytes;
    try {
      final file = File(path);
      if (file.lengthSync() > _maxFileBytes) continue;
      bytes = file.readAsBytesSync();
    } on FileSystemException {
      continue;
    }
    // A NUL marks a binary file, as ripgrep finds them.
    if (bytes.contains(0)) continue;
    final text = utf8.decode(bytes, allowMalformed: true);
    if (quick != null && !quick.hasMatch(text)) continue;
    final matches = ideMatchLines(
      text,
      regExp,
      limit: query.maxResults - count,
    );
    if (matches.isEmpty) continue;
    port.send(IdeFileMatches(path, matches));
    count += matches.length;
    if (count >= query.maxResults) {
      port.send(const IdeTextSearchComplete(limitHit: true));
      return;
    }
  }
  port.send(const IdeTextSearchComplete(limitHit: false));
}

/// The files Git would not ignore: tracked, and untracked outside
/// `.gitignore`; null outside a repository.
Future<Iterable<String>?> _gitFiles(String root) async {
  try {
    final result = await Process.run(
      'git',
      ['ls-files', '--cached', '--others', '--exclude-standard', '-z'],
      workingDirectory: root,
      stdoutEncoding: utf8,
    );
    if (result.exitCode != 0) return null;
    return {
      for (final path in (result.stdout as String).split('\x00'))
        if (path.isNotEmpty) path,
    };
  } on ProcessException {
    return null;
  }
}

/// Every file under [root], skipping the folders [query] excludes.
Iterable<String> _walk(String root, IdeTextQuery query) sync* {
  final excluded = [
    ...ideSearchPathGlobs(query.excludes),
    if (query.useExcludesAndIgnoreFiles) ...ideDefaultSearchExcludes,
  ];
  final folders = [Directory(root)];
  while (folders.isNotEmpty) {
    final folder = folders.removeLast();
    final List<FileSystemEntity> entries;
    try {
      entries = folder.listSync(followLinks: false)
        ..sort((a, b) => a.path.compareTo(b.path));
    } on FileSystemException {
      continue;
    }
    for (final entry in entries.reversed) {
      final relative = p.relative(entry.path, from: root).replaceAll(r'\', '/');
      if (entry is Directory) {
        if (!excluded.any((glob) => glob.hasMatch(relative))) {
          folders.add(entry);
        }
      } else if (entry is File) {
        yield relative;
      }
    }
  }
}
