import '../ide/ide_notifications.dart' show IdeSeverity;
import '../l10n/l10n.dart';
import '../platform/app_platform.dart';
import '../platform/context_menu.dart';
import '../platform/shell_command.dart';
import '../settings/app_settings.dart';
import '../settings/settings_dialog.dart';
import '../settings/shell_command_actions.dart';
import '../theme/codicons.dart';
import 'feature_tip.dart';

/// The ids of the app's tips, kept with what the user did with them.
abstract final class FeatureTipIds {
  static const contextMenu = 'contextMenu';
  static const shellCommand = 'shellCommand';
  static const importKeybindings = 'importKeybindings';
  static const colorTheme = 'colorTheme';
}

/// The settings.json key of the color theme (set once one is picked).
const _colorThemeSetting = 'workbench.colorTheme';

/// The features the app recommends, in the checklist's order. A new one is
/// one more entry here (its words in the .arb files).
List<FeatureTip> builtInFeatureTips(AppSettings settings) => [
  FeatureTip(
    id: FeatureTipIds.contextMenu,
    title: (l10n) => AppPlatform.isMacOS
        ? l10n.generalSettingsContextMenuFinder
        : l10n.generalSettingsContextMenuExplorer,
    body: (l10n) => l10n.tipContextMenuBody,
    icon: Codicons.listSelection,
    settings: SettingsSection.general,
    triggers: {
      TipTrigger.firstLaunch,
      TipTrigger.scenario(TipScenarios.openedFolder),
    },
    relevant: () async =>
        ContextMenu.supported &&
        await ContextMenu.status() == ContextMenuStatus.off,
    apply: (at) async {
      final l10n = at.context.l10n;
      try {
        await ContextMenu.install((
          agent: l10n.contextMenuOpenWith('BaoCode'),
          ide: l10n.contextMenuOpenWith('Fast Ide'),
        ));
      } on ContextMenuException catch (error) {
        throw TipFailure(error.message);
      }
      return true;
    },
  ),
  FeatureTip(
    id: FeatureTipIds.shellCommand,
    title: (l10n) => l10n.tipShellCommandTitle(ShellCommand.name),
    body: (l10n) => l10n.tipShellCommandBody(ShellCommand.name),
    icon: Codicons.terminal,
    settings: SettingsSection.general,
    triggers: {
      TipTrigger.firstLaunch,
      TipTrigger.scenario(TipScenarios.openedTerminal),
    },
    relevant: () async =>
        ShellCommand.supported &&
        await ShellCommand.status() == ShellCommandStatus.notInstalled,
    apply: (at) async {
      final outcome = await installShellCommand(at.context);
      if (outcome == null) return false;
      if (outcome.severity == IdeSeverity.error) {
        throw TipFailure(outcome.message);
      }
      return true;
    },
  ),
  FeatureTip(
    id: FeatureTipIds.importKeybindings,
    title: (l10n) => l10n.tipImportKeybindingsTitle,
    body: (l10n) => l10n.tipImportKeybindingsBody,
    icon: Codicons.keyboard,
    settings: SettingsSection.keyboard,
    triggers: {TipTrigger.firstLaunch},
    relevant: () async =>
        (await settings.installs?.detect())?.importable ?? false,
    apply: (at) async {
      await settings.showImport(at.context);
      return true;
    },
  ),
  FeatureTip(
    id: FeatureTipIds.colorTheme,
    title: (l10n) => l10n.appearanceSettingsColorTheme,
    body: (l10n) => l10n.tipColorThemeBody,
    icon: Codicons.symbolColor,
    settings: SettingsSection.appearance,
    triggers: {TipTrigger.firstLaunch},
    relevant: () async =>
        settings.files != null &&
        settings.files!.settings[_colorThemeSetting] == null,
    apply: (at) async {
      at.openSettings(SettingsSection.appearance);
      return true;
    },
  ),
];
