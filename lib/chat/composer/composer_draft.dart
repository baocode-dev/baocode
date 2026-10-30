import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../chat_models.dart';
import 'composer_embeds.dart' show ComposerEmbed;
import 'composer_files.dart';

/// What is typed in a composer and not sent yet, kept for when it shows
/// again (after another conversation was open): its content, caret and
/// images. Listened to by the composers showing it, as the same agent shows
/// in two windows: what is typed in one shows in the other.
class ComposerDraft extends ChangeNotifier {
  /// Its text, the things in it as the composer writes them (see
  /// [ComposerEmbed]); null until anything was typed or attached: start
  /// from what the composer was given.
  String? content;
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

  /// Lines of code to put in as tags of them, after what is typed (Add
  /// Selection to Chat), taken by the composer that shows the draft, or by
  /// the next to.
  List<CodeReference> get pendingCode => List.unmodifiable(_pendingCode);
  final List<CodeReference> _pendingCode = [];

  void insertCode(List<CodeReference> code) {
    if (code.isEmpty) return;
    _pendingCode.addAll(code);
    notifyListeners();
  }

  /// [pendingCode], no longer pending.
  List<CodeReference> takeCode() {
    final code = [..._pendingCode];
    _pendingCode.clear();
    return code;
  }

  /// A message to put back in, to be edited (a queued one taken back),
  /// taken by the composer that shows the draft, or by the next to.
  ({String text, List<ImageAttachment> images})? get pendingMessage =>
      _pendingMessage;
  ({String text, List<ImageAttachment> images})? _pendingMessage;

  void restore(String text, List<ImageAttachment> images) {
    _pendingMessage = (text: text, images: images);
    notifyListeners();
  }

  /// [pendingMessage], no longer pending.
  ({String text, List<ImageAttachment> images})? takeMessage() {
    final message = _pendingMessage;
    _pendingMessage = null;
    return message;
  }

  void save(
    String content,
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
