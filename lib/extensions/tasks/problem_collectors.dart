/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The problem collectors: a task's output, line by line, through its problem
// matchers into the markers (the Problems view, the editors' squiggles), the
// markers of the last run cleaned; a background task's begin and end
// patterns tell when it is busy.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/contrib/tasks/common/problemCollectors.ts.
//
// Deviation: which documents are open is asked of [isOpen] instead of
// following the model service; a closed model's markers are not matched
// again from the recorded lines (`onModelRemoved`).

import 'dart:async';
import 'dart:io' show Platform;

import 'package:bao_exthost/bao_exthost.dart';

import '../language/marker_service.dart';
import 'problem_matcher.dart';

/// `ProblemCollectorEventKind`.
enum ProblemCollectorEventKind {
  backgroundProcessingBegins,
  backgroundProcessingEnds,
}

/// `IProblemCollectorEvent`.
typedef ProblemCollectorEvent = ({
  ProblemCollectorEventKind kind,
  Map<String, String>? capturedVariables,
});

/// `AbstractProblemCollector`.
abstract base class AbstractProblemCollector {
  AbstractProblemCollector(
    this.problemMatchers,
    this.markerService, {
    bool Function(VsUri resource)? isOpen,
    ProblemFileSystem? files,
  }) : _isOpen = isOpen ?? _never {
    for (final matcher in problemMatchers.map(
      (m) => createLineMatcher(m, files),
    )) {
      final length = matcher.matchLength;
      if (length > _bufferLength) _bufferLength = length;
      _matchers.putIfAbsent(length, () => []).add(matcher);
    }
    for (final matcher in problemMatchers) {
      final current = applyToByOwner[matcher.owner];
      applyToByOwner[matcher.owner] = current == null
          ? matcher.applyTo
          : _mergeApplyTo(current, matcher.applyTo);
    }
  }

  static bool _never(VsUri _) => false;

  final List<ProblemMatcher> problemMatchers;
  final MarkerService markerService;
  final bool Function(VsUri resource) _isOpen;

  final _matchers = <int, List<LineMatcher>>{};
  LineMatcher? _activeMatcher;
  int _numberOfMatches = 0;
  MarkerSeverity? _maxMarkerSeverity;
  List<String> _buffer = [];
  int _bufferLength = 1;
  Future<void>? _tail;

  /// [owner] -> ApplyToKind
  final applyToByOwner = <String, ApplyToKind>{};

  /// [owner] -> [resource] -> URI
  var _resourcesToClean = <String, Map<String, VsUri>>{};

  /// [owner] -> [resource] -> [markerkey] -> markerData
  final _markers = <String, Map<String, Map<String, MarkerData>>>{};

  /// [owner] -> [resource] -> number
  final _deliveredMarkers = <String, Map<String, int>>{};

  final _onDidStateChange = StreamController<ProblemCollectorEvent>.broadcast(
    sync: true,
  );
  final _onDidFindFirstMatch = StreamController<void>.broadcast(sync: true);
  final _onDidFindErrors = StreamController<List<Marker>>.broadcast(sync: true);
  final _onDidRequestInvalidateLastMarker = StreamController<void>.broadcast(
    sync: true,
  );

  Stream<ProblemCollectorEvent> get onDidStateChange =>
      _onDidStateChange.stream;
  Stream<void> get onDidFindFirstMatch => _onDidFindFirstMatch.stream;
  Stream<List<Marker>> get onDidFindErrors => _onDidFindErrors.stream;
  Stream<void> get onDidRequestInvalidateLastMarker =>
      _onDidRequestInvalidateLastMarker.stream;

  void _fireState(
    ProblemCollectorEventKind kind, [
    Map<String, String>? capturedVariables,
  ]) {
    if (!_onDidStateChange.isClosed) {
      _onDidStateChange.add((kind: kind, capturedVariables: capturedVariables));
    }
  }

  /// Lines are processed in order, each once the one before is.
  void processLine(String line) {
    final tail = _tail;
    _tail = tail == null
        ? _processLineInternal(line)
        : tail.then((_) => _processLineInternal(line));
  }

  /// Once every line given is processed.
  Future<void> get idle async {
    while (true) {
      final tail = _tail;
      await tail;
      if (identical(tail, _tail)) return;
    }
  }

  Future<void> _processLineInternal(String line);

  void dispose() {
    _onDidStateChange.close();
    _onDidFindFirstMatch.close();
    _onDidFindErrors.close();
    _onDidRequestInvalidateLastMarker.close();
  }

  int get numberOfMatches => _numberOfMatches;

  MarkerSeverity? get maxMarkerSeverity => _maxMarkerSeverity;

  ProblemMatch? _tryFindMarker(String line) {
    ProblemMatch? result;
    if (_activeMatcher case final active?) {
      result = active.next(line);
      if (result != null) {
        _captureMatch(result);
        return result;
      }
      _clearBuffer();
      _activeMatcher = null;
    }
    if (_buffer.length < _bufferLength) {
      _buffer.add(line);
    } else {
      final end = _buffer.length - 1;
      for (var i = 0; i < end; i++) {
        _buffer[i] = _buffer[i + 1];
      }
      _buffer[end] = line;
    }
    result = _tryMatchers();
    if (result != null) _clearBuffer();
    return result;
  }

  Future<bool> _shouldApplyMatch(ProblemMatch result) async =>
      switch (result.description.applyTo) {
        ApplyToKind.allDocuments => true,
        ApplyToKind.openDocuments => _isOpen(await result.resource),
        ApplyToKind.closedDocuments => !_isOpen(await result.resource),
      };

  static ApplyToKind _mergeApplyTo(ApplyToKind current, ApplyToKind value) =>
      current == value || current == ApplyToKind.allDocuments
      ? current
      : ApplyToKind.allDocuments;

  ProblemMatch? _tryMatchers() {
    _activeMatcher = null;
    final length = _buffer.length;
    for (var startIndex = 0; startIndex < length; startIndex++) {
      final candidates = _matchers[length - startIndex];
      if (candidates == null) continue;
      for (final matcher in candidates) {
        final result = matcher.handle(_buffer, startIndex);
        if (result.match case final match?) {
          _captureMatch(match);
          if (result.continues) _activeMatcher = matcher;
          return match;
        }
      }
    }
    return null;
  }

  void _captureMatch(ProblemMatch match) {
    _numberOfMatches++;
    final max = _maxMarkerSeverity;
    if (max == null || match.marker.severity.value > max.value) {
      _maxMarkerSeverity = match.marker.severity;
    }
  }

  void _clearBuffer() {
    if (_buffer.isNotEmpty) _buffer = [];
  }

  void _recordResourcesToClean(String owner) {
    final toClean = _resourceSetToClean(owner);
    for (final marker in markerService.read(MarkerReadOptions(owner: owner))) {
      toClean['${marker.resource}'] = marker.resource;
    }
  }

  void _recordResourceToClean(String owner, VsUri resource) =>
      _resourceSetToClean(owner)['$resource'] = resource;

  void _removeResourceToClean(String owner, String resource) =>
      _resourcesToClean[owner]?.remove(resource);

  Map<String, VsUri> _resourceSetToClean(String owner) =>
      _resourcesToClean.putIfAbsent(owner, () => {});

  void _cleanAllMarkers() {
    _resourcesToClean.forEach(_cleanMarkersOf);
    _resourcesToClean = {};
  }

  void _cleanMarkers(String owner) {
    final toClean = _resourcesToClean.remove(owner);
    if (toClean != null) _cleanMarkersOf(owner, toClean);
  }

  void _cleanMarkersOf(String owner, Map<String, VsUri> toClean) {
    final applyTo = applyToByOwner[owner];
    markerService.remove(owner, [
      for (final uri in toClean.values)
        if (applyTo == ApplyToKind.allDocuments ||
            (applyTo == ApplyToKind.openDocuments && _isOpen(uri)) ||
            (applyTo == ApplyToKind.closedDocuments && !_isOpen(uri)))
          uri,
    ]);
  }

  void _recordMarker(MarkerData marker, String owner, String resource) {
    final perResource = _markers
        .putIfAbsent(owner, () => {})
        .putIfAbsent(resource, () => {});
    final key = marker.makeKey(useMessage: false);
    final existing = perResource[key];
    if (existing == null) {
      perResource[key] = marker;
    } else if (existing.message.length < marker.message.length &&
        Platform.isWindows) {
      // Most likely microsoft/vscode#77475: when the key is the same and
      // the message is shorter, we have hit this limitation.
      perResource[key] = marker;
    }
  }

  void _reportMarkers() {
    _markers.forEach((owner, perOwner) {
      final delivered = _deliveredMarkersPerOwner(owner);
      perOwner.forEach((resource, markers) {
        _deliverResolved(owner, resource, markers, delivered);
      });
    });
  }

  void _deliverMarkersPerOwnerAndResource(String owner, String resource) {
    final markers = _markers[owner]?[resource];
    if (markers == null) return;
    _deliverResolved(
      owner,
      resource,
      markers,
      _deliveredMarkersPerOwner(owner),
    );
  }

  void _deliverResolved(
    String owner,
    String resource,
    Map<String, MarkerData> markers,
    Map<String, int> reported,
  ) {
    if (markers.length != reported[resource]) {
      markerService.changeOne(
        owner,
        VsUri.parse(resource),
        markers.values.toList(),
      );
      reported[resource] = markers.length;
    }
  }

  Map<String, int> _deliveredMarkersPerOwner(String owner) =>
      _deliveredMarkers.putIfAbsent(owner, () => {});

  void _cleanMarkerCaches() {
    _numberOfMatches = 0;
    _maxMarkerSeverity = null;
    _markers.clear();
    _deliveredMarkers.clear();
  }

  /// The markers out, and those of the last run that were not found again
  /// cleaned.
  void done() {
    _reportMarkers();
    _cleanAllMarkers();
  }
}

/// `StartStopProblemCollector`: for a task that ends.
final class StartStopProblemCollector extends AbstractProblemCollector {
  StartStopProblemCollector(
    super.problemMatchers,
    super.markerService, {
    super.isOpen,
    super.files,
  }) {
    for (final owner in {for (final m in problemMatchers) m.owner}) {
      _recordResourcesToClean(owner);
    }
  }

  String? _currentOwner;
  String? _currentResource;
  bool _hasStarted = false;

  @override
  Future<void> _processLineInternal(String line) async {
    if (!_hasStarted) {
      _hasStarted = true;
      _fireState(ProblemCollectorEventKind.backgroundProcessingBegins);
    }
    final match = _tryFindMarker(line);
    if (match == null) return;
    final owner = match.description.owner;
    final resource = '${await match.resource}';
    _removeResourceToClean(owner, resource);
    if (await _shouldApplyMatch(match)) {
      _recordMarker(match.marker, owner, resource);
      if (_currentOwner != owner || _currentResource != resource) {
        if (_currentOwner != null && _currentResource != null) {
          _deliverMarkersPerOwnerAndResource(_currentOwner!, _currentResource!);
        }
        _currentOwner = owner;
        _currentResource = resource;
      }
    }
  }
}

typedef _BackgroundPatterns = ({
  int key,
  ProblemMatcher matcher,
  WatchingPattern begin,
  WatchingPattern end,
});

/// `WatchingProblemCollector`: for a background task, busy between its
/// matchers' begin and end patterns.
final class WatchingProblemCollector extends AbstractProblemCollector {
  WatchingProblemCollector(
    super.problemMatchers,
    super.markerService, {
    super.isOpen,
    super.files,
  }) {
    _resetCurrentResource();
    for (final (key, matcher) in problemMatchers.indexed) {
      final watching = matcher.watching;
      if (watching == null) continue;
      _backgroundPatterns.add((
        key: key,
        matcher: matcher,
        begin: watching.beginsPattern,
        end: watching.endsPattern,
      ));
      beginPatterns.add(watching.beginsPattern.regexp);
    }
  }

  final _backgroundPatterns = <_BackgroundPatterns>[];

  /// microsoft/vscode#44018.
  final _activeBackgroundMatchers = <int>{};
  String? _currentOwner;
  String? _currentResource;
  List<String> _lines = [];
  final beginPatterns = <RegExp>[];

  void aboutToStart() {
    for (final background in _backgroundPatterns) {
      if (background.matcher.watching?.activeOnStart ?? false) {
        _activeBackgroundMatchers.add(background.key);
        _fireState(ProblemCollectorEventKind.backgroundProcessingBegins);
        _recordResourcesToClean(background.matcher.owner);
      }
    }
  }

  @override
  Future<void> _processLineInternal(String line) async {
    if (await _tryBegin(line) || _tryFinish(line)) return;
    _lines.add(line);
    final match = _tryFindMarker(line);
    if (match == null) return;
    final resource = '${await match.resource}';
    final owner = match.description.owner;
    _removeResourceToClean(owner, resource);
    if (await _shouldApplyMatch(match)) {
      _recordMarker(match.marker, owner, resource);
      if (_currentOwner != owner || _currentResource != resource) {
        _reportMarkersForCurrentResource();
        _currentOwner = owner;
        _currentResource = resource;
      }
    }
  }

  void forceDelivery() => _reportMarkersForCurrentResource();

  Future<bool> _tryBegin(String line) async {
    var result = false;
    for (final background in _backgroundPatterns) {
      final matches = background.begin.regexp.firstMatch(line);
      if (matches == null) continue;
      if (_activeBackgroundMatchers.contains(background.key)) continue;
      _activeBackgroundMatchers.add(background.key);
      result = true;
      if (!_onDidFindFirstMatch.isClosed) _onDidFindFirstMatch.add(null);
      _lines = [line];
      _fireState(ProblemCollectorEventKind.backgroundProcessingBegins);
      _cleanMarkerCaches();
      _resetCurrentResource();
      final owner = background.matcher.owner;
      final index = background.begin.file;
      final file = index != null && index <= matches.groupCount
          ? matches.group(index)
          : null;
      if (file != null && file.isNotEmpty) {
        _recordResourceToClean(
          owner,
          await getProblemResource(file, background.matcher),
        );
      } else {
        _recordResourcesToClean(owner);
      }
    }
    return result;
  }

  bool _tryFinish(String line) {
    var result = false;
    for (final background in _backgroundPatterns) {
      final matches = background.end.regexp.firstMatch(line);
      if (matches == null) continue;
      if (_numberOfMatches > 0) {
        if (!_onDidFindErrors.isClosed) {
          _onDidFindErrors.add(
            markerService.read(
              MarkerReadOptions(owner: background.matcher.owner),
            ),
          );
        }
      } else if (!_onDidRequestInvalidateLastMarker.isClosed) {
        _onDidRequestInvalidateLastMarker.add(null);
      }
      if (_activeBackgroundMatchers.remove(background.key)) {
        _resetCurrentResource();
        final names = matches.groupNames.toList();
        _fireState(
          ProblemCollectorEventKind.backgroundProcessingEnds,
          names.isEmpty
              ? null
              : {for (final name in names) name: ?matches.namedGroup(name)},
        );
        result = true;
        _lines.add(line);
        _cleanMarkers(background.matcher.owner);
        _cleanMarkerCaches();
      }
    }
    return result;
  }

  void _resetCurrentResource() {
    _reportMarkersForCurrentResource();
    _currentOwner = null;
    _currentResource = null;
  }

  void _reportMarkersForCurrentResource() {
    if (_currentOwner != null && _currentResource != null) {
      _deliverMarkersPerOwnerAndResource(_currentOwner!, _currentResource!);
    }
  }

  @override
  void done() {
    for (final owner in applyToByOwner.keys) {
      _recordResourcesToClean(owner);
    }
    super.done();
  }

  bool get isWatching => _backgroundPatterns.isNotEmpty;
}
