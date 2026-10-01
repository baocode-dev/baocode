import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../l10n/command_titles.dart';
import '../l10n/l10n.dart';
import 'file_service.dart';
import 'ide_commands.dart';
import '../theme/material_file_icons.dart';
import 'ide_fuzzy.dart';
import 'ide_quick_input.dart';
import 'ide_workspace.dart';

/// A cached listing of the project's files for Quick Open. The cache is shown
/// at once and refreshed in the background each time Quick Open opens.
class IdeFileIndex extends ChangeNotifier {
  IdeFileIndex(
    this.files,
    this.root, {
    Future<IdeFileListing> Function(IdeFileService files, String root)? lister,
  }) : _lister = lister ?? listProjectFiles;

  final IdeFileService files;
  final String root;
  final Future<IdeFileListing> Function(IdeFileService, String) _lister;

  List<String> _paths = const [];
  List<String> _relative = const [];
  Set<String>? _pathSet;

  /// The last filter, and the indices of the paths it matched: a filter
  /// typed on from it matches only among those.
  String _lastFilter = '';
  List<int>? _lastMatches;
  bool _truncated = false;
  bool _loaded = false;
  Future<void>? _pending;
  bool _disposed = false;

  /// Absolute paths, sorted.
  List<String> get paths => _paths;

  /// [paths] relative to [root], with `/` separators, same order.
  List<String> get relativePaths => _relative;
  bool get truncated => _truncated;
  bool get loaded => _loaded;
  bool get loading => _pending != null;

  /// Whether [path] is one of [paths].
  bool contains(String path) => (_pathSet ??= _paths.toSet()).contains(path);

  /// The indices of the paths that may match [filter] (a subsequence of
  /// their relative path): those the last filter matched when [filter]
  /// extends it, else all.
  Iterable<int> _candidates(String filter) {
    final last = _lastMatches;
    if (last != null && filter.startsWith(_lastFilter)) return last;
    return Iterable<int>.generate(_paths.length);
  }

  void _matched(String filter, List<int> matches) {
    _lastFilter = filter;
    _lastMatches = matches;
  }

  /// Starts a new listing unless one is already running.
  Future<void> refresh() => _pending ??= _load();

  Future<void> _load() async {
    try {
      final listing = await _lister(files, root);
      if (_disposed) return;
      _paths = listing.paths;
      _relative = [
        for (final path in listing.paths)
          p.relative(path, from: root).replaceAll(r'\', '/'),
      ];
      _truncated = listing.truncated;
      _loaded = true;
      _pathSet = null;
      _lastMatches = null;
    } catch (_) {
      // Keep the previous listing; Quick Open still offers recent files.
    } finally {
      _pending = null;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
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
  final root = index.root;
  String relativeOf(String path) =>
      p.relative(path, from: root).replaceAll(r'\', '/');

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
    for (var i = 0; i < index.paths.length && items.length < limit; i++) {
      if (!seen.add(index.paths[i])) continue;
      items.add(
        item(
          index.paths[i],
          index.relativePaths[i],
          group: first ? strings.quickOpenFiles : null,
        ),
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

  final matches = <int>[];
  for (final i in index._candidates(query.filter)) {
    if (consider(index.paths[i], index.relativePaths[i])) matches.add(i);
  }
  index._matched(query.filter, matches);
  for (final path in recent) {
    if (!index.contains(path)) consider(path, relativeOf(path));
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
            : strings.quickOpenNoMatchingResults,
      ),
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
}) {
  final strings = l10n ?? englishLocalizations;
  final query = IdeQuickOpenQuery._normalize(filter);
  final scored =
      <({IdeDocument doc, int score, List<int> label, List<int> folder})>[];
  for (final doc in editors) {
    final folder = _folderOf(doc.path, root);
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
        description: _folderOf(entry.doc.path, root),
        descriptionMatches: entry.folder,
        icon: FileIcon(entry.doc.path, size: 16),
        onAccept: () => onOpen(entry.doc, inBackground: false),
        onAcceptInBackground: () => onOpen(entry.doc, inBackground: true),
      ),
  ];
}

/// [path]'s folder relative to [root], `/`-separated; null at the root.
String? _folderOf(String path, String root) {
  final folder = p.relative(p.dirname(path), from: root).replaceAll(r'\', '/');
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
