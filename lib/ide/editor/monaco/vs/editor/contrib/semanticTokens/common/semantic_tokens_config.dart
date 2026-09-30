/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Ported from VS Code src/vs/editor/contrib/semanticTokens/common/
// semanticTokensConfig.ts at 6a598d4a13031703d483d103c1d934a36ad27971, with
// the default of `editor.semanticHighlighting.enabled` from
// editor/common/config/editorConfigurationSchema.ts.
// Deviation: `isSemanticColoringEnabled` takes the setting's value and the
// theme's `semanticHighlighting` instead of the model and the configuration
// and theme services.

// ignore_for_file: constant_identifier_names

const String SEMANTIC_HIGHLIGHTING_SETTING_ID = 'editor.semanticHighlighting';

/// `editor.semanticHighlighting.enabled`: `true`, `false` or this, the
/// default, which leaves it to the color theme.
const String semanticHighlightingConfiguredByTheme = 'configuredByTheme';

/// [enabled] is the `editor.semanticHighlighting.enabled` setting's value.
bool isSemanticColoringEnabled(
  Object? enabled,
  bool themeSemanticHighlighting,
) {
  if (enabled is bool) {
    return enabled;
  }
  return themeSemanticHighlighting;
}
