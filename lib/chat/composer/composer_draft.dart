import 'package:flutter/services.dart';
import 'package:flutter_quill/quill_delta.dart';

import '../chat_models.dart';

/// What is typed in a composer and not sent yet, kept for when it shows
/// again (after another conversation was open): its content, caret and
/// images.
class ComposerDraft {
  /// Null until anything was typed or attached: start from what the
  /// composer was given.
  Delta? content;
  TextSelection selection = const TextSelection.collapsed(offset: 0);
  List<ImageAttachment> images = const [];

  bool get saved => content != null;

  void save(
    Delta content,
    TextSelection selection,
    List<ImageAttachment> images,
  ) {
    this.content = content;
    this.selection = selection;
    this.images = [...images];
  }
}
