import 'dart:io';

import '../../../platform/data_dir.dart' show writeFileAtomically;

/// `lsp.json` as Open Language Server Settings makes it, where there is
/// none: its examples commented out, so that it changes nothing until the
/// user has it do something (#304).
const lspSettingsTemplate = '''
// Language servers: your own, and settings for those BaoCode knows.
// Saved, it applies to the open files at once. Every field:
// https://github.com/baocode-dev/baocode/blob/main/lib/ide/lsp/packs/README.md
{
  // A server of your own for a language, e.g. rust-glancer in place of
  // rust-analyzer for Rust. Its command is a name on your PATH, or the
  // executable's full path.
  //
  // "servers": {
  //   "rust-glancer": { "command": "rust-glancer", "args": ["lsp"] }
  // },
  // "languages": {
  //   "rust": { "servers": ["rust-glancer"] }
  // }
}
''';

/// Makes [path] with [lspSettingsTemplate] if there is no such file yet.
Future<void> ensureLspSettingsFile(String path) async {
  final file = File(path);
  if (await file.exists()) return;
  await file.parent.create(recursive: true);
  await writeFileAtomically(file, lspSettingsTemplate);
}
