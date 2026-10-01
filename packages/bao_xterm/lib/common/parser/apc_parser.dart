// Copyright (c) 2025 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Ported from xterm.js src/common/parser/ApcParser.ts (c58ea36).

import 'dart:async';
import 'dart:typed_data';

import '../input/text_decoder.dart';
import '../lifecycle.dart';
import '../string_builder.dart';
import 'constants.dart';
import 'types.dart';

const List<IApcHandler> _emptyHandlers = <IApcHandler>[];

void _noopFallback(int ident, String action, Object? payload) {}

/// APC Parser for handling Application Program Command sequences.
///
/// APC sequences use the format: `ESC _ <identifier><data> ESC \`
///
/// Unlike OSC which uses numeric identifiers (e.g., OSC 1337), APC uses the
/// first character as the identifier (e.g., 'G' for Kitty graphics). The
/// identifier is the character code of the first byte after `ESC _`.
class ApcParser implements IApcParser {
  IHandlerCollection<IApcHandler> _handlers = <int, List<IApcHandler>>{};
  List<IApcHandler> _active = _emptyHandlers;
  int _ident = 0;
  ApcFallbackHandlerType _handlerFb = _noopFallback;
  final ISubParserStackState _stack = ISubParserStackState(
    paused: false,
    loopPosition: 0,
    fallThrough: false,
  );

  /// Registers an APC handler for a specific identifier.
  ///
  /// [ident] is the character code of the first byte (e.g., 0x47 for 'G').
  @override
  IDisposable registerHandler(int ident, IApcHandler handler) {
    final handlerList = _handlers.putIfAbsent(ident, () => <IApcHandler>[]);
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
  void setHandlerFallback(ApcFallbackHandlerType handler) {
    _handlerFb = handler;
  }

  @override
  void dispose() {
    _handlers = <int, List<IApcHandler>>{};
    _handlerFb = _noopFallback;
    _active = _emptyHandlers;
  }

  @override
  void reset() {
    // force cleanup handlers
    if (_active.isNotEmpty) {
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
    _ident = 0;
  }

  @override
  void start(int ident) {
    // always reset leftover handlers
    reset();
    _ident = ident;
    _active = _handlers[ident] ?? _emptyHandlers;
    if (_active.isEmpty) {
      _handlerFb(_ident, 'START', null);
    } else {
      for (var j = _active.length - 1; j >= 0; j--) {
        _active[j].start();
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

  /// Indicates the end of an APC command.
  ///
  /// Whether the APC got aborted or finished normally is indicated by
  /// [success]. [promiseResult] (default `true`) is the resolved value of the
  /// future returned by the previous call, when resuming.
  @override
  Future<bool>? end(bool success, [bool? promiseResult]) {
    if (_active.isEmpty) {
      _handlerFb(_ident, 'END', success);
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
      // cleanup left over handlers (fallThrough for async)
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
    _active = _emptyHandlers;
    _ident = 0;
    return null;
  }
}

/// Convenient class to allow attaching string based handler functions as APC
/// handlers.
class ApcHandler implements IApcHandler {
  ApcHandler(this._handler);

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
