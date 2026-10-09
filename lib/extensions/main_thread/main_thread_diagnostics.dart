/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The diagnostics an extension's `DiagnosticCollection` publishes, and the
// markers of every other owner that go back to the extension host.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadDiagnostics.ts
// (`MainThreadDiagnostics`: `$changeMany`, `$clear`, `_forwardMarkers`,
// `extHostId`/`origin`, the disposal that hands the owners' markers back).
//
// Deviations:
// - Markers go to `lib/extensions/language/marker_service.dart`
//   (`MarkerService`) rather than a platform service; the URI identity
//   service is not ported, so resources are keyed as they arrive.
// - `extHostId` is derived from the session rather than a process-wide
//   counter, so a restarted host can tell its own markers from another
//   host's.

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart';

import '../language/language_dto.dart' as dto;
import '../language/marker_service.dart';
import 'main_thread_context.dart';

final class MainThreadDiagnostics extends MainThreadDiagnosticsUnsupported {
  MainThreadDiagnostics({
    required this.markers,
    required RpcProtocol proxy,
    this.extensionHostId,
  }) : _proxy = ExtHostDiagnosticsProxy(proxy);

  final MarkerService markers;
  final ExtHostDiagnosticsProxy _proxy;

  /// This host's id, stamped on the markers it sends (`origin`).
  final String? extensionHostId;

  /// The owners a collection was created for (`_activeOwners`).
  final _activeOwners = <String>{};

  late final String _extHostId = extensionHostId ?? 'extHost1';

  StreamSubscription<List<VsUri>>? _subscription;

  /// Starts forwarding other owners' markers to the extension host (the
  /// constructor's `onMarkerChanged` listener).
  void listen() {
    _subscription ??= markers.onMarkerChanged.listen(_forwardMarkers);
  }

  @override
  void $changeMany(String owner, List<List<Object?>> entries) {
    for (final entry in entries) {
      if (entry.length < 2) continue;
      final uri = dto.decodeUri(entry[0]);
      if (uri == null) continue;
      final raw = entry[1];
      if (raw is! List) continue;
      final data = <MarkerData>[
        for (final marker in raw) dto.decodeMarkerData(marker),
      ];
      for (final marker in data) {
        marker.origin ??= _extHostId;
      }
      markers.changeOne(owner, uri, data);
    }
    _activeOwners.add(owner);
  }

  @override
  void $clear(String owner) {
    markers.changeAll(owner, const []);
    _activeOwners.remove(owner);
  }

  /// `_forwardMarkers`: every other owner's markers of [resources], by
  /// resource.
  void _forwardMarkers(List<VsUri> resources) {
    final data = <List<Object?>>[];
    for (final resource in resources) {
      final all = markers.read(
        MarkerReadOptions(resource: resource, ignoreResourceFilters: true),
      );
      final mine = [
        for (final marker in all)
          if (marker.origin != _extHostId) marker,
      ];
      data.add([resource.toJson(), [for (final m in mine) dto.encodeMarkerData(m)]]);
    }
    if (data.isEmpty) return;
    unawaited(_proxy.$acceptMarkersChange(data).catchError((Object _) {}));
  }

  /// The session ends: the markers this host published alone go away, so a
  /// restarted host does not keep answering for them.
  ///
  /// Upstream hands each owner's markers back; here the host's markers are
  /// simply dropped (the editors' own markers stay).
  void dispose() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    for (final owner in _activeOwners.toList()) {
      final other = [
        for (final marker in markers.read(MarkerReadOptions(owner: owner)))
          if (marker.origin != _extHostId)
            ResourceMarker(marker.resource, marker),
      ];
      markers.changeAll(owner, other);
    }
    _activeOwners.clear();
  }

  static RpcActor customer(MainThreadContext context, MainThreadDiagnostics actor) {
    actor.listen();
    return MainThreadDiagnosticsActor(actor);
  }
}
