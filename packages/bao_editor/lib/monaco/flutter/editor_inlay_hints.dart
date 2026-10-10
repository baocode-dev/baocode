// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See lib/monaco/LICENSE.txt.
//
// Inlay hints, adapted from VS Code 1.135.0
// (08d4889f9ec4a1685d257b9b95de036c8e1ce1e5)
// src/vs/editor/contrib/inlayHints/browser:
// - inlayHints.ts `InlayHintsFragments`: a hint is anchored to the word at
//   its position, after it when the word starts before the position and
//   before it otherwise;
// - inlayHintsController.ts `_updateHintsDecorators`: each label part is
//   injected text of its own (no cursor stop, but on the right of the last
//   one when no padding follows), paddings are a hair space a third of the
//   font size wide (the right one a cursor stop), parts are colored by the
//   hint's kind (`editorInlayHint.{type,parameter,}{Foreground,Background}`),
//   at `editor.inlayHints.fontSize`/`fontFamily`, boxed when
//   `editor.inlayHints.padding`, cut with `…` past `maximumLength` (43) per
//   line, spaces non-breaking (`fixSpace`); the decorations grow when typing
//   at their edges and collapse when their word is replaced;
//   `_installLinkGesture`: the part under the pointer with a command or
//   location is underlined, and with Cmd/Ctrl down it takes the link color
//   and a pointer, and a click runs it.
//
// Deviations: hints are given by the caller (no providers, resolve, cache,
// debounce or fixed lengths while typing); the word is the default word
// pattern (no language word definitions or token fallback); box corners are
// all rounded; tooltips and double-click text edits are left to the
// caller ([EditorInlayHintsController.onHover], [EditorInlayHintPart]).

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDownEvent;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show TextStyle, TextDecoration, Rect;

import '../vs/editor/common/core/position.dart';
import 'editor_code_lens.dart' show EditorCommand;
import 'document_snapshot.dart';
import 'editor_decorations.dart';
import 'editor_document_model.dart';
import 'editor_tracked_decorations.dart';

/// `InlayHintKind`.
enum EditorInlayHintKind { type, parameter }

/// `InlayHintLabelPart`: [location] is the caller's (e.g. a `Location` to
/// go to).
@immutable
class EditorInlayHintLabelPart {
  const EditorInlayHintLabelPart(
    this.label, {
    this.tooltip,
    this.command,
    this.location,
  });

  final String label;
  final Object? tooltip;
  final EditorCommand? command;
  final Object? location;

  bool get isLink => command != null || location != null;
}

/// `InlayHint` at one-based [position]. [data] is the caller's.
@immutable
class EditorInlayHint {
  const EditorInlayHint({
    required this.position,
    required this.label,
    this.kind,
    this.tooltip,
    this.paddingLeft = false,
    this.paddingRight = false,
    this.textEdits,
    this.data,
  });

  /// A hint whose label is plain [text].
  factory EditorInlayHint.text(
    Position position,
    String text, {
    EditorInlayHintKind? kind,
    Object? tooltip,
    bool paddingLeft = false,
    bool paddingRight = false,
    Object? data,
  }) => EditorInlayHint(
    position: position,
    label: [EditorInlayHintLabelPart(text)],
    kind: kind,
    tooltip: tooltip,
    paddingLeft: paddingLeft,
    paddingRight: paddingRight,
    data: data,
  );

  final Position position;
  final List<EditorInlayHintLabelPart> label;
  final EditorInlayHintKind? kind;
  final Object? tooltip;
  final bool paddingLeft;
  final bool paddingRight;
  final Object? textEdits;
  final Object? data;
}

/// Colors of inlay hints by kind.
@immutable
class EditorInlayHintColors {
  const EditorInlayHintColors({
    this.foreground = const Color(0xff969696),
    this.background = const Color(0x1a4d4d4d),
    Color? typeForeground,
    Color? typeBackground,
    Color? parameterForeground,
    Color? parameterBackground,
    this.linkForeground = const Color(0xff4e94ce),
  }) : typeForeground = typeForeground ?? foreground,
       typeBackground = typeBackground ?? background,
       parameterForeground = parameterForeground ?? foreground,
       parameterBackground = parameterBackground ?? background;

  /// From theme colors by id (null for ones it lacks).
  factory EditorInlayHintColors.from(Color? Function(String id) colors) {
    final foreground =
        colors('editorInlayHint.foreground') ?? const Color(0xff969696);
    final background =
        colors('editorInlayHint.background') ?? const Color(0x1a4d4d4d);
    return EditorInlayHintColors(
      foreground: foreground,
      background: background,
      typeForeground: colors('editorInlayHint.typeForeground'),
      typeBackground: colors('editorInlayHint.typeBackground'),
      parameterForeground: colors('editorInlayHint.parameterForeground'),
      parameterBackground: colors('editorInlayHint.parameterBackground'),
      linkForeground:
          colors('editorLink.activeForeground') ?? const Color(0xff4e94ce),
    );
  }

  final Color foreground;
  final Color background;
  final Color typeForeground;
  final Color typeBackground;
  final Color parameterForeground;
  final Color parameterBackground;

  /// `editorLink.activeForeground`.
  final Color linkForeground;

  (Color, Color) of(EditorInlayHintKind? kind) => switch (kind) {
    EditorInlayHintKind.type => (typeForeground, typeBackground),
    EditorInlayHintKind.parameter => (parameterForeground, parameterBackground),
    null => (foreground, background),
  };

  @override
  bool operator ==(Object other) =>
      other is EditorInlayHintColors &&
      other.foreground == foreground &&
      other.background == background &&
      other.typeForeground == typeForeground &&
      other.typeBackground == typeBackground &&
      other.parameterForeground == parameterForeground &&
      other.parameterBackground == parameterBackground &&
      other.linkForeground == linkForeground;

  @override
  int get hashCode => Object.hash(
    foreground,
    background,
    typeForeground,
    typeBackground,
    parameterForeground,
    parameterBackground,
    linkForeground,
  );
}

/// One shown label part of a hint (`RenderedInlayHintLabelPart`): the
/// `data` of its injected text, given to [EditorInlayHintsController]'s
/// callbacks.
class EditorInlayHintPart implements EditorInjectedTextTarget {
  EditorInlayHintPart._(this._controller, this.hint, this.index);

  final EditorInlayHintsController _controller;
  final EditorInlayHint hint;

  /// Index into the hint's label.
  final int index;

  EditorInlayHintLabelPart get part => hint.label[index];

  @override
  void hover(Rect? rect, {required bool modifier}) =>
      _controller._hover(rect == null ? null : this, rect, modifier);

  @override
  MouseCursor? cursor({required bool modifier}) {
    if (modifier && part.isLink) return SystemMouseCursors.click;
    if (hint.textEdits != null) return SystemMouseCursors.basic;
    return null;
  }

  @override
  bool pointerDown(PointerDownEvent event, {required bool modifier}) {
    final activate = _controller.onActivate;
    if (!modifier || !part.isLink || activate == null) return false;
    activate(this);
    return true;
  }
}

/// How one injected text of a hint looks, apart from the active state.
class _Rendered {
  const _Rendered({
    required this.hint,
    required this.partIndex,
    required this.text,
    required this.after,
    this.padding = EditorCssEdges.zero,
    this.radius = EditorCssLength.zero,
    this.width,
    this.cursorStops = InjectedTextCursorStops.none,
  });

  final int hint;

  /// -1 for padding whitespace.
  final int partIndex;
  final String text;
  final bool after;
  final EditorCssEdges padding;
  final EditorCssLength radius;
  final EditorCssLength? width;
  final InjectedTextCursorStops cursorStops;
}

/// The inlay hints of one document (`InlayHintsController`, reduced): set
/// them with [setHints] and give the controller to the surface's
/// decoration providers.
class EditorInlayHintsController extends ChangeNotifier
    implements EditorDecorationProvider {
  EditorInlayHintsController(
    this.document, {
    EditorInlayHintColors colors = const EditorInlayHintColors(),
    this.fontSize,
    this.fontFamily,
    this.padding = false,
    this.maximumLength = 43,
  }) : _tracked = EditorTrackedDecorations(document),
       // ignore: prefer_initializing_formals
       _colors = colors {
    _tracked.addListener(notifyListeners);
  }

  final EditorDocumentModel document;

  /// `editor.inlayHints.fontSize` in pixels (null or under 5: the
  /// editor's).
  final double? fontSize;

  /// `editor.inlayHints.fontFamily` (null: the editor's).
  final String? fontFamily;

  /// `editor.inlayHints.padding`.
  final bool padding;

  /// `editor.inlayHints.maximumLength` per line (0: no limit).
  final int maximumLength;

  /// Cmd/Ctrl+click on a part with a command or location.
  void Function(EditorInlayHintPart part)? onActivate;

  /// The pointer is over [part] (its box [rect], surface-local), or left
  /// it (null): for the hint's tooltip.
  void Function(EditorInlayHintPart? part, Rect? rect)? onHover;

  final EditorTrackedDecorations _tracked;
  final Object _owner = Object();
  EditorInlayHintColors _colors;
  List<EditorInlayHint> _hints = const [];
  ({int hint, int part, bool modifier})? _active;

  List<EditorInlayHint> get hints => List.unmodifiable(_hints);

  EditorInlayHintColors get colors => _colors;

  set colors(EditorInlayHintColors value) {
    if (value == _colors) return;
    _colors = value;
    _restyle();
  }

  @override
  EditorDecorationSet get decorations => _tracked.decorations;

  @override
  bool get affectsLayout => _tracked.affectsLayout;

  /// Replaces the hints (a provider's result for the document).
  void setHints(List<EditorInlayHint> hints) {
    _active = null;
    final snapshot = document.snapshot;
    final anchored = [
      for (final hint in hints)
        (hint: hint, anchor: _anchor(snapshot.text, snapshot, hint.position)),
    ]..sort((a, b) => Position.compare(a.hint.position, b.hint.position));
    _hints = [for (final item in anchored) item.hint];
    final decorations = <EditorTrackedDecoration>[];
    var line = 0;
    var lineLength = 0;
    for (final (index, (hint: hint, anchor: anchor)) in anchored.indexed) {
      final lineNumber = snapshot.positionAtOffset(anchor.start).lineNumber;
      if (lineNumber != line) {
        line = lineNumber;
        lineLength = 0;
      }
      if (maximumLength > 0 && lineLength > maximumLength) continue;
      void add(_Rendered rendered) {
        final empty = anchor.start == anchor.end;
        decorations.add(
          EditorTrackedDecoration(
            start: anchor.start,
            end: anchor.end,
            decoration: _decoration(rendered, anchor.start, anchor.end),
            collapseOnReplaceEdit: !empty,
            data: rendered,
          ),
        );
      }

      // A hair space a third of the font wide.
      _Rendered whitespace(bool last) => _Rendered(
        hint: index,
        partIndex: -1,
        text: '\u200a',
        after: anchor.after,
        width: const EditorCssLength(1 / 3, EditorCssUnit.em),
        cursorStops: last
            ? InjectedTextCursorStops.right
            : InjectedTextCursorStops.none,
      );

      if (hint.paddingLeft) add(whitespace(false));
      const quarter = EditorCssLength(0.25, EditorCssUnit.em);
      const onePixel = EditorCssLength(1);
      for (final (i, part) in hint.label.indexed) {
        final first = i == 0;
        var last = i == hint.label.length - 1;
        var text = part.label;
        lineLength += text.length;
        final over = maximumLength > 0 ? lineLength - maximumLength : 0;
        if (over > 0) {
          text = '${text.substring(0, math.max(0, text.length - over))}…';
          last = true;
        }
        var edges = EditorCssEdges.zero;
        var radius = EditorCssLength.zero;
        if (padding) {
          radius = quarter;
          edges = EditorCssEdges(
            top: onePixel,
            bottom: onePixel,
            left: first ? quarter : EditorCssLength.zero,
            right: last ? quarter : EditorCssLength.zero,
          );
          if (!first && !last) radius = EditorCssLength.zero;
        }
        add(
          _Rendered(
            hint: index,
            partIndex: i,
            text: text.replaceAll(RegExp('[ \t]'), '\u00a0'),
            after: anchor.after,
            padding: edges,
            radius: radius,
            cursorStops: i == hint.label.length - 1 && !hint.paddingRight
                ? InjectedTextCursorStops.right
                : InjectedTextCursorStops.none,
          ),
        );
        if (over > 0) break;
      }
      if (hint.paddingRight) add(whitespace(true));
    }
    _tracked.set(_owner, decorations);
  }

  /// Removes all hints.
  void clear() => setHints(const []);

  /// `InlayHintsFragments`: the hint's word range and side.
  static ({int start, int end, bool after}) _anchor(
    String text,
    DocumentSnapshot snapshot,
    Position position,
  ) {
    final offset = snapshot.offsetAtPosition(position);
    final line = snapshot.positionAtOffset(offset).lineNumber;
    final lineStart = snapshot.lineStarts[line - 1];
    final lineEnd = snapshot.contentEnds[line - 1];
    final lineText = text.substring(lineStart, lineEnd);
    final column = offset - lineStart;
    for (final match in _wordPattern.allMatches(lineText)) {
      if (match.start > column) break;
      if (match.end < column) continue;
      return match.start < column
          ? (start: lineStart + match.start, end: offset, after: true)
          : (start: offset, end: lineStart + match.end, after: false);
    }
    return (start: offset, end: offset, after: false);
  }

  /// `DEFAULT_WORD_REGEXP`.
  static final RegExp _wordPattern = RegExp(
    r'(-?\d*\.\d\w*)|([^`~!@#$%^&*()\-=+\[{\]}\\|;:'
    "'"
    r'",.<>/?\s]+)',
  );

  EditorDecoration _decoration(_Rendered rendered, int start, int end) {
    final hint = _hints[rendered.hint];
    final (foreground, background) = _colors.of(hint.kind);
    final whitespace = rendered.partIndex < 0;
    final active = _active;
    final isActive =
        !whitespace &&
        active != null &&
        active.hint == rendered.hint &&
        active.part == rendered.partIndex &&
        hint.label[rendered.partIndex].isLink;
    final size = fontSize;
    final text = EditorInjectedText(
      rendered.text,
      style: whitespace
          ? null
          : TextStyle(
              color: isActive && active.modifier
                  ? _colors.linkForeground
                  : foreground,
              fontFamily: fontFamily,
              decoration: isActive ? TextDecoration.underline : null,
              decorationColor: isActive && active.modifier
                  ? _colors.linkForeground
                  : foreground,
            ),
      fontSize: size != null && size >= 5 ? EditorCssLength(size) : null,
      backgroundColor: whitespace ? null : background,
      padding: rendered.padding,
      borderRadius: rendered.radius,
      width: rendered.width,
      cursorStops: rendered.cursorStops,
      data: whitespace
          ? null
          : EditorInlayHintPart._(this, hint, rendered.partIndex),
    );
    return EditorDecoration(
      start: start,
      end: end,
      showIfCollapsed: start == end,
      before: rendered.after ? null : text,
      after: rendered.after ? text : null,
    );
  }

  void _restyle() {
    _tracked.restyle(
      _owner,
      (decoration, data) =>
          _decoration(data! as _Rendered, decoration.start, decoration.end),
    );
  }

  void _hover(EditorInlayHintPart? part, Rect? rect, bool modifier) {
    final index = part == null ? -1 : _hints.indexOf(part.hint);
    final active = part == null || index < 0 || !part.part.isLink
        ? null
        : (hint: index, part: part.index, modifier: modifier);
    if (active != _active) {
      _active = active;
      _restyle();
    }
    onHover?.call(part, rect);
  }

  @override
  void dispose() {
    _tracked
      ..removeListener(notifyListeners)
      ..dispose();
    super.dispose();
  }
}
