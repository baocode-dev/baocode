import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../chat/widgets/hover_builder.dart';
import '../../ide/ide_hover.dart';
import '../../ide/ide_switch.dart';
import '../../kernel/extension_switches.dart';
import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import 'usage_charts.dart';
import 'usage_style.dart';

/// An MCP server's part of a context: its tools' definitions by name,
/// those deferred (out of it until needed) among them, its instructions.
typedef UsageMcpServer = ({
  Map<String, int> tools,
  Set<String> deferred,
  int notes,
});

/// A skill's part of a context; a plugin's ([plugin]) kept on by Claude
/// Code, no switch.
typedef UsageSkill = ({int tokens, bool plugin});

/// The MCP servers' and skills' switches, for a view that shows what they
/// take: as shown (as written once they are), rows of them, and whether
/// one was switched here (UsageSwitchedHint).
mixin UsageSwitching<T extends StatefulWidget> on State<T> {
  ExtensionSwitches? _switched;

  /// One was switched here: it takes on the next request.
  bool switched = false;

  ExtensionSwitches get switches => _switched ?? ExtensionSwitches.current();

  @override
  void initState() {
    super.initState();
    ExtensionSwitches.changes?.addListener(_changed);
  }

  @override
  void dispose() {
    ExtensionSwitches.changes?.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _switch(ExtensionSwitches next) async {
    setState(() {
      _switched = next;
      switched = true;
    });
    try {
      await ExtensionSwitches.save?.call(next);
    } on Object catch (error) {
      debugPrint('Switches not kept: $error');
    }
    if (mounted && identical(_switched, next)) {
      setState(() => _switched = null);
    }
  }

  /// [servers] a row each (its tools under it), a switch each; those
  /// turned off and so not in it ([withOff]) after them, to turn back on.
  List<UsageBreakdownItem> mcpRows(
    Map<String, UsageMcpServer> servers, {
    double Function(int tokens)? scaled,
    bool withOff = false,
  }) {
    final l10n = context.l10n;
    final switches = this.switches;
    final scale = scaled ?? (int tokens) => tokens.toDouble();
    final canSwitch = ExtensionSwitches.save != null;
    final shown = {...servers.keys.map(ExtensionSwitches.normalize)};
    return [
      for (final MapEntry(key: name, :value) in servers.entries)
        () {
          final on = switches.serverEnabled(name);
          final loaded = {
            for (final MapEntry(key: tool, value: tokens)
                in value.tools.entries)
              if (!value.deferred.contains(tool)) tool: tokens,
          };
          return UsageBreakdownItem(
            label: name,
            tokens: scale(
              loaded.values.fold(0, (sum, v) => sum + v) + value.notes,
            ),
            detail: l10n.ustatMcpTools(value.tools.length),
            off: !on,
            enabled: on,
            onSwitch: canSwitch
                ? (enabled) =>
                      unawaited(_switch(switches.withServer(name, enabled)))
                : null,
            children: [
              if (value.notes > 0)
                UsageBreakdownItem(
                  label: l10n.ustatMcpInstructions,
                  tokens: scale(value.notes),
                ),
              for (final MapEntry(key: tool, value: tokens)
                  in value.tools.entries)
                UsageBreakdownItem(
                  label: tool,
                  tokens: value.deferred.contains(tool) ? 0 : scale(tokens),
                  detail: value.deferred.contains(tool)
                      ? l10n.ustatDeferred(UsageFormat.tokens(tokens))
                      : null,
                  off: !on || !switches.toolEnabled(name, tool),
                  enabled: switches.toolEnabled(name, tool),
                  onSwitch: canSwitch && on
                      ? (enabled) => unawaited(
                          _switch(switches.withTool(name, tool, enabled)),
                        )
                      : null,
                ),
            ],
          );
        }(),
      if (withOff)
        for (final name in switches.disabledServers)
          if (!shown.contains(ExtensionSwitches.normalize(name)))
            UsageBreakdownItem(
              label: name,
              tokens: 0,
              detail: l10n.ustatSwitchedOff,
              off: true,
              enabled: false,
              onSwitch: canSwitch
                  ? (enabled) =>
                        unawaited(_switch(switches.withServer(name, enabled)))
                  : null,
            ),
    ];
  }

  /// [skills] a row each, a switch each but a plugin's; those turned off
  /// and so not in it ([withOff]) after them.
  List<UsageBreakdownItem> skillRows(
    Map<String, UsageSkill> skills, {
    double Function(int tokens)? scaled,
    bool withOff = false,
  }) {
    final l10n = context.l10n;
    final switches = this.switches;
    final scale = scaled ?? (int tokens) => tokens.toDouble();
    final canSwitch = ExtensionSwitches.save != null;
    return [
      for (final MapEntry(key: name, :value) in skills.entries)
        () {
          final on = switches.skillEnabled(name);
          return UsageBreakdownItem(
            label: name,
            tokens: scale(value.tokens),
            detail: value.plugin ? l10n.ustatSkillPlugin : null,
            off: !on,
            enabled: on,
            onSwitch: value.plugin || !canSwitch
                ? null
                : (enabled) =>
                      unawaited(_switch(switches.withSkills([name], enabled))),
          );
        }(),
      if (withOff)
        for (final name in switches.disabledSkills)
          if (!skills.containsKey(name))
            UsageBreakdownItem(
              label: name,
              tokens: 0,
              detail: l10n.ustatSwitchedOff,
              off: true,
              enabled: false,
              onSwitch: canSwitch
                  ? (enabled) =>
                        unawaited(_switch(switches.withSkills([name], enabled)))
                  : null,
            ),
    ];
  }
}

/// That a switch takes on the next request.
class UsageSwitchedHint extends StatelessWidget {
  const UsageSwitchedHint({super.key});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(Codicons.info, size: 12, color: AppColors.textFaint),
      const SizedBox(width: 6),
      Expanded(
        child: Text(context.l10n.ustatSwitchedHint, style: UsageText.faint),
      ),
    ],
  );
}

/// A file's path, short: its folder and its name.
String usageShortPath(String path) {
  final parts = path.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty);
  final list = parts.toList();
  if (list.length <= 2) return path;
  return '…/${list[list.length - 2]}/${list.last}';
}

/// A row of a [UsageBreakdownGroup]: a name and what it takes; a switch where it can be
/// turned off; rows under it, shown when it is opened.
class UsageBreakdownItem {
  const UsageBreakdownItem({
    required this.label,
    required this.tokens,
    this.detail,
    this.tooltip,
    this.off = false,
    this.enabled = true,
    this.onSwitch,
    this.children = const [],
  });

  final String label;
  final double tokens;
  final String? detail;
  final String? tooltip;

  /// Turned off already: dimmed.
  final bool off;

  /// Its switch's state.
  final bool enabled;
  final ValueChanged<bool>? onSwitch;
  final List<UsageBreakdownItem> children;
}

/// A part of the context by name: its color, what it takes and its share
/// of all, then a row a name, the largest first, [limit] till Show All.
class UsageBreakdownGroup extends StatefulWidget {
  const UsageBreakdownGroup({
    super.key,
    required this.title,
    required this.color,
    required this.total,
    required this.share,
    required this.rows,
    required this.open,
    required this.onOpen,
    this.limit = 6,
  });

  final String title;
  final Color color;
  final double total;
  final double share;
  final List<UsageBreakdownItem> rows;
  final int limit;
  final Set<String> open;
  final ValueChanged<String> onOpen;

  @override
  State<UsageBreakdownGroup> createState() => _UsageBreakdownGroupState();
}

class _UsageBreakdownGroupState extends State<UsageBreakdownGroup> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final rows = widget.rows;
    final top = rows.fold(0.0, (top, row) => math.max(top, row.tokens));
    final shown = _all ? rows : rows.take(widget.limit).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  rows.isEmpty
                      ? widget.title
                      : '${widget.title}  ·  ${rows.length}',
                  style: UsageText.label.copyWith(
                    color: AppColors.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '≈${UsageFormat.tokens(widget.total)}',
                style: UsageText.tabular.copyWith(fontWeight: FontWeight.w600),
              ),
              SizedBox(
                width: 44,
                child: Text(
                  UsageFormat.percent(widget.share, digits: 1),
                  textAlign: TextAlign.right,
                  style: UsageText.faint.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 3),
        for (final row in shown) ...[
          UsageBreakdownRow(
            item: row,
            fraction: top <= 0 ? 0 : row.tokens / top,
            color: widget.color,
            whole: widget.total / math.max(widget.share, 1e-9),
            open: widget.open.contains('${widget.title}/${row.label}'),
            onOpen: row.children.isEmpty
                ? null
                : () => widget.onOpen('${widget.title}/${row.label}'),
          ),
          if (widget.open.contains('${widget.title}/${row.label}'))
            for (final child
                in row.children..sort((a, b) => b.tokens.compareTo(a.tokens)))
              UsageBreakdownRow(
                item: child,
                indent: 18,
                fraction: row.tokens <= 0 ? 0 : child.tokens / row.tokens,
                color: widget.color,
                whole: widget.total / math.max(widget.share, 1e-9),
              ),
        ],
        if (rows.length > widget.limit)
          Align(
            alignment: Alignment.centerLeft,
            child: HoverBuilder(
              cursor: SystemMouseCursors.click,
              builder: (context, hovered) => GestureDetector(
                onTap: () => setState(() => _all = !_all),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 3, 6, 0),
                  child: Text(
                    _all ? l10n.ustatShowLess : l10n.ustatShowAll(rows.length),
                    style: UsageText.muted.copyWith(
                      color: hovered ? AppColors.text : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class UsageBreakdownRow extends StatelessWidget {
  const UsageBreakdownRow({
    super.key,
    required this.item,
    required this.fraction,
    required this.color,
    required this.whole,
    this.indent = 0,
    this.open = false,
    this.onOpen,
  });

  final UsageBreakdownItem item;
  final double fraction;
  final Color color;

  /// The request's context, for each row's share of it.
  final double whole;
  final double indent;
  final bool open;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final dim = item.off;
    final label = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: item.label,
            style: UsageText.body.copyWith(
              color: dim ? AppColors.textFaint : null,
              decoration: dim ? TextDecoration.lineThrough : null,
              decorationColor: AppColors.textFaint,
            ),
          ),
          if (item.detail case final detail?)
            TextSpan(text: '  $detail', style: UsageText.faint),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final row = HoverBuilder(
      cursor: onOpen == null ? MouseCursor.defer : SystemMouseCursors.click,
      builder: (context, hovered) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onOpen,
        child: Container(
          height: 24,
          padding: EdgeInsets.only(left: 6 + indent, right: 6),
          decoration: BoxDecoration(
            color: hovered ? AppColors.hover : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 14,
                child: onOpen == null
                    ? null
                    : Icon(
                        open ? Codicons.chevronDown : Codicons.chevronRight,
                        size: 11,
                        color: AppColors.textFaint,
                      ),
              ),
              Expanded(
                child: switch (item.tooltip) {
                  final tooltip? => IdeHover(message: tooltip, child: label),
                  null => label,
                },
              ),
              const SizedBox(width: 8),
              UsageMiniBar(
                width: 56,
                fraction: fraction,
                color: dim ? UsagePalette.other : color,
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 40),
                child: Text(
                  UsageFormat.tokens(item.tokens),
                  textAlign: TextAlign.right,
                  style: UsageText.tabular.copyWith(
                    color: dim ? AppColors.textFaint : null,
                  ),
                ),
              ),
              SizedBox(
                width: 44,
                child: Text(
                  whole <= 0
                      ? ''
                      : UsageFormat.percent(item.tokens / whole, digits: 1),
                  textAlign: TextAlign.right,
                  style: UsageText.faint.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              SizedBox(
                width: 36,
                child: switch (item.onSwitch) {
                  final onSwitch? => Align(
                    alignment: Alignment.centerRight,
                    child: IdeSwitch(
                      value: item.enabled,
                      height: 14,
                      semanticLabel: item.label,
                      onChanged: onSwitch,
                    ),
                  ),
                  null => null,
                },
              ),
            ],
          ),
        ),
      ),
    );
    return row;
  }
}
