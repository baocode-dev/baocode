import 'package:baocode/ide/editor/textmate/oniguruma/onig_lib.dart';
import 'package:baocode/ide/editor/textmate/vscode_textmate/onig_lib.dart';

/// The regex engine every Oniguruma-dependent test uses: native Oniguruma,
/// as vscode-textmate's own tests run on vscode-oniguruma.
Future<IOnigLib> testOnigLib() async =>
    loadNativeOnigLib() ?? (throw StateError('Oniguruma did not load'));
