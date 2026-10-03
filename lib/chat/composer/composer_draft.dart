import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/quill_delta.dart';

import '../chat_models.dart';

/// What is typed in a composer and not sent yet, kept for when it shows
/// again (after another conversation was open): its content, caret and
/// images. Listened to by the composers showing it, as the same agent shows
/// in two windows: what is typed in one shows in the other.
class ComposerDraft extends ChangeNotifier {
  /// Null until anything was typed or attached: start from what the
  /// composer was given.
  Delta? content;
  TextSelection selection = const TextSelection.collapsed(offset: 0);
  List<ImageAttachment> images = const [];

  bool get saved => content != null;

  /// Told of each [save], e.g. to keep the draft between runs.
  VoidCallback? onSaved;

  /// What saved it last ([save]'s `by`): the composer typing, which need
  /// not take up its own text.
  Object? get savedBy => _savedBy;
  Object? _savedBy;

  void save(
    Delta content,
    TextSelection selection,
    List<ImageAttachment> images, {
    Object? by,
  }) {
    this.content = content;
    this.selection = selection;
    this.images = [...images];
    _savedBy = by;
    onSaved?.call();
    notifyListeners();
  }
}
