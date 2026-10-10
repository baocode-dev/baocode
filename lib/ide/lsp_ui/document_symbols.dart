import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../theme/codicons.dart';
import '../../theme/app_theme.dart';
import '../../theme/workbench_theme.dart';
import '../ide_fuzzy.dart';
import '../ide_quick_input.dart';
import '../ide_workspace.dart';
import '../language/language_features.dart';
import '../language/language_types.dart';
import 'language_icons.dart';

/// The active document's symbols, re-requested (debounced) as it changes,
/// for the outline, breadcrumbs and Go to Symbol.
class IdeDocumentSymbols extends ChangeNotifier {
  IdeDocumentSymbols(this.languages);

  final LanguageFeatures languages;

  static const delay = Duration(milliseconds: 350);

  String? _path;
  int _version = -1;
  IdeDocument? _document;
  List<LspDocumentSymbol> _symbols = const [];
  bool _loaded = false;
  Timer? _timer;
  int _request = 0;
  bool _disposed = false;

  /// The document [symbols] belong to.
  String? get path => _path;
  List<LspDocumentSymbol> get symbols => _symbols;

  /// Whether an answer arrived for [path] (an empty one included).
  bool get loaded => _loaded;

  bool get supported =>
      _path != null &&
      languages.supports(_path!, LanguageRequest.documentSymbols);

  /// Follows [document] (the active one): a new document asks at once, an
  /// edit asks after [delay].
  void update(IdeDocument? document) {
    if (_disposed) return;
    if (document == null) {
      _timer?.cancel();
      _request++;
      if (_path != null) {
        _path = null;
        _document = null;
        _symbols = const [];
        _loaded = false;
        notifyListeners();
      }
      return;
    }
    if (identical(document, _document) && document.model.version == _version) {
      return;
    }
    final switched = !identical(document, _document);
    _document = document;
    _path = document.path;
    _version = document.model.version;
    _timer?.cancel();
    if (switched) {
      _symbols = const [];
      _loaded = false;
      notifyListeners();
      unawaited(_fetch(document));
    } else {
      _timer = Timer(delay, () => unawaited(_fetch(document)));
    }
  }

  /// Asks again now (e.g. once a server started).
  void refresh() {
    final document = _document;
    if (document != null) unawaited(_fetch(document));
  }

  Future<void> _fetch(IdeDocument document) async {
    final request = ++_request;
    final version = document.model.version;
    if (!languages.supports(document.path, LanguageRequest.documentSymbols)) {
      return;
    }
    List<LspDocumentSymbol> symbols;
    try {
      symbols = await languages.documentSymbols(document.path);
    } catch (_) {
      return;
    }
    if (_disposed ||
        request != _request ||
        !identical(document, _document) ||
        version != document.model.version) {
      return;
    }
    _symbols = symbols;
    _loaded = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}

/// The symbols enclosing [position], outermost first (breadcrumbs).
List<LspDocumentSymbol> ideSymbolPathAt(
  List<LspDocumentSymbol> symbols,
  LspPosition position,
) {
  final path = <LspDocumentSymbol>[];
  var level = symbols;
  while (true) {
    LspDocumentSymbol? found;
    for (final symbol in level) {
      if (symbol.range.contains(position)) {
        found = symbol;
        break;
      }
    }
    if (found == null) return path;
    path.add(found);
    level = found.children;
  }
}

/// Every symbol with its container names, in document order.
List<(LspDocumentSymbol, String?)> ideFlattenSymbols(
  List<LspDocumentSymbol> symbols, [
  String? container,
]) => [
  for (final symbol in symbols) ...[
    (symbol, container ?? symbol.detail),
    ...ideFlattenSymbols(symbol.children, symbol.name),
  ],
];

/// Rows for Go to Symbol in Editor (the `@` prefix); messages in [l10n]'s
/// language (English when null).
List<IdeQuickPickItem> symbolQuickPicks(
  String filter, {
  required List<LspDocumentSymbol> symbols,
  required bool loaded,
  required bool supported,
  required void Function(LspDocumentSymbol symbol) onGo,
  AppLocalizations? l10n,
}) {
  final strings = l10n ?? englishLocalizations;
  if (!supported) return [IdeQuickPickItem(label: strings.symbolsNoEditor)];
  if (!loaded) return [IdeQuickPickItem(label: strings.symbolsLoading)];
  final query = filter.trim();
  final flat = ideFlattenSymbols(symbols);
  if (flat.isEmpty) return [IdeQuickPickItem(label: strings.symbolsNone)];
  Widget icon(LspSymbolKind kind) {
    final kindIcon = ideSymbolKindIcon(kind);
    return Icon(kindIcon.icon, size: 15, color: kindIcon.color);
  }

  if (query.isEmpty) {
    return [
      for (final (symbol, container) in flat)
        IdeQuickPickItem(
          label: symbol.name,
          description: container,
          icon: icon(symbol.kind),
          onAccept: () => onGo(symbol),
        ),
    ];
  }
  final scored = <(LspDocumentSymbol, String?, IdeFuzzyMatch)>[];
  for (final (symbol, container) in flat) {
    final match = ideFuzzyMatch(query, symbol.name);
    if (match != null) scored.add((symbol, container, match));
  }
  if (scored.isEmpty) {
    return [IdeQuickPickItem(label: strings.symbolsNoMatching)];
  }
  scored.sort((a, b) => b.$3.score.compareTo(a.$3.score));
  return [
    for (final (symbol, container, match) in scored)
      IdeQuickPickItem(
        label: symbol.name,
        labelMatches: match.positions,
        description: container,
        icon: icon(symbol.kind),
        onAccept: () => onGo(symbol),
      ),
  ];
}

/// The Outline view: the active document's symbol tree, following the
/// caret; a click reveals a symbol.
class IdeOutlineView extends StatefulWidget {
  const IdeOutlineView({
    super.key,
    required this.symbols,
    required this.caret,
    required this.onReveal,
    this.showHeader = true,
  });

  final IdeDocumentSymbols? symbols;

  /// Its own OUTLINE header; false inside a pane, whose header it has.
  final bool showHeader;

  /// Where the caret is (zero-based), to highlight its symbol.
  final LspPosition? caret;
  final ValueChanged<LspDocumentSymbol> onReveal;

  @override
  State<IdeOutlineView> createState() => _IdeOutlineViewState();
}

class _IdeOutlineViewState extends State<IdeOutlineView> {
  final Set<String> _collapsed = {};

  static String _keyOf(List<String> path) => path.join('\u0000');

  @override
  Widget build(BuildContext context) {
    final model = widget.symbols;
    final header = Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      child: Text(
        context.l10n.outlineTitle,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: themeColors['sideBarSectionHeader.foreground'],
          letterSpacing: 0.4,
        ),
      ),
    );
    // `.outline-message`: the side bar's text.
    Widget message(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: themeColors['sideBar.foreground'],
        ),
      ),
    );
    return ColoredBox(
      color: AppColors.sidebarSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.showHeader) header,
          Expanded(
            child: ListenableBuilder(
              listenable: model ?? const _NoListenable(),
              builder: (context, _) {
                if (model == null || model.path == null || !model.supported) {
                  return Align(
                    alignment: Alignment.topLeft,
                    child: message(context.l10n.outlineNoEditor),
                  );
                }
                if (model.symbols.isEmpty) {
                  return Align(
                    alignment: Alignment.topLeft,
                    child: message(
                      model.loaded
                          ? context.l10n.outlineNoSymbols
                          : context.l10n.outlineLoading,
                    ),
                  );
                }
                final active = widget.caret == null
                    ? const <LspDocumentSymbol>[]
                    : ideSymbolPathAt(model.symbols, widget.caret!);
                final rows = <Widget>[];
                void add(
                  List<LspDocumentSymbol> symbols,
                  int depth,
                  List<String> parent,
                ) {
                  for (final symbol in symbols) {
                    final path = [...parent, symbol.name];
                    final key = _keyOf(path);
                    final collapsed = _collapsed.contains(key);
                    rows.add(
                      _OutlineRow(
                        symbol: symbol,
                        depth: depth,
                        expandable: symbol.children.isNotEmpty,
                        collapsed: collapsed,
                        selected:
                            active.isNotEmpty && identical(active.last, symbol),
                        onToggle: () => setState(() {
                          if (!_collapsed.remove(key)) _collapsed.add(key);
                        }),
                        onTap: () => widget.onReveal(symbol),
                      ),
                    );
                    if (!collapsed) add(symbol.children, depth + 1, path);
                  }
                }

                add(model.symbols, 0, const []);
                return ListView(children: rows);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NoListenable implements Listenable {
  const _NoListenable();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

class _OutlineRow extends StatefulWidget {
  const _OutlineRow({
    required this.symbol,
    required this.depth,
    required this.expandable,
    required this.collapsed,
    required this.selected,
    required this.onToggle,
    required this.onTap,
  });

  final LspDocumentSymbol symbol;
  final int depth;
  final bool expandable;
  final bool collapsed;
  final bool selected;
  final VoidCallback onToggle;
  final VoidCallback onTap;

  @override
  State<_OutlineRow> createState() => _OutlineRowState();
}

class _OutlineRowState extends State<_OutlineRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final kind = ideSymbolKindIcon(widget.symbol.kind);
    // The tree's row: the caret's symbol selected in the unfocused list.
    final colors = themeColors;
    final foreground = colors['sideBar.foreground'];
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          height: 22,
          color: widget.selected
              ? colors['list.inactiveSelectionBackground']
              : _hover
              ? colors['list.hoverBackground']
              : null,
          padding: EdgeInsets.only(left: 8.0 + widget.depth * 12),
          child: Row(
            children: [
              SizedBox(
                width: 16,
                child: widget.expandable
                    ? GestureDetector(
                        onTap: widget.onToggle,
                        child: Icon(
                          widget.collapsed
                              ? Codicons.chevronRight
                              : Codicons.chevronDown,
                          size: 14,
                          color: foreground,
                        ),
                      )
                    : null,
              ),
              Icon(kind.icon, size: 14, color: kind.color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  widget.symbol.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: widget.selected
                        ? colors.get('list.inactiveSelectionForeground') ??
                              foreground
                        : foreground,
                  ),
                ),
              ),
              if (widget.symbol.detail case final detail?
                  when detail.isNotEmpty) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: colors['descriptionForeground'],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
