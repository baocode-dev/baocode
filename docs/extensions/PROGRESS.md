# Extension host: progress

Goal file (not in the repo): /Users/leokun/Documents/kun6687/monad/docs/extension-host-goal.md.
Worktree: /Users/leokun/Documents/kun6687/monad-exthost, branch `feat/extension-host`.

## Pinned versions

| What | Value |
| --- | --- |
| Runtime | VSCodium REH **1.135.06055** (GitHub release `VSCodium/vscodium@1.135.06055`, 2026-09-09) |
| Product commit (handshake, init data) | `1a46a584725d5dd330e0bcd7f5510f24990efcf2` (VSCodium's build commit; not in microsoft/vscode) |
| Upstream VS Code | **1.135.0**, `08d4889f9ec4a1685d257b9b95de036c8e1ce1e5` (VSCodium `upstream/stable.json`) — port sources from this |
| Node in the runtime | v24.18.1 |

Upstream checkout for porting/codegen: `/tmp/vscode-1.135.0` (shallow fetch of the commit above; not persistent:
`git init; git fetch --depth 1 https://github.com/microsoft/vscode.git 08d4889f…; git checkout FETCH_HEAD`).
Downloaded REH for experiments: `/tmp/exthost-dl/reh-darwin-arm64`.

## Facts established (verified against the real REH)

- Server: `node out/server-main.js --host 127.0.0.1 --port 0 --connection-token-file F --server-data-dir D --extensions-dir E --accept-server-license-terms`
  prints `Extension host agent listening on <port>`.
- Connect: raw HTTP `GET ws://localhost/?reconnectionToken=<uuid>&reconnection=false&skipWebSocketFrames=true` with
  `Upgrade: websocket` + `Sec-WebSocket-Key`; after `101`, PersistentProtocol frames.
- Handshake: control `{type:auth, auth:<token>, data}` → `{type:sign, data, signedData}` → control
  `{type:connectionType, commit, signedData:<sign.data>, desiredConnectionType:1|2, args}` → `{type:ok}` (management)
  or `{}`/`{debugPort}` (ext host, preceded by a Pause; the ext host Resumes). No vsda in Code-OSS: any signedData passes.
- Management IPC: client sends serialized ctx `{remoteAuthority, clientId}` alone, then `[200]`. Server URIs come back
  as `vscode-remote://<remoteAuthority>/path` (server's `file:`); send `vscode-remote` for server paths.
- Ext host: receives `Ready` ([2]) → we send init data JSON → it sends `Initialized` ([1]) **immediately followed by RPC
  requests**: the handshake listener must detach synchronously on Initialized (messages then buffer until RPC listens).
- `remote.authority = null` in init data ⇒ no URI transformer in the ext host: all ext-host URIs are plain `file:` of the
  server's machine. Translate the management channel's `vscode-remote` URIs to `file:` for init data.
- Ext host does not activate anything until the main thread calls `ExtHostConfiguration.$initializeConfiguration` and
  `ExtHostWorkspace.$initializeWorkspace` (MainThreadConfiguration/MainThreadWorkspace constructors upstream).
- Proxy ids: 168 identifiers, `nid` = 1-based order of `MainContext` then `ExtHostContext` in extHost.protocol.ts;
  verified identical in the shipped bundle. Keys can differ from sids (`MainThreadLanguageModelTools` → sid
  `MainThreadChatSkills`).
- `packages/bao_exthost/tool/probe.dart` reproduces all of the above end to end (hello fixture activates, command
  round-trips through `$showMessage`).

## Done

- packages/bao_exthost: VsUri, PersistentProtocol, server handshake, IPC channels, RPCProtocol, generated proxies
  (`tool/generate_exthost_*`), runtime manifest/download.
- lib/extensions/host: server process and pool, connection, init data, activation events, crash restart, deltas
  (`$deltaExtensions` on install/uninstall/enable/disable; restart only when an activated extension goes).
- Main-thread actors: commands, configuration, documents and editors (EOL/BOM mapping), language features (all
  providers), diagnostics, workspace/files/search/trust, window (messages, progress, quick input, status bar, output,
  storage, secrets, URLs, authentication), webview degradation.
- bao_editor: decoration types, injected text, inlay hints, CodeLens zones, ghost text.
- Gallery/VSIX/import/capabilities/recommendations and the Extensions view (lib/extensions/ui).
- lib/debug: debug model, sessions, DAP client, Run and Debug views, Debug Console and floating/docked toolbar, wired to the workbench's activity bar, panel and commands (`test/extensions/workbench/ide_workbench_extensions_test.dart`).
- MainThreadDebugService: extension-host DAP transport, configuration/descriptor providers, session/cache/focus/custom
  events, breakpoints and console APIs. Scripted RPC evidence: `test/extensions/debug/main_thread_debug_service_test.dart`;
  related debug tests: 41 passed, 2 pre-existing presentation skips. Protocol fixtures/proxy/actor tests: 142 passed.
  This is protocol evidence; full real-extension debugging acceptance remains pending beyond Node launch/attach.
- WorkspaceDebugHost: IDE configuration/editor variables, trust requests, save, commands, quick input and read-only
  adapter sources (deferred reveal and adapter-backed reload); launch files through FileService and debug state through
  JsonStateStore. `test/extensions/workbench/workspace_debug_host_test.dart`: 8 passed.
- Workspace debug assembly: DebugService/launch files/state, dynamic workspace trust, launch reload and breakpoint removal
  are connected in `WorkspaceExtensions`. Tests cover headless restricted mode and persisted breakpoint/watch state in
  `test/extensions/workbench/workspace_extensions_debug_test.dart`.
- Run and Debug, Debug Console and toolbar are connected to the IDE workbench, with native view and debug commands;
  widget coverage is in `test/extensions/workbench/ide_workbench_extensions_test.dart`.
- The bundled js-debug is exercised with the real REH and its Node runtime: `pwa-node` launch and attach both bind a
  breakpoint, stop in `add`, and expose local arguments (`test/extensions/workbench/workspace_debug_exthost_test.dart`,
  tagged `exthost`). Empty editor groups are announced before tab updates (`main_thread_editor_tabs_test.dart`).
- Registry document highlights now paint read/write/text occurrences in the active editor, refresh on caret/content/provider
  changes, and clear on blur or disabled settings (`test/extensions/workbench/editor_feature_driver_test.dart`).
- Syntax folding providers now drive `bao_editor`'s folding model, retaining collapsed state across refreshes and falling
  back to indentation when the provider disappears (`packages/bao_editor/test/monaco/flutter/editor_surface_view_test.dart`).
  The editor drops outdated post-frame and async provider results on document edits/switches; focused tests in
  `test/ide/native_editor_integration_test.dart` and `test/extensions/workbench/editor_feature_driver_test.dart` pass.
- Document-link providers now render modifier-hover link decorations and open resolved links on Cmd/Ctrl-click. Results
  expire on edits, provider changes, and tab switches; stale resolves cannot open old links. Widget pointer tests and
  provider tests cover the editor surface; command URIs are not executed.
- Document colors: provider colors paint swatches (tracked through edits until the debounced refresh; late results
  dropped; `editor.colorDecorators`/`colorDecoratorsLimit`). A swatch click opens the color picker (saturation box,
  opacity and hue strips, header label = provider presentation, click to cycle; original color to revert). Drags
  preview the provider's presentation and write on release; each write applies the main and additional edits as one
  undo step, and the picker tracks the color's range for the next request. External edits, Escape, outside taps and tab
  switches close it. Tests: `editor_feature_driver_test.dart`, `test/ide/ide_editor_colors_test.dart` (real editor,
  screenshot `editor_color_picker.png`), `registry_language_features_test.dart`.
- Acceptance 九.1/九.7 (tagged `exthost`): `test/extensions/acceptance/fresh_runtime_ts_exthost_test.dart` — fresh data
  folder, the real dl.baocode.dev archive served by a local mirror that drops the first transfer (failure leaves nothing
  behind; retry completes with downloading/installing/ready progress), TS completion/hover/definition/references/
  rename/diagnostics/format/quick fix/CodeLens/inlay hints on a second, offline app, then SIGKILL of the extension host
  and automatic recovery. Fixes it found: failed starts no longer cache activations (and replay requested events on the
  next start, upstream `_allRequestedActivateEvents`), `onLanguage`/`onLanguage:<id>` are sent together, languages are
  asked again after a failed start, and socket write errors after a reset no longer escape as unhandled errors.
- Assembly (lib/extensions/workbench): `ExtensionsApp` (one per app) and `WorkspaceExtensions` (one per local IDE
  folder) over `IdeWorkspace` (`IdeTextEditors`, `IdeDocumentsPort`, `IdeWorkspaceEditApplier`); real-runtime test
  `test/extensions/workbench/workspace_extensions_exthost_test.dart` (TS diagnostics, completion, hover).
- App wiring: main.dart makes the `ExtensionsApp`; workbench.dart gives each local IDE space its extensions (remote
  folders: none yet); IdeWorkbench shows the Extensions view, extension pages, status bar entries, quick inputs,
  OUTPUT, palette commands, keybindings, runtime download status, recommendations, .vsix/dev-folder drops
  (`test/extensions/workbench/ide_workbench_extensions_test.dart`). lib/ide/extensions (LSP catalog view) removed.
- Workbench extension views: TreeViews in Explorer/activity-bar containers and panel containers; view/title and item
  menus, welcome content, file decorations and panel badges. Widget evidence:
  `test/extensions/workbench/ide_workbench_views_test.dart`.
- Terminals for extensions (lib/extensions/main_thread/main_thread_terminal_service.dart,
  main_thread_terminal_shell_integration.dart, lib/extensions/terminal/environment_variable_service.dart):
  `createTerminal` (shell, args, cwd, env/strictEnv, name, hideFromUser, waitOnExit, initialText) and Pseudoterminals
  on the panel's `TerminalService`, the terminal events, data events, `sendText`/`show`/`hide`/`dispose`, the default
  profile (`env.shell`), persistent environment variable collections, and shell integration (`executeCommand`,
  `read()`, exit codes, cwd, env). The workbench binds its service; headless, `ExtensionTerminals` keeps its own.
  Tests: `test/extensions/terminal/` (scripted) and `terminal_exthost_test.dart` (real REH, real zsh).
- Tasks (lib/extensions/tasks, lib/extensions/main_thread/main_thread_task.dart,
  lib/extensions/workbench/workspace_tasks.dart): tasks.json per folder (2.0.0 schema, OS overrides, `dependsOn` in
  parallel/sequence, inputs), problem patterns/matchers (built-in and contributed, background begin/end), the extensions'
  task providers and `taskDefinitions` (`onTaskType:` activation, customization by tasks.json), the terminal task system
  (shell/process/custom execution, terminal reuse, presentation, instance policy), `fetchTasks`/`executeTask`/
  `terminateTask` and task events for extensions, the Tasks commands and output channel, and the debugger's
  preLaunchTask/postDebugTask runner (`debug.onTaskErrors`, remembered choices, slow-task notice). Tests:
  `test/extensions/tasks/` (real shells, scripted RPC) and `tasks_exthost_test.dart` (real REH and fixture).
- Source control (lib/extensions/scm, lib/extensions/main_thread/main_thread_scm.dart): extensions' source controls
  with groups, resource splices, decorations, input box (validation, accept input command), action button and count, as
  panes in the Source Control view after BaoCode's Git panes, with `scm/title`, `scm/resourceGroup/context` and
  `scm/resourceState/context` menus. The built-in Git extension runs (its API sees the repository) and its provider is
  received but not shown. Tests: `test/extensions/scm/` (scripted, widget) and `scm_exthost_test.dart` (real REH).
- Language status items (lib/extensions/languages/language_status*.dart): `$setLanguageStatus` with selector
  matching and upstream's order, one status bar entry for the active document (severity icon, busy spinner, hover
  list, click menu of the items' commands). The TypeScript version item is asserted in the 九.1 acceptance test.

## In progress / next

1. Editor-feature rendering from the registry is complete (CodeLens, inlay hints, inline completions, highlights,
   folding, links, colors).
2. Complete real-extension debugging acceptance beyond Node launch/attach (Python, Go, Rust/C++, debugger controls,
   breakpoint variants and preLaunchTask in a real session). Implement the testing actor and the accept-only actors
   real extensions call (timeline, language model tools, profile content handlers).
3. Remove the remaining LSP implementation (lib/ide/lsp catalog/install/packs/client/manager/process, assets/lsp,
   bao_remote LSP, docs and l10n), after replacing its language capability coverage.
4. SSH remote: REH on the remote through bao_remote port forwarding, with the extensionKind split.
5. Real-extension integration tests and screenshots, docs and generated parity; then analyze, full test once, macOS
   build, merge.

## Decisions and deviations

- `LanguageFeatures`/`lsp_protocol.dart` types are the editor UI's model and survive the LSP removal (moved out of
  lib/ide/lsp/); the extension host feeds them.
- Language ids come from the bundled VS Code language contributions (bao_editor's TextMate manifest) plus
  installed extensions' `contributes.languages`; the REH ships no grammar/basics extensions.
- Crash restarts follow `ExtensionHostCrashTracker`: automatic restart while fewer than 3 crashes in 5 minutes, then
  the user restarts by hand.

- No reconnection in PersistentProtocol: a lost local connection restarts the extension host.
- Dart `null` ⇄ JS `undefined` in IPC; RPC replies `null` as `undefined` (`rpcNull` for a JSON null).
  `RpcProtocol.call(preserveJsonNull: true)` preserves JSON-null replies as `rpcNull` for debug configuration resolvers:
  JSON null opens launch.json; undefined cancels silently. Existing generated nullable proxies keep their prior behavior.
- Debug visualizers/visualizer trees remain explicitly unsupported (no model/UI service). No fake registration.
- The pinned VSCodium REH already bundles `ms-vscode.js-debug` 1.117.0 (MIT) and `ms-vscode.js-debug-companion` 1.1.3.
  The js-debug version and official VSIX SHA-256 match upstream 1.135.0's `product.json`; a prior assumption that they
  were absent was incorrect. Packaging needs no additional VSIX. Real launch and attach are covered by the tagged test.
- On macOS, `Directory.systemTemp` may return `/var/folders` while Node reports `/private/var/folders`; resolve the
  temporary test workspace symlink before setting js-debug breakpoints so the DAP source paths match.
- Tasks: folders' tasks.json only (no user or .code-workspace tasks, no 0.1.0 process engine); one-level task pick
  without recent tasks, problem-matcher attach prompt or templates (Configure Task opens the folder's tasks.json, made
  from the "Others" template); no reconnection to task terminals after a restart; no split terminals for
  `presentation.group`; a rerun resolves its variables again. A terminal's initial text and exit messages are not
  output lines for problem matchers; a process's exit is told after its output is parsed (`_flushXtermData`).
- Extension terminals live in the panel only (no editor-area terminals or splits); terminal completion, quick fix and
  link providers are accepted without UI; contributed terminal profiles are recorded, not offered in the menu.
  Remote (SSH) terminals do not get an extension's `env` or the environment collections.
- `TerminalShellExecution.read()` is cut from the process data at the OSC 633/133 `C`/`D` sequences rather than from
  xterm's post-parse data events, so a fast command's output is not lost when C, output and D arrive in one chunk.
- `test/ide/terminal/terminal_color_theme_test.dart` fails on the branch base too (pixel sampling).
- SCM: no quick diff, history or artifact providers from extensions (BaoCode's gutter and graph read Git); the input
  box is a plain text field (no `vscode-sourcecontrol:` model); resources are a list (no tree mode), single selection.
  Calls to actors BaoCode does not implement at all are counted in `ExtHostParity` as `Actor.$method`.
- Extension pages show over the editors (not as editor tabs): BaoCode's tabs are documents.
- A multi-folder workspace runs one extension host on its first folder for now.
- Keybindings: the keybinding service holds one set of extension keybindings, the visible workbench's.
- The built-in TypeScript extension declares `untrustedWorkspaces.supported: false`: in a new (untrusted) folder it runs
  only once the user trusts the folder (startup prompt), as upstream. Tests trust the folder explicitly.
- Toasts time out only while a workbench listens to the notifications (they are the workspace's now).
- Panel view containers render as bottom-panel tabs; auxiliary-bar containers use activity-bar entries.
- Color picker drags write on release, not on every move (upstream leaves an undo stop per move); no default
  color provider (`editor.defaultColorDecorators`).
- Tree drag and drop and `TreeItemAligner` are not implemented; alt menu actions are not shown.
- `test/chat/chat_width_test.dart` (composer grows with the setting), two chat mode-picker tests in
  `test/chat/chat_keys_test.dart`, and `test/workspace/quit_confirmation_test.dart` fail on the merge base too.
