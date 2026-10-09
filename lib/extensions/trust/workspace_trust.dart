/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Workspace trust: the folders the user trusts (kept for every window in
// the data folder), whether a workspace is trusted (all its folders are),
// the startup prompt, extensions' trust requests, and which extensions an
// untrusted workspace (Restricted Mode) runs.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/services/workspaces/common/workspaceTrust.ts
// (`WorkspaceTrustEnablementService`, `WorkspaceTrustManagementService`:
// `calculateWorkspaceTrust`, `doGetUriTrustInfo`, `getUrisTrust`,
// `setUrisTrust`, `setWorkspaceTrust`, `canSetParentFolderTrust`,
// `setParentFolderTrust`, the `content.trust.model.key` storage;
// `WorkspaceTrustRequestService`: `requestWorkspaceTrust`,
// `requestResourcesTrust`, `completeWorkspaceTrustRequest`,
// `cancelWorkspaceTrustRequest`), src/vs/workbench/contrib/workspace/
// browser/workspace.contribution.ts (`WorkspaceTrustRequestHandler`'s
// dialogs' outcomes, `showModalOnStart`), src/vs/workbench/services/
// extensions/common/extensionManifestPropertiesService.ts
// (`getExtensionUntrustedWorkspaceSupportType`).
//
// Deviations:
// - The trusted folders are kept in a JSON file of the app's data folder
//   ([WorkspaceTrustStore]) rather than the application storage database;
//   it is the same `{uriTrustInfo: [{uri, trusted}]}` object.
// - No Workspace Trust editor: "Manage" is offered only when the app
//   gives [WorkspaceTrustPrompt.canManage].
// - An empty window's trust is `security.workspace.trust.emptyWindow`
//   (no memento of a choice for it).

import 'dart:async';
import 'dart:convert';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:flutter/foundation.dart';

import '../files/file_service.dart' show uriDirname, uriBasename, uriIsEqualOrParent, uriEqual;

/// Reads and writes the trust storage's JSON (none yet: null).
abstract interface class WorkspaceTrustStorage {
  Future<String?> read();
  Future<void> write(String contents);
}

/// The trusted folders of every window (`IWorkspaceTrustInfo`) and the
/// workspaces already asked at startup.
final class WorkspaceTrustStore extends ChangeNotifier {
  WorkspaceTrustStore(this._storage, {this.ignorePathCase = false});

  final WorkspaceTrustStorage _storage;

  /// Paths compare without case (macOS, Windows disks).
  final bool ignorePathCase;

  final List<({VsUri uri, bool trusted})> _uriTrustInfo = [];
  final Set<String> _promptShown = {};
  Future<void>? _loaded;

  /// Loads the storage once.
  Future<void> load() => _loaded ??= () async {
    try {
      final text = await _storage.read();
      if (text == null || text.trim().isEmpty) return;
      final json = jsonDecode(text);
      if (json is! Map) return;
      for (final info in (json['uriTrustInfo'] as List?) ?? const []) {
        if (info is! Map || info['trusted'] != true) continue;
        final uri = VsUri.tryRevive(info['uri']);
        if (uri != null) _uriTrustInfo.add((uri: uri, trusted: true));
      }
      for (final id in (json['startupPromptShown'] as List?) ?? const []) {
        _promptShown.add('$id');
      }
    } on Object {
      // A broken file trusts nothing.
    }
  }();

  Future<void> _save() => _storage.write(
    const JsonEncoder.withIndent('  ').convert({
      'uriTrustInfo': [
        for (final info in _uriTrustInfo)
          {'uri': info.uri.toJson(), 'trusted': info.trusted},
      ],
      'startupPromptShown': _promptShown.toList(),
    }),
  );

  /// The trusted folders.
  List<VsUri> get trustedUris => [for (final i in _uriTrustInfo) i.uri];

  /// `doGetUriTrustInfo` without the enablement: the innermost trusted
  /// folder holding [uri].
  ({bool trusted, VsUri uri}) getUriTrustInfo(VsUri uri) {
    var result = (trusted: false, uri: uri);
    var maxLength = -1;
    for (final info in _uriTrustInfo) {
      if (uriIsEqualOrParent(uri, info.uri, ignoreCase: ignorePathCase)) {
        final length = info.uri.fsPath().length;
        if (length > maxLength) {
          maxLength = length;
          result = (trusted: info.trusted, uri: info.uri);
        }
      }
    }
    return result;
  }

  /// `setUrisTrust` / `doSetUrisTrust`.
  Future<void> setUrisTrust(List<VsUri> uris, bool trusted) async {
    var changed = false;
    for (final uri in uris) {
      if (trusted) {
        if (!_uriTrustInfo.any((i) => uriEqual(i.uri, uri, ignoreCase: ignorePathCase))) {
          _uriTrustInfo.add((uri: uri, trusted: true));
          changed = true;
        }
      } else {
        final before = _uriTrustInfo.length;
        _uriTrustInfo.removeWhere(
          (i) => uriEqual(i.uri, uri, ignoreCase: ignorePathCase),
        );
        changed |= before != _uriTrustInfo.length;
      }
    }
    if (!changed) return;
    notifyListeners();
    await _save();
  }

  /// `setTrustedUris`: replaces the trusted folders.
  Future<void> setTrustedUris(List<VsUri> uris) async {
    _uriTrustInfo
      ..clear()
      ..addAll([for (final u in uris) (uri: u, trusted: true)]);
    notifyListeners();
    await _save();
  }

  bool promptShown(String workspaceId) => _promptShown.contains(workspaceId);

  Future<void> markPromptShown(String workspaceId) async {
    if (_promptShown.add(workspaceId)) await _save();
  }
}

/// A button of an extension's trust request (`WorkspaceTrustRequestButton`).
typedef WorkspaceTrustRequestButton = ({String label, String type});

/// The dialogs trust needs (`dialogService.prompt`s of
/// workspace.contribution.ts).
abstract interface class WorkspaceTrustPrompt {
  /// The startup question: whether to trust (and, with [parentFolderName],
  /// whether its checkbox was checked); dismissing answers no.
  Future<({bool trust, bool trustParent})> startup({
    required bool workspace,
    required String label,
    String? parentFolderName,
  });

  /// An extension's request: the type of the button chosen (null: cancel).
  Future<String?> request({
    required bool workspace,
    String? message,
    required List<WorkspaceTrustRequestButton> buttons,
  });

  /// A request to trust [uri]: whether to trust it.
  Future<bool> resource(VsUri uri, {String? message});

  /// Whether "Manage" can be offered ([manage] then opens it).
  bool get canManage;
  void manage();
}

/// `IWorkspaceTrustManagementService` and `IWorkspaceTrustRequestService`
/// of one workspace.
final class WorkspaceTrustService extends ChangeNotifier {
  WorkspaceTrustService({
    required this.store,
    required this._workspaceUris,
    required this.workspaceId,
    this.isMultiRoot = false,
    this.isEmptyWindow = false,
    Object? Function(String key)? setting,
    this.prompt,
  }) : _setting = setting ?? ((_) => null) {
    store.addListener(_storeChanged);
  }

  final WorkspaceTrustStore store;
  final List<VsUri> Function() _workspaceUris;
  final Object? Function(String key) _setting;

  /// The workspace's id (for the startup prompt's "once").
  final String workspaceId;
  final bool isMultiRoot;
  final bool isEmptyWindow;
  WorkspaceTrustPrompt? prompt;

  bool? _trusted;
  final _trustChanges = StreamController<bool>.broadcast(sync: true);
  final _foldersChanges = StreamController<void>.broadcast(sync: true);

  /// `onDidChangeTrust`.
  Stream<bool> get onDidChangeTrust => _trustChanges.stream;

  /// `onDidChangeTrustedFolders`.
  Stream<void> get onDidChangeTrustedFolders => _foldersChanges.stream;

  /// `security.workspace.trust.enabled`.
  bool get isWorkspaceTrustEnabled =>
      _setting('security.workspace.trust.enabled') != false;

  /// Loads the trusted folders; trust is known after.
  Future<void> initialize() async {
    await store.load();
    _trusted = _calculate();
  }

  /// `isWorkspaceTrusted` (false until [initialize]d, unless disabled).
  bool get isWorkspaceTrusted => _trusted ?? !isWorkspaceTrustEnabled;

  bool _calculate() {
    if (!isWorkspaceTrustEnabled) return true;
    if (isEmptyWindow) {
      return _setting('security.workspace.trust.emptyWindow') != false;
    }
    return getUrisTrust(_workspaceUris());
  }

  /// `getUrisTrust`: all of [uris] trusted.
  bool getUrisTrust(List<VsUri> uris) =>
      uris.every((uri) => getUriTrustInfo(uri).trusted);

  /// `getUriTrustInfo`.
  ({bool trusted, VsUri uri}) getUriTrustInfo(VsUri uri) {
    if (!isWorkspaceTrustEnabled) return (trusted: true, uri: uri);
    return store.getUriTrustInfo(uri);
  }

  /// Recomputes trust (after the workspace's folders changed).
  void update() => _storeChanged();

  void _storeChanged() {
    if (_trusted == null) return;
    _foldersChanges.add(null);
    final next = _calculate();
    if (next == _trusted) return;
    _trusted = next;
    _trustChanges.add(next);
    notifyListeners();
  }

  /// `canSetWorkspaceTrust`.
  bool get canSetWorkspaceTrust =>
      isWorkspaceTrustEnabled && !isEmptyWindow && _workspaceUris().isNotEmpty;

  /// `setWorkspaceTrust`: trusts (or not) the workspace's folders.
  Future<void> setWorkspaceTrust(bool trusted) async {
    if (!canSetWorkspaceTrust) return;
    await store.setUrisTrust(_workspaceUris(), trusted);
  }

  /// `canSetParentFolderTrust`: a single folder whose parent is not the
  /// root.
  bool get canSetParentFolderTrust {
    if (!canSetWorkspaceTrust || isMultiRoot) return false;
    final uris = _workspaceUris();
    if (uris.length != 1) return false;
    final parent = uriDirname(uris.single);
    return parent != uris.single;
  }

  /// The parent folder's name, for the startup checkbox.
  String? get parentFolderName =>
      canSetParentFolderTrust ? uriBasename(uriDirname(_workspaceUris().single)) : null;

  /// `setParentFolderTrust`.
  Future<void> setParentFolderTrust(bool trusted) async {
    if (!canSetParentFolderTrust) return;
    await store.setUrisTrust([uriDirname(_workspaceUris().single)], trusted);
  }

  // --- requests

  Completer<bool?>? _request;

  /// `requestWorkspaceTrust`: true when trusted; a dialog otherwise, one
  /// at a time.
  Future<bool?> requestWorkspaceTrust({
    String? message,
    List<WorkspaceTrustRequestButton>? buttons,
  }) async {
    if (isWorkspaceTrusted) return true;
    final pending = _request;
    if (pending != null) return pending.future;
    final request = _request = Completer<bool?>();
    unawaited(_showRequest(message, buttons));
    return request.future;
  }

  Future<void> _showRequest(
    String? message,
    List<WorkspaceTrustRequestButton>? given,
  ) async {
    final p = prompt;
    if (p == null) {
      _complete(null);
      return;
    }
    final buttons = <WorkspaceTrustRequestButton>[
      ...given ??
          [
            (label: '', type: 'ContinueWithTrust'),
            if (p.canManage) (label: '', type: 'Manage'),
          ],
    ];
    if (!buttons.any((b) => b.type == 'Cancel')) {
      buttons.add((label: '', type: 'Cancel'));
    }
    String? chosen;
    try {
      chosen = await p.request(
        workspace: isMultiRoot,
        message: message,
        buttons: buttons,
      );
    } on Object {
      chosen = null;
    }
    switch (chosen) {
      case 'ContinueWithTrust':
        await setWorkspaceTrust(true);
        _complete(true);
      case 'ContinueWithoutTrust':
        _complete(isWorkspaceTrusted);
      case 'Manage':
        _complete(null);
        p.manage();
      default:
        _complete(null);
    }
  }

  void _complete(bool? trusted) {
    final request = _request;
    _request = null;
    request?.complete(trusted);
  }

  final _resourceRequests = <String, Future<bool?>>{};

  /// `requestResourcesTrust`: true when [uri] is trusted; asks otherwise.
  Future<bool?> requestResourcesTrust(VsUri uri, {String? message}) {
    if (getUriTrustInfo(uri).trusted) return Future.value(true);
    final key = uri.toString();
    return _resourceRequests[key] ??= () async {
      try {
        final p = prompt;
        if (p == null) return null;
        final trust = await p.resource(uri, message: message);
        if (!trust) return null;
        await store.setUrisTrust([uri], true);
        return true;
      } finally {
        _resourceRequests.remove(key);
      }
    }();
  }

  /// `showModalOnStart`: asks once (`security.workspace.trust.
  /// startupPrompt`) when the workspace is not trusted. Completes when
  /// answered.
  Future<void> showStartupPromptIfNeeded({required String label}) async {
    if (isWorkspaceTrusted || !canSetWorkspaceTrust) return;
    final setting = _setting('security.workspace.trust.startupPrompt') ?? 'once';
    if (setting == 'never') return;
    if (setting == 'once' && store.promptShown(workspaceId)) return;
    final p = prompt;
    if (p == null) return;
    final answer = await p.startup(
      workspace: isMultiRoot,
      label: label,
      parentFolderName: parentFolderName,
    );
    if (answer.trust) {
      if (answer.trustParent) {
        await setParentFolderTrust(true);
      } else {
        await setWorkspaceTrust(true);
      }
    }
    await store.markPromptShown(workspaceId);
  }

  @override
  void dispose() {
    store.removeListener(_storeChanged);
    _complete(null);
    unawaited(_trustChanges.close());
    unawaited(_foldersChanges.close());
    super.dispose();
  }
}

/// `getExtensionUntrustedWorkspaceSupportType`: whether [manifest]'s
/// extension runs in Restricted Mode: true, false or `'limited'`.
/// [configured] is `extensions.supportUntrustedWorkspaces` (user
/// settings), [product] the product's `extensionUntrustedWorkspaceSupport`.
Object untrustedWorkspaceSupportType(
  Map<String, Object?> manifest, {
  bool trustEnabled = true,
  Map<String, Object?>? configured,
  Map<String, Object?>? product,
}) {
  if (!trustEnabled || manifest['main'] == null) return true;
  final id = '${manifest['publisher']}.${manifest['name']}';
  Map<String, Object?>? entryOf(Map<String, Object?>? map) {
    if (map == null) return null;
    for (final MapEntry(:key, :value) in map.entries) {
      if (key.toLowerCase() == id.toLowerCase() && value is Map) {
        return value.cast();
      }
    }
    return null;
  }

  final configuredEntry = entryOf(configured);
  if (configuredEntry != null) {
    final version = configuredEntry['version'];
    final supported = configuredEntry['supported'];
    if ((version == null || version == manifest['version']) &&
        (supported == true || supported == false || supported == 'limited')) {
      return supported!;
    }
  }
  final productEntry = entryOf(product);
  if (productEntry?['override'] case final Object o) return o;
  final capabilities = manifest['capabilities'];
  if (capabilities is Map) {
    final untrusted = capabilities['untrustedWorkspaces'];
    if (untrusted is Map && untrusted.containsKey('supported')) {
      return untrusted['supported'] ?? false;
    }
  }
  if (productEntry?['default'] case final Object d) return d;
  return false;
}

/// Whether [manifest]'s extension runs in a workspace that is [trusted]
/// (`EnablementState.DisabledByTrustRequirement` otherwise).
bool runsInWorkspace(
  Map<String, Object?> manifest, {
  required bool trusted,
  bool trustEnabled = true,
  Map<String, Object?>? configured,
  Map<String, Object?>? product,
}) =>
    trusted ||
    untrustedWorkspaceSupportType(
          manifest,
          trustEnabled: trustEnabled,
          configured: configured,
          product: product,
        ) !=
        false;
