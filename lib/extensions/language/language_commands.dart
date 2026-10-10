/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The `_executeXxxProvider` and `_provideXxx` commands an extension runs
// through `vscode.executeHoverProvider` and its siblings
// (`extHostApiCommands.ts`' `internalId` of every `ApiCommand`): each asks
// this app's language feature providers and answers upstream's serialized
// result shape, which the extension host converts back into API types.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/editor/contrib/hover/browser/getHover.ts (`_executeHoverProvider`),
// gotoSymbol/browser/goToSymbol.ts (the definition family and
// `_sortedAndDeduped`), documentSymbols/browser/documentSymbols.ts,
// format/browser/format.ts, suggest/browser/suggest.ts,
// smartSelect/browser/smartSelect.ts, parameterHints/browser/
// provideSignatureHelp.ts, codelens/browser/codelens.ts,
// codeAction/browser/codeAction.ts, links/browser/getLinks.ts,
// colorPicker/browser/colorPickerContribution.ts,
// inlayHints/browser/inlayHintsController.ts, folding/browser/folding.ts,
// rename/browser/rename.ts, occurrences/browser/getOccurrences.ts,
// src/vs/workbench/contrib/search/browser/search.contribution.ts
// (`_executeWorkspaceSymbolProvider`),
// callHierarchy/common/callHierarchy.ts, typeHierarchy/common/typeHierarchy.ts,
// src/vs/workbench/api/common/extHostApiCommands.ts (which API command maps
// to which `_execute*`, and the `ApiCommandResult` converters each answer is
// read with).
//
// Deviations:
// - Coordinates are model coordinates throughout (the extension sends
//   one-based positions and ranges and reads them back the same way), so the
//   providers are called directly rather than through the editor-coordinate
//   `LanguageFeatures` surface.
// - `vscode.executeDefinitionProvider_recursive` and the other
//   `vscode.experimental.*_recursive` variants differ only in the
//   `recursive` flag the registries' `ordered` takes; both are registered.
// - `editor.folding` / `editor.foldingStrategy` are not consulted.
// - `vscode.provideDocumentSemanticTokens` answers a full result only (a
//   provider that sends edits is asked again for the document).

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart' show CancellationToken;

import '../commands/builtin_commands.dart';
import '../commands/command_arguments.dart';
import 'language_customers.dart';
import 'language_dto.dart' as dto;
import 'language_feature_document.dart';
import 'language_providers.dart';
import 'language_types.dart';
import 'language_feature_registry.dart' show stableSort;
import 'registry_language_features.dart'
    show
        CodeActionFilter,
        HierarchicalKind,
        RegistryLanguageFeatures;

/// The `_execute*` commands of the extension API, over [root]'s providers.
final class LanguageCommands {
  LanguageCommands(this.root);

  final LanguageFeatureRoot root;

  /// Registers every command; returns what removes them.
  void Function() register(BuiltinCommands commands) {
    final stops = <void Function()>[];
    void reg(String id, Future<Object?> Function(List<Object?> args) handler) =>
        stops.add(commands.register(id, handler));
    Object? arg(List<Object?> args, int i) => i < args.length ? args[i] : null;

    LanguageFeatureDocument? document(List<Object?> args) {
      final uri = uriArg(arg(args, 0));
      return uri == null ? null : root.documents?.documentForUri(uri);
    }

    Position? position(List<Object?> args, int i) {
      final value = positionArg(arg(args, i));
      return value == null
          ? null
          : Position(value.lineNumber, value.column);
    }

    Range? range(List<Object?> args, int i) {
      final value = rangeArg(arg(args, i));
      return value == null
          ? null
          : Range(
              value.startLineNumber,
              value.startColumn,
              value.endLineNumber,
              value.endColumn,
            );
    }

    // --- hover

    Future<Object?> hover(List<Object?> args, {bool recursive = false}) async {
      final model = document(args);
      final at = position(args, 1);
      if (model == null || at == null) return null;
      final hovers = await root.language.hoversFor(
        model,
        at,
        cancellationTokenOf(args),
        recursive,
      );
      return [for (final hover in hovers) dto.encodeHover(hover)];
    }

    reg('_executeHoverProvider', (args) => hover(args));
    reg(
      '_executeHoverProvider_recursive',
      (args) => hover(args, recursive: true),
    );

    // --- definitions and friends

    Future<Object?> locations(
      List<Object?> args, {
      required LanguageFeatureKind kind,
      bool recursive = false,
    }) async {
      final model = document(args);
      final at = position(args, 1);
      if (model == null || at == null) return null;
      final links = await _locationLinks(model, at, kind, recursive: recursive);
      return [
        for (final link in links)
          if (link.targetSelectionRange == null && link.originSelectionRange == null)
            dto.encodeLocation(Location(link.uri, link.range))
          else
            {
              'targetUri': link.uri.toJson(),
              'targetRange': dto.encodeRange(link.range),
              if (link.targetSelectionRange case final target?)
                'targetSelectionRange': dto.encodeRange(target),
              if (link.originSelectionRange case final origin?)
                'originSelectionRange': dto.encodeRange(origin),
            },
      ];
    }

    for (final (id, kind) in const [
      ('_executeDefinitionProvider', LanguageFeatureKind.definition),
      ('_executeTypeDefinitionProvider', LanguageFeatureKind.typeDefinition),
      ('_executeDeclarationProvider', LanguageFeatureKind.declaration),
      ('_executeImplementationProvider', LanguageFeatureKind.implementation),
      (
        '_executeDefinitionProvider_recursive',
        LanguageFeatureKind.definition,
      ),
      (
        '_executeTypeDefinitionProvider_recursive',
        LanguageFeatureKind.typeDefinition,
      ),
      (
        '_executeDeclarationProvider_recursive',
        LanguageFeatureKind.declaration,
      ),
      (
        '_executeImplementationProvider_recursive',
        LanguageFeatureKind.implementation,
      ),
    ]) {
      final recursive = id.endsWith('_recursive');
      reg(id, (args) => locations(args, kind: kind, recursive: recursive));
    }

    reg('_executeReferenceProvider', (args) async {
      final model = document(args);
      final at = position(args, 1);
      if (model == null || at == null) return null;
      final context = arg(args, 2);
      final includeDeclaration = context is Map
          ? context['includeDeclaration'] != false
          : true;
      final locations = <Location>[];
      for (final provider
          in root.service.referenceProvider.ordered(model)) {
        final result = await _safe(
          () => provider.provideReferences(
            model,
            at,
            ReferenceContext(includeDeclaration: includeDeclaration),
            cancellationTokenOf(args),
          ),
        );
        locations.addAll(result ?? const []);
      }
      return [for (final location in locations) dto.encodeLocation(location)];
    });

    reg('_executeDocumentHighlights', (args) async {
      final model = document(args);
      final at = position(args, 1);
      if (model == null || at == null) return null;
      final highlights = <DocumentHighlight>[];
      for (final provider
          in root.service.documentHighlightProvider.ordered(model)) {
        final result = await _safe(
          () => provider.provideDocumentHighlights(
            model,
            at,
            cancellationTokenOf(args),
          ),
        );
        highlights.addAll(result ?? const []);
      }
      return [
        for (final highlight in highlights)
          dto.encodeDocumentHighlight(highlight),
      ];
    });

    // --- outline

    reg('_executeDocumentSymbolProvider', (args) async {
      final model = document(args);
      if (model == null) return null;
      final symbols = await root.language.provideDocumentSymbols(
        model,
        cancellationTokenOf(args),
      );
      return [
        for (final symbol in symbols) dto.encodeDocumentSymbol(symbol),
      ];
    });

    // --- formatting

    Future<Object?> formatEdits(
      List<Object?> args, {
      FormattingKind kind = FormattingKind.file,
    }) async {
      final model = document(args);
      if (model == null) return null;
      final options = _formattingOptions(arg(args, kind == FormattingKind.file ? 1 : 2));
      final List<TextEdit>? edits = switch (kind) {
        FormattingKind.file => await root.language.formatEdits(
          model,
          options: options,
          token: cancellationTokenOf(args),
        ),
        FormattingKind.selection => await _rangeFormat(
          model,
          range(args, 1),
          options,
          args,
        ),
      };
      if (edits == null) return null;
      return [for (final edit in edits) dto.encodeTextEdit(edit)];
    }

    reg('_executeFormatDocumentProvider', (args) => formatEdits(args));
    reg(
      '_executeFormatRangeProvider',
      (args) => formatEdits(args, kind: FormattingKind.selection),
    );

    reg('_executeFormatOnTypeProvider', (args) async {
      final model = document(args);
      final at = position(args, 1);
      final ch = arg(args, 2);
      if (model == null || at == null || ch is! String) return null;
      final options = _formattingOptions(arg(args, 3));
      final edits = await root.language.onTypeFormatDocument(
        model,
        at,
        ch,
        options,
        cancellationTokenOf(args),
      );
      if (edits == null) return null;
      return [for (final edit in edits) dto.encodeTextEdit(edit)];
    });

    // --- symbol search

    reg('_executeWorkspaceSymbolProvider', (args) async {
      final query = arg(args, 0);
      if (query is! String) return null;
      final symbols = <WorkspaceSymbol>[];
      for (final provider in root.service.workspaceSymbolProviders) {
        final result = await _safe(
          () => provider.provideWorkspaceSymbols(
            query,
            cancellationTokenOf(args),
          ),
        );
        symbols.addAll(result ?? const []);
      }
      return [
        for (final symbol in symbols)
          {
            'name': symbol.name,
            'kind': dto.encodeSymbolKind(symbol.kind),
            if (symbol.containerName != null)
              'containerName': symbol.containerName,
            'location': dto.encodeLocation(symbol.location),
            if (symbol.tags.isNotEmpty)
              'tags': [for (final tag in symbol.tags) tag.value],
          },
      ];
    });

    // --- rename

    reg('_executePrepareRename', (args) async {
      final model = document(args);
      final at = position(args, 1);
      if (model == null || at == null) return null;
      final providers = root.service.renameProvider.ordered(model);
      for (final provider in providers) {
        if (!provider.canResolveRenameLocation) break;
        final result = await _safe(
          () => provider.resolveRenameLocation(
            model,
            at,
            cancellationTokenOf(args),
          ),
        );
        if (result == null) continue;
        return {
          'range': dto.encodeRange(result.range),
          'placeholder': result.text,
        };
      }
      return null;
    });

    reg('_executeDocumentRenameProvider', (args) async {
      final model = document(args);
      final at = position(args, 1);
      final newName = arg(args, 2);
      if (model == null || at == null || newName is! String) return null;
      for (final provider in root.service.renameProvider.ordered(model)) {
        final result = await _safe(
          () => provider.provideRenameEdits(
            model,
            at,
            newName,
            cancellationTokenOf(args),
          ),
        );
        if (result == null) continue;
        if (result.rejectReason != null) {
          return {'edits': <Object?>[], 'rejectReason': result.rejectReason};
        }
        return dto.encodeWorkspaceEdit(result);
      }
      return null;
    });

    // --- links

    reg('_executeLinkProvider', (args) async {
      final model = document(args);
      if (model == null) return null;
      final links = await _linkList(model, args);
      final resolveCount = arg(args, 1);
      final count = resolveCount is num ? resolveCount.toInt() : 0;
      final result = <Link>[];
      for (final (index, link) in links.indexed) {
        if (index < count) {
          result.add(await _resolveLink(link));
        } else {
          result.add(link);
        }
      }
      return [for (final link in result) dto.encodeLink(link)];
    });

    // --- semantic tokens

    reg('_provideDocumentSemanticTokensLegend', (args) async {
      final model = document(args);
      if (model == null) return null;
      final provider = _documentSemanticTokens(model);
      if (provider == null) return null;
      final legend = provider.getLegend();
      return {
        'tokenTypes': legend.tokenTypes,
        'tokenModifiers': legend.tokenModifiers,
      };
    });

    reg('_provideDocumentSemanticTokens', (args) async {
      final model = document(args);
      if (model == null) return null;
      final provider = _documentSemanticTokens(model);
      if (provider == null) return null;
      final result = await _safe(
        () => provider.provideDocumentSemanticTokens(
          model,
          null,
          cancellationTokenOf(args),
        ),
      );
      final data = switch (result) {
        final SemanticTokens tokens => tokens.data,
        _ => null,
      };
      if (data == null) return null;
      return dto.encodeSemanticTokensDto(0, data);
    });

    reg('_provideDocumentRangeSemanticTokensLegend', (args) async {
      final model = document(args);
      if (model == null) return null;
      final provider = _rangeSemanticTokens(model);
      if (provider == null) return null;
      final legend = provider.getLegend();
      return {
        'tokenTypes': legend.tokenTypes,
        'tokenModifiers': legend.tokenModifiers,
      };
    });

    reg('_provideDocumentRangeSemanticTokens', (args) async {
      final model = document(args);
      final requested = range(args, 1);
      if (model == null || requested == null) return null;
      final provider = _rangeSemanticTokens(model);
      if (provider == null) return null;
      final result = await _safe(
        () => provider.provideDocumentRangeSemanticTokens(
          model,
          requested,
          cancellationTokenOf(args),
        ),
      );
      if (result == null) return null;
      return dto.encodeSemanticTokensDto(0, result.data);
    });

    // --- completion

    reg('_executeCompletionItemProvider', (args) async {
      final model = document(args);
      final at = position(args, 1);
      if (model == null || at == null) return null;
      final triggerCharacter = arg(args, 2);
      final context = triggerCharacter is String
          ? CompletionContext(
              CompletionTriggerKind.triggerCharacter,
              triggerCharacter: triggerCharacter,
            )
          : const CompletionContext(CompletionTriggerKind.invoke);
      final items = await root.language.provideSuggestionItems(
        model,
        at,
        context,
        token: cancellationTokenOf(args),
      );
      final resolveCount = arg(args, 3);
      final count = resolveCount is num ? resolveCount.toInt() : 0;
      final resolved = <CompletionItem>[];
      for (final (index, item) in items.indexed) {
        if (index < count && item.provider.canResolveCompletionItem) {
          resolved.add(
            await _safe(
              () => item.provider.resolveCompletionItem(
                item.completion,
                cancellationTokenOf(args),
              ),
            ) ??
                item.completion,
          );
        } else {
          resolved.add(item.completion);
        }
      }
      return {
        'incomplete': items.any((item) => item.container.incomplete),
        'suggestions': [
          for (final item in resolved) dto.encodeCompletionItemFull(item),
        ],
      };
    });

    // --- signature help

    reg('_executeSignatureHelpProvider', (args) async {
      final model = document(args);
      final at = position(args, 1);
      if (model == null || at == null) return null;
      final triggerCharacter = arg(args, 2);
      final result = await root.language.provideSignatureHelp(
        model,
        at,
        SignatureHelpContext(
          triggerKind: SignatureHelpTriggerKind.invoke,
          triggerCharacter: triggerCharacter is String
              ? triggerCharacter
              : null,
        ),
        cancellationTokenOf(args),
      );
      if (result == null) return null;
      final help = dto.encodeSignatureHelp(result.value);
      result.dispose();
      return help;
    });

    // --- code lens

    reg('_executeCodeLensProvider', (args) async {
      final model = document(args);
      if (model == null) return null;
      final resolveCount = arg(args, 1);
      var remaining = resolveCount is num ? resolveCount.toInt() : -1;
      final lenses = <CodeLens>[];
      for (final provider in root.service.codeLensProvider.ordered(model)) {
        final list = await _safe(
          () => provider.provideCodeLenses(model, cancellationTokenOf(args)),
        );
        if (list == null) continue;
        for (final lens in list.lenses) {
          if (remaining != 0 && provider.canResolveCodeLens) {
            if (remaining > 0) remaining--;
            lenses.add(
              await _safe(
                () => provider.resolveCodeLens(
                  model,
                  lens,
                  cancellationTokenOf(args),
                ),
              ) ??
                  lens,
            );
          } else {
            lenses.add(lens);
          }
        }
        list.dispose();
      }
      return [
        for (final lens in lenses)
          {
            'range': dto.encodeRange(lens.range),
            if (lens.command case final command?)
              'command': dto.encodeCommandDto(command),
          },
      ];
    });

    // --- code actions

    reg('_executeCodeActionProvider', (args) async {
      final model = document(args);
      final requested = range(args, 1);
      if (model == null || requested == null) return null;
      final kind = arg(args, 2);
      final filter = CodeActionFilter(
        include: kind is String ? HierarchicalKind(kind) : null,
        includeSourceActions: true,
      );
      final actions = await root.language.provideCodeActions(
        model,
        requested,
        filter,
        token: cancellationTokenOf(args),
      );
      final resolveCount = arg(args, 3);
      final count = resolveCount is num ? resolveCount.toInt() : 0;
      final result = <CodeAction>[];
      for (final (index, (:action, :provider)) in actions.indexed) {
        if (index < count && provider.canResolveCodeAction) {
          result.add(
            await _safe(
              () => provider.resolveCodeAction(
                action,
                cancellationTokenOf(args),
              ),
            ) ??
                action,
          );
        } else {
          result.add(action);
        }
      }
      return [
        for (final action in result)
          {
            'title': action.title,
            if (action.kind != null) 'kind': action.kind,
            if (action.edit case final edit?)
              'edit': dto.encodeWorkspaceEdit(edit),
            if (action.command case final command?)
              'command': dto.encodeCommandDto(command),
            'isPreferred': action.isPreferred,
          },
      ];
    });

    // --- colors

    reg('_executeDocumentColorProvider', (args) async {
      final model = document(args);
      if (model == null) return null;
      final colors = <ColorInformation>[];
      for (final provider
          in root.service.colorProvider.ordered(model).reversed) {
        final result = await _safe(
          () => provider.provideDocumentColors(
            model,
            cancellationTokenOf(args),
          ),
        );
        colors.addAll(result ?? const []);
      }
      return [for (final info in colors) dto.encodeColorInformation(info)];
    });

    reg('_executeColorPresentationProvider', (args) async {
      final color = arg(args, 0);
      final context = locationArg(arg(args, 1));
      if (color is! List || context == null) return null;
      final model = root.documents?.documentForUri(context.uri);
      if (model == null) return null;
      final info = ColorInformation(
        Range(
          context.range.startLineNumber,
          context.range.startColumn,
          context.range.endLineNumber,
          context.range.endColumn,
        ),
        dto.decodeColor(color),
      );
      final presentations = <ColorPresentation>[];
      for (final provider
          in root.service.colorProvider.ordered(model).reversed) {
        final result = await _safe(
          () => provider.provideColorPresentations(
            model,
            info,
            cancellationTokenOf(args),
          ),
        );
        presentations.addAll(result ?? const []);
      }
      return [
        for (final presentation in presentations)
          dto.encodeColorPresentation(presentation),
      ];
    });

    // --- inlay hints

    reg('_executeInlayHintProvider', (args) async {
      final model = document(args);
      final requested = range(args, 1);
      if (model == null || requested == null) return null;
      final hints = <InlayHint>[];
      for (final provider
          in root.service.inlayHintsProvider.ordered(model).reversed) {
        final list = await _safe(
          () => provider.provideInlayHints(
            model,
            requested,
            cancellationTokenOf(args),
          ),
        );
        if (list == null) continue;
        hints.addAll(list.hints);
        list.dispose();
      }
      stableSortStarts(hints);
      return [
        for (final hint in hints) dto.encodeInlayHint(hint),
      ];
    });

    // --- folding, selection ranges

    reg('_executeFoldingRangeProvider', (args) async {
      final model = document(args);
      if (model == null) return null;
      final ranges = <FoldingRange>[];
      for (final provider in root.service.foldingRangeProvider.ordered(model)) {
        final result = await _safe(
          () => provider.provideFoldingRanges(
            model,
            const FoldingContext(),
            cancellationTokenOf(args),
          ),
        );
        ranges.addAll(result ?? const []);
      }
      return [for (final range in ranges) dto.encodeFoldingRange(range)];
    });

    reg('_executeSelectionRangeProvider', (args) async {
      final model = document(args);
      if (model == null) return null;
      final positions = [
        for (final raw in dto.asList(arg(args, 1)))
          ?switch (positionArg(raw)) {
            final value? => Position(value.lineNumber, value.column),
            _ => null,
          },
      ];
      final result = await root.language.selectionRangesForDocument(
        model,
        positions,
      );
      return [
        for (final ranges in result)
          [for (final selection in ranges) dto.encodeRange(selection)],
      ];
    });

    // --- call hierarchy

    reg('_executePrepareCallHierarchy', (args) async {
      final model = document(args);
      final at = position(args, 1);
      if (model == null || at == null) return null;
      for (final provider in root.service.callHierarchyProvider.ordered(model)) {
        final session = await _safe(
          () => provider.prepareCallHierarchy(
            model,
            at,
            cancellationTokenOf(args),
          ),
        );
        if (session == null) continue;
        return [
          for (final item in session.roots) dto.encodeHierarchyItem(item),
        ];
      }
      return null;
    });

    reg('_executeProvideIncomingCalls', (args) async {
      final item = hierarchyItemArg(arg(args, 0));
      if (item == null) return null;
      for (final provider in root.service.callHierarchyProvider.allNoModel()) {
        final result = await _safe(
          () => provider.provideIncomingCalls(
            item,
            cancellationTokenOf(args),
          ),
        );
        if (result == null) continue;
        return [
          for (final call in result)
            dto.encodeIncomingCall(call.from, call.fromRanges),
        ];
      }
      return null;
    });

    reg('_executeProvideOutgoingCalls', (args) async {
      final item = hierarchyItemArg(arg(args, 0));
      if (item == null) return null;
      for (final provider in root.service.callHierarchyProvider.allNoModel()) {
        final result = await _safe(
          () => provider.provideOutgoingCalls(
            item,
            cancellationTokenOf(args),
          ),
        );
        if (result == null) continue;
        return [
          for (final call in result)
            dto.encodeOutgoingCall(call.to, call.fromRanges),
        ];
      }
      return null;
    });

    // --- type hierarchy

    reg('_executePrepareTypeHierarchy', (args) async {
      final model = document(args);
      final at = position(args, 1);
      if (model == null || at == null) return null;
      for (final provider in root.service.typeHierarchyProvider.ordered(model)) {
        final session = await _safe(
          () => provider.prepareTypeHierarchy(
            model,
            at,
            cancellationTokenOf(args),
          ),
        );
        if (session == null) continue;
        return [
          for (final item in session.roots) dto.encodeHierarchyItem(item),
        ];
      }
      return null;
    });

    reg('_executeProvideSupertypes', (args) async {
      final item = hierarchyItemArg(arg(args, 0));
      if (item == null) return null;
      for (final provider in root.service.typeHierarchyProvider.allNoModel()) {
        final result = await _safe(
          () => provider.provideSupertypes(item, cancellationTokenOf(args)),
        );
        if (result == null) continue;
        return [for (final entry in result) dto.encodeHierarchyItem(entry)];
      }
      return null;
    });

    reg('_executeProvideSubtypes', (args) async {
      final item = hierarchyItemArg(arg(args, 0));
      if (item == null) return null;
      for (final provider in root.service.typeHierarchyProvider.allNoModel()) {
        final result = await _safe(
          () => provider.provideSubtypes(item, cancellationTokenOf(args)),
        );
        if (result == null) continue;
        return [for (final entry in result) dto.encodeHierarchyItem(entry)];
      }
      return null;
    });

    return () {
      for (final stop in stops) {
        stop();
      }
    };
  }

  // --- helpers

  Future<T?> _safe<T>(FutureOr<T?> Function() call) async {
    try {
      return await call();
    } on Object {
      return null;
    }
  }

  DocumentSemanticTokensProvider? _documentSemanticTokens(
    LanguageFeatureDocument model,
  ) =>
      root.service.documentSemanticTokensProvider.ordered(model).firstOrNull;

  DocumentRangeSemanticTokensProvider? _rangeSemanticTokens(
    LanguageFeatureDocument model,
  ) => root.service.documentRangeSemanticTokensProvider
      .ordered(model)
      .firstOrNull;

  Future<List<LocationLink>> _locationLinks(
    LanguageFeatureDocument model,
    Position position,
    LanguageFeatureKind kind, {
    bool recursive = false,
  }) async {
    final links = <LocationLink>[];
    switch (kind) {
      case LanguageFeatureKind.definition:
        for (final provider in root.service.definitionProvider.ordered(
          model,
          recursive: recursive,
        )) {
          links.addAll(
            await _safe(
                  () => provider.provideDefinition(
                    model,
                    position,
                    CancellationToken.none,
                  ),
                ) ??
                const [],
          );
        }
      case LanguageFeatureKind.declaration:
        for (final provider in root.service.declarationProvider.ordered(
          model,
          recursive: recursive,
        )) {
          links.addAll(
            await _safe(
                  () => provider.provideDeclaration(
                    model,
                    position,
                    CancellationToken.none,
                  ),
                ) ??
                const [],
          );
        }
      case LanguageFeatureKind.implementation:
        for (final provider in root.service.implementationProvider.ordered(
          model,
          recursive: recursive,
        )) {
          links.addAll(
            await _safe(
                  () => provider.provideImplementation(
                    model,
                    position,
                    CancellationToken.none,
                  ),
                ) ??
                const [],
          );
        }
      case LanguageFeatureKind.typeDefinition:
        for (final provider in root.service.typeDefinitionProvider.ordered(
          model,
          recursive: recursive,
        )) {
          links.addAll(
            await _safe(
                  () => provider.provideTypeDefinition(
                    model,
                    position,
                    CancellationToken.none,
                  ),
                ) ??
                const [],
          );
        }
    }
    return RegistryLanguageFeatures.sortedAndDeduped(links);
  }

  Future<List<TextEdit>?> _rangeFormat(
    LanguageFeatureDocument model,
    Range? requested,
    FormattingOptions options,
    List<Object?> args,
  ) async {
    if (requested == null) return null;
    for (final provider
        in root.service.documentRangeFormattingEditProvider.ordered(model)) {
      final result = await _safe(
        () => provider.provideDocumentRangeFormattingEdits(
          model,
          requested,
          options,
          cancellationTokenOf(args),
        ),
      );
      if (result != null) return result;
    }
    return null;
  }

  Future<List<Link>> _linkList(
    LanguageFeatureDocument model,
    List<Object?> args,
  ) async {
    final links = <Link>[];
    for (final provider
        in root.service.linkProvider.ordered(model).reversed) {
      final list = await _safe(
        () => provider.provideLinks(model, cancellationTokenOf(args)),
      );
      if (list == null) continue;
      links.addAll(list.links);
      list.dispose();
    }
    return links;
  }

  Future<Link> _resolveLink(Link link) async {
    for (final provider in root.service.linkProvider.allNoModel()) {
      if (!provider.canResolveLink) continue;
      final resolved = await _safe(
        () => provider.resolveLink(link, CancellationToken.none),
      );
      return resolved ?? link;
    }
    return link;
  }
}

/// Which of the four "go to" provider kinds a command runs.
enum LanguageFeatureKind { definition, declaration, implementation, typeDefinition }

/// The `CancellationToken` of a built-in command: commands are not
/// cancellable from the extension API, so it is `none`.
CancellationToken cancellationTokenOf(List<Object?> args) =>
    CancellationToken.none;

/// `ensureFormattingOptions` with the editor's defaults.
FormattingOptions _formattingOptions(Object? value) =>
    dto.decodeFormattingOptions(value);

/// `InlayHintsFragments`: the hints in position order.
void stableSortStarts(List<InlayHint> hints) => stableSort(
  hints,
  (a, b) {
    final line = a.position.lineNumber.compareTo(b.position.lineNumber);
    return line != 0 ? line : a.position.column.compareTo(b.position.column);
  },
);

/// The item a `vscode.provideIncomingCalls` and friends send.
HierarchyItem? hierarchyItemArg(Object? value) {
  if (value is! Map) return null;
  final map = value.map((key, v) => MapEntry('$key', v));
  if (map[r'_sessionId'] == null || map[r'_itemId'] == null) return null;
  return dto.decodeHierarchyItem(map);
}
