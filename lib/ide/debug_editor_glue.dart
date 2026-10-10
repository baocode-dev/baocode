// What the debug views need of the editor, kept in one place: where a
// breakpoint's glyph goes, the line a paused frame is on, the inline value
// after a variable's line, and a tap in the glyph margin adding or
// removing a breakpoint.
//
// This is the only debug file outside lib/debug/; it is deliberately thin:
// everything it shows is [EditorDecoration]s (packages/bao_editor's
// Monaco-shaped API: glyph margin icons, whole-line backgrounds, injected
// `after` text) and the geometry EditorSurfaceView gives, so it can be
// rebased on the editor's own breakpoint support later.
//
// Upstream: src/vs/workbench/contrib/debug/browser/
// breakpointEditorContribution.ts, debugEditorActions.ts,
// debugExpressionRenderer.ts and debugContentProvider.ts (the debug: scheme).

import 'dart:async';

import 'package:bao_editor/monaco/flutter/editor_surface.dart';

import '../base/uri.dart' show VsUri;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HardwareKeyboard;

import '../debug/common/debug_model.dart';
import '../debug/common/debug_source.dart';
import '../debug/common/debug_types.dart';
import '../debug/service/debug_service.dart';
import '../debug/ui/debug_icons.dart';
import '../debug/ui/debug_strings.dart';
import '../theme/codicons.dart';

/// The UTF-16 offset of [lineNumber]'s start, and of its content end, in a
/// document whose [lineStarts] are its lines' offsets (1-based lines; the
/// last line ends at [documentEnd]).
({int start, int end})? _lineRange(
  List<int> lineStarts,
  int lineNumber,
  int documentEnd,
) {
  if (lineNumber < 1 || lineNumber > lineStarts.length) return null;
  final start = lineStarts[lineNumber - 1];
  final end = lineNumber < lineStarts.length
      ? lineStarts[lineNumber] - 1
      : documentEnd;
  return (start: start, end: end < start ? start : end);
}

/// A codicon in the glyph margin, as an [EditorGutterIcon] for
/// `ideGutterIconBuilder` (`codicon:<code point>?color=<ARGB>`).
EditorGutterIcon debugGlyph(IconData icon, Color color) => EditorGutterIcon(
  'codicon:${icon.codePoint.toRadixString(16)}?color=${color.toARGB32().toRadixString(16).padLeft(8, '0')}',
);

/// The decorations of the file [uri] while [service] runs: each
/// breakpoint's glyph in the margin (normal, conditional, log, disabled,
/// unverified), the stopped threads' top frames and the focused frame
/// (`createCallStackDecorations`), and inline values. For
/// `IdeCodeEditor.decorations`.
///
/// [lineStarts] is `EditorDocumentModel.lineStarts`; [documentEnd] its
/// length.
List<EditorDecoration> debugEditorDecorations(
  DebugService service,
  VsUri uri, {
  required List<int> lineStarts,
  required int documentEnd,
  DebugStrings strings = DebugStrings.en,
  bool inlineValues = true,
}) {
  final model = service.model;
  final state = service.state;
  final activated = model.areBreakpointsActivated();
  final decorations = <EditorDecoration>[];

  for (final bp in model.getBreakpoints()) {
    if (bp.uri.toString() != uri.toString()) continue;
    final range = _lineRange(lineStarts, bp.lineNumber, documentEnd);
    if (range == null) continue;
    final presentation = breakpointPresentation(
      state,
      activated,
      bp,
      strings,
      model: model,
    );
    decorations.add(
      EditorDecoration(
        start: range.start,
        end: range.start,
        showIfCollapsed: true,
        gutterIcon: debugGlyph(presentation.icon, presentation.color),
      ),
    );
  }

  // Each stopped thread's top frame, and the focused frame when it is not
  // one: the line from the frame's column, and (in the focused session) the
  // margin's arrow, over a breakpoint's dot.
  final focused = service.viewModel.focusedStackFrame;
  for (final session in model.getSessions()) {
    final sessionFocused = identical(session, focused?.thread.session);
    for (final thread in session.getAllThreads()) {
      if (!thread.stopped) continue;
      final callStack = thread.getCallStack();
      if (callStack.isEmpty) continue;
      final top = callStack.first;
      for (final frame in [
        if (focused != null && !focused.equals(top)) focused,
        top,
      ]) {
        if (frame.source.uri.toString() != uri.toString()) continue;
        final range = _lineRange(
          lineStarts,
          frame.range.startLineNumber,
          documentEnd,
        );
        if (range == null) continue;
        final isTop = frame.equals(top);
        final column = frame.range.startColumn > 0
            ? frame.range.startColumn
            : 1;
        final start = (range.start + column - 1).clamp(range.start, range.end);
        decorations.add(
          EditorDecoration(
            start: start,
            end: range.end,
            backgroundColor: debugColor(
              isTop
                  ? 'editor.stackFrameHighlightBackground'
                  : 'editor.focusedStackFrameHighlightBackground',
            ),
            isWholeLine: true,
            showIfCollapsed: true,
          ),
        );
        if (sessionFocused) {
          decorations.add(
            EditorDecoration(
              start: range.start,
              end: range.start,
              showIfCollapsed: true,
              gutterIcon: debugGlyph(
                isTop
                    ? Codicons.debugStackframe
                    : Codicons.debugStackframeFocused,
                debugColor(
                  isTop
                      ? 'debugIcon.breakpointCurrentStackframeForeground'
                      : 'debugIcon.breakpointStackframeForeground',
                ),
              ),
            ),
          );
        }
      }
    }
  }

  if (inlineValues) {
    for (final value in debugInlineValues(service, uri)) {
      final range = _lineRange(lineStarts, value.lineNumber, documentEnd);
      if (range == null) continue;
      decorations.add(
        EditorDecoration(
          start: range.end,
          end: range.end,
          showIfCollapsed: true,
          afterText: value.text,
          afterColor: debugColor('editor.inlineValuesForeground'),
          afterMargin: 8,
          backgroundColor: debugColor('editor.inlineValuesBackground'),
        ),
      );
    }
  }
  return decorations;
}

/// A variable shown after its line (`getInlineValueDecorations`).
final class DebugInlineValue {
  const DebugInlineValue(this.lineNumber, this.text);

  final int lineNumber;

  /// `name = value`.
  final String text;
}

/// The inline values of a file: what was told with [setDebugInlineValues]
/// for the focused frame, when the setting is not `off`.
List<DebugInlineValue> debugInlineValues(DebugService service, VsUri uri) {
  if (service.settings().inlineValues == 'off') return const [];
  final frame = service.viewModel.focusedStackFrame;
  if (frame == null || frame.source.uri.toString() != uri.toString())
    return const [];
  return _inlineValues[frame.getId()] ?? const [];
}

/// Tells the glue a frame's inline values: the variables whose declaration
/// location is known, as the variables view loaded them.
void setDebugInlineValues(
  DebugService service,
  StackFrame frame,
  List<DebugInlineValue> values,
) {
  _inlineValues[frame.getId()] = values;
  service.viewModel.updateViews();
}

final _inlineValues = <String, List<DebugInlineValue>>{};

/// The glyph margin's overlay over an editor: a click on a line's glyph
/// adds a breakpoint (or removes it, when one is there; ⌥ toggles its
/// enabled state). Upstream puts this in the editor's own contribution;
/// until the editor calls back, this sits over its glyph margin.
class DebugGlyphMargin extends StatefulWidget {
  const DebugGlyphMargin({
    super.key,
    required this.service,
    required this.uri,
    required this.surfaceKey,
  });

  final DebugService service;
  final VsUri uri;

  /// The [EditorSurface]'s key, whose state is an [EditorSurfaceView].
  final GlobalKey surfaceKey;

  @override
  State<DebugGlyphMargin> createState() => _DebugGlyphMarginState();
}

class _DebugGlyphMarginState extends State<DebugGlyphMargin> {
  int? _hoveredLine;

  EditorSurfaceView? get _surface {
    // The key is on the surface inside the editor, whose state is the view.
    final state = widget.surfaceKey.currentState;
    return state is EditorSurfaceView ? state as EditorSurfaceView : null;
  }

  int? _lineAt(Offset position) {
    final surface = _surface;
    final visible = surface?.visibleLineRange;
    if (surface == null || visible == null) return null;
    for (var line = visible.first; line <= visible.last; line++) {
      if (surface.glyphMarginRect(line)?.contains(position) ?? false)
        return line;
    }
    return null;
  }

  Breakpoint? _breakpointAt(int line) => widget.service.model
      .getBreakpoints(uri: widget.uri, lineNumber: line)
      .firstOrNull;

  /// A click on [line]'s glyph: adds a breakpoint, or removes the line's
  /// (with ⇧, enables or disables them).
  Future<void> _tap(int line, {required bool toggleEnabled}) async {
    final service = widget.service;
    final existing = service.model.getBreakpoints(
      uri: widget.uri,
      lineNumber: line,
    );
    if (existing.isEmpty) {
      await service.addBreakpoints(widget.uri, [
        BreakpointData(lineNumber: line),
      ]);
    } else if (toggleEnabled) {
      final enabled = existing.any((bp) => bp.enabled);
      for (final bp in existing) {
        await service.enableOrDisableBreakpoints(!enabled, bp);
      }
    } else {
      await service.removeBreakpoints([for (final bp in existing) bp.getId()]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final surface = _surface;
    final visible = surface?.visibleLineRange;
    final width = visible == null
        ? null
        : surface?.glyphMarginRect(visible.first)?.width;
    if (surface == null || width == null) {
      // The surface lays out after this; its margin is known next frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _surface?.visibleLineRange != null) setState(() {});
      });
      return const SizedBox.shrink();
    }
    final hint = switch (_hoveredLine) {
      final line? when _breakpointAt(line) == null => surface.glyphMarginRect(
        line,
      ),
      _ => null,
    };
    return SizedBox(
      width: width,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onHover: (event) {
          final line = _lineAt(event.localPosition);
          if (line != _hoveredLine) setState(() => _hoveredLine = line);
        },
        onExit: (_) {
          if (_hoveredLine != null) setState(() => _hoveredLine = null);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            final line = _lineAt(details.localPosition);
            if (line == null) return;
            unawaited(
              _tap(
                line,
                toggleEnabled: HardwareKeyboard.instance.isShiftPressed,
              ),
            );
          },
          onSecondaryTapUp: (details) {
            final line = _lineAt(details.localPosition);
            if (line == null) return;
            final bp = _breakpointAt(line);
            if (bp != null)
              unawaited(
                widget.service.enableOrDisableBreakpoints(!bp.enabled, bp),
              );
          },
          child: Stack(
            children: [
              // `breakpointHelperDecoration`: the hint where a click adds one.
              if (hint != null)
                Positioned.fromRect(
                  rect: hint,
                  child: Opacity(
                    opacity: 0.4,
                    child: Icon(
                      Codicons.debugHint,
                      size: 14,
                      color: debugColor('debugIcon.breakpointForeground'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Whether a file of [languageId] can take breakpoints (`canSetBreakpointsIn`).
bool debugCanSetBreakpoints(DebugService service, String? languageId) =>
    service.canSetBreakpointsIn(languageId);

/// The content of a `debug:` source, from its session (`debugContentProvider`).
Future<String?> debugSourceContent(DebugService service, VsUri uri) async {
  if (uri.scheme != debugScheme) return null;
  final data = Source.getEncodedDebugData(uri);
  final session = service.model.getSession(data.sessionId);
  if (session == null) return null;
  final response = await session.loadSource(uri);
  return response?.obj('body')?.str('content');
}

/// The file a `debug:` source stands for, when it has a path.
VsUri? debugSourceFileUri(VsUri uri) {
  if (uri.scheme != debugScheme) return uri;
  final data = Source.getEncodedDebugData(uri);
  return data.path.isNotEmpty ? VsUri.file(data.path) : null;
}
