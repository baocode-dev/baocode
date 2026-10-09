import 'package:bao_editor/monaco/flutter/document_snapshot.dart';
import 'package:bao_editor/monaco/flutter/editor_decorations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import 'ide_commands.dart' show ideUsesMacKeys;

/// A document link in UTF-16 offsets of [EditorDocumentLinks.snapshot].
class EditorDocumentLink {
  const EditorDocumentLink(this.start, this.end, {this.tooltip, this.data});

  final int start;
  final int end;
  final String? tooltip;
  final Object? data;
}

/// The modifier-hover and click state for provider links in one editor.
class EditorDocumentLinks extends ChangeNotifier
    implements EditorDecorationProvider {
  DocumentSnapshot? _snapshot;
  List<EditorDocumentLink> _links = const [];
  EditorDocumentLink? _hovered;
  void Function(EditorDocumentLink link, DocumentSnapshot snapshot)? onOpen;
  Color _activeColor = const Color(0xff4e94ce);

  EditorDocumentLink? get hovered => _hovered;

  @override
  bool get affectsLayout => false;

  @override
  EditorDecorationSet get decorations => SortedDecorations([
    if (_hovered case final link?)
      EditorDecoration(
        start: link.start,
        end: link.end,
        underlineColor: _activeColor,
        underlineStyle: EditorUnderlineStyle.solid,
        hoverMessage: link.tooltip,
      ),
  ]);

  void setColor(Color? color) {
    final next = color ?? const Color(0xff4e94ce);
    if (next == _activeColor) return;
    _activeColor = next;
    if (_hovered != null) notifyListeners();
  }

  void setLinks(DocumentSnapshot? snapshot, List<EditorDocumentLink> links) {
    _snapshot = snapshot;
    _links = links;
    _setHovered(null);
  }

  void hover(DocumentSnapshot snapshot, int? offset) {
    if (!identical(snapshot, _snapshot) || offset == null || !_modifier) {
      _setHovered(null);
      return;
    }
    _setHovered(_at(offset));
  }

  bool pointerDown(
    DocumentSnapshot snapshot,
    int offset,
    PointerDownEvent event,
  ) {
    final keyboard = HardwareKeyboard.instance;
    if (!identical(snapshot, _snapshot) ||
        event.buttons & kPrimaryButton == 0 ||
        !_modifier ||
        keyboard.isAltPressed ||
        keyboard.isShiftPressed) {
      return false;
    }
    final link = _at(offset);
    if (link == null) return false;
    onOpen?.call(link, snapshot);
    _setHovered(null);
    return true;
  }

  EditorDocumentLink? _at(int offset) {
    for (final link in _links) {
      if (offset >= link.start && offset < link.end) return link;
    }
    return null;
  }

  bool get _modifier {
    final keyboard = HardwareKeyboard.instance;
    return ideUsesMacKeys ? keyboard.isMetaPressed : keyboard.isControlPressed;
  }

  void _setHovered(EditorDocumentLink? link) {
    if (identical(_hovered, link)) return;
    _hovered = link;
    notifyListeners();
  }
}
