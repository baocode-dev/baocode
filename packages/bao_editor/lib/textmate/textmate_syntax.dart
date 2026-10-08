// The editor's TextMate highlighting on the UI isolate: VS Code's language
// detection and color theme, each document's tokens as the worker
// (textmate_worker.dart) sends them, and the spans the editor paints. It
// never tokenizes; the worker does, off this isolate.
//
// Upstream, this is `TextMateTokenizationFeature` (grammars, theme, color
// map), `TextMateWorkerTokenizerController` (a model's side of the worker:
// changes the worker has not seen yet, tokens of older versions) and the text
// model's `ContiguousTokensStore`, at VS Code
// 6a598d4a13031703d483d103c1d934a36ad27971. See PORTING.md for how they map.

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

import '../monaco/flutter/document_snapshot.dart';
import '../monaco/flutter/language_assets.dart';
import '../monaco/vs/base/common/color.dart' as vs;
import '../monaco/vs/editor/common/core/misc/eol_counter.dart';
import '../monaco/vs/editor/common/encoded_token_attributes.dart'
    show MetadataConsts, TokenMetadata;
import '../monaco/vs/editor/common/services/languages_registry.dart';
import '../monaco/vs/editor/common/tokens/contiguous_tokens_store.dart';
import '../monaco/vs/editor/common/tokens/line_tokens.dart';
import '../monaco/vs/workbench/services/text_mate/browser/text_mate_tokenization_feature_impl.dart';
import '../monaco/vs/workbench/services/text_mate/common/tm_scope_registry.dart';
import '../monaco/vs/workbench/services/themes/common/color_theme_data.dart';
import 'textmate_manifest.dart';
import 'textmate_worker.dart';

/// How editors start their TextMate worker: in a background isolate. Widget
/// tests run it in their own isolate instead ([TextMateInProcessWorker]),
/// since other isolates do not follow their fake clock.
Future<TextMateWorkerChannel?> Function() textMateWorkerLauncher =
    spawnTextMateWorker;

/// VS Code language ids of languages Monaco's Monarch grammars (the
/// fallback) know by another id, as by the files each claims.
const Map<String, String> _monarchLanguageIds = {
  'shellscript': 'shell',
  'javascriptreact': 'javascript',
  'typescriptreact': 'typescript',
  'properties': 'ini',
  'dockercompose': 'yaml',
  'cuda-cpp': 'cpp',
  'jade': 'pug',
};

/// The Monarch language for a VS Code language id (or any other language
/// name, unchanged): for code named by its VS Code language, such as the
/// editor's, when Monarch colors it.
String monarchLanguageIdFor(String language) =>
    _monarchLanguageIds[language] ?? language;

/// A color theme as the editor paints it.
class TextMateEditorTheme {
  TextMateEditorTheme._(
    this.data,
    this.background,
    this.foreground,
    this._colors,
  );

  factory TextMateEditorTheme(ColorThemeData data) => TextMateEditorTheme._(
    data,
    _color(data.getColor(editorBackground)!),
    _color(data.getColor(editorForeground)!),
    [
      for (final color in data.tokenColorMap)
        color == null ? null : _color(vs.Color.fromHex(color)),
    ],
  );

  final ColorThemeData data;

  /// Whether the worker tokenizes the same with [other]: the rules and the
  /// color map `_updateTheme` compares.
  bool sameTokenTheme(TextMateEditorTheme other) =>
      listEquals(data.tokenColorMap, other.data.tokenColorMap) &&
      _rules(data) == _rules(other.data);

  static String _rules(ColorThemeData data) => jsonEncode([
    for (final rule in data.tokenColors)
      [
        rule.scope,
        rule.settings.foreground,
        rule.settings.background,
        rule.settings.fontStyle,
      ],
  ]);

  /// `editor.background`.
  final Color background;

  /// `editor.foreground`.
  final Color foreground;

  /// `tokenColorMap`, by color id.
  final List<Color?> _colors;
  final Map<int, TextStyle> _styles = {};

  /// The style of a token: its `mtk<foreground>` class and the `mtki`,
  /// `mtkb`, `mtku` and `mtks` font style classes
  /// (`TokenMetadata.getClassNameFromMetadata`), as the editor's CSS
  /// renders them. Token backgrounds are not rendered, as in VS Code.
  TextStyle styleOf(int metadata) {
    final foreground = TokenMetadata.getForeground(metadata);
    final fontStyle =
        (metadata & MetadataConsts.fontStyleMask) >>>
        MetadataConsts.fontStyleOffset;
    return _styles[(foreground << 4) | fontStyle] ??= TextStyle(
      color: foreground < _colors.length ? _colors[foreground] : null,
      fontStyle: metadata & MetadataConsts.italicMask != 0
          ? FontStyle.italic
          : null,
      fontWeight: metadata & MetadataConsts.boldMask != 0
          ? FontWeight.bold
          : null,
      decoration: TextDecoration.combine([
        if (metadata & MetadataConsts.underlineMask != 0)
          TextDecoration.underline,
        if (metadata & MetadataConsts.strikethroughMask != 0)
          TextDecoration.lineThrough,
      ]),
    );
  }

  static Color _color(vs.Color color) => Color.fromARGB(
    (color.rgba.a * 255).round(),
    color.rgba.r,
    color.rgba.g,
    color.rgba.b,
  );

  /// The spans of [text] from its end-offset [tokens]
  /// (`LineTokens.convertToEndOffset`), adjacent tokens of one style merged.
  List<TextSpan> spans(String text, Uint32List tokens) {
    final spans = <TextSpan>[];
    var start = 0;
    var end = 0;
    TextStyle? style;
    for (var i = 0; i < tokens.length && end < text.length; i += 2) {
      final tokenEnd = i + 2 >= tokens.length || tokens[i] > text.length
          ? text.length
          : tokens[i];
      if (tokenEnd <= end) continue;
      final tokenStyle = styleOf(tokens[i + 1]);
      if (!identical(tokenStyle, style)) {
        if (end > start) {
          spans.add(TextSpan(text: text.substring(start, end), style: style));
        }
        start = end;
        style = tokenStyle;
      }
      end = tokenEnd;
    }
    if (end > start) {
      spans.add(TextSpan(text: text.substring(start, end), style: style));
    }
    if (end < text.length) spans.add(TextSpan(text: text.substring(end)));
    return List.unmodifiable(spans);
  }
}

/// A file under [textMateAssetRoot], undecoded: `loadString` decodes large
/// files in another isolate, and grammars are decoded by the worker.
Future<Uint8List> _readAsset(AssetBundle bundle, String path) async {
  final data = await bundle.load('$textMateAssetRoot/$path');
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

/// What the editor needs from the bundled extensions: VS Code's languages
/// and the grammars as `TextMateTokenizationFeature` validates them. Loaded
/// once per asset bundle.
class _Resources {
  _Resources(this.registry, this.grammars, this._maxTokenizationLineLength)
    : grammarLanguages = {for (final grammar in grammars) ?grammar.language};

  // The resources, not a future of them: a future answers in the zone it
  // was made in, which may be gone (a widget test's fake async zone).
  static final Map<AssetBundle, _Resources> _loaded = {};

  static Future<_Resources> load(AssetBundle bundle) async =>
      _loaded[bundle] ??= await _load(bundle);

  static Future<_Resources> _load(AssetBundle bundle) async {
    Future<String> read(String path) async =>
        decodeTextMateResource(await _readAsset(bundle, path));
    final manifest = await TextMateManifest.load(read);
    final registry = LanguagesRegistry()
      ..setDynamicLanguages([
        // Without an extension: plaintext, which `ModesRegistry` registers.
        for (final language in manifest.languages)
          if (language.extension != null)
            ILanguageExtensionPoint(
              id: language.id,
              extensions: language.extensions,
              filenames: language.filenames,
              filenamePatterns: language.filenamePatterns,
              firstLine: language.firstLine,
              // `aliases: []` hides a language's name; absent does not.
              aliases: language.hasAliases ? language.aliases : null,
              mimetypes: language.mimetypes,
            ),
      ]);
    final grammars = [
      for (final grammar in manifest.grammars)
        ?validateGrammarDefinition(
          grammar,
          isRegisteredLanguageId: registry.isRegisteredLanguageId,
          encodeLanguageId: registry.languageIdCodec.encodeLanguageId,
          sourceExtensionId: 'vscode.${grammar.extension}',
        ),
    ];
    return _Resources(registry, grammars, manifest.maxTokenizationLineLengthOf);
  }

  final LanguagesRegistry registry;
  final int? Function(String languageId) _maxTokenizationLineLength;

  /// `editor.maxTokenizationLineLength` for [languageId]: the default, or
  /// what an extension's `configurationDefaults` sets for the language.
  int maxTokenizationLineLengthOf(String languageId) =>
      _maxTokenizationLineLength(languageId) ?? maxTokenizationLineLength;
  final List<IValidGrammarDefinition> grammars;

  /// `TMGrammarFactory.has`: the languages with a grammar.
  final Set<String> grammarLanguages;
}

/// A running worker with the resources it was given.
class _Runtime {
  _Runtime(this.syntax, this.resources, this.channel, this.theme) {
    _subscription = channel.responses.listen(_onResponse);
    channel
      ..send(TextMateInit(resources.grammars))
      ..send(
        TextMateSetTheme(toRawTheme(theme.data), theme.data.tokenColorMap),
      );
  }

  final TextMateSyntax syntax;
  final _Resources resources;

  /// The theme the worker tokenizes with.
  TextMateEditorTheme theme;
  final TextMateWorkerChannel channel;
  late final StreamSubscription<TextMateResponse> _subscription;
  final Map<int, TextMateDocument> documents = {};
  final Map<int, Completer<List<Uint32List>?>> colorizing = {};
  int _nextDocument = 0;
  int _nextColorize = 0;

  void _onResponse(TextMateResponse response) {
    switch (response) {
      case TextMateReadFile(:final requestId, :final path):
        _readAsset(syntax._bundle, path).then(
          (bytes) => channel.send(TextMateFileContent(requestId, bytes)),
          onError: (Object error) =>
              channel.send(TextMateFileContent(requestId, null, '$error')),
        );
      case TextMateTokens():
        documents[response.documentId]?._acceptTokens(response);
      case TextMateColorized(:final requestId, :final lines):
        colorizing.remove(requestId)?.complete(lines);
      case TextMateWorkerError(:final message):
        syntax._reportError(message);
    }
  }

  /// `_updateTheme`: the worker's grammars take [next]'s rules, and every
  /// document is tokenized again (`TokenizationRegistry.setColorMap` resets
  /// every model's tokenization).
  void setTheme(TextMateEditorTheme next) {
    theme = next;
    channel.send(
      TextMateSetTheme(toRawTheme(next.data), next.data.tokenColorMap),
    );
    for (final document in documents.values.toList()) {
      document._retheme();
    }
  }

  void dispose() {
    for (final document in documents.values.toList()) {
      document._detach();
    }
    for (final request in colorizing.values) {
      request.complete(null);
    }
    colorizing.clear();
    unawaited(_subscription.cancel());
    channel.dispose();
  }
}

/// Where [TextMateSyntax] gets the color theme it paints with, and word
/// when it changes: what VS Code's `IWorkbenchThemeService` gives an
/// editor. An app's workbench theme implements it.
abstract interface class TextMateThemeSource implements Listenable {
  /// The theme in use. One restored from storage has its rules; one whose
  /// [ColorThemeData.settingsId] starts with `__` has not read its file
  /// yet ([loadedColorTheme]).
  ColorThemeData get colorTheme;

  /// [colorTheme], its file read.
  Future<ColorThemeData> loadedColorTheme();
}

/// TextMate highlighting for one editor: VS Code's grammars and theme, with
/// tokenization in a worker. Unavailable (every method answers null) on the
/// web, where the native Oniguruma library does not load, or without the
/// assets; the editor highlights with Monarch then.
class TextMateSyntax {
  TextMateSyntax({
    AssetBundle? bundle,
    MonacoLanguageAssets? monarch,
    required this._themes,
    Future<TextMateWorkerChannel?> Function()? launch,
  }) : _bundle = bundle ?? rootBundle,
       _monarch = monarch ?? MonacoLanguageAssets(bundle: bundle),
       _launch = launch ?? textMateWorkerLauncher {
    _themes.addListener(_colorThemeChanged);
  }

  final AssetBundle _bundle;
  final MonacoLanguageAssets _monarch;
  final Future<TextMateWorkerChannel?> Function() _launch;

  /// The workbench theme, which the editor paints with.
  final TextMateThemeSource _themes;

  Future<_Runtime?>? _runtime;
  _Runtime? _started;
  bool _disposed = false;

  /// The theme the editor paints with; null until TextMate is available.
  ValueListenable<TextMateEditorTheme?> get editorTheme => _editorTheme;
  final ValueNotifier<TextMateEditorTheme?> _editorTheme = ValueNotifier(null);

  Future<_Runtime?> _ready() => _runtime ??= _start();

  Future<_Runtime?> _start() async {
    final _Resources resources;
    final TextMateWorkerChannel? channel;
    final ColorThemeData colorTheme;
    try {
      resources = await _Resources.load(_bundle);
      // A theme restored from storage has its rules; the first time, the
      // default theme's file is read first.
      colorTheme = _themes.colorTheme.settingsId.startsWith('__')
          ? await _themes.loadedColorTheme()
          : _themes.colorTheme;
      channel = await _launch();
    } catch (error, stack) {
      _reportError(error, stack);
      return null;
    }
    if (channel == null) return null;
    if (_disposed) {
      channel.dispose();
      return null;
    }
    final runtime = _started = _Runtime(
      this,
      resources,
      channel,
      TextMateEditorTheme(colorTheme),
    );
    _editorTheme.value = runtime.theme;
    _colorThemeChanged();
    return runtime;
  }

  void _colorThemeChanged() {
    final runtime = _started;
    if (runtime == null || _disposed) return;
    final colorTheme = _themes.colorTheme;
    if (identical(colorTheme, runtime.theme.data)) return;
    final next = TextMateEditorTheme(colorTheme);
    if (next.sameTokenTheme(runtime.theme)) {
      runtime.theme = next;
    } else {
      runtime.setTheme(next);
    }
    _editorTheme.value = next;
  }

  void _reportError(Object error, [StackTrace? stack]) =>
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'TextMate highlighting',
        ),
      );

  /// The theme, once TextMate is known to be available.
  Future<TextMateEditorTheme?> get theme async => (await _ready())?.theme;

  /// The VS Code language of the file at [path]
  /// (`guessLanguageIdByFilepathOrFirstLine`) when a grammar highlights it;
  /// null when Monarch does: a language pack's Monarch grammar claims the
  /// file, or VS Code has no grammar for it.
  Future<String?> languageIdForPath(String path, {String? firstLine}) async {
    final runtime = await _ready();
    if (runtime == null) return null;
    final monarch = await _monarch.registrationForPath(
      path,
      firstLine: firstLine,
    );
    if (monarch != null &&
        monarch.assetId.startsWith(MonacoLanguageAssets.packAssetPrefix)) {
      return null;
    }
    final languageId = runtime.resources.registry
        .guessLanguageIdByFilepathOrFirstLine(Uri.file(path), firstLine)
        .firstOrNull;
    return languageId != null &&
            runtime.resources.grammarLanguages.contains(languageId)
        ? languageId
        : null;
  }

  /// How token metadata numbers languages (`LanguageIdCodec`), once
  /// TextMate is available.
  @visibleForTesting
  Future<ILanguageIdCodec?> get languageIdCodec async =>
      (await _ready())?.resources.registry.languageIdCodec;

  /// Starts highlighting [snapshot] as [languageId] (from
  /// [languageIdForPath]); null until TextMate is available.
  TextMateDocument? open(String languageId, DocumentSnapshot snapshot) {
    final runtime = _started;
    if (runtime == null || _disposed) return null;
    final document = TextMateDocument._(
      runtime,
      runtime._nextDocument++,
      languageId,
      snapshot,
    );
    return document;
  }

  /// [code] in the language named [language] (an id or alias,
  /// `getLanguageIdByLanguageName`), styled a line at a time, as
  /// `tokenizeToString` colors code blocks in hovers; null when TextMate is
  /// unavailable or has no grammar by that name.
  Future<List<List<TextSpan>>?> colorize(String language, String code) async {
    final runtime = await _ready();
    if (runtime == null) return null;
    final registry = runtime.resources.registry;
    final languageId = registry.getLanguageIdByLanguageName(language);
    if (languageId == null ||
        !runtime.resources.grammarLanguages.contains(languageId)) {
      return null;
    }
    final document = DocumentSnapshot(code);
    final lines = [
      for (var i = 0; i < document.lineCount; i++)
        code.substring(document.lineStarts[i], document.contentEnds[i]),
    ];
    final tokens = await _tokenizeFromStart(runtime, languageId, lines);
    if (tokens == null) return null;
    final theme = runtime.theme;
    return [
      for (final (i, line) in lines.indexed) theme.spans(line, tokens[i]),
    ];
  }

  /// The end-offset tokens of [lines] tokenized from the initial state, as
  /// [colorize] has them.
  @visibleForTesting
  Future<List<Uint32List>?> tokenizeFromStart(
    String languageId,
    List<String> lines,
  ) async {
    final runtime = await _ready();
    return runtime == null
        ? null
        : _tokenizeFromStart(runtime, languageId, lines);
  }

  Future<List<Uint32List>?> _tokenizeFromStart(
    _Runtime runtime,
    String languageId,
    List<String> lines,
  ) {
    final requestId = runtime._nextColorize++;
    final result = runtime.colorizing[requestId] = Completer();
    runtime.channel.send(
      TextMateColorize(
        requestId,
        languageId,
        runtime.resources.registry.languageIdCodec.encodeLanguageId(languageId),
        runtime.resources.maxTokenizationLineLengthOf(languageId),
        lines,
      ),
    );
    return result.future;
  }

  void dispose() {
    _disposed = true;
    _themes.removeListener(_colorThemeChanged);
    _started?.dispose();
    _started = null;
    _editorTheme.dispose();
  }
}

/// A change the worker has not answered yet: lines
/// `[startLineNumber, endLineNumberExclusive)` became [newLineCount] lines
/// at [versionId].
typedef _PendingChange = ({
  int versionId,
  int startLineNumber,
  int endLineNumberExclusive,
  int newLineCount,
});

/// One document highlighted by the worker; notifies when its spans change.
class TextMateDocument extends ChangeNotifier {
  TextMateDocument._(
    this._runtime,
    this._id,
    this.languageId,
    DocumentSnapshot snapshot,
  ) : _snapshot = snapshot,
      _tokens = ContiguousTokensStore(
        _runtime.resources.registry.languageIdCodec,
      ),
      _spans = List.filled(snapshot.lineCount, null, growable: true) {
    _open();
  }

  final _Runtime _runtime;
  int _id;

  /// The VS Code language.
  final String languageId;
  DocumentSnapshot _snapshot;
  int _versionId = 1;
  final ContiguousTokensStore _tokens;

  /// Spans by line index, built on first use.
  final List<List<TextSpan>?> _spans;
  final ListQueue<_PendingChange> _pendingChanges = ListQueue();
  Map<int, List<TextSpan>>? _styledLines;
  (int, int)? _viewport;
  Timer? _viewportTimer;
  bool _disposed = false;

  DocumentSnapshot get snapshot => _snapshot;

  TextMateEditorTheme get theme => _runtime.theme;

  /// The spans of the lines with tokens, by one-based line number, built as
  /// they are read; a new map whenever they change.
  Map<int, List<TextSpan>> get styledLines =>
      _kept ?? (_styledLines ??= _TextMateStyledLines(this));

  /// After a theme change, the spans the lines on screen had, until the
  /// worker's first tokens in the new theme.
  Map<int, List<TextSpan>>? _kept;

  /// The theme changed: tokenized again from the start, as upstream resets
  /// every model's tokenization. Deviation: upstream tokenizes the viewport
  /// on the spot; here the lines on screen keep their old spans until the
  /// worker has tokenized them.
  void _retheme() {
    if (_disposed) return;
    final viewport = _viewport;
    final kept = <int, List<TextSpan>>{};
    if (viewport != null) {
      for (var line = viewport.$1; line <= viewport.$2; line++) {
        if (_spansOf(line - 1) case final spans?) kept[line] = spans;
      }
    }
    _reopen();
    _kept = kept.isEmpty ? null : kept;
    notifyListeners();
  }

  void _open() {
    _runtime.documents[_id] = this;
    _runtime.channel.send(
      TextMateOpen(
        _id,
        languageId,
        _runtime.resources.registry.languageIdCodec.encodeLanguageId(
          languageId,
        ),
        _runtime.resources.maxTokenizationLineLengthOf(languageId),
        _versionId,
        [for (var i = 0; i < _snapshot.lineCount; i++) _lineContent(i)],
      ),
    );
  }

  String _lineContent(int index) => _snapshot.text.substring(
    _snapshot.lineStarts[index],
    _snapshot.contentEnds[index],
  );

  /// The text changed to [next]: tokens follow the edit at once
  /// (`ContiguousTokensStore.acceptEdit`), and the worker retokenizes the
  /// lines it touched.
  void update(DocumentSnapshot next) {
    final old = _snapshot;
    if (_disposed || identical(old, next)) return;
    if (old.text == next.text) {
      _snapshot = next;
      return;
    }
    _kept = null;
    // The edit as one replacement, as a model content change describes it.
    final a = old.text;
    final b = next.text;
    final shortest = a.length < b.length ? a.length : b.length;
    var prefix = 0;
    while (prefix < shortest && a.codeUnitAt(prefix) == b.codeUnitAt(prefix)) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < shortest - prefix &&
        a.codeUnitAt(a.length - 1 - suffix) ==
            b.codeUnitAt(b.length - 1 - suffix)) {
      suffix++;
    }
    // Never between the CR and LF of a line break.
    if (prefix > 0 && a.codeUnitAt(prefix - 1) == 0x0D) prefix--;
    if (suffix > 0 && a.codeUnitAt(a.length - suffix) == 0x0A) suffix--;
    final start = old.positionAtOffset(prefix);
    final end = old.positionAtOffset(a.length - suffix);
    final (eolCount, firstLineLength, _, _) = countEOL(
      b.substring(prefix, b.length - suffix),
    );
    _snapshot = next;
    _versionId++;
    final removedLines = end.lineNumber - start.lineNumber;
    if (old.lineCount - removedLines + eolCount != next.lineCount) {
      // Not expected: start over rather than misplace tokens.
      _reopen();
      return;
    }

    _tokens.acceptEdit(
      (
        startLineNumber: start.lineNumber,
        startColumn: start.column,
        endLineNumber: end.lineNumber,
        endColumn: end.column,
      ),
      eolCount,
      firstLineLength,
    );
    _spans.replaceRange(
      start.lineNumber - 1,
      end.lineNumber,
      List.filled(eolCount + 1, null),
    );
    _pendingChanges.add((
      versionId: _versionId,
      startLineNumber: start.lineNumber,
      endLineNumberExclusive: end.lineNumber + 1,
      newLineCount: eolCount + 1,
    ));
    _runtime.channel.send(
      TextMateChange(_id, _versionId, start.lineNumber, end.lineNumber + 1, [
        for (var i = 0; i <= eolCount; i++)
          _lineContent(start.lineNumber - 1 + i),
      ]),
    );
    _styledLines = null;
  }

  /// Tokenizes the whole document again, as a new one to the worker (whose
  /// answers about the old one are ignored).
  void _reopen() {
    _runtime.documents.remove(_id);
    _runtime.channel.send(TextMateClose(_id));
    _id = _runtime._nextDocument++;
    _tokens.flush();
    _spans
      ..clear()
      ..addAll(List.filled(_snapshot.lineCount, null));
    _pendingChanges.clear();
    _styledLines = null;
    _open();
    if (_viewport case (final first, final last)?) {
      _runtime.channel.send(TextMateViewport(_id, first, last));
    }
  }

  /// The one-based lines on screen, tokenized first. Sent 50ms after the
  /// last change, as an attached view's visible ranges are
  /// (`AttachedViewHandler`).
  void setViewport(int first, int last) {
    if (_disposed || _viewport == (first, last)) return;
    _viewport = (first, last);
    _viewportTimer?.cancel();
    _viewportTimer = Timer(const Duration(milliseconds: 50), () {
      if (_disposed) return;
      _runtime.channel.send(TextMateViewport(_id, first, last));
    });
  }

  /// No view shows it now, as a detached view's visible ranges go
  /// (`AttachedViews`): a viewport not sent yet is dropped. The next view
  /// sets its own.
  void clearViewport() {
    _viewportTimer?.cancel();
    _viewportTimer = null;
    _viewport = null;
  }

  /// `TextMateWorkerTokenizerController.setTokensAndStates`: tokens of an
  /// older version are moved past the changes made since, and dropped on
  /// lines those changes touched (the worker sends those again).
  void _acceptTokens(TextMateTokens message) {
    if (_disposed) return;
    while (_pendingChanges.isNotEmpty &&
        _pendingChanges.first.versionId <= message.versionId) {
      _pendingChanges.removeFirst();
    }
    var changed = false;
    for (final (lineNumber, tokens) in message.lines) {
      int? line = lineNumber;
      for (final change in _pendingChanges) {
        if (line! < change.startLineNumber) continue;
        if (line < change.endLineNumberExclusive) {
          line = null;
          break;
        }
        line +=
            change.newLineCount -
            (change.endLineNumberExclusive - change.startLineNumber);
      }
      if (line == null || line > _snapshot.lineCount) continue;
      final index = line - 1;
      final length = _snapshot.contentEnds[index] - _snapshot.lineStarts[index];
      if (_tokens.setTokens(languageId, index, length, tokens, true)) {
        _spans[index] = null;
        changed = true;
      }
    }
    if (changed) {
      _styledLines = null;
      _kept = null;
      notifyListeners();
    }
  }

  List<TextSpan>? _spansOf(int index) {
    if (index < 0 || index >= _snapshot.lineCount) return null;
    if (!_tokens.hasLineTokens(index)) return null;
    final cached = _spans[index];
    if (cached != null) return cached;
    final text = _lineContent(index);
    return _spans[index] = theme.spans(
      text,
      _tokens.getTokens(languageId, index, text),
    );
  }

  /// The end-offset tokens of one-based [lineNumber], null before any came.
  Uint32List? lineTokens(int lineNumber) {
    final index = lineNumber - 1;
    if (index < 0 || index >= _snapshot.lineCount) return null;
    if (!_tokens.hasLineTokens(index)) return null;
    return _tokens.getTokens(languageId, index, _lineContent(index));
  }

  Iterable<int> get _linesWithTokens sync* {
    for (var i = 0; i < _snapshot.lineCount; i++) {
      if (_tokens.hasLineTokens(i)) yield i + 1;
    }
  }

  /// The worker is gone.
  void _detach() {
    _disposed = true;
    _viewportTimer?.cancel();
  }

  @override
  void dispose() {
    if (!_disposed) {
      _detach();
      _runtime.documents.remove(_id);
      _runtime.channel.send(TextMateClose(_id));
    }
    super.dispose();
  }
}

class _TextMateStyledLines extends MapBase<int, List<TextSpan>> {
  _TextMateStyledLines(this._document);

  final TextMateDocument _document;

  @override
  List<TextSpan>? operator [](Object? key) =>
      key is int ? _document._spansOf(key - 1) : null;

  @override
  Iterable<int> get keys => _document._linesWithTokens;

  @override
  void operator []=(int key, List<TextSpan> value) =>
      throw UnsupportedError('Styled lines are read-only');

  @override
  void clear() => throw UnsupportedError('Styled lines are read-only');

  @override
  List<TextSpan>? remove(Object? key) =>
      throw UnsupportedError('Styled lines are read-only');
}
