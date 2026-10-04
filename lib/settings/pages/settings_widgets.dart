import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/workbench_theme.dart' show themeColors;

/// The settings pages' text: one size and weight for each part.
abstract final class SettingsText {
  static TextStyle get title => TextStyle(
    color: AppColors.textPrimary,
    fontSize: 18,
    fontWeight: FontWeight.w600,
  );

  /// A group's heading, over its card.
  static TextStyle get heading => TextStyle(
    color: AppColors.textMuted,
    fontSize: 12.5,
    fontWeight: FontWeight.w500,
  );

  static TextStyle get label =>
      TextStyle(color: AppColors.textPrimary, fontSize: 13, height: 1.4);

  static TextStyle get description =>
      TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.5);

  static TextStyle get path => TextStyle(
    color: AppColors.text,
    fontSize: 12,
    height: 1.5,
    fontFamily: AppFonts.mono,
  );
}

/// A settings page: its title, a description under it, then its cards
/// (and [SettingsGroup]s), in a column as wide as reads well.
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.title,
    this.description,
    required this.children,
  });

  static const inset = 32.0;

  /// The column's width at most.
  static const maxWidth = 720.0;

  final String title;
  final String? description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SettingsColumn(
    children: [
      Text(title, style: SettingsText.title),
      if (description case final description?) ...[
        const SizedBox(height: 4),
        Text(description, style: SettingsText.description),
      ],
      for (final child in children) ...[const SizedBox(height: 16), child],
    ],
  );
}

/// A page's scrolling column, [SettingsPage.maxWidth] wide at most, in
/// the middle of what is left of the window.
class SettingsColumn extends StatelessWidget {
  const SettingsColumn({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final side = ((constraints.maxWidth - SettingsPage.maxWidth) / 2).clamp(
        SettingsPage.inset,
        double.infinity,
      );
      return ListView(
        padding: EdgeInsets.fromLTRB(side, 40, side, 40),
        children: children,
      );
    },
  );
}

/// Settings under a heading: the heading over their card, as a page's
/// part (Startup, Notifications…).
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    super.key,
    required this.title,
    required this.children,
    this.description,
  });

  final String title;
  final String? description;

  /// Its rows, in one card.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: SettingsText.heading),
              if (description case final description?) ...[
                const SizedBox(height: 2),
                Text(description, style: SettingsText.description),
              ],
            ],
          ),
        ),
        SettingsCard(children: children),
      ],
    ),
  );
}

/// Settings that belong together: a card a shade off the page, a line
/// between rows (bordered in high contrast themes).
class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.children});

  final List<Widget> children;

  /// The card: the text's color over the page's, faintly.
  static Color get background => Color.alphaBlend(
    AppColors.textPrimary.withValues(alpha: 0.04),
    AppColors.code,
  );

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(10),
      border: switch (themeColors.get('contrastBorder')) {
        final border? => Border.all(color: border),
        null => null,
      },
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, child) in children.indexed) ...[
          if (i > 0)
            Container(
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: 12),
              color: AppColors.border,
            ),
          child,
        ],
      ],
    ),
  );
}

/// One setting: its label and description at the left, its control at
/// the right; [below] under the description. Narrower than [stackBelow],
/// the control goes under them.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.label,
    this.description,
    this.below = const [],
    this.trailing,
    this.onTap,
  });

  final String label;
  final String? description;
  final List<Widget> below;
  final Widget? trailing;

  /// What a click anywhere on the row does: a switch's row toggles it.
  final VoidCallback? onTap;

  static const stackBelow = 480.0;

  @override
  Widget build(BuildContext context) {
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: SettingsText.label),
        if (description case final description?) ...[
          const SizedBox(height: 2),
          Text(description, style: SettingsText.description),
        ],
        for (final widget in below) ...[const SizedBox(height: 4), widget],
      ],
    );
    final trailing = this.trailing;
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: trailing == null
          ? text
          : LayoutBuilder(
              builder: (context, constraints) =>
                  constraints.maxWidth < stackBelow
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        text,
                        const SizedBox(height: 10),
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: trailing,
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: text),
                        const SizedBox(width: 16),
                        trailing,
                      ],
                    ),
            ),
    );
    final onTap = this.onTap;
    if (onTap == null) return row;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: row,
      ),
    );
  }
}

/// A setting that is on or off, as a row's control: a switch, green when
/// on.
class SettingsSwitch extends StatelessWidget {
  const SettingsSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
    this.enabled = true,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String semanticLabel;
  final bool enabled;

  /// On: green, whatever the theme, as the system's switches.
  static const onColor = Color(0xFF3DA35D);

  @override
  Widget build(BuildContext context) {
    final off = AppColors.textFaint.withValues(alpha: 0.45);
    return Semantics(
      toggled: value,
      enabled: enabled,
      label: semanticLabel,
      excludeSemantics: true,
      onTap: enabled ? () => onChanged(!value) : null,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        child: GestureDetector(
          onTap: enabled ? () => onChanged(!value) : null,
          child: Opacity(
            opacity: enabled ? 1 : 0.5,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOut,
              width: 34,
              height: 20,
              padding: const EdgeInsets.all(2),
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              decoration: BoxDecoration(
                color: value ? onColor : off,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Container(
                width: 16,
                height: 16,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: Color(0x33000000), blurRadius: 2),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A [SettingsRow] with a [SettingsSwitch]: a click on the row toggles it.
class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.description,
    this.enabled = true,
  });

  final String label;
  final String? description;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: enabled ? 1 : 0.6,
    child: SettingsRow(
      label: label,
      description: description,
      onTap: enabled ? () => onChanged(!value) : null,
      trailing: SettingsSwitch(
        value: value,
        enabled: enabled,
        semanticLabel: label,
        onChanged: onChanged,
      ),
    ),
  );
}

/// Buttons side by side, as a row's control.
class SettingsButtons extends StatelessWidget {
  const SettingsButtons({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final (i, child) in children.indexed) ...[
        if (i > 0) const SizedBox(width: 6),
        child,
      ],
    ],
  );
}
