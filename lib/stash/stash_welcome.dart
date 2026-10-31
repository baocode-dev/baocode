import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../base/step_clock.dart';
import '../chat/widgets/hover_builder.dart';
import '../icons/brand_logos.dart' show BaoCodeLogo;
import '../ide/ide_button.dart';
import '../l10n/l10n.dart';
import '../platform/app_platform.dart';
import '../settings/pages/stash_hotkey_field.dart' show StashHotkeyField;
import '../theme/app_theme.dart';
import '../theme/codicons.dart';
import '../theme/workbench_theme.dart' show themeColors;
import '../tips/welcome_dialog.dart';
import 'stash_controller.dart';
import 'stash_settings.dart';

/// What Stash is, the first time its page shows: a picture of stashes
/// coming in, three lines (note it down, hand it to an agent, see how it
/// goes), and the one thing to do: the shortcut that notes one down from
/// any app, recorded right there (the suggested one a click away).
Future<void> showStashWelcome(
  BuildContext context, {
  required StashController controller,
}) => showWelcomeDialog(
  context,
  builder: (context) => StashWelcome(controller: controller),
);

class StashWelcome extends StatefulWidget {
  const StashWelcome({super.key, required this.controller});

  /// Whose shortcut it sets (settings.json's `stash.hotkey`).
  final StashController controller;

  @override
  State<StashWelcome> createState() => _StashWelcomeState();
}

class _StashWelcomeState extends State<StashWelcome>
    with TickerProviderStateMixin {
  /// The picture's cards coming in, then the lines, one after another.
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..forward();

  /// The cards afloat once in.
  // On the shared clock's frames, not every vsync: it goes on for as
  // long as the page shows.
  final StepLoop _float = StepLoop(
    const Duration(milliseconds: 3600),
    reverse: true,
  );

  @override
  void initState() {
    super.initState();
    _intro.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        _float.start(context);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _float.keepTo(context);
  }

  @override
  void dispose() {
    _intro.dispose();
    _float.dispose();
    super.dispose();
  }

  Animation<double> _step(double from, double to, {Curve? curve}) =>
      CurvedAnimation(
        parent: _intro,
        curve: Interval(from, to, curve: curve ?? Curves.easeOutCubic),
      );

  /// The shortcut as just recorded, till settings.json says so.
  String? _recorded;

  String get _hotkey => _recorded ?? widget.controller.settings.hotkey;

  void _setHotkey(String spec) {
    setState(() => _recorded = spec);
    unawaited(
      widget.controller.updateSetting
          ?.call(StashSettings.hotkeyKey, spec.isEmpty ? null : spec)
          .catchError((Object error) {
            debugPrint('${StashSettings.hotkeyKey} not kept: $error');
          }),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    // The shortcut kept, and whether the system gave it.
    listenable: Listenable.merge([
      ?widget.controller.settingsChanges,
      widget.controller,
    ]),
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final l10n = context.l10n;
    final hotkey = _hotkey;
    final label = StashSettings.label(hotkey, mac: AppPlatform.isMacOS);
    final lines = [
      (
        const Icon(Codicons.edit, size: 15),
        l10n.stashWelcomeNoteTitle,
        l10n.stashWelcomeNoteBody,
      ),
      (
        const BaoCodeLogo(size: 15),
        l10n.stashWelcomeAgentTitle,
        l10n.stashWelcomeAgent,
      ),
      (
        const Icon(Codicons.pulse, size: 15),
        l10n.stashWelcomeTrackTitle,
        l10n.stashWelcomeTrack,
      ),
    ];
    return WelcomeFrame(
      picture: _Picture(
        cards: [
          _step(0, .45, curve: Curves.easeOutBack),
          _step(.08, .53, curve: Curves.easeOutBack),
          _step(.16, .61, curve: Curves.easeOutBack),
        ],
        extras: _step(.4, .75),
        float: _float,
        hotkey: label,
      ),
      body: [
        WelcomeRise(
          animation: _step(.3, .7),
          child: WelcomeHeading(
            title: l10n.stashWelcomeTitle,
            lead: l10n.stashWelcomeLead,
          ),
        ),
        const SizedBox(height: 10),
        for (final (i, (icon, title, text)) in lines.indexed)
          WelcomeRise(
            animation: _step(.42 + i * .1, .82 + i * .06),
            child: WelcomeLine(icon: icon, title: title, text: text),
          ),
        WelcomeRise(
          animation: _step(.62, .95),
          child: _HotkeyStep(
            hotkey: hotkey,
            label: label,
            taken: widget.controller.hotkeyTaken,
            onChanged: _setHotkey,
          ),
        ),
      ],
      footer: WelcomeRise(
        animation: _step(.7, 1),
        child: Row(
          children: [
            Expanded(
              child: hotkey.isEmpty
                  ? Text(
                      l10n.stashWelcomeHotkeyLater,
                      style: TextStyle(
                        color: AppColors.textFaint,
                        fontSize: 12,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(width: 12),
            IdeButton(
              label: l10n.stashWelcomeStart,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}

/// The shortcut that notes a stash down from any app: recorded in place,
/// the suggested one a click away while there is none; said whether the
/// system gave it.
class _HotkeyStep extends StatelessWidget {
  const _HotkeyStep({
    required this.hotkey,
    required this.label,
    required this.taken,
    required this.onChanged,
  });

  final String hotkey;
  final String label;

  /// Whether the system gave it; null before it was asked.
  final bool? taken;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final set = hotkey.isNotEmpty;
    final suggested = StashSettings.label(
      StashSettings.suggestedHotkey,
      mac: AppPlatform.isMacOS,
    );
    return WelcomeStep(
      done: set,
      icon: Codicons.keyboard,
      title: set
          ? l10n.stashWelcomeHotkeySetTitle
          : l10n.stashWelcomeHotkeyTitle,
      text: set ? l10n.stashWelcomeHotkeySet(label) : l10n.stashWelcomeHotkey,
      below: [
        if (set && taken == false) ...[
          const SizedBox(height: 4),
          Text(
            l10n.stashSettingsHotkeyTaken,
            style: TextStyle(color: AppColors.caution, fontSize: 12),
          ),
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            StashHotkeyField(
              hotkey: hotkey,
              onChanged: onChanged,
              semanticLabel: l10n.stashWelcomeHotkeyTitle,
            ),
            if (!set)
              _Link(
                l10n.stashHotkeySuggested(suggested),
                onTap: () => onChanged(StashSettings.suggestedHotkey),
              ),
          ],
        ),
      ],
    );
  }
}

class _Link extends StatelessWidget {
  const _Link(this.label, {required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => HoverBuilder(
    cursor: SystemMouseCursors.click,
    builder: (context, hovered) => GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: TextStyle(
          color: themeColors['textLink.foreground'],
          fontSize: 12.5,
          decoration: hovered ? TextDecoration.underline : null,
          decorationColor: themeColors['textLink.foreground'],
        ),
      ),
    ),
  );
}

// --- The picture ---------------------------------------------------------------

/// Three stashes coming in, fanned out, afloat: one with a picture, one
/// carried out in a conversation, one with its pull request merged; the
/// shortcut that notes one down, above them.
class _Picture extends StatelessWidget {
  const _Picture({
    required this.cards,
    required this.extras,
    required this.float,
    required this.hotkey,
  });

  final List<Animation<double>> cards;
  final Animation<double> extras;
  final Animation<double> float;
  final String hotkey;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([...cards, extras, float]),
    builder: (context, _) {
      final drift = math.sin(float.value * math.pi);
      return Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          _place(
            cards[0],
            dx: -112,
            dy: 14 - drift * 3,
            turn: -.075,
            child: const _MiniCard(tag: '#12', picture: true),
          ),
          _place(
            cards[1],
            dx: 112,
            dy: 18 + drift * 2,
            turn: .065,
            child: const _MiniCard(tag: '#18', pull: true),
          ),
          _place(
            cards[2],
            dx: 0,
            dy: 4 - drift * 4,
            turn: 0,
            child: const _MiniCard(tag: '#31', thread: true, front: true),
          ),
          // Set meanwhile: it pops in.
          Positioned(
            top: 18,
            right: 26,
            child: Opacity(
              opacity: extras.value.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, (1 - extras.value) * -8 + drift * 2),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 360),
                  transitionBuilder: (child, animation) => ScaleTransition(
                    scale: CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutBack,
                    ),
                    child: FadeTransition(opacity: animation, child: child),
                  ),
                  child: hotkey.isEmpty
                      ? const SizedBox.shrink()
                      : _Keycap(hotkey, key: ValueKey(hotkey)),
                ),
              ),
            ),
          ),
          Positioned(
            top: 26,
            left: 34,
            child: Opacity(
              opacity: extras.value.clamp(0.0, 1.0),
              child: Transform.rotate(
                angle: float.value * .6,
                child: Icon(
                  Codicons.sparkle,
                  size: 14,
                  color: AppColors.textMuted.withValues(alpha: .7),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );

  Widget _place(
    Animation<double> animation, {
    required double dx,
    required double dy,
    required double turn,
    required Widget child,
  }) {
    final t = animation.value;
    return Opacity(
      opacity: t.clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(dx * t, dy + (1 - t) * 46),
        child: Transform.rotate(angle: turn * t * math.pi, child: child),
      ),
    );
  }
}

/// A stash's card, small: its number, its lines, and what it shows.
class _MiniCard extends StatelessWidget {
  const _MiniCard({
    required this.tag,
    this.picture = false,
    this.thread = false,
    this.pull = false,
    this.front = false,
  });

  final String tag;
  final bool picture;
  final bool thread;
  final bool pull;
  final bool front;

  @override
  Widget build(BuildContext context) {
    final bar = AppColors.textMuted.withValues(alpha: .28);
    Widget line(double width, {double height = 6, Color? color}) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color ?? bar,
        borderRadius: BorderRadius.circular(3),
      ),
    );
    return Container(
      width: 150,
      height: 112,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: front ? AppColors.borderStrong : AppColors.border,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0x26000000),
            blurRadius: front ? 22 : 12,
            offset: Offset(0, front ? 10 : 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          line(front ? 92 : 78, height: 8, color: bar.withValues(alpha: .5)),
          const SizedBox(height: 9),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      line(double.infinity),
                      const SizedBox(height: 6),
                      line(picture ? 54 : 96),
                      if (thread) ...[const SizedBox(height: 9), _ThreadChip()],
                    ],
                  ),
                ),
                if (picture) ...[
                  const SizedBox(width: 8),
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(5),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          themeColors['charts.blue'].withValues(alpha: .55),
                          themeColors['charts.purple'].withValues(alpha: .4),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Row(
            children: [
              Text(
                tag,
                style: TextStyle(
                  color: AppColors.textFaint,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (pull) const _Pill(),
            ],
          ),
        ],
      ),
    );
  }
}

/// The conversation a stash is carried out in, as its card shows it.
class _ThreadChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: AppColors.border),
    ),
    child: Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: themeColors['charts.green'],
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Container(
            height: 5,
            decoration: BoxDecoration(
              color: AppColors.textMuted.withValues(alpha: .25),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ],
    ),
  );
}

/// A pull request merged, as a card's mark.
class _Pill extends StatelessWidget {
  const _Pill();

  @override
  Widget build(BuildContext context) {
    final color = themeColors['charts.purple'];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Codicons.gitMerge, size: 9, color: color),
          const SizedBox(width: 2),
          Text('#7', style: TextStyle(color: color, fontSize: 9.5)),
        ],
      ),
    );
  }
}

class _Keycap extends StatelessWidget {
  const _Keycap(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.surfaceRaised,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: AppColors.borderStrong),
      boxShadow: const [
        BoxShadow(
          color: Color(0x1F000000),
          blurRadius: 8,
          offset: Offset(0, 3),
        ),
      ],
    ),
    child: Text(
      label,
      style: TextStyle(
        color: AppColors.text,
        fontSize: 11.5,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}
