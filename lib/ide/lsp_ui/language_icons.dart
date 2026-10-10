import 'package:flutter/material.dart';

import '../../theme/codicons.dart';
import '../../theme/workbench_theme.dart';
import '../lsp/lsp_protocol.dart';

// Completion and symbol kinds as VS Code draws them: `CompletionItemKinds`
// and `SymbolKinds.toIcon` of src/vs/editor/common/languages.ts, colored by
// the codicon's `symbolIcon.*Foreground` of
// src/vs/editor/contrib/symbolIcons/browser/symbolIcons.ts and
// symbolIcons.css, at 6a598d4a13031703d483d103c1d934a36ad27971.

typedef IdeKindIcon = ({IconData icon, Color color});

/// [icon] in `symbolIcon.<kind>Foreground` of the current color theme.
IdeKindIcon _icon(IconData icon, String kind) =>
    (icon: icon, color: themeColors['symbolIcon.${kind}Foreground']);

IdeKindIcon ideCompletionKindIcon(LspCompletionKind kind) => switch (kind) {
  LspCompletionKind.method => _icon(Codicons.symbolMethod, 'method'),
  LspCompletionKind.function => _icon(Codicons.symbolFunction, 'function'),
  LspCompletionKind.constructor => _icon(
    Codicons.symbolConstructor,
    'constructor',
  ),
  LspCompletionKind.field => _icon(Codicons.symbolField, 'field'),
  LspCompletionKind.variable => _icon(Codicons.symbolVariable, 'variable'),
  LspCompletionKind.klass => _icon(Codicons.symbolClass, 'class'),
  LspCompletionKind.interface => _icon(Codicons.symbolInterface, 'interface'),
  LspCompletionKind.module => _icon(Codicons.symbolModule, 'module'),
  LspCompletionKind.property => _icon(Codicons.symbolProperty, 'property'),
  LspCompletionKind.unit => _icon(Codicons.symbolUnit, 'unit'),
  LspCompletionKind.value => _icon(Codicons.symbolValue, 'enumerator'),
  LspCompletionKind.enumeration => _icon(Codicons.symbolEnum, 'enumerator'),
  LspCompletionKind.enumMember => _icon(
    Codicons.symbolEnumMember,
    'enumeratorMember',
  ),
  LspCompletionKind.keyword => _icon(Codicons.symbolKeyword, 'keyword'),
  LspCompletionKind.snippet => _icon(Codicons.symbolSnippet, 'snippet'),
  LspCompletionKind.color => _icon(Codicons.symbolColor, 'color'),
  LspCompletionKind.file => _icon(Codicons.symbolFile, 'file'),
  LspCompletionKind.reference => _icon(Codicons.symbolReference, 'reference'),
  LspCompletionKind.folder => _icon(Codicons.symbolFolder, 'folder'),
  LspCompletionKind.constant => _icon(Codicons.symbolConstant, 'constant'),
  LspCompletionKind.struct => _icon(Codicons.symbolStruct, 'struct'),
  LspCompletionKind.event => _icon(Codicons.symbolEvent, 'event'),
  LspCompletionKind.operator => _icon(Codicons.symbolOperator, 'operator'),
  LspCompletionKind.typeParameter => _icon(
    Codicons.symbolTypeParameter,
    'typeParameter',
  ),
  LspCompletionKind.text => _icon(Codicons.symbolText, 'text'),
};

IdeKindIcon ideSymbolKindIcon(LspSymbolKind kind) => switch (kind) {
  LspSymbolKind.method => _icon(Codicons.symbolMethod, 'method'),
  LspSymbolKind.function => _icon(Codicons.symbolFunction, 'function'),
  LspSymbolKind.constructor => _icon(Codicons.symbolConstructor, 'constructor'),
  LspSymbolKind.field => _icon(Codicons.symbolField, 'field'),
  LspSymbolKind.variable => _icon(Codicons.symbolVariable, 'variable'),
  LspSymbolKind.klass => _icon(Codicons.symbolClass, 'class'),
  LspSymbolKind.interface => _icon(Codicons.symbolInterface, 'interface'),
  LspSymbolKind.enumeration => _icon(Codicons.symbolEnum, 'enumerator'),
  LspSymbolKind.enumMember => _icon(
    Codicons.symbolEnumMember,
    'enumeratorMember',
  ),
  LspSymbolKind.constant => _icon(Codicons.symbolConstant, 'constant'),
  LspSymbolKind.property => _icon(Codicons.symbolProperty, 'property'),
  LspSymbolKind.event => _icon(Codicons.symbolEvent, 'event'),
  LspSymbolKind.module => _icon(Codicons.symbolModule, 'module'),
  LspSymbolKind.namespace => _icon(Codicons.symbolNamespace, 'namespace'),
  LspSymbolKind.package => _icon(Codicons.symbolPackage, 'package'),
  LspSymbolKind.file => _icon(Codicons.symbolFile, 'file'),
  LspSymbolKind.struct => _icon(Codicons.symbolStruct, 'struct'),
  LspSymbolKind.typeParameter => _icon(
    Codicons.symbolTypeParameter,
    'typeParameter',
  ),
  LspSymbolKind.operator => _icon(Codicons.symbolOperator, 'operator'),
  LspSymbolKind.string => _icon(Codicons.symbolString, 'string'),
  LspSymbolKind.number => _icon(Codicons.symbolNumber, 'number'),
  LspSymbolKind.boolean => _icon(Codicons.symbolBoolean, 'boolean'),
  LspSymbolKind.nullValue => _icon(Codicons.symbolNull, 'null'),
  LspSymbolKind.array => _icon(Codicons.symbolArray, 'array'),
  LspSymbolKind.object => _icon(Codicons.symbolObject, 'object'),
  LspSymbolKind.key => _icon(Codicons.symbolKey, 'key'),
};
