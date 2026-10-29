import 'composer_files.dart';
import 'paste_store_stub.dart'
    if (dart.library.io) 'paste_store_io.dart'
    as platform;

/// Pastes too long to go in a message as they are: each kept in a file of
/// this machine's app data (`<data>/pastes/`, named by what it holds), and
/// the message saying where, for the agent to read (Claude Code is let read
/// the folder, see [ClaudeLaunch.readable]). Shorter ones go in the message
/// whole; so do all of a remote project's, whose agent cannot read this
/// machine's files. Either way they show as the same tag.
abstract final class PasteStore {
  /// Kept in a file past this many characters…
  static const maxSentLength = 40000;

  /// …or lines.
  static const maxSentLines = 1000;

  /// Whether [text], pasted, goes in a file rather than in the message.
  static bool isStored(String text) =>
      text.length > maxSentLength ||
      '\n'.allMatches(text).length >= maxSentLines;

  /// Where they are kept; null where there are no files (the web).
  static String? get directory => platform.pastesDirectory();

  /// Keeps [text]; where, or null where it could not be.
  static String? save(String text) => platform.savePaste(text);

  /// What the paste kept at [path] says; null where it is gone. One kept
  /// before the app's data moved is looked for where they are now.
  static Future<String?> read(String path) => platform.readPaste(path);

  /// [read], at once: for a copy, which has to have it now.
  static String? readNow(String path) => platform.readPasteNow(path);

  /// [text], a message with its [codeAppendix], with the pastes in it that
  /// are too long ([isStored]) kept in files, and named in their place.
  static String offload(String text) {
    bool stores(AppendedText reference) =>
        reference is PastedText &&
        reference.file == null &&
        isStored(reference.text);
    final (:body, :references) = splitCodeAppendix(text);
    if (!references.values.any(stores)) return text;
    return body +
        codeAppendix([
          for (final reference in references.values)
            if (stores(reference))
              switch (save((reference as PastedText).text)) {
                final path? => reference.storedAt(path),
                null => reference,
              }
            else
              reference,
        ]);
  }
}
