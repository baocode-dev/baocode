import 'dart:async';
import 'dart:ui' show AppExitResponse, AppExitType;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show ServicesBinding;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:path/path.dart' as p;

import 'package:bao_editor/monaco/flutter/language_assets.dart';

import 'chat/chat_width.dart';
import 'customize/customization_store.dart';
import 'extensions/workbench/jsonc_settings_file.dart';
import 'extensions/workbench/window_file_pickers.dart';
import 'extensions/workbench/workspace_extensions.dart';
import 'ide/git/git_repository.dart';
import 'ide/git/repository_scan.dart';
import 'ide/lsp/lsp_process.dart';
import 'ide/lsp/packs/language_packs.dart';
import 'ide/terminal/pty.dart';
import 'ide/terminal/terminal_colors.dart';
import 'ide/terminal/terminal_instance.dart';
import 'icons/emoji_sheet.dart';
import 'icons/icon_library.dart';
import 'icons/icon_storage.dart';
import 'kernel/claude_code/claude_onboarding.dart';
import 'kernel/claude_code/process_transport.dart';
import 'kernel/commit_attribution.dart';
import 'keybindings/keybindings_sync.dart';
import 'keybindings/keymap.dart';
import 'keybindings/vscode_import.dart';
import 'l10n/l10n.dart';
import 'models/model_providers.dart';
import 'models/model_runtime.dart';
import 'notifications/attention_host.dart';
import 'notifications/attention_settings.dart';
import 'platform/app_platform.dart';
import 'platform/data_dir.dart';
import 'platform/error_log.dart';
import 'platform/open_requests.dart';
import 'remote/project_host.dart';
import 'remote/remote_claude.dart';
import 'remote/ssh_host.dart';
import 'search/claude_conversation_search.dart';
import 'search/conversation_search.dart';
import 'settings/app_locale.dart';
import 'settings/app_settings.dart';
import 'settings/data_dir_startup.dart';
import 'settings/user_settings.dart';
import 'telemetry/telemetry_platform.dart';
import 'telemetry/telemetry_service.dart';
import 'telemetry/telemetry_store.dart';
import 'theme/app_theme.dart';
import 'theme/code_font.dart';
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
  }
  unawaited(reapClaudeProcesses());
  unawaited(reapLspProcesses());
  unawaited(reapPtyProcesses());
  WidgetsFlutterBinding.ensureInitialized();
  // The Windows app's own logs go beside it.
  if (errors != null) unawaited(errors.shareWithHost());
  // Emoji as pictures: fetched into the cache the first run, in the
  // background.
  EmojiSheet.start(EmojiSheetStore.cache());
  // The editor's language packs are the language servers' (README.md in
  // lib/ide/lsp/packs).
  MonacoLanguageAssets.defaultPacks = () => LanguagePackRegistry.instance;
  // The user's settings files ([SettingsFiles.instance]): read before the
  // first frame, which is in their language and theme, and followed as
  // they change on disk.
  final files = kIsWeb ? null : SettingsFiles.instance;
  await files?.load();
  files?.watch();
  // Read as each agent starts.
  if (files != null) {
    CommitAttribution.current = () =>
        CommitAttribution.parse(files.settings[CommitAttribution.settingKey]);
    // Settings → Models: the upstreams, kept in settings.json.
    ModelProviders.current = ModelProviders.settings(files.settings);
    // Settings → Appearance: how wide the conversation grows.
    ChatWidth.follow(
      files.settings,
      () => files.settings[ChatWidth.settingKey],
    );
    // Settings → Appearance: the code's font, size and ligatures, and the
    // window's text size.
    CodeFont.follow(files.settings, (key) => files.settings[key]);
  }
  await prepareClaudeOnboarding();
  final locale = AppLocale(storage: files?.argv);
  final workspace = Workspace(
    preferences: PreferenceStore.file(),
    // Beside state.json: written as the user types.
    drafts: kIsWeb
        ? null
        : PreferenceStore.file(
            p.join(DataDirectory.current.stateDir, 'drafts.json'),
          ),
    // The data folder's icons/.
    icons: IconLibrary(storage: IconStorage.directory()),
    titler: claudeAgentTitle,
    l10n: () =>
        lookupAppLocalizations(locale.locale ?? AppLocale.systemLocale()),
  )..load();
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
  final ColorThemeStorage colorTheme = files == null
      ? workspace
      : ColorThemeSettings(settings: files.settings, state: workspace);
  final themes = WorkbenchThemeService.instance
    ..restore(
      setting: colorTheme.colorThemeSetting,
      data: colorTheme.colorThemeData,
    )
    ..storage = colorTheme;
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
    );
    _startTelemetry(files);
  }
  // VS Code's extensions (lib/extensions/): one runtime and server for
  // the app, a host per IDE workspace.
  final extensions = files == null
      ? null
      : ExtensionsApp(
          userSettings: JsoncSettingsFile(files.settings),
          openExternal: openExternal,
          filePickers: const WindowFilePickers(),
          language: () =>
              locale.setting ??
              switch (WidgetsBinding.instance.platformDispatcher.locale) {
                Locale(languageCode: 'zh') => AppLocale.simplifiedChinese,
                _ => AppLocale.english,
              },
        );
  final app = BaoCodeApp(
    windows: windows,
    workspace: workspace,
    appLocale: locale,
    settings: settings,
    extensions: extensions,
    // The extension host of a folder on this machine.
    extensionsFor: extensions == null
        ? null
        : (folder) {
            final host = ProjectHost.of(folder);
            if (host.name != null) return null;
            return extensions.workspace(host.pathOf(folder));
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
    customizations: CustomizationStore(),
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

/// The app's usage data (lib/telemetry/): once a UTC day it is in front,
/// as settings.json's `telemetry.telemetryLevel` allows. None in a debug
/// build, or with `DO_NOT_TRACK` set.
void _startTelemetry(SettingsFiles files) {
  final platform = platformTelemetry();
  if (platform == null) return;
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
    enabled: () =>
        TelemetrySetting.enabled(files.settings[TelemetrySetting.settingKey]),
    settingsChanges: files.settings,
    store: GlobalTelemetryStore(files.storage),
    inFront: inFront,
  )..start();
  // Back in front: a new day, if it is one. For the app's whole run.
  AppLifecycleListener(onResume: telemetry.markActive);
}

class BaoCodeApp extends StatefulWidget {
  const BaoCodeApp({
    super.key,
    this.workspace,
    this.extensions,
    this.extensionsFor,
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

  /// The app's extensions, whose server stops as the app quits.
  final ExtensionsApp? extensions;

  /// The extensions of a project the IDE opens (its language features
  /// among them); none when null, or when it gives null.
  final WorkspaceExtensions? Function(String folder)? extensionsFor;

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
        ?widget.extensions?.dispose(),
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
      builder: (context) => AppLocaleScope(
        notifier: _locale,
        child: ListenableBuilder(
          // The code's font, size and ligatures are read as the app is
          // built, so a change rebuilds it; the text scale is a MediaQuery
          // instead (see the builder in _app).
          listenable: Listenable.merge([
            _locale,
            CodeFont.families,
            CodeFont.size,
            CodeFont.ligatures,
          ]),
          builder: (context, _) => _windows.started
              ? ListenableBuilder(
                  listenable: _windows,
                  builder: (context, _) => ViewCollection(
                    views: [
                      for (final window in [
                        _windows.chat,
                        ..._windows.ideWindows,
                        ..._windows.agentWindows,
                      ])
                        if (_windows.host.viewOf(window.viewId)
                            case final view?)
                          View(
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
    builder: (context, child) => ValueListenableBuilder<int>(
      valueListenable: CodeFont.uiScale,
      builder: (context, percent, scaled) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: TextScaler.linear(
              media.textScaler.scale(1) * percent / 100,
            ),
          ),
          child: scaled!,
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
      FlutterQuillLocalizations.delegate,
    ],
    home: Workbench(
      key: ValueKey((window.viewId, window.generation)),
      workspace: _workspace,
      windows: _windows,
      window: window,
      extensionsFor: widget.extensionsFor,
      gitFor: widget.gitFor,
      repositoriesIn: widget.repositoriesIn,
      terminalBackend: widget.terminalBackend,
      settings: _settings,
      conversations: widget.conversations ?? const NoConversationSearch(),
      customizations: widget.customizations,
    ),
  );
}
