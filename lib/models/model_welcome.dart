import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../base/step_clock.dart';
import '../icons/brand_logos.dart';
import '../ide/ide_button.dart';
import '../l10n/l10n.dart';
import '../settings/pages/models_page.dart' show ModelsSettingsPage;
import '../settings/settings_dialog.dart' show SettingsOpener, SettingsSection;
import '../settings/user_settings.dart' show GlobalStorage;
import '../theme/app_theme.dart';
import '../theme/codicons.dart';
import '../theme/workbench_theme.dart' show themeColors;
import '../tips/welcome_dialog.dart';
import 'model_provider.dart';
import 'model_providers.dart';

/// What a session with no model to run on offers (BaoCode's own core, no
/// upstream turned on): what an upstream is, three lines (any upstream, the
/// keys kept here, switched any time), and the one thing to do: adding one,
/// in Settings → Models, the welcome left under it. Done there, the step
/// says the model new conversations start on. The settings opened by
/// [openSettings], else by the [SettingsOpener] above [context].
Future<void> showModelWelcome(
  BuildContext context, {
  ModelProviders? providers,
  void Function(SettingsSection section)? openSettings,
}) {
  final store = providers ?? ModelProviders.current;
  final open = openSettings ?? SettingsOpener.maybeOf(context);
  final name = context.l10n.modelsNewProviderName;
  ModelWelcome.welcomed = true;
  return showWelcomeDialog(
    context,
    builder: (context) => ModelWelcome(
      providers: store,
      addUpstream: open == null
          ? null
          : () async {
              final id = await ModelsSettingsPage.addUpstream(store, name);
              ModelsSettingsPage.reveal.value = id;
              open(SettingsSection.models);
            },
    ),
  );
}

class ModelWelcome extends StatefulWidget {
  const ModelWelcome({super.key, required this.providers, this.addUpstream});

  /// Whose upstreams turn the step green.
  final ModelProviders providers;

  /// Adds an upstream and opens its page in Settings → Models; no button
  /// without it.
  final Future<void> Function()? addUpstream;

  /// Where [welcomed] is kept (main.dart sets it).
  static GlobalStorage? storage;
  static const welcomedKey = 'models.welcomed';

  /// Whether the welcome has shown, by itself or asked for: it shows by
  /// itself once. As if it had where nothing is kept (a test).
  static bool get welcomed =>
      _welcomed ?? (storage == null || storage!.get<bool>(welcomedKey) == true);
  static bool? _welcomed;

  static set welcomed(bool welcomed) {
    _welcomed = welcomed;
    unawaited(
      storage
          ?.set(welcomedKey, welcomed)
          .catchError((Object error) => debugPrint('$welcomedKey: $error')),
    );
  }

  @override
  State<ModelWelcome> createState() => _ModelWelcomeState();
}

class _ModelWelcomeState extends State<ModelWelcome>
    with TickerProviderStateMixin {
  /// The logos coming out round the mark, then the lines, one after
  /// another.
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..forward();

  /// The ring turning, slowly, once in.
  // On the shared clock's frames, not every vsync: it goes on for as
  // long as the page shows.
  final StepLoop _turn = StepLoop(const Duration(seconds: 60));

  @override
  void initState() {
    super.initState();
    _intro.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        _turn.start(context);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _turn.keepTo(context);
  }

  @override
  void dispose() {
    _intro.dispose();
    _turn.dispose();
    super.dispose();
  }

  Animation<double> _step(double from, double to, {Curve? curve}) =>
      CurvedAnimation(
        parent: _intro,
        curve: Interval(from, to, curve: curve ?? Curves.easeOutCubic),
      );

  bool _adding = false;

  Future<void> _add() async {
    setState(() => _adding = true);
    try {
      await widget.addUpstream!();
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.providers,
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final l10n = context.l10n;
    final providers = widget.providers;
    // What new conversations start on: the default, else the first.
    final ready =
        providers.resolve(providers.defaultModel) ??
        providers.resolve(providers.firstModel);
    final lines = [
      (Codicons.plug, l10n.modelWelcomeAnyTitle, l10n.modelWelcomeAny),
      (Codicons.lock, l10n.modelWelcomeKeysTitle, l10n.modelWelcomeKeys),
      (
        Codicons.arrowSwap,
        l10n.modelWelcomeSwitchTitle,
        l10n.modelWelcomeSwitch,
      ),
    ];
    return WelcomeFrame(
      picture: _Picture(
        logos: [
          for (final (i, _) in _Picture.names.indexed)
            _step(i * .05, .45 + i * .05, curve: Curves.easeOutBack),
        ],
        mark: _step(0, .35, curve: Curves.easeOutBack),
        turn: _turn,
        ready: ready != null,
      ),
      body: [
        WelcomeRise(
          animation: _step(.3, .7),
          child: WelcomeHeading(
            title: l10n.modelWelcomeTitle,
            lead: l10n.modelWelcomeLead,
          ),
        ),
        const SizedBox(height: 10),
        for (final (i, (icon, title, text)) in lines.indexed)
          WelcomeRise(
            animation: _step(.42 + i * .1, .82 + i * .06),
            child: WelcomeLine(
              icon: Icon(icon, size: 15),
              title: title,
              text: text,
            ),
          ),
        WelcomeRise(
          animation: _step(.62, .95),
          child: WelcomeStep(
            done: ready != null,
            icon: Codicons.add,
            title: ready == null
                ? l10n.modelWelcomeStepTitle
                : l10n.modelWelcomeReadyTitle,
            text: switch (ready) {
              (final ModelProvider provider, final ProviderModel model) =>
                l10n.modelWelcomeReady(
                  '${provider.name} · ${model.displayName}',
                ),
              null => l10n.modelWelcomeStep,
            },
            below: [
              if (ready == null && widget.addUpstream != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    IdeButton(
                      label: l10n.modelsAddProvider,
                      icon: Codicons.add,
                      spinning: _adding,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 5,
                      ),
                      onPressed: _adding ? null : () => unawaited(_add()),
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
            Expanded(
              child: ready == null
                  ? Text(
                      l10n.modelWelcomeLater,
                      style: TextStyle(
                        color: AppColors.textFaint,
                        fontSize: 12,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(width: 12),
            IdeButton(
              label: ready == null
                  ? l10n.modelWelcomeSkip
                  : l10n.modelWelcomeStart,
              secondary: ready == null,
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

/// BaoCode's mark in a tile, the makers of models round it on a ring that
/// turns, each upright; a tick on the mark once there is a model.
class _Picture extends StatelessWidget {
  const _Picture({
    required this.logos,
    required this.mark,
    required this.turn,
    required this.ready,
  });

  /// Some of [BrandLogos], round the ring in this order.
  static const names = [
    'claude',
    'openai',
    'gemini',
    'deepseek',
    'qwen',
    'kimi',
    'zhipu',
    'openrouter',
  ];

  static const _radius = 68.0;

  final List<Animation<double>> logos;
  final Animation<double> mark;
  final Animation<double> turn;
  final bool ready;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([...logos, mark, turn]),
    builder: (context, _) {
      final angle = turn.value * 2 * math.pi;
      return Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // The ring the logos go round on.
          Opacity(
            opacity: mark.value.clamp(0.0, 1.0),
            child: Container(
              width: _radius * 2,
              height: _radius * 2,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.textMuted.withValues(alpha: .14),
                ),
              ),
            ),
          ),
          for (final (i, name) in names.indexed)
            _logo(name, logos[i].value, angle + i * 2 * math.pi / names.length),
          Transform.scale(
            scale: mark.value,
            child: _Mark(ready: ready),
          ),
        ],
      );
    },
  );

  /// [name]'s tile at [angle] on the ring, come out from the middle as far
  /// as [t] says.
  Widget _logo(String name, double t, double angle) {
    final distance = _radius * t;
    return Opacity(
      opacity: t.clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(
          math.cos(angle - math.pi / 2) * distance,
          math.sin(angle - math.pi / 2) * distance,
        ),
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: AppColors.border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1F000000),
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: BrandLogo(name, size: 15, color: AppColors.text),
        ),
      ),
    );
  }
}

/// BaoCode's mark in the accent's tile; a tick at its corner once ready.
class _Mark extends StatelessWidget {
  const _Mark({required this.ready});

  final bool ready;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accent;
    final green = themeColors['charts.green'];
    return SizedBox.square(
      dimension: 64,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: accent.withValues(alpha: .45)),
              boxShadow: [
                BoxShadow(color: accent.withValues(alpha: .18), blurRadius: 24),
              ],
            ),
            child: BaoCodeLogo(size: 32, color: accent),
          ),
          Positioned(
            right: -6,
            bottom: -6,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutBack,
                ),
                child: child,
              ),
              child: ready
                  ? Container(
                      key: const ValueKey(true),
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: green,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: themeColors['editorWidget.background'],
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Codicons.check,
                        size: 12,
                        color: Colors.white,
                      ),
                    )
                  : const SizedBox.shrink(key: ValueKey(false)),
            ),
          ),
        ],
      ),
    );
  }
}
