// Copyright (c) 2021 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/LICENSE.txt.
// Ported from xterm.js src/common/public/ParserApi.ts (c58ea36).
//
// The deprecated `add*Handler` aliases are kept, as upstream keeps them; they
// are not part of the typings' `IParser`.

import 'dart:async';

import '../../typings/xterm.dart' as api;
import '../core_terminal.dart';
import '../lifecycle.dart';
import '../parser/types.dart';

class ParserApi implements api.IParser {
  ParserApi(this._core);

  final ICoreTerminal _core;

  @override
  IDisposable registerCsiHandler(
    IFunctionIdentifier id,
    FutureOr<bool> Function(List<Object> params) callback,
  ) {
    return _core.registerCsiHandler(
      id,
      (IParams params) => callback(params.toArray()),
    );
  }

  IDisposable addCsiHandler(
    IFunctionIdentifier id,
    FutureOr<bool> Function(List<Object> params) callback,
  ) {
    return registerCsiHandler(id, callback);
  }

  @override
  IDisposable registerDcsHandler(
    IFunctionIdentifier id,
    FutureOr<bool> Function(String data, List<Object> param) callback,
  ) {
    return _core.registerDcsHandler(
      id,
      (String data, IParams params) => callback(data, params.toArray()),
    );
  }

  IDisposable addDcsHandler(
    IFunctionIdentifier id,
    FutureOr<bool> Function(String data, List<Object> param) callback,
  ) {
    return registerDcsHandler(id, callback);
  }

  @override
  IDisposable registerEscHandler(
    IFunctionIdentifier id,
    FutureOr<bool> Function() handler,
  ) {
    return _core.registerEscHandler(id, handler);
  }

  IDisposable addEscHandler(
    IFunctionIdentifier id,
    FutureOr<bool> Function() handler,
  ) {
    return registerEscHandler(id, handler);
  }

  @override
  IDisposable registerOscHandler(
    int ident,
    FutureOr<bool> Function(String data) callback,
  ) {
    return _core.registerOscHandler(ident, callback);
  }

  IDisposable addOscHandler(
    int ident,
    FutureOr<bool> Function(String data) callback,
  ) {
    return registerOscHandler(ident, callback);
  }

  @override
  IDisposable registerApcHandler(
    IFunctionIdentifier id,
    FutureOr<bool> Function(String data) callback,
  ) {
    return _core.registerApcHandler(id, callback);
  }
}
