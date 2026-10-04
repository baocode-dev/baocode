import 'dart:async';

import 'package:flutter/foundation.dart';

import '../ide/ide_notifications.dart';
import '../l10n/l10n.dart';
import '../update/version.dart';
import 'feature_tip.dart';

/// What the user did with a tip, as kept.
enum TipState {
  /// Offered in a notification, and let be.
  seen,

  /// Closed, or "Don't Show Again": not offered again.
  dismissed,

  /// Turned on from the tip.
  accepted,
}

/// Where the workbench shows a tip that comes up by itself, and how it
/// does what the tip offers (see FeatureTipsController.attach).
class TipsPresenter {
  const TipsPresenter({
    required this.notifications,
    required this.l10n,
    required this.context,
    this.busy,
  });

  final IdeNotifications notifications;
  final AppLocalizations Function() l10n;

  /// What a tip's action is done with; null once the window is gone.
  final TipContext? Function() context;

  /// Whether now would interrupt: an agent answering, the user typing.
  final bool Function()? busy;
}

/// The app's feature tips ([FeatureTip]), and what the user did with them:
///
/// - the setup checklist, a card on the new agent's page (and the empty
///   workspace) at the first launches: the tips of [TipTrigger.firstLaunch]
///   on and relevant. Done, collapsed, or let be for
///   [idleLaunchesToCollapse] launches, it folds into the sidebar's
///   "Setup n/m" ([entryVisible]); [restore] (Show Setup Guide) brings it
///   back;
/// - after an update, one notification of the tips that came in since the
///   version that ran last ([TipTrigger.upgrade], [FeatureTip.since]);
/// - a tip of a [TipTrigger.scenario] when that happens: one notification
///   a launch at most, once ever, put off while the user is busy.
///
/// What was done is kept in the app's storage under [storageKey]; the
/// setting [enabledSetting] (`workbench.tips.enabled`) false shows none.
class FeatureTipsController extends ChangeNotifier {
  FeatureTipsController({
    required this.tips,
    required this.storage,
    bool Function()? enabled,
    this.settingsChanges,
    AppVersion? version,
    DateTime Function()? now,
    this.retryDelay = const Duration(seconds: 2),
  }) : _enabled = enabled ?? (() => true),
       _version = version ?? currentAppVersion,
       _now = now ?? DateTime.now {
    settingsChanges?.addListener(_settingsChanged);
  }

  static const storageKey = 'featureTips';
  static const enabledSetting = 'workbench.tips.enabled';

  /// Launches the checklist shows without anything done before it folds.
  static const idleLaunchesToCollapse = 3;

  final List<FeatureTip> tips;

  /// Where what the user did is kept.
  final TipStorage storage;

  /// Tells when settings.json changes, [enabledSetting] with it.
  final Listenable? settingsChanges;

  final bool Function() _enabled;
  final AppVersion _version;
  final DateTime Function() _now;

  /// How long a tip put off waits before it looks again.
  final Duration retryDelay;

  bool _disposed = false;
  bool _wasEnabled = true;

  bool get enabled => _enabled();

  void _settingsChanged() {
    final enabled = this.enabled;
    if (enabled == _wasEnabled) return;
    _wasEnabled = enabled;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // --- What is kept ---------------------------------------------------------

  Map<String, Object?> get _kept => switch (storage.get(storageKey)) {
    final Map<Object?, Object?> map => {
      for (final MapEntry(:key, :value) in map.entries)
        if (key is String) key: value,
    },
    _ => {},
  };

  Future<void> _keep(void Function(Map<String, Object?> kept) change) {
    final kept = _kept;
    change(kept);
    return storage.set(storageKey, kept);
  }

  Map<String, Object?> _tipRecords(Map<String, Object?> kept) =>
      switch (kept['tips']) {
        final Map<Object?, Object?> map => {
          for (final MapEntry(:key, :value) in map.entries)
            if (key is String) key: value,
        },
        _ => {},
      };

  /// What the user did with [tip], if anything.
  TipState? stateOf(FeatureTip tip) => switch (_tipRecords(_kept)[tip.id]) {
    {'state': final String name} => TipState.values.asNameMap()[name],
    _ => null,
  };

  Future<void> _setState(FeatureTip tip, TipState state) => _keep((kept) {
    final records = _tipRecords(kept);
    records[tip.id] = {
      'state': state.name,
      'at': _now().toUtc().toIso8601String(),
    };
    kept['tips'] = records;
  });

  // --- The launch -----------------------------------------------------------

  bool _started = false;
  List<FeatureTip> _checklist = const [];
  bool _collapsed = false;
  bool _showDismissed = false;

  /// The version that ran before this launch, when it was older: an update.
  AppVersion? _updatedFrom;
  List<FeatureTip> _upgradeTips = const [];

  /// What this launch shows: the checklist (counting a launch it is let be
  /// at), and, after an update, its tips; then keeps this version as the
  /// one that ran. Once a launch.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _wasEnabled = enabled;
    final kept = _kept;
    final last = switch (kept['lastVersion']) {
      final String text => _parse(text),
      _ => null,
    };
    if (last != null && last < _version) {
      _updatedFrom = last;
      _upgradeTips = [
        for (final tip in tips)
          if (tip.triggers.contains(TipTrigger.upgrade) &&
              _cameAfter(tip, last) &&
              _offerable(tip) &&
              await _relevant(tip))
            tip,
      ];
    }
    _checklist = await _listChecklist();
    var collapsed = kept['collapsed'] == true;
    var idle = switch (kept['idleLaunches']) {
      final int count => count,
      _ => 0,
    };
    if (!collapsed && _checklist.isNotEmpty && !_allDone) {
      if (idle >= idleLaunchesToCollapse) {
        collapsed = true;
      } else {
        idle++;
      }
    }
    _collapsed = collapsed;
    await _keep((kept) {
      kept['lastVersion'] = '$_version';
      kept['collapsed'] = collapsed;
      kept['idleLaunches'] = idle;
    });
    _notify();
  }

  static AppVersion? _parse(String text) {
    try {
      return AppVersion.parse(text);
    } on FormatException {
      return null;
    }
  }

  /// Whether [tip] came in after [last], up to this version.
  bool _cameAfter(FeatureTip tip, AppVersion last) {
    final since = switch (tip.since) {
      final String text => _parse(text),
      null => null,
    };
    return since != null && last < since && since <= _version;
  }

  /// Not turned on from a tip, nor dismissed.
  bool _offerable(FeatureTip tip) => switch (stateOf(tip)) {
    TipState.accepted || TipState.dismissed => false,
    _ => true,
  };

  Future<bool> _relevant(FeatureTip tip) async {
    try {
      return await tip.relevant();
    } on Object catch (error) {
      debugPrint('${tip.id}: $error');
      return false;
    }
  }

  /// The checklist's tips: those of the first launch turned on from it,
  /// and those relevant not dismissed (dismissed too when restored).
  Future<List<FeatureTip>> _listChecklist() async => [
    for (final tip in tips)
      if (tip.triggers.contains(TipTrigger.firstLaunch))
        if (stateOf(tip) == TipState.accepted ||
            ((_showDismissed || stateOf(tip) != TipState.dismissed) &&
                await _relevant(tip)))
          tip,
  ];

  // --- The checklist --------------------------------------------------------

  /// The checklist's tips, in order.
  List<FeatureTip> get checklist => _checklist;

  bool isDone(FeatureTip tip) => stateOf(tip) == TipState.accepted;

  int get doneCount => _checklist.where(isDone).length;

  bool get _allDone => _checklist.every(isDone);

  /// Whether the card shows.
  bool get cardVisible =>
      enabled && _started && !_collapsed && _checklist.isNotEmpty && !_allDone;

  /// Whether the sidebar's "Setup n/m" shows instead.
  bool get entryVisible =>
      enabled && _started && _collapsed && _checklist.isNotEmpty;

  /// The tip turned on, last, failed with this: shown under it.
  final Map<String, String> errors = {};

  /// Turns [tip] on: kept as accepted once it is. Done with the last of the
  /// checklist, the card folds.
  Future<bool> accept(FeatureTip tip, TipContext context) async {
    errors.remove(tip.id);
    bool done;
    try {
      done = await tip.apply(context);
    } on Object catch (error) {
      errors[tip.id] = '$error';
      _notify();
      return false;
    }
    if (done) {
      await _setState(tip, TipState.accepted);
      await _acted();
    }
    _notify();
    return done;
  }

  /// Takes [tip] off the checklist, and out of the notifications for good.
  Future<void> dismiss(FeatureTip tip) async {
    await _setState(tip, TipState.dismissed);
    await tip.onDismiss?.call();
    _checklist = [
      for (final listed in _checklist)
        if (!identical(listed, tip)) listed,
    ];
    await _acted();
    _notify();
  }

  /// Something done in the checklist: the launches it is let be at count
  /// again; with nothing left to do, it folds.
  Future<void> _acted() async {
    if (_checklist.isNotEmpty && _allDone) _collapsed = true;
    await _keep((kept) {
      kept['idleLaunches'] = 0;
      kept['collapsed'] = _collapsed;
    });
  }

  /// Folds the card into the sidebar's entry.
  Future<void> collapse() async {
    _collapsed = true;
    await _keep((kept) => kept['collapsed'] = true);
    _notify();
  }

  /// How many times the card was brought back: the main window shows where
  /// it is (a new agent) at each.
  int get restores => _restores;
  int _restores = 0;

  /// Show Setup Guide (and the sidebar's entry): the card back, with the
  /// tips dismissed before too.
  Future<void> restore() async {
    _restores++;
    _started = true;
    _showDismissed = true;
    _collapsed = false;
    _checklist = await _listChecklist();
    await _keep((kept) {
      kept['collapsed'] = false;
      kept['idleLaunches'] = 0;
    });
    _notify();
  }

  /// The tips not on yet, relevant here (Settings → General's list).
  Future<List<FeatureTip>> pending() async => [
    for (final tip in tips)
      if (await _relevant(tip)) tip,
  ];

  // --- Notifications --------------------------------------------------------

  TipsPresenter? _presenter;

  /// Whether this launch has told of a tip already.
  bool _notified = false;

  /// The scenario tip put off while the user is busy.
  FeatureTip? _pending;
  Timer? _retry;

  /// Where tips show from now on: told of the update's at once.
  void attach(TipsPresenter presenter) {
    _presenter = presenter;
    _showUpgrade();
  }

  void detach(TipsPresenter presenter) {
    if (identical(_presenter, presenter)) _presenter = null;
  }

  /// The version updated from and its tips, for the notice.
  @visibleForTesting
  List<FeatureTip> get upgradeTips => _upgradeTips;

  void _showUpgrade() {
    final presenter = _presenter;
    final from = _updatedFrom;
    if (presenter == null || from == null || !enabled || _notified) return;
    final shown = _upgradeTips;
    _upgradeTips = const [];
    if (shown.isEmpty) return;
    _notified = true;
    final l10n = presenter.l10n();
    for (final tip in shown) {
      unawaited(_setState(tip, TipState.seen));
    }
    var acted = false;
    presenter.notifications.notify(
      IdeSeverity.info,
      l10n.tipsUpdated(
        _version.marketing,
        shown.map((tip) => tip.title(l10n)).join(l10n.tipsListSeparator),
      ),
      sticky: true,
      primary: [
        for (final tip in shown)
          IdeNotificationAction(
            shown.length == 1 ? l10n.tipsTurnOn : tip.title(l10n),
            () {
              acted = true;
              unawaited(_acceptFromNotification(tip));
            },
          ),
        IdeNotificationAction(l10n.tipsDontShowAgain, () {
          acted = true;
          for (final tip in shown) {
            unawaited(dismiss(tip));
          }
        }),
      ],
      onClose: () => scheduleMicrotask(() {
        if (acted) return;
        for (final tip in shown) {
          unawaited(dismiss(tip));
        }
      }),
    );
  }

  /// [id] happened: its tip, if one is offerable, relevant and not shown
  /// before, shows once the user is not busy (none if this launch has
  /// told of one already).
  Future<void> scenario(String id) async {
    if (!enabled || _notified || _pending != null) return;
    final trigger = TipTrigger.scenario(id);
    for (final tip in tips) {
      if (!tip.triggers.contains(trigger)) continue;
      if (stateOf(tip) != null) continue;
      if (!await _relevant(tip)) continue;
      if (_notified || _pending != null) return;
      _pending = tip;
      _deliver();
      return;
    }
  }

  void _deliver() {
    _retry?.cancel();
    _retry = null;
    final tip = _pending;
    final presenter = _presenter;
    if (tip == null || presenter == null || _disposed) return;
    if (!enabled || _notified) {
      _pending = null;
      return;
    }
    if (presenter.busy?.call() ?? false) {
      _retry = Timer(retryDelay, _deliver);
      return;
    }
    _pending = null;
    _notified = true;
    unawaited(_setState(tip, TipState.seen));
    final l10n = presenter.l10n();
    var acted = false;
    presenter.notifications.notify(
      IdeSeverity.info,
      '${tip.title(l10n)}: ${tip.body(l10n)}',
      sticky: true,
      primary: [
        IdeNotificationAction(l10n.tipsTurnOn, () {
          acted = true;
          unawaited(_acceptFromNotification(tip));
        }),
        IdeNotificationAction(l10n.tipsDontShowAgain, () {
          acted = true;
          unawaited(dismiss(tip));
        }),
      ],
      onClose: () => scheduleMicrotask(() {
        if (!acted) unawaited(dismiss(tip));
      }),
    );
  }

  /// Turns [tip] on from a notification; what failed is told in another.
  Future<void> _acceptFromNotification(FeatureTip tip) async {
    final presenter = _presenter;
    final context = presenter?.context();
    if (presenter == null || context == null) return;
    await accept(tip, context);
    if (errors[tip.id] case final error?) {
      presenter.notifications.notify(
        IdeSeverity.error,
        presenter.l10n().tipsFailed(tip.title(presenter.l10n()), error),
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _retry?.cancel();
    settingsChanges?.removeListener(_settingsChanged);
    super.dispose();
  }
}
