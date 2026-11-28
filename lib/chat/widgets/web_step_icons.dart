import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../browser/browser_steps.dart' show browserIcon;
import '../../icons/icon_library.dart';
import '../../icons/project_icon_view.dart';
import '../../icons/site_icons.dart';
import '../../theme/app_theme.dart';
import '../chat_models.dart';
import '../selection/chat_selection.dart';
import '../step_folds.dart';

/// A web search step's globe icon (Phosphor's globe-simple).
const webSearchIcon = 'assets/icons/ph-globe-simple.svg';

/// The site [target] refers to for a `WebFetch` step; null when [target] is
/// not an HTTP(S) URL with a host.
Uri? webFetchSite(String target) {
  final uri = Uri.tryParse(target.trim());
  if (uri == null || uri.host.isEmpty) return null;
  final scheme = uri.scheme.toLowerCase();
  return scheme == 'http' || scheme == 'https' ? uri : null;
}

final _ipHostPattern = RegExp(r'^[\d.]+$|:');
final _browserOutputUrlPattern = RegExp(
  r'^URL:\s*(https?://\S+)',
  multiLine: true,
);

/// A public HTTP(S) site with a domain name (not `localhost` or an IP
/// address), suitable for fetching a favicon.
Uri? _publicSite(String raw) {
  final uri = webFetchSite(raw);
  if (uri == null) return null;
  final host = uri.host.toLowerCase();
  if (!host.contains('.') ||
      host == 'localhost' ||
      host.endsWith('.localhost') ||
      host.endsWith('.local') ||
      _ipHostPattern.hasMatch(host)) {
    return null;
  }
  return uri;
}

/// Public sites a [ToolKind.browser] step opened, navigated to, or read.
/// Scans only the head of [ToolCallItem.output] so huge DOM snapshots stay O(1).
List<Uri> browserStepSites(ToolCallItem item) {
  final sites = <Uri>[];
  final hosts = <String>{};
  void add(String? raw) {
    if (raw == null || raw.isEmpty) return;
    final site = _publicSite(raw);
    if (site != null && hosts.add(site.host.toLowerCase())) {
      sites.add(site);
    }
  }

  if (item.input['url'] case final String url) add(url);
  if (item.tool == 'browser_act' && item.input['steps'] is List) {
    for (final step in (item.input['steps'] as List).whereType<Map>()) {
      if (step['action'] == 'navigate' && step['url'] is String) {
        add(step['url'] as String);
      }
    }
  }
  final output = item.output;
  if (output != null && output.isNotEmpty) {
    final head = output.length > 512 ? output.substring(0, 512) : output;
    if (head.contains('URL:')) {
      for (final match in _browserOutputUrlPattern.allMatches(head)) {
        add(match.group(1));
      }
    }
  }
  if (sites.isEmpty &&
      (item.tool == 'browser_open' || item.tool == 'browser_navigate')) {
    final target = item.target.trim();
    if (target.isNotEmpty && !target.contains(RegExp(r'\s'))) {
      add(target.contains('://') ? target : 'https://$target');
    }
  }
  return sites;
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

/// A `"url":"…"` pair in a results list, for one cut short of valid JSON.
final _urlPairPattern = RegExp(r'"url"\s*:\s*"(https?://[^"\\]+)"');

/// Whether [url] is a search engine's own redirect to a result: no site
/// of its own to show (Brave's `/go/`, 360's and Sogou's `/link`, Bing's
/// `/ck/a`, DuckDuckGo's `/l/`).
bool _isEngineRedirect(Uri url) {
  final host = url.host.toLowerCase();
  final path = url.path;
  bool at(String domain) => host == domain || host.endsWith('.$domain');
  return (at('brave.com') && path.startsWith('/go/')) ||
      ((at('so.com') || at('sogou.com')) && path.startsWith('/link')) ||
      (at('bing.com') && path.startsWith('/ck/')) ||
      (at('duckduckgo.com') && path.startsWith('/l/'));
}

/// Extracts deduplicated source sites from a `WebSearch` tool's [output]
/// (`Results: [...]` from bao_agent or `Links: [...]` from Claude Code CLI).
///
/// Google Grounding redirect URLs (`vertexaisearch.cloud.google.com`) carry the
/// real domain in their `title` field; when `title` is a valid hostname, it is
/// used as the site so its favicon can be fetched. A search engine's own
/// redirect links are skipped: their site is the engine's, not the result's.
/// A list cut short (an output shortened for showing) still gives the sites
/// of the entries that survived whole.
List<Uri> webSearchResultSites(String? output) {
  if (output == null ||
      output.isEmpty ||
      (!output.contains('Results:') && !output.contains('Links:'))) {
    return const [];
  }
  final sites = <Uri>[];
  final hosts = <String>{};
  void add(String url, {Object? title}) {
    final raw = webFetchSite(url);
    if (raw == null) return;
    final Uri site;
    if (raw.host.toLowerCase() == _groundingRedirectHost) {
      final candidate = title is String ? title.trim() : '';
      if (!_domainHostPattern.hasMatch(candidate)) return;
      site = Uri.https(candidate.toLowerCase());
    } else if (_isEngineRedirect(raw)) {
      return;
    } else {
      site = raw;
    }
    if (hosts.add(site.host.toLowerCase())) sites.add(site);
  }

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
    Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } on FormatException {
      decoded = null;
    }
    if (decoded is List) {
      for (final entry in decoded) {
        if (entry is! Map) continue;
        final url = entry['url'];
        if (url is String) add(url, title: entry['title']);
      }
    } else {
      for (final match in _urlPairPattern.allMatches(payload)) {
        add(match.group(1)!);
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

/// Renders the browser icon (Lucide chrome) for a browser step badge.
Widget webBrowserMark({double size = 14, Color? color}) => SvgPicture.asset(
  browserIcon,
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

/// How dark a favicon may be and still read on the dark surface, and how
/// light it may be and do the same: below the first it stands on a light
/// plate, above the second on a dark one.
const _darkFavicon = 0.3;
const _lightFavicon = 0.7;

/// Renders a fetched site's favicon in a step's row, on a plate picked by
/// how light it is ([IconImage.luminance]): a dark mark (GitHub's) on a
/// light one, a light mark on a dark one, anything between (or one whose
/// light is not known) on the faint plate the folded header's badges have.
/// [size] is the plate's, its 1px ring's included.
Widget webSiteFaviconBadge(IconImage image, {double size = 18}) {
  final surface = AppColors.conversationSurface;
  final (plate, ring) = switch (image.luminance) {
    final light? when light < _darkFavicon => (
      Color.alphaBlend(Colors.white.withValues(alpha: 0.92), surface),
      Colors.black.withValues(alpha: 0.12),
    ),
    final light? when light > _lightFavicon => (
      Color.alphaBlend(Colors.black.withValues(alpha: 0.5), surface),
      AppColors.text.withValues(alpha: 0.2),
    ),
    _ => (
      Color.alphaBlend(AppColors.text.withValues(alpha: 0.08), surface),
      AppColors.text.withValues(alpha: 0.12),
    ),
  };
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: plate,
      border: Border.all(color: ring),
    ),
    child: ClipOval(child: IconImageView(image, size: size - 2)),
  );
}

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

/// A web icon collected from a fold's steps: a search globe, a browser mark,
/// or a fetched/browsed site whose favicon shows once available.
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

/// A browser step in a fold with no public site URL (e.g. localhost or tab
/// actions without a URL).
final class FoldWebBrowserIcon extends FoldWebIcon {
  const FoldWebBrowserIcon();

  @override
  bool operator ==(Object other) => other is FoldWebBrowserIcon;

  @override
  int get hashCode => (FoldWebBrowserIcon).hashCode;
}

/// A fetched or browsed site in a fold, keyed by host.
final class FoldWebSiteIcon extends FoldWebIcon {
  const FoldWebSiteIcon(this.site, {this.fromBrowser = false});

  final Uri site;

  /// Whether this site came from a [ToolKind.browser] step: falls back to
  /// the browser icon rather than the globe while its favicon is unavailable.
  final bool fromBrowser;

  @override
  bool operator ==(Object other) =>
      other is FoldWebSiteIcon &&
      other.site.host.toLowerCase() == site.host.toLowerCase();

  @override
  int get hashCode => site.host.toLowerCase().hashCode;
}

/// Single-pass collector for [foldWebIcons], shared with [FoldSummary].
class FoldWebIconCollector {
  final List<FoldWebIcon> _out = [];
  final Set<String> _hosts = {};
  bool _sawSearch = false;
  bool _sawBrowserSite = false;
  int? _browserPlaceholderAt;

  void add(ChatItem item) {
    if (item is! ToolCallItem ||
        item.status == ToolStatus.failed ||
        standsOutOfWork(item)) {
      return;
    }
    if (item.kind == ToolKind.web) {
      if (isWebSearchTool(tool: item.tool, target: item.target)) {
        final sites = webSearchResultSites(item.output);
        if (sites.isNotEmpty) {
          for (final site in sites) {
            if (_hosts.add(site.host.toLowerCase())) {
              _out.add(FoldWebSiteIcon(site));
            }
          }
        } else if (!_sawSearch) {
          _sawSearch = true;
          _out.add(const FoldWebSearchIcon());
        }
      } else if (webFetchSite(item.target) case final site?) {
        if (_hosts.add(site.host.toLowerCase())) {
          _out.add(FoldWebSiteIcon(site));
        }
      }
    } else if (item.kind == ToolKind.browser) {
      final sites = browserStepSites(item);
      if (sites.isNotEmpty) {
        _sawBrowserSite = true;
        if (_browserPlaceholderAt case final at?) {
          _out.removeAt(at);
          _browserPlaceholderAt = null;
        }
        for (final site in sites) {
          if (_hosts.add(site.host.toLowerCase())) {
            _out.add(FoldWebSiteIcon(site, fromBrowser: true));
          }
        }
      } else if (!_sawBrowserSite && _browserPlaceholderAt == null) {
        _browserPlaceholderAt = _out.length;
        _out.add(const FoldWebBrowserIcon());
      }
    }
  }

  List<FoldWebIcon> get icons => _out;
}

/// The deduplicated web and browser icons among [items] (in order of first
/// appearance): source sites from `WebSearch` results, fetched sites from
/// `WebFetch`, and public sites from browser steps (deduplicated by host),
/// plus at most one globe for searches without parsed sites and at most one
/// browser icon for browser steps without public sites; failed calls are
/// skipped.
List<FoldWebIcon> foldWebIcons(Iterable<ChatItem> items) {
  final collector = FoldWebIconCollector();
  for (final item in items) {
    collector.add(item);
  }
  return collector.icons;
}

/// Stacked circular web icons shown after a folded header while it is closed:
/// up to [max] overlapping badges (globes for web searches, browser marks for
/// browser steps, favicons for sites that have one), with `+$rest` for any
/// beyond [max].
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
    final visibleCount = icons.length < max ? icons.length : max;
    final rest = icons.length - visibleCount;
    final needsSiteIcons =
        shown &&
        icons.take(visibleCount).any((icon) => icon is FoldWebSiteIcon);

    Widget buildContent(BuildContext context, Widget? _) {
      final resolved = shown && visibleCount > 0
          ? <_ResolvedWebBadge>[
              for (var i = 0; i < visibleCount; i++)
                switch (icons[i]) {
                  FoldWebSearchIcon() => const _ResolvedWebBadge.search(),
                  FoldWebBrowserIcon() => const _ResolvedWebBadge.browser(),
                  FoldWebSiteIcon(:final site, :final fromBrowser) =>
                    _ResolvedWebBadge.site(
                      site.host.toLowerCase(),
                      SiteIcons.current.of(site),
                      fromBrowser: fromBrowser,
                    ),
                },
            ]
          : const <_ResolvedWebBadge>[];
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
          child: resolved.isNotEmpty
              ? _row(resolved, rest)
              : const SizedBox(key: ValueKey('none'), height: badgeSize),
        ),
      );
    }

    if (!needsSiteIcons) return buildContent(context, null);
    return ListenableBuilder(
      listenable: SiteIcons.current,
      builder: buildContent,
    );
  }

  Widget _row(List<_ResolvedWebBadge> visible, int rest) {
    final stackWidth = badgeSize + (visible.length - 1) * step;
    return Padding(
      key: const ValueKey('web_icons'),
      padding: const EdgeInsetsDirectional.only(start: gap),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Transform.translate(
            // The line's glyphs sit a little below its box's middle (CJK
            // ideographs and lowercase Latin both): the badges follow.
            offset: const Offset(0, 0.5),
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
                      child: _AnimatedWebBadge(
                        index: i,
                        image: badge.image,
                        browserFallback: badge.browserFallback,
                      ),
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
  const _AnimatedWebBadge({
    required this.index,
    required this.image,
    this.browserFallback = false,
  });

  final int index;
  final IconImage? image;
  final bool browserFallback;

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
      null when widget.browserFallback => KeyedSubtree(
        key: const ValueKey('browser'),
        child: webBrowserMark(size: 13, color: AppColors.textMuted),
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
  const _ResolvedWebBadge.search()
    : id = 'search',
      image = null,
      browserFallback = false;
  const _ResolvedWebBadge.browser()
    : id = 'browser',
      image = null,
      browserFallback = true;
  const _ResolvedWebBadge.site(
    String host,
    this.image, {
    bool fromBrowser = false,
  }) : id = 'site:$host',
       browserFallback = fromBrowser;

  final String id;
  final IconImage? image;
  final bool browserFallback;
}
