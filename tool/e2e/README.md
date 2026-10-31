# Desktop code navigation E2E

This launches the real macOS BaoCode window. It uses the production app,
standard language catalog, a temporary project on disk, and the real Dart SDK
language server. It does not use `flutter_test`, a fake LSP server, or call the
editor's navigation methods to simulate a result.

Build from the repository root:

```sh
flutter build macos --debug --target tool/e2e/code_navigation_app.dart
```

Run with an output directory and the **SDK binary**, rather than the Flutter
`bin/dart` shell wrapper:

```sh
navigation_out="$(mktemp -d /private/tmp/baocode-navigation-e2e.XXXXXX)"
BAOCODE_DATA_DIR="$navigation_out/data" \
BAOCODE_E2E_OUT="$navigation_out" \
BAOCODE_E2E_DART=/absolute/path/to/flutter/bin/cache/dart-sdk/bin/dart \
  build/macos/Build/Products/Debug/BaoCode.app/Contents/MacOS/BaoCode
```

The app creates its own workspace and data folder, brings its window forward,
and drives pointer events through hit testing and keys through the hardware
keyboard and focus tree, using the existing desktop performance input driver.
File setup uses the workbench's regular file-open entrypoint. The navigation
under test uses keyboard and mouse input.

Checks:

1. Click `greet` in the calling file and press F12 while the language server
   is starting. A launcher holds the real server until after the keypress,
   then execs `dart language-server`. The first request must open the
   declaration in the other file at line 1, column 8 without another keypress.
2. Reopen the calling file and Cmd+click `greet`; check the same file and caret.
3. Press Shift+F12; check that the visible References panel contains both the
   call and declaration in their respective files.
4. Click the declaration's reference row; check that it opens the declaration
   and selects exactly `greet`.

The saved IDE layout closes the unrelated chat panel. Flutter errors still
fail the run. There are no model requests or language-server downloads.

The app writes `result.json` with paths, caret/selection positions, errors and
pass/fail results, plus PNG screenshots before and after navigation. Inspect
the screenshots as well as the JSON. The process exits 0 only if every check
passes; startup and scenario timeouts fail the run. Keep the output directory
for evidence, and use a new one for each run.

This driver verifies local macOS navigation. SSH transport and Windows GUI
coverage require a separately authenticated SSH environment and a Windows
runner; a local passing run does not imply those environments were exercised.
