// A fresh data folder and project with real Open VSX extensions installed
// through the workspace's management (the server's install, with their
// dependencies and packs), the extension host running them, and what they
// asked for that is not supported. The .vsix files are kept in
// `BAOCODE_OPENVSX_CACHE` (else /tmp/exthost-dl/openvsx-cache) so each
// one downloads once.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bao_editor/monaco/flutter/editor_surface_controller.dart';
import 'package:bao_exthost/bao_exthost.dart';
import 'package:baocode/extensions/configuration/configuration_service.dart';
import 'package:baocode/extensions/configuration/core_configuration.dart';
import 'package:baocode/extensions/gallery/open_vsx_client.dart';
import 'package:baocode/extensions/host/extension_host_manager.dart';
import 'package:baocode/extensions/workbench/workspace_extensions.dart';
import 'package:baocode/ide/ide_editor_features.dart';
import 'package:baocode/ide/ide_editor_views.dart';
import 'package:baocode/ide/ide_workspace.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../host/exthost_runtime.dart';

/// Where the downloaded .vsix files are kept between runs.
String openVsxCacheDir() =>
    Platform.environment['BAOCODE_OPENVSX_CACHE'] ??
    '/tmp/exthost-dl/openvsx-cache';

/// Why an Open VSX acceptance test cannot run here, or false.
Object openVsxSkip() =>
    exthostRuntimeDir() == null ? 'No runtime: set BAOCODE_EXTHOST_DIR' : false;

final class AcceptanceSettings extends ChangeNotifier implements SettingsFile {
  AcceptanceSettings(this.values);

  @override
  final Map<String, Object?> values;

  /// `[key]` or `['[lang]', key]`, as settings.json keeps them; null
  /// removes.
  @override
  Future<void> write(List<String> path, Object? value) async {
    var target = values;
    for (final key in path.take(path.length - 1)) {
      target = (target[key] ??= <String, Object?>{}) as Map<String, Object?>;
    }
    if (value == null) {
      target.remove(path.last);
    } else {
      target[path.last] = value;
    }
    notifyListeners();
  }
}

/// Polls [read] until it gives something.
Future<T> eventually<T>(
  String what,
  FutureOr<T?> Function() read, {
  Duration timeout = const Duration(seconds: 90),
}) async {
  final end = DateTime.now().add(timeout);
  Object? last;
  while (true) {
    try {
      final value = await read();
      if (value != null) return value;
    } on TestFailure {
      rethrow;
    } on Object catch (e) {
      last = e;
    }
    if (DateTime.now().isAfter(end)) {
      throw TimeoutException('No $what after $timeout (last error: $last)');
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
}

final class OpenVsxWorkspace {
  OpenVsxWorkspace._(
    this.root,
    this.project,
    this.app,
    this.extensions,
    this.workspace,
    this.close,
  );

  final String root;
  final String project;
  final ExtensionsApp app;
  final WorkspaceExtensions extensions;
  final IdeWorkspace workspace;

  /// Quits: the workspace, then the app (as the app quitting does); its
  /// data folder stays until the test ends.
  final Future<void> Function() close;

  /// `Actor.$method`s the extensions called that are not supported.
  final Set<String> unsupported = {};

  String path(String relative) => p.join(project, relative);

  /// A temporary data folder and project with [files], [extensionIds]
  /// installed from Open VSX (plus [development] folders), the folder
  /// trusted and the host started. Torn down with the test.
  ///
  /// [reopen] is another's [root]: the app starting again on its data
  /// folder and project (left for that one to delete).
  static Future<OpenVsxWorkspace> create({
    required List<String> extensionIds,
    Map<String, String> files = const {},
    Map<String, Object?> settings = const {},
    List<String> development = const [],
    void Function(String project)? prepare,
    String? reopen,
  }) async {
    // The binding answers every HttpClient request with a 400: these
    // download for real.
    HttpOverrides.global = null;
    final runtime = exthostRuntimeDir()!;
    final root =
        reopen ??
        (await Directory.systemTemp.createTemp('exthost-openvsx'))
            .resolveSymbolicLinksSync();
    final project = p.join(root, 'proj');
    for (final MapEntry(:key, :value) in files.entries) {
      File(p.join(project, key))
        ..createSync(recursive: true)
        ..writeAsStringSync(value);
    }
    Directory(project).createSync(recursive: true);
    prepare?.call(project);

    final app = ExtensionsApp(
      userSettings: AcceptanceSettings({...settings}),
      dataDirectory: p.join(root, 'data'),
      loadRuntime: () => ExtHostRuntime.load(runtime),
      coreConfiguration: () async => CoreConfiguration.fromJson(
        (jsonDecode(
          File('assets/exthost/core_configuration.json').readAsStringSync(),
        ) as Map).cast(),
        platform: CoreConfiguration.currentPlatform,
      ),
      gallery: OpenVsxClient(cacheDir: openVsxCacheDir()),
    );
    final extensions = app.workspace(project);
    final workspace = IdeWorkspace(
      project,
      languages: extensions.languages,
      extensionLanguageId: extensions.languageIdFor,
    );
    // In order: the workspace, its last writes, the app, then the folder.
    Future<void>? closing;
    Future<void> close() => closing ??= () async {
      extensions.dispose();
      workspace.dispose();
      await extensions.debugShutdown;
      await app.storage.flush();
      await app.dispose();
      // The stores' last writes (the terminal environment's is not
      // awaited by dispose).
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }();
    addTearDown(() async {
      await close();
      if (reopen != null) return;
      if (Platform.environment['BAOCODE_KEEP_ACCEPTANCE'] != null) {
        debugPrint('Kept $root');
        return;
      }
      try {
        await Directory(root).delete(recursive: true);
      } on FileSystemException {
        // A server still writing its logs.
      }
    });
    final result = OpenVsxWorkspace._(
      root,
      project,
      app,
      extensions,
      workspace,
      close,
    );
    final parity = ExtHostParity.instance.onUnsupportedCall.listen(
      (call) => result.unsupported.add(call.name),
    );
    addTearDown(parity.cancel);

    await extensions.attach(workspace, start: false);
    await extensions.trust!.setWorkspaceTrust(true);
    for (final id in extensionIds) {
      await extensions.management
          .installFromGallery(id)
          .timeout(const Duration(minutes: 5));
    }
    extensions.host!.developmentLocations = [
      for (final folder in development) VsUri.file(p.absolute(folder)),
    ];
    await extensions.startHost().timeout(const Duration(minutes: 2));
    expect(
      extensions.host!.manager.state,
      ExtensionHostState.running,
      reason: '${extensions.host!.manager.error}',
    );
    return result;
  }

  /// Opens [relative] in the editor (the extensions see the document).
  Future<String> open(String relative) async {
    final file = path(relative);
    await workspace.open(file);
    return file;
  }

  /// Opens [relative] and shows it in an editor without a widget (the
  /// extensions' `activeTextEditor`): its decorations, CodeLenses and
  /// carets are the view's, as the editor widget's would be.
  Future<IdeEditorView> show(String relative) async {
    final file = await open(relative);
    final doc = workspace.documents.singleWhere((d) => d.path == file);
    final controller = EditorSurfaceController(document: doc.model);
    final features = IdeEditorFeatures(
      controller: controller,
      types: workspace.editorViews.decorationTypes,
    );
    final view = IdeEditorView(
      document: doc,
      controller: controller,
      features: features,
      visibleLines: () => (first: 1, last: doc.model.snapshot.lineCount),
      hasFocus: () => true,
      focus: () {},
      reveal: (_, _, {center = false}) {},
    );
    // As the editor widget does: its carets and text moving tell the
    // extensions.
    void changed() => workspace.editorViews.changed(view);
    controller.addListener(changed);
    addTearDown(() {
      controller.removeListener(changed);
      workspace.editorViews.hide(view);
      features.dispose();
      controller.dispose();
    });
    workspace.editorViews.show(view);
    return view;
  }

  /// Waits until [id] is activated, failing on its activation error.
  Future<void> activated(String id, {Duration? timeout}) async {
    await eventually('$id activated', () {
      final running = extensions.running.extension(id);
      if (running?.activationError case final error?) {
        fail('$id failed to activate: ${error.message}');
      }
      return running?.activationTimes == null || running!.activating
          ? null
          : true;
    }, timeout: timeout ?? const Duration(minutes: 2));
  }

  /// Waits for a notification from [source] (an extension's name) and
  /// picks its [action], as its user would.
  Future<void> answer(String source, String action) async {
    String shown() => [
      for (final n in workspace.notifications.notifications)
        '${n.source}: ${n.message} ${[for (final a in n.primary) a.label]}',
    ].join('\n');
    final notification = await eventually('a notification from $source', () {
      for (final n in workspace.notifications.notifications) {
        if (n.source?.contains(source) ?? false) return n;
      }
      return null;
    }).catchError((Object e) => fail('$e\nNotifications:\n${shown()}'));
    final labels = [for (final a in notification.primary) a.label];
    expect(labels, contains(action), reason: shown());
    notification.primary.firstWhere((a) => a.label == action).run();
  }

  /// What went wrong in the extensions, for a failure's reason.
  String report() => [
    'Unsupported: $unsupported',
    for (final e in extensions.running.withErrors)
      '${e.id}: ${e.errors.map((x) => x.message).join(' | ')}',
  ].join('\n');
}
