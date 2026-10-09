# Goal：BaoCode 原生支持 VS Code 插件（上游 Extension Host + Dart 主线程），取代现有 LSP 体系

## 一、背景与最终效果

BaoCode 桌面端（仓库 /Users/leokun/Documents/kun6687/monad，Flutter，macOS/Windows）目前的“扩展”只是一套自研的 LSP 客户端：Helix 语言映射、mason 安装、language-packs，代码在 lib/ide/lsp/，远程版本在 lib/remote/remote_lsp.dart 和 packages/bao_remote。现在要换成**完整的 VS Code 插件支持**。

最终用户体验：
1. 安装包里**不带** Node 和插件运行时。用户第一次需要插件能力时（打开带代码的项目、打开扩展视图、安装插件、开始调试），应用自动从 `https://dl.baocode.dev` 下载我们固定版本的运行时，校验后持久化到数据目录。全程只在状态栏和通知里显示进度，不需要用户做任何操作；之后离线也能用。
2. 插件功能完整可用：
   - 从 Open VSX 搜索、安装、卸载、启用、禁用、更新插件；
   - 把 `.vsix` 拖进窗口即可安装；
   - 一键从 VS Code、Cursor、Windsurf、VSCodium 导入已装插件；
   - 内置扩展（TypeScript、JSON、CSS、HTML、Markdown、Git、js-debug 等）开箱即用。
3. 调试完整可用：VS Code 的“运行和调试”（DAP），能力见第九节验收。
4. 现有 LSP 体系整体删除，语言功能全部由插件提供。
5. **不做 Webview**。依赖 Webview 的 API 要安静降级（见第五节第 15 条）。

## 二、架构（已定，不要改方向）

- **Node 侧完全使用上游原版，不修改任何 JS 代码**：VS Code 远程服务端（reh）加上 `extensionHostProcess.js`，以及运行时自带的内置扩展。插件看到的是 100% 原版 `vscode` API。
- **Dart 侧实现“主线程”**：用 Dart 移植 `src/vs/workbench/api/browser/mainThread*.ts` 及其依赖的服务，后端接到 BaoCode 现有模块。做法同 packages/bao_editor 移植 Monaco：注明上游 commit 和路径，保留 MIT 许可声明，用上游行为做对照测试。先读 packages/bao_editor/HANDOFF.md、PORTING.md、PARITY.md 了解这套惯例。
- 连接方式：
  - Dart 通过 TCP 连接 127.0.0.1 上的 reh，用 connection token 鉴权；
  - 开两条连接：Management（扩展管理、扫描、环境信息）和 ExtensionHost（RPC）；
  - 握手时用 `skipWebSocketFrames=true`，跳过 WebSocket 帧；
  - 远程项目在远端启动同一个 reh，通过 bao_remote 已有的 SSH 通道做端口转发，Dart 侧代码不区分本地和远程。
- 进程模型：
  - 整个应用共享一个本地 reh；
  - 每个打开的工作区一个 ext host，懒启动，只在有插件需要激活时才拉起；
  - 进程登记到 lib/platform/child_process_registry.dart，启动时回收残留，退出时停止；
  - ext host 崩溃后自动重启，5 分钟内最多 3 次，超过就给用户发通知；
  - 根据 RPC 的 Acknowledged 消息检测 ext host 是否无响应。

## 三、运行时：固定版本、分发、下载

1. **选版本**：
   - 开工时选当时最新的 **VSCodium 稳定版 REH**（MIT 许可，product.json 已经指向 Open VSX）。如果 VSCodium 的包无法满足需求，就用 Code-OSS 源码执行 `gulp vscode-reh-<平台>-min` 自行构建。
   - 记下 VS Code 版本号和 commit，写进 `lib/extensions/runtime/runtime_version.dart`。**整个项目只认这一个版本**，Dart 生成的协议代码必须和它的 commit 一致。
   - **禁止**从本机 /Applications 里的微软 VS Code 或 Cursor 拷贝任何文件用于分发。它们不是 MIT 许可，只能用来对照行为。
2. **打包工具** `tool/build_exthost_runtime.dart`，仿照 tool/build_remote_server.dart 和 docs/ssh-remote.md 第 9 节的 servers.json 做法：
   - 下载固定版本的 REH，平台包括 darwin-arm64、darwin-x64、win32-x64、linux-x64、linux-arm64（后两个给 SSH 远程用）。
   - 修改 product.json：nameShort/nameLong 改为 BaoCode，`urlProtocol: baocode`，独立的 `serverDataFolderName`，`extensionsGallery` 指向 Open VSX，保留 `extensionEnabledApiProposals`。
   - 去掉明显用不到的部分，重新打包成 `.tar.gz`（Windows 用 `.zip`）。
   - 生成 `exthost_runtimes.json`，内容为各平台的下载地址、大小、SHA-256。这个文件提交进仓库，并打进安装包。
3. **R2 路径**：`https://dl.baocode.dev/releases/exthost/<vscode版本>-<短哈希>/<文件>`。在 .github/workflows 里加发布任务：仅在运行时版本变化时上传，只新增文件，不覆盖已有的版本目录。
4. **上传授权**：允许用 `wrangler r2 object put` 把运行时上传到 R2 的 `releases/exthost/` 前缀下。只能新增，不能删除或覆盖任何已有对象，也不能碰 `releases/` 下的其他路径。如果没有可用的凭据，就把文件和上传命令准备好，写进最终报告。
5. **应用内下载**（`lib/extensions/runtime/`）：
   - 按需触发；HTTP 跟随重定向；先下载到临时文件，校验 SHA-256，解压到 `<data>/exthost/<版本>/` 的临时目录，再原子改名就位。中途失败不能留下半成品。
   - 支持重试，进度显示在状态栏。
   - 提供环境变量 `BAOCODE_EXTHOST_BASE_URL` 和 `BAOCODE_EXTHOST_DIR`，用于开发、测试和自建镜像。
   - 需要解压工具时，从 lib/ide/lsp/install/archive.dart 迁出到通用位置（例如 lib/platform/），再删除 LSP。
6. **数据目录布局**：
   - `<data>/exthost/<版本>/`：运行时
   - `<data>/extensions/`：用户插件，格式与 VS Code 完全一致，即 `publisher.name-版本[-平台]/` 加 `extensions.json`
   - `<data>/exthost-data/`：reh 的 server-data
   - `<data>/User/settings.json`：设置。插件的 globalStorage、workspaceStorage、日志按 VS Code 的布局放在数据目录下。
   - `<data>` 指 DataDirectory.current。

## 四、协议层（新建纯 Dart 包 packages/bao_exthost，不依赖 Flutter）

以下细节以所钉版本的源码为准。把上游源码 clone 到 /tmp 使用，不要纳入仓库；生成脚本要先校验上游 HEAD。

- `base/parts/ipc/common/ipc.net.ts`：PersistentProtocol。13 字节帧头，ack，keepalive。
- `platform/remote/common/remoteAgentConnection.ts`：握手流程 auth → sign → connectionType（Management / ExtensionHost），附带 commit。
- `base/parts/ipc/common/ipc.ts`：IPC 序列化和 ChannelClient。Management 侧用到的通道：`extensions`（getInstalled/install/installFromGallery/uninstall 及事件）、`remoteExtensionsScanner`、`remoteextensionsenvironment`。
- `workbench/services/extensions/common/extensionHostProtocol.ts` 和 `rpcProtocol.ts`：先完成 Ready / InitData / Initialized 握手，再实现 RPC 的各种请求和回复、取消、Acknowledged、带 `$mid` 的对象（URI、VSBuffer）的编解码。
- **代码生成** `tool/generate_exthost_protocol.mjs <vscode-checkout> <out>`：
  - 用 ts-morph 读 `workbench/api/common/extHost.protocol.ts`，生成全部 `MainThread*Shape`、`ExtHost*Shape` 的 Dart 接口、调用 ext host 的 Proxy、主线程的分发器。
  - **proxy 的数字编号不能靠解析源码顺序推算**，要用 Node 加载编译后的 extHost.protocol.js 导出编号表。
  - DTO 类型：高频的生成强类型（补全项、TreeItem、装饰选项、WorkspaceEdit、文档变更、调试相关），其余用 Map 透传。
  - **每个 Shape 都要有兜底实现**：未实现的方法一律明确返回错误，不能让对方的 Promise 挂起，并记录被调用的次数。根据记录自动生成 `docs/extensions/EXTHOST_PARITY.md`。
- 协议层测试：用 Node 加载上游序列化代码生成固定字节样本，Dart 解码后逐字节对照（仿照 generate_monaco_core_fixtures.mjs 的做法）。

## 五、主线程实现（lib/extensions/，按依赖顺序）

1. **初始化与激活**：
   - 构造 IExtensionHostInitData；按上游 abstractExtensionService 的启动顺序推送初始状态（配置、文档和编辑器、工作区、主题类型、窗口焦点、终端环境变量集合等）。
   - 移植 `implicitActivationEvents.ts`，也就是从 contributes 推导出的隐式激活事件。
   - Dart 负责触发 `*`、`onStartupFinished`、`onLanguage`、`onCommand`、`onView`、`onFileSystem`、`onUri`、`onDebug*`、`onTaskType` 等激活事件。插件增删时增量更新扩展列表（`$deltaExtensions`），不重启 ext host。
2. **文档同步**（重点，bug 最集中的地方）：
   - `$acceptDocumentsAndEditorsDelta`、`$acceptModelChanged`（数据来自 EditorDocumentModel.changes）、保存和脏状态变化、保存前钩子（`$participateInSave`）。
   - **换行符映射**：BaoCode 保留混合 CR/LF，而 ext host 的镜像模型只有单一换行符。必须有一层双向映射，并配随机对照测试。
   - versionId 严格递增，与 `$tryApplyEdits` 的版本检查对齐。
   - 列位置按 UTF-16 计算；超过 50MB 的文件不同步；languageId 一律使用 VS Code 的 id。
   - `$tryApplyWorkspaceEdit` 和 `$tryApplyEdits` 落到 IdeWorkspace，变更再回流给 ext host。
3. **语言功能**：
   - 移植 `languageFeatureRegistry.ts` 和 `languageSelector.ts`。lib/ide/lsp_ui/ 继续只依赖 `LanguageFeatures` 接口，改由这个注册表提供实现。lsp_ui 里以 Lsp 开头的类型名可以保留，以减少改动。
   - 覆盖上游全部 provider：补全（含 resolve、提交字符、片段）、hover、签名帮助、定义/类型定义/实现/声明/引用、文档高亮、文档与工作区符号、重命名、格式化（文档、选区、输入时）、代码操作与快速修复、CodeLens、InlayHints、文档链接、颜色、折叠、选区扩展、语义 token、调用层级、类型层级、内联补全（ghost text）、链接编辑。
   - 实现插件常调的 `_executeXxxProvider` 等 API 命令，清单见上游 extHostApiCommands.ts。
4. **诊断**：`$changeMany` 和 `$clear` 接到 Problems 面板和编辑器波浪线；同时通过 `$acceptMarkersChange` 回传给 ext host。
5. **命令、菜单、快捷键、上下文键**：
   - 命令进 IdeCommand 和命令面板；`contributes.menus` 的 when 条件复用 lib/keybindings/when_expression.dart；`contributes.keybindings` 进 KeybindingService。
   - 支持 `setContext`；插件调用的内置命令（`vscode.open`、`vscode.diff`、`workbench.action.*`、`editor.action.*` 等）建映射表。
   - 有插件注册了 `type` 命令时（例如 VSCodeVim），编辑器的键入改走这个命令。
6. **配置**：
   - 汇总所有插件的 `contributes.configuration` 和 `configurationDefaults`，生成 IConfigurationInitData，配置变化时推送。
   - 插件写设置时，用现有的 jsonc 工具写回 settings.json。
   - 设置界面按 schema 自动生成插件设置项。
7. **工作区与文件**：
   - findFiles 和 findTextInFiles 接现有搜索；文件监视事件通过 `$onFileEvent` 推送。
   - 文件操作参与者 `$onWill/DidRunFileOperation` 要支持，例如重命名文件时 TS 自动更新 import。
   - 工作区信任：首次打开时提示，受限模式按上游语义处理。
8. **窗口与 UI**：
   - 通知（含模态对话框和按钮）、Progress、QuickPick 和 InputBox（完整对象 API）、状态栏项。
   - 输出通道：ext host 把内容写到日志文件，Dart 跟踪读取，显示在输出面板。
   - Storage（globalState、workspaceState）、Secrets（macOS Keychain、Windows 凭据管理器）、剪贴板、`openExternal`。
   - 注册 `baocode://` URL scheme，交给插件的 UriHandler 处理，用于 OAuth 回调。
   - Authentication 接口，内置的 github-authentication 扩展要能完成登录。
9. **视图**：
   - `viewsContainers` 映射到活动栏和侧栏；`views` 用 TreeView 实现（`$getChildren`、刷新、reveal、消息、badge、复选框、拖放、展开/选中/可见性回传）。
   - TreeItem 图标：`$(codicon)` 用已有的 codicon 字体，svg/png 用 flutter_svg。
   - 支持 `view/title` 和 `view/item/context` 菜单，以及 `viewsWelcome`。
   - 文件装饰（资源管理器里的 badge 和颜色）。
10. **编辑器装饰**：在 packages/bao_editor 中实现 TextEditorDecorationType 的完整渲染选项：
    - 背景、边框、颜色、下划线、整行、gutter 图标、概览标尺、light/dark 变体、ThemeColor；
    - 行尾的 before/after 文本，以及行中间插入文本（与 InlayHints 共用同一套实现）；
    - CodeLens 用 view zone 实现。
11. **终端与任务**：
    - 终端创建、sendText、伪终端（Pseudoterminal）、EnvironmentVariableCollection（Python 靠它激活虚拟环境）、shell integration 事件，后端接 lib/ide/terminal 和 bao_pty。
    - 任务：provider、shell/process/customExecution 三种执行方式、problemMatchers、tasks.json、依赖任务。
12. **SCM**：
    - 内置 git 扩展必须运行，GitLens 等插件依赖它的 API。它注册的 SCM provider 接收但不显示，继续使用 BaoCode 自己的 Git 视图。
    - 其他插件注册的 SCM provider 正常显示。
13. **调试**（`MainThreadDebugService` 加 DAP）：
    - 移植上游 debug model、session、rawDebugSession 的核心逻辑。
    - 调试适配器由 ext host 提供，包括 executable、server、inline 三种。
    - UI 包括：运行和调试视图、launch.json（按 `contributes.debuggers` 的 configurationSnippets 和 initialConfigurations 生成，并做变量替换）、调试工具栏、断点（条件断点、命中次数、日志点、函数断点、异常断点、数据断点）、调用栈（多线程）、变量、监视、调试控制台 REPL（含补全）、inline values、preLaunchTask/postDebugTask、compound 配置、attach、重启、热重载按钮。
    - 插件侧 `vscode.debug` 的全部事件和 API 都要支持。
14. **测试 API**：TestController 接一个测试资源管理器树视图，支持运行、调试、结果展示、跳转到失败位置。
15. **不做 Webview，按以下方式降级**：
    - `$createWebviewPanel`：接受后立即回调 `$onDidDisposeWebviewPanel`，同一个插件只提示一次“此功能需要 Webview，BaoCode 不支持”。
    - `$registerWebviewViewProvider` 和 `$registerCustomEditorProvider`：接受注册，但不显示、不使用。
    - `$postMessage`：返回 false。
    - 内置 markdown 扩展的预览命令，改为打开 BaoCode 自己的 Markdown 预览。
    - Notebook 和 notebook renderer 也属于不支持范围，按同样方式处理。
    - 安装和导入时做能力分析：静态检查 manifest 和主入口 JS 中的 webview 相关调用，在扩展列表上标注“完全可用 / 部分可用 / 需要 Webview”。

## 六、扩展视图与插件来源

- 用 Open VSX 插件市场重写 lib/ide/extensions/ 的视图：搜索、详情（README、更新日志、贡献点、能力分析结果）、安装、卸载、启用/禁用（全局和按工作区）、更新、预发布版本、版本选择。
- **拖入**：
  - `.vsix`：先预览 manifest（名称、版本、engines 兼容性、能力分析），确认后调用 Management 通道的 install。
  - 含 package.json 的文件夹：作为开发模式加载，放进 extensionDevelopmentLocationURI 并重启 ext host。
  - 拖放复用 ide_workbench.dart 里已有的处理。
- **导入**：扩展 lib/keybindings/vscode_import.dart 的 VsCodeInstalls，扫描 ~/.vscode、~/.vscode-insiders、~/.cursor、~/.windsurf、~/.vscode-oss 下的 extensions 目录，逐个处理：
  - Open VSX 上有的：重新下载对应平台的包；
  - 微软闭源插件（Pylance、cpptools、C# Dev Kit、Remote-*、Copilot 等）：提示许可限制并推荐替代品，例如 basedpyright、clangd；
  - `anysphere.*` 直接跳过。
  - 同时导入属于这些插件的 settings 配置项，最后给出导入报告。
- **推荐**：打开某种文件、但没有任何插件提供该语言功能时，推荐 Open VSX 上的对应插件（Python、Go、Rust、C/C++、Java 等），取代原来 mason 的推荐安装。

## 七、删除现有 LSP 体系

在插件路径已经覆盖原有能力之后再删除，删除前用 grep 确认没有其他地方引用：

- lib/ide/lsp/ 下的 catalog、install（mason）、packs、lsp_client、lsp_manager、lsp_process*、json_rpc 等；
- assets/lsp/；tool/generate_lsp_languages.mjs 和 generate_mason_registry.mjs；
- lib/remote/remote_lsp.dart，以及 packages/bao_remote 里的 LSP 部分（lsp.dart、lsp_install.dart、src/lsp/、server_lsp.dart，以及协议中对应的方法）；
- language-packs 和 lsp.json 的读取逻辑。

同步更新：README、packs/README.md（删除）、docs/ssh-remote.md 的语言服务器章节、PARITY.md 中 Extensions 和 LSP 的条目、pubspec 的 assets 列表、l10n 文案（中英文都要改）。

Web 构建继续走 stub：不支持插件，也不能编译失败。

## 八、远程项目（SSH）

- 远程主机在需要时下载对应 linux 或 darwin 的运行时。远端能联网就直接从 dl 下载；不能联网就由本机下载后上传，复用 docs/ssh-remote.md 中 Claude Code 的“本机下载再上传”逻辑。
- 由 bao_remote 的服务端在远端启动 reh，再通过已有 SSH 通道转发端口。
- 按 extensionKind 分流：`workspace` 类插件在远端运行，`ui` 类插件在本地运行，遵循上游 extensionManifestPropertiesService 的规则。

## 九、验收标准（全部满足才算完成）

每一条都要按第十节“验证方式”留下自动化证据。只能手动验证的部分写进手动检查清单，不能写成“已验证可用”。

1. 全新数据目录首次打开一个 TS 项目：自动下载运行时并显示进度；内置 TS 扩展提供补全、hover、跳转、引用、重命名、诊断、格式化、快速修复、CodeLens、InlayHints。
2. 从 Open VSX 安装后实际可用：
   - Python（ms-python.python 加 basedpyright）
   - rust-analyzer、Go、clangd
   - ESLint、Prettier（保存时格式化）
   - GitLens（blame、CodeLens、hover、树视图）、Error Lens、Todo Tree、Code Spell Checker
   - VSCodeVim、Docker
   - 至少一个主题和一个图标主题
3. `.vsix` 拖入安装、从 VS Code 或 Cursor 导入、启用/禁用、卸载、更新都正常；重启应用后状态保留。
4. 调试：
   - Node.js（内置 js-debug）：launch 和 attach；
   - Python（debugpy）、Go（delve）、Rust/C++（CodeLLDB）：至少能 launch。
   - 断点各种类型、单步、调用栈、变量、监视、调试控制台、preLaunchTask 全部可用。
5. 依赖 Webview 的插件不崩溃、提示清晰，非 Webview 部分照常工作。
6. SSH 远程项目上，第 1、2、4 项中至少 TS、Python、Node 调试可用。
7. ext host 被强制杀死后能自动恢复；断网时已下载的运行时照常使用；下载中途中断后再次触发能成功完成。
8. LSP 相关代码和资源全部移除；`flutter analyze --no-pub` 无问题；相关测试全部通过。
9. 文档：
   - `docs/extensions.md`：架构、协议、运行时版本与发布流程、升级 VS Code 版本的步骤、数据目录、故障排查；
   - 自动生成的 `docs/extensions/EXTHOST_PARITY.md`：已实现和未实现的方法、不支持的能力。

## 十、工作方式与约束

- **本目标文件**：位于主工作树的 docs/extension-host-goal.md，未提交。不要把它复制到 worktree 或提交到分支，否则合并时会和主工作树里这个未跟踪文件冲突。需要时按绝对路径 /Users/leokun/Documents/kun6687/monad/docs/extension-host-goal.md 读取。
- **使用 worktree 开发**：执行 `git worktree add ../monad-exthost -b feat/extension-host main`，所有开发都在 /Users/leokun/Documents/kun6687/monad-exthost 进行。不要在主工作树 /Users/leokun/Documents/kun6687/monad 上开发：那里有我未提交的改动（lib/ide/git/*、lib/chat/side_panel/* 等），**禁止 stash、reset、checkout、clean 或以任何方式改动这些文件**。
- 小步提交，提交信息沿用仓库风格，例如 `feat(extensions): …`、`fix(exthost): …`，英文书写。开发过程中定期把 main 合并进本分支，减少最终冲突。
- **测试**：遵守 CLAUDE.md，改了什么只跑相关测试，不要随便跑全量测试。
  - 协议层、映射层用固定字节样本和随机对照做单元测试；
  - 需要真实 Node 运行时的集成测试统一打 `exthost` tag，不进默认测试集，手动用 `--tags exthost` 运行；
  - 测试用的插件 fixture 放在 test/fixtures/extensions/。
  - 合并前跑一次 `flutter analyze --no-pub`，再跑一次全量测试。
- 构建验证：完成后执行 `flutter build macos --debug`，必须成功。
- **验证方式**（agent 无法操作桌面 GUI，验证全靠以下手段）：
  1. **自动化测试是主力**：第九节每一条都要有对应的自动化测试，测试名或注释里注明对应第九节哪一条。
     - 用 widget 测试或 `integration_test`（`flutter test integration_test -d macos`，真窗口、真引擎、代码驱动），启动真实的 reh、ext host 和 Open VSX 上的真实插件，打 `exthost` tag。
     - 驱动真实的 UI 组件树，例如点“安装”、展开 TreeView、在编辑器里触发补全、设置断点并启动调试，再断言状态和语义树（复用 test/semantics_tree.dart）。
     - 需要 `integration_test` 时，在 pubspec 的 dev_dependencies 里加上它，目录用 integration_test/。
  2. **离屏截图**：关键界面用 `matchesGoldenFile` 或 `RenderRepaintBoundary.toImage` 渲染成 PNG，放在 `build/exthost-screens/`，不提交。agent 要自己打开截图逐张核对（布局、编辑器装饰、行尾文字、InlayHints、CodeLens、TreeView、调试面板、扩展视图、下载进度），发现问题就修。至少包括：扩展视图（列表、详情、能力标注）、运行时下载中、TS 补全和 hover、GitLens blame 加 Error Lens 行尾文字、Todo Tree、断点命中时的调试视图、Webview 降级提示。
  3. 不要用 `screencapture`、`osascript`、模拟鼠标键盘这类方式操作我的桌面。
  4. **手动检查清单**：维护 `docs/extensions/MANUAL_CHECKLIST.md`，列出代码驱动不了、或驱动了也不等于真实可用的项，每项写明操作步骤和预期结果。至少包括：
     - 从 Finder 把 `.vsix` 真实拖进窗口安装；
     - 输入法（IME）在插件补全、QuickPick、InputBox 中的表现，原生菜单，系统对话框；
     - GitHub 登录：浏览器 OAuth 完成后，系统跳回 `baocode://` 的回调；
     - 首次写入 Keychain 时的系统授权弹窗；
     - 全新用户首次打开项目时运行时自动下载的完整体验；
     - Windows 上第九节的主要条目；
     - 大项目里的流畅度：键入、补全、滚动、调试单步时是否卡顿或闪烁。
- **进度文件**：在 worktree 里维护 `docs/extensions/PROGRESS.md`，记录已完成项、当前在做什么、遇到的偏差和决定、下一步。上下文被压缩或会话重启后，先读这个文件再继续。
- 遇到上游行为与本文件描述不一致时，以所钉版本的源码为准，并记进 PROGRESS.md。不要为了凑覆盖率写空实现；做不到的写进 PARITY 文档并说明原因。
- **完成后合并**：
  1. 确认第九节中能自动化的部分全部通过，只能手动验证的部分已写进 MANUAL_CHECKLIST.md；
  2. 在主工作树执行 `git merge --no-ff feat/extension-host`；
  3. 如果 git 因为我未提交的改动拒绝合并，或者出现冲突，**停下来报告**，不要自行处理我的改动；
  4. 合并成功后不要 push，删除 worktree 前先确认分支已经合并。
- **最终报告**：说明完成情况，并逐条列出第九节的验收结果，每条标明属于以下哪一类：
  - “自动化已验证”：附上测试文件路径和截图路径；
  - “待手动验证”：指向 MANUAL_CHECKLIST.md 中的对应项；
  - “未完成”：说明原因。

  另外列出：未支持的能力清单、运行时版本和 R2 文件清单（是否已上传）、我需要手动做的事情。
