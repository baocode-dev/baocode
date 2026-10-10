/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// An extension's `contributes.snippets`: the snippet files it ships for a
// language, offered by the suggest widget as completion items of kind
// `Snippet` whose insert text is the snippet body, with the editor's
// snippet session taking over (tab stops, placeholders, variables).
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/contrib/snippets/browser/snippetsService.ts
// (`SnippetService.getSnippetsSync`, `SnippetFile` loading),
// src/vs/workbench/contrib/snippets/browser/snippetCompletionProvider.ts
// (`SnippetCompletionProvider.provideCompletionItems`: the `$`-prefixed
// filter text, the Label with the snippet's prefix, `Snippet` kind,
// `InsertAsSnippet` rule, and the sort text).
//
// Deviations:
// - The snippet JSON is read from the extension's files by the caller
//   ([snippetFilesFor]); this provider only turns loaded snippets into
//   completion items.
// - Variables (`$TM_FILENAME`, `$CURRENT_YEAR`, …) are resolved by
//   bao_editor's snippet session, not here.

import 'package:bao_editor/monaco/vs/base/common/ecmascript_lower_case.dart';
import 'package:bao_exthost/bao_exthost.dart' show CancellationToken;

import '../language/language_feature_document.dart';
import '../language/language_providers.dart';
import '../language/language_types.dart';

/// One entry of a snippet file (`contributes.snippets`).
class SnippetDefinition {
  const SnippetDefinition({
    required this.name,
    required this.prefix,
    required this.body,
    required this.source,
    this.description,
  });

  final String name;

  /// The trigger prefixes (a snippet may have several).
  final List<String> prefix;

  /// The snippet body, its lines joined by `\n`.
  final String body;

  /// The extension or user file it came from.
  final String source;
  final String? description;

  /// The completion's label: the prefix when there is one, else the name.
  String get label => prefix.isEmpty ? name : prefix.first;
}

/// Reads the snippets of a `contributes.snippets` file's JSON.
List<SnippetDefinition> snippetsFromJson(
  Object? json, {
  required String source,
}) {
  final list = switch (json) {
    {'snippets': final Map<Object?, Object?> snippets} => snippets.entries,
    final Map<Object?, Object?> snippets => snippets.entries,
    _ => null,
  };
  if (list == null) return const [];
  final result = <SnippetDefinition>[];
  for (final MapEntry(:key, :value) in list) {
    if (value is! Map) continue;
    final body = value['body'];
    final prefix = switch (value['prefix']) {
      final String prefix when prefix.isNotEmpty => [prefix],
      final List<Object?> prefixes => prefixes.whereType<String>().toList(),
      _ => const <String>[],
    };
    final text = switch (body) {
      final String body => body,
      final List<Object?> lines => lines.whereType<String>().join('\n'),
      _ => null,
    };
    if (text == null) continue;
    result.add(
      SnippetDefinition(
        name: '${value['name'] ?? key}',
        prefix: prefix,
        body: text,
        source: source,
        description: value['description'] as String?,
      ),
    );
  }
  return result;
}

/// The snippets of one language, as the suggest widget's items.
class SnippetCompletionProvider extends CompletionItemProvider {
  SnippetCompletionProvider({
    required this.languageId,
    required this.snippets,
    this.source,
    this.extensionId,
  });

  final String languageId;
  final List<SnippetDefinition> snippets;

  /// The extension the snippets came from; null for the user's own
  /// (`snippets/<language>.json`).
  final String? source;

  @override
  final String? extensionId;

  @override
  String? get displayName => 'snippets:$languageId';

  @override
  Future<CompletionList?> provideCompletionItems(
    LanguageFeatureDocument model,
    Position position,
    CompletionContext context,
    CancellationToken token,
  ) async {
    if (snippets.isEmpty) return null;
    final line = jsToLowerCase(model.getLineContent(position.lineNumber));
    final before = line.substring(
      0,
      (position.column - 1).clamp(0, line.length),
    );
    final triggerCharacter = context.triggerCharacter == null
        ? null
        : jsToLowerCase(context.triggerCharacter!);
    final items = <CompletionItem>[];
    for (final snippet in snippets) {
      final prefix = snippet.prefix.isEmpty
          ? snippet.name
          : snippet.prefix.first;
      final prefixLow = jsToLowerCase(prefix);
      if (context.triggerKind == CompletionTriggerKind.triggerCharacter &&
          triggerCharacter != null &&
          !prefixLow.startsWith(triggerCharacter)) {
        // Trigger characters must prefix-match, as upstream's strict case.
        continue;
      }
      if (before.isNotEmpty && !prefixLow.startsWith(before.trimLeft())) {
        continue;
      }
      items.add(
        CompletionItem(
          label: CompletionItemLabel(
            prefix,
            description: snippet.name == prefix ? null : snippet.name,
          ),
          detail: snippet.description == null
              ? '${snippet.name} (${snippet.source})'
              : '${snippet.description} (${snippet.source})',
          kind: CompletionItemKind.snippet,
          insertText: snippet.body,
          filterText: '\$$prefix',
          // `SnippetCompletion`'s sort text: user snippets sort before
          // extensions' (`a-` vs `z-`).
          sortText: '${source == null ? 'a' : 'z'}-$prefix',
          insertTextRules: CompletionItemInsertTextRule.insertAsSnippet,
        ),
      );
    }
    if (items.isEmpty) return null;
    return CompletionList(items);
  }
}
