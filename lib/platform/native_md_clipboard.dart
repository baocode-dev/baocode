import 'package:bao_markdown/bao_markdown.dart';
import 'package:flutter/services.dart';

import '../workspace/window_controls.dart';

/// The editors' clipboard in the desktop app: what an editor copies goes on
/// the clipboard as its text, for other apps, and beside it as its markdown
/// in a format of the app's own (macOS, Windows), for the editors to paste
/// back as it was (the composer's tags and all), in any of its windows,
/// whatever was copied since of the same text. Copied elsewhere since, the
/// format is gone with the rest. Where the host has no such format (Linux),
/// the markdown stays in memory, as [MdClipboard]'s.
class NativeMdClipboard extends MdClipboard {
  const NativeMdClipboard();

  @override
  Future<void> write(MdClip clip) async {
    remember(clip);
    try {
      if (await WindowControls.writePasteboardMarkdown(
        clip.plain,
        clip.markdown,
        plain: clip.fromPlain,
      )) {
        return;
      }
    } on MissingPluginException {
      // The text alone, below.
    } on PlatformException {
      // The text alone, below.
    }
    await Clipboard.setData(ClipboardData(text: clip.plain));
  }

  @override
  Future<({String? text, MdClip? clip})> read() async {
    final text = await readText();
    try {
      final copy = await WindowControls.readPasteboardMarkdown();
      return (
        text: text,
        clip: copy == null
            ? null
            : MdClip(
                plain: text ?? '',
                markdown: copy.markdown,
                fromPlain: copy.plain,
              ),
      );
    } on MissingPluginException {
      return (text: text, clip: lastFor(text));
    } on PlatformException {
      return (text: text, clip: lastFor(text));
    }
  }

  /// On Linux the snapshot taken as the paste happened (see
  /// [WindowControls.readPasteboardText]).
  @override
  Future<String?> readText() => WindowControls.readPasteboardText();
}
