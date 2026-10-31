import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../base/step_clock.dart';
import '../ide/ide_button.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import '../theme/codicons.dart';
import '../theme/workbench_theme.dart' show themeColors;
import '../tips/welcome_dialog.dart';
import 'browser_bridge.dart';
import 'browser_steps.dart' show browserIcon;
import 'extension_store.dart';

/// What the agents do with the user's browser: once after the update that
/// brought it (to a user who has not connected one), and from its command
/// (Connect Your Browser…) any time. A picture of an agent clicking in a
/// shared tab as the side panel follows it, three lines (only the tabs
/// shared, watched as it goes, shown once), and the one thing to do: the
/// extension, which turns the step green as it connects.
Future<void> showBrowserWelcome(
  BuildContext context, {
  required VoidCallback openSettings,
  BrowserBridge? bridge,
}) => showWelcomeDialog(
  context,
  builder: (context) => BrowserWelcome(
    bridge: bridge ?? BrowserBridge.instance,
    openSettings: openSettings,
  ),
);

class BrowserWelcome extends StatefulWidget {
  const BrowserWelcome({
    super.key,
    required this.bridge,
    required this.openSettings,
  });

  /// Whose browsers connecting turn the step green.
  final BrowserBridge bridge;

  /// Settings → Browser, the dialog closed.
  final VoidCallback openSettings;

  @override
  State<BrowserWelcome> createState() => _BrowserWelcomeState();
}

class _BrowserWelcomeState extends State<BrowserWelcome>
    with TickerProviderStateMixin {
  /// The window coming in, then the lines, one after another.
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..forward();

  /// The agent's pointer going to the button and clicking it, over again.
  // On the shared clock's frames, not every vsync: it goes on for as
  // long as the page shows.
  final StepLoop _pointer = StepLoop(const Duration(milliseconds: 3600));

  @override
  void initState() {
    super.initState();
    _intro.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        _pointer.start(context);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pointer.keepTo(context);
  }

  @override
  void dispose() {
    _intro.dispose();
    _pointer.dispose();
    super.dispose();
  }

  Animation<double> _step(double from, double to, {Curve? curve}) =>
      CurvedAnimation(
        parent: _intro,
        curve: Interval(from, to, curve: curve ?? Curves.easeOutCubic),
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.bridge,
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final l10n = context.l10n;
    final bridge = widget.bridge;
    final connected = bridge.browsers.firstOrNull;
    final lines = [
      (
        const Icon(Codicons.lock, size: 15),
        l10n.browserWelcomeSharedTitle,
        l10n.browserWelcomeShared,
      ),
      (
        const Icon(Codicons.eye, size: 15),
        l10n.browserWelcomeWatchTitle,
        l10n.browserWelcomeWatch,
      ),
      (
        const Icon(Codicons.record, size: 15),
        l10n.browserWelcomeShowTitle,
        l10n.browserWelcomeShow,
      ),
    ];
    final String title;
    final String text;
    if (connected != null) {
      title = l10n.browserWelcomeConnected(connected.browser ?? '');
      text = l10n.browserWelcomeTry;
    } else if (!bridge.enabled) {
      title = l10n.browserWelcomeInstallTitle;
      text = l10n.browserWelcomeTurnedOff;
    } else {
      title = l10n.browserWelcomeInstallTitle;
      text = l10n.browserWelcomeInstall;
    }
    void settings() {
      Navigator.pop(context);
      widget.openSettings();
    }

    return WelcomeFrame(
      picture: _Picture(
        window: _step(0, .55, curve: Curves.easeOutBack),
        panel: _step(.2, .7, curve: Curves.easeOutBack),
        pointer: _pointer,
      ),
      body: [
        WelcomeRise(
          animation: _step(.3, .7),
          child: WelcomeHeading(
            title: l10n.browserWelcomeTitle,
            lead: l10n.browserWelcomeLead,
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
          child: WelcomeStep(
            done: connected != null,
            icon: Codicons.extensions,
            title: title,
            text: text,
            below: [
              if (connected == null) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: bridge.enabled
                      ? [
                          IdeButton(
                            label: l10n.browserSettingsStoreOpen,
                            icon: Codicons.linkExternal,
                            onPressed: () =>
                                unawaited(ExtensionStore.openPage()),
                          ),
                          IdeButton(
                            label: l10n.browserWelcomeUnpacked,
                            icon: Codicons.cloudDownload,
                            secondary: true,
                            onPressed: () =>
                                unawaited(ExtensionStore.openZip()),
                          ),
                        ]
                      : [
                          IdeButton(
                            label: l10n.browserSettingsOpen,
                            icon: Codicons.settingsGear,
                            onPressed: settings,
                          ),
                        ],
                ),
              ],
            ],
          ),
        ),
      ],
      footer: WelcomeRise(
        animation: _step(.7, 1),
        child: Row(
          children: [
            IdeButton(
              label: l10n.browserSettingsOpen,
              icon: Codicons.settingsGear,
              secondary: true,
              onPressed: settings,
            ),
            const Spacer(),
            IdeButton(
              label: l10n.browserWelcomeDone,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}

// --- The picture ---------------------------------------------------------------

/// A browser window, its yellow BaoCode tab group in front, an agent's
/// pointer clicking a button on its page; the side panel beside it,
/// showing the same page and the step it took.
class _Picture extends StatelessWidget {
  const _Picture({
    required this.window,
    required this.panel,
    required this.pointer,
  });

  final Animation<double> window;
  final Animation<double> panel;

  /// Once round: to the button, a click, the button done, back.
  final Animation<double> pointer;

  /// The button's place in the window, and where the pointer starts.
  static const _button = Offset(66, 104);
  static const _start = Offset(170, 150);

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([window, panel, pointer]),
    builder: (context, _) {
      final t = pointer.value;
      // To the button by .35, the click at .4, done till .8, back.
      final travel = Curves.easeInOutCubic.transform(
        t < .35 ? t / .35 : (t > .8 ? 1 - (t - .8) / .2 : 1),
      );
      final clicked = t >= .4 && t < .85;
      final press = t >= .35 && t < .5
          ? math.sin((t - .35) / .15 * math.pi)
          : 0.0;
      final at = Offset.lerp(_start, _button + const Offset(30, 10), travel)!;
      return Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          _place(
            window,
            dx: -44,
            dy: 6,
            child: _Window(
              clicked: clicked,
              press: press,
              pointer: window.value >= 1 ? at : null,
            ),
          ),
          _place(panel, dx: 128, dy: 14, child: _Panel(clicked: clicked)),
        ],
      );
    },
  );

  Widget _place(
    Animation<double> animation, {
    required double dx,
    required double dy,
    required Widget child,
  }) {
    final t = animation.value;
    return Opacity(
      opacity: t.clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(dx, dy + (1 - t) * 40),
        child: child,
      ),
    );
  }
}

Color get _yellow => themeColors['charts.yellow'];

Widget _bar(double width, {double height = 6, Color? color}) => Container(
  width: width,
  height: height,
  decoration: BoxDecoration(
    color: color ?? AppColors.textMuted.withValues(alpha: .28),
    borderRadius: BorderRadius.circular(3),
  ),
);

/// The browser: its tab strip (the BaoCode group's two tabs, one of the
/// user's beside them), a page with a button, and the agent's pointer.
class _Window extends StatelessWidget {
  const _Window({
    required this.clicked,
    required this.press,
    required this.pointer,
  });

  final bool clicked;

  /// How far the button is pressed in, 0 to 1.
  final double press;

  /// Where the pointer is, in the window; none till the window is in.
  final Offset? pointer;

  @override
  Widget build(BuildContext context) {
    final yellow = _yellow;
    final green = themeColors['charts.green'];
    return Container(
      width: 250,
      height: 140,
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderStrong),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 22,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The tab strip.
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 9, 10, 0),
                child: Row(
                  children: [
                    for (final color in const [
                      Color(0xFFFF5F57),
                      Color(0xFFFEBC2E),
                      Color(0xFF28C840),
                    ]) ...[
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: .8),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: yellow,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'BaoCode',
                        style: TextStyle(
                          color: Color(0xFF1B1A17),
                          fontSize: 8.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    _Tab(underline: yellow, front: true),
                    _Tab(underline: yellow),
                    const _Tab(),
                  ],
                ),
              ),
              Container(
                height: 1,
                margin: const EdgeInsets.only(top: 6),
                color: AppColors.border,
              ),
              // The page.
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _bar(
                      120,
                      height: 8,
                      color: AppColors.textMuted.withValues(alpha: .45),
                    ),
                    const SizedBox(height: 8),
                    _bar(200),
                    const SizedBox(height: 5),
                    _bar(160),
                    const SizedBox(height: 12),
                    Transform.scale(
                      scale: 1 - press * .06,
                      alignment: Alignment.centerLeft,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 76,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: clicked
                              ? green.withValues(alpha: .2)
                              : AppColors.accent.withValues(alpha: .85),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: clicked
                            ? Icon(Codicons.check, size: 12, color: green)
                            : _bar(
                                40,
                                height: 5,
                                color: const Color(0xCCFFFFFF),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (pointer case final at?)
            Positioned(
              left: at.dx,
              top: at.dy,
              child: _Pointer(press: press),
            ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({this.underline, this.front = false});

  /// Its group's color.
  final Color? underline;
  final bool front;

  @override
  Widget build(BuildContext context) => Container(
    width: 34,
    height: 14,
    margin: const EdgeInsets.only(right: 3),
    padding: const EdgeInsets.symmetric(horizontal: 5),
    alignment: Alignment.centerLeft,
    decoration: BoxDecoration(
      color: front ? AppColors.textMuted.withValues(alpha: .12) : null,
      borderRadius: BorderRadius.circular(4),
      border: underline == null
          ? null
          : Border(bottom: BorderSide(color: underline!, width: 2)),
    ),
    child: _bar(18, height: 4),
  );
}

/// The agent's pointer, a ring where it clicks.
class _Pointer extends StatelessWidget {
  const _Pointer({required this.press});

  final double press;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 22,
    height: 22,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        if (press > 0)
          Positioned(
            left: -9 * press,
            top: -9 * press,
            child: Container(
              width: 18 * press,
              height: 18 * press,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: 1 - press * .5),
                  width: 1.5,
                ),
              ),
            ),
          ),
        CustomPaint(size: const Size(14, 18), painter: _ArrowPainter()),
      ],
    ),
  );
}

/// A pointer's arrow, outlined.
class _ArrowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(0, size.height * .82)
      ..lineTo(size.width * .3, size.height * .6)
      ..lineTo(size.width * .5, size.height)
      ..lineTo(size.width * .66, size.height * .92)
      ..lineTo(size.width * .46, size.height * .54)
      ..lineTo(size.width * .86, size.height * .54)
      ..close();
    canvas
      ..drawPath(path, Paint()..color = const Color(0xFF1B1A17))
      ..drawPath(
        path,
        Paint()
          ..color = const Color(0xFFFFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
  }

  @override
  bool shouldRepaint(_ArrowPainter oldDelegate) => false;
}

/// BaoCode's side panel: the page small, and the step the agent took.
class _Panel extends StatelessWidget {
  const _Panel({required this.clicked});

  final bool clicked;

  @override
  Widget build(BuildContext context) => Container(
    width: 118,
    height: 112,
    padding: const EdgeInsets.all(9),
    decoration: BoxDecoration(
      color: AppColors.surfaceRaised,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.border),
      boxShadow: const [
        BoxShadow(
          color: Color(0x26000000),
          blurRadius: 14,
          offset: Offset(0, 6),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The page as the panel shows it.
        Container(
          height: 50,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _bar(50, height: 4),
              const SizedBox(height: 4),
              _bar(80, height: 3),
              const Spacer(),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 30,
                height: 9,
                decoration: BoxDecoration(
                  color: clicked
                      ? themeColors['charts.green'].withValues(alpha: .3)
                      : AppColors.accent.withValues(alpha: .7),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // The conversation's step.
        Row(
          children: [
            SvgPicture.asset(
              browserIcon,
              width: 11,
              height: 11,
              colorFilter: ColorFilter.mode(
                AppColors.textMuted,
                BlendMode.srcIn,
              ),
            ),
            const SizedBox(width: 5),
            Expanded(child: _bar(double.infinity, height: 5)),
          ],
        ),
        const SizedBox(height: 7),
        AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: clicked ? 1 : 0,
          child: Row(
            children: [
              SvgPicture.asset(
                browserIcon,
                width: 11,
                height: 11,
                colorFilter: ColorFilter.mode(_yellow, BlendMode.srcIn),
              ),
              const SizedBox(width: 5),
              _bar(54, height: 5, color: _yellow.withValues(alpha: .6)),
            ],
          ),
        ),
      ],
    ),
  );
}
