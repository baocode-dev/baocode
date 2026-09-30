// Copyright (c) 2021 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Ported from xterm.js src/common/public/BufferNamespaceApi.ts (c58ea36).

import '../../typings/xterm.dart' as api;
import '../core_terminal.dart';
import '../event.dart';
import '../lifecycle.dart';
import 'buffer_api_view.dart';

class BufferNamespaceApi extends Disposable implements api.IBufferNamespace {
  BufferNamespaceApi(this._core) {
    _normal = BufferApiView(_core.buffers.normal, 'normal');
    _alternate = BufferApiView(_core.buffers.alt, 'alternate');
    register(
      _core.buffers.onBufferActivate((_) => _onBufferChange.fire(active)),
    );
  }

  final ICoreTerminal _core;
  late final BufferApiView _normal;
  late final BufferApiView _alternate;

  late final Emitter<api.IBuffer> _onBufferChange = register(
    Emitter<api.IBuffer>(),
  );
  @override
  late final IEvent<api.IBuffer> onBufferChange = _onBufferChange.event;

  @override
  api.IBuffer get active {
    if (identical(_core.buffers.active, _core.buffers.normal)) {
      return normal;
    }
    if (identical(_core.buffers.active, _core.buffers.alt)) {
      return alternate;
    }
    throw StateError('Active buffer is neither normal nor alternate');
  }

  @override
  api.IBuffer get normal => _normal.init(_core.buffers.normal);

  @override
  api.IBuffer get alternate => _alternate.init(_core.buffers.alt);
}
