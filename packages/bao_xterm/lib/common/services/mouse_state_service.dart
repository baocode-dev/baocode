// Copyright (c) 2019 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/LICENSE.txt.
// Ported from xterm.js src/common/services/MouseStateService.ts (c58ea36).

import '../event.dart';
import '../lifecycle.dart';
import '../types.dart';
import 'services.dart';

/// Supported default protocols.
final Map<String, ICoreMouseProtocol> _defaultProtocols =
    <String, ICoreMouseProtocol>{
      // NONE
      // Events: none
      // Modifiers: none
      'NONE': ICoreMouseProtocol(
        events: CoreMouseEventType.none,
        restrict: (_) => false,
      ),
      // X10
      // Events: mousedown
      // Modifiers: none
      'X10': ICoreMouseProtocol(
        events: CoreMouseEventType.down,
        restrict: (e) {
          // no wheel, no move, no up
          if (e.button == CoreMouseButton.wheel ||
              e.action != CoreMouseAction.down) {
            return false;
          }
          // no modifiers
          e.ctrl = false;
          e.alt = false;
          e.shift = false;
          return true;
        },
      ),
      // VT200
      // Events: mousedown / mouseup / wheel
      // Modifiers: all
      'VT200': ICoreMouseProtocol(
        events:
            CoreMouseEventType.down |
            CoreMouseEventType.up |
            CoreMouseEventType.wheel,
        restrict: (e) {
          // no move
          if (e.action == CoreMouseAction.move) {
            return false;
          }
          return true;
        },
      ),
      // DRAG
      // Events: mousedown / mouseup / wheel / mousedrag
      // Modifiers: all
      'DRAG': ICoreMouseProtocol(
        events:
            CoreMouseEventType.down |
            CoreMouseEventType.up |
            CoreMouseEventType.wheel |
            CoreMouseEventType.drag,
        restrict: (e) {
          // no move without button
          if (e.action == CoreMouseAction.move &&
              e.button == CoreMouseButton.none) {
            return false;
          }
          return true;
        },
      ),
      // ANY
      // Events: all mouse related events
      // Modifiers: all
      'ANY': ICoreMouseProtocol(
        events:
            CoreMouseEventType.down |
            CoreMouseEventType.up |
            CoreMouseEventType.wheel |
            CoreMouseEventType.drag |
            CoreMouseEventType.move,
        restrict: (_) => true,
      ),
    };

abstract final class _Modifiers {
  static const int shift = 4;
  static const int alt = 8;
  static const int ctrl = 16;
}

// helper for default encoders to generate the event code.
int _eventCode(ICoreMouseEvent e, bool isSGR) {
  var code =
      (e.ctrl == true ? _Modifiers.ctrl : 0) |
      (e.shift == true ? _Modifiers.shift : 0) |
      (e.alt == true ? _Modifiers.alt : 0);
  if (e.button == CoreMouseButton.wheel) {
    code |= 64;
    code |= e.action;
  } else {
    code |= e.button & 3;
    if ((e.button & 4) != 0) {
      code |= 64;
    }
    if ((e.button & 8) != 0) {
      code |= 128;
    }
    if (e.action == CoreMouseAction.move) {
      code |= CoreMouseAction.move;
    } else if (e.action == CoreMouseAction.up && !isSGR) {
      // special case - only SGR can report button on release
      // all others have to go with NONE
      code |= CoreMouseButton.none;
    }
  }
  return code;
}

String _s(int code) => String.fromCharCode(code);

/// Supported default encodings.
final Map<String, CoreMouseEncoding>
_defaultEncodings = <String, CoreMouseEncoding>{
  // DEFAULT - CSI M Pb Px Py
  // Single byte encoding for coords and event code.
  // Can encode values up to 223 (1-based).
  'DEFAULT': (e) {
    final params = <int>[_eventCode(e, false) + 32, e.col + 32, e.row + 32];
    // supress mouse report if we exceed addressible range
    // Note this is handled differently by emulators
    // - xterm:         sends 0;0 coords instead
    // - vte, konsole:  no report
    if (params[0] > 255 || params[1] > 255 || params[2] > 255) {
      return '';
    }
    return '\x1b[M${_s(params[0])}${_s(params[1])}${_s(params[2])}';
  },
  // SGR - CSI < Pb ; Px ; Py M|m
  // No encoding limitation.
  // Can report button on release and works with a well formed sequence.
  'SGR': (e) {
    final final_ =
        (e.action == CoreMouseAction.up && e.button != CoreMouseButton.wheel)
        ? 'm'
        : 'M';
    return '\x1b[<${_eventCode(e, true)};${e.col};${e.row}$final_';
  },
  'SGR_PIXELS': (e) {
    final final_ =
        (e.action == CoreMouseAction.up && e.button != CoreMouseButton.wheel)
        ? 'm'
        : 'M';
    return '\x1b[<${_eventCode(e, true)};${e.x};${e.y}$final_';
  },
};

/// MouseStateService
///
/// Provides mouse tracking reports with different protocols and encodings.
///  - protocols: NONE (default), X10, VT200, DRAG, ANY
///  - encodings: DEFAULT, SGR (UTF8, URXVT removed in #2507)
///
/// Custom protocols/encodings can be added by `addProtocol` / `addEncoding`.
/// To activate a protocol/encoding, set `activeProtocol` / `activeEncoding`.
/// Switching a protocol will send a notification event `onProtocolChange`
/// with a list of needed events to track.
///
/// The service handles the mouse tracking state and decides whether to send
/// a tracking report to the backend based on protocol and encoding
/// limitations. To send a mouse event call `triggerMouseEvent`.
class MouseStateService extends Disposable implements IMouseStateService {
  MouseStateService() {
    _onProtocolChange = register(Emitter<int>());
    onProtocolChange = _onProtocolChange.event;

    // register default protocols and encodings
    for (final name in _defaultProtocols.keys) {
      addProtocol(name, _defaultProtocols[name]!);
    }
    for (final name in _defaultEncodings.keys) {
      addEncoding(name, _defaultEncodings[name]!);
    }
    // call reset to set defaults
    reset();
  }

  final Map<String, ICoreMouseProtocol> _protocols =
      <String, ICoreMouseProtocol>{};
  final Map<String, CoreMouseEncoding> _encodings =
      <String, CoreMouseEncoding>{};
  String _activeProtocol = '';
  String _activeEncoding = '';
  bool Function(Object event)? _customWheelEventHandler;

  /// Upstream private `_protocols`; public for the ported tests.
  Map<String, ICoreMouseProtocol> get protocols => _protocols;

  /// Upstream private `_encodings`; public for the ported tests.
  Map<String, CoreMouseEncoding> get encodings => _encodings;

  late final Emitter<int> _onProtocolChange;

  /// Fires the [CoreMouseEventType] flags of the new protocol.
  @override
  late final IEvent<int> onProtocolChange;

  @override
  void addProtocol(String name, ICoreMouseProtocol protocol) {
    _protocols[name] = protocol;
  }

  @override
  void addEncoding(String name, CoreMouseEncoding encoding) {
    _encodings[name] = encoding;
  }

  @override
  String get activeProtocol {
    return _activeProtocol;
  }

  @override
  bool get areMouseEventsActive {
    return _protocols[_activeProtocol]!.events != 0;
  }

  @override
  set activeProtocol(String name) {
    final protocol = _protocols[name];
    if (protocol == null) {
      throw ArgumentError('unknown protocol "$name"');
    }
    _activeProtocol = name;
    _onProtocolChange.fire(protocol.events);
  }

  @override
  String get activeEncoding {
    return _activeEncoding;
  }

  @override
  set activeEncoding(String name) {
    if (_encodings[name] == null) {
      throw ArgumentError('unknown encoding "$name"');
    }
    _activeEncoding = name;
  }

  @override
  void reset() {
    activeProtocol = 'NONE';
    activeEncoding = 'DEFAULT';
  }

  /// [customWheelEventHandler] receives the DOM `WheelEvent` upstream.
  @override
  void setCustomWheelEventHandler(
    bool Function(Object event)? customWheelEventHandler,
  ) {
    _customWheelEventHandler = customWheelEventHandler;
  }

  @override
  bool allowCustomWheelEvent(Object ev) {
    final handler = _customWheelEventHandler;
    return handler != null ? handler(ev) != false : true;
  }

  @override
  bool restrictMouseEvent(ICoreMouseEvent e) {
    return _protocols[_activeProtocol]!.restrict(e);
  }

  @override
  String encodeMouseEvent(ICoreMouseEvent e) {
    return _encodings[_activeEncoding]!(e);
  }

  @override
  bool get isDefaultEncoding {
    return _activeEncoding == 'DEFAULT';
  }

  @override
  bool get isPixelEncoding {
    return _activeEncoding == 'SGR_PIXELS';
  }
}
