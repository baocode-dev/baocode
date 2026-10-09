# 扩展（VS Code 插件）

BaoCode 的插件系统跑的是**未经修改的上游 VS Code 扩展宿主**。应用本身是
Dart/Flutter，实现 VS Code 的"主线程"一侧；插件进程里跑的是微软的
`extensionHostProcess.js`，由 VSCodium 的 REH（Remote Extension Host）服务器
拉起。两者之间是 VS Code 自己的 RPC 协议（`packages/bao_exthost` 里用 Dart
逐字移植的 `PersistentProtocol` / IPC channel / `rpcProtocol`）。

这套做法有两点好处：插件的语义、激活规则、API 行为都由上游代码保证，不用担心
"仿得像不像"；坏处是必须跟随一个固定的 VS Code 版本（见下文"升级"）。

```
BaoCode (Dart, 主线程)                       插件进程 (Node)
  ExtensionHostService  ──RPC──▶  extensionHostProcess.js
  MainThreadXxxActor               ExtHostXxx (上游代码)
        ▲
        │ 管理连接 (IPC channels: extensions / remoteExtensionsScanner /
        │            remoteextensionsenvironment …)
  ExtensionServer (reh, node out/server-main.js)
```

## 架构

- **运行时**：VSCodium 的 REH，由 `tool/build_exthost_runtime.dart` 重新打包成
  BaoCode 自己的 `product.json`（nameLong `BaoCode`、`urlProtocol baocode`、
  Open VSX gallery、保留 `extensionEnabledApiProposals`）。五个平台，
  上传到 `https://dl.baocode.dev/releases/exthost/<id>/`。
- **服务器**：应用里只有一个 reh 进程（`ExtensionServerPool`），
  `--host 127.0.0.1 --port 0`，连接令牌写在服务器数据目录里。服务器负责扫描
  扩展、安装扩展（`extensions` channel）、提供环境信息。
- **扩展宿主**：每个工作区一个（`ExtensionHostService`），第一次需要激活事件时
  才启动，空闲不启动。连接是 TCP + VS Code 的握手（`auth` → `sign` →
  `connectionType`），`skipWebSocketFrames=true`，之后是
  `Ready` → init data → `Initialized` → RPC。
- **主线程一侧**：`lib/extensions/main_thread/` 下每个 `MainThreadXxxActor` 对应
  上游 `mainThreadXxx.ts`。协议代码由 `tool/generate_exthost_protocol.mjs` 从
  `extHost.protocol.ts` 生成——接口、`Unsupported` 兜底（调用会计数，供 parity
  报告）、解码参数的 actor、调用插件侧的 proxy。没有实现的形状不会静默返回
  null：它会抛 `RpcUnsupported` 并记进 `docs/extensions/EXTHOST_PARITY.md`。
- **进程管理**：`lib/platform/child_process_registry.dart` 记录子进程，崩溃或强退
  后下次启动会清理。扩展宿主崩溃按上游 `ExtensionHostCrashTracker` 处理：五分钟
  内自动重启最多 3 次，之后提示用户手动重启。
- **远程（SSH）**：远端项目由 `bao_remote` 在远端启动同一个 reh，端口经 SSH
  转发；插件按 `extensionKind` 分流——`workspace` 类在远端跑，`ui` 类在本机跑
  （`lib/extensions/host/extension_kind.dart`，规则照抄
  `extensionManifestPropertiesService.ts`）。

### 协议要点（调试时最常看）

| 层 | 文件（Dart） | 上游 |
| --- | --- | --- |
| socket 帧 / ack / keepalive | `packages/bao_exthost/lib/src/net/persistent_protocol.dart` | `ipc.net.ts` |
| 握手 | `.../net/remote_connection.dart` | `remoteAgentConnection.ts` |
| 管理连接 channel | `.../ipc/ipc.dart` | `ipc.ts` |
| RPC | `.../rpc/rpc_protocol.dart` | `rpcProtocol.ts` |
| 生成的服务形状 | `.../lib/src/generated/` | `extHost.protocol.ts` |

## 数据目录

```
<data>/exthost/<runtime-id>/       运行时（解压后的 reh）
<data>/extensions/                 已安装的扩展，VS Code 的布局
                                   publisher.name-version[-targetPlatform]/
                                   extensions.json
<data>/exthost-data/               服务器自己的数据：日志、扩展的 globalStorage
<data>/User/settings.json          设置（扩展的设置也在这里）
```

`DataDirectory`（`lib/platform/data_dir.dart`）列出了这些条目，所以"移动数据
文件夹"会把运行时和扩展一起搬走。

## 运行时版本与发布

固定的版本写在 `lib/extensions/runtime/runtime_version.dart`，打包清单在
`assets/exthost/exthost_runtimes.json`（随应用分发），里面有每个平台的 URL、
大小和 SHA-256。`test/extensions/runtime` 会检查两者一致。

构建与发布：

```sh
# 本机打包（会下载 VSCodium 的 release assets 并校验哈希）
dart run tool/build_exthost_runtime.dart            # 五个平台
dart run tool/build_exthost_runtime.dart --check    # 校验已有清单仍能重现
```

产物在 `build/exthost-runtime/`，清单写到 `assets/exthost/exthost_runtimes.json`。
CI（`.github/workflows/exthost-runtime.yml`）在 `v*` 标签上重跑 `--check`，
一致才上传；上传只写 `releases/exthost/<id>/` 且**只在目标前缀为空时**写入，
不覆盖已有对象。

安装路径（`packages/bao_exthost/lib/src/runtime/`）：下载到临时文件（边下边校验
大小和 SHA-256）→ 解压到 `<id>.tmp-*` → 原子重命名入位；中途失败不留半成品，
并发调用共用一次下载，支持重试。环境变量覆盖：

- `BAOCODE_EXTHOST_BASE_URL`：换下载源（调试时可用 `file:///…/build/exthost-runtime/`）。
- `BAOCODE_EXTHOST_DIR`：直接用某个已解压的运行时，不下载。

## 升级 VS Code 版本

1. 挑一个 VSCodium 的 REH 版本（`VSCodium/vscodium` 的 release），记下
   release tag 和它的 `product.json` 里的 `commit`。
2. 从 VSCodium 的 `upstream/stable.json` 找出对应的 VS Code commit，浅克隆到
   `/tmp/vscode-<版本>` 供移植和生成使用。
3. 改 `lib/extensions/runtime/runtime_version.dart` 的四个常量。
4. 重新生成（都会自己检查 commit，对不上会报错）：
   ```sh
   npm ci --prefix tool/exthost_codegen
   node tool/generate_exthost_protocol.mjs <checkout> <reh>/out/vs/workbench/api/node/extensionHostProcess.js \
        packages/bao_exthost/lib/src/generated
   node tool/generate_exthost_fixtures.mjs <checkout> packages/bao_exthost/test/fixtures/protocol.json
   node tool/generate_core_configuration.mjs <checkout> assets/exthost/core_configuration.json \
        --product <reh>/product.json
   dart run tool/generate_exthost_parity.dart
   ```
5. `dart run tool/build_exthost_runtime.dart`，跑 `flutter test --tags exthost`，
   再上传新前缀。
6. 上游改过行为的地方，看 `docs/extensions/EXTHOST_PARITY.md` 里新多出来的
   "unsupported" 调用。

## 故障排查

- **状态栏一直显示"Downloading extension runtime"**：看
  `<data>/exthost/` 是否留下 `.tmp-*`；用 `BAOCODE_EXTHOST_BASE_URL` 指向
  `build/exthost-runtime/`（`file://`）可以离线验证。网络中断会重试，校验和
  不符不会重试也不会留下半成品。
- **扩展没生效**：看 `Output` 面板里该扩展的通道，或者
  `Extension Host` 通道；`MainThreadXxx` 没实现的方法会打印
  `Unsupported: MainThreadXxx.$method`，并在
  `docs/extensions/EXTHOST_PARITY.md` 里计数。
- **扩展宿主反复崩溃**：五分钟内 3 次之后不再自动重启，状态栏会提示，
  点它手动重启。崩溃日志在 `<data>/exthost-data/data/logs/<时间戳>/`。
- **服务器起不来**：手工跑
  `<data>/exthost/<id>/node <id>/out/server-main.js --help`，确认运行时完整；
  连接令牌在 `<data>/exthost-data/connection-token`。
- **设置里看不到某个扩展的设置**：它得在 `contributes.configuration` 里声明；
  未声明的键在 `settings.json` 里仍然有效，只是没有 UI。
- **装了依赖 Webview 的扩展**：会用占位提示代替 Webview（本应用不支持
  Webview），其余功能照常。

## 相关工作

- `docs/extensions/EXTHOST_PARITY.md`：已实现/未实现的主线程方法（自动生成）。
- `docs/extensions/MANUAL_CHECKLIST.md`：只能手动验证的部分。
- `docs/extensions/PROGRESS.md`：开发进度与决定。
- `docs/ssh-remote.md`：SSH 远程项目。
