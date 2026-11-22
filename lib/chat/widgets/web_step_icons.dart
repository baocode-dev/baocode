import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../icons/icon_library.dart';
import '../../icons/project_icon_view.dart';
import '../../icons/site_icons.dart';
import '../../theme/app_theme.dart';
import '../chat_models.dart';
import '../selection/chat_selection.dart';
import '../step_folds.dart';

/// A web search step's globe icon (Lucide's globe).
const webSearchIcon = 'assets/icons/lucide-globe.svg';

/// The site [target] refers to for a `WebFetch` step; null when [target] is
/// not an HTTP(S) URL with a host.
Uri? webFetchSite(String target) {
  final uri = Uri.tryParse(target.trim());
  if (uri == null || uri.host.isEmpty) return null;
  final scheme = uri.scheme.toLowerCase();
  return scheme == 'http' || scheme == 'https' ? uri : null;
}

/// Whether a [ToolKind.web] step is a web search rather than a page fetch.
bool isWebSearchTool({String? tool, required String target}) => switch (tool) {
  'WebSearch' => true,
  'WebFetch' => false,
  _ => webFetchSite(target) == null,
};

const _groundingRedirectHost = 'vertexaisearch.cloud.google.com';

final _domainHostPattern = RegExp(
  r'^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+$',
  caseSensitive: false,
);

/// Extracts deduplicated source sites from a `WebSearch` tool's [output]
/// (`Results: [...]` from bao_agent or `Links: [...]` from Claude Code CLI).
///
/// Google Grounding redirect URLs (`vertexaisearch.cloud.google.com`) carry the
/// real domain in their `title` field; when `title` is a valid hostname, it is
/// used as the site so its favicon can be fetched.
List<Uri> webSearchResultSites(String? output) {
  if (output == null || output.isEmpty) return const [];
  final sites = <Uri>[];
  final hosts = <String>{};
  for (final line in const LineSplitter().convert(output)) {
    final trimmed = line.trim();
    final String? payload;
    if (trimmed.startsWith('Results:')) {
      payload = trimmed.substring('Results:'.length).trim();
    } else if (trimmed.startsWith('Links:')) {
      payload = trimmed.substring('Links:'.length).trim();
    } else {
      continue;
    }
    if (payload.isEmpty || !payload.startsWith('[')) continue;
    final Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } on FormatException {
      continue;
    }
    if (decoded is! List) continue;
    for (final entry in decoded) {
      if (entry is! Map) continue;
      final url = entry['url'];
      if (url is! String) continue;
      final raw = webFetchSite(url);
      if (raw == null) continue;
      final Uri site;
      if (raw.host.toLowerCase() == _groundingRedirectHost) {
        final title = entry['title'];
        final candidate = title is String ? title.trim() : '';
        if (!_domainHostPattern.hasMatch(candidate)) continue;
        site = Uri.https(candidate.toLowerCase());
      } else {
        site = raw;
      }
      if (hosts.add(site.host.toLowerCase())) {
        sites.add(site);
      }
    }
  }
  return sites;
}

/// Renders the globe icon for a web search step.
Widget webSearchGlobe({double size = 14, Color? color}) => SvgPicture.asset(
  webSearchIcon,
  width: size,
  height: size,
  colorFilter: ColorFilter.mode(color ?? AppColors.textMuted, BlendMode.srcIn),
);

/// Renders a fetched site's favicon in a circular clip.
Widget webSiteFavicon(IconImage image, {double size = 16}) => ClipOval(
  child: SizedBox.square(
    dimension: size,
    child: IconImageView(image, size: size),
  ),
);

/// Smoothly cross-fades and subtly scales when a site's favicon replaces the
/// fallback globe icon.
Widget webIconSwitcher({
  required Widget child,
  Duration duration = const Duration(milliseconds: 200),
}) => AnimatedSwitcher(
  duration: duration,
  switchInCurve: Curves.easeOutCubic,
  switchOutCurve: Curves.easeIn,
  transitionBuilder: (child, animation) => FadeTransition(
    opacity: animation,
    child: ScaleTransition(
      scale: Tween<double>(begin: 0.85, end: 1.0).animate(animation),
      child: child,
    ),
  ),
  child: child,
);

/// A web icon collected from a fold's steps: a search globe, or a fetched
/// site whose favicon shows once available.
sealed class FoldWebIcon {
  const FoldWebIcon();
}

/// A web search step in a fold.
final class FoldWebSearchIcon extends FoldWebIcon {
  const FoldWebSearchIcon();

  @override
  bool operator ==(Object other) => other is FoldWebSearchIcon;

  @override
  int get hashCode => (FoldWebSearchIcon).hashCode;
}

/// A fetched site in a fold, keyed by host.
final class FoldWebSiteIcon extends FoldWebIcon {
  const FoldWebSiteIcon(this.site);

  final Uri site;

  @override
  bool operator ==(Object other) =>
      other is FoldWebSiteIcon &&
      other.site.host.toLowerCase() == site.host.toLowerCase();

  @override
  int get hashCode => site.host.toLowerCase().hashCode;
}

/// The deduplicated web icons among [items] (in order of first appearance):
/// source sites from `WebSearch` results and fetched sites from `WebFetch`
/// (deduplicated by host), plus at most one globe for searches that have not
/// yielded any parsed sites yet; failed calls are skipped.
List<FoldWebIcon> foldWebIcons(Iterable<ChatItem> items) {
  final out = <FoldWebIcon>[];
  var sawSearch = false;
  final hosts = <String>{};
  for (final item in items) {
    if (item is! ToolCallItem ||
        item.kind != ToolKind.web ||
        item.status == ToolStatus.failed ||
        standsOutOfWork(item)) {
      continue;
    }
    if (isWebSearchTool(tool: item.tool, target: item.target)) {
      final sites = webSearchResultSites(item.output);
      if (sites.isNotEmpty) {
        for (final site in sites) {
          if (hosts.add(site.host.toLowerCase())) {
            out.add(FoldWebSiteIcon(site));
          }
        }
      } else if (!sawSearch) {
        sawSearch = true;
        out.add(const FoldWebSearchIcon());
      }
    } else if (webFetchSite(item.target) case final site?) {
      if (hosts.add(site.host.toLowerCase())) {
        out.add(FoldWebSiteIcon(site));
      }
    }
  }
  return out;
}

/// Stacked circular web icons shown after a folded header while it is closed:
/// up to [max] overlapping badges (globes for web searches, favicons for
/// fetched sites that have one), with `+$rest` for any beyond [max].
class StepWebIcons extends StatelessWidget {
  const StepWebIcons({
    super.key,
    required this.icons,
    this.shown = true,
    this.max = 5,
  });

  final List<FoldWebIcon> icons;
  final bool shown;
  final int max;

  static const badgeSize = 22.0;
  static const ringWidth = 1.0;
  static const innerSize = badgeSize - ringWidth * 2;
  static const step = 15.0;
  static const gap = 6.0;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SiteIcons.current,
      builder: (context, _) {
        final resolved = <_ResolvedWebBadge>[
          for (final icon in icons)
            switch (icon) {
              FoldWebSearchIcon() => const _ResolvedWebBadge.search(),
              FoldWebSiteIcon(:final site) => _ResolvedWebBadge.site(
                site.host.toLowerCase(),
                SiteIcons.current.of(site),
              ),
            },
        ];
        return ChatUnselectable(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) => SizeTransition(
              axis: Axis.horizontal,
              alignment: AlignmentDirectional.centerStart,
              sizeFactor: animation,
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: shown && resolved.isNotEmpty
                ? _row(resolved)
                : const SizedBox(key: ValueKey('none'), height: badgeSize),
          ),
        );
      },
    );
  }

  Widget _row(List<_ResolvedWebBadge> badges) {
    final visible = badges.take(max).toList();
    final rest = badges.length - visible.length;
    final stackWidth = badgeSize + (visible.length - 1) * step;
    return Padding(
      key: const ValueKey('web_icons'),
      padding: const EdgeInsetsDirectional.only(start: gap),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Transform.translate(
            offset: const Offset(0, -1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              width: stackWidth,
              height: badgeSize,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (final (i, badge) in visible.indexed)
                    AnimatedPositioned(
                      key: ValueKey(badge.id),
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      left: i * step,
                      top: 0,
                      child: _AnimatedWebBadge(index: i, image: badge.image),
                    ),
                ],
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeIn,
            child: rest > 0
                ? Padding(
                    key: ValueKey(rest),
                    padding: const EdgeInsetsDirectional.only(start: 5),
                    child: Text(
                      '+$rest',
                      style: TextStyle(
                        color: AppColors.textFaint,
                        fontSize: 12,
                      ),
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey(0)),
          ),
        ],
      ),
    );
  }
}

class _AnimatedWebBadge extends StatefulWidget {
  const _AnimatedWebBadge({required this.index, required this.image});

  final int index;
  final IconImage? image;

  @override
  State<_AnimatedWebBadge> createState() => _AnimatedWebBadgeState();
}

class _AnimatedWebBadgeState extends State<_AnimatedWebBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _progress;

  @override
  void initState() {
    super.initState();
    final delayMs = widget.index * 28;
    const enterMs = 200;
    final totalMs = delayMs + enterMs;
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: totalMs),
    );
    _progress = CurvedAnimation(
      parent: _controller,
      curve: Interval(delayMs / totalMs, 1.0, curve: Curves.easeOutCubic),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fill = Color.alphaBlend(
      AppColors.text.withValues(alpha: 0.08),
      AppColors.conversationSurface,
    );
    final outline = AppColors.text.withValues(alpha: 0.12);
    final content = switch (widget.image) {
      final image? => KeyedSubtree(
        key: const ValueKey('favicon'),
        child: webSiteFavicon(image, size: StepWebIcons.innerSize),
      ),
      null => KeyedSubtree(
        key: const ValueKey('globe'),
        child: webSearchGlobe(size: 14, color: AppColors.textMuted),
      ),
    };
    return FadeTransition(
      opacity: _progress,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(-0.22, 0),
          end: Offset.zero,
        ).animate(_progress),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.65, end: 1.0).animate(_progress),
          child: Container(
            width: StepWebIcons.badgeSize,
            height: StepWebIcons.badgeSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.conversationSurface,
            ),
            child: Container(
              width: StepWebIcons.innerSize,
              height: StepWebIcons.innerSize,
              decoration: BoxDecoration(shape: BoxShape.circle, color: fill),
              foregroundDecoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: outline, width: 1),
              ),
              clipBehavior: Clip.antiAlias,
              alignment: Alignment.center,
              child: webIconSwitcher(child: content),
            ),
          ),
        ),
      ),
    );
  }
}

class _ResolvedWebBadge {
  const _ResolvedWebBadge.search() : id = 'search', image = null;
  const _ResolvedWebBadge.site(String host, this.image) : id = 'site:$host';

  final String id;
  final IconImage? image;
}
