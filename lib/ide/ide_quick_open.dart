import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../l10n/command_titles.dart';
import '../l10n/l10n.dart';
import 'file_index_store.dart';
import 'file_service.dart';
import 'ide_commands.dart';
import '../theme/material_file_icons.dart';
import 'ide_fuzzy.dart';
import 'ide_quick_input.dart';
import 'ide_workspace.dart';

/// A file Quick Open found: absolute, and relative as it shows it.
typedef IdeFileHit = ({String path, String relative});

/// A cached listing of the project's files for Quick Open. The cache is shown
/// at once and refreshed in the background each time Quick Open opens (a
/// remote project's, once it is a while old).
///
/// A large listing is kept packed on an isolate of its own (see
/// [FileIndexWorker]), as VS Code keeps its in the extension host: a filter
/// goes there and the best few come back, and the listing is let go once
/// nothing has asked for a while. A small one is matched here.
class IdeFileIndex extends ChangeNotifier {
  IdeFileIndex(
    this.files,
    this.root, {
    this._lister,
    List<String>? roots,
    p.Context? pathContext,
  }) : pathContext = pathContext ?? p.context,
       _roots = roots == null ? null : [...roots];

  final IdeFileService files;
  final String root;
  final p.Context pathContext;

  /// At most this many files are listed: past it, Quick Open says so.
  static const maxFiles = 1000000;

  /// Above this many files, the listing is kept and matched off the UI
  /// isolate.
  static const backgroundAbove = 5000;

  /// A listing kept off the UI isolate is let go after this long unused.
  static const idleRelease = Duration(minutes: 5);

  /// How many files of the listing are kept here, for no filter.
  static const _headSize = 500;

  /// A multi-folder workspace's folders, listed in place of [root]: each
  /// file's relative path then starts with its folder's name, as VS Code
  /// labels them. Null for a folder's project.
  List<String>? get roots => _roots;
  List<String>? _roots;
  set roots(List<String>? roots) {
    if (roots == _roots ||
        (roots != null && _roots != null && listEquals(roots, _roots))) {
      return;
    }
    _roots = roots;
    if (_loaded) unawaited(refresh());
  }

  /// [path] as Quick Open shows it: relative to its folder, `/` between.
  String relativeOf(String path) {
    final roots = _roots;
    if (roots == null) {
      return pathContext.relative(path, from: root).replaceAll(r'\', '/');
    }
    for (final folder in roots) {
      if (pathContext.isWithin(folder, path)) {
        final relative = pathContext
            .relative(path, from: folder)
            .replaceAll(r'\', '/');
        return '${pathContext.basename(folder)}/$relative';
      }
    }
    return path.replaceAll(r'\', '/');
  }

  final Future<IdeFileListing> Function(IdeFileService, String)? _lister;

  /// The files of [root], or of each of [roots], listed here.
  Future<IdeFileListing> _list(List<String> folders) async {
    final lister =
        _lister ??
        (files, root) => listProjectFiles(files, root, limit: maxFiles);
    final listings = await Future.wait([
      for (final folder in folders) lister(files, folder),
    ]);
    return IdeFileListing([
      for (final listing in listings) ...listing.paths,
    ], truncated: listings.any((listing) => listing.truncated));
  }

  /// The folders listed last, and the start of their files' relative paths
  /// (their names, in a multi-folder workspace).
  List<String> _folders = const [];
  List<int> _prefixLengths = const [];

  /// The listing, when kept here.
  FileIndexStore? _store;

  /// Where the listing is kept otherwise.
  FileIndexWorker? _worker;
  Timer? _idle;

  List<IdeFileHit> _head = const [];
  int _count = 0;
  bool _truncated = false;
  bool _loaded = false;
  Future<void>? _pending;
  bool _disposed = false;

  /// How many files are listed.
  int get count => _count;

  /// Whether more files are there than were listed (see [maxFiles]).
  bool get truncated => _truncated;
  bool get loaded => _loaded;
  bool get loading => _pending != null;

  /// Whether a filter is being matched off the UI isolate (see [bestFor]).
  bool get searching => _finding != null;

  /// [entry] as found: its absolute path made again from its folder's.
  IdeFileHit _hitOf(FileIndexEntry entry) {
    if (entry.absolute case final path?) {
      return (path: path, relative: entry.relative);
    }
    final folder = _folders[entry.folder];
    final rest = entry.relative.length > _prefixLengths[entry.folder]
        ? entry.relative.substring(_prefixLengths[entry.folder])
        : '';
    return (
      path: rest.isEmpty
          ? folder
          : pathContext.joinAll([folder, ...rest.split('/')]),
      relative: entry.relative,
    );
  }

  /// [path] as the listing of [folders] keeps it.
  FileIndexEntry _entryOf(String path, List<String> folders) {
    for (var i = 0; i < folders.length; i++) {
      if (pathContext.isWithin(folders[i], path)) {
        return (relative: relativeOf(path), folder: i, absolute: null);
      }
    }
    return (
      relative: relativeOf(path),
      folder: fileIndexNoFolder,
      absolute: path,
    );
  }

  /// The best matches of the filter last matched, whichever it was: shown,
  /// matched anew, while [bestFor] finds those of the filter typed since.
  List<IdeFileHit> get lastFound => _found?.best ?? const [];

  /// The filter last matched, the limit it was matched to, and its best.
  ({String filter, int limit, List<IdeFileHit> best})? _found;

  /// The filter being matched off the UI isolate, if any.
  String? _finding;

  /// Counts the listings, so a match of an earlier one is dropped.
  int _generation = 0;

  /// Counts the matches asked for, and the last found: one found after a
  /// later one is dropped.
  int _requests = 0;
  int _foundRequest = 0;

  /// The files best matching [filter] (see [scoreFilePath]), best first, at
  /// most [limit]; the first listed for no filter. Off the UI isolate for a
  /// large listing: null until found, listeners hear when they are.
  List<IdeFileHit>? bestFor(String filter, {required int limit}) {
    if (filter.isEmpty) return _head.take(limit).toList();
    if (_store case final store?) {
      final best = [
        for (final entry in store.find(filter, limit)) _hitOf(entry),
      ];
      _found = (filter: filter, limit: limit, best: best);
      return best;
    }
    if (_worker == null) return const [];
    _touch();
    if (_found case (filter: final found, limit: final kept, :final best)
        when found == filter && kept == limit) {
      return best;
    }
    if (_finding != filter) {
      _finding = filter;
      unawaited(_find(filter, limit));
    }
    return null;
  }

  Future<void> _find(String filter, int limit) async {
    final worker = _worker!;
    final generation = _generation;
    final request = ++_requests;
    List<FileIndexEntry> found;
    try {
      found = await worker.find(filter, limit);
    } on StateError {
      // Let go meanwhile.
      if (_finding == filter) _finding = null;
      return;
    }
    if (_disposed || generation != _generation) return;
    if (_finding == filter) _finding = null;
    // Matched while a later filter was typed: still the nearest there is
    // to show, unless that one was found first.
    if (request < _foundRequest) return;
    _foundRequest = request;
    _found = (
      filter: filter,
      limit: limit,
      best: [for (final entry in found) _hitOf(entry)],
    );
    notifyListeners();
  }

  /// The files best matching [filter], at most [limit], once found: as
  /// [bestFor], waited for.
  Future<List<IdeFileHit>> find(String filter, {required int limit}) async {
    if (filter.isEmpty || _store != null) return bestFor(filter, limit: limit)!;
    final worker = _worker;
    if (worker == null) return const [];
    _touch();
    final generation = _generation;
    try {
      final found = await worker.find(filter, limit);
      if (generation != _generation) return const [];
      return [for (final entry in found) _hitOf(entry)];
    } on StateError {
      return const [];
    }
  }

  /// The folders of the files whose paths match [filter] scoring [minScore]
  /// or more (see [scoreFilePath]), the best [limit], best first.
  Future<List<({IdeFileHit folder, int score})>> findFolders(
    String filter, {
    required int limit,
    int minScore = 0,
  }) async {
    List<({FileIndexEntry entry, int score})> found;
    final generation = _generation;
    if (_store case final store?) {
      found = store.findFolders(filter, limit, minScore);
    } else if (_worker case final worker?) {
      _touch();
      try {
        found = await worker.findFolders(filter, limit, minScore);
      } on StateError {
        return const [];
      }
      if (generation != _generation) return const [];
    } else {
      return const [];
    }
    return [
      for (final (:entry, :score) in found)
        (folder: _hitOf(entry), score: score),
    ];
  }

  /// When the paths were last listed.
  DateTime? _listedAt;

  /// Starts a new listing unless one is already running.
  Future<void> refresh() => _pending ??= _load();

  /// As [refresh], unless the paths were listed less than [age] ago: a
  /// remote project's are not listed again each time Quick Open opens.
  Future<void> refreshIfOlder(Duration age) {
    final listedAt = _listedAt;
    if (listedAt != null && DateTime.now().difference(listedAt) < age) {
      return Future.value();
    }
    return refresh();
  }

  Future<void> _load() async {
    // A worker spawned for this listing: let go unless it keeps it.
    FileIndexWorker? spawned;
    try {
      final folders = _roots ?? [root];
      final multi = _roots != null;
      final prefixes = [
        for (final folder in folders)
          multi ? '${pathContext.basename(folder)}/' : '',
      ];
      // Kept here, or by the worker.
      FileIndexStore? store;
      FileIndexWorker? worker;
      List<FileIndexEntry> head;
      int count;
      bool truncated;
      if (_lister == null && !kIsWeb && isLocalFileService(files)) {
        // Listed there, and kept there unless few.
        final there = _worker ?? (spawned = await FileIndexWorker.spawn());
        final listing = await there.listLocal(
          folders,
          prefixes,
          limit: maxFiles,
          head: _headSize,
          returnAtMost: backgroundAbove,
        );
        if (listing.all case final all?) {
          store = FileIndexStore(all);
        } else {
          worker = there;
        }
        head = listing.head;
        count = listing.count;
        truncated = listing.truncated;
      } else {
        final listing = await _list(folders);
        final entries = [
          for (final path in listing.paths) _entryOf(path, folders),
        ];
        count = entries.length;
        truncated = listing.truncated;
        if (kIsWeb || count <= backgroundAbove) {
          store = FileIndexStore(entries);
          head = store.head(_headSize);
        } else {
          final there = _worker ?? (spawned = await FileIndexWorker.spawn());
          await there.load(entries);
          worker = there;
          // As the worker sorts them.
          entries.sort((a, b) => a.relative.compareTo(b.relative));
          head = entries.take(_headSize).toList();
        }
      }
      if (_disposed) return;
      if (!identical(worker, _worker)) _worker?.dispose();
      _worker = worker;
      _store = store;
      _folders = folders;
      _prefixLengths = [for (final prefix in prefixes) prefix.length];
      _head = [for (final entry in head) _hitOf(entry)];
      _count = count;
      _truncated = truncated;
      _loaded = true;
      _listedAt = DateTime.now();
      _generation++;
      _found = null;
      _finding = null;
      _touch();
    } catch (_) {
      // Keep the previous listing; Quick Open still offers recent files.
    } finally {
      if (spawned != null && !identical(spawned, _worker)) spawned.dispose();
      _pending = null;
      if (!_disposed) notifyListeners();
    }
  }

  /// Puts off letting go of a listing kept off the UI isolate.
  void _touch() {
    _idle?.cancel();
    _idle = _worker == null ? null : Timer(idleRelease, _release);
  }

  /// Lets the listing kept off the UI isolate go, unless something shows
  /// it: listed again when next asked for.
  void _release() {
    if (hasListeners || _pending != null) {
      _touch();
      return;
    }
    _worker?.dispose();
    _worker = null;
    _idle = null;
    _head = const [];
    _count = 0;
    _loaded = false;
    _listedAt = null;
    _generation++;
    _found = null;
    _finding = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _idle?.cancel();
    _worker?.dispose();
    _worker = null;
    super.dispose();
  }
}

/// A Quick Open query: a file filter with an optional `:line[:column]`.
@immutable
class IdeQuickOpenQuery {
  const IdeQuickOpenQuery(this.filter, {this.line, this.column});

  factory IdeQuickOpenQuery.parse(String text) {
    final match = RegExp(r'^(.*?)(?::(-?\d*)(?:[:,](\d*))?)?\s*$')
        .firstMatch(text.trim());
    if (match == null) return IdeQuickOpenQuery(_normalize(text));
    return IdeQuickOpenQuery(
      _normalize(match.group(1) ?? ''),
      line: int.tryParse(match.group(2) ?? ''),
      column: int.tryParse(match.group(3) ?? ''),
    );
  }

  /// Whitespace is ignored and separators are `/`, as in VS Code.
  static String _normalize(String text) =>
      text.replaceAll(RegExp(r'\s+'), '').replaceAll(r'\', '/');

  final String filter;
  final int? line;
  final int? column;
}

/// Scores [relative] (a `/`-separated project path) against [filter]: file
/// name matches rank above folder matches. Returns positions split into the
/// name and the folder (description) parts, or null for no match.
({int score, List<int> label, List<int> description})? scoreFilePath(
  String filter,
  String relative,
) {
  final slash = relative.lastIndexOf('/');
  final name = relative.substring(slash + 1);
  if (!filter.contains('/')) {
    final match = ideFuzzyMatch(filter, name);
    if (match != null) {
      // Exact or prefix matches of the name rank highest.
      final lowerName = name.toLowerCase();
      final lowerFilter = filter.toLowerCase();
      final bonus = lowerName == lowerFilter
          ? 400
          : lowerName.startsWith(lowerFilter)
          ? 200
          : 0;
      return (
        score: 1000 + bonus + match.score,
        label: match.positions,
        description: const [],
      );
    }
  }
  final match = ideFuzzyMatch(filter, relative);
  if (match == null) return null;
  final nameStart = slash + 1;
  return (
    score: match.score,
    label: [
      for (final i in match.positions)
        if (i >= nameStart) i - nameStart,
    ],
    description: [
      for (final i in match.positions)
        if (i < slash) i,
    ],
  );
}

/// Rows for Quick Open (no prefix). [recent] is most-recent-first absolute
/// paths; [onOpen] opens a file at an optional one-based line and column,
/// and [onOpenInBackground], if given, while Quick Open stays (upstream
/// `quickInput.acceptInBackground`). Messages are in [l10n]'s language
/// (English when null).
List<IdeQuickPickItem> fileQuickPicks(
  String text, {
  required IdeFileIndex index,
  required List<String> recent,
  required void Function(String path, int? line, int? column) onOpen,
  void Function(String path, int? line, int? column)? onOpenInBackground,
  int limit = 200,
  AppLocalizations? l10n,
}) {
  final strings = l10n ?? englishLocalizations;
  final query = IdeQuickOpenQuery.parse(text);
  String relativeOf(String path) => index.relativeOf(path);

  IdeQuickPickItem item(
    String path,
    String relative, {
    List<int> label = const [],
    List<int> description = const [],
    String? group,
  }) {
    final slash = relative.lastIndexOf('/');
    return IdeQuickPickItem(
      label: relative.substring(slash + 1),
      labelMatches: label,
      description: slash < 0 ? null : relative.substring(0, slash),
      descriptionMatches: description,
      icon: FileIcon(path, size: 16),
      group: group,
      onAccept: () => onOpen(path, query.line, query.column),
      onAcceptInBackground: onOpenInBackground == null
          ? null
          : () => onOpenInBackground(path, query.line, query.column),
    );
  }

  if (query.filter.isEmpty) {
    final seen = <String>{};
    final items = <IdeQuickPickItem>[];
    for (final path in recent) {
      if (!seen.add(path)) continue;
      items.add(
        item(
          path,
          relativeOf(path),
          group: items.isEmpty ? strings.quickOpenRecentlyOpened : null,
        ),
      );
    }
    var first = true;
    for (final (:path, :relative) in index.bestFor('', limit: limit)!) {
      if (items.length >= limit) break;
      if (!seen.add(path)) continue;
      items.add(
        item(path, relative, group: first ? strings.quickOpenFiles : null),
      );
      first = false;
    }
    if (items.isEmpty) {
      items.add(
        IdeQuickPickItem(
          label: index.loading
              ? strings.quickOpenLoadingFiles
              : strings.quickOpenNoFiles,
        ),
      );
    }
    return items;
  }

  final recentRank = <String, int>{
    for (var i = 0; i < recent.length; i++) recent[i]: i,
  };
  final scored =
      <
        ({
          String path,
          String relative,
          int score,
          List<int> label,
          List<int> description,
        })
      >[];
  bool consider(String path, String relative) {
    final result = scoreFilePath(query.filter, relative);
    if (result == null) return false;
    final rank = recentRank[path];
    scored.add((
      path: path,
      relative: relative,
      score: result.score + (rank == null ? 0 : 300 - (rank * 5).clamp(0, 150)),
      label: result.label,
      description: result.description,
    ));
    return true;
  }

  // A large listing's best are found off the UI isolate, those of the
  // filter found last shown (those still matching) until they are.
  // Recently opened files are matched here, all of them, for their rank to
  // count.
  final recentSet = recent.toSet();
  final best = index.bestFor(query.filter, limit: limit) ?? index.lastFound;
  for (final (:path, :relative) in best) {
    if (!recentSet.contains(path)) consider(path, relative);
  }
  for (final path in recentSet) {
    consider(path, relativeOf(path));
  }
  scored.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    final byLength = a.relative.length.compareTo(b.relative.length);
    return byLength != 0 ? byLength : a.relative.compareTo(b.relative);
  });
  final items = [
    for (final entry in scored.take(limit))
      item(
        entry.path,
        entry.relative,
        label: entry.label,
        description: entry.description,
      ),
  ];
  if (items.isEmpty) {
    items.add(
      IdeQuickPickItem(
        label: index.loading && !index.loaded
            ? strings.quickOpenLoadingFiles
            : index.searching
            ? strings.quickOpenSearchingFiles
            : strings.quickOpenNoMatchingResults,
      ),
    );
  }
  if (index.truncated) {
    items.add(
      IdeQuickPickItem(label: strings.quickOpenTooManyFiles(index.count)),
    );
  }
  return items;
}

/// Rows for the editor pickers (the `edt ` prefixes; upstream
/// editorQuickAccess.ts `BaseEditorQuickAccessProvider._getPicks`):
/// [editors] in the order the picker lists them, those matching [filter]
/// on their name and folder, best first. [onOpen] brings one to the front,
/// with [inBackground] while the picker stays (upstream `accept` with
/// `preserveFocus: event.inBackground`). Messages are in [l10n]'s language
/// (English when null).
///
/// Deviations: no close buttons, dirty or preview marks, and no groups.
List<IdeQuickPickItem> editorQuickPicks(
  String filter, {
  required List<IdeDocument> editors,
  required String root,
  required void Function(IdeDocument doc, {required bool inBackground}) onOpen,
  AppLocalizations? l10n,
  p.Context? paths,
}) {
  final pathContext = paths ?? p.context;
  final strings = l10n ?? englishLocalizations;
  final query = IdeQuickOpenQuery._normalize(filter);
  final scored =
      <({IdeDocument doc, int score, List<int> label, List<int> folder})>[];
  for (final doc in editors) {
    final folder = _folderOf(doc.path, root, pathContext);
    if (query.isEmpty) {
      scored.add((doc: doc, score: 0, label: const [], folder: const []));
      continue;
    }
    final result = scoreFilePath(
      query,
      folder == null ? doc.title : '$folder/${doc.title}',
    );
    if (result == null) continue;
    scored.add((
      doc: doc,
      score: result.score,
      label: result.label,
      folder: result.description,
    ));
  }
  if (query.isNotEmpty) {
    // Stable: equal scores keep the picker's order.
    final order = {for (final (i, entry) in scored.indexed) entry.doc: i};
    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : order[a.doc]!.compareTo(order[b.doc]!);
    });
  }
  if (scored.isEmpty) {
    return [IdeQuickPickItem(label: strings.quickOpenNoMatchingEditors)];
  }
  return [
    for (final entry in scored)
      IdeQuickPickItem(
        label: entry.doc.title,
        labelMatches: entry.label,
        description: _folderOf(entry.doc.path, root, pathContext),
        descriptionMatches: entry.folder,
        icon: FileIcon(entry.doc.path, size: 16),
        onAccept: () => onOpen(entry.doc, inBackground: false),
        onAcceptInBackground: () => onOpen(entry.doc, inBackground: true),
      ),
  ];
}

/// [path]'s folder relative to [root], `/`-separated; null at the root.
String? _folderOf(String path, String root, p.Context paths) {
  final folder = paths
      .relative(paths.dirname(path), from: root)
      .replaceAll(r'\', '/');
  return folder == '.' ? null : folder;
}

/// Rows for Go to Line (the `:` prefix), for a document of [lineCount] lines
/// whose caret is at [currentLine]:[currentColumn]. Negative lines count from
/// the end, as in VS Code. Messages are in [l10n]'s language (English when
/// null).
List<IdeQuickPickItem> gotoLineQuickPicks(
  String text, {
  required int? lineCount,
  int currentLine = 1,
  int currentColumn = 1,
  required void Function(int line, int? column) onGo,
  AppLocalizations? l10n,
}) {
  final strings = l10n ?? englishLocalizations;
  if (lineCount == null) {
    return [IdeQuickPickItem(label: strings.gotoLineNoEditor)];
  }
  final query = IdeQuickOpenQuery.parse(':$text');
  var line = query.line;
  if (line == null || line == 0) {
    return [
      IdeQuickPickItem(
        label: strings.gotoLineCurrent(currentLine, currentColumn, lineCount),
      ),
    ];
  }
  if (line < 0) line = lineCount + line + 1;
  line = line.clamp(1, lineCount);
  final column = query.column;
  final target = line;
  return [
    IdeQuickPickItem(
      label: column == null
          ? strings.gotoLineLine(target)
          : strings.gotoLineLineAndCharacter(target, column),
      onAccept: () => onGo(target, column),
    ),
  ];
}

/// Rows for the command palette (the `>` prefix). Recently run commands come
/// first while the filter is empty; [onRun] records and runs a command.
///
/// Titles are in [l10n]'s language (English when null); a query matches the
/// localized title or the English one, which is shown after it when it
/// differs (upstream `commandAlias`).
List<IdeQuickPickItem> commandQuickPicks(
  String filter, {
  required List<IdeCommand> commands,
  required IdeRecentList recent,
  required void Function(IdeCommand command) onRun,
  AppLocalizations? l10n,
}) {
  final strings = l10n ?? englishLocalizations;
  final query = filter.trim();
  final enabled = [
    for (final command in commands)
      if (command.enabled) command,
  ];
  final titles = {
    for (final command in enabled)
      command: l10n == null
          ? command.title
          : localizedCommandTitle(l10n, command),
  };
  String titleOf(IdeCommand command) => titles[command]!;
  String? aliasOf(IdeCommand command) =>
      titleOf(command) == command.title ? null : command.title;
  IdeQuickPickItem item(
    IdeCommand command, {
    List<int> matches = const [],
    List<int> aliasMatches = const [],
    String? group,
  }) => IdeQuickPickItem(
    label: titleOf(command),
    labelMatches: matches,
    description: aliasOf(command),
    descriptionMatches: aliasMatches,
    keybinding: command.shortcutLabel(),
    group: group,
    onAccept: () => onRun(command),
  );

  if (query.isEmpty) {
    final byId = {for (final command in enabled) command.id: command};
    final recents = [for (final id in recent.items) ?byId[id]];
    final rest = enabled.where((command) => !recents.contains(command)).toList()
      ..sort((a, b) => titleOf(a).compareTo(titleOf(b)));
    return [
      for (final (i, command) in recents.indexed)
        item(command, group: i == 0 ? strings.quickOpenRecentlyUsed : null),
      for (final (i, command) in rest.indexed)
        item(
          command,
          group: i == 0 && recents.isNotEmpty
              ? strings.quickOpenOtherCommands
              : null,
        ),
    ];
  }

  final scored = <(IdeCommand, int, IdeFuzzyMatch?, IdeFuzzyMatch?)>[];
  for (final command in enabled) {
    final match = ideFuzzyMatch(query, titleOf(command));
    final alias = aliasOf(command);
    final aliasMatch = alias == null ? null : ideFuzzyMatch(query, alias);
    if (match == null && aliasMatch == null) continue;
    final score = math.max(
      match?.score ?? aliasMatch!.score,
      aliasMatch?.score ?? match!.score,
    );
    scored.add((command, score, match, aliasMatch));
  }
  int recency(IdeCommand command) {
    final at = recent.indexOf(command.id);
    return at < 0 ? 1 << 20 : at;
  }

  scored.sort((a, b) {
    final byScore = b.$2.compareTo(a.$2);
    if (byScore != 0) return byScore;
    final byRecent = recency(a.$1).compareTo(recency(b.$1));
    return byRecent != 0 ? byRecent : titleOf(a.$1).compareTo(titleOf(b.$1));
  });
  if (scored.isEmpty) {
    return [IdeQuickPickItem(label: strings.quickOpenNoMatchingCommands)];
  }
  return [
    for (final (command, _, match, aliasMatch) in scored)
      item(
        command,
        matches: match?.positions ?? const [],
        aliasMatches: aliasMatch?.positions ?? const [],
      ),
  ];
}
