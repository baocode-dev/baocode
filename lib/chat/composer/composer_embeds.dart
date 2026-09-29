import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';

import '../../theme/cursor_theme.dart';
import '../../theme/material_file_icons.dart';
import '../widgets/file_label.dart';
import '../../kernel/kernel_types.dart';
import 'composer_mock_data.dart';

/// Inline, atomic token for an @mention or a /command. It occupies a single
/// character in the document, so the caret skips it and backspace deletes it
/// as a whole.
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

  /// Text a token contributes to the sent message and to plain-text copies.
  static String plainText(Object? data) {
    final token = decode(data);
    return token.kind == SuggestionKind.command
        ? '/${token.value}'
        : '@${token.value}';
  }
}

/// What can become a token: the kernel's `/commands` and the project's
/// `@mentions`, for the composer and the sent messages under it.
class ComposerVocabulary extends InheritedWidget {
  const ComposerVocabulary({
    super.key,
    required this.commands,
    required this.mentions,
    this.suggestFiles,
    required super.child,
  });

  final List<Suggestion> commands;
  final List<Suggestion> mentions;

  /// Looks files up as `@` is typed; given, any `@path` counts as a
  /// mention, not only those in [mentions].
  final Future<List<FileSuggestion>> Function(String query)? suggestFiles;

  /// Outside any: the mock project's mentions, no commands.
  static const fallback = ComposerVocabulary(
    commands: [],
    mentions: ComposerMockData.mentions,
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
      !identical(mentions, oldWidget.mentions) ||
      suggestFiles != oldWidget.suggestFiles;
}

/// A composer document for sent [text], the inverse of
/// [ComposerTokenEmbed.plainText]: see [composerDeltaFromPaste].
Delta composerDeltaFromText(String text, ComposerVocabulary vocabulary) =>
    composerDeltaFromPaste(text, vocabulary, atStart: true)..insert('\n');

/// [text] (plain, e.g. pasted) as composer content, without the document's
/// closing newline: `@value` of a known mention becomes a token again, and
/// so does a leading `/command` when the text goes [atStart] of the message
/// (where alone a command counts). Any other `@word` stays text: pasted text
/// is full of those (`@override`, handles).
Delta composerDeltaFromPaste(
  String text,
  ComposerVocabulary vocabulary, {
  required bool atStart,
}) {
  final delta = Delta();
  final buffer = StringBuffer();
  void flush() {
    if (buffer.isEmpty) return;
    delta.insert(buffer.toString());
    buffer.clear();
  }

  void token(Suggestion suggestion) {
    flush();
    delta.insert(ComposerTokenEmbed.fromSuggestion(suggestion).toJson());
  }

  // Where a token's value may end: not inside a path or word.
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
        token(command);
        i = 1 + command.value.length;
        break;
      }
    }
  }
  final mentions = longestFirst(vocabulary.mentions);
  while (i < text.length) {
    final atBoundary = i == 0 || text[i - 1].trim().isEmpty;
    if (text[i] == '@' && atBoundary) {
      final mention = mentions
          .where((m) => text.startsWith(m.value, i + 1))
          .where((m) => endsAt(i + 1 + m.value.length))
          .firstOrNull;
      if (mention != null) {
        token(mention);
        i += 1 + mention.value.length;
        continue;
      }
      if (vocabulary.suggestFiles != null) {
        var end = i + 1;
        while (end < text.length && valueChar.hasMatch(text[end])) {
          end++;
        }
        final path = text.substring(i + 1, end);
        if (path.contains('/') || path.contains('.')) {
          token(fileSuggestion(FileSuggestion(path)));
          i = end;
          continue;
        }
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
    return _SelectableToken(
      text: ComposerTokenEmbed.plainText(data),
      child: _CenteredOnText(
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
              decoration: BoxDecoration(
                color: isCommand
                    ? const Color(0x264C9DFF)
                    : CursorColors.surface,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isCommand
                      ? const Color(0x404C9DFF)
                      : CursorColors.borderStrong,
                ),
              ),
              child: switch (token.kind) {
                SuggestionKind.file => FileLabel(token.label, fontSize: 12),
                SuggestionKind.command => Text(
                  '/${token.label}',
                  style: const TextStyle(
                    color: CursorColors.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                _ => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (token.kind == SuggestionKind.folder)
                      FolderIcon(token.label, size: 14)
                    else
                      const Icon(
                        Icons.alternate_email_rounded,
                        size: 13,
                        color: CursorColors.textMuted,
                      ),
                    const SizedBox(width: 4),
                    Text(
                      token.label,
                      style: const TextStyle(
                        color: CursorColors.text,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              },
            ),
          ),
        ),
      ),
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
      const Color(0x664C9DFF);
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
