// The debug views' colors (with VS Code's defaults where the theme has
// none) and the breakpoint glyphs.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/contrib/debug/browser/debugColors.ts (defaults),
// debugIcons.ts and breakpointsView.ts (`getBreakpointMessageAndIcon`).

import 'package:flutter/widgets.dart';

import '../../theme/codicons.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../common/debug_model.dart';
import '../common/debug_types.dart';
import 'debug_strings.dart';

/// A color by id, else upstream's default for dark or light themes.
Color debugColor(String id) {
  final c = themeColors.get(id);
  if (c != null) return c;
  final dark = themeColors.dark;
  final d = _defaults[id];
  if (d != null) return Color(dark ? d.$1 : d.$2);
  return themeColors[id];
}

const _blue = (0xFF75BEFF, 0xFF007ACC);
const _defaults = <String, (int, int)>{
  'debugIcon.breakpointForeground': (0xFFE51400, 0xFFE51400),
  'debugIcon.breakpointDisabledForeground': (0xFF848484, 0xFF848484),
  'debugIcon.breakpointUnverifiedForeground': (0xFF848484, 0xFF848484),
  'debugIcon.breakpointCurrentStackframeForeground': (0xFFFFCC00, 0xFFBE8700),
  'debugIcon.breakpointStackframeForeground': (0xFF89D185, 0xFF89D185),
  'debugIcon.startForeground': (0xFF89D185, 0xFF388A34),
  'debugIcon.pauseForeground': _blue,
  'debugIcon.stopForeground': (0xFFF48771, 0xFFA1260D),
  'debugIcon.disconnectForeground': (0xFFF48771, 0xFFA1260D),
  'debugIcon.restartForeground': (0xFF89D185, 0xFF388A34),
  'debugIcon.stepOverForeground': _blue,
  'debugIcon.stepIntoForeground': _blue,
  'debugIcon.stepOutForeground': _blue,
  'debugIcon.continueForeground': _blue,
  'debugIcon.stepBackForeground': _blue,
  'debugToolBar.background': (0xFF333333, 0xFFF3F3F3),
  'checkbox.background': (0xFF313131, 0xFFFFFFFF),
  'checkbox.border': (0xFF3C3C3C, 0xFFCECECE),
  'checkbox.foreground': (0xFFF0F0F0, 0xFF3B3B3B),
  'panel.border': (0xFF808080, 0xFF808080),
  'debugTokenExpression.name': (0xFFC586C0, 0xFF9B46B0),
  'debugTokenExpression.type': (0xFF4A90E2, 0xFF4A90E2),
  'debugTokenExpression.value': (0x99CCCCCC, 0xCC6C6C6C),
  'debugTokenExpression.string': (0xFFCE9178, 0xFFA31515),
  'debugTokenExpression.boolean': (0xFF4E94CE, 0xFF0000FF),
  'debugTokenExpression.number': (0xFFB5CEA8, 0xFF098658),
  'debugTokenExpression.error': (0xFFF48771, 0xFFE51400),
  'debugView.stateLabelBackground': (0x44888888, 0x44888888),
  'debugView.valueChangedHighlight': (0xFF569CD6, 0xFF569CD6),
  'debugConsole.infoForeground': (0xFF3794FF, 0xFF1A85FF),
  'debugConsole.warningForeground': (0xFFCCA700, 0xFFBF8803),
  'debugConsole.errorForeground': (0xFFF48771, 0xFFA1260D),
  'debugConsole.sourceForeground': (0xFFCCCCCC, 0xFF616161),
  'debugConsoleInputIcon.foreground': (0xFFCCCCCC, 0xFF616161),
  'editor.stackFrameHighlightBackground': (0x33FFFF00, 0x66FFFF66),
  'editor.focusedStackFrameHighlightBackground': (0x337AD980, 0x4DCEE7CE),
  'editor.inlineValuesForeground': (0x80FFFFFF, 0x80000000),
  'editor.inlineValuesBackground': (0x33FFC800, 0x33FFC800),
};

/// How a breakpoint shows (`getBreakpointMessageAndIcon`).
final class BreakpointPresentation {
  const BreakpointPresentation(this.icon, this.color, this.message, {this.showAdapterUnverifiedMessage = false});

  final IconData icon;
  final Color color;
  final String? message;
  final bool showAdapterUnverifiedMessage;
}

enum _Kind { regular, disabled, unverified }

({IconData regular, IconData disabled, IconData unverified}) _iconsFor(BaseBreakpoint bp) => switch (bp) {
  DataBreakpoint() => (
    regular: Codicons.debugBreakpointData,
    disabled: Codicons.debugBreakpointDataDisabled,
    unverified: Codicons.debugBreakpointDataUnverified,
  ),
  FunctionBreakpoint() => (
    regular: Codicons.debugBreakpointFunction,
    disabled: Codicons.debugBreakpointFunctionDisabled,
    unverified: Codicons.debugBreakpointFunctionUnverified,
  ),
  _ when bp.logMessage != null && bp.logMessage!.isNotEmpty => (
    regular: Codicons.debugBreakpointLog,
    disabled: Codicons.debugBreakpointLogDisabled,
    unverified: Codicons.debugBreakpointLogUnverified,
  ),
  _ => (
    regular: Codicons.debugBreakpoint,
    disabled: Codicons.debugBreakpointDisabled,
    unverified: Codicons.debugBreakpointUnverified,
  ),
};

Color _colorFor(_Kind kind) => switch (kind) {
  _Kind.regular => debugColor('debugIcon.breakpointForeground'),
  _Kind.disabled => debugColor('debugIcon.breakpointDisabledForeground'),
  _Kind.unverified => debugColor('debugIcon.breakpointUnverifiedForeground'),
};

/// The glyph and hover message of [breakpoint] in [state].
BreakpointPresentation breakpointPresentation(
  DebugState state,
  bool breakpointsActivated,
  BaseBreakpoint breakpoint,
  DebugStrings s, {
  DebugModel? model,
}) {
  final debugActive = state == DebugState.running || state == DebugState.stopped;
  final icons = _iconsFor(breakpoint);
  final isLog = breakpoint.logMessage != null && breakpoint.logMessage!.isNotEmpty;
  if (!breakpoint.enabled || !breakpointsActivated) {
    return BreakpointPresentation(
      icons.disabled,
      _colorFor(_Kind.disabled),
      isLog ? '${s.disabledBreakpoint} (${s.logpoint})' : s.disabledBreakpoint,
    );
  }
  String appendMessage(String text) {
    final m = breakpoint.message;
    return m != null && m.isNotEmpty ? '$text, $m' : text;
  }

  if (debugActive && breakpoint is Breakpoint && breakpoint.pending) {
    return BreakpointPresentation(Codicons.debugBreakpointPending, _colorFor(_Kind.unverified), null);
  }
  if (debugActive && !breakpoint.verified) {
    final m = breakpoint.message;
    return BreakpointPresentation(
      icons.unverified,
      _colorFor(_Kind.unverified),
      m != null && m.isNotEmpty ? m : s.unverifiedBreakpoint,
      showAdapterUnverifiedMessage: true,
    );
  }
  if (breakpoint is DataBreakpoint) {
    return BreakpointPresentation(icons.regular, _colorFor(_Kind.regular), breakpoint.message ?? s.dataBreakpoint);
  }
  if (breakpoint is FunctionBreakpoint) {
    final messages = [
      breakpoint.message ?? s.functionBreakpoint,
      if (breakpoint.condition case final c? when c.isNotEmpty) s.conditionLabel(c),
      if (breakpoint.hitCondition case final h? when h.isNotEmpty) s.hitCountLabel(h),
    ];
    return BreakpointPresentation(icons.regular, _colorFor(_Kind.regular), messages.join('\n'));
  }
  Breakpoint? triggering;
  if (breakpoint is Breakpoint && breakpoint.triggeredBy != null && model != null) {
    triggering = model.getBreakpoints().where((b) => b.getId() == breakpoint.triggeredBy).firstOrNull;
  }
  final condition = breakpoint.condition;
  final hitCondition = breakpoint.hitCondition;
  if (isLog ||
      (condition != null && condition.isNotEmpty) ||
      (hitCondition != null && hitCondition.isNotEmpty) ||
      triggering != null) {
    final messages = <String>[];
    var icon = isLog ? Codicons.debugBreakpointLog : Codicons.debugBreakpointConditional;
    if (!breakpoint.supported) icon = Codicons.debugBreakpointUnsupported;
    if (isLog) messages.add(s.logMessageLabel(breakpoint.logMessage!));
    if (condition != null && condition.isNotEmpty) messages.add(s.conditionLabel(condition));
    if (hitCondition != null && hitCondition.isNotEmpty) messages.add(s.hitCountLabel(hitCondition));
    if (triggering != null) messages.add('→ ${triggering.toString()}');
    return BreakpointPresentation(icon, _colorFor(_Kind.regular), appendMessage(messages.join('\n')));
  }
  final m = breakpoint.message;
  return BreakpointPresentation(
    icons.regular,
    _colorFor(_Kind.regular),
    m != null && m.isNotEmpty ? m : (breakpoint is Breakpoint ? breakpoint.uri.path : s.breakpoint),
  );
}

/// The color a variable or expression value is drawn in, by what it
/// looks like (`renderExpressionValue`'s classes).
Color debugValueColor(String value, {bool error = false, String? type}) {
  if (error) return debugColor('debugTokenExpression.error');
  if (value == 'true' || value == 'false') return debugColor('debugTokenExpression.boolean');
  if (RegExp(r'^-?(\d+\.?\d*|\.\d+)([eE][-+]?\d+)?[nfdlLuU]*$').hasMatch(value) ||
      RegExp(r'^0[xX][0-9a-fA-F]+$').hasMatch(value)) {
    return debugColor('debugTokenExpression.number');
  }
  if (value.length >= 2 &&
      ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'")))) {
    return debugColor('debugTokenExpression.string');
  }
  return debugColor('debugTokenExpression.value');
}
