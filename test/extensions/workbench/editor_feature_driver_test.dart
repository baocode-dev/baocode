// The extensions' CodeLenses, inlay hints and inline completions reach the
// editor on screen (goal 九.1: CodeLens and InlayHints of the TS extension
// go through this driver).

import 'dart:async';

import 'package:bao_editor/monaco/flutter/editor_document_model.dart'
    show EditorOffsetEdit;
import 'package:bao_editor/monaco/flutter/editor_surface_controller.dart';
import 'package:bao_editor/monaco/vs/editor/contrib/folding/browser/folding_ranges.dart'
    show FoldRange;
import 'package:bao_exthost/bao_exthost.dart' show CancellationToken, VsUri;
import 'package:baocode/extensions/documents/ext_host_document_mirror.dart';
import 'package:baocode/extensions/language/language_feature_document.dart';
import 'package:baocode/extensions/language/language_features_service.dart';
import 'package:baocode/extensions/language/language_providers.dart';
import 'package:baocode/extensions/language/language_selector.dart';
import 'package:baocode/extensions/language/language_types.dart';
import 'package:baocode/extensions/language/marker_service.dart';
import 'package:baocode/extensions/language/registry_language_features.dart';
import 'package:baocode/extensions/workbench/editor_feature_driver.dart';
import 'package:baocode/ide/ide_commands.dart' show ideUsesMacKeys;
import 'package:baocode/ide/ide_editor_colors.dart';
import 'package:baocode/ide/ide_editor_features.dart';
import 'package:baocode/ide/ide_editor_views.dart';
import 'package:baocode/ide/ide_workspace.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/painting.dart' as ui show Color;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _path = '/w/a.ts';

class _Lenses extends CodeLensProvider {
  final changes = StreamController<void>.broadcast();
  int asked = 0;

  @override
  Stream<void>? get onDidChange => changes.stream;

  @override
  FutureOr<CodeLensList?> provideCodeLenses(
    LanguageFeatureDocument model,
    CancellationToken token,
  ) {
    asked++;
    return CodeLensList([CodeLens(Range(1, 1, 1, 6), id: 'a')]);
  }

  @override
  bool get canResolveCodeLens => true;

  @override
  FutureOr<CodeLens?> resolveCodeLens(
    LanguageFeatureDocument model,
    CodeLens codeLens,
    CancellationToken token,
  ) => CodeLens(
    codeLens.range,
    id: codeLens.id,
    command: const Command(
      id: 'acme.references',
      title: '2 references',
      arguments: [1],
    ),
  );
}

class _Hints extends InlayHintsProvider {
  final ranges = <Range>[];

  @override
  FutureOr<InlayHintList?> provideInlayHints(
    LanguageFeatureDocument model,
    Range range,
    CancellationToken token,
  ) {
    ranges.add(range);
    return InlayHintList([
      const InlayHint(
        label: [InlayHintLabelPart(': number')],
        position: Position(1, 6),
        kind: InlayHintKind.type,
      ),
    ]);
  }
}

class _Highlights extends DocumentHighlightProvider {
  final positions = <Position>[];

  @override
  FutureOr<List<DocumentHighlight>?> provideDocumentHighlights(
    LanguageFeatureDocument model,
    Position position,
    CancellationToken token,
  ) {
    positions.add(position);
    return [
      DocumentHighlight(Range(1, 1, 1, 6), kind: DocumentHighlightKind.read),
      DocumentHighlight(Range(2, 1, 2, 8), kind: DocumentHighlightKind.write),
    ];
  }
}

class _DelayedHighlights extends DocumentHighlightProvider {
  final requests = <Completer<List<DocumentHighlight>?>>[];

  @override
  Future<List<DocumentHighlight>?> provideDocumentHighlights(
    LanguageFeatureDocument model,
    Position position,
    CancellationToken token,
  ) {
    final request = Completer<List<DocumentHighlight>?>();
    requests.add(request);
    return request.future;
  }
}

class _Folds extends FoldingRangeProvider {
  final changes = StreamController<void>.broadcast();
  int asked = 0;

  @override
  Stream<void>? get onDidChange => changes.stream;

  @override
  FutureOr<List<FoldingRange>?> provideFoldingRanges(
    LanguageFeatureDocument model,
    FoldingContext context,
    CancellationToken token,
  ) {
    asked++;
    return const [FoldingRange(1, 2, kind: FoldingRangeKind.region)];
  }
}

class _DelayedFolds extends FoldingRangeProvider {
  final requests = <Completer<List<FoldingRange>?>>[];

  @override
  Future<List<FoldingRange>?> provideFoldingRanges(
    LanguageFeatureDocument model,
    FoldingContext context,
    CancellationToken token,
  ) {
    final request = Completer<List<FoldingRange>?>();
    requests.add(request);
    return request.future;
  }
}

class _Links extends LinkProvider {
  int asked = 0;
  int resolved = 0;
  Completer<Link?>? pendingResolve;

  @override
  FutureOr<LinksList?> provideLinks(
    LanguageFeatureDocument model,
    CancellationToken token,
  ) {
    asked++;
    return LinksList([Link(Range(1, 1, 1, 6), tooltip: 'Open count')]);
  }

  @override
  bool get canResolveLink => true;

  @override
  FutureOr<Link?> resolveLink(Link link, CancellationToken token) {
    resolved++;
    return pendingResolve?.future ??
        Link(link.range, url: VsUri.parse('https://example.org/count'));
  }
}

/// `console` (line 2) is a color; its presentations are hex and rgb, each
/// writing a marker comment at the top as an additional edit.
class _Colors extends DocumentColorProvider {
  final asked = <Completer<List<ColorInformation>?>>[];
  final presented = <(Range, Color)>[];
  bool delayed = false;

  @override
  FutureOr<List<ColorInformation>?> provideDocumentColors(
    LanguageFeatureDocument model,
    CancellationToken token,
  ) {
    final result = [
      ColorInformation(Range(2, 1, 2, 8), const Color(0, 0, 1, 1), data: 7),
    ];
    if (!delayed) return result;
    final request = Completer<List<ColorInformation>?>();
    asked.add(request);
    return request.future;
  }

  @override
  FutureOr<List<ColorPresentation>?> provideColorPresentations(
    LanguageFeatureDocument model,
    ColorInformation colorInfo,
    CancellationToken token,
  ) {
    final color = colorInfo.color;
    presented.add((colorInfo.range as Range, color));
    int byte(double value) => (value * 255).round();
    String hex(double value) => byte(value).toRadixString(16).padLeft(2, '0');
    final hexLabel =
        '#${hex(color.red)}${hex(color.green)}${hex(color.blue)}';
    final rgbLabel =
        'rgb(${byte(color.red)}, ${byte(color.green)}, ${byte(color.blue)})';
    return [
      for (final label in [hexLabel, rgbLabel])
        ColorPresentation(
          label,
          textEdit: TextEdit(colorInfo.range, label),
          additionalTextEdits: [TextEdit(Range(1, 1, 1, 1), '/*c*/')],
        ),
    ];
  }
}

class _Inline extends InlineCompletionsProvider {
  final shown = <String>[];
  int disposed = 0;

  @override
  FutureOr<InlineCompletions?> provideInlineCompletions(
    LanguageFeatureDocument model,
    Position position,
    InlineCompletionContext context,
    CancellationToken token,
  ) => const InlineCompletions([
    InlineCompletion(
      insertText: 'log()',
      command: Command(id: 'acme.accepted', title: ''),
    ),
  ]);

  @override
  void handleItemDidShow(
    InlineCompletions completions,
    InlineCompletion item,
    String updatedInsertText,
  ) => shown.add(updatedInsertText);

  @override
  void disposeInlineCompletions(
    InlineCompletions completions,
    InlineCompletionsDisposeReason reason,
  ) => disposed++;
}

void main() {
  late LanguageFeaturesService service;
  late MarkerService markers;
  late RegistryLanguageFeatures languages;
  late IdeEditorViews views;
  late IdeDocument document;
  late EditorSurfaceController controller;
  late IdeEditorFeatures features;
  late IdeEditorView view;
  late List<(String, List<Object?>)> commands;
  late List<VsUri> openedLinks;
  late Map<String, Object?> settings;
  late bool focused;
  List<FoldRange>? folds;
  ExtensionEditorFeatureDriver? driver;

  setUp(() {
    service = LanguageFeaturesService();
    markers = MarkerService();
    final documents = LocalLanguageFeatureDocuments()
      ..add(
        _path,
        ExtHostDocumentMirror(
          uri: VsUri.file(_path),
          languageId: 'typescript',
          text: 'count\nconsole.\n',
        ),
      );
    languages = RegistryLanguageFeatures(
      service: service,
      markers: markers,
      documents: documents,
    );
    views = IdeEditorViews();
    document = IdeDocument(_path, 'count\nconsole.\n');
    controller = EditorSurfaceController(document: document.model);
    features = IdeEditorFeatures(
      controller: controller,
      types: EditorDecorationTypeRegistry(),
    );
    focused = true;
    folds = null;
    view = IdeEditorView(
      document: document,
      controller: controller,
      features: features,
      visibleLines: () => (first: 1, last: 2),
      hasFocus: () => focused,
      focus: () {},
      reveal: (_, _, {center = false}) {},
      setFoldingRanges: (ranges) => folds = ranges,
    );
    commands = [];
    openedLinks = [];
    settings = {};
  });

  tearDown(() {
    driver?.dispose();
    driver = null;
    features.dispose();
    controller.dispose();
    views.dispose();
    languages.dispose();
    markers.dispose();
    service.dispose();
  });

  ExtensionEditorFeatureDriver start() => driver = ExtensionEditorFeatureDriver(
    views: views,
    languages: languages,
    service: service,
    executeCommand: (id, args) async {
      commands.add((id, args));
      return null;
    },
    openLocation: (_, _) async {},
    openLink: (uri) async => openedLinks.add(uri),
    setting: (key, _) => settings[key],
  );

  // Before the binding checks for timers, which is before tear-downs.
  Future<void> stop(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 1));
    driver?.dispose();
    driver = null;
  }

  final ts = LanguageSelector.parse('typescript')!;

  testWidgets('CodeLenses show, resolve into commands that run, and follow '
      'the provider\'s changes', (tester) async {
    final lenses = _Lenses();
    service.codeLensProvider.register(ts, lenses);
    start();
    views.show(view);
    await tester.pump(const Duration(milliseconds: 10));
    expect(features.codeLens.lenses, hasLength(1));
    expect('${features.codeLens.lenses.single.range}', '${Range(1, 1, 1, 6)}');

    final resolved = await features.codeLens.resolve!(
      features.codeLens.lenses.single,
    );
    expect(resolved!.command!.title, '2 references');
    features.codeLens.onCommand!(resolved, resolved.command!);
    await tester.pump();
    expect(commands.single.$1, 'acme.references');
    expect(commands.single.$2, [1]);

    final before = lenses.asked;
    lenses.changes.add(null);
    await tester.pump(const Duration(milliseconds: 300));
    expect(lenses.asked, before + 1);
    await stop(tester);
  });

  testWidgets('editor.codeLens: false shows none', (tester) async {
    service.codeLensProvider.register(ts, _Lenses());
    settings['editor.codeLens'] = false;
    start();
    views.show(view);
    await tester.pump(const Duration(milliseconds: 10));
    expect(features.codeLens.lenses, isEmpty);
    await stop(tester);
  });

  testWidgets('inlay hints are asked for the lines on screen and painted', (
    tester,
  ) async {
    final hints = _Hints();
    service.inlayHintsProvider.register(ts, hints);
    start();
    views.show(view);
    await tester.pump(const Duration(milliseconds: 10));
    expect('${hints.ranges.single}', '${Range(1, 1, 2, 9)}');
    expect(features.inlayHints.hints.single.label.single.label, ': number');
    expect(
      '${features.inlayHints.hints.single.position}',
      '${const Position(1, 6)}',
    );
    await stop(tester);
  });

  testWidgets(
    'provider document highlights follow the caret and clear on blur',
    (tester) async {
      final highlights = _Highlights();
      service.documentHighlightProvider.register(ts, highlights);
      start();
      views.show(view);
      await tester.pump(const Duration(milliseconds: 10));
      expect(highlights.positions, hasLength(1));
      final decorations = features.decorations.decorations.items.toList();
      expect(decorations.map((item) => (item.start, item.end)), [
        (0, 5),
        (6, 13),
      ]);
      expect(
        features.decorations.typeKeys,
        contains('baocode.occurrence.read'),
      );
      expect(
        features.decorations.typeKeys,
        contains('baocode.occurrence.write'),
      );

      controller.setSelections([const TextSelection.collapsed(offset: 2)]);
      views.changed(view);
      await tester.pump(const Duration(milliseconds: 300));
      expect(highlights.positions, hasLength(2));
      views.changed(view);
      await tester.pump(const Duration(milliseconds: 300));
      expect(highlights.positions, hasLength(2));

      focused = false;
      views.changed(view);
      expect(features.decorations.decorations.isEmpty, isTrue);
      settings['editor.occurrencesHighlight'] = 'off';
      focused = true;
      views.changed(view);
      await tester.pump(const Duration(milliseconds: 300));
      expect(features.decorations.decorations.isEmpty, isTrue);
      expect(highlights.positions, hasLength(2));
      await stop(tester);
    },
  );

  testWidgets('late document highlights never replace newer caret results', (
    tester,
  ) async {
    final highlights = _DelayedHighlights();
    service.documentHighlightProvider.register(ts, highlights);
    start();
    views.show(view);
    await tester.pump(const Duration(milliseconds: 10));
    expect(highlights.requests, hasLength(1));

    controller.setSelections([const TextSelection.collapsed(offset: 2)]);
    views.changed(view);
    await tester.pump(const Duration(milliseconds: 300));
    expect(highlights.requests, hasLength(2));
    highlights.requests.last.complete([
      DocumentHighlight(Range(2, 1, 2, 8), kind: DocumentHighlightKind.write),
    ]);
    await tester.pump();
    expect(features.decorations.decorations.items.single.start, 6);

    highlights.requests.first.complete([
      DocumentHighlight(Range(1, 1, 1, 6), kind: DocumentHighlightKind.read),
    ]);
    await tester.pump();
    expect(features.decorations.decorations.items.single.start, 6);
    await stop(tester);
  });

  testWidgets(
    'folding provider ranges reach the editor and refresh on change',
    (tester) async {
      final provider = _Folds();
      service.foldingRangeProvider.register(ts, provider);
      start();
      views.show(view);
      await tester.pump(const Duration(milliseconds: 10));
      expect(provider.asked, 1);
      expect(folds, hasLength(1));
      expect(
        (folds!.single.startLineNumber, folds!.single.endLineNumber),
        (1, 2),
      );
      expect(folds!.single.type, 'region');

      provider.changes.add(null);
      expect(folds, hasLength(1));
      await tester.pump(const Duration(milliseconds: 300));
      expect(provider.asked, 2);
      expect(folds, hasLength(1));
      views.hide(view);
      expect(folds, isNull);
      await stop(tester);
      await provider.changes.close();
    },
  );

  testWidgets('late folding ranges never replace the newer snapshot', (
    tester,
  ) async {
    final provider = _DelayedFolds();
    service.foldingRangeProvider.register(ts, provider);
    start();
    views.show(view);
    await tester.pump(const Duration(milliseconds: 10));
    expect(provider.requests, hasLength(1));

    controller.applyEdits([const EditorOffsetEdit(0, 0, 'new\n')]);
    await tester.pump(const Duration(milliseconds: 300));
    expect(provider.requests, hasLength(2));
    provider.requests.last.complete(const [FoldingRange(2, 3)]);
    await tester.pump();
    expect(folds, hasLength(1));
    expect(folds!.single.startLineNumber, 2);

    provider.requests.first.complete(const [FoldingRange(1, 2)]);
    await tester.pump();
    expect(folds!.single.startLineNumber, 2);
    await stop(tester);
  });

  testWidgets('provider links resolve on modifier-click and expire on edit', (
    tester,
  ) async {
    final provider = _Links();
    service.linkProvider.register(ts, provider);
    start();
    views.show(view);
    await tester.pump(const Duration(milliseconds: 10));
    expect(provider.asked, 1);
    final snapshot = controller.document.snapshot;
    final modifier = ideUsesMacKeys
        ? LogicalKeyboardKey.metaLeft
        : LogicalKeyboardKey.controlLeft;
    await tester.sendKeyDownEvent(modifier);
    features.links.hover(snapshot, 2);
    expect(features.links.hovered?.tooltip, 'Open count');
    expect(features.links.decorations.items.single.start, 0);
    const event = PointerDownEvent(
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    );
    expect(features.links.pointerDown(snapshot, 2, event), isTrue);
    await tester.pump();
    expect(provider.resolved, 1);
    expect(openedLinks.single.toString(), 'https://example.org/count');

    controller.applyEdits([const EditorOffsetEdit(0, 0, 'x')]);
    expect(features.links.pointerDown(snapshot, 2, event), isFalse);
    await tester.pump(const Duration(milliseconds: 300));
    expect(provider.asked, 2);
    await tester.sendKeyUpEvent(modifier);
    await stop(tester);
  });

  testWidgets('late link resolution cannot open an edited document', (
    tester,
  ) async {
    final provider = _Links()..pendingResolve = Completer<Link?>();
    service.linkProvider.register(ts, provider);
    start();
    views.show(view);
    await tester.pump(const Duration(milliseconds: 10));
    final snapshot = controller.document.snapshot;
    final modifier = ideUsesMacKeys
        ? LogicalKeyboardKey.metaLeft
        : LogicalKeyboardKey.controlLeft;
    await tester.sendKeyDownEvent(modifier);
    expect(
      features.links.pointerDown(
        snapshot,
        2,
        const PointerDownEvent(
          kind: PointerDeviceKind.mouse,
          buttons: kPrimaryMouseButton,
        ),
      ),
      isTrue,
    );
    await tester.pump();
    expect(provider.resolved, 1);
    controller.applyEdits([const EditorOffsetEdit(0, 0, 'x')]);
    provider.pendingResolve!.complete(
      Link(Range(1, 1, 1, 6), url: 'https://example.org/stale'),
    );
    await tester.pump();
    expect(openedLinks, isEmpty);
    await tester.sendKeyUpEvent(modifier);
    await stop(tester);
  });

  testWidgets('typing asks for an inline completion, shown as ghost text; '
      'accepting runs its command', (tester) async {
    final inline = _Inline();
    service.inlineCompletionsProvider.register(ts, inline);
    start();
    views.show(view);
    // `console.` typed to `console.l`, the caret after it.
    controller.applyEdits([const EditorOffsetEdit(14, 14, 'l')]);
    controller.setSelections([const TextSelection.collapsed(offset: 15)]);
    await tester.pump(const Duration(milliseconds: 100));
    expect(features.inlineSuggest.isVisible, isTrue);
    expect(inline.shown, ['log()']);

    expect(features.inlineSuggest.accept(), isTrue);
    await tester.pump();
    expect(commands.map((c) => c.$1), ['acme.accepted']);
    expect(inline.disposed, greaterThan(0));
    await stop(tester);
  });

  testWidgets('an editor without the focus asks for no inline completion', (
    tester,
  ) async {
    final inline = _Inline();
    service.inlineCompletionsProvider.register(ts, inline);
    focused = false;
    start();
    views.show(view);
    controller.applyEdits([const EditorOffsetEdit(0, 0, 'x')]);
    await tester.pump(const Duration(milliseconds: 100));
    expect(features.inlineSuggest.isVisible, isFalse);
    await stop(tester);
  });

  testWidgets('provider colors show swatches that move with edits; late '
      'results and the setting leave none', (tester) async {
    final provider = _Colors();
    service.colorProvider.register(ts, provider);
    start();
    views.show(view);
    await tester.pump(const Duration(milliseconds: 10));
    final swatch = features.colors.decorations.items.single;
    expect((swatch.start, swatch.end), (6, 13));
    expect(swatch.before!.backgroundColor, const ui.Color(0xff0000ff));
    expect(features.colors.affectsLayout, isTrue);

    // Typing before it moves it at once; the refresh comes later.
    provider.delayed = true;
    controller.applyEdits([const EditorOffsetEdit(0, 0, 'x')]);
    expect(features.colors.decorations.items.single.start, 7);
    await tester.pump(const Duration(milliseconds: 300));
    expect(provider.asked, hasLength(1));
    controller.applyEdits([const EditorOffsetEdit(0, 0, 'y')]);
    await tester.pump(const Duration(milliseconds: 300));
    expect(provider.asked, hasLength(2));
    // The first answer is of a text that is gone.
    provider.asked.first.complete([
      ColorInformation(Range(1, 1, 1, 2), const Color(1, 0, 0, 1)),
    ]);
    await tester.pump();
    expect(features.colors.decorations.items.single.start, 8);
    provider.asked.last.complete([
      ColorInformation(Range(2, 1, 2, 8), const Color(0, 1, 0, 1)),
    ]);
    await tester.pump();
    final current = features.colors.decorations.items.single;
    expect(current.before!.backgroundColor, const ui.Color(0xff00ff00));

    settings['editor.colorDecorators'] = false;
    controller.applyEdits([const EditorOffsetEdit(0, 0, 'z')]);
    await tester.pump(const Duration(milliseconds: 300));
    expect(features.colors.decorations.isEmpty, isTrue);
    await stop(tester);
  });

  testWidgets('the color picker previews provider presentations and writes '
      'one with its additional edits as one undo step', (tester) async {
    final provider = _Colors();
    service.colorProvider.register(ts, provider);
    start();
    views.show(view);
    await tester.pump(const Duration(milliseconds: 10));
    final swatch =
        features.colors.decorations.items.single.before!.data!
            as EditorColorSwatch;
    expect(
      swatch.pointerDown(
        const PointerDownEvent(
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        ),
        modifier: false,
      ),
      isFalse,
    );
    expect(
      swatch.pointerDown(
        const PointerDownEvent(
          kind: PointerDeviceKind.mouse,
          buttons: kPrimaryMouseButton,
          position: Offset(40, 30),
        ),
        modifier: false,
      ),
      isTrue,
    );
    final picker = features.colors.picker!;
    expect(picker.anchor, const Offset(40, 30));
    await tester.pump();
    expect(picker.presentations.map((p) => p.label), [
      '#0000ff',
      'rgb(0, 0, 255)',
    ]);
    expect('${provider.presented.single.$1}', '${Range(2, 1, 2, 8)}');

    // Dragging previews: the label follows, the text does not.
    await picker.preview(const ui.Color(0xffff0000));
    expect(picker.presentation!.label, '#ff0000');
    expect(controller.document.text, 'count\nconsole.\n');

    await picker.commit();
    expect(controller.document.text, '/*c*/count\n#ff0000.\n');
    expect((picker.start, picker.end), (11, 18));
    expect(picker.isOpen, isTrue);

    // The next presentation is asked for at the color's new place.
    await picker.nextPresentation();
    expect('${provider.presented.last.$1}', '${Range(2, 1, 2, 8)}');
    expect(
      controller.document.text,
      '/*c*//*c*/count\nrgb(255, 0, 0).\n',
    );
    expect((picker.start, picker.end), (16, 30));

    // One undo takes back the main and the additional edit together.
    expect(controller.undo(), isTrue);
    expect(controller.document.text, '/*c*/count\n#ff0000.\n');
    // A change not the picker's own closes it.
    expect(features.colors.picker, isNull);
    expect(picker.isOpen, isFalse);
    await stop(tester);
  });

  testWidgets('reverting writes the original color; switching tabs closes '
      'the picker', (tester) async {
    final provider = _Colors();
    service.colorProvider.register(ts, provider);
    start();
    views.show(view);
    await tester.pump(const Duration(milliseconds: 10));
    final swatch =
        features.colors.decorations.items.single.before!.data!
            as EditorColorSwatch;
    final picker = features.colors.open(swatch, Offset.zero)!;
    await tester.pump();
    await picker.pick(const ui.Color(0xff00ff00));
    expect(controller.document.text, '/*c*/count\n#00ff00.\n');
    await picker.revert();
    expect(controller.document.text, '/*c*//*c*/count\n#0000ff.\n');
    expect(picker.value, picker.originalColor);

    views.hide(view);
    expect(features.colors.picker, isNull);
    expect(features.colors.decorations.isEmpty, isTrue);
    await stop(tester);
  });
}
