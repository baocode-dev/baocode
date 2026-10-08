import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/material_file_icons.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import 'composer_mock_data.dart';

/// A ranked suggestion with the indexes of the query characters it matched.
class SuggestionMatch {
  const SuggestionMatch(this.suggestion, this.matched);

  final Suggestion suggestion;
  final List<int> matched;
}

List<SuggestionMatch> rankSuggestions(List<Suggestion> source, String query) {
  final scored = <(SuggestionMatch, int)>[];
  for (final suggestion in source) {
    final match = fuzzyMatch(suggestion.label, query);
    if (match != null) {
      scored.add((SuggestionMatch(suggestion, match.indexes), match.score));
    }
  }
  if (query.isNotEmpty) scored.sort((a, b) => b.$2.compareTo(a.$2));
  return [for (final (match, _) in scored) match];
}

/// [source] (in groups, see [Suggestion.group]) that match [query]: the
/// groups in their order, each's best matches first.
List<SuggestionMatch> rankGroupedSuggestions(
  List<Suggestion> source,
  String query,
) {
  final groups = <String?, List<Suggestion>>{};
  for (final suggestion in source) {
    (groups[suggestion.group] ??= []).add(suggestion);
  }
  return [for (final group in groups.values) ...rankSuggestions(group, query)];
}

/// Keyboard-driven popup for @mentions and /commands. The composer owns the
/// highlighted index; this widget only renders and reports pointer input.
///
/// Suggestions with a [Suggestion.group] are listed under its heading (a
/// conversation's project folder), where it changes: the headings are not
/// for picking, so the arrows go from suggestion to suggestion over them.
class SuggestionMenu extends StatefulWidget {
  const SuggestionMenu({
    super.key,
    required this.title,
    required this.matches,
    required this.highlighted,
    required this.onHighlight,
    required this.onSelect,
  });

  final String title;
  final List<SuggestionMatch> matches;
  final int highlighted;
  final ValueChanged<int> onHighlight;
  final ValueChanged<int> onSelect;

  static const width = 360.0;
  static const _rowHeight = 30.0;
  static const _headingHeight = 26.0;
  static const _maxVisibleRows = 8;

  @override
  State<SuggestionMenu> createState() => _SuggestionMenuState();
}

class _SuggestionMenuState extends State<SuggestionMenu> {
  final ScrollController _scrollController = ScrollController();

  @override
  void didUpdateWidget(SuggestionMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.highlighted != widget.highlighted) _revealHighlighted();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// The rows: each suggestion, by its index, after the heading of its
  /// group where that changes.
  List<({int index, String? heading})> get _entries {
    final entries = <({int index, String? heading})>[];
    String? group;
    for (final (index, match) in widget.matches.indexed) {
      final next = match.suggestion.group;
      if (next != null && next != group) {
        entries.add((index: index, heading: next));
      }
      group = next;
      entries.add((index: index, heading: null));
    }
    return entries;
  }

  static double _heightOf(({int index, String? heading}) entry) =>
      entry.heading == null
      ? SuggestionMenu._rowHeight
      : SuggestionMenu._headingHeight;

  void _revealHighlighted() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    var top = 0.0;
    for (final entry in _entries) {
      if (entry.heading == null && entry.index == widget.highlighted) break;
      top += _heightOf(entry);
    }
    // The first of a group shows with its heading.
    final heading = _entries.any(
      (e) => e.heading != null && e.index == widget.highlighted,
    );
    final bottom = top + SuggestionMenu._rowHeight;
    if (heading) top -= SuggestionMenu._headingHeight;
    if (top < position.pixels) {
      _scrollController.jumpTo(top);
    } else if (bottom > position.pixels + position.viewportDimension) {
      _scrollController.jumpTo(bottom - position.viewportDimension);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    final height = entries.isEmpty
        ? SuggestionMenu._rowHeight
        : entries.fold(0.0, (sum, entry) => sum + _heightOf(entry));
    final colors = themeColors;
    // The editor's suggest widget, as the chat input's completions upstream.
    return Material(
      type: MaterialType.transparency,
      child: Container(
        width: SuggestionMenu.width,
        decoration: BoxDecoration(
          color: colors['editorSuggestWidget.background'],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors['editorSuggestWidget.border']),
          boxShadow: [
            BoxShadow(
              color: colors['widget.shadow'],
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 7, 10, 3),
              child: Text(
                widget.title,
                style: TextStyle(
                  color: AppColors.textFaint,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            // Up to its natural height, less when the window has no room
            // (the floating layer caps it).
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight:
                      height.clamp(
                        0,
                        SuggestionMenu._maxVisibleRows *
                            SuggestionMenu._rowHeight,
                      ) +
                      8,
                ),
                child: widget.matches.isEmpty
                    ? Center(
                        child: Text(
                          context.l10n.composerNoResults,
                          style: TextStyle(
                            color: AppColors.textFaint,
                            fontSize: 12.5,
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                        itemExtentBuilder: (index, _) => index < entries.length
                            ? _heightOf(entries[index])
                            : null,
                        itemCount: entries.length,
                        itemBuilder: (context, at) {
                          final (:index, :heading) = entries[at];
                          if (heading != null) return _GroupHeading(heading);
                          return _SuggestionRow(
                            match: widget.matches[index],
                            highlighted: index == widget.highlighted,
                            onHover: () => widget.onHighlight(index),
                            onTap: () => widget.onSelect(index),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({
    required this.match,
    required this.highlighted,
    required this.onHover,
    required this.onTap,
  });

  final SuggestionMatch match;
  final bool highlighted;
  final VoidCallback onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final suggestion = match.suggestion;
    final isCommand = suggestion.kind == SuggestionKind.command;
    final colors = themeColors;
    final outline = highlighted
        ? colors.get('editorSuggestWidget.focusOutline')
        : null;
    final label = Text.rich(
      _highlightedLabel(
        isCommand ? '/${suggestion.label}' : suggestion.label,
        isCommand ? 1 : 0,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    // The editor keeps the focus while the arrows move the highlight: the
    // row says it is the one Enter takes.
    return Semantics(
      button: true,
      selected: highlighted,
      excludeSemantics: true,
      label: [
        isCommand ? '/${suggestion.label}' : suggestion.label,
        if (suggestion.detail.isNotEmpty) suggestion.detail,
        ?suggestion.group,
      ].join(', '),
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onHover: (_) {
          if (!highlighted) onHover();
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: highlighted
                  ? colors['editorSuggestWidget.selectedBackground']
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
            ),
            foregroundDecoration: outline == null
                ? null
                : BoxDecoration(
                    border: Border.all(color: outline),
                    borderRadius: BorderRadius.circular(5),
                  ),
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  child: switch (suggestion.kind) {
                    SuggestionKind.file => FileIcon(suggestion.label, size: 15),
                    SuggestionKind.folder => FolderIcon(
                      suggestion.label,
                      size: 15,
                    ),
                    _ => Icon(
                      suggestion.kind == SuggestionKind.session
                          ? Icons.chat_bubble_outline_rounded
                          : suggestion.icon,
                      size: 14,
                      color: highlighted
                          ? colors['editorSuggestWidget.selectedIconForeground']
                          : AppColors.textMuted,
                    ),
                  },
                ),
                const SizedBox(width: 6),
                // A conversation's title takes the room it needs, up to all.
                if (suggestion.detail.isEmpty)
                  Expanded(child: label)
                else ...[
                  label,
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      suggestion.detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textFaint,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ],
                // An icon rather than '↵': no bundled font has that glyph,
                // and on the web the fallback font is fetched on first use.
                if (highlighted)
                  Icon(
                    Icons.keyboard_return_rounded,
                    size: 12,
                    color: AppColors.textFaint,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  TextSpan _highlightedLabel(String label, int offset) {
    final hits = {for (final index in match.matched) index + offset};
    final colors = themeColors;
    return TextSpan(
      style: TextStyle(
        color:
            colors[highlighted
                ? 'editorSuggestWidget.selectedForeground'
                : 'editorSuggestWidget.foreground'],
        fontSize: 12.5,
      ),
      children: [
        for (var i = 0; i < label.length; i++)
          TextSpan(
            text: label[i],
            style: hits.contains(i)
                ? TextStyle(
                    color:
                        colors[highlighted
                            ? 'editorSuggestWidget.focusHighlightForeground'
                            : 'editorSuggestWidget.highlightForeground'],
                    fontWeight: FontWeight.w600,
                  )
                : null,
          ),
      ],
    );
  }
}

/// Over a group's suggestions: its project's folder.
class _GroupHeading extends StatelessWidget {
  const _GroupHeading(this.name);

  final String name;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 2),
      child: Row(
        children: [
          SizedBox(width: 18, child: FolderIcon(name, size: 14)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.textFaint,
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
