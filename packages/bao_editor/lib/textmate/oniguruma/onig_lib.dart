// Oniguruma for TextMate grammars, as vscode-oniguruma 1.7.0 gives it to
// vscode-textmate: native/oniguruma through dart:ffi on the desktop
// (onig_lib_io.dart). The web has no dart:ffi, and no Oniguruma here.

import '../vscode_textmate/onig_lib.dart';
import 'onig_lib_stub.dart'
    if (dart.library.ffi) 'onig_lib_io.dart'
    as platform;

/// Oniguruma, or null where it is not available: on the web, or when the
/// native library did not load.
IOnigLib? loadNativeOnigLib() => platform.loadNativeOnigLib();

/// A pattern Oniguruma rejected, with its message, as vscode-oniguruma's
/// `OnigScanner` means to throw it.
class OnigError implements Exception {
  const OnigError(this.message, {this.pattern});

  /// Oniguruma's `onig_error_code_to_str`, e.g. `invalid pattern in
  /// look-behind`.
  final String message;

  final String? pattern;

  @override
  String toString() => 'OnigError: $message';
}
