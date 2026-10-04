import 'package:baocode/ide/ide_notifications.dart';
import 'package:baocode/l10n/l10n.dart';
import 'package:baocode/tips/feature_tip.dart';
import 'package:baocode/tips/feature_tips_controller.dart';
import 'package:baocode/update/version.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The app's storage, in memory: what a launch leaves for the next.
class _Storage implements TipStorage {
  final Map<String, Object?> values = {};

  @override
  Object? get(String key) => values[key];

  @override
  Future<void> set(String key, Object? value) async {
    if (value == null) {
      values.remove(key);
    } else {
      // As JSON keeps it: a copy, not the map the controller holds.
      values[key] = _copy(value);
    }
  }

  static Object? _copy(Object? value) => switch (value) {
    final Map<Object?, Object?> map => {
      for (final MapEntry(:key, :value) in map.entries) key: _copy(value),
    },
    _ => value,
  };
}

/// A feature of the test's: on or not, as [on] says; turned on by its tip.
class _Feature {
  _Feature(
    this.id, {
    this.supported = true,
    this.since,
    Set<TipTrigger>? triggers,
  }) : triggers = triggers ?? {TipTrigger.firstLaunch};

  final String id;
  final bool supported;
  final String? since;
  final Set<TipTrigger> triggers;
  bool on = false;
  int applied = 0;

  late final FeatureTip tip = FeatureTip(
    id: id,
    title: (_) => 'Title $id',
    body: (_) => 'Body $id',
    icon: const IconData(0),
    since: since,
    triggers: triggers,
    relevant: () async => supported && !on,
    apply: (_) async {
      applied++;
      on = true;
      return true;
    },
  );
}

void main() {
  late _Storage storage;
  late IdeNotifications notifications;
  var busy = false;

  setUp(() {
    storage = _Storage();
    notifications = IdeNotifications();
    busy = false;
  });
  tearDown(() => notifications.dispose());

  FeatureTipsController controller(
    List<_Feature> features, {
    String version = '1.0.0',
    bool enabled = true,
  }) => FeatureTipsController(
    tips: [for (final feature in features) feature.tip],
    storage: storage,
    enabled: () => enabled,
    version: AppVersion.parse(version),
  );

  TipsPresenter presenter() => TipsPresenter(
    notifications: notifications,
    l10n: () => englishLocalizations,
    context: () => null,
    busy: () => busy,
  );

  /// A launch: a controller of its own over the same storage, started.
  Future<FeatureTipsController> launch(
    List<_Feature> features, {
    String version = '1.0.0',
    bool enabled = true,
  }) async {
    final tips = controller(features, version: version, enabled: enabled);
    addTearDown(tips.dispose);
    await tips.start();
    return tips;
  }

  group('the checklist', () {
    test(
      'lists the first launch\'s tips that are relevant, in order',
      () async {
        final a = _Feature('a');
        final unsupported = _Feature('unsupported', supported: false);
        final on = _Feature('on')..on = true;
        final later = _Feature('later', triggers: {TipTrigger.scenario('x')});
        final tips = await launch([a, unsupported, on, later]);
        expect(tips.checklist.map((tip) => tip.id), ['a']);
        expect(tips.cardVisible, isTrue);
        expect(tips.entryVisible, isFalse);
      },
    );

    test(
      'what is done, closed or hidden is kept for the next launch',
      () async {
        final a = _Feature('a');
        final b = _Feature('b');
        final c = _Feature('c');
        var tips = await launch([a, b, c]);
        final context = TipContext(_NoContext(), openSettings: (_) {});
        expect(await tips.accept(a.tip, context), isTrue);
        expect(a.applied, 1);
        await tips.dismiss(b.tip);
        expect(tips.checklist.map((tip) => tip.id), ['a', 'c']);
        expect(tips.isDone(a.tip), isTrue);
        expect(tips.doneCount, 1);

        tips = await launch([a, b, c]);
        // Turned on, it stays listed, ticked; closed, it is gone.
        expect(tips.checklist.map((tip) => tip.id), ['a', 'c']);
        expect(tips.isDone(a.tip), isTrue);
        expect(tips.stateOf(b.tip), TipState.dismissed);
        expect(tips.cardVisible, isTrue);

        await tips.collapse();
        expect(tips.cardVisible, isFalse);
        expect(tips.entryVisible, isTrue);
        tips = await launch([a, b, c]);
        expect(tips.cardVisible, isFalse);
        expect(tips.entryVisible, isTrue);
      },
    );

    test('let be for three launches, it folds into the sidebar\'s entry at '
        'the fourth', () async {
      final a = _Feature('a');
      for (var i = 0; i < FeatureTipsController.idleLaunchesToCollapse; i++) {
        final tips = await launch([a]);
        expect(tips.cardVisible, isTrue, reason: 'launch ${i + 1}');
      }
      final tips = await launch([a]);
      expect(tips.cardVisible, isFalse);
      expect(tips.entryVisible, isTrue);
    });

    test('something done counts the launches from nothing again', () async {
      final a = _Feature('a');
      final b = _Feature('b');
      await launch([a, b]);
      final tips = await launch([a, b]);
      await tips.dismiss(b.tip);
      for (var i = 0; i < FeatureTipsController.idleLaunchesToCollapse; i++) {
        expect((await launch([a, b])).cardVisible, isTrue);
      }
      expect((await launch([a, b])).cardVisible, isFalse);
    });

    test('all done, it folds', () async {
      final a = _Feature('a');
      final tips = await launch([a]);
      await tips.accept(a.tip, TipContext(_NoContext(), openSettings: (_) {}));
      expect(tips.cardVisible, isFalse);
      expect(tips.entryVisible, isTrue);
      expect(tips.doneCount, 1);
    });

    test('restored (Show Setup Guide), the card is back with what was '
        'closed', () async {
      final a = _Feature('a');
      final b = _Feature('b');
      final tips = await launch([a, b]);
      await tips.dismiss(b.tip);
      await tips.collapse();
      await tips.restore();
      expect(tips.cardVisible, isTrue);
      expect(tips.checklist.map((tip) => tip.id), ['a', 'b']);
    });

    test('a failure is kept to show under the tip, nothing marked', () async {
      final tip = FeatureTip(
        id: 'fails',
        title: (_) => 'Fails',
        body: (_) => '',
        icon: const IconData(0),
        triggers: {TipTrigger.firstLaunch},
        relevant: () async => true,
        apply: (_) async => throw const TipFailure('Access is denied.'),
      );
      final tips = FeatureTipsController(tips: [tip], storage: storage);
      addTearDown(tips.dispose);
      await tips.start();
      expect(
        await tips.accept(tip, TipContext(_NoContext(), openSettings: (_) {})),
        isFalse,
      );
      expect(tips.errors['fails'], 'Access is denied.');
      expect(tips.stateOf(tip), isNull);
    });
  });

  group('scenarios', () {
    final scenario = TipTrigger.scenario(TipScenarios.openedTerminal);

    test('one notification a launch at most; not again once shown', () async {
      final a = _Feature('a', triggers: {scenario});
      final b = _Feature('b', triggers: {scenario});
      var tips = await launch([a, b]);
      tips.attach(presenter());
      await tips.scenario(TipScenarios.openedTerminal);
      await tips.scenario(TipScenarios.openedTerminal);
      expect(notifications.notifications, hasLength(1));
      expect(notifications.notifications.single.message, 'Title a: Body a');
      expect(tips.stateOf(a.tip), TipState.seen);

      // The next launch: b's turn, a's never again.
      tips = await launch([a, b]);
      tips.attach(presenter());
      await tips.scenario(TipScenarios.openedTerminal);
      expect(notifications.notifications.first.message, 'Title b: Body b');
      expect(notifications.notifications, hasLength(2));
    });

    test('put off while an agent answers or the user types', () async {
      const delay = Duration(milliseconds: 10);
      final a = _Feature('a', triggers: {scenario});
      final tips = FeatureTipsController(
        tips: [a.tip],
        storage: storage,
        retryDelay: delay,
      );
      addTearDown(tips.dispose);
      await tips.start();
      tips.attach(presenter());
      busy = true;
      await tips.scenario(TipScenarios.openedTerminal);
      await Future<void>.delayed(delay * 5);
      expect(notifications.notifications, isEmpty);
      busy = false;
      await Future<void>.delayed(delay * 3);
      expect(notifications.notifications, hasLength(1));
    });

    test('"Don\'t Show Again", or closed: never offered again', () async {
      final a = _Feature('a', triggers: {scenario, TipTrigger.firstLaunch});
      final tips = await launch([a]);
      tips.attach(presenter());
      await tips.scenario(TipScenarios.openedTerminal);
      final note = notifications.notifications.single;
      expect(note.primary.map((action) => action.label), [
        'Turn On',
        "Don't Show Again",
      ]);
      // As a toast's button does: closed, then run.
      notifications.close(note);
      note.primary.last.run();
      await pumpEventQueue();
      expect(tips.stateOf(a.tip), TipState.dismissed);
      expect(tips.checklist, isEmpty);

      final next = await launch([a]);
      next.attach(presenter());
      await next.scenario(TipScenarios.openedTerminal);
      expect(notifications.notifications, isEmpty);
    });

    test('closed by its X counts as dismissed', () async {
      final a = _Feature('a', triggers: {scenario});
      final tips = await launch([a]);
      tips.attach(presenter());
      await tips.scenario(TipScenarios.openedTerminal);
      notifications.close(notifications.notifications.single);
      await pumpEventQueue();
      expect(tips.stateOf(a.tip), TipState.dismissed);
    });

    test('a tip no longer relevant is not offered', () async {
      final a = _Feature('a', triggers: {scenario})..on = true;
      final tips = await launch([a]);
      tips.attach(presenter());
      await tips.scenario(TipScenarios.openedTerminal);
      expect(notifications.notifications, isEmpty);
    });
  });

  group('after an update', () {
    List<_Feature> features() => [
      _Feature('old', since: '1.0.0', triggers: {TipTrigger.upgrade}),
      _Feature('new', since: '1.1.0', triggers: {TipTrigger.upgrade}),
      _Feature('newer', since: '1.2.0', triggers: {TipTrigger.upgrade}),
      _Feature('future', since: '1.3.0', triggers: {TipTrigger.upgrade}),
      _Feature('none', triggers: {TipTrigger.upgrade}),
    ];

    test(
      'one notice of the tips that came after the version that ran last',
      () async {
        final all = features();
        await launch(all, version: '1.0.0');
        final tips = await launch(all, version: '1.2.0');
        tips.attach(presenter());
        final note = notifications.notifications.single;
        expect(
          note.message,
          'BaoCode was updated to 1.2.0. New: Title new, Title newer.',
        );
        expect(note.primary.map((action) => action.label), [
          'Title new',
          'Title newer',
          "Don't Show Again",
        ]);
        // And not again at the next launch.
        final next = await launch(all, version: '1.2.0');
        next.attach(presenter());
        expect(notifications.notifications, hasLength(1));
      },
    );

    test('a new install is no update', () async {
      final tips = await launch(features(), version: '1.2.0');
      tips.attach(presenter());
      expect(notifications.notifications, isEmpty);
      expect(tips.upgradeTips, isEmpty);
    });

    test('the update\'s notice is the launch\'s one notification', () async {
      final scenario = TipTrigger.scenario(TipScenarios.openedTerminal);
      final all = [
        _Feature('new', since: '1.1.0', triggers: {TipTrigger.upgrade}),
        _Feature('scene', triggers: {scenario}),
      ];
      await launch(all, version: '1.0.0');
      final tips = await launch(all, version: '1.1.0');
      tips.attach(presenter());
      await tips.scenario(TipScenarios.openedTerminal);
      expect(notifications.notifications, hasLength(1));
    });
  });

  test(
    'workbench.tips.enabled false: no card, no entry, no notification',
    () async {
      final scenario = TipTrigger.scenario(TipScenarios.openedTerminal);
      final all = [
        _Feature('a'),
        _Feature(
          'new',
          since: '1.1.0',
          triggers: {TipTrigger.upgrade, scenario},
        ),
      ];
      await launch(all, version: '1.0.0', enabled: false);
      final tips = await launch(all, version: '1.1.0', enabled: false);
      tips.attach(presenter());
      await tips.scenario(TipScenarios.openedTerminal);
      expect(tips.cardVisible, isFalse);
      expect(tips.entryVisible, isFalse);
      expect(notifications.notifications, isEmpty);
      await tips.collapse();
      expect(tips.entryVisible, isFalse);
    },
  );
}

/// A context for tips whose actions need none.
class _NoContext implements BuildContext {
  @override
  bool get mounted => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
