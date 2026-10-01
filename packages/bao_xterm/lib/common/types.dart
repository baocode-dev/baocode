// Copyright (c) 2018 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/LICENSE.txt.
// Ported from xterm.js src/common/Types.ts (c58ea36).
//
// `IDisposable`, `ITerminalOptions` and `IWindowOptions` are the declarations
// of lifecycle.dart and the typings, re-exported here.

import 'dart:async';
import 'dart:typed_data';

import '../typings/xterm.dart' show IFunctionIdentifier;
import 'event.dart';
import 'lifecycle.dart';

export '../typings/xterm.dart' show ITerminalOptions, IWindowOptions;
export 'lifecycle.dart' show IDisposable;

/// Sequence params serialized to lists: each element is an `int`, or a
/// `List<int>` of a param followed by its sub params.
typedef ParamsArray = List<Object>;

/// Interface of the Params storage class.
abstract interface class IParams {
  /// From the constructor.
  abstract int maxLength;
  abstract int maxSubParamsLength;

  /// Param values and their count.
  abstract Int32List params;
  abstract int length;

  IParams clone();
  ParamsArray toArray();
  void reset();
  void resetZdm();
  void addParam(int value);
  void addSubParam(int value);
  bool hasSubParams(int idx);
  Int32List? getSubParams(int idx);
  Map<int, Int32List> getSubParamsAll();
}

/// `'block'`, `'underline'` or `'bar'`.
typedef CursorStyle = String;

/// `'outline'`, `'block'`, `'bar'`, `'underline'` or `'none'`.
typedef CursorInactiveStyle = String;

/// A listener of any arguments.
typedef XtermListener = Function;

/// A keyboard event that does not depend on the DOM; the DOM's
/// `KeyboardEvent` has these fields.
class IKeyboardEvent {
  IKeyboardEvent({
    required this.altKey,
    required this.ctrlKey,
    required this.shiftKey,
    required this.metaKey,
    required this.keyCode,
    required this.key,
    required this.type,
    required this.code,
  });

  bool altKey;
  bool ctrlKey;
  bool shiftKey;
  bool metaKey;

  /// Deprecated in the DOM, see `KeyboardEvent.keyCode`.
  int keyCode;
  String key;
  String type;
  String code;
}

class IScrollEvent {
  IScrollEvent({required this.position});

  int position;
}

abstract final class KeyboardResultType {
  static const int sendKey = 0;
  static const int selectAll = 1;
  static const int pageUp = 2;
  static const int pageDown = 3;
}

class IKeyboardResult {
  IKeyboardResult({required this.type, required this.cancel, this.key});

  /// A [KeyboardResultType].
  int type;
  bool cancel;
  String? key;
}

/// A character set: replacement strings by character.
typedef ICharset = Map<String, String>;

/// A color as CSS string and as RGBA number.
class IColor {
  const IColor({required this.css, required this.rgba});

  final String css;

  /// 32-bit unsigned int with r, g, b and a in its bytes, from high to low.
  final int rgba;

  @override
  bool operator ==(Object other) =>
      other is IColor && other.css == css && other.rgba == rgba;

  @override
  int get hashCode => Object.hash(css, rgba);

  @override
  String toString() => 'IColor(css: $css, rgba: 0x${rgba.toRadixString(16)})';
}

/// `[red, green, blue]`, each 0-255.
typedef IColorRGB = List<int>;

/// Tracks the current hyperlink. Since these are treated as extended
/// attributes, they are passed on to the linkifier when anything is printed,
/// so the link is tracked even when the cursor moves around unexpectedly.
class IOscLinkData {
  IOscLinkData({this.id, required this.uri});

  String? id;
  String uri;
}

class IModes {
  IModes({required this.insertMode});

  bool insertMode;
}

class IDecPrivateModes {
  IDecPrivateModes({
    required this.applicationCursorKeys,
    required this.applicationKeypad,
    required this.bracketedPasteMode,
    required this.colorSchemeUpdates,
    required this.cursorBlink,
    required this.cursorStyle,
    required this.origin,
    required this.reverseWraparound,
    required this.sendFocus,
    required this.synchronizedOutput,
    required this.win32InputMode,
    required this.wraparound,
  });

  bool applicationCursorKeys;
  bool applicationKeypad;
  bool bracketedPasteMode;
  bool colorSchemeUpdates;
  bool? cursorBlink;
  CursorStyle? cursorStyle;
  bool origin;
  bool reverseWraparound;
  bool sendFocus;
  bool synchronizedOutput;
  bool win32InputMode;

  /// Defaults: xterm - true, vt100 - false.
  bool wraparound;
}

/// Kitty keyboard protocol state: per-screen stacks of enhancement flags.
class IKittyKeyboardState {
  IKittyKeyboardState({
    required this.flags,
    required this.mainFlags,
    required this.altFlags,
    required this.mainStack,
    required this.altStack,
  });

  /// Current active enhancement flags (for the current screen).
  int flags;

  /// Saved flags for the main screen while the alternate one is active.
  int mainFlags;

  /// Saved flags for the alternate screen while the main one is active.
  int altFlags;

  /// Stack of flags for the main screen.
  List<int> mainStack;

  /// Stack of flags for the alternate screen.
  List<int> altStack;
}

class IRowRange {
  IRowRange({required this.start, required this.end});

  int start;
  int end;
}

/// Mouse buttons of core mouse events.
abstract final class CoreMouseButton {
  static const int left = 0;
  static const int middle = 1;
  static const int right = 2;
  static const int none = 3;
  static const int wheel = 4;
  // Additional buttons 1..8, untested.
  static const int aux1 = 8;
  static const int aux2 = 9;
  static const int aux3 = 10;
  static const int aux4 = 11;
  static const int aux5 = 12;
  static const int aux6 = 13;
  static const int aux7 = 14;
  static const int aux8 = 15;
}

abstract final class CoreMouseAction {
  /// Buttons, wheel.
  static const int up = 0;

  /// Buttons, wheel.
  static const int down = 1;

  /// Wheel only.
  static const int left = 2;

  /// Wheel only.
  static const int right = 3;

  /// Buttons only.
  static const int move = 32;
}

/// A mouse event in the core.
class ICoreMouseEvent {
  ICoreMouseEvent({
    required this.col,
    required this.row,
    required this.x,
    required this.y,
    required this.button,
    required this.action,
    this.ctrl,
    this.alt,
    this.shift,
  });

  /// Column (zero based).
  int col;

  /// Row (zero based).
  int row;

  /// Pixel positions.
  int x;
  int y;

  /// The [CoreMouseButton] of the action. The tracking protocols cannot report
  /// several buttons at once; the wheel counts as a button. Invalid
  /// combinations (like move + wheel) are silently ignored by the
  /// MouseStateService.
  int button;

  /// A [CoreMouseAction].
  int action;

  /// Modifier states; protocols add or ignore them by their restrictions.
  bool? ctrl;
  bool? alt;
  bool? shift;
}

/// Which events a mouse protocol wants forwarded to the MouseStateService, as
/// bit flags.
abstract final class CoreMouseEventType {
  static const int none = 0;

  /// Any mousedown event.
  static const int down = 1;

  /// Any mouseup event.
  static const int up = 2;

  /// Any mousemove event while a button is held.
  static const int drag = 4;

  /// Any mousemove event without a button.
  static const int move = 8;

  /// Any wheel event.
  static const int wheel = 16;
}

/// A mouse protocol, registered and activated at the MouseStateService.
///
/// [events] lists the needed events ([CoreMouseEventType] flags) as a hint
/// for the browser component; [restrict] applies protocol specific
/// restrictions like disallowed modifiers or invalid event types.
class ICoreMouseProtocol {
  ICoreMouseProtocol({required this.events, required this.restrict});

  int events;
  bool Function(ICoreMouseEvent e) restrict;
}

/// Encodes an event that passed the protocol's restrictions; an empty string
/// suppresses the report.
typedef CoreMouseEncoding = String Function(ICoreMouseEvent event);

/// Color events from common, used for OSC 4/10/11/12 and 104/110/111/112.
abstract final class ColorRequestType {
  static const int report = 0;
  static const int set = 1;
  static const int restore = 2;
}

/// A number from 0 to 255.
typedef ColorIndex = int;

/// A [ColorIndex] or a [SpecialColorIndex].
typedef AllColorIndex = int;

abstract final class SpecialColorIndex {
  static const int foreground = 256;
  static const int background = 257;
  static const int cursor = 258;
}

/// One of [IColorReportRequest], [IColorSetRequest] and
/// [IColorRestoreRequest] (a TypeScript union upstream).
sealed class IColorRequest {
  /// The [ColorRequestType].
  int get type;
}

class IColorReportRequest implements IColorRequest {
  IColorReportRequest({required this.index});

  @override
  int get type => ColorRequestType.report;
  AllColorIndex index;
}

class IColorSetRequest implements IColorRequest {
  IColorSetRequest({required this.index, required this.color});

  @override
  int get type => ColorRequestType.set;
  AllColorIndex index;
  IColorRGB color;
}

class IColorRestoreRequest implements IColorRequest {
  IColorRestoreRequest({this.index});

  @override
  int get type => ColorRequestType.restore;
  AllColorIndex? index;
}

typedef IColorEvent = List<IColorRequest>;

/// Calls the parser and handles actions generated by the parser.
///
/// `parse` returns a future only when a handler went async and
/// [promiseResult] is set (upstream's `void | Promise<boolean>`).
abstract interface class IInputHandler {
  IEvent<String> get onTitleChange;

  /// [data] is a `String` or a `Uint8List`.
  Future<bool>? parse(Object data, [bool? promiseResult]);
  void print(Uint32List data, int start, int end);
  IDisposable registerCsiHandler(
    IFunctionIdentifier id,
    FutureOr<bool> Function(IParams params) callback,
  );
  IDisposable registerDcsHandler(
    IFunctionIdentifier id,
    FutureOr<bool> Function(String data, IParams param) callback,
  );
  IDisposable registerEscHandler(
    IFunctionIdentifier id,
    FutureOr<bool> Function() callback,
  );
  IDisposable registerOscHandler(
    int ident,
    FutureOr<bool> Function(String data) callback,
  );
  IDisposable registerApcHandler(
    IFunctionIdentifier id,
    FutureOr<bool> Function(String data) callback,
  );

  /// C0 BEL
  bool bell();

  /// C0 LF
  bool lineFeed();

  /// C0 CR
  bool carriageReturn();

  /// C0 BS
  bool backspace();

  /// C0 HT
  bool tab();

  /// C0 SO
  bool shiftOut();

  /// C0 SI
  bool shiftIn();

  /// CSI @
  bool insertChars(IParams params);

  /// CSI SP @
  bool scrollLeft(IParams params);

  /// CSI A
  bool cursorUp(IParams params);

  /// CSI SP A
  bool scrollRight(IParams params);

  /// CSI B
  bool cursorDown(IParams params);

  /// CSI C
  bool cursorForward(IParams params);

  /// CSI D
  bool cursorBackward(IParams params);

  /// CSI E
  bool cursorNextLine(IParams params);

  /// CSI F
  bool cursorPrecedingLine(IParams params);

  /// CSI G
  bool cursorCharAbsolute(IParams params);

  /// CSI H
  bool cursorPosition(IParams params);

  /// CSI I
  bool cursorForwardTab(IParams params);

  /// CSI J
  bool eraseInDisplay(IParams params);

  /// CSI K
  bool eraseInLine(IParams params);

  /// CSI L
  bool insertLines(IParams params);

  /// CSI M
  bool deleteLines(IParams params);

  /// CSI P
  bool deleteChars(IParams params);

  /// CSI S
  bool scrollUp(IParams params);

  /// CSI T
  bool scrollDown(IParams params, [String? collect]);

  /// CSI X
  bool eraseChars(IParams params);

  /// CSI Z
  bool cursorBackwardTab(IParams params);

  /// CSI `
  bool charPosAbsolute(IParams params);

  /// CSI a
  bool hPositionRelative(IParams params);

  /// CSI b
  bool repeatPrecedingCharacter(IParams params);

  /// CSI c
  bool sendDeviceAttributesPrimary(IParams params);

  /// CSI > c
  bool sendDeviceAttributesSecondary(IParams params);

  /// CSI d
  bool linePosAbsolute(IParams params);

  /// CSI e
  bool vPositionRelative(IParams params);

  /// CSI f
  bool hVPosition(IParams params);

  /// CSI g
  bool tabClear(IParams params);

  /// CSI h
  bool setMode(IParams params, [String? collect]);

  /// CSI l
  bool resetMode(IParams params, [String? collect]);

  /// CSI m
  bool charAttributes(IParams params);

  /// CSI n
  bool deviceStatus(IParams params, [String? collect]);

  /// CSI p
  bool softReset(IParams params, [String? collect]);

  /// CSI q
  bool setCursorStyle(IParams params, [String? collect]);

  /// CSI r
  bool setScrollRegion(IParams params, [String? collect]);

  /// CSI s
  bool saveCursor(IParams params);

  /// CSI u
  bool restoreCursor(IParams params);

  /// CSI ' }
  bool insertColumns(IParams params);

  /// CSI ' ~
  bool deleteColumns(IParams params);

  /// OSC 0, OSC 2
  bool setTitle(String data);

  /// OSC 4
  bool setOrReportIndexedColor(String data);

  /// OSC 10
  bool setOrReportFgColor(String data);

  /// OSC 11
  bool setOrReportBgColor(String data);

  /// OSC 12
  bool setOrReportCursorColor(String data);

  /// OSC 104
  bool restoreIndexedColor(String data);

  /// OSC 110
  bool restoreFgColor(String data);

  /// OSC 111
  bool restoreBgColor(String data);

  /// OSC 112
  bool restoreCursorColor(String data);

  /// ESC E
  bool nextLine();

  /// ESC =
  bool keypadApplicationMode();

  /// ESC >
  bool keypadNumericMode();

  /// ESC % G, ESC % @
  bool selectDefaultCharset();

  /// ESC ( C, ESC ) C, ESC * C, ESC + C, ESC - C, ESC . C, ESC / C
  bool selectCharset(String collectAndFlag);

  /// ESC D
  bool index();

  /// ESC H
  bool tabSet();

  /// ESC M
  bool reverseIndex();

  /// ESC c
  bool fullReset();

  /// ESC n, ESC o, ESC |, ESC }, ESC ~
  bool setgLevel(int level);

  /// ESC # 8
  bool screenAlignmentPattern();
}

class IParseStack {
  IParseStack({
    required this.paused,
    required this.cursorStartX,
    required this.cursorStartY,
    required this.decodedLength,
    required this.position,
  });

  bool paused;
  int cursorStartX;
  int cursorStartY;
  int decodedLength;
  int position;
}
