// The Search view as the workbench has it (upstream `SearchView` with
// `ISearchViewModelWorkbenchService` and searchActions*.ts): its inputs and
// results kept while other views show, searched where the workspace's
// files are, and found in from a command, a folder or the next result.
//
// Deviations:
// - Find in Files and Replace in Files do not take the editor's selection
//   for the search (the editor does not give it); Find in Files'
//   `onlyOpenEditors` is not supported.

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../file_service.dart' show IdeHostFiles;
import '../ide_workspace.dart';
import '../lsp/lsp_protocol.dart';
import '../search/ide_search_view.dart';
import '../search/text_search.dart';
import '../workbench/contributions.dart';
import '../workbench/services.dart';
import '../workbench/storage.dart';
import '../workbench/views.dart';
import 'editors.dart';
import 'layout.dart';

class SearchViewService
    implements WorkbenchStorageParticipant, WorkbenchDisposable {
  SearchViewService({
    required this.host,
    required this.layout,
    required this.editors,
    required this._workspace,
    required this._textSearch,
    required this._storage,
  }) {
    session.keptChanges.addListener(_storage.changed);
  }

  final WorkbenchHost host;
  final LayoutService layout;
  final EditorService editors;
  final IdeWorkspace Function() _workspace;
  IdeWorkspace get workspace => _workspace();

  /// The search engine for a folder on this machine.
  final IdeTextSearch Function() _textSearch;
  final WorkbenchStorage _storage;

  /// The view's inputs and results, while other views show.
  late final IdeSearchSession session = IdeSearchSession(
    engine: (root, query) => switch (workspace) {
      // A multi-folder workspace's folders, each searched.
      final IdeWorkspace workspace when workspace.isMultiRoot => searchFolders(
        workspace.roots,
        query,
        _textSearch(),
      ),
      // A remote project's files are searched there.
      IdeWorkspace(hasFolder: true, files: final IdeHostFiles files) =>
        files.searchText(root, query),
      IdeWorkspace(hasFolder: true) => _textSearch()(root, query),
      _ => _searchOpenFiles(query),
    },
    // The results follow their files: an open one's text in the editor,
    // unsaved edits and all, as upstream's; others' on disk.
    read: (path) async =>
        _openFileDocument(path)?.text ?? workspace.files.read(path),
    watch: (directory) => workspace.watchFolder(directory),
  );

  /// The view's widget, while it shows.
  final viewKey = GlobalKey<IdeSearchViewState>();
  IdeSearchViewState? get view => viewKey.currentState;

  IdeDocument? _openFileDocument(String path) => workspace.documents
      .where((doc) => doc.isFile && doc.path == path)
      .firstOrNull;

  /// Whether the view shows in the side bar.
  bool get visible => layout.sidebarShown && layout.view == IdeSideView.search;

  /// Search without a folder: the open files' text, as upstream searches
  /// the open editors alone in an empty window.
  Stream<Object> _searchOpenFiles(IdeTextQuery query) async* {
    final pattern = query.toRegExp();
    var count = 0;
    var limitHit = false;
    final searched = <String>{};
    for (final doc in [...workspace.documents]) {
      if (!doc.isFile || !searched.add(doc.path)) continue;
      final left = query.maxResults - count;
      final matches = ideMatchLines(
        doc.text,
        pattern,
        // One more: whether the limit cut it short.
        limit: left + 1,
        multiline: query.isMultiline,
      );
      if (matches.length > left) {
        limitHit = true;
        matches.removeRange(left, matches.length);
      }
      count += matches.length;
      if (matches.isNotEmpty) yield IdeFileMatches(doc.path, matches);
      if (limitHit) break;
    }
    yield IdeTextSearchComplete(limitHit: limitHit);
  }

  /// The results of the open files matched again, after they were edited
  /// or read again; and of those just closed, their unsaved edits perhaps
  /// discarded.
  void documentsChanged() {
    final open = {
      for (final doc in workspace.documents)
        if (doc.isFile) doc.path,
    };
    session.refresh({...open, ..._searchedOpen});
    _searchedOpen = open;
  }

  Set<String> _searchedOpen = const {};

  /// Find in Files (upstream `findInFilesCommand` with the view): the
  /// view shown with [args]' options (`query`, `replace`,
  /// `triggerSearch`, `filesToInclude`, `isRegex`…), its search input
  /// focused; the replace input shows, with it, when [args] has `replace`,
  /// and is left as it is when not.
  void findInFiles([Object? args]) {
    final options = args is Map ? args : const {};
    T? option<T>(String name) => switch (options[name]) {
      final T value => value,
      _ => null,
    };
    final replace = option<String>('replace');
    if (replace != null) {
      session.replaceShown = true;
      session.replace.text = replace;
    }
    if (option<bool>('isCaseSensitive') case final value?) {
      session.matchCase = value;
    }
    if (option<bool>('matchWholeWord') case final value?) {
      session.wholeWord = value;
    }
    if (option<bool>('isRegex') case final value?) session.useRegExp = value;
    if (option<String>('filesToInclude') case final value?) {
      session.includes.text = value;
    }
    if (option<String>('filesToExclude') case final value?) {
      session.excludes.text = value;
    }
    if (option<String>('query') case final value?) session.query.text = value;
    if (option<bool>('preserveCase') case final value?) {
      session.preserveCase = value;
    }
    if (option<bool>('useExcludeSettingsAndIgnoreFiles') case final value?) {
      session.useExcludesAndIgnoreFiles = value;
    }
    if (option<bool>('showIncludesExcludes') case final value?) {
      session.detailsShown = value;
    } else if (session.includes.text.isNotEmpty ||
        session.excludes.text.isNotEmpty) {
      // Files to include or exclude: shown, not to be missed.
      session.detailsShown = true;
    }
    layout.showView(IdeSideView.search);
    session.requestFocus();
    if (option<bool>('triggerSearch') ?? false) {
      session.search(workspace.root);
    }
  }

  /// Replace in Files: the view with its replace input shown, its search
  /// input focused (upstream `findOrReplaceInFiles`).
  void replaceInFiles() {
    session.replaceShown = true;
    layout.showView(IdeSideView.search);
    session.requestFocus();
  }

  /// Find in Folder…: the view shown, searching in [folder] (the
  /// explorer's).
  void findInFolder(String folder) {
    final workspace = this.workspace;
    final relative = workspace.isMultiRoot
        ? workspace.relativePath(folder)
        : workspace.paths.relative(folder, from: workspace.root);
    session.findInFolder(relative == '.' ? '' : relative, workspace.root);
    layout.showView(IdeSideView.search);
  }

  /// Focus Next / Previous Search Result (F4 / ⇧F4): the view shown (not
  /// focused), its next match selected and shown in the editor, which
  /// keeps the keyboard where it is.
  void focusResult({required bool next}) {
    if (!visible) layout.showView(IdeSideView.search);
    final row = session.selectMatch(next: next);
    final match = row?.$2;
    if (row == null || match == null) return;
    unawaited(
      editors.open(
        row.$1.path,
        range: LspRange(
          LspPosition(match.line, match.start),
          LspPosition(match.line, match.end),
        ),
        select: true,
      ),
    );
  }

  /// The results' list focused (Focus List), the view shown.
  void focusResults() {
    layout.showView(IdeSideView.search);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (host.context != null) view?.moveFocusToResults();
    });
  }

  /// A search toggle flipped, and the search run again.
  void toggleOption(void Function(IdeSearchSession session) flip) {
    flip(session);
    session.search(workspace.root);
  }

  /// The view's context keys (upstream `SearchViewVisibleKey`,
  /// `HasSearchResults`…); null for others.
  Object? contextKey(String key) {
    final visible = this.visible;
    return switch (key) {
      'searchViewletVisible' => visible,
      'searchViewletFocus' => visible && layout.sidebarFocus.hasFocus,
      'replaceActive' => visible && session.replaceShown,
      'hasSearchResult' => session.results.isNotEmpty,
      'viewHasSearchPattern' => session.query.text.isNotEmpty,
      'viewHasReplacePattern' => session.replace.text.isNotEmpty,
      'viewHasFilePattern' =>
        session.includes.text.isNotEmpty || session.excludes.text.isNotEmpty,
      'viewHasSomeCollapsibleResult' =>
        session.results.isNotEmpty && session.anyExpanded,
      'inputBoxFocus' ||
      'searchInputBoxFocus' ||
      'replaceInputBoxFocus' ||
      'patternIncludesInputBoxFocus' ||
      'patternExcludesInputBoxFocus' ||
      'firstMatchFocus' ||
      'fileMatchOrMatchFocus' ||
      'fileMatchOrFolderMatchFocus' ||
      'fileMatchOrFolderMatchWithResourceFocus' ||
      'fileMatchFocus' ||
      'folderMatchFocus' ||
      'matchFocus' ||
      'isEditableItem' => view?.contextKey(key) ?? false,
      _ => null,
    };
  }

  @override
  void restoreState(Map<String, Object?> kept) =>
      session.restore(kept['search']);

  @override
  void saveState(Map<String, Object?> into) {
    final search = session.kept;
    if (search.isNotEmpty) into['search'] = search;
  }

  @override
  void dispose() {
    session.keptChanges.removeListener(_storage.changed);
    session.dispose();
  }
}

/// Searches each of [roots] with [search], as one search: the matches of
/// all, then one end (cut short if any was).
Stream<Object> searchFolders(
  List<String> roots,
  IdeTextQuery query,
  IdeTextSearch search,
) {
  if (roots.isEmpty) {
    return Stream.value(const IdeTextSearchComplete(limitHit: false));
  }
  late final StreamController<Object> controller;
  final subscriptions = <StreamSubscription<Object>>[];
  var open = roots.length;
  var limitHit = false;
  void ended() {
    if (--open > 0) return;
    controller
      ..add(IdeTextSearchComplete(limitHit: limitHit))
      ..close();
  }

  controller = StreamController<Object>(
    onListen: () {
      for (final root in roots) {
        subscriptions.add(
          search(root, query).listen(
            (event) {
              if (event is IdeTextSearchComplete) {
                limitHit |= event.limitHit;
              } else {
                controller.add(event);
              }
            },
            onError: controller.addError,
            onDone: ended,
          ),
        );
      }
    },
    onCancel: () async {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    },
  );
  return controller.stream;
}
