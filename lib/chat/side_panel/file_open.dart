import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../../ide/file_service.dart';
import '../chat_models.dart';
import 'file_link.dart';

/// A file to show: at [range], or as its changes ([diff]) against
/// [original], its text before (the agent's edit, or Git's HEAD or index).
@immutable
class FileOpenRequest {
  const FileOpenRequest(
    this.path, {
    this.range,
    this.diff = false,
    this.change,
    this.original,
    this.modified,
  });

  /// Absolute, on the project's host.
  final String path;
  final FileLineRange? range;

  /// Its changes rather than its text, where they are known.
  final bool diff;

  /// The change [diff] shows, when the session lists it.
  final FileChange? change;

  /// Reads [path]'s text before it changed; null when unknown.
  final Future<String> Function()? original;

  /// Reads [path]'s text after it changed (a staged change's, the index's);
  /// the file's when null.
  final Future<String> Function()? modified;

  FileOpenRequest copyWith({
    FileLineRange? range,
    FileChange? change,
    Future<String> Function()? original,
  }) => FileOpenRequest(
    path,
    range: range ?? this.range,
    diff: diff,
    change: change ?? this.change,
    original: original ?? this.original,
    modified: modified,
  );

  @override
  String toString() =>
      'FileOpenRequest($path${range == null ? '' : ', $range'}'
      '${diff ? ', diff' : ''})';
}

/// Where a chat's files open (the agent window's side panel, the IDE's
/// editor), and how it learns which exist.
class FileLinkTarget {
  const FileLinkTarget({
    required this.open,
    this.exists,
    this.paths,
    this.roots,
  });

  final ValueChanged<FileOpenRequest> open;

  /// A multi-folder workspace's folders as they are now: its files are
  /// theirs (see [FileOpenScope.roots]).
  final List<String> Function()? roots;

  /// Whether the file at an absolute path is there; inline code naming a
  /// file is a link only once it is known to be. None: never a link.
  final Future<bool> Function(String path)? exists;

  /// How the project's host spells paths; this machine's when null.
  final p.Context? paths;
}

/// Whether a file is in [files], as the listing of its folder says: on a
/// remote project's host as well as here. A folder listed is kept a few
/// seconds, for the paths asked together.
Future<bool> Function(String path) fileExistsIn(
  IdeFileService files, {
  p.Context? paths,
}) {
  final context = paths ?? p.context;
  final listings = <String, ({DateTime at, Future<Set<String>> names})>{};
  return (path) async {
    final folder = context.dirname(path);
    final now = DateTime.now();
    var listing = listings[folder];
    if (listing == null || now.difference(listing.at).inSeconds >= 5) {
      listing = (
        at: now,
        names: files
            .list(folder)
            .then(
              (entries) => {
                for (final entry in entries)
                  if (!entry.isDirectory) entry.name,
              },
            ),
      );
      listings[folder] = listing;
    }
    try {
      return (await listing.names).contains(context.basename(path));
    } catch (_) {
      return false;
    }
  };
}

/// Which files exist, as [check] finds, asked once each: a listener is
/// told (once for those found together) as answers come.
class FileExistence extends ChangeNotifier {
  FileExistence(this.check);

  final Future<bool> Function(String path)? check;

  final Map<String, bool> _known = {};
  final Set<String> _asking = {};
  bool _notifying = false;
  bool _disposed = false;

  /// Whether [path] exists: null until known, asked then.
  bool? known(String path) {
    if (_known[path] case final known?) return known;
    final check = this.check;
    if (check == null) return false;
    if (_asking.add(path)) {
      unawaited(
        check(path).then((found) => found, onError: (_) => false).then((found) {
          _asking.remove(path);
          _known[path] = found;
          if (found) _notifySoon();
        }),
      );
    }
    return null;
  }

  void _notifySoon() {
    if (_notifying || _disposed) return;
    _notifying = true;
    scheduleMicrotask(() {
      _notifying = false;
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// What the file links under it open: those in [root] (on the project's
/// host, spelled as [paths]), or a workspace's [roots], through [onOpen].
class FileOpenScope extends InheritedWidget {
  const FileOpenScope({
    super.key,
    required this.root,
    required this.onOpen,
    required this.existence,
    this.paths,
    this.roots = const [],
    required super.child,
  });

  final String root;
  final ValueChanged<FileOpenRequest> onOpen;
  final FileExistence existence;
  final p.Context? paths;

  /// A multi-folder workspace's folders, its files' ([root], the agent's
  /// directory, only holds its settings): a relative path is looked for in
  /// each, in order.
  final List<String> roots;

  static FileOpenScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FileOpenScope>();

  /// [path] (absolute, or relative to [root]) in [root]; null outside it.
  /// In a workspace, the first of its folders' found to have it; until
  /// one is, the first's.
  String? resolve(String path) {
    final candidates = _candidates(path);
    if (candidates.length < 2) return candidates.firstOrNull;
    for (final candidate in candidates) {
      if (existence.known(candidate) == true) return candidate;
    }
    return candidates.first;
  }

  /// Where [path] may be: in each of [roots], then in [root].
  List<String> _candidates(String path) {
    final found = <String>{};
    for (final folder in [...roots, root]) {
      if (FileLink.resolvePath(path, folder, paths: paths) case final full?) {
        found.add(full);
      }
    }
    return [...found];
  }

  /// Opens [link] if it is in [root]; false if it is not. In a workspace,
  /// once it is found in one of its folders, if that is not known yet.
  bool openLink(FileLink link, {bool diff = false}) {
    final path = resolve(link.path);
    if (path == null) return false;
    void open(String path) =>
        onOpen(FileOpenRequest(path, range: link.range, diff: diff));
    final check = existence.check;
    final candidates = _candidates(link.path);
    if (candidates.length < 2 ||
        check == null ||
        existence.known(path) == true) {
      open(path);
      return true;
    }
    unawaited(() async {
      for (final candidate in candidates) {
        final found = await check(candidate)
            .then((found) => found, onError: (_) => false);
        if (found) return open(candidate);
      }
      open(path);
    }());
    return true;
  }

  /// What a click on a markdown link to [href] does: opens the file it goes
  /// to, when that is in [root]; null for any other.
  GestureRecognizer? linkRecognizer(String? href) {
    final link = FileLink.parseHref(href);
    if (link == null || resolve(link.path) == null) return null;
    return TapGestureRecognizer()..onTap = () => openLink(link);
  }

  /// What a click on inline [code] does: opens the file it names, once
  /// that is known to exist in [root]; null until then, and for any other.
  GestureRecognizer? codeRecognizer(String code) {
    final link = FileLink.parseText(code);
    if (link == null) return null;
    final path = resolve(link.path);
    if (path == null || existence.known(path) != true) return null;
    return TapGestureRecognizer()..onTap = () => openLink(link);
  }

  @override
  bool updateShouldNotify(FileOpenScope oldWidget) =>
      root != oldWidget.root ||
      onOpen != oldWidget.onOpen ||
      existence != oldWidget.existence ||
      paths != oldWidget.paths ||
      !listEquals(roots, oldWidget.roots);
}
