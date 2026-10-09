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
import 'package:bao_exthost/bao_exthost.dart' show VsUri;
import 'package:flutter/material.dart';

import '../debug/common/debug_model.dart';
import '../debug/common/debug_source.dart';
import '../debug/common/debug_types.dart';
import '../debug/service/debug_service.dart';
import '../debug/ui/debug_icons.dart';
import '../debug/ui/debug_strings.dart';

/// The UTF-16 offset of [lineNumber]'s start, and of its content end, in a
/// document whose [lineStarts] are its lines' offsets (1-based lines; the
/// last line ends at [documentEnd]).
({int start, int end})? _lineRange(List<int> lineStarts, int lineNumber, int documentEnd) {
  if (lineNumber < 1 || lineNumber > lineStarts.length) return null;
  final start = lineStarts[lineNumber - 1];
  final end = lineNumber < lineStarts.length ? lineStarts[lineNumber] - 1 : documentEnd;
  return (start: start, end: end < start ? start : end);
}

/// The decorations of the file [uri] while [service] runs: each
/// breakpoint's glyph in the margin (normal, conditional, log, disabled,
/// unverified), the focused frame's line, and inline values. For
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
    final presentation = breakpointPresentation(state, activated, bp, strings, model: model);
    // A breakpoint's own column, where it has one.
    final start = bp.column != null && bp.column! > 0 ? range.start + bp.column! - 1 : range.start;
    decorations.add(
      EditorDecoration(
        start: start,
        end: range.end < start ? start : range.end,
        isWholeLine: true,
        lineDecorationIcon: presentation.icon,
        lineDecorationColor: presentation.color,
        hoverMessage: presentation.message,
      ),
    );
  }

  final frame = service.viewModel.focusedStackFrame;
  if (frame != null && frame.source.uri.toString() == uri.toString()) {
    final range = _lineRange(lineStarts, frame.range.startLineNumber, documentEnd);
    if (range != null) {
      final column = frame.range.startColumn > 0 ? frame.range.startColumn : 1;
      decorations.add(
        EditorDecoration(
          start: range.start + column - 1,
          end: range.end,
          backgroundColor: debugColor('editor.stackFrameHighlightBackground'),
          borderColor: debugColor('editor.focusedStackFrameHighlightBackground'),
          isWholeLine: true,
          showIfCollapsed: true,
        ),
      );
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
  if (frame == null || frame.source.uri.toString() != uri.toString()) return const [];
  return _inlineValues[frame.getId()] ?? const [];
}

/// Tells the glue a frame's inline values: the variables whose declaration
/// location is known, as the variables view loaded them.
void setDebugInlineValues(DebugService service, StackFrame frame, List<DebugInlineValue> values) {
  _inlineValues[frame.getId()] = values;
  service.viewModel.updateViews();
}

final _inlineValues = <String, List<DebugInlineValue>>{};

/// The glyph margin's overlay over an editor: a click on a line's glyph
/// adds a breakpoint (or removes it, when one is there; ⌥ toggles its
/// enabled state). Upstream puts this in the editor's own contribution;
/// until the editor calls back, this sits over its glyph margin.
class DebugGlyphMargin extends StatefulWidget {
  const DebugGlyphMargin({super.key, required this.service, required this.uri, required this.surfaceKey, required this.width});

  final DebugService service;
  final VsUri uri;

  /// The [EditorSurface]'s key, whose state is an [EditorSurfaceView].
  final GlobalKey surfaceKey;

  /// The glyph margin's width.
  final double width;

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
      if (surface.glyphMarginRect(line)?.contains(position) ?? false) return line;
    }
    return null;
  }

  Breakpoint? _breakpointAt(int line) =>
      widget.service.model.getBreakpoints(uri: widget.uri, lineNumber: line).firstOrNull;

  Future<void> _tap(int line, {required bool toggleEnabled}) async {
    final service = widget.service;
    final existing = _breakpointAt(line);
    if (existing == null) {
      await service.addBreakpoints(widget.uri, [BreakpointData(lineNumber: line)]);
    } else if (toggleEnabled) {
      await service.enableOrDisableBreakpoints(!existing.enabled, existing);
    } else {
      await service.removeBreakpoints([existing.getId()]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final surface = _surface;
    final visible = surface?.visibleLineRange;
    return SizedBox(
      width: widget.width,
      child: surface == null || visible == null
          ? const SizedBox.expand()
          : MouseRegion(
              cursor: SystemMouseCursors.click,
              onHover: (event) {
                final line = _lineAt(event.localPosition);
                if (line != _hoveredLine) setState(() => _hoveredLine = line);
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) {
                  final line = _lineAt(details.localPosition);
                  if (line != null) unawaited(_tap(line, toggleEnabled: false));
                },
                onSecondaryTapUp: (details) {
                  final line = _lineAt(details.localPosition);
                  if (line == null) return;
                  final bp = _breakpointAt(line);
                  if (bp != null) unawaited(widget.service.enableOrDisableBreakpoints(!bp.enabled, bp));
                },
                child: CustomPaint(
                  painter: _GlyphHoverPainter(
                    rects: [?_hoveredLine == null ? null : surface.glyphMarginRect(_hoveredLine!)],
                    color: debugColor('editorGutter.background').withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
    );
  }
}

class _GlyphHoverPainter extends CustomPainter {
  _GlyphHoverPainter({required this.rects, required this.color});

  final List<Rect> rects;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (final rect in rects) {
      canvas.drawRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(_GlyphHoverPainter oldDelegate) => oldDelegate.rects != rects || oldDelegate.color != color;
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
