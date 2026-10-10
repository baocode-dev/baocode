import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';

/// The composer's [QuillController]: keeps an input method's edit from
/// turning the tags and images before it into text.
///
/// Quill finds what the input method changed assuming the caret ends the
/// text it put in. One that shows a suggestion after the caret while
/// composing (an inline emoji, `ni hc〔表情：👋〕`) breaks that: the change
/// found then starts before the composition and takes in what precedes it,
/// embeds as the U+FFFC standing for them, which it puts back as text (drawn
/// as a boxed "OBJ" on Windows 10). Leaving out what such a replacement keeps
/// as it was leaves those embeds be.
class ComposerController extends QuillController {
  ComposerController({
    required super.document,
    required super.selection,
    super.config,
  });

  ComposerController.basic({super.config})
    : super(
        document: Document(),
        selection: const TextSelection.collapsed(offset: 0),
      );

  @override
  void replaceText(
    int index,
    int len,
    Object? data,
    TextSelection? textSelection, {
    bool ignoreFocus = false,
    bool shouldNotifyListeners = true,
  }) {
    if (data is String &&
        len > 0 &&
        data.contains(Embed.kObjectReplacementCharacter)) {
      final old = document.toPlainText().substring(index, index + len);
      final shorter = math.min(old.length, data.length);
      var head = 0;
      while (head < shorter && old.codeUnitAt(head) == data.codeUnitAt(head)) {
        head++;
      }
      // Not between the halves of a surrogate pair.
      if (head > 0 && _isLeadSurrogate(old.codeUnitAt(head - 1))) head--;
      var tail = 0;
      while (tail < shorter - head &&
          old.codeUnitAt(old.length - 1 - tail) ==
              data.codeUnitAt(data.length - 1 - tail)) {
        tail++;
      }
      if (tail > 0 && _isTrailSurrogate(old.codeUnitAt(old.length - tail))) {
        tail--;
      }
      index += head;
      len -= head + tail;
      data = data.substring(head, data.length - tail);
    }
    super.replaceText(
      index,
      len,
      data,
      textSelection,
      ignoreFocus: ignoreFocus,
      // ignore: experimental_member_use
      shouldNotifyListeners: shouldNotifyListeners,
    );
  }
}

bool _isLeadSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;

bool _isTrailSurrogate(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;
