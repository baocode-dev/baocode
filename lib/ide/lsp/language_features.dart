import 'package:flutter/foundation.dart';

import 'lsp_protocol.dart';

/// What the editor asks of language servers, for one workspace. The LSP
/// manager implements it over every server attached to a document (merging
/// answers in the language's server order); tests use in-memory fakes.
///
/// Documents are addressed by absolute file path. Positions use the
/// protocol's zero-based line and UTF-16 character, which the editor's
/// [DocumentSnapshot] maps directly. Requests for a document no server
/// serves complete with an empty answer. Every request reflects the
/// document's latest synchronized text.
///
/// Notifies when diagnostics, server status, or capabilities change.
abstract interface class LanguageFeatures implements Listenable {
  /// Diagnostics for [path] from every server, in server order.
  List<LspDiagnostic> diagnosticsFor(String path);

  /// All documents with diagnostics, for the problems panel.
  Map<String, List<LspDiagnostic>> get allDiagnostics;

  /// Whether some running server attached to [path] can answer [request].
  bool supports(String path, LanguageRequest request);

  /// Characters that should open completion / signature help in [path].
  Set<String> completionTriggerCharacters(String path);
  Set<String> signatureHelpTriggerCharacters(String path);
  Set<String> signatureHelpRetriggerCharacters(String path);

  Future<LspHover?> hover(String path, LspPosition position);
  Future<List<LspLocation>> definition(String path, LspPosition position);
  Future<List<LspLocation>> typeDefinition(String path, LspPosition position);
  Future<List<LspLocation>> implementation(String path, LspPosition position);
  Future<List<LspLocation>> references(
    String path,
    LspPosition position, {
    bool includeDeclaration = true,
  });

  /// [triggerCharacter] is the typed character that opened it, if any.
  Future<LspCompletionList> completion(
    String path,
    LspPosition position, {
    String? triggerCharacter,
    bool retrigger = false,
  });

  /// Fills in documentation/edits the list left out; the item itself when
  /// its server cannot resolve.
  Future<LspCompletionItem> resolveCompletion(
    String path,
    LspCompletionItem item,
  );

  Future<LspSignatureHelp?> signatureHelp(
    String path,
    LspPosition position, {
    String? triggerCharacter,
    bool retrigger = false,
  });

  /// The range and placeholder to rename at [position]; null when the
  /// servers say nothing can be renamed there (or do not support asking).
  Future<({LspRange range, String placeholder})?> prepareRename(
    String path,
    LspPosition position,
  );
  Future<LspWorkspaceEdit?> rename(
    String path,
    LspPosition position,
    String newName,
  );

  /// Formats [path], or [range] of it.
  Future<List<LspTextEdit>> format(
    String path, {
    LspRange? range,
    required int tabSize,
    required bool insertSpaces,
  });

  Future<List<LspDocumentSymbol>> documentSymbols(String path);

  Future<List<LspCodeAction>> codeActions(
    String path,
    LspRange range, {
    List<LspDiagnostic> diagnostics = const [],
    List<String>? only,
  });
  Future<LspCodeAction> resolveCodeAction(String path, LspCodeAction action);

  /// Runs a server command (from a code action or completion item) on the
  /// server that offered it. Edits the server then applies arrive through
  /// [workspaceEdits].
  Future<void> executeCommand(
    String path,
    LspCommand command, {
    String? serverId,
  });

  /// Semantic tokens for the whole of [path], decoded; null when no server
  /// provides them.
  Future<List<LspSemanticToken>?> semanticTokens(String path);

  /// `workspace/applyEdit` requests from servers: the editor applies each
  /// edit and completes with whether it did.
  Stream<LspApplyEditRequest> get workspaceEdits;

  /// Servers for [path] and how they stand, for the status bar.
  List<LanguageServerStatus> statusFor(String path);

  /// Restarts a failed or stopped server now, resetting its backoff.
  void retry(String serverId, {String? path});

  /// Installs the package a missing server needs, then starts it.
  Future<void> install(String serverId, {String? path});
}

enum LanguageRequest {
  hover,
  definition,
  typeDefinition,
  implementation,
  references,
  completion,
  signatureHelp,
  rename,
  format,
  rangeFormat,
  documentSymbols,
  codeActions,
  semanticTokens,
}

class LspApplyEditRequest {
  LspApplyEditRequest(this.edit, {this.label});

  final LspWorkspaceEdit edit;
  final String? label;
  final _done = <void Function(bool)>[];

  bool _answered = false;

  /// Answers the server; later calls are ignored.
  void complete(bool applied) {
    if (_answered) return;
    _answered = true;
    for (final callback in _done) {
      callback(applied);
    }
  }

  /// For the manager: called with the editor's answer.
  void onComplete(void Function(bool applied) callback) => _done.add(callback);
}

enum LanguageServerState {
  /// Not started yet (starts on the first document it serves).
  idle,
  starting,
  running,

  /// Stopped after being idle; starts again when needed.
  stopped,

  /// Crashed; restarting after a backoff (see [LanguageServerStatus.retryAt]).
  restarting,

  /// Gave up after repeated crashes, or could not start.
  failed,

  /// Its executable is not on PATH or installed.
  missing,
  installing,
}

class LanguageServerStatus {
  const LanguageServerStatus({
    required this.serverId,
    required this.state,
    this.message,
    this.progress,
    this.installable = false,
    this.missingRuntime,
    this.retryAt,
  });

  final String serverId;
  final LanguageServerState state;

  /// Why it failed, or what an install is doing.
  final String? message;

  /// A `$/progress` title and message from the server (e.g. indexing).
  final String? progress;

  /// Whether [LanguageFeatures.install] can install it.
  final bool installable;

  /// A runtime installing needs but is absent (`node`, `python3`, `go`).
  final String? missingRuntime;
  final DateTime? retryAt;
}

/// What the workspace tells the language servers about its documents
/// (implemented by the LSP manager; [IdeWorkspace] calls it). Paths are
/// absolute; versions increase with every change.
abstract interface class LanguageDocumentSync {
  /// [path] was opened with [text].
  void openDocument(String path, String text, {int version = 0});

  /// [path] now reads [text] at [version]: [changes] (in the protocol's
  /// sequential order) turn the previous text into it; null when only the
  /// whole text is known.
  void changeDocument(
    String path,
    String text, {
    required int version,
    List<LspTextDocumentContentChange>? changes,
  });

  /// [path] was saved with [text].
  void saveDocument(String path, String text);

  void closeDocument(String path);

  /// Stops every server; the workspace calls it when disposed. Later
  /// documents are ignored.
  Future<void> shutdown();
}
