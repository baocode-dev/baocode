/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The Notebook degradation (the goal's 五.15, as Webviews degrade):
// BaoCode has no notebook editor, so the notebook shapes accept what
// extensions register, never open a notebook, and say so instead of
// quietly swallowing it. Upstream behavior each degrades: VS Code
// 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0)
// src/vs/workbench/api/browser/mainThreadNotebook.ts (serializers, cell
// status bar item providers), mainThreadNotebookDocuments.ts
// (`$tryCreateNotebook`, `$tryOpenNotebook`, `$trySaveNotebook`),
// mainThreadNotebookEditors.ts (`$tryShowNotebookDocument`, reveal and
// selections), mainThreadNotebookKernels.ts (kernels, detection tasks,
// source action providers, `$postMessage`) and
// mainThreadNotebookRenderers.ts (`$postMessage`).
//
// Deviations, all intended by the goal: a serializer is recorded as a
// placeholder with one line in the Output panel's "Extension Host" channel
// and never asked for a notebook (its files open as text in BaoCode's own
// editors); opening, creating or showing a notebook fails with a notice;
// saving one answers false; a message to a kernel or renderer answers false;
// no execution is ever requested, so the execution methods stay
// unsupported.

import 'package:bao_exthost/bao_exthost.dart';

import '../../ide/ide_notifications.dart';
import '../window/webview_degradation.dart';
import '../window/webview_placeholders.dart';
import 'main_thread_context.dart';

ExtensionWebviewUi _uiOf(MainThreadContext context) =>
    context.maybeService<ExtensionWebviewUi>() ??
    ExtensionWebviewUi(
      placeholders: context.service<ExtensionWebviewPlaceholders>(),
    );

/// Raised to the extension for what needs a notebook editor.
final class NotebooksUnsupportedError extends StateError {
  NotebooksUnsupportedError(VsUri? uri)
    : super(
        'Notebooks are not supported in BaoCode'
        '${uri == null ? '' : ': ${uri.path}'}',
      );
}

final class MainThreadNotebook extends MainThreadNotebookUnsupported {
  MainThreadNotebook(this._ui);

  final ExtensionWebviewUi _ui;

  /// The serializers' notebook types, by handle; never asked for a notebook.
  final Map<num, String> serializers = {};

  /// The cell status bar item providers' notebook types, by handle.
  final Map<num, String> cellStatusBarProviders = {};

  static RpcActor customer(MainThreadContext context) =>
      MainThreadNotebookActor(MainThreadNotebook(_uiOf(context)));

  @override
  void $registerNotebookSerializer(
    num handle,
    Map<String, Object?> extension,
    String viewType,
    Map<String, Object?> options,
    Map<String, Object?>? registration,
  ) {
    serializers[handle] = viewType;
    final placeholder = _ui.placeholders.showNotebook(
      viewType: viewType,
      extension: extension,
      title: '${registration?['displayName'] ?? viewType}',
    );
    // One line per notebook type, as for a custom editor: the notice waits
    // for something to try to open one.
    _ui.placeholders.logLine(placeholder.description);
  }

  @override
  void $unregisterNotebookSerializer(num handle) {
    final viewType = serializers.remove(handle);
    if (viewType != null) _ui.placeholders.remove('notebook:$viewType');
  }

  @override
  void $registerNotebookCellStatusBarItemProvider(
    num handle,
    num? eventHandle,
    String viewType,
  ) => cellStatusBarProviders[handle] = viewType;

  @override
  void $unregisterNotebookCellStatusBarItemProvider(
    num handle,
    num? eventHandle,
  ) => cellStatusBarProviders.remove(handle);

  /// No cell shows its status bar.
  @override
  void $emitCellStatusBarEvent(num eventHandle) {}
}

/// Tells the user, once per document, that a notebook was not opened.
final class NotebookNotices {
  NotebookNotices(this.ui);

  final ExtensionWebviewUi ui;
  final Set<String> _noticed = {};

  void notice(VsUri? uri) {
    final name = uri == null ? 'Untitled' : uri.path.split('/').last;
    if (!_noticed.add(uri?.toString() ?? '')) return;
    ui.placeholders.logLine(ui.strings.windowNotebookUnsupported(name));
    ui.notifications?.notify(
      IdeSeverity.warning,
      ui.strings.windowNotebookUnsupported(name),
      source: 'BaoCode',
    );
  }
}

final class MainThreadNotebookDocuments
    extends MainThreadNotebookDocumentsUnsupported {
  MainThreadNotebookDocuments(this._notices);

  final NotebookNotices _notices;

  static RpcActor customer(MainThreadContext context) =>
      MainThreadNotebookDocumentsActor(
        MainThreadNotebookDocuments(NotebookNotices(_uiOf(context))),
      );

  @override
  Future<VsUri> $tryCreateNotebook(Map<String, Object?> options) async {
    _notices.notice(null);
    throw NotebooksUnsupportedError(null);
  }

  @override
  Future<VsUri> $tryOpenNotebook(VsUri uriComponents) async {
    _notices.notice(uriComponents);
    throw NotebooksUnsupportedError(uriComponents);
  }

  /// None is open to save.
  @override
  Future<bool> $trySaveNotebook(VsUri uri) async => false;
}

final class MainThreadNotebookEditors
    extends MainThreadNotebookEditorsUnsupported {
  MainThreadNotebookEditors(this._notices);

  final NotebookNotices _notices;

  static RpcActor customer(MainThreadContext context) =>
      MainThreadNotebookEditorsActor(
        MainThreadNotebookEditors(NotebookNotices(_uiOf(context))),
      );

  @override
  Future<String> $tryShowNotebookDocument(
    VsUri uriComponents,
    String viewType,
    Map<String, Object?> options,
  ) async {
    _notices.notice(uriComponents);
    throw NotebooksUnsupportedError(uriComponents);
  }

  /// No notebook editor exists to reveal in.
  @override
  void $tryRevealRange(String id, Map<String, Object?> range, int revealType) {}

  /// No notebook editor exists to select in.
  @override
  void $trySetSelections(String id, List<Map<String, Object?>> range) {}
}

final class MainThreadNotebookKernels
    extends MainThreadNotebookKernelsUnsupported {
  /// The kernels (notebook controllers) extensions added, by handle; none
  /// is ever asked to run a cell.
  final Map<num, Map<String, Object?>> kernels = {};

  /// The kernel detection tasks' notebook types, by handle.
  final Map<num, String> detectionTasks = {};

  /// The kernel source action providers' notebook types, by handle.
  final Map<num, String> sourceActionProviders = {};

  static RpcActor customer(MainThreadContext context) =>
      MainThreadNotebookKernelsActor(MainThreadNotebookKernels());

  /// No notebook editor runs the kernel's renderer side.
  @override
  Future<bool> $postMessage(
    num handle,
    String? editorId,
    Object? message,
  ) async => false;

  @override
  void $addKernel(num handle, Map<String, Object?> data) =>
      kernels[handle] = data;

  @override
  void $updateKernel(num handle, Map<String, Object?> data) =>
      kernels[handle] = {...?kernels[handle], ...data};

  @override
  void $removeKernel(num handle) => kernels.remove(handle);

  @override
  void $updateNotebookPriority(num handle, VsUri uri, num? value) {}

  @override
  void $addKernelDetectionTask(num handle, String notebookType) =>
      detectionTasks[handle] = notebookType;

  @override
  void $removeKernelDetectionTask(num handle) => detectionTasks.remove(handle);

  @override
  void $addKernelSourceActionProvider(
    num handle,
    num eventHandle,
    String notebookType,
  ) => sourceActionProviders[handle] = notebookType;

  @override
  void $removeKernelSourceActionProvider(num handle, num eventHandle) =>
      sourceActionProviders.remove(handle);

  @override
  void $emitNotebookKernelSourceActionsChangeEvent(num eventHandle) {}
}

final class MainThreadNotebookRenderers
    extends MainThreadNotebookRenderersUnsupported {
  static RpcActor customer(MainThreadContext context) =>
      MainThreadNotebookRenderersActor(MainThreadNotebookRenderers());

  /// No renderer runs to receive it.
  @override
  Future<bool> $postMessage(
    String? editorId,
    String rendererId,
    Object? message,
  ) async => false;
}
