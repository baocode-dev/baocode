/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// GENERATED FILE - DO NOT EDIT. Regenerate with tool/generate_exthost_protocol.mjs.
//
// Proxies for the extension host's shapes (`ExtHost*Shape`): what the main
// thread calls.
//
// Generated from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/common/extHost.protocol.ts; proxy identifier numbers from the compiled
// out/vs/workbench/api/node/extensionHostProcess.js.

// ignore_for_file: non_constant_identifier_names

import '../base/cancellation.dart';
import '../base/uri.dart';
import '../rpc/rpc_args.dart';
import '../rpc/rpc_protocol.dart';
import 'proxy_identifiers.g.dart';

/// Calls `ExtHostCodeMapperShape` (`ExtHostCodeMapper`) in the extension host.
final class ExtHostCodeMapperProxy {
  ExtHostCodeMapperProxy(this._rpc);

  static const identifier = ExtHostContext.extHostCodeMapper;

  final RpcProtocol _rpc;

  /// `$mapCode(handle: number, request: ICodeMapperRequestDto, token: CancellationToken): Promise<ICodeMapperResult | null | undefined>`
  Future<Map<String, Object?>?> $mapCode(
    num handle,
    Map<String, Object?> request, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostCodeMapper.$mapCode',
    await _rpc.call(identifier.nid, r'$mapCode', [
      handle,
      request,
    ], token: token),
    decodeNullable(decodeMap),
  );
}

/// Calls `ExtHostCommandsShape` (`ExtHostCommands`) in the extension host.
final class ExtHostCommandsProxy {
  ExtHostCommandsProxy(this._rpc);

  static const identifier = ExtHostContext.extHostCommands;

  final RpcProtocol _rpc;

  /// `$executeContributedCommand(id: string, ...args: unknown[]): Promise<unknown>`
  Future<Object?> $executeContributedCommand(String id, List<Object?> args) =>
      _rpc.call(identifier.nid, r'$executeContributedCommand', [id, ...args]);

  /// `$getContributedCommandMetadata(): Promise<{ [id: string]: string | ICommandMetadataDto }>`
  Future<Map<String, Object?>> $getContributedCommandMetadata() async =>
      decodeReply(
        r'ExtHostCommands.$getContributedCommandMetadata',
        await _rpc.call(identifier.nid, r'$getContributedCommandMetadata', []),
        decodeMapOf(decodeObject),
      );
}

/// Calls `ExtHostConfigurationShape` (`ExtHostConfiguration`) in the extension host.
final class ExtHostConfigurationProxy {
  ExtHostConfigurationProxy(this._rpc);

  static const identifier = ExtHostContext.extHostConfiguration;

  final RpcProtocol _rpc;

  /// `$initializeConfiguration(data: IConfigurationInitData): void`
  Future<void> $initializeConfiguration(Map<String, Object?> data) =>
      _rpc.call(identifier.nid, r'$initializeConfiguration', [data]);

  /// `$acceptConfigurationChanged(data: IConfigurationInitData, change: IConfigurationChange): void`
  Future<void> $acceptConfigurationChanged(
    Map<String, Object?> data,
    Map<String, Object?> change,
  ) =>
      _rpc.call(identifier.nid, r'$acceptConfigurationChanged', [data, change]);
}

/// Calls `ExtHostDiagnosticsShape` (`ExtHostDiagnostics`) in the extension host.
final class ExtHostDiagnosticsProxy {
  ExtHostDiagnosticsProxy(this._rpc);

  static const identifier = ExtHostContext.extHostDiagnostics;

  final RpcProtocol _rpc;

  /// `$acceptMarkersChange(data: [UriComponents, IMarkerData[]][]): void`
  Future<void> $acceptMarkersChange(List<List<Object?>> data) =>
      _rpc.call(identifier.nid, r'$acceptMarkersChange', [data]);
}

/// Calls `ExtHostDebugServiceShape` (`ExtHostDebugService`) in the extension host.
final class ExtHostDebugServiceProxy {
  ExtHostDebugServiceProxy(this._rpc);

  static const identifier = ExtHostContext.extHostDebugService;

  final RpcProtocol _rpc;

  /// `$substituteVariables(folder: UriComponents | undefined, config: IConfig): Promise<IConfig>`
  Future<Map<String, Object?>> $substituteVariables(
    VsUri? folder,
    Map<String, Object?> config,
  ) async => decodeReply(
    r'ExtHostDebugService.$substituteVariables',
    await _rpc.call(identifier.nid, r'$substituteVariables', [
      folder ?? rpcUndefined,
      config,
    ]),
    decodeMap,
  );

  /// `$runInTerminal(args: DebugProtocol.RunInTerminalRequestArguments, sessionId: string): Promise<number | undefined>`
  Future<num?> $runInTerminal(
    Map<String, Object?> args,
    String sessionId,
  ) async => decodeReply(
    r'ExtHostDebugService.$runInTerminal',
    await _rpc.call(identifier.nid, r'$runInTerminal', [args, sessionId]),
    decodeNullable(decodeNum),
  );

  /// `$startDASession(handle: number, session: IDebugSessionDto): Promise<void>`
  Future<void> $startDASession(num handle, Object? session) =>
      _rpc.call(identifier.nid, r'$startDASession', [handle, session]);

  /// `$stopDASession(handle: number): Promise<void>`
  Future<void> $stopDASession(num handle) =>
      _rpc.call(identifier.nid, r'$stopDASession', [handle]);

  /// `$sendDAMessage(handle: number, message: DebugProtocol.ProtocolMessage): void`
  Future<void> $sendDAMessage(num handle, Map<String, Object?> message) =>
      _rpc.call(identifier.nid, r'$sendDAMessage', [handle, message]);

  /// `$resolveDebugConfiguration(handle: number, folder: UriComponents | undefined, debugConfiguration: IConfig, token: CancellationToken): Promise<IConfig | null | undefined>`
  Future<Map<String, Object?>?> $resolveDebugConfiguration(
    num handle,
    VsUri? folder,
    Map<String, Object?> debugConfiguration, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostDebugService.$resolveDebugConfiguration',
    await _rpc.call(identifier.nid, r'$resolveDebugConfiguration', [
      handle,
      folder ?? rpcUndefined,
      debugConfiguration,
    ], token: token),
    decodeNullable(decodeMap),
  );

  /// `$resolveDebugConfigurationWithSubstitutedVariables(handle: number, folder: UriComponents | undefined, debugConfiguration: IConfig, token: CancellationToken): Promise<IConfig | null | undefined>`
  Future<Map<String, Object?>?>
  $resolveDebugConfigurationWithSubstitutedVariables(
    num handle,
    VsUri? folder,
    Map<String, Object?> debugConfiguration, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostDebugService.$resolveDebugConfigurationWithSubstitutedVariables',
    await _rpc.call(
      identifier.nid,
      r'$resolveDebugConfigurationWithSubstitutedVariables',
      [handle, folder ?? rpcUndefined, debugConfiguration],
      token: token,
    ),
    decodeNullable(decodeMap),
  );

  /// `$provideDebugConfigurations(handle: number, folder: UriComponents | undefined, token: CancellationToken): Promise<IConfig[]>`
  Future<List<Map<String, Object?>>> $provideDebugConfigurations(
    num handle,
    VsUri? folder, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostDebugService.$provideDebugConfigurations',
    await _rpc.call(identifier.nid, r'$provideDebugConfigurations', [
      handle,
      folder ?? rpcUndefined,
    ], token: token),
    decodeListOf(decodeMap),
  );

  /// `$provideDebugAdapter(handle: number, session: IDebugSessionDto): Promise<Dto<IAdapterDescriptor>>`
  Future<Map<String, Object?>> $provideDebugAdapter(
    num handle,
    Object? session,
  ) async => decodeReply(
    r'ExtHostDebugService.$provideDebugAdapter',
    await _rpc.call(identifier.nid, r'$provideDebugAdapter', [handle, session]),
    decodeMap,
  );

  /// `$acceptDebugSessionStarted(session: IDebugSessionDto): void`
  Future<void> $acceptDebugSessionStarted(Object? session) =>
      _rpc.call(identifier.nid, r'$acceptDebugSessionStarted', [session]);

  /// `$acceptDebugSessionTerminated(session: IDebugSessionDto): void`
  Future<void> $acceptDebugSessionTerminated(Object? session) =>
      _rpc.call(identifier.nid, r'$acceptDebugSessionTerminated', [session]);

  /// `$acceptDebugSessionActiveChanged(session: IDebugSessionDto | undefined): void`
  Future<void> $acceptDebugSessionActiveChanged(Object? session) => _rpc.call(
    identifier.nid,
    r'$acceptDebugSessionActiveChanged',
    [session ?? rpcUndefined],
  );

  /// `$acceptDebugSessionCustomEvent(session: IDebugSessionDto, event: any): void`
  Future<void> $acceptDebugSessionCustomEvent(Object? session, Object? event) =>
      _rpc.call(identifier.nid, r'$acceptDebugSessionCustomEvent', [
        session,
        event,
      ]);

  /// `$acceptBreakpointsDelta(delta: IBreakpointsDeltaDto): void`
  Future<void> $acceptBreakpointsDelta(Map<String, Object?> delta) =>
      _rpc.call(identifier.nid, r'$acceptBreakpointsDelta', [delta]);

  /// `$acceptDebugSessionNameChanged(session: IDebugSessionDto, name: string): void`
  Future<void> $acceptDebugSessionNameChanged(Object? session, String name) =>
      _rpc.call(identifier.nid, r'$acceptDebugSessionNameChanged', [
        session,
        name,
      ]);

  /// `$acceptStackFrameFocus(focus: IThreadFocusDto | IStackFrameFocusDto | undefined): void`
  Future<void> $acceptStackFrameFocus(Map<String, Object?>? focus) => _rpc.call(
    identifier.nid,
    r'$acceptStackFrameFocus',
    [focus ?? rpcUndefined],
  );

  /// `$provideDebugVisualizers(extensionId: string, id: string, context: IDebugVisualizationContext, token: CancellationToken): Promise<IDebugVisualization.Serialized[]>`
  Future<List<Map<String, Object?>>> $provideDebugVisualizers(
    String extensionId,
    String id,
    Map<String, Object?> context, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostDebugService.$provideDebugVisualizers',
    await _rpc.call(identifier.nid, r'$provideDebugVisualizers', [
      extensionId,
      id,
      context,
    ], token: token),
    decodeListOf(decodeMap),
  );

  /// `$resolveDebugVisualizer(id: number, token: CancellationToken): Promise<MainThreadDebugVisualization>`
  Future<Map<String, Object?>> $resolveDebugVisualizer(
    num id, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostDebugService.$resolveDebugVisualizer',
    await _rpc.call(identifier.nid, r'$resolveDebugVisualizer', [
      id,
    ], token: token),
    decodeMap,
  );

  /// `$executeDebugVisualizerCommand(id: number): Promise<void>`
  Future<void> $executeDebugVisualizerCommand(num id) =>
      _rpc.call(identifier.nid, r'$executeDebugVisualizerCommand', [id]);

  /// `$disposeDebugVisualizers(ids: number[]): void`
  Future<void> $disposeDebugVisualizers(List<num> ids) =>
      _rpc.call(identifier.nid, r'$disposeDebugVisualizers', [ids]);

  /// `$getVisualizerTreeItem(treeId: string, element: IDebugVisualizationContext): Promise<IDebugVisualizationTreeItem.Serialized | undefined>`
  Future<Map<String, Object?>?> $getVisualizerTreeItem(
    String treeId,
    Map<String, Object?> element,
  ) async => decodeReply(
    r'ExtHostDebugService.$getVisualizerTreeItem',
    await _rpc.call(identifier.nid, r'$getVisualizerTreeItem', [
      treeId,
      element,
    ]),
    decodeNullable(decodeMap),
  );

  /// `$getVisualizerTreeItemChildren(treeId: string, element: number): Promise<IDebugVisualizationTreeItem.Serialized[]>`
  Future<List<Map<String, Object?>>> $getVisualizerTreeItemChildren(
    String treeId,
    num element,
  ) async => decodeReply(
    r'ExtHostDebugService.$getVisualizerTreeItemChildren',
    await _rpc.call(identifier.nid, r'$getVisualizerTreeItemChildren', [
      treeId,
      element,
    ]),
    decodeListOf(decodeMap),
  );

  /// `$editVisualizerTreeItem(element: number, value: string): Promise<IDebugVisualizationTreeItem.Serialized | undefined>`
  Future<Map<String, Object?>?> $editVisualizerTreeItem(
    num element,
    String value,
  ) async => decodeReply(
    r'ExtHostDebugService.$editVisualizerTreeItem',
    await _rpc.call(identifier.nid, r'$editVisualizerTreeItem', [
      element,
      value,
    ]),
    decodeNullable(decodeMap),
  );

  /// `$disposeVisualizedTree(element: number): void`
  Future<void> $disposeVisualizedTree(num element) =>
      _rpc.call(identifier.nid, r'$disposeVisualizedTree', [element]);
}

/// Calls `ExtHostDecorationsShape` (`ExtHostDecorations`) in the extension host.
final class ExtHostDecorationsProxy {
  ExtHostDecorationsProxy(this._rpc);

  static const identifier = ExtHostContext.extHostDecorations;

  final RpcProtocol _rpc;

  /// `$provideDecorations(handle: number, requests: DecorationRequest[], token: CancellationToken): Promise<DecorationReply>`
  Future<Map<String, List<Object?>>> $provideDecorations(
    num handle,
    List<Map<String, Object?>> requests, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostDecorations.$provideDecorations',
    await _rpc.call(identifier.nid, r'$provideDecorations', [
      handle,
      requests,
    ], token: token),
    decodeMapOf(decodeListOf(decodeObject)),
  );
}

/// Calls `ExtHostDocumentsAndEditorsShape` (`ExtHostDocumentsAndEditors`) in the extension host.
final class ExtHostDocumentsAndEditorsProxy {
  ExtHostDocumentsAndEditorsProxy(this._rpc);

  static const identifier = ExtHostContext.extHostDocumentsAndEditors;

  final RpcProtocol _rpc;

  /// `$acceptDocumentsAndEditorsDelta(delta: IDocumentsAndEditorsDelta): void`
  Future<void> $acceptDocumentsAndEditorsDelta(Map<String, Object?> delta) =>
      _rpc.call(identifier.nid, r'$acceptDocumentsAndEditorsDelta', [delta]);
}

/// Calls `ExtHostDocumentsShape` (`ExtHostDocuments`) in the extension host.
final class ExtHostDocumentsProxy {
  ExtHostDocumentsProxy(this._rpc);

  static const identifier = ExtHostContext.extHostDocuments;

  final RpcProtocol _rpc;

  /// `$acceptModelLanguageChanged(strURL: UriComponents, newLanguageId: string): void`
  Future<void> $acceptModelLanguageChanged(
    VsUri strURL,
    String newLanguageId,
  ) => _rpc.call(identifier.nid, r'$acceptModelLanguageChanged', [
    strURL,
    newLanguageId,
  ]);

  /// `$acceptModelSaved(strURL: UriComponents): void`
  Future<void> $acceptModelSaved(VsUri strURL) =>
      _rpc.call(identifier.nid, r'$acceptModelSaved', [strURL]);

  /// `$acceptDirtyStateChanged(strURL: UriComponents, isDirty: boolean): void`
  Future<void> $acceptDirtyStateChanged(VsUri strURL, bool isDirty) =>
      _rpc.call(identifier.nid, r'$acceptDirtyStateChanged', [strURL, isDirty]);

  /// `$acceptEncodingChanged(strURL: UriComponents, encoding: string): void`
  Future<void> $acceptEncodingChanged(VsUri strURL, String encoding) =>
      _rpc.call(identifier.nid, r'$acceptEncodingChanged', [strURL, encoding]);

  /// `$acceptModelChanged(strURL: UriComponents, e: ISerializedModelContentChangedEvent, isDirty: boolean): void`
  Future<void> $acceptModelChanged(
    VsUri strURL,
    Map<String, Object?> e,
    bool isDirty,
  ) => _rpc.call(identifier.nid, r'$acceptModelChanged', [strURL, e, isDirty]);
}

/// Calls `ExtHostDocumentContentProvidersShape` (`ExtHostDocumentContentProviders`) in the extension host.
final class ExtHostDocumentContentProvidersProxy {
  ExtHostDocumentContentProvidersProxy(this._rpc);

  static const identifier = ExtHostContext.extHostDocumentContentProviders;

  final RpcProtocol _rpc;

  /// `$provideTextDocumentContent(handle: number, uri: UriComponents): Promise<string | null | undefined>`
  Future<String?> $provideTextDocumentContent(num handle, VsUri uri) async =>
      decodeReply(
        r'ExtHostDocumentContentProviders.$provideTextDocumentContent',
        await _rpc.call(identifier.nid, r'$provideTextDocumentContent', [
          handle,
          uri,
        ]),
        decodeNullable(decodeString),
      );
}

/// Calls `ExtHostDocumentSaveParticipantShape` (`ExtHostDocumentSaveParticipant`) in the extension host.
final class ExtHostDocumentSaveParticipantProxy {
  ExtHostDocumentSaveParticipantProxy(this._rpc);

  static const identifier = ExtHostContext.extHostDocumentSaveParticipant;

  final RpcProtocol _rpc;

  /// `$participateInSave(resource: UriComponents, reason: SaveReason): Promise<boolean[]>`
  Future<List<bool>> $participateInSave(VsUri resource, int reason) async =>
      decodeReply(
        r'ExtHostDocumentSaveParticipant.$participateInSave',
        await _rpc.call(identifier.nid, r'$participateInSave', [
          resource,
          reason,
        ]),
        decodeListOf(decodeBool),
      );
}

/// Calls `ExtHostEditorsShape` (`ExtHostEditors`) in the extension host.
final class ExtHostEditorsProxy {
  ExtHostEditorsProxy(this._rpc);

  static const identifier = ExtHostContext.extHostEditors;

  final RpcProtocol _rpc;

  /// `$acceptEditorPropertiesChanged(id: string, props: IEditorPropertiesChangeData): void`
  Future<void> $acceptEditorPropertiesChanged(
    String id,
    Map<String, Object?> props,
  ) =>
      _rpc.call(identifier.nid, r'$acceptEditorPropertiesChanged', [id, props]);

  /// `$acceptEditorPositionData(data: ITextEditorPositionData): void`
  Future<void> $acceptEditorPositionData(Map<String, Object?> data) =>
      _rpc.call(identifier.nid, r'$acceptEditorPositionData', [data]);

  /// `$acceptEditorDiffInformation(id: string, diffInformation: ITextEditorDiffInformation[] | undefined): void`
  Future<void> $acceptEditorDiffInformation(
    String id,
    List<Map<String, Object?>>? diffInformation,
  ) => _rpc.call(identifier.nid, r'$acceptEditorDiffInformation', [
    id,
    diffInformation ?? rpcUndefined,
  ]);
}

/// Calls `ExtHostTreeViewsShape` (`ExtHostTreeViews`) in the extension host.
final class ExtHostTreeViewsProxy {
  ExtHostTreeViewsProxy(this._rpc);

  static const identifier = ExtHostContext.extHostTreeViews;

  final RpcProtocol _rpc;

  /// To reduce what is sent on the wire:
  /// w
  /// x
  /// y
  /// z
  ///
  /// for [x,y] returns
  /// [[1,z]], where the inner array is [original index, ...children]
  ///
  /// `$getChildren(treeViewId: string, treeItemHandles?: string[]): Promise<(readonly (number | ITreeItem)[])[] | undefined>`
  Future<List<List<Object?>>?> $getChildren(
    String treeViewId, [
    List<String>? treeItemHandles,
  ]) async => decodeReply(
    r'ExtHostTreeViews.$getChildren',
    await _rpc.call(identifier.nid, r'$getChildren', [
      treeViewId,
      treeItemHandles ?? rpcUndefined,
    ]),
    decodeNullable(decodeListOf(decodeListOf(decodeObject))),
  );

  /// `$handleDrop(destinationViewId: string, requestId: number, treeDataTransfer: DataTransferDTO, targetHandle: string | undefined, token: CancellationToken, operationUuid?: string, sourceViewId?: string, sourceTreeItemHandles?: string[]): Promise<void>`
  Future<void> $handleDrop(
    String destinationViewId,
    num requestId,
    Map<String, Object?> treeDataTransfer,
    String? targetHandle,
    CancellationToken? tokenArg, [
    String? operationUuid,
    String? sourceViewId,
    List<String>? sourceTreeItemHandles,
  ]) => _rpc.call(identifier.nid, r'$handleDrop', [
    destinationViewId,
    requestId,
    treeDataTransfer,
    targetHandle ?? rpcUndefined,
    encodeInlineToken(tokenArg),
    operationUuid ?? rpcUndefined,
    sourceViewId ?? rpcUndefined,
    sourceTreeItemHandles ?? rpcUndefined,
  ]);

  /// `$handleDrag(sourceViewId: string, sourceTreeItemHandles: string[], operationUuid: string, token: CancellationToken): Promise<DataTransferDTO | undefined>`
  Future<Map<String, Object?>?> $handleDrag(
    String sourceViewId,
    List<String> sourceTreeItemHandles,
    String operationUuid, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostTreeViews.$handleDrag',
    await _rpc.call(identifier.nid, r'$handleDrag', [
      sourceViewId,
      sourceTreeItemHandles,
      operationUuid,
    ], token: token),
    decodeNullable(decodeMap),
  );

  /// `$setExpanded(treeViewId: string, treeItemHandle: string, expanded: boolean): void`
  Future<void> $setExpanded(
    String treeViewId,
    String treeItemHandle,
    bool expanded,
  ) => _rpc.call(identifier.nid, r'$setExpanded', [
    treeViewId,
    treeItemHandle,
    expanded,
  ]);

  /// `$setSelectionAndFocus(treeViewId: string, selectionHandles: string[], focusHandle: string): void`
  Future<void> $setSelectionAndFocus(
    String treeViewId,
    List<String> selectionHandles,
    String focusHandle,
  ) => _rpc.call(identifier.nid, r'$setSelectionAndFocus', [
    treeViewId,
    selectionHandles,
    focusHandle,
  ]);

  /// `$setVisible(treeViewId: string, visible: boolean): void`
  Future<void> $setVisible(String treeViewId, bool visible) =>
      _rpc.call(identifier.nid, r'$setVisible', [treeViewId, visible]);

  /// `$changeCheckboxState(treeViewId: string, checkboxUpdates: CheckboxUpdate[]): void`
  Future<void> $changeCheckboxState(
    String treeViewId,
    List<Map<String, Object?>> checkboxUpdates,
  ) => _rpc.call(identifier.nid, r'$changeCheckboxState', [
    treeViewId,
    checkboxUpdates,
  ]);

  /// `$hasResolve(treeViewId: string): Promise<boolean>`
  Future<bool> $hasResolve(String treeViewId) async => decodeReply(
    r'ExtHostTreeViews.$hasResolve',
    await _rpc.call(identifier.nid, r'$hasResolve', [treeViewId]),
    decodeBool,
  );

  /// `$resolve(treeViewId: string, treeItemHandle: string, token: CancellationToken): Promise<ITreeItem | undefined>`
  Future<Map<String, Object?>?> $resolve(
    String treeViewId,
    String treeItemHandle, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostTreeViews.$resolve',
    await _rpc.call(identifier.nid, r'$resolve', [
      treeViewId,
      treeItemHandle,
    ], token: token),
    decodeNullable(decodeMap),
  );
}

/// Calls `ExtHostFileSystemShape` (`ExtHostFileSystem`) in the extension host.
final class ExtHostFileSystemProxy {
  ExtHostFileSystemProxy(this._rpc);

  static const identifier = ExtHostContext.extHostFileSystem;

  final RpcProtocol _rpc;

  /// `$stat(handle: number, resource: UriComponents): Promise<files.IStat>`
  Future<Map<String, Object?>> $stat(num handle, VsUri resource) async =>
      decodeReply(
        r'ExtHostFileSystem.$stat',
        await _rpc.call(identifier.nid, r'$stat', [handle, resource]),
        decodeMap,
      );

  /// `$readdir(handle: number, resource: UriComponents): Promise<[string, files.FileType][]>`
  Future<List<List<Object?>>> $readdir(num handle, VsUri resource) async =>
      decodeReply(
        r'ExtHostFileSystem.$readdir',
        await _rpc.call(identifier.nid, r'$readdir', [handle, resource]),
        decodeListOf(decodeListOf(decodeObject)),
      );

  /// `$readFile(handle: number, resource: UriComponents): Promise<VSBuffer>`
  Future<RpcBuffer> $readFile(num handle, VsUri resource) async => decodeReply(
    r'ExtHostFileSystem.$readFile',
    await _rpc.call(identifier.nid, r'$readFile', [handle, resource]),
    decodeBuffer,
  );

  /// `$writeFile(handle: number, resource: UriComponents, content: VSBuffer, opts: files.IFileWriteOptions): Promise<void>`
  Future<void> $writeFile(
    num handle,
    VsUri resource,
    RpcBuffer content,
    Map<String, Object?> opts,
  ) => _rpc.call(identifier.nid, r'$writeFile', [
    handle,
    resource,
    content,
    opts,
  ]);

  /// `$rename(handle: number, resource: UriComponents, target: UriComponents, opts: files.IFileOverwriteOptions): Promise<void>`
  Future<void> $rename(
    num handle,
    VsUri resource,
    VsUri target,
    Map<String, Object?> opts,
  ) => _rpc.call(identifier.nid, r'$rename', [handle, resource, target, opts]);

  /// `$copy(handle: number, resource: UriComponents, target: UriComponents, opts: files.IFileOverwriteOptions): Promise<void>`
  Future<void> $copy(
    num handle,
    VsUri resource,
    VsUri target,
    Map<String, Object?> opts,
  ) => _rpc.call(identifier.nid, r'$copy', [handle, resource, target, opts]);

  /// `$mkdir(handle: number, resource: UriComponents): Promise<void>`
  Future<void> $mkdir(num handle, VsUri resource) =>
      _rpc.call(identifier.nid, r'$mkdir', [handle, resource]);

  /// `$delete(handle: number, resource: UriComponents, opts: files.IFileDeleteOptions): Promise<void>`
  Future<void> $delete(num handle, VsUri resource, Map<String, Object?> opts) =>
      _rpc.call(identifier.nid, r'$delete', [handle, resource, opts]);

  /// `$watch(handle: number, session: number, resource: UriComponents, opts: files.IWatchOptions): void`
  Future<void> $watch(
    num handle,
    num session,
    VsUri resource,
    Map<String, Object?> opts,
  ) => _rpc.call(identifier.nid, r'$watch', [handle, session, resource, opts]);

  /// `$unwatch(handle: number, session: number): void`
  Future<void> $unwatch(num handle, num session) =>
      _rpc.call(identifier.nid, r'$unwatch', [handle, session]);

  /// `$open(handle: number, resource: UriComponents, opts: files.IFileOpenOptions): Promise<number>`
  Future<num> $open(
    num handle,
    VsUri resource,
    Map<String, Object?> opts,
  ) async => decodeReply(
    r'ExtHostFileSystem.$open',
    await _rpc.call(identifier.nid, r'$open', [handle, resource, opts]),
    decodeNum,
  );

  /// `$close(handle: number, fd: number): Promise<void>`
  Future<void> $close(num handle, num fd) =>
      _rpc.call(identifier.nid, r'$close', [handle, fd]);

  /// `$read(handle: number, fd: number, pos: number, length: number): Promise<VSBuffer>`
  Future<RpcBuffer> $read(num handle, num fd, num pos, num length) async =>
      decodeReply(
        r'ExtHostFileSystem.$read',
        await _rpc.call(identifier.nid, r'$read', [handle, fd, pos, length]),
        decodeBuffer,
      );

  /// `$write(handle: number, fd: number, pos: number, data: VSBuffer): Promise<number>`
  Future<num> $write(num handle, num fd, num pos, RpcBuffer data) async =>
      decodeReply(
        r'ExtHostFileSystem.$write',
        await _rpc.call(identifier.nid, r'$write', [handle, fd, pos, data]),
        decodeNum,
      );
}

/// Calls `ExtHostFileSystemInfoShape` (`ExtHostFileSystemInfo`) in the extension host.
final class ExtHostFileSystemInfoProxy {
  ExtHostFileSystemInfoProxy(this._rpc);

  static const identifier = ExtHostContext.extHostFileSystemInfo;

  final RpcProtocol _rpc;

  /// `$acceptProviderInfos(uri: UriComponents, capabilities: number | null): void`
  Future<void> $acceptProviderInfos(VsUri uri, num? capabilities) =>
      _rpc.call(identifier.nid, r'$acceptProviderInfos', [uri, capabilities]);
}

/// Calls `ExtHostFileSystemEventServiceShape` (`ExtHostFileSystemEventService`) in the extension host.
final class ExtHostFileSystemEventServiceProxy {
  ExtHostFileSystemEventServiceProxy(this._rpc);

  static const identifier = ExtHostContext.extHostFileSystemEventService;

  final RpcProtocol _rpc;

  /// `$onFileEvent(events: FileSystemEvents): void`
  Future<void> $onFileEvent(Map<String, Object?> events) =>
      _rpc.call(identifier.nid, r'$onFileEvent', [events]);

  /// `$onWillRunFileOperation(operation: files.FileOperation, files: readonly SourceTargetPair[], timeout: number, token: CancellationToken): Promise<IWillRunFileOperationParticipation | undefined>`
  Future<Map<String, Object?>?> $onWillRunFileOperation(
    int operation,
    List<Map<String, Object?>> files,
    num timeout, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostFileSystemEventService.$onWillRunFileOperation',
    await _rpc.call(identifier.nid, r'$onWillRunFileOperation', [
      operation,
      files,
      timeout,
    ], token: token),
    decodeNullable(decodeMap),
  );

  /// `$onDidRunFileOperation(operation: files.FileOperation, files: readonly SourceTargetPair[]): void`
  Future<void> $onDidRunFileOperation(
    int operation,
    List<Map<String, Object?>> files,
  ) => _rpc.call(identifier.nid, r'$onDidRunFileOperation', [operation, files]);
}

/// Calls `ExtHostLanguagesShape` (`ExtHostLanguages`) in the extension host.
final class ExtHostLanguagesProxy {
  ExtHostLanguagesProxy(this._rpc);

  static const identifier = ExtHostContext.extHostLanguages;

  final RpcProtocol _rpc;

  /// `$acceptLanguageIds(ids: string[]): void`
  Future<void> $acceptLanguageIds(List<String> ids) =>
      _rpc.call(identifier.nid, r'$acceptLanguageIds', [ids]);

  /// `$acceptSyntaxHighlightingThemeChanged(): void`
  Future<void> $acceptSyntaxHighlightingThemeChanged() =>
      _rpc.call(identifier.nid, r'$acceptSyntaxHighlightingThemeChanged', []);
}

/// Calls `ExtHostLanguageFeaturesShape` (`ExtHostLanguageFeatures`) in the extension host.
final class ExtHostLanguageFeaturesProxy {
  ExtHostLanguageFeaturesProxy(this._rpc);

  static const identifier = ExtHostContext.extHostLanguageFeatures;

  final RpcProtocol _rpc;

  /// `$provideDocumentSymbols(handle: number, resource: UriComponents, token: CancellationToken): Promise<languages.DocumentSymbol[] | undefined>`
  Future<List<Map<String, Object?>>?> $provideDocumentSymbols(
    num handle,
    VsUri resource, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostLanguageFeatures.$provideDocumentSymbols',
    await _rpc.call(identifier.nid, r'$provideDocumentSymbols', [
      handle,
      resource,
    ], token: token),
    decodeNullable(decodeListOf(decodeMap)),
  );

  /// `$provideCodeLenses(handle: number, resource: UriComponents, token: CancellationToken): Promise<ICodeLensListDto | undefined>`
  Future<Map<String, Object?>?> $provideCodeLenses(
    num handle,
    VsUri resource, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostLanguageFeatures.$provideCodeLenses',
    await _rpc.call(identifier.nid, r'$provideCodeLenses', [
      handle,
      resource,
    ], token: token),
    decodeNullable(decodeMap),
  );

  /// `$resolveCodeLens(handle: number, symbol: ICodeLensDto, token: CancellationToken): Promise<ICodeLensDto | undefined>`
  Future<Map<String, Object?>?> $resolveCodeLens(
    num handle,
    Map<String, Object?> symbol, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostLanguageFeatures.$resolveCodeLens',
    await _rpc.call(identifier.nid, r'$resolveCodeLens', [
      handle,
      symbol,
    ], token: token),
    decodeNullable(decodeMap),
  );

  /// `$releaseCodeLenses(handle: number, id: number): void`
  Future<void> $releaseCodeLenses(num handle, num id) =>
      _rpc.call(identifier.nid, r'$releaseCodeLenses', [handle, id]);

  /// `$provideDefinition(handle: number, resource: UriComponents, position: IPosition, token: CancellationToken): Promise<ILocationLinkDto[]>`
  Future<List<Map<String, Object?>>> $provideDefinition(
    num handle,
    VsUri resource,
    Map<String, Object?> position, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostLanguageFeatures.$provideDefinition',
    await _rpc.call(identifier.nid, r'$provideDefinition', [
      handle,
      resource,
      position,
    ], token: token),
    decodeListOf(decodeMap),
  );

  /// `$provideDeclaration(handle: number, resource: UriComponents, position: IPosition, token: CancellationToken): Promise<ILocationLinkDto[]>`
  Future<List<Map<String, Object?>>> $provideDeclaration(
    num handle,
    VsUri resource,
    Map<String, Object?> position, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostLanguageFeatures.$provideDeclaration',
    await _rpc.call(identifier.nid, r'$provideDeclaration', [
      handle,
      resource,
      position,
    ], token: token),
    decodeListOf(decodeMap),
  );

  /// `$provideImplementation(handle: number, resource: UriComponents, position: IPosition, token: CancellationToken): Promise<ILocationLinkDto[]>`
  Future<List<Map<String, Object?>>> $provideImplementation(
    num handle,
    VsUri resource,
    Map<String, Object?> position, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostLanguageFeatures.$provideImplementation',
    await _rpc.call(identifier.nid, r'$provideImplementation', [
      handle,
      resource,
      position,
    ], token: token),
    decodeListOf(decodeMap),
  );

  /// `$provideTypeDefinition(handle: number, resource: UriComponents, position: IPosition, token: CancellationToken): Promise<ILocationLinkDto[]>`
  Future<List<Map<String, Object?>>> $provideTypeDefinition(
    num handle,
    VsUri resource,
    Map<String, Object?> position, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostLanguageFeatures.$provideTypeDefinition',
    await _rpc.call(identifier.nid, r'$provideTypeDefinition', [
      handle,
      resource,
      position,
    ], token: token),
    decodeListOf(decodeMap),
  );

  /// `$provideHover(handle: number, resource: UriComponents, position: IPosition, context: languages.HoverContext<{ id: number }> | undefined, token: CancellationToken): Promise<HoverWithId | undefined>`
  Future<Map<String, Object?>?> $provideHover(
    num handle,
    VsUri resource,
    Map<String, Object?> position,
    Map<String, Object?>? context, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostLanguageFeatures.$provideHover',
    await _rpc.call(identifier.nid, r'$provideHover', [
      handle,
      resource,
      position,
      context ?? rpcUndefined,
    ], token: token),
    decodeNullable(decodeMap),
  );

  /// `$releaseHover(handle: number, id: number): void`
  Future<void> $releaseHover(num handle, num id) =>
      _rpc.call(identifier.nid, r'$releaseHover', [handle, id]);

  /// `$provideEvaluatableExpression(handle: number, resource: UriComponents, position: IPosition, token: CancellationToken): Promise<languages.EvaluatableExpression | undefined>`
  Future<Map<String, Object?>?> $provideEvaluatableExpression(
    num handle,
    VsUri resource,
    Map<String, Object?> position, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostLanguageFeatures.$provideEvaluatableExpression',
    await _rpc.call(identifier.nid, r'$provideEvaluatableExpression', [
      handle,
      resource,
      position,
    ], token: token),
    decodeNullable(decodeMap),
  );

  /// `$provideInlineValues(handle: number, resource: UriComponents, range: IRange, context: languages.InlineValueContext, token: CancellationToken): Promise<languages.InlineValue[] | undefined>`
  Future<List<Map<String, Object?>>?> $provideInlineValues(
    num handle,
    VsUri resource,
    Map<String, Object?> range,
    Map<String, Object?> context, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostLanguageFeatures.$provideInlineValues',
    await _rpc.call(identifier.nid, r'$provideInlineValues', [
      handle,
      resource,
      range,
      context,
    ], token: token),
    decodeNullable(decodeListOf(decodeMap)),
  );

  /// `$provideDocumentHighlights(handle: number, resource: UriComponents, position: IPosition, token: CancellationToken): Promise<languages.DocumentHighlight[] | undefined>`
  Future<List<Map<String, Object?>>?> $provideDocumentHighlights(
    num handle,
    VsUri resource,
    Map<String, Object?> position, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostLanguageFeatures.$provideDocumentHighlights',
    await _rpc.call(identifier.nid, r'$provideDocumentHighlights', [
      handle,
      resource,
      position,
    ], token: token),
    decodeNullable(decodeListOf(decodeMap)),
  );

  /// `$provideMultiDocumentHighlights(handle: number, resource: UriComponents, position: IPosition, otherModels: UriComponents[], token: CancellationToken): Promise<Dto<languages.MultiDocumentHighlight[]> | undefined>`
  Future<List<Map<String, Object?>>?> $provideMultiDocumentHighlights(
    num handle,
    VsUri resource,
    Map<String, Object?> position,
    List<VsUri> otherModels, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostLanguageFeatures.$provideMultiDocumentHighlights',
    await _rpc.call(identifier.nid, r'$provideMultiDocumentHighlights', [
      handle,
      resource,
      position,
      otherModels,
    ], token: token),
    decodeNullable(decodeListOf(decodeMap)),
  );

  /// `$provideLinkedEditingRanges(handle: number, resource: UriComponents, position: IPosition, token: CancellationToken): Promise<ILinkedEditingRangesDto | undefined>`
  Future<Map<String, Object?>?> $provideLinkedEditingRanges(
    num handle,
    VsUri resource,
    Map<String, Object?> position, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostLanguageFeatures.$provideLinkedEditingRanges',
    await _rpc.call(identifier.nid, r'$provideLinkedEditingRanges', [
      handle,
      resource,
      position,
    ], token: token),
    decodeNullable(decodeMap),
  );

  /// `$provideReferences(handle: number, resource: UriComponents, position: IPosition, context: languages.ReferenceContext, token: CancellationToken): Promise<ILocationDto[] | undefined>`
  Future<List<Map<String, Object?>>?> $provideReferences(
    num handle,
    VsUri resource,
    Map<String, Object?> position,
    Map<String, Object?> context, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostLanguageFeatures.$provideReferences',
    await _rpc.call(identifier.nid, r'$provideReferences', [
      handle,
      resource,
      position,
      context,
    ], token: token),
    decodeNullable(decodeListOf(decodeMap)),
  );

  /// `$provideCodeActions(handle: number, resource: UriComponents, rangeOrSelection: IRange | ISelection, context: languages.CodeActionContext, token: CancellationToken): Promise<ICodeActionListDto | undefined>`
  Future<Map<String, Object?>?> $provideCodeActions(
    num handle,
    VsUri resource,
    Map<String, Object?> rangeOrSelection,
    Map<String, Object?> context, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostLanguageFeatures.$provideCodeActions',
    await _rpc.call(identifier.nid, r'$provideCodeActions', [
      handle,
      resource,
      rangeOrSelection,
      context,
    ], token: token),
    decodeNullable(decodeMap),
  );

  /// `$resolveCodeAction(handle: number, id: ChainedCacheId, token: CancellationToken): Promise<{ edit?: IWorkspaceEditDto; command?: ICommandDto }>`
  Future<Map<String, Object?>> $resolveCodeAction(
    num handle,
    List<Object?> id, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostLanguageFeatures.$resolveCodeAction',
    await _rpc.call(identifier.nid, r'$resolveCodeAction', [
      handle,
      id,
    ], token: token),
    decodeMap,
  );

  /// `$releaseCodeActions(handle: number, cacheId: number): void`
  Future<void> $releaseCodeActions(num handle, num cacheId) =>
      _rpc.call(identifier.nid, r'$releaseCodeActions', [handle, cacheId]);

  /// `$prepareDocumentPaste(handle: number, uri: UriComponents, ranges: readonly IRange[], dataTransfer: DataTransferDTO, token: CancellationToken): Promise<DataTransferDTO | undefined>`
  Future<Map<String, Object?>?> $prepareDocumentPaste(
    num handle,
    VsUri uri,
    List<Map<String, Object?>> ranges,
    Map<String, Object?> dataTransfer, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostLanguageFeatures.$prepareDocumentPaste',
    await _rpc.call(identifier.nid, r'$prepareDocumentPaste', [
      handle,
      uri,
      ranges,
      dataTransfer,
    ], token: token),
    decodeNullable(decodeMap),
  );

  /// `$providePasteEdits(handle: number, requestId: number, uri: UriComponents, ranges: IRange[], dataTransfer: DataTransferDTO, context: IDocumentPasteContextDto, token: CancellationToken): Promise<IPasteEditDto[] | undefined>`
  Future<List<Map<String, Object?>>?> $providePasteEdits(
    num handle,
    num requestId,
    VsUri uri,
    List<Map<String, Object?>> ranges,
    Map<String, Object?> dataTransfer,
    Map<String, Object?> context, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostLanguageFeatures.$providePasteEdits',
    await _rpc.call(identifier.nid, r'$providePasteEdits', [
      handle,
      requestId,
      uri,
      ranges,
      dataTransfer,
      context,
    ], token: token),
    decodeNullable(decodeListOf(decodeMap)),
  );

  /// `$resolvePasteEdit(handle: number, id: ChainedCacheId, token: CancellationToken): Promise<{ insertText?: string; additionalEdit?: IWorkspaceEditDto }>`
  Future<Map<String, Object?>> $resolvePasteEdit(
    num handle,
    List<Object?> id, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostLanguageFeatures.$resolvePasteEdit',
    await _rpc.call(identifier.nid, r'$resolvePasteEdit', [
      handle,
      id,
    ], token: token),
    decodeMap,
  );

  /// `$releasePasteEdits(handle: number, cacheId: number): void`
  Future<void> $releasePasteEdits(num handle, num cacheId) =>
      _rpc.call(identifier.nid, r'$releasePasteEdits', [handle, cacheId]);

  /// `$provideDocumentFormattingEdits(handle: number, resource: UriComponents, options: languages.FormattingOptions, token: CancellationToken): Promise<languages.TextEdit[] | undefined>`
  Future<List<Map<String, Object?>>?> $provideDocumentFormattingEdits(
    num handle,
    VsUri resource,
    Map<String, Object?> options, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostLanguageFeatures.$provideDocumentFormattingEdits',
    await _rpc.call(identifier.nid, r'$provideDocumentFormattingEdits', [
      handle,
      resource,
      options,
    ], token: token),
    decodeNullable(decodeListOf(decodeMap)),
  );

  /// `$provideDocumentRangeFormattingEdits(handle: number, resource: UriComponents, range: IRange, options: languages.FormattingOptions, token: CancellationToken): Promise<languages.TextEdit[] | undefined>`
  Future<List<Map<String, Object?>>?> $provideDocumentRangeFormattingEdits(
    num handle,
    VsUri resource,
    Map<String, Object?> range,
    Map<String, Object?> options, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostLanguageFeatures.$provideDocumentRangeFormattingEdits',
    await _rpc.call(identifier.nid, r'$provideDocumentRangeFormattingEdits', [
      handle,
      resource,
      range,
      options,
    ], token: token),
    decodeNullable(decodeListOf(decodeMap)),
  );

  /// `$provideDocumentRangesFormattingEdits(handle: number, resource: UriComponents, range: IRange[], options: languages.FormattingOptions, token: CancellationToken): Promise<languages.TextEdit[] | undefined>`
  Future<List<Map<String, Object?>>?> $provideDocumentRangesFormattingEdits(
    num handle,
    VsUri resource,
    List<Map<String, Object?>> range,
    Map<String, Object?> options, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostLanguageFeatures.$provideDocumentRangesFormattingEdits',
    await _rpc.call(identifier.nid, r'$provideDocumentRangesFormattingEdits', [
      handle,
      resource,
      range,
      options,
    ], token: token),
    decodeNullable(decodeListOf(decodeMap)),
  );

  /// `$provideOnTypeFormattingEdits(handle: number, resource: UriComponents, position: IPosition, ch: string, options: languages.FormattingOptions, token: CancellationToken): Promise<languages.TextEdit[] | undefined>`
  Future<List<Map<String, Object?>>?> $provideOnTypeFormattingEdits(
    num handle,
    VsUri resource,
    Map<String, Object?> position,
    String ch,
    Map<String, Object?> options, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostLanguageFeatures.$provideOnTypeFormattingEdits',
    await _rpc.call(identifier.nid, r'$provideOnTypeFormattingEdits', [
      handle,
      resource,
      position,
      ch,
      options,
    ], token: token),
    decodeNullable(decodeListOf(decodeMap)),
  );

  /// `$provideWorkspaceSymbols(handle: number, search: string, token: CancellationToken): Promise<IWorkspaceSymbolsDto>`
  Future<Map<String, Object?>> $provideWorkspaceSymbols(
    num handle,
    String search, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostLanguageFeatures.$provideWorkspaceSymbols',
    await _rpc.call(identifier.nid, r'$provideWorkspaceSymbols', [
      handle,
      search,
    ], token: token),
    decodeMap,
  );

  /// `$resolveWorkspaceSymbol(handle: number, symbol: IWorkspaceSymbolDto, token: CancellationToken): Promise<IWorkspaceSymbolDto | undefined>`
  Future<Map<String, Object?>?> $resolveWorkspaceSymbol(
    num handle,
    Map<String, Object?> symbol, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostLanguageFeatures.$resolveWorkspaceSymbol',
    await _rpc.call(identifier.nid, r'$resolveWorkspaceSymbol', [
      handle,
      symbol,
    ], token: token),
    decodeNullable(decodeMap),
  );

  /// `$releaseWorkspaceSymbols(handle: number, id: number): void`
  Future<void> $releaseWorkspaceSymbols(num handle, num id) =>
      _rpc.call(identifier.nid, r'$releaseWorkspaceSymbols', [handle, id]);

  /// `$provideRenameEdits(handle: number, resource: UriComponents, position: IPosition, newName: string, token: CancellationToken): Promise<IWorkspaceEditDto & { rejectReason?: string } | undefined>`
  Future<Map<String, Object?>?> $provideRenameEdits(
    num handle,
    VsUri resource,
    Map<String, Object?> position,
    String newName, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostLanguageFeatures.$provideRenameEdits',
    await _rpc.call(identifier.nid, r'$provideRenameEdits', [
      handle,
      resource,
      position,
      newName,
    ], token: token),
    decodeNullable(decodeMap),
  );

  /// `$resolveRenameLocation(handle: number, resource: UriComponents, position: IPosition, token: CancellationToken): Promise<languages.RenameLocation | undefined>`
  Future<Map<String, Object?>?> $resolveRenameLocation(
    num handle,
    VsUri resource,
    Map<String, Object?> position, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostLanguageFeatures.$resolveRenameLocation',
    await _rpc.call(identifier.nid, r'$resolveRenameLocation', [
      handle,
      resource,
      position,
    ], token: token),
    decodeNullable(decodeMap),
  );

  /// `$supportsAutomaticNewSymbolNamesTriggerKind(handle: number): Promise<boolean | undefined>`
  Future<bool?> $supportsAutomaticNewSymbolNamesTriggerKind(num handle) async =>
      decodeReply(
        r'ExtHostLanguageFeatures.$supportsAutomaticNewSymbolNamesTriggerKind',
        await _rpc.call(
          identifier.nid,
          r'$supportsAutomaticNewSymbolNamesTriggerKind',
          [handle],
        ),
        decodeNullable(decodeBool),
      );

  /// `$provideNewSymbolNames(handle: number, resource: UriComponents, range: IRange, triggerKind: languages.NewSymbolNameTriggerKind, token: CancellationToken): Promise<languages.NewSymbolName[] | undefined>`
  Future<List<Map<String, Object?>>?> $provideNewSymbolNames(
    num handle,
    VsUri resource,
    Map<String, Object?> range,
    int triggerKind, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostLanguageFeatures.$provideNewSymbolNames',
    await _rpc.call(identifier.nid, r'$provideNewSymbolNames', [
      handle,
      resource,
      range,
      triggerKind,
    ], token: token),
    decodeNullable(decodeListOf(decodeMap)),
  );

  /// `$provideDocumentSemanticTokens(handle: number, resource: UriComponents, previousResultId: number, token: CancellationToken): Promise<VSBuffer | null>`
  Future<RpcBuffer?> $provideDocumentSemanticTokens(
    num handle,
    VsUri resource,
    num previousResultId, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostLanguageFeatures.$provideDocumentSemanticTokens',
    await _rpc.call(identifier.nid, r'$provideDocumentSemanticTokens', [
      handle,
      resource,
      previousResultId,
    ], token: token),
    decodeNullable(decodeBuffer),
  );

  /// `$releaseDocumentSemanticTokens(handle: number, semanticColoringResultId: number): void`
  Future<void> $releaseDocumentSemanticTokens(
    num handle,
    num semanticColoringResultId,
  ) => _rpc.call(identifier.nid, r'$releaseDocumentSemanticTokens', [
    handle,
    semanticColoringResultId,
  ]);

  /// `$provideDocumentRangeSemanticTokens(handle: number, resource: UriComponents, range: IRange, token: CancellationToken): Promise<VSBuffer | null>`
  Future<RpcBuffer?> $provideDocumentRangeSemanticTokens(
    num handle,
    VsUri resource,
    Map<String, Object?> range, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostLanguageFeatures.$provideDocumentRangeSemanticTokens',
    await _rpc.call(identifier.nid, r'$provideDocumentRangeSemanticTokens', [
      handle,
      resource,
      range,
    ], token: token),
    decodeNullable(decodeBuffer),
  );

  /// `$provideCompletionItems(handle: number, resource: UriComponents, position: IPosition, context: languages.CompletionContext, token: CancellationToken): Promise<ISuggestResultDto | undefined>`
  Future<Map<String, Object?>?> $provideCompletionItems(
    num handle,
    VsUri resource,
    Map<String, Object?> position,
    Map<String, Object?> context, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostLanguageFeatures.$provideCompletionItems',
    await _rpc.call(identifier.nid, r'$provideCompletionItems', [
      handle,
      resource,
      position,
      context,
    ], token: token),
    decodeNullable(decodeMap),
  );

  /// `$resolveCompletionItem(handle: number, id: ChainedCacheId, token: CancellationToken): Promise<ISuggestDataDto | undefined>`
  Future<Map<String, Object?>?> $resolveCompletionItem(
    num handle,
    List<Object?> id, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostLanguageFeatures.$resolveCompletionItem',
    await _rpc.call(identifier.nid, r'$resolveCompletionItem', [
      handle,
      id,
    ], token: token),
    decodeNullable(decodeMap),
  );

  /// `$releaseCompletionItems(handle: number, id: number): void`
  Future<void> $releaseCompletionItems(num handle, num id) =>
      _rpc.call(identifier.nid, r'$releaseCompletionItems', [handle, id]);

  /// `$provideInlineCompletions(handle: number, resource: UriComponents, position: IPosition, context: languages.InlineCompletionContext, token: CancellationToken): Promise<IdentifiableInlineCompletions | undefined>`
  Future<Map<String, Object?>?> $provideInlineCompletions(
    num handle,
    VsUri resource,
    Map<String, Object?> position,
    Map<String, Object?> context, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostLanguageFeatures.$provideInlineCompletions',
    await _rpc.call(identifier.nid, r'$provideInlineCompletions', [
      handle,
      resource,
      position,
      context,
    ], token: token),
    decodeNullable(decodeMap),
  );

  /// `$handleInlineCompletionDidShow(handle: number, pid: number, idx: number, updatedInsertText: string): void`
  Future<void> $handleInlineCompletionDidShow(
    num handle,
    num pid,
    num idx,
    String updatedInsertText,
  ) => _rpc.call(identifier.nid, r'$handleInlineCompletionDidShow', [
    handle,
    pid,
    idx,
    updatedInsertText,
  ]);

  /// `$handleInlineCompletionPartialAccept(handle: number, pid: number, idx: number, acceptedCharacters: number, info: languages.PartialAcceptInfo): void`
  Future<void> $handleInlineCompletionPartialAccept(
    num handle,
    num pid,
    num idx,
    num acceptedCharacters,
    Map<String, Object?> info,
  ) => _rpc.call(identifier.nid, r'$handleInlineCompletionPartialAccept', [
    handle,
    pid,
    idx,
    acceptedCharacters,
    info,
  ]);

  /// `$handleInlineCompletionEndOfLifetime(handle: number, pid: number, idx: number, reason: languages.InlineCompletionEndOfLifeReason<{ pid: number; idx: number }>): void`
  Future<void> $handleInlineCompletionEndOfLifetime(
    num handle,
    num pid,
    num idx,
    Map<String, Object?> reason,
  ) => _rpc.call(identifier.nid, r'$handleInlineCompletionEndOfLifetime', [
    handle,
    pid,
    idx,
    reason,
  ]);

  /// `$handleInlineCompletionRejection(handle: number, pid: number, idx: number): void`
  Future<void> $handleInlineCompletionRejection(num handle, num pid, num idx) =>
      _rpc.call(identifier.nid, r'$handleInlineCompletionRejection', [
        handle,
        pid,
        idx,
      ]);

  /// `$freeInlineCompletionsList(handle: number, pid: number, reason: languages.InlineCompletionsDisposeReason): void`
  Future<void> $freeInlineCompletionsList(
    num handle,
    num pid,
    Map<String, Object?> reason,
  ) => _rpc.call(identifier.nid, r'$freeInlineCompletionsList', [
    handle,
    pid,
    reason,
  ]);

  /// `$acceptInlineCompletionsUnificationState(state: IInlineCompletionsUnificationState): void`
  Future<void> $acceptInlineCompletionsUnificationState(
    Map<String, Object?> state,
  ) => _rpc.call(identifier.nid, r'$acceptInlineCompletionsUnificationState', [
    state,
  ]);

  /// `$handleInlineCompletionSetCurrentModelId(handle: number, modelId: string): void`
  Future<void> $handleInlineCompletionSetCurrentModelId(
    num handle,
    String modelId,
  ) => _rpc.call(identifier.nid, r'$handleInlineCompletionSetCurrentModelId', [
    handle,
    modelId,
  ]);

  /// `$handleInlineCompletionSetProviderOption(handle: number, optionId: string, valueId: string): void`
  Future<void> $handleInlineCompletionSetProviderOption(
    num handle,
    String optionId,
    String valueId,
  ) => _rpc.call(identifier.nid, r'$handleInlineCompletionSetProviderOption', [
    handle,
    optionId,
    valueId,
  ]);

  /// `$provideSignatureHelp(handle: number, resource: UriComponents, position: IPosition, context: languages.SignatureHelpContext, token: CancellationToken): Promise<ISignatureHelpDto | undefined>`
  Future<Map<String, Object?>?> $provideSignatureHelp(
    num handle,
    VsUri resource,
    Map<String, Object?> position,
    Map<String, Object?> context, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostLanguageFeatures.$provideSignatureHelp',
    await _rpc.call(identifier.nid, r'$provideSignatureHelp', [
      handle,
      resource,
      position,
      context,
    ], token: token),
    decodeNullable(decodeMap),
  );

  /// `$releaseSignatureHelp(handle: number, id: number): void`
  Future<void> $releaseSignatureHelp(num handle, num id) =>
      _rpc.call(identifier.nid, r'$releaseSignatureHelp', [handle, id]);

  /// `$provideInlayHints(handle: number, resource: UriComponents, range: IRange, token: CancellationToken): Promise<IInlayHintsDto | undefined>`
  Future<Map<String, Object?>?> $provideInlayHints(
    num handle,
    VsUri resource,
    Map<String, Object?> range, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostLanguageFeatures.$provideInlayHints',
    await _rpc.call(identifier.nid, r'$provideInlayHints', [
      handle,
      resource,
      range,
    ], token: token),
    decodeNullable(decodeMap),
  );

  /// `$resolveInlayHint(handle: number, id: ChainedCacheId, token: CancellationToken): Promise<IInlayHintDto | undefined>`
  Future<Map<String, Object?>?> $resolveInlayHint(
    num handle,
    List<Object?> id, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostLanguageFeatures.$resolveInlayHint',
    await _rpc.call(identifier.nid, r'$resolveInlayHint', [
      handle,
      id,
    ], token: token),
    decodeNullable(decodeMap),
  );

  /// `$releaseInlayHints(handle: number, id: number): void`
  Future<void> $releaseInlayHints(num handle, num id) =>
      _rpc.call(identifier.nid, r'$releaseInlayHints', [handle, id]);

  /// `$provideDocumentLinks(handle: number, resource: UriComponents, token: CancellationToken): Promise<ILinksListDto | undefined>`
  Future<Map<String, Object?>?> $provideDocumentLinks(
    num handle,
    VsUri resource, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostLanguageFeatures.$provideDocumentLinks',
    await _rpc.call(identifier.nid, r'$provideDocumentLinks', [
      handle,
      resource,
    ], token: token),
    decodeNullable(decodeMap),
  );

  /// `$resolveDocumentLink(handle: number, id: ChainedCacheId, token: CancellationToken): Promise<ILinkDto | undefined>`
  Future<Map<String, Object?>?> $resolveDocumentLink(
    num handle,
    List<Object?> id, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostLanguageFeatures.$resolveDocumentLink',
    await _rpc.call(identifier.nid, r'$resolveDocumentLink', [
      handle,
      id,
    ], token: token),
    decodeNullable(decodeMap),
  );

  /// `$releaseDocumentLinks(handle: number, id: number): void`
  Future<void> $releaseDocumentLinks(num handle, num id) =>
      _rpc.call(identifier.nid, r'$releaseDocumentLinks', [handle, id]);

  /// `$provideDocumentColors(handle: number, resource: UriComponents, token: CancellationToken): Promise<IRawColorInfo[]>`
  Future<List<Map<String, Object?>>> $provideDocumentColors(
    num handle,
    VsUri resource, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostLanguageFeatures.$provideDocumentColors',
    await _rpc.call(identifier.nid, r'$provideDocumentColors', [
      handle,
      resource,
    ], token: token),
    decodeListOf(decodeMap),
  );

  /// `$provideColorPresentations(handle: number, resource: UriComponents, colorInfo: IRawColorInfo, token: CancellationToken): Promise<languages.IColorPresentation[] | undefined>`
  Future<List<Map<String, Object?>>?> $provideColorPresentations(
    num handle,
    VsUri resource,
    Map<String, Object?> colorInfo, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostLanguageFeatures.$provideColorPresentations',
    await _rpc.call(identifier.nid, r'$provideColorPresentations', [
      handle,
      resource,
      colorInfo,
    ], token: token),
    decodeNullable(decodeListOf(decodeMap)),
  );

  /// `$provideFoldingRanges(handle: number, resource: UriComponents, context: languages.FoldingContext, token: CancellationToken): Promise<languages.FoldingRange[] | undefined>`
  Future<List<Map<String, Object?>>?> $provideFoldingRanges(
    num handle,
    VsUri resource,
    Map<String, Object?> context, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostLanguageFeatures.$provideFoldingRanges',
    await _rpc.call(identifier.nid, r'$provideFoldingRanges', [
      handle,
      resource,
      context,
    ], token: token),
    decodeNullable(decodeListOf(decodeMap)),
  );

  /// `$provideSelectionRanges(handle: number, resource: UriComponents, positions: IPosition[], token: CancellationToken): Promise<languages.SelectionRange[][]>`
  Future<List<List<Map<String, Object?>>>> $provideSelectionRanges(
    num handle,
    VsUri resource,
    List<Map<String, Object?>> positions, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostLanguageFeatures.$provideSelectionRanges',
    await _rpc.call(identifier.nid, r'$provideSelectionRanges', [
      handle,
      resource,
      positions,
    ], token: token),
    decodeListOf(decodeListOf(decodeMap)),
  );

  /// `$prepareCallHierarchy(handle: number, resource: UriComponents, position: IPosition, token: CancellationToken): Promise<ICallHierarchyItemDto[] | undefined>`
  Future<List<Map<String, Object?>>?> $prepareCallHierarchy(
    num handle,
    VsUri resource,
    Map<String, Object?> position, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostLanguageFeatures.$prepareCallHierarchy',
    await _rpc.call(identifier.nid, r'$prepareCallHierarchy', [
      handle,
      resource,
      position,
    ], token: token),
    decodeNullable(decodeListOf(decodeMap)),
  );

  /// `$provideCallHierarchyIncomingCalls(handle: number, sessionId: string, itemId: string, token: CancellationToken): Promise<IIncomingCallDto[] | undefined>`
  Future<List<Map<String, Object?>>?> $provideCallHierarchyIncomingCalls(
    num handle,
    String sessionId,
    String itemId, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostLanguageFeatures.$provideCallHierarchyIncomingCalls',
    await _rpc.call(identifier.nid, r'$provideCallHierarchyIncomingCalls', [
      handle,
      sessionId,
      itemId,
    ], token: token),
    decodeNullable(decodeListOf(decodeMap)),
  );

  /// `$provideCallHierarchyOutgoingCalls(handle: number, sessionId: string, itemId: string, token: CancellationToken): Promise<IOutgoingCallDto[] | undefined>`
  Future<List<Map<String, Object?>>?> $provideCallHierarchyOutgoingCalls(
    num handle,
    String sessionId,
    String itemId, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostLanguageFeatures.$provideCallHierarchyOutgoingCalls',
    await _rpc.call(identifier.nid, r'$provideCallHierarchyOutgoingCalls', [
      handle,
      sessionId,
      itemId,
    ], token: token),
    decodeNullable(decodeListOf(decodeMap)),
  );

  /// `$releaseCallHierarchy(handle: number, sessionId: string): void`
  Future<void> $releaseCallHierarchy(num handle, String sessionId) =>
      _rpc.call(identifier.nid, r'$releaseCallHierarchy', [handle, sessionId]);

  /// `$setWordDefinitions(wordDefinitions: ILanguageWordDefinitionDto[]): void`
  Future<void> $setWordDefinitions(
    List<Map<String, Object?>> wordDefinitions,
  ) => _rpc.call(identifier.nid, r'$setWordDefinitions', [wordDefinitions]);

  /// `$prepareTypeHierarchy(handle: number, resource: UriComponents, position: IPosition, token: CancellationToken): Promise<ITypeHierarchyItemDto[] | undefined>`
  Future<List<Map<String, Object?>>?> $prepareTypeHierarchy(
    num handle,
    VsUri resource,
    Map<String, Object?> position, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostLanguageFeatures.$prepareTypeHierarchy',
    await _rpc.call(identifier.nid, r'$prepareTypeHierarchy', [
      handle,
      resource,
      position,
    ], token: token),
    decodeNullable(decodeListOf(decodeMap)),
  );

  /// `$provideTypeHierarchySupertypes(handle: number, sessionId: string, itemId: string, token: CancellationToken): Promise<ITypeHierarchyItemDto[] | undefined>`
  Future<List<Map<String, Object?>>?> $provideTypeHierarchySupertypes(
    num handle,
    String sessionId,
    String itemId, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostLanguageFeatures.$provideTypeHierarchySupertypes',
    await _rpc.call(identifier.nid, r'$provideTypeHierarchySupertypes', [
      handle,
      sessionId,
      itemId,
    ], token: token),
    decodeNullable(decodeListOf(decodeMap)),
  );

  /// `$provideTypeHierarchySubtypes(handle: number, sessionId: string, itemId: string, token: CancellationToken): Promise<ITypeHierarchyItemDto[] | undefined>`
  Future<List<Map<String, Object?>>?> $provideTypeHierarchySubtypes(
    num handle,
    String sessionId,
    String itemId, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostLanguageFeatures.$provideTypeHierarchySubtypes',
    await _rpc.call(identifier.nid, r'$provideTypeHierarchySubtypes', [
      handle,
      sessionId,
      itemId,
    ], token: token),
    decodeNullable(decodeListOf(decodeMap)),
  );

  /// `$releaseTypeHierarchy(handle: number, sessionId: string): void`
  Future<void> $releaseTypeHierarchy(num handle, String sessionId) =>
      _rpc.call(identifier.nid, r'$releaseTypeHierarchy', [handle, sessionId]);

  /// `$provideDocumentOnDropEdits(handle: number, requestId: number, resource: UriComponents, position: IPosition, dataTransferDto: DataTransferDTO, token: CancellationToken): Promise<IDocumentDropEditDto[] | undefined>`
  Future<List<Map<String, Object?>>?> $provideDocumentOnDropEdits(
    num handle,
    num requestId,
    VsUri resource,
    Map<String, Object?> position,
    Map<String, Object?> dataTransferDto, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostLanguageFeatures.$provideDocumentOnDropEdits',
    await _rpc.call(identifier.nid, r'$provideDocumentOnDropEdits', [
      handle,
      requestId,
      resource,
      position,
      dataTransferDto,
    ], token: token),
    decodeNullable(decodeListOf(decodeMap)),
  );

  /// `$releaseDocumentOnDropEdits(handle: number, cacheId: number): void`
  Future<void> $releaseDocumentOnDropEdits(num handle, num cacheId) => _rpc
      .call(identifier.nid, r'$releaseDocumentOnDropEdits', [handle, cacheId]);
}

/// Calls `ExtHostQuickOpenShape` (`ExtHostQuickOpen`) in the extension host.
final class ExtHostQuickOpenProxy {
  ExtHostQuickOpenProxy(this._rpc);

  static const identifier = ExtHostContext.extHostQuickOpen;

  final RpcProtocol _rpc;

  /// `$onItemSelected(handle: number): void`
  Future<void> $onItemSelected(num handle) =>
      _rpc.call(identifier.nid, r'$onItemSelected', [handle]);

  /// `$validateInput(input: string): Promise<string | { content: string; severity: Severity } | null | undefined>`
  Future<Object?> $validateInput(String input) =>
      _rpc.call(identifier.nid, r'$validateInput', [input]);

  /// `$onDidChangeActive(sessionId: number, handles: number[]): void`
  Future<void> $onDidChangeActive(num sessionId, List<num> handles) =>
      _rpc.call(identifier.nid, r'$onDidChangeActive', [sessionId, handles]);

  /// `$onDidChangeSelection(sessionId: number, handles: number[]): void`
  Future<void> $onDidChangeSelection(num sessionId, List<num> handles) =>
      _rpc.call(identifier.nid, r'$onDidChangeSelection', [sessionId, handles]);

  /// `$onDidAccept(sessionId: number): void`
  Future<void> $onDidAccept(num sessionId) =>
      _rpc.call(identifier.nid, r'$onDidAccept', [sessionId]);

  /// `$onDidChangeValue(sessionId: number, value: string): void`
  Future<void> $onDidChangeValue(num sessionId, String value) =>
      _rpc.call(identifier.nid, r'$onDidChangeValue', [sessionId, value]);

  /// `$onDidTriggerButton(sessionId: number, handle: number, checked?: boolean): void`
  Future<void> $onDidTriggerButton(
    num sessionId,
    num handle, [
    bool? checked,
  ]) => _rpc.call(identifier.nid, r'$onDidTriggerButton', [
    sessionId,
    handle,
    checked ?? rpcUndefined,
  ]);

  /// `$onDidTriggerItemButton(sessionId: number, itemHandle: number, buttonHandle: number, checked?: boolean): void`
  Future<void> $onDidTriggerItemButton(
    num sessionId,
    num itemHandle,
    num buttonHandle, [
    bool? checked,
  ]) => _rpc.call(identifier.nid, r'$onDidTriggerItemButton', [
    sessionId,
    itemHandle,
    buttonHandle,
    checked ?? rpcUndefined,
  ]);

  /// `$onDidHide(sessionId: number): void`
  Future<void> $onDidHide(num sessionId) =>
      _rpc.call(identifier.nid, r'$onDidHide', [sessionId]);
}

/// Calls `ExtHostQuickDiffShape` (`ExtHostQuickDiff`) in the extension host.
final class ExtHostQuickDiffProxy {
  ExtHostQuickDiffProxy(this._rpc);

  static const identifier = ExtHostContext.extHostQuickDiff;

  final RpcProtocol _rpc;

  /// `$provideOriginalResource(sourceControlHandle: number, uri: UriComponents, token: CancellationToken): Promise<UriComponents | null>`
  Future<VsUri?> $provideOriginalResource(
    num sourceControlHandle,
    VsUri uri, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostQuickDiff.$provideOriginalResource',
    await _rpc.call(identifier.nid, r'$provideOriginalResource', [
      sourceControlHandle,
      uri,
    ], token: token),
    decodeNullable(decodeUri),
  );

  /// `$acceptSourceControlDiffInformation(handle: number, diffInformation: ITextEditorDiffInformation | undefined): void`
  Future<void> $acceptSourceControlDiffInformation(
    num handle,
    Map<String, Object?>? diffInformation,
  ) => _rpc.call(identifier.nid, r'$acceptSourceControlDiffInformation', [
    handle,
    diffInformation ?? rpcUndefined,
  ]);
}

/// Calls `ExtHostAgentEditorCommentsShape` (`ExtHostAgentEditorComments`) in the extension host.
final class ExtHostAgentEditorCommentsProxy {
  ExtHostAgentEditorCommentsProxy(this._rpc);

  static const identifier = ExtHostContext.extHostAgentEditorComments;

  final RpcProtocol _rpc;

  /// `$acceptAgentEditorComments(handle: number, comments: IAgentEditorCommentDto[], acceptsComments: boolean): void`
  Future<void> $acceptAgentEditorComments(
    num handle,
    List<Map<String, Object?>> comments,
    bool acceptsComments,
  ) => _rpc.call(identifier.nid, r'$acceptAgentEditorComments', [
    handle,
    comments,
    acceptsComments,
  ]);

  /// `$revealAgentEditorComment(handle: number, id: string): void`
  Future<void> $revealAgentEditorComment(num handle, String id) =>
      _rpc.call(identifier.nid, r'$revealAgentEditorComment', [handle, id]);
}

/// Calls `ExtHostStatusBarShape` (`ExtHostStatusBar`) in the extension host.
final class ExtHostStatusBarProxy {
  ExtHostStatusBarProxy(this._rpc);

  static const identifier = ExtHostContext.extHostStatusBar;

  final RpcProtocol _rpc;

  /// `$acceptStaticEntries(added?: StatusBarItemDto[]): void`
  Future<void> $acceptStaticEntries([List<Map<String, Object?>>? added]) => _rpc
      .call(identifier.nid, r'$acceptStaticEntries', [added ?? rpcUndefined]);

  /// `$provideTooltip(entryId: string, cancellation: CancellationToken): Promise<string | IMarkdownString | undefined>`
  Future<Object?> $provideTooltip(String entryId, {CancellationToken? token}) =>
      _rpc.call(identifier.nid, r'$provideTooltip', [entryId], token: token);
}

/// Calls `ExtHostShareShape` (`ExtHostShare`) in the extension host.
final class ExtHostShareProxy {
  ExtHostShareProxy(this._rpc);

  static const identifier = ExtHostContext.extHostShare;

  final RpcProtocol _rpc;

  /// `$provideShare(handle: number, shareableItem: IShareableItemDto, token: CancellationToken): Promise<UriComponents | string | undefined>`
  Future<Object?> $provideShare(
    num handle,
    Map<String, Object?> shareableItem, {
    CancellationToken? token,
  }) => _rpc.call(identifier.nid, r'$provideShare', [
    handle,
    shareableItem,
  ], token: token);
}

/// Calls `ExtHostExtensionServiceShape` (`ExtHostExtensionService`) in the extension host.
final class ExtHostExtensionServiceProxy {
  ExtHostExtensionServiceProxy(this._rpc);

  static const identifier = ExtHostContext.extHostExtensionService;

  final RpcProtocol _rpc;

  /// `$resolveAuthority(remoteAuthority: string, resolveAttempt: number): Promise<Dto<IResolveAuthorityResult>>`
  Future<Map<String, Object?>> $resolveAuthority(
    String remoteAuthority,
    num resolveAttempt,
  ) async => decodeReply(
    r'ExtHostExtensionService.$resolveAuthority',
    await _rpc.call(identifier.nid, r'$resolveAuthority', [
      remoteAuthority,
      resolveAttempt,
    ]),
    decodeMap,
  );

  /// Returns `null` if no resolver for `remoteAuthority` is found.
  ///
  /// `$getCanonicalURI(remoteAuthority: string, uri: UriComponents): Promise<UriComponents | null>`
  Future<VsUri?> $getCanonicalURI(String remoteAuthority, VsUri uri) async =>
      decodeReply(
        r'ExtHostExtensionService.$getCanonicalURI',
        await _rpc.call(identifier.nid, r'$getCanonicalURI', [
          remoteAuthority,
          uri,
        ]),
        decodeNullable(decodeUri),
      );

  /// `$startExtensionHost(extensionsDelta: IExtensionDescriptionDelta): Promise<void>`
  Future<void> $startExtensionHost(Map<String, Object?> extensionsDelta) =>
      _rpc.call(identifier.nid, r'$startExtensionHost', [extensionsDelta]);

  /// `$extensionTestsExecute(): Promise<number>`
  Future<num> $extensionTestsExecute() async => decodeReply(
    r'ExtHostExtensionService.$extensionTestsExecute',
    await _rpc.call(identifier.nid, r'$extensionTestsExecute', []),
    decodeNum,
  );

  /// `$activateByEvent(activationEvent: string, activationKind: ActivationKind): Promise<void>`
  Future<void> $activateByEvent(String activationEvent, int activationKind) =>
      _rpc.call(identifier.nid, r'$activateByEvent', [
        activationEvent,
        activationKind,
      ]);

  /// `$activate(extensionId: ExtensionIdentifier, reason: ExtensionActivationReason): Promise<boolean>`
  Future<bool> $activate(
    Map<String, Object?> extensionId,
    Map<String, Object?> reason,
  ) async => decodeReply(
    r'ExtHostExtensionService.$activate',
    await _rpc.call(identifier.nid, r'$activate', [extensionId, reason]),
    decodeBool,
  );

  /// `$setRemoteEnvironment(env: { [key: string]: string | null }): Promise<void>`
  Future<void> $setRemoteEnvironment(Map<String, String?> env) =>
      _rpc.call(identifier.nid, r'$setRemoteEnvironment', [env]);

  /// `$updateRemoteConnectionData(connectionData: IRemoteConnectionData): Promise<void>`
  Future<void> $updateRemoteConnectionData(
    Map<String, Object?> connectionData,
  ) => _rpc.call(identifier.nid, r'$updateRemoteConnectionData', [
    connectionData,
  ]);

  /// `$deltaExtensions(extensionsDelta: IExtensionDescriptionDelta): Promise<void>`
  Future<void> $deltaExtensions(Map<String, Object?> extensionsDelta) =>
      _rpc.call(identifier.nid, r'$deltaExtensions', [extensionsDelta]);

  /// `$test_latency(n: number): Promise<number>`
  Future<num> $test_latency(num n) async => decodeReply(
    r'ExtHostExtensionService.$test_latency',
    await _rpc.call(identifier.nid, r'$test_latency', [n]),
    decodeNum,
  );

  /// `$test_up(b: VSBuffer): Promise<number>`
  Future<num> $test_up(RpcBuffer b) async => decodeReply(
    r'ExtHostExtensionService.$test_up',
    await _rpc.call(identifier.nid, r'$test_up', [b]),
    decodeNum,
  );

  /// `$test_down(size: number): Promise<VSBuffer>`
  Future<RpcBuffer> $test_down(num size) async => decodeReply(
    r'ExtHostExtensionService.$test_down',
    await _rpc.call(identifier.nid, r'$test_down', [size]),
    decodeBuffer,
  );
}

/// Calls `ExtHostLogLevelServiceShape` (`ExtHostLogLevelServiceShape`) in the extension host.
final class ExtHostLogLevelServiceShapeProxy {
  ExtHostLogLevelServiceShapeProxy(this._rpc);

  static const identifier = ExtHostContext.extHostLogLevelServiceShape;

  final RpcProtocol _rpc;

  /// `$setLogLevel(level: LogLevel, resource?: UriComponents): void`
  Future<void> $setLogLevel(int level, [VsUri? resource]) => _rpc.call(
    identifier.nid,
    r'$setLogLevel',
    [level, resource ?? rpcUndefined],
  );
}

/// Calls `ExtHostTerminalServiceShape` (`ExtHostTerminalService`) in the extension host.
final class ExtHostTerminalServiceProxy {
  ExtHostTerminalServiceProxy(this._rpc);

  static const identifier = ExtHostContext.extHostTerminalService;

  final RpcProtocol _rpc;

  /// `$acceptTerminalClosed(id: number, exitCode: number | undefined, exitReason: TerminalExitReason): void`
  Future<void> $acceptTerminalClosed(num id, num? exitCode, int exitReason) =>
      _rpc.call(identifier.nid, r'$acceptTerminalClosed', [
        id,
        exitCode ?? rpcUndefined,
        exitReason,
      ]);

  /// `$acceptTerminalOpened(id: number, extHostTerminalId: string | undefined, name: string, shellLaunchConfig: IShellLaunchConfigDto): void`
  Future<void> $acceptTerminalOpened(
    num id,
    String? extHostTerminalId,
    String name,
    Map<String, Object?> shellLaunchConfig,
  ) => _rpc.call(identifier.nid, r'$acceptTerminalOpened', [
    id,
    extHostTerminalId ?? rpcUndefined,
    name,
    shellLaunchConfig,
  ]);

  /// `$acceptActiveTerminalChanged(id: number | null): void`
  Future<void> $acceptActiveTerminalChanged(num? id) =>
      _rpc.call(identifier.nid, r'$acceptActiveTerminalChanged', [id]);

  /// `$acceptTerminalProcessId(id: number, processId: number): void`
  Future<void> $acceptTerminalProcessId(num id, num processId) =>
      _rpc.call(identifier.nid, r'$acceptTerminalProcessId', [id, processId]);

  /// `$acceptTerminalProcessData(id: number, data: string): void`
  Future<void> $acceptTerminalProcessData(num id, String data) =>
      _rpc.call(identifier.nid, r'$acceptTerminalProcessData', [id, data]);

  /// `$acceptDidExecuteCommand(id: number, command: ITerminalCommandDto): void`
  Future<void> $acceptDidExecuteCommand(num id, Map<String, Object?> command) =>
      _rpc.call(identifier.nid, r'$acceptDidExecuteCommand', [id, command]);

  /// `$acceptTerminalTitleChange(id: number, name: string): void`
  Future<void> $acceptTerminalTitleChange(num id, String name) =>
      _rpc.call(identifier.nid, r'$acceptTerminalTitleChange', [id, name]);

  /// `$acceptTerminalDimensions(id: number, cols: number, rows: number): void`
  Future<void> $acceptTerminalDimensions(num id, num cols, num rows) =>
      _rpc.call(identifier.nid, r'$acceptTerminalDimensions', [id, cols, rows]);

  /// `$acceptTerminalMaximumDimensions(id: number, cols: number, rows: number): void`
  Future<void> $acceptTerminalMaximumDimensions(num id, num cols, num rows) =>
      _rpc.call(identifier.nid, r'$acceptTerminalMaximumDimensions', [
        id,
        cols,
        rows,
      ]);

  /// `$acceptTerminalInteraction(id: number): void`
  Future<void> $acceptTerminalInteraction(num id) =>
      _rpc.call(identifier.nid, r'$acceptTerminalInteraction', [id]);

  /// `$acceptTerminalSelection(id: number, selection: string | undefined): void`
  Future<void> $acceptTerminalSelection(num id, String? selection) => _rpc.call(
    identifier.nid,
    r'$acceptTerminalSelection',
    [id, selection ?? rpcUndefined],
  );

  /// `$acceptTerminalShellType(id: number, shellType: TerminalShellType | undefined): void`
  Future<void> $acceptTerminalShellType(num id, String? shellType) => _rpc.call(
    identifier.nid,
    r'$acceptTerminalShellType',
    [id, shellType ?? rpcUndefined],
  );

  /// `$startExtensionTerminal(id: number, initialDimensions: ITerminalDimensionsDto | undefined): Promise<ITerminalLaunchError | undefined>`
  Future<Map<String, Object?>?> $startExtensionTerminal(
    num id,
    Map<String, Object?>? initialDimensions,
  ) async => decodeReply(
    r'ExtHostTerminalService.$startExtensionTerminal',
    await _rpc.call(identifier.nid, r'$startExtensionTerminal', [
      id,
      initialDimensions ?? rpcUndefined,
    ]),
    decodeNullable(decodeMap),
  );

  /// `$acceptProcessAckDataEvent(id: number, charCount: number): void`
  Future<void> $acceptProcessAckDataEvent(num id, num charCount) =>
      _rpc.call(identifier.nid, r'$acceptProcessAckDataEvent', [id, charCount]);

  /// `$acceptProcessInput(id: number, data: string): void`
  Future<void> $acceptProcessInput(num id, String data) =>
      _rpc.call(identifier.nid, r'$acceptProcessInput', [id, data]);

  /// `$acceptProcessResize(id: number, cols: number, rows: number): void`
  Future<void> $acceptProcessResize(num id, num cols, num rows) =>
      _rpc.call(identifier.nid, r'$acceptProcessResize', [id, cols, rows]);

  /// `$acceptProcessShutdown(id: number, immediate: boolean): void`
  Future<void> $acceptProcessShutdown(num id, bool immediate) =>
      _rpc.call(identifier.nid, r'$acceptProcessShutdown', [id, immediate]);

  /// `$acceptProcessRequestInitialCwd(id: number): void`
  Future<void> $acceptProcessRequestInitialCwd(num id) =>
      _rpc.call(identifier.nid, r'$acceptProcessRequestInitialCwd', [id]);

  /// `$acceptProcessRequestCwd(id: number): void`
  Future<void> $acceptProcessRequestCwd(num id) =>
      _rpc.call(identifier.nid, r'$acceptProcessRequestCwd', [id]);

  /// `$acceptProcessRequestLatency(id: number): Promise<number>`
  Future<num> $acceptProcessRequestLatency(num id) async => decodeReply(
    r'ExtHostTerminalService.$acceptProcessRequestLatency',
    await _rpc.call(identifier.nid, r'$acceptProcessRequestLatency', [id]),
    decodeNum,
  );

  /// `$provideLinks(id: number, line: string): Promise<ITerminalLinkDto[]>`
  Future<List<Map<String, Object?>>> $provideLinks(num id, String line) async =>
      decodeReply(
        r'ExtHostTerminalService.$provideLinks',
        await _rpc.call(identifier.nid, r'$provideLinks', [id, line]),
        decodeListOf(decodeMap),
      );

  /// `$activateLink(id: number, linkId: number): void`
  Future<void> $activateLink(num id, num linkId) =>
      _rpc.call(identifier.nid, r'$activateLink', [id, linkId]);

  /// `$initEnvironmentVariableCollections(collections: [string, ISerializableEnvironmentVariableCollection][]): void`
  Future<void> $initEnvironmentVariableCollections(
    List<List<Object?>> collections,
  ) => _rpc.call(identifier.nid, r'$initEnvironmentVariableCollections', [
    collections,
  ]);

  /// `$acceptDefaultProfile(profile: ITerminalProfile, automationProfile: ITerminalProfile): void`
  Future<void> $acceptDefaultProfile(
    Map<String, Object?> profile,
    Map<String, Object?> automationProfile,
  ) => _rpc.call(identifier.nid, r'$acceptDefaultProfile', [
    profile,
    automationProfile,
  ]);

  /// `$createContributedProfileTerminal(id: string, options: ICreateContributedTerminalProfileOptions): Promise<void>`
  Future<void> $createContributedProfileTerminal(
    String id,
    Map<String, Object?> options,
  ) => _rpc.call(identifier.nid, r'$createContributedProfileTerminal', [
    id,
    options,
  ]);

  /// `$provideTerminalQuickFixes(id: string, matchResult: TerminalCommandMatchResultDto, token: CancellationToken): Promise<SingleOrMany<TerminalQuickFix> | undefined>`
  Future<Object?> $provideTerminalQuickFixes(
    String id,
    Map<String, Object?> matchResult, {
    CancellationToken? token,
  }) => _rpc.call(identifier.nid, r'$provideTerminalQuickFixes', [
    id,
    matchResult,
  ], token: token);

  /// `$provideTerminalCompletions(id: string, options: ITerminalCompletionContextDto, token: CancellationToken): Promise<TerminalCompletionListDto | undefined>`
  Future<Map<String, Object?>?> $provideTerminalCompletions(
    String id,
    Map<String, Object?> options, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostTerminalService.$provideTerminalCompletions',
    await _rpc.call(identifier.nid, r'$provideTerminalCompletions', [
      id,
      options,
    ], token: token),
    decodeNullable(decodeMap),
  );
}

/// Calls `ExtHostTerminalShellIntegrationShape` (`ExtHostTerminalShellIntegration`) in the extension host.
final class ExtHostTerminalShellIntegrationProxy {
  ExtHostTerminalShellIntegrationProxy(this._rpc);

  static const identifier = ExtHostContext.extHostTerminalShellIntegration;

  final RpcProtocol _rpc;

  /// `$shellIntegrationChange(instanceId: number, supportsExecuteCommandApi: boolean): void`
  Future<void> $shellIntegrationChange(
    num instanceId,
    bool supportsExecuteCommandApi,
  ) => _rpc.call(identifier.nid, r'$shellIntegrationChange', [
    instanceId,
    supportsExecuteCommandApi,
  ]);

  /// `$shellExecutionStart(instanceId: number, supportsExecuteCommandApi: boolean, commandLineValue: string, commandLineConfidence: TerminalShellExecutionCommandLineConfidence, isTrusted: boolean, cwd: string | undefined): void`
  Future<void> $shellExecutionStart(
    num instanceId,
    bool supportsExecuteCommandApi,
    String commandLineValue,
    int commandLineConfidence,
    bool isTrusted,
    String? cwd,
  ) => _rpc.call(identifier.nid, r'$shellExecutionStart', [
    instanceId,
    supportsExecuteCommandApi,
    commandLineValue,
    commandLineConfidence,
    isTrusted,
    cwd ?? rpcUndefined,
  ]);

  /// `$shellExecutionEnd(instanceId: number, commandLineValue: string, commandLineConfidence: TerminalShellExecutionCommandLineConfidence, isTrusted: boolean, exitCode: number | undefined): void`
  Future<void> $shellExecutionEnd(
    num instanceId,
    String commandLineValue,
    int commandLineConfidence,
    bool isTrusted,
    num? exitCode,
  ) => _rpc.call(identifier.nid, r'$shellExecutionEnd', [
    instanceId,
    commandLineValue,
    commandLineConfidence,
    isTrusted,
    exitCode ?? rpcUndefined,
  ]);

  /// `$shellExecutionData(instanceId: number, data: string): void`
  Future<void> $shellExecutionData(num instanceId, String data) =>
      _rpc.call(identifier.nid, r'$shellExecutionData', [instanceId, data]);

  /// `$shellEnvChange(instanceId: number, shellEnvKeys: string[], shellEnvValues: string[], isTrusted: boolean): void`
  Future<void> $shellEnvChange(
    num instanceId,
    List<String> shellEnvKeys,
    List<String> shellEnvValues,
    bool isTrusted,
  ) => _rpc.call(identifier.nid, r'$shellEnvChange', [
    instanceId,
    shellEnvKeys,
    shellEnvValues,
    isTrusted,
  ]);

  /// `$cwdChange(instanceId: number, cwd: string | undefined): void`
  Future<void> $cwdChange(num instanceId, String? cwd) => _rpc.call(
    identifier.nid,
    r'$cwdChange',
    [instanceId, cwd ?? rpcUndefined],
  );

  /// `$closeTerminal(instanceId: number): void`
  Future<void> $closeTerminal(num instanceId) =>
      _rpc.call(identifier.nid, r'$closeTerminal', [instanceId]);
}

/// Calls `ExtHostSCMShape` (`ExtHostSCM`) in the extension host.
final class ExtHostSCMProxy {
  ExtHostSCMProxy(this._rpc);

  static const identifier = ExtHostContext.extHostSCM;

  final RpcProtocol _rpc;

  /// `$provideOriginalResource(sourceControlHandle: number, uri: UriComponents, token: CancellationToken): Promise<UriComponents | null>`
  Future<VsUri?> $provideOriginalResource(
    num sourceControlHandle,
    VsUri uri, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostSCM.$provideOriginalResource',
    await _rpc.call(identifier.nid, r'$provideOriginalResource', [
      sourceControlHandle,
      uri,
    ], token: token),
    decodeNullable(decodeUri),
  );

  /// `$provideSecondaryOriginalResource(sourceControlHandle: number, uri: UriComponents, token: CancellationToken): Promise<UriComponents | null>`
  Future<VsUri?> $provideSecondaryOriginalResource(
    num sourceControlHandle,
    VsUri uri, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostSCM.$provideSecondaryOriginalResource',
    await _rpc.call(identifier.nid, r'$provideSecondaryOriginalResource', [
      sourceControlHandle,
      uri,
    ], token: token),
    decodeNullable(decodeUri),
  );

  /// `$onInputBoxValueChange(sourceControlHandle: number, value: string): void`
  Future<void> $onInputBoxValueChange(num sourceControlHandle, String value) =>
      _rpc.call(identifier.nid, r'$onInputBoxValueChange', [
        sourceControlHandle,
        value,
      ]);

  /// `$executeResourceCommand(sourceControlHandle: number, groupHandle: number, handle: number, preserveFocus: boolean): Promise<void>`
  Future<void> $executeResourceCommand(
    num sourceControlHandle,
    num groupHandle,
    num handle,
    bool preserveFocus,
  ) => _rpc.call(identifier.nid, r'$executeResourceCommand', [
    sourceControlHandle,
    groupHandle,
    handle,
    preserveFocus,
  ]);

  /// `$validateInput(sourceControlHandle: number, value: string, cursorPosition: number): Promise<[string | IMarkdownString, number] | undefined>`
  Future<List<Object?>?> $validateInput(
    num sourceControlHandle,
    String value,
    num cursorPosition,
  ) async => decodeReply(
    r'ExtHostSCM.$validateInput',
    await _rpc.call(identifier.nid, r'$validateInput', [
      sourceControlHandle,
      value,
      cursorPosition,
    ]),
    decodeNullable(decodeListOf(decodeObject)),
  );

  /// `$setSelectedSourceControl(selectedSourceControlHandle: number | undefined): Promise<void>`
  Future<void> $setSelectedSourceControl(num? selectedSourceControlHandle) =>
      _rpc.call(identifier.nid, r'$setSelectedSourceControl', [
        selectedSourceControlHandle ?? rpcUndefined,
      ]);

  /// `$provideHistoryItemRefs(sourceControlHandle: number, historyItemRefs: string[] | undefined, token: CancellationToken): Promise<SCMHistoryItemRefDto[] | undefined>`
  Future<List<Map<String, Object?>>?> $provideHistoryItemRefs(
    num sourceControlHandle,
    List<String>? historyItemRefs, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostSCM.$provideHistoryItemRefs',
    await _rpc.call(identifier.nid, r'$provideHistoryItemRefs', [
      sourceControlHandle,
      historyItemRefs ?? rpcUndefined,
    ], token: token),
    decodeNullable(decodeListOf(decodeMap)),
  );

  /// `$provideHistoryItems(sourceControlHandle: number, options: ISCMHistoryOptions, token: CancellationToken): Promise<SCMHistoryItemDto[] | undefined>`
  Future<List<Map<String, Object?>>?> $provideHistoryItems(
    num sourceControlHandle,
    Map<String, Object?> options, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostSCM.$provideHistoryItems',
    await _rpc.call(identifier.nid, r'$provideHistoryItems', [
      sourceControlHandle,
      options,
    ], token: token),
    decodeNullable(decodeListOf(decodeMap)),
  );

  /// `$provideHistoryItemChanges(sourceControlHandle: number, historyItemId: string, historyItemParentId: string | undefined, token: CancellationToken): Promise<SCMHistoryItemChangeDto[] | undefined>`
  Future<List<Map<String, Object?>>?> $provideHistoryItemChanges(
    num sourceControlHandle,
    String historyItemId,
    String? historyItemParentId, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostSCM.$provideHistoryItemChanges',
    await _rpc.call(identifier.nid, r'$provideHistoryItemChanges', [
      sourceControlHandle,
      historyItemId,
      historyItemParentId ?? rpcUndefined,
    ], token: token),
    decodeNullable(decodeListOf(decodeMap)),
  );

  /// `$resolveHistoryItem(sourceControlHandle: number, historyItemId: string, token: CancellationToken): Promise<SCMHistoryItemDto | undefined>`
  Future<Map<String, Object?>?> $resolveHistoryItem(
    num sourceControlHandle,
    String historyItemId, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostSCM.$resolveHistoryItem',
    await _rpc.call(identifier.nid, r'$resolveHistoryItem', [
      sourceControlHandle,
      historyItemId,
    ], token: token),
    decodeNullable(decodeMap),
  );

  /// `$resolveHistoryItemChatContext(sourceControlHandle: number, historyItemId: string, token: CancellationToken): Promise<string | undefined>`
  Future<String?> $resolveHistoryItemChatContext(
    num sourceControlHandle,
    String historyItemId, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostSCM.$resolveHistoryItemChatContext',
    await _rpc.call(identifier.nid, r'$resolveHistoryItemChatContext', [
      sourceControlHandle,
      historyItemId,
    ], token: token),
    decodeNullable(decodeString),
  );

  /// `$resolveHistoryItemChangeRangeChatContext(sourceControlHandle: number, historyItemId: string, historyItemParentId: string, path: string, token: CancellationToken): Promise<string | undefined>`
  Future<String?> $resolveHistoryItemChangeRangeChatContext(
    num sourceControlHandle,
    String historyItemId,
    String historyItemParentId,
    String path, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostSCM.$resolveHistoryItemChangeRangeChatContext',
    await _rpc.call(
      identifier.nid,
      r'$resolveHistoryItemChangeRangeChatContext',
      [sourceControlHandle, historyItemId, historyItemParentId, path],
      token: token,
    ),
    decodeNullable(decodeString),
  );

  /// `$resolveHistoryItemRefsCommonAncestor(sourceControlHandle: number, historyItemRefs: string[], token: CancellationToken): Promise<string | undefined>`
  Future<String?> $resolveHistoryItemRefsCommonAncestor(
    num sourceControlHandle,
    List<String> historyItemRefs, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostSCM.$resolveHistoryItemRefsCommonAncestor',
    await _rpc.call(identifier.nid, r'$resolveHistoryItemRefsCommonAncestor', [
      sourceControlHandle,
      historyItemRefs,
    ], token: token),
    decodeNullable(decodeString),
  );

  /// `$provideArtifactGroups(sourceControlHandle: number, token: CancellationToken): Promise<SCMArtifactGroupDto[] | undefined>`
  Future<List<Map<String, Object?>>?> $provideArtifactGroups(
    num sourceControlHandle, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostSCM.$provideArtifactGroups',
    await _rpc.call(identifier.nid, r'$provideArtifactGroups', [
      sourceControlHandle,
    ], token: token),
    decodeNullable(decodeListOf(decodeMap)),
  );

  /// `$provideArtifacts(sourceControlHandle: number, group: string, token: CancellationToken): Promise<SCMArtifactDto[] | undefined>`
  Future<List<Map<String, Object?>>?> $provideArtifacts(
    num sourceControlHandle,
    String group, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostSCM.$provideArtifacts',
    await _rpc.call(identifier.nid, r'$provideArtifacts', [
      sourceControlHandle,
      group,
    ], token: token),
    decodeNullable(decodeListOf(decodeMap)),
  );
}

/// Calls `ExtHostSearchShape` (`ExtHostSearch`) in the extension host.
final class ExtHostSearchProxy {
  ExtHostSearchProxy(this._rpc);

  static const identifier = ExtHostContext.extHostSearch;

  final RpcProtocol _rpc;

  /// `$enableExtensionHostSearch(): void`
  Future<void> $enableExtensionHostSearch() =>
      _rpc.call(identifier.nid, r'$enableExtensionHostSearch', []);

  /// `$getAIName(handle: number): Promise<string | undefined>`
  Future<String?> $getAIName(num handle) async => decodeReply(
    r'ExtHostSearch.$getAIName',
    await _rpc.call(identifier.nid, r'$getAIName', [handle]),
    decodeNullable(decodeString),
  );

  /// `$provideFileSearchResults(handle: number, session: number, query: search.IRawQuery, token: CancellationToken): Promise<search.ISearchCompleteStats>`
  Future<Map<String, Object?>> $provideFileSearchResults(
    num handle,
    num session,
    Map<String, Object?> query, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostSearch.$provideFileSearchResults',
    await _rpc.call(identifier.nid, r'$provideFileSearchResults', [
      handle,
      session,
      query,
    ], token: token),
    decodeMap,
  );

  /// `$provideAITextSearchResults(handle: number, session: number, query: search.IRawAITextQuery, token: CancellationToken): Promise<search.ISearchCompleteStats>`
  Future<Map<String, Object?>> $provideAITextSearchResults(
    num handle,
    num session,
    Map<String, Object?> query, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostSearch.$provideAITextSearchResults',
    await _rpc.call(identifier.nid, r'$provideAITextSearchResults', [
      handle,
      session,
      query,
    ], token: token),
    decodeMap,
  );

  /// `$provideTextSearchResults(handle: number, session: number, query: search.IRawTextQuery, token: CancellationToken): Promise<search.ISearchCompleteStats>`
  Future<Map<String, Object?>> $provideTextSearchResults(
    num handle,
    num session,
    Map<String, Object?> query, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostSearch.$provideTextSearchResults',
    await _rpc.call(identifier.nid, r'$provideTextSearchResults', [
      handle,
      session,
      query,
    ], token: token),
    decodeMap,
  );

  /// `$clearCache(cacheKey: string): Promise<void>`
  Future<void> $clearCache(String cacheKey) =>
      _rpc.call(identifier.nid, r'$clearCache', [cacheKey]);
}

/// Calls `ExtHostTaskShape` (`ExtHostTask`) in the extension host.
final class ExtHostTaskProxy {
  ExtHostTaskProxy(this._rpc);

  static const identifier = ExtHostContext.extHostTask;

  final RpcProtocol _rpc;

  /// `$provideTasks(handle: number, validTypes: { [key: string]: boolean }): Promise<tasks.ITaskSetDTO>`
  Future<Map<String, Object?>> $provideTasks(
    num handle,
    Map<String, bool> validTypes,
  ) async => decodeReply(
    r'ExtHostTask.$provideTasks',
    await _rpc.call(identifier.nid, r'$provideTasks', [handle, validTypes]),
    decodeMap,
  );

  /// `$resolveTask(handle: number, taskDTO: tasks.ITaskDTO): Promise<tasks.ITaskDTO | undefined>`
  Future<Map<String, Object?>?> $resolveTask(
    num handle,
    Map<String, Object?> taskDTO,
  ) async => decodeReply(
    r'ExtHostTask.$resolveTask',
    await _rpc.call(identifier.nid, r'$resolveTask', [handle, taskDTO]),
    decodeNullable(decodeMap),
  );

  /// `$onDidStartTask(execution: tasks.ITaskExecutionDTO, terminalId: number, resolvedDefinition: tasks.ITaskDefinitionDTO): void`
  Future<void> $onDidStartTask(
    Map<String, Object?> execution,
    num terminalId,
    Map<String, Object?> resolvedDefinition,
  ) => _rpc.call(identifier.nid, r'$onDidStartTask', [
    execution,
    terminalId,
    resolvedDefinition,
  ]);

  /// `$onDidStartTaskProcess(value: tasks.ITaskProcessStartedDTO): void`
  Future<void> $onDidStartTaskProcess(Map<String, Object?> value) =>
      _rpc.call(identifier.nid, r'$onDidStartTaskProcess', [value]);

  /// `$onDidEndTaskProcess(value: tasks.ITaskProcessEndedDTO): void`
  Future<void> $onDidEndTaskProcess(Map<String, Object?> value) =>
      _rpc.call(identifier.nid, r'$onDidEndTaskProcess', [value]);

  /// `$OnDidEndTask(execution: tasks.ITaskExecutionDTO): void`
  Future<void> $OnDidEndTask(Map<String, Object?> execution) =>
      _rpc.call(identifier.nid, r'$OnDidEndTask', [execution]);

  /// `$onDidStartTaskProblemMatchers(status: tasks.ITaskProblemMatcherStartedDto): void`
  Future<void> $onDidStartTaskProblemMatchers(Map<String, Object?> status) =>
      _rpc.call(identifier.nid, r'$onDidStartTaskProblemMatchers', [status]);

  /// `$onDidEndTaskProblemMatchers(status: tasks.ITaskProblemMatcherEndedDto): void`
  Future<void> $onDidEndTaskProblemMatchers(Map<String, Object?> status) =>
      _rpc.call(identifier.nid, r'$onDidEndTaskProblemMatchers', [status]);

  /// `$resolveVariables(workspaceFolder: UriComponents, toResolve: { process?: { name: string; cwd?: string }; variables: string[] }): Promise<{ process?: string; variables: { [key: string]: string } }>`
  Future<Map<String, Object?>> $resolveVariables(
    VsUri workspaceFolder,
    Map<String, Object?> toResolve,
  ) async => decodeReply(
    r'ExtHostTask.$resolveVariables',
    await _rpc.call(identifier.nid, r'$resolveVariables', [
      workspaceFolder,
      toResolve,
    ]),
    decodeMap,
  );

  /// `$jsonTasksSupported(): Promise<boolean>`
  Future<bool> $jsonTasksSupported() async => decodeReply(
    r'ExtHostTask.$jsonTasksSupported',
    await _rpc.call(identifier.nid, r'$jsonTasksSupported', []),
    decodeBool,
  );

  /// `$findExecutable(command: string, cwd?: string, paths?: string[]): Promise<string | undefined>`
  Future<String?> $findExecutable(
    String command, [
    String? cwd,
    List<String>? paths,
  ]) async => decodeReply(
    r'ExtHostTask.$findExecutable',
    await _rpc.call(identifier.nid, r'$findExecutable', [
      command,
      cwd ?? rpcUndefined,
      paths ?? rpcUndefined,
    ]),
    decodeNullable(decodeString),
  );
}

/// Calls `ExtHostWorkspaceShape` (`ExtHostWorkspace`) in the extension host.
final class ExtHostWorkspaceProxy {
  ExtHostWorkspaceProxy(this._rpc);

  static const identifier = ExtHostContext.extHostWorkspace;

  final RpcProtocol _rpc;

  /// `$initializeWorkspace(workspace: IWorkspaceData | null, trusted: boolean): void`
  Future<void> $initializeWorkspace(
    Map<String, Object?>? workspace,
    bool trusted,
  ) => _rpc.call(identifier.nid, r'$initializeWorkspace', [workspace, trusted]);

  /// `$acceptWorkspaceData(workspace: IWorkspaceData | null): void`
  Future<void> $acceptWorkspaceData(Map<String, Object?>? workspace) =>
      _rpc.call(identifier.nid, r'$acceptWorkspaceData', [workspace]);

  /// `$handleTextSearchResult(result: search.IRawFileMatch2, requestId: number): void`
  Future<void> $handleTextSearchResult(
    Map<String, Object?> result,
    num requestId,
  ) => _rpc.call(identifier.nid, r'$handleTextSearchResult', [
    result,
    requestId,
  ]);

  /// `$onDidGrantWorkspaceTrust(): void`
  Future<void> $onDidGrantWorkspaceTrust() =>
      _rpc.call(identifier.nid, r'$onDidGrantWorkspaceTrust', []);

  /// `$onDidChangeWorkspaceTrustedFolders(): void`
  Future<void> $onDidChangeWorkspaceTrustedFolders() =>
      _rpc.call(identifier.nid, r'$onDidChangeWorkspaceTrustedFolders', []);

  /// `$getEditSessionIdentifier(folder: UriComponents, token: CancellationToken): Promise<string | undefined>`
  Future<String?> $getEditSessionIdentifier(
    VsUri folder, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostWorkspace.$getEditSessionIdentifier',
    await _rpc.call(identifier.nid, r'$getEditSessionIdentifier', [
      folder,
    ], token: token),
    decodeNullable(decodeString),
  );

  /// `$provideEditSessionIdentityMatch(folder: UriComponents, identity1: string, identity2: string, token: CancellationToken): Promise<EditSessionIdentityMatch | undefined>`
  Future<int?> $provideEditSessionIdentityMatch(
    VsUri folder,
    String identity1,
    String identity2, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostWorkspace.$provideEditSessionIdentityMatch',
    await _rpc.call(identifier.nid, r'$provideEditSessionIdentityMatch', [
      folder,
      identity1,
      identity2,
    ], token: token),
    decodeNullable(decodeInt),
  );

  /// `$onWillCreateEditSessionIdentity(folder: UriComponents, token: CancellationToken, timeout: number): Promise<void>`
  Future<void> $onWillCreateEditSessionIdentity(
    VsUri folder,
    CancellationToken? tokenArg,
    num timeout,
  ) => _rpc.call(identifier.nid, r'$onWillCreateEditSessionIdentity', [
    folder,
    encodeInlineToken(tokenArg),
    timeout,
  ]);

  /// `$provideCanonicalUri(uri: UriComponents, targetScheme: string, token: CancellationToken): Promise<UriComponents | undefined>`
  Future<VsUri?> $provideCanonicalUri(
    VsUri uri,
    String targetScheme, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostWorkspace.$provideCanonicalUri',
    await _rpc.call(identifier.nid, r'$provideCanonicalUri', [
      uri,
      targetScheme,
    ], token: token),
    decodeNullable(decodeUri),
  );
}

/// Calls `ExtHostWindowShape` (`ExtHostWindow`) in the extension host.
final class ExtHostWindowProxy {
  ExtHostWindowProxy(this._rpc);

  static const identifier = ExtHostContext.extHostWindow;

  final RpcProtocol _rpc;

  /// `$onDidChangeWindowFocus(value: boolean): void`
  Future<void> $onDidChangeWindowFocus(bool value) =>
      _rpc.call(identifier.nid, r'$onDidChangeWindowFocus', [value]);

  /// `$onDidChangeWindowActive(value: boolean): void`
  Future<void> $onDidChangeWindowActive(bool value) =>
      _rpc.call(identifier.nid, r'$onDidChangeWindowActive', [value]);

  /// `$onDidChangeActiveNativeWindowHandle(handle: string | undefined): void`
  Future<void> $onDidChangeActiveNativeWindowHandle(String? handle) =>
      _rpc.call(identifier.nid, r'$onDidChangeActiveNativeWindowHandle', [
        handle ?? rpcUndefined,
      ]);
}

/// Calls `ExtHostPowerShape` (`ExtHostPower`) in the extension host.
final class ExtHostPowerProxy {
  ExtHostPowerProxy(this._rpc);

  static const identifier = ExtHostContext.extHostPower;

  final RpcProtocol _rpc;

  /// `$onDidSuspend(): void`
  Future<void> $onDidSuspend() =>
      _rpc.call(identifier.nid, r'$onDidSuspend', []);

  /// `$onDidResume(): void`
  Future<void> $onDidResume() => _rpc.call(identifier.nid, r'$onDidResume', []);

  /// `$onDidChangeOnBatteryPower(isOnBattery: boolean): void`
  Future<void> $onDidChangeOnBatteryPower(bool isOnBattery) =>
      _rpc.call(identifier.nid, r'$onDidChangeOnBatteryPower', [isOnBattery]);

  /// `$onDidChangeThermalState(state: PowerThermalState): void`
  Future<void> $onDidChangeThermalState(String state) =>
      _rpc.call(identifier.nid, r'$onDidChangeThermalState', [state]);

  /// `$onDidChangeSpeedLimit(limit: number): void`
  Future<void> $onDidChangeSpeedLimit(num limit) =>
      _rpc.call(identifier.nid, r'$onDidChangeSpeedLimit', [limit]);

  /// `$onWillShutdown(): void`
  Future<void> $onWillShutdown() =>
      _rpc.call(identifier.nid, r'$onWillShutdown', []);

  /// `$onDidLockScreen(): void`
  Future<void> $onDidLockScreen() =>
      _rpc.call(identifier.nid, r'$onDidLockScreen', []);

  /// `$onDidUnlockScreen(): void`
  Future<void> $onDidUnlockScreen() =>
      _rpc.call(identifier.nid, r'$onDidUnlockScreen', []);
}

/// Calls `ExtHostWebviewsShape` (`ExtHostWebviews`) in the extension host.
final class ExtHostWebviewsProxy {
  ExtHostWebviewsProxy(this._rpc);

  static const identifier = ExtHostContext.extHostWebviews;

  final RpcProtocol _rpc;

  /// `$onMessage(handle: WebviewHandle, jsonSerializedMessage: string, buffers: SerializableObjectWithBuffers<VSBuffer[]>): void`
  Future<void> $onMessage(
    String handle,
    String jsonSerializedMessage,
    Object? buffers,
  ) => _rpc.call(identifier.nid, r'$onMessage', [
    handle,
    jsonSerializedMessage,
    buffers,
  ]);

  /// `$onMissingCsp(handle: WebviewHandle, extensionId: string): void`
  Future<void> $onMissingCsp(String handle, String extensionId) =>
      _rpc.call(identifier.nid, r'$onMissingCsp', [handle, extensionId]);
}

/// Calls `ExtHostWebviewPanelsShape` (`ExtHostWebviewPanels`) in the extension host.
final class ExtHostWebviewPanelsProxy {
  ExtHostWebviewPanelsProxy(this._rpc);

  static const identifier = ExtHostContext.extHostWebviewPanels;

  final RpcProtocol _rpc;

  /// `$onDidChangeWebviewPanelViewStates(newState: WebviewPanelViewStateData): void`
  Future<void> $onDidChangeWebviewPanelViewStates(
    Map<String, Object?> newState,
  ) => _rpc.call(identifier.nid, r'$onDidChangeWebviewPanelViewStates', [
    newState,
  ]);

  /// `$onDidDisposeWebviewPanel(handle: WebviewHandle): Promise<void>`
  Future<void> $onDidDisposeWebviewPanel(String handle) =>
      _rpc.call(identifier.nid, r'$onDidDisposeWebviewPanel', [handle]);

  /// `$deserializeWebviewPanel(newWebviewHandle: WebviewHandle, viewType: string, initData: { title: string; state: any; webviewOptions: IWebviewContentOptions; panelOptions: IWebviewPanelOptions; active: boolean; }, position: EditorGroupColumn): Promise<void>`
  Future<void> $deserializeWebviewPanel(
    String newWebviewHandle,
    String viewType,
    Map<String, Object?> initData,
    num position,
  ) => _rpc.call(identifier.nid, r'$deserializeWebviewPanel', [
    newWebviewHandle,
    viewType,
    initData,
    position,
  ]);
}

/// Calls `ExtHostCustomEditorsShape` (`ExtHostCustomEditors`) in the extension host.
final class ExtHostCustomEditorsProxy {
  ExtHostCustomEditorsProxy(this._rpc);

  static const identifier = ExtHostContext.extHostCustomEditors;

  final RpcProtocol _rpc;

  /// `$resolveCustomEditor(resource: UriComponents, newWebviewHandle: WebviewHandle, viewType: string, initData: { title: string; contentOptions: IWebviewContentOptions; options: IWebviewPanelOptions; active: boolean; }, position: EditorGroupColumn, cancellation: CancellationToken): Promise<void>`
  Future<void> $resolveCustomEditor(
    VsUri resource,
    String newWebviewHandle,
    String viewType,
    Map<String, Object?> initData,
    num position, {
    CancellationToken? token,
  }) => _rpc.call(identifier.nid, r'$resolveCustomEditor', [
    resource,
    newWebviewHandle,
    viewType,
    initData,
    position,
  ], token: token);

  /// `$resolveCustomEditorInlineDiff(originalResource: UriComponents, modifiedResource: UriComponents, newWebviewHandle: WebviewHandle, viewType: string, initData: CustomEditorDiffInitData, position: EditorGroupColumn, cancellation: CancellationToken): Promise<void>`
  Future<void> $resolveCustomEditorInlineDiff(
    VsUri originalResource,
    VsUri modifiedResource,
    String newWebviewHandle,
    String viewType,
    Map<String, Object?> initData,
    num position, {
    CancellationToken? token,
  }) => _rpc.call(identifier.nid, r'$resolveCustomEditorInlineDiff', [
    originalResource,
    modifiedResource,
    newWebviewHandle,
    viewType,
    initData,
    position,
  ], token: token);

  /// `$resolveCustomEditorSideBySideDiff(originalResource: UriComponents, modifiedResource: UriComponents, webviewHandles: CustomEditorSideBySideDiffWebviewHandles, viewType: string, initData: CustomEditorSideBySideDiffInitData, position: EditorGroupColumn, cancellation: CancellationToken): Promise<void>`
  Future<void> $resolveCustomEditorSideBySideDiff(
    VsUri originalResource,
    VsUri modifiedResource,
    Map<String, Object?> webviewHandles,
    String viewType,
    Map<String, Object?> initData,
    num position, {
    CancellationToken? token,
  }) => _rpc.call(identifier.nid, r'$resolveCustomEditorSideBySideDiff', [
    originalResource,
    modifiedResource,
    webviewHandles,
    viewType,
    initData,
    position,
  ], token: token);

  /// `$createCustomDocument(resource: UriComponents, viewType: string, backupId: string | undefined, untitledDocumentData: VSBuffer | undefined, cancellation: CancellationToken): Promise<{ editable: boolean }>`
  Future<Map<String, Object?>> $createCustomDocument(
    VsUri resource,
    String viewType,
    String? backupId,
    RpcBuffer? untitledDocumentData, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostCustomEditors.$createCustomDocument',
    await _rpc.call(identifier.nid, r'$createCustomDocument', [
      resource,
      viewType,
      backupId ?? rpcUndefined,
      untitledDocumentData ?? rpcUndefined,
    ], token: token),
    decodeMap,
  );

  /// `$disposeCustomDocument(resource: UriComponents, viewType: string): Promise<void>`
  Future<void> $disposeCustomDocument(VsUri resource, String viewType) => _rpc
      .call(identifier.nid, r'$disposeCustomDocument', [resource, viewType]);

  /// `$undo(resource: UriComponents, viewType: string, editId: number, isDirty: boolean): Promise<void>`
  Future<void> $undo(
    VsUri resource,
    String viewType,
    num editId,
    bool isDirty,
  ) => _rpc.call(identifier.nid, r'$undo', [
    resource,
    viewType,
    editId,
    isDirty,
  ]);

  /// `$redo(resource: UriComponents, viewType: string, editId: number, isDirty: boolean): Promise<void>`
  Future<void> $redo(
    VsUri resource,
    String viewType,
    num editId,
    bool isDirty,
  ) => _rpc.call(identifier.nid, r'$redo', [
    resource,
    viewType,
    editId,
    isDirty,
  ]);

  /// `$revert(resource: UriComponents, viewType: string, cancellation: CancellationToken): Promise<void>`
  Future<void> $revert(
    VsUri resource,
    String viewType, {
    CancellationToken? token,
  }) =>
      _rpc.call(identifier.nid, r'$revert', [resource, viewType], token: token);

  /// `$disposeEdits(resourceComponents: UriComponents, viewType: string, editIds: number[]): void`
  Future<void> $disposeEdits(
    VsUri resourceComponents,
    String viewType,
    List<num> editIds,
  ) => _rpc.call(identifier.nid, r'$disposeEdits', [
    resourceComponents,
    viewType,
    editIds,
  ]);

  /// `$onSave(resource: UriComponents, viewType: string, cancellation: CancellationToken): Promise<void>`
  Future<void> $onSave(
    VsUri resource,
    String viewType, {
    CancellationToken? token,
  }) =>
      _rpc.call(identifier.nid, r'$onSave', [resource, viewType], token: token);

  /// `$onSaveAs(resource: UriComponents, viewType: string, targetResource: UriComponents, cancellation: CancellationToken): Promise<void>`
  Future<void> $onSaveAs(
    VsUri resource,
    String viewType,
    VsUri targetResource, {
    CancellationToken? token,
  }) => _rpc.call(identifier.nid, r'$onSaveAs', [
    resource,
    viewType,
    targetResource,
  ], token: token);

  /// `$backup(resource: UriComponents, viewType: string, cancellation: CancellationToken): Promise<string>`
  Future<String> $backup(
    VsUri resource,
    String viewType, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostCustomEditors.$backup',
    await _rpc.call(identifier.nid, r'$backup', [
      resource,
      viewType,
    ], token: token),
    decodeString,
  );

  /// `$onMoveCustomEditor(handle: WebviewHandle, newResource: UriComponents, viewType: string): Promise<void>`
  Future<void> $onMoveCustomEditor(
    String handle,
    VsUri newResource,
    String viewType,
  ) => _rpc.call(identifier.nid, r'$onMoveCustomEditor', [
    handle,
    newResource,
    viewType,
  ]);
}

/// Calls `ExtHostWebviewViewsShape` (`ExtHostWebviewViews`) in the extension host.
final class ExtHostWebviewViewsProxy {
  ExtHostWebviewViewsProxy(this._rpc);

  static const identifier = ExtHostContext.extHostWebviewViews;

  final RpcProtocol _rpc;

  /// `$resolveWebviewView(webviewHandle: WebviewHandle, viewType: string, title: string | undefined, state: any, cancellation: CancellationToken): Promise<void>`
  Future<void> $resolveWebviewView(
    String webviewHandle,
    String viewType,
    String? title,
    Object? state, {
    CancellationToken? token,
  }) => _rpc.call(identifier.nid, r'$resolveWebviewView', [
    webviewHandle,
    viewType,
    title ?? rpcUndefined,
    state,
  ], token: token);

  /// `$onDidChangeWebviewViewVisibility(webviewHandle: WebviewHandle, visible: boolean): void`
  Future<void> $onDidChangeWebviewViewVisibility(
    String webviewHandle,
    bool visible,
  ) => _rpc.call(identifier.nid, r'$onDidChangeWebviewViewVisibility', [
    webviewHandle,
    visible,
  ]);

  /// `$disposeWebviewView(webviewHandle: WebviewHandle): void`
  Future<void> $disposeWebviewView(String webviewHandle) =>
      _rpc.call(identifier.nid, r'$disposeWebviewView', [webviewHandle]);
}

/// Calls `ExtHostEditorInsetsShape` (`ExtHostEditorInsets`) in the extension host.
final class ExtHostEditorInsetsProxy {
  ExtHostEditorInsetsProxy(this._rpc);

  static const identifier = ExtHostContext.extHostEditorInsets;

  final RpcProtocol _rpc;

  /// `$onDidDispose(handle: number): void`
  Future<void> $onDidDispose(num handle) =>
      _rpc.call(identifier.nid, r'$onDidDispose', [handle]);

  /// `$onDidReceiveMessage(handle: number, message: any): void`
  Future<void> $onDidReceiveMessage(num handle, Object? message) =>
      _rpc.call(identifier.nid, r'$onDidReceiveMessage', [handle, message]);
}

/// Calls `IExtHostEditorTabsShape` (`ExtHostEditorTabs`) in the extension host.
final class ExtHostEditorTabsProxy {
  ExtHostEditorTabsProxy(this._rpc);

  static const identifier = ExtHostContext.extHostEditorTabs;

  final RpcProtocol _rpc;

  /// `$acceptEditorTabModel(tabGroups: IEditorTabGroupDto[]): void`
  Future<void> $acceptEditorTabModel(List<Map<String, Object?>> tabGroups) =>
      _rpc.call(identifier.nid, r'$acceptEditorTabModel', [tabGroups]);

  /// `$acceptTabGroupUpdate(groupDto: IEditorTabGroupDto): void`
  Future<void> $acceptTabGroupUpdate(Map<String, Object?> groupDto) =>
      _rpc.call(identifier.nid, r'$acceptTabGroupUpdate', [groupDto]);

  /// `$acceptTabOperation(operation: TabOperation): void`
  Future<void> $acceptTabOperation(Map<String, Object?> operation) =>
      _rpc.call(identifier.nid, r'$acceptTabOperation', [operation]);
}

/// Calls `ExtHostProgressShape` (`ExtHostProgress`) in the extension host.
final class ExtHostProgressProxy {
  ExtHostProgressProxy(this._rpc);

  static const identifier = ExtHostContext.extHostProgress;

  final RpcProtocol _rpc;

  /// `$acceptProgressCanceled(handle: number): void`
  Future<void> $acceptProgressCanceled(num handle) =>
      _rpc.call(identifier.nid, r'$acceptProgressCanceled', [handle]);
}

/// Calls `ExtHostCommentsShape` (`ExtHostComments`) in the extension host.
final class ExtHostCommentsProxy {
  ExtHostCommentsProxy(this._rpc);

  static const identifier = ExtHostContext.extHostComments;

  final RpcProtocol _rpc;

  /// `$createCommentThreadTemplate(commentControllerHandle: number, uriComponents: UriComponents, range: IRange | undefined, editorId?: string): Promise<void>`
  Future<void> $createCommentThreadTemplate(
    num commentControllerHandle,
    VsUri uriComponents,
    Map<String, Object?>? range, [
    String? editorId,
  ]) => _rpc.call(identifier.nid, r'$createCommentThreadTemplate', [
    commentControllerHandle,
    uriComponents,
    range ?? rpcUndefined,
    editorId ?? rpcUndefined,
  ]);

  /// `$updateCommentThreadTemplate(commentControllerHandle: number, threadHandle: number, range: IRange): Promise<void>`
  Future<void> $updateCommentThreadTemplate(
    num commentControllerHandle,
    num threadHandle,
    Map<String, Object?> range,
  ) => _rpc.call(identifier.nid, r'$updateCommentThreadTemplate', [
    commentControllerHandle,
    threadHandle,
    range,
  ]);

  /// `$updateCommentThread(commentControllerHandle: number, threadHandle: number, changes: CommentThreadChanges): Promise<void>`
  Future<void> $updateCommentThread(
    num commentControllerHandle,
    num threadHandle,
    Map<String, Object?> changes,
  ) => _rpc.call(identifier.nid, r'$updateCommentThread', [
    commentControllerHandle,
    threadHandle,
    changes,
  ]);

  /// `$deleteCommentThread(commentControllerHandle: number, commentThreadHandle: number): void`
  Future<void> $deleteCommentThread(
    num commentControllerHandle,
    num commentThreadHandle,
  ) => _rpc.call(identifier.nid, r'$deleteCommentThread', [
    commentControllerHandle,
    commentThreadHandle,
  ]);

  /// `$provideCommentingRanges(commentControllerHandle: number, uriComponents: UriComponents, token: CancellationToken): Promise<{ ranges: IRange[]; fileComments: boolean } | undefined>`
  Future<Map<String, Object?>?> $provideCommentingRanges(
    num commentControllerHandle,
    VsUri uriComponents, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostComments.$provideCommentingRanges',
    await _rpc.call(identifier.nid, r'$provideCommentingRanges', [
      commentControllerHandle,
      uriComponents,
    ], token: token),
    decodeNullable(decodeMap),
  );

  /// `$toggleReaction(commentControllerHandle: number, threadHandle: number, uri: UriComponents, comment: languages.Comment, reaction: languages.CommentReaction): Promise<void>`
  Future<void> $toggleReaction(
    num commentControllerHandle,
    num threadHandle,
    VsUri uri,
    Map<String, Object?> comment,
    Map<String, Object?> reaction,
  ) => _rpc.call(identifier.nid, r'$toggleReaction', [
    commentControllerHandle,
    threadHandle,
    uri,
    comment,
    reaction,
  ]);

  /// `$setActiveComment(controllerHandle: number, commentInfo: { commentThreadHandle: number; uniqueIdInThread?: number } | undefined): Promise<void>`
  Future<void> $setActiveComment(
    num controllerHandle,
    Map<String, Object?>? commentInfo,
  ) => _rpc.call(identifier.nid, r'$setActiveComment', [
    controllerHandle,
    commentInfo ?? rpcUndefined,
  ]);
}

/// Calls `ExtHostSecretStateShape` (`ExtHostSecretState`) in the extension host.
final class ExtHostSecretStateProxy {
  ExtHostSecretStateProxy(this._rpc);

  static const identifier = ExtHostContext.extHostSecretState;

  final RpcProtocol _rpc;

  /// `$onDidChangePassword(e: { extensionId: string; key: string }): Promise<void>`
  Future<void> $onDidChangePassword(Map<String, Object?> e) =>
      _rpc.call(identifier.nid, r'$onDidChangePassword', [e]);
}

/// Calls `ExtHostStorageShape` (`ExtHostStorage`) in the extension host.
final class ExtHostStorageProxy {
  ExtHostStorageProxy(this._rpc);

  static const identifier = ExtHostContext.extHostStorage;

  final RpcProtocol _rpc;

  /// `$acceptValue(shared: boolean, extensionId: string, value: string): void`
  Future<void> $acceptValue(bool shared, String extensionId, String value) =>
      _rpc.call(identifier.nid, r'$acceptValue', [shared, extensionId, value]);
}

/// Calls `ExtHostUrlsShape` (`ExtHostUrls`) in the extension host.
final class ExtHostUrlsProxy {
  ExtHostUrlsProxy(this._rpc);

  static const identifier = ExtHostContext.extHostUrls;

  final RpcProtocol _rpc;

  /// `$handleExternalUri(handle: number, uri: UriComponents): Promise<void>`
  Future<void> $handleExternalUri(num handle, VsUri uri) =>
      _rpc.call(identifier.nid, r'$handleExternalUri', [handle, uri]);
}

/// Calls `ExtHostUriOpenersShape` (`ExtHostUriOpeners`) in the extension host.
final class ExtHostUriOpenersProxy {
  ExtHostUriOpenersProxy(this._rpc);

  static const identifier = ExtHostContext.extHostUriOpeners;

  final RpcProtocol _rpc;

  /// `$canOpenUri(id: string, uri: UriComponents, token: CancellationToken): Promise<languages.ExternalUriOpenerPriority>`
  Future<int> $canOpenUri(
    String id,
    VsUri uri, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostUriOpeners.$canOpenUri',
    await _rpc.call(identifier.nid, r'$canOpenUri', [id, uri], token: token),
    decodeInt,
  );

  /// `$openUri(id: string, context: { resolvedUri: UriComponents; sourceUri: UriComponents }, token: CancellationToken): Promise<void>`
  Future<void> $openUri(
    String id,
    Map<String, Object?> context, {
    CancellationToken? token,
  }) => _rpc.call(identifier.nid, r'$openUri', [id, context], token: token);
}

/// Calls `ExtHostChatOutputRendererShape` (`ExtHostChatOutputRenderer`) in the extension host.
final class ExtHostChatOutputRendererProxy {
  ExtHostChatOutputRendererProxy(this._rpc);

  static const identifier = ExtHostContext.extHostChatOutputRenderer;

  final RpcProtocol _rpc;

  /// `$renderChatOutput(viewType: string, mime: string, valueData: VSBuffer, webviewHandle: string, context: IChatOutputRenderContextDto, token: CancellationToken): Promise<void>`
  Future<void> $renderChatOutput(
    String viewType,
    String mime,
    RpcBuffer valueData,
    String webviewHandle,
    Map<String, Object?> context, {
    CancellationToken? token,
  }) => _rpc.call(identifier.nid, r'$renderChatOutput', [
    viewType,
    mime,
    valueData,
    webviewHandle,
    context,
  ], token: token);
}

/// Calls `ExtHostProfileContentHandlersShape` (`ExtHostProfileContentHandlers`) in the extension host.
final class ExtHostProfileContentHandlersProxy {
  ExtHostProfileContentHandlersProxy(this._rpc);

  static const identifier = ExtHostContext.extHostProfileContentHandlers;

  final RpcProtocol _rpc;

  /// `$saveProfile(id: string, name: string, content: string, token: CancellationToken): Promise<UriDto<ISaveProfileResult> | null>`
  Future<Map<String, Object?>?> $saveProfile(
    String id,
    String name,
    String content, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostProfileContentHandlers.$saveProfile',
    await _rpc.call(identifier.nid, r'$saveProfile', [
      id,
      name,
      content,
    ], token: token),
    decodeNullable(decodeMap),
  );

  /// `$readProfile(id: string, idOrUri: string | UriComponents, token: CancellationToken): Promise<string | null>`
  Future<String?> $readProfile(
    String id,
    Object? idOrUri, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostProfileContentHandlers.$readProfile',
    await _rpc.call(identifier.nid, r'$readProfile', [
      id,
      idOrUri,
    ], token: token),
    decodeNullable(decodeString),
  );
}

/// Calls `ExtHostOutputServiceShape` (`ExtHostOutputService`) in the extension host.
final class ExtHostOutputServiceProxy {
  ExtHostOutputServiceProxy(this._rpc);

  static const identifier = ExtHostContext.extHostOutputService;

  final RpcProtocol _rpc;

  /// `$setVisibleChannel(channelId: string | null): void`
  Future<void> $setVisibleChannel(String? channelId) =>
      _rpc.call(identifier.nid, r'$setVisibleChannel', [channelId]);
}

/// Calls `ExtHostLabelServiceShape` (`ExtHostLabelService`) in the extension host.
final class ExtHostLabelServiceProxy {
  ExtHostLabelServiceProxy(this._rpc);

  static const identifier = ExtHostContext.extHostLabelService;

  final RpcProtocol _rpc;

  /// `$registerResourceLabelFormatter(formatter: ResourceLabelFormatter): IDisposable`
  Future<Map<String, Object?>> $registerResourceLabelFormatter(
    Map<String, Object?> formatter,
  ) async => decodeReply(
    r'ExtHostLabelService.$registerResourceLabelFormatter',
    await _rpc.call(identifier.nid, r'$registerResourceLabelFormatter', [
      formatter,
    ]),
    decodeMap,
  );
}

/// Calls `ExtHostNotebookShape` (`ExtHostNotebook`) in the extension host.
final class ExtHostNotebookProxy {
  ExtHostNotebookProxy(this._rpc);

  static const identifier = ExtHostContext.extHostNotebook;

  final RpcProtocol _rpc;

  /// `$provideNotebookCellStatusBarItems(handle: number, uri: UriComponents, index: number, token: CancellationToken): Promise<INotebookCellStatusBarListDto | undefined>`
  Future<Map<String, Object?>?> $provideNotebookCellStatusBarItems(
    num handle,
    VsUri uri,
    num index, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostNotebook.$provideNotebookCellStatusBarItems',
    await _rpc.call(identifier.nid, r'$provideNotebookCellStatusBarItems', [
      handle,
      uri,
      index,
    ], token: token),
    decodeNullable(decodeMap),
  );

  /// `$releaseNotebookCellStatusBarItems(id: number): void`
  Future<void> $releaseNotebookCellStatusBarItems(num id) =>
      _rpc.call(identifier.nid, r'$releaseNotebookCellStatusBarItems', [id]);

  /// `$dataToNotebook(handle: number, data: VSBuffer, token: CancellationToken): Promise<SerializableObjectWithBuffers<NotebookDataDto>>`
  Future<Object?> $dataToNotebook(
    num handle,
    RpcBuffer data, {
    CancellationToken? token,
  }) => _rpc.call(identifier.nid, r'$dataToNotebook', [
    handle,
    data,
  ], token: token);

  /// `$notebookToData(handle: number, data: SerializableObjectWithBuffers<NotebookDataDto>, token: CancellationToken): Promise<VSBuffer>`
  Future<RpcBuffer> $notebookToData(
    num handle,
    Object? data, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostNotebook.$notebookToData',
    await _rpc.call(identifier.nid, r'$notebookToData', [
      handle,
      data,
    ], token: token),
    decodeBuffer,
  );

  /// `$saveNotebook(handle: number, uri: UriComponents, versionId: number, options: files.IWriteFileOptions, token: CancellationToken): Promise<INotebookPartialFileStatsWithMetadata | files.FileOperationError>`
  Future<Map<String, Object?>> $saveNotebook(
    num handle,
    VsUri uri,
    num versionId,
    Map<String, Object?> options, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostNotebook.$saveNotebook',
    await _rpc.call(identifier.nid, r'$saveNotebook', [
      handle,
      uri,
      versionId,
      options,
    ], token: token),
    decodeMap,
  );

  /// `$searchInNotebooks(handle: number, textQuery: search.ITextQuery, viewTypeFileTargets: NotebookPriorityInfo[], otherViewTypeFileTargets: NotebookPriorityInfo[], token: CancellationToken): Promise<{ results: IRawClosedNotebookFileMatch[]; limitHit: boolean }>`
  Future<Map<String, Object?>> $searchInNotebooks(
    num handle,
    Map<String, Object?> textQuery,
    List<Map<String, Object?>> viewTypeFileTargets,
    List<Map<String, Object?>> otherViewTypeFileTargets, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostNotebook.$searchInNotebooks',
    await _rpc.call(identifier.nid, r'$searchInNotebooks', [
      handle,
      textQuery,
      viewTypeFileTargets,
      otherViewTypeFileTargets,
    ], token: token),
    decodeMap,
  );

  /// `$acceptDocumentAndEditorsDelta(delta: SerializableObjectWithBuffers<INotebookDocumentsAndEditorsDelta>): void`
  Future<void> $acceptDocumentAndEditorsDelta(Object? delta) =>
      _rpc.call(identifier.nid, r'$acceptDocumentAndEditorsDelta', [delta]);
}

/// Calls `ExtHostNotebookDocumentsShape` (`ExtHostNotebookDocuments`) in the extension host.
final class ExtHostNotebookDocumentsProxy {
  ExtHostNotebookDocumentsProxy(this._rpc);

  static const identifier = ExtHostContext.extHostNotebookDocuments;

  final RpcProtocol _rpc;

  /// `$acceptModelChanged(uriComponents: UriComponents, event: SerializableObjectWithBuffers<NotebookCellsChangedEventDto>, isDirty: boolean, newMetadata?: notebookCommon.NotebookDocumentMetadata): void`
  Future<void> $acceptModelChanged(
    VsUri uriComponents,
    Object? event,
    bool isDirty, [
    Map<String, Object?>? newMetadata,
  ]) => _rpc.call(identifier.nid, r'$acceptModelChanged', [
    uriComponents,
    event,
    isDirty,
    newMetadata ?? rpcUndefined,
  ]);

  /// `$acceptDirtyStateChanged(uriComponents: UriComponents, isDirty: boolean): void`
  Future<void> $acceptDirtyStateChanged(VsUri uriComponents, bool isDirty) =>
      _rpc.call(identifier.nid, r'$acceptDirtyStateChanged', [
        uriComponents,
        isDirty,
      ]);

  /// `$acceptModelSaved(uriComponents: UriComponents): void`
  Future<void> $acceptModelSaved(VsUri uriComponents) =>
      _rpc.call(identifier.nid, r'$acceptModelSaved', [uriComponents]);
}

/// Calls `ExtHostNotebookEditorsShape` (`ExtHostNotebookEditors`) in the extension host.
final class ExtHostNotebookEditorsProxy {
  ExtHostNotebookEditorsProxy(this._rpc);

  static const identifier = ExtHostContext.extHostNotebookEditors;

  final RpcProtocol _rpc;

  /// `$acceptEditorPropertiesChanged(id: string, data: INotebookEditorPropertiesChangeData): void`
  Future<void> $acceptEditorPropertiesChanged(
    String id,
    Map<String, Object?> data,
  ) => _rpc.call(identifier.nid, r'$acceptEditorPropertiesChanged', [id, data]);

  /// `$acceptEditorViewColumns(data: INotebookEditorViewColumnInfo): void`
  Future<void> $acceptEditorViewColumns(Map<String, num> data) =>
      _rpc.call(identifier.nid, r'$acceptEditorViewColumns', [data]);
}

/// Calls `ExtHostNotebookKernelsShape` (`ExtHostNotebookKernels`) in the extension host.
final class ExtHostNotebookKernelsProxy {
  ExtHostNotebookKernelsProxy(this._rpc);

  static const identifier = ExtHostContext.extHostNotebookKernels;

  final RpcProtocol _rpc;

  /// `$acceptNotebookAssociation(handle: number, uri: UriComponents, value: boolean): void`
  Future<void> $acceptNotebookAssociation(num handle, VsUri uri, bool value) =>
      _rpc.call(identifier.nid, r'$acceptNotebookAssociation', [
        handle,
        uri,
        value,
      ]);

  /// `$executeCells(handle: number, uri: UriComponents, handles: number[]): Promise<void>`
  Future<void> $executeCells(num handle, VsUri uri, List<num> handles) =>
      _rpc.call(identifier.nid, r'$executeCells', [handle, uri, handles]);

  /// `$cancelCells(handle: number, uri: UriComponents, handles: number[]): Promise<void>`
  Future<void> $cancelCells(num handle, VsUri uri, List<num> handles) =>
      _rpc.call(identifier.nid, r'$cancelCells', [handle, uri, handles]);

  /// `$acceptKernelMessageFromRenderer(handle: number, editorId: string, message: any): void`
  Future<void> $acceptKernelMessageFromRenderer(
    num handle,
    String editorId,
    Object? message,
  ) => _rpc.call(identifier.nid, r'$acceptKernelMessageFromRenderer', [
    handle,
    editorId,
    message,
  ]);

  /// `$provideKernelSourceActions(handle: number, token: CancellationToken): Promise<notebookCommon.INotebookKernelSourceAction[]>`
  Future<List<Map<String, Object?>>> $provideKernelSourceActions(
    num handle, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostNotebookKernels.$provideKernelSourceActions',
    await _rpc.call(identifier.nid, r'$provideKernelSourceActions', [
      handle,
    ], token: token),
    decodeListOf(decodeMap),
  );

  /// `$provideVariables(handle: number, requestId: string, notebookUri: UriComponents, parentId: number | undefined, kind: 'named' | 'indexed', start: number, token: CancellationToken): Promise<void>`
  Future<void> $provideVariables(
    num handle,
    String requestId,
    VsUri notebookUri,
    num? parentId,
    String kind,
    num start, {
    CancellationToken? token,
  }) => _rpc.call(identifier.nid, r'$provideVariables', [
    handle,
    requestId,
    notebookUri,
    parentId ?? rpcUndefined,
    kind,
    start,
  ], token: token);
}

/// Calls `ExtHostNotebookRenderersShape` (`ExtHostNotebookRenderers`) in the extension host.
final class ExtHostNotebookRenderersProxy {
  ExtHostNotebookRenderersProxy(this._rpc);

  static const identifier = ExtHostContext.extHostNotebookRenderers;

  final RpcProtocol _rpc;

  /// `$postRendererMessage(editorId: string, rendererId: string, message: unknown): void`
  Future<void> $postRendererMessage(
    String editorId,
    String rendererId,
    Object? message,
  ) => _rpc.call(identifier.nid, r'$postRendererMessage', [
    editorId,
    rendererId,
    message,
  ]);
}

/// Calls `ExtHostNotebookDocumentSaveParticipantShape` (`ExtHostNotebookDocumentSaveParticipant`) in the extension host.
final class ExtHostNotebookDocumentSaveParticipantProxy {
  ExtHostNotebookDocumentSaveParticipantProxy(this._rpc);

  static const identifier =
      ExtHostContext.extHostNotebookDocumentSaveParticipant;

  final RpcProtocol _rpc;

  /// `$participateInSave(resource: UriComponents, reason: SaveReason, token: CancellationToken): Promise<boolean>`
  Future<bool> $participateInSave(
    VsUri resource,
    int reason, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostNotebookDocumentSaveParticipant.$participateInSave',
    await _rpc.call(identifier.nid, r'$participateInSave', [
      resource,
      reason,
    ], token: token),
    decodeBool,
  );
}

/// Calls `ExtHostInteractiveShape` (`ExtHostInteractive`) in the extension host.
final class ExtHostInteractiveProxy {
  ExtHostInteractiveProxy(this._rpc);

  static const identifier = ExtHostContext.extHostInteractive;

  final RpcProtocol _rpc;

  /// `$willAddInteractiveDocument(uri: UriComponents, eol: string, languageId: string, notebookUri: UriComponents): void`
  Future<void> $willAddInteractiveDocument(
    VsUri uri,
    String eol,
    String languageId,
    VsUri notebookUri,
  ) => _rpc.call(identifier.nid, r'$willAddInteractiveDocument', [
    uri,
    eol,
    languageId,
    notebookUri,
  ]);

  /// `$willRemoveInteractiveDocument(uri: UriComponents, notebookUri: UriComponents): void`
  Future<void> $willRemoveInteractiveDocument(VsUri uri, VsUri notebookUri) =>
      _rpc.call(identifier.nid, r'$willRemoveInteractiveDocument', [
        uri,
        notebookUri,
      ]);
}

/// Calls `ExtHostChatAgentsShape2` (`ExtHostChatAgents`) in the extension host.
final class ExtHostChatAgents2Proxy {
  ExtHostChatAgents2Proxy(this._rpc);

  static const identifier = ExtHostContext.extHostChatAgents2;

  final RpcProtocol _rpc;

  /// `$invokeAgent(handle: number, request: Dto<IChatAgentRequest>, context: { history: IChatAgentHistoryEntryDto[]; chatSessionContext?: IChatSessionContextDto }, token: CancellationToken): Promise<IChatAgentInvokeResult | undefined>`
  Future<Map<String, Object?>?> $invokeAgent(
    num handle,
    Map<String, Object?> request,
    Map<String, Object?> context, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostChatAgents2.$invokeAgent',
    await _rpc.call(identifier.nid, r'$invokeAgent', [
      handle,
      request,
      context,
    ], token: token),
    decodeNullable(decodeMap),
  );

  /// `$provideFollowups(request: Dto<IChatAgentRequest>, handle: number, result: IChatAgentResult, context: { history: IChatAgentHistoryEntryDto[] }, token: CancellationToken): Promise<IChatFollowup[]>`
  Future<List<Map<String, Object?>>> $provideFollowups(
    Map<String, Object?> request,
    num handle,
    Map<String, Object?> result,
    Map<String, Object?> context, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostChatAgents2.$provideFollowups',
    await _rpc.call(identifier.nid, r'$provideFollowups', [
      request,
      handle,
      result,
      context,
    ], token: token),
    decodeListOf(decodeMap),
  );

  /// `$acceptFeedback(handle: number, result: IChatAgentResult, voteAction: IChatVoteAction): void`
  Future<void> $acceptFeedback(
    num handle,
    Map<String, Object?> result,
    Map<String, Object?> voteAction,
  ) => _rpc.call(identifier.nid, r'$acceptFeedback', [
    handle,
    result,
    voteAction,
  ]);

  /// `$handleQuestionCarouselAnswer(requestId: string, resolveId: string, answers: Record<string, unknown> | undefined): void`
  Future<void> $handleQuestionCarouselAnswer(
    String requestId,
    String resolveId,
    Map<String, Object?>? answers,
  ) => _rpc.call(identifier.nid, r'$handleQuestionCarouselAnswer', [
    requestId,
    resolveId,
    answers ?? rpcUndefined,
  ]);

  /// `$acceptAction(handle: number, result: IChatAgentResult, action: IChatUserActionEvent): void`
  Future<void> $acceptAction(
    num handle,
    Map<String, Object?> result,
    Map<String, Object?> action,
  ) => _rpc.call(identifier.nid, r'$acceptAction', [handle, result, action]);

  /// `$invokeCompletionProvider(handle: number, query: string, token: CancellationToken): Promise<IChatAgentCompletionItem[]>`
  Future<List<Map<String, Object?>>> $invokeCompletionProvider(
    num handle,
    String query, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostChatAgents2.$invokeCompletionProvider',
    await _rpc.call(identifier.nid, r'$invokeCompletionProvider', [
      handle,
      query,
    ], token: token),
    decodeListOf(decodeMap),
  );

  /// `$provideChatTitle(handle: number, context: IChatAgentHistoryEntryDto[], token: CancellationToken): Promise<string | undefined>`
  Future<String?> $provideChatTitle(
    num handle,
    List<Map<String, Object?>> context, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostChatAgents2.$provideChatTitle',
    await _rpc.call(identifier.nid, r'$provideChatTitle', [
      handle,
      context,
    ], token: token),
    decodeNullable(decodeString),
  );

  /// `$provideChatSummary(handle: number, context: IChatAgentHistoryEntryDto[], token: CancellationToken): Promise<string | undefined>`
  Future<String?> $provideChatSummary(
    num handle,
    List<Map<String, Object?>> context, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostChatAgents2.$provideChatSummary',
    await _rpc.call(identifier.nid, r'$provideChatSummary', [
      handle,
      context,
    ], token: token),
    decodeNullable(decodeString),
  );

  /// `$releaseSession(sessionResource: UriComponents): void`
  Future<void> $releaseSession(VsUri sessionResource) =>
      _rpc.call(identifier.nid, r'$releaseSession', [sessionResource]);

  /// `$detectChatParticipant(handle: number, request: Dto<IChatAgentRequest>, context: { history: IChatAgentHistoryEntryDto[] }, options: { participants: IChatParticipantMetadata[]; location: ChatAgentLocation }, token: CancellationToken): Promise<IChatParticipantDetectionResult | null | undefined>`
  Future<Map<String, Object?>?> $detectChatParticipant(
    num handle,
    Map<String, Object?> request,
    Map<String, Object?> context,
    Map<String, Object?> options, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostChatAgents2.$detectChatParticipant',
    await _rpc.call(identifier.nid, r'$detectChatParticipant', [
      handle,
      request,
      context,
      options,
    ], token: token),
    decodeNullable(decodeMap),
  );

  /// `$providePromptFiles(handle: number, type: PromptsType, context: IPromptFileContext, token: CancellationToken): Promise<Dto<IPromptFileResource>[] | undefined>`
  Future<List<Map<String, Object?>>?> $providePromptFiles(
    num handle,
    String type,
    Map<String, Object?> context, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostChatAgents2.$providePromptFiles',
    await _rpc.call(identifier.nid, r'$providePromptFiles', [
      handle,
      type,
      context,
    ], token: token),
    decodeNullable(decodeListOf(decodeMap)),
  );

  /// `$provideChatSessionCustomizations(handle: number, sessionResource: UriComponents, token: CancellationToken): Promise<IChatSessionCustomizationItemDto[] | undefined>`
  Future<List<Map<String, Object?>>?> $provideChatSessionCustomizations(
    num handle,
    VsUri sessionResource, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostChatAgents2.$provideChatSessionCustomizations',
    await _rpc.call(identifier.nid, r'$provideChatSessionCustomizations', [
      handle,
      sessionResource,
    ], token: token),
    decodeNullable(decodeListOf(decodeMap)),
  );

  /// `$provideSourceFolders(handle: number, sessionResource: UriComponents, type: string, token: CancellationToken): Promise<IChatSessionCustomizationSourceFolderDto[] | undefined>`
  Future<List<Map<String, Object?>>?> $provideSourceFolders(
    num handle,
    VsUri sessionResource,
    String type, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostChatAgents2.$provideSourceFolders',
    await _rpc.call(identifier.nid, r'$provideSourceFolders', [
      handle,
      sessionResource,
      type,
    ], token: token),
    decodeNullable(decodeListOf(decodeMap)),
  );

  /// `$setRequestTools(requestId: string, tools: UserSelectedTools): void`
  Future<void> $setRequestTools(String requestId, Map<String, bool> tools) =>
      _rpc.call(identifier.nid, r'$setRequestTools', [requestId, tools]);

  /// `$setYieldRequested(requestId: string, value: boolean): void`
  Future<void> $setYieldRequested(String requestId, bool value) =>
      _rpc.call(identifier.nid, r'$setYieldRequested', [requestId, value]);

  /// `$acceptActiveChatSession(sessionResource: UriComponents | undefined): void`
  Future<void> $acceptActiveChatSession(VsUri? sessionResource) => _rpc.call(
    identifier.nid,
    r'$acceptActiveChatSession',
    [sessionResource ?? rpcUndefined],
  );

  /// `$onDidChangeCustomAgents(): void`
  Future<void> $onDidChangeCustomAgents() =>
      _rpc.call(identifier.nid, r'$onDidChangeCustomAgents', []);

  /// `$onDidChangeInstructions(): void`
  Future<void> $onDidChangeInstructions() =>
      _rpc.call(identifier.nid, r'$onDidChangeInstructions', []);

  /// `$onDidChangeSkills(): void`
  Future<void> $onDidChangeSkills() =>
      _rpc.call(identifier.nid, r'$onDidChangeSkills', []);

  /// `$onDidChangeSlashCommands(): void`
  Future<void> $onDidChangeSlashCommands() =>
      _rpc.call(identifier.nid, r'$onDidChangeSlashCommands', []);

  /// `$onDidChangeHooks(): void`
  Future<void> $onDidChangeHooks() =>
      _rpc.call(identifier.nid, r'$onDidChangeHooks', []);

  /// `$onDidChangePlugins(): void`
  Future<void> $onDidChangePlugins() =>
      _rpc.call(identifier.nid, r'$onDidChangePlugins', []);
}

/// Calls `ExtHostLanguageModelToolsShape` (`ExtHostChatSkills`) in the extension host.
final class ExtHostLanguageModelToolsProxy {
  ExtHostLanguageModelToolsProxy(this._rpc);

  static const identifier = ExtHostContext.extHostLanguageModelTools;

  final RpcProtocol _rpc;

  /// `$onDidChangeTools(tools: IToolDataDto[]): void`
  Future<void> $onDidChangeTools(List<Map<String, Object?>> tools) =>
      _rpc.call(identifier.nid, r'$onDidChangeTools', [tools]);

  /// `$invokeTool(dto: Dto<IToolInvocation>, token: CancellationToken): Promise<Dto<IToolResult> | SerializableObjectWithBuffers<Dto<IToolResult>>>`
  Future<Object?> $invokeTool(
    Map<String, Object?> dto, {
    CancellationToken? token,
  }) => _rpc.call(identifier.nid, r'$invokeTool', [dto], token: token);

  /// `$countTokensForInvocation(callId: string, input: string, token: CancellationToken): Promise<number>`
  Future<num> $countTokensForInvocation(
    String callId,
    String input, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostLanguageModelTools.$countTokensForInvocation',
    await _rpc.call(identifier.nid, r'$countTokensForInvocation', [
      callId,
      input,
    ], token: token),
    decodeNum,
  );

  /// `$handleToolStream(toolId: string, context: IToolInvocationStreamContext, token: CancellationToken): Promise<IStreamedToolInvocation | undefined>`
  Future<Map<String, Object?>?> $handleToolStream(
    String toolId,
    Map<String, Object?> context, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostLanguageModelTools.$handleToolStream',
    await _rpc.call(identifier.nid, r'$handleToolStream', [
      toolId,
      context,
    ], token: token),
    decodeNullable(decodeMap),
  );

  /// `$prepareToolInvocation(toolId: string, context: IToolInvocationPreparationContext, token: CancellationToken): Promise<IPreparedToolInvocation | undefined>`
  Future<Map<String, Object?>?> $prepareToolInvocation(
    String toolId,
    Map<String, Object?> context, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostLanguageModelTools.$prepareToolInvocation',
    await _rpc.call(identifier.nid, r'$prepareToolInvocation', [
      toolId,
      context,
    ], token: token),
    decodeNullable(decodeMap),
  );
}

/// Calls `ExtHostLanguageModelsShape` (`ExtHostChatProvider`) in the extension host.
final class ExtHostChatProviderProxy {
  ExtHostChatProviderProxy(this._rpc);

  static const identifier = ExtHostContext.extHostChatProvider;

  final RpcProtocol _rpc;

  /// `$provideLanguageModelChatInfo(vendor: string, options: ILanguageModelChatInfoOptions, token: CancellationToken): Promise<ILanguageModelChatMetadataAndIdentifier[]>`
  Future<List<Map<String, Object?>>> $provideLanguageModelChatInfo(
    String vendor,
    Map<String, Object?> options, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostChatProvider.$provideLanguageModelChatInfo',
    await _rpc.call(identifier.nid, r'$provideLanguageModelChatInfo', [
      vendor,
      options,
    ], token: token),
    decodeListOf(decodeMap),
  );

  /// `$updateModelAccesslist(data: { from: ExtensionIdentifier; to: ExtensionIdentifier; enabled: boolean }[]): void`
  Future<void> $updateModelAccesslist(List<Map<String, Object?>> data) =>
      _rpc.call(identifier.nid, r'$updateModelAccesslist', [data]);

  /// `$onChatModelsChange(): void`
  Future<void> $onChatModelsChange() =>
      _rpc.call(identifier.nid, r'$onChatModelsChange', []);

  /// `$startChatRequest(modelId: string, requestId: number, from: ExtensionIdentifier | undefined, messages: SerializableObjectWithBuffers<IChatMessage[]>, options: ILanguageModelChatRequestOptions, token: CancellationToken): Promise<void>`
  Future<void> $startChatRequest(
    String modelId,
    num requestId,
    Map<String, Object?>? from,
    Object? messages,
    Map<String, Object?> options, {
    CancellationToken? token,
  }) => _rpc.call(identifier.nid, r'$startChatRequest', [
    modelId,
    requestId,
    from ?? rpcUndefined,
    messages,
    options,
  ], token: token);

  /// `$acceptResponsePart(requestId: number, chunk: SerializableObjectWithBuffers<IChatResponsePart | IChatResponsePart[]>): Promise<void>`
  Future<void> $acceptResponsePart(num requestId, Object? chunk) =>
      _rpc.call(identifier.nid, r'$acceptResponsePart', [requestId, chunk]);

  /// `$acceptResponseDone(requestId: number, error: SerializedError | undefined): Promise<void>`
  Future<void> $acceptResponseDone(
    num requestId,
    Map<String, Object?>? error,
  ) => _rpc.call(identifier.nid, r'$acceptResponseDone', [
    requestId,
    error ?? rpcUndefined,
  ]);

  /// `$cancelLanguageModelChatRequest(requestId: number): void`
  Future<void> $cancelLanguageModelChatRequest(num requestId) => _rpc.call(
    identifier.nid,
    r'$cancelLanguageModelChatRequest',
    [requestId],
  );

  /// `$provideTokenLength(modelId: string, value: string | IChatMessage, token: CancellationToken): Promise<number>`
  Future<num> $provideTokenLength(
    String modelId,
    Object? value, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostChatProvider.$provideTokenLength',
    await _rpc.call(identifier.nid, r'$provideTokenLength', [
      modelId,
      value,
    ], token: token),
    decodeNum,
  );

  /// `$isFileIgnored(handle: number, uri: UriComponents, token: CancellationToken): Promise<boolean>`
  Future<bool> $isFileIgnored(
    num handle,
    VsUri uri, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostChatProvider.$isFileIgnored',
    await _rpc.call(identifier.nid, r'$isFileIgnored', [
      handle,
      uri,
    ], token: token),
    decodeBool,
  );
}

/// Calls `ExtHostChatContextShape` (`ExtHostChatContext`) in the extension host.
final class ExtHostChatContextProxy {
  ExtHostChatContextProxy(this._rpc);

  static const identifier = ExtHostContext.extHostChatContext;

  final RpcProtocol _rpc;

  /// `$provideWorkspaceChatContext(handle: number, token: CancellationToken): Promise<IChatContextItem[]>`
  Future<List<Map<String, Object?>>> $provideWorkspaceChatContext(
    num handle, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostChatContext.$provideWorkspaceChatContext',
    await _rpc.call(identifier.nid, r'$provideWorkspaceChatContext', [
      handle,
    ], token: token),
    decodeListOf(decodeMap),
  );

  /// `$provideExplicitChatContext(handle: number, token: CancellationToken): Promise<IChatContextItem[]>`
  Future<List<Map<String, Object?>>> $provideExplicitChatContext(
    num handle, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostChatContext.$provideExplicitChatContext',
    await _rpc.call(identifier.nid, r'$provideExplicitChatContext', [
      handle,
    ], token: token),
    decodeListOf(decodeMap),
  );

  /// `$resolveExplicitChatContext(handle: number, context: IChatContextItem, token: CancellationToken): Promise<IChatContextItem>`
  Future<Map<String, Object?>> $resolveExplicitChatContext(
    num handle,
    Map<String, Object?> context, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostChatContext.$resolveExplicitChatContext',
    await _rpc.call(identifier.nid, r'$resolveExplicitChatContext', [
      handle,
      context,
    ], token: token),
    decodeMap,
  );

  /// `$provideResourceChatContext(handle: number, options: { resource: UriComponents; withValue: boolean; viewType?: string }, token: CancellationToken): Promise<IChatContextItem | undefined>`
  Future<Map<String, Object?>?> $provideResourceChatContext(
    num handle,
    Map<String, Object?> options, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostChatContext.$provideResourceChatContext',
    await _rpc.call(identifier.nid, r'$provideResourceChatContext', [
      handle,
      options,
    ], token: token),
    decodeNullable(decodeMap),
  );

  /// `$resolveResourceChatContext(handle: number, context: IChatContextItem, token: CancellationToken): Promise<IChatContextItem>`
  Future<Map<String, Object?>> $resolveResourceChatContext(
    num handle,
    Map<String, Object?> context, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostChatContext.$resolveResourceChatContext',
    await _rpc.call(identifier.nid, r'$resolveResourceChatContext', [
      handle,
      context,
    ], token: token),
    decodeMap,
  );

  /// `$executeChatContextItemCommand(itemHandle: number): Promise<void>`
  Future<void> $executeChatContextItemCommand(num itemHandle) => _rpc.call(
    identifier.nid,
    r'$executeChatContextItemCommand',
    [itemHandle],
  );
}

/// Calls `ExtHostChatDebugShape` (`ExtHostChatDebug`) in the extension host.
final class ExtHostChatDebugProxy {
  ExtHostChatDebugProxy(this._rpc);

  static const identifier = ExtHostContext.extHostChatDebug;

  final RpcProtocol _rpc;

  /// `$provideChatDebugLog(handle: number, sessionResource: UriComponents, token: CancellationToken): Promise<IChatDebugEventDto[] | undefined>`
  Future<List<Map<String, Object?>>?> $provideChatDebugLog(
    num handle,
    VsUri sessionResource, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostChatDebug.$provideChatDebugLog',
    await _rpc.call(identifier.nid, r'$provideChatDebugLog', [
      handle,
      sessionResource,
    ], token: token),
    decodeNullable(decodeListOf(decodeMap)),
  );

  /// `$resolveChatDebugLogEvent(handle: number, eventId: string, token: CancellationToken): Promise<IChatDebugResolvedEventContentDto | undefined>`
  Future<Map<String, Object?>?> $resolveChatDebugLogEvent(
    num handle,
    String eventId, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostChatDebug.$resolveChatDebugLogEvent',
    await _rpc.call(identifier.nid, r'$resolveChatDebugLogEvent', [
      handle,
      eventId,
    ], token: token),
    decodeNullable(decodeMap),
  );

  /// `$exportChatDebugLog(handle: number, sessionResource: UriComponents, coreEvents: IChatDebugEventDto[], sessionTitle: string | undefined, token: CancellationToken): Promise<VSBuffer | undefined>`
  Future<RpcBuffer?> $exportChatDebugLog(
    num handle,
    VsUri sessionResource,
    List<Map<String, Object?>> coreEvents,
    String? sessionTitle, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostChatDebug.$exportChatDebugLog',
    await _rpc.call(identifier.nid, r'$exportChatDebugLog', [
      handle,
      sessionResource,
      coreEvents,
      sessionTitle ?? rpcUndefined,
    ], token: token),
    decodeNullable(decodeBuffer),
  );

  /// `$importChatDebugLog(handle: number, data: VSBuffer, token: CancellationToken): Promise<{ uri: UriComponents; sessionTitle?: string } | undefined>`
  Future<Map<String, Object?>?> $importChatDebugLog(
    num handle,
    RpcBuffer data, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostChatDebug.$importChatDebugLog',
    await _rpc.call(identifier.nid, r'$importChatDebugLog', [
      handle,
      data,
    ], token: token),
    decodeNullable(decodeMap),
  );

  /// `$getAvailableDebugSessionResources(handle: number, token: CancellationToken): Promise<{ uri: UriComponents; title?: string }[]>`
  Future<List<Map<String, Object?>>> $getAvailableDebugSessionResources(
    num handle, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostChatDebug.$getAvailableDebugSessionResources',
    await _rpc.call(identifier.nid, r'$getAvailableDebugSessionResources', [
      handle,
    ], token: token),
    decodeListOf(decodeMap),
  );

  /// `$onCoreDebugEvent(event: IChatDebugEventDto): void`
  Future<void> $onCoreDebugEvent(Map<String, Object?> event) =>
      _rpc.call(identifier.nid, r'$onCoreDebugEvent', [event]);
}

/// Calls `ExtHostSpeechShape` (`ExtHostSpeech`) in the extension host.
final class ExtHostSpeechProxy {
  ExtHostSpeechProxy(this._rpc);

  static const identifier = ExtHostContext.extHostSpeech;

  final RpcProtocol _rpc;

  /// `$createSpeechToTextSession(handle: number, session: number, language?: string): Promise<void>`
  Future<void> $createSpeechToTextSession(
    num handle,
    num session, [
    String? language,
  ]) => _rpc.call(identifier.nid, r'$createSpeechToTextSession', [
    handle,
    session,
    language ?? rpcUndefined,
  ]);

  /// `$cancelSpeechToTextSession(session: number): Promise<void>`
  Future<void> $cancelSpeechToTextSession(num session) =>
      _rpc.call(identifier.nid, r'$cancelSpeechToTextSession', [session]);

  /// `$createTextToSpeechSession(handle: number, session: number, language?: string): Promise<void>`
  Future<void> $createTextToSpeechSession(
    num handle,
    num session, [
    String? language,
  ]) => _rpc.call(identifier.nid, r'$createTextToSpeechSession', [
    handle,
    session,
    language ?? rpcUndefined,
  ]);

  /// `$synthesizeSpeech(session: number, text: string): Promise<void>`
  Future<void> $synthesizeSpeech(num session, String text) =>
      _rpc.call(identifier.nid, r'$synthesizeSpeech', [session, text]);

  /// `$cancelTextToSpeechSession(session: number): Promise<void>`
  Future<void> $cancelTextToSpeechSession(num session) =>
      _rpc.call(identifier.nid, r'$cancelTextToSpeechSession', [session]);

  /// `$createKeywordRecognitionSession(handle: number, session: number): Promise<void>`
  Future<void> $createKeywordRecognitionSession(num handle, num session) =>
      _rpc.call(identifier.nid, r'$createKeywordRecognitionSession', [
        handle,
        session,
      ]);

  /// `$cancelKeywordRecognitionSession(session: number): Promise<void>`
  Future<void> $cancelKeywordRecognitionSession(num session) =>
      _rpc.call(identifier.nid, r'$cancelKeywordRecognitionSession', [session]);
}

/// Calls `ExtHostEmbeddingsShape` (`ExtHostEmbeddings`) in the extension host.
final class ExtHostEmbeddingsProxy {
  ExtHostEmbeddingsProxy(this._rpc);

  static const identifier = ExtHostContext.extHostEmbeddings;

  final RpcProtocol _rpc;

  /// `$provideEmbeddings(handle: number, input: string[], token: CancellationToken): Promise<{ values: number[] }[]>`
  Future<List<Map<String, Object?>>> $provideEmbeddings(
    num handle,
    List<String> input, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostEmbeddings.$provideEmbeddings',
    await _rpc.call(identifier.nid, r'$provideEmbeddings', [
      handle,
      input,
    ], token: token),
    decodeListOf(decodeMap),
  );

  /// `$acceptEmbeddingModels(models: string[]): void`
  Future<void> $acceptEmbeddingModels(List<String> models) =>
      _rpc.call(identifier.nid, r'$acceptEmbeddingModels', [models]);
}

/// Calls `ExtHostAiRelatedInformationShape` (`ExtHostAiRelatedInformation`) in the extension host.
final class ExtHostAiRelatedInformationProxy {
  ExtHostAiRelatedInformationProxy(this._rpc);

  static const identifier = ExtHostContext.extHostAiRelatedInformation;

  final RpcProtocol _rpc;

  /// `$provideAiRelatedInformation(handle: number, query: string, token: CancellationToken): Promise<RelatedInformationResult[]>`
  Future<List<Map<String, Object?>>> $provideAiRelatedInformation(
    num handle,
    String query, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostAiRelatedInformation.$provideAiRelatedInformation',
    await _rpc.call(identifier.nid, r'$provideAiRelatedInformation', [
      handle,
      query,
    ], token: token),
    decodeListOf(decodeMap),
  );
}

/// Calls `ExtHostAiEmbeddingVectorShape` (`ExtHostAiEmbeddingVector`) in the extension host.
final class ExtHostAiEmbeddingVectorProxy {
  ExtHostAiEmbeddingVectorProxy(this._rpc);

  static const identifier = ExtHostContext.extHostAiEmbeddingVector;

  final RpcProtocol _rpc;

  /// `$provideAiEmbeddingVector(handle: number, strings: string[], token: CancellationToken): Promise<number[][]>`
  Future<List<List<num>>> $provideAiEmbeddingVector(
    num handle,
    List<String> strings, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostAiEmbeddingVector.$provideAiEmbeddingVector',
    await _rpc.call(identifier.nid, r'$provideAiEmbeddingVector', [
      handle,
      strings,
    ], token: token),
    decodeListOf(decodeListOf(decodeNum)),
  );
}

/// Calls `ExtHostAiSettingsSearchShape` (`ExtHostAiSettingsSearch`) in the extension host.
final class ExtHostAiSettingsSearchProxy {
  ExtHostAiSettingsSearchProxy(this._rpc);

  static const identifier = ExtHostContext.extHostAiSettingsSearch;

  final RpcProtocol _rpc;

  /// `$startSearch(handle: number, query: string, option: AiSettingsSearchProviderOptions, token: CancellationToken): Promise<void>`
  Future<void> $startSearch(
    num handle,
    String query,
    Map<String, Object?> option, {
    CancellationToken? token,
  }) => _rpc.call(identifier.nid, r'$startSearch', [
    handle,
    query,
    option,
  ], token: token);
}

/// Calls `ExtHostThemingShape` (`ExtHostTheming`) in the extension host.
final class ExtHostThemingProxy {
  ExtHostThemingProxy(this._rpc);

  static const identifier = ExtHostContext.extHostTheming;

  final RpcProtocol _rpc;

  /// `$onColorThemeChange(themeType: string): void`
  Future<void> $onColorThemeChange(String themeType) =>
      _rpc.call(identifier.nid, r'$onColorThemeChange', [themeType]);
}

/// Calls `ExtHostTunnelServiceShape` (`ExtHostTunnelService`) in the extension host.
final class ExtHostTunnelServiceProxy {
  ExtHostTunnelServiceProxy(this._rpc);

  static const identifier = ExtHostContext.extHostTunnelService;

  final RpcProtocol _rpc;

  /// `$forwardPort(tunnelOptions: TunnelOptions, tunnelCreationOptions: TunnelCreationOptions): Promise<TunnelDto | string | undefined>`
  Future<Object?> $forwardPort(
    Map<String, Object?> tunnelOptions,
    Map<String, Object?> tunnelCreationOptions,
  ) => _rpc.call(identifier.nid, r'$forwardPort', [
    tunnelOptions,
    tunnelCreationOptions,
  ]);

  /// `$closeTunnel(remote: { host: string; port: number }, silent?: boolean): Promise<void>`
  Future<void> $closeTunnel(Map<String, Object?> remote, [bool? silent]) => _rpc
      .call(identifier.nid, r'$closeTunnel', [remote, silent ?? rpcUndefined]);

  /// `$onDidTunnelsChange(): Promise<void>`
  Future<void> $onDidTunnelsChange() =>
      _rpc.call(identifier.nid, r'$onDidTunnelsChange', []);

  /// `$registerCandidateFinder(enable: boolean): Promise<void>`
  Future<void> $registerCandidateFinder(bool enable) =>
      _rpc.call(identifier.nid, r'$registerCandidateFinder', [enable]);

  /// `$applyCandidateFilter(candidates: CandidatePort[]): Promise<CandidatePort[]>`
  Future<List<Map<String, Object?>>> $applyCandidateFilter(
    List<Map<String, Object?>> candidates,
  ) async => decodeReply(
    r'ExtHostTunnelService.$applyCandidateFilter',
    await _rpc.call(identifier.nid, r'$applyCandidateFilter', [candidates]),
    decodeListOf(decodeMap),
  );

  /// `$providePortAttributes(handles: number[], ports: number[], pid: number | undefined, commandline: string | undefined, cancellationToken: CancellationToken): Promise<ProvidedPortAttributes[]>`
  Future<List<Map<String, Object?>>> $providePortAttributes(
    List<num> handles,
    List<num> ports,
    num? pid,
    String? commandline, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostTunnelService.$providePortAttributes',
    await _rpc.call(identifier.nid, r'$providePortAttributes', [
      handles,
      ports,
      pid ?? rpcUndefined,
      commandline ?? rpcUndefined,
    ], token: token),
    decodeListOf(decodeMap),
  );
}

/// Calls `ExtHostManagedSocketsShape` (`ExtHostManagedSockets`) in the extension host.
final class ExtHostManagedSocketsProxy {
  ExtHostManagedSocketsProxy(this._rpc);

  static const identifier = ExtHostContext.extHostManagedSockets;

  final RpcProtocol _rpc;

  /// `$openRemoteSocket(socketFactoryId: number): Promise<number>`
  Future<num> $openRemoteSocket(num socketFactoryId) async => decodeReply(
    r'ExtHostManagedSockets.$openRemoteSocket',
    await _rpc.call(identifier.nid, r'$openRemoteSocket', [socketFactoryId]),
    decodeNum,
  );

  /// `$remoteSocketWrite(socketId: number, buffer: VSBuffer): void`
  Future<void> $remoteSocketWrite(num socketId, RpcBuffer buffer) =>
      _rpc.call(identifier.nid, r'$remoteSocketWrite', [socketId, buffer]);

  /// `$remoteSocketEnd(socketId: number): void`
  Future<void> $remoteSocketEnd(num socketId) =>
      _rpc.call(identifier.nid, r'$remoteSocketEnd', [socketId]);

  /// `$remoteSocketDrain(socketId: number): Promise<void>`
  Future<void> $remoteSocketDrain(num socketId) =>
      _rpc.call(identifier.nid, r'$remoteSocketDrain', [socketId]);
}

/// Calls `ExtHostBrowserTunnelProxyShape` (`ExtHostBrowserTunnelProxy`) in the extension host.
final class ExtHostBrowserTunnelProxyProxy {
  ExtHostBrowserTunnelProxyProxy(this._rpc);

  static const identifier = ExtHostContext.extHostBrowserTunnelProxy;

  final RpcProtocol _rpc;

  /// `$setEnabled(enabled: boolean): void`
  Future<void> $setEnabled(bool enabled) =>
      _rpc.call(identifier.nid, r'$setEnabled', [enabled]);
}

/// Calls `ExtHostAuthenticationShape` (`ExtHostAuthentication`) in the extension host.
final class ExtHostAuthenticationProxy {
  ExtHostAuthenticationProxy(this._rpc);

  static const identifier = ExtHostContext.extHostAuthentication;

  final RpcProtocol _rpc;

  /// `$getSessions(id: string, scopes: string[] | undefined, options: IAuthenticationGetSessionsOptions): Promise<ReadonlyArray<AuthenticationSession>>`
  Future<List<Map<String, Object?>>> $getSessions(
    String id,
    List<String>? scopes,
    Map<String, Object?> options,
  ) async => decodeReply(
    r'ExtHostAuthentication.$getSessions',
    await _rpc.call(identifier.nid, r'$getSessions', [
      id,
      scopes ?? rpcUndefined,
      options,
    ]),
    decodeListOf(decodeMap),
  );

  /// `$createSession(id: string, scopes: string[], options: IAuthenticationCreateSessionOptions): Promise<AuthenticationSession>`
  Future<Map<String, Object?>> $createSession(
    String id,
    List<String> scopes,
    Map<String, Object?> options,
  ) async => decodeReply(
    r'ExtHostAuthentication.$createSession',
    await _rpc.call(identifier.nid, r'$createSession', [id, scopes, options]),
    decodeMap,
  );

  /// `$getSessionsFromChallenges(id: string, constraint: IAuthenticationConstraint, options: IAuthenticationGetSessionsOptions): Promise<ReadonlyArray<AuthenticationSession>>`
  Future<List<Map<String, Object?>>> $getSessionsFromChallenges(
    String id,
    Map<String, Object?> constraint,
    Map<String, Object?> options,
  ) async => decodeReply(
    r'ExtHostAuthentication.$getSessionsFromChallenges',
    await _rpc.call(identifier.nid, r'$getSessionsFromChallenges', [
      id,
      constraint,
      options,
    ]),
    decodeListOf(decodeMap),
  );

  /// `$createSessionFromChallenges(id: string, constraint: IAuthenticationConstraint, options: IAuthenticationCreateSessionOptions): Promise<AuthenticationSession>`
  Future<Map<String, Object?>> $createSessionFromChallenges(
    String id,
    Map<String, Object?> constraint,
    Map<String, Object?> options,
  ) async => decodeReply(
    r'ExtHostAuthentication.$createSessionFromChallenges',
    await _rpc.call(identifier.nid, r'$createSessionFromChallenges', [
      id,
      constraint,
      options,
    ]),
    decodeMap,
  );

  /// `$removeSession(id: string, sessionId: string): Promise<void>`
  Future<void> $removeSession(String id, String sessionId) =>
      _rpc.call(identifier.nid, r'$removeSession', [id, sessionId]);

  /// `$onDidChangeAuthenticationSessions(id: string, label: string, extensionIdFilter?: string[]): Promise<void>`
  Future<void> $onDidChangeAuthenticationSessions(
    String id,
    String label, [
    List<String>? extensionIdFilter,
  ]) => _rpc.call(identifier.nid, r'$onDidChangeAuthenticationSessions', [
    id,
    label,
    extensionIdFilter ?? rpcUndefined,
  ]);

  /// `$onDidUnregisterAuthenticationProvider(id: string): Promise<void>`
  Future<void> $onDidUnregisterAuthenticationProvider(String id) => _rpc.call(
    identifier.nid,
    r'$onDidUnregisterAuthenticationProvider',
    [id],
  );

  /// `$registerDynamicAuthProvider(authorizationServer: UriComponents, serverMetadata: IAuthorizationServerMetadata, resource?: IAuthorizationProtectedResourceMetadata, clientId?: string, clientSecret?: string, initialTokens?: (IAuthorizationTokenResponse & { created_at: number })[]): Promise<string>`
  Future<String> $registerDynamicAuthProvider(
    VsUri authorizationServer,
    Map<String, Object?> serverMetadata, [
    Map<String, Object?>? resource,
    String? clientId,
    String? clientSecret,
    List<Map<String, Object?>>? initialTokens,
  ]) async => decodeReply(
    r'ExtHostAuthentication.$registerDynamicAuthProvider',
    await _rpc.call(identifier.nid, r'$registerDynamicAuthProvider', [
      authorizationServer,
      serverMetadata,
      resource ?? rpcUndefined,
      clientId ?? rpcUndefined,
      clientSecret ?? rpcUndefined,
      initialTokens ?? rpcUndefined,
    ]),
    decodeString,
  );

  /// `$registerXaaAuthProvider(issuer: UriComponents, serverMetadata: IAuthorizationServerMetadata, clientId?: string, clientSecret?: string, initialTokens?: (IAuthorizationTokenResponse & { created_at: number })[]): Promise<string>`
  Future<String> $registerXaaAuthProvider(
    VsUri issuer,
    Map<String, Object?> serverMetadata, [
    String? clientId,
    String? clientSecret,
    List<Map<String, Object?>>? initialTokens,
  ]) async => decodeReply(
    r'ExtHostAuthentication.$registerXaaAuthProvider',
    await _rpc.call(identifier.nid, r'$registerXaaAuthProvider', [
      issuer,
      serverMetadata,
      clientId ?? rpcUndefined,
      clientSecret ?? rpcUndefined,
      initialTokens ?? rpcUndefined,
    ]),
    decodeString,
  );

  /// `$onDidChangeDynamicAuthProviderTokens(authProviderId: string, clientId: string, tokens?: (IAuthorizationTokenResponse & { created_at: number })[]): Promise<void>`
  Future<void> $onDidChangeDynamicAuthProviderTokens(
    String authProviderId,
    String clientId, [
    List<Map<String, Object?>>? tokens,
  ]) => _rpc.call(identifier.nid, r'$onDidChangeDynamicAuthProviderTokens', [
    authProviderId,
    clientId,
    tokens ?? rpcUndefined,
  ]);
}

/// Calls `ExtHostTimelineShape` (`ExtHostTimeline`) in the extension host.
final class ExtHostTimelineProxy {
  ExtHostTimelineProxy(this._rpc);

  static const identifier = ExtHostContext.extHostTimeline;

  final RpcProtocol _rpc;

  /// `$getTimeline(source: string, uri: UriComponents, options: TimelineOptions, token: CancellationToken): Promise<Dto<Timeline> | undefined>`
  Future<Map<String, Object?>?> $getTimeline(
    String source,
    VsUri uri,
    Map<String, Object?> options, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostTimeline.$getTimeline',
    await _rpc.call(identifier.nid, r'$getTimeline', [
      source,
      uri,
      options,
    ], token: token),
    decodeNullable(decodeMap),
  );
}

/// Calls `ExtHostTestingShape` (`ExtHostTesting`) in the extension host.
final class ExtHostTestingProxy {
  ExtHostTestingProxy(this._rpc);

  static const identifier = ExtHostContext.extHostTesting;

  final RpcProtocol _rpc;

  /// `$runControllerTests(req: IStartControllerTests[], token: CancellationToken): Promise<{ error?: string }[]>`
  Future<List<Map<String, Object?>>> $runControllerTests(
    List<Map<String, Object?>> req, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostTesting.$runControllerTests',
    await _rpc.call(identifier.nid, r'$runControllerTests', [
      req,
    ], token: token),
    decodeListOf(decodeMap),
  );

  /// `$startContinuousRun(req: ICallProfileRunHandler[], token: CancellationToken): Promise<{ error?: string }[]>`
  Future<List<Map<String, Object?>>> $startContinuousRun(
    List<Map<String, Object?>> req, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostTesting.$startContinuousRun',
    await _rpc.call(identifier.nid, r'$startContinuousRun', [
      req,
    ], token: token),
    decodeListOf(decodeMap),
  );

  /// `$cancelExtensionTestRun(runId: string | undefined, taskId: string | undefined): void`
  Future<void> $cancelExtensionTestRun(String? runId, String? taskId) =>
      _rpc.call(identifier.nid, r'$cancelExtensionTestRun', [
        runId ?? rpcUndefined,
        taskId ?? rpcUndefined,
      ]);

  /// Handles a diff of tests, as a result of a subscribeToDiffs() call
  ///
  /// `$acceptDiff(diff: TestsDiffOp.Serialized[]): void`
  Future<void> $acceptDiff(List<Map<String, Object?>> diff) =>
      _rpc.call(identifier.nid, r'$acceptDiff', [diff]);

  /// Expands a test item's children, by the given number of levels.
  ///
  /// `$expandTest(testId: string, levels: number): Promise<void>`
  Future<void> $expandTest(String testId, num levels) =>
      _rpc.call(identifier.nid, r'$expandTest', [testId, levels]);

  /// Requests coverage details for a test run. Errors if not available.
  ///
  /// `$getCoverageDetails(coverageId: string, testId: string | undefined, token: CancellationToken): Promise<CoverageDetails.Serialized[]>`
  Future<List<Map<String, Object?>>> $getCoverageDetails(
    String coverageId,
    String? testId, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostTesting.$getCoverageDetails',
    await _rpc.call(identifier.nid, r'$getCoverageDetails', [
      coverageId,
      testId ?? rpcUndefined,
    ], token: token),
    decodeListOf(decodeMap),
  );

  /// Disposes resources associated with a test run.
  ///
  /// `$disposeRun(runId: string): void`
  Future<void> $disposeRun(String runId) =>
      _rpc.call(identifier.nid, r'$disposeRun', [runId]);

  /// Configures a test run config.
  ///
  /// `$configureRunProfile(controllerId: string, configId: number): void`
  Future<void> $configureRunProfile(String controllerId, num configId) => _rpc
      .call(identifier.nid, r'$configureRunProfile', [controllerId, configId]);

  /// Asks the controller to refresh its tests
  ///
  /// `$refreshTests(controllerId: string, token: CancellationToken): Promise<void>`
  Future<void> $refreshTests(String controllerId, {CancellationToken? token}) =>
      _rpc.call(identifier.nid, r'$refreshTests', [controllerId], token: token);

  /// Ensures any pending test diffs are flushed
  ///
  /// `$syncTests(): Promise<void>`
  Future<void> $syncTests() => _rpc.call(identifier.nid, r'$syncTests', []);

  /// Sets the active test run profiles
  ///
  /// `$setDefaultRunProfiles(profiles: Record</* controller id */string, /* profile id */ number[]>): void`
  Future<void> $setDefaultRunProfiles(Map<String, List<num>> profiles) =>
      _rpc.call(identifier.nid, r'$setDefaultRunProfiles', [profiles]);

  /// `$getTestsRelatedToCode(uri: UriComponents, position: IPosition, token: CancellationToken): Promise<string[]>`
  Future<List<String>> $getTestsRelatedToCode(
    VsUri uri,
    Map<String, Object?> position, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostTesting.$getTestsRelatedToCode',
    await _rpc.call(identifier.nid, r'$getTestsRelatedToCode', [
      uri,
      position,
    ], token: token),
    decodeListOf(decodeString),
  );

  /// `$getCodeRelatedToTest(testId: string, token: CancellationToken): Promise<ILocationDto[]>`
  Future<List<Map<String, Object?>>> $getCodeRelatedToTest(
    String testId, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostTesting.$getCodeRelatedToTest',
    await _rpc.call(identifier.nid, r'$getCodeRelatedToTest', [
      testId,
    ], token: token),
    decodeListOf(decodeMap),
  );

  /// Publishes that a test run finished.
  ///
  /// `$publishTestResults(results: ISerializedTestResults[]): void`
  Future<void> $publishTestResults(List<Map<String, Object?>> results) =>
      _rpc.call(identifier.nid, r'$publishTestResults', [results]);

  /// Requests followup actions for a test (failure) message
  ///
  /// `$provideTestFollowups(req: TestMessageFollowupRequest, token: CancellationToken): Promise<TestMessageFollowupResponse[]>`
  Future<List<Map<String, Object?>>> $provideTestFollowups(
    Map<String, Object?> req, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostTesting.$provideTestFollowups',
    await _rpc.call(identifier.nid, r'$provideTestFollowups', [
      req,
    ], token: token),
    decodeListOf(decodeMap),
  );

  /// Actions a followup actions for a test (failure) message
  ///
  /// `$executeTestFollowup(id: number): Promise<void>`
  Future<void> $executeTestFollowup(num id) =>
      _rpc.call(identifier.nid, r'$executeTestFollowup', [id]);

  /// Disposes followup actions for a test (failure) message
  ///
  /// `$disposeTestFollowups(id: number[]): void`
  Future<void> $disposeTestFollowups(List<num> id) =>
      _rpc.call(identifier.nid, r'$disposeTestFollowups', [id]);
}

/// Calls `ExtHostTelemetryShape` (`ExtHostTelemetry`) in the extension host.
final class ExtHostTelemetryProxy {
  ExtHostTelemetryProxy(this._rpc);

  static const identifier = ExtHostContext.extHostTelemetry;

  final RpcProtocol _rpc;

  /// `$initializeTelemetryLevel(level: TelemetryLevel, supportsTelemetry: boolean, productConfig?: { usage: boolean; error: boolean }): void`
  Future<void> $initializeTelemetryLevel(
    int level,
    bool supportsTelemetry, [
    Map<String, Object?>? productConfig,
  ]) => _rpc.call(identifier.nid, r'$initializeTelemetryLevel', [
    level,
    supportsTelemetry,
    productConfig ?? rpcUndefined,
  ]);

  /// `$onDidChangeTelemetryLevel(level: TelemetryLevel): void`
  Future<void> $onDidChangeTelemetryLevel(int level) =>
      _rpc.call(identifier.nid, r'$onDidChangeTelemetryLevel', [level]);
}

/// Calls `ExtHostMeteredConnectionShape` (`ExtHostMeteredConnection`) in the extension host.
final class ExtHostMeteredConnectionProxy {
  ExtHostMeteredConnectionProxy(this._rpc);

  static const identifier = ExtHostContext.extHostMeteredConnection;

  final RpcProtocol _rpc;

  /// `$initializeIsConnectionMetered(isMetered: boolean): void`
  Future<void> $initializeIsConnectionMetered(bool isMetered) =>
      _rpc.call(identifier.nid, r'$initializeIsConnectionMetered', [isMetered]);

  /// `$onDidChangeIsConnectionMetered(isMetered: boolean): void`
  Future<void> $onDidChangeIsConnectionMetered(bool isMetered) => _rpc.call(
    identifier.nid,
    r'$onDidChangeIsConnectionMetered',
    [isMetered],
  );
}

/// Calls `ExtHostLocalizationShape` (`ExtHostLocalization`) in the extension host.
final class ExtHostLocalizationProxy {
  ExtHostLocalizationProxy(this._rpc);

  static const identifier = ExtHostContext.extHostLocalization;

  // ignore: unused_field
  final RpcProtocol _rpc;
}

/// Calls `ExtHostMcpShape` (`ExtHostMcp`) in the extension host.
final class ExtHostMcpProxy {
  ExtHostMcpProxy(this._rpc);

  static const identifier = ExtHostContext.extHostMcp;

  final RpcProtocol _rpc;

  /// `$substituteVariables(workspaceFolder: UriComponents | undefined, value: McpServerLaunch.Serialized): Promise<McpServerLaunch.Serialized>`
  Future<Map<String, Object?>> $substituteVariables(
    VsUri? workspaceFolder,
    Map<String, Object?> value,
  ) async => decodeReply(
    r'ExtHostMcp.$substituteVariables',
    await _rpc.call(identifier.nid, r'$substituteVariables', [
      workspaceFolder ?? rpcUndefined,
      value,
    ]),
    decodeMap,
  );

  /// `$resolveMcpLaunch(collectionId: string, label: string): Promise<McpServerLaunch.Serialized | undefined>`
  Future<Map<String, Object?>?> $resolveMcpLaunch(
    String collectionId,
    String label,
  ) async => decodeReply(
    r'ExtHostMcp.$resolveMcpLaunch',
    await _rpc.call(identifier.nid, r'$resolveMcpLaunch', [
      collectionId,
      label,
    ]),
    decodeNullable(decodeMap),
  );

  /// `$startMcp(id: number, opts: IStartMcpOptions): void`
  Future<void> $startMcp(num id, Map<String, Object?> opts) =>
      _rpc.call(identifier.nid, r'$startMcp', [id, opts]);

  /// `$stopMcp(id: number): void`
  Future<void> $stopMcp(num id) => _rpc.call(identifier.nid, r'$stopMcp', [id]);

  /// `$sendMessage(id: number, message: string): void`
  Future<void> $sendMessage(num id, String message) =>
      _rpc.call(identifier.nid, r'$sendMessage', [id, message]);

  /// `$waitForInitialCollectionProviders(): Promise<void>`
  Future<void> $waitForInitialCollectionProviders() =>
      _rpc.call(identifier.nid, r'$waitForInitialCollectionProviders', []);

  /// `$onDidChangeMcpServerDefinitions(servers: McpServerDefinition.Serialized[]): void`
  Future<void> $onDidChangeMcpServerDefinitions(
    List<Map<String, Object?>> servers,
  ) =>
      _rpc.call(identifier.nid, r'$onDidChangeMcpServerDefinitions', [servers]);

  /// `$onDidChangeGatewayServers(gatewayId: string, servers: { label: string; address: UriComponents }[]): void`
  Future<void> $onDidChangeGatewayServers(
    String gatewayId,
    List<Map<String, Object?>> servers,
  ) => _rpc.call(identifier.nid, r'$onDidChangeGatewayServers', [
    gatewayId,
    servers,
  ]);
}

/// Calls `ExtHostDataChannelsShape` (`ExtHostDataChannels`) in the extension host.
final class ExtHostDataChannelsProxy {
  ExtHostDataChannelsProxy(this._rpc);

  static const identifier = ExtHostContext.extHostDataChannels;

  final RpcProtocol _rpc;

  /// `$onDidReceiveData(channelId: string, data: unknown): void`
  Future<void> $onDidReceiveData(String channelId, Object? data) =>
      _rpc.call(identifier.nid, r'$onDidReceiveData', [channelId, data]);

  /// `$acceptLinkPresentationRules(rules: readonly { id: string; source: string; flags: string; initialKind: LinkPresentationKind }[]): void`
  Future<void> $acceptLinkPresentationRules(List<Map<String, Object?>> rules) =>
      _rpc.call(identifier.nid, r'$acceptLinkPresentationRules', [rules]);

  /// `$acceptLinkPresentation(handle: number, data: unknown): void`
  Future<void> $acceptLinkPresentation(num handle, Object? data) =>
      _rpc.call(identifier.nid, r'$acceptLinkPresentation', [handle, data]);

  /// `$createLinkPresentationWatcher(handle: number, providerHandle: number, resource: UriComponents): Promise<unknown>`
  Future<Object?> $createLinkPresentationWatcher(
    num handle,
    num providerHandle,
    VsUri resource,
  ) => _rpc.call(identifier.nid, r'$createLinkPresentationWatcher', [
    handle,
    providerHandle,
    resource,
  ]);

  /// `$disposeLinkPresentationWatcher(handle: number): void`
  Future<void> $disposeLinkPresentationWatcher(num handle) =>
      _rpc.call(identifier.nid, r'$disposeLinkPresentationWatcher', [handle]);
}

/// Calls `ExtHostChatSessionsShape` (`ExtHostChatSessions`) in the extension host.
final class ExtHostChatSessionsProxy {
  ExtHostChatSessionsProxy(this._rpc);

  static const identifier = ExtHostContext.extHostChatSessions;

  final RpcProtocol _rpc;

  /// `$refreshChatSessionItems(providerHandle: number, token: CancellationToken): Promise<void>`
  Future<void> $refreshChatSessionItems(
    num providerHandle, {
    CancellationToken? token,
  }) => _rpc.call(identifier.nid, r'$refreshChatSessionItems', [
    providerHandle,
  ], token: token);

  /// `$onDidChangeChatSessionItemState(providerHandle: number, sessionResource: UriComponents, archived: boolean): void`
  Future<void> $onDidChangeChatSessionItemState(
    num providerHandle,
    VsUri sessionResource,
    bool archived,
  ) => _rpc.call(identifier.nid, r'$onDidChangeChatSessionItemState', [
    providerHandle,
    sessionResource,
    archived,
  ]);

  /// `$newChatSessionItem(controllerHandle: number, request: IChatNewSessionRequestDto, token: CancellationToken): Promise<Dto<IChatSessionItem> | undefined>`
  Future<Map<String, Object?>?> $newChatSessionItem(
    num controllerHandle,
    Map<String, Object?> request, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostChatSessions.$newChatSessionItem',
    await _rpc.call(identifier.nid, r'$newChatSessionItem', [
      controllerHandle,
      request,
    ], token: token),
    decodeNullable(decodeMap),
  );

  /// `$provideChatSessionContent(providerHandle: number, sessionResource: UriComponents, context: ChatSessionContentContextDto, token: CancellationToken): Promise<IChatSessionDto>`
  Future<Map<String, Object?>> $provideChatSessionContent(
    num providerHandle,
    VsUri sessionResource,
    Map<String, Object?> context, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostChatSessions.$provideChatSessionContent',
    await _rpc.call(identifier.nid, r'$provideChatSessionContent', [
      providerHandle,
      sessionResource,
      context,
    ], token: token),
    decodeMap,
  );

  /// `$interruptChatSessionActiveResponse(providerHandle: number, sessionResource: UriComponents, requestId: string): Promise<void>`
  Future<void> $interruptChatSessionActiveResponse(
    num providerHandle,
    VsUri sessionResource,
    String requestId,
  ) => _rpc.call(identifier.nid, r'$interruptChatSessionActiveResponse', [
    providerHandle,
    sessionResource,
    requestId,
  ]);

  /// `$disposeChatSessionContent(providerHandle: number, sessionResource: UriComponents): Promise<void>`
  Future<void> $disposeChatSessionContent(
    num providerHandle,
    VsUri sessionResource,
  ) => _rpc.call(identifier.nid, r'$disposeChatSessionContent', [
    providerHandle,
    sessionResource,
  ]);

  /// `$invokeChatSessionRequestHandler(providerHandle: number, sessionResource: UriComponents, request: IChatAgentRequest, history: any[], token: CancellationToken): Promise<IChatAgentResult>`
  Future<Map<String, Object?>> $invokeChatSessionRequestHandler(
    num providerHandle,
    VsUri sessionResource,
    Map<String, Object?> request,
    List<Object?> history, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostChatSessions.$invokeChatSessionRequestHandler',
    await _rpc.call(identifier.nid, r'$invokeChatSessionRequestHandler', [
      providerHandle,
      sessionResource,
      request,
      history,
    ], token: token),
    decodeMap,
  );

  /// `$provideChatSessionProviderOptions(providerHandle: number, token: CancellationToken): Promise<IChatSessionProviderOptions | undefined>`
  Future<Map<String, Object?>?> $provideChatSessionProviderOptions(
    num providerHandle, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostChatSessions.$provideChatSessionProviderOptions',
    await _rpc.call(identifier.nid, r'$provideChatSessionProviderOptions', [
      providerHandle,
    ], token: token),
    decodeNullable(decodeMap),
  );

  /// `$provideHandleOptionsChange(providerHandle: number, sessionResource: UriComponents, updates: Record<string, string | IChatSessionProviderOptionItem | undefined>, token: CancellationToken): Promise<void>`
  Future<void> $provideHandleOptionsChange(
    num providerHandle,
    VsUri sessionResource,
    Map<String, Object?> updates, {
    CancellationToken? token,
  }) => _rpc.call(identifier.nid, r'$provideHandleOptionsChange', [
    providerHandle,
    sessionResource,
    updates,
  ], token: token);

  /// `$forkChatSession(providerHandle: number, sessionResource: UriComponents, request: IChatSessionRequestHistoryItemDto | undefined, token: CancellationToken): Promise<Dto<IChatSessionItem>>`
  Future<Map<String, Object?>> $forkChatSession(
    num providerHandle,
    VsUri sessionResource,
    Map<String, Object?>? request, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostChatSessions.$forkChatSession',
    await _rpc.call(identifier.nid, r'$forkChatSession', [
      providerHandle,
      sessionResource,
      request ?? rpcUndefined,
    ], token: token),
    decodeMap,
  );

  /// `$resolveChatSessionItem(providerHandle: number, sessionResource: UriComponents, token: CancellationToken): Promise<Dto<IChatSessionItem> | undefined>`
  Future<Map<String, Object?>?> $resolveChatSessionItem(
    num providerHandle,
    VsUri sessionResource, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostChatSessions.$resolveChatSessionItem',
    await _rpc.call(identifier.nid, r'$resolveChatSessionItem', [
      providerHandle,
      sessionResource,
    ], token: token),
    decodeNullable(decodeMap),
  );

  /// `$provideChatSessionInputState(controllerHandle: number, sessionResource: UriComponents | undefined, token: CancellationToken): Promise<IChatSessionProviderOptionGroup[] | undefined>`
  Future<List<Map<String, Object?>>?> $provideChatSessionInputState(
    num controllerHandle,
    VsUri? sessionResource, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostChatSessions.$provideChatSessionInputState',
    await _rpc.call(identifier.nid, r'$provideChatSessionInputState', [
      controllerHandle,
      sessionResource ?? rpcUndefined,
    ], token: token),
    decodeNullable(decodeListOf(decodeMap)),
  );
}

/// Calls `ExtHostChatQuotaShape` (`ExtHostChatQuota`) in the extension host.
final class ExtHostChatQuotaProxy {
  ExtHostChatQuotaProxy(this._rpc);

  static const identifier = ExtHostContext.extHostChatQuota;

  // ignore: unused_field
  final RpcProtocol _rpc;
}

/// Calls `ExtHostGitExtensionShape` (`ExtHostGitExtension`) in the extension host.
final class ExtHostGitExtensionProxy {
  ExtHostGitExtensionProxy(this._rpc);

  static const identifier = ExtHostContext.extHostGitExtension;

  final RpcProtocol _rpc;

  /// `$isGitExtensionAvailable(): Promise<boolean>`
  Future<bool> $isGitExtensionAvailable() async => decodeReply(
    r'ExtHostGitExtension.$isGitExtensionAvailable',
    await _rpc.call(identifier.nid, r'$isGitExtensionAvailable', []),
    decodeBool,
  );

  /// `$openRepository(root: UriComponents): Promise<{ handle: number; rootUri: UriComponents; state: GitRepositoryStateDto } | undefined>`
  Future<Map<String, Object?>?> $openRepository(VsUri root) async =>
      decodeReply(
        r'ExtHostGitExtension.$openRepository',
        await _rpc.call(identifier.nid, r'$openRepository', [root]),
        decodeNullable(decodeMap),
      );

  /// `$getRefs(handle: number, query: GitRefQueryDto, token?: CancellationToken): Promise<GitRefDto[]>`
  Future<List<Map<String, Object?>>> $getRefs(
    num handle,
    Map<String, Object?> query, {
    CancellationToken? token,
  }) async => decodeReply(
    r'ExtHostGitExtension.$getRefs',
    await _rpc.call(identifier.nid, r'$getRefs', [handle, query], token: token),
    decodeListOf(decodeMap),
  );

  /// `$getRepositoryState(handle: number): Promise<GitRepositoryStateDto | undefined>`
  Future<Map<String, Object?>?> $getRepositoryState(num handle) async =>
      decodeReply(
        r'ExtHostGitExtension.$getRepositoryState',
        await _rpc.call(identifier.nid, r'$getRepositoryState', [handle]),
        decodeNullable(decodeMap),
      );

  /// `$diffBetweenWithStats(handle: number, ref1: string, ref2: string, path?: string): Promise<GitDiffChangeDto[]>`
  Future<List<Map<String, Object?>>> $diffBetweenWithStats(
    num handle,
    String ref1,
    String ref2, [
    String? path,
  ]) async => decodeReply(
    r'ExtHostGitExtension.$diffBetweenWithStats',
    await _rpc.call(identifier.nid, r'$diffBetweenWithStats', [
      handle,
      ref1,
      ref2,
      path ?? rpcUndefined,
    ]),
    decodeListOf(decodeMap),
  );

  /// `$diffBetweenWithStats2(handle: number, ref: string, path?: string): Promise<GitDiffChangeDto[]>`
  Future<List<Map<String, Object?>>> $diffBetweenWithStats2(
    num handle,
    String ref, [
    String? path,
  ]) async => decodeReply(
    r'ExtHostGitExtension.$diffBetweenWithStats2',
    await _rpc.call(identifier.nid, r'$diffBetweenWithStats2', [
      handle,
      ref,
      path ?? rpcUndefined,
    ]),
    decodeListOf(decodeMap),
  );
}

/// Calls `ExtHostBrowsersShape` (`ExtHostBrowsers`) in the extension host.
final class ExtHostBrowsersProxy {
  ExtHostBrowsersProxy(this._rpc);

  static const identifier = ExtHostContext.extHostBrowsers;

  final RpcProtocol _rpc;

  /// `$onDidOpenBrowserTab(browser: BrowserTabDto): void`
  Future<void> $onDidOpenBrowserTab(Map<String, Object?> browser) =>
      _rpc.call(identifier.nid, r'$onDidOpenBrowserTab', [browser]);

  /// `$onDidCloseBrowserTab(browserId: string): void`
  Future<void> $onDidCloseBrowserTab(String browserId) =>
      _rpc.call(identifier.nid, r'$onDidCloseBrowserTab', [browserId]);

  /// `$onDidChangeActiveBrowserTab(browserId: string | undefined): void`
  Future<void> $onDidChangeActiveBrowserTab(String? browserId) => _rpc.call(
    identifier.nid,
    r'$onDidChangeActiveBrowserTab',
    [browserId ?? rpcUndefined],
  );

  /// `$onDidChangeBrowserTabState(browser: BrowserTabDto): void`
  Future<void> $onDidChangeBrowserTabState(Map<String, Object?> browser) =>
      _rpc.call(identifier.nid, r'$onDidChangeBrowserTabState', [browser]);

  /// `$onCDPSessionMessage(sessionId: string, message: CDPResponse | CDPEvent): void`
  Future<void> $onCDPSessionMessage(
    String sessionId,
    Map<String, Object?> message,
  ) => _rpc.call(identifier.nid, r'$onCDPSessionMessage', [sessionId, message]);

  /// `$onCDPSessionClosed(sessionId: string): void`
  Future<void> $onCDPSessionClosed(String sessionId) =>
      _rpc.call(identifier.nid, r'$onCDPSessionClosed', [sessionId]);
}
