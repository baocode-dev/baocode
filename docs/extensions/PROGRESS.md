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

- packages/bao_exthost: VsUri (uri.ts), PersistentProtocol (ipc.net.ts), server handshake (remoteAgentConnection.ts),
  IPC channels (ipc.ts), RPCProtocol (rpcProtocol.ts), cancellation.

## In progress / next

See the work plan below; each item notes its owner.

## Decisions and deviations

- No reconnection in PersistentProtocol: a lost local connection restarts the extension host.
- Dart `null` ⇄ JS `undefined` in IPC; RPC replies `null` as `undefined` (`rpcNull` for a JSON null).
