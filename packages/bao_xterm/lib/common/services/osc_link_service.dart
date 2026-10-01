// Copyright (c) 2022 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/LICENSE.txt.
// Ported from xterm.js src/common/services/OscLinkService.ts (c58ea36).

import '../buffer/types.dart';
import '../types.dart';
import 'services.dart';

class OscLinkService implements IOscLinkService {
  OscLinkService(this._bufferService);

  final IBufferService _bufferService;

  int _nextId = 1;

  /// A map of the link key to link entry. This is used to add additional
  /// lines to links with ids.
  final Map<String, _OscLinkEntry> _entriesWithId = <String, _OscLinkEntry>{};

  /// A map of the link id to the link entry. The "link id" (number) which is
  /// the numberic representation of a unique link should not be confused
  /// with "id" (string) which comes in with `id=` in the OSC link's
  /// properties.
  final Map<int, _OscLinkEntry> _dataByLinkId = <int, _OscLinkEntry>{};

  @override
  int registerLink(IOscLinkData data) {
    final buffer = _bufferService.buffer;

    // Links with no id will only ever be registered a single time
    if (data.id == null) {
      final marker = buffer.addMarker(buffer.ybase + buffer.y);
      final entry = _OscLinkEntry(
        data: data,
        id: _nextId++,
        lines: <IMarker>[marker],
      );
      marker.onDispose((_) => _removeMarkerFromLink(entry, marker));
      _dataByLinkId[entry.id] = entry;
      return entry.id;
    }

    // Add the line to the link if it already exists
    final key = _getEntryIdKey(data);
    final match = _entriesWithId[key];
    if (match != null) {
      addLineToLink(match.id, buffer.ybase + buffer.y);
      return match.id;
    }

    // Create the link
    final marker = buffer.addMarker(buffer.ybase + buffer.y);
    final entry = _OscLinkEntry(
      id: _nextId++,
      key: _getEntryIdKey(data),
      data: data,
      lines: <IMarker>[marker],
    );
    marker.onDispose((_) => _removeMarkerFromLink(entry, marker));
    _entriesWithId[entry.key!] = entry;
    _dataByLinkId[entry.id] = entry;
    return entry.id;
  }

  @override
  void addLineToLink(int linkId, int y) {
    final entry = _dataByLinkId[linkId];
    if (entry == null) {
      return;
    }
    if (entry.lines.every((e) => e.line != y)) {
      final marker = _bufferService.buffer.addMarker(y);
      entry.lines.add(marker);
      marker.onDispose((_) => _removeMarkerFromLink(entry, marker));
    }
  }

  @override
  IOscLinkData? getLinkData(int linkId) {
    return _dataByLinkId[linkId]?.data;
  }

  /// [linkData] has an id (upstream's `Required<IOscLinkData>`).
  String _getEntryIdKey(IOscLinkData linkData) {
    return '${linkData.id};;${linkData.uri}';
  }

  void _removeMarkerFromLink(_OscLinkEntry entry, IMarker marker) {
    final index = entry.lines.indexOf(marker);
    if (index == -1) {
      return;
    }
    entry.lines.removeAt(index);
    if (entry.lines.isEmpty) {
      if (entry.data.id != null) {
        _entriesWithId.remove(entry.key);
      }
      _dataByLinkId.remove(entry.id);
    }
  }
}

/// Upstream's `IOscLinkEntryNoId` (no [key]) and `IOscLinkEntryWithId`.
class _OscLinkEntry {
  _OscLinkEntry({
    required this.data,
    required this.id,
    required this.lines,
    this.key,
  });

  IOscLinkData data;
  int id;
  List<IMarker> lines;
  String? key;
}
