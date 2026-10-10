/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The source controls extensions register, into the workspace's
// [ScmService]; the input box's changes and the resources' commands go back
// to the extension host.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadSCM.ts (`MainThreadSCM`).
//
// Deviations: a provider registers at once (no input box text model to
// wait for, so no barrier); the history and artifact providers' changes are
// accepted and dropped (scm_service.dart says why); the selected source
// control is the first one shown, told once as it registers.

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:path/path.dart' as p;

import '../scm/scm_service.dart';
import '../workspace/workspace_context.dart';
import 'main_thread_context.dart';

final class MainThreadSCM extends MainThreadSCMUnsupported {
  MainThreadSCM(this._service, this._workspace, this._proxy);

  final ScmService _service;
  final WorkspaceContextService? _workspace;
  final ExtHostSCMProxy _proxy;
  final Set<int> _handles = {};

  static RpcActor customer(MainThreadContext context) {
    final main = MainThreadSCM(
      context.service<ScmService>(),
      context.maybeService<WorkspaceContextService>(),
      ExtHostSCMProxy(context.rpc),
    );
    context.onDispose(main.dispose);
    return MainThreadSCMActor(main);
  }

  void dispose() {
    for (final handle in _handles) {
      _service.unregister(handle);
    }
    _handles.clear();
  }

  @override
  void $registerSourceControl(
    num handle,
    num? parentHandle,
    String id,
    String label,
    VsUri? rootUri,
    Object? iconPath,
    bool? isHidden,
    VsUri inputBoxDocumentUri,
  ) {
    String? name;
    if (rootUri != null) {
      final folder = _workspace?.getWorkspaceFolder(rootUri);
      if (folder != null && folder.uri.toString() == rootUri.toString()) {
        name = folder.name;
      } else if (rootUri.path != '/') {
        name = p.posix.basename(rootUri.path);
      }
    }
    final provider = ScmProvider(
      handle: handle.toInt(),
      parentHandle: parentHandle?.toInt(),
      providerId: id,
      label: label,
      rootUri: rootUri,
      icon: scmIcon(iconPath),
      isHidden: isHidden ?? false,
      name: name,
    );
    provider.input.onUserChange = (value) => unawaited(
      _proxy.$onInputBoxValueChange(handle, value).catchError((Object _) {}),
    );
    provider.openResource = (resource, preserveFocus) =>
        _proxy.$executeResourceCommand(
          handle,
          resource.group.handle,
          resource.handle,
          preserveFocus,
        );
    _handles.add(provider.handle);
    _service.register(provider);
    if (provider.shown &&
        _service.shownProviders.firstOrNull?.handle == provider.handle) {
      unawaited(
        _proxy.$setSelectedSourceControl(handle).catchError((Object _) {}),
      );
    }
  }

  ScmProvider? _provider(num handle) => _service.provider(handle.toInt());

  @override
  void $updateSourceControl(num handle, Map<String, Object?> features) =>
      _provider(handle)?.updateFeatures(features);

  @override
  void $unregisterSourceControl(num handle) {
    _handles.remove(handle.toInt());
    _service.unregister(handle.toInt());
  }

  @override
  void $registerGroups(
    num sourceControlHandle,
    List<List<Object?>> groups,
    List<List<Object?>> splices,
  ) {
    final provider = _provider(sourceControlHandle);
    if (provider == null) return;
    provider
      ..registerGroups(groups)
      ..spliceResourceStates(splices);
  }

  @override
  void $updateGroup(
    num sourceControlHandle,
    num handle,
    Map<String, Object?> features,
  ) => _provider(sourceControlHandle)?.updateGroup(handle.toInt(), features);

  @override
  void $updateGroupLabel(num sourceControlHandle, num handle, String label) =>
      _provider(sourceControlHandle)?.updateGroupLabel(handle.toInt(), label);

  @override
  void $unregisterGroup(num sourceControlHandle, num handle) =>
      _provider(sourceControlHandle)?.unregisterGroup(handle.toInt());

  @override
  void $spliceResourceStates(
    num sourceControlHandle,
    List<List<Object?>> splices,
  ) => _provider(sourceControlHandle)?.spliceResourceStates(splices);

  @override
  void $setInputBoxValue(num sourceControlHandle, String value) =>
      _provider(sourceControlHandle)?.input.setValue(value);

  @override
  void $setInputBoxPlaceholder(num sourceControlHandle, String placeholder) =>
      _provider(sourceControlHandle)?.input.setPlaceholder(placeholder);

  @override
  void $setInputBoxEnablement(num sourceControlHandle, bool enabled) =>
      _provider(sourceControlHandle)?.input.setEnabled(enabled);

  @override
  void $setInputBoxVisibility(num sourceControlHandle, bool visible) =>
      _provider(sourceControlHandle)?.input.setVisible(visible);

  @override
  void $showValidationMessage(
    num sourceControlHandle,
    Object? message,
    int type,
  ) => _provider(sourceControlHandle)?.input.showValidationMessage((
    message: _text(message),
    type: _validationType(type),
  ));

  @override
  void $setValidationProviderIsEnabled(num sourceControlHandle, bool enabled) {
    final provider = _provider(sourceControlHandle);
    if (provider == null) return;
    provider.input.validate = !enabled
        ? null
        : (value, cursor) async {
            final result = await _proxy.$validateInput(
              sourceControlHandle,
              value,
              cursor,
            );
            if (result == null || result.length < 2) return null;
            return (
              message: _text(result[0]),
              type: _validationType((result[1]! as num).toInt()),
            );
          };
  }

  @override
  void $onDidChangeHistoryProviderCurrentHistoryItemRefs(
    num sourceControlHandle,
    Map<String, Object?>? historyItemRef,
    Map<String, Object?>? historyItemRemoteRef,
    Map<String, Object?>? historyItemBaseRef,
  ) {}

  @override
  void $onDidChangeHistoryProviderHistoryItemRefs(
    num sourceControlHandle,
    Map<String, Object?> historyItemRefs,
  ) {}

  @override
  void $onDidChangeArtifacts(num sourceControlHandle, List<String> groups) {}
}

String _text(Object? message) => switch (message) {
  final String s => s,
  {'value': final String s} => s,
  _ => '$message',
};

ScmInputValidationType _validationType(int type) => switch (type) {
  0 => ScmInputValidationType.error,
  1 => ScmInputValidationType.warning,
  _ => ScmInputValidationType.information,
};
