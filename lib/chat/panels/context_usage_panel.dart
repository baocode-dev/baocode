import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../chat/widgets/hover_builder.dart';
import '../../ide/ide_hover.dart';
import '../../kernel/kernel_types.dart';
import '../../keybindings/chat_keybindings.dart';
import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../../usage/ui/usage_breakdown.dart';
import '../../usage/ui/usage_style.dart';
import '../chat_keys.dart';
import 'panel_card.dart';

/// A part of the window: the usage views' (UsagePalette.part), or one
/// of Claude Code's they do not know, by its own name.
typedef _Part = ({String key, String label, int tokens, Color color});

/// Modal area, opened from the composer ring: what fills the context
/// window, a part each (the usage views' parts, in their colors), and in a
/// part picked what is in it (the MCP servers and skills a switch each);
/// the room left until it is compacted; what the session cost, and how
/// much of the account's limits is used.
class ContextUsagePanel extends StatefulWidget {
  const ContextUsagePanel({
    super.key,
    required this.usage,
    required this.onClose,
    this.stats,
  });

  final ContextUsage usage;
  final UsageStats? stats;
  final VoidCallback onClose;

  static String _format(int tokens) => tokens >= 1000000
      ? '${(tokens / 1000000).toStringAsFixed(1)}M'
      : tokens >= 1000
      ? '${(tokens / 1000).toStringAsFixed(1)}k'
      : '$tokens';

  /// Claude Code's categories (by their English names, as it reports
  /// them) as the usage views' parts: an agent's definition is in the
  /// Agent tool's, the servers' instructions with their tools, the slash
  /// commands with the skills.
  @visibleForTesting
  static String? partOf(String category) =>
      switch (category.toLowerCase().trim()) {
        'system prompt' => 'system',
        'system tools' || 'custom agents' => 'tools',
        'mcp tools' || 'mcp server instructions' => 'mcp',
        'memory files' => 'memory',
        'skills' || 'slash commands' => 'skills',
        'messages' => 'messages',
        _ => null,
      };

  @override
  State<ContextUsagePanel> createState() => _ContextUsagePanelState();
}

class _ContextUsagePanelState extends State<ContextUsagePanel>
    with UsageSwitching {
  /// The part whose things show.
  String? _picked;
  final Set<String> _open = {};

  static const _order = [
    'system',
    'memory',
    'skills',
    'tools',
    'mcp',
    'messages',
    'toolResult',
  ];

  List<_Part> _parts() {
    final l10n = context.l10n;
    final usage = widget.usage;
    final tokens = <String, int>{};
    final labels = <String, String>{};
    for (final segment in usage.segments) {
      if (segment.kind != ContextKind.used || segment.tokens <= 0) continue;
      final key = ContextUsagePanel.partOf(segment.label) ?? segment.label;
      tokens[key] = (tokens[key] ?? 0) + segment.tokens;
      labels[key] ??= segment.label;
    }
    if (tokens.isEmpty) {
      return [
        (
          key: 'used',
          label: l10n.usageUsed,
          tokens: usage.used,
          color: UsagePalette.part('messages'),
        ),
      ];
    }
    // The tools' results apart from the rest of the messages, by Claude
    // Code's estimate of them.
    final detail = usage.detail;
    final messages = tokens['messages'] ?? 0;
    if (detail != null && detail.messages > 0 && messages > 0) {
      final results = (messages * detail.toolResults / detail.messages).round();
      if (results > 0) {
        tokens['toolResult'] = results;
        tokens['messages'] = messages - results;
      }
    }
    final known = _order.where(tokens.containsKey);
    final others = tokens.keys.where((key) => !_order.contains(key));
    return [
      for (final key in [...known, ...others])
        (
          key: key,
          label: _order.contains(key)
              ? UsageFormat.part(context, key)
              : labels[key] ?? key,
          tokens: tokens[key]!,
          color: UsagePalette.part(key),
        ),
    ];
  }

  /// [part]'s things, as the kernel tells them; none without.
  List<UsageBreakdownItem> _items(_Part part, ContextDetail detail) {
    final l10n = context.l10n;
    double raw(int tokens) => tokens.toDouble();
    // The messages' are estimates: in the part's count.
    double Function(int) scaledTo(int estimate) =>
        estimate <= 0 ? raw : (tokens) => tokens * part.tokens / estimate;
    switch (part.key) {
      case 'system':
        return [
          for (final item in detail.systemPrompt)
            UsageBreakdownItem(label: item.name, tokens: raw(item.tokens)),
        ];
      case 'tools':
        return [
          for (final item in detail.systemTools)
            UsageBreakdownItem(label: item.name, tokens: raw(item.tokens)),
          for (final item in detail.agents)
            UsageBreakdownItem(
              label: item.name,
              tokens: raw(item.tokens),
              detail: l10n.usageAgentDefinition,
            ),
          for (final item in detail.deferredTools)
            UsageBreakdownItem(
              label: item.name,
              tokens: item.loaded ? raw(item.tokens) : 0,
              detail: item.loaded
                  ? null
                  : l10n.ustatDeferred(UsageFormat.tokens(item.tokens)),
              off: !item.loaded,
            ),
        ];
      case 'mcp':
        final servers = <String, UsageMcpServer>{};
        for (final item in detail.mcpTools) {
          final server = servers[item.group ?? ''] ??= (
            tools: <String, int>{},
            deferred: <String>{},
            notes: 0,
          );
          server.tools[item.name] = item.tokens;
          if (!item.loaded) server.deferred.add(item.name);
        }
        final tools = detail.mcpTools
            .where((item) => item.loaded)
            .fold(0, (sum, item) => sum + item.tokens);
        // The servers' instructions, not told apart by server.
        final notes = part.tokens - tools;
        return [
          ...mcpRows(servers, withOff: true),
          if (notes > 0 && detail.mcpTools.isNotEmpty)
            UsageBreakdownItem(
              label: l10n.ustatMcpInstructions,
              tokens: raw(notes),
            ),
        ];
      case 'skills':
        return skillRows({
          for (final item in detail.skills)
            item.name: (
              tokens: item.tokens,
              plugin: item.group != null || item.source == 'plugin',
            ),
        }, withOff: true);
      case 'memory':
        return [
          for (final item in detail.memoryFiles)
            UsageBreakdownItem(
              label: usageShortPath(item.name),
              tooltip: item.name,
              detail: item.source,
              tokens: raw(item.tokens),
            ),
        ];
      case 'toolResult':
        final scaled = scaledTo(detail.toolResults);
        return [
          for (final item in detail.toolUses)
            if (item.results > 0)
              UsageBreakdownItem(
                label: item.name,
                tokens: scaled(item.results),
              ),
        ];
      case 'messages':
        final scaled = scaledTo(detail.messages - detail.toolResults);
        return [
          if (detail.userMessages > 0)
            UsageBreakdownItem(
              label: l10n.ustatPartUser,
              tokens: scaled(detail.userMessages),
            ),
          if (detail.assistantMessages > 0)
            UsageBreakdownItem(
              label: l10n.ustatPartAssistant,
              tokens: scaled(detail.assistantMessages),
            ),
          if (detail.toolCalls > 0)
            UsageBreakdownItem(
              label: l10n.ustatPartToolUse,
              tokens: scaled(detail.toolCalls),
              children: [
                for (final item in detail.toolUses)
                  if (item.tokens > 0)
                    UsageBreakdownItem(
                      label: item.name,
                      tokens: scaled(item.tokens),
                    ),
              ],
            ),
          if (detail.attachmentTokens > 0)
            UsageBreakdownItem(
              label: l10n.usageAttachments,
              tokens: scaled(detail.attachmentTokens),
              children: [
                for (final item in detail.attachments)
                  if (item.tokens > 0)
                    UsageBreakdownItem(
                      label: item.name,
                      tokens: scaled(item.tokens),
                    ),
              ],
            ),
        ];
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final usage = widget.usage;
    final used = usage.used;
    final total = usage.window;
    final parts = _parts();
    final reserved = usage.segments
        .where((s) => s.kind == ContextKind.buffer)
        .fold(0, (sum, s) => sum + s.tokens);
    final detail = usage.detail;
    // Where it is compacted: as told, else where the reserve starts.
    final compactAt =
        detail?.autoCompactAt ?? (reserved > 0 ? total - reserved : null);
    final left = compactAt == null ? null : math.max(0, compactAt - used);
    final stats = widget.stats;
    final picked = parts.where((p) => p.key == _picked).firstOrNull;
    final items = picked == null || detail == null
        ? const <UsageBreakdownItem>[]
        : _items(picked, detail);
    final faint = TextStyle(color: AppColors.textFaint, fontSize: 11);
    return PanelCard(
      maxBodyHeight: 440,
      header: Row(
        children: [
          Text(
            l10n.usageContextWindow,
            style: TextStyle(
              color: AppColors.text,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              [
                l10n.usageTokensSummary(
                  ContextUsagePanel._format(used),
                  ContextUsagePanel._format(total),
                  total == 0 ? '0' : (used / total * 100).toStringAsFixed(0),
                ),
                if (left != null)
                  l10n.usageUntilCompaction(ContextUsagePanel._format(left)),
              ].join('  ·  '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: faint,
            ),
          ),
          const SizedBox(width: 8),
          // With the keys of Toggle Context Panel, which closes it too
          // (none by default).
          IdeHover(
            message: ChatKeys.titleWithKey(
              l10n.commonClose,
              ChatCommandIds.toggleContextPanel,
              const {ChatContextKeys.inChat: true},
            ),
            child: GestureDetector(
              onTap: widget.onClose,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Icon(
                  Icons.close_rounded,
                  size: 15,
                  color: AppColors.textMuted,
                ),
              ),
            ),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 8,
              width: double.infinity,
              child: CustomPaint(
                painter: _WindowPainter(
                  window: total,
                  used: [
                    for (final part in parts)
                      (part.tokens, part.color, part.key == _picked),
                  ],
                  picked: _picked != null,
                  compactAt: compactAt,
                  track: themeColors['editorWidget.border'],
                  hatch: AppColors.textFaint,
                  gap: AppColors.surface,
                ),
              ),
            ),
            if (parts.length > 1 || reserved > 0) ...[
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) {
                  // As many columns as fit, each at least 190 wide.
                  final columns = math.max(
                    1,
                    math.min(3, ((constraints.maxWidth + 8) / 198).floor()),
                  );
                  final width =
                      (constraints.maxWidth - 8 * (columns - 1)) / columns;
                  return Wrap(
                    spacing: 8,
                    runSpacing: 0,
                    children: [
                      for (final part in parts)
                        SizedBox(
                          width: width,
                          child: _PartCell(
                            color: part.color,
                            label: part.label,
                            value: ContextUsagePanel._format(part.tokens),
                            share: used <= 0 ? null : part.tokens / used,
                            picked: part.key == _picked,
                            onTap: detail == null || parts.length < 2
                                ? null
                                : () => setState(
                                    () => _picked = part.key == _picked
                                        ? null
                                        : part.key,
                                  ),
                          ),
                        ),
                      // Not taken: room kept free, at the window's end.
                      if (reserved > 0)
                        SizedBox(
                          width: width,
                          child: _PartCell(
                            label: l10n.usageReservedForCompaction,
                            value: ContextUsagePanel._format(reserved),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
            if (picked != null && items.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.fromLTRB(2, 8, 2, 6),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: AppColors.partBorder),
                    bottom: BorderSide(color: AppColors.partBorder),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    UsageBreakdownGroup(
                      key: ValueKey(picked.key),
                      title: picked.label,
                      color: picked.color,
                      total: picked.tokens.toDouble(),
                      share: used <= 0 ? 0 : picked.tokens / used,
                      rows: items,
                      limit: 10,
                      open: _open,
                      onOpen: (key) => setState(() {
                        if (!_open.remove(key)) _open.add(key);
                      }),
                    ),
                    if (switched) ...[
                      const SizedBox(height: 6),
                      const UsageSwitchedHint(),
                    ],
                  ],
                ),
              ),
            ],
            if (stats?.cache case final cache?) ...[
              const SizedBox(height: 10),
              _PromptCacheMeter(cache: cache),
            ],
            if (stats != null &&
                (stats.costUsd != null ||
                    stats.limits.isNotEmpty ||
                    stats.limitsState != LimitsState.idle)) ...[
              const SizedBox(height: 12),
              Divider(height: 1, color: AppColors.partBorder),
              const SizedBox(height: 10),
              _PlanUsage(stats: stats),
            ],
          ],
        ),
      ),
    );
  }
}

/// A part's name, what it takes and its share of all taken; picked, its
/// things show under the parts. Without a [color], room not taken (the
/// reserve, hatched as in the bar).
class _PartCell extends StatelessWidget {
  const _PartCell({
    required this.label,
    required this.value,
    this.color,
    this.share,
    this.picked = false,
    this.onTap,
  });

  final Color? color;
  final String label;
  final String value;
  final double? share;
  final bool picked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final mono = TextStyle(
      color: AppColors.text,
      fontFamily: AppFonts.mono,
      fontFamilyFallback: AppFonts.monoFallbacks,
      fontSize: 11,
    );
    return HoverBuilder(
      cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      builder: (context, hovered) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: picked
                ? AppColors.accent.withValues(alpha: 0.14)
                : hovered && onTap != null
                ? AppColors.hover
                : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                  border: color == null
                      ? Border.all(color: AppColors.textFaint)
                      : null,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                ),
              ),
              Text(value, style: mono),
              SizedBox(
                width: 38,
                child: Text(
                  share == null ? '' : '${(share! * 100).toStringAsFixed(0)}%',
                  textAlign: TextAlign.right,
                  style: mono.copyWith(color: AppColors.textFaint),
                ),
              ),
              SizedBox(
                width: 14,
                child: onTap == null
                    ? null
                    : Icon(
                        picked ? Codicons.chevronUp : Codicons.chevronDown,
                        size: 11,
                        color: AppColors.textFaint,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// How the prompt cache took the last request's input, in a row as the
/// plan's limits: a strip of it whole (read, written, neither), its hit
/// rate, and the conversation's; the counts on hover.
class _PromptCacheMeter extends StatelessWidget {
  const _PromptCacheMeter({required this.cache});

  final PromptCache cache;

  static String _percent(CacheTokens tokens) =>
      (tokens.hitRate * 100).toStringAsFixed(0);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final last = cache.last;
    final all = cache.conversation;
    final colors = themeColors;
    final format = ContextUsagePanel._format;
    return IdeHover(
      message: [
        l10n.usageCacheLast(
          format(last.read),
          format(last.written),
          format(last.uncached),
        ),
        l10n.usageCacheConversation(
          format(all.read),
          format(all.written),
          _percent(all),
        ),
        l10n.usageCacheExcludes,
      ].join('\n'),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: Text(
              l10n.usagePromptCache,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
            ),
          ),
          Expanded(
            child: SizedBox(
              height: 4,
              child: CustomPaint(
                painter: _UsageBarPainter(
                  window: last.total,
                  used: [
                    (last.read, colors['charts.green']),
                    (last.written, colors['charts.yellow']),
                    (last.uncached, colors['charts.red']),
                  ],
                  track: colors['editorWidget.border'],
                ),
              ),
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              '${_percent(last)}%',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: AppColors.text,
                fontFamily: AppFonts.mono,
                fontFamilyFallback: AppFonts.monoFallbacks,
                fontSize: 11,
              ),
            ),
          ),
          SizedBox(
            width: 104,
            child: Text(
              l10n.usageCacheOverall(_percent(all)),
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.textFaint, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

/// The account's limits, one row each, and what the session cost.
class _PlanUsage extends StatelessWidget {
  const _PlanUsage({required this.stats});

  final UsageStats stats;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                context.l10n.usagePlanUsage,
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (stats.costUsd case final cost?)
              _Stat(
                label: context.l10n.usageThisSession,
                value: '\$${cost.toStringAsFixed(2)}',
              ),
          ],
        ),
        for (final limit in stats.limits) ...[
          const SizedBox(height: 8),
          _LimitMeter(limit: limit),
        ],
        // Nothing known yet: say why there are no rows.
        if (stats.limits.isEmpty)
          if (switch (stats.limitsState) {
                LimitsState.checking => context.l10n.usageCheckingLimits,
                LimitsState.unavailable => context.l10n.usageLimitsUnavailable,
                LimitsState.off => context.l10n.usageLimitsAfterMessage,
                LimitsState.idle => null,
              }
              case final note?) ...[
            const SizedBox(height: 8),
            Text(
              note,
              style: TextStyle(color: AppColors.textFaint, fontSize: 11),
            ),
          ],
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
        ),
        const SizedBox(width: 6),
        Text(
          value,
          style: TextStyle(
            color: AppColors.text,
            fontFamily: AppFonts.mono,
            fontFamilyFallback: AppFonts.monoFallbacks,
            fontSize: 11.5,
          ),
        ),
      ],
    );
  }
}

class _LimitMeter extends StatelessWidget {
  const _LimitMeter({required this.limit});

  final RateLimitWindow limit;

  @override
  Widget build(BuildContext context) {
    final resets = limit.resetsAt;
    // Past its reset, the window starts over.
    final over = resets != null && !resets.isAfter(DateTime.now());
    final fraction = over ? 0.0 : limit.utilization.clamp(0.0, 1.0);
    // As upstream's quota indicator.
    final color =
        themeColors[fraction >= 0.9
            ? 'editorError.foreground'
            : fraction >= 0.7
            ? 'editorWarning.foreground'
            : 'focusBorder'];
    return Row(
      children: [
        SizedBox(
          width: 150,
          child: Text(
            limit.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
          ),
        ),
        Expanded(
          child: SizedBox(
            height: 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: fraction,
                color: color,
                backgroundColor: themeColors['editorWidget.border'],
              ),
            ),
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            '${(fraction * 100).round()}%',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: fraction >= 0.9 ? color : AppColors.text,
              fontFamily: AppFonts.mono,
              fontFamilyFallback: AppFonts.monoFallbacks,
              fontSize: 11,
            ),
          ),
        ),
        SizedBox(
          width: 104,
          child: Text(
            resets == null || over
                ? ''
                : context.l10n.usageResets(
                    resetsIn(resets, l10n: context.l10n),
                  ),
            textAlign: TextAlign.right,
            maxLines: 1,
            style: TextStyle(color: AppColors.textFaint, fontSize: 11),
          ),
        ),
      ],
    );
  }
}

/// How long until [time], e.g. "in 46m", "in 3h 20m", "in 2d 5h"; in
/// [l10n]'s language (English when null).
@visibleForTesting
String resetsIn(DateTime time, {DateTime? now, AppLocalizations? l10n}) {
  final strings = l10n ?? englishLocalizations;
  final left = time.difference(now ?? DateTime.now());
  final minutes = left.inMinutes.clamp(0, 1 << 31);
  if (minutes < 60) return strings.usageInMinutes(minutes);
  final hours = minutes ~/ 60;
  if (hours < 24) {
    return minutes % 60 == 0
        ? strings.usageInHours(hours)
        : strings.usageInHoursMinutes(hours, minutes % 60);
  }
  return hours % 24 == 0
      ? strings.usageInDays(hours ~/ 24)
      : strings.usageInDaysHours(hours ~/ 24, hours % 24);
}

/// The window as one rounded strip: what is used from the left, a part
/// each, a hairline of the surface between them (a part too small to see
/// is drawn 2 pixels wide); where it is compacted on, hatched to its end.
/// A part picked, the others fade.
class _WindowPainter extends CustomPainter {
  const _WindowPainter({
    required this.window,
    required this.used,
    required this.track,
    required this.hatch,
    required this.gap,
    this.picked = false,
    this.compactAt,
  });

  static const _minWidth = 2.0;

  final int window;
  final List<(int, Color, bool)> used;
  final bool picked;
  final int? compactAt;
  final Color track;
  final Color hatch;
  final Color gap;

  @override
  void paint(Canvas canvas, Size size) {
    final bar = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height / 2),
    );
    canvas
      ..save()
      ..clipRRect(bar)
      ..drawRect(Offset.zero & size, Paint()..color = track);
    if (window > 0) {
      if (compactAt case final at? when at < window) {
        final x = size.width * at / window;
        final rect = Rect.fromLTRB(x, 0, size.width, size.height);
        canvas
          ..save()
          ..clipRect(rect);
        final paint = Paint()
          ..color = hatch.withValues(alpha: 0.45)
          ..strokeWidth = 1;
        for (var d = x - size.height; d < size.width; d += 4) {
          canvas.drawLine(
            Offset(d, size.height),
            Offset(d + size.height, 0),
            paint,
          );
        }
        canvas.restore();
      }
      double width(int tokens) => tokens <= 0
          ? 0
          : (size.width * tokens / window).clamp(_minWidth, size.width);
      var x = 0.0;
      for (final (i, (tokens, color, lit)) in used.indexed) {
        final w = width(tokens).clamp(0.0, size.width - x);
        if (w <= 0) continue;
        canvas.drawRect(
          Rect.fromLTWH(x, 0, w, size.height),
          Paint()..color = color.withValues(alpha: picked && !lit ? 0.35 : 1),
        );
        x += w;
        if (i < used.length - 1 && w > 3) {
          canvas.drawRect(
            Rect.fromLTWH(x - 1, 0, 1, size.height),
            Paint()..color = gap,
          );
        }
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WindowPainter old) =>
      old.window != window ||
      old.picked != picked ||
      old.compactAt != compactAt ||
      old.track != track ||
      !listEquals(old.used, used);
}

/// A whole as one rounded strip: its parts from the left, one color a
/// part, end to end. A part too small to see is drawn 2 pixels wide.
class _UsageBarPainter extends CustomPainter {
  const _UsageBarPainter({
    required this.window,
    required this.used,
    required this.track,
  });

  static const _minWidth = 2.0;

  final int window;
  final List<(int, Color)> used;

  /// Under what is used.
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final bar = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height / 2),
    );
    canvas
      ..save()
      ..clipRRect(bar)
      ..drawRect(Offset.zero & size, Paint()..color = track);
    if (window > 0) {
      double width(int tokens) => tokens <= 0
          ? 0
          : (size.width * tokens / window).clamp(_minWidth, size.width);
      var x = 0.0;
      for (final (tokens, color) in used) {
        final w = width(tokens).clamp(0.0, size.width - x);
        canvas.drawRect(
          Rect.fromLTWH(x, 0, w, size.height),
          Paint()..color = color,
        );
        x += w;
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_UsageBarPainter old) =>
      old.window != window || old.track != track || !listEquals(old.used, used);
}
