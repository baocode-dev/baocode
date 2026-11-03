// The TextMate tokenization worker: VS Code's grammars, on native
// Oniguruma, tokenizing the editor's documents off the UI isolate, as VS
// Code's `TextMateTokenizationWorker` does in a web worker.
//
// It owns the grammar factory and one `TextMateWorkerTokenizer` per open
// document; the UI isolate sends it documents and their edits, and it sends
// back end-offset tokens (see textmate_syntax.dart). Files are read by the UI
// isolate on request, through its asset bundle.
//
// Pure Dart: it runs in a background isolate ([spawnTextMateWorker],
// textmate_worker_io.dart), or in the calling isolate for widget tests
// ([TextMateInProcessWorker]).

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../monaco/vs/editor/common/tokens/line_tokens.dart';
import '../monaco/vs/workbench/services/text_mate/browser/background_tokenization/worker/text_mate_worker_tokenizer.dart';
import '../monaco/vs/workbench/services/text_mate/browser/tokenization_support/text_mate_tokenization_support.dart';
import '../monaco/vs/workbench/services/text_mate/browser/tokenization_support/tokenization_support_with_line_limit.dart';
import '../monaco/vs/workbench/services/text_mate/common/tm_grammar_factory.dart';
import '../monaco/vs/workbench/services/text_mate/common/tm_scope_registry.dart';
import 'oniguruma/onig_lib.dart';
import 'textmate_worker_stub.dart'
    if (dart.library.io) 'textmate_worker_io.dart'
    as platform;
import 'vscode_textmate/main.dart';

/// A grammar or theme file's text, as VS Code reads extension resources:
/// UTF-8 without its byte order mark (`TextDecoder`).
String decodeTextMateResource(Uint8List bytes) {
  final text = utf8.decode(bytes, allowMalformed: true);
  return text.startsWith('\uFEFF') ? text.substring(1) : text;
}

// UI isolate → worker.

sealed class TextMateRequest {
  const TextMateRequest();
}

/// The grammars (validated as VS Code validates them); sent once, first.
class TextMateInit extends TextMateRequest {
  const TextMateInit(this.grammars);

  final List<IValidGrammarDefinition> grammars;
}

/// The theme's token rules and `tokenColorMap`; every document is
/// tokenized again.
class TextMateSetTheme extends TextMateRequest {
  const TextMateSetTheme(this.theme, this.colorMap);

  final IRawTheme theme;
  final List<String?> colorMap;
}

class TextMateOpen extends TextMateRequest {
  const TextMateOpen(
    this.documentId,
    this.languageId,
    this.encodedLanguageId,
    this.maxTokenizationLineLength,
    this.versionId,
    this.lines,
  );

  final int documentId;
  final String languageId;
  final int encodedLanguageId;

  /// `editor.maxTokenizationLineLength` for the language.
  final int maxTokenizationLineLength;
  final int versionId;
  final List<String> lines;
}

/// Lines `[startLineNumber, endLineNumberExclusive)` became [newLines] (at
/// least one) at [versionId].
class TextMateChange extends TextMateRequest {
  const TextMateChange(
    this.documentId,
    this.versionId,
    this.startLineNumber,
    this.endLineNumberExclusive,
    this.newLines,
  );

  final int documentId;
  final int versionId;
  final int startLineNumber;
  final int endLineNumberExclusive;
  final List<String> newLines;
}

/// The one-based lines on screen.
class TextMateViewport extends TextMateRequest {
  const TextMateViewport(this.documentId, this.first, this.last);

  final int documentId;
  final int first;
  final int last;
}

class TextMateClose extends TextMateRequest {
  const TextMateClose(this.documentId);

  final int documentId;
}

/// Code outside any document (a hover's code block), tokenized from the
/// initial state as `tokenizeToString` does.
class TextMateColorize extends TextMateRequest {
  const TextMateColorize(
    this.requestId,
    this.languageId,
    this.encodedLanguageId,
    this.maxTokenizationLineLength,
    this.lines,
  );

  final int requestId;
  final String languageId;
  final int encodedLanguageId;
  final int maxTokenizationLineLength;
  final List<String> lines;
}

/// The answer to a [TextMateReadFile]: the file's bytes, decoded here.
class TextMateFileContent extends TextMateRequest {
  const TextMateFileContent(this.requestId, this.bytes, [this.error]);

  final int requestId;
  final Uint8List? bytes;
  final String? error;
}

// Worker → UI isolate.

sealed class TextMateResponse {
  const TextMateResponse();
}

/// Asks the UI isolate for a grammar file, by its asset path.
class TextMateReadFile extends TextMateResponse {
  const TextMateReadFile(this.requestId, this.path);

  final int requestId;
  final String path;
}

/// End-offset tokens (`LineTokens.convertToEndOffset`) of some lines, as
/// of [versionId]; [heuristic] when tokenized from a guessed state.
class TextMateTokens extends TextMateResponse {
  const TextMateTokens(
    this.documentId,
    this.versionId,
    this.lines, {
    this.heuristic = false,
  });

  final int documentId;
  final int versionId;
  final List<(int lineNumber, Uint32List tokens)> lines;
  final bool heuristic;
}

/// End-offset tokens of every line of a [TextMateColorize]; null without a
/// grammar.
class TextMateColorized extends TextMateResponse {
  const TextMateColorized(this.requestId, this.lines);

  final int requestId;
  final List<Uint32List>? lines;
}

/// Something went wrong in the worker (upstream logs these).
class TextMateWorkerError extends TextMateResponse {
  const TextMateWorkerError(this.message);

  final String message;
}

/// The worker itself, whichever isolate it runs in.
class TextMateWorker implements ITMGrammarFactoryHost {
  TextMateWorker(this._send, IOnigLib onigLib)
    : _onigLib = Future.value(onigLib) {
    debugCreated++;
  }

  /// Workers made in this isolate: none on the UI isolate outside tests
  /// (which check it).
  static int debugCreated = 0;

  /// Lines a [TextMateColorize] had tokenized, in any worker of this
  /// isolate: those colored as before are not.
  static int debugColorizedLines = 0;

  final void Function(TextMateResponse response) _send;
  final Future<IOnigLib> _onigLib;
  TMGrammarFactory? _grammarFactory;
  final Map<int, Future<ICreateGrammarResult?>> _grammarCache = {};
  final Map<int, _Document> _documents = {};
  final Map<int, Completer<String>> _files = {};
  int _nextFileRequest = 0;

  void handle(TextMateRequest request) {
    switch (request) {
      case TextMateInit(:final grammars):
        _grammarFactory = TMGrammarFactory(this, grammars, _onigLib);
        _colored.clear();
      case TextMateSetTheme(:final theme, :final colorMap):
        _grammarFactory?.setTheme(theme, colorMap);
        // Its tokens carry the theme's colors.
        _colored.clear();
        for (final document in _documents.values) {
          document.tokenizer.retokenize(
            1,
            document.tokenizer.getLineCount() + 1,
          );
        }
      case TextMateOpen():
        _documents[request.documentId]?.tokenizer.dispose();
        _documents[request.documentId] = _Document(
          request.documentId,
          this,
          request,
        );
      case TextMateChange():
        _documents[request.documentId]?.tokenizer.acceptChange(
          request.versionId,
          request.startLineNumber,
          request.endLineNumberExclusive,
          request.newLines,
        );
      case TextMateViewport(:final documentId, :final first, :final last):
        _documents[documentId]?.tokenizer.tokenizeViewport(first, last);
      case TextMateClose(:final documentId):
        _documents.remove(documentId)?.tokenizer.dispose();
      case TextMateColorize():
        unawaited(_colorize(request));
      case TextMateFileContent(:final requestId, :final bytes, :final error):
        final completer = _files.remove(requestId);
        if (bytes != null) {
          completer?.complete(decodeTextMateResource(bytes));
        } else {
          completer?.completeError(StateError(error ?? 'Unreadable'));
        }
    }
  }

  /// `TextMateTokenizationWorker.getOrCreateGrammar`: one per language.
  Future<ICreateGrammarResult?> getOrCreateGrammar(
    String languageId,
    int encodedLanguageId,
  ) {
    final factory = _grammarFactory;
    if (factory == null || !factory.has(languageId)) {
      return Future.value(null);
    }
    return _grammarCache[encodedLanguageId] ??= factory
        .createGrammar(languageId, encodedLanguageId)
        .then<ICreateGrammarResult?>(
          (result) => result,
          onError: (Object error) {
            logError('Cannot create grammar for $languageId', error);
            return null;
          },
        );
  }

  Future<void> _colorize(TextMateColorize request) async {
    List<Uint32List>? lines;
    try {
      lines = await _tokenizeFromStart(request);
    } catch (error) {
      // Left uncolored, as the UI answers a failed colorization.
      logError('Cannot colorize ${request.languageId}', error);
    }
    _send(TextMateColorized(request.requestId, lines));
  }

  Future<List<Uint32List>?> _tokenizeFromStart(TextMateColorize request) async {
    final r = await getOrCreateGrammar(
      request.languageId,
      request.encodedLanguageId,
    );
    final grammar = r?.grammar;
    if (grammar == null) return null;
    // `_tokenizeToString` (textToHtmlTokenizer.ts), with the tokenization
    // support the language registers.
    final support = TokenizationSupportWithLineLimit(
      request.encodedLanguageId,
      TextMateTokenizationSupport(
        grammar,
        r!.initialState,
        r.containsEmbeddedLanguages,
      ),
      request.maxTokenizationLineLength,
    );
    // From the first line that changed of the code most like it colored
    // lately: code the agent writes on is not tokenized from the start
    // again for every piece of it.
    _Colored? before;
    var same = 0;
    for (final colored in _colored) {
      final kept = colored.sameLines(request);
      if (kept > same) (before, same) = (colored, kept);
    }
    final tokens = <Uint32List>[...?before?.tokens.take(same)];
    final states = <StateStack>[...?before?.states.take(same)];
    var currentState = same > 0 ? states.last : support.getInitialState();
    for (final line in request.lines.skip(same)) {
      final tokenizationResult = support.tokenizeEncoded(
        line,
        true,
        currentState,
      );
      LineTokens.convertToEndOffset(tokenizationResult.tokens, line.length);
      tokens.add(tokenizationResult.tokens);
      currentState = tokenizationResult.endState;
      states.add(currentState);
      debugColorizedLines++;
    }
    _colored
      ..remove(before)
      ..insert(0, _Colored(request, tokens, states));
    if (_colored.length > _coloredKept) _colored.removeLast();
    return tokens;
  }

  /// The code last colored, the latest first: a few blocks being written at
  /// once each go on from their own.
  final List<_Colored> _colored = [];
  static const _coloredKept = 8;

  void dispose() {
    for (final document in _documents.values) {
      document.tokenizer.dispose();
    }
    _documents.clear();
    _grammarFactory?.dispose();
  }

  // ITMGrammarFactoryHost.

  @override
  void logTrace(String msg) {}

  @override
  void logError(String msg, Object? err) =>
      _send(TextMateWorkerError('$msg: $err'));

  @override
  Future<String> readFile(String resource) {
    final requestId = _nextFileRequest++;
    final completer = _files[requestId] = Completer<String>();
    _send(TextMateReadFile(requestId, resource));
    return completer.future;
  }
}

/// Lines a [TextMateColorize] colored, each line's tokens and the state
/// after it.
class _Colored {
  _Colored(TextMateColorize request, this.tokens, this.states)
    : encodedLanguageId = request.encodedLanguageId,
      maxTokenizationLineLength = request.maxTokenizationLineLength,
      lines = request.lines;

  final int encodedLanguageId;
  final int maxTokenizationLineLength;
  final List<String> lines;
  final List<Uint32List> tokens;
  final List<StateStack> states;

  /// How many of [request]'s first lines are these, tokenized the same.
  int sameLines(TextMateColorize request) {
    if (request.encodedLanguageId != encodedLanguageId ||
        request.maxTokenizationLineLength != maxTokenizationLineLength) {
      return 0;
    }
    final other = request.lines;
    var same = 0;
    while (same < lines.length &&
        same < other.length &&
        lines[same] == other[same]) {
      same++;
    }
    return same;
  }
}

class _Document implements TextMateModelTokenizerHost {
  _Document(this.documentId, this._worker, TextMateOpen open) {
    tokenizer = TextMateWorkerTokenizer(
      open.lines,
      open.versionId,
      this,
      open.languageId,
      open.encodedLanguageId,
      open.maxTokenizationLineLength,
    );
  }

  final int documentId;
  final TextMateWorker _worker;
  late final TextMateWorkerTokenizer tokenizer;

  @override
  Future<ICreateGrammarResult?> getOrCreateGrammar(
    String languageId,
    int encodedLanguageId,
  ) => _worker.getOrCreateGrammar(languageId, encodedLanguageId);

  @override
  void setTokens(
    int versionId,
    List<(int, Uint32List)> tokens, {
    bool heuristic = false,
  }) => _worker._send(
    TextMateTokens(documentId, versionId, tokens, heuristic: heuristic),
  );
}

/// Where the UI isolate talks to a worker.
abstract interface class TextMateWorkerChannel {
  void send(TextMateRequest request);

  Stream<TextMateResponse> get responses;

  void dispose();
}

/// A worker in a background isolate; null on the web, or where Oniguruma is
/// unavailable.
Future<TextMateWorkerChannel?> spawnTextMateWorker() =>
    platform.spawnTextMateWorker();

/// The worker in the calling isolate, for widget tests (whose fake clock
/// real isolates do not follow). Messages still go through the event loop.
class TextMateInProcessWorker implements TextMateWorkerChannel {
  TextMateInProcessWorker._(IOnigLib onigLib) {
    _worker = TextMateWorker((response) {
      scheduleMicrotask(() {
        if (!_responses.isClosed) _responses.add(response);
      });
    }, onigLib);
  }

  /// Null where Oniguruma is unavailable.
  static TextMateInProcessWorker? create() {
    final onigLib = loadNativeOnigLib();
    return onigLib == null ? null : TextMateInProcessWorker._(onigLib);
  }

  late final TextMateWorker _worker;
  final StreamController<TextMateResponse> _responses =
      StreamController.broadcast();

  @override
  void send(TextMateRequest request) =>
      scheduleMicrotask(() => _worker.handle(request));

  @override
  Stream<TextMateResponse> get responses => _responses.stream;

  @override
  void dispose() {
    _worker.dispose();
    unawaited(_responses.close());
  }
}
