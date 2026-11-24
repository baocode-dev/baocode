import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../icons/brand_logos.dart';
import '../icons/icon_library.dart';
import '../icons/project_icon.dart';
import '../icons/project_icon_view.dart';
import '../icons/site_icons.dart';
import '../theme/codicons.dart';
import 'featured_upstreams.dart';
import 'model_brand.dart';
import 'model_provider.dart';
import 'model_providers.dart';
import 'upstream.dart';

/// Claude Code's own models' heading's logo: Anthropic's.
const builtinProviderLogo = 'anthropic';

/// Claude's logo, Claude Code's own models' (and Claude's elsewhere).
const claudeLogo = 'claude';

/// The icon [provider] shows: the one picked for it, else its maker's
/// logo; null when it has neither (its site's icon shows then).
ProjectIcon? providerIconOf(ModelProvider provider) =>
    provider.icon ??
    switch (ModelBrand.ofProvider(provider)) {
      final brand? => BrandIcon(brand),
      null => null,
    };

/// The site [provider] is of, whose icon it shows without another:
/// ChatGPT's for Codex, Antigravity's for it (the legacy one and the ACP
/// one alike), else its base URL's.
Uri? providerSite(ModelProvider provider) => switch (provider.protocol) {
  ProviderProtocol.codex => Uri.https('chatgpt.com'),
  ProviderProtocol.antigravity ||
  ProviderProtocol.agy => Uri.https('antigravity.google'),
  _ => UpstreamUrls.parse(provider.baseUrl),
};

/// The logo bundled for [site], in its colors, if there is one: Antigravity's
/// (the ACP and the legacy upstream alike). Null otherwise.
String? bundledSiteLogo(Uri? site) => site?.host == 'antigravity.google'
    ? 'assets/provider_logos/antigravity.png'
    : null;

/// Fetches, in the background, the icons of [providers]' sites that show
/// no other: now, and as one is added or its base URL changes, so that
/// each is there by the time it shows.
void prefetchProviderIcons(ModelProviders providers, SiteIcons icons) {
  void fetch() {
    for (final provider in providers.providers) {
      if (providerIconOf(provider) != null) continue;
      if (providerSite(provider) case final site?) icons.request(site);
    }
  }

  providers.addListener(fetch);
  fetch();
}

/// Provider [id]'s icon (of [ModelProviders.current], as it is now) in a
/// square of [size]: see [ProviderIconView].
class ProviderIcon extends StatelessWidget {
  const ProviderIcon(this.id, {super.key, required this.size, this.color});

  /// Claude Code's own ([builtinProviderId]), or an upstream's.
  final String id;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (id == builtinProviderId) {
      return BrandLogo(builtinProviderLogo, size: size, color: color);
    }
    final providers = ModelProviders.current;
    return ListenableBuilder(
      listenable: providers,
      builder: (context, _) {
        final provider = providers.provider(id);
        return ProviderIconView(
          icon: provider == null ? null : providerIconOf(provider),
          site: provider == null ? null : providerSite(provider),
          size: size,
          color: color,
        );
      },
    );
  }
}

/// [icon] as an upstream shows it, in a square of [size]: a glyph or a
/// logo as large as a glyph of it, a picture a little larger. Without one,
/// the logo BaoCode lists [site] with ([FeaturedUpstream.known]); else
/// [site]'s icon ([SiteIcons]); without that, a globe.
class ProviderIconView extends StatelessWidget {
  const ProviderIconView({
    super.key,
    required this.icon,
    required this.size,
    this.site,
    this.color,
  });

  final ProjectIcon? icon;
  final Uri? site;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => switch (icon) {
    // Its own maker's logo, unless an icon is picked for it.
    null when bundledSiteLogo(site) != null => _spilling(
      Image.asset(bundledSiteLogo(site)!, width: size + 2, height: size + 2),
    ),
    null => ListenableBuilder(
      listenable: Listenable.merge([SiteIcons.current, FeaturedUpstream.known]),
      builder: (context, _) {
        final fetched = switch (switch (site) {
          final site? => SiteIcons.current.of(site),
          null => null,
        }) {
          final image? => _spilling(IconImageView(image, size: size + 2)),
          null => Icon(Codicons.globe, size: size, color: color),
        };
        // A site BaoCode lists: the logo it is listed with.
        final logo = switch (site) {
          final site? => FeaturedUpstream.knownAt(site.host)?.logo,
          null => null,
        };
        if (logo == null) return fetched;
        final file = File(logo);
        final side = size + 2;
        return _spilling(
          ClipRRect(
            borderRadius: BorderRadius.circular(side / 5),
            child: logo.toLowerCase().endsWith('.svg')
                ? SvgPicture.file(
                    file,
                    width: side,
                    height: side,
                    errorBuilder: (_, _, _) => fetched,
                  )
                : Image.file(
                    file,
                    width: side,
                    height: side,
                    errorBuilder: (_, _, _) => fetched,
                  ),
          ),
        );
      },
    ),
    BrandIcon(:final name) => BrandLogo(name, size: size, color: color),
    final icon => ListenableBuilder(
      listenable: IconLibrary.current,
      builder: (context, _) => _spilling(
        ProjectIconView(
          icon: icon,
          library: IconLibrary.current,
          size: size + 3,
          color: color,
          fallback: Codicons.globe,
        ),
      ),
    ),
  };

  /// [child], a picture: in the room of a glyph of [size], spilling over
  /// it a little, as large as the glyph looks.
  Widget _spilling(Widget child) => SizedBox.square(
    dimension: size,
    child: OverflowBox(maxWidth: size + 3, maxHeight: size + 3, child: child),
  );
}

/// Model [model]'s icon: its maker's logo, as its name says; else its
/// upstream's ([provider], [builtinProviderId] for Claude Code's own).
class ModelIcon extends StatelessWidget {
  const ModelIcon({
    super.key,
    required this.provider,
    required this.model,
    required this.size,
    this.color,
  });

  final String provider;
  final String model;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => switch (provider == builtinProviderId
      ? claudeLogo
      : ModelBrand.ofModel(model)) {
    final brand? => BrandLogo(brand, size: size, color: color),
    null => ProviderIcon(provider, size: size, color: color),
  };
}
