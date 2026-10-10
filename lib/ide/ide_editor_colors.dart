// Document colors in the editor: the swatch before each color a provider
// finds, and the color picker opened on one.
//
// Follows VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/editor/contrib/colorPicker/browser/colorDetector.ts (an injected
// swatch before every provider color, moved with the text until the next
// refresh), colorPickerModel.ts (the picked color, the provider's
// presentations of it and the selected one; `guessColorPresentation` picks
// the presentation matching the text), and colorPickerParticipantUtils.ts
// (`updateColorPresentations`, `updateEditorModel`: the presentation's
// `textEdit` — or its label over the color's range — and its
// `additionalTextEdits`, applied as one undo step; the color's range is the
// edit's, tracked through the edits).
//
// Deviations: a drag on the picker previews the color and its presentation
// and edits the text when the drag ends (upstream edits on every move,
// leaving an undo stop per move); a text change other than the picker's own
// closes the picker.

import 'dart:async';

import 'package:bao_editor/monaco/flutter/document_snapshot.dart';
import 'package:bao_editor/monaco/flutter/editor_decorations.dart';
import 'package:bao_editor/monaco/flutter/editor_document_model.dart';
import 'package:bao_editor/monaco/flutter/editor_surface_controller.dart';
import 'package:bao_editor/monaco/flutter/editor_tracked_decorations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

/// A provider color in UTF-16 offsets of the snapshot it was found in;
/// [data] is the provider's own (handed back for presentations).
class EditorDocumentColor {
  const EditorDocumentColor(this.start, this.end, this.color, {this.data});

  final int start;
  final int end;
  final Color color;
  final Object? data;
}

/// A provider's presentation of a color: [label], and the edits that write
/// it, in offsets of [snapshot] (null [edit]: [label] over the color's
/// range).
class EditorColorPresentation {
  const EditorColorPresentation(
    this.label, {
    required this.snapshot,
    this.edit,
    this.additionalEdits = const [],
  });

  final String label;
  final DocumentSnapshot snapshot;
  final EditorOffsetEdit? edit;
  final List<EditorOffsetEdit> additionalEdits;
}

/// The presentations of [color] for the color at [start, end) of the
/// current text, from the provider of [source].
typedef EditorColorPresentationsProvider =
    Future<List<EditorColorPresentation>> Function(
      EditorDocumentColor source,
      int start,
      int end,
      Color color,
    );

/// A clickable color swatch injected before the provider's color range.
class EditorColorSwatch implements EditorInjectedTextTarget {
  EditorColorSwatch(this.owner, this.color);

  final EditorDocumentColors owner;
  final EditorDocumentColor color;

  @override
  void hover(Rect? rect, {required bool modifier}) {}

  @override
  MouseCursor? cursor({required bool modifier}) => SystemMouseCursors.click;

  @override
  bool pointerDown(PointerDownEvent event, {required bool modifier}) {
    if (event.buttons & kPrimaryMouseButton == 0) return false;
    return owner.open(this, event.position) != null;
  }
}

/// The active editor's provider colors: their swatches (moved with the
/// text) and the color picker open on one of them.
class EditorDocumentColors extends ChangeNotifier
    implements EditorDecorationProvider {
  EditorDocumentColors(this.controller)
    : _tracked = EditorTrackedDecorations(controller.document) {
    _tracked.addListener(notifyListeners);
    _changes = controller.document.changes.listen((_) {
      if (!_applying) closePicker();
    });
  }

  final EditorSurfaceController controller;
  final EditorTrackedDecorations _tracked;
  late final StreamSubscription<EditorContentChangeEvent> _changes;
  List<EditorDocumentColor> _colors = const [];
  Color _border = const Color(0xffeeeeee);
  EditorColorPicker? _picker;
  bool _applying = false;
  bool _disposed = false;

  /// Asks the color's provider for its presentations; none without it.
  EditorColorPresentationsProvider? onPresentations;

  /// The colors last set, in offsets of the snapshot they were found in.
  List<EditorDocumentColor> get colors => _colors;

  /// The picker open on a swatch, if any.
  EditorColorPicker? get picker => _picker;

  @override
  bool get affectsLayout => _tracked.affectsLayout;

  @override
  EditorDecorationSet get decorations => _tracked.decorations;

  /// Shows [colors] found in [source]; ignored unless [source] is the
  /// current text (results that outlived an edit).
  bool setColors(DocumentSnapshot source, List<EditorDocumentColor> colors) {
    if (_disposed || !identical(source, controller.document.snapshot)) {
      return false;
    }
    _colors = List.unmodifiable(colors);
    final length = source.text.length;
    _tracked.set(this, [
      for (final color in _colors)
        if (color.start >= 0 && color.end > color.start && color.end <= length)
          EditorTrackedDecoration(
            start: color.start,
            end: color.end,
            stickiness: TrackedRangeStickiness.neverGrowsWhenTypingAtEdges,
            data: color,
            decoration: _swatch(color),
          ),
    ]);
    return true;
  }

  /// The swatches' border: upstream's `#eee` on dark themes, `#000` on
  /// light ones.
  void setDark(bool dark) {
    final border = dark ? const Color(0xffeeeeee) : const Color(0xff000000);
    if (border == _border) return;
    _border = border;
    _tracked.restyle(
      this,
      (decoration, data) => _swatch(data! as EditorDocumentColor),
    );
  }

  // Upstream's `.colorpicker-color-decoration`: a 0.8em box, a 0.1em
  // border, 0.2em apart from the text (at the editor's 13px).
  EditorDecoration _swatch(EditorDocumentColor color) => EditorDecoration(
    start: color.start,
    end: color.end,
    before: EditorInjectedText(
      ' ',
      backgroundColor: color.color,
      borderColor: _border,
      borderWidth: const EditorCssLength(1),
      width: const EditorCssLength(10),
      height: const EditorCssLength(10),
      margin: const EditorCssEdges(
        left: EditorCssLength(3),
        right: EditorCssLength(3),
      ),
      cursorStops: InjectedTextCursorStops.none,
      data: EditorColorSwatch(this, color),
    ),
  );

  /// No swatches (the picker stays: it tracks its own range).
  void clear() {
    if (_disposed) return;
    _colors = const [];
    _tracked.clear(this);
  }

  /// [swatch]'s color range in the current text; null when it is not one
  /// of the swatches shown or its text is gone.
  ({int start, int end})? rangeOf(EditorColorSwatch swatch) {
    for (final range in _tracked.rangesOf(this)) {
      if (identical(range.data, swatch.color)) {
        return range.end > range.start
            ? (start: range.start, end: range.end)
            : null;
      }
    }
    return null;
  }

  /// Opens the picker on [swatch] at [anchor] (global), replacing any.
  EditorColorPicker? open(EditorColorSwatch swatch, Offset anchor) {
    if (_disposed || !identical(swatch.owner, this)) return null;
    final range = rangeOf(swatch);
    if (range == null) return null;
    _picker?._close();
    final picker = _picker = EditorColorPicker._(
      this,
      swatch.color,
      start: range.start,
      end: range.end,
      anchor: anchor,
    );
    notifyListeners();
    unawaited(picker._present(picker.value, guess: true));
    return picker;
  }

  void closePicker() {
    final picker = _picker;
    if (picker == null) return;
    _picker = null;
    picker._close();
    if (!_disposed) notifyListeners();
  }

  /// Applies [presentation] at [picker]'s range as one undo step; returns
  /// the range of its text afterwards, or null when nothing was applied.
  ({int start, int end})? _apply(
    EditorColorPicker picker,
    EditorColorPresentation presentation,
  ) {
    final document = controller.document;
    if (_disposed ||
        !identical(_picker, picker) ||
        !identical(presentation.snapshot, document.snapshot)) {
      return null;
    }
    final main =
        presentation.edit ??
        EditorOffsetEdit(picker.start, picker.end, presentation.label);
    final edits = [main, ...presentation.additionalEdits];
    // Upstream tracks the main edit's range (GrowsOnlyWhenTypingAfter)
    // through all of them: what comes before it moves it.
    var shift = 0;
    for (final edit in presentation.additionalEdits) {
      if (edit.end <= main.start) {
        shift += edit.text.length - (edit.end - edit.start);
      }
    }
    _applying = true;
    try {
      controller.applyEdits(edits);
    } on StateError {
      // Overlapping edits: upstream's executeEdits rejects them too.
      return null;
    } finally {
      _applying = false;
    }
    final start = main.start + shift;
    return (start: start, end: start + main.text.length);
  }

  @override
  void dispose() {
    _disposed = true;
    _picker?._close();
    _picker = null;
    unawaited(_changes.cancel());
    _tracked
      ..removeListener(notifyListeners)
      ..dispose();
    super.dispose();
  }
}

/// The color picker open on a swatch (upstream `ColorPickerModel` and the
/// hover participant's edits).
class EditorColorPicker extends ChangeNotifier {
  EditorColorPicker._(
    this.owner,
    this.source, {
    required this.start,
    required this.end,
    required this.anchor,
  }) : originalColor = source.color,
       _value = source.color;

  final EditorDocumentColors owner;

  /// The provider color it was opened on.
  final EditorDocumentColor source;

  /// The color when it opened (the header's right box: click to revert).
  final Color originalColor;

  /// Where the swatch was clicked (global).
  final Offset anchor;

  /// The color's text in the current document.
  int start;
  int end;

  Color _value;
  List<EditorColorPresentation> _presentations = const [];
  int _index = 0;
  Color? _presented;
  int _request = 0;
  bool _closed = false;
  Future<void> _pending = Future.value();

  bool get isOpen => !_closed && identical(owner.picker, this);

  /// The picked color.
  Color get value => _value;

  /// The provider's presentations of [value] and the one in use.
  List<EditorColorPresentation> get presentations => _presentations;
  int get presentationIndex => _index;
  EditorColorPresentation? get presentation =>
      _presentations.isEmpty ? null : _presentations[_index];

  /// Shows [color] being picked: asks for its presentations, edits nothing.
  Future<void> preview(Color color) {
    if (!isOpen) return Future.value();
    _value = color;
    notifyListeners();
    return _present(color);
  }

  /// Picks [color] and writes the selected presentation of it.
  Future<void> pick(Color color) async {
    await preview(color);
    await commit();
  }

  /// Writes the selected presentation of [value], once its presentations
  /// are the current ones.
  Future<void> commit() => _pending = _pending.then((_) async {
    if (!isOpen) return;
    if (_presented != _value ||
        !identical(
          presentation?.snapshot,
          owner.controller.document.snapshot,
        )) {
      await _present(_value);
    }
    final selected = presentation;
    if (!isOpen || selected == null || _presented != _value) return;
    final range = owner._apply(this, selected);
    if (range == null) return;
    start = range.start;
    end = range.end;
    // The presentations' edits were of the text before.
    _presented = null;
    notifyListeners();
  });

  /// Clicking the presentation label: the next presentation, written.
  Future<void> nextPresentation() {
    if (!isOpen || _presentations.length < 2) return Future.value();
    _index = (_index + 1) % _presentations.length;
    notifyListeners();
    return commit();
  }

  /// Clicking the original color: back to it, written.
  Future<void> revert() => pick(originalColor);

  Future<void> _present(Color color, {bool guess = false}) async {
    final provider = owner.onPresentations;
    if (provider == null || !isOpen) return;
    final request = ++_request;
    final snapshot = owner.controller.document.snapshot;
    final List<EditorColorPresentation> result;
    try {
      result = await provider(source, start, end, color);
    } on Object {
      return;
    }
    if (!isOpen ||
        request != _request ||
        !identical(snapshot, owner.controller.document.snapshot)) {
      return;
    }
    _presentations = List.unmodifiable(result);
    _presented = color;
    if (guess) {
      final text = _normalize(snapshot.text.substring(start, end));
      final index = result.indexWhere((p) => _normalize(p.label) == text);
      _index = index < 0 ? 0 : index;
    } else if (_index >= result.length) {
      _index = 0;
    }
    notifyListeners();
  }

  static String _normalize(String text) =>
      text.replaceAll(RegExp(r'\s'), '').toLowerCase();

  /// Closes it (not a picker opened since).
  void close() {
    if (identical(owner.picker, this)) owner.closePicker();
  }

  void _close() {
    if (_closed) return;
    _closed = true;
    _request++;
  }
}
