import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'ide/git/git_repository.dart';
import 'ide/git/git_service.dart';
import 'ide/lsp/catalog/standard_lsp.dart';
import 'ide/lsp/language_features.dart';
import 'ide/lsp/lsp_process.dart';
import 'ide/terminal/pty.dart';
import 'ide/terminal/terminal_colors.dart';
import 'ide/terminal/terminal_instance.dart';
import 'kernel/claude_code/process_transport.dart';
import 'keybindings/keybindings_sync.dart';
import 'keybindings/keymap.dart';
import 'keybindings/vscode_import.dart';
import 'l10n/l10n.dart';
import 'platform/data_dir.dart';
import 'settings/app_locale.dart';
import 'settings/app_settings.dart';
import 'settings/data_dir_startup.dart';
import 'settings/user_settings.dart';
import 'theme/app_theme.dart';
import 'theme/workbench_theme.dart';
import 'workbench.dart';
import 'workspace/preference_store.dart';
import 'workspace/window_controls.dart';
import 'workspace/workspace.dart';

Future<void> main() async {
  // All the app keeps is in its data folder: found first, once. One the
  // user set that cannot be used (a drive gone) is reported before the app
  // shows, never swapped for the default unasked.
  if (!kIsWeb) {
    final resolution = resolveDataDirectory();
    if (resolution.ok) {
      DataDirectory.current = resolution.directory;
    } else {
      WidgetsFlutterBinding.ensureInitialized();
      DataDirectory.current = await recoverDataDirectory(resolution);
    }
  }
  unawaited(reapClaudeProcesses());
  unawaited(reapLspProcesses());
  unawaited(reapPtyProcesses());
  WidgetsFlutterBinding.ensureInitialized();
  // The user's settings files ([SettingsFiles.instance]): read before the
  // first frame, which is in their language and theme, and followed as
  // they change on disk.
  final files = kIsWeb ? null : SettingsFiles.instance;
  await files?.load();
  files?.watch();
  final workspace = Workspace(preferences: PreferenceStore.file())..load();
  // The first frame is in the kept theme, restored from storage as VS Code
  // does before the workbench shows; its file is read after. The setting
  // is settings.json's `workbench.colorTheme`, the theme's colors the
  // workspace's state.
  await workspace.restored;
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
  final locale = AppLocale(storage: files?.argv);
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
    );
  }
  runApp(
    MonadApp(
      workspace: workspace,
      appLocale: locale,
      settings: settings,
      languagesFor: standardLspManager,
      gitFor: (root) => IdeGitRepository(IdeGitService(root)),
      // The default profile and the user's profiles are settings.json's.
      terminalBackend: TerminalBackend(settings: files?.settings),
    ),
  );
}

class MonadApp extends StatefulWidget {
  const MonadApp({
    super.key,
    this.workspace,
    this.languagesFor,
    this.gitFor,
    this.terminalBackend,
    this.appLocale,
    this.settings,
  });

  /// Defaults to the projects and sessions the kernels keep.
  final Workspace? workspace;

  /// The display language setting; the system's language when null.
  final AppLocale? appLocale;

  /// What the settings dialog shows; by default, the pages over
  /// [appLocale] and the app's keybindings.
  final AppSettings? settings;

  /// The language servers for a project the IDE opens; none when null.
  final LanguageFeatures Function(String root)? languagesFor;

  /// The Git repository of a project the IDE opens; none when null.
  final IdeGitRepository Function(String root)? gitFor;

  /// What the IDE's terminals run on; none when null.
  final TerminalBackend? terminalBackend;

  @override
  State<MonadApp> createState() => _MonadAppState();
}

class _MonadAppState extends State<MonadApp> {
  late final Workspace _workspace =
      widget.workspace ??
      (Workspace(preferences: PreferenceStore.file())..load());

  late final AppLocale _locale = widget.appLocale ?? AppLocale();

  late final AppSettings _settings =
      widget.settings ?? AppSettings(locale: _locale);

  /// Quitting ends the Claude Code processes too: left alone, one would
  /// finish its turn (subagents and all) unseen, and a resumed session would
  /// then run beside it. Language servers end with the app as well, and the
  /// terminals' shells are hung up, as closing their window would.
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(
    onExitRequested: () async {
      await Future.wait([
        stopClaudeProcesses(),
        stopLspProcesses(),
        stopPtyProcesses(),
      ]);
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
    _lifecycle.dispose();
    _workspace.dispose();
    if (widget.appLocale == null) _locale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A theme change restyles everything, as the workbench's does; so does
    // a language change, at once.
    return WorkbenchThemeScope(
      builder: (context) => AppLocaleScope(
        notifier: _locale,
        child: ListenableBuilder(
          listenable: _locale,
          builder: (context, _) => MaterialApp(
            title: 'Monad',
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(),
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
              workspace: _workspace,
              languagesFor: widget.languagesFor,
              gitFor: widget.gitFor,
              terminalBackend: widget.terminalBackend,
              settings: _settings,
            ),
          ),
        ),
      ),
    );
  }
}
