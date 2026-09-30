// Copyright (c) 2017 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Ported from xterm.js src/common/parser/Types.ts (c58ea36).
//
// Upstream's `IParamsConstructor` (a constructor and a static `fromArray`) has
// no Dart interface form; `Params` provides both. `IFunctionIdentifier` is the
// typings' declaration (identical to upstream's copy here), re-exported.

import 'dart:async';
import 'dart:typed_data';

import '../../typings/xterm.dart' show IFunctionIdentifier;
import '../types.dart';

export '../../typings/xterm.dart' show IFunctionIdentifier;
export '../types.dart' show IParams, ParamsArray;

/// Internal state of EscapeSequenceParser.
///
/// Used as argument of the error handler to allow introspection at runtime on
/// parse errors. Return it with altered values to recover from faulty states
/// (not yet supported). Set [abort] to `true` to abort the current parsing.
class IParsingState {
  IParsingState({
    required this.position,
    required this.code,
    required this.currentState,
    required this.collect,
    required this.params,
    required this.abort,
  });

  /// Position in the parse string.
  int position;

  /// Actual character code.
  int code;

  /// Current parser state, a `ParserState`.
  int currentState;

  /// Collect buffer with intermediate characters.
  int collect;

  /// Params buffer.
  IParams params;

  /// Should abort (default: false).
  bool abort;
}

// Command handler interfaces.

/// CSI handler; `params` is borrowed.
typedef CsiHandlerType = FutureOr<bool> Function(IParams params);
typedef CsiFallbackHandlerType = void Function(int ident, IParams params);

/// DCS handler.
abstract interface class IDcsHandler {
  /// Called when a DCS command starts. Prepare needed data structures here.
  /// [params] is borrowed.
  void hook(IParams params);

  /// Incoming payload chunk; [data] is borrowed.
  void put(Uint32List data, int start, int end);

  /// End of DCS command. [success] indicates whether the command finished
  /// normally or got aborted, thus final execution of the command should
  /// depend on [success]. To save memory also cleanup data structures here.
  FutureOr<bool> unhook(bool success);
}

/// [action] is `'HOOK'`, `'PUT'` or `'UNHOOK'`; [payload] is null where
/// upstream omits it.
typedef DcsFallbackHandlerType = void Function(
  int ident,
  String action,
  Object? payload,
);

/// ESC handler.
typedef EscHandlerType = FutureOr<bool> Function();
typedef EscFallbackHandlerType = void Function(int identifier);

/// EXECUTE handler; upstream's optional `ident` is never passed, so it is
/// dropped.
typedef ExecuteHandlerType = bool Function();
typedef ExecuteFallbackHandlerType = void Function(int ident);

/// OSC handler.
abstract interface class IOscHandler {
  /// Announces start of this OSC command. Prepare needed data structures
  /// here.
  void start();

  /// Incoming data chunk; [data] is borrowed.
  void put(Uint32List data, int start, int end);

  /// End of OSC command. [success] indicates whether the command finished
  /// normally or got aborted, thus final execution of the command should
  /// depend on [success]. To save memory also cleanup data structures here.
  FutureOr<bool> end(bool success);
}

/// [action] is `'START'`, `'PUT'` or `'END'`; [payload] is null where
/// upstream omits it.
typedef OscFallbackHandlerType = void Function(
  int ident,
  String action,
  Object? payload,
);

/// APC handler.
abstract interface class IApcHandler {
  /// Announces start of this APC command. Prepare needed data structures
  /// here.
  void start();

  /// Incoming data chunk.
  void put(Uint32List data, int start, int end);

  /// End of APC command. [success] indicates whether the command finished
  /// normally or got aborted, thus final execution of the command should
  /// depend on [success]. To save memory also cleanup data structures here.
  FutureOr<bool> end(bool success);
}

/// [action] is `'START'`, `'PUT'` or `'END'`; [payload] is null where
/// upstream omits it.
typedef ApcFallbackHandlerType = void Function(
  int ident,
  String action,
  Object? payload,
);

/// PRINT handler.
typedef PrintHandlerType = void Function(Uint32List data, int start, int end);
typedef PrintFallbackHandlerType = PrintHandlerType;

/// EscapeSequenceParser interface.
///
/// `parse` returns a future only when a handler went async and
/// `promiseResult` is set (upstream's `void | Promise<boolean>`).
abstract interface class IEscapeSequenceParser implements IDisposable {
  /// Preceding grapheme-join-state (`UnicodeCharProperties`).
  ///
  /// Used for joining grapheme clusters across calls to `print`, and by REP
  /// to check if repeating a character is allowed. The parser resets it for
  /// any valid sequence besides text.
  abstract int precedingJoinState;

  /// Resets the parser to its initial state (handlers are kept).
  void reset();

  /// Parses UTF32 codepoints in [data] up to [length].
  Future<bool>? parse(Uint32List data, int length, [bool? promiseResult]);

  /// Gets the string of the numerical function identifier [ident].
  ///
  /// Useful in fallback handlers which expose the low level numerical
  /// function identifier for debugging purposes. A full back translation to
  /// `IFunctionIdentifier` is not implemented.
  String identToString(int ident);

  void setPrintHandler(PrintHandlerType handler);
  void clearPrintHandler();

  IDisposable registerEscHandler(
    IFunctionIdentifier id,
    EscHandlerType handler,
  );
  void clearEscHandler(IFunctionIdentifier id);
  void setEscHandlerFallback(EscFallbackHandlerType handler);

  void setExecuteHandler(String flag, ExecuteHandlerType handler);
  void clearExecuteHandler(String flag);
  void setExecuteHandlerFallback(ExecuteFallbackHandlerType handler);

  IDisposable registerCsiHandler(
    IFunctionIdentifier id,
    CsiHandlerType handler,
  );
  void clearCsiHandler(IFunctionIdentifier id);
  void setCsiHandlerFallback(CsiFallbackHandlerType callback);

  IDisposable registerDcsHandler(IFunctionIdentifier id, IDcsHandler handler);
  void clearDcsHandler(IFunctionIdentifier id);
  void setDcsHandlerFallback(DcsFallbackHandlerType handler);

  IDisposable registerOscHandler(int ident, IOscHandler handler);
  void clearOscHandler(int ident);
  void setOscHandlerFallback(OscFallbackHandlerType handler);

  IDisposable registerApcHandler(IFunctionIdentifier id, IApcHandler handler);
  void clearApcHandler(IFunctionIdentifier id);
  void setApcHandlerFallback(ApcFallbackHandlerType handler);

  void setErrorHandler(IParsingState Function(IParsingState state) handler);
  void clearErrorHandler();
}

/// Subparser interfaces.
///
/// The subparsers are instantiated in `EscapeSequenceParser` and called
/// during `EscapeSequenceParser.parse`.
abstract interface class ISubParser<T, U> implements IDisposable {
  void reset();
  IDisposable registerHandler(int ident, T handler);
  void clearHandler(int ident);
  void setHandlerFallback(U handler);
  void put(Uint32List data, int start, int end);
}

abstract interface class IOscParser
    implements ISubParser<IOscHandler, OscFallbackHandlerType> {
  void start();
  Future<bool>? end(bool success, [bool? promiseResult]);
}

abstract interface class IDcsParser
    implements ISubParser<IDcsHandler, DcsFallbackHandlerType> {
  void hook(int ident, IParams params);
  Future<bool>? unhook(bool success, [bool? promiseResult]);
}

abstract interface class IApcParser
    implements ISubParser<IApcHandler, ApcFallbackHandlerType> {
  void start(int ident);
  Future<bool>? end(bool success, [bool? promiseResult]);
}

/// Handler lists by numeric function identifier (upstream's string-keyed
/// object indexed with numbers).
typedef IHandlerCollection<T> = Map<int, List<T>>;

// Types for async parser support.

/// Type of saved stack state in parser.
abstract final class ParserStackType {
  static const int none = 0;
  static const int fail = 1;
  static const int reset = 2;
  static const int csi = 3;
  static const int esc = 4;
  static const int osc = 5;
  static const int dcs = 6;
  static const int apc = 7;
}

/// Aggregate of resumable handler lists: a `List<CsiHandlerType>` or a
/// `List<EscHandlerType>`.
typedef ResumableHandlersType = List<Function>;

/// Saved stack state of the parser.
class IParserStackState {
  IParserStackState({
    required this.state,
    required this.handlers,
    required this.handlerPos,
    required this.transition,
    required this.chunkPos,
  });

  /// A [ParserStackType].
  int state;
  ResumableHandlersType handlers;
  int handlerPos;
  int transition;
  int chunkPos;
}

/// Saved stack state of a subparser (OSC and DCS).
class ISubParserStackState {
  ISubParserStackState({
    required this.paused,
    required this.loopPosition,
    required this.fallThrough,
  });

  bool paused;
  int loopPosition;
  bool fallThrough;
}
