// Copyright (c) 2019 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Ported from xterm.js src/common/parser/DcsParser.ts (c58ea36).

import 'dart:async';
import 'dart:typed_data';

import '../input/text_decoder.dart';
import '../lifecycle.dart';
import '../string_builder.dart';
import 'constants.dart';
import 'params.dart';
import 'types.dart';

const List<IDcsHandler> _emptyHandlers = <IDcsHandler>[];

void _noopFallback(int ident, String action, Object? payload) {}

class DcsParser implements IDcsParser {
  IHandlerCollection<IDcsHandler> _handlers = <int, List<IDcsHandler>>{};
  List<IDcsHandler> _active = _emptyHandlers;
  int _ident = 0;
  DcsFallbackHandlerType _handlerFb = _noopFallback;
  final ISubParserStackState _stack = ISubParserStackState(
    paused: false,
    loopPosition: 0,
    fallThrough: false,
  );

  @override
  void dispose() {
    _handlers = <int, List<IDcsHandler>>{};
    _handlerFb = _noopFallback;
    _active = _emptyHandlers;
  }

  @override
  IDisposable registerHandler(int ident, IDcsHandler handler) {
    final handlerList = _handlers.putIfAbsent(ident, () => <IDcsHandler>[]);
    handlerList.add(handler);
    return toDisposable(() {
      final handlerIndex = handlerList.indexOf(handler);
      if (handlerIndex != -1) {
        handlerList.removeAt(handlerIndex);
      }
    });
  }

  @override
  void clearHandler(int ident) {
    _handlers.remove(ident);
  }

  @override
  void setHandlerFallback(DcsFallbackHandlerType handler) {
    _handlerFb = handler;
  }

  @override
  void reset() {
    // force cleanup leftover handlers
    if (_active.isNotEmpty) {
      for (
        var j = _stack.paused ? _stack.loopPosition - 1 : _active.length - 1;
        j >= 0;
        --j
      ) {
        _active[j].unhook(false);
      }
    }
    _stack.paused = false;
    _active = _emptyHandlers;
    _ident = 0;
  }

  @override
  void hook(int ident, IParams params) {
    // always reset leftover handlers
    reset();
    _ident = ident;
    _active = _handlers[ident] ?? _emptyHandlers;
    if (_active.isEmpty) {
      _handlerFb(_ident, 'HOOK', params);
    } else {
      for (var j = _active.length - 1; j >= 0; j--) {
        _active[j].hook(params);
      }
    }
  }

  @override
  void put(Uint32List data, int start, int end) {
    if (_active.isEmpty) {
      _handlerFb(_ident, 'PUT', utf32ToString(data, start, end));
    } else {
      for (var j = _active.length - 1; j >= 0; j--) {
        _active[j].put(data, start, end);
      }
    }
  }

  /// Ends the DCS command; [promiseResult] (default `true`) is the resolved
  /// value of the future returned by the previous call, when resuming.
  @override
  Future<bool>? unhook(bool success, [bool? promiseResult]) {
    if (_active.isEmpty) {
      _handlerFb(_ident, 'UNHOOK', success);
    } else {
      FutureOr<bool> handlerResult = false;
      var j = _active.length - 1;
      var fallThrough = false;
      if (_stack.paused) {
        j = _stack.loopPosition - 1;
        handlerResult = promiseResult ?? true;
        fallThrough = _stack.fallThrough;
        _stack.paused = false;
      }
      if (!fallThrough && handlerResult == false) {
        for (; j >= 0; j--) {
          handlerResult = _active[j].unhook(success);
          if (handlerResult == true) {
            break;
          } else if (handlerResult is Future<bool>) {
            _stack.paused = true;
            _stack.loopPosition = j;
            _stack.fallThrough = false;
            return handlerResult;
          }
        }
        j--;
      }
      // cleanup left over handlers (fallThrough for async)
      for (; j >= 0; j--) {
        handlerResult = _active[j].unhook(false);
        if (handlerResult is Future<bool>) {
          _stack.paused = true;
          _stack.loopPosition = j;
          _stack.fallThrough = true;
          return handlerResult;
        }
      }
    }
    _active = _emptyHandlers;
    _ident = 0;
    return null;
  }
}

// predefine empty params as [0] (ZDM)
final Params _emptyParams = Params()..addParam(0);

/// Convenient class to create a DCS handler from a single callback function.
///
/// Note: The payload is limited to [ParserConstants.payloadLimit]
/// (hardcoded).
class DcsHandler implements IDcsHandler {
  DcsHandler(this._handler);

  /// Upstream private static `_payloadLimit`; public for the ported tests.
  static int payloadLimit = ParserConstants.payloadLimit;

  final LimitedStringBuilder _data = LimitedStringBuilder(payloadLimit);
  IParams _params = _emptyParams;
  bool _hitLimit = false;
  final FutureOr<bool> Function(String data, IParams params) _handler;

  @override
  void hook(IParams params) {
    // since we need to preserve params until `unhook`, we have to clone it
    // (only borrowed from parser and spans multiple parser states)
    // perf optimization:
    // clone only, if we have non empty params, otherwise stick with default
    _params = (params.length > 1 || params.params[0] != 0)
        ? params.clone()
        : _emptyParams;
    _data.reset();
    _hitLimit = false;
  }

  @override
  void put(Uint32List data, int start, int end) {
    if (_hitLimit) {
      return;
    }
    if (_data.append(utf32ToString(data, start, end))) {
      _hitLimit = true;
    }
  }

  @override
  FutureOr<bool> unhook(bool success) {
    FutureOr<bool> ret = false;
    if (_hitLimit) {
      ret = false;
    } else if (success) {
      ret = _handler(_data.toString(), _params);
      if (ret is Future<bool>) {
        // need to hold data and params until `ret` got resolved
        // dont care for errors, data will be freed anyway on next start
        return ret.then((res) {
          _params = _emptyParams;
          _data.reset();
          _hitLimit = false;
          return res;
        });
      }
    }
    _params = _emptyParams;
    _data.reset();
    _hitLimit = false;
    return ret;
  }
}
