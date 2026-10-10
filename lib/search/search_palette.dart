import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../chat/widgets/hover_builder.dart';
import '../ide/ide_fuzzy.dart';
import '../ide/ide_quick_input.dart' show IdeKeycap;
import '../ide/ide_quick_open.dart';
import '../l10n/l10n.dart';
import '../platform/app_platform.dart';
import '../sidebar/sidebar.dart' show StatusIndicator, relativeTime;
import '../theme/app_theme.dart';
import '../theme/material_file_icons.dart';
import '../theme/workbench_theme.dart' show themeColors;
import '../workspace/workspace.dart';
import 'conversation_search.dart';

/// What the palette lists: everything, or one kind.
enum SearchFilter {
  all,
  agents,
  files,
  actions,
  settings;

  String label(AppLocalizations l10n) => switch (this) {
    all => l10n.paletteFilterAll,
    agents => l10n.paletteFilterAgents,
    files => l10n.paletteFilterFiles,
    actions => l10n.paletteFilterActions,
    settings => l10n.paletteFilterSettings,
  };
}

/// Something the palette runs: a window command, or a settings page.
class PaletteAction {
  const PaletteAction({
    required this.id,
    required this.label,
    required this.icon,
    required this.run,
    this.keybinding,
  });

  /// Its command's id: what [SearchPalette.recentActions] keeps.
  final String id;
  final String label;
  final IconData icon;

  /// The key that runs it too, as the keybindings have it (`⌘N`).
  final String? keybinding;
  final VoidCallback run;
}

/// Shows the search palette over the window: agents (their titles and what
/// was said in them), the project's files, the window's actions and the
/// settings' pages, each a filter of its own. Picking one closes it first.
Future<void> showSearchPalette(
  BuildContext context, {
  required List<AgentThread> agents,
  required ConversationSearch conversations,
  required List<PaletteAction> actions,
  required List<PaletteAction> settings,
  required ValueChanged<AgentThread> onOpenAgent,
  required ValueChanged<String> onOpenFile,
  required ValueChanged<PaletteAction> onRunAction,
  List<String> recentActions = const [],
  IdeFileIndex? files,
  SearchFilter filter = SearchFilter.all,
}) {
  VoidCallback? picked;
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    // Black, not the theme's: as upstream's modal backdrops.
    barrierColor: const Color(0x33000000),
    transitionDuration: const Duration(milliseconds: 100),
    transitionBuilder: (context, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
    pageBuilder: (context, _, _) => SearchPalette(
      agents: agents,
      conversations: conversations,
      files: files,
      actions: actions,
      recentActions: recentActions,
      settings: settings,
      filter: filter,
      onPick: (run) {
        picked = run;
        Navigator.of(context).pop();
      },
      onOpenAgent: onOpenAgent,
      onOpenFile: onOpenFile,
      onRunAction: onRunAction,
    ),
  ).then((_) => picked?.call());
}

/// The palette [showSearchPalette] shows.
class SearchPalette extends StatefulWidget {
  const SearchPalette({
    super.key,
    required this.agents,
    required this.conversations,
    required this.actions,
    required this.settings,
    required this.onPick,
    required this.onOpenAgent,
    required this.onOpenFile,
    required this.onRunAction,
    this.recentActions = const [],
    this.files,
    this.filter = SearchFilter.all,
  });

  /// The agents to find, the most recent first.
  final List<AgentThread> agents;
  final ConversationSearch conversations;

  /// The current project's files; none without a project.
  final IdeFileIndex? files;
  final List<PaletteAction> actions;

  /// The ids of the actions last run, the last first.
  final List<String> recentActions;
  final List<PaletteAction> settings;
  final SearchFilter filter;

  /// What was picked, to run once the palette has closed.
  final ValueChanged<VoidCallback> onPick;
  final ValueChanged<AgentThread> onOpenAgent;
  final ValueChanged<String> onOpenFile;
  final ValueChanged<PaletteAction> onRunAction;

  static const width = 640.0;
  static const rowHeight = 30.0;
  static const snippetRowHeight = 48.0;

  @override
  State<SearchPalette> createState() => _SearchPaletteState();
}

/// A row of the list: what it shows, and what picking it does.
class _Entry {
  const _Entry({
    required this.title,
    required this.run,
    this.titleMatches = const [],
    this.leading,
    this.snippet,
    this.trailing,
    this.keybinding,
  });

  final String title;
  final List<int> titleMatches;
  final Widget? leading;

  /// What a conversation says, the match highlighted: a second line.
  final ConversationHit? snippet;
  final String? trailing;
  final String? keybinding;
  final VoidCallback run;

  double get height => snippet == null
      ? SearchPalette.rowHeight
      : SearchPalette.snippetRowHeight;
}

typedef _Section = ({String label, List<_Entry> entries});

class _SearchPaletteState extends State<SearchPalette> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _input = FocusNode(debugLabel: 'search palette');
  final ScrollController _scroll = ScrollController();
  late SearchFilter _filter = widget.filter;
  int _selected = 0;

  /// Laid out last: the sections, and their rows in order.
  List<_Section> _sections = const [];
  List<_Entry> _rows = const [];

  /// What the conversations say, for [_hitsFor]; searched a moment after
  /// typing stops.
  List<ConversationHit> _hits = const [];
  String _hitsFor = '';
  bool _searching = false;
  Timer? _debounce;
  int _generation = 0;

  /// In each section of everything: the first few.
  static const _fewAgents = 5;
  static const _fewHits = 5;
  static const _fewFiles = 5;
  static const _fewActions = 5;
  static const _fewSettings = 3;
  static const _many = 100;

  @override
  void initState() {
    super.initState();
    _query.addListener(_queryChanged);
    widget.files?.addListener(_refresh);
    unawaited(widget.files?.refresh());
    // Read meanwhile, so the first search is quick.
    unawaited(widget.conversations.prepare());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.files?.removeListener(_refresh);
    _query.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  String _lastText = '';

  void _queryChanged() {
    if (_query.text == _lastText) return;
    _lastText = _query.text;
    setState(() => _selected = 0);
    _debounce?.cancel();
    final query = _query.text.trim();
    if (query.length < 2) {
      _generation++;
      setState(() {
        _hits = const [];
        _hitsFor = '';
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 150), () => _search(query));
  }

  Future<void> _search(String query) async {
    final generation = ++_generation;
    // The conversations open in this run, as they are now; then those kept
    // on disk that are not.
    final open = <String, ConversationHit>{};
    for (final thread in widget.agents) {
      final id = thread.id ?? '#${identityHashCode(thread)}';
      if (!thread.isOpen) continue;
      if (findIn(id, sessionText(thread.session), query) case final hit?) {
        open[id] = hit;
      }
    }
    List<ConversationHit> kept;
    try {
      kept = await widget.conversations.search(query, limit: _many);
    } on Object {
      kept = const [];
    }
    if (!mounted || generation != _generation) return;
    setState(() {
      _hits = [
        ...open.values,
        for (final hit in kept)
          if (!open.containsKey(hit.sessionId)) hit,
      ];
      _hitsFor = query;
      _searching = false;
    });
  }

  void _setFilter(SearchFilter filter) {
    if (filter == _filter) return;
    setState(() {
      _filter = filter;
      _selected = 0;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _cycleFilter(int step) {
    const filters = SearchFilter.values;
    _setFilter(filters[(_filter.index + step) % filters.length]);
  }

  void _pick(_Entry entry) => widget.onPick(entry.run);

  // --- What is listed --------------------------------------------------------

  bool _shows(SearchFilter filter) =>
      _filter == SearchFilter.all || _filter == filter;

  int get _agentLimit => _filter == SearchFilter.all ? _fewAgents : _many;

  List<_Section> _build(AppLocalizations l10n) {
    final query = _query.text.trim();
    final all = _filter == SearchFilter.all;
    if (query.isEmpty) {
      return [
        if (_shows(SearchFilter.agents))
          (
            label: l10n.paletteRecentAgents,
            entries: [
              for (final thread in widget.agents.take(_agentLimit))
                _agentEntry(thread, l10n),
            ],
          ),
        if (_shows(SearchFilter.actions)) ...[
          if (_recentActions() case final recent when recent.isNotEmpty)
            (
              label: l10n.paletteRecentActions,
              entries: [
                for (final action in recent.take(all ? 3 : _many))
                  _actionEntry(action),
              ],
            ),
          (
            label: l10n.paletteFilterActions,
            entries: [
              for (final action in widget.actions.take(
                all ? _fewActions : _many,
              ))
                _actionEntry(action),
            ],
          ),
        ],
        if (_filter == SearchFilter.settings)
          (
            label: l10n.paletteFilterSettings,
            entries: [
              for (final setting in widget.settings) _actionEntry(setting),
            ],
          ),
        if (_filter == SearchFilter.files && widget.files != null)
          (
            label: l10n.paletteFilesIn(p.basename(widget.files!.root)),
            entries: _fileEntries('', _many),
          ),
      ];
    }
    return [
      if (_shows(SearchFilter.agents)) ...[
        (label: l10n.paletteFilterAgents, entries: _agentMatches(query, l10n)),
        (label: l10n.paletteMessages, entries: _hitEntries(l10n)),
      ],
      if (_shows(SearchFilter.files) && widget.files != null)
        (
          label: l10n.paletteFilterFiles,
          entries: _fileEntries(query, all ? _fewFiles : _many),
        ),
      if (_shows(SearchFilter.actions))
        (
          label: l10n.paletteFilterActions,
          entries: _actionMatches(
            widget.actions,
            query,
            all ? _fewActions : _many,
          ),
        ),
      if (_shows(SearchFilter.settings))
        (
          label: l10n.paletteFilterSettings,
          entries: _actionMatches(
            widget.settings,
            query,
            all ? _fewSettings : _many,
          ),
        ),
    ];
  }

  List<PaletteAction> _recentActions() {
    final byId = {for (final action in widget.actions) action.id: action};
    return [for (final id in widget.recentActions) ?byId[id]];
  }

  _Entry _agentEntry(
    AgentThread thread,
    AppLocalizations l10n, {
    List<int> matches = const [],
    ConversationHit? snippet,
  }) => _Entry(
    title: thread.localizedTitle(l10n),
    titleMatches: matches,
    leading: SizedBox(
      width: 14,
      child: Center(
        child: thread.status == ThreadStatus.idle
            ? Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.textFaint,
                  shape: BoxShape.circle,
                ),
              )
            : StatusIndicator(thread.status),
      ),
    ),
    snippet: snippet,
    trailing:
        '${thread.project.name}   '
        '${relativeTime(thread.updatedAt, DateTime.now(), l10n)}',
    run: () => widget.onOpenAgent(thread),
  );

  /// Agents whose title matches (fuzzily), else whose project's name does;
  /// the better matches first, then the more recent.
  List<_Entry> _agentMatches(String query, AppLocalizations l10n) {
    final scored = <({AgentThread thread, int score, List<int> matches})>[];
    final lower = query.toLowerCase();
    for (final thread in widget.agents) {
      final title = thread.localizedTitle(l10n);
      final at = title.toLowerCase().indexOf(lower);
      if (at >= 0) {
        scored.add((
          thread: thread,
          score: 1 << 20,
          matches: [for (var i = at; i < at + lower.length; i++) i],
        ));
      } else if (ideFuzzyMatch(query, title) case final match?) {
        scored.add((
          thread: thread,
          score: match.score,
          matches: match.positions,
        ));
      } else if (thread.project.name.toLowerCase().contains(lower)) {
        scored.add((thread: thread, score: -1, matches: const []));
      }
    }
    // A stable sort keeps the recent order among equals.
    final order = {for (final (i, thread) in widget.agents.indexed) thread: i};
    scored.sort((a, b) {
      final score = b.score.compareTo(a.score);
      return score != 0 ? score : order[a.thread]!.compareTo(order[b.thread]!);
    });
    return [
      for (final match in scored.take(_agentLimit))
        _agentEntry(match.thread, l10n, matches: match.matches),
    ];
  }

  List<_Entry> _hitEntries(AppLocalizations l10n) {
    if (_hitsFor != _query.text.trim()) return const [];
    final byId = <String, AgentThread>{
      for (final thread in widget.agents)
        thread.id ?? '#${identityHashCode(thread)}': thread,
    };
    return [
      for (final hit in _hits)
        if (byId[hit.sessionId] case final thread?)
          _agentEntry(thread, l10n, snippet: hit),
    ].take(_filter == SearchFilter.all ? _fewHits : _many).toList();
  }

  List<_Entry> _fileEntries(String query, int limit) {
    final index = widget.files!;
    final filter = IdeQuickOpenQuery.parse(query).filter;
    final scored = <({int i, int score, List<int> label})>[];
    final relative = index.relativePaths;
    if (filter.isEmpty) {
      for (var i = 0; i < relative.length && i < limit; i++) {
        scored.add((i: i, score: 0, label: const []));
      }
    } else {
      for (var i = 0; i < relative.length; i++) {
        if (scoreFilePath(filter, relative[i]) case final match?) {
          scored.add((i: i, score: match.score, label: match.label));
        }
      }
      scored.sort((a, b) => b.score.compareTo(a.score));
    }
    return [
      for (final match in scored.take(limit))
        _fileEntry(
          index.paths[match.i],
          relative[match.i],
          matches: match.label,
        ),
    ];
  }

  _Entry _fileEntry(
    String path,
    String relative, {
    List<int> matches = const [],
  }) {
    final slash = relative.lastIndexOf('/');
    return _Entry(
      title: relative.substring(slash + 1),
      titleMatches: matches,
      leading: FileIcon(path, size: 15),
      trailing: slash < 0 ? null : relative.substring(0, slash),
      run: () => widget.onOpenFile(path),
    );
  }

  List<_Entry> _actionMatches(
    List<PaletteAction> actions,
    String query,
    int limit,
  ) {
    final scored = [
      for (final action in actions)
        if (ideFuzzyMatch(query, action.label) case final match?)
          (action: action, match: match),
    ]..sort((a, b) => b.match.score.compareTo(a.match.score));
    return [
      for (final (:action, :match) in scored.take(limit))
        _actionEntry(action, matches: match.positions),
    ];
  }

  _Entry _actionEntry(PaletteAction action, {List<int> matches = const []}) =>
      _Entry(
        title: action.label,
        titleMatches: matches,
        leading: Icon(action.icon, size: 15),
        keybinding: action.keybinding,
        run: () => widget.onRunAction(action),
      );

  // --- Keys ------------------------------------------------------------------

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    // An input method composing text keeps its keys.
    final composing = _query.value.composing;
    if (composing.isValid && !composing.isCollapsed) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    final command = AppPlatform.isMacOS
        ? keyboard.isMetaPressed
        : keyboard.isControlPressed;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        _move(1);
      case LogicalKeyboardKey.arrowUp:
        _move(-1);
      case LogicalKeyboardKey.pageDown:
        _move(8);
      case LogicalKeyboardKey.pageUp:
        _move(-8);
      case LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter:
        if (_selected < _rows.length) _pick(_rows[_selected]);
      case LogicalKeyboardKey.escape:
        Navigator.of(context).pop();
      case LogicalKeyboardKey.tab:
        _cycleFilter(keyboard.isShiftPressed ? -1 : 1);
      case LogicalKeyboardKey.bracketLeft when command:
        _cycleFilter(-1);
      case LogicalKeyboardKey.bracketRight when command:
        _cycleFilter(1);
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _move(int step) {
    if (_rows.isEmpty) return;
    setState(() => _selected = (_selected + step).clamp(0, _rows.length - 1));
    _reveal();
  }

  /// Scrolls the selected row into view.
  void _reveal() {
    if (!_scroll.hasClients) return;
    var top = 0.0;
    var found = false;
    for (final section in _sections) {
      if (section.entries.isEmpty) continue;
      top += _headerHeight;
      for (final entry in section.entries) {
        if (identical(entry, _rows[_selected])) {
          found = true;
          break;
        }
        top += entry.height;
      }
      if (found) break;
    }
    final height = _rows[_selected].height;
    final position = _scroll.position;
    if (top < position.pixels) {
      _scroll.jumpTo(math.max(0, top - _headerHeight));
    } else if (top + height > position.pixels + position.viewportDimension) {
      _scroll.jumpTo(top + height - position.viewportDimension + 4);
    }
  }

  static const _headerHeight = 28.0;

  // --- Drawing ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = themeColors;
    _sections = _build(l10n);
    _rows = [for (final section in _sections) ...section.entries];
    if (_selected >= _rows.length) _selected = math.max(0, _rows.length - 1);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(SearchPalette.width, constraints.maxWidth - 32);
        final maxListHeight = math.max(
          120.0,
          math.min(420.0, constraints.maxHeight * 0.6),
        );
        return Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: EdgeInsets.only(
              top: math.min(72, constraints.maxHeight * 0.08),
            ),
            child: Focus(
              onKeyEvent: _onKey,
              child: Material(
                color: colors['quickInput.background'],
                elevation: 6,
                shadowColor: colors['widget.shadow'],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: colors.get('widget.border') ?? AppColors.partBorder,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: SizedBox(
                  width: width,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildInput(l10n),
                      _buildFilters(l10n),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: maxListHeight),
                        child: _buildList(l10n),
                      ),
                      _buildFooter(l10n),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInput(AppLocalizations l10n) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
    child: TextField(
      controller: _query,
      focusNode: _input,
      autofocus: true,
      autocorrect: false,
      enableSuggestions: false,
      cursorColor: AppColors.text,
      cursorHeight: 17,
      style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
      decoration: InputDecoration(
        isDense: true,
        border: InputBorder.none,
        hintText: l10n.palettePlaceholder,
        hintStyle: TextStyle(color: AppColors.textFaint, fontSize: 15),
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
      ),
    ),
  );

  Widget _buildFilters(AppLocalizations l10n) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 2, 10, 6),
    child: Row(
      children: [
        for (final filter in SearchFilter.values)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: _FilterChip(
              label: filter.label(l10n),
              selected: filter == _filter,
              onTap: () {
                _setFilter(filter);
                _input.requestFocus();
              },
            ),
          ),
        const Spacer(),
        if (_searching)
          SizedBox.square(
            dimension: 10,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: AppColors.textFaint,
            ),
          ),
        const SizedBox(width: 6),
      ],
    ),
  );

  Widget _buildList(AppLocalizations l10n) {
    final sections = [
      for (final section in _sections)
        if (section.entries.isNotEmpty) section,
    ];
    if (sections.isEmpty) {
      final query = _query.text.trim();
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
        child: Text(
          _searching
              ? l10n.paletteSearching
              : _filter == SearchFilter.files && widget.files == null
              ? l10n.paletteNoProject
              : query.isEmpty
              ? l10n.paletteTypeToSearch
              : l10n.paletteNoResults,
          style: TextStyle(color: AppColors.textFaint, fontSize: 12.5),
        ),
      );
    }
    final children = <Widget>[];
    var index = 0;
    for (final section in sections) {
      children.add(
        Container(
          height: _headerHeight,
          padding: const EdgeInsets.only(left: 16, top: 8),
          alignment: Alignment.centerLeft,
          child: Text(
            section.label,
            style: TextStyle(
              color: AppColors.textFaint,
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );
      for (final entry in section.entries) {
        final at = index++;
        children.add(
          _PaletteRow(
            entry: entry,
            selected: at == _selected,
            onHover: () {
              if (_selected != at) setState(() => _selected = at);
            },
            onTap: () => _pick(entry),
          ),
        );
      }
    }
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: ListView(
        controller: _scroll,
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 6),
        children: children,
      ),
    );
  }

  Widget _buildFooter(AppLocalizations l10n) {
    final command = AppPlatform.isMacOS ? '⌘' : 'Ctrl+';
    final style = TextStyle(color: AppColors.textFaint, fontSize: 11.5);
    Widget hint(List<String> keys, String label) => Padding(
      padding: const EdgeInsets.only(right: 14),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final key in keys) ...[
            Text(key, style: style.copyWith(color: AppColors.textMuted)),
            const SizedBox(width: 4),
          ],
          Text(label, style: style),
        ],
      ),
    );
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.partBorder)),
      ),
      child: Row(
        children: [
          hint(['↑↓'], l10n.paletteHintSelect),
          hint(['↵'], l10n.paletteHintOpen),
          hint(['$command[', '$command]'], l10n.paletteHintChangeFilter),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => HoverBuilder(
    cursor: SystemMouseCursors.click,
    builder: (context, hovered) => GestureDetector(
      onTap: onTap,
      child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? themeColors['toolbar.activeBackground']
              : hovered
              ? AppColors.hover
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.textPrimary : AppColors.textMuted,
            fontSize: 12.5,
          ),
        ),
      ),
    ),
  );
}

class _PaletteRow extends StatelessWidget {
  const _PaletteRow({
    required this.entry,
    required this.selected,
    required this.onHover,
    required this.onTap,
  });

  final _Entry entry;
  final bool selected;
  final VoidCallback onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    final foreground = selected ? AppColors.textPrimary : AppColors.text;
    final faint = TextStyle(color: AppColors.textFaint, fontSize: 11.5);
    final snippet = entry.snippet;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onHover: (_) => onHover(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: entry.height,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            // A shade, not the list's focus color: as Cursor's palette.
            color: selected
                ? AppColors.textPrimary.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          // High contrast themes outline it, as the IDE's lists do.
          foregroundDecoration: selected
              ? switch (colors.get('contrastActiveBorder')) {
                  final outline? => BoxDecoration(
                    border: Border.all(color: outline),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  null => null,
                }
              : null,
          child: IconTheme.merge(
            data: IconThemeData(color: AppColors.textMuted),
            child: Row(
              children: [
                if (entry.leading case final leading?) ...[
                  SizedBox(width: 16, child: Center(child: leading)),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _highlighted(
                        entry.title,
                        entry.titleMatches,
                        TextStyle(color: foreground, fontSize: 13),
                      ),
                      if (snippet != null) ...[
                        const SizedBox(height: 2),
                        _highlighted(snippet.snippet, [
                          for (
                            var i = snippet.matchStart;
                            i < snippet.matchStart + snippet.matchLength;
                            i++
                          )
                            i,
                        ], TextStyle(color: AppColors.textMuted, fontSize: 12)),
                      ],
                    ],
                  ),
                ),
                if (entry.trailing case final trailing?) ...[
                  const SizedBox(width: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Text(
                      trailing,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: faint,
                    ),
                  ),
                ],
                if (entry.keybinding case final keys?) ...[
                  const SizedBox(width: 12),
                  IdeKeycap(keys),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// [text] with the characters at [matches] in bold and the link color.
  static Widget _highlighted(String text, List<int> matches, TextStyle style) {
    if (matches.isEmpty) {
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    final marked = matches.toSet();
    final spans = <TextSpan>[];
    var start = 0;
    for (var i = 1; i <= text.length; i++) {
      final at =
          i == text.length || marked.contains(i) != marked.contains(i - 1);
      if (!at) continue;
      final part = text.substring(start, i);
      spans.add(
        marked.contains(start)
            ? TextSpan(
                text: part,
                style: TextStyle(
                  color: themeColors['list.highlightForeground'],
                  fontWeight: FontWeight.w600,
                ),
              )
            : TextSpan(text: part),
      );
      start = i;
    }
    return Text.rich(
      TextSpan(children: spans),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
}
