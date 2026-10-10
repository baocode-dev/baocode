/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// An extension's `language-configuration.json` as the editor edits the
// language with it (comments, brackets, auto-closing pairs, surrounding
// pairs, folding markers, word pattern, indentation rules, on-enter
// rules).
//
// The conversion of the JSON shape is bao_editor's
// `languageConfigurationFromMonaco` (the same shape Monaco's `conf` object
// has); this file only names the result and keeps the extension it came
// from for messages.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/editor/common/languages/languageConfigurationRegistry.ts
// (`LanguageConfigurationRegistry.register`), the `language-configuration`
// contribution of a `contributes.languages` entry.
//
// Deviations: the configuration is resolved per document by the caller
// (there is no registry keyed by language id in bao_editor).

import 'package:bao_editor/monaco/flutter/language_configuration_assets.dart'
    show languageConfigurationFromMonaco;
import 'package:bao_editor/monaco/vs/editor/common/languages/language_configuration.dart';

/// A `language-configuration.json` and the extension that contributed it.
class LanguageConfigurationEntry {
  const LanguageConfigurationEntry(this.json, this.extensionId);

  final Map<String, Object?> json;
  final String extensionId;

  /// The editor's view of it.
  LanguageConfiguration get configuration =>
      languageConfigurationFromMonaco(json);
}

/// Builds the editor's [LanguageConfiguration] from a
/// `language-configuration.json`'s JSON.
LanguageConfiguration languageConfigurationFromJson(
  Map<String, Object?> json,
) => languageConfigurationFromMonaco(json);
