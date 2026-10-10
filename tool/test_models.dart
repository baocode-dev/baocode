import 'dart:io';

/// The same fail-fast gate used by both release packagers and CI. These tests
/// use loopback HTTP and memory accounts, never a developer's real API keys.
const modelTestFiles = [
  'test/models/model_test_test.dart',
  'test/models/model_test_io_test.dart',
  'test/models/codex_test.dart',
  'test/models/proxy',
  'test/settings/model_test_preset_test.dart',
  'test/settings/model_test_result_view_test.dart',
  'test/settings/model_test_dialog_test.dart',
  'test/settings/model_table_pagination_test.dart',
  'test/settings/model_test_table_test.dart',
  'test/settings/models_page_test.dart',
  'test/ide/ide_drag_selection_test.dart',
  'test/ide/ide_hover_test.dart',
  'test/tool/test_models_test.dart',
];

Future<void> main() async {
  final root = File.fromUri(Platform.script).parent.parent.path;
  exitCode = await runModelTests(root);
}

/// A nonzero exit code must stop packaging before build/sign/upload begins.
Future<int> runModelTests(String root, {String executable = 'flutter'}) async {
  stdout.writeln('==> Model protocol and settings regression tests');
  final process = await Process.start(
    executable,
    ['test', ...modelTestFiles, '--reporter', 'expanded'],
    workingDirectory: root,
    runInShell: Platform.isWindows,
    mode: ProcessStartMode.inheritStdio,
  );
  final code = await process.exitCode;
  if (code != 0) stderr.writeln('Model tests failed; packaging is blocked.');
  return code;
}
