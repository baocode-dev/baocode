import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../vs/base/common/strings_cursor.dart' show GraphemeIterator;
import '../vs/editor/common/core/range.dart';
import 'editor_document_model.dart';

/// Editing state for the opt-in painted surface. Not a Monaco editor replacement:
/// there is one selection, and each composing revision is currently its own undo
/// step. The caller owns an injected [document]; this controller owns its default.
class EditorSurfaceController extends ValueNotifier<TextEditingValue> {
  EditorSurfaceController({EditorDocumentModel? document})
    : document = document ?? EditorDocumentModel(''),
      _ownsDocument = document == null,
      super(
        TextEditingValue(
          text: document?.text ?? '',
          selection: TextSelection.collapsed(
            offset: (document?.text ?? '').length,
          ),
        ),
      );

  final EditorDocumentModel document;
  final bool _ownsDocument;
  bool _disposed = false;

  /// Assign the complete platform value, including its raw UTF-16 text,
  /// selection orientation, and composing range, as one atomic notification.
  @override
  set value(TextEditingValue next) {
    if (_disposed) return;
    final before = super.value.text;
    if (next.text != before) {
      var prefix = 0;
      while (prefix < before.length &&
          prefix < next.text.length &&
          before.codeUnitAt(prefix) == next.text.codeUnitAt(prefix)) {
        prefix++;
      }
      var suffix = 0;
      while (suffix < before.length - prefix &&
          suffix < next.text.length - prefix &&
          before.codeUnitAt(before.length - suffix - 1) ==
              next.text.codeUnitAt(next.text.length - suffix - 1)) {
        suffix++;
      }
      var end = before.length - suffix;
      // Range positions cannot address the interior of a CRLF. Replacing the
      // whole document also avoids splitting a surrogate across edit pieces.
      bool splitsPair(String text, int offset) =>
          offset > 0 &&
          offset < text.length &&
          text.codeUnitAt(offset - 1) >= 0xD800 &&
          text.codeUnitAt(offset - 1) <= 0xDBFF &&
          text.codeUnitAt(offset) >= 0xDC00 &&
          text.codeUnitAt(offset) <= 0xDFFF;
      final startPosition = document.positionAtOffset(prefix);
      final endPosition = document.positionAtOffset(end);
      if (document.offsetAtPosition(startPosition) != prefix ||
          document.offsetAtPosition(endPosition) != end ||
          splitsPair(before, prefix) ||
          splitsPair(before, end) ||
          splitsPair(next.text, prefix) ||
          splitsPair(next.text, next.text.length - suffix)) {
        prefix = 0;
        end = before.length;
        suffix = 0;
      }
      document.applyEdit(
        Range.fromPositions(
          document.positionAtOffset(prefix),
          document.positionAtOffset(end),
        ),
        next.text.substring(prefix, next.text.length - suffix),
      );
      assert(document.text == next.text);
    }
    super.value = next;
  }

  /// Refresh after an external edit to the supplied document. Callers of an
  /// injected document must explicitly sync because it has no notifications.
  void syncFromDocument() {
    if (_disposed) return;
    final text = document.text;
    final selection = value.selection;
    final base = selection.isValid
        ? selection.baseOffset.clamp(0, text.length)
        : 0;
    final extent = selection.isValid
        ? selection.extentOffset.clamp(0, text.length)
        : 0;
    super.value = TextEditingValue(
      text: text,
      selection: TextSelection(baseOffset: base, extentOffset: extent),
    );
  }

  void select(int base, int extent) {
    if (_disposed) return;
    value = value.copyWith(
      selection: TextSelection(
        baseOffset: base.clamp(0, value.text.length),
        extentOffset: extent.clamp(0, value.text.length),
      ),
      composing: TextRange.empty,
    );
  }

  void selectAll() => select(0, value.text.length);

  /// Requests that a listening surface reveal the current selection, even when
  /// its offsets have not changed. Does not alter text, composing, or history.
  void revealSelection() {
    if (!_disposed) notifyListeners();
  }

  void replaceSelection(String replacement) {
    if (_disposed) return;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : 0;
    final end = selection.isValid ? selection.end : 0;
    _replaceRange(start, end, replacement);
  }

  void _replaceRange(int start, int end, String replacement) {
    value = TextEditingValue(
      text: value.text.replaceRange(start, end, replacement),
      selection: TextSelection.collapsed(offset: start + replacement.length),
    );
  }

  /// Deletes the preceding pinned grapheme (or the exact nonempty selection).
  /// A caret inside a cluster deletes that entire cluster, not just its prefix.
  void deleteBackward() => _deleteGrapheme(forward: false);

  /// Deletes the following pinned grapheme (or the exact nonempty selection).
  /// A caret inside a cluster deletes that entire cluster, not just its suffix.
  void deleteForward() => _deleteGrapheme(forward: true);

  void _deleteGrapheme({required bool forward}) {
    final selection = value.selection;
    if (_disposed || !selection.isValid) return;
    if (!selection.isCollapsed) {
      replaceSelection('');
      return;
    }
    final range = _adjacentGrapheme(selection.extentOffset, forward: forward);
    if (!range.isCollapsed) _replaceRange(range.start, range.end, '');
  }

  TextRange _adjacentGrapheme(int offset, {required bool forward}) {
    final text = value.text;
    offset = offset.clamp(0, text.length);
    if ((forward && offset == text.length) || (!forward && offset == 0)) {
      return TextRange.collapsed(offset);
    }
    // Platform values can put a UTF-16 caret inside a surrogate pair. Keep the
    // raw value unchanged, but begin traversal at a complete code point.
    if (offset > 0 &&
        offset < text.length &&
        text.codeUnitAt(offset - 1) >= 0xD800 &&
        text.codeUnitAt(offset - 1) <= 0xDBFF &&
        text.codeUnitAt(offset) >= 0xDC00 &&
        text.codeUnitAt(offset) <= 0xDFFF) {
      offset += forward ? -1 : 1;
    }
    final iterator = GraphemeIterator(text, offset);
    // Walk back from the discovered boundary to include a cluster's other half
    // when the original caret is inside it, including the interior of CRLF.
    if (forward) {
      iterator.nextGraphemeLength();
      final end = iterator.offset;
      iterator.prevGraphemeLength();
      return TextRange(start: iterator.offset, end: end);
    }
    iterator.prevGraphemeLength();
    final start = iterator.offset;
    iterator.nextGraphemeLength();
    return TextRange(start: start, end: iterator.offset);
  }

  bool undo() {
    if (!document.undo()) return false;
    syncFromDocument();
    return true;
  }

  bool redo() {
    if (!document.redo()) return false;
    syncFromDocument();
    return true;
  }

  Future<void> copy() async {
    final selection = value.selection;
    if (selection.isValid && !selection.isCollapsed) {
      await Clipboard.setData(
        ClipboardData(
          text: value.text.substring(selection.start, selection.end),
        ),
      );
    }
  }

  /// [canEdit] lets a surface cancel a pending cut after losing editability.
  Future<void> cut({bool Function()? canEdit}) async {
    if (_disposed || canEdit?.call() == false) return;
    final before = value;
    if (!before.selection.isValid || before.selection.isCollapsed) return;
    final selected = before.text.substring(
      before.selection.start,
      before.selection.end,
    );
    await Clipboard.setData(ClipboardData(text: selected));
    // A clipboard round trip must not delete a selection that has since moved.
    if (_disposed ||
        canEdit?.call() == false ||
        value.text != before.text ||
        value.selection != before.selection) {
      return;
    }
    replaceSelection('');
  }

  /// A clipboard round trip must not insert into a different editing state.
  /// [canEdit] is checked before and after the request (e.g. for focus/read-only).
  Future<void> paste({bool Function()? canEdit}) async {
    if (_disposed || canEdit?.call() == false) return;
    final before = value;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (_disposed ||
        canEdit?.call() == false ||
        value.text != before.text ||
        value.selection != before.selection) {
      return;
    }
    if (data?.text != null) replaceSelection(data!.text!);
  }

  /// Move to the next/previous pinned grapheme boundary, keeping CRLF atomic.
  /// Uses VS Code's pinned approximation, not full Unicode segmentation: for
  /// example, consecutive regional indicators are one cluster, not flag pairs.
  /// Explicit selection edges and incoming platform values remain raw UTF-16.
  /// Set [collapseSelection] false to move from a range's extent instead of
  /// collapsing to its edge, as required by accessibility cursor actions.
  void moveHorizontal(
    int direction, {
    bool extend = false,
    bool collapseSelection = true,
  }) {
    final selection = value.selection;
    if (_disposed || !selection.isValid || direction == 0) return;
    if (collapseSelection && !extend && !selection.isCollapsed) {
      final edge = direction < 0 ? selection.start : selection.end;
      select(edge, edge);
      return;
    }
    final range = _adjacentGrapheme(
      selection.extentOffset,
      forward: direction > 0,
    );
    final target = direction < 0 ? range.start : range.end;
    select(extend ? selection.baseOffset : target, target);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_ownsDocument) document.dispose();
    super.dispose();
  }
}
