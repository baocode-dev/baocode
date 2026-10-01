/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Ported from VS Code src/vs/workbench/services/themes/common/
// tokenClassificationExtensionPoint.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971: the handlers of the
// `semanticTokenTypes`, `semanticTokenModifiers` and `semanticTokenScopes`
// extension points (`TokenClassificationExtensionPoints`), plus the
// contributions of the built-in extensions, as the workbench hands them over
// at startup.
//
// Not ported: the extension point JSON schemas and `delta.removed` (built-in
// extensions are never removed). Deviations: there is no extension registry;
// [TokenClassificationExtensionPoints] takes the users of each point directly
// and collects the `collector.error` messages in [errors]. Values that make
// upstream throw a TypeError (a `null` contribution, a `superType` that is
// not a string) are reported as errors and skipped, and a falsy `language`
// that is not a string counts as none.

import '../../../../platform/theme/common/token_classification_registry.dart';

/// An extension's value for one extension point (`IExtensionPointUser`).
class ExtensionPointUser {
  const ExtensionPointUser(this.extensionId, this.value);

  /// `description.identifier`, for messages.
  final String extensionId;

  /// The extension's `contributes.<point>`, as JSON.
  final Object? value;
}

/// What one extension's package.json contributes to token classification.
class TokenClassificationContribution {
  const TokenClassificationContribution(
    this.extensionId, {
    this.semanticTokenTypes,
    this.semanticTokenModifiers,
    this.semanticTokenScopes,
  });

  final String extensionId;
  final Object? semanticTokenTypes;
  final Object? semanticTokenModifiers;
  final Object? semanticTokenScopes;
}

class TokenClassificationExtensionPoints {
  TokenClassificationExtensionPoints([TokenClassificationRegistry? registry])
    : _registry = registry ?? getTokenClassificationRegistry();

  final TokenClassificationRegistry _registry;

  /// `collector.error` messages, as `<extension id>: <message>`.
  final List<String> errors = [];

  /// Hands [contributions] to the three points in the order the workbench
  /// registers (and so handles) them.
  void handle(List<TokenClassificationContribution> contributions) {
    handleSemanticTokenTypes([
      for (final c in contributions)
        if (c.semanticTokenTypes != null)
          ExtensionPointUser(c.extensionId, c.semanticTokenTypes),
    ]);
    handleSemanticTokenModifiers([
      for (final c in contributions)
        if (c.semanticTokenModifiers != null)
          ExtensionPointUser(c.extensionId, c.semanticTokenModifiers),
    ]);
    handleSemanticTokenScopes([
      for (final c in contributions)
        if (c.semanticTokenScopes != null)
          ExtensionPointUser(c.extensionId, c.semanticTokenScopes),
    ]);
  }

  bool _validateTypeOrModifier(
    Map<String, Object?> contribution,
    String extensionPoint,
    void Function(String) error,
  ) {
    final id = contribution['id'];
    if (id is! String || id.isEmpty) {
      error(
        "'configuration.$extensionPoint.id' must be defined and can not be "
        'empty',
      );
      return false;
    }
    if (!RegExp(typeAndModifierIdPattern).hasMatch(id)) {
      error(
        "'configuration.$extensionPoint.id' must follow the pattern "
        'letterOrDigit[-_letterOrDigit]*',
      );
      return false;
    }
    final superType = contribution['superType'];
    if (_isTruthy(superType) &&
        (superType is! String ||
            !RegExp(typeAndModifierIdPattern).hasMatch(superType))) {
      error(
        "'configuration.$extensionPoint.superType' must follow the pattern "
        'letterOrDigit[-_letterOrDigit]*',
      );
      return false;
    }
    if (contribution['description'] is! String) {
      error(
        "'configuration.$extensionPoint.description' must be defined and can "
        'not be empty',
      );
      return false;
    }
    return true;
  }

  void handleSemanticTokenTypes(List<ExtensionPointUser> added) {
    for (final extension in added) {
      void error(String message) =>
          errors.add('${extension.extensionId}: $message');
      final extensionValue = extension.value;
      if (extensionValue is! List<Object?>) {
        error("'configuration.semanticTokenType' must be an array");
        return;
      }
      for (final contribution in extensionValue) {
        final map = _contributionMap(contribution, error);
        if (map != null &&
            _validateTypeOrModifier(map, 'semanticTokenType', error)) {
          final superType = map['superType'];
          _registry.registerTokenType(
            map['id'] as String,
            map['description'] as String,
            superType is String ? superType : null,
          );
        }
      }
    }
  }

  void handleSemanticTokenModifiers(List<ExtensionPointUser> added) {
    for (final extension in added) {
      void error(String message) =>
          errors.add('${extension.extensionId}: $message');
      final extensionValue = extension.value;
      if (extensionValue is! List<Object?>) {
        error("'configuration.semanticTokenModifier' must be an array");
        return;
      }
      for (final contribution in extensionValue) {
        final map = _contributionMap(contribution, error);
        if (map != null &&
            _validateTypeOrModifier(map, 'semanticTokenModifier', error)) {
          _registry.registerTokenModifier(
            map['id'] as String,
            map['description'] as String,
          );
        }
      }
    }
  }

  void handleSemanticTokenScopes(List<ExtensionPointUser> added) {
    for (final extension in added) {
      void error(String message) =>
          errors.add('${extension.extensionId}: $message');
      final extensionValue = extension.value;
      if (extensionValue is! List<Object?>) {
        error("'configuration.semanticTokenScopes' must be an array");
        return;
      }
      for (final contribution in extensionValue) {
        final map = _contributionMap(contribution, error);
        if (map == null) continue;
        final language = map['language'];
        if (_isTruthy(language) && language is! String) {
          error(
            "'configuration.semanticTokenScopes.language' must be a string",
          );
          continue;
        }
        final scopes = map['scopes'];
        if (!_isTruthy(scopes) ||
            (scopes is! Map<String, Object?> && scopes is! List<Object?>)) {
          error(
            "'configuration.semanticTokenScopes.scopes' must be defined as an "
            'object',
          );
          continue;
        }
        for (final MapEntry(key: selectorString, value: tmScopes) in _forIn(
          scopes!,
        )) {
          if (tmScopes is! List<Object?> || tmScopes.any((l) => l is! String)) {
            error(
              "'configuration.semanticTokenScopes.scopes' values must be an "
              'array of strings',
            );
            continue;
          }
          final selector = _registry.parseTokenSelector(
            selectorString,
            language is String ? language : null,
          );
          _registry.registerTokenStyleDefault(
            selector,
            TokenStyleDefaults(
              scopesToProbe: [
                for (final s in tmScopes) (s as String).split(' '),
              ],
            ),
          );
        }
      }
    }
  }

  Map<String, Object?>? _contributionMap(
    Object? contribution,
    void Function(String) error,
  ) {
    if (contribution is Map<String, Object?>) return contribution;
    if (contribution == null) {
      error('contribution is null');
      return null;
    }
    // Upstream reads properties of the value, which are all undefined.
    return const {};
  }
}

/// The token classification contributions of the built-in extensions VS
/// Code ships at the pinned revision, in the order the workbench handles
/// them (by extension folder name): only `javascript` and
/// `typescript-basics` contribute, and only `semanticTokenScopes`, copied
/// from their package.json. tool/generate_semantic_token_fixtures.mjs records
/// what upstream registers, and the tests compare.
const List<TokenClassificationContribution>
builtinTokenClassificationContributions = [
  TokenClassificationContribution(
    'vscode.javascript',
    semanticTokenScopes: [
      {
        'language': 'javascript',
        'scopes': {
          'property': ['variable.other.property.js'],
          'property.readonly': ['variable.other.constant.property.js'],
          'variable': ['variable.other.readwrite.js'],
          'variable.readonly': ['variable.other.constant.object.js'],
          'function': ['entity.name.function.js'],
          'namespace': ['entity.name.type.module.js'],
          'variable.defaultLibrary': ['support.variable.js'],
          'function.defaultLibrary': ['support.function.js'],
        },
      },
      {
        'language': 'javascriptreact',
        'scopes': {
          'property': ['variable.other.property.jsx'],
          'property.readonly': ['variable.other.constant.property.jsx'],
          'variable': ['variable.other.readwrite.jsx'],
          'variable.readonly': ['variable.other.constant.object.jsx'],
          'function': ['entity.name.function.jsx'],
          'namespace': ['entity.name.type.module.jsx'],
          'variable.defaultLibrary': ['support.variable.js'],
          'function.defaultLibrary': ['support.function.js'],
        },
      },
    ],
  ),
  TokenClassificationContribution(
    'vscode.typescript',
    semanticTokenScopes: [
      {
        'language': 'typescript',
        'scopes': {
          'property': ['variable.other.property.ts'],
          'property.readonly': ['variable.other.constant.property.ts'],
          'variable': ['variable.other.readwrite.ts'],
          'variable.readonly': ['variable.other.constant.object.ts'],
          'function': ['entity.name.function.ts'],
          'namespace': ['entity.name.type.module.ts'],
          'variable.defaultLibrary': ['support.variable.ts'],
          'function.defaultLibrary': ['support.function.ts'],
        },
      },
      {
        'language': 'typescriptreact',
        'scopes': {
          'property': ['variable.other.property.tsx'],
          'property.readonly': ['variable.other.constant.property.tsx'],
          'variable': ['variable.other.readwrite.tsx'],
          'variable.readonly': ['variable.other.constant.object.tsx'],
          'function': ['entity.name.function.tsx'],
          'namespace': ['entity.name.type.module.tsx'],
          'variable.defaultLibrary': ['support.variable.tsx'],
          'function.defaultLibrary': ['support.function.tsx'],
        },
      },
    ],
  ),
];

bool _builtinsHandled = false;

/// [getTokenClassificationRegistry] once the built-in extensions'
/// contributions are registered, as the workbench has it.
TokenClassificationRegistry getWorkbenchTokenClassificationRegistry() {
  final registry = getTokenClassificationRegistry();
  if (!_builtinsHandled) {
    _builtinsHandled = true;
    TokenClassificationExtensionPoints(registry)
        .handle(builtinTokenClassificationContributions);
  }
  return registry;
}

/// JavaScript truthiness of a JSON value.
bool _isTruthy(Object? value) => switch (value) {
  null || false || '' => false,
  num n => n != 0 && !n.isNaN,
  _ => true,
};

/// JavaScript's `for...in` over a JSON object or array.
Iterable<MapEntry<String, Object?>> _forIn(Object value) sync* {
  if (value is Map<String, Object?>) {
    yield* value.entries;
  } else if (value is List<Object?>) {
    for (var i = 0; i < value.length; i++) {
      yield MapEntry('$i', value[i]);
    }
  }
}
