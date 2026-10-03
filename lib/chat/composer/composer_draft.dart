import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/quill_delta.dart';

import '../chat_models.dart';
import 'composer_files.dart';

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

  /// Files to put in as if pasted (Explorer's Open with BaoCode), taken by
  /// the composer that shows the draft, or by the next to.
  List<ComposerFile> get pendingFiles => List.unmodifiable(_pendingFiles);
  final List<ComposerFile> _pendingFiles = [];

  void insertFiles(List<ComposerFile> files) {
    if (files.isEmpty) return;
    _pendingFiles.addAll(files);
    notifyListeners();
  }

  /// [pendingFiles], no longer pending.
  List<ComposerFile> takeFiles() {
    final files = [..._pendingFiles];
    _pendingFiles.clear();
    return files;
  }

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
