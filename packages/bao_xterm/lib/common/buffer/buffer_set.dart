// Copyright (c) 2017 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Ported from xterm.js src/common/buffer/BufferSet.ts (c58ea36).

import '../event.dart';
import '../lifecycle.dart';
import '../services/services.dart';
import 'buffer.dart';
import 'types.dart';

/// The BufferSet represents the set of two buffers used by xterm terminals
/// (normal and alt) and provides also utilities for working with them.
class BufferSet extends Disposable implements IBufferSet {
  /// Create a new BufferSet for the given terminal.
  BufferSet(this._optionsService, this._bufferService, this._logService) {
    _normalBuffer = register(MutableDisposable<Buffer>());
    _altBuffer = register(MutableDisposable<Buffer>());
    _onBufferActivate = register(
      Emitter<({IBuffer activeBuffer, IBuffer inactiveBuffer})>(),
    );
    onBufferActivate = _onBufferActivate.event;
    reset();
    register(
      _optionsService.onSpecificOptionChange<int>(
        'scrollback',
        (_) => resize(_bufferService.cols, _bufferService.rows),
      ),
    );
    register(
      _optionsService.onSpecificOptionChange<int>(
        'tabStopWidth',
        (_) => setupTabStops(),
      ),
    );
  }

  final IOptionsService _optionsService;
  final IBufferService _bufferService;
  final ILogService _logService;

  late Buffer _normal;
  late Buffer _alt;
  late Buffer _activeBuffer;
  late final MutableDisposable<Buffer> _normalBuffer;
  late final MutableDisposable<Buffer> _altBuffer;

  late final Emitter<({IBuffer activeBuffer, IBuffer inactiveBuffer})>
  _onBufferActivate;
  @override
  late final IEvent<({IBuffer activeBuffer, IBuffer inactiveBuffer})>
  onBufferActivate;

  @override
  void reset() {
    _normal = Buffer(true, _optionsService, _bufferService, _logService);
    _normalBuffer.value = _normal;
    _normal.fillViewportRows();

    // The alt buffer should never have scrollback.
    // See http://invisible-island.net/xterm/ctlseqs/ctlseqs.html#h2-The-Alternate-Screen-Buffer
    _alt = Buffer(false, _optionsService, _bufferService, _logService);
    _altBuffer.value = _alt;
    _activeBuffer = _normal;
    _onBufferActivate.fire((activeBuffer: _normal, inactiveBuffer: _alt));

    setupTabStops();
  }

  /// Returns the alt Buffer of the BufferSet
  @override
  Buffer get alt {
    return _alt;
  }

  /// Returns the currently active Buffer of the BufferSet
  @override
  Buffer get active {
    return _activeBuffer;
  }

  /// Returns the normal Buffer of the BufferSet
  @override
  Buffer get normal {
    return _normal;
  }

  /// Sets the normal Buffer of the BufferSet as its currently active Buffer
  @override
  void activateNormalBuffer() {
    if (identical(_activeBuffer, _normal)) {
      return;
    }
    _normal.x = _alt.x;
    _normal.y = _alt.y;
    // The alt buffer should always be cleared when we switch to the normal
    // buffer. This frees up memory since the alt buffer should always be new
    // when activated.
    _alt.clearAllMarkers();
    _alt.clear();
    _activeBuffer = _normal;
    _onBufferActivate.fire((activeBuffer: _normal, inactiveBuffer: _alt));
  }

  /// Sets the alt Buffer of the BufferSet as its currently active Buffer
  @override
  void activateAltBuffer([IAttributeData? fillAttr]) {
    if (identical(_activeBuffer, _alt)) {
      return;
    }
    // Since the alt buffer is always cleared when the normal buffer is
    // activated, we want to fill it when switching to it.
    _alt.fillViewportRows(fillAttr);
    _alt.x = _normal.x;
    _alt.y = _normal.y;
    _activeBuffer = _alt;
    _onBufferActivate.fire((activeBuffer: _alt, inactiveBuffer: _normal));
  }

  /// Resizes both normal and alt buffers to [newCols] columns and [newRows]
  /// rows, adjusting their data accordingly.
  @override
  void resize(int newCols, int newRows) {
    _normal.resize(newCols, newRows);
    _alt.resize(newCols, newRows);
    setupTabStops(newCols);
  }

  /// Setup the tab stops, starting from index [i].
  @override
  void setupTabStops([int? i]) {
    _normal.setupTabStops(i);
    _alt.setupTabStops(i);
  }
}
