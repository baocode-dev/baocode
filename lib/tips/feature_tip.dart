import 'package:flutter/widgets.dart';

import '../l10n/l10n.dart';
import '../settings/settings_dialog.dart';

/// When a tip is offered: in the setup checklist of the first launches,
/// in the notice of an update that brought it, or as a notification when
/// what it is about happens ([TipTrigger.scenario], see [TipScenarios]).
final class TipTrigger {
  const TipTrigger._(this.kind, [this.scenario]);

  /// When [id] happens (one of [TipScenarios]).
  const TipTrigger.scenario(String id) : this._(TipTriggerKind.scenario, id);

  static const firstLaunch = TipTrigger._(TipTriggerKind.firstLaunch);
  static const upgrade = TipTrigger._(TipTriggerKind.upgrade);

  final TipTriggerKind kind;

  /// The scenario's id, for [TipTriggerKind.scenario].
  final String? scenario;

  @override
  bool operator ==(Object other) =>
      other is TipTrigger && other.kind == kind && other.scenario == scenario;

  @override
  int get hashCode => Object.hash(kind, scenario);
}

enum TipTriggerKind { firstLaunch, upgrade, scenario }

/// What the workbench tells the tips of (see FeatureTipsController.scenario).
abstract final class TipScenarios {
  /// A project opened from its folder (Open Folder…, or dropped on the
  /// window), once its agent has answered.
  static const openedFolder = 'openedFolder';

  /// The terminal panel shown.
  static const openedTerminal = 'openedTerminal';
}

/// What a tip's actions are done with: where it was accepted (for the
/// dialogs it may show), and the settings dialog to show a page of.
class TipContext {
  const TipContext(this.context, {required this.openSettings});

  /// The settings of [context]: the dialog's page when it is in the
  /// settings dialog, else the window's dialog (see [SettingsOpener]).
  factory TipContext.of(BuildContext context) {
    final dialog = context.findAncestorStateOfType<SettingsDialogState>();
    final opener = SettingsOpener.maybeOf(context);
    return TipContext(
      context,
      openSettings: (section) {
        if (dialog != null && dialog.mounted) return dialog.show(section);
        opener?.call(section);
      },
    );
  }

  final BuildContext context;
  final void Function(SettingsSection section) openSettings;
}

/// One feature the app recommends (see FeatureTipsController): what it
/// says, whether it is worth saying here and now, and how to turn it on
/// in one go. A new feature to recommend is one more of these in
/// builtInFeatureTips.
class FeatureTip {
  const FeatureTip({
    required this.id,
    required this.title,
    required this.body,
    required this.icon,
    required this.relevant,
    required this.apply,
    this.since,
    this.settings,
    this.triggers = const {},
  });

  /// Kept with what the user did with it: stable once shipped.
  final String id;

  final String Function(AppLocalizations l10n) title;
  final String Function(AppLocalizations l10n) body;
  final IconData icon;

  /// The version the feature came in (`1.2.0`): an update past it says so
  /// (see [TipTrigger.upgrade]). Null for one that came before tips.
  final String? since;

  /// Whether the feature is on this platform and not on yet.
  final Future<bool> Function() relevant;

  /// Turns it on; true once it is (false: the user said no to a dialog of
  /// it). Throws with what went wrong, in words to show.
  final Future<bool> Function(TipContext context) apply;

  /// The settings page it is on, for "Settings" beside it.
  final SettingsSection? settings;

  final Set<TipTrigger> triggers;
}

/// Where the tips keep what the user did with them: the app's global
/// storage (see AppSettings).
abstract interface class TipStorage {
  Object? get(String key);

  Future<void> set(String key, Object? value);
}

/// Why a tip could not turn its feature on, in words to show.
class TipFailure implements Exception {
  const TipFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
