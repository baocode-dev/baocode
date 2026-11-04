import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

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
  final excluded = [
    ...ideSearchPathGlobs(query.excludes),
    if (query.useExcludesAndIgnoreFiles) ...ideDefaultSearchExcludes,
  ];
  // Walked as ripgrep walks for upstream, `.gitignore` files at every level
  // and in repositories inside honored, ignored folders not gone into; Git's
  // own list would miss those inside, and fails without Git or outside a
  // repository.
  final files = walkUnignored(
    root,
    ignoreFiles: query.useExcludesAndIgnoreFiles,
    skipDirectory: (relative, _) =>
        excluded.any((glob) => glob.hasMatch(relative)),
  );
  var count = 0;
  for (final (:relative, :path) in files) {
    if (!accept(relative)) continue;
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
      multiline: query.isMultiline,
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
