// Copyright (c) 2019 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/LICENSE.txt.
// Ported from xterm.js src/common/parser/OscParser.ts (c58ea36).

import 'dart:async';
import 'dart:typed_data';

import '../input/text_decoder.dart';
import '../lifecycle.dart';
import '../string_builder.dart';
import 'constants.dart';
import 'types.dart';

const List<IOscHandler> _emptyHandlers = <IOscHandler>[];

void _noopFallback(int ident, String action, Object? payload) {}

class OscParser implements IOscParser {
  int _state = OscState.start;
  List<IOscHandler> _active = _emptyHandlers;
  int _id = -1;
  IHandlerCollection<IOscHandler> _handlers = <int, List<IOscHandler>>{};
  OscFallbackHandlerType _handlerFb = _noopFallback;
  final ISubParserStackState _stack = ISubParserStackState(
    paused: false,
    loopPosition: 0,
    fallThrough: false,
  );

  @override
  IDisposable registerHandler(int ident, IOscHandler handler) {
    final handlerList = _handlers.putIfAbsent(ident, () => <IOscHandler>[]);
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
  void setHandlerFallback(OscFallbackHandlerType handler) {
    _handlerFb = handler;
  }

  @override
  void dispose() {
    _handlers = <int, List<IOscHandler>>{};
    _handlerFb = _noopFallback;
    _active = _emptyHandlers;
  }

  @override
  void reset() {
    // force cleanup handlers if payload was already sent
    if (_state == OscState.payload) {
      for (
        var j = _stack.paused ? _stack.loopPosition - 1 : _active.length - 1;
        j >= 0;
        --j
      ) {
        _active[j].end(false);
      }
    }
    _stack.paused = false;
    _active = _emptyHandlers;
    _id = -1;
    _state = OscState.start;
  }

  void _start() {
    _active = _handlers[_id] ?? _emptyHandlers;
    if (_active.isEmpty) {
      _handlerFb(_id, 'START', null);
    } else {
      for (var j = _active.length - 1; j >= 0; j--) {
        _active[j].start();
      }
    }
  }

  void _put(Uint32List data, int start, int end) {
    if (_active.isEmpty) {
      _handlerFb(_id, 'PUT', utf32ToString(data, start, end));
    } else {
      for (var j = _active.length - 1; j >= 0; j--) {
        _active[j].put(data, start, end);
      }
    }
  }

  @override
  void start() {
    // always reset leftover handlers
    reset();
    _state = OscState.id;
  }

  /// Puts data to the current OSC command.
  ///
  /// Expects the identifier of the OSC command in the form
  /// `OSC id ; payload ST/BEL`. Payload chunks are not further processed and
  /// get directly passed to the handlers.
  @override
  void put(Uint32List data, int start, int end) {
    if (_state == OscState.abort) {
      return;
    }
    if (_state == OscState.id) {
      while (start < end) {
        final code = data[start++];
        if (code == 0x3b) {
          _state = OscState.payload;
          _start();
          break;
        }
        if (code < 0x30 || 0x39 < code) {
          _state = OscState.abort;
          return;
        }
        if (_id == -1) {
          _id = 0;
        }
        _id = _id * 10 + code - 48;
      }
    }
    if (_state == OscState.payload && end - start > 0) {
      _put(data, start, end);
    }
  }

  /// Indicates the end of an OSC command.
  ///
  /// Whether the OSC got aborted or finished normally is indicated by
  /// [success]. [promiseResult] (default `true`) is the resolved value of the
  /// future returned by the previous call, when resuming.
  @override
  Future<bool>? end(bool success, [bool? promiseResult]) {
    if (_state == OscState.start) {
      return null;
    }
    // do nothing if command was faulty
    if (_state != OscState.abort) {
      // if we are still in ID state and get an early end
      // means that the command has no payload thus we still have
      // to announce START and send END right after
      if (_state == OscState.id) {
        _start();
      }

      if (_active.isEmpty) {
        _handlerFb(_id, 'END', success);
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
            handlerResult = _active[j].end(success);
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
        // cleanup left over handlers
        // we always have to call .end for proper cleanup,
        // here we use `success` to indicate whether a handler should execute
        for (; j >= 0; j--) {
          handlerResult = _active[j].end(false);
          if (handlerResult is Future<bool>) {
            _stack.paused = true;
            _stack.loopPosition = j;
            _stack.fallThrough = true;
            return handlerResult;
          }
        }
      }
    }
    _active = _emptyHandlers;
    _id = -1;
    _state = OscState.start;
    return null;
  }
}

/// Convenient class to allow attaching string based handler functions as OSC
/// handlers.
class OscHandler implements IOscHandler {
  OscHandler(this._handler);

  /// Upstream private static `_payloadLimit`; public for the ported tests.
  static int payloadLimit = ParserConstants.payloadLimit;

  final LimitedStringBuilder _data = LimitedStringBuilder(payloadLimit);
  bool _hitLimit = false;
  final FutureOr<bool> Function(String data) _handler;

  @override
  void start() {
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
  FutureOr<bool> end(bool success) {
    FutureOr<bool> ret = false;
    if (_hitLimit) {
      ret = false;
    } else if (success) {
      ret = _handler(_data.toString());
      if (ret is Future<bool>) {
        // need to hold data until `ret` got resolved
        // dont care for errors, data will be freed anyway on next start
        return ret.then((res) {
          _data.reset();
          _hitLimit = false;
          return res;
        });
      }
    }
    _data.reset();
    _hitLimit = false;
    return ret;
  }
}
