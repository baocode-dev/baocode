import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// The settings pages' text: one size and weight for each part.
abstract final class SettingsText {
  static TextStyle get title => TextStyle(
    color: AppColors.textPrimary,
    fontSize: 15,
    fontWeight: FontWeight.w600,
  );

  static TextStyle get label => TextStyle(
    color: AppColors.textPrimary,
    fontSize: 13,
    fontWeight: FontWeight.w500,
  );

  static TextStyle get description =>
      TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.5);

  static TextStyle get path => TextStyle(
    color: AppColors.text,
    fontSize: 12,
    height: 1.5,
    fontFamily: AppFonts.mono,
  );
}

/// A settings page: its title, a description under it, then its cards.
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.title,
    this.description,
    required this.children,
  });

  static const inset = 24.0;

  final String title;
  final String? description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(inset, 20, inset, inset),
    children: [
      // Room at the right for the dialog's close button.
      Padding(
        padding: const EdgeInsets.only(right: 24),
        child: Text(title, style: SettingsText.title),
      ),
      if (description case final description?) ...[
        const SizedBox(height: 4),
        Text(description, style: SettingsText.description),
      ],
      for (final child in children) ...[const SizedBox(height: 16), child],
    ],
  );
}

/// Settings that belong together: a bordered card, a line between rows.
class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, child) in children.indexed) ...[
          if (i > 0) Container(height: 1, color: AppColors.border),
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
  });

  final String label;
  final String? description;
  final List<Widget> below;
  final Widget? trailing;

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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
  }
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
