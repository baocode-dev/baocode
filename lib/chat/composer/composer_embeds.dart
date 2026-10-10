import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';

import '../../kernel/kernel_types.dart' show FileSuggestion;
import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/material_file_icons.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../chat_models.dart';
import '../floating/hover_tooltip.dart';
import '../widgets/file_label.dart';
import '../widgets/image_thumbnails.dart';
import 'composer_files.dart';
import 'composer_mock_data.dart';

/// Inline, atomic token for a file or folder, or a /command. It occupies a
/// single character in the document, so the caret skips it and backspace
/// deletes it as a whole.
class ComposerTokenEmbed {
  static const type = 'composer-token';

  static Embeddable fromSuggestion(Suggestion suggestion) => Embeddable(
    type,
    jsonEncode({
      'kind': suggestion.kind.name,
      'label': suggestion.label,
      'value': suggestion.value,
    }),
  );

  /// The file or folder at [path], as the message refers to it (see
  /// [displayPath]).
  static Embeddable file(String path, {bool directory = false}) => Embeddable(
    type,
    jsonEncode({
      'kind': (directory ? SuggestionKind.folder : SuggestionKind.file).name,
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
  static Embeddable session(String id, String title) => Embeddable(
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

  static Embeddable of(CodeReference reference) =>
      Embeddable(type, jsonEncode(reference.toJson()));

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

  static Embeddable of(PastedText pasted) =>
      Embeddable(type, jsonEncode(pasted.toJson()));

  static PastedText decode(Object? data) =>
      PastedText.fromJson(jsonDecode(data as String) as Map<String, Object?>);

  /// Text it contributes to the sent message and to plain-text copies.
  static String plainText(Object? data) => decode(data).reference;
}

/// Where what is dragged over the composer would go, released: the tags it
/// would put in, faint. Never sent; only there while the drag is.
class ComposerGhostEmbed {
  static const type = 'composer-ghost';

  static Embeddable of(List<ComposerFile> files) => Embeddable(
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

  static Embeddable of(int number) => Embeddable(type, '$number');

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

/// What can become a token besides dropped files: the kernel's `/commands`,
/// the project's files `@` looks up, and the other conversations to refer
/// to, for the composer and the sent messages under it.
class ComposerVocabulary extends InheritedWidget {
  const ComposerVocabulary({
    super.key,
    required this.commands,
    this.suggestFiles,
    this.sessions,
    required super.child,
  });

  final List<Suggestion> commands;

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
      (suggestFiles == null) != (oldWidget.suggestFiles == null);
}

/// A composer document for sent [text], the inverse of
/// [ComposerTokenEmbed.plainText]: see [composerDeltaFromPaste].
Delta composerDeltaFromText(
  String text,
  ComposerVocabulary vocabulary, {
  Set<int> images = const {},
}) =>
    composerDeltaFromPaste(text, vocabulary, atStart: true, images: images)
      ..insert('\n');

/// [text] (plain, e.g. pasted) as composer content, without the document's
/// closing newline: an `@path` becomes a file's token again (see
/// [parseFileReference]; `@override`, handles stay text), and so does a
/// leading `/command` when the text goes [atStart] of the message (where
/// alone a command counts). An `[Image #N]` becomes a reference again when
/// image N is among [images], and a `[path:12-30]` (or a `[Pasted text #1]`)
/// when what it refers to is in the [codeAppendix] at the end, which goes.
/// A `[Session id: …]`
/// becomes the conversation's token again (see [parseSessionReference]).
Delta composerDeltaFromPaste(
  String text,
  ComposerVocabulary vocabulary, {
  required bool atStart,
  Set<int> images = const {},
}) {
  final (body: body, references: code) = splitCodeAppendix(text);
  text = body;
  final delta = Delta();
  final buffer = StringBuffer();
  void flush() {
    if (buffer.isEmpty) return;
    delta.insert(buffer.toString());
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
        delta.insert(ComposerTokenEmbed.fromSuggestion(command).toJson());
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
        delta.insert(ComposerTokenEmbed.session(id, title).toJson());
        i = end;
        continue;
      }
      if (images.isNotEmpty) {
        if (imageReferencePattern.matchAsPrefix(text, i) case final match?
            when images.contains(int.parse(match[1]!))) {
          flush();
          delta.insert(ComposerImageEmbed.of(int.parse(match[1]!)).toJson());
          i = match.end;
          continue;
        }
      }
      if (code.isNotEmpty) {
        final close = text.indexOf(']', i);
        final reference = close < 0 ? null : code[text.substring(i, close + 1)];
        if (reference != null) {
          flush();
          delta.insert(switch (reference) {
            CodeReference() => ComposerCodeEmbed.of(reference).toJson(),
            PastedText() => ComposerPastedTextEmbed.of(reference).toJson(),
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
        delta.insert(
          ComposerTokenEmbed.file(path, directory: directory).toJson(),
        );
        i = end;
        continue;
      }
    }
    buffer.write(text[i]);
    i++;
  }
  flush();
  return delta;
}

class ComposerTokenEmbedBuilder extends EmbedBuilder {
  const ComposerTokenEmbedBuilder();

  @override
  String get key => ComposerTokenEmbed.type;

  @override
  bool get expanded => false;

  // Baseline alignment against a baseline we report ourselves (see
  // [_CenteredOnText]). `PlaceholderAlignment.middle` depends on the glyph
  // runs sharing the line, so a line holding only a token and a trailing
  // space laid out taller than one with text, and the composer jumped.
  @override
  WidgetSpan buildWidgetSpan(Widget widget) => WidgetSpan(
    alignment: PlaceholderAlignment.baseline,
    baseline: TextBaseline.alphabetic,
    child: widget,
  );

  @override
  String toPlainText(Embed node) =>
      ComposerTokenEmbed.plainText(node.value.data);

  @override
  Widget build(BuildContext context, EmbedContext embedContext) =>
      ComposerTokenChip(
        data: embedContext.node.value.data,
        textStyle: embedContext.textStyle,
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
    return _SelectableToken(
      text: ComposerTokenEmbed.plainText(data),
      child: tag,
    );
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

class ComposerCodeEmbedBuilder extends EmbedBuilder {
  const ComposerCodeEmbedBuilder();

  @override
  String get key => ComposerCodeEmbed.type;

  @override
  bool get expanded => false;

  // As a token's (see [ComposerTokenEmbedBuilder]).
  @override
  WidgetSpan buildWidgetSpan(Widget widget) => WidgetSpan(
    alignment: PlaceholderAlignment.baseline,
    baseline: TextBaseline.alphabetic,
    child: widget,
  );

  @override
  String toPlainText(Embed node) =>
      ComposerCodeEmbed.plainText(node.value.data);

  @override
  Widget build(BuildContext context, EmbedContext embedContext) =>
      ComposerCodeChip(
        data: embedContext.node.value.data,
        textStyle: embedContext.textStyle,
      );
}

/// The inline tag for lines of a file ([ComposerCodeEmbed] data), centered
/// on text of [textStyle]: the file's name and the lines, the lines
/// themselves on hover. In the composer and in sent messages alike.
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
        child: tag,
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

class ComposerPastedTextEmbedBuilder extends EmbedBuilder {
  const ComposerPastedTextEmbedBuilder();

  @override
  String get key => ComposerPastedTextEmbed.type;

  @override
  bool get expanded => false;

  // As a token's (see [ComposerTokenEmbedBuilder]).
  @override
  WidgetSpan buildWidgetSpan(Widget widget) => WidgetSpan(
    alignment: PlaceholderAlignment.baseline,
    baseline: TextBaseline.alphabetic,
    child: widget,
  );

  @override
  String toPlainText(Embed node) =>
      ComposerPastedTextEmbed.plainText(node.value.data);

  @override
  Widget build(BuildContext context, EmbedContext embedContext) =>
      ComposerPastedTextChip(
        data: embedContext.node.value.data,
        textStyle: embedContext.textStyle,
      );
}

/// The inline tag for a long paste ([ComposerPastedTextEmbed] data),
/// centered on text of [textStyle]: its number and its count of lines, its
/// first lines on hover. In the composer and in sent messages alike.
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
        content: (context) => _TextPreview(label: name, text: pasted.text),
        child: tag,
      ),
    );
  }
}

class ComposerGhostEmbedBuilder extends EmbedBuilder {
  const ComposerGhostEmbedBuilder();

  @override
  String get key => ComposerGhostEmbed.type;

  @override
  bool get expanded => false;

  // As a token's (see [ComposerTokenEmbedBuilder]).
  @override
  WidgetSpan buildWidgetSpan(Widget widget) => WidgetSpan(
    alignment: PlaceholderAlignment.baseline,
    baseline: TextBaseline.alphabetic,
    child: widget,
  );

  @override
  String toPlainText(Embed node) => '';

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final files = [
      for (final file in jsonDecode(
        embedContext.node.value.data as String,
      ) as List<dynamic>)
        file as Map<String, dynamic>,
    ];
    return _CenteredOnText(
      textStyle: embedContext.textStyle,
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

class ComposerImageEmbedBuilder extends EmbedBuilder {
  const ComposerImageEmbedBuilder();

  @override
  String get key => ComposerImageEmbed.type;

  @override
  bool get expanded => false;

  // As a token's (see [ComposerTokenEmbedBuilder]).
  @override
  WidgetSpan buildWidgetSpan(Widget widget) => WidgetSpan(
    alignment: PlaceholderAlignment.baseline,
    baseline: TextBaseline.alphabetic,
    child: widget,
  );

  @override
  String toPlainText(Embed node) =>
      ComposerImageEmbed.plainText(node.value.data);

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final number = ComposerImageEmbed.decode(embedContext.node.value.data);
    return ComposerImageChip(
      number: number,
      image: ComposerImages.of(context)[number],
      textStyle: embedContext.textStyle,
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
        content: (context) => ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240, maxHeight: 180),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.memory(
              image.bytes,
              fit: BoxFit.contain,
              cacheWidth: 720,
              gaplessPlayback: true,
            ),
          ),
        ),
        child: chip,
      );
    }
    return _SelectableToken(text: imageReference(number), child: chip);
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
    final painter = TextPainter(
      text: TextSpan(text: 'x', style: textStyle.copyWith(height: null)),
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
