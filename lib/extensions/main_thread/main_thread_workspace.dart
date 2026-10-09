/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadWorkspace.ts,
// src/vs/workbench/services/extensions/common/workspaceContains.ts
// (`checkGlobFileExists`).
//
// Deviations:
// - `$initializeWorkspace` is sent by ExtensionHostService.
// - Edit session identity and canonical URI providers are registered
//   here ([MainThreadWorkspace.getEditSessionIdentifier],
//   [MainThreadWorkspace.provideCanonicalUri]); the app has no edit
//   sessions to use them.
// - Proxy, credentials and certificates come from [NetworkService]
//   (see network_service_io.dart); without one there are none.

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart';

import '../configuration/configuration_service.dart';
import '../search/query_builder.dart';
import '../search/search_service.dart';
import '../trust/workspace_trust.dart';
import '../workspace/encoding_oracle.dart';
import '../workspace/network_service_io.dart';
import '../workspace/workspace_context.dart';
import '../workspace/workspace_save.dart';
import 'main_thread_context.dart';

final class MainThreadWorkspace extends MainThreadWorkspaceUnsupported {
  MainThreadWorkspace({
    required RpcProtocol rpc,
    required this.workspace,
    required this.search,
    required this.queryBuilder,
    required this.encodings,
    this.trust,
    this.save,
    this.network,
  }) : _proxy = ExtHostWorkspaceProxy(rpc) {
    workspace.addListener(_onDidChangeWorkspace);
    _trustChanges = trust?.onDidChangeTrust.listen((trusted) {
      if (trusted) _send(_proxy.$onDidGrantWorkspaceTrust());
    });
    _foldersChanges = trust?.onDidChangeTrustedFolders.listen(
      (_) => _send(_proxy.$onDidChangeWorkspaceTrustedFolders()),
    );
  }

  static RpcActor customer(MainThreadContext c) {
    final configuration = c.service<ConfigurationService>();
    final workspace = c.service<WorkspaceContextService>();
    final actor = MainThreadWorkspace(
      rpc: c.rpc,
      workspace: workspace,
      search: c.service<SearchService>(),
      queryBuilder:
          c.maybeService<QueryBuilder>() ??
          QueryBuilder(configuration: configuration, workspace: workspace),
      encodings:
          c.maybeService<EncodingOracle>() ??
          EncodingOracle(configuration: configuration, workspace: workspace),
      trust: c.maybeService<WorkspaceTrustService>(),
      save: c.maybeService<WorkspaceSavePort>(),
      network: c.maybeService<NetworkService>(),
    );
    c.onDispose(actor.dispose);
    return MainThreadWorkspaceActor(actor);
  }

  final ExtHostWorkspaceProxy _proxy;
  final WorkspaceContextService workspace;
  final SearchService search;
  final QueryBuilder queryBuilder;
  final EncodingOracle encodings;
  final WorkspaceTrustService? trust;
  final WorkspaceSavePort? save;
  final NetworkService? network;

  StreamSubscription<void>? _trustChanges;
  StreamSubscription<void>? _foldersChanges;
  bool _disposed = false;

  static void _send(Future<void> call) =>
      unawaited(call.catchError((Object _) {}));

  void dispose() {
    _disposed = true;
    workspace.removeListener(_onDidChangeWorkspace);
    unawaited(_trustChanges?.cancel());
    unawaited(_foldersChanges?.cancel());
  }

  // --- workspace

  void _onDidChangeWorkspace() {
    if (_disposed) return;
    _send(_proxy.$acceptWorkspaceData(workspace.toWorkspaceData()));
  }

  @override
  Future<void> $updateWorkspaceFolders(
    String extensionName,
    num index,
    num deleteCount,
    List<Map<String, Object?>> workspaceFoldersToAdd,
  ) async {
    final add = [
      for (final f in workspaceFoldersToAdd)
        (uri: VsUri.revive((f['uri']! as Map).cast()), name: f['name'] as String?),
    ];
    workspace.folders?.showStatus(extensionName, add.length, deleteCount.toInt());
    await workspace.updateFolders(index.toInt(), deleteCount.toInt(), add);
  }

  // --- search

  List<VsUri> get _folderUris => [
    for (final f in workspace.workspaceFolders) f.uri,
  ];

  @override
  Future<List<VsUri>?> $startFileSearch(
    VsUri? includeFolder,
    Map<String, Object?> options,
    CancellationToken token,
  ) async {
    final query = queryBuilder.file(
      includeFolder != null ? [includeFolder] : _folderUris,
      options,
    );
    try {
      final result = await search.fileSearch(query, token);
      return [
        for (final m in result.results) ?VsUri.tryRevive(m['resource']),
      ];
    } on CancellationException {
      return null;
    }
  }

  @override
  Future<Map<String, Object?>?> $startTextSearch(
    Map<String, Object?> query,
    VsUri? folder,
    Map<String, Object?> options,
    num requestId,
    CancellationToken token,
  ) async {
    final textQuery = queryBuilder.text(
      query,
      folder != null ? [folder] : _folderUris,
      options,
    )..['_reason'] = 'startTextSearch';
    try {
      final result = await search.textSearch(textQuery, token, (match) {
        if (match['results'] != null) {
          _send(_proxy.$handleTextSearchResult(match, requestId));
        }
      });
      return {'limitHit': result.limitHit};
    } on CancellationException {
      return null;
    }
  }

  @override
  Future<bool> $checkExists(
    List<VsUri> folders,
    List<String> includes,
    CancellationToken token,
  ) async {
    final query = queryBuilder.file(folders, {
      '_reason': 'checkExists',
      'includePattern': includes,
      'exists': true,
    });
    try {
      return (await search.fileSearch(query, token)).limitHit;
    } on CancellationException {
      return false;
    }
  }

  // --- save

  @override
  Future<VsUri?> $save(VsUri uri, Map<String, Object?> options) async =>
      save?.save(uri, saveAs: options['saveAs'] == true);

  @override
  Future<bool> $saveAll(bool? includeUntitled) async =>
      await save?.saveAll(includeUntitled: includeUntitled ?? false) ?? false;

  // --- network

  @override
  Future<String?> $resolveProxy(String url) async =>
      network?.resolveProxy(url);

  @override
  Future<Map<String, Object?>?> $lookupAuthorization(
    Map<String, Object?> authInfo,
  ) async => network?.lookupAuthorization(authInfo);

  @override
  Future<String?> $lookupKerberosAuthorization(String url) async => null;

  @override
  Future<List<String>> $loadCertificates() async =>
      await network?.loadCertificates() ?? const [];

  // --- trust

  @override
  Future<bool?> $requestResourceTrust(Map<String, Object?> options) async {
    final uri = VsUri.revive((options['uri']! as Map).cast());
    final t = trust;
    if (t == null) return true;
    return t.requestResourcesTrust(uri, message: options['message'] as String?);
  }

  @override
  Future<bool?> $requestWorkspaceTrust(Map<String, Object?>? options) async {
    final t = trust;
    if (t == null) return true;
    final buttons = options?['buttons'];
    return t.requestWorkspaceTrust(
      message: options?['message'] as String?,
      buttons: buttons is List
          ? [
              for (final b in buttons)
                if (b is Map) (label: '${b['label']}', type: '${b['type']}'),
            ]
          : null,
    );
  }

  @override
  Future<bool> $isResourceTrusted(VsUri resource) async =>
      trust?.getUriTrustInfo(resource).trusted ?? true;

  // --- edit sessions and canonical URIs

  /// Edit session identity providers, by handle: their schemes.
  final editSessionProviders = <int, String>{};

  /// Canonical URI providers, by handle: their schemes.
  final canonicalUriProviders = <int, String>{};

  @override
  void $registerEditSessionIdentityProvider(num handle, String scheme) =>
      editSessionProviders[handle.toInt()] = scheme;

  @override
  void $unregisterEditSessionIdentityProvider(num handle) =>
      editSessionProviders.remove(handle.toInt());

  @override
  void $registerCanonicalUriProvider(num handle, String scheme) =>
      canonicalUriProviders[handle.toInt()] = scheme;

  @override
  void $unregisterCanonicalUriProvider(num handle) =>
      canonicalUriProviders.remove(handle.toInt());

  /// `IEditSessionIdentityService.getEditSessionIdentifier` for [folder]'s
  /// scheme: null when no extension provides one.
  Future<String?> getEditSessionIdentifier(
    VsUri folder, [
    CancellationToken? token,
  ]) async {
    if (!editSessionProviders.containsValue(folder.scheme)) return null;
    return _proxy.$getEditSessionIdentifier(folder, token: token);
  }

  /// `ICanonicalUriService.provideCanonicalUri`.
  Future<VsUri?> provideCanonicalUri(
    VsUri uri,
    String targetScheme, [
    CancellationToken? token,
  ]) async {
    if (!canonicalUriProviders.containsValue(uri.scheme)) return null;
    return _proxy.$provideCanonicalUri(uri, targetScheme, token: token);
  }

  // --- encodings

  @override
  Future<Map<String, Object?>> $resolveDecoding(
    VsUri? resource,
    Map<String, Object?>? options,
  ) async => encodings.resolveDecoding(resource, options);

  @override
  Future<String> $validateDetectedEncoding(
    VsUri? resource,
    String detectedEncoding,
    Map<String, Object?>? options,
  ) async => encodings.validateDetectedEncoding(resource, detectedEncoding, options);

  @override
  Future<Map<String, Object?>> $resolveEncoding(
    VsUri? resource,
    Map<String, Object?>? options,
  ) async => encodings.resolveEncoding(resource, options);
}
