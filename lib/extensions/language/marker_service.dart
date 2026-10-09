/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Diagnostics ("markers") by owner and resource: what extensions publish
// through `MainThreadDiagnostics.$changeMany`/`$clear`, read by the problems
// panel and the editor.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/platform/markers/common/markers.ts (`IMarkerData`, `IMarker`,
// `MarkerSeverity`, `MarkerTag`, `IRelatedInformation`, `IResourceMarker`,
// `IMarkerReadOptions`, `MarkerStatistics`, `IMarkerData.makeKey`),
// src/vs/platform/markers/common/markerService.ts (`MarkerService`,
// `DoubleResourceMap`, `MarkerStats`, `unsupportedSchemas`).
//
// Deviations:
// - `onMarkerChanged` merges the resources of every change in one microtask
//   (`MicrotaskEmitter` with `_merge`) and is a Dart stream; the service is
//   also a [ChangeNotifier] notifying with the same timing.
// - Resource keys are `VsUri.toString()` (ResourceMap's default key).
// - Statistics are recomputed on read instead of maintained incrementally.

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart' show VsUri;
import 'package:flutter/foundation.dart';

/// `MarkerSeverity` (bit values, for [MarkerReadOptions.severities]).
enum MarkerSeverity {
  hint(1),
  info(2),
  warning(4),
  error(8);

  const MarkerSeverity(this.value);
  final int value;

  static MarkerSeverity fromValue(int value) => switch (value) {
    8 => error,
    4 => warning,
    2 => info,
    _ => hint,
  };

  String get displayName => switch (this) {
    error => 'Error',
    warning => 'Warning',
    info => 'Info',
    hint => '',
  };
}

/// `MarkerTag`.
enum MarkerTag {
  unnecessary(1),
  deprecated(2);

  const MarkerTag(this.value);
  final int value;
}

/// `IRelatedInformation`.
class RelatedInformation {
  const RelatedInformation({
    required this.resource,
    required this.message,
    required this.startLineNumber,
    required this.startColumn,
    required this.endLineNumber,
    required this.endColumn,
  });

  final VsUri resource;
  final String message;
  final int startLineNumber;
  final int startColumn;
  final int endLineNumber;
  final int endColumn;
}

/// A marker code: `string | { value, target }`.
class MarkerCode {
  const MarkerCode(this.value, {this.target});

  final String value;
  final VsUri? target;
}

/// `IMarkerData`: one-based model coordinates.
class MarkerData {
  MarkerData({
    required this.severity,
    required this.message,
    required this.startLineNumber,
    required this.startColumn,
    required this.endLineNumber,
    required this.endColumn,
    this.code,
    this.source,
    this.modelVersionId,
    this.relatedInformation,
    this.tags,
    this.origin,
  });

  final MarkerCode? code;
  final MarkerSeverity severity;
  final String message;
  final String? source;
  final int startLineNumber;
  final int startColumn;
  final int endLineNumber;
  final int endColumn;
  final int? modelVersionId;
  final List<RelatedInformation>? relatedInformation;
  final List<MarkerTag>? tags;

  /// Who publishes it (the extension host that sent it); upstream sets it
  /// when the extension host did not.
  String? origin;

  /// `IMarkerData.makeKey`.
  String get key => makeKey(useMessage: true);

  /// `IMarkerData.makeKeyOptionalMessage`.
  String makeKey({required bool useMessage}) {
    String esc(String s) => s.replaceFirst('¦', '\\¦');
    return [
      '',
      source != null && source!.isNotEmpty ? esc(source!) : '',
      code != null && code!.value.isNotEmpty ? esc(code!.value) : '',
      severity.displayName,
      useMessage && message.isNotEmpty ? esc(message) : '',
      '$startLineNumber',
      '$startColumn',
      '$endLineNumber',
      '$endColumn',
      '',
    ].join('¦');
  }
}

/// `IMarker`.
class Marker extends MarkerData {
  Marker({
    required this.owner,
    required this.resource,
    required super.severity,
    required super.message,
    required super.startLineNumber,
    required super.startColumn,
    required super.endLineNumber,
    required super.endColumn,
    super.code,
    super.source,
    super.modelVersionId,
    super.relatedInformation,
    super.tags,
    super.origin,
  });

  final String owner;
  final VsUri resource;
}

/// `IResourceMarker`.
class ResourceMarker {
  const ResourceMarker(this.resource, this.marker);

  final VsUri resource;
  final MarkerData marker;
}

/// `MarkerStatistics`.
class MarkerStatistics {
  const MarkerStatistics({
    this.errors = 0,
    this.warnings = 0,
    this.infos = 0,
    this.unknowns = 0,
  });

  final int errors;
  final int warnings;
  final int infos;
  final int unknowns;
}

/// `unsupportedSchemas`: resources whose markers statistics ignore.
const unsupportedSchemas = {
  'inmemory',
  'vscode-scm',
  'walkThrough',
  'walkThroughSnippet',
  'vscode-chat-code-block',
  'vscode-terminal',
};

/// `DoubleResourceMap`.
class _DoubleResourceMap<V> {
  final _byResource = <String, Map<String, V>>{};
  final _byOwner = <String, Map<String, V>>{};

  void set(VsUri resource, String owner, V value) {
    _byResource.putIfAbsent('$resource', () => {})[owner] = value;
    _byOwner.putIfAbsent(owner, () => {})['$resource'] = value;
  }

  V? get(VsUri resource, String owner) => _byResource['$resource']?[owner];

  bool delete(VsUri resource, String owner) {
    var removedA = false;
    var removedB = false;
    final ownerMap = _byResource['$resource'];
    if (ownerMap != null) {
      removedA = ownerMap.containsKey(owner);
      ownerMap.remove(owner);
      if (ownerMap.isEmpty) _byResource.remove('$resource');
    }
    final resourceMap = _byOwner[owner];
    if (resourceMap != null) {
      removedB = resourceMap.containsKey('$resource');
      resourceMap.remove('$resource');
      if (resourceMap.isEmpty) _byOwner.remove(owner);
    }
    if (removedA != removedB) {
      throw StateError('illegal state');
    }
    return removedA && removedB;
  }

  Iterable<V> valuesOfOwner(String owner) =>
      _byOwner[owner]?.values ?? const [];

  Iterable<V> valuesOfResource(VsUri resource) =>
      _byResource['$resource']?.values ?? const [];

  Iterable<V> values() => _byOwner.values.expand((map) => map.values);
}

/// `IMarkerReadOptions`.
class MarkerReadOptions {
  const MarkerReadOptions({
    this.owner,
    this.resource,
    this.severities,
    this.take,
    this.ignoreResourceFilters = false,
  });

  final String? owner;
  final VsUri? resource;

  /// [MarkerSeverity.value] bits to accept.
  final int? severities;
  final int? take;
  final bool ignoreResourceFilters;
}

/// `MarkerService`.
class MarkerService extends ChangeNotifier {
  final _data = _DoubleResourceMap<List<Marker>>();
  final _filteredResources = <String, List<String>>{};
  final _onMarkerChanged = StreamController<List<VsUri>>.broadcast(sync: true);
  List<VsUri>? _pending;
  bool _disposed = false;

  /// Resources whose markers changed, merged per microtask.
  Stream<List<VsUri>> get onMarkerChanged => _onMarkerChanged.stream;

  void _fire(List<VsUri> resources) {
    final pending = _pending;
    if (pending != null) {
      pending.addAll(resources);
      return;
    }
    _pending = [...resources];
    scheduleMicrotask(() {
      final all = _pending!;
      _pending = null;
      // ResourceMap merge: unique, first-seen order.
      final seen = <String>{};
      final merged = [
        for (final uri in all)
          if (seen.add('$uri')) uri,
      ];
      if (_disposed) return;
      _onMarkerChanged.add(merged);
      notifyListeners();
    });
  }

  MarkerStatistics getStatistics() {
    var errors = 0, warnings = 0, infos = 0, unknowns = 0;
    for (final marker in read()) {
      if (unsupportedSchemas.contains(marker.resource.scheme)) continue;
      switch (marker.severity) {
        case MarkerSeverity.error:
          errors++;
        case MarkerSeverity.warning:
          warnings++;
        case MarkerSeverity.info:
          infos++;
        case MarkerSeverity.hint:
          unknowns++;
      }
    }
    return MarkerStatistics(
      errors: errors,
      warnings: warnings,
      infos: infos,
      unknowns: unknowns,
    );
  }

  void remove(String owner, List<VsUri> resources) {
    for (final resource in resources) {
      changeOne(owner, resource, const []);
    }
  }

  void changeOne(String owner, VsUri resource, List<MarkerData> markerData) {
    if (markerData.isEmpty) {
      // remove marker for this (owner,resource)-tuple
      if (_data.delete(resource, owner)) _fire([resource]);
    } else {
      // insert marker for this (owner,resource)-tuple
      final markers = [
        for (final data in markerData) ?_toMarker(owner, resource, data),
      ];
      _data.set(resource, owner, markers);
      _fire([resource]);
    }
  }

  /// Pauses problems for [resource] (`installResourceFilter`); call the
  /// returned function to resume.
  void Function() installResourceFilter(VsUri resource, String reason) {
    _filteredResources.putIfAbsent('$resource', () => []).add(reason);
    _fire([resource]);
    var disposed = false;
    return () {
      if (disposed) return;
      disposed = true;
      final reasons = _filteredResources['$resource'];
      if (reasons == null) return;
      if (reasons.remove(reason)) {
        if (reasons.isEmpty) _filteredResources.remove('$resource');
        _fire([resource]);
      }
    };
  }

  static Marker? _toMarker(String owner, VsUri resource, MarkerData data) {
    if (data.message.isEmpty) return null;

    // santize data
    final startLineNumber = data.startLineNumber > 0 ? data.startLineNumber : 1;
    final startColumn = data.startColumn > 0 ? data.startColumn : 1;
    final endLineNumber = data.endLineNumber >= startLineNumber
        ? data.endLineNumber
        : startLineNumber;
    final endColumn = data.endColumn > 0 ? data.endColumn : startColumn;

    return Marker(
      owner: owner,
      resource: resource,
      code: data.code,
      severity: data.severity,
      message: data.message,
      source: data.source,
      startLineNumber: startLineNumber,
      startColumn: startColumn,
      endLineNumber: endLineNumber,
      endColumn: endColumn,
      relatedInformation: data.relatedInformation,
      modelVersionId: data.modelVersionId,
      tags: data.tags,
      origin: data.origin,
    );
  }

  void changeAll(String owner, List<ResourceMarker> data) {
    final changes = <VsUri>[];

    // remove old marker
    for (final markers in _data.valuesOfOwner(owner).toList()) {
      if (markers.isNotEmpty) {
        final resource = markers.first.resource;
        changes.add(resource);
        _data.delete(resource, owner);
      }
    }

    // add new markers
    final groups = <String, (VsUri, List<Marker>)>{};
    for (final ResourceMarker(:resource, marker: markerData) in data) {
      final marker = _toMarker(owner, resource, markerData);
      if (marker == null) continue; // filter bad markers
      final group = groups['$resource'];
      if (group == null) {
        groups['$resource'] = (resource, [marker]);
        changes.add(resource);
      } else {
        group.$2.add(marker);
      }
    }
    for (final (resource, markers) in groups.values) {
      _data.set(resource, owner, markers);
    }

    if (changes.isNotEmpty) _fire(changes);
  }

  Marker _createFilteredMarker(VsUri resource, List<String> reasons) => Marker(
    owner: 'markersFilter',
    resource: resource,
    severity: MarkerSeverity.info,
    message: reasons.length == 1
        ? 'Problems are paused because: "${reasons[0]}"'
        : 'Problems are paused because: "${reasons[0]}" and '
              '${reasons.length - 1} more',
    startLineNumber: 1,
    startColumn: 1,
    endLineNumber: 1,
    endColumn: 1,
  );

  List<Marker> read([MarkerReadOptions filter = const MarkerReadOptions()]) {
    final owner = filter.owner;
    final resource = filter.resource;
    final severities = filter.severities;
    var take = filter.take ?? -1;
    if (take < 0) take = -1;

    List<String>? reasonsOf(VsUri resource) =>
        filter.ignoreResourceFilters ? null : _filteredResources['$resource'];

    if (owner != null && owner.isNotEmpty && resource != null) {
      // exactly one owner AND resource
      final reasons = reasonsOf(resource);
      if (reasons != null && reasons.isNotEmpty) {
        return [_createFilteredMarker(resource, reasons)];
      }
      final data = _data.get(resource, owner);
      if (data == null) return [];
      final result = <Marker>[];
      for (final marker in data) {
        if (take > 0 && result.length == take) break;
        if (_accept(marker, severities)) result.add(marker);
      }
      return result;
    }

    // of one resource OR owner
    final iterable = (owner == null || owner.isEmpty) && resource == null
        ? _data.values()
        : resource != null
        ? _data.valuesOfResource(resource)
        : _data.valuesOfOwner(owner!);

    final result = <Marker>[];
    final filtered = <String>{};
    for (final markers in iterable) {
      for (final data in markers) {
        if (filtered.contains('${data.resource}')) continue;
        if (take > 0 && result.length == take) break;
        final reasons = reasonsOf(data.resource);
        if (reasons != null && reasons.isNotEmpty) {
          result.add(_createFilteredMarker(data.resource, reasons));
          filtered.add('${data.resource}');
        } else if (_accept(data, severities)) {
          result.add(data);
        }
      }
    }
    return result;
  }

  static bool _accept(Marker marker, int? severities) =>
      severities == null ||
      (severities & marker.severity.value) == marker.severity.value;

  @override
  void dispose() {
    _disposed = true;
    _onMarkerChanged.close();
    super.dispose();
  }
}
