/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The Webview degradation (the goal's 五.15): BaoCode does not implement
// Webviews, so the shapes below accept what extensions ask for, never show
// one, and say so once per extension instead of quietly swallowing it.
// Upstream behavior each degrades: VS Code
// 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0)
// src/vs/workbench/api/browser/mainThreadWebviews.ts (`$setHtml`,
// `$setOptions`, `$postMessage`), mainThreadWebviewPanels.ts
// (`$createWebviewPanel`, `$reveal`, `$setTitle`, `$setIconPath`,
// `$registerSerializer`, `$disposeWebview`), mainThreadWebviewViews.ts
// (`$registerWebviewViewProvider`, title, description, badge, `$show`) and
// mainThreadCustomEditors.ts (`$registerTextEditorProvider`,
// `$registerCustomEditorProvider`, `$onDidEdit`, `$onContentChange`), with
// the extension hosts' sides: extHostWebviewPanels.ts (a panel's
// `dispose()` runs `$onDidDisposeWebviewPanel`, which its `onDidDispose`
// listener needs), extHostWebviewViews.ts and extHostCustomEditors.ts.
//
// Deviations, all intended by the goal: `$createWebviewPanel` answers
// `$onDidDisposeWebviewPanel` immediately (the extension sees a panel that
// closed at once); `$postMessage` answers false; `$onDidChangeWebviewPanelViewStates`
// is accepted and ignored (no panel is left to change); a custom editor's
// documents open in BaoCode's own editors; every degradation is recorded
// (webview_placeholders.dart) for a placeholder and one line in the Output
// panel's "Extension Host" channel.

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart';

import '../window/webview_degradation.dart';
import '../window/webview_placeholders.dart';
import 'main_thread_context.dart';

/// The UI a session's Webviews degrade with; the workbench passes one, and
/// the shapes fall back to the placeholders alone when it does not.
ExtensionWebviewUi _uiOf(MainThreadContext context) =>
    context.maybeService<ExtensionWebviewUi>() ??
    ExtensionWebviewUi(
      placeholders: context.service<ExtensionWebviewPlaceholders>(),
    );

final class MainThreadWebviews extends MainThreadWebviewsUnsupported {
  MainThreadWebviews(this._ui);

  final ExtensionWebviewUi _ui;

  static RpcActor customer(MainThreadContext context) =>
      MainThreadWebviewsActor(MainThreadWebviews(_uiOf(context)));

  /// Remembered, never rendered.
  @override
  void $setHtml(String handle, String value) => _ui.placeholders.html[handle] = value;

  /// Remembered, never rendered.
  @override
  void $setOptions(String handle, Map<String, Object?> options) =>
      _ui.placeholders.options[handle] = options;

  /// A message cannot be delivered: there is no webview to deliver it to.
  @override
  Future<bool> $postMessage(
    String handle,
    String value,
    List<RpcBuffer> buffers,
  ) async => false;
}

final class MainThreadWebviewPanels
    extends MainThreadWebviewPanelsUnsupported {
  MainThreadWebviewPanels(this._ui, this._notices, this._proxy);

  final ExtensionWebviewUi _ui;
  final ExtensionWebviewNotices _notices;
  final ExtHostWebviewPanelsProxy _proxy;

  /// The serializers extensions registered; never run (a restored panel is
  /// disposed like a fresh one).
  final Set<String> serializers = {};

  static RpcActor customer(MainThreadContext context) {
    final ui = _uiOf(context);
    return MainThreadWebviewPanelsActor(
      MainThreadWebviewPanels(
        ui,
        ExtensionWebviewNotices(ui),
        ExtHostWebviewPanelsProxy(context.rpc),
      ),
    );
  }

  @override
  void $createWebviewPanel(
    Map<String, Object?> extension,
    String handle,
    String viewType,
    Map<String, Object?> initData,
    Map<String, Object?> showOptions,
  ) {
    final title = '${initData['title'] ?? viewType}';
    final placeholder = _ui.placeholders.showPanel(
      handle: handle,
      extension: extension,
      viewType: viewType,
      title: title,
    );
    _notices.notice(
      extension,
      _ui.strings.windowWebviewPanelDetail(placeholder.extensionName, title),
      primary: webviewFallbackActions(_ui, handle),
      logLine: placeholder.description,
    );
    // The extension's panel closed right away: it sees onDidDispose.
    unawaited(
      _proxy.$onDidDisposeWebviewPanel(handle).catchError((Object _) {}),
    );
  }

  @override
  void $disposeWebview(String handle) => _ui.placeholders.remove(handle);

  @override
  void $reveal(String handle, Map<String, Object?> showOptions) =>
      _ui.placeholders.reveal(handle);

  @override
  void $setTitle(String handle, String value) {
    _ui.placeholders.title[handle] = value;
    _ui.placeholders.placeholder(handle)?.title = value;
  }

  @override
  void $setIconPath(String handle, Map<String, Object?>? value) =>
      _ui.placeholders.icon[handle] = value ?? const {};

  @override
  void $registerSerializer(String viewType, Map<String, Object?> options) =>
      serializers.add(viewType);

  @override
  void $unregisterSerializer(String viewType) => serializers.remove(viewType);
}

final class MainThreadWebviewViews extends MainThreadWebviewViewsUnsupported {
  MainThreadWebviewViews(this._ui);

  final ExtensionWebviewUi _ui;

  /// The view types of the providers that registered
  /// (`$registerWebviewViewProvider`).
  final Map<String, Map<String, Object?>> providers = {};

  static RpcActor customer(MainThreadContext context) =>
      MainThreadWebviewViewsActor(MainThreadWebviewViews(_uiOf(context)));

  @override
  void $registerWebviewViewProvider(
    Map<String, Object?> extension,
    String viewType,
    Map<String, Object?> options,
  ) {
    providers[viewType] = extension;
    _ui.placeholders.showView(
      viewType: viewType,
      extension: extension,
      title: viewType,
    );
  }

  @override
  void $unregisterWebviewViewProvider(String viewType) =>
      providers.remove(viewType);

  @override
  void $setWebviewViewTitle(String handle, String? value) =>
      _ui.placeholders.title[handle] = value;

  @override
  void $setWebviewViewDescription(String handle, String? value) =>
      _ui.placeholders.description[handle] = value;

  @override
  void $setWebviewViewBadge(String handle, Map<String, Object?>? badge) =>
      _ui.placeholders.badge[handle] = badge ?? const {};

  @override
  void $show(String handle, bool preserveFocus) =>
      _ui.placeholders.reveal(handle);
}

final class MainThreadCustomEditors
    extends MainThreadCustomEditorsUnsupported {
  MainThreadCustomEditors(this._ui);

  final ExtensionWebviewUi _ui;

  /// The view types of the registered providers; their documents open in
  /// BaoCode's own editors.
  final Map<String, Map<String, Object?>> providers = {};

  static RpcActor customer(MainThreadContext context) =>
      MainThreadCustomEditorsActor(MainThreadCustomEditors(_uiOf(context)));

  @override
  void $registerTextEditorProvider(
    Map<String, Object?> extension,
    String viewType,
    Map<String, Object?> options,
    Map<String, Object?> capabilities,
    bool serializeBuffersForPostMessage,
  ) => _register(extension, viewType);

  @override
  void $registerCustomEditorProvider(
    Map<String, Object?> extension,
    String viewType,
    Map<String, Object?> options,
    Map<String, Object?> capabilities,
    bool supportsMultipleEditorsPerDocument,
    bool serializeBuffersForPostMessage,
  ) => _register(extension, viewType);

  void _register(Map<String, Object?> extension, String viewType) {
    providers[viewType] = extension;
    final placeholder = _ui.placeholders.showCustomEditor(
      viewType: viewType,
      extension: extension,
    );
    // One line per extension and editor type, in the Output panel: the
    // notice itself would be too much for an editor no document uses yet.
    _ui.placeholders.logLine(placeholder.description);
  }

  @override
  void $unregisterEditorProvider(String viewType) => providers.remove(viewType);

  /// A resolved custom editor's edits: it never opened one.
  @override
  void $onDidEdit(VsUri resource, String viewType, num editId, String? label) {}

  /// A resolved custom editor's content changed: it never opened one.
  @override
  void $onContentChange(VsUri resource, String viewType) {}
}
