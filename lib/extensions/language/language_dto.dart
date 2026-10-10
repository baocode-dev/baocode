/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The wire shapes of `MainThreadLanguageFeatures`: what the extension host
// sends and expects for every provider kind.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/common/extHostTypeConverters.ts (every `from`/`to` of
// the language features: Position, Range, location, DefinitionLink, Hover,
// MarkdownString, Diagnostic, DocumentSymbol, SymbolKind, WorkspaceSymbol,
// DocumentHighlight, CompletionItem (`to`) and CompletionsAdapter's
// `_convertCompletionItem` (the compact `ISuggestDataDto`), SignatureHelp,
// ParameterInformation, InlayHint, Color, ColorPresentation, FoldingRange,
// SelectionRange, WorkspaceEdit, TextEdit, CallHierarchyItem,
// TypeHierarchyItem, DocumentLink, CodeAction, CodeLens, InlineCompletion),
// src/vs/workbench/api/common/extHost.protocol.ts (`ISuggestDataDto` and its
// field letters, `ISuggestResultDto`, `ISignatureHelpDto`,
// `ILinkedEditingRangesDto`, `IRawColorInfo`, `ICodeActionListDto`,
// `IWorkspaceSymbolsDto`, `IInlayHintsDto`, `ILinksListDto`,
// `ICodeLensListDto`, the `CachedSession`/`ChainedCacheId` wrappers),
// src/vs/editor/common/services/semanticTokensDto.ts
// (`encodeSemanticTokensDto`, `decodeSemanticTokensDto`).
//
// Deviations:
// - Both directions live here (`decodeX` reads what the extension host sends,
//   `encodeX` writes what it expects back); the upstream names are given per
//   function.
// - A Markdown string is always written as an `IMarkdownString` object, never
//   as a bare string: the ported models cannot tell a plain string from one
//   (`language_types.dart`).
// - `eol` in a `TextEdit` is an internal-only field upstream; it is dropped.
// - A cache id is `(session, item)`: `decodeCacheId` reads upstream's
//   `ChainedCacheId` (`[number, number]`) or a bare number.

import 'dart:typed_data';

import 'package:bao_exthost/bao_exthost.dart' show RpcBuffer, VsUri;

import 'language_types.dart';
import 'marker_service.dart';

// --- primitives

int asInt(Object? value, [int fallback = 0]) =>
    value is num ? value.toInt() : fallback;

bool asBool(Object? value) => value == true;

Map<String, Object?> asMap(Object? value) =>
    value is Map ? value.map((k, v) => MapEntry('$k', v)) : const {};

List<Map<String, Object?>> asMapList(Object? value) => [
  if (value is List) for (final item in value) asMap(item),
];

List<Object?> asList(Object? value) => value is List ? value : const [];

/// `IPosition` as the protocol carries it (one-based).
Position decodePosition(Object? value) {
  final map = asMap(value);
  return Position(
    asInt(map['lineNumber'], 1),
    asInt(map['column'], 1),
  );
}

Map<String, Object?> encodePosition(IPosition position) => {
  'lineNumber': position.lineNumber,
  'column': position.column,
};

/// `IRange` (not `ISelection`: no `selectionStartLineNumber`).
Range decodeRange(Object? value) {
  final map = asMap(value);
  return Range(
    asInt(map['startLineNumber'], 1),
    asInt(map['startColumn'], 1),
    asInt(map['endLineNumber'], 1),
    asInt(map['endColumn'], 1),
  );
}

Map<String, Object?> encodeRange(IRange range) => {
  'startLineNumber': range.startLineNumber,
  'startColumn': range.startColumn,
  'endLineNumber': range.endLineNumber,
  'endColumn': range.endColumn,
};

bool isSelection(Map<String, Object?> value) =>
    value.containsKey('selectionStartLineNumber') &&
    value.containsKey('positionLineNumber');

/// The range of a `IRange | ISelection` (`Selection`'s fields win).
Range decodeRangeOrSelection(Object? value) {
  final map = asMap(value);
  if (isSelection(map)) {
    return Range(
      asInt(map['selectionStartLineNumber'], 1),
      asInt(map['selectionStartColumn'], 1),
      asInt(map['positionLineNumber'], 1),
      asInt(map['positionColumn'], 1),
    );
  }
  return decodeRange(value);
}

/// The protocol range of a `Range | Selection` (a selection's start/end, as
/// extHostTypeConverters.Selection.from does).
Map<String, Object?> encodeRangeOrSelection(IRange range, {bool selection = false}) =>
    selection
    ? {
        'selectionStartLineNumber': range.startLineNumber,
        'selectionStartColumn': range.startColumn,
        'positionLineNumber': range.endLineNumber,
        'positionColumn': range.endColumn,
        'startLineNumber': range.startLineNumber,
        'startColumn': range.startColumn,
        'endLineNumber': range.endLineNumber,
        'endColumn': range.endColumn,
      }
    : encodeRange(range);

/// A cache id as the protocol carries it.
typedef CacheId = (int session, int item);

/// `ChainedCacheId` (`[session, item]`) or a bare id.
CacheId? decodeCacheId(Object? value) => switch (value) {
  final List list when list.length >= 2 => (
    asInt(list[0]),
    asInt(list[1]),
  ),
  final num n => (n.toInt(), 0),
  _ => null,
};

List<Object?> encodeCacheId(CacheId id) => [id.$1, id.$2];

VsUri? decodeUri(Object? value) => switch (value) {
  final VsUri uri => uri,
  final Map<Object?, Object?> map => VsUri.tryRevive(map),
  _ => null,
};

// --- markdown, commands

/// `MarkdownString.from` / `fromStrict`: a string, a `{language, value}`
/// code block, or an `IMarkdownString`.
MarkdownString? decodeMarkdown(Object? value) {
  switch (value) {
    case null:
      return null;
    case final String text:
      return MarkdownString(text);
    case final Map<Object?, Object?> map:
      if (map['language'] is String && map['value'] is String) {
        // `{language, value}`: upstream renders it as a fenced block.
        return MarkdownString(
          '```${map['language']}\n${map['value']}\n```\n',
        );
      }
      final text = map['value'];
      if (text is! String) return null;
      return MarkdownString(
        text,
        isTrusted: map['isTrusted'] == true,
        supportThemeIcons: map['supportThemeIcons'] == true,
        supportHtml: map['supportHtml'] == true,
        baseUri: decodeUri(map['baseUri']),
      );
    default:
      return null;
  }
}

/// `MarkdownString.to`: what the extension host reads back.
Map<String, Object?> encodeMarkdown(MarkdownString value) => {
  'value': value.value,
  'isTrusted': value.isTrusted,
  'supportThemeIcons': value.supportThemeIcons,
  'supportHtml': value.supportHtml,
  if (value.baseUri case final base?) 'baseUri': base.toJson(),
};

Map<String, Object?>? encodeMarkdownOrNull(MarkdownString? value) =>
    value == null ? null : encodeMarkdown(value);

/// `ICommandDto`: [Command] plus the `$ident` upstream adds for a command
/// whose arguments stay behind in the extension host.
class CommandDto {
  const CommandDto(this.command, {this.ident});

  final Command command;
  final String? ident;
}

CommandDto? decodeCommandDto(Object? value) {
  if (value is! Map) return null;
  final map = asMap(value);
  final id = map['id'];
  if (id is! String) return null;
  final ident = map[r'$ident'];
  return CommandDto(
    Command(
      id: id,
      title: '${map['title'] ?? ''}',
      tooltip: map['tooltip'] as String?,
      arguments: [
        // Upstream: a command with an `$ident` carries it as the only
        // argument (`_inflateSuggestDto`).
        if (ident is String) ident else ...asList(map['arguments']),
      ],
    ),
    ident: ident is String ? ident : null,
  );
}

/// `ICommandDto` of [command]: [ident] keeps its arguments in the extension
/// host and becomes the first (and only) argument.
Map<String, Object?> encodeCommandDto(Command command, {String? ident}) => {
  // Upstream's key, written out because an interpolated key cannot use the
  // null-aware element syntax.
  r'$ident': ?ident,
  'id': command.id,
  'title': command.title,
  'tooltip': ?command.tooltip,
  if (ident != null)
    'arguments': [ident]
  else
    'arguments': ?command.arguments,
};

/// The command of a resolved `$resolveCodeLens` and friends: a `Command`
/// with a title; null when the id is empty.
Command? decodeCommandOrNull(Object? value) => decodeCommandDto(value)?.command;

// --- hover

/// HoverAdapter.provideHover: `Hover` plus the id the extension host keeps
/// for `HoverVerbosityRequest`s.
class HoverResult {
  const HoverResult(this.hover, this.id);

  final Hover hover;
  final int id;
}

HoverResult? decodeHover(Object? value) {
  final map = asMap(value);
  final contents = [
    for (final item in asList(map['contents'])) ?decodeMarkdown(item),
  ];
  if (contents.isEmpty) return null;
  return HoverResult(
    Hover(
      contents,
      range: map['range'] == null ? null : decodeRange(map['range']),
      canIncreaseVerbosity: map['canIncreaseVerbosity'] == true,
      canDecreaseVerbosity: map['canDecreaseVerbosity'] == true,
    ),
    asInt(map['id']),
  );
}

/// `Hover.To` (`_executeHoverProvider`): what the extension host revives.
Map<String, Object?> encodeHover(Hover hover) => {
  'contents': [for (final content in hover.contents) encodeMarkdown(content)],
  if (hover.range case final range?) 'range': encodeRange(range),
  'canIncreaseVerbosity': hover.canIncreaseVerbosity,
  'canDecreaseVerbosity': hover.canDecreaseVerbosity,
};

/// `HoverContext` for `$provideHover`: only a verbosity request, by id.
Map<String, Object?> encodeHoverContext(HoverContext? context) {
  final delta = context?.verbosityDelta;
  final previous = context?.previousHover;
  if (delta == null || previous == null) return const {'verbosityRequest': null};
  return {
    'verbosityRequest': {
      'verbosityDelta': delta,
      'previousHover': {'id': hoverIdOf(previous) ?? 0},
    },
  };
}

/// The extension host's id of a hover it sent (kept by [hoverIds]).
final Expando<int> hoverIds = Expando<int>('hoverId');
int? hoverIdOf(Hover hover) => hoverIds[hover];

// --- locations

Location? decodeLocation(Object? value) {
  final map = asMap(value);
  final uri = decodeUri(map['uri']);
  if (uri == null) return null;
  return Location(uri, decodeRange(map['range']));
}

Map<String, Object?> encodeLocation(Location location) => {
  'uri': location.uri.toJson(),
  'range': encodeRange(location.range),
};

LocationLink? decodeLocationLink(Object? value) {
  final map = asMap(value);
  final uri = decodeUri(map['uri']);
  if (uri == null) return null;
  return LocationLink(
    uri: uri,
    range: decodeRange(map['range']),
    targetSelectionRange: map['targetSelectionRange'] == null
        ? null
        : decodeRange(map['targetSelectionRange']),
    originSelectionRange: map['originSelectionRange'] == null
        ? null
        : decodeRange(map['originSelectionRange']),
  );
}

Map<String, Object?> encodeLocationLink(LocationLink link) => {
  'uri': link.uri.toJson(),
  'range': encodeRange(link.range),
  if (link.targetSelectionRange case final target?)
    'targetSelectionRange': encodeRange(target),
  if (link.originSelectionRange case final origin?)
    'originSelectionRange': encodeRange(origin),
};

// --- symbols

SymbolKind decodeSymbolKind(Object? value) {
  final index = asInt(value, SymbolKind.property.index);
  return index >= 0 && index < SymbolKind.values.length
      ? SymbolKind.values[index]
      : SymbolKind.property;
}

int encodeSymbolKind(SymbolKind kind) => kind.index;

List<SymbolTag> decodeSymbolTags(Object? value) => [
  for (final tag in asList(value))
    if (asInt(tag) == SymbolTag.deprecated.value) SymbolTag.deprecated,
];

DocumentSymbol decodeDocumentSymbol(Object? value) {
  final map = asMap(value);
  return DocumentSymbol(
    name: '${map['name'] ?? ''}',
    detail: '${map['detail'] ?? ''}',
    kind: decodeSymbolKind(map['kind']),
    tags: decodeSymbolTags(map['tags']),
    containerName: map['containerName'] as String?,
    range: decodeRange(map['range']),
    selectionRange: decodeRange(map['selectionRange']),
    children: map['children'] == null
        ? null
        : [for (final child in asList(map['children'])) decodeDocumentSymbol(child)],
  );
}

Map<String, Object?> encodeDocumentSymbol(DocumentSymbol symbol) => {
  'name': symbol.name,
  'detail': symbol.detail,
  'kind': encodeSymbolKind(symbol.kind),
  'tags': [for (final tag in symbol.tags) tag.value],
  if (symbol.containerName != null) 'containerName': symbol.containerName,
  'range': encodeRange(symbol.range),
  'selectionRange': encodeRange(symbol.selectionRange),
  'children': [
    for (final child in symbol.children ?? const <DocumentSymbol>[])
      encodeDocumentSymbol(child),
  ],
};

/// `IWorkspaceSymbolDto`: a `SymbolInformation` and its cache id.
WorkspaceSymbol decodeWorkspaceSymbol(Object? value) {
  final map = asMap(value);
  return WorkspaceSymbol(
    name: '${map['name'] ?? ''}',
    containerName: map['containerName'] as String?,
    kind: decodeSymbolKind(map['kind']),
    tags: decodeSymbolTags(map['tags']),
    location:
        decodeLocation(map['location']) ?? Location(VsUri.file(''), Range(1, 1, 1, 1)),
    data: decodeCacheId(map['cacheId']),
  );
}

Map<String, Object?> encodeWorkspaceSymbol(WorkspaceSymbol symbol) => {
  'name': symbol.name,
  if (symbol.containerName != null) 'containerName': symbol.containerName,
  'kind': encodeSymbolKind(symbol.kind),
  'tags': [for (final tag in symbol.tags) tag.value],
  'location': encodeLocation(symbol.location),
  if (symbol.data case final CacheId id) 'cacheId': encodeCacheId(id),
};

// --- diagnostics

MarkerData decodeMarkerData(Object? value) {
  final map = asMap(value);
  final code = map['code'];
  return MarkerData(
    severity: MarkerSeverity.fromValue(asInt(map['severity'])),
    message: '${map['message'] ?? ''}',
    startLineNumber: asInt(map['startLineNumber'], 1),
    startColumn: asInt(map['startColumn'], 1),
    endLineNumber: asInt(map['endLineNumber'], 1),
    endColumn: asInt(map['endColumn'], 1),
    source: map['source'] as String?,
    code: switch (code) {
      final String text => MarkerCode(text),
      final Map<Object?, Object?> codeMap => MarkerCode(
        '${codeMap['value'] ?? ''}',
        target: decodeUri(codeMap['target']),
      ),
      _ => null,
    },
    relatedInformation: map['relatedInformation'] == null
        ? null
        : [
            for (final info in asList(map['relatedInformation']))
              () {
                final m = asMap(info);
                return RelatedInformation(
                  resource: decodeUri(m['resource']) ?? VsUri.file(''),
                  message: '${m['message'] ?? ''}',
                  startLineNumber: asInt(m['startLineNumber'], 1),
                  startColumn: asInt(m['startColumn'], 1),
                  endLineNumber: asInt(m['endLineNumber'], 1),
                  endColumn: asInt(m['endColumn'], 1),
                );
              }(),
          ],
    tags: map['tags'] == null
        ? null
        : [
            for (final tag in asList(map['tags']))
              for (final known in MarkerTag.values)
                if (asInt(tag) == known.value) known,
          ],
    origin: map['origin'] as String?,
  );
}

/// `IMarkerData` as `$acceptMarkersChange` carries it (`Range` fields first,
/// then the rest, as upstream's `Diagnostic.from` spreads them).
Map<String, Object?> encodeMarkerData(MarkerData marker) {
  final code = marker.code;
  return {
    'startLineNumber': marker.startLineNumber,
    'startColumn': marker.startColumn,
    'endLineNumber': marker.endLineNumber,
    'endColumn': marker.endColumn,
    'message': marker.message,
    if (marker.source != null) 'source': marker.source,
    if (code != null)
      'code': code.target == null
          ? code.value
          : {'value': code.value, 'target': code.target!.toJson()},
    'severity': marker.severity.value,
    if (marker.relatedInformation case final related?)
      'relatedInformation': [
        for (final info in related)
          {
            'startLineNumber': info.startLineNumber,
            'startColumn': info.startColumn,
            'endLineNumber': info.endLineNumber,
            'endColumn': info.endColumn,
            'message': info.message,
            'resource': info.resource.toJson(),
          },
      ],
    if (marker.tags case final tags?)
      'tags': [for (final tag in tags) tag.value],
  };
}

// --- highlights, linked editing

DocumentHighlight decodeDocumentHighlight(Object? value) {
  final map = asMap(value);
  final kind = map['kind'];
  return DocumentHighlight(
    decodeRange(map['range']),
    kind: kind is num && kind.toInt() >= 0 && kind.toInt() < 3
        ? DocumentHighlightKind.values[kind.toInt()]
        : null,
  );
}

Map<String, Object?> encodeDocumentHighlight(DocumentHighlight highlight) => {
  'range': encodeRange(highlight.range),
  if (highlight.kind case final kind?) 'kind': kind.index,
};

LinkedEditingRanges? decodeLinkedEditingRanges(Object? value) {
  if (value == null) return null;
  final map = asMap(value);
  final pattern = map['wordPattern'];
  return LinkedEditingRanges(
    [for (final range in asList(map['ranges'])) decodeRange(range)],
    wordPattern: pattern is Map
        ? RegExp(
            '${pattern['pattern'] ?? ''}',
            multiLine: '${pattern['flags'] ?? ''}'.contains('m'),
            caseSensitive: !'${pattern['flags'] ?? ''}'.contains('i'),
            unicode: '${pattern['flags'] ?? ''}'.contains('u'),
          )
        : null,
  );
}

Map<String, Object?> encodeLinkedEditingRanges(LinkedEditingRanges ranges) => {
  'ranges': [for (final range in ranges.ranges) encodeRange(range)],
  if (ranges.wordPattern case final pattern?)
    'wordPattern': {
      'pattern': pattern.pattern,
      'flags': [
        if (pattern.isMultiLine) 'm',
        if (!pattern.isCaseSensitive) 'i',
        if (pattern.isUnicode) 'u',
      ].join(),
    },
};

// --- completion

/// `ISuggestDataDtoField`: the compact completion item's letters.
abstract final class SuggestField {
  static const label = 'a';
  static const kind = 'b';
  static const detail = 'c';
  static const documentation = 'd';
  static const sortText = 'e';
  static const filterText = 'f';
  static const preselect = 'g';
  static const insertText = 'h';
  static const insertTextRules = 'i';
  static const range = 'j';
  static const commitCharacters = 'k';
  static const additionalTextEdits = 'l';
  static const kindModifier = 'm';
  static const commandIdent = 'n';
  static const commandId = 'o';
  static const commandArguments = 'p';
}

/// `ISuggestResultDtoField`.
abstract final class SuggestResultField {
  static const defaultRanges = 'a';
  static const completions = 'b';
  static const isIncomplete = 'c';
  static const duration = 'd';
}

/// `MainThreadLanguageFeatures._inflateSuggestDto`: the compact item
/// ([defaultRanges] when the item has none of its own).
class CompletionListResult {
  CompletionListResult(this.list, this.cacheId);

  final CompletionList list;
  final int cacheId;
}

CompletionListResult? decodeSuggestResult(Object? value) {
  if (value == null) return null;
  final map = asMap(value);
  final ranges = asMap(map[SuggestResultField.defaultRanges]);
  final defaultRanges = CompletionItemRanges(
    insert: decodeRange(ranges['insert']),
    replace: decodeRange(ranges['replace']),
  );
  final cacheId = asInt(map['x']);
  return CompletionListResult(
    CompletionList(
      [
        for (final item
            in asList(map[SuggestResultField.completions]))
          ?decodeSuggestData(asMap(item), defaultRanges),
      ],
      incomplete: map[SuggestResultField.isIncomplete] == true,
    ),
    cacheId,
  );
}

CompletionItem? decodeSuggestData(
  Map<String, Object?> map,
  CompletionItemRanges defaultRanges,
) {
  final label = map[SuggestField.label];
  final commandDto = decodeCommandDto({
    if (map[SuggestField.commandIdent] != null)
      'id': map[SuggestField.commandIdent],
    if (map[SuggestField.commandId] != null)
      'id': map[SuggestField.commandId],
    'title': '',
    if (map[SuggestField.commandIdent] != null)
      r'$ident': map[SuggestField.commandIdent],
    if (map[SuggestField.commandArguments] != null)
      'arguments': map[SuggestField.commandArguments],
  });
  final range = map[SuggestField.range];
  final insertText = map[SuggestField.insertText];
  return CompletionItem(
    label: switch (label) {
      final Map<Object?, Object?> map => CompletionItemLabel(
        '${map['label'] ?? ''}',
        detail: map['detail'] as String?,
        description: map['description'] as String?,
      ),
      final String text => CompletionItemLabel(text),
      _ => const CompletionItemLabel(''),
    },
    kind: decodeCompletionItemKind(map[SuggestField.kind]),
    tags: [
      for (final tag in asList(map[SuggestField.kindModifier]))
        if (asInt(tag) == 1) CompletionItemTag.deprecated,
    ],
    detail: map[SuggestField.detail] as String?,
    documentation: decodeMarkdown(map[SuggestField.documentation]),
    sortText: map[SuggestField.sortText] as String?,
    filterText: map[SuggestField.filterText] as String?,
    preselect: map[SuggestField.preselect] == true,
    insertText: switch (insertText) {
      final String text => text,
      _ => switch (label) {
        final String text => text,
        final Map<Object?, Object?> map => '${map['label'] ?? ''}',
        _ => '',
      },
    },
    insertTextRules: asInt(map[SuggestField.insertTextRules]),
    range: switch (range) {
      final Map<Object?, Object?> rangeMap when rangeMap.containsKey('insert') =>
        CompletionItemRanges(
          insert: decodeRange(rangeMap['insert']),
          replace: decodeRange(rangeMap['replace']),
        ),
      final Map<Object?, Object?> rangeMap => CompletionItemRanges.single(
        decodeRange(rangeMap),
      ),
      _ => defaultRanges,
    },
    commitCharacters: switch (map[SuggestField.commitCharacters]) {
      final String characters => characters.split(''),
      _ => null,
    },
    additionalTextEdits: map[SuggestField.additionalTextEdits] == null
        ? null
        : [
            for (final edit in asList(map[SuggestField.additionalTextEdits]))
              decodeSingleEditOperation(edit),
          ],
    command: commandDto?.command,
    // Not standard: the item's `ChainedCacheId`, which a resolve sends.
    data: decodeCacheId(map['x']),
  );
}

CompletionItemKind decodeCompletionItemKind(Object? value) {
  final index = asInt(value, CompletionItemKind.property.index);
  return index >= 0 && index < CompletionItemKind.values.length
      ? CompletionItemKind.values[index]
      : CompletionItemKind.property;
}

/// `languages.CompletionItem` as `_executeCompletionItemProvider` returns it
/// (a full item, not the compact encoding).
Map<String, Object?> encodeCompletionItemFull(CompletionItem item) => {
  'label': item.label.label,
  'kind': item.kind.index,
  if (item.tags.isNotEmpty) 'tags': [for (final tag in item.tags) tag.value],
  if (item.detail != null) 'detail': item.detail,
  if (item.documentation case final documentation?)
    'documentation': encodeMarkdown(documentation),
  if (item.sortText != null) 'sortText': item.sortText,
  'filterText': ?item.filterText,
  'preselect': item.preselect,
  'insertText': item.insertText,
  'insertTextRules': item.insertTextRules,
  if (item.range case final ranges?) 'range': encodeCompletionItemRanges(ranges),
  'commitCharacters': ?item.commitCharacters,
  if (item.additionalTextEdits case final edits?)
    // A list, so no null-aware element here.
    'additionalTextEdits': [
      for (final edit in edits) encodeSingleEditOperation(edit),
    ],
  if (item.command case final command?) 'command': encodeCommandDto(command),
};

Map<String, Object?> encodeCompletionItemRanges(CompletionItemRanges ranges) =>
    Range.equalsRanges(ranges.insert, ranges.replace)
    ? encodeRange(ranges.insert)
    : {
        'insert': encodeRange(ranges.insert),
        'replace': encodeRange(ranges.replace),
      };

// --- text edits, workspace edits

/// `ISingleEditOperation` / `TextEdit`: a null text deletes (the compact
/// `ISuggestDataDto`'s additional edits carry `text: null`).
SingleEditOperation decodeSingleEditOperation(Object? value) {
  final map = asMap(value);
  return SingleEditOperation(
    decodeRange(map['range']),
    map['text'] as String?,
    forceMoveMarkers: map['forceMoveMarkers'] as bool?,
  );
}

Map<String, Object?> encodeSingleEditOperation(SingleEditOperation edit) => {
  'range': encodeRange(edit.range),
  'text': edit.text,
};

TextEdit decodeTextEdit(Object? value) {
  final map = asMap(value);
  return TextEdit(decodeRange(map['range']), '${map['text'] ?? ''}');
}

Map<String, Object?> encodeTextEdit(TextEdit edit) => {
  'range': encodeRange(edit.range),
  'text': edit.text,
};

FormattingOptions decodeFormattingOptions(
  Object? value, {
  int tabSize = 4,
  bool insertSpaces = true,
}) {
  final map = asMap(value);
  return FormattingOptions(
    tabSize: asInt(map['tabSize'], tabSize),
    insertSpaces: map['insertSpaces'] is bool
        ? map['insertSpaces'] as bool
        : insertSpaces,
  );
}

/// `IWorkspaceEditDto`.
WorkspaceEdit? decodeWorkspaceEdit(Object? value) {
  if (value == null) return null;
  final map = asMap(value);
  final edits = <WorkspaceEditEntry>[];
  for (final raw in asList(map['edits'])) {
    final entry = asMap(raw);
    if (entry.containsKey('textEdit')) {
      final resource = decodeUri(entry['resource']);
      final textEdit = asMap(entry['textEdit']);
      if (resource == null) continue;
      edits.add(
        WorkspaceTextEdit(
          resource: resource,
          textEdit: TextEdit(
            decodeRange(textEdit['range']),
            '${textEdit['text'] ?? ''}',
          ),
          versionId: entry['versionId'] is num
              ? asInt(entry['versionId'])
              : null,
          insertAsSnippet: textEdit['insertAsSnippet'] == true,
          keepWhitespace: textEdit['keepWhitespace'] == true,
          metadata: decodeEditMetadata(entry['metadata']),
        ),
      );
    } else if (entry.containsKey('oldResource') ||
        entry.containsKey('newResource')) {
      final options = asMap(entry['options']);
      edits.add(
        WorkspaceFileEdit(
          oldResource: decodeUri(entry['oldResource']),
          newResource: decodeUri(entry['newResource']),
          options: options.isEmpty
              ? null
              : WorkspaceFileEditOptions(
                  overwrite: options['overwrite'] as bool?,
                  ignoreIfNotExists: options['ignoreIfNotExists'] as bool?,
                  ignoreIfExists: options['ignoreIfExists'] as bool?,
                  recursive: options['recursive'] as bool?,
                  copy: options['copy'] as bool?,
                  folder: options['folder'] as bool?,
                  skipTrashBin: options['skipTrashBin'] as bool?,
                ),
          metadata: decodeEditMetadata(entry['metadata']),
        ),
      );
    }
  }
  return WorkspaceEdit(edits, rejectReason: map['rejectReason'] as String?);
}

WorkspaceEditMetadata? decodeEditMetadata(Object? value) {
  if (value is! Map) return null;
  final map = asMap(value);
  return WorkspaceEditMetadata(
    needsConfirmation: map['needsConfirmation'] == true,
    label: '${map['label'] ?? ''}',
    description: map['description'] as String?,
  );
}

/// `WorkspaceEdit.from`: what the extension host revives.
Map<String, Object?> encodeWorkspaceEdit(WorkspaceEdit edit) => {
  'edits': [
    for (final entry in edit.edits)
      switch (entry) {
        WorkspaceTextEdit(
          :final resource,
          :final textEdit,
          :final versionId,
          :final insertAsSnippet,
          :final keepWhitespace,
          :final metadata,
        ) =>
          {
            'resource': resource.toJson(),
            'textEdit': {
              'range': encodeRange(textEdit.range),
              'text': textEdit.text,
              if (insertAsSnippet) 'insertAsSnippet': true,
              if (keepWhitespace) 'keepWhitespace': true,
            },
            'versionId': ?versionId,
            if (metadata != null) 'metadata': encodeEditMetadata(metadata),
          },
        WorkspaceFileEdit(
          :final oldResource,
          :final newResource,
          :final options,
          :final metadata,
        ) =>
          {
            if (oldResource != null) 'oldResource': oldResource.toJson(),
            if (newResource != null) 'newResource': newResource.toJson(),
            if (options != null)
              'options': {
                if (options.overwrite != null) 'overwrite': options.overwrite,
                if (options.ignoreIfNotExists != null)
                  'ignoreIfNotExists': options.ignoreIfNotExists,
                if (options.ignoreIfExists != null)
                  'ignoreIfExists': options.ignoreIfExists,
                if (options.recursive != null) 'recursive': options.recursive,
                if (options.copy != null) 'copy': options.copy,
                if (options.folder != null) 'folder': options.folder,
                if (options.skipTrashBin != null)
                  'skipTrashBin': options.skipTrashBin,
              },
            if (metadata != null) 'metadata': encodeEditMetadata(metadata),
          },
      },
  ],
  if (edit.rejectReason != null) 'rejectReason': edit.rejectReason,
};

Map<String, Object?> encodeEditMetadata(WorkspaceEditMetadata metadata) => {
  'needsConfirmation': metadata.needsConfirmation,
  'label': metadata.label,
  if (metadata.description != null) 'description': metadata.description,
};

/// `languages.RenameLocation & Rejection`.
RenameLocation? decodeRenameLocation(Object? value) {
  if (value == null) return null;
  final map = asMap(value);
  return RenameLocation(
    decodeRange(map['range']),
    '${map['text'] ?? ''}',
    rejectReason: map['rejectReason'] as String?,
  );
}

Map<String, Object?> encodeRenameLocation(RenameLocation location) => {
  'range': encodeRange(location.range),
  'text': location.text,
  if (location.rejectReason != null) 'rejectReason': location.rejectReason,
};

// --- code actions

/// `ICodeActionDto` and the list's cache id.
class CodeActionListResult {
  CodeActionListResult(this.list, this.cacheId);

  final CodeActionList list;
  final int cacheId;
}

CodeActionListResult? decodeCodeActionList(Object? value) {
  if (value == null) return null;
  final map = asMap(value);
  final cacheId = asInt(map['cacheId']);
  return CodeActionListResult(
    CodeActionList([
      for (final action in asList(map['actions']))
        decodeCodeAction(asMap(action)),
    ]),
    cacheId,
  );
}

CodeAction decodeCodeAction(Map<String, Object?> map) => CodeAction(
  title: '${map['title'] ?? ''}',
  command: decodeCommandOrNull(map['command']),
  edit: decodeWorkspaceEdit(map['edit']),
  diagnostics: map['diagnostics'] == null
      ? null
      : [
          for (final marker in asList(map['diagnostics']))
            decodeMarkerData(marker),
        ],
  kind: map['kind'] as String?,
  isPreferred: map['isPreferred'] == true,
  isAI: map['isAI'] == true,
  disabled: map['disabled'] as String?,
  ranges: map['ranges'] == null
      ? null
      : [for (final range in asList(map['ranges'])) decodeRange(range)],
  data: decodeCacheId(map['cacheId']),
);

Map<String, Object?> encodeCodeAction(CodeAction action, {CacheId? cacheId}) => {
  if (cacheId != null) 'cacheId': encodeCacheId(cacheId),
  'title': action.title,
  if (action.edit case final edit?) 'edit': encodeWorkspaceEdit(edit),
  if (action.diagnostics case final diagnostics?)
    'diagnostics': [
      for (final marker in diagnostics) encodeMarkerData(marker),
    ],
  if (action.command case final command?)
    'command': encodeCommandDto(command),
  if (action.kind != null) 'kind': action.kind,
  'isPreferred': action.isPreferred,
  if (action.isAI) 'isAI': true,
  if (action.disabled != null) 'disabled': action.disabled,
  if (action.ranges case final ranges?)
    'ranges': [for (final range in ranges) encodeRange(range)],
};

/// `ICodeActionListDto`.
Map<String, Object?> encodeCodeActionList(CodeActionList list, int cacheId) => {
  'cacheId': cacheId,
  'actions': [
    for (final (index, action) in list.actions.indexed)
      encodeCodeAction(action, cacheId: (cacheId, index)),
  ],
};

// --- signature help

/// `ISignatureHelpDto` and its cache id.
class SignatureHelpResultDto {
  SignatureHelpResultDto(this.help, this.id);

  final SignatureHelp help;
  final int id;
}

SignatureHelpResultDto? decodeSignatureHelp(Object? value) {
  if (value == null) return null;
  final map = asMap(value);
  return SignatureHelpResultDto(
    SignatureHelp(
      signatures: [
        for (final signature in asList(map['signatures']))
          () {
            final m = asMap(signature);
            return SignatureInformation(
              label: '${m['label'] ?? ''}',
              documentation: decodeMarkdown(m['documentation']),
              parameters: [
                for (final parameter in asList(m['parameters']))
                  () {
                    final p = asMap(parameter);
                    final label = p['label'];
                    return ParameterInformation(
                      label: label is String ? label : null,
                      labelOffsets: label is List && label.length >= 2
                          ? (asInt(label[0]), asInt(label[1]))
                          : null,
                      documentation: decodeMarkdown(p['documentation']),
                    );
                  }(),
              ],
              activeParameter: p2(m['activeParameter']),
            );
          }(),
      ],
      activeSignature: asInt(map['activeSignature']),
      activeParameter: asInt(map['activeParameter']),
    ),
    asInt(map['id']),
  );
}

int? p2(Object? value) => value is num ? value.toInt() : null;

/// `ISignatureHelpDto` (`_executeSignatureHelpProvider` returns one without
/// an id, as the extension host only reads its fields).
Map<String, Object?> encodeSignatureHelp(SignatureHelp help, {int? id}) => {
  'id': ?id,
  'signatures': [
    for (final signature in help.signatures)
      {
        'label': signature.label,
        if (signature.documentation case final documentation?)
          'documentation': encodeMarkdown(documentation),
        'parameters': [
          for (final parameter in signature.parameters)
            {
              'label': parameter.labelOffsets == null
                  ? parameter.label
                  : [parameter.labelOffsets!.$1, parameter.labelOffsets!.$2],
              if (parameter.documentation case final documentation?)
                'documentation': encodeMarkdown(documentation),
            },
        ],
        if (signature.activeParameter != null)
          'activeParameter': signature.activeParameter,
      },
  ],
  'activeSignature': help.activeSignature,
  'activeParameter': help.activeParameter,
};

/// `SignatureHelpContext` for `$provideSignatureHelp`.
Map<String, Object?> encodeSignatureHelpContext(SignatureHelpContext context) => {
  'triggerKind': context.triggerKind.value,
  'triggerCharacter': context.triggerCharacter,
  'isRetrigger': context.isRetrigger,
  if (context.activeSignatureHelp case final help?)
    'activeSignatureHelp': encodeSignatureHelp(help),
};

// --- code lens

class CodeLensListResult {
  CodeLensListResult(this.list, this.cacheId);

  final CodeLensList list;
  final int cacheId;
}

CodeLensListResult? decodeCodeLensList(Object? value) {
  if (value == null) return null;
  final map = asMap(value);
  final cacheId = asInt(map['cacheId']);
  return CodeLensListResult(
    CodeLensList([
      for (final lens in asList(map['lenses'])) ?decodeCodeLens(asMap(lens)),
    ]),
    cacheId,
  );
}

CodeLens? decodeCodeLens(Map<String, Object?> map) {
  if (map['range'] == null) return null;
  return CodeLens(
    decodeRange(map['range']),
    id: map['id'] as String?,
    command: decodeCommandOrNull(map['command']),
    data: decodeCacheId(map['cacheId']),
  );
}

Map<String, Object?> encodeCodeLens(CodeLens lens, {CacheId? cacheId}) => {
  if (cacheId != null) 'cacheId': encodeCacheId(cacheId),
  'range': encodeRange(lens.range),
  if (lens.id != null) 'id': lens.id,
  if (lens.command case final command?) 'command': encodeCommandDto(command),
};

Map<String, Object?> encodeCodeLensList(CodeLensList list, int cacheId) => {
  'cacheId': cacheId,
  'lenses': [
    for (final (index, lens) in list.lenses.indexed)
      encodeCodeLens(lens, cacheId: (cacheId, index)),
  ],
};

// --- inlay hints

class InlayHintListResult {
  InlayHintListResult(this.list, this.cacheId);

  final InlayHintList list;
  final int cacheId;
}

InlayHintListResult? decodeInlayHintList(Object? value) {
  if (value == null) return null;
  final map = asMap(value);
  final cacheId = asInt(map['cacheId']);
  return InlayHintListResult(
    InlayHintList([
      for (final hint in asList(map['hints'])) ?decodeInlayHint(asMap(hint)),
    ]),
    cacheId,
  );
}

InlayHint? decodeInlayHint(Map<String, Object?> map) {
  if (map['position'] == null) return null;
  final kind = map['kind'];
  return InlayHint(
    label: [
      for (final part in switch (map['label']) {
        final String text => [{'label': text}],
        final Object? value => asList(value).map(asMap).toList(),
      })
        InlayHintLabelPart(
          '${part['label'] ?? ''}',
          tooltip: decodeMarkdown(part['tooltip']),
          command: decodeCommandOrNull(part['command']),
          location: decodeLocation(part['location']),
        ),
    ],
    position: decodePosition(map['position']),
    tooltip: decodeMarkdown(map['tooltip']),
    textEdits: map['textEdits'] == null
        ? null
        : [for (final edit in asList(map['textEdits'])) decodeTextEdit(edit)],
    kind: kind is num && kind.toInt() >= 1 && kind.toInt() <= 2
        ? InlayHintKind.values[kind.toInt() - 1]
        : null,
    paddingLeft: map['paddingLeft'] == true,
    paddingRight: map['paddingRight'] == true,
    data: decodeCacheId(map['cacheId']),
  );
}

Map<String, Object?> encodeInlayHint(InlayHint hint, {CacheId? cacheId}) => {
  if (cacheId != null) 'cacheId': encodeCacheId(cacheId),
  'label': [
    for (final part in hint.label)
      {
        'label': part.label,
        if (part.tooltip case final tooltip?) 'tooltip': encodeMarkdown(tooltip),
        if (part.command case final command?)
          'command': encodeCommandDto(command),
        if (part.location case final location?)
          'location': encodeLocation(location),
      },
  ],
  'position': encodePosition(hint.position),
  if (hint.tooltip case final tooltip?) 'tooltip': encodeMarkdown(tooltip),
  if (hint.textEdits case final edits?)
    'textEdits': [for (final edit in edits) encodeTextEdit(edit)],
  if (hint.kind case final kind?) 'kind': kind.value,
  'paddingLeft': hint.paddingLeft,
  'paddingRight': hint.paddingRight,
};

/// `IInlayHintsDto`.
Map<String, Object?> encodeInlayHintList(InlayHintList list, int cacheId) => {
  'cacheId': cacheId,
  'hints': [
    for (final (index, hint) in list.hints.indexed)
      encodeInlayHint(hint, cacheId: (cacheId, index)),
  ],
};

// --- links, colors

class LinksListResult {
  LinksListResult(this.list, this.cacheId);

  final LinksList list;
  final int cacheId;
}

LinksListResult? decodeLinksList(Object? value) {
  if (value == null) return null;
  final map = asMap(value);
  return LinksListResult(
    LinksList([
      for (final link in asList(map['links'])) decodeLink(asMap(link)),
    ]),
    asInt(map['cacheId']),
  );
}

Link decodeLink(Map<String, Object?> map) => Link(
  decodeRange(map['range']),
  url: _linkUrl(map),
  tooltip: map['tooltip'] as String?,
);

/// `ILinkDto.target` (a URI or a string) or the `url` of a plain
/// `languages.ILink`.
Object? _linkUrl(Map<String, Object?> map) {
  if (map['target'] == null) {
    return map['url'] is String ? map['url'] : null;
  }
  return decodeUri(map['target']) ?? map['target'];
}

Map<String, Object?> encodeLink(Link link, {CacheId? cacheId}) => {
  if (cacheId != null) 'cacheId': encodeCacheId(cacheId),
  'range': encodeRange(link.range),
  if (link.url case final VsUri uri) 'target': uri.toJson(),
  if (link.url case final String url) 'target': url,
  'tooltip': ?link.tooltip,
};

Map<String, Object?> encodeLinksList(LinksList list, int cacheId) => {
  'cacheId': cacheId,
  'links': [
    for (final (index, link) in list.links.indexed)
      encodeLink(link, cacheId: (cacheId, index)),
  ],
};

/// `IRawColorInfo`: `color` is `[red, green, blue, alpha]` in 0..1 and
/// [range] a plain `IRange`.
ColorInformation decodeRawColorInfo(Object? value) {
  final map = asMap(value);
  return ColorInformation(
    decodeRange(map['range']),
    decodeColor(map['color']),
  );
}

Color decodeColor(Object? value) {
  final parts = asList(value);
  double at(int index) => parts.length > index && parts[index] is num
      ? (parts[index] as num).toDouble()
      : 0;
  return Color(at(0), at(1), at(2), at(3));
}

List<Object?> encodeColor(Color color) => [
  color.red,
  color.green,
  color.blue,
  color.alpha,
];

Map<String, Object?> encodeColorInformation(ColorInformation info) => {
  'color': encodeColor(info.color),
  'range': encodeRange(info.range),
};

ColorPresentation decodeColorPresentation(Object? value) {
  final map = asMap(value);
  return ColorPresentation(
    '${map['label'] ?? ''}',
    textEdit: map['textEdit'] == null ? null : decodeTextEdit(map['textEdit']),
    additionalTextEdits: map['additionalTextEdits'] == null
        ? null
        : [
            for (final edit in asList(map['additionalTextEdits']))
              decodeTextEdit(edit),
          ],
  );
}

Map<String, Object?> encodeColorPresentation(ColorPresentation presentation) => {
  'label': presentation.label,
  if (presentation.textEdit case final edit?) 'textEdit': encodeTextEdit(edit),
  if (presentation.additionalTextEdits case final edits?)
    'additionalTextEdits': [for (final edit in edits) encodeTextEdit(edit)],
};

// --- folding, selection ranges

FoldingRange decodeFoldingRange(Object? value) {
  final map = asMap(value);
  final kind = map['kind'] as String?;
  return FoldingRange(
    asInt(map['start'], 1),
    asInt(map['end'], 1),
    kind: kind == null ? null : FoldingRangeKind.fromValue(kind),
  );
}

Map<String, Object?> encodeFoldingRange(FoldingRange range) => {
  'start': range.start,
  'end': range.end,
  if (range.kind case final kind?) 'kind': kind.value,
};

/// `SelectionRange[][]`: one list per position, innermost first.
List<List<SelectionRange>> decodeSelectionRanges(Object? value) => [
  for (final list in asList(value))
    [
      for (final range in asList(list))
        SelectionRange(decodeRange(asMap(range)['range'])),
    ],
];

List<List<Map<String, Object?>>> encodeSelectionRanges(
  List<List<SelectionRange>> ranges,
) => [
  for (final list in ranges)
    [
      for (final range in list) {'range': encodeRange(range.range)},
    ],
];

// --- semantic tokens

/// `decodeSemanticTokensDto`: the `id` and either the full data or the edits.
sealed class SemanticTokensDto {
  const SemanticTokensDto(this.id);

  final int id;
}

final class FullSemanticTokensDto extends SemanticTokensDto {
  const FullSemanticTokensDto(super.id, this.data);

  final Uint32List data;
}

final class DeltaSemanticTokensDto extends SemanticTokensDto {
  const DeltaSemanticTokensDto(super.id, this.deltas);

  final List<SemanticTokensEdit> deltas;
}

const _semanticTokensFull = 1;
const _semanticTokensDelta = 2;

/// `decodeSemanticTokensDto` over an [RpcBuffer] or its bytes.
SemanticTokensDto? decodeSemanticTokensDto(Object? value) {
  final bytes = switch (value) {
    final RpcBuffer buffer => buffer.bytes,
    final Uint8List bytes => bytes,
    final List<int> bytes => Uint8List.fromList(bytes),
    _ => null,
  };
  if (bytes == null || bytes.length < 8) return null;
  final data = _u32FromLittleEndian(bytes);
  var offset = 0;
  final id = data[offset++];
  final type = data[offset++];
  if (type == _semanticTokensFull) {
    final length = data[offset++];
    return FullSemanticTokensDto(
      id,
      Uint32List.sublistView(data, offset, offset + length),
    );
  }
  if (type != _semanticTokensDelta) return null;
  final count = data[offset++];
  final deltas = <SemanticTokensEdit>[];
  for (var i = 0; i < count; i++) {
    final start = data[offset++];
    final deleteCount = data[offset++];
    final length = data[offset++];
    deltas.add(
      SemanticTokensEdit(
        start,
        deleteCount,
        length > 0
            ? Uint32List.sublistView(data, offset, offset + length)
            : null,
      ),
    );
    offset += length;
  }
  return DeltaSemanticTokensDto(id, deltas);
}

/// `encodeSemanticTokensDto` as a little-endian [RpcBuffer] (`data: 'full'`
/// only, as the main thread only ever sends full results to the extension
/// host).
RpcBuffer encodeSemanticTokensDto(int id, Uint32List data) {
  final out = Uint32List(3 + data.length);
  out[0] = id;
  out[1] = _semanticTokensFull;
  out[2] = data.length;
  out.setRange(3, out.length, data);
  return RpcBuffer(_u32ToLittleEndian(out));
}

Uint32List _u32FromLittleEndian(Uint8List bytes) {
  final aligned = bytes.offsetInBytes % 4 == 0
      ? bytes
      : Uint8List.fromList(bytes);
  final view = ByteData.sublistView(aligned);
  final count = aligned.length ~/ 4;
  final out = Uint32List(count);
  for (var i = 0; i < count; i++) {
    out[i] = view.getUint32(i * 4, Endian.little);
  }
  return out;
}

Uint8List _u32ToLittleEndian(Uint32List data) {
  final view = ByteData(data.length * 4);
  for (var i = 0; i < data.length; i++) {
    view.setUint32(i * 4, data[i], Endian.little);
  }
  return view.buffer.asUint8List();
}

/// `SemanticTokensLegend` of `$registerDocumentSemanticTokensProvider`.
SemanticTokensLegend decodeSemanticTokensLegend(Object? value) {
  final map = asMap(value);
  return SemanticTokensLegend(
    [for (final type in asList(map['tokenTypes'])) '$type'],
    [for (final modifier in asList(map['tokenModifiers'])) '$modifier'],
  );
}

/// `DocumentSemanticTokensAdapter.applySemanticTokensEdits` (the extension
/// host applies our deltas itself, so this is only for tests and for
/// providers that return edits).
Uint32List applySemanticTokensEdits(
  Uint32List data,
  List<SemanticTokensEdit> edits,
) {
  var result = data;
  for (final edit in edits) {
    final start = edit.start.clamp(0, result.length);
    final deleteCount = edit.deleteCount.clamp(0, result.length - start);
    final replacement = edit.data ?? Uint32List(0);
    final next = Uint32List(result.length - deleteCount + replacement.length);
    next.setRange(0, start, result);
    next.setRange(start, start + replacement.length, replacement);
    next.setRange(start + replacement.length, next.length, result, start + deleteCount);
    result = next;
  }
  return result;
}

// --- inline completions

/// `IdentifiableInlineCompletions`: the items plus the pid the extension
/// host's cache is keyed by.
class InlineCompletionsResultDto {
  const InlineCompletionsResultDto(
    this.completions,
    this.pid,
    this.items,
  );

  final InlineCompletions completions;
  final int pid;

  /// The items, with their index in the provider's list.
  final List<(int, InlineCompletion)> items;
}

InlineCompletionsResultDto? decodeInlineCompletions(Object? value) {
  if (value == null) return null;
  final map = asMap(value);
  final pid = asInt(map['pid']);
  final items = <(int, InlineCompletion)>[];
  for (final raw in asList(map['items'])) {
    final item = asMap(raw);
    final insertText = item['insertText'];
    items.add((
      asInt(item['idx']),
      InlineCompletion(
        insertText: insertText is String ? insertText : null,
        snippet: insertText is Map ? '${insertText['snippet'] ?? ''}' : null,
        range: item['range'] == null ? null : decodeRange(item['range']),
        additionalTextEdits: item['additionalTextEdits'] == null
            ? null
            : [
                for (final edit in asList(item['additionalTextEdits']))
                  decodeSingleEditOperation(edit),
              ],
        command: decodeCommandOrNull(item['command']),
        completeBracketPairs: item['completeBracketPairs'] == true,
        isInlineEdit: item['isInlineEdit'] == true,
        showRange: item['showRange'] == null
            ? null
            : decodeRange(item['showRange']),
        correlationId: item['correlationId'] as String?,
      ),
    ));
  }
  return InlineCompletionsResultDto(
    InlineCompletions(
      [for (final (_, item) in items) item],
      commands: [
        for (final command in asList(map['commands'])) ?decodeCommandOrNull(command),
      ],
      suppressSuggestions: map['suppressSuggestions'] as bool?,
      enableForwardStability: map['enableForwardStability'] as bool?,
    ),
    pid,
    items,
  );
}

/// `IdentifiableInlineCompletions` for `$provideInlineCompletions`.
Map<String, Object?> encodeInlineCompletions(
  InlineCompletions completions, {
  required String languageId,
  required int pid,
  required List<int> indexes,
}) => {
  'pid': pid,
  'languageId': languageId,
  'items': [
    for (final (index, item) in completions.items.indexed)
      {
        'insertText': ?item.insertText,
        if (item.snippet case final snippet)
          'insertText': {'snippet': snippet},
        if (item.range case final range?) 'range': encodeRange(range),
        if (item.showRange case final shownRange?) 'showRange': encodeRange(shownRange),
        if (item.command case final command?)
          'command': encodeCommandDto(command),
        'pid': pid,
        'idx': index < indexes.length ? indexes[index] : index,
        'completeBracketPairs': item.completeBracketPairs,
        'isInlineEdit': item.isInlineEdit,
        'correlationId': ?item.correlationId,
      },
  ],
  'commands': [
    for (final command in completions.commands) encodeCommandDto(command),
  ],
  'suppressSuggestions': ?completions.suppressSuggestions,
  'enableForwardStability': ?completions.enableForwardStability,
};

/// `InlineCompletionContext` for `$provideInlineCompletions`.
Map<String, Object?> encodeInlineCompletionContext(InlineCompletionContext context) => {
  'triggerKind': context.triggerKind == InlineCompletionTriggerKind.explicit
      ? 1
      : 0,
  'requestUuid': context.requestUuid,
  'includeInlineEdits': context.includeInlineEdits,
  'includeInlineCompletions': context.includeInlineCompletions,
  'requestIssuedDateTime': context.requestIssuedDateTime,
  'earliestShownDateTime': context.earliestShownDateTime,
  if (context.selectedSuggestionInfo case final info?)
    'selectedSuggestionInfo': {
      'range': encodeRange(info.range),
      'text': info.text,
    },
};

/// `InlineCompletionsDisposeReason` for `$freeInlineCompletionsList`.
Map<String, Object?> encodeInlineCompletionsDisposeReason(
  InlineCompletionsDisposeReason reason,
) => {
  'kind': switch (reason) {
    InlineCompletionsDisposeReason.lostRace => 'lostRace',
    InlineCompletionsDisposeReason.tokenCancellation => 'tokenCancellation',
    InlineCompletionsDisposeReason.other => 'other',
    InlineCompletionsDisposeReason.empty => 'empty',
    InlineCompletionsDisposeReason.notTaken => 'notTaken',
  },
};

// --- call and type hierarchy

HierarchyItem decodeHierarchyItem(Object? value) {
  final map = asMap(value);
  return HierarchyItem(
    sessionId: '${map[r'_sessionId'] ?? ''}',
    itemId: '${map[r'_itemId'] ?? ''}',
    kind: decodeSymbolKind(map['kind']),
    name: '${map['name'] ?? ''}',
    detail: map['detail'] as String?,
    uri: decodeUri(map['uri']) ?? VsUri.file(''),
    range: decodeRange(map['range']),
    selectionRange: decodeRange(map['selectionRange']),
    tags: decodeSymbolTags(map['tags']),
  );
}

Map<String, Object?> encodeHierarchyItem(HierarchyItem item) => {
  r'_sessionId': item.sessionId,
  r'_itemId': item.itemId,
  'name': item.name,
  if (item.detail != null) 'detail': item.detail,
  'kind': encodeSymbolKind(item.kind),
  'uri': item.uri.toJson(),
  'range': encodeRange(item.range),
  'selectionRange': encodeRange(item.selectionRange),
  if (item.tags.isNotEmpty) 'tags': [for (final tag in item.tags) tag.value],
};

Map<String, Object?> encodeIncomingCall(
  HierarchyItem from,
  List<IRange> fromRanges,
) => {
  'from': encodeHierarchyItem(from),
  'fromRanges': [for (final range in fromRanges) encodeRange(range)],
};

Map<String, Object?> encodeOutgoingCall(
  HierarchyItem to,
  List<IRange> fromRanges,
) => {
  'to': encodeHierarchyItem(to),
  'fromRanges': [for (final range in fromRanges) encodeRange(range)],
};

// --- misc

/// `languages.Command` of a documentation entry
Map<String, Object?> encodeCodeActionDocumentation(
  List<({String kind, Command command})> documentation,
) => {
  'documentation': [
    for (final entry in documentation)
      {'kind': entry.kind, 'command': encodeCommandDto(entry.command)},
  ],
};
