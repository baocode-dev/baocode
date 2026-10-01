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

/// Keyboard-driven popup for @mentions and /commands. The composer owns the
/// highlighted index; this widget only renders and reports pointer input.
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

  void _revealHighlighted() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final top = widget.highlighted * SuggestionMenu._rowHeight;
    final bottom = top + SuggestionMenu._rowHeight;
    if (top < position.pixels) {
      _scrollController.jumpTo(top);
    } else if (bottom > position.pixels + position.viewportDimension) {
      _scrollController.jumpTo(bottom - position.viewportDimension);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.matches.length.clamp(1, SuggestionMenu._maxVisibleRows);
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
                  maxHeight: rows * SuggestionMenu._rowHeight + 8,
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
                        itemExtent: SuggestionMenu._rowHeight,
                        itemCount: widget.matches.length,
                        itemBuilder: (context, index) => _SuggestionRow(
                          match: widget.matches[index],
                          highlighted: index == widget.highlighted,
                          onHover: () => widget.onHighlight(index),
                          onTap: () => widget.onSelect(index),
                        ),
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
    return MouseRegion(
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
                    suggestion.icon,
                    size: 14,
                    color: highlighted
                        ? colors['editorSuggestWidget.selectedIconForeground']
                        : AppColors.textMuted,
                  ),
                },
              ),
              const SizedBox(width: 6),
              Text.rich(
                _highlightedLabel(
                  isCommand ? '/${suggestion.label}' : suggestion.label,
                  isCommand ? 1 : 0,
                ),
                maxLines: 1,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  suggestion.detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.textFaint, fontSize: 11.5),
                ),
              ),
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
