import 'dart:async';

import 'package:flutter/material.dart';

import '../../chat/widgets/hover_builder.dart';
import '../../ide/ide_hover.dart';
import '../../ide/ide_menu.dart';
import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';

/// A time to look at: the last of it, up to now.
enum UsageRange {
  hour,
  today,
  day,
  week,
  month,
  quarter,
  all;

  /// Where it starts, at [now]; null for all.
  DateTime? from(DateTime now) => switch (this) {
    hour => now.subtract(const Duration(hours: 1)),
    today => DateTime(now.year, now.month, now.day),
    day => now.subtract(const Duration(hours: 24)),
    week => DateTime(now.year, now.month, now.day - 6),
    month => DateTime(now.year, now.month, now.day - 29),
    quarter => DateTime(now.year, now.month, now.day - 89),
    all => null,
  };

  String label(BuildContext context) {
    final l10n = context.l10n;
    return switch (this) {
      hour => l10n.ustatRangeHour,
      today => l10n.ustatRangeToday,
      day => l10n.ustatRangeDay,
      week => l10n.ustatRangeWeek,
      month => l10n.ustatRangeMonth,
      quarter => l10n.ustatRangeQuarter,
      all => l10n.ustatRangeAll,
    };
  }
}

/// A filter's button: an icon, what is picked, a chevron; a click opens
/// its choices under it ([onTap], with where it is).
class UsageFilterChip extends StatelessWidget {
  const UsageFilterChip({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.tooltip,
    this.chevron = true,
  });

  final IconData icon;
  final String label;
  final void Function(Rect anchor) onTap;

  /// Something is picked (not all): its border and text stronger.
  final bool active;
  final String? tooltip;
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    final chip = HoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (context, hovered) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          final box = context.findRenderObject() as RenderBox?;
          if (box == null) return;
          onTap(box.localToGlobal(Offset.zero) & box.size);
        },
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: active
                ? AppColors.accent.withValues(alpha: 0.10)
                : hovered
                ? AppColors.hover
                : Colors.transparent,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: active
                  ? AppColors.accent.withValues(alpha: 0.55)
                  : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 12,
                color: active ? AppColors.accent : AppColors.textMuted,
              ),
              const SizedBox(width: 5),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: active ? AppColors.text : AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ),
              if (chevron) ...[
                const SizedBox(width: 3),
                Icon(
                  Codicons.chevronDown,
                  size: 11,
                  color: AppColors.textFaint,
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return switch (tooltip) {
      final message? => IdeHover(message: message, child: chip),
      null => chip,
    };
  }
}

/// The time looked at: its presets in a menu, the one picked checked.
class UsageRangePicker extends StatelessWidget {
  const UsageRangePicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.choices = UsageRange.values,
  });

  final UsageRange value;
  final ValueChanged<UsageRange> onChanged;
  final List<UsageRange> choices;

  @override
  Widget build(BuildContext context) => UsageFilterChip(
    icon: Codicons.calendar,
    label: value.label(context),
    active: true,
    onTap: (anchor) => unawaited(
      showIdeMenu(
        context,
        anchor: anchor,
        entries: [
          for (final range in choices)
            IdeMenuAction(
              range.label(context),
              checked: range == value,
              onSelected: () => onChanged(range),
            ),
        ],
      ),
    ),
  );
}

/// One of a filter's choices: its value, as shown, and a mark before it
/// (a series' color).
typedef UsageChoice<T> = ({T value, String label, Color? color});

/// A filter of several choices, any number of them picked (none: all):
/// a menu that stays open as they are checked, searched as it is typed
/// over where there are many.
class UsageMultiPicker<T> extends StatefulWidget {
  const UsageMultiPicker({
    super.key,
    required this.icon,
    required this.label,
    required this.choices,
    required this.selected,
    required this.onChanged,
  });

  final IconData icon;

  /// What it filters by (Model, Upstream…).
  final String label;
  final List<UsageChoice<T>> choices;
  final Set<T> selected;
  final ValueChanged<Set<T>> onChanged;

  @override
  State<UsageMultiPicker<T>> createState() => _UsageMultiPickerState<T>();
}

class _UsageMultiPickerState<T> extends State<UsageMultiPicker<T>> {
  late Set<T> _picked = {...widget.selected};

  @override
  void didUpdateWidget(UsageMultiPicker<T> old) {
    super.didUpdateWidget(old);
    _picked = {...widget.selected};
  }

  String _shown(BuildContext context) {
    final picked = widget.selected;
    if (picked.isEmpty) return '${widget.label}: ${context.l10n.ustatAll}';
    if (picked.length == 1) {
      final only = widget.choices
          .where((choice) => choice.value == picked.first)
          .firstOrNull;
      return '${widget.label}: ${only?.label ?? picked.first}';
    }
    return '${widget.label} · ${picked.length}';
  }

  Widget _dot(Color color) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );

  void _toggle(T value) {
    setState(() {
      if (!_picked.remove(value)) _picked.add(value);
    });
    widget.onChanged({..._picked});
  }

  @override
  Widget build(BuildContext context) => UsageFilterChip(
    icon: widget.icon,
    label: _shown(context),
    active: widget.selected.isNotEmpty,
    onTap: (anchor) => unawaited(
      showIdeMenu(
        context,
        anchor: anchor,
        speedSearch: widget.choices.length > 8,
        entries: [
          IdeMenuAction(
            context.l10n.ustatAll,
            keepOpen: true,
            checkedNow: () => _picked.isEmpty,
            onSelected: () {
              setState(_picked.clear);
              widget.onChanged(const {});
            },
          ),
          if (widget.choices.isNotEmpty) const IdeMenuSeparator(),
          for (final choice in widget.choices)
            IdeMenuAction(
              choice.label,
              icon: switch (choice.color) {
                final color? => Center(child: _dot(color)),
                null => null,
              },
              keepOpen: true,
              checkedNow: () => _picked.contains(choice.value),
              onSelected: () => _toggle(choice.value),
            ),
        ],
      ),
    ),
  );
}

/// One of a few, side by side in a track: the one picked raised.
class UsageSegmented<T> extends StatelessWidget {
  const UsageSegmented({
    super.key,
    required this.value,
    required this.segments,
    required this.onChanged,
    this.dense = false,
  });

  final T value;
  final List<({T value, String label})> segments;
  final ValueChanged<T> onChanged;
  final bool dense;

  @override
  Widget build(BuildContext context) => Container(
    height: dense ? 22 : 26,
    padding: const EdgeInsets.all(2),
    decoration: BoxDecoration(
      color: AppColors.hover,
      borderRadius: BorderRadius.circular(dense ? 11 : 13),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final segment in segments)
          _Segment(
            label: segment.label,
            selected: segment.value == value,
            dense: dense,
            onTap: () => onChanged(segment.value),
          ),
      ],
    ),
  );
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.dense,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool dense;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: HoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (context, hovered) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.surfaceRaised : Colors.transparent,
            borderRadius: BorderRadius.circular(dense ? 9 : 11),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected || hovered ? AppColors.text : AppColors.textMuted,
              fontSize: dense ? 11 : 11.5,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    ),
  );
}

/// The filters, in one row above what they scope (wrapping where it is
/// narrow); [trailing] at its end.
class UsageFilterBar extends StatelessWidget {
  const UsageFilterBar({
    super.key,
    required this.children,
    this.trailing = const [],
  });

  final List<Widget> children;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: Wrap(spacing: 6, runSpacing: 6, children: children)),
      if (trailing.isNotEmpty) ...[
        const SizedBox(width: 8),
        Row(mainAxisSize: MainAxisSize.min, children: trailing),
      ],
    ],
  );
}

/// A small round button with an icon: refreshing, resetting the filters.
class UsageIconButton extends StatelessWidget {
  const UsageIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IdeHover(
    message: tooltip,
    child: HoverBuilder(
      cursor: onPressed == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      builder: (context, hovered) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: hovered && onPressed != null
                ? AppColors.hover
                : Colors.transparent,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(
            icon,
            size: 14,
            color: onPressed == null
                ? AppColors.textFaint
                : AppColors.textMuted,
          ),
        ),
      ),
    ),
  );
}

/// One of a [UsageTabs]': its value, its name, a count after it, a mark
/// before it.
typedef UsageTab<T> = ({T value, String label, String? count, Color? color});

/// Views of one thing side by side, the one looked at raised: the main
/// agent's and each subagent's, as a conversation switches between them.
/// Wraps where there are more than fit.
class UsageTabs<T> extends StatelessWidget {
  const UsageTabs({
    super.key,
    required this.tabs,
    required this.value,
    required this.onChanged,
  });

  final List<UsageTab<T>> tabs;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 4,
    runSpacing: 4,
    children: [
      for (final tab in tabs)
        _Tab(
          tab: tab,
          selected: tab.value == value,
          onTap: () => onChanged(tab.value),
        ),
    ],
  );
}

class _Tab<T> extends StatelessWidget {
  const _Tab({required this.tab, required this.selected, required this.onTap});

  final UsageTab<T> tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: HoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (context, hovered) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accent.withValues(alpha: 0.14)
                : hovered
                ? AppColors.hover
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected
                  ? AppColors.accent.withValues(alpha: 0.5)
                  : AppColors.border.withValues(alpha: 0.6),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (tab.color case final color?) ...[
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  tab.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected || hovered
                        ? AppColors.text
                        : AppColors.textMuted,
                    fontSize: 11.5,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (tab.count case final count?) ...[
                const SizedBox(width: 5),
                Text(
                  count,
                  style: TextStyle(
                    color: AppColors.textFaint,
                    fontSize: 10.5,
                    fontFeatures: const [FontFeature.tabularFigures()],
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

/// Debugging's switch, in a filter bar: off, a chip that starts it; on,
/// a live dot and how many requests were kept whole, a click stops it.
class UsageTraceToggle extends StatelessWidget {
  const UsageTraceToggle({
    super.key,
    required this.on,
    required this.count,
    required this.onChanged,
  });

  final bool on;

  /// The requests kept whole since it was turned on.
  final int count;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // A dot that stays: not one that pulses, which would draw a frame
    // after another for as long as it is on.
    return IdeHover(
      message: on ? l10n.ustatTraceStop : l10n.ustatTraceStartHint,
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(!on),
          child: Container(
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(
              color: on
                  ? AppColors.accent.withValues(alpha: 0.12)
                  : hovered
                  ? AppColors.hover
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: on
                    ? AppColors.accent.withValues(alpha: 0.55)
                    : AppColors.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (on)
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      shape: BoxShape.circle,
                    ),
                  )
                else
                  Icon(Codicons.debugAlt, size: 12, color: AppColors.textMuted),
                const SizedBox(width: 6),
                Text(
                  on ? l10n.ustatTraceOn(count) : l10n.ustatTraceStart,
                  style: TextStyle(
                    color: on ? AppColors.text : AppColors.textMuted,
                    fontSize: 12,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (on && hovered) ...[
                  const SizedBox(width: 6),
                  Icon(Codicons.debugStop, size: 12, color: AppColors.text),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
