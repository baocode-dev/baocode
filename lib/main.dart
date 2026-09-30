import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'ide/git/git_repository.dart';
import 'ide/git/git_service.dart';
import 'ide/lsp/catalog/standard_lsp.dart';
import 'ide/lsp/language_features.dart';
import 'ide/lsp/lsp_process.dart';
import 'ide/terminal/pty.dart';
import 'ide/terminal/terminal_colors.dart';
import 'kernel/claude_code/process_transport.dart';
import 'theme/cursor_theme.dart';
import 'theme/workbench_theme.dart';
import 'workbench.dart';
import 'workspace/preference_store.dart';
import 'workspace/window_controls.dart';
import 'workspace/workspace.dart';

Future<void> main() async {
  unawaited(reapClaudeProcesses());
  unawaited(reapLspProcesses());
  unawaited(reapPtyProcesses());
  WidgetsFlutterBinding.ensureInitialized();
  final workspace = Workspace(preferences: PreferenceStore.file())..load();
  // The first frame is in the kept theme, restored from storage as VS Code
  // does before the workbench shows; its file is read after.
  await workspace.restored;
  final themes = WorkbenchThemeService.instance
    ..restore(
      setting: workspace.colorThemeSetting,
      data: workspace.colorThemeData,
    )
    ..storage = workspace;
  unawaited(themes.initialize());
  runApp(
    MonadApp(
      workspace: workspace,
      languagesFor: standardLspManager,
      gitFor: (root) => IdeGitRepository(IdeGitService(root)),
    ),
  );
}

class MonadApp extends StatefulWidget {
  const MonadApp({super.key, this.workspace, this.languagesFor, this.gitFor});

  /// Defaults to the projects and sessions the kernels keep.
  final Workspace? workspace;

  /// The language servers for a project the IDE opens; none when null.
  final LanguageFeatures Function(String root)? languagesFor;

  /// The Git repository of a project the IDE opens; none when null.
  final IdeGitRepository Function(String root)? gitFor;

  @override
  State<MonadApp> createState() => _MonadAppState();
}

class _MonadAppState extends State<MonadApp> {
  late final Workspace _workspace =
      widget.workspace ??
      (Workspace(preferences: PreferenceStore.file())..load());

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A theme change restyles everything, as the workbench's does.
    return WorkbenchThemeScope(
      builder: (context) => MaterialApp(
        title: 'Monad',
        debugShowCheckedModeBanner: false,
        theme: buildCursorTheme(),
        localizationsDelegates: const [FlutterQuillLocalizations.delegate],
        home: Workbench(
          workspace: _workspace,
          languagesFor: widget.languagesFor,
          gitFor: widget.gitFor,
        ),
      ),
    );
  }
}
