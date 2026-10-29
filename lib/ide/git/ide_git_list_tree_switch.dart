// List and Tree, side by side: how a commit's files show in the log, and
// the local changes in the commit panel.

import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../theme/codicons.dart';
import '../ide_hover.dart';
import '../ide_list.dart';

class IdeGitListTreeSwitch extends StatelessWidget {
  const IdeGitListTreeSwitch({
    super.key,
    required this.tree,
    required this.onChanged,
    this.labels = true,
  });

  final bool tree;
  final ValueChanged<bool> onChanged;

  /// Their names by the icons; else the icons only, named when hovered.
  final bool labels;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Segment(
          icon: Codicons.listFlat,
          label: l10n.gitLogList,
          showLabel: labels,
          selected: !tree,
          onTap: () => onChanged(false),
        ),
        const SizedBox(width: 2),
        _Segment(
          icon: Codicons.listTree,
          label: l10n.gitLogTree,
          showLabel: labels,
          selected: tree,
          onTap: () => onChanged(true),
        ),
      ],
    );
  }
}

class _Segment extends StatefulWidget {
  const _Segment({
    required this.icon,
    required this.label,
    required this.showLabel,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool showLabel;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_Segment> createState() => _SegmentState();
}

class _SegmentState extends State<_Segment> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final foreground = IdeListColors.foreground;
    final segment = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: 24,
          padding: EdgeInsets.symmetric(horizontal: widget.showLabel ? 8 : 5),
          decoration: BoxDecoration(
            color: widget.selected
                ? IdeListColors.inactiveSelection
                : _hover
                ? IdeActionButton.hoverBackground
                : null,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 14, color: foreground),
              if (widget.showLabel) ...[
                const SizedBox(width: 4),
                Text(
                  widget.label,
                  style: TextStyle(fontSize: 12, color: foreground),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    if (widget.showLabel) return segment;
    return IdeHover(message: widget.label, child: segment);
  }
}
