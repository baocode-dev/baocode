import 'package:flutter/material.dart';

import '../../chat/chat_width.dart';
import '../../chat/widgets/scroll_edge_fade.dart';
import '../../theme/app_theme.dart';
import '../../theme/workbench_theme.dart' show themeColors;

/// The settings pages' colors, as Cursor's settings have them: the editor's
/// foreground at a strength for each part, over the editor's background
/// (the page). Its `--cursor-text-*`, `--cursor-icon-*`, `--cursor-bg-*`
/// and `--cursor-stroke-*` (workbench.desktop.main.css); stronger text and
/// the inputs' border for the lines in high contrast themes.
abstract final class SettingsColors {
  static Color get _foreground => themeColors['editor.foreground'];

  static Color _at(double strength) =>
      _foreground.withValues(alpha: _foreground.a * strength);

  /// Titles, labels: the foreground.
  static Color get textPrimary => _foreground;

  /// Descriptions, group headings.
  static Color get textSecondary => _at(themeColors.highContrast ? 0.84 : 0.74);

  /// A group's description.
  static Color get textTertiary => _at(themeColors.highContrast ? 0.72 : 0.6);

  /// What is faint: a host by its name, a dash for no result yet.
  static Color get textQuaternary => _at(themeColors.highContrast ? 0.6 : 0.36);

  /// An icon not selected.
  static Color get iconTertiary => _at(0.52);

  /// What is selected or under the pointer in a list.
  static Color get hover => _at(0.06);

  /// Around a field.
  static Color get stroke =>
      themeColors.highContrast ? themeColors['input.border'] : _at(0.08);

  /// A card, over the page.
  static Color get card => Color.alphaBlend(_at(0.04), AppColors.code);

  /// Between a card's rows.
  static Color get divider =>
      themeColors.highContrast ? themeColors['input.border'] : _at(0.04);
}

/// The settings pages' text: one size and weight for each part.
abstract final class SettingsText {
  static TextStyle get title => TextStyle(
    color: SettingsColors.textPrimary,
    fontSize: 18,
    fontWeight: FontWeight.w600,
  );

  /// Under the page's title.
  static TextStyle get lead => description;

  /// A group's heading, over its card.
  static TextStyle get heading => TextStyle(
    color: SettingsColors.textSecondary,
    fontSize: 12.5,
    fontWeight: FontWeight.w500,
  );

  /// Under a group's heading.
  static TextStyle get headingDescription =>
      description.copyWith(color: SettingsColors.textTertiary);

  static TextStyle get label =>
      TextStyle(color: SettingsColors.textPrimary, fontSize: 13, height: 1.4);

  static TextStyle get description =>
      TextStyle(color: SettingsColors.textSecondary, fontSize: 12, height: 1.5);

  static TextStyle get path => TextStyle(
    color: SettingsColors.textPrimary,
    fontSize: 12,
    height: 1.5,
    fontFamily: AppFonts.mono,
    fontFamilyFallback: AppFonts.monoFallbacks,
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

  final String title;
  final String? description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SettingsColumn(
    children: [
      // Its title and description in as far as the groups' headings.
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: SettingsText.title),
            if (description case final description?) ...[
              const SizedBox(height: 4),
              Text(description, style: SettingsText.lead),
            ],
          ],
        ),
      ),
      for (final child in children) ...[const SizedBox(height: 20), child],
    ],
  );
}

/// A page's scrolling column, as wide at most as the conversation's
/// ([ChatWidth]), in the middle of what is left of the window.
class SettingsColumn extends StatelessWidget {
  const SettingsColumn({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
    valueListenable: ChatWidth.current,
    builder: (context, maxWidth, _) => LayoutBuilder(
      builder: (context, constraints) {
        final side = maxWidth.isInfinite
            ? SettingsPage.inset
            : ((constraints.maxWidth - maxWidth) / 2).clamp(
                SettingsPage.inset,
                double.infinity,
              );
        // Fading out towards an edge it is scrolled past, over about two
        // lines of a description.
        return ScrollEdgeFade(
          fadeLength: 56,
          child: ListView(
            // Under the window's draggable strip already: the title near the
            // nav's back button.
            padding: EdgeInsets.fromLTRB(side, 16, side, 48),
            children: children,
          ),
        );
      },
    ),
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
    // 28 between groups, as Cursor's sections.
    padding: const EdgeInsets.only(top: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 4, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: SettingsText.heading),
              if (description case final description?) ...[
                const SizedBox(height: 2),
                Text(description, style: SettingsText.headingDescription),
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
  static Color get background => SettingsColors.card;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(12),
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
              color: SettingsColors.divider,
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
          const SizedBox(height: 1),
          Text(description, style: SettingsText.description),
        ],
        for (final widget in below) ...[const SizedBox(height: 8), widget],
      ],
    );
    final trailing = this.trailing;
    final row = Padding(
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
                        const SizedBox(height: 12),
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: trailing,
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: text),
                        const SizedBox(width: 20),
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

/// A setting that is on or off, as a row's control: a switch, in the
/// theme's button colors when on.
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

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    // On: `button.background` under a `button.foreground` knob. Off: a faint
    // track under a knob in the descriptions' color.
    final track = value
        ? colors['button.background']
        : AppColors.textFaint.withValues(alpha: 0.45);
    final knob = value
        ? colors['button.foreground']
        : SettingsColors.textSecondary;
    // As tall as its label's letters, with the interface's font size.
    final height = MediaQuery.textScalerOf(
      context,
    ).scale(SettingsText.label.fontSize! * 1.2).roundToDouble();
    final knobSize = height - 4;
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
              width: (height * 1.75).roundToDouble(),
              height: height,
              padding: const EdgeInsets.all(2),
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              decoration: BoxDecoration(
                color: track,
                borderRadius: BorderRadius.circular(height / 2),
              ),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOut,
                width: knobSize,
                height: knobSize,
                decoration: BoxDecoration(
                  color: knob,
                  shape: BoxShape.circle,
                  boxShadow: const [
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

/// One of [count] steps, as a row's control: a slider that stops at each,
/// [label] (the step's name) beside it.
class SettingsSlider extends StatelessWidget {
  const SettingsSlider({
    super.key,
    required this.step,
    required this.count,
    required this.label,
    required this.semanticLabel,
    required this.onChanged,
    this.tapOnly = false,
  });

  final int step;
  final int count;
  final String label;
  final String semanticLabel;
  final ValueChanged<int> onChanged;

  /// A step is picked by a click, not by dragging the thumb: for one whose
  /// every step relayouts the window, which a drag would do on each.
  final bool tapOnly;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accent;
    // One semantics node per slider: several in a card otherwise fail the
    // engine's semantics check.
    return MergeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: SettingsText.description),
          const SizedBox(width: 8),
          SizedBox(
            width: 180,
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                activeTrackColor: accent,
                inactiveTrackColor: AppColors.textFaint.withValues(alpha: 0.35),
                activeTickMarkColor: Colors.white.withValues(alpha: 0.7),
                inactiveTickMarkColor: AppColors.textMuted,
                thumbColor: Colors.white,
                overlayColor: accent.withValues(alpha: 0.12),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                tickMarkShape: const RoundSliderTickMarkShape(
                  tickMarkRadius: 1.5,
                ),
                showValueIndicator: ShowValueIndicator.never,
              ),
              child: Slider(
                value: step.toDouble(),
                max: (count - 1).toDouble(),
                divisions: count - 1,
                allowedInteraction: tapOnly ? SliderInteraction.tapOnly : null,
                semanticFormatterCallback: (_) => semanticLabel,
                onChanged: (value) {
                  final picked = value.round();
                  if (picked != step) onChanged(picked);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A line of text, as a row's control: [value] as it is kept, and what is
/// typed goes to [onSubmitted] once it is entered or the field loses focus,
/// when that changed it. [hint] shows where it is empty.
class SettingsTextField extends StatefulWidget {
  const SettingsTextField({
    super.key,
    required this.value,
    required this.semanticLabel,
    required this.onSubmitted,
    this.hint,
    this.width = 220,
  });

  final String value;
  final String semanticLabel;
  final ValueChanged<String> onSubmitted;
  final String? hint;
  final double width;

  @override
  State<SettingsTextField> createState() => _SettingsTextFieldState();
}

class _SettingsTextFieldState extends State<SettingsTextField> {
  late final _controller = TextEditingController(text: widget.value);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
  }

  @override
  void didUpdateWidget(SettingsTextField old) {
    super.didUpdateWidget(old);
    // Shows the kept value when it changes elsewhere, never over a typing.
    if (!_focus.hasFocus && _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_focusChanged);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _focusChanged() {
    if (!_focus.hasFocus) _submit(_controller.text);
  }

  void _submit(String text) {
    final typed = text.trim();
    if (typed == widget.value) return;
    widget.onSubmitted(typed);
  }

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(5),
      borderSide: BorderSide(color: AppColors.borderStrong),
    );
    final mono = TextStyle(
      fontFamily: AppFonts.mono,
      fontFamilyFallback: AppFonts.monoFallbacks,
      fontSize: 12,
    );
    return Semantics(
      textField: true,
      label: widget.semanticLabel,
      child: SizedBox(
        width: widget.width,
        child: TextField(
          controller: _controller,
          focusNode: _focus,
          onSubmitted: _submit,
          style: mono.copyWith(color: AppColors.text),
          decoration: InputDecoration(
            isDense: true,
            hintText: widget.hint,
            hintStyle: mono.copyWith(color: AppColors.textFaint),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 6,
            ),
            border: border,
            enabledBorder: border,
            focusedBorder: border.copyWith(
              borderSide: BorderSide(color: AppColors.accent),
            ),
          ),
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
