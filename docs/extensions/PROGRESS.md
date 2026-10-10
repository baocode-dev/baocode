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
- App wiring: main.dart makes the `ExtensionsApp`; workbench.dart gives each IDE space its extensions (remote
  folders: their host's and this machine's, see 九.6); IdeWorkbench shows the Extensions view, extension pages, status bar entries, quick inputs,
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
- Testing API (lib/extensions/testing, lib/extensions/main_thread/main_thread_testing.dart): controllers, the test
  collection from diffs (resolve handlers through `$expandTest`), run profiles, runs from the view (trust, save, one
  request per controller) and runs extensions start, live results with upstream's state priorities, messages and
  output; the Testing view (activity bar entry once a controller registers) with Run/Debug per test and for all,
  Refresh, Cancel, the last run's summary, failures under their tests opening their locations, Go to Next Failure, and
  the "Test Results" output channel. Tests: `test/extensions/testing/` (widget) and `testing_exthost_test.dart` (real
  REH and fixture).
- Open VSX acceptance harness (test/extensions/acceptance/open_vsx_workspace.dart): a fresh data folder, real
  extensions installed through the workspace's management (dependencies and pack members from Open VSX too), the
  host started, unsupported calls and extension errors recorded. 九.2 language extensions pass with the machine's
  toolchains: Python + basedpyright, rust-analyzer, Go (gopls), clangd (`language_extensions_exthost_test.dart`);
  ESLint (project eslint, fix on save) and Prettier (default formatter, format on save)
  (`eslint_prettier_exthost_test.dart`).
- Management fixes found by it: `updateMetadata`/`installFromLocation` get the server's default profile location,
  the server's untransformed `install` answers are sent back as it takes them, dependencies and packs install, and
  a platform package is preferred when the version pages run out (rust-analyzer).
- Webview and Notebook degradation (九.5, `webview_degradation_exthost_test.dart`): notebook serializers, kernels and
  renderers are recorded with an Extension Host channel line; opening a notebook fails with a notice. Accept-only
  actors for absent features: language model tools (`$getTools` → none), profile content handlers, timeline, link
  presentation, ports attributes, debug visualizers. The placeholders' lines reach the Output panel.
- Save participants (lib/extensions/workbench/save_participants.dart): trim trailing whitespace, code actions on
  save, format on save, insert final newline, trim final newlines, then `onWillSaveTextDocument` (1750 ms), in
  upstream's order, for every save (`IdeWorkspace.saveParticipants`); `editor.defaultFormatter` and the formatter
  pick (lib/extensions/workbench/default_formatter.dart). Test: `save_participants_exthost_test.dart`.
- 九.2 editor extensions (`editor_extensions_exthost_test.dart`): GitLens (current-line blame decoration, hovers, its
  views), Error Lens + Code Spell Checker (inline diagnostics decorations, spelling diagnostics and quick fixes),
  Todo Tree (its tree and highlights), VSCodeVim (Normal/Insert modes, `x`, `dd`, `i`, Escape, `u`, the block
  cursor and its status bar item). For these: decoration types/ranges from the registry, the editor's caret styles
  (`TextEditorCursorStyle`, block/underline/outline painting) and line numbers styles (relative, interval) set by
  extensions through `$trySetOptions`, the `type`/`default:type` override, configuration-driven context keys,
  `editor.action.wordHighlight.trigger`, and V8-style stacks on errors sent back to the host.
- 九.2 Docker (`docker_exthost_test.dart`): `ms-azuretools.vscode-docker` brings Container Tools; the Dockerfile
  diagnostics, hover and completions, Compose completions, and the Images view listing the machine's images through
  the Docker CLI (read only; skipped without a daemon).
- 九.2 themes (`theme_extensions_exthost_test.dart`): Dracula (colors and TextMate rules applied from its file) and
  vscode-icons (its welcome notification answered with Activate, which sets `workbench.iconTheme`; Python, npm,
  TypeScript and `src` icons by name/extension/language from the installed folder); a second app on the same data
  folder lists both and uses vscode-icons before any host runs. `ExtensionsApp.followIconThemeSetting` follows the
  setting (main() and the test share it).
- 九.2 all together (`all_extensions_exthost_test.dart`): the 15 Open VSX extensions in one data folder, each
  activated on the project's files, no activation errors and no unsupported calls.
- Startup follows upstream: only `*` is waited for; `onStartupFinished` extensions activate without the workbench
  waiting (one may wait on its user, as vscode-icons' welcome does), and a restart resends the requested events
  without waiting for their activations. A workspace disposed while its host starts no longer builds actors on
  disposed services (the connection is closed instead).
- 九.4 debugging (`debug_extensions_exthost_test.dart`, plus `workspace_debug_exthost_test.dart` for Node attach):
  Python (debugpy), Go (Delve), C++ and Rust (CodeLLDB), Node (bundled js-debug), each through the workbench's debug
  service: hit count, conditional, function, data (Break on Value Change), log point and exception breakpoints set
  before and during the session; stepping in/over/out; call stack, scopes and variables; watch; the debug console;
  preLaunchTask (C++ clang++ build, Node) and CodeLLDB's cargo build; the debuggee's `runInTerminal` terminal.
  The task service sets `customExecutionSupported`/`shellExecutionSupported`/`processExecutionSupported` (debugpy's
  debugger `when`). CodeLLDB downloads its platform package on first use and installs it with
  `workbench.extensions.command.installFromVSIX`.
- Install Extension VSIX (`workbench.extensions.command.installFromVSIX`): `installGivenVersion`, all installs
  settled before the first failure is thrown, upstream's notifications. Extension deltas follow
  `_deltaExtensions`: one whose activation started is neither removed nor replaced; it waits in `pendingRestart`
  and the Extensions view and page offer Restart Extensions (no automatic host restart on update/uninstall).
- 九.3 management (`management_exthost_test.dart`): a .vsix dropped and installed (activating in the running host),
  import from VS Code and Cursor (Open VSX reinstall, alternatives, settings and keybindings), enable/disable in the
  workspace and globally (Restart Extensions for those that ran), update, uninstall, then a second app on the same data
  folder keeps all of it. Extensions added while the host runs activate without a restart (`_deltaExtensions`).
- 九.6 remote projects (lib/extensions/workbench/remote_extensions.dart, lib/remote/remote_exthost.dart,
  bao_remote `exthost/*`): the BaoCode server installs the runtime on the host (the host downloads it; when it cannot,
  this machine downloads it and sends it over SSH), starts its VS Code server there, and the app reaches it through
  the SSH connection's port forwarding. Each extension runs by `extensionKind` (manifest, `remote.extensionKind`,
  product.json's `extensionKind`/`extensionPointExtensionKind`): workspace ones in the host's extension host
  (`isRemote`, authority `ssh-remote+<host>`, upstream's URI transformer on the RPC and the init data), ui ones in
  this machine's (its URIs `vscode-remote` there). The host's user extensions follow this machine's. File service,
  tasks, terminals, debug machine (os, home, env), problems and language configuration read the host. The status bar
  shows the install on the host. Tests: `ssh_remote_exthost_test.dart` (the server in memory, this machine as the
  host) and `ssh_docker_exthost_test.dart` (real `ssh` to a Debian container, test/fixtures/extensions/sshd, runtime
  sent from here): TypeScript diagnostics/completion/hover on the host, VSCodeVim here editing and saving the host's
  file, Python (debugpy installed there) and Node (js-debug) debugging on the host. Unit: `uri_transformer_test.dart`,
  host_test's init data transform, remote_server_test's "extension runtime" group.
- IoExtHostSocket holds writes while it flushes (Dart's IOSink throws on `add` during `flush`): a reply written
  while a terminate was drained used to escape as an error (`socket_test.dart`).

## In progress / next

1. 九.1–九.7 are covered by tagged acceptance tests (see Done).
2. 九.8: remove the LSP implementation (lib/ide/lsp, assets/lsp, tool/generate_lsp_languages.mjs,
   tool/generate_mason_registry.mjs, lib/remote/remote_lsp.dart, bao_remote's LSP, language-packs/lsp.json, docs and
   l10n); `LanguageFeatures`/`LspPosition` and the other editor models move out of lib/ide/lsp.
3. 九.9: docs/extensions.md, generated EXTHOST_PARITY.md, MANUAL_CHECKLIST.md, offscreen screenshots in
   build/exthost-screens; then analyze, the full suite once, macOS build, merge.

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
- Debug visualizers/visualizer trees are accepted and kept, never offered (no visualizer UI in the Variables view).
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
- Testing: no coverage view (coverage is kept per task), continuous runs, follow-ups, related code, filter box,
  `testing/item/context` menus or gutter decorations; failures show under their tests instead of a peek view; results
  last for the session.
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
- Save participants: `editor.formatOnSaveMode` `modifications` formats the whole file (no line diff of a file);
  `files.trimTrailingWhitespaceInRegexAndStrings: false` trims anyway (no tokens); no progress/Skip notification.
  Format Document with several formatters and no default picks without the confirmation dialog first.
- Dependencies and pack members are installed by BaoCode from Open VSX after the extension (`donotIncludePackAndDependencies`
  on the server's install), not with it; a dependency that cannot be installed fails a gallery install afterwards.
- Todo Tree's Open VSX package lacks `@vscode/ripgrep`: the acceptance sets `todo-tree.ripgrep.ripgrep` to a ripgrep
  binary. Its default highlight colors are `ThemeColor`s it constructs without `new`, which throws upstream too; the
  test sets explicit colors. GitLens' onboarding is skipped by its setting (`gitlens.advanced.skipOnboarding`).
- VSCodeVim: typing reaches it through the `type` command override; IME composition does not go through the
  override yet (MANUAL_CHECKLIST). Its first start logs `ENOENT .registers` (the file does not exist yet), as upstream.
- Block caret painting takes the next UTF-16 code point (surrogate pairs), not a full grapheme cluster, and redraws it
  in the caret's inverted color without its token color.
- Virtual documents from extensions are read-only; references show in the references panel instead of a peek;
  `cursorMove` moves by logical lines.
- On shutdown upstream's host invalidates its proxies before `deactivate`: extensions that call the main thread from
  `deactivate` log `Channel has been closed`, as upstream (`ms-python.vscode-python-envs` also throws in its own
  `deactivate`).
- Delve stops a function breakpoint on the function's declaration line; a step in also lands there first. vscode-go
  waits 30 s for `dlv dap` to start; one run timed out once (not reproduced).
- Xcode's lldb-dap (LLVM 21) answers REPL evaluations as `(int) $0 = 84` and reports function breakpoint stops as
  `breakpoint`; the lldb-dap test accepts both forms.
- CodeLLDB reports its `rust_panic` filter's stop as a breakpoint in `__rustc::rust_panic`; its console runs LLDB
  commands (`?` evaluates an expression). An empty `cwd` in `runInTerminal` is the workspace folder (upstream's
  `getCwd`); a terminal launched in `''` used to exit at once.
- Remote projects: upstream leaves installing local extensions on the host to the user; BaoCode keeps the host's in
  step with this machine's (Open VSX package for the host's platform, else the folder packed as a .vsix). Each extension
  host is told only the extensions it runs, so a dependency on an extension of the other side is not found. This
  machine's ui host gets no remote authority (`vscode.env.remoteName` is undefined there; upstream says the remote's).
  The host's VS Code server lives as long as the connection: a lost connection restarts both. Handle-keyed registries
  shared by both hosts (SCM, tree views) key by handle only; language features keep each host's handles apart.
- A Linux host's extension host offers its port finder (`$setRemoteTunnelService`); with no Ports view upstream's
  ports features stay disabled, so it is never asked (`$registerCandidateFinder`). No port forwarding for extensions.
