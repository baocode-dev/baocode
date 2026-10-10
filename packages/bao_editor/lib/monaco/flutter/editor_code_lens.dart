// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See lib/monaco/LICENSE.txt.
//
// CodeLens, adapted from VS Code 1.135.0
// (08d4889f9ec4a1685d257b9b95de036c8e1ce1e5)
// src/vs/editor/contrib/codelens/browser:
// - codeLensCache/codelensController.ts: lenses grouped by the line they
//   start on, each group a view zone above its line; lenses without a
//   command are resolved when they come into view (debounced), and their
//   ranges follow edits (`collapseOnReplaceEdit`);
// - codelensWidget.ts/.css: the zone is `(fontSize * max(1.3,
//   lineHeight / fontSize)) | 0` tall for a font `(editorFontSize * 0.9) | 0`
//   big, its text starts at the line's first non-blank column, titles
//   (with `$(icon)`s) are joined by `&nbsp;|&nbsp;`, those with a command
//   id are links (`editorCodeLens.foreground`, hovered
//   `editorLink.activeForeground`, a pointer) and the others plain text.
//
// Deviations: lenses are given by the caller (no providers or cache); a
// lens's tooltip shows as a plain [Tooltip].

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' show Tooltip;
import 'package:flutter/widgets.dart';

import '../vs/editor/common/core/position.dart';
import '../vs/editor/common/core/range.dart';
import 'document_snapshot.dart';
import 'editor_decorations.dart';
import 'editor_document_model.dart';
import 'editor_surface.dart' show EditorViewZone;
import 'editor_tracked_decorations.dart';

/// A command (`Command`) of a CodeLens or inlay hint: [title] may hold
/// `$(icon)`s; [id] is empty for a lens that only shows text.
@immutable
class EditorCommand {
  const EditorCommand({
    required this.title,
    this.id = '',
    this.tooltip,
    this.arguments,
  });

  final String title;
  final String id;
  final String? tooltip;
  final List<Object?>? arguments;
}

/// A CodeLens over [range]; one without a [command] is resolved before it
/// shows (see [EditorCodeLensController.resolve]). [data] is the caller's.
@immutable
class EditorCodeLens {
  const EditorCodeLens({required this.range, this.command, this.data});

  final Range range;
  final EditorCommand? command;
  final Object? data;

  EditorCodeLens withCommand(EditorCommand? command) =>
      EditorCodeLens(range: range, command: command, data: data);
}

/// Colors of CodeLens zones.
@immutable
class EditorCodeLensColors {
  const EditorCodeLensColors({
    this.foreground = const Color(0xff999999),
    this.linkForeground = const Color(0xff4e94ce),
  });

  factory EditorCodeLensColors.from(Color? Function(String id) colors) =>
      EditorCodeLensColors(
        foreground:
            colors('editorCodeLens.foreground') ?? const Color(0xff999999),
        linkForeground:
            colors('editorLink.activeForeground') ?? const Color(0xff4e94ce),
      );

  /// `editorCodeLens.foreground`.
  final Color foreground;

  /// `editorLink.activeForeground`, under the pointer.
  final Color linkForeground;

  @override
  bool operator ==(Object other) =>
      other is EditorCodeLensColors &&
      other.foreground == foreground &&
      other.linkForeground == linkForeground;

  @override
  int get hashCode => Object.hash(foreground, linkForeground);
}

/// The CodeLenses of one document (`CodeLensContribution`, reduced): set
/// them with [setLenses], give the controller to the surface's `codeLens`
/// (which shows its [zones] and reports what is in view), and handle
/// [onCommand].
class EditorCodeLensController extends ChangeNotifier {
  EditorCodeLensController(
    this.document, {
    this.resolve,
    this.onCommand,
    this.resolveDelay = const Duration(milliseconds: 250),
  }) : _tracked = EditorTrackedDecorations(document) {
    _tracked.addListener(_onMoved);
  }

  final EditorDocumentModel document;

  /// `resolveCodeLens`: the lens with its command (null keeps it as is).
  Future<EditorCodeLens?> Function(EditorCodeLens lens)? resolve;

  /// A click on a lens's command (`executeCommand`).
  void Function(EditorCodeLens lens, EditorCommand command)? onCommand;

  /// How long the view must rest before lenses in it resolve.
  final Duration resolveDelay;

  final EditorTrackedDecorations _tracked;
  final Object _owner = Object();
  List<EditorCodeLens> _lenses = const [];
  final Set<int> _resolving = {};
  int _generation = 0;
  Timer? _resolveTimer;
  ({int first, int last})? _viewport;
  List<_Group>? _groups;
  bool _disposed = false;

  /// The lenses, with their resolved commands and set ranges.
  List<EditorCodeLens> get lenses => List.unmodifiable(_lenses);

  /// Replaces the lenses (a provider's new result).
  void setLenses(List<EditorCodeLens> lenses) {
    _generation++;
    _resolving.clear();
    _lenses = List.of(lenses);
    final snapshot = document.snapshot;
    _tracked.set(_owner, [
      for (final (index, lens) in _lenses.indexed)
        () {
          final start = snapshot.offsetAtPosition(
            lens.range.getStartPosition(),
          );
          final end = snapshot.offsetAtPosition(lens.range.getEndPosition());
          return EditorTrackedDecoration(
            start: start,
            end: math.max(start, end),
            decoration: EditorDecoration(start: start, end: end),
            stickiness: TrackedRangeStickiness.neverGrowsWhenTypingAtEdges,
            collapseOnReplaceEdit: true,
            data: index,
          );
        }(),
    ]);
    _scheduleResolve();
  }

  /// Removes all lenses.
  void clear() => setLenses(const []);

  void _onMoved() {
    _groups = null;
    if (!_disposed) notifyListeners();
  }

  /// The lenses by the (current) line they start on, in line order.
  List<_Group> get _grouped {
    final cached = _groups;
    if (cached != null) return cached;
    final snapshot = document.snapshot;
    final byLine = <int, List<int>>{};
    for (final range in _tracked.rangesOf(_owner)) {
      final line = snapshot.positionAtOffset(range.start).lineNumber;
      (byLine[line] ??= []).add(range.data! as int);
    }
    final lines = byLine.keys.toList()..sort();
    return _groups = [for (final line in lines) _Group(line, byLine[line]!)];
  }

  /// The surface's visible model lines, after it lays out: lenses there
  /// resolve once it rests for [resolveDelay].
  void viewportChanged(int firstLine, int lastLine) {
    final viewport = (first: firstLine, last: lastLine);
    if (viewport == _viewport) return;
    _viewport = viewport;
    _scheduleResolve();
  }

  void _scheduleResolve() {
    _resolveTimer?.cancel();
    if (resolve == null || _viewport == null) return;
    _resolveTimer = Timer(resolveDelay, _resolveInView);
  }

  /// `resolveCodeLensesInViewport`.
  void _resolveInView() {
    final resolve = this.resolve;
    final viewport = _viewport;
    if (resolve == null || viewport == null || _disposed) return;
    final generation = _generation;
    for (final group in _grouped) {
      // A zone above the first line in view is in view too.
      if (group.lineNumber < viewport.first ||
          group.lineNumber > viewport.last + 1) {
        continue;
      }
      for (final index in group.lenses) {
        if (_lenses[index].command != null || !_resolving.add(index)) continue;
        unawaited(
          resolve(_lenses[index]).then(
            (resolved) {
              if (_disposed || generation != _generation) return;
              _resolving.remove(index);
              if (resolved?.command == null) return;
              _lenses[index] = _lenses[index].withCommand(resolved!.command);
              _groups = null;
              notifyListeners();
            },
            onError: (Object _) {
              if (generation == _generation) _resolving.remove(index);
            },
          ),
        );
      }
    }
  }

  /// One zone per line with lenses, in an editor whose text is [style]
  /// and lines [lineHeight] tall. Titles' `$(name)` icons come from
  /// [icon] (left as text without it).
  List<EditorViewZone> zones({
    required TextStyle style,
    required double lineHeight,
    EditorCodeLensColors colors = const EditorCodeLensColors(),
    IconData? Function(String name)? icon,
    int tabSize = 4,
  }) {
    final groups = _grouped;
    if (groups.isEmpty || lineHeight <= 0) return const [];
    final editorFontSize = style.fontSize ?? 14;
    final fontSize = (editorFontSize * 0.9).floorToDouble();
    final height = (fontSize * math.max(1.3, lineHeight / fontSize))
        .floorToDouble();
    final snapshot = document.snapshot;
    return [
      for (final group in groups)
        EditorViewZone(
          afterLineNumber: group.lineNumber - 1,
          heightInLines: height / lineHeight,
          interactive: true,
          content: _CodeLensLine(
            indent: _indentation(snapshot, group.lineNumber, tabSize),
            style: style,
            fontSize: fontSize,
            colors: colors,
            icon: icon,
            lenses: [for (final index in group.lenses) _lenses[index]],
            onCommand: onCommand,
          ),
        ),
    ];
  }

  /// The line's leading whitespace, tabs as spaces.
  static String _indentation(
    DocumentSnapshot snapshot,
    int lineNumber,
    int tabSize,
  ) {
    final text = snapshot.text;
    final start = snapshot.lineStarts[lineNumber - 1];
    final end = snapshot.contentEnds[lineNumber - 1];
    final buffer = StringBuffer();
    for (var i = start; i < end; i++) {
      final char = text.codeUnitAt(i);
      if (char == 0x20) {
        buffer.write(' ');
      } else if (char == 0x09) {
        buffer.write(' ' * (tabSize - buffer.length % tabSize));
      } else {
        break;
      }
    }
    return buffer.toString();
  }

  /// The one-based position where [lens] currently starts.
  Position? positionOf(EditorCodeLens lens) {
    final index = _lenses.indexOf(lens);
    if (index < 0) return null;
    for (final range in _tracked.rangesOf(_owner)) {
      if (range.data == index) return document.positionAtOffset(range.start);
    }
    return null;
  }

  @override
  void dispose() {
    _disposed = true;
    _resolveTimer?.cancel();
    _tracked
      ..removeListener(_onMoved)
      ..dispose();
    super.dispose();
  }
}

class _Group {
  const _Group(this.lineNumber, this.lenses);

  final int lineNumber;

  /// Indices into the lenses.
  final List<int> lenses;
}

/// `CodeLensContentWidget`: the line's indentation, then the titles.
class _CodeLensLine extends StatefulWidget {
  const _CodeLensLine({
    required this.indent,
    required this.style,
    required this.fontSize,
    required this.colors,
    required this.icon,
    required this.lenses,
    required this.onCommand,
  });

  final String indent;
  final TextStyle style;
  final double fontSize;
  final EditorCodeLensColors colors;
  final IconData? Function(String name)? icon;
  final List<EditorCodeLens> lenses;
  final void Function(EditorCodeLens lens, EditorCommand command)? onCommand;

  @override
  State<_CodeLensLine> createState() => _CodeLensLineState();
}

class _CodeLensLineState extends State<_CodeLensLine> {
  int? _hovered;

  static final RegExp _iconPattern = RegExp(r'\$\(([a-z0-9\-]+)(?:~[a-z]+)?\)');

  List<InlineSpan> _title(String title, TextStyle style) {
    final icon = widget.icon;
    if (icon == null) return [TextSpan(text: title, style: style)];
    final spans = <InlineSpan>[];
    var last = 0;
    for (final match in _iconPattern.allMatches(title)) {
      final data = icon(match[1]!);
      if (data == null) continue;
      if (match.start > last) {
        spans.add(TextSpan(text: title.substring(last, match.start)));
      }
      spans.add(
        TextSpan(
          text: String.fromCharCode(data.codePoint),
          style: TextStyle(
            fontFamily: data.fontFamily,
            package: data.fontPackage,
            fontStyle: FontStyle.normal,
          ),
        ),
      );
      last = match.end;
    }
    if (last < title.length) spans.add(TextSpan(text: title.substring(last)));
    return [TextSpan(style: style, children: spans)];
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.style.copyWith(
      fontSize: widget.fontSize,
      height: 1,
      color: widget.colors.foreground,
      decoration: TextDecoration.none,
      backgroundColor: null,
    );
    final children = <InlineSpan>[];
    final commands = [
      for (final lens in widget.lenses)
        if (lens.command case final command?) (lens, command),
    ];
    for (final (index, (lens, command)) in commands.indexed) {
      // `&nbsp;|&nbsp;`
      if (index > 0) children.add(const TextSpan(text: '\u00a0|\u00a0'));
      final link = command.id.isNotEmpty;
      final hovered = link && _hovered == index;
      final style = hovered
          ? TextStyle(color: widget.colors.linkForeground)
          : const TextStyle();
      final spans = _title(command.title, style);
      final tooltip = command.tooltip;
      if (!link && (tooltip == null || tooltip.isEmpty)) {
        // `<span>`: plain text.
        children.add(TextSpan(style: style, children: spans));
        continue;
      }
      Widget label = Text.rich(
        TextSpan(style: base, children: spans),
        textScaler: TextScaler.noScaling,
        softWrap: false,
      );
      if (tooltip != null && tooltip.isNotEmpty) {
        label = Tooltip(message: tooltip, child: label);
      }
      if (link) {
        // `<a>`: the link color under the pointer, and a click runs it.
        label = MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = index),
          onExit: (_) => setState(() => _hovered = null),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onCommand?.call(lens, command),
            child: label,
          ),
        );
      }
      children.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: label,
        ),
      );
    }
    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text.rich(
          TextSpan(
            children: [
              // The indentation in the editor's font keeps the titles over
              // the line's first character.
              TextSpan(
                text: widget.indent,
                style: widget.style.copyWith(
                  color: const Color(0x00000000),
                  height: 1,
                  decoration: TextDecoration.none,
                ),
              ),
              TextSpan(
                text: commands.isEmpty ? ' ' : null,
                style: base,
                children: children,
              ),
            ],
          ),
          textScaler: TextScaler.noScaling,
          softWrap: false,
          maxLines: 1,
          overflow: TextOverflow.clip,
        ),
      ),
    );
  }
}
