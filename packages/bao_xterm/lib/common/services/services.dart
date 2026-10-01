// Copyright (c) 2019 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/LICENSE.txt.
// Ported from xterm.js src/common/services/Services.ts (c58ea36).
//
// The service interfaces without the dependency injection: no
// `createDecorator` identifiers, no `serviceBrand`, no `IInstantiationService`
// or `IBrandedService`. A service takes the services it depends on as
// constructor parameters.
//
// The options types (`ITerminalOptions`, `ITheme`, `ITerminalQuirks`,
// `IScrollbarOptions`, `IVtExtensions`, `FontWeight`, `LogLevel`) and
// `IUnicodeVersionProvider` are the typings' declarations (identical to
// upstream's copies here), re-exported.

import '../../typings/xterm.dart'
    show
        IDecoration,
        IDecorationOptions,
        IUnicodeVersionProvider,
        RequiredTerminalOptions;
import '../buffer/types.dart';
import '../event.dart';
import '../types.dart';

export '../../typings/xterm.dart'
    show
        FontWeight,
        ILinkHandler,
        ILogger,
        IOverviewRulerOptions,
        IScrollbarOptions,
        ITerminalOptions,
        ITerminalQuirks,
        ITheme,
        IUnicodeVersionProvider,
        IVtExtensions,
        IWindowsPty,
        LogLevel,
        RequiredTerminalOptions;

abstract interface class IBufferService {
  int get cols;
  int get rows;
  IBuffer get buffer;
  IBufferSet get buffers;
  abstract bool isUserScrolling;
  IEvent<IBufferResizeEvent> get onResize;
  IEvent<int> get onScroll;
  void scroll(IAttributeData eraseAttr, [bool? isWrapped]);
  void scrollLines(int disp, [bool? suppressScrollEvent]);
  void resize(int cols, int rows);
  void reset();
}

class IBufferResizeEvent {
  IBufferResizeEvent({
    required this.cols,
    required this.rows,
    required this.colsChanged,
    required this.rowsChanged,
  });

  int cols;
  int rows;
  bool colsChanged;
  bool rowsChanged;
}

abstract interface class IMouseStateService {
  abstract String activeProtocol;
  abstract String activeEncoding;
  bool get areMouseEventsActive;
  void addProtocol(String name, ICoreMouseProtocol protocol);
  void addEncoding(String name, CoreMouseEncoding encoding);
  void reset();

  /// [customWheelEventHandler] receives the DOM `WheelEvent` upstream.
  void setCustomWheelEventHandler(
    bool Function(Object event)? customWheelEventHandler,
  );
  bool allowCustomWheelEvent(Object ev);

  /// Event to announce changes in mouse tracking ([CoreMouseEventType]
  /// flags).
  IEvent<int> get onProtocolChange;
  bool restrictMouseEvent(ICoreMouseEvent event);
  String encodeMouseEvent(ICoreMouseEvent event);
  bool get isDefaultEncoding;
  bool get isPixelEncoding;
}

abstract interface class ICoreService {
  /// Initially the cursor will not be visible until the first time the
  /// terminal is focused.
  abstract bool isCursorInitialized;
  abstract bool isCursorHidden;

  IModes get modes;
  IDecPrivateModes get decPrivateModes;
  IKittyKeyboardState get kittyKeyboard;

  IEvent<String> get onData;
  IEvent<void> get onUserInput;
  IEvent<String> get onBinary;
  IEvent<void> get onRequestScrollToBottom;

  void reset();

  /// Triggers the onData event in the public API.
  ///
  /// [wasUserInput] is whether the data originated from the user (as opposed
  /// to resulting from parsing incoming data). When true this will also
  /// scroll to the bottom of the buffer if the option scrollOnUserInput is
  /// true, and fire the `onUserInput` event (so selection can be cleared).
  void triggerDataEvent(String data, [bool? wasUserInput]);

  /// Triggers the onBinary event in the public API.
  void triggerBinaryEvent(String data);
}

abstract interface class ICharsetService {
  abstract ICharset? charset;
  int get glevel;
  List<ICharset?> get charsets;

  void reset();

  /// Sets the G level of the terminal.
  void setgLevel(int g);

  /// Sets the charset for the given G level of the terminal.
  void setgCharset(int g, ICharset? charset);
}

/// Upstream's numeric log levels (a regular `enum`, compared with `<=`).
abstract final class LogLevelEnum {
  static const int trace = 0;
  static const int debug = 1;
  static const int info = 2;
  static const int warn = 3;
  static const int error = 4;
  static const int off = 5;
}

/// Upstream's rest parameter `...optionalParams` is the list
/// [optionalParams]; an element that is a function is called lazily, only
/// when the message is logged.
abstract interface class ILogService {
  /// A [LogLevelEnum].
  int get logLevel;

  void trace(
    String message, [
    List<Object?> optionalParams = const <Object?>[],
  ]);
  void debug(
    String message, [
    List<Object?> optionalParams = const <Object?>[],
  ]);
  void info(String message, [List<Object?> optionalParams = const <Object?>[]]);
  void warn(String message, [List<Object?> optionalParams = const <Object?>[]]);
  void error(
    String message, [
    List<Object?> optionalParams = const <Object?>[],
  ]);
}

abstract interface class IOptionsService {
  /// Read only access to the raw options object, this is an internal-only
  /// fast path for accessing single options without any validation.
  RequiredTerminalOptions get rawOptions;

  /// Options as exposed through the public API, with validating setters,
  /// which makes it safer but slower. [rawOptions] should be used for pretty
  /// much all internal usage for performance reasons.
  RequiredTerminalOptions get options;

  /// Fires with the key of any option that changes.
  IEvent<String> get onOptionChange;

  /// Adds a listener for when the option [key] changes, called with its new
  /// value; preferred over [onOptionChange] when only a single option is
  /// being listened to.
  IDisposable onSpecificOptionChange<T>(
    String key,
    void Function(T value) listener,
  );

  /// Adds a listener for when any of [keys] changes; preferred over
  /// [onOptionChange] when several options are handled the same way.
  IDisposable onMultipleOptionChange(
    List<String> keys,
    void Function() listener,
  );
}

abstract interface class IOscLinkService {
  /// Registers a link to the service, returning the link ID. The link data is
  /// managed by this service and will be freed when this current cursor
  /// position is trimmed off the buffer.
  int registerLink(IOscLinkData linkData);

  /// Adds a line to a link if needed.
  void addLineToLink(int linkId, int y);

  /// Gets the link data associated with a link ID.
  IOscLinkData? getLinkData(int linkId);
}

/// Width and Grapheme_Cluster_Break properties of a character as a bit mask.
///
/// Bit 0: shouldJoin - should combine with the preceding character. Bit
/// 1..2: wcwidth - see [UnicodeCharWidth]. Bit 3..31: class of character
/// (currently only 4 bits are used), used to determine grapheme clustering -
/// which codepoints are combined into a single compound character.
///
/// Use `UnicodeService.createPropertyValue` to create one;
/// `extractShouldJoin`, `extractWidth` and `extractCharKind` extract the
/// components.
typedef UnicodeCharProperties = int;

/// Width in columns of a character: 0, 1 or 2.
///
/// In a CJK context, "half-width" characters (such as Latin) are width 1,
/// while "full-width" characters (such as Kanji) are 2 columns wide.
/// Combining characters (such as accents) are width 0.
typedef UnicodeCharWidth = int;

abstract interface class IUnicodeService {
  /// Registers a Unicode version provider.
  void register(IUnicodeVersionProvider provider);

  /// Registered Unicode versions.
  List<String> get versions;

  /// Currently active version.
  abstract String activeVersion;

  /// Event triggered when the active version changes.
  IEvent<String> get onChange;

  /// Unicode version dependent.
  UnicodeCharWidth wcwidth(int codepoint);
  int getStringCellWidth(String s);

  /// Returns the character width and type for grapheme clustering.
  ///
  /// If [preceding] != 0, it is the return code from the previous character;
  /// in that case the result specifies if the characters should be joined.
  UnicodeCharProperties charProperties(
    int codepoint,
    UnicodeCharProperties preceding,
  );
}

abstract interface class IDecorationService implements IDisposable {
  Iterable<IInternalDecoration> get decorations;
  IEvent<IInternalDecoration> get onDecorationRegistered;
  IEvent<IInternalDecoration> get onDecorationRemoved;
  IDecoration? registerDecoration(IDecorationOptions decorationOptions);
  void reset();

  /// Triggers a callback over the decorations at a cell (in no particular
  /// order). This uses a callback instead of an iterator as it's typically
  /// used in hot code paths. [layer] is `'bottom'`, `'top'` or null.
  void forEachDecorationAtCell(
    int x,
    int line,
    String? layer,
    void Function(IInternalDecoration decoration) callback,
  );
}

abstract interface class IInternalDecoration implements IDecoration {
  @override
  IDecorationOptions get options;
  IColor? get backgroundColorRGB;
  IColor? get foregroundColorRGB;

  /// Fires the renderer's element (`HTMLElement` upstream).
  Emitter<Object> get onRenderEmitter;

  /// Upstream `_indexedStartLine` (internal): start line for line-index
  /// removal; kept in sync on buffer line shifts.
  abstract int indexedStartLine;
}
