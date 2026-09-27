import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'theme/cursor_theme.dart';
import 'workbench.dart';
import 'workspace/workspace.dart';

void main() {
  runApp(MonadApp(workspace: Workspace.mock()..startDemoRuns()));
}

class MonadApp extends StatefulWidget {
  const MonadApp({super.key, this.workspace});

  /// Defaults to the sample workspace, with nothing running.
  final Workspace? workspace;

  @override
  State<MonadApp> createState() => _MonadAppState();
}

class _MonadAppState extends State<MonadApp> {
  late final Workspace _workspace = widget.workspace ?? Workspace.mock();

  @override
  void dispose() {
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
      home: Workbench(workspace: _workspace),
    );
  }
}
