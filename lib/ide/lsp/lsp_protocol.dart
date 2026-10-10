/// Language Server Protocol 3.17 structures the IDE uses, with JSON
/// conversion. Positions are zero-based lines and UTF-16 code-unit
/// characters, the protocol's default encoding and the editor model's own.
///
/// Each type keeps the server's [json] so what the client does not model
/// (e.g. `data` for a later resolve) round-trips unchanged.
library;

import 'package:bao_remote/lsp.dart' show JsonMap;

export 'package:bao_remote/lsp.dart' show JsonMap;

JsonMap? _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : null;

List<JsonMap> _maps(Object? value) => [
  if (value is List)
    for (final item in value) ?_map(item),
];

int _int(Object? value, [int fallback = 0]) =>
    value is num ? value.toInt() : fallback;

String? _string(Object? value) => value is String ? value : null;

class LspPosition implements Comparable<LspPosition> {
  const LspPosition(this.line, this.character);

  factory LspPosition.fromJson(JsonMap json) =>
      LspPosition(_int(json['line']), _int(json['character']));

  final int line;

  /// UTF-16 code units from the start of [line].
  final int character;

  JsonMap toJson() => {'line': line, 'character': character};

  @override
  int compareTo(LspPosition other) => line != other.line
      ? line.compareTo(other.line)
      : character.compareTo(other.character);

  @override
  bool operator ==(Object other) =>
      other is LspPosition &&
      other.line == line &&
      other.character == character;

  @override
  int get hashCode => Object.hash(line, character);

  @override
  String toString() => '$line:$character';
}

class LspRange {
  const LspRange(this.start, this.end);

  factory LspRange.fromJson(JsonMap json) => LspRange(
    LspPosition.fromJson(_map(json['start']) ?? const {}),
    LspPosition.fromJson(_map(json['end']) ?? const {}),
  );

  final LspPosition start;
  final LspPosition end;

  bool get isEmpty => start == end;

  bool contains(LspPosition position) =>
      start.compareTo(position) <= 0 && position.compareTo(end) <= 0;

  JsonMap toJson() => {'start': start.toJson(), 'end': end.toJson()};

  @override
  bool operator ==(Object other) =>
      other is LspRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => '[$start-$end]';
}

/// A document location: `Location`, or a `LocationLink`'s target.
class LspLocation {
  const LspLocation(this.uri, this.range, {this.selectionRange});

  factory LspLocation.fromJson(JsonMap json) {
    if (json['targetUri'] case final String uri) {
      final range = LspRange.fromJson(_map(json['targetRange']) ?? const {});
      final selection = _map(json['targetSelectionRange']);
      return LspLocation(
        uri,
        range,
        selectionRange: selection == null ? null : LspRange.fromJson(selection),
      );
    }
    return LspLocation(
      _string(json['uri']) ?? '',
      LspRange.fromJson(_map(json['range']) ?? const {}),
    );
  }

  /// `Location | Location[] | LocationLink[] | null`, as definition and
  /// references answer.
  static List<LspLocation> listFromJson(Object? json) => [
    if (_map(json) case final single?) LspLocation.fromJson(single),
    for (final item in _maps(json)) LspLocation.fromJson(item),
  ];

  final String uri;
  final LspRange range;

  /// Where to put the caret (a link's name, not its whole declaration).
  final LspRange? selectionRange;

  LspRange get revealRange => selectionRange ?? range;
}

class LspTextEdit {
  const LspTextEdit(this.range, this.newText);

  factory LspTextEdit.fromJson(JsonMap json) {
    // InsertReplaceEdit: the replace range, as VS Code's default.
    final range = _map(json['range']) ?? _map(json['replace']) ?? const {};
    return LspTextEdit(
      LspRange.fromJson(range),
      _string(json['newText']) ?? '',
    );
  }

  static List<LspTextEdit> listFromJson(Object? json) => [
    for (final item in _maps(json)) LspTextEdit.fromJson(item),
  ];

  final LspRange range;
  final String newText;

  JsonMap toJson() => {'range': range.toJson(), 'newText': newText};
}

/// A workspace edit's text changes by document URI; `documentChanges`
/// text edits are folded in. File create/rename/delete operations are kept
/// in [resourceOperations] for the caller to apply or refuse.
class LspWorkspaceEdit {
  const LspWorkspaceEdit(this.changes, {this.resourceOperations = const []});

  factory LspWorkspaceEdit.fromJson(JsonMap json) {
    final changes = <String, List<LspTextEdit>>{};
    final operations = <JsonMap>[];
    if (_map(json['changes']) case final byUri?) {
      for (final MapEntry(:key, :value) in byUri.entries) {
        changes
            .putIfAbsent(key, () => [])
            .addAll(LspTextEdit.listFromJson(value));
      }
    }
    for (final change in _maps(json['documentChanges'])) {
      if (_map(change['textDocument']) case final document?) {
        changes
            .putIfAbsent(_string(document['uri']) ?? '', () => [])
            .addAll(LspTextEdit.listFromJson(change['edits']));
      } else {
        operations.add(change);
      }
    }
    return LspWorkspaceEdit(changes, resourceOperations: operations);
  }

  final Map<String, List<LspTextEdit>> changes;
  final List<JsonMap> resourceOperations;

  bool get isEmpty =>
      resourceOperations.isEmpty && changes.values.every((e) => e.isEmpty);
}

enum LspDiagnosticSeverity { error, warning, information, hint }

class LspDiagnostic {
  const LspDiagnostic({
    required this.range,
    required this.message,
    this.severity = LspDiagnosticSeverity.error,
    this.code,
    this.source,
    this.unnecessary = false,
    this.deprecated = false,
    this.json = const {},
  });

  factory LspDiagnostic.fromJson(JsonMap json) {
    final tags = [
      if (json['tags'] case final List tags)
        for (final tag in tags) _int(tag),
    ];
    return LspDiagnostic(
      range: LspRange.fromJson(_map(json['range']) ?? const {}),
      message: _string(json['message']) ?? '',
      severity: switch (_int(json['severity'], 1)) {
        2 => LspDiagnosticSeverity.warning,
        3 => LspDiagnosticSeverity.information,
        4 => LspDiagnosticSeverity.hint,
        _ => LspDiagnosticSeverity.error,
      },
      code: json['code'] == null ? null : '${json['code']}',
      source: _string(json['source']),
      unnecessary: tags.contains(1),
      deprecated: tags.contains(2),
      json: json,
    );
  }

  final LspRange range;
  final String message;
  final LspDiagnosticSeverity severity;
  final String? code;
  final String? source;
  final bool unnecessary;
  final bool deprecated;

  /// As the server sent it, for code action requests.
  final JsonMap json;
}

/// Markup (`MarkupContent`, `MarkedString` or a list of them) as Markdown.
String lspMarkupToMarkdown(Object? contents) {
  if (contents is String) return contents;
  if (contents is List) {
    return contents
        .map(lspMarkupToMarkdown)
        .where((s) => s.isNotEmpty)
        .join('\n\n---\n\n');
  }
  final map = _map(contents);
  if (map == null) return '';
  final value = _string(map['value']) ?? '';
  // MarkedString with a language is a code block; MarkupContent says kind.
  if (map['language'] case final String language) {
    return '```$language\n$value\n```';
  }
  if (map['kind'] == 'plaintext') {
    return value.replaceAllMapped(
      RegExp(r'[\\`*_{}\[\]()#+\-.!<>|]'),
      (m) => '\\${m[0]}',
    );
  }
  return value;
}

class LspHover {
  const LspHover(this.markdown, {this.range});

  static LspHover? fromJson(Object? json) {
    final map = _map(json);
    if (map == null) return null;
    final markdown = lspMarkupToMarkdown(map['contents']);
    if (markdown.trim().isEmpty) return null;
    final range = _map(map['range']);
    return LspHover(
      markdown,
      range: range == null ? null : LspRange.fromJson(range),
    );
  }

  final String markdown;
  final LspRange? range;
}

class LspCommand {
  const LspCommand(this.title, this.command, [this.arguments]);

  static LspCommand? fromJson(Object? json) {
    final map = _map(json);
    if (map == null || map['command'] is! String) return null;
    return LspCommand(
      _string(map['title']) ?? '',
      map['command']! as String,
      map['arguments'] is List ? map['arguments']! as List : null,
    );
  }

  final String title;
  final String command;
  final List<Object?>? arguments;

  JsonMap toJson() => {
    'title': title,
    'command': command,
    if (arguments != null) 'arguments': arguments,
  };
}

/// `CompletionItemKind` (1-based in the protocol).
enum LspCompletionKind {
  text,
  method,
  function,
  constructor,
  field,
  variable,
  klass,
  interface,
  module,
  property,
  unit,
  value,
  enumeration,
  keyword,
  snippet,
  color,
  file,
  reference,
  folder,
  enumMember,
  constant,
  struct,
  event,
  operator,
  typeParameter;

  static LspCompletionKind of(Object? value) {
    final index = _int(value, 1) - 1;
    return index >= 0 && index < values.length ? values[index] : text;
  }
}

class LspCompletionItem {
  const LspCompletionItem({
    required this.label,
    this.kind = LspCompletionKind.text,
    this.detail,
    this.documentation,
    this.insertText,
    this.isSnippet = false,
    this.textEdit,
    this.insertRange,
    this.additionalTextEdits = const [],
    this.sortText,
    this.filterText,
    this.preselect = false,
    this.deprecated = false,
    this.commitCharacters = const [],
    this.command,
    this.labelDetail,
    this.labelDescription,
    this.serverId,
    this.json = const {},
  });

  factory LspCompletionItem.fromJson(
    JsonMap json, {
    String? serverId,
    LspRange? defaultRange,
    bool defaultSnippet = false,
  }) {
    final edit = _map(json['textEdit']);
    final details = _map(json['labelDetails']);
    final format = json['insertTextFormat'];
    return LspCompletionItem(
      label: _string(json['label']) ?? '',
      kind: LspCompletionKind.of(json['kind']),
      detail: _string(json['detail']),
      documentation: json['documentation'] == null
          ? null
          : lspMarkupToMarkdown(json['documentation']),
      insertText: _string(json['insertText']),
      isSnippet: format == null ? defaultSnippet : format == 2,
      textEdit: edit == null
          ? (defaultRange == null
                ? null
                : LspTextEdit(
                    defaultRange,
                    _string(json['insertText']) ?? _string(json['label']) ?? '',
                  ))
          : LspTextEdit.fromJson(edit),
      insertRange: switch (_map(edit?['insert'])) {
        final insert? => LspRange.fromJson(insert),
        null => null,
      },
      additionalTextEdits: LspTextEdit.listFromJson(
        json['additionalTextEdits'],
      ),
      sortText: _string(json['sortText']),
      filterText: _string(json['filterText']),
      preselect: json['preselect'] == true,
      deprecated:
          json['deprecated'] == true ||
          (json['tags'] is List && (json['tags']! as List).contains(1)),
      commitCharacters: [
        if (json['commitCharacters'] case final List chars)
          for (final c in chars)
            if (c is String) c,
      ],
      command: LspCommand.fromJson(json['command']),
      labelDetail: _string(details?['detail']),
      labelDescription: _string(details?['description']),
      serverId: serverId,
      json: json,
    );
  }

  final String label;
  final LspCompletionKind kind;
  final String? detail;

  /// Markdown.
  final String? documentation;
  final String? insertText;

  /// Whether [insertText] / [textEdit] is a snippet (`$1`, `${2:x}`, `$0`).
  final bool isSnippet;

  /// What to replace (the replace range of an insert/replace edit).
  final LspTextEdit? textEdit;

  /// The insert range of an insert/replace edit, if any.
  final LspRange? insertRange;
  final List<LspTextEdit> additionalTextEdits;
  final String? sortText;
  final String? filterText;
  final bool preselect;
  final bool deprecated;
  final List<String> commitCharacters;
  final LspCommand? command;
  final String? labelDetail;
  final String? labelDescription;

  /// The server that offered it: resolve and commands go back to it.
  final String? serverId;
  final JsonMap json;

  String get text => textEdit?.newText ?? insertText ?? label;
}

class LspCompletionList {
  const LspCompletionList(this.items, {this.isIncomplete = false});

  static const empty = LspCompletionList([]);

  factory LspCompletionList.fromJson(Object? json, {String? serverId}) {
    if (json is List) {
      return LspCompletionList([
        for (final item in _maps(json))
          LspCompletionItem.fromJson(item, serverId: serverId),
      ]);
    }
    final map = _map(json);
    if (map == null) return empty;
    final defaults = _map(map['itemDefaults']);
    final editRange = _map(defaults?['editRange']);
    final range = editRange == null
        ? null
        : LspRange.fromJson(_map(editRange['replace']) ?? editRange);
    return LspCompletionList([
      for (final item in _maps(map['items']))
        LspCompletionItem.fromJson(
          item,
          serverId: serverId,
          defaultRange: range,
          defaultSnippet: defaults?['insertTextFormat'] == 2,
        ),
    ], isIncomplete: map['isIncomplete'] == true);
  }

  final List<LspCompletionItem> items;
  final bool isIncomplete;
}

class LspParameterInformation {
  const LspParameterInformation(
    this.label, {
    this.documentation,
    this.labelRange,
  });

  final String label;

  /// Offsets into the signature label, when the server gives them.
  final (int, int)? labelRange;
  final String? documentation;
}

class LspSignature {
  const LspSignature(
    this.label, {
    this.documentation,
    this.parameters = const [],
    this.activeParameter,
  });

  final String label;
  final String? documentation;
  final List<LspParameterInformation> parameters;
  final int? activeParameter;
}

class LspSignatureHelp {
  const LspSignatureHelp(
    this.signatures, {
    this.activeSignature = 0,
    this.activeParameter = 0,
  });

  static LspSignatureHelp? fromJson(Object? json) {
    final map = _map(json);
    if (map == null) return null;
    final signatures = [
      for (final signature in _maps(map['signatures']))
        LspSignature(
          _string(signature['label']) ?? '',
          documentation: signature['documentation'] == null
              ? null
              : lspMarkupToMarkdown(signature['documentation']),
          activeParameter: signature['activeParameter'] is num
              ? _int(signature['activeParameter'])
              : null,
          parameters: [
            for (final parameter in _maps(signature['parameters']))
              switch (parameter['label']) {
                [final num from, final num to] => LspParameterInformation(
                  (_string(signature['label']) ?? '').substring(
                    from.toInt().clamp(
                      0,
                      (_string(signature['label']) ?? '').length,
                    ),
                    to.toInt().clamp(
                      0,
                      (_string(signature['label']) ?? '').length,
                    ),
                  ),
                  labelRange: (from.toInt(), to.toInt()),
                  documentation: parameter['documentation'] == null
                      ? null
                      : lspMarkupToMarkdown(parameter['documentation']),
                ),
                final label => LspParameterInformation(
                  '${label ?? ''}',
                  documentation: parameter['documentation'] == null
                      ? null
                      : lspMarkupToMarkdown(parameter['documentation']),
                ),
              },
          ],
        ),
    ];
    if (signatures.isEmpty) return null;
    return LspSignatureHelp(
      signatures,
      activeSignature: _int(map['activeSignature']),
      activeParameter: _int(map['activeParameter']),
    );
  }

  final List<LspSignature> signatures;
  final int activeSignature;
  final int activeParameter;
}

/// `SymbolKind` (1-based in the protocol).
enum LspSymbolKind {
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
  typeParameter;

  static LspSymbolKind of(Object? value) {
    final index = _int(value, 1) - 1;
    return index >= 0 && index < values.length ? values[index] : variable;
  }
}

/// A `DocumentSymbol`; flat `SymbolInformation` answers become roots.
class LspDocumentSymbol {
  const LspDocumentSymbol({
    required this.name,
    required this.kind,
    required this.range,
    required this.selectionRange,
    this.detail,
    this.children = const [],
  });

  static List<LspDocumentSymbol> listFromJson(Object? json) => [
    for (final item in _maps(json))
      if (_map(item['location']) case final location?)
        LspDocumentSymbol(
          name: _string(item['name']) ?? '',
          kind: LspSymbolKind.of(item['kind']),
          range: LspRange.fromJson(_map(location['range']) ?? const {}),
          selectionRange: LspRange.fromJson(
            _map(location['range']) ?? const {},
          ),
          detail: _string(item['containerName']),
        )
      else
        LspDocumentSymbol(
          name: _string(item['name']) ?? '',
          kind: LspSymbolKind.of(item['kind']),
          range: LspRange.fromJson(_map(item['range']) ?? const {}),
          selectionRange: LspRange.fromJson(
            _map(item['selectionRange']) ?? _map(item['range']) ?? const {},
          ),
          detail: _string(item['detail']),
          children: listFromJson(item['children']),
        ),
  ];

  final String name;
  final String? detail;
  final LspSymbolKind kind;
  final LspRange range;
  final LspRange selectionRange;
  final List<LspDocumentSymbol> children;
}

class LspCodeAction {
  const LspCodeAction({
    required this.title,
    this.kind,
    this.isPreferred = false,
    this.diagnostics = const [],
    this.edit,
    this.command,
    this.disabledReason,
    this.serverId,
    this.json = const {},
  });

  /// A `Command` or `CodeAction` from a code action answer.
  factory LspCodeAction.fromJson(JsonMap json, {String? serverId}) {
    if (json['command'] is String) {
      return LspCodeAction(
        title: _string(json['title']) ?? '',
        command: LspCommand.fromJson(json),
        serverId: serverId,
        json: json,
      );
    }
    final edit = _map(json['edit']);
    return LspCodeAction(
      title: _string(json['title']) ?? '',
      kind: _string(json['kind']),
      isPreferred: json['isPreferred'] == true,
      diagnostics: [
        for (final d in _maps(json['diagnostics'])) LspDiagnostic.fromJson(d),
      ],
      edit: edit == null ? null : LspWorkspaceEdit.fromJson(edit),
      command: LspCommand.fromJson(json['command']),
      disabledReason: _string(_map(json['disabled'])?['reason']),
      serverId: serverId,
      json: json,
    );
  }

  final String title;
  final String? kind;
  final bool isPreferred;
  final List<LspDiagnostic> diagnostics;
  final LspWorkspaceEdit? edit;
  final LspCommand? command;
  final String? disabledReason;
  final String? serverId;
  final JsonMap json;

  bool get isQuickFix => kind?.startsWith('quickfix') ?? false;
}

/// Semantic tokens decoded against the server's legend: absolute positions.
class LspSemanticToken {
  const LspSemanticToken(
    this.line,
    this.character,
    this.length,
    this.type,
    this.modifiers,
  );

  final int line;
  final int character;
  final int length;
  final String type;
  final Set<String> modifiers;
}

class LspSemanticTokensLegend {
  const LspSemanticTokensLegend(this.tokenTypes, this.tokenModifiers);

  factory LspSemanticTokensLegend.fromJson(JsonMap json) =>
      LspSemanticTokensLegend(
        [for (final t in (json['tokenTypes'] as List? ?? const [])) '$t'],
        [for (final m in (json['tokenModifiers'] as List? ?? const [])) '$m'],
      );

  final List<String> tokenTypes;
  final List<String> tokenModifiers;

  /// Decodes the relative five-integer encoding of `SemanticTokens.data`.
  List<LspSemanticToken> decode(List<int> data) {
    final tokens = <LspSemanticToken>[];
    var line = 0;
    var character = 0;
    for (var i = 0; i + 4 < data.length; i += 5) {
      line += data[i];
      character = data[i] == 0 ? character + data[i + 1] : data[i + 1];
      final typeIndex = data[i + 3];
      final bits = data[i + 4];
      tokens.add(
        LspSemanticToken(
          line,
          character,
          data[i + 2],
          typeIndex < tokenTypes.length ? tokenTypes[typeIndex] : 'unknown',
          {
            for (var m = 0; m < tokenModifiers.length; m++)
              if (bits & (1 << m) != 0) tokenModifiers[m],
          },
        ),
      );
    }
    return tokens;
  }
}

/// A `TextDocumentContentChangeEvent`: [text] replaces [range] in the
/// document as the previous changes of the same notification left it, or
/// the whole document when [range] is null.
class LspTextDocumentContentChange {
  const LspTextDocumentContentChange(this.text, {this.range});

  final LspRange? range;
  final String text;

  JsonMap toJson() => {
    if (range case final range?) 'range': range.toJson(),
    'text': text,
  };
}
