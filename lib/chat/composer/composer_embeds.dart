import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:bao_markdown/bao_markdown.dart';
import 'package:path/path.dart' as p;

import '../../kernel/kernel_types.dart' show FileSuggestion;
import '../../l10n/l10n.dart';
import '../../stash/stash_store.dart';
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../../theme/material_file_icons.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../chat_models.dart';
import '../floating/hover_tooltip.dart';
import '../widgets/file_label.dart';
import '../side_panel/file_link.dart';
import '../side_panel/file_link_menu.dart';
import '../side_panel/file_open.dart';
import '../widgets/image_thumbnails.dart';
import '../widgets/text_preview.dart';
import 'command_details.dart';
import 'composer_files.dart';
import 'paste_store.dart';
import 'composer_mock_data.dart';

/// One of the composer's things in its text (a tag, a picture's
/// reference…), atomic: written in the text as one atom ([MdAtoms]), its
/// [type] and its [data], so the caret skips it and Backspace deletes it as
/// a whole.
@immutable
class ComposerEmbed {
  const ComposerEmbed(this.type, this.data);

  /// [ComposerTokenEmbed.type], [ComposerImageEmbed.type]…
  final String type;

  /// As its type has it (JSON, a number).
  final String data;

  /// It, as the composer's text has it: its type, a space, its data. Its
  /// data is on one line (JSON's line breaks are escaped), and the atom's
  /// marks in it are escaped too, as JSON reads them back.
  String get atom => MdAtoms.encode(
    '$type ${data.replaceAll(MdAtoms.open, r'\ue000').replaceAll(MdAtoms.close, r'\ue001')}',
  );

  /// The embed an atom holding [atomData] is; null for none of the
  /// composer's.
  static ComposerEmbed? parse(String atomData) {
    final space = atomData.indexOf(' ');
    if (space < 0) return null;
    return ComposerEmbed(
      atomData.substring(0, space),
      atomData.substring(space + 1),
    );
  }

  /// The embed [run] (an atom of [line]) is.
  static ComposerEmbed? of(MdInline run, String line) =>
      parse(MdAtoms.data(run, line));

  /// Text it contributes to the sent message.
  String get plainText => switch (type) {
    ComposerTokenEmbed.type => ComposerTokenEmbed.plainText(data),
    ComposerCodeEmbed.type => ComposerCodeEmbed.plainText(data),
    ComposerPastedTextEmbed.type => ComposerPastedTextEmbed.plainText(data),
    ComposerStashEmbed.type => ComposerStashEmbed.plainText(data),
    ComposerImageEmbed.type => ComposerImageEmbed.plainText(data),
    _ => '',
  };

  /// What it is copied as, for other apps: what was pasted to make it (a
  /// long paste's text, the code of lines copied from the IDE), not the
  /// message's reference to it; the rest as [plainText].
  String get copiedText => switch (type) {
    ComposerCodeEmbed.type => ComposerCodeEmbed.decode(data).code,
    ComposerPastedTextEmbed.type => switch (ComposerPastedTextEmbed.decode(
      data,
    )) {
      PastedText(:final file?) => PasteStore.readNow(file) ?? plainText,
      final pasted => pasted.text,
    },
    _ => plainText,
  };

  @override
  bool operator ==(Object other) =>
      other is ComposerEmbed && other.type == type && other.data == data;

  @override
  int get hashCode => Object.hash(type, data);

  @override
  String toString() => 'ComposerEmbed($type, $data)';
}

/// The composer's text in pieces: its text (a [String]) and its things
/// ([ComposerEmbed]s), in order.
Iterable<Object> composerPieces(String content) sync* {
  var at = 0;
  for (final run in MdAtoms.parse(content)) {
    if (run.start > at) yield content.substring(at, run.start);
    yield ComposerEmbed.of(run, content) ?? '';
    at = run.end;
  }
  if (at < content.length) yield content.substring(at);
}

/// The things in the composer's text, with where each is.
Iterable<({int start, int end, ComposerEmbed embed})> composerEmbedsIn(
  String content,
) sync* {
  for (final run in MdAtoms.parse(content)) {
    if (ComposerEmbed.of(run, content) case final embed?) {
      yield (start: run.start, end: run.end, embed: embed);
    }
  }
}

/// [content], a copy of the composer's pasted back into one, its long
/// pastes numbered on from [from], as pasted anew they would be: their
/// references, which tell them apart in the message, not the same as
/// those of the pastes already there.
String renumberPastes(String content, {required int from}) {
  var next = from;
  final renumbered = StringBuffer();
  var at = 0;
  for (final (:start, :end, :embed) in composerEmbedsIn(content)) {
    if (embed.type != ComposerPastedTextEmbed.type) continue;
    final pasted = ComposerPastedTextEmbed.decode(embed.data);
    renumbered
      ..write(content.substring(at, start))
      ..write(ComposerPastedTextEmbed.of(pasted.numbered(next++)).atom);
    at = end;
  }
  if (at == 0) return content;
  return (renumbered..write(content.substring(at))).toString();
}

/// The composer's text as it shows, each thing in it one character
/// (U+FFFC): as an input method is told of it ([MdTold]).
String composerShownText(String content) => MdTold.of(content).text;

/// The composer's text as text: each thing as the message says it.
String composerPlainText(String content) {
  if (!content.contains(MdAtoms.open)) return content;
  final plain = StringBuffer();
  for (final piece in composerPieces(content)) {
    plain.write(switch (piece) {
      final String text => text,
      final ComposerEmbed embed => embed.plainText,
      _ => '',
    });
  }
  return plain.toString();
}

/// Inline, atomic token for a file or folder, or a /command.
class ComposerTokenEmbed {
  static const type = 'composer-token';

  static ComposerEmbed fromSuggestion(Suggestion suggestion) => ComposerEmbed(
    type,
    jsonEncode({
      'kind': suggestion.kind.name,
      'label': suggestion.label,
      'value': suggestion.value,
    }),
  );

  /// The file or folder at [path], as the message refers to it (see
  /// [displayPath]).
  static ComposerEmbed file(String path, {bool directory = false}) =>
      ComposerEmbed(
        type,
        jsonEncode({
          'kind':
              (directory ? SuggestionKind.folder : SuggestionKind.file).name,
          'label': _name(path),
          'value': path,
        }),
      );

  /// The last part of [path], whichever its separators.
  static String _name(String path) {
    final trimmed = path.replaceFirst(RegExp(r'[/\\]+$'), '');
    final name = trimmed.split(RegExp(r'[/\\]')).last;
    return name.isEmpty ? path : name;
  }

  static ({SuggestionKind kind, String label, String value}) decode(
    Object? data,
  ) {
    final map = jsonDecode(data as String) as Map<String, dynamic>;
    return (
      kind: SuggestionKind.values.byName(map['kind'] as String),
      label: map['label'] as String,
      value: map['value'] as String,
    );
  }

  /// Another conversation, by its session's [id], titled [title].
  static ComposerEmbed session(String id, String title) => ComposerEmbed(
    type,
    jsonEncode({
      'kind': SuggestionKind.session.name,
      'label': title,
      'value': id,
    }),
  );

  /// Text a token contributes to the sent message and to plain-text copies.
  static String plainText(Object? data) {
    final token = decode(data);
    return switch (token.kind) {
      SuggestionKind.command => '/${token.value}',
      SuggestionKind.session => sessionReferenceText(token.value, token.label),
      _ => fileReferenceText(
        token.value,
        directory: token.kind == SuggestionKind.folder,
      ),
    };
  }
}

/// Another conversation as a message's text refers to it, by its session's
/// [id], which Claude Code finds it by, and its [title]:
/// `[Session 4f1c…: Fix the login]`. See [parseSessionReference].
String sessionReferenceText(String id, String title) {
  // Nothing in it ends the reference early.
  final words = title.replaceAll(RegExp(r'\s*[\]\r\n]+\s*'), ' ').trim();
  return words.isEmpty ? '[Session $id]' : '[Session $id: $words]';
}

final _sessionReference = RegExp(
  r'\[Session ([A-Za-z0-9][A-Za-z0-9_\-]*)(?:: ([^\]\n]*))?\]',
);

/// The conversation a [sessionReferenceText] at [at] of [text] refers to,
/// and where it ends; null when there is none there.
({String id, String title, int end})? parseSessionReference(
  String text,
  int at,
) {
  final match = _sessionReference.matchAsPrefix(text, at);
  if (match == null) return null;
  return (id: match[1]!, title: match[2] ?? '', end: match.end);
}

/// Inline, atomic reference to lines of a file, copied from the IDE's
/// editor: the message's text says `[lib/main.dart:12-30]`, and the lines
/// go after it (see [codeAppendix]).
class ComposerCodeEmbed {
  static const type = 'composer-code';

  static ComposerEmbed of(CodeReference reference) =>
      ComposerEmbed(type, jsonEncode(reference.toJson()));

  static CodeReference decode(Object? data) => CodeReference.fromJson(
    jsonDecode(data as String) as Map<String, Object?>,
  );

  /// Text it contributes to the sent message and to plain-text copies.
  static String plainText(Object? data) => decode(data).reference;
}

/// Inline, atomic reference to text too long to paste as it is: the
/// message's text says `[Pasted text #1 +120 lines]`, and the text goes
/// after it (see [PastedText], [codeAppendix]).
class ComposerPastedTextEmbed {
  static const type = 'composer-pasted';

  static ComposerEmbed of(PastedText pasted) =>
      ComposerEmbed(type, jsonEncode(pasted.toJson()));

  static PastedText decode(Object? data) =>
      PastedText.fromJson(jsonDecode(data as String) as Map<String, Object?>);

  /// Text it contributes to the sent message and to plain-text copies.
  static String plainText(Object? data) => decode(data).reference;
}

/// Inline, atomic reference to a stash: the message's text says
/// `[Stash #12]`, and the stash's text goes after it (see
/// [StashReference], [codeAppendix]).
class ComposerStashEmbed {
  static const type = 'composer-stash';

  static ComposerEmbed of(StashReference stash) =>
      ComposerEmbed(type, jsonEncode(stash.toJson()));

  static StashReference decode(Object? data) => StashReference.fromJson(
    jsonDecode(data as String) as Map<String, Object?>,
  );

  /// Text it contributes to the sent message and to plain-text copies.
  static String plainText(Object? data) => decode(data).reference;
}

/// Where what is dragged over the composer would go, released: the tags it
/// would put in, faint. Never sent; only there while the drag is.
class ComposerGhostEmbed {
  static const type = 'composer-ghost';

  static ComposerEmbed of(List<ComposerFile> files) => ComposerEmbed(
    type,
    jsonEncode([
      for (final file in files)
        {
          'name': file.name,
          'directory': file.directory,
          'image': file.maybeImage,
        },
    ]),
  );
}

/// Inline, atomic reference to an image of the message, by its number:
/// what the message's text says of it (`[Image #3]`). The text decides
/// which images go: deleting the reference takes its image out; taking
/// the image out leaves words in its place (see the composer).
class ComposerImageEmbed {
  static const type = 'composer-image';

  static ComposerEmbed of(int number) => ComposerEmbed(type, '$number');

  static int decode(Object? data) => int.parse('$data');

  /// Text it contributes to the sent message and to plain-text copies.
  static String plainText(Object? data) => imageReference(decode(data));
}

/// The images a composer holds, by number, for the references in its text
/// to show.
class ComposerImages extends InheritedWidget {
  const ComposerImages({super.key, required this.images, required super.child});

  final Map<int, ImageAttachment> images;

  static Map<int, ImageAttachment> of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ComposerImages>()?.images ??
      const {};

  @override
  bool updateShouldNotify(ComposerImages oldWidget) =>
      !identical(images, oldWidget.images);
}

/// The composer's things as its editor shows them: each as its tag,
/// centered on the text around it; copied as the message says it.
class ComposerChips extends MarkdownEmbeds {
  const ComposerChips();

  @override
  InlineSpan inline(BuildContext context, MdEmbed embed) {
    final style = embed.style;
    final Widget chip = switch (ComposerEmbed.of(embed.run, embed.line)) {
      ComposerEmbed(type: ComposerTokenEmbed.type, :final data) =>
        ComposerTokenChip(data: data, textStyle: style),
      ComposerEmbed(type: ComposerCodeEmbed.type, :final data) =>
        ComposerCodeChip(data: data, textStyle: style),
      ComposerEmbed(type: ComposerPastedTextEmbed.type, :final data) =>
        ComposerPastedTextChip(data: data, textStyle: style),
      ComposerEmbed(type: ComposerStashEmbed.type, :final data) =>
        ComposerStashChip(data: data, textStyle: style),
      ComposerEmbed(type: ComposerImageEmbed.type, :final data) =>
        _ComposerImageAtom(ComposerImageEmbed.decode(data), style),
      ComposerEmbed(type: ComposerGhostEmbed.type, :final data) =>
        ComposerGhostChip(data: data, textStyle: style),
      _ => const SizedBox.shrink(),
    };
    // Baseline alignment against a baseline the tag reports itself (see
    // [_CenteredOnText]). `PlaceholderAlignment.middle` depends on the glyph
    // runs sharing the line, so a line holding only a tag and a trailing
    // space laid out taller than one with text, and the composer jumped.
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: chip,
    );
  }

  @override
  String plainText(MdInline run, String line) =>
      ComposerEmbed.of(run, line)?.copiedText ?? '';
}

/// An image's reference in the composer: the image as [ComposerImages]
/// has it now (the editor keeps its lines as they were built).
class _ComposerImageAtom extends StatelessWidget {
  const _ComposerImageAtom(this.number, this.textStyle);

  final int number;
  final TextStyle textStyle;

  @override
  Widget build(BuildContext context) => ComposerImageChip(
    number: number,
    image: ComposerImages.of(context)[number],
    textStyle: textStyle,
  );
}

/// What can become a token besides dropped files: the kernel's `/commands`,
/// the project's files `@` looks up, and the other conversations to refer
/// to, for the composer and the sent messages under it.
class ComposerVocabulary extends InheritedWidget {
  const ComposerVocabulary({
    super.key,
    required this.commands,
    this.suggestFiles,
    this.sessions,
    this.stashes,
    this.stash,
    required super.child,
  });

  final List<Suggestion> commands;

  /// The stashes `@` offers ([Suggestion.stash]s), listed after the files;
  /// none without it.
  final List<Suggestion> Function()? stashes;

  /// The stash numbered so, to put in; null when it is gone.
  final StashReference? Function(int id)? stash;

  /// Files and folders matching what follows an `@` (see [fileSuggestion]);
  /// null when there is no looking.
  final Future<List<Suggestion>> Function(String query)? suggestFiles;

  /// The conversations `@` offers ([Suggestion.session]s), as they are when
  /// it is typed; none without it.
  final List<Suggestion> Function()? sessions;

  /// Outside any: no commands.
  static const fallback = ComposerVocabulary(
    commands: [],
    child: SizedBox.shrink(),
  );

  static ComposerVocabulary of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ComposerVocabulary>() ??
      fallback;

  /// [of] without depending on it (e.g. from `initState`).
  static ComposerVocabulary read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ComposerVocabulary>() ?? fallback;

  @override
  bool updateShouldNotify(ComposerVocabulary oldWidget) =>
      !identical(commands, oldWidget.commands) ||
      (sessions == null) != (oldWidget.sessions == null) ||
      (stashes == null) != (oldWidget.stashes == null) ||
      (suggestFiles == null) != (oldWidget.suggestFiles == null);
}

/// The composer's text for sent [text], the inverse of
/// [composerPlainText]: see [composerContentFromPaste].
String composerContentFromText(
  String text,
  ComposerVocabulary vocabulary, {
  Set<int> images = const {},
}) => composerContentFromPaste(text, vocabulary, atStart: true, images: images);

/// [text] (plain, e.g. pasted) as the composer's text: an `@path` becomes a file's token again (see
/// [parseFileReference]; `@override`, handles stay text), and so does a
/// leading `/command` when the text goes [atStart] of the message (where
/// alone a command counts). An `[Image #N]` becomes a reference again when
/// image N is among [images], and a `[path:12-30]` (or a `[Pasted text #1]`)
/// when what it refers to is in the [codeAppendix] at the end, which goes.
/// A `[Session id: …]`
/// becomes the conversation's token again (see [parseSessionReference]).
String composerContentFromPaste(
  String text,
  ComposerVocabulary vocabulary, {
  required bool atStart,
  Set<int> images = const {},
}) {
  final (body: body, references: code) = splitCodeAppendix(MdAtoms.strip(text));
  text = body;
  final content = StringBuffer();
  final buffer = StringBuffer();
  void flush() {
    if (buffer.isEmpty) return;
    content.write(buffer);
    buffer.clear();
  }

  // Where a command ends: not inside a word.
  final valueChar = RegExp(r'[A-Za-z0-9_./\-]');
  bool endsAt(int index) =>
      index >= text.length || !valueChar.hasMatch(text[index]);
  List<Suggestion> longestFirst(List<Suggestion> source) =>
      [...source]..sort((a, b) => b.value.length.compareTo(a.value.length));

  var i = 0;
  if (atStart && text.startsWith('/')) {
    for (final command in longestFirst(vocabulary.commands)) {
      if (text.startsWith(command.value, 1) &&
          endsAt(1 + command.value.length)) {
        flush();
        content.write(ComposerTokenEmbed.fromSuggestion(command).atom);
        i = 1 + command.value.length;
        break;
      }
    }
  }
  while (i < text.length) {
    if (text[i] == '[') {
      if (parseSessionReference(text, i) case (
        :final id,
        :final title,
        :final end,
      )) {
        flush();
        content.write(ComposerTokenEmbed.session(id, title).atom);
        i = end;
        continue;
      }
      if (images.isNotEmpty) {
        if (imageReferencePattern.matchAsPrefix(text, i) case final match?
            when images.contains(int.parse(match[1]!))) {
          flush();
          content.write(ComposerImageEmbed.of(int.parse(match[1]!)).atom);
          i = match.end;
          continue;
        }
      }
      if (code.isNotEmpty) {
        final close = text.indexOf(']', i);
        final reference = close < 0 ? null : code[text.substring(i, close + 1)];
        if (reference != null) {
          flush();
          content.write(switch (reference) {
            CodeReference() => ComposerCodeEmbed.of(reference).atom,
            PastedText() => ComposerPastedTextEmbed.of(reference).atom,
            StashReference() => ComposerStashEmbed.of(reference).atom,
          });
          i = close + 1;
          continue;
        }
      }
    }
    final atBoundary = i == 0 || text[i - 1].trim().isEmpty;
    if (text[i] == '@' && atBoundary) {
      if (parseFileReference(text, i) case (
        :final path,
        :final directory,
        :final end,
      )) {
        flush();
        content.write(ComposerTokenEmbed.file(path, directory: directory).atom);
        i = end;
        continue;
      }
    }
    buffer.write(text[i]);
    i++;
  }
  flush();
  return content.toString();
}

/// A draft kept by a version that kept the composer's text as its old
/// editor's operations ([ops]: inserts of text or of an embed, as JSON):
/// the text as it is kept now, and where [offset]s of it (an embed one
/// character) are in that.
({String content, int Function(int offset) offset}) composerContentFromOps(
  List<Object?> ops,
) {
  final content = StringBuffer();
  // Where each embed was, and how much longer it is now.
  final shifts = <(int, int)>[];
  var at = 0;
  for (final op in ops) {
    if (op is! Map || op['insert'] == null) continue;
    switch (op['insert']) {
      case final String text:
        content.write(MdAtoms.strip(text));
        at += text.length;
      case final Map<Object?, Object?> embed when embed.length == 1:
        final MapEntry(:key, :value) = embed.entries.single;
        final atom = ComposerEmbed('$key', '$value').atom;
        content.write(atom);
        shifts.add((at, atom.length - 1));
        at++;
      default:
        at++;
    }
  }
  var text = content.toString();
  // The document's closing newline is not the composer's.
  if (text.endsWith('\n')) text = text.substring(0, text.length - 1);
  return (
    content: text,
    offset: (offset) {
      var moved = offset;
      for (final (where, by) in shifts) {
        if (where >= offset) break;
        moved += by;
      }
      return moved.clamp(0, text.length);
    },
  );
}

/// The inline tag for a token ([ComposerTokenEmbed] data), centered on text
/// of [textStyle]: used in the composer and in sent messages alike.
///
/// Inside a selectable area it copies as its message text (`@lib/main.dart`,
/// `/plan`) whenever any of it is selected, not as the label it shows.
class ComposerTokenChip extends StatelessWidget {
  const ComposerTokenChip({
    super.key,
    required this.data,
    required this.textStyle,
  });

  final Object? data;
  final TextStyle textStyle;

  /// [ComposerTokenChip] as a span for rich text of [textStyle].
  static InlineSpan span(Object? data, TextStyle textStyle) => WidgetSpan(
    alignment: PlaceholderAlignment.baseline,
    baseline: TextBaseline.alphabetic,
    child: ComposerTokenChip(data: data, textStyle: textStyle),
  );

  @override
  Widget build(BuildContext context) {
    final token = ComposerTokenEmbed.decode(data);
    final isCommand = token.kind == SuggestionKind.command;
    Widget tag = _CenteredOnText(
      textStyle: textStyle,
      // A 1.5 line height would otherwise make the token taller than the
      // line itself.
      child: DefaultTextStyle.merge(
        style: const TextStyle(
          height: 1.25,
          leadingDistribution: TextLeadingDistribution.even,
        ),
        // The label is for show; the tag selects and copies as a whole.
        child: SelectionContainer.disabled(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 1),
            padding: const EdgeInsets.fromLTRB(4, 1, 5, 1),
            // A command as upstream's in the chat input; a file as an
            // attachment's pill.
            decoration: BoxDecoration(
              color: isCommand
                  ? themeColors['chat.slashCommandBackground']
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isCommand
                    ? Colors.transparent
                    : themeColors['chat.requestBorder'],
              ),
            ),
            child: switch (token.kind) {
              SuggestionKind.command => Text(
                '/${token.label}',
                style: TextStyle(
                  color: themeColors['chat.slashCommandForeground'],
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              SuggestionKind.folder => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FolderIcon(token.label, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    token.label,
                    style: TextStyle(color: AppColors.text, fontSize: 12),
                  ),
                ],
              ),
              SuggestionKind.file => FileLabel(token.label, fontSize: 12),
              // Stashes have tags of their own ([ComposerStashChip]).
              SuggestionKind.stash => Text(
                token.label,
                style: TextStyle(color: AppColors.text, fontSize: 12),
              ),
              SuggestionKind.session => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 13,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(width: 4),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 240),
                    child: Text(
                      // Untitled, its id's start.
                      token.label.isEmpty
                          ? token.value.substring(
                              0,
                              token.value.length.clamp(0, 8),
                            )
                          : token.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.text, fontSize: 12),
                    ),
                  ),
                ],
              ),
            },
          ),
        ),
      ),
    );
    // Where it is, when the tag shows only its name.
    if (!isCommand && token.value != token.label) {
      tag = HoverTooltip(
        content: (context) => _PathTip(token.value),
        child: tag,
      );
    }
    // A command's whole description, its file on a click (#220).
    if (isCommand) tag = CommandTagDetails(name: token.label, child: tag);
    // A file or folder, where the chat's files open, on a click.
    if (_opener(context, token) case final open?) {
      tag = PreviewClick(onOpen: open, child: tag);
    }
    return _SelectableToken(
      text: ComposerTokenEmbed.plainText(data),
      child: tag,
    );
  }

  /// What a click on [token] does: a file opens where the chat's files
  /// do, a folder shows in the side panel's tree; null for any other, or
  /// where there is nowhere to open it.
  static VoidCallback? _opener(
    BuildContext context,
    ({SuggestionKind kind, String label, String value}) token,
  ) {
    final scope = FileOpenScope.maybeOf(context);
    if (scope == null) return null;
    final inProject = scope.resolve(token.value);
    final path =
        inProject ??
        ((scope.paths ?? p.context).isAbsolute(token.value)
            ? token.value
            : null);
    if (path == null) return null;
    return switch (token.kind) {
      // One outside the project (dropped from elsewhere) as it is.
      SuggestionKind.file when inProject == null => () => scope.onOpen(
        FileOpenRequest(path),
      ),
      SuggestionKind.file => () => scope.activate(
        FileLink(token.value),
        path,
        context,
      ),
      SuggestionKind.folder => switch (scope.onOpenFolder) {
        final open? => () => open(path),
        null => null,
      },
      _ => null,
    };
  }
}

/// A tag's hover: the path it stands for.
class _PathTip extends StatelessWidget {
  const _PathTip(this.path);

  final String path;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 420),
    child: Text(path, style: TextStyle(color: AppColors.text, fontSize: 12)),
  );
}

/// The inline tag for lines of a file ([ComposerCodeEmbed] data), centered
/// on text of [textStyle]: the file's name and the lines, the lines
/// themselves on hover, all of them on a click (see [showTextPreview]). In
/// the composer and in sent messages alike.
///
/// Inside a selectable area it copies as its message text
/// (`[lib/main.dart:12-30]`).
class ComposerCodeChip extends StatelessWidget {
  const ComposerCodeChip({
    super.key,
    required this.data,
    required this.textStyle,
  });

  final Object? data;
  final TextStyle textStyle;

  /// [ComposerCodeChip] as a span for rich text of [textStyle].
  static InlineSpan span(Object? data, TextStyle textStyle) => WidgetSpan(
    alignment: PlaceholderAlignment.baseline,
    baseline: TextBaseline.alphabetic,
    child: ComposerCodeChip(data: data, textStyle: textStyle),
  );

  @override
  Widget build(BuildContext context) {
    final reference = ComposerCodeEmbed.decode(data);
    final name = ComposerTokenEmbed._name(reference.path);
    final lines = reference.start == reference.end
        ? '${reference.start}'
        : '${reference.start}-${reference.end}';
    final tag = _CenteredOnText(
      textStyle: textStyle,
      child: DefaultTextStyle.merge(
        style: const TextStyle(
          height: 1.25,
          leadingDistribution: TextLeadingDistribution.even,
        ),
        child: SelectionContainer.disabled(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 1),
            padding: const EdgeInsets.fromLTRB(4, 1, 5, 1),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: themeColors['chat.requestBorder']),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FileIcon(name, size: 15),
                const SizedBox(width: 5),
                Text(
                  name,
                  style: TextStyle(color: AppColors.text, fontSize: 12),
                ),
                Text(
                  ':$lines',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return _SelectableToken(
      text: reference.reference,
      child: HoverTooltip(
        content: (context) =>
            _TextPreview(label: reference.label, text: reference.code),
        child: PreviewClick(
          onOpen: () {
            // The file at those lines, where the chat's files open; the
            // lines as they were copied where it is not to be found.
            final scope = FileOpenScope.find(context);
            final link = FileLink(
              reference.path,
              FileLineRange(reference.start, reference.end),
            );
            if (scope != null) {
              if (scope.openLink(link)) return;
              // One outside the project, as it is.
              if ((scope.paths ?? p.context).isAbsolute(reference.path)) {
                return scope.onOpen(
                  FileOpenRequest(reference.path, range: link.range),
                );
              }
            }
            unawaited(
              showTextPreview(
                context,
                title: reference.label,
                text: reference.code,
                // Its file's extension, for its language.
                name:
                    '${p.basenameWithoutExtension(name)} ($lines)'
                    '${p.extension(name)}',
              ),
            );
          },
          child: tag,
        ),
      ),
    );
  }
}

/// A tag's hover for the text it stands for: [label] over its first lines.
class _TextPreview extends StatelessWidget {
  const _TextPreview({required this.label, required this.text});

  final String label;
  final String text;

  /// Lines shown, at most…
  static const _lines = 14;

  /// …and characters of each: a long paste may be one line of megabytes.
  static const _lineLength = 200;

  /// The first [_lines] of [text], without splitting all of it.
  static String _shown(String text) {
    final lines = <String>[];
    var start = 0;
    while (lines.length < _lines) {
      final end = text.indexOf('\n', start);
      final line = text.substring(start, end < 0 ? text.length : end);
      lines.add(
        line.length > _lineLength ? line.substring(0, _lineLength) : line,
      );
      if (end < 0) return lines.join('\n');
      start = end + 1;
    }
    return start < text.length ? '${lines.join('\n')}\n…' : lines.join('\n');
  }

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 480),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
        ),
        const SizedBox(height: 4),
        Text(
          _shown(text),
          softWrap: false,
          overflow: TextOverflow.fade,
          style: TextStyle(
            color: AppColors.text,
            fontFamily: AppFonts.mono,
            fontFamilyFallback: AppFonts.monoFallbacks,
            fontSize: 11.5,
            height: 1.4,
          ),
        ),
      ],
    ),
  );
}

/// The inline tag for a long paste ([ComposerPastedTextEmbed] data),
/// centered on text of [textStyle]: its number and its count of lines, its
/// first lines on hover, all of it on a click (see [showTextPreview]). In
/// the composer and in sent messages alike.
///
/// Inside a selectable area it copies as its message text
/// (`[Pasted text #1 +120 lines]`).
class ComposerPastedTextChip extends StatelessWidget {
  const ComposerPastedTextChip({
    super.key,
    required this.data,
    required this.textStyle,
  });

  final Object? data;
  final TextStyle textStyle;

  /// [ComposerPastedTextChip] as a span for rich text of [textStyle].
  static InlineSpan span(Object? data, TextStyle textStyle) => WidgetSpan(
    alignment: PlaceholderAlignment.baseline,
    baseline: TextBaseline.alphabetic,
    child: ComposerPastedTextChip(data: data, textStyle: textStyle),
  );

  @override
  Widget build(BuildContext context) {
    final pasted = ComposerPastedTextEmbed.decode(data);
    final l10n = context.l10n;
    final name = l10n.pastedTextChip(pasted.number);
    final lines = pasted.extraLines;
    final tag = _CenteredOnText(
      textStyle: textStyle,
      child: DefaultTextStyle.merge(
        style: const TextStyle(
          height: 1.25,
          leadingDistribution: TextLeadingDistribution.even,
        ),
        child: SelectionContainer.disabled(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 1),
            padding: const EdgeInsets.fromLTRB(4, 1, 5, 1),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: themeColors['chat.requestBorder']),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.notes_rounded, size: 13, color: AppColors.textMuted),
                const SizedBox(width: 4),
                Text(
                  name,
                  style: TextStyle(color: AppColors.text, fontSize: 12),
                ),
                if (lines > 0)
                  Text(
                    ' ${l10n.pastedTextLines(lines)}',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    return _SelectableToken(
      text: pasted.reference,
      child: HoverTooltip(
        content: (context) => switch (pasted.file) {
          final file? => _KeptTextPreview(label: name, file: file),
          null => _TextPreview(label: name, text: pasted.text),
        },
        child: PreviewClick(
          onOpen: () => unawaited(() async {
            final text = await _textOf(pasted, context.l10n);
            if (context.mounted) {
              await showTextPreview(context, title: name, text: text);
            }
          }()),
          child: tag,
        ),
      ),
    );
  }

  /// What [pasted] says: read from where it is kept, if it is.
  static Future<String> _textOf(
    PastedText pasted,
    AppLocalizations l10n,
  ) async => switch (pasted.file) {
    final file? => await PasteStore.read(file) ?? l10n.pastedTextGone(file),
    null => pasted.text,
  };
}

/// A kept paste's hover (see [PastedText.file]): read as it shows.
class _KeptTextPreview extends StatefulWidget {
  const _KeptTextPreview({required this.label, required this.file});

  final String label;
  final String file;

  @override
  State<_KeptTextPreview> createState() => _KeptTextPreviewState();
}

class _KeptTextPreviewState extends State<_KeptTextPreview> {
  late final Future<String?> _text = PasteStore.read(widget.file);

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _text,
    builder: (context, snapshot) => _TextPreview(
      label: widget.label,
      text: switch (snapshot) {
        AsyncSnapshot(data: final text?) => text,
        AsyncSnapshot(connectionState: ConnectionState.done) =>
          context.l10n.pastedTextGone(widget.file),
        _ => '…',
      },
    ),
  );
}

/// The inline tag for a stash ([ComposerStashEmbed] data), centered on
/// text of [textStyle]: its number and title, its text on hover, the stash
/// itself on a click (where the chat's files open, as the Stash page shows
/// it; its text by [showTextPreview] once it is gone). In the composer and
/// in sent messages alike.
class ComposerStashChip extends StatelessWidget {
  const ComposerStashChip({
    super.key,
    required this.data,
    required this.textStyle,
  });

  final Object? data;
  final TextStyle textStyle;

  /// [ComposerStashChip] as a span for rich text of [textStyle].
  static InlineSpan span(Object? data, TextStyle textStyle) => WidgetSpan(
    alignment: PlaceholderAlignment.baseline,
    baseline: TextBaseline.alphabetic,
    child: ComposerStashChip(data: data, textStyle: textStyle),
  );

  @override
  Widget build(BuildContext context) {
    final stash = ComposerStashEmbed.decode(data);
    final name = 'Stash #${stash.id}';
    final title = stash.title.trim();
    final tag = _CenteredOnText(
      textStyle: textStyle,
      child: DefaultTextStyle.merge(
        style: const TextStyle(
          height: 1.25,
          leadingDistribution: TextLeadingDistribution.even,
        ),
        child: SelectionContainer.disabled(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 1),
            padding: const EdgeInsets.fromLTRB(4, 1, 5, 1),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: themeColors['chat.requestBorder']),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Codicons.note, size: 13, color: AppColors.textMuted),
                const SizedBox(width: 4),
                Text(
                  name,
                  style: TextStyle(color: AppColors.text, fontSize: 12),
                ),
                if (title.isNotEmpty)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Text(
                      ' $title',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    final label = title.isEmpty ? name : '$name · $title';
    return _SelectableToken(
      text: stash.reference,
      child: HoverTooltip(
        content: (context) => _TextPreview(label: label, text: stash.text),
        child: PreviewClick(
          onOpen: () {
            // The stash itself, as the Stash page shows it, while it is
            // kept; else the text it was sent with.
            if ((
                  FileOpenScope.find(context),
                  StashStore.current?.fileOf(stash.id),
                )
                case (final scope?, final file?)) {
              scope.showLocal(file);
              return;
            }
            unawaited(
              showTextPreview(
                context,
                title: label,
                text: stash.text,
                name: '$name.md',
              ),
            );
          },
          child: tag,
        ),
      ),
    );
  }
}

/// Where what is dragged over the composer would go ([ComposerGhostEmbed]
/// data): the tags it would put in, faint, centered on text of
/// [textStyle].
class ComposerGhostChip extends StatelessWidget {
  const ComposerGhostChip({
    super.key,
    required this.data,
    required this.textStyle,
  });

  final String data;
  final TextStyle textStyle;

  @override
  Widget build(BuildContext context) {
    final files = [
      for (final file in jsonDecode(data) as List<dynamic>)
        file as Map<String, dynamic>,
    ];
    return _CenteredOnText(
      textStyle: textStyle,
      child: IgnorePointer(
        child: Opacity(
          opacity: .45,
          child: DefaultTextStyle.merge(
            style: const TextStyle(
              height: 1.25,
              leadingDistribution: TextLeadingDistribution.even,
            ),
            child: Row(
              key: const ValueKey(ComposerGhostEmbed.type),
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final file in files)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    padding: const EdgeInsets.fromLTRB(4, 1, 5, 1),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: themeColors['agentsChatInput.focusBorder'],
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (file['directory'] == true)
                          FolderIcon(file['name'] as String, size: 14)
                        else if (file['image'] == true)
                          Icon(
                            Icons.image_outlined,
                            size: 13,
                            color: AppColors.textMuted,
                          )
                        else
                          FileIcon(file['name'] as String, size: 15),
                        const SizedBox(width: 4),
                        Text(
                          file['name'] as String,
                          style: TextStyle(color: AppColors.text, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The inline reference to image [number] of a message, centered on text
/// of [textStyle]: a small picture of it and its name, the picture shown
/// larger on hover and whole on a click. In the composer and in sent
/// messages alike.
///
/// Inside a selectable area it copies as its message text (`[Image #3]`).
class ComposerImageChip extends StatelessWidget {
  const ComposerImageChip({
    super.key,
    required this.number,
    required this.image,
    required this.textStyle,
  });

  final int number;
  final ImageAttachment? image;
  final TextStyle textStyle;

  /// [ComposerImageChip] as a span for rich text of [textStyle].
  static InlineSpan span(
    int number,
    ImageAttachment? image,
    TextStyle textStyle,
  ) => WidgetSpan(
    alignment: PlaceholderAlignment.baseline,
    baseline: TextBaseline.alphabetic,
    child: ComposerImageChip(
      number: number,
      image: image,
      textStyle: textStyle,
    ),
  );

  static const _pictureSize = 14.0;

  @override
  Widget build(BuildContext context) {
    final image = this.image;
    Widget chip = _CenteredOnText(
      textStyle: textStyle,
      child: DefaultTextStyle.merge(
        style: const TextStyle(
          height: 1.25,
          leadingDistribution: TextLeadingDistribution.even,
        ),
        child: SelectionContainer.disabled(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 1),
            padding: const EdgeInsets.fromLTRB(2, 1, 5, 1),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: themeColors['chat.requestBorder']),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(2.5),
                  child: SizedBox.square(
                    dimension: _pictureSize,
                    child: image == null
                        ? Icon(
                            Icons.image_outlined,
                            size: 12,
                            color: AppColors.textMuted,
                          )
                        : Image.memory(
                            image.bytes,
                            fit: BoxFit.cover,
                            cacheWidth: (_pictureSize * 3).round(),
                            gaplessPlayback: true,
                            errorBuilder: (context, error, stack) => Icon(
                              Icons.broken_image_outlined,
                              size: 12,
                              color: AppColors.textFaint,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  context.l10n.imageChip(number),
                  style: TextStyle(color: AppColors.text, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (image != null) {
      chip = ImagePreviewClick(image: image, child: chip);
      chip = HoverTooltip(
        content: (context) => _ImageHover(image.bytes),
        child: FileLinkMenuRegion(menu: ImageMenu(image), child: chip),
      );
    }
    return _SelectableToken(text: imageReference(number), child: chip);
  }
}

/// An image on hover, small.
class _ImageHover extends StatelessWidget {
  const _ImageHover(this.bytes);

  final Uint8List bytes;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 240, maxHeight: 180),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.memory(
        bytes,
        fit: BoxFit.contain,
        cacheWidth: 720,
        gaplessPlayback: true,
      ),
    ),
  );
}

/// The tag for an image file the chat links to, as an attached image's
/// ([ComposerImageChip]): its picture small and the link's [label],
/// centered on text of [textStyle]. A click shows it enlarged; a right
/// click has the file's menu (see [FileOpenScope.menuFor]).
class FileImageChip extends StatefulWidget {
  const FileImageChip({
    super.key,
    required this.path,
    required this.label,
    required this.files,
    required this.textStyle,
  });

  /// Absolute, on the project's host.
  final String path;
  final String label;
  final FileOpenScope files;
  final TextStyle textStyle;

  /// [FileImageChip] as a span for rich text of [textStyle].
  static InlineSpan span({
    required String path,
    required String label,
    required FileOpenScope files,
    required TextStyle textStyle,
  }) => WidgetSpan(
    alignment: PlaceholderAlignment.baseline,
    baseline: TextBaseline.alphabetic,
    child: FileImageChip(
      path: path,
      label: label,
      files: files,
      textStyle: textStyle,
    ),
  );

  @override
  State<FileImageChip> createState() => _FileImageChipState();
}

class _FileImageChipState extends State<FileImageChip> {
  /// The images read lately, by where they are read from (a project's
  /// host) and path: the history builds its rows anew as they scroll into
  /// view.
  static final _read = <(Object?, String), Future<ImageAttachment?>>{};

  /// Past this an image is not read to be shown this small.
  static const _maxBytes = 20 << 20;

  late Future<ImageAttachment?> _image = _imageOf(widget.path);

  Future<ImageAttachment?> _imageOf(String path) {
    final key = (widget.files.readBytes, path);
    if (_read.remove(key) case final read?) return _read[key] = read;
    if (_read.length >= 24) _read.remove(_read.keys.first);
    return _read[key] = widget.files.image(path, maxBytes: _maxBytes);
  }

  @override
  void didUpdateWidget(FileImageChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.path != oldWidget.path) _image = _imageOf(widget.path);
  }

  @override
  Widget build(BuildContext context) {
    final FileImageChip(:path, :label, :files) = widget;
    return FutureBuilder(
      future: _image,
      builder: (context, snapshot) {
        final image = snapshot.data;
        Widget chip = _CenteredOnText(
          textStyle: widget.textStyle,
          child: DefaultTextStyle.merge(
            style: const TextStyle(
              height: 1.25,
              leadingDistribution: TextLeadingDistribution.even,
            ),
            child: SelectionContainer.disabled(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 1),
                padding: const EdgeInsets.fromLTRB(2, 1, 5, 1),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: themeColors['chat.requestBorder']),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2.5),
                      child: SizedBox.square(
                        dimension: ComposerImageChip._pictureSize,
                        child: image == null
                            ? Icon(
                                snapshot.connectionState == ConnectionState.done
                                    ? Icons.broken_image_outlined
                                    : Icons.image_outlined,
                                size: 12,
                                color: AppColors.textMuted,
                              )
                            : Image.memory(
                                image.bytes,
                                fit: BoxFit.cover,
                                cacheWidth: (ComposerImageChip._pictureSize * 3)
                                    .round(),
                                gaplessPlayback: true,
                                errorBuilder: (context, error, stack) => Icon(
                                  Icons.broken_image_outlined,
                                  size: 12,
                                  color: AppColors.textFaint,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppColors.text, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        chip = PreviewClick(
          onOpen: () => unawaited(
            files.preview(
              context,
              path,
              orElse: () => files.onOpen(FileOpenRequest(path)),
            ),
          ),
          child: FileLinkMenuRegion(
            menu: files.menuFor(
              path,
              () => files.onOpen(FileOpenRequest(path)),
              context: context,
            ),
            child: chip,
          ),
        );
        if (image != null) {
          chip = HoverTooltip(
            content: (context) => _ImageHover(image.bytes),
            child: chip,
          );
        }
        return _SelectableToken(text: label, child: chip);
      },
    );
  }
}

/// Makes [child] one unit of text selection: selected whole or not at all
/// (whenever the two selection edges fall on either side of it), and copied
/// as [text].
///
/// A leaf [Selectable] rather than a [SelectionContainer] around the label:
/// nested containers each replay the last edge positions they saw when
/// their content re-registers, which in a scrolling list goes stale.
class _SelectableToken extends SingleChildRenderObjectWidget {
  const _SelectableToken({required this.text, required super.child});

  final String text;

  @override
  _RenderSelectableToken createRenderObject(BuildContext context) =>
      _RenderSelectableToken(text, _selectionColor(context))
        ..registrar = SelectionContainer.maybeOf(context);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSelectableToken renderObject,
  ) {
    renderObject
      ..text = text
      ..selectionColor = _selectionColor(context)
      ..registrar = SelectionContainer.maybeOf(context);
  }

  static Color _selectionColor(BuildContext context) =>
      DefaultSelectionStyle.of(context).selectionColor ??
      AppColors.textSelection;
}

class _RenderSelectableToken extends RenderProxyBox
    with Selectable, SelectionRegistrant {
  _RenderSelectableToken(this.text, this._selectionColor);

  String text;

  Color _selectionColor;
  set selectionColor(Color value) {
    if (value == _selectionColor) return;
    _selectionColor = value;
    if (_selected) markNeedsPaint();
  }

  /// Which side of the tag each edge is on: false before, true after.
  bool? _startAfter;
  bool? _endAfter;

  bool get _selected =>
      _startAfter != null && _endAfter != null && _startAfter != _endAfter;

  // --- Where a point is -----------------------------------------------------

  /// Before or after the tag in reading order: above or left of it on its
  /// line is before; inside, the nearer half decides.
  bool _isAfter(Offset globalPosition) {
    final local = globalToLocal(globalPosition);
    if (local.dy < 0) return false;
    if (local.dy > size.height) return true;
    return local.dx > size.width / 2;
  }

  SelectionResult _resultFor(Offset globalPosition) {
    final local = globalToLocal(globalPosition);
    if (size.contains(local)) return SelectionResult.end;
    return _isAfter(globalPosition)
        ? SelectionResult.next
        : SelectionResult.previous;
  }

  // --- Selectable -------------------------------------------------------------

  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) {
    final wasSelected = _selected;
    final SelectionResult result;
    switch (event) {
      case SelectionEdgeUpdateEvent(:final globalPosition, :final type):
        final after = _isAfter(globalPosition);
        if (type == SelectionEventType.startEdgeUpdate) {
          _startAfter = after;
        } else {
          _endAfter = after;
        }
        result = _resultFor(globalPosition);
      case SelectAllSelectionEvent():
        _startAfter = false;
        _endAfter = true;
        result = SelectionResult.none;
      case ClearSelectionEvent():
        _startAfter = _endAfter = null;
        result = SelectionResult.none;
      case SelectWordSelectionEvent(:final globalPosition) ||
          SelectParagraphSelectionEvent(:final globalPosition):
        result = _resultFor(globalPosition);
        if (result == SelectionResult.end) {
          _startAfter = false;
          _endAfter = true;
        }
      default:
        result = SelectionResult.none;
    }
    if (_selected != wasSelected) {
      markNeedsPaint();
      _notifyListeners();
    }
    return result;
  }

  @override
  SelectionGeometry get value {
    if (!_selected) {
      return const SelectionGeometry(
        status: SelectionStatus.none,
        hasContent: true,
      );
    }
    final forward = _endAfter!;
    SelectionPoint point(bool right) => SelectionPoint(
      localPosition: Offset(right ? size.width : 0, size.height),
      lineHeight: size.height,
      handleType: right
          ? TextSelectionHandleType.right
          : TextSelectionHandleType.left,
    );
    return SelectionGeometry(
      status: SelectionStatus.uncollapsed,
      hasContent: true,
      startSelectionPoint: point(!forward),
      endSelectionPoint: point(forward),
      selectionRects: [Offset.zero & size],
    );
  }

  @override
  SelectedContent? getSelectedContent() =>
      _selected ? SelectedContent(plainText: text) : null;

  @override
  SelectedContentRange? getSelection() {
    if (!_selected) return null;
    final forward = _endAfter!;
    return SelectedContentRange(
      startOffset: forward ? 0 : text.length,
      endOffset: forward ? text.length : 0,
    );
  }

  @override
  int get contentLength => text.length;

  @override
  List<Rect> get boundingBoxes => [Offset.zero & size];

  @override
  void pushHandleLayers(LayerLink? startHandle, LayerLink? endHandle) {}

  final List<VoidCallback> _listeners = [];

  @override
  void addListener(VoidCallback listener) => _listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  void _notifyListeners() {
    for (final listener in [..._listeners]) {
      listener();
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    if (_selected) {
      context.canvas.drawRRect(
        RRect.fromRectAndRadius(offset & size, const Radius.circular(4)),
        Paint()..color = _selectionColor,
      );
    }
  }
}

/// Reports a baseline that puts the child's vertical center on the center of
/// the glyphs of [textStyle], so a baseline-aligned token sits optically
/// centered on the surrounding text regardless of what else is on the line.
class _CenteredOnText extends SingleChildRenderObjectWidget {
  const _CenteredOnText({required this.textStyle, required super.child});

  final TextStyle textStyle;

  /// Distance from the alphabetic baseline up to the glyph center.
  double _glyphCenterAboveBaseline(TextScaler scaler) {
    // The line's leading, if any, even above and below: as the font's own
    // metrics, else (proportional) more of it above, and the center higher.
    // (`copyWith(height: null)` keeps the height.)
    final painter = TextPainter(
      text: TextSpan(
        text: 'x',
        style: textStyle.copyWith(
          leadingDistribution: TextLeadingDistribution.even,
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout();
    final metrics = painter.computeLineMetrics().first;
    painter.dispose();
    return (metrics.ascent - metrics.descent) / 2;
  }

  @override
  _RenderCenteredOnText createRenderObject(BuildContext context) =>
      _RenderCenteredOnText(
        _glyphCenterAboveBaseline(MediaQuery.textScalerOf(context)),
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderCenteredOnText renderObject,
  ) {
    renderObject.centerAboveBaseline = _glyphCenterAboveBaseline(
      MediaQuery.textScalerOf(context),
    );
  }
}

class _RenderCenteredOnText extends RenderProxyBox {
  _RenderCenteredOnText(this._centerAboveBaseline);

  double _centerAboveBaseline;
  set centerAboveBaseline(double value) {
    if (value == _centerAboveBaseline) return;
    _centerAboveBaseline = value;
    markNeedsLayout();
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      size.height / 2 + _centerAboveBaseline;

  @override
  double? computeDryBaseline(
    BoxConstraints constraints,
    TextBaseline baseline,
  ) => getDryLayout(constraints).height / 2 + _centerAboveBaseline;
}

/// A file the kernel found, as a mention suggestion.
Suggestion fileSuggestion(FileSuggestion file) {
  final directory = file.isDirectory;
  final path = directory
      ? file.path.substring(0, file.path.length - 1)
      : file.path;
  final slash = path.lastIndexOf('/');
  return Suggestion(
    kind: directory ? SuggestionKind.folder : SuggestionKind.file,
    label: path.substring(slash + 1),
    detail: slash < 0 ? '' : path.substring(0, slash),
  );
}
