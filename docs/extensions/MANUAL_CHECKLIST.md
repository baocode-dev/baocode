# Manual checks (extension support)

Everything the automated tests cannot prove: steps that need a real desktop,
real input methods, real system dialogs, or a real network. Each item says
what to do and what should happen. Reported in the final report as
"待手动验证".

Automated evidence (tests and screenshots) is in `docs/extensions.md` and in
the test files named `exthost`.

## 1. First run on a fresh data folder (九.1)

1. Move the data folder aside (`~/.baocode` on macOS) or set
   `BAOCODE_DATA_DIR` to an empty folder, and make sure no runtime is
   installed there.
2. Open the app and a TypeScript project.
3. Expect: the status bar shows "Downloading extension runtime" with a
   percentage, then "Installing…", then it disappears. Opening a `.ts` file
   then gives completions, hover, go to definition, references, rename,
   diagnostics, formatting, quick fixes, CodeLens and inlay hints.
4. Expect no other window, no file dialog and no console window.

Note: `flutter build macos --debug` was run, but the download path itself is
covered only by tests that use a local HTTP server and the real CDN
(see `packages/bao_exthost/test/runtime`).

## 2. Dragging a `.vsix` in from Finder (九.3)

1. Download any `.vsix` (e.g. from Open VSX) to Finder.
2. Drag it onto the BaoCode window.
3. Expect: a sheet showing the extension's name, version, publisher and a
   capability badge; installing it shows the extension in the Extensions view
   and its commands work.
4. Drag a folder that contains a `package.json` with `main`.
5. Expect: offered as a development extension, and its changes take effect
   after "Reload Window" (or without, when it is a UI-only extension).

The widget-level drop path is covered by tests; what a Finder drag actually
delivers (file URLs, promises, multiple items) is not.

## 3. Input methods (IME)

1. With a Chinese input method active, type into: the editor, an extension's
   completion filter, a QuickPick with a filter box, and an InputBox.
2. Expect: the composition is not broken, no characters are lost, the
   candidate window is not cut off, and Enter confirms the candidate rather
   than the dialog.

## 4. Native menus and system dialogs

1. Open an extension's context menu (editor right-click, explorer
   right-click) and check that items appear, are grouped and are enabled in
   the situations their `when` clauses describe.
2. Trigger `vscode.window.showOpenDialog` / `showSaveDialog` from an
   extension (e.g. an "open file" command).
3. Expect: real native dialogs, and the result reaching the extension.
4. Check the macOS menu bar and the Windows title bar menus still work with
   extensions that contribute keybindings that clash with the app's own.

## 5. GitHub sign-in (九.2, authentication)

1. Install an extension that needs GitHub (e.g. GitLens) and run its sign-in.
2. Expect: a consent dialog naming the extension and the account being
   requested; the browser opens; after authorising, the browser or the
   system brings the app forward again through the `baocode://` callback;
   the account then appears in the accounts menu and the extension receives a
   session.
3. Sign out from the accounts menu and check the extension sees it.

The `baocode://` scheme is registered in `macos/Runner/Info.plist`. Windows
and Linux registration has to be done by the installer:
- Windows: registry `HKEY_CLASSES_ROOT\baocode` with
  `URL Protocol` and a `shell\open\command` of
  `"<install dir>\baocode.exe" "%1"`.
- Linux: a `.desktop` file with `MimeType=x-scheme-handler/baocode;`.

## 6. Keychain authorisation (secrets)

1. Install an extension that keeps a token (`SecretStorage`), e.g. one that
   signs in.
2. The first write should make macOS ask whether BaoCode may use the
   "BaoCode Extension Secrets" keychain item; allowing it should stick.
3. On Windows, check the Credential Manager entry appears under
   "BaoCode Extension Secrets".

A real keychain test tagged `exthost` covers read/write/delete on macOS; the
authorisation prompt itself cannot be driven from a test.

## 7. Killing the extension host (九.7)

1. Start a project, confirm extensions are running (an extension's output
   channel, or a CodeLens).
2. `pkill -f server-main.js` (or kill the extension host node process).
3. Expect: a brief "Extension host terminated unexpectedly. Restarting…"
   status, then completions and CodeLens work again; the third crash within
   five minutes asks instead of restarting by itself, and "Restart Extension
   Host" works.
4. Kill it while offline and confirm already-downloaded extensions, themes and
   grammars still work.

## 8. Interrupted runtime download (九.7)

1. Start a download and kill the network (turn Wi-Fi off) halfway.
2. Expect: the status item turns into a failure with a retry action and
   nothing half-installed is left in `<data>/exthost/`.
3. Turn the network back on and retry (or restart the app): the download
   completes and the runtime works.
4. Point the app at a mirror with `BAOCODE_EXTHOST_BASE_URL` and at an
   already-extracted runtime with `BAOCODE_EXTHOST_DIR`.

## 9. Windows

Repeat on Windows, since everything above was checked on macOS:
- First-run download with the progress in the status bar.
- Dragging a `.vsix` from Explorer.
- `baocode://` registration (see 5).
- Credential Manager (see 6).
- The download path with a proxy configured in Windows settings.

## 10. Large project responsiveness

1. Open a large repository (tens of thousands of files).
2. Check: typing latency, completion latency, scrolling smoothness, the
   extension host's CPU while idle, and stepping in the debugger.
3. Expect: no visible stutter; the file watcher does not re-read files while
   typing; memory does not grow without bound.

## 11. SSH remote (九.6)

1. Add an SSH host, open a remote project.
2. Expect: the remote runtime is downloaded (from the CDN when the host has
   network, otherwise downloaded here and uploaded), the extension host
   starts on the remote, and TypeScript completions, Python and Node
   debugging work there.
3. Expect `ui`-only extensions (themes, keybinding extensions) to keep
   running locally, and `workspace` ones remotely (see the "Extensions" view
   per-kind badges).

## 12. Themes and icon themes (九.2)

1. Install a colour theme and an icon theme from Open VSX, pick them.
2. Expect: the whole workbench, editor token colours and the file icons
   change, and the choice survives a restart.
