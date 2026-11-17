import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../../browser/browser_bridge.dart';
import '../../browser/browser_tools.dart' show BrowserHistory;
import '../../browser/extension_store.dart';
import '../../ide/ide_button.dart';
import '../../ide/ide_dialog.dart';
import '../../l10n/l10n.dart';
import '../../theme/codicons.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../user_settings.dart';
import 'data_dir_page.dart';
import 'settings_widgets.dart';

/// Settings → Browser: whether the agents may use the user's browsers
/// (settings.json's `browser.enabled`, see [BrowserBridge.enabled]), which
/// are connected, the debugging history kept of the shared tabs (see
/// [BrowserHistory]), and the extension to get: from the Chrome Web Store,
/// or as a zip to load unpacked (see [ExtensionStore]).
class BrowserSettingsPage extends StatelessWidget {
  const BrowserSettingsPage({
    super.key,
    this.settings,
    this.browsers,
    this.history,
  });

  /// settings.json; none under test, where the choice is not kept.
  final UserSettings? settings;

  /// The bridge to the browsers; the app's by default.
  final BrowserBridge? browsers;
  BrowserBridge get bridge => browsers ?? BrowserBridge.instance;

  /// The debugging history; the app's by default.
  final BrowserHistory? history;
  BrowserHistory get kept => history ?? BrowserHistory.instance;

  void _detailed(bool on) {
    kept.detailed = on;
    final settings = this.settings;
    if (settings == null) return;
    unawaited(
      settings.update(BrowserHistory.detailedKey, on ? true : null).catchError((
        Object error,
      ) {
        debugPrint('${BrowserHistory.detailedKey} not kept: $error');
      }),
    );
  }

  /// Asks, then deletes the history.
  static Future<void> clearHistory(
    BuildContext context,
    BrowserHistory history,
  ) async {
    final l10n = context.l10n;
    final chosen = await showIdeDialog(
      context,
      message: l10n.browserHistoryClearConfirm,
      detail: l10n.browserHistoryClearDetail,
      buttons: [l10n.browserHistoryClear],
    );
    if (chosen == 0) await history.clear();
  }

  void _enable(bool on) {
    bridge.enabled = on;
    final settings = this.settings;
    if (settings == null) return;
    unawaited(
      settings.update(BrowserBridge.settingKey, on ? null : false).catchError((
        Object error,
      ) {
        // A settings file that does not parse is left as it is; its
        // error is shown.
        debugPrint('${BrowserBridge.settingKey} not kept: $error');
      }),
    );
  }

  /// Has the agents use [browser] from now on, and keeps that in
  /// settings.json ([BrowserBridge.preferredKey]).
  void _use(BrowserConnection browser) {
    final path = browser.executable;
    if (path == null) return;
    bridge.preferred = path;
    final settings = this.settings;
    if (settings == null) return;
    unawaited(
      settings.update(BrowserBridge.preferredKey, path).catchError((
        Object error,
      ) {
        debugPrint('${BrowserBridge.preferredKey} not kept: $error');
      }),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([bridge, kept]),
    builder: (context, _) => _page(context),
  );

  Widget _page(BuildContext context) {
    final l10n = context.l10n;
    final bridge = this.bridge;
    return SettingsPage(
      title: l10n.settingsSectionBrowser,
      description: l10n.browserSettingsDescription,
      children: [
        if (!bridge.supported)
          SettingsCard(
            children: [SettingsRow(label: l10n.browserSettingsUnsupported)],
          )
        else ...[
          SettingsCard(
            children: [
              SettingsSwitchRow(
                label: l10n.browserSettingsEnabled,
                description: l10n.browserSettingsEnabledDescription,
                value: bridge.enabled,
                onChanged: _enable,
              ),
            ],
          ),
          if (bridge.enabled)
            SettingsGroup(
              title: l10n.browserSettingsStatus,
              description: l10n.browserSettingsStatusDescription,
              children: [
                for (final (label, description, browser) in status(
                  l10n,
                  bridge,
                ))
                  SettingsRow(
                    label: label,
                    description: description,
                    trailing: browser == null || browser.executable == null
                        ? null
                        : IdeButton(
                            label: bridge.isActive(browser)
                                ? l10n.browserSettingsUsing
                                : l10n.browserSettingsUse,
                            secondary: true,
                            onPressed: bridge.isActive(browser)
                                ? null
                                : () => _use(browser),
                          ),
                  ),
              ],
            ),
          if (bridge.enabled)
            SettingsGroup(
              title: l10n.browserHistoryTitle,
              description: l10n.browserHistoryDescription,
              children: [
                SettingsSwitchRow(
                  label: l10n.browserHistoryDetailed,
                  description: l10n.browserHistoryDetailedDescription,
                  value: kept.detailed,
                  onChanged: _detailed,
                ),
                SettingsRow(
                  label: l10n.browserHistorySize(
                    BrowserHistory.sizeText(kept.size ?? 0),
                  ),
                  description: kept.folder,
                  trailing: SettingsButtons(
                    children: [
                      if (DataDirectoryPage.canReveal)
                        IdeButton(
                          label: l10n.revealInFileManager,
                          secondary: true,
                          onPressed: () {
                            Directory(kept.folder).createSync(recursive: true);
                            unawaited(
                              DataDirectoryPage.revealFolder(kept.folder),
                            );
                          },
                        ),
                      IdeButton(
                        label: l10n.browserHistoryClear,
                        secondary: true,
                        onPressed: (kept.size ?? 0) == 0
                            ? null
                            : () => unawaited(clearHistory(context, kept)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
        SettingsGroup(
          title: l10n.browserSettingsInstall,
          children: [
            SettingsRow(
              label: l10n.browserSettingsStore,
              description: l10n.browserSettingsStoreDescription,
              trailing: IdeButton(
                label: l10n.browserSettingsStoreOpen,
                icon: Codicons.linkExternal,
                onPressed: () => unawaited(ExtensionStore.openPage()),
              ),
            ),
            SettingsRow(
              label: l10n.browserSettingsUnpacked,
              description: l10n.browserSettingsUnpackedDescription,
              trailing: IdeButton(
                label: l10n.browserSettingsUnpackedDownload,
                icon: Codicons.cloudDownload,
                secondary: true,
                onPressed: () => unawaited(ExtensionStore.openZip()),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// What the status group says, a row each: the browsers connected (each
  /// with which it is, to choose it), the one chosen but not connected,
  /// those whose extension speaks another protocol, or why there is none.
  @visibleForTesting
  static List<(String, String?, BrowserConnection?)> status(
    AppLocalizations l10n,
    BrowserBridge bridge,
  ) {
    if (bridge.otherApp) return [(l10n.browserOtherApp, null, null)];
    final browsers = bridge.browsers;
    final mismatched = bridge.mismatched;
    if (browsers.isEmpty && mismatched.isEmpty) {
      return [
        bridge.connectedBefore
            ? (
                l10n.browserSettingsNotRunning,
                l10n.browserSettingsNotRunningDescription,
                null,
              )
            : (
                l10n.browserSettingsNotInstalled,
                l10n.browserSettingsNotInstalledDescription,
                null,
              ),
        if (bridge.sandboxedBrowsers)
          (
            l10n.browserSettingsSandboxed,
            l10n.browserSettingsSandboxedDescription,
            null,
          ),
      ];
    }
    return [
      for (final browser in browsers)
        (
          l10n.browserSettingsConnected(browser.displayName),
          _details(browser, l10n),
          browser,
        ),
      if (bridge.preferred case final path?
          when bridge.chosen == null && bridge.active != null)
        (
          l10n.browserSettingsChosenMissing,
          l10n.browserSettingsChosenMissingDescription(
            path,
            bridge.active!.displayName,
          ),
          null,
        ),
      for (final browser in browsers)
        if (browser.fileAccess == false)
          (
            l10n.browserSettingsNoFileAccess,
            '${browser.displayName}: '
                '${l10n.browserSettingsNoFileAccessDescription}',
            null,
          ),
      for (final browser in mismatched)
        (
          l10n.browserSettingsIncompatible(browser.displayName),
          browser.protocol < BrowserBridge.protocol
              ? l10n.browserSettingsExtensionOld
              : l10n.browserSettingsAppOld,
          null,
        ),
    ];
  }

  /// A connected browser's row under its name: its engine, its executable
  /// and its extension's version, ` · ` between.
  static String _details(BrowserConnection browser, AppLocalizations l10n) => [
    ?browser.engine,
    ?browser.executable,
    l10n.browserSettingsExtensionVersion(browser.version ?? '?'),
  ].join(' · ');
}

/// Said above every settings page while the debugging history is over
/// [BrowserHistory.warnSize]: how much it takes, to clear it, or to open
/// [open] (Settings → Browser).
class BrowserHistoryNotice extends StatelessWidget {
  const BrowserHistoryNotice({super.key, required this.open, this.history});

  final VoidCallback open;

  /// The debugging history; the app's by default.
  final BrowserHistory? history;

  @override
  Widget build(BuildContext context) {
    final kept = history ?? BrowserHistory.instance;
    return ListenableBuilder(
      listenable: kept,
      builder: (context, _) {
        if (!kept.tooLarge) return const SizedBox.shrink();
        final l10n = context.l10n;
        final colors = themeColors;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
            decoration: BoxDecoration(
              color: colors['inputValidation.warningBackground'],
              border: Border.all(
                color: colors['inputValidation.warningBorder'],
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Icon(
                  Codicons.warning,
                  size: 14,
                  color: colors['editorWarning.foreground'],
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.browserHistoryTooLarge(
                          BrowserHistory.sizeText(kept.size ?? 0),
                        ),
                        style: TextStyle(
                          color: colors['foreground'],
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        l10n.browserHistoryTooLargeDetail,
                        style: TextStyle(
                          color: colors['descriptionForeground'],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                IdeButton(
                  label: l10n.browserHistoryOpenSettings,
                  secondary: true,
                  onPressed: open,
                ),
                const SizedBox(width: 6),
                IdeButton(
                  label: l10n.browserHistoryClear,
                  onPressed: () => unawaited(
                    BrowserSettingsPage.clearHistory(context, kept),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
