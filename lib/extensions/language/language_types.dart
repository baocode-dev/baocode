/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The values language feature providers produce. Ranges and positions are
// one-based model coordinates of the document they refer to (UTF-16
// columns, no BOM), as in VS Code's main thread.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/editor/common/languages.ts (Hover, Completion*, InlineCompletion*,
// CodeAction*, SignatureHelp*, DocumentHighlight*, LinkedEditingRanges,
// Location, LocationLink, SymbolKind, SymbolTag, DocumentSymbol, TextEdit,
// FormattingOptions, ILink, IColor*, SelectionRange, FoldingRange*,
// WorkspaceEdit, Rejection, RenameLocation, Command, CodeLens*, InlayHint*,
// SemanticTokens*), src/vs/base/common/htmlContent.ts (`IMarkdownString`),
// src/vs/editor/common/model.ts (`EndOfLineSequence`),
// src/vs/editor/common/core/editOperation.ts (`ISingleEditOperation`),
// src/vs/workbench/contrib/search/common/search.ts (`IWorkspaceSymbol`),
// src/vs/workbench/contrib/callHierarchy/common/callHierarchy.ts and
// src/vs/workbench/contrib/typeHierarchy/common/typeHierarchy.ts (items,
// calls, sessions).
//
// Deviations:
// - Unions become Dart types: `string | IMarkdownString` documentation is a
//   [MarkdownString] (plain strings via [MarkdownString.plain]); `string |
//   CompletionItemLabel` is a [CompletionItemLabel]; `IRange |
//   CompletionItemRanges` is [CompletionItemRanges] (equal insert/replace for
//   a plain range); `Definition` is a list of [LocationLink]s.
// - `dispose?()` on lists is an optional [onDispose] callback.
// - Internal/telemetry-only fields (`_id`, `extensionId` objects, inline
//   completion lifetime and model-picker fields) are omitted; provider
//   identity lives on the provider objects.

import 'dart:typed_data';

import 'package:bao_editor/monaco/vs/editor/common/core/position.dart';
import 'package:bao_editor/monaco/vs/editor/common/core/range.dart';
import 'package:bao_exthost/bao_exthost.dart' show VsUri;

import 'marker_service.dart' show MarkerData;

export 'package:bao_editor/monaco/vs/editor/common/core/position.dart'
    show IPosition, Position;
export 'package:bao_editor/monaco/vs/editor/common/core/range.dart'
    show IRange, Range;

/// Something a provider result holds on to until the editor is done with it
/// (`IDisposable` lists).
mixin DisposableResult {
  /// Releases what the provider keeps for this result (the extension host's
  /// cached items); called once.
  void Function()? get onDispose;

  void dispose() => onDispose?.call();
}

/// `IMarkdownString`.
class MarkdownString {
  const MarkdownString(
    this.value, {
    this.isTrusted = false,
    this.supportThemeIcons = false,
    this.supportHtml = false,
    this.baseUri,
  });

  /// A plain-text string as Markdown (escaped like `MarkdownString.appendText`).
  factory MarkdownString.plain(String text) => MarkdownString(
    text.replaceAllMapped(
      RegExp(r'[\\`*_{}\[\]()#+\-!~|<>]'),
      (m) => '\\${m[0]}',
    ),
  );

  final String value;
  final bool isTrusted;
  final bool supportThemeIcons;
  final bool supportHtml;
  final VsUri? baseUri;
}

/// `Command`.
class Command {
  const Command({
    required this.id,
    required this.title,
    this.tooltip,
    this.arguments,
  });

  final String id;
  final String title;
  final String? tooltip;
  final List<Object?>? arguments;
}

/// `ISingleEditOperation` / `TextEdit` without `eol`.
class SingleEditOperation {
  const SingleEditOperation(this.range, this.text, {this.forceMoveMarkers});

  final IRange range;

  /// Null deletes.
  final String? text;
  final bool? forceMoveMarkers;
}

/// `EndOfLineSequence`.
enum EndOfLineSequence { lf, crlf }

/// `TextEdit`.
class TextEdit {
  const TextEdit(this.range, this.text, {this.eol});

  final IRange range;
  final String text;

  /// Switch the document to this EOL as part of the edit.
  final EndOfLineSequence? eol;
}

// --- hover

/// `Hover`.
class Hover {
  const Hover(
    this.contents, {
    this.range,
    this.canIncreaseVerbosity = false,
    this.canDecreaseVerbosity = false,
  });

  final List<MarkdownString> contents;

  /// The range the hover applies to. The editor drops hovers without one
  /// (`isValid` in getHover.ts); extension host hovers always have one.
  final IRange? range;
  final bool canIncreaseVerbosity;
  final bool canDecreaseVerbosity;
}

/// `HoverVerbosityAction`.
enum HoverVerbosityAction { increase, decrease }

/// `HoverContext` with its `HoverVerbosityRequest`.
class HoverContext {
  const HoverContext({this.verbosityDelta, this.previousHover});

  final int? verbosityDelta;
  final Hover? previousHover;
}

// --- completion

/// `CompletionItemKind`, in upstream order (the index is the protocol value).
enum CompletionItemKind {
  method,
  function,
  constructor,
  field,
  variable,
  klass,
  struct,
  interface,
  module,
  property,
  event,
  operator,
  unit,
  value,
  constant,
  enumeration,
  enumMember,
  keyword,
  text,
  color,
  file,
  reference,
  customcolor,
  folder,
  typeParameter,
  user,
  issue,
  tool,
  snippet,
}

/// `CompletionItemTag`.
enum CompletionItemTag {
  deprecated(1);

  const CompletionItemTag(this.value);
  final int value;
}

/// `CompletionItemInsertTextRule` bits.
abstract final class CompletionItemInsertTextRule {
  static const none = 0;

  /// Adjust whitespace/indentation of multiline insert texts to match the
  /// current line indentation.
  static const keepWhitespace = 0x1;

  /// `insertText` is a snippet.
  static const insertAsSnippet = 0x4;
}

/// `CompletionItemLabel` (a plain label has no detail/description).
class CompletionItemLabel {
  const CompletionItemLabel(this.label, {this.detail, this.description});

  final String label;
  final String? detail;
  final String? description;
}

/// `CompletionItemRanges`: what accepting inserts over (insert) or
/// replaces (replace); single-line ranges containing the position.
class CompletionItemRanges {
  const CompletionItemRanges({required this.insert, required this.replace});

  /// A plain `IRange`.
  CompletionItemRanges.single(IRange range) : insert = range, replace = range;

  final IRange insert;
  final IRange replace;
}

/// `CompletionItem`. [range] and [sortText] may be left out; the editor
/// fills them in (`provideSuggestionItems`).
class CompletionItem {
  CompletionItem({
    required this.label,
    required this.kind,
    required this.insertText,
    this.tags = const [],
    this.detail,
    this.documentation,
    this.sortText,
    this.filterText,
    this.preselect = false,
    this.insertTextRules = CompletionItemInsertTextRule.none,
    this.range,
    this.commitCharacters,
    this.additionalTextEdits,
    this.command,
    this.action,
    this.data,
  });

  final CompletionItemLabel label;
  final CompletionItemKind kind;
  final List<CompletionItemTag> tags;
  final String? detail;
  final MarkdownString? documentation;
  String? sortText;
  final String? filterText;
  final bool preselect;
  final String insertText;

  /// [CompletionItemInsertTextRule] bits.
  final int insertTextRules;
  CompletionItemRanges? range;
  final List<String>? commitCharacters;
  final List<SingleEditOperation>? additionalTextEdits;
  final Command? command;
  final Command? action;

  /// Provider data a resolve needs (the extension host's cache id).
  final Object? data;

  bool get isSnippet =>
      insertTextRules & CompletionItemInsertTextRule.insertAsSnippet != 0;
  bool get isDeprecated => tags.contains(CompletionItemTag.deprecated);
}

/// `CompletionList`.
class CompletionList with DisposableResult {
  CompletionList(this.suggestions, {this.incomplete = false, this.onDispose});

  final List<CompletionItem> suggestions;
  final bool incomplete;
  @override
  final void Function()? onDispose;
}

/// `CompletionTriggerKind`.
enum CompletionTriggerKind {
  invoke,
  triggerCharacter,
  triggerForIncompleteCompletions,
}

/// `CompletionContext`.
class CompletionContext {
  const CompletionContext(this.triggerKind, {this.triggerCharacter});

  final CompletionTriggerKind triggerKind;
  final String? triggerCharacter;
}

// --- inline completions

/// `InlineCompletionTriggerKind`.
enum InlineCompletionTriggerKind { automatic, explicit }

/// `SelectedSuggestionInfo`.
class SelectedSuggestionInfo {
  const SelectedSuggestionInfo(
    this.range,
    this.text,
    this.completionKind,
    this.isSnippetText,
  );

  final IRange range;
  final String text;
  final CompletionItemKind completionKind;
  final bool isSnippetText;
}

/// `InlineCompletionContext` (the fields extensions see).
class InlineCompletionContext {
  const InlineCompletionContext({
    required this.triggerKind,
    required this.requestUuid,
    this.selectedSuggestionInfo,
    this.includeInlineEdits = true,
    this.includeInlineCompletions = true,
    this.requestIssuedDateTime = 0,
    this.earliestShownDateTime = 0,
  });

  final InlineCompletionTriggerKind triggerKind;
  final SelectedSuggestionInfo? selectedSuggestionInfo;
  final String requestUuid;
  final bool includeInlineEdits;
  final bool includeInlineCompletions;
  final int requestIssuedDateTime;
  final int earliestShownDateTime;
}

/// `InlineCompletion`.
class InlineCompletion {
  const InlineCompletion({
    this.insertText,
    this.snippet,
    this.range,
    this.additionalTextEdits,
    this.command,
    this.completeBracketPairs = false,
    this.isInlineEdit = false,
    this.showRange,
    this.correlationId,
  });

  /// The text, unless [snippet] is set.
  final String? insertText;

  /// `{ snippet }` insert text.
  final String? snippet;
  final IRange? range;
  final List<SingleEditOperation>? additionalTextEdits;
  final Command? command;
  final bool completeBracketPairs;
  final bool isInlineEdit;
  final IRange? showRange;
  final String? correlationId;
}

/// `InlineCompletions`.
class InlineCompletions {
  const InlineCompletions(
    this.items, {
    this.commands = const [],
    this.suppressSuggestions,
    this.enableForwardStability,
  });

  final List<InlineCompletion> items;
  final List<Command> commands;
  final bool? suppressSuggestions;
  final bool? enableForwardStability;
}

/// `InlineCompletionsDisposeReason.kind`.
enum InlineCompletionsDisposeReason {
  lostRace,
  tokenCancellation,
  other,
  empty,
  notTaken,
}

// --- code actions

/// `CodeAction`.
class CodeAction {
  const CodeAction({
    required this.title,
    this.command,
    this.edit,
    this.diagnostics,
    this.kind,
    this.isPreferred = false,
    this.isAI = false,
    this.disabled,
    this.ranges,
    this.data,
  });

  final String title;
  final Command? command;
  final WorkspaceEdit? edit;

  final List<MarkerData>? diagnostics;
  final String? kind;
  final bool isPreferred;
  final bool isAI;

  /// Why it cannot be applied, when it cannot.
  final String? disabled;
  final List<IRange>? ranges;

  /// Provider data a resolve needs (the extension host's cache ids).
  final Object? data;
}

/// `CodeActionTriggerType`.
enum CodeActionTriggerType {
  invoke(1),
  auto(2);

  const CodeActionTriggerType(this.value);
  final int value;
}

/// `CodeActionContext`.
class CodeActionContext {
  const CodeActionContext({required this.trigger, this.only});

  final String? only;
  final CodeActionTriggerType trigger;
}

/// `CodeActionList`.
class CodeActionList with DisposableResult {
  CodeActionList(this.actions, {this.onDispose});

  final List<CodeAction> actions;
  @override
  final void Function()? onDispose;
}

// --- signature help

/// `ParameterInformation`: [label] is a string, or [labelOffsets] into the
/// signature label.
class ParameterInformation {
  const ParameterInformation({
    this.label,
    this.labelOffsets,
    this.documentation,
  });

  final String? label;
  final (int, int)? labelOffsets;
  final MarkdownString? documentation;
}

/// `SignatureInformation`.
class SignatureInformation {
  const SignatureInformation({
    required this.label,
    this.documentation,
    this.parameters = const [],
    this.activeParameter,
  });

  final String label;
  final MarkdownString? documentation;
  final List<ParameterInformation> parameters;
  final int? activeParameter;
}

/// `SignatureHelp`.
class SignatureHelp {
  const SignatureHelp({
    required this.signatures,
    this.activeSignature = 0,
    this.activeParameter = 0,
  });

  final List<SignatureInformation> signatures;
  final int activeSignature;
  final int activeParameter;
}

/// `SignatureHelpResult`.
class SignatureHelpResult with DisposableResult {
  SignatureHelpResult(this.value, {this.onDispose});

  final SignatureHelp value;
  @override
  final void Function()? onDispose;
}

/// `SignatureHelpTriggerKind`.
enum SignatureHelpTriggerKind {
  invoke(1),
  triggerCharacter(2),
  contentChange(3);

  const SignatureHelpTriggerKind(this.value);
  final int value;
}

/// `SignatureHelpContext`.
class SignatureHelpContext {
  const SignatureHelpContext({
    required this.triggerKind,
    this.triggerCharacter,
    this.isRetrigger = false,
    this.activeSignatureHelp,
  });

  final SignatureHelpTriggerKind triggerKind;
  final String? triggerCharacter;
  final bool isRetrigger;
  final SignatureHelp? activeSignatureHelp;
}

// --- highlights, linked editing

/// `DocumentHighlightKind`.
enum DocumentHighlightKind { text, read, write }

/// `DocumentHighlight`.
class DocumentHighlight {
  const DocumentHighlight(this.range, {this.kind});

  final IRange range;
  final DocumentHighlightKind? kind;
}

/// `LinkedEditingRanges`.
class LinkedEditingRanges {
  const LinkedEditingRanges(this.ranges, {this.wordPattern});

  final List<IRange> ranges;
  final RegExp? wordPattern;
}

// --- locations

/// `ReferenceContext`.
class ReferenceContext {
  const ReferenceContext({required this.includeDeclaration});

  final bool includeDeclaration;
}

/// `Location`.
class Location {
  const Location(this.uri, this.range);

  final VsUri uri;
  final IRange range;
}

/// `LocationLink` (a plain `Location` has no origin/target selection).
class LocationLink {
  const LocationLink({
    required this.uri,
    required this.range,
    this.originSelectionRange,
    this.targetSelectionRange,
  });

  factory LocationLink.fromLocation(Location location) =>
      LocationLink(uri: location.uri, range: location.range);

  final IRange? originSelectionRange;
  final VsUri uri;

  /// The full target range.
  final IRange range;

  /// The part of [range] to select (a symbol's name).
  final IRange? targetSelectionRange;
}

// --- symbols

/// `SymbolKind` (the index is the protocol value).
enum SymbolKind {
  file,
  module,
  namespace,
  package,
  klass,
  method,
  property,
  field,
  constructor,
  enumeration,
  interface,
  function,
  variable,
  constant,
  string,
  number,
  boolean,
  array,
  object,
  key,
  nullValue,
  enumMember,
  struct,
  event,
  operator,
  typeParameter,
}

/// `SymbolTag`.
enum SymbolTag {
  deprecated(1);

  const SymbolTag(this.value);
  final int value;
}

/// `DocumentSymbol`.
class DocumentSymbol {
  const DocumentSymbol({
    required this.name,
    required this.kind,
    required this.range,
    required this.selectionRange,
    this.detail = '',
    this.tags = const [],
    this.containerName,
    this.children,
  });

  final String name;
  final String detail;
  final SymbolKind kind;
  final List<SymbolTag> tags;
  final String? containerName;
  final IRange range;
  final IRange selectionRange;
  final List<DocumentSymbol>? children;
}

/// `IWorkspaceSymbol`.
class WorkspaceSymbol {
  const WorkspaceSymbol({
    required this.name,
    required this.kind,
    required this.location,
    this.containerName,
    this.tags = const [],
    this.data,
  });

  final String name;
  final String? containerName;
  final SymbolKind kind;
  final List<SymbolTag> tags;
  final Location location;

  /// Provider data a resolve needs.
  final Object? data;
}

// --- formatting

/// `FormattingOptions`.
class FormattingOptions {
  const FormattingOptions({required this.tabSize, required this.insertSpaces});

  final int tabSize;
  final bool insertSpaces;
}

/// `FormattingMode` (format.ts): a user gesture or an automatic format.
enum FormattingMode { explicit, silent }

/// `FormattingKind` (format.ts).
enum FormattingKind { file, selection }

// --- links, colors

/// `ILink`.
class Link {
  const Link(this.range, {this.url, this.tooltip, this.data});

  final IRange range;

  /// A [VsUri] or a string (a command URI, an unparsed URL); null until
  /// resolved.
  final Object? url;
  final String? tooltip;

  /// Provider data a resolve needs.
  final Object? data;
}

/// `ILinksList`.
class LinksList with DisposableResult {
  LinksList(this.links, {this.onDispose});

  final List<Link> links;
  @override
  final void Function()? onDispose;
}

/// `IColor`: channels in 0..1.
class Color {
  const Color(this.red, this.green, this.blue, this.alpha);

  final double red;
  final double green;
  final double blue;
  final double alpha;
}

/// `IColorPresentation`.
class ColorPresentation {
  const ColorPresentation(
    this.label, {
    this.textEdit,
    this.additionalTextEdits,
  });

  final String label;
  final TextEdit? textEdit;
  final List<TextEdit>? additionalTextEdits;
}

/// `IColorInformation`.
class ColorInformation {
  const ColorInformation(this.range, this.color, {this.data});

  final IRange range;
  final Color color;

  /// Provider data a color presentation needs (the extension host's cache
  /// id); null when the provider cannot resolve one.
  final Object? data;
}

// --- selection, folding

/// `SelectionRange`.
class SelectionRange {
  const SelectionRange(this.range);

  final IRange range;
}

/// `FoldingContext`.
class FoldingContext {
  const FoldingContext();
}

/// `FoldingRangeKind`.
class FoldingRangeKind {
  const FoldingRangeKind(this.value);

  static const comment = FoldingRangeKind('comment');
  static const imports = FoldingRangeKind('imports');
  static const region = FoldingRangeKind('region');

  static FoldingRangeKind fromValue(String value) => switch (value) {
    'comment' => comment,
    'imports' => imports,
    'region' => region,
    _ => FoldingRangeKind(value),
  };

  final String value;
}

/// `FoldingRange`: one-based lines [start] (shown) to [end] (hidden).
class FoldingRange {
  const FoldingRange(this.start, this.end, {this.kind});

  final int start;
  final int end;
  final FoldingRangeKind? kind;
}

// --- workspace edits, rename

/// `WorkspaceEditMetadata`.
class WorkspaceEditMetadata {
  const WorkspaceEditMetadata({
    required this.needsConfirmation,
    required this.label,
    this.description,
  });

  final bool needsConfirmation;
  final String label;
  final String? description;
}

/// `WorkspaceFileEditOptions`.
class WorkspaceFileEditOptions {
  const WorkspaceFileEditOptions({
    this.overwrite,
    this.ignoreIfNotExists,
    this.ignoreIfExists,
    this.recursive,
    this.copy,
    this.folder,
    this.skipTrashBin,
    this.maxSize,
    this.contents,
  });

  final bool? overwrite;
  final bool? ignoreIfNotExists;
  final bool? ignoreIfExists;
  final bool? recursive;
  final bool? copy;
  final bool? folder;
  final bool? skipTrashBin;
  final int? maxSize;

  /// Content of a created file.
  final Future<Uint8List>? contents;
}

/// One entry of a [WorkspaceEdit].
sealed class WorkspaceEditEntry {
  const WorkspaceEditEntry({this.metadata});

  final WorkspaceEditMetadata? metadata;
}

/// `IWorkspaceTextEdit`.
final class WorkspaceTextEdit extends WorkspaceEditEntry {
  const WorkspaceTextEdit({
    required this.resource,
    required this.textEdit,
    this.versionId,
    this.insertAsSnippet = false,
    this.keepWhitespace = false,
    super.metadata,
  });

  final VsUri resource;
  final TextEdit textEdit;

  /// The model version the edit was computed against, if checked.
  final int? versionId;
  final bool insertAsSnippet;
  final bool keepWhitespace;
}

/// `IWorkspaceFileEdit`: create ([newResource] only), delete
/// ([oldResource] only), rename/copy (both).
final class WorkspaceFileEdit extends WorkspaceEditEntry {
  const WorkspaceFileEdit({
    this.oldResource,
    this.newResource,
    this.options,
    super.metadata,
  });

  final VsUri? oldResource;
  final VsUri? newResource;
  final WorkspaceFileEditOptions? options;
}

/// `WorkspaceEdit & Rejection`.
class WorkspaceEdit {
  const WorkspaceEdit(this.edits, {this.rejectReason});

  final List<WorkspaceEditEntry> edits;

  /// Set when a rename provider refuses.
  final String? rejectReason;
}

/// `RenameLocation & Rejection`.
class RenameLocation {
  const RenameLocation(this.range, this.text, {this.rejectReason});

  final IRange range;
  final String text;
  final String? rejectReason;
}

// --- code lens, inlay hints

/// `CodeLens`.
class CodeLens {
  const CodeLens(this.range, {this.id, this.command, this.data});

  final IRange range;
  final String? id;

  /// Null until resolved.
  final Command? command;

  /// Provider data a resolve needs (the extension host's cache id).
  final Object? data;
}

/// `CodeLensList`.
class CodeLensList with DisposableResult {
  CodeLensList(this.lenses, {this.onDispose});

  final List<CodeLens> lenses;
  @override
  final void Function()? onDispose;
}

/// `InlayHintKind`.
enum InlayHintKind {
  type(1),
  parameter(2);

  const InlayHintKind(this.value);
  final int value;
}

/// `InlayHintLabelPart`.
class InlayHintLabelPart {
  const InlayHintLabelPart(
    this.label, {
    this.tooltip,
    this.command,
    this.location,
  });

  final String label;
  final MarkdownString? tooltip;
  final Command? command;
  final Location? location;
}

/// `InlayHint`: [label] is one part for a string label.
class InlayHint {
  const InlayHint({
    required this.label,
    required this.position,
    this.tooltip,
    this.textEdits,
    this.kind,
    this.paddingLeft = false,
    this.paddingRight = false,
    this.data,
  });

  final List<InlayHintLabelPart> label;
  final MarkdownString? tooltip;
  final List<TextEdit>? textEdits;
  final IPosition position;
  final InlayHintKind? kind;
  final bool paddingLeft;
  final bool paddingRight;

  /// Provider data a resolve needs.
  final Object? data;

  String get text => label.map((p) => p.label).join();
}

/// `InlayHintList`.
class InlayHintList with DisposableResult {
  InlayHintList(this.hints, {this.onDispose});

  final List<InlayHint> hints;
  @override
  final void Function()? onDispose;
}

// --- semantic tokens

/// `SemanticTokensLegend`.
class SemanticTokensLegend {
  const SemanticTokensLegend(this.tokenTypes, this.tokenModifiers);

  final List<String> tokenTypes;
  final List<String> tokenModifiers;
}

/// `SemanticTokens | SemanticTokensEdits`.
sealed class SemanticTokensResult {
  const SemanticTokensResult({this.resultId});

  final String? resultId;
}

/// `SemanticTokens`: five integers per token, relative to the previous
/// (delta line, delta start, length, type index, modifier bits).
final class SemanticTokens extends SemanticTokensResult {
  const SemanticTokens(this.data, {super.resultId});

  final Uint32List data;
}

/// `SemanticTokensEdit`.
class SemanticTokensEdit {
  const SemanticTokensEdit(this.start, this.deleteCount, [this.data]);

  final int start;
  final int deleteCount;
  final Uint32List? data;
}

/// `SemanticTokensEdits`: edits to the previous result's data.
final class SemanticTokensEdits extends SemanticTokensResult {
  const SemanticTokensEdits(this.edits, {super.resultId});

  final List<SemanticTokensEdit> edits;
}

// --- call and type hierarchy

/// `CallHierarchyItem` / `TypeHierarchyItem`.
class HierarchyItem {
  const HierarchyItem({
    required this.sessionId,
    required this.itemId,
    required this.kind,
    required this.name,
    required this.uri,
    required this.range,
    required this.selectionRange,
    this.detail,
    this.tags = const [],
  });

  final String sessionId;
  final String itemId;
  final SymbolKind kind;
  final String name;
  final String? detail;
  final VsUri uri;
  final IRange range;
  final IRange selectionRange;
  final List<SymbolTag> tags;
}

typedef CallHierarchyItem = HierarchyItem;
typedef TypeHierarchyItem = HierarchyItem;

/// `CallHierarchySession` / `TypeHierarchySession`.
class HierarchySession with DisposableResult {
  HierarchySession(this.roots, {this.onDispose});

  final List<HierarchyItem> roots;
  @override
  final void Function()? onDispose;
}

/// `IncomingCall`.
class IncomingCall {
  const IncomingCall(this.from, this.fromRanges);

  final CallHierarchyItem from;
  final List<IRange> fromRanges;
}

/// `OutgoingCall`.
class OutgoingCall {
  const OutgoingCall(this.to, this.fromRanges);

  final CallHierarchyItem to;
  final List<IRange> fromRanges;
}
