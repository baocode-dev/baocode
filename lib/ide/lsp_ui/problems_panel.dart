// The bottom panel: Problems, References and the terminal's tab.
//
// The lists' keyboard adapted from VS Code
// 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/contrib/markers/browser/markersView.ts and
// markersTreeViewer.ts (the Problems tree, `setMarkerSelection`),
// markersModel.ts (a marker copied: `Marker.toString`),
// extensions/references-view/src/ (the References list) and
// src/vs/workbench/browser/actions/listCommands.ts (`list.*`, through
// [IdeKeyboardList]).
//
// Deviations: a row is focused and selected at once (one of each list);
// Problems has no filter, no table view and no related information; a
// problem copied has no `owner` (the language server's name upstream).

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../keybindings/keybinding_service.dart';
import '../../l10n/l10n.dart';
import '../../theme/codicons.dart';
import '../../theme/app_theme.dart';
import '../../theme/material_file_icons.dart';
import '../../theme/workbench_theme.dart';

import 'package:bao_editor/monaco/flutter/document_snapshot.dart';

import '../ide_hover.dart';
import '../ide_list.dart';
import '../lsp/language_features.dart';
import '../lsp/lsp_protocol.dart';
import 'diagnostics.dart';
import 'lsp_convert.dart';

enum IdePanelTab { problems, references, terminal }

/// Locations Find References (or several definitions) produced.
class IdeReferences {
  const IdeReferences(this.title, this.locations);

  final String title;
  final List<IdeLocation> locations;
}

/// [references]' locations as the References list shows them: by file, in
/// the order the files came, and by position in each.
List<IdeLocation> ideReferencesInOrder(IdeReferences references) {
  final byPath = <String, List<IdeLocation>>{};
  for (final location in references.locations) {
    byPath.putIfAbsent(location.path, () => []).add(location);
  }
  return [
    for (final locations in byPath.values)
      ...(locations..sort((a, b) => a.range.start.compareTo(b.range.start))),
  ];
}

/// Every problem as the Problems list shows them (hints are not problems):
/// by file path, and in each by severity, then position.
List<(String path, List<LspDiagnostic> problems)> ideProblemsByFile(
  Map<String, List<LspDiagnostic>> all,
) {
  final paths = [
    for (final MapEntry(key: path, value: list) in all.entries)
      if (list.any((d) => d.severity != LspDiagnosticSeverity.hint)) path,
  ]..sort();
  return [
    for (final path in paths)
      (
        path,
        [
          for (final d in all[path]!)
            if (d.severity != LspDiagnosticSeverity.hint) d,
        ]..sort((a, b) {
          final bySeverity = a.severity.index.compareTo(b.severity.index);
          return bySeverity != 0
              ? bySeverity
              : a.range.start.compareTo(b.range.start);
        }),
      ),
  ];
}

/// A problem's row in [IdePanelListModel.focused].
typedef IdeProblemId = (String path, LspRange range, String message);

/// The row of [problem] of [path].
IdeProblemId ideProblemId(String path, LspDiagnostic problem) =>
    (path, problem.range, problem.message);

/// The problems of [all] a Problems row stands for: a file's (its path),
/// or one ([IdeProblemId]).
List<(String path, LspDiagnostic problem)> ideProblemsOf(
  Map<String, List<LspDiagnostic>> all,
  Object? row,
) => [
  for (final (path, problems) in ideProblemsByFile(all))
    for (final problem in problems)
      if (row == path || row == ideProblemId(path, problem)) (path, problem),
];

/// Copy (`problems.action.copy`): [problems] as upstream's markers print
/// (`Marker.toString`, tab-indented JSON), in brackets.
String ideProblemsJson(List<(String path, LspDiagnostic problem)> problems) {
  const encoder = JsonEncoder.withIndent('\t');
  final markers = [
    for (final (path, d) in problems)
      encoder.convert({
        'resource': path,
        if (d.code != null) 'code': d.code,
        'severity': switch (d.severity) {
          LspDiagnosticSeverity.error => 8,
          LspDiagnosticSeverity.warning => 4,
          LspDiagnosticSeverity.information => 2,
          LspDiagnosticSeverity.hint => 1,
        },
        'message': d.message,
        if (d.source != null) 'source': d.source,
        'startLineNumber': d.range.start.line + 1,
        'startColumn': d.range.start.character + 1,
        'endLineNumber': d.range.end.line + 1,
        'endColumn': d.range.end.character + 1,
      }),
  ];
  return '[${markers.join(',')}]';
}

/// What a Problems or References list keeps while other tabs show (the
/// workbench owns one of each, as upstream's trees keep their state): the
/// focused row, the collapsed files, and whether it has the keyboard.
class IdePanelListModel extends ChangeNotifier {
  Object? _focused;
  final Set<String> _collapsed = {};
  bool _focusPending = false;
  bool _hasFocus = false;

  /// The focused (and selected) row: a file's path, a reference's
  /// [IdeLocation] or a problem's [IdeProblemId]; null for none.
  Object? get focused => _focused;

  /// Whether the focused row is a problem or a reference, not a file.
  bool get entryFocused => _focused != null && _focused is! String;

  /// Whether the list has the keyboard.
  bool get hasFocus => _hasFocus;

  bool isCollapsed(String path) => _collapsed.contains(path);

  void focus(Object? row) {
    if (row == _focused) return;
    _focused = row;
    notifyListeners();
  }

  void setCollapsed(String path, bool collapsed) {
    if (collapsed ? _collapsed.add(path) : _collapsed.remove(path)) {
      notifyListeners();
    }
  }

  /// Gives the list the keyboard once it shows, with the first entry
  /// focused if no row is (upstream `setMarkerSelection`).
  void requestFocus() {
    _focusPending = true;
    notifyListeners();
  }

  /// Forgets the rows, for new results.
  void clear() {
    _focused = null;
    _collapsed.clear();
    notifyListeners();
  }
}

/// The bottom panel: Problems (every document's diagnostics, grouped by
/// file), References (the last Find References) and the Terminal, like VS
/// Code's panel. Its card and height are the workbench's; its colors the
/// color theme's `panelTitle.*` and the markers view's (markers.css).
class IdeBottomPanel extends StatelessWidget {
  const IdeBottomPanel({
    super.key,
    required this.tab,
    required this.root,
    required this.languages,
    required this.references,
    required this.onTab,
    required this.onClose,
    required this.onOpen,
    required this.textOf,
    this.onOpenFocused,
    this.problemsList,
    this.referencesList,
    this.terminal,
    this.terminalActions,
  });

  final IdePanelTab tab;
  final String root;
  final LanguageFeatures? languages;
  final IdeReferences? references;
  final ValueChanged<IdePanelTab> onTab;
  final VoidCallback onClose;

  /// Opens a location; [select] selects its range instead of placing the
  /// caret at its start.
  final void Function(IdeLocation location, {bool select}) onOpen;

  /// Opens a location from the keyboard (`list.select`,
  /// `problems.action.open`): its range selected, the editor focused;
  /// [onOpen] without.
  final ValueChanged<IdeLocation>? onOpenFocused;

  /// The lists' state, kept by the host; each list keeps its own without.
  final IdePanelListModel? problemsList;
  final IdePanelListModel? referencesList;

  /// A file's text for previews (open documents first, then disk).
  final Future<String?> Function(String path) textOf;

  /// The integrated terminal; none where there are no terminals (the web).
  final Widget? terminal;

  /// The terminal's title actions, before Close Panel while TERMINAL shows.
  final Widget? terminalActions;

  @override
  Widget build(BuildContext context) {
    final languages = this.languages;
    return ListenableBuilder(
      listenable: languages ?? _never,
      builder: (context, _) {
        final all = languages?.allDiagnostics ?? const {};
        final counts = ideDiagnosticCounts(all);
        final total = counts.errors + counts.warnings + counts.infos;
        // `panelTitle.border`: under the title in high contrast themes.
        final titleBorder = themeColors.get('panelTitle.border');
        // A tab's hover: its view's name and the keys showing it, as the
        // activity bar's (compositeBarActions.ts `computeTitle`).
        final keys = KeybindingService.instance;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 30,
              decoration: titleBorder == null
                  ? null
                  : BoxDecoration(
                      border: Border(bottom: BorderSide(color: titleBorder)),
                    ),
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  // Narrow, the tabs scroll and the actions stay whole.
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Tab(
                            label: context.l10n.panelProblems,
                            tooltip: keys.titleWithKeybinding(
                              context.l10n.idePanelProblems,
                              'workbench.actions.view.problems',
                            ),
                            badge: total == 0 ? null : '$total',
                            selected: tab == IdePanelTab.problems,
                            onTap: () => onTab(IdePanelTab.problems),
                          ),
                          _Tab(
                            label: context.l10n.panelReferences,
                            tooltip: context.l10n.idePanelReferences,
                            badge: references == null
                                ? null
                                : '${references!.locations.length}',
                            selected: tab == IdePanelTab.references,
                            onTap: () => onTab(IdePanelTab.references),
                          ),
                          if (terminal != null)
                            _Tab(
                              label: context.l10n.panelTerminal,
                              tooltip: keys.titleWithKeybinding(
                                context.l10n.idePanelTerminal,
                                'workbench.action.terminal.toggleTerminal',
                              ),
                              selected: tab == IdePanelTab.terminal,
                              onTap: () => onTab(IdePanelTab.terminal),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (tab == IdePanelTab.terminal) ?terminalActions,
                  IdeActionButton(
                    icon: Codicons.close,
                    // Upstream's is Toggle Panel's (`MenuId.PanelTitle`,
                    // panelActions.ts): its keys, else Hide Panel's.
                    tooltip: switch (keys.labelFor(
                      'workbench.action.togglePanel',
                    )) {
                      final toggle? => '${context.l10n.panelClose} ($toggle)',
                      null => keys.titleWithKeybinding(
                        context.l10n.panelClose,
                        'workbench.action.closePanel',
                      ),
                    },
                    onPressed: onClose,
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
            Expanded(
              child: switch (tab) {
                IdePanelTab.problems => _problems(all, context.l10n),
                IdePanelTab.references => _references(context.l10n),
                IdePanelTab.terminal =>
                  terminal ?? _message(context.l10n.panelTerminalUnavailable),
              },
            ),
          ],
        );
      },
    );
  }

  static final _never = ChangeNotifier();

  Widget _message(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
    child: Text(
      text,
      style: TextStyle(fontSize: 12, color: themeColors['foreground']),
    ),
  );

  void _openFocused(IdeLocation location) {
    if (onOpenFocused case final open?) return open(location);
    onOpen(location, select: true);
  }

  Widget _problems(
    Map<String, List<LspDiagnostic>> all,
    AppLocalizations l10n,
  ) {
    final files = ideProblemsByFile(all);
    if (files.isEmpty) {
      return _message(l10n.problemsNone);
    }
    return _PanelList(
      key: const ValueKey('problems'),
      model: problemsList,
      root: root,
      onOpen: (location) => onOpen(location, select: true),
      onOpenFocused: _openFocused,
      groups: [
        for (final (path, problems) in files)
          (
            path,
            [
              for (final d in problems)
                _EntryRow(
                  path,
                  ideProblemId(path, d),
                  IdeLocation(path, d.range),
                  (selected) => _Entry(
                    selected: selected,
                    leading: Icon(
                      ideDiagnosticIcon(d.severity),
                      size: 14,
                      color: ideDiagnosticColor(d.severity),
                    ),
                    text: TextSpan(
                      text: d.message.split('\n').first,
                      children: [
                        if (d.source != null || d.code != null)
                          TextSpan(
                            text:
                                '  ${d.source ?? ''}'
                                '${d.code == null ? '' : '(${d.code})'}',
                            style: TextStyle(
                              color: themeColors['descriptionForeground'],
                            ),
                          ),
                        TextSpan(
                          text:
                              '  ${l10n.problemsPosition(d.range.start.line + 1, d.range.start.character + 1)}',
                          style: TextStyle(
                            color: themeColors['descriptionForeground'],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _references(AppLocalizations l10n) {
    final references = this.references;
    if (references == null) return _message(l10n.referencesNone);
    final byPath = <String, List<IdeLocation>>{};
    for (final location in ideReferencesInOrder(references)) {
      byPath.putIfAbsent(location.path, () => []).add(location);
    }
    final count = references.locations.length;
    return _PanelList(
      key: const ValueKey('references'),
      model: referencesList,
      root: root,
      header: _message(
        l10n.referencesSummary(references.title, count, byPath.length),
      ),
      onOpen: (location) => onOpen(location, select: true),
      onOpenFocused: _openFocused,
      groups: [
        for (final MapEntry(key: path, value: locations) in byPath.entries)
          (
            path,
            [
              for (final location in locations)
                _EntryRow(
                  path,
                  location,
                  location,
                  (selected) => _ReferenceRow(
                    key: ValueKey(('reference', location)),
                    location: location,
                    textOf: textOf,
                    selected: selected,
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.tooltip,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final String label;

  /// Its view's name (not upper-cased) and keybinding.
  final String tooltip;
  final String? badge;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    return IdeHover(
      message: tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: selected
                      ? colors['panelTitle.activeBorder']
                      : Colors.transparent,
                ),
              ),
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.3,
                    color:
                        colors[selected
                            ? 'panelTitle.activeForeground'
                            : 'panelTitle.inactiveForeground'],
                  ),
                ),
                if (badge != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(
                      color: colors['panelTitleBadge.background'],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      badge!,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: colors['panelTitleBadge.foreground'],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A row of a panel list: a file, or one of its problems or references.
sealed class _ListRow {
  String get path;

  /// What [IdePanelListModel.focused] holds for it.
  Object get id;
}

final class _FileRow implements _ListRow {
  _FileRow(this.path, this.count);

  @override
  final String path;
  final int count;

  @override
  Object get id => path;
}

final class _EntryRow implements _ListRow {
  _EntryRow(this.path, this.id, this.location, this.build);

  @override
  final String path;
  @override
  final Object id;
  final IdeLocation location;

  /// Its content, told whether it is selected.
  final Widget Function(bool selected) build;
}

/// A Problems or References list: files, each with its entries under it
/// unless collapsed, a tree the keyboard walks (`list.*`).
class _PanelList extends StatefulWidget {
  const _PanelList({
    super.key,
    required this.model,
    required this.root,
    required this.groups,
    required this.onOpen,
    required this.onOpenFocused,
    this.header,
  });

  final IdePanelListModel? model;
  final String root;
  final List<(String path, List<_EntryRow> entries)> groups;

  /// A click on an entry.
  final ValueChanged<IdeLocation> onOpen;

  /// An entry opened from the keyboard.
  final ValueChanged<IdeLocation> onOpenFocused;

  /// Above the rows (the references' summary).
  final Widget? header;

  @override
  State<_PanelList> createState() => _PanelListState();
}

class _PanelListState extends State<_PanelList>
    with IdeKeyboardList<_PanelList> {
  final _focus = FocusNode(debugLabel: 'panel list');
  final _scroll = ScrollController();
  IdePanelListModel? _own;

  IdePanelListModel get _model =>
      widget.model ?? (_own ??= IdePanelListModel());

  List<_ListRow> get _rows => [
    for (final (path, entries) in widget.groups) ...[
      _FileRow(path, entries.length),
      if (!_model.isCollapsed(path)) ...entries,
    ],
  ];

  @override
  void initState() {
    super.initState();
    _model.addListener(_changed);
    _focus.addListener(_focusChanged);
    _takeFocusIfAsked();
  }

  @override
  void didUpdateWidget(_PanelList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget.model ?? _own;
    if (old != _model) {
      old?.removeListener(_changed);
      _model.addListener(_changed);
      _takeFocusIfAsked();
    }
  }

  @override
  void dispose() {
    _model
      ..removeListener(_changed)
      .._hasFocus = false;
    _own?.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _changed() {
    _takeFocusIfAsked();
    if (mounted) setState(() {});
    final at = listFocusedIndex;
    if (at >= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ideRevealRow(_scroll, at);
      });
    }
  }

  void _focusChanged() {
    _model._hasFocus = _focus.hasFocus;
    if (mounted) setState(() {});
  }

  /// [IdePanelListModel.requestFocus], once the list has been laid out.
  void _takeFocusIfAsked() {
    final model = _model;
    if (!model._focusPending) return;
    model._focusPending = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focus.requestFocus();
      if (listFocusedIndex >= 0) return;
      final rows = _rows;
      final first = rows.whereType<_EntryRow>().firstOrNull;
      if (first != null) {
        model.focus(first.id);
      } else if (widget.groups.firstOrNull case (
        final path,
        [final entry, ...],
      )) {
        model
          ..setCollapsed(path, false)
          ..focus(entry.id);
      } else if (rows.isNotEmpty) {
        model.focus(rows.first.id);
      }
    });
  }

  _ListRow? get _focusedRow {
    final at = listFocusedIndex;
    return at < 0 ? null : _rows[at];
  }

  @override
  bool get listHasFocus => _focus.hasFocus;

  @override
  int get listLength => _rows.length;

  @override
  int get listFocusedIndex {
    final focused = _model.focused;
    if (focused == null) return -1;
    return _rows.indexWhere((row) => row.id == focused);
  }

  @override
  int get listPageSize => ideRowsPerPage(_scroll);

  @override
  void listFocusAt(int index) => _model.focus(_rows[index].id);

  @override
  void listSelect() {
    switch (_focusedRow) {
      case _FileRow(:final path):
        _model.setCollapsed(path, !_model.isCollapsed(path));
      case _EntryRow(:final location):
        widget.onOpenFocused(location);
      case null:
    }
  }

  @override
  void listToggleExpand() {
    if (_focusedRow case _FileRow(:final path)) {
      _model.setCollapsed(path, !_model.isCollapsed(path));
    }
  }

  @override
  void listExpand() {
    if (_focusedRow case _FileRow(:final path)) {
      if (_model.isCollapsed(path)) {
        _model.setCollapsed(path, false);
      } else {
        listFocusNext(1);
      }
    }
  }

  @override
  void listCollapse() {
    switch (_focusedRow) {
      case _FileRow(:final path):
        _model.setCollapsed(path, true);
      case _EntryRow(:final path):
        _model.focus(path);
      case null:
    }
  }

  @override
  void listCollapseAll() {
    final focused = _focusedRow;
    for (final (path, _) in widget.groups) {
      _model.setCollapsed(path, true);
    }
    if (focused != null) _model.focus(focused.path);
  }

  @override
  bool listTreeKey(String key) {
    final row = _focusedRow;
    return switch (key) {
      'treeElementCanCollapse' =>
        row is _FileRow && !_model.isCollapsed(row.path),
      'treeElementCanExpand' => row is _FileRow && _model.isCollapsed(row.path),
      'treeElementHasChild' => row is _FileRow,
      'treeElementHasParent' => row is _EntryRow,
      _ => false,
    };
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final focused = _model.focused;
    final active = _focus.hasFocus;
    final list = Focus(
      focusNode: _focus,
      child: ListView.builder(
        controller: _scroll,
        itemExtent: IdeListColors.rowHeight,
        itemCount: rows.length,
        itemBuilder: (context, index) {
          final row = rows[index];
          final selected = row.id == focused;
          void take() {
            _focus.requestFocus();
            _model.focus(row.id);
          }

          return switch (row) {
            _FileRow(:final path, :final count) => _RowFrame(
              key: ValueKey(('file', path)),
              selected: selected,
              focused: active,
              padding: const EdgeInsets.only(left: 4, right: 12),
              onTap: () {
                take();
                _model.setCollapsed(path, !_model.isCollapsed(path));
              },
              child: _FileHeader(
                path: path,
                root: widget.root,
                count: count,
                collapsed: _model.isCollapsed(path),
                selected: selected,
              ),
            ),
            _EntryRow(:final location, :final build) => _RowFrame(
              key: ValueKey(('entry', row.id)),
              selected: selected,
              focused: active,
              padding: const EdgeInsets.only(left: 32, right: 12),
              onTap: () {
                take();
                widget.onOpen(location);
              },
              child: build(selected),
            ),
          };
        },
      ),
    );
    final header = widget.header;
    if (header == null) return list;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        Expanded(child: list),
      ],
    );
  }
}

/// A 22px row: hover, and the selection's background and outline
/// (`listWidget.ts` `DefaultStyleController`).
class _RowFrame extends StatefulWidget {
  const _RowFrame({
    super.key,
    required this.selected,
    required this.focused,
    required this.padding,
    required this.onTap,
    required this.child,
  });

  final bool selected;

  /// Whether the list has the keyboard: its selection is the active one.
  final bool focused;
  final EdgeInsets padding;
  final VoidCallback onTap;
  final Widget child;

  @override
  State<_RowFrame> createState() => _RowFrameState();
}

class _RowFrameState extends State<_RowFrame> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    final selected = widget.selected;
    final focused = widget.focused;
    final Color? outline = selected && focused
        ? colors.get('list.focusAndSelectionOutline') ??
              colors.get('contrastActiveBorder') ??
              colors.get('list.focusOutline')
        : null;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          height: IdeListColors.rowHeight,
          color: selected
              ? (focused
                    ? IdeListColors.activeSelection
                    : IdeListColors.inactiveSelection)
              : _hover
              ? IdeListColors.hover
              : null,
          foregroundDecoration: outline == null
              ? null
              : BoxDecoration(border: Border.all(color: outline)),
          padding: widget.padding,
          child: widget.child,
        ),
      ),
    );
  }
}

/// A selected row's text color, else [fallback].
Color _foreground(bool selected, Color fallback) =>
    (selected ? themeColors.get('list.activeSelectionForeground') : null) ??
    fallback;

class _FileHeader extends StatelessWidget {
  const _FileHeader({
    required this.path,
    required this.root,
    required this.count,
    required this.collapsed,
    required this.selected,
  });

  final String path;
  final String root;
  final int count;
  final bool collapsed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final name = p.basename(path);
    final folder = p.isWithin(root, path)
        ? p.dirname(p.relative(path, from: root))
        : p.dirname(path);
    final colors = themeColors;
    final badgeBorder = colors.get('contrastBorder');
    final foreground = _foreground(selected, colors['foreground']);
    return Row(
      children: [
        Icon(
          collapsed ? Codicons.chevronRight : Codicons.chevronDown,
          size: 16,
          color: foreground,
        ),
        const SizedBox(width: 4),
        FileIcon(name, size: 14),
        const SizedBox(width: 6),
        Text(name, style: TextStyle(fontSize: 12.5, color: foreground)),
        if (folder != '.') ...[
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              folder,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                color: colors['descriptionForeground'],
              ),
            ),
          ),
        ],
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          // `defaultCountBadgeStyles`.
          decoration: BoxDecoration(
            color: colors['badge.background'],
            border: badgeBorder == null ? null : Border.all(color: badgeBorder),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$count',
            style: TextStyle(fontSize: 10.5, color: colors['badge.foreground']),
          ),
        ),
      ],
    );
  }
}

/// A problem's or a reference's content: an icon and a line of text.
class _Entry extends StatelessWidget {
  const _Entry({
    required this.leading,
    required this.text,
    required this.selected,
  });

  final Widget leading;
  final InlineSpan text;
  final bool selected;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      leading,
      const SizedBox(width: 6),
      Expanded(
        child: Text.rich(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12.5,
            color: _foreground(selected, themeColors['foreground']),
          ),
        ),
      ),
    ],
  );
}

class _ReferenceRow extends StatefulWidget {
  const _ReferenceRow({
    super.key,
    required this.location,
    required this.textOf,
    required this.selected,
  });

  final IdeLocation location;
  final Future<String?> Function(String path) textOf;
  final bool selected;

  @override
  State<_ReferenceRow> createState() => _ReferenceRowState();
}

class _ReferenceRowState extends State<_ReferenceRow> {
  String? _line;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    String? text;
    try {
      text = await widget.textOf(widget.location.path);
    } catch (_) {
      return;
    }
    if (text == null || !mounted) return;
    final snapshot = DocumentSnapshot(text);
    final line = widget.location.range.start.line;
    if (line >= snapshot.lineCount) return;
    setState(() {
      _line = text!.substring(
        snapshot.lineStarts[line],
        snapshot.contentEnds[line],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final range = widget.location.range;
    final line = _line;
    final spans = <InlineSpan>[];
    if (line != null) {
      final start = range.start.character.clamp(0, line.length);
      final end = range.start.line == range.end.line
          ? range.end.character.clamp(start, line.length)
          : line.length;
      final lead = line.substring(0, start);
      final trimmed = lead.trimLeft();
      spans
        ..add(TextSpan(text: trimmed))
        ..add(
          TextSpan(
            text: line.substring(start, end),
            style: TextStyle(
              backgroundColor:
                  themeColors['peekViewResult.matchHighlightBackground'],
            ),
          ),
        )
        ..add(TextSpan(text: line.substring(end)));
    }
    spans.add(
      TextSpan(
        text:
            '  ${context.l10n.referencesPosition(range.start.line + 1, range.start.character + 1)}',
        style: TextStyle(color: themeColors['descriptionForeground']),
      ),
    );
    return _Entry(
      leading: const SizedBox(width: 0),
      selected: widget.selected,
      text: TextSpan(children: spans, style: AppFonts.uiCodeStyle(12)),
    );
  }
}
