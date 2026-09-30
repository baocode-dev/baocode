import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'ide/git/git_repository.dart';
import 'ide/git/git_service.dart';
import 'ide/lsp/catalog/standard_lsp.dart';
import 'ide/lsp/language_features.dart';
import 'ide/lsp/lsp_process.dart';
import 'kernel/claude_code/process_transport.dart';
import 'theme/cursor_theme.dart';
import 'workbench.dart';
import 'workspace/preference_store.dart';
import 'workspace/workspace.dart';

void main() {
  unawaited(reapClaudeProcesses());
  unawaited(reapLspProcesses());
  runApp(
    MonadApp(
      workspace: Workspace(preferences: PreferenceStore.file())..load(),
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
  /// then run beside it. Language servers end with the app as well.
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(
    onExitRequested: () async {
      await Future.wait([stopClaudeProcesses(), stopLspProcesses()]);
      return AppExitResponse.exit;
    },
  );

  @override
  void initState() {
    super.initState();
    _lifecycle;
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _workspace.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Monad',
      debugShowCheckedModeBanner: false,
      theme: buildCursorTheme(),
      localizationsDelegates: const [FlutterQuillLocalizations.delegate],
      home: Workbench(
        workspace: _workspace,
        languagesFor: widget.languagesFor,
        gitFor: widget.gitFor,
      ),
    );
  }
}
