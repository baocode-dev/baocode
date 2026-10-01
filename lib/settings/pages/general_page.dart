import 'dart:async';

import 'package:flutter/material.dart';

import '../../ide/ide_button.dart';
import '../../ide/ide_menu.dart';
import '../../ide/ide_notifications.dart' show IdeSeverity;
import '../../kernel/commit_attribution.dart';
import '../../l10n/l10n.dart';
import '../../platform/shell_command.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../../workspace/main_window.dart';
import '../shell_command_actions.dart';
import '../user_settings.dart';
import 'settings_dropdown.dart';
import 'settings_widgets.dart';

/// Settings → General: the window the app opens to
/// (`workbench.mainWindow`), who the commits and pull requests agents
/// write credit (`chat.commitAttribution` in settings.json), and the
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
