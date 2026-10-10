import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../ide/ide_hover.dart';
import '../../l10n/l10n.dart';
import '../../network/network_proxy.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import 'settings_widgets.dart';

/// Where a site's test is.
sealed class SiteResult {
  const SiteResult();
}

class SiteTesting extends SiteResult {
  const SiteTesting();
}

class SiteReached extends SiteResult {
  const SiteReached(this.time);
  final Duration time;
}

class SiteUnreached extends SiteResult {
  const SiteUnreached(this.failure);
  final ProbeFailure failure;
}

/// A site of the connection test, as a row of the card: its logo, name
/// and host at the left; at the right, a spinner while it is tested, then
/// how long it took, or why it was not reached.
class NetworkTestRow extends StatelessWidget {
  const NetworkTestRow({super.key, required this.site, this.result});

  final TestSite site;

  /// None before it is tested.
  final SiteResult? result;

  /// The name's column, so that the hosts line up row under row.
  static const nameWidth = 88.0;

  static String failureName(BuildContext context, ProbeFailureKind kind) {
    final l10n = context.l10n;
    return switch (kind) {
      ProbeFailureKind.timeout => l10n.networkFailureTimeout,
      ProbeFailureKind.refused => l10n.networkFailureRefused,
      ProbeFailureKind.reset => l10n.networkFailureReset,
      ProbeFailureKind.dns => l10n.networkFailureDns,
      ProbeFailureKind.tls => l10n.networkFailureTls,
      ProbeFailureKind.proxyAuth => l10n.networkFailureProxyAuth,
      ProbeFailureKind.other => l10n.networkFailureOther,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final result = this.result;
    final error = themeColors['errorForeground'];
    // Figures of one width: the times line up row under row.
    final style = TextStyle(
      color: SettingsColors.textPrimary,
      fontSize: 12.5,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final String said;
    final Widget end;
    switch (result) {
      case null:
        said = l10n.networkTestIdle;
        end = Text(
          '—',
          style: style.copyWith(color: SettingsColors.textQuaternary),
        );
      case SiteTesting():
        said = l10n.networkTesting;
        end = SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: SettingsColors.textSecondary,
          ),
        );
      case SiteReached(:final time):
        said = l10n.networkTestMs(time.inMilliseconds);
        end = Text(said, style: style);
      case SiteUnreached(:final failure):
        said =
            '${l10n.networkTestUnreachable} · '
            '${failureName(context, failure.kind)}';
        end = Text(said, style: style.copyWith(color: error));
    }
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        children: [
          SvgPicture.asset(
            site.icon,
            width: 16,
            height: 16,
            colorFilter: ColorFilter.mode(
              SettingsColors.textSecondary,
              BlendMode.srcIn,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                // The hosts in a column of their own.
                SizedBox(
                  width: nameWidth,
                  child: Text(
                    site.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SettingsText.label,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    site.url.host,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SettingsText.description.copyWith(
                      color: SettingsColors.textQuaternary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // At the row's end, level with the Run Test button's edge; one
          // height for the spinner and the text, so a row does not move.
          SizedBox(
            height: 18,
            child: Align(alignment: AlignmentDirectional.centerEnd, child: end),
          ),
        ],
      ),
    );
    final detail = switch (result) {
      SiteUnreached(:final failure) when failure.detail.isNotEmpty =>
        failure.detail,
      _ => null,
    };
    final semantics = Semantics(
      container: true,
      label: '${site.name}, $said',
      excludeSemantics: true,
      child: row,
    );
    if (detail == null) return semantics;
    // As a list row's: below it, from the pointer.
    return IdeHover(message: detail, followMouse: true, child: semantics);
  }
}
