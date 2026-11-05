import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../ide/explorer_excludes.dart';
import '../../ide/explorer_line_count.dart';
import '../../ide/ide_button.dart';
import '../../ide/ide_menu.dart';
import '../../ide/ide_notifications.dart' show IdeSeverity;
import '../../kernel/claude_code/claude_core_setting.dart';
import '../../kernel/claude_code/claude_path_setting.dart';
import '../../kernel/commit_attribution.dart';
import '../../kernel/prompt_suggestions.dart';
import '../../chat/composer/composer_polish.dart' show ComposerPolishSetting;
import '../../chat/widgets/turn_footer.dart' show LiveTurnStatsSetting;
import '../../kernel/queued_messages.dart';
import '../../l10n/l10n.dart';
import '../../platform/app_platform.dart';
import '../../platform/context_menu.dart';
import '../../platform/shell_command.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../../tips/feature_tips_controller.dart';
import '../../tips/feature_tips_view.dart';
import '../../window/window_settings.dart';
import '../../workspace/main_window.dart';
import '../shell_command_actions.dart';
import '../user_settings.dart';
import 'settings_dropdown.dart';
import 'settings_widgets.dart';

/// Settings → General: what the app shows at launch
/// (`workbench.mainWindow`), where the IDE opens and how its windows open,
/// come back and close (`window.*`), who the commits and pull requests
/// agents write credit (`chat.commitAttribution` in settings.json), when a
/// message sent while the agent works is taken up (`chat.queuedMessages`),
/// whether the next prompt is suggested after each turn
/// (`chat.promptSuggestions`), whether the composer has its Polish button
/// (`chat.composer.polish`), whether the turn under way shows its time,
/// speed and tokens (`chat.liveTurnStats`), the Claude Code to run
/// (`claudeCode.path`),
/// the `code` shell command, and Open with BaoCode in Finder's or
/// Explorer's context menu. A choice is written at once; the default is not
/// written.
class GeneralSettingsPage extends StatelessWidget {
  const GeneralSettingsPage({
    super.key,
    this.settings,
    this.tips,
    this.claudeStatus,
  });

  /// settings.json; none under test, where choices are not kept.
  final UserSettings? settings;

  /// The Claude Code that runs now ([localClaudeStatus]); none under
  /// test and on the web, where the path is not shown.
  final Future<LocalClaudeStatus?> Function()? claudeStatus;

  /// The feature tips: those not on yet are listed first.
  final FeatureTipsController? tips;

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
    // VS Code's `default` is `off`'s, so not a choice of its own.
    final open = {
      OpenInNewWindow.off.setting: l10n.generalSettingsOpenOff,
      OpenInNewWindow.on.setting: l10n.generalSettingsOpenOn,
    };
    return [
      _choiceRow(
        context,
        key: WindowSettings.ideWindowsKey,
        label: l10n.generalSettingsIdeWindows,
        description: l10n.generalSettingsIdeWindowsDescription,
        values: {
          IdeWindows.mainWindow.name: l10n.generalSettingsIdeWindowsMain,
          IdeWindows.separate.name: l10n.generalSettingsIdeWindowsSeparate,
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
          RestoreWindows.one.name: l10n.generalSettingsRestoreOne,
          RestoreWindows.all.name: l10n.generalSettingsRestoreAll,
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
    String? fallback,
  }) {
    // A fallback given may change (e.g. as an install is found): the
    // choice is then kept as made, whichever it is.
    final keep = fallback != null;
    fallback ??= values.keys.first;
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
              onSelected: () =>
                  _write(key, !keep && value == fallback ? null : value),
            ),
        ],
      ),
    );
  }

  void _write(String key, Object? value) {
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

  /// The explorer's exclusions as a list for
  /// [IdeExplorerExcludes.settingKey]: the comma-separated patterns typed
  /// in the field, trimmed; null (the setting removed) when there are none.
  @visibleForTesting
  static List<String>? excludePatterns(String value) {
    final patterns = [
      for (final part in splitPatterns(value))
        if (part.trim().isNotEmpty) part.trim(),
    ];
    return patterns.isEmpty ? null : patterns;
  }

  /// [value] split at its commas, but not those in a glob's `{a,b}` or
  /// `[…]`: `*.{log,tmp}` is one pattern.
  @visibleForTesting
  static List<String> splitPatterns(String value) {
    final parts = <String>[];
    final part = StringBuffer();
    var braces = 0;
    var brackets = false;
    for (final char in value.split('')) {
      switch (char) {
        case '[' when !brackets:
          brackets = true;
        case ']' when brackets:
          brackets = false;
        case '{' when !brackets:
          braces++;
        case '}' when !brackets && braces > 0:
          braces--;
        case ',' when braces == 0 && !brackets:
          parts.add('$part');
          part.clear();
          continue;
      }
      part.write(char);
    }
    parts.add('$part');
    return parts;
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
            if (tips case final tips?)
              FeatureTipsSettingsList(
                controller: tips,
                builder: (context, rows) => SettingsGroup(
                  title: l10n.tipsSettingsTitle,
                  description: l10n.tipsSettingsDescription,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
                      child: Column(children: rows),
                    ),
                  ],
                ),
              ),
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
                _choiceRow(
                  context,
                  key: QueuedMessages.settingKey,
                  label: l10n.generalSettingsQueuedMessages,
                  description: l10n.generalSettingsQueuedMessagesDescription,
                  values: {
                    QueuedMessages.afterTurn.name:
                        l10n.generalSettingsQueuedAfterTurn,
                    QueuedMessages.duringTurn.name:
                        l10n.generalSettingsQueuedDuringTurn,
                  },
                ),
                SettingsSwitchRow(
                  label: l10n.generalSettingsPromptSuggestions,
                  description: l10n.generalSettingsPromptSuggestionsDescription,
                  value: PromptSuggestions.enabled(
                    settings?[PromptSuggestions.settingKey],
                  ),
                  onChanged: (on) => _write(
                    PromptSuggestions.settingKey,
                    on ? null : PromptSuggestions.off,
                  ),
                ),
                SettingsSwitchRow(
                  label: l10n.generalSettingsComposerPolish,
                  description: l10n.generalSettingsComposerPolishDescription,
                  value: ComposerPolishSetting.enabled(
                    settings?[ComposerPolishSetting.settingKey],
                  ),
                  onChanged: (on) => _write(
                    ComposerPolishSetting.settingKey,
                    on ? null : ComposerPolishSetting.off,
                  ),
                ),
                SettingsSwitchRow(
                  label: l10n.generalSettingsLiveTurnStats,
                  description: l10n.generalSettingsLiveTurnStatsDescription,
                  value: LiveTurnStatsSetting.enabled(
                    settings?[LiveTurnStatsSetting.settingKey],
                  ),
                  onChanged: (on) => _write(
                    LiveTurnStatsSetting.settingKey,
                    on ? null : LiveTurnStatsSetting.off,
                  ),
                ),
              ],
            ),
            if (claudeStatus case final claudeStatus? when !kIsWeb)
              SettingsGroup(
                title: 'Claude Code',
                children: [
                  SettingsCard(
                    children: [
                      _choiceRow(
                        context,
                        key: ClaudeCore.settingKey,
                        label: l10n.generalSettingsClaudeCore,
                        description: l10n.generalSettingsClaudeCoreDescription,
                        values: {
                          ClaudeCore.cli.name:
                              l10n.generalSettingsClaudeCoreCli,
                          ClaudeCore.builtin.name:
                              l10n.generalSettingsClaudeCoreBuiltin,
                        },
                        fallback: ClaudeCore.fallback.name,
                      ),
                      _ClaudePathSetting(
                        path: ClaudePathSetting.parse(
                          settings?[ClaudePathSetting.settingKey],
                        ),
                        status: claudeStatus,
                        onChanged: (path) => _write(
                          ClaudePathSetting.settingKey,
                          path.isEmpty ? null : path,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            SettingsGroup(
              title: l10n.generalSettingsWindows,
              children: _windowRows(context),
            ),
            SettingsGroup(
              title: l10n.generalSettingsIde,
              children: [
                SettingsCard(
                  children: [
                    SettingsRow(
                      label: l10n.explorerExcludeSetting,
                      description: l10n.explorerExcludeSettingDescription,
                      trailing: SettingsTextField(
                        value: IdeExplorerExcludes.parse(
                          settings?[IdeExplorerExcludes.settingKey],
                        ).patterns.join(', '),
                        width: 260,
                        hint: l10n.explorerExcludeSettingPlaceholder,
                        semanticLabel: l10n.explorerExcludeSetting,
                        onSubmitted: (value) => _write(
                          IdeExplorerExcludes.settingKey,
                          excludePatterns(value),
                        ),
                      ),
                    ),
                    SettingsSwitchRow(
                      label: l10n.explorerLineCountSetting,
                      description: l10n.explorerLineCountSettingDescription,
                      value: (settings?[IdeExplorerLineCount.settingEnabled] as bool?) ?? true,
                      onChanged: (on) => _write(
                        IdeExplorerLineCount.settingEnabled,
                        on ? null : false,
                      ),
                    ),
                    SettingsRow(
                      label: l10n.explorerLineCountMinLinesSetting,
                      description: l10n.explorerLineCountMinLinesSettingDescription,
                      trailing: SettingsTextField(
                        value: (settings?[IdeExplorerLineCount.settingMinLineDisplay] ?? 0).toString(),
                        width: 120,
                        hint: '0',
                        semanticLabel: l10n.explorerLineCountMinLinesSetting,
                        onSubmitted: (value) {
                          final count = int.tryParse(value.trim());
                          _write(
                            IdeExplorerLineCount.settingMinLineDisplay,
                            (count == null || count <= 0) ? null : count,
                          );
                        },
                      ),
                    ),
                    SettingsRow(
                      label: l10n.explorerLineCountMaxFileSizeSetting,
                      description: l10n.explorerLineCountMaxFileSizeSettingDescription,
                      trailing: SettingsTextField(
                        value: (settings?[IdeExplorerLineCount.settingMaxFileSize] ?? 2).toString(),
                        width: 120,
                        hint: '2',
                        semanticLabel: l10n.explorerLineCountMaxFileSizeSetting,
                        onSubmitted: (value) {
                          final mb = num.tryParse(value.trim());
                          _write(
                            IdeExplorerLineCount.settingMaxFileSize,
                            (mb == null || mb == 2) ? null : mb,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (ShellCommand.supported)
              const SettingsCard(children: [_ShellCommandSetting()]),
            if (ContextMenu.supported)
              const SettingsCard(children: [_ContextMenuSetting()]),
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

/// Whether Open with BaoCode and Open with Fast Ide are in the system's
/// context menu (see ContextMenu), and the buttons to turn them on or off
/// (and, on macOS, System Settings' extensions); what failed, under them.
class _ContextMenuSetting extends StatefulWidget {
  const _ContextMenuSetting();

  @override
  State<_ContextMenuSetting> createState() => _ContextMenuSettingState();
}

class _ContextMenuSettingState extends State<_ContextMenuSetting> {
  ContextMenuStatus? _status;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_read());
  }

  Future<void> _read() async {
    ContextMenuStatus status;
    try {
      status = await ContextMenu.status();
    } on ContextMenuException catch (error) {
      status = ContextMenuStatus.off;
      _error = error.message;
    }
    if (mounted) setState(() => _status = status);
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    String? error;
    try {
      await action();
    } on ContextMenuException catch (failure) {
      error = failure.message;
    } on Object catch (failure) {
      error = '$failure';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
    await _read();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final status = _status;
    final error = _error;
    final openSystemSettings = ContextMenu.openSystemSettings;
    final ready = !_busy && status != null;
    return SettingsRow(
      label: AppPlatform.isMacOS
          ? l10n.generalSettingsContextMenuFinder
          : l10n.generalSettingsContextMenuExplorer,
      description: [
        l10n.generalSettingsContextMenuDescription,
        if (AppPlatform.isMacOS) l10n.generalSettingsContextMenuMacNote,
      ].join(' '),
      below: [
        if (status != null)
          Text(switch (status) {
            ContextMenuStatus.on => l10n.generalSettingsContextMenuOn,
            ContextMenuStatus.off => l10n.generalSettingsContextMenuOff,
            ContextMenuStatus.unsupported =>
              l10n.generalSettingsContextMenuUnsupported,
          }, style: SettingsText.description),
        if (error != null)
          SelectableText(
            l10n.generalSettingsContextMenuFailed(error),
            style: SettingsText.description.copyWith(
              color: themeColors['errorForeground'],
            ),
          ),
      ],
      trailing: SettingsButtons(
        children: [
          IdeButton(
            label: l10n.generalSettingsContextMenuTurnOn,
            onPressed: ready && status == ContextMenuStatus.off
                ? () => unawaited(
                    _run(
                      () => ContextMenu.install((
                        agent: l10n.contextMenuOpenWith('BaoCode'),
                        ide: l10n.contextMenuOpenWith('Fast Ide'),
                      )),
                    ),
                  )
                : null,
          ),
          IdeButton(
            label: l10n.generalSettingsContextMenuTurnOff,
            secondary: true,
            onPressed: ready && status == ContextMenuStatus.on
                ? () => unawaited(_run(ContextMenu.uninstall))
                : null,
          ),
          if (openSystemSettings != null)
            IdeButton(
              label: l10n.generalSettingsContextMenuSystemSettings,
              secondary: true,
              onPressed: () => unawaited(openSystemSettings()),
            ),
        ],
      ),
    );
  }
}

/// The Claude Code to run: the path set (none for the newest found), and
/// under it the one that runs now, read again as the path changes.
class _ClaudePathSetting extends StatefulWidget {
  const _ClaudePathSetting({
    required this.path,
    required this.status,
    required this.onChanged,
  });

  final String? path;
  final Future<LocalClaudeStatus?> Function() status;
  final ValueChanged<String> onChanged;

  @override
  State<_ClaudePathSetting> createState() => _ClaudePathSettingState();
}

class _ClaudePathSettingState extends State<_ClaudePathSetting> {
  late Future<LocalClaudeStatus?> _status = widget.status();

  @override
  void didUpdateWidget(_ClaudePathSetting old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _status = widget.status();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SettingsRow(
      label: l10n.claudePathSetting,
      description: l10n.claudePathSettingDescription,
      below: [
        FutureBuilder(
          future: _status,
          builder: (context, snapshot) {
            final (text, failed) = switch (snapshot.data) {
              _ when snapshot.connectionState != ConnectionState.done => (
                l10n.claudePathChecking,
                false,
              ),
              LocalClaudeFound(:final version?, downloaded: true) => (
                l10n.claudePathInUseDownloaded(version),
                false,
              ),
              LocalClaudeFound(:final path, :final version?) => (
                l10n.claudePathInUse(path, version),
                false,
              ),
              LocalClaudeFound(:final path) => (
                l10n.claudePathInUseUnknown(path),
                false,
              ),
              LocalClaudeMissing() => (l10n.claudePathMissing, false),
              LocalClaudeFailed(:final message) => (message, true),
              null => ('', false),
            };
            if (text.isEmpty) return const SizedBox.shrink();
            return SelectableText(
              text,
              style: failed
                  ? SettingsText.path.copyWith(
                      color: themeColors['errorForeground'],
                    )
                  : SettingsText.path,
            );
          },
        ),
      ],
      trailing: SettingsTextField(
        value: widget.path ?? '',
        hint: l10n.claudePathSettingHint,
        semanticLabel: 'Claude Code ${l10n.claudePathSetting}',
        width: 260,
        onSubmitted: widget.onChanged,
      ),
    );
  }
}
