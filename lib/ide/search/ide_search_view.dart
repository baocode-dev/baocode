/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The Search view: the search and replace inputs with their toggles, the
// files to include and exclude, the message, and the results by file with
// each match's preview and actions.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/contrib/search/browser/searchView.ts, searchWidget.ts,
// patternInputWidget.ts, searchResultsView.ts, searchActions*.ts and
// media/searchview.css. What the keyboard does here are the workbench's
// commands (ide_workbench_keys.dart), on [IdeSearchViewState]'s
// `focusNextInputBox`, `moveFocusToResults`… as upstream's on `SearchView`.
//
// Deviations: results are a list of files (no tree of folders), there is
// no search editor or search history, "Search only in Open Editors" is
// not offered, replacing does not preview a diff, and one row of the
// results is both focused and selected.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../keybindings/keybinding_service.dart';
import '../../l10n/l10n.dart';
import '../../theme/codicons.dart';
import '../../theme/app_theme.dart';
import '../../theme/material_file_icons.dart';
import '../../theme/workbench_theme.dart';
import '../ide_commands.dart' show ideWithKeybinding;
import '../ide_dialog.dart';
import '../ide_hover.dart';
import '../ide_input.dart';
import '../ide_list.dart';
import '../ide_menu.dart';
import '../ide_panes.dart';
import '../ide_workspace.dart';
import '../lsp/lsp_protocol.dart';
import 'text_search.dart';

/// The inputs of the Search view, for [IdeSearchSession.requestFocus].
enum IdeSearchInput { query, replace }

/// A row of the results: a file's, or one of its matches.
typedef IdeSearchRow = (IdeSearchFileResult file, IdeTextMatch? match);

/// A file's results: its matches, less those dismissed or replaced.
class IdeSearchFileResult {
  IdeSearchFileResult(this.path, this.matches);

  final String path;
  final List<IdeTextMatch> matches;
}

/// The Search view's inputs and results, kept by the workbench while other
/// views show; it runs the searches.
class IdeSearchSession extends ChangeNotifier {
  IdeSearchSession({this.engine = ideSearchText});

  final IdeTextSearch engine;

  final query = TextEditingController();
  final replace = TextEditingController();
  final includes = TextEditingController();
  final excludes = TextEditingController();

  bool matchCase = false;
  bool wholeWord = false;
  bool useRegExp = false;
  bool preserveCase = false;
  bool useExcludesAndIgnoreFiles = true;
  // All of it shows at first: the replace input, and the files to include
  // and exclude (a deviation: upstream's are folded away).
  bool replaceShown = true;
  bool detailsShown = true;

  final List<IdeSearchFileResult> results = [];
  final Set<String> collapsed = {};

  /// The last search's query, while its results show.
  IdeTextQuery? searched;
  bool searching = false;
  bool limitHit = false;

  /// Why the search failed (an invalid expression).
  String? error;

  /// After Replace All: what was replaced.
  String? replaced;

  /// Asks the view to focus [focusInput] (see [requestFocus]), once it
  /// shows if it does not: the view handles requests up to
  /// [focusHandled].
  int focusRequest = 0;
  int focusHandled = 0;
  IdeSearchInput focusInput = IdeSearchInput.query;

  /// The selected (focused) row of the results: a file's path, and one of
  /// its matches or none for the file's row.
  (String, IdeTextMatch?)? selected;

  StreamSubscription<Object>? _search;
  Timer? _debounce;
  bool _disposed = false;

  int get matchCount =>
      results.fold(0, (count, file) => count + file.matches.length);

  IdeTextQuery get currentQuery => IdeTextQuery(
    query.text,
    isRegExp: useRegExp,
    isCaseSensitive: matchCase,
    isWordMatch: wholeWord,
    includes: includes.text,
    excludes: excludes.text,
    useExcludesAndIgnoreFiles: useExcludesAndIgnoreFiles,
  );

  /// The query as a regular expression; null (and [error]) when invalid.
  RegExp? get regExp {
    try {
      return currentQuery.toRegExp();
    } on FormatException {
      return null;
    }
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  /// The rows the results show: each file's, then its matches unless it
  /// is collapsed.
  List<IdeSearchRow> get rows => [
    for (final file in results) ...[
      (file, null),
      if (!collapsed.contains(file.path))
        for (final match in file.matches) (file, match),
    ],
  ];

  /// The [selected] row's index in [rows]; -1 when none shows.
  int get selectedIndex {
    final selected = this.selected;
    if (selected == null) return -1;
    return rows.indexWhere(
      (row) => row.$1.path == selected.$1 && row.$2 == selected.$2,
    );
  }

  /// Whether a file shows its matches (upstream
  /// `viewHasSomeCollapsibleResult`).
  bool get anyExpanded => collapsed.length < results.length;

  /// Asks the view (shown, or once it shows) to focus [input].
  void requestFocus([IdeSearchInput input = IdeSearchInput.query]) {
    focusInput = input;
    focusRequest++;
    _changed();
  }

  /// Selects [row] (none: null).
  void select(IdeSearchRow? row) {
    selected = row == null ? null : (row.$1.path, row.$2);
    _changed();
  }

  /// Selects the next (or previous) match, expanding its file, from the
  /// selected row, around the ends (upstream `SearchView.selectNextMatch`
  /// and `selectPreviousMatch`); null when there are none.
  IdeSearchRow? selectMatch({required bool next}) {
    final all = [
      for (final file in results)
        for (final match in file.matches) (file, match),
    ];
    if (all.isEmpty) return null;
    final selected = this.selected;
    var at = selected == null
        ? -1
        : all.indexWhere(
            (row) => row.$1.path == selected.$1 && row.$2 == selected.$2,
          );
    if (at < 0 && selected != null) {
      // A file's row: its first match is next, the match before it
      // previous.
      final first = all.indexWhere((row) => row.$1.path == selected.$1);
      at = next ? first - 1 : first;
    }
    final index = next
        ? (at + 1) % all.length
        : (at < 0 ? all.length - 1 : (at - 1) % all.length);
    final row = all[index];
    collapsed.remove(row.$1.path);
    this.selected = (row.$1.path, row.$2);
    _changed();
    return row;
  }

  /// Cancel Search: the search running stops, with the results so far.
  void cancel() {
    _debounce?.cancel();
    unawaited(_search?.cancel());
    _search = null;
    if (!searching) return;
    searching = false;
    _changed();
  }

  /// `search.searchOnType`: searches 300ms after the last change.
  void searchSoon(String root) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => search(root));
  }

  /// Searches under [root] now, replacing the results.
  void search(String root) {
    _debounce?.cancel();
    unawaited(_search?.cancel());
    _search = null;
    results.clear();
    collapsed.clear();
    limitHit = false;
    error = null;
    replaced = null;
    final query = currentQuery;
    if (query.pattern.isEmpty) {
      searched = null;
      searching = false;
      _changed();
      return;
    }
    try {
      query.toRegExp();
    } on FormatException catch (e) {
      searched = null;
      searching = false;
      error = e.message;
      _changed();
      return;
    }
    searched = query;
    searching = true;
    _changed();
    _search = engine(root, query).listen(
      (event) {
        switch (event) {
          case IdeFileMatches(:final path, :final matches):
            final index = results.indexWhere(
              (file) => _comparePaths(file.path, path) > 0,
            );
            final result = IdeSearchFileResult(path, [...matches]);
            if (index < 0) {
              results.add(result);
            } else {
              results.insert(index, result);
            }
          case IdeTextSearchComplete(:final limitHit):
            this.limitHit = limitHit;
            searching = false;
        }
        _changed();
      },
      onError: (Object e) {
        error = '$e';
        searching = false;
        _changed();
      },
      onDone: () {
        searching = false;
        _changed();
      },
    );
  }

  /// Folders before the files beside them, then by name.
  static int _comparePaths(String a, String b) {
    final aParts = p.split(a);
    final bParts = p.split(b);
    for (var i = 0; i < aParts.length && i < bParts.length; i++) {
      final aLast = i == aParts.length - 1;
      final bLast = i == bParts.length - 1;
      if (aLast != bLast) return aLast ? 1 : -1;
      final order = aParts[i].toLowerCase().compareTo(bParts[i].toLowerCase());
      if (order != 0) return order;
    }
    return aParts.length.compareTo(bParts.length);
  }

  /// Clear Search Results: the inputs too, as VS Code clears them.
  void clear() {
    _debounce?.cancel();
    unawaited(_search?.cancel());
    _search = null;
    query.clear();
    replace.clear();
    results.clear();
    collapsed.clear();
    selected = null;
    searched = null;
    searching = false;
    limitHit = false;
    error = null;
    replaced = null;
    _changed();
  }

  void dismiss(IdeSearchFileResult file, [IdeTextMatch? match]) {
    if (match == null || file.matches.length == 1) {
      results.remove(file);
    } else {
      file.matches.remove(match);
    }
    _changed();
  }

  /// Find in Folder...: searches in [relativeFolder].
  void findInFolder(String relativeFolder, String root) {
    includes.text = relativeFolder.isEmpty ? '' : './$relativeFolder';
    detailsShown = true;
    focusInput = IdeSearchInput.query;
    focusRequest++;
    if (query.text.isNotEmpty) {
      search(root);
    } else {
      _changed();
    }
  }

  void toggleCollapsed(String path) {
    if (!collapsed.remove(path)) collapsed.add(path);
    _changed();
  }

  /// Collapse All when anything is expanded, else Expand All.
  void toggleCollapseAll() => anyExpanded ? collapseAll() : expandAll();

  /// Collapse All: a match selected gives way to its file.
  void collapseAll() {
    collapsed.addAll(results.map((file) => file.path));
    if (selected case (final path, _?)) selected = (path, null);
    _changed();
  }

  void expandAll() {
    collapsed.clear();
    _changed();
  }

  void notify() => _changed();

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    unawaited(_search?.cancel());
    query.dispose();
    replace.dispose();
    includes.dispose();
    excludes.dispose();
    super.dispose();
  }
}

/// A selected row's text: the list's selection foreground, focused or not;
/// the side bar's where the theme has none.
Color _selectedForeground({required bool focused}) {
  final colors = themeColors;
  return colors.get(
        focused
            ? 'list.activeSelectionForeground'
            : 'list.inactiveSelectionForeground',
      ) ??
      colors['sideBar.foreground'];
}

class IdeSearchView extends StatefulWidget {
  const IdeSearchView({
    super.key,
    required this.session,
    required this.workspace,
    required this.onOpen,
    this.onError,
  });

  final IdeSearchSession session;
  final IdeWorkspace workspace;

  /// Opens a match: its file with [range] selected; [focusEditor] when
  /// double-clicked.
  final Future<void> Function(
    String path,
    LspRange range, {
    required bool focusEditor,
  })
  onOpen;
  final ValueChanged<Object>? onError;

  @override
  State<IdeSearchView> createState() => IdeSearchViewState();
}

/// The Search view's keyboard (upstream `SearchView`'s): its inputs and
/// its results, which the workbench's search commands and `list.*` move
/// in (see [contextKey]).
class IdeSearchViewState extends State<IdeSearchView>
    with IdeKeyboardList<IdeSearchView> {
  final FocusNode _queryFocus = FocusNode(debugLabel: 'search');
  final FocusNode _replaceFocus = FocusNode(debugLabel: 'search replace');
  final FocusNode _includesFocus = FocusNode(debugLabel: 'search include');
  final FocusNode _excludesFocus = FocusNode(debugLabel: 'search exclude');
  final FocusNode _resultsFocus = FocusNode(debugLabel: 'search results');
  final ScrollController _scroll = ScrollController();

  /// The selection last scrolled into view.
  (String, IdeTextMatch?)? _revealed;

  IdeSearchSession get _session => widget.session;
  String get _root => widget.workspace.root;

  List<FocusNode> get _focusNodes => [
    _queryFocus,
    _replaceFocus,
    _includesFocus,
    _excludesFocus,
    _resultsFocus,
  ];

  @override
  void initState() {
    super.initState();
    _session.addListener(_changed);
    for (final node in _focusNodes) {
      node.addListener(_focusChanged);
    }
    _revealed = _session.selected;
    WidgetsBinding.instance.addPostFrameCallback((_) => _changed());
  }

  @override
  void didUpdateWidget(IdeSearchView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session.removeListener(_changed);
      widget.session.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _session.removeListener(_changed);
    for (final node in _focusNodes) {
      node.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  void _focusChanged() {
    if (mounted) setState(() {});
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    final session = _session;
    final focus = session.focusRequest != session.focusHandled;
    final reveal = session.selected != _revealed;
    if (!focus && !reveal) return;
    session.focusHandled = session.focusRequest;
    _revealed = session.selected;
    // After the rebuild: the replace input may show only then.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (focus) {
        _focusSearchWidget(
          replace: session.focusInput == IdeSearchInput.replace,
        );
      }
      if (reveal && session.selectedIndex >= 0) {
        ideRevealRow(_scroll, session.selectedIndex);
      }
    });
  }

  void _toggle(void Function() change) {
    change();
    _session.search(_root);
  }

  /// [command]'s keybinding, for a tooltip or a menu.
  String? _keybinding(String command) =>
      KeybindingService.instance.labelFor(command);

  /// [withKeys]' text with [command]'s keybinding, if it has one.
  String _withKeys(String Function(String keys) withKeys, String command) =>
      ideWithKeybinding(withKeys, _keybinding(command));

  // --- Keyboard ------------------------------------------------------------

  /// The focused row of the results, while they have the keyboard.
  IdeSearchRow? get _focusedRow {
    if (!_resultsFocus.hasFocus) return null;
    final index = _session.selectedIndex;
    return index < 0 ? null : _session.rows[index];
  }

  /// The view's context keys (upstream `Constants.SearchContext`'s that
  /// follow the focus); null for others.
  Object? contextKey(String key) {
    final row = _focusedRow;
    return switch (key) {
      'inputBoxFocus' =>
        _queryFocus.hasFocus ||
            _replaceFocus.hasFocus ||
            _includesFocus.hasFocus ||
            _excludesFocus.hasFocus,
      'searchInputBoxFocus' => _queryFocus.hasFocus,
      'replaceInputBoxFocus' => _replaceFocus.hasFocus,
      'patternIncludesInputBoxFocus' => _includesFocus.hasFocus,
      'patternExcludesInputBoxFocus' => _excludesFocus.hasFocus,
      'firstMatchFocus' => row != null && _session.selectedIndex == 0,
      'fileMatchOrMatchFocus' => row != null,
      'fileMatchOrFolderMatchFocus' ||
      'fileMatchOrFolderMatchWithResourceFocus' ||
      'fileMatchFocus' => row != null && row.$2 == null,
      'matchFocus' => row?.$2 != null,
      'folderMatchFocus' => false,
      'isEditableItem' => true,
      _ => null,
    };
  }

  /// Focuses [node], its text selected (upstream `focus(select: true)`).
  void _focusField(FocusNode node, TextEditingController controller) {
    node.requestFocus();
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );
  }

  /// The search input focused, or the replace input if [replace] and it
  /// shows (upstream `SearchWidget.focus`).
  void _focusSearchWidget({bool replace = false}) {
    if (replace && _session.replaceShown) {
      _focusField(_replaceFocus, _session.replace);
    } else {
      _focusField(_queryFocus, _session.query);
    }
  }

  /// Focus Next Input: search, replace, files to include, files to exclude,
  /// then the results (upstream `focusNextInputBox`).
  void focusNextInputBox() {
    if (_queryFocus.hasFocus) {
      if (_session.replaceShown) {
        _focusSearchWidget(replace: true);
      } else {
        _moveFocusFromSearchOrReplace();
      }
    } else if (_replaceFocus.hasFocus) {
      _moveFocusFromSearchOrReplace();
    } else if (_includesFocus.hasFocus) {
      _focusField(_excludesFocus, _session.excludes);
    } else if (_excludesFocus.hasFocus) {
      moveFocusToResults(selectFirst: true);
    }
  }

  void _moveFocusFromSearchOrReplace() {
    if (_session.detailsShown) {
      _focusField(_includesFocus, _session.includes);
    } else {
      moveFocusToResults(selectFirst: true);
    }
  }

  /// Focus Previous Input, and Focus Search From Results (upstream
  /// `focusPreviousInputBox`).
  void focusPreviousInputBox() {
    if (_replaceFocus.hasFocus) {
      _focusSearchWidget();
    } else if (_includesFocus.hasFocus) {
      _focusSearchWidget(replace: true);
    } else if (_excludesFocus.hasFocus) {
      _focusField(_includesFocus, _session.includes);
    } else if (_resultsFocus.hasFocus) {
      if (_session.detailsShown) {
        _focusField(_excludesFocus, _session.excludes);
      } else {
        _focusSearchWidget(replace: true);
      }
    }
  }

  /// Focus List: the results focused; with [selectFirst], their first row
  /// when none is (upstream `moveFocusToResults`,
  /// `selectTreeIfNotSelected`).
  void moveFocusToResults({bool selectFirst = false}) {
    _resultsFocus.requestFocus();
    final rows = _session.rows;
    if (selectFirst && _session.selectedIndex < 0 && rows.isNotEmpty) {
      _session.select(rows.first);
    }
  }

  /// Toggle Query Details: the files to include and exclude shown, the
  /// first focused, or hidden, the search input focused.
  void toggleQueryDetails({bool? show}) {
    final session = _session;
    session.detailsShown = show ?? !session.detailsShown;
    session.notify();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (session.detailsShown) {
        _focusField(_includesFocus, session.includes);
      } else {
        _focusSearchWidget();
      }
    });
  }

  /// Close Replace Widget: the replace input hidden, the search input
  /// focused.
  void closeReplace() {
    _session.replaceShown = false;
    _session.notify();
    _focusSearchWidget();
  }

  /// Open Match: the focused match, or a file's first, opened in the
  /// editor, which is focused.
  void openFocused() {
    final row = _focusedRow;
    if (row == null) return;
    final match = row.$2 ?? row.$1.matches.firstOrNull;
    if (match != null) unawaited(_openMatch(row.$1, match, focusEditor: true));
  }

  /// Dismiss: the focused row's matches gone from the results, the row
  /// now in its place focused.
  void removeFocused() {
    final index = _session.selectedIndex;
    if (index < 0) return;
    final (file, match) = _session.rows[index];
    _session.dismiss(file, match);
    _focusRowNear(index);
  }

  /// Replace, and Replace All in a file's row: the focused row's matches
  /// replaced, the row now in its place focused.
  void replaceFocused() {
    final index = _session.selectedIndex;
    if (index < 0 || !_session.replaceShown) return;
    final (file, match) = _session.rows[index];
    unawaited(
      _replace({
        file: match == null ? [...file.matches] : [match],
      }).then((_) {
        if (mounted) _focusRowNear(index);
      }),
    );
  }

  void _focusRowNear(int index) {
    final rows = _session.rows;
    _session.select(
      rows.isEmpty ? null : rows[math.min(index, rows.length - 1)],
    );
    _resultsFocus.requestFocus();
  }

  /// Replace All, confirmed.
  void replaceAll() => unawaited(_replaceAll());

  /// Copy: the focused row's text; Copy Path: its file's path; Copy All.
  void copyFocused({bool path = false}) {
    final row = _focusedRow;
    if (row == null) return;
    unawaited(
      Clipboard.setData(
        ClipboardData(text: path ? row.$1.path : _copyText(row.$1, row.$2)),
      ),
    );
  }

  void copyAll() => unawaited(
    Clipboard.setData(
      ClipboardData(
        text: [for (final file in _session.results) _copyText(file)]
            .join('\n\n'),
      ),
    ),
  );

  // --- The results as a list (`list.*`) -------------------------------------

  @override
  bool get listHasFocus => _resultsFocus.hasFocus;

  @override
  int get listLength => _session.rows.length;

  @override
  int get listFocusedIndex => _session.selectedIndex;

  @override
  int get listPageSize => ideRowsPerPage(_scroll);

  @override
  void listFocusAt(int index) => _session.select(_session.rows[index]);

  /// A file's row toggles, a match opens (upstream `selectElement`).
  @override
  void listSelect() {
    final row = _focusedRow;
    if (row == null) return;
    if (row.$2 == null) {
      _session.toggleCollapsed(row.$1.path);
    } else {
      openFocused();
    }
  }

  @override
  void listToggleExpand() {
    final row = _focusedRow;
    if (row != null && row.$2 == null) {
      _session.toggleCollapsed(row.$1.path);
    } else {
      listSelect();
    }
  }

  @override
  void listExpand() {
    final row = _focusedRow;
    if (row == null || row.$2 != null) return;
    if (_session.collapsed.contains(row.$1.path)) {
      _session.toggleCollapsed(row.$1.path);
    } else if (row.$1.matches.isNotEmpty) {
      _session.select((row.$1, row.$1.matches.first));
    }
  }

  @override
  void listCollapse() {
    final row = _focusedRow;
    if (row == null) return;
    if (row.$2 != null) {
      _session.select((row.$1, null));
    } else if (!_session.collapsed.contains(row.$1.path)) {
      _session.toggleCollapsed(row.$1.path);
    }
  }

  @override
  void listCollapseAll() => _session.collapseAll();

  @override
  bool listTreeKey(String key) {
    final row = _focusedRow;
    if (row == null) return false;
    final file = row.$2 == null;
    final expanded = file && !_session.collapsed.contains(row.$1.path);
    return switch (key) {
      'treeElementCanCollapse' => expanded,
      'treeElementCanExpand' => file && !expanded,
      'treeElementHasChild' => expanded && row.$1.matches.isNotEmpty,
      'treeElementHasParent' => !file,
      _ => false,
    };
  }

  // --- Replace -------------------------------------------------------------

  /// Replaces [matches] by file: open documents are edited (and saved
  /// when they had no unsaved changes), other files are rewritten. Returns
  /// how many were replaced.
  Future<int> _replace(
    Map<IdeSearchFileResult, List<IdeTextMatch>> matches,
  ) async {
    final regExp = _session.regExp;
    final searched = _session.searched;
    if (regExp == null || searched == null) return 0;
    final workspace = widget.workspace;
    var count = 0;
    for (final MapEntry(key: file, value: list) in matches.entries) {
      try {
        final open = workspace.documents
            .where((doc) => doc.path == file.path)
            .firstOrNull;
        final text = open?.text ?? await workspace.files.read(file.path);
        final (updated, replaced) = _applyReplace(text, list, regExp);
        if (replaced == 0) continue;
        if (open != null) {
          final wasDirty = open.dirty;
          workspace.edit(file.path, updated);
          if (!wasDirty) await workspace.save(open);
        } else {
          await workspace.files.write(file.path, updated, expectedText: text);
        }
        count += replaced;
        for (final match in list) {
          file.matches.remove(match);
        }
        if (file.matches.isEmpty) _session.results.remove(file);
      } catch (error) {
        widget.onError?.call(error);
      }
    }
    workspace.git?.scheduleRefresh();
    _session.notify();
    return count;
  }

  /// [text] with [matches] replaced, where their lines are unchanged.
  (String, int) _applyReplace(
    String text,
    List<IdeTextMatch> matches,
    RegExp regExp,
  ) {
    final lineStarts = [0];
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 0x0A) lineStarts.add(i + 1);
    }
    final sorted = [...matches]
      ..sort((a, b) => a.line != b.line ? b.line - a.line : b.start - a.start);
    var result = text;
    var count = 0;
    for (final match in sorted) {
      if (match.line >= lineStarts.length) continue;
      final start = lineStarts[match.line];
      if (!text.startsWith(match.text, start)) continue;
      final replacement = ideReplaceString(
        match,
        _session.replace.text,
        regExp: regExp,
        isRegExp: _session.useRegExp,
        preserveCase: _session.preserveCase,
      );
      result = result.replaceRange(
        start + match.start,
        start + match.end,
        replacement,
      );
      count++;
    }
    return (result, count);
  }

  /// Replace All, confirmed as VS Code confirms it.
  Future<void> _replaceAll() async {
    final occurrences = _session.matchCount;
    final files = _session.results.length;
    if (occurrences == 0) return;
    final value = _session.replace.text;
    final l10n = context.l10n;
    final counts = l10n.searchOccurrences(occurrences, files);
    final pick = await showIdeDialog(
      context,
      type: IdeDialogType.question,
      message: value.isEmpty
          ? l10n.searchConfirmReplace(counts)
          : l10n.searchConfirmReplaceWith(counts, value),
      buttons: [l10n.searchReplace],
    );
    if (pick != 0 || !mounted) return;
    final replaced = await _replace({
      for (final file in [..._session.results]) file: [...file.matches],
    });
    if (!mounted) return;
    final done = l10n.searchOccurrences(replaced, files);
    _session.replaced = value.isEmpty
        ? l10n.searchReplaced(done)
        : l10n.searchReplacedWith(done, value);
    _session.notify();
  }

  // --- Widgets -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final anyExpanded = session.anyExpanded;
    // The title's actions are the view's commands: their keybindings in
    // their tooltips (searchActionsTopBar.ts, in `MenuId.ViewTitle`).
    final keys = KeybindingService.instance;
    return ColoredBox(
      color: AppColors.sidebarSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IdeViewTitle(
            context.l10n.searchTitle,
            actions: [
              IdePaneAction(
                icon: Codicons.refresh,
                tooltip: keys.titleWithKeybinding(
                  context.l10n.commonRefresh,
                  'search.action.refreshSearchResults',
                ),
                onPressed: session.query.text.isEmpty
                    ? null
                    : () => session.search(_root),
              ),
              IdePaneAction(
                icon: Codicons.clearAll,
                tooltip: keys.titleWithKeybinding(
                  context.l10n.searchClearResults,
                  'search.action.clearSearchResults',
                ),
                onPressed: session.query.text.isEmpty && session.results.isEmpty
                    ? null
                    : session.clear,
              ),
              IdePaneAction(
                icon: anyExpanded ? Codicons.collapseAll : Codicons.expandAll,
                tooltip: anyExpanded
                    ? keys.titleWithKeybinding(
                        context.l10n.commonCollapseAll,
                        'search.action.collapseSearchResults',
                      )
                    : keys.titleWithKeybinding(
                        context.l10n.commonExpandAll,
                        'search.action.expandSearchResults',
                      ),
                onPressed: session.results.isEmpty
                    ? null
                    : session.toggleCollapseAll,
              ),
            ],
          ),
          SizedBox(
            height: 2,
            child: session.searching
                ? LinearProgressIndicator(
                    minHeight: 2,
                    backgroundColor: Colors.transparent,
                    color: themeColors['progressBar.background'],
                  )
                : null,
          ),
          _widgets(),
          _details(),
          _messages(),
          Expanded(child: _results()),
        ],
      ),
    );
  }

  /// The search and replace inputs' (`textarea.input`), 2px shorter than
  /// the others.
  static const _widgetPadding = EdgeInsets.fromLTRB(6, 3, 0, 3);

  /// `.search-widgets-container`: the replace toggle, and the search and
  /// replace inputs.
  Widget _widgets() {
    final session = _session;
    final regExpError = session.error;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 12, 6),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ToggleReplace(
              expanded: session.replaceShown,
              onPressed: () {
                session.replaceShown = !session.replaceShown;
                session.notify();
              },
            ),
            const SizedBox(width: 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  IdeInputBox(
                    controller: session.query,
                    focusNode: _queryFocus,
                    autofocus: true,
                    placeholder: context.l10n.searchTitle,
                    semanticsLabel: context.l10n.searchTitle,
                    padding: _widgetPadding,
                    validation: regExpError == null
                        ? null
                        : IdeInputValidation(regExpError),
                    onChanged: (_) => session.searchSoon(_root),
                    onSubmitted: (_) => session.search(_root),
                    toggles: [
                      IdeInputToggle(
                        icon: Codicons.caseSensitive,
                        tooltip: _withKeys(
                          context.l10n.searchMatchCase,
                          'toggleSearchCaseSensitive',
                        ),
                        checked: session.matchCase,
                        onChanged: (value) =>
                            _toggle(() => session.matchCase = value),
                      ),
                      IdeInputToggle(
                        icon: Codicons.wholeWord,
                        tooltip: _withKeys(
                          context.l10n.searchMatchWholeWord,
                          'toggleSearchWholeWord',
                        ),
                        checked: session.wholeWord,
                        onChanged: (value) =>
                            _toggle(() => session.wholeWord = value),
                      ),
                      IdeInputToggle(
                        icon: Codicons.regex,
                        tooltip: _withKeys(
                          context.l10n.searchUseRegExp,
                          'toggleSearchRegex',
                        ),
                        checked: session.useRegExp,
                        onChanged: (value) =>
                            _toggle(() => session.useRegExp = value),
                      ),
                    ],
                  ),
                  if (session.replaceShown) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: IdeInputBox(
                            controller: session.replace,
                            focusNode: _replaceFocus,
                            placeholder: context.l10n.searchReplace,
                            semanticsLabel: context.l10n.searchReplace,
                            padding: _widgetPadding,
                            onChanged: (_) => session.notify(),
                            toggles: [
                              IdeInputToggle(
                                icon: Codicons.preserveCase,
                                tooltip: _withKeys(
                                  context.l10n.searchPreserveCase,
                                  'toggleSearchPreserveCase',
                                ),
                                checked: session.preserveCase,
                                onChanged: (value) {
                                  session.preserveCase = value;
                                  session.notify();
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 2),
                        IdeActionButton(
                          icon: Codicons.replaceAll,
                          tooltip: _withKeys(
                            context.l10n.searchReplaceAllKeys,
                            'search.action.replaceAll',
                          ),
                          size: 22,
                          onPressed: session.results.isEmpty
                              ? null
                              : () => unawaited(_replaceAll()),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// `.query-details`: Toggle Search Details, and the files to include and
  /// exclude.
  Widget _details() {
    final session = _session;
    // `.query-details h4`: the side bar's text.
    final heading = TextStyle(
      fontSize: 11,
      color: themeColors['sideBar.foreground'],
    );
    return Padding(
      padding: const EdgeInsets.only(left: 19, right: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            // `right: -2px`.
            child: Transform.translate(
              offset: const Offset(2, 0),
              child: _ToggleDetails(
                expanded: session.detailsShown,
                onPressed: () {
                  session.detailsShown = !session.detailsShown;
                  session.notify();
                },
              ),
            ),
          ),
          if (session.detailsShown) ...[
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 2),
              child: Text(context.l10n.searchFilesToInclude, style: heading),
            ),
            IdeInputBox(
              controller: session.includes,
              focusNode: _includesFocus,
              placeholder: context.l10n.searchIncludeExample,
              semanticsLabel: context.l10n.searchFilesToInclude,
              onChanged: (_) => session.searchSoon(_root),
              onSubmitted: (_) => session.search(_root),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 2),
              child: Text(context.l10n.searchFilesToExclude, style: heading),
            ),
            IdeInputBox(
              controller: session.excludes,
              focusNode: _excludesFocus,
              placeholder: context.l10n.searchExcludeExample,
              semanticsLabel: context.l10n.searchFilesToExclude,
              onChanged: (_) => session.searchSoon(_root),
              onSubmitted: (_) => session.search(_root),
              toggles: [
                IdeInputToggle(
                  icon: Codicons.exclude,
                  tooltip: context.l10n.searchUseExcludeSettings,
                  checked: session.useExcludesAndIgnoreFiles,
                  onChanged: (value) =>
                      _toggle(() => session.useExcludesAndIgnoreFiles = value),
                ),
              ],
            ),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }

  /// `.messages`: the counts, or why there are none.
  Widget _messages() {
    final session = _session;
    final searched = session.searched;
    final l10n = context.l10n;
    final lines = <String>[];
    if (session.replaced case final replaced?) lines.add(replaced);
    if (searched != null && !session.searching) {
      final matches = session.matchCount;
      final files = session.results.length;
      if (session.limitHit) {
        lines.add(l10n.searchLimitHit);
      }
      if (matches > 0) {
        lines.add(l10n.searchResultCount(matches, files));
      } else if (session.replaced == null) {
        final include = searched.includes.trim();
        final exclude = searched.excludes.trim();
        lines.add(switch ((include.isEmpty, exclude.isEmpty)) {
          (false, false) => l10n.searchNoResultsIncludeExclude(
            include,
            exclude,
          ),
          (false, true) => l10n.searchNoResultsInclude(include),
          (true, false) => l10n.searchNoResultsExclude(exclude),
          (true, true) => l10n.searchNoResults,
        });
      }
    }
    if (lines.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: SelectableText(
                line,
                style: TextStyle(
                  fontSize: 13,
                  color: themeColors['search.resultsInfoForeground'],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _results() {
    final session = _session;
    final rows = session.rows;
    final selectedIndex = session.selectedIndex;
    final focused = _resultsFocus.hasFocus;
    final regExp = session.regExp;
    final replaceKeys = _keybinding('search.action.replace');
    final replaceAllKeys = _keybinding('search.action.replaceAllInFile');
    final dismissKeys = _keybinding('search.action.remove');
    return Focus(
      focusNode: _resultsFocus,
      child: ListView.builder(
        controller: _scroll,
        itemExtent: IdeListColors.rowHeight,
        itemCount: rows.length,
        itemBuilder: (context, index) {
          final (file, match) = rows[index];
          final selected = index == selectedIndex;
          void select() {
            _resultsFocus.requestFocus();
            session.select((file, match));
          }

          if (match == null) {
            return _FileRow(
              key: ValueKey(('file', file.path)),
              root: _root,
              file: file,
              expanded: !session.collapsed.contains(file.path),
              selected: selected,
              focused: focused,
              replacing: session.replaceShown,
              replaceAllKeys: replaceAllKeys,
              dismissKeys: dismissKeys,
              onTap: () {
                select();
                session.toggleCollapsed(file.path);
              },
              onReplaceAll: () => unawaited(
                _replace({
                  file: [...file.matches],
                }),
              ),
              onDismiss: () => session.dismiss(file),
              onContextMenu: (position) {
                select();
                unawaited(_showMenu(position, file, null));
              },
            );
          }
          return _MatchRow(
            key: ValueKey(('match', file.path, match.line, match.start)),
            match: match,
            replacement: session.replaceShown && regExp != null
                ? ideReplaceString(
                    match,
                    session.replace.text,
                    regExp: regExp,
                    isRegExp: session.useRegExp,
                    preserveCase: session.preserveCase,
                  )
                : null,
            selected: selected,
            focused: focused,
            replaceKeys: replaceKeys,
            dismissKeys: dismissKeys,
            onTap: () {
              select();
              unawaited(_openMatch(file, match, focusEditor: false));
            },
            onDoubleTap: () =>
                unawaited(_openMatch(file, match, focusEditor: true)),
            onReplace: () => unawaited(
              _replace({
                file: [match],
              }),
            ),
            onDismiss: () => session.dismiss(file, match),
            onContextMenu: (position) {
              select();
              unawaited(_showMenu(position, file, match));
            },
          );
        },
      ),
    );
  }

  Future<void> _openMatch(
    IdeSearchFileResult file,
    IdeTextMatch match, {
    required bool focusEditor,
  }) => widget.onOpen(
    file.path,
    LspRange(
      LspPosition(match.line, match.start),
      LspPosition(match.line, match.end),
    ),
    focusEditor: focusEditor,
  );

  String _copyText(IdeSearchFileResult file, [IdeTextMatch? match]) {
    String line(IdeTextMatch match) =>
        '  ${match.line + 1},${match.start + 1}: ${match.text.trim()}';
    if (match != null) return line(match);
    return [
      p.relative(file.path, from: _root),
      for (final match in file.matches) line(match),
    ].join('\n');
  }

  /// The results' context menu: Copy, Copy Path, Copy All, and Dismiss.
  Future<void> _showMenu(
    Offset position,
    IdeSearchFileResult file,
    IdeTextMatch? match,
  ) => showIdeMenu(
    context,
    position: position,
    entries: ideMenuGroups([
      [
        IdeMenuAction(
          context.l10n.commonCopy,
          keybinding: _keybinding('search.action.copyMatch'),
          onSelected: () => unawaited(
            Clipboard.setData(ClipboardData(text: _copyText(file, match))),
          ),
        ),
        IdeMenuAction(
          context.l10n.tabCopyPath,
          keybinding: _keybinding('search.action.copyPath'),
          onSelected: () =>
              unawaited(Clipboard.setData(ClipboardData(text: file.path))),
        ),
        IdeMenuAction(
          context.l10n.searchCopyAll,
          keybinding: _keybinding('search.action.copyAll'),
          onSelected: copyAll,
        ),
      ],
      [
        if (_session.replaceShown)
          IdeMenuAction(
            match == null
                ? context.l10n.searchReplaceAll
                : context.l10n.searchReplace,
            keybinding: _keybinding(
              match == null
                  ? 'search.action.replaceAllInFile'
                  : 'search.action.replace',
            ),
            onSelected: () => unawaited(
              _replace({
                file: match == null ? [...file.matches] : [match],
              }),
            ),
          ),
        IdeMenuAction(
          context.l10n.searchDismiss,
          keybinding: _keybinding('search.action.remove'),
          onSelected: () => _session.dismiss(file, match),
        ),
      ],
    ]),
  );
}

/// `.toggle-replace-button`: a 16px column with the chevron.
class _ToggleReplace extends StatefulWidget {
  const _ToggleReplace({required this.expanded, required this.onPressed});

  final bool expanded;
  final VoidCallback onPressed;

  @override
  State<_ToggleReplace> createState() => _ToggleReplaceState();
}

class _ToggleReplaceState extends State<_ToggleReplace> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => IdeHover(
    message: context.l10n.searchToggleReplace,
    child: Semantics(
      button: true,
      expanded: widget.expanded,
      label: context.l10n.searchToggleReplace,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: Container(
            width: 16,
            decoration: BoxDecoration(
              color: _hover ? themeColors['toolbar.hoverBackground'] : null,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              widget.expanded ? Codicons.chevronDown : Codicons.chevronRight,
              size: 16,
              color: themeColors['sideBar.foreground'],
            ),
          ),
        ),
      ),
    ),
  );
}

/// `.query-details .more`: a bare 16px codicon in a 25 by 16 box.
class _ToggleDetails extends StatelessWidget {
  const _ToggleDetails({required this.expanded, required this.onPressed});

  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IdeHover(
    // `appendKeybinding` (searchView.ts `renderQueryDetails`).
    message: KeybindingService.instance.titleWithKeybinding(
      context.l10n.searchToggleDetails,
      'workbench.action.search.toggleQueryDetails',
    ),
    child: Semantics(
      button: true,
      expanded: expanded,
      label: context.l10n.searchToggleDetails,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: SizedBox(
            width: 25,
            height: 16,
            child: Icon(
              Codicons.ellipsis,
              size: 16,
              color: themeColors['sideBar.foreground'],
            ),
          ),
        ),
      ),
    ),
  );
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    super.key,
    required this.root,
    required this.file,
    required this.expanded,
    required this.selected,
    required this.focused,
    required this.replacing,
    required this.replaceAllKeys,
    required this.dismissKeys,
    required this.onTap,
    required this.onReplaceAll,
    required this.onDismiss,
    required this.onContextMenu,
  });

  final String root;
  final IdeSearchFileResult file;
  final bool expanded;
  final bool selected;
  final bool focused;
  final bool replacing;

  /// Replace All's and Dismiss's keybindings, for their tooltips.
  final String? replaceAllKeys;
  final String? dismissKeys;
  final VoidCallback onTap;
  final VoidCallback onReplaceAll;
  final VoidCallback onDismiss;
  final ValueChanged<Offset> onContextMenu;

  @override
  Widget build(BuildContext context) {
    final folder = p.relative(p.dirname(file.path), from: root);
    return IdeListRow(
      selected: selected,
      focused: focused,
      onTap: onTap,
      onContextMenu: onContextMenu,
      tooltip: file.path,
      builder: (context, hovered) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Row(
          children: [
            Icon(
              expanded ? Codicons.chevronDown : Codicons.chevronRight,
              size: 16,
              color: themeColors['sideBar.foreground'],
            ),
            const SizedBox(width: 2),
            FileIcon(file.path, size: 16),
            const SizedBox(width: 5),
            Expanded(
              child: IdeResourceLabel(
                name: p.basename(file.path),
                description: folder == '.' ? null : folder,
                nameColor: selected
                    ? _selectedForeground(focused: focused)
                    : null,
              ),
            ),
            if (hovered || (selected && focused)) ...[
              if (replacing)
                IdeActionButton(
                  icon: Codicons.replaceAll,
                  tooltip: ideWithKeybinding(
                    context.l10n.searchReplaceAllKeys,
                    replaceAllKeys,
                  ),
                  size: 20,
                  onPressed: onReplaceAll,
                ),
              IdeActionButton(
                icon: Codicons.close,
                tooltip: ideWithKeybinding(
                  context.l10n.searchDismissKeys,
                  dismissKeys,
                ),
                size: 20,
                onPressed: onDismiss,
              ),
              const SizedBox(width: 8),
            ] else
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: IdeCountBadge(file.matches.length),
              ),
          ],
        ),
      ),
    );
  }
}

class _MatchRow extends StatelessWidget {
  const _MatchRow({
    super.key,
    required this.match,
    required this.replacement,
    required this.selected,
    required this.focused,
    required this.replaceKeys,
    required this.dismissKeys,
    required this.onTap,
    required this.onDoubleTap,
    required this.onReplace,
    required this.onDismiss,
    required this.onContextMenu,
  });

  final IdeTextMatch match;

  /// The replace string, while replacing.
  final String? replacement;
  final bool selected;
  final bool focused;

  /// Replace's and Dismiss's keybindings, for their tooltips.
  final String? replaceKeys;
  final String? dismissKeys;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final VoidCallback onReplace;
  final VoidCallback onDismiss;
  final ValueChanged<Offset> onContextMenu;

  @override
  Widget build(BuildContext context) {
    final preview = ideMatchPreview(match);
    final replacement = this.replacement;
    // searchview.css: high contrast themes outline matches instead of
    // filling them (not drawn here).
    final colors = themeColors;
    Color? fill(String id) => colors.highContrast ? null : colors[id];
    return IdeListRow(
      selected: selected,
      focused: focused,
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      onContextMenu: onContextMenu,
      tooltip: replacement == null ? null : '${match.matched} → $replacement',
      builder: (context, hovered) => Padding(
        padding: const EdgeInsets.only(left: 4 + 12 + 18),
        child: Row(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: preview.before),
                    TextSpan(
                      text: preview.inside,
                      style: TextStyle(
                        backgroundColor: fill(
                          replacement == null
                              ? 'editor.findMatchHighlightBackground'
                              : 'diffEditor.removedTextBackground',
                        ),
                        decoration: replacement == null
                            ? null
                            : TextDecoration.lineThrough,
                      ),
                    ),
                    if (replacement != null && replacement.isNotEmpty)
                      TextSpan(
                        text: replacement,
                        style: TextStyle(
                          backgroundColor: fill(
                            'diffEditor.insertedTextBackground',
                          ),
                        ),
                      ),
                    TextSpan(text: preview.after),
                  ],
                ),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: selected
                      ? _selectedForeground(focused: focused)
                      : colors['sideBar.foreground'],
                ),
              ),
            ),
            if (hovered || (selected && focused)) ...[
              if (replacement != null)
                IdeActionButton(
                  icon: Codicons.replace,
                  tooltip: ideWithKeybinding(
                    context.l10n.searchReplaceKeys,
                    replaceKeys,
                  ),
                  size: 20,
                  onPressed: onReplace,
                ),
              IdeActionButton(
                icon: Codicons.close,
                tooltip: ideWithKeybinding(
                  context.l10n.searchDismissKeys,
                  dismissKeys,
                ),
                size: 20,
                onPressed: onDismiss,
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }
}
