// How an issue or pull request is drawn wherever it shows (a stash's card
// of it, its detail, the conversations' sidebar): its forge's logo, and
// its state as the forge draws it, in an icon and a color.

import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/codicons.dart';
import '../theme/workbench_theme.dart' show themeColors;
import 'forge_api.dart';
import 'forge_ref.dart';

/// [kind]'s logo in a square of [size], in [color] (the icons' around it
/// when null).
class ForgeLogo extends StatelessWidget {
  const ForgeLogo(this.kind, {super.key, this.size = 16, this.color});

  static const gitlabAsset = 'assets/branding/gitlab.svg';
  static const giteeAsset = 'assets/branding/gitee.svg';

  final ForgeKind kind;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? IconTheme.of(context).color;
    Widget svg(String asset) => SizedBox.square(
      dimension: size,
      child: Center(
        child: SvgPicture.asset(
          asset,
          width: size * .875,
          colorFilter: color == null
              ? null
              : ColorFilter.mode(color, BlendMode.srcIn),
        ),
      ),
    );
    return switch (kind) {
      ForgeKind.github => Icon(Codicons.github, size: size, color: color),
      ForgeKind.gitlab => svg(gitlabAsset),
      ForgeKind.gitee => svg(giteeAsset),
    };
  }
}

/// An issue's or pull request's state as its forge draws it: open green,
/// done (closed issue, merged) purple, a pull request closed unmerged red,
/// a draft grey; unknown (not asked yet, or cannot be) as open, greyed.
(IconData, Color) forgeStateLook(ForgeItemKind kind, ForgeState? state) {
  final colors = themeColors;
  final grey = colors['descriptionForeground'];
  final green = colors['charts.green'];
  final purple = colors['charts.purple'];
  return switch ((kind, state)) {
    (ForgeItemKind.issue, ForgeState.closed || ForgeState.merged) => (
      Codicons.issueClosed,
      purple,
    ),
    (ForgeItemKind.issue, null) => (Codicons.issues, grey),
    (ForgeItemKind.issue, _) => (Codicons.issues, green),
    (ForgeItemKind.pull, ForgeState.open) => (Codicons.gitPullRequest, green),
    (ForgeItemKind.pull, ForgeState.draft) => (
      Codicons.gitPullRequestDraft,
      grey,
    ),
    (ForgeItemKind.pull, ForgeState.merged) => (Codicons.gitMerge, purple),
    (ForgeItemKind.pull, ForgeState.closed) => (
      Codicons.gitPullRequestClosed,
      colors['charts.red'],
    ),
    (ForgeItemKind.pull, null) => (Codicons.gitPullRequest, grey),
  };
}

/// [forgeStateLook]'s icon, [size] square.
class ForgeStateIcon extends StatelessWidget {
  const ForgeStateIcon(this.kind, this.state, {super.key, this.size = 14});

  final ForgeItemKind kind;
  final ForgeState? state;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = forgeStateLook(kind, state);
    return Icon(icon, size: size, color: color);
  }
}

/// A pull request's checks: passed, failed, running.
class ForgeChecksIcon extends StatelessWidget {
  const ForgeChecksIcon(this.checks, {super.key, this.size = 14});

  final ForgeChecks checks;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    final (icon, color) = switch (checks) {
      ForgeChecks.success => (Codicons.check, colors['charts.green']),
      ForgeChecks.failure => (Codicons.close, colors['charts.red']),
      ForgeChecks.pending => (Codicons.circleFilled, colors['charts.yellow']),
    };
    return Icon(
      icon,
      size: checks == ForgeChecks.pending ? size * .6 : size,
      color: color,
    );
  }
}

/// A label's color as its forge has it (`#rrggbb` or `rrggbb`); null when
/// it says none.
Color? forgeLabelColor(String? hex) {
  final digits = hex?.replaceFirst('#', '');
  if (digits == null || digits.length != 6) return null;
  final value = int.tryParse(digits, radix: 16);
  return value == null ? null : Color(0xff000000 | value);
}
