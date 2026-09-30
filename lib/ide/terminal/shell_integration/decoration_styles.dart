/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// How a command's decoration looks: its status (running, succeeded, failed)
// with the icon and color for it, the text of its hover, and its size.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/contrib/terminal/browser/xterm/decorationStyles.ts, with
// the icons of src/vs/workbench/contrib/terminal/browser/terminalIcons.ts,
// the colors of the terminal.css rules for `.terminal-command-decoration`
// and `getDurationString` from src/vs/base/common/date.ts.
//
// The CSS classes are kept as names (`classNames`); the color they give is
// [decorationColorOf]. `updateLayout`, which styles an element, is
// [decorationLayout], which says the sizes.

import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter/widgets.dart' show IconData;

import '../../../theme/codicons.dart';
import '../../ide_dates.dart';
import '../terminal_colors.dart';
import 'capabilities/capabilities.dart';

/// The decoration's size in pixels at the default font size.
const decorationDefaultDimension = 16.0;

/// How far left of the grid the decoration sits, in pixels at the default
/// font size: into the terminal's 20px left padding.
const decorationMarginLeft = -17.0;

/// Upstream `DecorationSelector`: the CSS classes of a decoration.
abstract final class DecorationSelector {
  static const commandDecoration = 'terminal-command-decoration';
  static const hide = 'hide';
  static const errorColor = 'error';
  static const defaultColor = 'default-color';

  /// Not interactive (`pointer-events: none`), in the default color.
  static const defaultClass = 'default';
  static const codicon = 'codicon';
  static const xtermDecoration = 'xterm-decoration';
  static const overviewRuler = '.xterm-decoration-overview-ruler';

  /// Upstream adds the literal `'success'`.
  static const success = 'success';
}

/// Icon for a terminal decoration mark.
const terminalDecorationMark = Codicons.circleSmallFilled;

/// Icon for a terminal decoration of a command that was incomplete.
const terminalDecorationIncomplete = Codicons.circle;

/// Icon for a terminal decoration of a command that errored.
const terminalDecorationError = Codicons.errorSmall;

/// Icon for a terminal decoration of a command that was successful.
const terminalDecorationSuccess = Codicons.circleFilled;

/// A decoration's color from its [classNames], as terminal.css gives it:
/// `terminalCommandDecoration.errorBackground` for `error`,
/// `.defaultBackground` for `default`, else `.successBackground`.
Color decorationColorOf(List<String> classNames) {
  if (classNames.contains(DecorationSelector.errorColor)) {
    return TerminalColors.commandDecorationErrorBackground;
  }
  if (classNames.contains(DecorationSelector.defaultClass)) {
    return TerminalColors.commandDecorationDefaultBackground;
  }
  return TerminalColors.commandDecorationSuccessBackground;
}

String getTerminalDecorationHoverContent(
  ITerminalCommand? command, [
  String? hoverMessage,
  bool showCommandActions = false,
]) {
  var hoverContent = showCommandActions
      ? 'Show Command Actions\n\n---\n\n'
      : '';
  if (command == null) {
    if (hoverMessage != null && hoverMessage.isNotEmpty) {
      hoverContent = hoverMessage;
    } else {
      return '';
    }
  } else if (command.markProperties != null ||
      (hoverMessage != null && hoverMessage.isNotEmpty)) {
    final message =
        _nonEmpty(command.markProperties?.hoverMessage) ??
        _nonEmpty(hoverMessage);
    if (message != null) {
      hoverContent = message;
    } else {
      return '';
    }
  } else {
    // Upstream checks `isNumber(command.duration)`, always true here.
    final durationText = getDurationString(command.duration);
    final exitCode = command.exitCode;
    final ago = _fromNow(command.timestamp);
    if (exitCode != null && exitCode != 0) {
      if (exitCode == -1) {
        hoverContent += 'Command executed $ago, took $durationText and failed';
      } else {
        hoverContent +=
            'Command executed $ago, took $durationText and failed '
            '(Exit Code $exitCode)';
      }
    } else {
      hoverContent += 'Command executed $ago and took $durationText';
    }
  }
  return hoverContent;
}

class TerminalCommandDecorationPersistedState {
  const TerminalCommandDecorationPersistedState({
    this.exitCode,
    this.timestamp,
    this.duration,
  });

  final int? exitCode;
  final int? timestamp;
  final int? duration;
}

enum TerminalCommandDecorationStatus { unknown, running, success, error }

class TerminalCommandDecorationState {
  const TerminalCommandDecorationState({
    required this.status,
    required this.icon,
    required this.classNames,
    required this.exitCode,
    required this.exitCodeText,
    required this.startTimestamp,
    required this.startText,
    required this.duration,
    required this.durationText,
    required this.hoverMessage,
  });

  final TerminalCommandDecorationStatus status;
  final IconData icon;
  final List<String> classNames;
  final int? exitCode;
  final String exitCodeText;
  final int? startTimestamp;
  final String startText;
  final int? duration;
  final String durationText;
  final String hoverMessage;

  /// The color its [classNames] give it.
  Color get color => decorationColorOf(classNames);
}

const _unknownText = 'Unknown';
const _runningText = 'Running';

String getTerminalCommandDecorationTooltip([
  ITerminalCommand? command,
  TerminalCommandDecorationPersistedState? storedState,
]) {
  if (command != null) {
    return getTerminalDecorationHoverContent(command);
  }
  if (storedState == null) {
    return '';
  }
  final timestamp = storedState.timestamp;
  final exitCode = storedState.exitCode;
  final duration = storedState.duration;
  if (timestamp == null) {
    return '';
  }
  var hoverContent = '';
  final fromNowText = _fromNow(timestamp);
  if (duration != null) {
    final durationText = getDurationString(math.max(duration, 0));
    if (exitCode != null && exitCode != 0) {
      if (exitCode == -1) {
        hoverContent +=
            'Command executed $fromNowText, took $durationText and failed';
      } else {
        hoverContent +=
            'Command executed $fromNowText, took $durationText and failed '
            '(Exit Code $exitCode)';
      }
    } else {
      hoverContent += 'Command executed $fromNowText and took $durationText';
    }
  } else {
    if (exitCode != null && exitCode != 0) {
      if (exitCode == -1) {
        hoverContent += 'Command executed $fromNowText and failed';
      } else {
        hoverContent +=
            'Command executed $fromNowText and failed (Exit Code $exitCode)';
      }
    } else {
      hoverContent += 'Command executed $fromNowText ';
    }
  }
  return hoverContent;
}

/// [now] is milliseconds since the epoch, `Date.now()` by default.
TerminalCommandDecorationState getTerminalCommandDecorationState(
  ITerminalCommand? command, [
  TerminalCommandDecorationPersistedState? storedState,
  int? now,
]) {
  now ??= DateTime.now().millisecondsSinceEpoch;
  var status = TerminalCommandDecorationStatus.unknown;
  final exitCode = command?.exitCode ?? storedState?.exitCode;
  var exitCodeText = _unknownText;
  final startTimestamp = command?.timestamp ?? storedState?.timestamp;
  var startText = _unknownText;
  int? durationMs;
  var durationText = _unknownText;

  if (startTimestamp != null) {
    // Upstream `new Date(startTimestamp).toLocaleString()`.
    startText = DateTime.fromMillisecondsSinceEpoch(startTimestamp)
        .toString()
        .split('.')
        .first;
  }

  if (command != null) {
    if (command.exitCode == null) {
      status = TerminalCommandDecorationStatus.running;
      exitCodeText = _runningText;
      durationMs = startTimestamp != null
          ? math.max(0, now - startTimestamp)
          : null;
    } else if (command.exitCode != 0) {
      status = TerminalCommandDecorationStatus.error;
      exitCodeText = '${command.exitCode}';
      durationMs = command.duration;
    } else {
      status = TerminalCommandDecorationStatus.success;
      exitCodeText = '${command.exitCode}';
      durationMs = command.duration;
    }
  } else if (storedState != null) {
    if (storedState.exitCode == null) {
      status = TerminalCommandDecorationStatus.running;
      exitCodeText = _runningText;
      durationMs = startTimestamp != null
          ? math.max(0, now - startTimestamp)
          : null;
    } else if (storedState.exitCode != 0) {
      status = TerminalCommandDecorationStatus.error;
      exitCodeText = '${storedState.exitCode}';
      durationMs = storedState.duration;
    } else {
      status = TerminalCommandDecorationStatus.success;
      exitCodeText = '${storedState.exitCode}';
      durationMs = storedState.duration;
    }
  }

  if (durationMs != null) {
    durationText = getDurationString(math.max(durationMs, 0));
  }

  final classNames = <String>[];
  var icon = terminalDecorationIncomplete;
  switch (status) {
    case TerminalCommandDecorationStatus.running:
    case TerminalCommandDecorationStatus.unknown:
      classNames.addAll([
        DecorationSelector.defaultColor,
        DecorationSelector.defaultClass,
      ]);
      icon = terminalDecorationIncomplete;
    case TerminalCommandDecorationStatus.error:
      classNames.add(DecorationSelector.errorColor);
      icon = terminalDecorationError;
    case TerminalCommandDecorationStatus.success:
      classNames.add(DecorationSelector.success);
      icon = terminalDecorationSuccess;
  }

  final hoverMessage = getTerminalCommandDecorationTooltip(
    command,
    storedState,
  );

  return TerminalCommandDecorationState(
    status: status,
    icon: icon,
    classNames: classNames,
    exitCode: exitCode,
    exitCodeText: exitCodeText,
    startTimestamp: startTimestamp,
    startText: startText,
    duration: durationMs,
    durationText: durationText,
    hoverMessage: hoverMessage,
  );
}

/// A decoration's box, in logical pixels: [width] by [height] with its
/// icon at [fontSize], [marginLeft] from the grid's left edge (negative:
/// in the padding), at the top of its row.
typedef TerminalDecorationLayout = ({
  double width,
  double height,
  double fontSize,
  double marginLeft,
});

/// Upstream `updateLayout`: the default dimension scaled down (never up) by
/// the font size over its default, [lineHeight] tall.
TerminalDecorationLayout decorationLayout({
  required double fontSize,
  required double defaultFontSize,
  required double lineHeight,
}) {
  final scalar = (fontSize / defaultFontSize) <= 1
      ? (fontSize / defaultFontSize)
      : 1.0;
  return (
    width: scalar * decorationDefaultDimension,
    height: scalar * decorationDefaultDimension * lineHeight,
    fontSize: scalar * decorationDefaultDimension,
    marginLeft: scalar * decorationMarginLeft,
  );
}

/// Upstream `getDurationString` (short words).
String getDurationString(int ms) {
  const minute = 60;
  const hour = minute * 60;
  const day = hour * 24;
  final seconds = (ms / 1000).abs();
  if (seconds < 1) {
    return '${ms}ms';
  }
  if (seconds < minute) {
    return '${_jsNumber(ms / 1000)}s';
  }
  if (seconds < hour) {
    return '${(ms / (1000 * minute)).round()} mins';
  }
  if (seconds < day) {
    return '${(ms / (1000 * hour)).round()} hrs';
  }
  return '${(ms / (1000 * day)).round()} days';
}

String _fromNow(int timestamp) =>
    ideFromNow(DateTime.fromMillisecondsSinceEpoch(timestamp), ago: true);

/// A number as JavaScript prints it: no `.0` on whole ones.
String _jsNumber(double value) =>
    value == value.truncateToDouble() ? '${value.toInt()}' : '$value';

String? _nonEmpty(String? s) => s == null || s.isEmpty ? null : s;
