import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What a [MarkdownEditor] copied: [plain] for other apps (what it shows,
/// its embeds as their [MarkdownEmbeds.plainText]), [markdown] for editors
/// of its kind ([fromPlain]: a plain text's, see
/// [MarkdownController.plain]).
@immutable
class MdClip {
  const MdClip({
    required this.plain,
    required this.markdown,
    required this.fromPlain,
  });

  final String plain;
  final String markdown;
  final bool fromPlain;

  @override
  bool operator ==(Object other) =>
      other is MdClip &&
      other.plain == plain &&
      other.markdown == markdown &&
      other.fromPlain == fromPlain;

  @override
  int get hashCode => Object.hash(plain, markdown, fromPlain);
}

/// Where the editors copy to and paste from ([instance]).
///
/// This one has the clipboard's text alone: the markdown stays in memory,
/// pasted back while the clipboard still has the very text copied with it.
/// An app that can put a format of its own on the clipboard beside the text
/// (see [write], [read]) overrides it, the markdown then on the clipboard
/// itself: pasted in its other windows, and past a copy elsewhere of the
/// same text.
class MdClipboard {
  const MdClipboard();

  static MdClipboard instance = const MdClipboard();

  /// The last copy, any editor's.
  static MdClip? _last;

  /// [clip] kept as the last copy, for [read] where the clipboard has its
  /// text alone.
  @protected
  void remember(MdClip clip) => _last = clip;

  /// [clip] on the clipboard.
  Future<void> write(MdClip clip) async {
    remember(clip);
    await Clipboard.setData(ClipboardData(text: clip.plain));
  }

  /// What the clipboard has: its [text], and the editors' copy ([clip])
  /// where it is one.
  Future<({String? text, MdClip? clip})> read() async {
    final text = await readText();
    return (text: text, clip: lastFor(text));
  }

  /// The clipboard's text.
  @protected
  Future<String?> readText() async =>
      (await Clipboard.getData(Clipboard.kTextPlain))?.text;

  /// The last copy, where the clipboard's [text] is still its text.
  @protected
  MdClip? lastFor(String? text) {
    final last = _last;
    return text != null && last != null && text == last.plain ? last : null;
  }

  /// Forgets the last copy (tests).
  @visibleForTesting
  static void reset() => _last = null;
}
