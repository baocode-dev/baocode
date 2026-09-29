import 'package:flutter/material.dart';

import '../../theme/codicons.dart';
import '../lsp/lsp_protocol.dart';

// Completion and symbol kinds as VS Code draws them: `CompletionItemKinds`
// and `SymbolKinds.toIcon` of src/vs/editor/common/languages.ts, colored by
// src/vs/editor/contrib/symbolIcons/browser/symbolIcons.ts (dark), at
// 6a598d4a13031703d483d103c1d934a36ad27971.

/// The dark `symbolIcon.*Foreground` colors; every kind not listed is the
/// plain `foreground`.
abstract final class IdeSymbolColors {
  /// Methods, functions, constructors.
  static const method = Color(0xFFB180D7);

  /// Variables, fields, interfaces, enum members.
  static const variable = Color(0xFF75BEFF);

  /// Classes, enums, events.
  static const klass = Color(0xFFEE9D28);
  static const plain = Color(0xFFCCCCCC);
}

typedef IdeKindIcon = ({IconData icon, Color color});

IdeKindIcon ideCompletionKindIcon(LspCompletionKind kind) => switch (kind) {
  LspCompletionKind.method => (
    icon: Codicons.symbolMethod,
    color: IdeSymbolColors.method,
  ),
  LspCompletionKind.function => (
    icon: Codicons.symbolFunction,
    color: IdeSymbolColors.method,
  ),
  LspCompletionKind.constructor => (
    icon: Codicons.symbolConstructor,
    color: IdeSymbolColors.method,
  ),
  LspCompletionKind.field => (
    icon: Codicons.symbolField,
    color: IdeSymbolColors.variable,
  ),
  LspCompletionKind.variable => (
    icon: Codicons.symbolVariable,
    color: IdeSymbolColors.variable,
  ),
  LspCompletionKind.klass => (
    icon: Codicons.symbolClass,
    color: IdeSymbolColors.klass,
  ),
  LspCompletionKind.interface => (
    icon: Codicons.symbolInterface,
    color: IdeSymbolColors.variable,
  ),
  LspCompletionKind.module => (
    icon: Codicons.symbolModule,
    color: IdeSymbolColors.plain,
  ),
  LspCompletionKind.property => (
    icon: Codicons.symbolProperty,
    color: IdeSymbolColors.plain,
  ),
  LspCompletionKind.unit => (
    icon: Codicons.symbolUnit,
    color: IdeSymbolColors.plain,
  ),
  LspCompletionKind.value => (
    icon: Codicons.symbolValue,
    color: IdeSymbolColors.plain,
  ),
  LspCompletionKind.enumeration => (
    icon: Codicons.symbolEnum,
    color: IdeSymbolColors.klass,
  ),
  LspCompletionKind.enumMember => (
    icon: Codicons.symbolEnumMember,
    color: IdeSymbolColors.variable,
  ),
  LspCompletionKind.keyword => (
    icon: Codicons.symbolKeyword,
    color: IdeSymbolColors.plain,
  ),
  LspCompletionKind.snippet => (
    icon: Codicons.symbolSnippet,
    color: IdeSymbolColors.plain,
  ),
  LspCompletionKind.color => (
    icon: Codicons.symbolColor,
    color: IdeSymbolColors.plain,
  ),
  LspCompletionKind.file => (
    icon: Codicons.symbolFile,
    color: IdeSymbolColors.plain,
  ),
  LspCompletionKind.reference => (
    icon: Codicons.symbolReference,
    color: IdeSymbolColors.plain,
  ),
  LspCompletionKind.folder => (
    icon: Codicons.symbolFolder,
    color: IdeSymbolColors.plain,
  ),
  LspCompletionKind.constant => (
    icon: Codicons.symbolConstant,
    color: IdeSymbolColors.plain,
  ),
  LspCompletionKind.struct => (
    icon: Codicons.symbolStruct,
    color: IdeSymbolColors.plain,
  ),
  LspCompletionKind.event => (
    icon: Codicons.symbolEvent,
    color: IdeSymbolColors.klass,
  ),
  LspCompletionKind.operator => (
    icon: Codicons.symbolOperator,
    color: IdeSymbolColors.plain,
  ),
  LspCompletionKind.typeParameter => (
    icon: Codicons.symbolTypeParameter,
    color: IdeSymbolColors.plain,
  ),
  LspCompletionKind.text => (
    icon: Codicons.symbolText,
    color: IdeSymbolColors.plain,
  ),
};

IdeKindIcon ideSymbolKindIcon(LspSymbolKind kind) => switch (kind) {
  LspSymbolKind.method => (
    icon: Codicons.symbolMethod,
    color: IdeSymbolColors.method,
  ),
  LspSymbolKind.function => (
    icon: Codicons.symbolFunction,
    color: IdeSymbolColors.method,
  ),
  LspSymbolKind.constructor => (
    icon: Codicons.symbolConstructor,
    color: IdeSymbolColors.method,
  ),
  LspSymbolKind.field => (
    icon: Codicons.symbolField,
    color: IdeSymbolColors.variable,
  ),
  LspSymbolKind.variable => (
    icon: Codicons.symbolVariable,
    color: IdeSymbolColors.variable,
  ),
  LspSymbolKind.klass => (
    icon: Codicons.symbolClass,
    color: IdeSymbolColors.klass,
  ),
  LspSymbolKind.interface => (
    icon: Codicons.symbolInterface,
    color: IdeSymbolColors.variable,
  ),
  LspSymbolKind.enumeration => (
    icon: Codicons.symbolEnum,
    color: IdeSymbolColors.klass,
  ),
  LspSymbolKind.enumMember => (
    icon: Codicons.symbolEnumMember,
    color: IdeSymbolColors.variable,
  ),
  LspSymbolKind.constant => (
    icon: Codicons.symbolConstant,
    color: IdeSymbolColors.plain,
  ),
  LspSymbolKind.property => (
    icon: Codicons.symbolProperty,
    color: IdeSymbolColors.plain,
  ),
  LspSymbolKind.event => (
    icon: Codicons.symbolEvent,
    color: IdeSymbolColors.klass,
  ),
  LspSymbolKind.module => (
    icon: Codicons.symbolModule,
    color: IdeSymbolColors.plain,
  ),
  LspSymbolKind.namespace => (
    icon: Codicons.symbolNamespace,
    color: IdeSymbolColors.plain,
  ),
  LspSymbolKind.package => (
    icon: Codicons.symbolPackage,
    color: IdeSymbolColors.plain,
  ),
  LspSymbolKind.file => (
    icon: Codicons.symbolFile,
    color: IdeSymbolColors.plain,
  ),
  LspSymbolKind.struct => (
    icon: Codicons.symbolStruct,
    color: IdeSymbolColors.plain,
  ),
  LspSymbolKind.typeParameter => (
    icon: Codicons.symbolTypeParameter,
    color: IdeSymbolColors.plain,
  ),
  LspSymbolKind.operator => (
    icon: Codicons.symbolOperator,
    color: IdeSymbolColors.plain,
  ),
  LspSymbolKind.string => (
    icon: Codicons.symbolString,
    color: IdeSymbolColors.plain,
  ),
  LspSymbolKind.number => (
    icon: Codicons.symbolNumber,
    color: IdeSymbolColors.plain,
  ),
  LspSymbolKind.boolean => (
    icon: Codicons.symbolBoolean,
    color: IdeSymbolColors.plain,
  ),
  LspSymbolKind.nullValue => (
    icon: Codicons.symbolNull,
    color: IdeSymbolColors.plain,
  ),
  LspSymbolKind.array => (
    icon: Codicons.symbolArray,
    color: IdeSymbolColors.plain,
  ),
  LspSymbolKind.object => (
    icon: Codicons.symbolObject,
    color: IdeSymbolColors.plain,
  ),
  LspSymbolKind.key => (icon: Codicons.symbolKey, color: IdeSymbolColors.plain),
};
