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
// media/searchview.css.
//
// Deviations: results are a list of files (no tree of folders), there is
// no search editor or search history, "Search only in Open Editors" is
// not offered, and replacing does not preview a diff.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../theme/codicons.dart';
import '../../theme/cursor_theme.dart';
import '../../theme/material_file_icons.dart';
import '../../theme/workbench_theme.dart';
import '../ide_commands.dart';
import '../ide_dialog.dart';
import '../ide_hover.dart';
import '../ide_input.dart';
import '../ide_list.dart';
import '../ide_menu.dart';
import '../ide_panes.dart';
import '../ide_workspace.dart';
import '../lsp/lsp_protocol.dart';
import 'text_search.dart';

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
  bool replaceShown = false;
  bool detailsShown = false;

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

  /// Asks the view to focus the search input.
  int focusRequest = 0;

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
  void toggleCollapseAll() {
    if (collapsed.length < results.length) {
      collapsed.addAll(results.map((file) => file.path));
    } else {
      collapsed.clear();
    }
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
  State<IdeSearchView> createState() => _IdeSearchViewState();
}

class _IdeSearchViewState extends State<IdeSearchView> {
  final FocusNode _queryFocus = FocusNode(debugLabel: 'search');
  final FocusNode _resultsFocus = FocusNode(debugLabel: 'search results');
  (String, IdeTextMatch?)? _selected;
  int _focusRequest = 0;

  IdeSearchSession get _session => widget.session;
  String get _root => widget.workspace.root;

  @override
  void initState() {
    super.initState();
    _session.addListener(_changed);
    _focusRequest = _session.focusRequest;
    _queryFocus.addListener(_changed);
    _resultsFocus.addListener(_changed);
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
    _queryFocus.dispose();
    _resultsFocus.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (_session.focusRequest != _focusRequest) {
      _focusRequest = _session.focusRequest;
      _queryFocus.requestFocus();
    }
  }

  void _toggle(void Function() change) {
    change();
    _session.search(_root);
  }

  String _keys(String mac, String other) => ideUsesMacKeys ? mac : other;

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

  String _plural(int n, String one, String many) => n == 1 ? one : many;

  /// Replace All, confirmed as VS Code confirms it.
  Future<void> _replaceAll() async {
    final occurrences = _session.matchCount;
    final files = _session.results.length;
    if (occurrences == 0) return;
    final value = _session.replace.text;
    final counts =
        '$occurrences ${_plural(occurrences, 'occurrence', 'occurrences')} '
        'across $files ${_plural(files, 'file', 'files')}';
    final pick = await showIdeDialog(
      context,
      type: IdeDialogType.question,
      message: value.isEmpty
          ? 'Replace $counts?'
          : "Replace $counts with '$value'?",
      buttons: const ['Replace'],
    );
    if (pick != 0 || !mounted) return;
    final replaced = await _replace({
      for (final file in [..._session.results]) file: [...file.matches],
    });
    if (!mounted) return;
    final done =
        '$replaced ${_plural(replaced, 'occurrence', 'occurrences')} '
        'across $files ${_plural(files, 'file', 'files')}';
    _session.replaced = value.isEmpty
        ? 'Replaced $done.'
        : "Replaced $done with '$value'.";
    _session.notify();
  }

  // --- Widgets -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final anyExpanded = session.collapsed.length < session.results.length;
    return ColoredBox(
      color: CursorColors.sidebarSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IdeViewTitle(
            'Search',
            actions: [
              IdePaneAction(
                icon: Codicons.refresh,
                tooltip: 'Refresh',
                onPressed: session.query.text.isEmpty
                    ? null
                    : () => session.search(_root),
              ),
              IdePaneAction(
                icon: Codicons.clearAll,
                tooltip: 'Clear Search Results',
                onPressed: session.query.text.isEmpty && session.results.isEmpty
                    ? null
                    : session.clear,
              ),
              IdePaneAction(
                icon: anyExpanded ? Codicons.collapseAll : Codicons.expandAll,
                tooltip: anyExpanded ? 'Collapse All' : 'Expand All',
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
                    placeholder: 'Search',
                    semanticsLabel: 'Search',
                    padding: _widgetPadding,
                    validation: regExpError == null
                        ? null
                        : IdeInputValidation(regExpError),
                    onChanged: (_) => session.searchSoon(_root),
                    onSubmitted: (_) => session.search(_root),
                    toggles: [
                      IdeInputToggle(
                        icon: Codicons.caseSensitive,
                        tooltip: 'Match Case (${_keys('⌥⌘C', 'Alt+C')})',
                        checked: session.matchCase,
                        onChanged: (value) =>
                            _toggle(() => session.matchCase = value),
                      ),
                      IdeInputToggle(
                        icon: Codicons.wholeWord,
                        tooltip: 'Match Whole Word (${_keys('⌥⌘W', 'Alt+W')})',
                        checked: session.wholeWord,
                        onChanged: (value) =>
                            _toggle(() => session.wholeWord = value),
                      ),
                      IdeInputToggle(
                        icon: Codicons.regex,
                        tooltip:
                            'Use Regular Expression (${_keys('⌥⌘R', 'Alt+R')})',
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
                            placeholder: 'Replace',
                            semanticsLabel: 'Replace',
                            padding: _widgetPadding,
                            onChanged: (_) => session.notify(),
                            toggles: [
                              IdeInputToggle(
                                icon: Codicons.preserveCase,
                                tooltip:
                                    'Preserve Case (${_keys('⌥⌘P', 'Alt+P')})',
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
                          tooltip:
                              'Replace All '
                              '(${_keys('⌥⌘Enter', 'Ctrl+Alt+Enter')})',
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
              child: Text('files to include', style: heading),
            ),
            IdeInputBox(
              controller: session.includes,
              placeholder: 'e.g. *.ts, src/**/include',
              semanticsLabel: 'files to include',
              onChanged: (_) => session.searchSoon(_root),
              onSubmitted: (_) => session.search(_root),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 2),
              child: Text('files to exclude', style: heading),
            ),
            IdeInputBox(
              controller: session.excludes,
              placeholder: 'e.g. *.ts, src/**/exclude',
              semanticsLabel: 'files to exclude',
              onChanged: (_) => session.searchSoon(_root),
              onSubmitted: (_) => session.search(_root),
              toggles: [
                IdeInputToggle(
                  icon: Codicons.exclude,
                  tooltip: 'Use Exclude Settings and Ignore Files',
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
    final lines = <String>[];
    if (session.replaced case final replaced?) lines.add(replaced);
    if (searched != null && !session.searching) {
      final matches = session.matchCount;
      final files = session.results.length;
      if (session.limitHit) {
        lines.add(
          'The result set only contains a subset of all matches. Be more '
          'specific in your search to narrow down the results.',
        );
      }
      if (matches > 0) {
        lines.add(
          '$matches ${_plural(matches, 'result', 'results')} in $files '
          '${_plural(files, 'file', 'files')}',
        );
      } else if (session.replaced == null) {
        final include = searched.includes.trim();
        final exclude = searched.excludes.trim();
        lines.add(switch ((include.isEmpty, exclude.isEmpty)) {
          (false, false) =>
            "No results found in '$include' excluding '$exclude'",
          (false, true) => "No results found in '$include'",
          (true, false) => "No results found excluding '$exclude'",
          (true, true) =>
            'No results found. Review your settings for configured '
                'exclusions and check your gitignore files',
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
    final rows = <(IdeSearchFileResult, IdeTextMatch?)>[
      for (final file in session.results) ...[
        (file, null),
        if (!session.collapsed.contains(file.path))
          for (final match in file.matches) (file, match),
      ],
    ];
    final regExp = session.regExp;
    return Focus(
      focusNode: _resultsFocus,
      onKeyEvent: (node, event) {
        if (event is KeyUpEvent) return KeyEventResult.ignored;
        final selected = _selected;
        if (selected == null) return KeyEventResult.ignored;
        final key = event.logicalKey;
        final keys = HardwareKeyboard.instance;
        final remove = ideUsesMacKeys
            ? key == LogicalKeyboardKey.backspace && keys.isMetaPressed
            : key == LogicalKeyboardKey.delete;
        if (!remove) return KeyEventResult.ignored;
        final file = session.results
            .where((file) => file.path == selected.$1)
            .firstOrNull;
        if (file != null) session.dismiss(file, selected.$2);
        return KeyEventResult.handled;
      },
      child: ListView.builder(
        itemExtent: IdeListColors.rowHeight,
        itemCount: rows.length,
        itemBuilder: (context, index) {
          final (file, match) = rows[index];
          final selected = _selected?.$1 == file.path && _selected?.$2 == match;
          void select() {
            _resultsFocus.requestFocus();
            setState(() => _selected = (file.path, match));
          }

          if (match == null) {
            return _FileRow(
              key: ValueKey(('file', file.path)),
              root: _root,
              file: file,
              expanded: !session.collapsed.contains(file.path),
              selected: selected,
              focused: _resultsFocus.hasFocus,
              replacing: session.replaceShown,
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
            focused: _resultsFocus.hasFocus,
            replaceKeys: _keys('⇧⌘1', 'Ctrl+Shift+1'),
            dismissKeys: _keys('⌘Backspace', 'Delete'),
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
          'Copy',
          keybinding: _keys('⌘C', 'Ctrl+C'),
          onSelected: () => unawaited(
            Clipboard.setData(ClipboardData(text: _copyText(file, match))),
          ),
        ),
        IdeMenuAction(
          'Copy Path',
          keybinding: _keys('⌥⌘C', 'Shift+Alt+C'),
          onSelected: () =>
              unawaited(Clipboard.setData(ClipboardData(text: file.path))),
        ),
        IdeMenuAction(
          'Copy All',
          onSelected: () => unawaited(
            Clipboard.setData(
              ClipboardData(
                text: [for (final file in _session.results) _copyText(file)]
                    .join('\n\n'),
              ),
            ),
          ),
        ),
      ],
      [
        if (_session.replaceShown)
          IdeMenuAction(
            match == null ? 'Replace All' : 'Replace',
            onSelected: () => unawaited(
              _replace({
                file: match == null ? [...file.matches] : [match],
              }),
            ),
          ),
        IdeMenuAction(
          'Dismiss',
          keybinding: _keys('⌘Backspace', 'Delete'),
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
    message: 'Toggle Replace',
    child: Semantics(
      button: true,
      expanded: widget.expanded,
      label: 'Toggle Replace',
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
    message: 'Toggle Search Details',
    child: Semantics(
      button: true,
      expanded: expanded,
      label: 'Toggle Search Details',
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
                  tooltip:
                      'Replace All (${ideUsesMacKeys ? '⇧⌘1' : 'Ctrl+Shift+1'})',
                  size: 20,
                  onPressed: onReplaceAll,
                ),
              IdeActionButton(
                icon: Codicons.close,
                tooltip:
                    'Dismiss (${ideUsesMacKeys ? '⌘Backspace' : 'Delete'})',
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
  final String replaceKeys;
  final String dismissKeys;
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
                  tooltip: 'Replace ($replaceKeys)',
                  size: 20,
                  onPressed: onReplace,
                ),
              IdeActionButton(
                icon: Codicons.close,
                tooltip: 'Dismiss ($dismissKeys)',
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
