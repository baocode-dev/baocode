// Auto save (upstream `EditorAutoSave` with `IFilesConfigurationService`'s
// `files.autoSave`, src/vs/workbench/browser/parts/editor/
// editorAutoSave.ts): `off` (the default), `afterDelay`, `onFocusChange`
// or `onWindowChange`, as settings.json says.

import 'dart:async';

import '../ide_workspace.dart';
import '../workbench/contributions.dart';
import '../workbench/services.dart';
import 'configuration.dart';
import 'editors.dart';

class AutoSaveService implements WorkbenchDisposable {
  AutoSaveService({
    required this.host,
    required this.config,
    required this.editors,
    required this._workspace,
  });

  final WorkbenchHost host;
  final ConfigurationService config;
  final EditorService editors;
  final IdeWorkspace? Function() _workspace;

  /// `files.autoSave`.
  String get mode => switch (config.settings?['files.autoSave']) {
    final String mode => mode,
    _ => 'off',
  };

  /// `files.autoSaveDelay`: how long after the last edit `afterDelay`
  /// saves.
  Duration get delay => switch (config.settings?['files.autoSaveDelay']) {
    final int ms when ms >= 0 => Duration(milliseconds: ms),
    _ => const Duration(seconds: 1),
  };

  Timer? _timer;

  /// The documents whose auto save failed (changed on disk, say): left to
  /// be saved by hand, lest the error come back with every edit.
  final Set<IdeDocument> _failed = Set.identity();

  bool _saves(IdeDocument doc) =>
      doc.dirty && doc.isFile && !doc.deleted && !_failed.contains(doc);

  /// After an edit, or the settings read again: `afterDelay` saves once
  /// edits stop for its delay.
  void schedule() {
    _timer?.cancel();
    _timer = null;
    final workspace = _workspace();
    if (mode != 'afterDelay' ||
        workspace == null ||
        !workspace.documents.any(_saves)) {
      return;
    }
    _timer = Timer(delay, () => unawaited(saveNow()));
  }

  /// The documents changed: those saved or closed may fail again.
  void documentsChanged() {
    final documents = _workspace()?.documents ?? const [];
    _failed.removeWhere((doc) => !doc.dirty || !documents.contains(doc));
    schedule();
  }

  /// Saves the documents auto save keeps when it is on in one of [modes];
  /// none of them formatted, as VS Code's `afterDelay` does not.
  Future<void> saveNow([
    Set<String> modes = const {'afterDelay', 'onFocusChange', 'onWindowChange'},
  ]) async {
    _timer?.cancel();
    _timer = null;
    final workspace = _workspace();
    if (workspace == null || host.context == null || !modes.contains(mode)) {
      return;
    }
    final dirty = workspace.documents.where(_saves).toList();
    if (dirty.isEmpty) return;
    await editors.flush();
    for (final doc in dirty) {
      if (host.context == null || !identical(workspace, _workspace())) return;
      try {
        await workspace.save(doc);
      } catch (error) {
        _failed.add(doc);
        host.report(error);
      }
    }
  }

  /// Another workspace: nothing of the last one's to save.
  void detach() {
    _timer?.cancel();
    _timer = null;
    _failed.clear();
  }

  @override
  void dispose() => detach();
}
