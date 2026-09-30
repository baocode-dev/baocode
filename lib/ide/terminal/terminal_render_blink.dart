// Copyright (c) 2017 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Ported from xterm.js addons/addon-webgl/src/CursorBlinkStateManager.ts and
// src/browser/renderer/shared/TextBlinkStateManager.ts (c58ea36).
//
// Deviation: a restart of the cursor's blinking restarts its timers at once;
// upstream defers that to the next tick of its interval, to spare the
// browser's timers.

import 'dart:async';

/// Upstream `RendererConstants.CURSOR_BLINK_IDLE_TIMEOUT`: the idle time
/// after which the cursor stops blinking.
const Duration cursorBlinkIdleTimeout = Duration(minutes: 5);

/// The time between cursor blinks.
const Duration cursorBlinkInterval = Duration(milliseconds: 600);

/// Whether a blinking cursor shows, while the terminal is focused.
class TerminalCursorBlink {
  TerminalCursorBlink(this._renderCallback, {required bool isFocused}) {
    if (isFocused) {
      _restartInterval();
      _resetIdleTimer();
    }
  }

  final void Function() _renderCallback;

  bool isCursorVisible = true;
  Timer? _blinkStartTimeout;
  Timer? _blinkInterval;
  Timer? _idleTimeout;
  bool _isIdlePaused = false;

  bool get isPaused => _blinkStartTimeout == null && _blinkInterval == null;

  void dispose() => _clearTimers();

  /// Shows the cursor and blinks it afresh, as on input or a click.
  void restartBlinkAnimation() {
    if (_isIdlePaused) {
      _resetIdleTimer();
    }
    if (isPaused) {
      return;
    }
    // Force a cursor render to ensure it's visible and in the correct position
    isCursorVisible = true;
    _restartInterval();
    _renderCallback();
  }

  void _restartInterval() {
    _blinkInterval?.cancel();
    _blinkInterval = null;
    _blinkStartTimeout?.cancel();
    // Hide the cursor after an interval, then invert it every interval.
    _blinkStartTimeout = Timer(cursorBlinkInterval, () {
      _blinkStartTimeout = null;
      isCursorVisible = false;
      _renderCallback();
      _blinkInterval = Timer.periodic(cursorBlinkInterval, (_) {
        isCursorVisible = !isCursorVisible;
        _renderCallback();
      });
    });
  }

  /// On blur: the cursor shows, still.
  void pause() {
    isCursorVisible = true;
    _isIdlePaused = false;
    _clearTimers();
  }

  /// On focus.
  void resume() {
    // Clear out any existing timers just in case
    pause();
    _restartInterval();
    _resetIdleTimer();
    restartBlinkAnimation();
  }

  void _resetIdleTimer() {
    _isIdlePaused = false;
    _idleTimeout?.cancel();
    _idleTimeout = Timer(cursorBlinkIdleTimeout, _stopBlinkingDueToIdle);
  }

  void _stopBlinkingDueToIdle() {
    // Make cursor visible and stop blinking
    isCursorVisible = true;
    _isIdlePaused = true;
    _blinkInterval?.cancel();
    _blinkInterval = null;
    _blinkStartTimeout?.cancel();
    _blinkStartTimeout = null;
    _idleTimeout = null;
    // Trigger a render to show the cursor in its final visible state
    _renderCallback();
  }

  void _clearTimers() {
    _blinkInterval?.cancel();
    _blinkInterval = null;
    _blinkStartTimeout?.cancel();
    _blinkStartTimeout = null;
    _idleTimeout?.cancel();
    _idleTimeout = null;
  }
}

/// Whether blinking text (SGR 5) shows: it alternates every
/// `blinkIntervalDuration` while such text is in view.
class TerminalTextBlink {
  TerminalTextBlink(this._renderCallback);

  final void Function() _renderCallback;
  int _intervalDuration = 0;
  Timer? _interval;
  bool _blinkOn = true;
  bool _needsBlinkInViewport = false;
  bool _isViewportVisible = true;

  bool get isBlinkOn => _blinkOn;

  bool get isEnabled => _intervalDuration > 0;

  void dispose() => _clearInterval();

  void setNeedsBlinkInViewport(bool needsBlinkInViewport) {
    if (_needsBlinkInViewport == needsBlinkInViewport) {
      return;
    }
    _needsBlinkInViewport = needsBlinkInViewport;
    _updateIntervalState();
  }

  void setViewportVisible(bool isVisible) {
    if (_isViewportVisible == isVisible) {
      return;
    }
    _isViewportVisible = isVisible;
    _updateIntervalState();
  }

  /// [duration] in milliseconds; 0 turns blinking off.
  void setIntervalDuration(int duration) {
    if (duration == _intervalDuration) {
      return;
    }
    _intervalDuration = duration;
    _clearInterval();
    _updateIntervalState();
  }

  void _updateIntervalState() {
    final shouldBlink =
        _intervalDuration > 0 && _needsBlinkInViewport && _isViewportVisible;
    if (shouldBlink) {
      if (_interval != null) {
        return;
      }
      final wasBlinkOn = _blinkOn;
      _blinkOn = true;
      _interval = Timer.periodic(Duration(milliseconds: _intervalDuration), (
        _,
      ) {
        _blinkOn = !_blinkOn;
        _renderCallback();
      });
      if (!wasBlinkOn) {
        _renderCallback();
      }
      return;
    }
    _clearInterval();
    if (!_blinkOn) {
      _blinkOn = true;
      _renderCallback();
    }
  }

  void _clearInterval() {
    _interval?.cancel();
    _interval = null;
  }
}
