// The extensions' CodeLenses, inlay hints and inline completions in the
// editor on screen: asked of the provider registries as the text, the
// scroll position and the providers change, and painted through the
// editor's features (lib/ide/ide_editor_features.dart).
//
// Follows VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/editor/contrib/codelens/browser/codelensController.ts (refresh on
// content, provider and `onDidChange` events, debounced; resolve what
// scrolls into view; run the command clicked), src/vs/editor/contrib/
// inlayHints/browser/inlayHintsController.ts (the visible ranges, refreshed
// as they scroll; a label part's command or location on click), and
// src/vs/editor/contrib/inlineCompletions/browser/model/
// inlineCompletionsModel.ts (asked as the user types at one caret; the
// first item shown; `handleItemDidShow`, the item's command on accept, the
// result disposed when replaced), and src/vs/editor/contrib/colorPicker/
// browser/colorDetector.ts (every provider's colors, debounced on content
// and provider changes, `editor.colorDecorators` and
// `editor.colorDecoratorsLimit`; the picker asks the color's provider for
// presentations at the color's current range).
//
// Deviations: one inline completion shows (no cycling through the others);
// its `additionalTextEdits` are not applied; inlay hints are asked for the
// lines on screen without the extra margin upstream adds; no default color
// provider (`editor.defaultColorDecorators`): colors come from extensions.

import 'dart:async';
import 'dart:ui' show Color;

import 'package:bao_editor/monaco/flutter/document_snapshot.dart';
import 'package:bao_editor/monaco/flutter/editor_document_model.dart'
    show EditorOffsetEdit;
import 'package:bao_editor/monaco/flutter/editor_code_lens.dart';
import 'package:bao_editor/monaco/flutter/editor_decoration_types.dart'
    show EditorDecorationTypeRegistry;
import 'package:bao_editor/monaco/flutter/editor_inlay_hints.dart';
import 'package:bao_editor/monaco/flutter/editor_inline_suggest.dart';
import 'package:bao_editor/monaco/vs/editor/common/core/position.dart';
import 'package:bao_editor/monaco/vs/editor/common/core/range.dart';
import 'package:bao_editor/monaco/vs/editor/common/decoration_render_options.dart';
import 'package:bao_editor/monaco/vs/editor/contrib/folding/browser/folding_ranges.dart'
    show FoldRange;
import 'package:bao_editor/monaco/vs/editor/contrib/snippet/browser/snippet_parser.dart';
import 'package:bao_exthost/bao_exthost.dart' show VsUri;

import '../../ide/ide_editor_colors.dart';
import '../../ide/ide_editor_links.dart';
import '../../ide/ide_editor_views.dart';
import '../language/language_features_service.dart';
import '../language/language_types.dart' as lang;
import '../language/registry_language_features.dart';

/// Reads an editor setting for a language (`editor.codeLens`…).
typedef EditorSettingReader = Object? Function(String key, String? languageId);

/// The extensions' editor features of an IDE workspace's editor on screen.
final class ExtensionEditorFeatureDriver {
  ExtensionEditorFeatureDriver({
    required this.views,
    required this.languages,
    required this.service,
    required this.executeCommand,
    required this.openLocation,
    required this.openLink,
    this.languageIdOf,
    this.setting,
    this.codeLensDelay = const Duration(milliseconds: 250),
    this.inlayHintsDelay = const Duration(milliseconds: 250),
    this.highlightDelay = const Duration(milliseconds: 250),
    this.foldingDelay = const Duration(milliseconds: 250),
    this.linkDelay = const Duration(milliseconds: 250),
    this.colorDelay = const Duration(milliseconds: 250),
    this.inlineDelay = const Duration(milliseconds: 50),
  }) {
    views.addListener(_activeChanged);
    _viewChanges = views.changes.listen(_viewChanged);
    _providers = service.onDidChangeProviders.listen((_) => _refreshAll());
    _activeChanged();
  }

  final IdeEditorViews views;
  final RegistryLanguageFeatures languages;
  final LanguageFeaturesService service;

  /// Runs a command (a CodeLens', an inlay hint's, an inline
  /// completion's).
  final Future<Object?> Function(String id, List<Object?> args) executeCommand;

  /// Opens a location (an inlay hint part's).
  final Future<void> Function(VsUri uri, Range range) openLocation;

  /// Opens a resolved document link; the workbench handles its URI scheme.
  final Future<void> Function(VsUri uri) openLink;

  /// The language id of a document's path, for language-specific settings.
  final String? Function(String path)? languageIdOf;
  final EditorSettingReader? setting;

  final Duration codeLensDelay;
  final Duration inlayHintsDelay;
  final Duration highlightDelay;
  final Duration foldingDelay;
  final Duration linkDelay;
  final Duration colorDelay;
  final Duration inlineDelay;

  static const _highlightColors = {
    'baocode.occurrence.text': 'editor.wordHighlightTextBackground',
    'baocode.occurrence.read': 'editor.wordHighlightBackground',
    'baocode.occurrence.write': 'editor.wordHighlightStrongBackground',
  };

  late final StreamSubscription<IdeEditorView> _viewChanges;
  late final StreamSubscription<void> _providers;
  IdeEditorView? _view;
  StreamSubscription<Object?>? _changes;
  final List<StreamSubscription<void>> _providerChanges = [];
  Timer? _codeLensTimer;
  Timer? _inlayTimer;
  Timer? _highlightTimer;
  Timer? _foldingTimer;
  Timer? _linkTimer;
  Timer? _colorTimer;
  Timer? _inlineTimer;
  int _codeLensGeneration = 0;
  int _inlayGeneration = 0;
  int _highlightGeneration = 0;
  int _foldingGeneration = 0;
  int _linkGeneration = 0;
  int _colorGeneration = 0;
  int _inlineGeneration = 0;
  DocumentSnapshot? _highlightSnapshot;
  int? _highlightOffset;
  bool? _highlightEnabled;
  EditorDecorationTypeRegistry? _highlightTypes;
  ({int first, int last})? _inlayLines;
  List<InlineCompletionsResult> _inlineResults = const [];
  bool _disposed = false;

  bool _enabled(String key, {Object? off = false}) {
    final view = _view;
    if (view == null) return false;
    final value = setting?.call(key, languageIdOf?.call(view.document.path));
    return value != off;
  }

  void _activeChanged() {
    final view = views.active;
    if (identical(view, _view)) return;
    _detach();
    _view = view;
    if (view == null) return;
    final features = view.features;
    _registerHighlightTypes(features.types);
    features.codeLens
      ..resolve = ((lens) => _resolveCodeLens(view, lens))
      ..onCommand = (lens, command) => unawaited(_run(command));
    features.inlayHints.onActivate = (part) => unawaited(_activateHint(part));
    features.inlineSuggest
      ..onAccepted = _inlineAccepted
      ..onDismissed = (_) => _clearInline();
    features.links.onOpen = (link, snapshot) =>
        unawaited(_openDocumentLink(view, snapshot, link));
    features.colors.onPresentations = (color, start, end, value) =>
        _colorPresentations(view, color, start, end, value);
    _changes = view.controller.document.changes.listen((event) {
      _scheduleCodeLens();
      _scheduleInlayHints();
      _scheduleHighlights();
      _scheduleFolding();
      _scheduleLinks();
      _scheduleColors();
      if (!event.isUndoing && !event.isRedoing) _scheduleInline(event);
    });
    _watchProviders(view);
    _scheduleCodeLens(immediately: true);
    _scheduleInlayHints(immediately: true);
    _scheduleHighlights(immediately: true);
    _scheduleFolding(immediately: true);
    _scheduleLinks(immediately: true);
    _scheduleColors(immediately: true);
  }

  void _registerHighlightTypes(EditorDecorationTypeRegistry types) {
    if (identical(_highlightTypes, types)) return;
    for (final key in _highlightColors.keys) {
      _highlightTypes?.removeDecorationType(key);
    }
    _highlightTypes = types;
    for (final entry in _highlightColors.entries) {
      types.registerDecorationType(
        entry.key,
        DecorationRenderOptions(backgroundColor: ThemeColorValue(entry.value)),
      );
    }
  }

  /// `editor.action.wordHighlight.trigger` (upstream
  /// `WordHighlighter.restore(250)`): the shown editor's occurrences
  /// looked up again after [highlightDelay], unless turned off.
  void restoreHighlights() {
    _highlightSnapshot = null;
    _scheduleHighlights();
  }

  void _clearHighlights(IdeEditorView view) {
    for (final key in _highlightColors.keys) {
      view.features.decorations.removeDecorationsByType(key);
    }
  }

  void _detach() {
    unawaited(_changes?.cancel());
    _changes = null;
    for (final subscription in _providerChanges) {
      unawaited(subscription.cancel());
    }
    _providerChanges.clear();
    _codeLensTimer?.cancel();
    _inlayTimer?.cancel();
    _highlightTimer?.cancel();
    _foldingTimer?.cancel();
    _linkTimer?.cancel();
    _colorTimer?.cancel();
    _inlineTimer?.cancel();
    _codeLensGeneration++;
    _inlayGeneration++;
    _highlightGeneration++;
    _foldingGeneration++;
    _linkGeneration++;
    _colorGeneration++;
    _inlineGeneration++;
    _inlayLines = null;
    _highlightSnapshot = null;
    _highlightOffset = null;
    _highlightEnabled = null;
    final view = _view;
    if (view != null) {
      _clearHighlights(view);
      view.setFoldingRanges?.call(null);
      view.features.links
        ..setLinks(null, const [])
        ..onOpen = null;
      view.features.colors
        ..closePicker()
        ..clear()
        ..onPresentations = null;
      view.features.codeLens
        ..resolve = null
        ..onCommand = null;
      view.features.inlayHints.onActivate = null;
      view.features.inlineSuggest
        ..onAccepted = null
        ..onDismissed = null;
    }
    _disposeInline();
    _view = null;
  }

  /// Providers that say their results changed (`onDidChange`) refresh the
  /// editor's.
  void _watchProviders(IdeEditorView view) {
    for (final subscription in _providerChanges) {
      unawaited(subscription.cancel());
    }
    _providerChanges.clear();
    final doc = languages.documents.documentForPath(view.document.path);
    if (doc == null) return;
    for (final provider in service.codeLensProvider.ordered(doc)) {
      if (provider.onDidChange case final changes?) {
        _providerChanges.add(changes.listen((_) => _scheduleCodeLens()));
      }
    }
    for (final provider in service.inlayHintsProvider.ordered(doc)) {
      if (provider.onDidChangeInlayHints case final changes?) {
        _providerChanges.add(changes.listen((_) => _scheduleInlayHints()));
      }
    }
    for (final provider in service.foldingRangeProvider.ordered(doc)) {
      if (provider.onDidChange case final changes?) {
        _providerChanges.add(changes.listen((_) => _scheduleFolding()));
      }
    }
  }

  void _refreshAll() {
    final view = _view;
    if (view == null) return;
    _watchProviders(view);
    _scheduleCodeLens();
    _scheduleInlayHints();
    _highlightSnapshot = null;
    _scheduleHighlights();
    _scheduleFolding();
    _scheduleLinks();
    _scheduleColors();
  }

  void _viewChanged(IdeEditorView view) {
    if (!identical(view, _view)) return;
    _scheduleHighlights();
    final lines = view.visibleLines();
    if (lines == null) return;
    view.features.codeLens.viewportChanged(lines.first, lines.last);
    if (lines != _inlayLines) _scheduleInlayHints();
  }

  // --- CodeLens ------------------------------------------------------------

  void _scheduleCodeLens({bool immediately = false}) {
    _codeLensTimer?.cancel();
    if (_disposed || _view == null) return;
    _codeLensTimer = Timer(
      immediately ? Duration.zero : codeLensDelay,
      () => unawaited(_updateCodeLenses()),
    );
  }

  Future<void> _updateCodeLenses() async {
    final view = _view;
    if (view == null) return;
    final generation = ++_codeLensGeneration;
    if (!_enabled('editor.codeLens')) {
      view.features.codeLens.clear();
      return;
    }
    final lenses = await languages.codeLenses(view.document.path);
    if (_disposed || generation != _codeLensGeneration) return;
    view.features.codeLens.setLenses([
      for (final lens in lenses)
        EditorCodeLens(
          range: lens.range as Range,
          command: _editorCommand(lens.command),
          data: lens,
        ),
    ]);
    if (view.visibleLines() case final lines?) {
      view.features.codeLens.viewportChanged(lines.first, lines.last);
    }
  }

  Future<EditorCodeLens?> _resolveCodeLens(
    IdeEditorView view,
    EditorCodeLens lens,
  ) async {
    final original = lens.data;
    if (original is! lang.CodeLens) return lens;
    final resolved = await languages.resolveCodeLens(
      view.document.path,
      original,
    );
    return EditorCodeLens(
      range: resolved.range as Range,
      command: _editorCommand(resolved.command),
      data: resolved,
    );
  }

  static EditorCommand? _editorCommand(lang.Command? command) => command == null
      ? null
      : EditorCommand(
          id: command.id,
          title: command.title,
          tooltip: command.tooltip,
          arguments: command.arguments,
        );

  Future<void> _run(EditorCommand command) async {
    if (command.id.isEmpty) return;
    try {
      await executeCommand(command.id, command.arguments ?? const []);
    } on Object {
      // The command reports its own failure.
    }
  }

  // --- Inlay hints ---------------------------------------------------------

  void _scheduleInlayHints({bool immediately = false}) {
    _inlayTimer?.cancel();
    if (_disposed || _view == null) return;
    _inlayTimer = Timer(
      immediately ? Duration.zero : inlayHintsDelay,
      () => unawaited(_updateInlayHints()),
    );
  }

  Future<void> _updateInlayHints() async {
    final view = _view;
    if (view == null) return;
    final generation = ++_inlayGeneration;
    if (!_enabled('editor.inlayHints.enabled', off: 'off')) {
      view.features.inlayHints.clear();
      return;
    }
    final snapshot = view.controller.document.snapshot;
    final lines =
        view.visibleLines() ??
        (first: 1, last: snapshot.lineCount.clamp(1, 200));
    _inlayLines = lines;
    final last = lines.last.clamp(1, snapshot.lineCount);
    final first = lines.first.clamp(1, last);
    final lastLength =
        snapshot.contentEnds[last - 1] - snapshot.lineStarts[last - 1];
    final hints = await languages.inlayHints(
      view.document.path,
      Range(first, 1, last, lastLength + 1),
    );
    if (_disposed || generation != _inlayGeneration) return;
    view.features.inlayHints.setHints([
      for (final hint in hints)
        EditorInlayHint(
          position: hint.position as Position,
          label: [
            for (final part in hint.label)
              EditorInlayHintLabelPart(
                part.label,
                tooltip: part.tooltip?.value,
                command: _editorCommand(part.command),
                location: part.location,
              ),
          ],
          kind: switch (hint.kind) {
            lang.InlayHintKind.type => EditorInlayHintKind.type,
            lang.InlayHintKind.parameter => EditorInlayHintKind.parameter,
            null => null,
          },
          tooltip: hint.tooltip?.value,
          paddingLeft: hint.paddingLeft,
          paddingRight: hint.paddingRight,
          data: hint,
        ),
    ]);
  }

  Future<void> _activateHint(EditorInlayHintPart part) async {
    if (part.part.command case final command?) {
      await _run(command);
    } else if (part.part.location case final lang.Location location) {
      await openLocation(location.uri, location.range as Range);
    }
  }

  // --- Document highlights -------------------------------------------------

  void _scheduleHighlights({bool immediately = false}) {
    final view = _view;
    if (_disposed || view == null) return;
    final snapshot = view.controller.document.snapshot;
    final selections = view.controller.selections;
    final offset =
        view.hasFocus() &&
            selections.length == 1 &&
            selections.first.isCollapsed
        ? selections.first.extentOffset
        : null;
    final preference = setting?.call(
      'editor.occurrencesHighlight',
      languageIdOf?.call(view.document.path),
    );
    final enabled = preference != false && preference != 'off';
    if (identical(snapshot, _highlightSnapshot) &&
        offset == _highlightOffset &&
        enabled == _highlightEnabled) {
      return;
    }
    _highlightSnapshot = snapshot;
    _highlightOffset = offset;
    _highlightEnabled = enabled;
    _highlightTimer?.cancel();
    final generation = ++_highlightGeneration;
    if (offset == null || !enabled) {
      _clearHighlights(view);
      return;
    }
    _highlightTimer = Timer(
      immediately ? Duration.zero : highlightDelay,
      () => unawaited(_updateHighlights(view, snapshot, offset, generation)),
    );
  }

  Future<void> _updateHighlights(
    IdeEditorView view,
    DocumentSnapshot snapshot,
    int offset,
    int generation,
  ) async {
    final highlights = await languages.documentHighlights(
      view.document.path,
      snapshot.positionAtOffset(offset),
    );
    if (_disposed ||
        generation != _highlightGeneration ||
        !identical(view, _view) ||
        !identical(snapshot, view.controller.document.snapshot)) {
      return;
    }
    for (final key in _highlightColors.keys) {
      final kind = switch (key) {
        'baocode.occurrence.read' => lang.DocumentHighlightKind.read,
        'baocode.occurrence.write' => lang.DocumentHighlightKind.write,
        _ => lang.DocumentHighlightKind.text,
      };
      view.features.decorations.setDecorations(key, [
        for (final highlight in highlights ?? const <lang.DocumentHighlight>[])
          if ((highlight.kind ?? lang.DocumentHighlightKind.text) == kind)
            DecorationOptions(range: highlight.range as Range),
      ]);
    }
  }

  // --- Folding ranges ------------------------------------------------------

  void _scheduleFolding({bool immediately = false}) {
    final view = _view;
    if (_disposed || view == null || view.setFoldingRanges == null) return;
    _foldingTimer?.cancel();
    final generation = ++_foldingGeneration;
    _foldingTimer = Timer(
      immediately ? Duration.zero : foldingDelay,
      () => unawaited(_updateFolding(view, generation)),
    );
  }

  Future<void> _updateFolding(IdeEditorView view, int generation) async {
    final snapshot = view.controller.document.snapshot;
    final results = await languages.foldingRanges(view.document.path);
    if (_disposed ||
        generation != _foldingGeneration ||
        !identical(view, _view) ||
        !identical(snapshot, view.controller.document.snapshot)) {
      return;
    }
    if (results == null) {
      view.setFoldingRanges!(null);
      return;
    }
    final sorted = [...results]
      ..sort((a, b) {
        final start = a.range.start.compareTo(b.range.start);
        if (start != 0) return start;
        final rank = a.rank.compareTo(b.rank);
        return rank != 0 ? rank : b.range.end.compareTo(a.range.end);
      });
    view.setFoldingRanges!([
      for (final result in sorted)
        FoldRange(
          startLineNumber: result.range.start,
          endLineNumber: result.range.end,
          type: result.range.kind?.value,
        ),
    ]);
  }

  // --- Document links ------------------------------------------------------

  void _scheduleLinks({bool immediately = false}) {
    final view = _view;
    if (_disposed || view == null) return;
    _linkTimer?.cancel();
    final generation = ++_linkGeneration;
    // Do not leave clickable ranges from an older document snapshot on screen.
    view.features.links.setLinks(null, const []);
    _linkTimer = Timer(
      immediately ? Duration.zero : linkDelay,
      () => unawaited(_updateLinks(view, generation)),
    );
  }

  Future<void> _updateLinks(IdeEditorView view, int generation) async {
    final snapshot = view.controller.document.snapshot;
    final links = await languages.documentLinks(view.document.path);
    if (_disposed ||
        generation != _linkGeneration ||
        !identical(view, _view) ||
        !identical(snapshot, view.controller.document.snapshot)) {
      return;
    }
    view.features.links.setLinks(snapshot, [
      for (final link in links)
        if (link.range case final Range range)
          EditorDocumentLink(
            snapshot.offsetAtPosition(range.getStartPosition()),
            snapshot.offsetAtPosition(range.getEndPosition()),
            tooltip: link.tooltip,
            data: link,
          ),
    ]);
  }

  Future<void> _openDocumentLink(
    IdeEditorView view,
    DocumentSnapshot snapshot,
    EditorDocumentLink link,
  ) async {
    if (_disposed ||
        !identical(view, _view) ||
        !identical(snapshot, view.controller.document.snapshot) ||
        link.data is! lang.Link) {
      return;
    }
    final resolved = await languages.resolveLink(link.data! as lang.Link);
    if (_disposed ||
        !identical(view, _view) ||
        !identical(snapshot, view.controller.document.snapshot)) {
      return;
    }
    final url = resolved.url;
    final uri = switch (url) {
      final VsUri uri => uri,
      final String text => Uri.tryParse(text),
      _ => null,
    };
    if (uri case final VsUri target) {
      await openLink(target);
    } else if (uri case final Uri target when target.hasScheme) {
      await openLink(VsUri.parse(target.toString()));
    }
  }

  // --- Document colors ---------------------------------------------------

  void _scheduleColors({bool immediately = false}) {
    final view = _view;
    if (_disposed || view == null) return;
    _colorTimer?.cancel();
    final generation = ++_colorGeneration;
    // The swatches shown move with the text until the new ones come.
    _colorTimer = Timer(
      immediately ? Duration.zero : colorDelay,
      () => unawaited(_updateColors(view, generation)),
    );
  }

  Future<void> _updateColors(IdeEditorView view, int generation) async {
    if (!_enabled('editor.colorDecorators')) {
      view.features.colors.clear();
      return;
    }
    final snapshot = view.controller.document.snapshot;
    final colors = await languages.documentColors(view.document.path);
    if (_disposed ||
        generation != _colorGeneration ||
        !identical(view, _view) ||
        !identical(snapshot, view.controller.document.snapshot)) {
      return;
    }
    // `editor.colorDecoratorsLimit` (upstream default 500).
    final limit = switch (setting?.call(
      'editor.colorDecoratorsLimit',
      languageIdOf?.call(view.document.path),
    )) {
      final int value when value >= 0 => value,
      _ => 500,
    };
    view.features.colors.setColors(snapshot, [
      for (final info in colors.take(limit))
        if (info.range case final Range range)
          EditorDocumentColor(
            snapshot.offsetAtPosition(range.getStartPosition()),
            snapshot.offsetAtPosition(range.getEndPosition()),
            Color.from(
              alpha: info.color.alpha,
              red: info.color.red,
              green: info.color.green,
              blue: info.color.blue,
            ),
            data: info,
          ),
    ]);
  }

  /// The provider's presentations of [value] for [color]'s text, now at
  /// [start, end) (upstream `getColorPresentations` with the picker's
  /// tracked range).
  Future<List<EditorColorPresentation>> _colorPresentations(
    IdeEditorView view,
    EditorDocumentColor color,
    int start,
    int end,
    Color value,
  ) async {
    final info = color.data;
    if (info is! lang.ColorInformation) return const [];
    final snapshot = view.controller.document.snapshot;
    final range = Range.fromPositions(
      snapshot.positionAtOffset(start),
      snapshot.positionAtOffset(end),
    );
    final presentations = await languages.colorPresentations(
      view.document.path,
      info,
      range: range,
      preview: lang.Color(value.r, value.g, value.b, value.a),
    );
    if (_disposed ||
        !identical(view, _view) ||
        !identical(snapshot, view.controller.document.snapshot)) {
      return const [];
    }
    EditorOffsetEdit offsetEdit(lang.TextEdit edit) => EditorOffsetEdit(
      snapshot.offsetAtPosition(Range.startPositionOf(edit.range)),
      snapshot.offsetAtPosition(Range.endPositionOf(edit.range)),
      edit.text,
    );
    return [
      for (final presentation in presentations)
        EditorColorPresentation(
          presentation.label,
          snapshot: snapshot,
          edit: switch (presentation.textEdit) {
            final edit? => offsetEdit(edit),
            null => null,
          },
          additionalEdits: [
            for (final edit
                in presentation.additionalTextEdits ?? const <lang.TextEdit>[])
              offsetEdit(edit),
          ],
        ),
    ];
  }

  // --- Inline completions --------------------------------------------------

  void _scheduleInline(Object event) {
    _inlineTimer?.cancel();
    final view = _view;
    if (_disposed || view == null) return;
    if (!view.hasFocus()) return;
    _inlineTimer = Timer(inlineDelay, () => unawaited(_updateInline()));
  }

  /// Asks for inline completions at the caret now
  /// (`editor.action.inlineSuggest.trigger`).
  Future<void> trigger() => _updateInline(explicit: true);

  Future<void> _updateInline({bool explicit = false}) async {
    final view = _view;
    if (view == null) return;
    final generation = ++_inlineGeneration;
    if (!_enabled('editor.inlineSuggest.enabled')) return;
    final controller = view.controller;
    final selections = controller.selections;
    // One caret, nothing selected (upstream asks for the primary cursor;
    // with several, the ghost text would not follow the others).
    if (selections.length != 1 || !selections.first.isCollapsed) return;
    final offset = selections.first.extentOffset;
    final snapshot = controller.document.snapshot;
    final position = snapshot.positionAtOffset(offset);
    final results = await languages.inlineCompletions(
      view.document.path,
      position,
      lang.InlineCompletionContext(
        triggerKind: explicit
            ? lang.InlineCompletionTriggerKind.explicit
            : lang.InlineCompletionTriggerKind.automatic,
        requestUuid: '${DateTime.now().microsecondsSinceEpoch}-$generation',
      ),
    );
    if (_disposed ||
        generation != _inlineGeneration ||
        !identical(view, _view) ||
        !identical(controller.document.snapshot, snapshot)) {
      for (final result in results) {
        result.dispose(lang.InlineCompletionsDisposeReason.lostRace);
      }
      return;
    }
    _disposeInline();
    _inlineResults = results;
    for (final result in results) {
      for (final (index, item) in result.items.indexed) {
        final suggestion = _suggestion(snapshot, offset, result, index, item);
        if (suggestion == null) continue;
        view.features.inlineSuggest.show(suggestion);
        if (view.features.inlineSuggest.isVisible) {
          result.provider.handleItemDidShow(
            result.completions,
            result.completions.items[index],
            suggestion.text,
          );
          return;
        }
      }
    }
  }

  EditorInlineSuggestion? _suggestion(
    DocumentSnapshot snapshot,
    int caret,
    InlineCompletionsResult result,
    int index,
    lang.InlineCompletion item,
  ) {
    if (item.isInlineEdit) return null;
    final text = switch (item) {
      lang.InlineCompletion(:final String insertText) => insertText,
      lang.InlineCompletion(:final String snippet) =>
        SnippetParser.asInsertText(snippet),
      _ => null,
    };
    if (text == null || text.isEmpty) return null;
    final range = item.range;
    final start = range == null
        ? caret
        : snapshot.offsetAtPosition(
            Position(range.startLineNumber, range.startColumn),
          );
    final end = range == null
        ? caret
        : snapshot.offsetAtPosition(
            Position(range.endLineNumber, range.endColumn),
          );
    // Ghost text extends what is at the caret; a range elsewhere is an
    // edit, not a completion.
    if (start > caret || end < caret) return null;
    return EditorInlineSuggestion(
      start: start,
      end: end,
      text: text,
      data: (result: result, index: index),
    );
  }

  void _inlineAccepted(EditorInlineSuggestion suggestion, int length) {
    if (suggestion.data case (
      result: final InlineCompletionsResult result,
      index: final int index,
    )) {
      final item = result.items[index];
      if (length < suggestion.text.length) {
        result.provider.handlePartialAccept(
          result.completions,
          result.completions.items[index],
          length,
        );
        return;
      }
      if (item.command case final command?) {
        unawaited(
          _run(
            EditorCommand(
              id: command.id,
              title: command.title,
              arguments: command.arguments,
            ),
          ),
        );
      }
    }
    _disposeInline();
  }

  void _clearInline() {
    _inlineGeneration++;
    _disposeInline();
  }

  void _disposeInline() {
    final results = _inlineResults;
    _inlineResults = const [];
    for (final result in results) {
      result.dispose();
    }
  }

  void dispose() {
    if (_disposed) return;
    _detach();
    for (final key in _highlightColors.keys) {
      _highlightTypes?.removeDecorationType(key);
    }
    _highlightTypes = null;
    _disposed = true;
    views.removeListener(_activeChanged);
    unawaited(_viewChanges.cancel());
    unawaited(_providers.cancel());
  }
}
