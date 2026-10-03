import 'dart:async';

import 'package:flutter/material.dart';

import '../../ide/ide_button.dart';
import '../../ide/ide_menu.dart';
import '../../ide/ide_notifications.dart' show IdeSeverity;
import '../../kernel/commit_attribution.dart';
import '../../l10n/l10n.dart';
import '../../platform/shell_command.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../../window/window_settings.dart';
import '../../workspace/main_window.dart';
import '../shell_command_actions.dart';
import '../user_settings.dart';
import 'settings_dropdown.dart';
import 'settings_widgets.dart';

/// Settings → General: what the app shows at launch
/// (`workbench.mainWindow`), where the IDE opens and how its windows open,
/// come back and close (`window.*`), who the commits and pull requests
/// agents write credit (`chat.commitAttribution` in settings.json), and the
/// `code` shell command. A choice is written at once; the default is not
/// written.
class GeneralSettingsPage extends StatelessWidget {
  const GeneralSettingsPage({super.key, this.settings});

  /// settings.json; none under test, where choices are not kept.
  final UserSettings? settings;

  static String attributionName(BuildContext context, CommitAttribution value) {
    final l10n = context.l10n;
    return switch (value) {
      CommitAttribution.baocode => 'BaoCode',
      CommitAttribution.agent => l10n.generalSettingsAttributionAgent,
      CommitAttribution.none => l10n.generalSettingsAttributionNone,
    };
  }

  static String _attributionDetail(
    BuildContext context,
    CommitAttribution value,
  ) {
    final l10n = context.l10n;
    return switch (value) {
      CommitAttribution.baocode => CommitAttribution.baoCodeCommit,
      CommitAttribution.agent => l10n.generalSettingsAttributionAgentDetail,
      CommitAttribution.none => l10n.generalSettingsAttributionNoneDetail,
    };
  }

  static String mainWindowName(BuildContext context, MainWindow value) {
    final l10n = context.l10n;
    return switch (value) {
      MainWindow.chat => l10n.generalSettingsMainWindowChat,
      MainWindow.ide => l10n.generalSettingsMainWindowIde,
      MainWindow.last => l10n.generalSettingsMainWindowLast,
    };
  }

  void _select(CommitAttribution value) => _write(
    CommitAttribution.settingKey,
    value == CommitAttribution.fallback ? null : value.name,
  );

  void _selectMainWindow(MainWindow value) => _write(
    MainWindow.settingKey,
    value == MainWindow.fallback ? null : value.name,
  );

  /// The `window.*` settings' rows: each its label, description, and
  /// values (the first the default) as settings.json has them and named.
  List<Widget> _windowRows(BuildContext context) {
    final l10n = context.l10n;
    final open = {
      OpenInNewWindow.defaultMode.setting: l10n.generalSettingsOpenDefault,
      OpenInNewWindow.on.setting: l10n.generalSettingsOpenOn,
      OpenInNewWindow.off.setting: l10n.generalSettingsOpenOff,
    };
    return [
      _choiceRow(
        context,
        key: WindowSettings.ideWindowsKey,
        label: l10n.generalSettingsIdeWindows,
        description: l10n.generalSettingsIdeWindowsDescription,
        values: {
          IdeWindows.separate.name: l10n.generalSettingsIdeWindowsSeparate,
          IdeWindows.mainWindow.name: l10n.generalSettingsIdeWindowsMain,
        },
      ),
      _choiceRow(
        context,
        key: WindowSettings.openFoldersKey,
        label: l10n.generalSettingsOpenFolders,
        description: l10n.generalSettingsOpenFoldersDescription,
        values: open,
      ),
      _choiceRow(
        context,
        key: WindowSettings.openFilesKey,
        label: l10n.generalSettingsOpenFiles,
        description: l10n.generalSettingsOpenFilesDescription,
        values: open,
      ),
      _choiceRow(
        context,
        key: WindowSettings.restoreWindowsKey,
        label: l10n.generalSettingsRestoreWindows,
        description: l10n.generalSettingsRestoreWindowsDescription,
        values: {
          RestoreWindows.all.name: l10n.generalSettingsRestoreAll,
          RestoreWindows.one.name: l10n.generalSettingsRestoreOne,
          RestoreWindows.folders.name: l10n.generalSettingsRestoreFolders,
          RestoreWindows.none.name: l10n.generalSettingsRestoreNone,
        },
      ),
      _choiceRow(
        context,
        key: WindowSettings.newWindowDimensionsKey,
        label: l10n.generalSettingsNewWindowDimensions,
        description: l10n.generalSettingsNewWindowDimensionsDescription,
        values: {
          NewWindowDimensions.defaultSize.setting:
              l10n.generalSettingsDimensionsDefault,
          NewWindowDimensions.inherit.setting:
              l10n.generalSettingsDimensionsInherit,
          NewWindowDimensions.maximized.setting:
              l10n.generalSettingsDimensionsMaximized,
          NewWindowDimensions.fullscreen.setting:
              l10n.generalSettingsDimensionsFullscreen,
        },
      ),
      _choiceRow(
        context,
        key: WindowSettings.confirmBeforeCloseKey,
        label: l10n.generalSettingsConfirmBeforeClose,
        description: l10n.generalSettingsConfirmBeforeCloseDescription,
        values: {
          ConfirmBeforeClose.never.name: l10n.generalSettingsConfirmNever,
          ConfirmBeforeClose.keyboardOnly.name:
              l10n.generalSettingsConfirmKeyboard,
          ConfirmBeforeClose.always.name: l10n.generalSettingsConfirmAlways,
        },
      ),
    ];
  }

  Widget _choiceRow(
    BuildContext context, {
    required String key,
    required String label,
    required String description,
    required Map<String, String> values,
  }) {
    final fallback = values.keys.first;
    final setting = settings?[key];
    final current = values.containsKey(setting) ? setting as String : fallback;
    final shown = values[current]!;
    return SettingsRow(
      label: label,
      description: description,
      trailing: SettingsDropdown(
        current: shown,
        semanticLabel: context.l10n.generalSettingsWindowLabel(label, shown),
        entries: () => [
          for (final MapEntry(key: value, value: name) in values.entries)
            IdeMenuAction(
              name,
              checked: value == current,
              onSelected: () => _write(key, value == fallback ? null : value),
            ),
        ],
      ),
    );
  }

  void _write(String key, String? value) {
    final settings = this.settings;
    if (settings == null) return;
    unawaited(
      settings.update(key, value).catchError((Object error) {
        // A settings file that does not parse is left as it is; its
        // error is shown.
        debugPrint('$key not kept: $error');
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final settings = this.settings;
    return ListenableBuilder(
      listenable: settings ?? Listenable.merge(const []),
      builder: (context, _) {
        final current = CommitAttribution.parse(
          settings?[CommitAttribution.settingKey],
        );
        final name = attributionName(context, current);
        final detail = _attributionDetail(context, current);
        final mainWindow = MainWindow.parse(settings?[MainWindow.settingKey]);
        final mainWindowShown = mainWindowName(context, mainWindow);
        return SettingsPage(
          title: l10n.generalSettingsTitle,
          children: [
            SettingsCard(
              children: [
                SettingsRow(
                  label: l10n.generalSettingsMainWindow,
                  description: l10n.generalSettingsMainWindowDescription,
                  trailing: SettingsDropdown(
                    current: mainWindowShown,
                    semanticLabel: l10n.generalSettingsMainWindowLabel(
                      mainWindowShown,
                    ),
                    entries: () => [
                      for (final value in MainWindow.values)
                        IdeMenuAction(
                          mainWindowName(context, value),
                          checked: value == mainWindow,
                          onSelected: () => _selectMainWindow(value),
                        ),
                    ],
                  ),
                ),
                SettingsRow(
                  label: l10n.generalSettingsCommitAttribution,
                  description: l10n.generalSettingsCommitAttributionDescription,
                  below: [
                    SelectableText(
                      detail,
                      style: current == CommitAttribution.baocode
                          ? SettingsText.path
                          : SettingsText.description,
                    ),
                  ],
                  trailing: SettingsDropdown(
                    current: name,
                    semanticLabel: l10n.generalSettingsCommitAttributionLabel(
                      name,
                    ),
                    entries: () => [
                      for (final value in CommitAttribution.values)
                        IdeMenuAction(
                          attributionName(context, value),
                          checked: value == current,
                          onSelected: () => _select(value),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            SettingsGroup(
              title: l10n.generalSettingsWindows,
              children: _windowRows(context),
            ),
            if (ShellCommand.supported)
              const SettingsCard(children: [_ShellCommandSetting()]),
          ],
        );
      },
    );
  }
}

/// Whether the `code` command is installed, and the buttons to install or
/// remove it; what that came to, under them.
class _ShellCommandSetting extends StatefulWidget {
  const _ShellCommandSetting();

  @override
  State<_ShellCommandSetting> createState() => _ShellCommandSettingState();
}

class _ShellCommandSettingState extends State<_ShellCommandSetting> {
  ShellCommandStatus? _status;
  bool _busy = false;
  ShellCommandOutcome? _outcome;

  @override
  void initState() {
    super.initState();
    unawaited(_read());
  }

  Future<void> _read() async {
    final status = await ShellCommand.status();
    if (mounted) setState(() => _status = status);
  }

  Future<void> _run(
    Future<ShellCommandOutcome?> Function(BuildContext) action,
  ) async {
    setState(() {
      _busy = true;
      _outcome = null;
    });
    final outcome = await action(context);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _outcome = outcome;
    });
    await _read();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final status = _status;
    final outcome = _outcome;
    return SettingsRow(
      label: l10n.generalSettingsShellCommand,
      description: l10n.generalSettingsShellCommandDescription(
        ShellCommand.location,
      ),
      below: [
        if (status != null)
          Text(switch (status) {
            ShellCommandStatus.installed =>
              l10n.generalSettingsShellCommandInstalled,
            ShellCommandStatus.occupied =>
              l10n.generalSettingsShellCommandOccupied,
            _ => l10n.generalSettingsShellCommandNotInstalled,
          }, style: SettingsText.description),
        if (outcome != null)
          SelectableText(
            outcome.message,
            style: outcome.severity == IdeSeverity.error
                ? SettingsText.description.copyWith(
                    color: themeColors['errorForeground'],
                  )
                : SettingsText.description,
          ),
      ],
      trailing: SettingsButtons(
        children: [
          IdeButton(
            label: l10n.generalSettingsShellCommandInstall,
            onPressed: _busy || status == null
                ? null
                : () => unawaited(_run(installShellCommand)),
          ),
          IdeButton(
            label: l10n.generalSettingsShellCommandUninstall,
            secondary: true,
            onPressed: _busy || status != ShellCommandStatus.installed
                ? null
                : () => unawaited(_run(uninstallShellCommand)),
          ),
        ],
      ),
    );
  }
}
