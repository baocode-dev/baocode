import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:baocode/ide/language/language_features.dart';
import 'package:baocode/ide/language/language_types.dart';

/// Scripted language services for widget tests: answers come from the
/// `on*` callbacks (empty when unset) and every request is recorded in
/// [requests] as `'<kind> <basename-free path> <line>:<character>'`.
class FakeLanguageFeatures extends ChangeNotifier implements LanguageFeatures {
  FakeLanguageFeatures({Set<LanguageRequest>? supported})
    : supported = supported ?? LanguageRequest.values.toSet();

  /// What [supports] answers for every document.
  Set<LanguageRequest> supported;

  final Map<String, List<LspDiagnostic>> diagnostics = {};
  Set<String> completionTriggers = {'.'};
  Set<String> signatureTriggers = {'(', ','};
  Set<String> signatureRetriggers = {')'};

  final List<String> requests = [];
  final List<(LspCommand, String?)> executed = [];

  LspHover? Function(String path, LspPosition position)? onHover;
  List<LspLocation> Function(String path, LspPosition position)? onDefinition;
  List<LspLocation> Function(String path, LspPosition position)?
  onTypeDefinition;
  List<LspLocation> Function(String path, LspPosition position)?
  onImplementation;
  List<LspLocation> Function(String path, LspPosition position)? onReferences;
  LspCompletionList Function(
    String path,
    LspPosition position,
    String? triggerCharacter,
  )?
  onCompletion;
  LspCompletionItem Function(LspCompletionItem item)? onResolveCompletion;
  LspSignatureHelp? Function(String path, LspPosition position)?
  onSignatureHelp;
  ({LspRange range, String placeholder})? Function(
    String path,
    LspPosition position,
  )?
  onPrepareRename;
  LspWorkspaceEdit? Function(String path, LspPosition position, String newName)?
  onRename;
  List<LspTextEdit> Function(String path, LspRange? range)? onFormat;
  List<LspDocumentSymbol> Function(String path)? onDocumentSymbols;
  List<LspCodeAction> Function(
    String path,
    LspRange range,
    List<LspDiagnostic> diagnostics,
  )?
  onCodeActions;
  LspCodeAction Function(LspCodeAction action)? onResolveCodeAction;
  List<LspSemanticToken>? Function(String path)? onSemanticTokens;

  final _workspaceEdits = StreamController<LspApplyEditRequest>.broadcast();

  void setDiagnostics(String path, List<LspDiagnostic> list) {
    diagnostics[path] = list;
    notifyListeners();
  }

  /// Sends a `workspace/applyEdit` and completes with the editor's answer.
  Future<bool> requestApplyEdit(LspWorkspaceEdit edit) {
    final request = LspApplyEditRequest(edit);
    final answer = Completer<bool>();
    request.onComplete(answer.complete);
    _workspaceEdits.add(request);
    return answer.future;
  }

  void _record(String kind, String path, [LspPosition? position]) =>
      requests.add(position == null ? '$kind $path' : '$kind $path $position');

  int count(String kind) =>
      requests.where((r) => r.startsWith('$kind ')).length;

  @override
  List<LspDiagnostic> diagnosticsFor(String path) =>
      diagnostics[path] ?? const [];

  @override
  Map<String, List<LspDiagnostic>> get allDiagnostics => diagnostics;

  @override
  bool supports(String path, LanguageRequest request) =>
      supported.contains(request);

  @override
  Set<String> completionTriggerCharacters(String path) => completionTriggers;

  @override
  Set<String> signatureHelpTriggerCharacters(String path) => signatureTriggers;

  @override
  Set<String> signatureHelpRetriggerCharacters(String path) =>
      signatureRetriggers;

  @override
  Future<LspHover?> hover(String path, LspPosition position) async {
    _record('hover', path, position);
    return onHover?.call(path, position);
  }

  @override
  Future<List<LspLocation>> definition(
    String path,
    LspPosition position,
  ) async {
    _record('definition', path, position);
    return onDefinition?.call(path, position) ?? const [];
  }

  @override
  Future<List<LspLocation>> typeDefinition(
    String path,
    LspPosition position,
  ) async {
    _record('typeDefinition', path, position);
    return onTypeDefinition?.call(path, position) ?? const [];
  }

  @override
  Future<List<LspLocation>> implementation(
    String path,
    LspPosition position,
  ) async {
    _record('implementation', path, position);
    return onImplementation?.call(path, position) ?? const [];
  }

  @override
  Future<List<LspLocation>> references(
    String path,
    LspPosition position, {
    bool includeDeclaration = true,
  }) async {
    _record('references', path, position);
    return onReferences?.call(path, position) ?? const [];
  }

  @override
  Future<LspCompletionList> completion(
    String path,
    LspPosition position, {
    String? triggerCharacter,
    bool retrigger = false,
  }) async {
    _record('completion', path, position);
    return onCompletion?.call(path, position, triggerCharacter) ??
        LspCompletionList.empty;
  }

  @override
  Future<LspCompletionItem> resolveCompletion(
    String path,
    LspCompletionItem item,
  ) async {
    _record('resolveCompletion', path);
    return onResolveCompletion?.call(item) ?? item;
  }

  @override
  Future<LspSignatureHelp?> signatureHelp(
    String path,
    LspPosition position, {
    String? triggerCharacter,
    bool retrigger = false,
  }) async {
    _record('signatureHelp', path, position);
    return onSignatureHelp?.call(path, position);
  }

  @override
  Future<({LspRange range, String placeholder})?> prepareRename(
    String path,
    LspPosition position,
  ) async {
    _record('prepareRename', path, position);
    return onPrepareRename?.call(path, position);
  }

  @override
  Future<LspWorkspaceEdit?> rename(
    String path,
    LspPosition position,
    String newName,
  ) async {
    _record('rename', path, position);
    return onRename?.call(path, position, newName);
  }

  @override
  Future<List<LspTextEdit>> format(
    String path, {
    LspRange? range,
    required int tabSize,
    required bool insertSpaces,
  }) async {
    _record('format', path);
    return onFormat?.call(path, range) ?? const [];
  }

  @override
  Future<List<LspDocumentSymbol>> documentSymbols(String path) async {
    _record('documentSymbols', path);
    return onDocumentSymbols?.call(path) ?? const [];
  }

  @override
  Future<List<LspCodeAction>> codeActions(
    String path,
    LspRange range, {
    List<LspDiagnostic> diagnostics = const [],
    List<String>? only,
  }) async {
    _record('codeActions', path, range.start);
    return onCodeActions?.call(path, range, diagnostics) ?? const [];
  }

  @override
  Future<LspCodeAction> resolveCodeAction(
    String path,
    LspCodeAction action,
  ) async {
    _record('resolveCodeAction', path);
    return onResolveCodeAction?.call(action) ?? action;
  }

  @override
  Future<void> executeCommand(
    String path,
    LspCommand command, {
    String? serverId,
  }) async {
    _record('executeCommand', path);
    executed.add((command, serverId));
  }

  @override
  Future<List<LspSemanticToken>?> semanticTokens(String path) async {
    _record('semanticTokens', path);
    return onSemanticTokens?.call(path);
  }

  @override
  Stream<LspApplyEditRequest> get workspaceEdits => _workspaceEdits.stream;

  @override
  void dispose() {
    unawaited(_workspaceEdits.close());
    super.dispose();
  }
}

/// A zero-based range on one line.
LspRange lspRange(int line, int start, int end, {int? endLine}) =>
    LspRange(LspPosition(line, start), LspPosition(endLine ?? line, end));
