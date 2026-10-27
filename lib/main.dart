import 'dart:async';
import 'dart:ui' show AppExitResponse, AppExitType;

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show ServicesBinding;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path/path.dart' as p;
import 'package:bao_editor/textmate/textmate_syntax.dart';

import 'package:bao_editor/monaco/flutter/language_assets.dart';

import 'base/quiet_view.dart';
import 'base/smooth_scroll.dart' show BaoScrollBehavior;
import 'browser/browser_bridge.dart';
import 'browser/browser_tools.dart' show BrowserHistory;
import 'chat/composer/composer_files.dart' show ComposerFile, pastedAsPicture;
import 'chat/chat_width.dart';
import 'chat/reply_scroll.dart';
import 'chat/user_message_style.dart';
import 'chat/widgets/chat_minimap.dart';
import 'chat/widgets/pixel_loader.dart';
import 'chat/resume_after_reset.dart';
import 'chat/widgets/turn_footer.dart' show LiveTurnStatsSetting;
import 'customize/customization_store.dart';
import 'diagnostics/app_event_watch.dart';
import 'diagnostics/frame_watch.dart';
import 'diagnostics/diagnostics_upload.dart';
import 'extensions/theme_extensions.dart';
import 'ide/editor_word_wrap.dart';
import 'ide/git/git_repository.dart';
import 'ide/git/repository_scan.dart';
import 'ide/language_mode.dart';
import 'ide/lsp/language_features.dart';
import 'ide/lsp/lsp_process.dart';
import 'ide/lsp/packs/language_packs.dart';
import 'ide/terminal/pty.dart';
import 'ide/terminal/terminal_colors.dart';
import 'ide/terminal/terminal_instance.dart';
import 'icons/emoji_sheet.dart';
import 'icons/icon_library.dart';
import 'icons/icon_storage.dart';
import 'icons/site_icons.dart';
import 'kernel/claude_code/claude_code_kernel.dart';
import 'kernel/claude_code/claude_core_setting.dart';
import 'kernel/claude_code/claude_onboarding.dart';
import 'kernel/claude_code/claude_path_setting.dart';
import 'kernel/claude_code/process_transport.dart';
import 'kernel/claude_code/turn_stats_stub.dart'
    if (dart.library.io) 'kernel/claude_code/turn_stats_io.dart'
    show turnStatsIn;
import 'kernel/commit_attribution.dart';
import 'kernel/prompt_suggestions.dart';
import 'chat/composer/composer_polish.dart' show ComposerPolishSetting;
import 'kernel/queued_messages.dart';
import 'keybindings/keybindings_sync.dart';
import 'link/link_host.dart';
import 'keybindings/keymap.dart';
import 'keybindings/vscode_import.dart';
import 'l10n/l10n.dart';
import 'models/featured_upstreams.dart';
import 'models/model_icons.dart';
import 'models/model_providers.dart';
import 'models/model_runtime.dart';
import 'models/model_welcome.dart';
import 'network/network_proxy.dart';
import 'notifications/attention_host.dart';
import 'notifications/attention_settings.dart';
import 'platform/memory_budget.dart';
import 'platform/app_platform.dart';
import 'platform/data_dir.dart';
import 'platform/error_log.dart';
import 'platform/event_log.dart';
import 'platform/open_requests.dart';
import 'platform/shell_command.dart';
import 'remote/project_host.dart';
import 'remote/remote_claude.dart';
import 'remote/ssh_host.dart';
import 'search/claude_conversation_search.dart';
import 'search/conversation_search.dart';
import 'channel/account/account_send.dart';
import 'channel/account/channel_account.dart';
import 'channel/channel_gate.dart';
import 'channel/channel_setup.dart';
import 'channel/channel_setup_platform.dart';
import 'settings/app_locale.dart';
import 'settings/app_settings.dart';
import 'settings/data_dir_startup.dart';
import 'settings/user_settings.dart';
import 'sidebar/sidebar_times.dart';
import 'telemetry/telemetry_platform.dart';
import 'stash/stash_editor.dart' show StashEditor;
import 'forge/forge_accounts.dart';
import 'forge/forge_io_stub.dart'
    if (dart.library.io) 'forge/forge_io.dart'
    show IoForgeHttp;
import 'stash/stash_controller.dart';
import 'stash/stash_forge.dart';
import 'stash/stash_disk.dart';
import 'stash/stash_panel_view.dart';
import 'stash/stash_settings.dart';
import 'stash/stash_store.dart';
import 'telemetry/telemetry_service.dart';
import 'telemetry/telemetry_store.dart';
import 'theme/app_theme.dart';
import 'theme/code_font.dart';
import 'theme/pixel_snapped_text_scaler.dart';
import 'theme/ui_zoom.dart';
import 'theme/window_blur.dart';
import 'theme/workbench_theme.dart';
import 'update/update_controller.dart';
import 'update/update_platform.dart';
import 'update/update_service.dart';
import 'update/update_settings.dart';
import 'update/update_store.dart';
import 'update/version.dart';
import 'window/app_windows.dart';
import 'window/code_args.dart';
import 'window/window_host.dart';
import 'window/window_settings.dart';
import 'workbench.dart';
import 'workspace/editor_launcher.dart';
import 'workspace/agent_title.dart';
import 'workspace/main_window.dart';
import 'workspace/preference_store.dart';
import 'workspace/window_controls.dart';
import 'workspace/workspace.dart';

Future<void> main(List<String> arguments) async {
  // All the app keeps is in its data folder: found first, once. One the
  // user set that cannot be used (a drive gone) is reported before the app
  // shows, never swapped for the default unasked.
  ErrorLog? errors;
  if (!kIsWeb) {
    final resolution = resolveDataDirectory();
    if (resolution.ok) {
      DataDirectory.current = resolution.directory;
    } else {
      WidgetsFlutterBinding.ensureInitialized();
      DataDirectory.current = await recoverDataDirectory(resolution);
    }
    // What goes wrong unseen from here on, kept for the user to send.
    errors = ErrorLog(DataDirectory.current.logsDir)..install();
    // And what the app went through, to read what led to it.
    EventLog.current = EventLog(DataDirectory.current.logsDir);
  }
  unawaited(reapClaudeProcesses());
  unawaited(reapLspProcesses());
  unawaited(reapPtyProcesses());
  WidgetsFlutterBinding.ensureInitialized();
  MemoryBudget.apply();
  if (!kIsWeb) {
    AppEventWatch.start();
    FrameWatch.start();
  }
  // The Windows app's own logs go beside it.
  if (errors != null) unawaited(errors.shareWithHost());
  // The editor's language packs are the language servers' (README.md in
  // lib/ide/lsp/packs).
  MonacoLanguageAssets.defaultPacks = () => LanguagePackRegistry.instance;
  // The user's settings files ([SettingsFiles.instance]): read before the
  // first frame, which is in their language and theme, and followed as
  // they change on disk.
  final files = kIsWeb ? null : SettingsFiles.instance;
  await files?.load();
  if (files != null) keepLanguageModes(files.storage);
  files?.watch();
  if (files != null) {
    // Settings → Network: the proxy every request and Claude Code go
    // through, the system's by default; read before the first request.
    await startNetworkProxy(
      files.settings,
      (key) => files.settings[key],
    ).timeout(const Duration(seconds: 1), onTimeout: () {});
    // Read as each agent starts.
    CommitAttribution.current = () =>
        CommitAttribution.parse(files.settings[CommitAttribution.settingKey]);
    // Read as each message is sent.
    QueuedMessages.current = () =>
        QueuedMessages.parse(files.settings[QueuedMessages.settingKey]);
    // Read as each agent starts, and as each message is sent.
    PromptSuggestions.current = () =>
        PromptSuggestions.enabled(files.settings[PromptSuggestions.settingKey]);
    // The composer's Polish button, shown or not as it changes.
    ComposerPolishSetting.current = () => ComposerPolishSetting.enabled(
      files.settings[ComposerPolishSetting.settingKey],
    );
    ComposerPolishSetting.changes = files.settings;
    // The turn under way's line of figures, shown or not as it changes.
    LiveTurnStatsSetting.current = () => LiveTurnStatsSetting.enabled(
      files.settings[LiveTurnStatsSetting.settingKey],
    );
    LiveTurnStatsSetting.changes = files.settings;
    // An agent stopped at the usage limit: whether it goes on once it
    // resets, set in the model picker.
    ResumeAfterResetSetting.current = () => ResumeAfterResetSetting.enabled(
      files.settings[ResumeAfterResetSetting.settingKey],
    );
    ResumeAfterResetSetting.changes = files.settings;
    ResumeAfterResetSetting.write = (on) => unawaited(
      files.settings
          .update(
            ResumeAfterResetSetting.settingKey,
            on ? ResumeAfterResetSetting.on : null,
          )
          .catchError((Object error) {
            // A settings file that does not parse is left as it is; its
            // error is shown.
            debugPrint(
              '${ResumeAfterResetSetting.settingKey} not kept: $error',
            );
          }),
    );
    // Settings → General → Claude Code: the build to run, read as each
    // agent starts.
    ClaudePathSetting.current = () =>
        ClaudePathSetting.parse(files.settings[ClaudePathSetting.settingKey]);
    // Settings → General → Claude Code: the core sessions run on (BaoCode's
    // own, or the CLI), read as each agent starts. Unset, the CLI where it
    // is installed (looked for on the app's PATH, then the shell's), else
    // the built-in core, which suggests the CLI.
    ClaudeCore.cliInstalled = localClaudeInstalled;
    unawaited(lookForLocalClaude());
    ClaudeCore.current = () =>
        ClaudeCore.parse(files.settings[ClaudeCore.settingKey]);
    ClaudeCore.changes = files.settings;
    ClaudeCore.pick = (core) =>
        files.settings.update(ClaudeCore.settingKey, core.name);
    // Settings → Models: the upstreams, kept in settings.json.
    ModelProviders.current = ModelProviders.settings(files.settings);
    // Claude Code's own models as it last listed them: in the picker
    // before a session on them starts.
    ClaudeCodeKernel.modelCache = files.storage;
    // Whether the welcome to setting a model up has shown by itself.
    ModelWelcome.storage = files.storage;
    // The channel build's first start: set up before anything else shows.
    await _beginChannelSetup(files);
    _openChannelGate(files);
    // What each turn took and spent, for its footer when the session is
    // opened again: in the data folder, a file per session.
    ClaudeCodeKernel.turnStats = turnStatsIn(
      p.join(DataDirectory.current.path, 'turn-stats'),
    );
    // The upstreams' sites' icons, for those that show no other: in the
    // cache, fetched as soon as one is added.
    SiteIcons.current = SiteIcons(
      library: IconLibrary(
        storage: IconStorage.directory(
          p.join(DataDirectory.current.cacheDir, 'site-icons'),
        ),
      ),
    );
    prefetchProviderIcons(ModelProviders.current, SiteIcons.current);
    // The logos of the sites listed, for their upstreams' icons, as kept
    // last time (Settings → Models gets the list again).
    unawaited(FeaturedUpstream.readKept());
    // Settings → Appearance: how wide the conversation grows.
    ChatWidth.follow(
      files.settings,
      () => files.settings[ChatWidth.settingKey],
    );
    // Settings → Appearance: how the user's messages show.
    UserMessageStyle.follow(
      files.settings,
      () => files.settings[UserMessageStyle.settingKey],
    );
    // Settings → Appearance: where a conversation stays as a reply comes.
    ReplyScroll.keep(
      files.settings,
      () => files.settings[ReplyScroll.settingKey],
    );
    // Settings → Appearance: whether the conversation has a minimap, how
    // opaque its glass is and how much it stretches.
    ChatMinimap.follow(files.settings, (key) => files.settings[key]);
    // Settings → Appearance: what an agent and a subagent show running.
    PixelLoaderRole.follow(files.settings, (key) => files.settings[key]);
    // Settings → Appearance: whether the windows are blurred underneath.
    WindowBlur.follow(
      files.settings,
      () => files.settings[WindowBlur.settingKey],
    );
    // Settings → Appearance: whether the sidebar's agents show their times.
    SidebarTimes.follow(
      files.settings,
      () => files.settings[SidebarTimes.settingKey],
    );
    // Settings → Browser: whether the agents may use the user's browsers.
    BrowserBridge.instance.follow(
      files.settings,
      () => files.settings[BrowserBridge.settingKey],
    );
    // Settings → Browser: whether the history keeps bodies and steps too.
    BrowserHistory.instance.follow(
      files.settings,
      () => files.settings[BrowserHistory.detailedKey],
    );
    // Settings → Appearance: the code's font, size and ligatures, and the
    // window's text size.
    CodeFont.follow(files.settings, (key) => files.settings[key]);
    // Whether the editors wrap long lines.
    EditorWordWrap.follow(files.settings);
  }
  // Emoji as pictures: fetched into the cache the first run, in the
  // background, through the proxy.
  EmojiSheet.start(EmojiSheetStore.cache());
  await prepareClaudeOnboarding();
  final locale = AppLocale(storage: files?.argv);
  // The agents to go on once the usage limit resets, kept beside
  // state.json: one due while the app was closed goes on as it opens.
  if (!kIsWeb) {
    ResumeAfterReset.current = ResumeAfterReset(
      store: PreferenceStore.file(
        p.join(DataDirectory.current.stateDir, ResumeAfterReset.fileName),
      ),
    );
    unawaited(ResumeAfterReset.current.load());
  }
  final workspace = Workspace(
    preferences: PreferenceStore.file(),
    // Beside state.json: written as the user types.
    drafts: kIsWeb
        ? null
        : PreferenceStore.file(
            p.join(DataDirectory.current.stateDir, 'drafts.json'),
          ),
    // The data folder's icons/, the upstreams of models' pictures too.
    icons: IconLibrary.current = IconLibrary(storage: IconStorage.directory()),
    titler: claudeAgentTitle,
    l10n: () =>
        lookupAppLocalizations(locale.locale ?? AppLocale.systemLocale()),
  )..load();
  // Claude Code's skills, agents, commands, rules, servers, hooks and
  // plugins: the Customize view beside the chat, and Settings → Customize.
  final customizations = CustomizationStore();
  // The phones paired with this computer (Settings → Mobile): listening
  // for them, if they are allowed to connect.
  final link = kIsWeb
      ? null
      : LinkHost(workspace: workspace, customizations: customizations);
  unawaited(link?.load());
  // The first frame is in the kept theme, restored from storage as VS Code
  // does before the workbench shows; its file is read after. The setting
  // is settings.json's `workbench.colorTheme`, the theme's colors the
  // workspace's state.
  await workspace.restored;
  // The app's windows: the chat's, and the IDE's own, one per folder,
  // where the system can open them (see lib/window/).
  final windows = AppWindows(
    host: ChannelWindowHost(),
    workspace: workspace,
    l10n: () =>
        lookupAppLocalizations(locale.locale ?? AppLocale.systemLocale()),
    store: kIsWeb
        ? null
        : PreferenceStore.file(
            p.join(DataDirectory.current.stateDir, AppWindows.fileName),
          ),
    settings: () => WindowSettings.parse(files?.settings.values ?? const {}),
    mainWindow: () => MainWindow.parse(files?.settings[MainWindow.settingKey]),
    updateSetting: files == null
        ? null
        : (key, value) => unawaited(
            files.settings
                .update(key, value)
                .catchError((Object error) => debugPrint('$key: $error')),
          ),
    hasTray: () =>
        AttentionSettings.parse(files?.settings.values ?? const {}).tray,
  );
  await windows.start();
  // The stash (docs/stash.md): its shortcut works from any app, its panel
  // made hidden a moment after the windows, to show at once.
  if (files != null) {
    final store = StashStore.current = StashStore(
      StashDisk.files(StashSettings.parse(files.settings.values).directory),
    );
    // Its pictures, copied out of it, go into a message as pictures.
    pastedAsPicture = (path) =>
        p.isWithin(store.root, path) && ComposerFile(path).maybeImage;
    // Its code blocks in the editor's colors, by TextMate (started as the
    // first is shown).
    TextMateSyntax? stashSyntax;
    StashEditor.colorize = (language, code) => (stashSyntax ??= TextMateSyntax(
      themes: WorkbenchThemeService.instance,
    )).colorize(language, code);
    final stash = StashController.current = StashController(
      store: store,
      workspace: workspace,
      windows: windows,
      settings: () => files.settings.values,
      updateSetting: files.settings.update,
      settingsChanges: files.settings,
      cacheDir: DataDirectory.current.cacheDir,
      storage: files.storage,
      // Claude Code's skills are the installed app's: a build run from the
      // source, often on a data folder of its own (`BAOCODE_DATA_DIR`),
      // would point the user's agents at its stashes.
      installSkill: !kDebugMode,
      // The user's GitHub and GitLab accounts: their tokens in the
      // keychain, the rest in the global storage.
      accounts: ForgeAccounts.current = ForgeAccounts(
        http: IoForgeHttp(),
        read: () => files.storage.get<List<Object?>>(forgeAccountsKey),
        write: (json) => files.storage.set(forgeAccountsKey, json),
      ),
    );
    StashForge.current = stash.forge;
    unawaited(stash.start());
  }
  // What shows at launch (settings.json's `workbench.mainWindow`): with
  // windows of the IDE's own, the chat's and those to open again; with
  // the IDE in the main window, its layout. Started for something (Open
  // with BaoCode or Fast Ide, the `code` command), that alone.
  final request = AppPlatform.isMacOS
      ? await OpenRequests.launchRequest()
      : LaunchRequest.of(arguments);
  await windows.prepareLaunch(request: request);
  if (request == LaunchRequest.agent) {
    // In a window of its own; without them, in the main window's chat.
    if (!windows.started) workspace.layout = WorkspaceLayout.chat;
  } else if (files != null && !windows.multi) {
    workspace.layout = MainWindow.parse(files.settings[MainWindow.settingKey])
        .layoutAtLaunch(workspace.layout);
  }
  WindowControls.trackActiveView();
  // An older `code` script opened windows for `code --version`.
  unawaited(ShellCommand.refresh());
  final ColorThemeStorage colorTheme = files == null
      ? workspace
      : ColorThemeSettings(settings: files.settings, state: workspace);
  final themes = WorkbenchThemeService.instance
    ..restore(
      setting: colorTheme.colorThemeSetting,
      data: colorTheme.colorThemeData,
    )
    ..storage = colorTheme
    // A theme of an extension applies once they are read.
    ..waitsForExtensionThemes = files != null;
  if (colorTheme is ColorThemeSettings) colorTheme.follow(themes);
  unawaited(themes.initialize());
  // The keybindings: keybindings.json and the selected keymap, in effect
  // from the first frame and followed as they change.
  AppSettings? settings;
  if (files != null) {
    final catalog = KeymapCatalog(keymapsDir: DataDirectory.current.keymapsDir);
    final sync = KeybindingsSync(
      keybindings: files.keybindings,
      settings: files.settings,
      catalog: catalog,
    )..start();
    await sync.ready;
    settings = AppSettings(
      locale: locale,
      files: files,
      catalog: catalog,
      sync: sync,
      installs: VsCodeInstalls.current(),
      updates: _startUpdates(files),
      diagnostics: DiagnosticsUploader.platform(),
      workspace: workspace,
      claudeStatus: localClaudeStatus,
      link: link,
      customizations: customizations,
    );
    _startTelemetry(files);
  }
  // The theme extensions (lib/extensions/): color and file icon themes
  // from Open VSX or a .vsix, `workbench.iconTheme` followed as
  // settings.json changes.
  final themeExtensions = files == null
      ? null
      : ThemeExtensions.inDataDirectory(
          DataDirectory.current.path,
          locale:
              locale.setting ??
              switch (WidgetsBinding.instance.platformDispatcher.locale) {
                Locale(languageCode: 'zh') => AppLocale.simplifiedChinese,
                _ => AppLocale.english,
              },
        );
  if (themeExtensions != null) {
    unawaited(themeExtensions.apply());
    themeExtensions.followIconThemeSetting(files!.settings);
  }
  final app = BaoCodeApp(
    windows: windows,
    workspace: workspace,
    appLocale: locale,
    settings: settings,
    themeExtensions: themeExtensions,
    // On the folder's host: this machine, or a remote one's.
    languagesFor: (folder) {
      final host = ProjectHost.of(folder);
      return host.languages(host.pathOf(folder));
    },
    gitFor: (folder) {
      final host = ProjectHost.of(folder);
      return host.git(host.pathOf(folder));
    },
    repositoriesIn: (folder, scan) {
      final host = ProjectHost.of(folder);
      return host.repositoriesIn(host.pathOf(folder), scan);
    },
    // The default profile and the user's profiles are settings.json's.
    terminalBackend: TerminalBackend(settings: files?.settings),
    // What Claude Code keeps: its sessions to search, its skills, agents,
    // commands, rules, servers, hooks and plugins to customize.
    conversations: ClaudeConversationSearch(),
    customizations: customizations,
  );
  // With windows, each is a view of its own (see [BaoCodeApp.build]).
  if (windows.started) {
    runWidget(app);
  } else {
    runApp(app);
  }
}

/// The app's updates (lib/update/): looked for as settings.json's
/// `update.mode` says, from baocode.dev, installed as the app quits. None
/// where the build does not update itself.
UpdateController? _startUpdates(SettingsFiles files) {
  final platform = platformUpdates(
    updatesDirectory: DataDirectory.current.updatesDir,
  );
  if (platform == null) return null;
  final service = UpdateService(
    current: currentAppVersion,
    platform: platform.platform,
    manifestUrl: platform.manifestUrl,
    backend: platform.backend,
    installer: platform.installer,
    mode: () => UpdateMode.parse(files.settings[UpdateMode.settingKey]),
    settingsChanges: files.settings,
    store: GlobalUpdateStore(files.storage),
  )..start();
  return UpdateController(
    service: service,
    // As the Data Folder page's Quit Now goes, but asked as any quit is.
    quit: () async {
      if (AppPlatform.isWindows) return ChannelAttentionHost.instance.quit();
      await ServicesBinding.instance.exitApplication(AppExitType.cancelable);
    },
    openUrl: (url) => openExternal('$url'),
    openFile: openExternal,
  );
}

/// The channel build's first start (lib/channel/): to set up while it is
/// pending, for the windows to show. The install's id made now, to give
/// the page, and kept before the telemetry would make its own.
Future<void> _beginChannelSetup(SettingsFiles files) async {
  if (kIsWeb) return;
  final store = GlobalChannelSetupStore(files.storage);
  if (!ChannelSetup.begin(store)) return;
  var id = GlobalTelemetryStore(files.storage).installId;
  if (id == null) {
    id = TelemetryService.randomInstallId();
    await files.storage
        .set(GlobalTelemetryStore.installIdKey, id)
        .catchError(
          (Object error) => debugPrint('install id not kept: $error'),
        );
  }
  ChannelSetup.current = _channelSetup(store, id);
}

ChannelSetup _channelSetup(
  ChannelSetupStore store,
  String installId, {
  String? again,
}) => ChannelSetup(
  store: store,
  installId: installId,
  again: again,
  lookUp: lookUpChannel,
  open: (url) => openExternal('$url'),
);

/// The channel build's way in (lib/channel/): set up, then signed in to
/// its channel's account site, whose key is its only upstream.
void _openChannelGate(SettingsFiles files) {
  if (kIsWeb || !ChannelSetup.channelBuild) return;
  final accounts = GlobalChannelAccountStore(files.storage);
  final setupStore =
      ChannelSetup.current?.store ?? GlobalChannelSetupStore(files.storage);
  ChannelGate.current = ChannelGate(
    setup: ChannelSetup.current,
    setupStore: setupStore,
    accountStore: accounts,
    fetch: channelEntry,
    // Its link opened, the setup asking takes it (workbench.dart).
    makeSetupAgain: () => ChannelSetup.current = _channelSetup(
      setupStore,
      GlobalTelemetryStore(files.storage).installId ??
          TelemetryService.randomInstallId(),
      again: TelemetryService.randomInstallId(),
    ),
    makeAccount: (channel) => ChannelAccount(
      site: channel.info.account!,
      channelName: channel.info.name,
      store: accounts,
      send: sendToAccountSite,
      listModels: listUpstreamModels,
    ),
  );
}

/// The app's usage data (lib/telemetry/): once a UTC day it is in front.
/// None in a debug build.
void _startTelemetry(SettingsFiles files) {
  final platform = platformTelemetry();
  if (platform == null) return;
  // The setup's, read back as it was set.
  final channel =
      ChannelSetup.current?.store ?? GlobalChannelSetupStore(files.storage);
  bool inFront() => switch (WidgetsBinding.instance.lifecycleState) {
    null || AppLifecycleState.resumed => true,
    _ => false,
  };
  final telemetry = TelemetryService(
    current: currentAppVersion,
    os: platform.os,
    arch: platform.arch,
    sender: platform.sender,
    url: platform.url,
    store: GlobalTelemetryStore(files.storage),
    inFront: inFront,
    edition: () => ChannelSetup.editionOf(channel),
    attribution: () => channel.attribution?.toJson(),
  )..start();
  // Back in front: a new day, if it is one. For the app's whole run.
  AppLifecycleListener(onResume: telemetry.markActive);
}

class BaoCodeApp extends StatefulWidget {
  const BaoCodeApp({
    super.key,
    this.workspace,
    this.themeExtensions,
    this.languagesFor,
    this.gitFor,
    this.repositoriesIn,
    this.terminalBackend,
    this.appLocale,
    this.settings,
    this.conversations,
    this.customizations,
    this.windows,
  });

  /// The app's windows; by default, the one ([AppWindows.multi] false).
  final AppWindows? windows;

  /// What the search palette searches conversations with; none when null.
  final ConversationSearch? conversations;

  /// Claude Code's customizations; no Customize when null.
  final CustomizationStore? customizations;

  /// Defaults to the projects and sessions the kernels keep.
  final Workspace? workspace;

  /// The display language setting; the system's language when null.
  final AppLocale? appLocale;

  /// What the settings dialog shows; by default, the pages over
  /// [appLocale] and the app's keybindings.
  final AppSettings? settings;

  /// The installed theme extensions (the Extensions view's).
  final ThemeExtensions? themeExtensions;

  /// The language servers for a project the IDE opens; none when null.
  final LanguageFeatures Function(String root)? languagesFor;

  /// The Git repository of a project the IDE opens; none when null.
  final IdeGitRepository Function(String root)? gitFor;

  /// The repositories in a folder's subfolders, by path on its host; none
  /// looked for when null.
  final Future<List<String>> Function(String folder, IdeRepositoryScan scan)?
  repositoriesIn;

  /// What the IDE's terminals run on; none when null.
  final TerminalBackend? terminalBackend;

  @override
  State<BaoCodeApp> createState() => _BaoCodeAppState();
}

class _BaoCodeAppState extends State<BaoCodeApp> {
  late final Workspace _workspace =
      widget.workspace ??
      (Workspace(preferences: PreferenceStore.file())..load());

  late final AppLocale _locale = widget.appLocale ?? AppLocale();

  /// The code's font, size and ligatures: what restyles all code; and the
  /// windows' blur, which every surface over it is tinted for.
  static final Listenable _codeFont = Listenable.merge([
    CodeFont.families,
    CodeFont.size,
    CodeFont.ligatures,
    WindowBlur.enabled,
  ]);

  late final AppSettings _settings =
      widget.settings ?? AppSettings(locale: _locale);

  late final AppWindows _windows =
      widget.windows ??
      AppWindows(
        host: ChannelWindowHost(),
        workspace: _workspace,
        l10n: () =>
            lookupAppLocalizations(_locale.locale ?? AppLocale.systemLocale()),
      );

  /// Quitting ends the Claude Code processes too: left alone, one would
  /// finish its turn (subagents and all) unseen, and a resumed session would
  /// then run beside it. Language servers end with the app as well, and the
  /// terminals' shells are hung up, as closing their window would.
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(
    onExitRequested: () async {
      // The unsaved files of all windows asked about at once, then the
      // agents at work; in the window in front.
      final updates = _settings.updates?.service;
      if (!await _windows.confirmQuit()) {
        updates?.disarm();
        return AppExitResponse.cancel;
      }
      // Restart to Update: the installer waits for the app to go. One that
      // will not start keeps the app (and says why).
      if (updates != null && !await updates.launchArmed()) {
        return AppExitResponse.cancel;
      }
      await Future.wait([
        stopClaudeProcesses(),
        RemoteClaudeTransport.stopAll(),
        stopModelProxy(),
        stopLspProcesses(),
        ?widget.themeExtensions?.dispose(),
        stopPtyProcesses(),
      ]);
      // The remote hosts' servers end, and all they run with them.
      await SshHosts.instance.closeAll();
      return AppExitResponse.exit;
    },
  );

  final WorkbenchThemeService _themes = WorkbenchThemeService.instance;
  bool? _darkAppearance;

  @override
  void initState() {
    super.initState();
    _lifecycle;
    _themes.addListener(_colorThemeChanged);
    _colorThemeChanged();
    _locale.addListener(_windows.relabel);
    _settings.files?.settings.addListener(_windows.settingsChanged);
    // The IDE's windows of the last run, once the main one is drawn.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_windows.restore()),
    );
  }

  /// The terminals take the theme's colors (`getXtermTheme`); the window's
  /// own parts follow its type.
  void _colorThemeChanged() {
    final colors = _themes.colors;
    terminalColorTheme.value = TerminalColorTheme.resolve(
      colors.get,
      type: colors.type,
    );
    editorTerminalColorTheme.value = TerminalColorTheme.resolve(
      colors.get,
      type: colors.type,
      inEditor: true,
    );
    final dark = colors.dark;
    if (dark == _darkAppearance) return;
    _darkAppearance = dark;
    unawaited(WindowControls.setDarkAppearance(dark));
  }

  @override
  void dispose() {
    _themes.removeListener(_colorThemeChanged);
    _locale.removeListener(_windows.relabel);
    _settings.files?.settings.removeListener(_windows.settingsChanged);
    if (widget.windows == null) _windows.dispose();
    _lifecycle.dispose();
    _workspace.dispose();
    if (widget.appLocale == null) _locale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A theme change restyles everything, as the workbench's does; so does
    // a language change, at once: in all windows.
    return WorkbenchThemeScope(
      // The code's font, size and ligatures are read as widgets build, so a
      // change rebuilds everything, as a theme change does: what a window's
      // navigator keeps (its page) would not be by rebuilding the app
      // alone. The text scale is a MediaQuery instead (see _app's builder).
      restyle: _codeFont,
      builder: (context) => AppLocaleScope(
        notifier: _locale,
        child: ListenableBuilder(
          listenable: _locale,
          builder: (context, _) => _windows.started
              ? ListenableBuilder(
                  listenable: _windows,
                  builder: (context, _) => ViewCollection(
                    views: [
                      for (final window in [
                        _windows.chat,
                        ..._windows.ideWindows,
                        ..._windows.agentWindows,
                        ?_windows.stash,
                      ])
                        if (_windows.host.viewOf(window.viewId)
                            case final view?)
                          QuietView(
                            key: ValueKey(window.viewId),
                            view: view,
                            child: _app(window),
                          ),
                    ],
                  ),
                )
              : _app(_windows.chat),
        ),
      ),
    );
  }

  /// A window's app: its own navigator, dialogs, overlay and focus; what
  /// it shows built anew as its folder changes.
  Widget _app(AppWindow window) => MaterialApp(
    title: 'BaoCode',
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    scrollBehavior: const BaoScrollBehavior(),
    builder: (context, child) => ValueListenableBuilder<int>(
      valueListenable: CodeFont.uiScale,
      builder: (context, percent, scaled) {
        // The whole window is zoomed, not its text alone: its fixed heights,
        // icons and gaps grow with the text they hold.
        final zoom = percent / 100;
        final media = UiZoom.zoomed(MediaQuery.of(context), zoom);
        // The traffic lights, level with the title bar as it grows.
        WindowControls.setTitleBarDrop(
          AppMetrics.titleBarHeight * (zoom - 1) / 2,
          viewId: window.viewId,
        );
        // Windows blurs glyphs drawn at a fractional pixel size.
        TextScaler snapped(TextScaler scaler) => AppPlatform.isWindows
            ? PixelSnappedTextScaler(scaler, media.devicePixelRatio)
            : scaler;
        final system = media.textScaler;
        return SystemTextScale(
          // Code at its own size: the zoom taken back off.
          scaler: snapped(
            zoom == 1 ? system : TextScaler.linear(system.scale(1) / zoom),
          ),
          child: MediaQuery(
            data: media.copyWith(textScaler: snapped(system)),
            child: UiZoom(scale: zoom, child: scaled),
          ),
        );
      },
      child: child,
    ),
    locale: _locale.locale,
    supportedLocales: AppLocale.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    home: window.isStash
        ? Material(
            type: MaterialType.transparency,
            child: StashPanelView(
              controller: StashController.current!,
              viewId: window.viewId,
            ),
          )
        : Workbench(
            key: ValueKey((window.viewId, window.generation)),
            workspace: _workspace,
            windows: _windows,
            window: window,
            languagesFor: widget.languagesFor,
            themeExtensions: widget.themeExtensions,
            gitFor: widget.gitFor,
            repositoriesIn: widget.repositoriesIn,
            terminalBackend: widget.terminalBackend,
            settings: _settings,
            conversations: widget.conversations ?? const NoConversationSearch(),
            customizations: widget.customizations,
          ),
  );
}
