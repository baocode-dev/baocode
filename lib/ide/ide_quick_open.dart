import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'file_service.dart';
import 'ide_commands.dart';
import '../theme/material_file_icons.dart';
import 'ide_fuzzy.dart';
import 'ide_quick_input.dart';

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
/// paths; [onOpen] opens a file at an optional one-based line and column.
List<IdeQuickPickItem> fileQuickPicks(
  String text, {
  required IdeFileIndex index,
  required List<String> recent,
  required void Function(String path, int? line, int? column) onOpen,
  int limit = 200,
}) {
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
          group: items.isEmpty ? 'recently opened' : null,
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
          group: first ? 'files' : null,
        ),
      );
      first = false;
    }
    if (items.isEmpty) {
      items.add(
        IdeQuickPickItem(
          label: index.loading ? 'Loading files…' : 'No files in this project',
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
  final indexed = <String>{};
  void consider(String path, String relative) {
    final result = scoreFilePath(query.filter, relative);
    if (result == null) return;
    final rank = recentRank[path];
    scored.add((
      path: path,
      relative: relative,
      score: result.score + (rank == null ? 0 : 300 - (rank * 5).clamp(0, 150)),
      label: result.label,
      description: result.description,
    ));
  }

  for (var i = 0; i < index.paths.length; i++) {
    indexed.add(index.paths[i]);
    consider(index.paths[i], index.relativePaths[i]);
  }
  for (final path in recent) {
    if (!indexed.contains(path)) consider(path, relativeOf(path));
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
            ? 'Loading files…'
            : 'No matching results',
      ),
    );
  }
  return items;
}

/// Rows for Go to Line (the `:` prefix), for a document of [lineCount] lines
/// whose caret is at [currentLine]:[currentColumn]. Negative lines count from
/// the end, as in VS Code.
List<IdeQuickPickItem> gotoLineQuickPicks(
  String text, {
  required int? lineCount,
  int currentLine = 1,
  int currentColumn = 1,
  required void Function(int line, int? column) onGo,
}) {
  if (lineCount == null) {
    return const [
      IdeQuickPickItem(label: 'Open a text editor first to go to a line.'),
    ];
  }
  final query = IdeQuickOpenQuery.parse(':$text');
  var line = query.line;
  if (line == null || line == 0) {
    return [
      IdeQuickPickItem(
        label:
            'Current Line: $currentLine, Character: $currentColumn. '
            'Type a line number between 1 and $lineCount to navigate to.',
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
          ? 'Go to line $target.'
          : 'Go to line $target and character $column.',
      onAccept: () => onGo(target, column),
    ),
  ];
}

/// Rows for the command palette (the `>` prefix). Recently run commands come
/// first while the filter is empty; [onRun] records and runs a command.
List<IdeQuickPickItem> commandQuickPicks(
  String filter, {
  required List<IdeCommand> commands,
  required IdeRecentList recent,
  required void Function(IdeCommand command) onRun,
}) {
  final query = filter.trim();
  final enabled = [
    for (final command in commands)
      if (command.enabled) command,
  ];
  IdeQuickPickItem item(
    IdeCommand command, {
    List<int> matches = const [],
    String? group,
  }) => IdeQuickPickItem(
    label: command.title,
    labelMatches: matches,
    keybinding: command.shortcutLabel(),
    group: group,
    onAccept: () => onRun(command),
  );

  if (query.isEmpty) {
    final byId = {for (final command in enabled) command.id: command};
    final recents = [for (final id in recent.items) ?byId[id]];
    final rest = enabled.where((command) => !recents.contains(command)).toList()
      ..sort((a, b) => a.title.compareTo(b.title));
    return [
      for (final (i, command) in recents.indexed)
        item(command, group: i == 0 ? 'recently used' : null),
      for (final (i, command) in rest.indexed)
        item(
          command,
          group: i == 0 && recents.isNotEmpty ? 'other commands' : null,
        ),
    ];
  }

  final scored = <(IdeCommand, IdeFuzzyMatch)>[];
  for (final command in enabled) {
    final match = ideFuzzyMatch(query, command.title);
    if (match != null) scored.add((command, match));
  }
  int recency(IdeCommand command) {
    final at = recent.indexOf(command.id);
    return at < 0 ? 1 << 20 : at;
  }

  scored.sort((a, b) {
    final byScore = b.$2.score.compareTo(a.$2.score);
    if (byScore != 0) return byScore;
    final byRecent = recency(a.$1).compareTo(recency(b.$1));
    return byRecent != 0 ? byRecent : a.$1.title.compareTo(b.$1.title);
  });
  if (scored.isEmpty) {
    return const [IdeQuickPickItem(label: 'No matching commands')];
  }
  return [
    for (final (command, match) in scored)
      item(command, matches: match.positions),
  ];
}
