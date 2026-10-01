import '../vscode_textmate/onig_lib.dart';

/// The web has no dart:ffi to reach Oniguruma through.
IOnigLib? loadNativeOnigLib() => null;
