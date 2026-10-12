import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../chat/widgets/hover_builder.dart';
import '../../chat/widgets/scroll_edge_fade.dart';
import '../../ide/ide_button.dart';
import '../../ide/ide_hover.dart';
import '../../l10n/l10n.dart';
import '../../models/featured_upstreams.dart';
import '../../theme/codicons.dart';
import '../../theme/ui_tokens.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../../workspace/editor_launcher.dart' show openExternal;
import 'settings_widgets.dart';

/// Settings → Models' row of upstreams that added the one-click import
/// ([FeaturedUpstream]): a card of each, in an order of chance each time it
/// shows, scrolled sideways and faded out at an edge with more past it.
/// A card's hover has the site in full; "Why am I seeing this?" under
/// them, a click on it, how a site gets listed too ([_Why]).
///
/// A user with an upstream at a listed site's [hosts] (one imported from
/// it, say) sees that site's card first, held there while the rest scroll
/// by. One site only: that of the newest such upstream, one imported later
/// taking the place of one before.
///
/// Nothing at all, not the space above it either, until the list is got,
/// nor where none could be. What shows at once is the list kept last time;
/// the new one, as baocode.dev answers (see [FeaturedUpstream.load]).
class FeaturedUpstreamsStrip extends StatefulWidget {
  const FeaturedUpstreamsStrip({
    super.key,
    this.upstreams,
    this.follow,
    this.hosts = const [],
    this.random,
    this.open = _openUrl,
  });

  /// Those listed; the app's ([FeaturedUpstream.load]) when null.
  final Future<List<FeaturedUpstream>>? upstreams;

  /// Whether the list got again behind [upstreams] shows as it answers
  /// ([FeaturedUpstream.known]): where [upstreams] is the app's. So when
  /// null, where [upstreams] is null too.
  final bool? follow;

  /// The hosts of the user's upstreams, the oldest first.
  final Iterable<String> hosts;

  /// What their order is drawn with.
  final Random? random;

  /// Opens a card's link.
  final void Function(Uri url) open;

  static void _openUrl(Uri url) => unawaited(openExternal('$url'));

  /// How tall a card is.
  static const cardHeight = 52.0;
  static const cardWidth = 196.0;

  /// The page for a site to be listed (site/upstreams.html).
  static Uri joinUrl(String languageCode) => Uri.https(
    'baocode.dev',
    languageCode == 'zh' ? '/zh/upstreams' : '/upstreams',
  );

  @override
  State<FeaturedUpstreamsStrip> createState() => _FeaturedUpstreamsStripState();
}

class _FeaturedUpstreamsStripState extends State<FeaturedUpstreamsStrip> {
  final ScrollController _scroll = ScrollController();
  List<FeaturedUpstream> _upstreams = const [];

  bool get _follows => widget.follow ?? widget.upstreams == null;

  @override
  void initState() {
    super.initState();
    // Before the list is got: the new one may answer first.
    if (_follows) FeaturedUpstream.known.addListener(_refresh);
    unawaited(_load());
  }

  Future<void> _load() async {
    final listed = await (widget.upstreams ?? FeaturedUpstream.load());
    // Not where the new list showed before it.
    if (mounted && _upstreams.isEmpty) {
      setState(() => _upstreams = [...listed]..shuffle(widget.random));
    }
  }

  /// The list [FeaturedUpstream.load] got again, once it answers: those
  /// shown keep their places, those new drawn into theirs, those gone
  /// taken out. An empty one leaves them as they are.
  void _refresh() {
    final listed = FeaturedUpstream.known.value;
    if (listed.isEmpty || !mounted) return;
    final byId = {for (final upstream in listed) upstream.id: upstream};
    final kept = [for (final upstream in _upstreams) ?byId.remove(upstream.id)];
    final random = widget.random ?? Random();
    for (final upstream in byId.values) {
      kept.insert(random.nextInt(kept.length + 1), upstream);
    }
    setState(() => _upstreams = kept);
  }

  @override
  void dispose() {
    if (_follows) FeaturedUpstream.known.removeListener(_refresh);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Nothing until the list is got, nor where none could be.
    if (_upstreams.isEmpty) return const SizedBox.shrink();
    final language = Localizations.localeOf(context).languageCode;
    // One leads, of the newest of their upstreams at a listed site.
    final theirs = [
      for (final host in widget.hosts.toList().reversed)
        ?FeaturedUpstream.at(host, _upstreams),
    ].take(1).toList();
    final join = FeaturedUpstreamsStrip.joinUrl(language);
    _Card card(FeaturedUpstream upstream) {
      final about = upstream.describe(language);
      return _Card(
        key: ValueKey(upstream.id),
        logo: _Logo(upstream),
        title: upstream.name,
        subtitle: about ?? upstream.url.host,
        hover: [upstream.name, ?about, upstream.url.host].join('\n'),
        // The site in full: its name, the line about it, where a click goes.
        hoverContent: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Logo(upstream),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      upstream.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              if (about != null) ...[const SizedBox(height: 6), Text(about)],
              const SizedBox(height: 6),
              // Opens it, as the card does.
              Semantics(
                link: true,
                child: HoverBuilder(
                  cursor: SystemMouseCursors.click,
                  builder: (context, hovered) {
                    final link = themeColors['textLink.foreground'];
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => widget.open(upstream.url),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Codicons.linkExternal, size: 12, color: link),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              upstream.url.host,
                              style: TextStyle(
                                color: link,
                                decoration: hovered
                                    ? TextDecoration.underline
                                    : null,
                                decorationColor: link,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        onTap: () => widget.open(upstream.url),
      );
    }

    final cards = [
      for (final upstream in _upstreams)
        if (!theirs.contains(upstream)) card(upstream),
    ];
    final scrolled = SizedBox(
      height: FeaturedUpstreamsStrip.cardHeight,
      child: Row(
        children: [
          // Theirs stay put; the rest scroll by them.
          for (final upstream in theirs) ...[
            card(upstream),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: ScrollConfiguration(
              // Dragged with the mouse too: there may be no wheel
              // sideways.
              behavior: ScrollConfiguration.of(context).copyWith(
                scrollbars: false,
                dragDevices: PointerDeviceKind.values.toSet(),
              ),
              child: ScrollEdgeFade(
                axis: Axis.horizontal,
                fadeLength: 40,
                child: ListView.separated(
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  itemCount: cards.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, index) => cards[index],
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        scrolled,
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: _Why(onJoin: () => widget.open(join)),
        ),
      ],
    );
  }
}

/// "Why am I seeing this?", and a click on it, why: that these sites are
/// listed, how a site gets listed too, and a button to the page for it. A
/// click on it again, or anywhere else, closes that.
class _Why extends StatefulWidget {
  const _Why({required this.onJoin});

  final VoidCallback onJoin;

  @override
  State<_Why> createState() => _WhyState();
}

class _WhyState extends State<_Why> {
  final _popup = OverlayPortalController();
  final _link = LayerLink();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TapRegion(
      groupId: _popup,
      onTapOutside: (_) => _popup.hide(),
      child: CompositedTransformTarget(
        link: _link,
        child: OverlayPortal(
          controller: _popup,
          overlayChildBuilder: (context) => CompositedTransformFollower(
            link: _link,
            targetAnchor: Alignment.bottomLeft,
            offset: const Offset(0, 4),
            child: Align(
              alignment: Alignment.topLeft,
              child: TapRegion(
                groupId: _popup,
                child: IdeHoverBox(
                  compact: false,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.modelsFeaturedNote),
                      const SizedBox(height: 2),
                      Text(
                        l10n.modelsFeaturedNoteHow,
                        style: TextStyle(
                          color: themeColors['descriptionForeground'],
                        ),
                      ),
                      const SizedBox(height: 10),
                      IdeButton(
                        label: l10n.modelsFeaturedNoteLink,
                        onPressed: () {
                          _popup.hide();
                          widget.onJoin();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Lit as a whole while the pointer is on it.
          child: HoverBuilder(
            cursor: SystemMouseCursors.click,
            builder: (context, hovered) {
              final color = hovered
                  ? SettingsColors.textTertiary
                  : SettingsColors.textQuaternary;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _popup.toggle,
                child: Semantics(
                  button: true,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: hovered ? SettingsColors.hover : null,
                      borderRadius: BorderRadius.circular(UiRadius.medium),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Codicons.question, size: 11, color: color),
                        const SizedBox(width: 3),
                        Text(
                          l10n.modelsFeaturedWhy,
                          style: SettingsText.description.copyWith(
                            fontSize: UiText.caption,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// A card of the row: [logo], [title] over [subtitle]; a click opens what
/// it is of.
class _Card extends StatelessWidget {
  const _Card({
    super.key,
    required this.logo,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.hover,
    this.hoverContent,
  });

  final Widget logo;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// Where it goes, in a hover.
  final String? hover;

  /// Shown in the hover in place of [hover], which screen readers read.
  final Widget? hoverContent;

  @override
  Widget build(BuildContext context) {
    final card = HoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (context, hovered) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Semantics(
          button: true,
          link: true,
          label: '$title, $subtitle',
          excludeSemantics: true,
          child: Container(
            width: FeaturedUpstreamsStrip.cardWidth,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: hovered
                  ? Color.alphaBlend(SettingsColors.hover, SettingsColors.card)
                  : SettingsColors.card,
              borderRadius: BorderRadius.circular(UiRadius.large),
            ),
            child: Row(
              children: [
                SizedBox.square(dimension: 24, child: Center(child: logo)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SettingsText.label.copyWith(
                          fontSize: UiText.secondary,
                          height: 1.3,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SettingsText.description.copyWith(
                          fontSize: UiText.caption,
                          height: 1.35,
                          color: SettingsColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final hover = this.hover;
    return hover == null
        ? card
        : IdeHover(
            message: hover,
            content: hoverContent,
            interactive: hoverContent != null,
            child: card,
          );
  }
}

/// [upstream]'s logo, as it drew it; its name's first letter without one,
/// or while it cannot be read (not downloaded yet).
class _Logo extends StatelessWidget {
  const _Logo(this.upstream);

  final FeaturedUpstream upstream;

  @override
  Widget build(BuildContext context) {
    final letter = Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: SettingsColors.hover,
        borderRadius: BorderRadius.circular(UiRadius.medium),
      ),
      child: Text(
        upstream.name.characters.first.toUpperCase(),
        style: SettingsText.label.copyWith(
          fontSize: UiText.secondary,
          fontWeight: FontWeight.w600,
          color: SettingsColors.textSecondary,
        ),
      ),
    );
    final logo = upstream.logo;
    if (logo == null) return letter;
    final file = File(logo);
    return ClipRRect(
      borderRadius: BorderRadius.circular(UiRadius.medium),
      child: logo.toLowerCase().endsWith('.svg')
          ? SvgPicture.file(
              file,
              width: 22,
              height: 22,
              errorBuilder: (_, _, _) => letter,
            )
          : Image.file(
              file,
              width: 22,
              height: 22,
              errorBuilder: (_, _, _) => letter,
            ),
    );
  }
}
