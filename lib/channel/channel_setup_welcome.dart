import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../base/step_clock.dart';
import '../chat/widgets/hover_builder.dart';
import '../icons/brand_logos.dart' show BaoCodeLogo;
import '../ide/ide_button.dart';
import '../ide/ide_input.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import '../theme/codicons.dart';
import '../theme/workbench_theme.dart' show themeColors;
import '../tips/welcome_dialog.dart';
import 'account/account_api.dart' show AccountBlocked;
import 'channel_gate.dart';
import 'channel_setup.dart';

/// The channel build's way in ([ChannelGate]): its first start's setup,
/// which stays till done; then its channel's welcome (channels.json): its
/// logo beside BaoCode's, its words, and Sign In, which opens the login
/// window on its account site. It closes once signed in, and not before;
/// a channel the build cannot be used with says so, and stays.
/// [trouble], Having trouble?: the diagnostics' upload.
Future<void> showChannelSetupWelcome(
  BuildContext context, {
  required ChannelGate gate,
  void Function(BuildContext context)? trouble,
}) => showWelcomeDialog(
  context,
  builder: (context) => ChannelSetupWelcome(gate: gate, trouble: trouble),
);

class ChannelSetupWelcome extends StatefulWidget {
  const ChannelSetupWelcome({super.key, required this.gate, this.trouble});

  final ChannelGate gate;
  final void Function(BuildContext context)? trouble;

  @override
  State<ChannelSetupWelcome> createState() => _ChannelSetupWelcomeState();
}

class _ChannelSetupWelcomeState extends State<ChannelSetupWelcome>
    with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..forward();

  /// The dot going from BaoCode to the browser, again and again, while it
  /// waits.
  // On the shared clock's frames, not every vsync: it goes on for as
  // long as the page shows.
  final StepLoop _travel = StepLoop(const Duration(milliseconds: 1500));

  /// The channel's welcome coming in, once there is one.
  late final AnimationController _hello = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  /// The windows afloat once in.
  // On the shared clock's frames, not every vsync: it goes on for as
  // long as the page shows.
  final StepLoop _float = StepLoop(
    const Duration(milliseconds: 3600),
    reverse: true,
  );

  final _link = TextEditingController();
  bool _pasting = false;
  ChannelLinkResult? _linkResult;
  bool _closing = false;

  ChannelGate get _gate => widget.gate;

  /// The first start's setup, while this run has one.
  ChannelSetup? get _setup => _gate.setup;

  /// The channel's welcome, once its account site is known.
  bool get _welcoming => switch (_gate.stage) {
    ChannelStage.signIn || ChannelStage.ready => _gate.channel != null,
    _ => false,
  };

  String get _language =>
      Localizations.localeOf(context).languageCode == 'zh' ? 'zh' : 'en';

  @override
  void initState() {
    super.initState();
    _gate.addListener(_changed);
    _intro.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        _float.start(context);
      }
    });
    if (_setup case final setup? when !setup.done) unawaited(setup.check());
    // Once there is a context: its language, for the channel's words.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_gate.stage != ChannelStage.setup && _gate.channel == null) {
        unawaited(_gate.find(_language));
      }
      _changed();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _float.keepTo(context);
    _travel.keepTo(context);
  }

  @override
  void dispose() {
    _gate.removeListener(_changed);
    _intro.dispose();
    _hello.dispose();
    _travel.dispose();
    _float.dispose();
    _link.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    final waiting =
        (_setup?.waiting ?? false) && !(_setup?.openFailed ?? false);
    if (waiting && !_travel.isGoing) {
      _travel.start(context);
    } else if (!waiting && _travel.isGoing) {
      _travel.stop();
    }
    if (_gate.stage != ChannelStage.setup && _gate.channel == null) {
      unawaited(_gate.find(_language));
    }
    if (_welcoming && _hello.isDismissed) unawaited(_hello.forward());
    if (_gate.ready && !_closing) {
      _closing = true;
      Navigator.pop(context);
      _setup?.start();
      return;
    }
    setState(() {});
  }

  Animation<double> _step(
    double from,
    double to, {
    Curve? curve,
    AnimationController? of,
  }) => CurvedAnimation(
    parent: of ?? _intro,
    curve: Interval(from, to, curve: curve ?? Curves.easeOutCubic),
  );

  void _open() => unawaited(_setup?.openPage(zh: _language == 'zh'));

  void _retry() => unawaited(_gate.retry());

  /// Not a channel with accounts: the browser asked once more, at once.
  void _confirmAgain() {
    _gate.confirmAgain();
    _open();
  }

  void _paste() {
    final result = _setup?.acceptLink(_link.text);
    setState(() => _linkResult = result);
  }

  /// The login window on the channel's account site; or, signed in
  /// already, the account read and a key put to use once more.
  void _signIn() {
    final account = _gate.account;
    if (account == null || account.signingIn || account.busy) return;
    if (account.signedIn) {
      unawaited(account.settle());
    } else {
      unawaited(account.signIn(title: _gate.channel?.info.name ?? 'BaoCode'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _gate.ready,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        child: _welcoming
            ? KeyedSubtree(
                key: const ValueKey('channel'),
                child: _buildChannel(context, _gate.channel!),
              )
            : KeyedSubtree(
                key: const ValueKey('setup'),
                child: _buildSetup(context),
              ),
      ),
    );
  }

  Widget _buildChannel(BuildContext context, ChannelShown channel) {
    final l10n = context.l10n;
    final account = _gate.account;
    final welcome = channel.info.welcome;
    final name = channel.info.name;
    final signingIn = account?.signingIn ?? false;
    final busy = account?.busy ?? false;
    final error = account?.error;
    Animation<double> step(double from, double to, {Curve? curve}) =>
        _step(from, to, curve: curve, of: _hello);
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.enter): _signIn},
      child: WelcomeFrame(
        closable: false,
        stacked: true,
        picture: _ChannelPicture(
          logo: channel.logo,
          name: name,
          appear: step(0, .55, curve: Curves.easeOutBack),
          burst: step(.25, 1),
          float: _float,
        ),
        body: [
          WelcomeRise(
            animation: step(.3, .75),
            child: Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: WelcomeHeading(
                above: _setup == null
                    ? null
                    : _DoneChip(l10n.channelSetupDoneTitle),
                title: welcome?.title ?? l10n.channelWelcomeTitle(name),
                lead: welcome?.text ?? l10n.channelWelcomeText(name),
              ),
            ),
          ),
          if (error != null)
            _Failed(
              error is AccountBlocked
                  ? l10n.channelAccountBlocked(error.host, error.request)
                  : l10n.channelWelcomeFailed('$error'),
            ),
        ],
        footer: WelcomeRise(
          animation: step(.55, 1),
          child: Center(
            child: SizedBox(
              width: 260,
              child: IdeButton(
                label: signingIn
                    ? l10n.channelWelcomeSigningIn
                    : busy
                    ? l10n.channelWelcomePreparing
                    : welcome?.button ?? l10n.channelWelcomeSignIn,
                icon: signingIn || busy ? Codicons.loading : null,
                spinning: signingIn || busy,
                expand: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                onPressed: account == null || busy ? null : _signIn,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSetup(BuildContext context) {
    final l10n = context.l10n;
    final stage = _gate.stage;
    final setup = _setup;
    final done = stage != ChannelStage.setup;
    // The browser did not open the page: its address, to open by hand.
    final failed = !done && (setup?.openFailed ?? false);
    final waiting = !done && !failed && (setup?.waiting ?? false);
    final finding = stage == ChannelStage.finding;
    final String title;
    final String text;
    switch (stage) {
      case ChannelStage.setup when failed:
        title = l10n.channelSetupOpenFailedTitle;
        text = l10n.channelSetupOpenFailed;
      case ChannelStage.setup when waiting:
        title = l10n.channelSetupWaitingTitle;
        text = l10n.channelSetupWaiting;
      case ChannelStage.setup:
        title = l10n.channelSetupStepTitle;
        text = l10n.channelSetupStep;
      case ChannelStage.offline:
        title = l10n.channelSetupSiteOfflineTitle;
        text = l10n.channelSetupSiteOffline;
      case ChannelStage.unavailable:
        title = l10n.channelSetupUnavailableTitle;
        text = l10n.channelSetupUnavailable;
      case ChannelStage.finding || ChannelStage.signIn || ChannelStage.ready:
        title = l10n.channelSetupFindingTitle;
        text = l10n.channelSetupFinding;
    }
    final stuck =
        stage == ChannelStage.offline || stage == ChannelStage.unavailable;
    final trouble = widget.trouble;
    return WelcomeFrame(
      closable: false,
      stacked: true,
      picture: _Picture(
        app: _step(0, .5, curve: Curves.easeOutBack),
        browser: _step(.1, .6, curve: Curves.easeOutBack),
        way: _step(.35, .75),
        float: _float,
        travel: _travel,
        waiting: waiting,
        done: done,
      ),
      body: [
        WelcomeRise(
          animation: _step(.3, .7),
          child: WelcomeHeading(
            title: l10n.channelSetupTitle,
            lead: l10n.channelSetupLead,
          ),
        ),
        const SizedBox(height: 10),
        for (final (i, (icon, title, text)) in [
          (Codicons.history, l10n.channelSetupOnceTitle, l10n.channelSetupOnce),
          (
            Codicons.shield,
            l10n.channelSetupPrivateTitle,
            l10n.channelSetupPrivate,
          ),
        ].indexed)
          WelcomeRise(
            animation: _step(.42 + i * .1, .82 + i * .06),
            child: WelcomeLine(
              icon: Icon(icon, size: 15),
              title: title,
              text: text,
            ),
          ),
        WelcomeRise(
          animation: _step(.6, .95),
          child: WelcomeStep(
            done: done && !stuck && !finding,
            spinning: waiting || finding,
            icon: stuck || failed
                ? Codicons.warning
                : waiting || finding
                ? Codicons.loading
                : Codicons.globe,
            title: title,
            text: text,
            below: [
              if (setup != null && failed) ...[
                const SizedBox(height: 8),
                _PageAddress('${setup.page(zh: _language == 'zh')}'),
              ],
              if (setup != null && setup.offline && !done) ...[
                const SizedBox(height: 6),
                Text(
                  l10n.channelSetupOffline,
                  style: TextStyle(color: AppColors.caution, fontSize: 12),
                ),
                const SizedBox(height: 4),
                _Link(l10n.channelSetupRetry, onTap: _open),
              ],
              if (!done) ...[
                const SizedBox(height: 10),
                if (!_pasting)
                  _Link(
                    l10n.channelSetupNoResponse,
                    onTap: () => setState(() => _pasting = true),
                  )
                else
                  _Paste(
                    controller: _link,
                    result: _linkResult,
                    onSubmit: _paste,
                    onChanged: () {
                      if (_linkResult != null) {
                        setState(() => _linkResult = null);
                      }
                    },
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 4),
      ],
      footer: WelcomeRise(
        animation: _step(.7, 1),
        child: Row(
          children: [
            if (trouble != null && (!done || stuck))
              _Link(
                l10n.channelSetupTrouble,
                muted: true,
                onTap: () => trouble(context),
              ),
            const Spacer(),
            const SizedBox(width: 12),
            if (!done)
              IdeButton(
                label: waiting || failed
                    ? l10n.channelSetupOpenAgain
                    : l10n.channelSetupOpen,
                icon: waiting || failed ? null : Codicons.linkExternal,
                secondary: waiting || failed,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                onPressed: _open,
              )
            else if (stage == ChannelStage.unavailable &&
                _gate.makeSetupAgain != null) ...[
              IdeButton(
                label: l10n.channelSetupRetry,
                secondary: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                onPressed: _retry,
              ),
              const SizedBox(width: 8),
              IdeButton(
                label: l10n.channelSetupConfirmAgain,
                icon: Codicons.linkExternal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                onPressed: _confirmAgain,
              ),
            ] else if (stuck)
              IdeButton(
                label: l10n.channelSetupRetry,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                onPressed: _retry,
              ),
          ],
        ),
      ),
    );
  }
}

/// The page's address, when the browser did not open it: copied, to open
/// by hand.
class _PageAddress extends StatefulWidget {
  const _PageAddress(this.url);

  final String url;

  @override
  State<_PageAddress> createState() => _PageAddressState();
}

class _PageAddressState extends State<_PageAddress> {
  bool _copied = false;
  Timer? _copiedTimer;

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  void _copy() {
    unawaited(Clipboard.setData(ClipboardData(text: widget.url)));
    _copiedTimer?.cancel();
    setState(() => _copied = true);
    _copiedTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.borderStrong),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              widget.url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.text,
                fontSize: 12,
                fontFamily: AppFonts.mono,
                fontFamilyFallback: AppFonts.monoFallbacks,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IdeButton(
          label: _copied ? l10n.channelSetupAddressCopied : l10n.commonCopy,
          icon: _copied ? Codicons.check : Codicons.copy,
          onPressed: _copy,
        ),
      ],
    );
  }
}

/// The link the page hands over, pasted: said what is wrong with one that
/// is not.
class _Paste extends StatelessWidget {
  const _Paste({
    required this.controller,
    required this.result,
    required this.onSubmit,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ChannelLinkResult? result;
  final VoidCallback onSubmit;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final problem = switch (result) {
      ChannelLinkResult.invalid => l10n.channelSetupLinkInvalid,
      ChannelLinkResult.otherInstall => l10n.channelSetupLinkOther,
      ChannelLinkResult.accepted || null => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.channelSetupPasteLead,
          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: IdeInputBox(
                controller: controller,
                autofocus: true,
                placeholder: 'baocode://activate?…',
                semanticsLabel: l10n.channelSetupPasteLead,
                validation: problem == null
                    ? null
                    : IdeInputValidation(problem),
                onChanged: (_) => onChanged(),
                onSubmitted: (_) => onSubmit(),
              ),
            ),
            const SizedBox(width: 8),
            IdeButton(
              label: l10n.channelSetupPasteConfirm,
              secondary: true,
              onPressed: onSubmit,
            ),
          ],
        ),
      ],
    );
  }
}

class _Link extends StatelessWidget {
  const _Link(this.label, {required this.onTap, this.muted = false});

  final String label;
  final VoidCallback onTap;

  /// In the footer: faint till pointed at.
  final bool muted;

  @override
  Widget build(BuildContext context) => HoverBuilder(
    cursor: SystemMouseCursors.click,
    builder: (context, hovered) {
      final color = muted && !hovered
          ? AppColors.textFaint
          : themeColors['textLink.foreground'];
      return GestureDetector(
        onTap: onTap,
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12.5,
            decoration: hovered ? TextDecoration.underline : null,
            decorationColor: color,
          ),
        ),
      );
    },
  );
}

// --- The picture ---------------------------------------------------------------

/// BaoCode's window and the browser's, fanned out, afloat, an arc between:
/// a dot going along it while it waits; once done, the arc green and a
/// tick on the browser's page.
class _Picture extends StatelessWidget {
  const _Picture({
    required this.app,
    required this.browser,
    required this.way,
    required this.float,
    required this.travel,
    required this.waiting,
    required this.done,
  });

  final Animation<double> app;
  final Animation<double> browser;
  final Animation<double> way;
  final Animation<double> float;
  final Animation<double> travel;
  final bool waiting;
  final bool done;

  static const _dx = 104.0;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([app, browser, way, float, travel]),
    builder: (context, _) {
      final drift = math.sin(float.value * math.pi);
      final green = themeColors['charts.green'];
      return Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          _place(
            app,
            dx: -_dx,
            dy: 22 - drift * 3,
            turn: -.03,
            child: const _MiniWindow(app: true),
          ),
          _place(
            browser,
            dx: _dx,
            dy: 22 + drift * 3,
            turn: .03,
            child: _MiniWindow(app: false, done: done),
          ),
          // Over them, from the top of BaoCode's window to the browser's.
          Positioned.fill(
            child: Opacity(
              opacity: way.value.clamp(0.0, 1.0),
              child: CustomPaint(
                painter: _Arc(
                  from: Offset(-_dx, 57 - drift * 3),
                  to: Offset(_dx, 57 + drift * 3),
                  color: done
                      ? green.withValues(alpha: .8)
                      : AppColors.textMuted.withValues(alpha: .5),
                  dot: waiting
                      ? Curves.easeInOutCubic.transform(travel.value)
                      : null,
                  dotColor: AppColors.accent,
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
        offset: Offset(dx * t, dy + (1 - t) * 40),
        child: Transform.rotate(angle: turn * t * math.pi, child: child),
      ),
    );
  }
}

/// A window, small: BaoCode's, its sidebar and its logo; or the browser's,
/// baocode.dev in its address bar, a tick on its page once done.
class _MiniWindow extends StatelessWidget {
  const _MiniWindow({required this.app, this.done = false});

  final bool app;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final bar = AppColors.textMuted.withValues(alpha: .28);
    final green = themeColors['charts.green'];
    Widget line(double width, {double height = 6, Color? color}) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color ?? bar,
        borderRadius: BorderRadius.circular(3),
      ),
    );
    final lights = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final color in const [
          Color(0xFFFF5F57),
          Color(0xFFFEBC2E),
          Color(0xFF28C840),
        ])
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .85),
              shape: BoxShape.circle,
            ),
          ),
      ],
    );
    final Widget top;
    final Widget page;
    if (app) {
      top = lights;
      page = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              line(30),
              const SizedBox(height: 6),
              line(22),
              const SizedBox(height: 6),
              line(26),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Center(
              child: BaoCodeLogo(size: 30, color: AppColors.textPrimary),
            ),
          ),
        ],
      );
    } else {
      top = Row(
        children: [
          lights,
          const SizedBox(width: 2),
          Expanded(
            child: Container(
              height: 14,
              padding: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: AppColors.textMuted.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Row(
                children: [
                  Icon(Codicons.lock, size: 8, color: AppColors.textMuted),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      'baocode.dev',
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      softWrap: false,
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 8.5,
                        height: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
      page = Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              line(84, height: 8, color: bar.withValues(alpha: .5)),
              const SizedBox(height: 8),
              line(double.infinity),
              const SizedBox(height: 6),
              line(64),
            ],
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 360),
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutBack,
                ),
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: done
                  ? Container(
                      key: const ValueKey('done'),
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: green.withValues(alpha: .16),
                        shape: BoxShape.circle,
                        border: Border.all(color: green.withValues(alpha: .5)),
                      ),
                      child: Icon(Codicons.check, size: 13, color: green),
                    )
                  : const SizedBox(key: ValueKey('waiting'), width: 22),
            ),
          ),
        ],
      );
    }
    return Container(
      width: 156,
      height: 112,
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 12),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          top,
          const SizedBox(height: 10),
          Expanded(child: page),
        ],
      ),
    );
  }
}

/// The way between the windows: dots along an arc from [from] to [to]
/// (from the middle of the top of the picture), and the one going along it
/// at [dot] (0 to 1), if any.
class _Arc extends CustomPainter {
  _Arc({
    required this.from,
    required this.to,
    required this.color,
    required this.dot,
    required this.dotColor,
  });

  final Offset from;
  final Offset to;
  final Color color;
  final double? dot;
  final Color dotColor;

  Offset _at(Size size, double t) {
    final origin = Offset(size.width / 2, 0);
    final start = origin + from;
    final end = origin + to;
    final control = Offset(size.width / 2, -18);
    final u = 1 - t;
    return start * (u * u) + control * (2 * u * t) + end * (t * t);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    const steps = 28;
    for (var i = 2; i < steps - 1; i++) {
      canvas.drawCircle(_at(size, i / steps), 1.6, paint);
    }
    // Where it leaves one window and comes to the other.
    for (final t in const [0.0, 1.0]) {
      canvas.drawCircle(_at(size, t), 3, paint);
    }
    if (dot case final t?) {
      final at = _at(size, .08 + t * .84);
      canvas.drawCircle(at, 7, Paint()..color = dotColor.withValues(alpha: .2));
      canvas.drawCircle(at, 3.5, Paint()..color = dotColor);
    }
  }

  @override
  bool shouldRepaint(_Arc old) =>
      old.from != from ||
      old.to != to ||
      old.color != color ||
      old.dot != dot ||
      old.dotColor != dotColor;
}

/// Set up, said small above a channel's welcome.
class _DoneChip extends StatelessWidget {
  const _DoneChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final green = themeColors['charts.green'];
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 3, 9, 3),
      decoration: BoxDecoration(
        color: green.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Codicons.check, size: 12, color: green),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: green,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Why signing in did not go through: under the welcome's words, in line
/// with them, a warning's tint around it.
class _Failed extends StatelessWidget {
  const _Failed(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final caution = AppColors.caution;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 6, 28, 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
        decoration: BoxDecoration(
          color: caution.withValues(alpha: .08),
          border: Border.all(color: caution.withValues(alpha: .25)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(Codicons.warning, size: 14, color: caution),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: caution, fontSize: 12.5, height: 1.45),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A channel's welcome's picture: its logo and BaoCode's, side by side,
/// a × between, coming in; confetti bursting out from between them, then
/// afloat.
class _ChannelPicture extends StatelessWidget {
  const _ChannelPicture({
    required this.logo,
    required this.name,
    required this.appear,
    required this.burst,
    required this.float,
  });

  /// SVG or a picture; the name's first letter without.
  final Uint8List? logo;
  final String name;
  final Animation<double> appear;
  final Animation<double> burst;
  final Animation<double> float;

  static const _tile = 84.0;
  static const _dx = 74.0;

  /// The confetti: where each goes (angle in turns, how far), its size and
  /// its shape, the same each time.
  static const _bits = [
    (.02, 150.0, 7.0, 0),
    (.09, 118.0, 5.0, 1),
    (.16, 166.0, 6.0, 2),
    (.24, 132.0, 4.0, 0),
    (.31, 172.0, 8.0, 1),
    (.40, 112.0, 5.0, 2),
    (.47, 158.0, 6.0, 0),
    (.55, 140.0, 7.0, 1),
    (.62, 170.0, 5.0, 2),
    (.70, 122.0, 6.0, 0),
    (.78, 160.0, 4.0, 1),
    (.85, 136.0, 7.0, 2),
    (.93, 168.0, 5.0, 0),
    (.05, 96.0, 4.0, 2),
    (.20, 190.0, 5.0, 1),
    (.35, 92.0, 4.0, 0),
    (.51, 196.0, 6.0, 2),
    (.66, 98.0, 4.0, 1),
    (.74, 192.0, 5.0, 0),
    (.88, 100.0, 4.0, 2),
    (.98, 196.0, 6.0, 1),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = [
      themeColors['charts.blue'],
      themeColors['charts.purple'],
      themeColors['charts.green'],
      themeColors['charts.yellow'],
      themeColors['charts.orange'],
      AppColors.accent,
    ];
    return AnimatedBuilder(
      animation: Listenable.merge([appear, burst, float]),
      builder: (context, _) {
        final t = appear.value;
        final b = burst.value.clamp(0.0, 1.0);
        final drift = math.sin(float.value * math.pi);
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // The glow behind them.
            Opacity(
              opacity: t.clamp(0.0, 1.0),
              child: Container(
                width: 260,
                height: 150,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      AppColors.accent.withValues(alpha: .16),
                      AppColors.accent.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            for (final (i, (turn, far, size, shape)) in _bits.indexed)
              Transform.translate(
                offset:
                    Offset(
                          math.cos(turn * 2 * math.pi) * far * .75,
                          math.sin(turn * 2 * math.pi) * far * .42,
                        ) *
                        Curves.easeOutCubic.transform(b) +
                    Offset(0, (i.isEven ? drift : -drift) * 3),
                child: Opacity(
                  opacity: (b * 3).clamp(0.0, 1.0) * .85,
                  child: Transform.rotate(
                    angle: (turn + b * .5 + float.value * .1) * math.pi * 2,
                    child: _Bit(
                      size: size,
                      shape: shape,
                      color: colors[i % colors.length],
                    ),
                  ),
                ),
              ),
            _place(
              t,
              dx: -_dx,
              dy: -drift * 3,
              turn: -.03,
              child: _LogoTile(child: _logo(context)),
            ),
            Opacity(
              opacity: t.clamp(0.0, 1.0),
              child: Text(
                '×',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 22,
                  fontWeight: FontWeight.w300,
                ),
              ),
            ),
            _place(
              t,
              dx: _dx,
              dy: drift * 3,
              turn: .03,
              child: _LogoTile(
                child: BaoCodeLogo(size: 44, color: AppColors.textPrimary),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _logo(BuildContext context) {
    final bytes = logo;
    const size = _tile * .58;
    Widget letter() => Text(
      name.characters.first.toUpperCase(),
      style: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 34,
        fontWeight: FontWeight.w600,
      ),
    );
    if (bytes == null) return letter();
    final head = String.fromCharCodes(bytes.take(256)).trimLeft();
    if (head.startsWith('<')) {
      return SvgPicture.memory(
        bytes,
        width: size,
        height: size,
        errorBuilder: (_, _, _) => letter(),
      );
    }
    return Image.memory(
      bytes,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => letter(),
    );
  }

  Widget _place(
    double t, {
    required double dx,
    required double dy,
    required double turn,
    required Widget child,
  }) => Opacity(
    opacity: t.clamp(0.0, 1.0),
    child: Transform.translate(
      offset: Offset(dx * t, dy + (1 - t) * 30),
      child: Transform.rotate(
        angle: turn * t * math.pi,
        child: Transform.scale(scale: .7 + .3 * t, child: child),
      ),
    ),
  );
}

class _LogoTile extends StatelessWidget {
  const _LogoTile({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: _ChannelPicture._tile,
    height: _ChannelPicture._tile,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: AppColors.surfaceRaised,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.borderStrong),
      boxShadow: const [
        BoxShadow(
          color: Color(0x2E000000),
          blurRadius: 24,
          offset: Offset(0, 10),
        ),
      ],
    ),
    child: child,
  );
}

/// One bit of confetti: a dot, a strip or a square.
class _Bit extends StatelessWidget {
  const _Bit({required this.size, required this.shape, required this.color});

  final double size;
  final int shape;
  final Color color;

  @override
  Widget build(BuildContext context) => switch (shape) {
    0 => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    ),
    1 => Container(
      width: size * 1.8,
      height: size * .7,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size),
      ),
    ),
    _ => Container(
      width: size * 1.2,
      height: size * 1.2,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(1.5),
      ),
    ),
  };
}
