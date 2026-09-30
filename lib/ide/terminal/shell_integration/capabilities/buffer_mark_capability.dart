/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Marks: buffer lines, named or not, kept track of as the buffer scrolls.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/platform/terminal/common/capabilities/bufferMarkCapability.ts.

import '../../xterm/common/buffer/types.dart';
import '../../xterm/common/event.dart';
import '../../xterm/common/lifecycle.dart';
import '../../xterm/headless/terminal.dart';
import 'capabilities.dart';

/// Manages "marks" in the buffer which are lines that are tracked when lines
/// are added to or removed from the buffer.
class BufferMarkCapability extends Disposable implements IBufferMarkCapability {
  BufferMarkCapability(this._terminal);

  final Terminal _terminal;

  @override
  TerminalCapability<IBufferMarkCapability> get type =>
      TerminalCapability.bufferMarkDetection;

  final Map<String, IMarker> _idToMarkerMap = {};
  final Map<int, IMarker> _anonymousMarkers = {};

  late final _onMarkAdded = register(Emitter<IMarkProperties>());
  @override
  late final IEvent<IMarkProperties> onMarkAdded = _onMarkAdded.event;

  @override
  Iterable<IMarker> markers() sync* {
    yield* _idToMarkerMap.values;
    yield* _anonymousMarkers.values;
  }

  @override
  void addMark([IMarkProperties? properties]) {
    final marker = properties?.marker ?? _terminal.registerMarker(0);
    final id = properties?.id;
    if (id != null && id.isNotEmpty) {
      _idToMarkerMap[id] = marker;
      marker.onDispose((_) => _idToMarkerMap.remove(id));
    } else {
      _anonymousMarkers[marker.id] = marker;
      marker.onDispose((_) => _anonymousMarkers.remove(marker.id));
    }
    _onMarkAdded.fire(
      IMarkProperties(
        marker: marker,
        id: id,
        hidden: properties?.hidden,
        hoverMessage: properties?.hoverMessage,
      ),
    );
  }

  @override
  IMarker? getMark(String id) {
    return _idToMarkerMap[id];
  }
}
