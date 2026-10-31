// Speed search, as IntelliJ's trees and lists have: typed over a list, what
// is typed shows as a filter on, and the matched characters of what it
// leaves stand out. The sidebar's projects and the menus that ask for it
// (`showIdeMenu(speedSearch: true)`) share these.

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/codicons.dart';
import '../theme/workbench_theme.dart' show themeColors;
import 'ide_hover.dart';
import 'ide_list.dart';

/// What the speed search has been typed, as a filter on: how many of
/// [total] it leaves ([found]), and a button to clear it. Red while none
/// matches.
class IdeSpeedSearchField extends StatelessWidget {
  const IdeSpeedSearchField({
    super.key,
    required this.query,
    required this.found,
    required this.total,
    required this.onClear,
  });

  final String query;
  final int found;
  final int total;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final none = found == 0;
    final tint = none ? themeColors['errorForeground'] : AppColors.accent;
    return Container(
      height: 22,
      padding: const EdgeInsets.only(left: 6, right: 2),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: .12),
        border: Border.all(color: tint.withValues(alpha: .7)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Icon(Codicons.filterFilled, size: 13, color: tint),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              query,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: none ? tint : AppColors.text,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.none,
              ),
            ),
          ),
          Text(
            '$found/$total',
            style: TextStyle(
              color: none ? tint : AppColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w400,
              decoration: TextDecoration.none,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 2),
          IdeActionButton(
            icon: Icons.close_rounded,
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            size: 18,
            iconSize: 12,
            onPressed: onClear,
          ),
        ],
      ),
    );
  }
}

/// [text], the characters at [matched] in the list's highlight, as a
/// tree's filter shows its matches.
TextSpan ideSpeedSpan(String text, List<int> matched) {
  if (matched.isEmpty) return TextSpan(text: text);
  final highlight = TextStyle(
    color: IdeListColors.highlight,
    fontWeight: FontWeight.w700,
  );
  final hits = matched.toSet();
  final spans = <TextSpan>[];
  var start = 0;
  for (var i = 1; i <= text.length; i++) {
    if (i < text.length && hits.contains(i) == hits.contains(start)) continue;
    spans.add(
      TextSpan(
        text: text.substring(start, i),
        style: hits.contains(start) ? highlight : null,
      ),
    );
    start = i;
  }
  return TextSpan(children: spans);
}
