// Adapted from vscode-textmate 9.3.2 (25b68dad91920b1ed79d357534b8c4582f62d80d):
// src/debug.ts (MIT, see LICENSE.md).

/// Upstream reads `VSCODE_TEXTMATE_DEBUG` from the environment; this port
/// starts disabled and never logs. The flag only makes `parseRawGrammar`
/// record `$vscodeTextmateLocation` metadata, as upstream does.
abstract final class DebugFlags {
  static bool inDebugMode = false;
}

const bool useOnigurumaFindOptions = false;
