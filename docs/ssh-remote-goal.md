# Goal：BaoCode 支持 SSH 远程项目（Claude Code 在远端运行）

## 背景
BaoCode 是 Flutter 桌面应用（macOS / Windows），给 Claude Code 做 UI，并自带 IDE（文件、搜索、git、终端、LSP）。
现在所有能力都只针对本机：各服务通过条件导入在编译期选 `*_io.dart` 或 `*_stub.dart`，`Project` 只有 `name + path`（lib/workspace/workspace.dart:31）。
目标：用户能打开 `ssh 主机 + 远端目录` 作为项目。Claude Code、文件、git、搜索、终端、语言服务器都在远端执行，UI、凭据、模型配置留在本机。

## 核心架构（必须遵守）
1. **远端 server**：新建纯 Dart 包 `packages/bao_remote`（不能依赖 Flutter），包含协议和 `bin/baocode_server.dart`。
   用 `dart compile exe --target-os linux --target-arch {x64,arm64}` 交叉编译，产物随 App 一起打包（改 tool/build_macos.dart、tool/build_windows.dart、tool/baocode.iss）。
   另外新增 tool/build_remote_server.dart 负责编译。
2. **复用现有实现**：下面这些 io 实现基本是纯 Dart，把 server 需要的部分抽进 `packages/bao_remote`（或新建一个纯 Dart 包），App 里原有的公开 API 保留为薄封装，保证现有测试不变：
   - lib/ide/file_service_io.dart
   - lib/ide/git/git_service_io.dart
   - lib/ide/search/text_search_io.dart
   - lib/kernel/claude_code/process_transport_io.dart
   - lib/kernel/claude_code/claude_storage_io.dart
   - lib/chat/review/review_store_io.dart
   - lib/ide/terminal/pty_io.dart（依赖 packages/bao_pty，它运行时不依赖 Flutter）
   - lib/ide/lsp/lsp_process_io.dart
   - lib/ide/lsp/install/ 下的执行部分（install_io.dart、archive.dart、mason_server_provider.dart 里下载、解压、执行命令、链接的逻辑）

   遇到 `package:flutter/foundation.dart` 的 `visibleForTesting`，改用 `package:meta`。
3. **连接**：调用系统的 `ssh`（Windows 用 System32\OpenSSH\ssh.exe，找不到就给出明确报错），不要引入 Dart SSH 库，这样能复用 ~/.ssh/config、ProxyJump、agent、known_hosts。
   - 参数：`-T -o BatchMode=yes -o ServerAliveInterval=15`
   - 启动流程：远端先跑一段引导脚本：`uname -sm` 判断平台，检查 `~/.baocode-server/<版本>/baocode-server`，不存在就通过 stdin 上传（先写临时文件，再 chmod、mv，保证原子替换），然后 exec。
   - **每个主机只开一条 ssh 连接**，该主机上的所有项目共用。
4. **协议**：JSON-RPC 2.0，每行一个 JSON，走 server 的 stdin/stdout；stderr 只写日志。
   - 先做 `initialize` 握手，带协议版本，server 同时回报远端平台和架构；版本不匹配就重新部署 server。
   - 流式数据（文件监听、搜索结果、PTY 输出、Claude 消息、LSP 进程的 stdin/stdout/stderr 字节、安装进度、端口转发数据）用带 streamId 的 notification；二进制用 base64。
   - 支持 `$/cancel` 取消请求。
   - 可以参考 lib/ide/lsp/json_rpc.dart。
5. **Host 抽象**：在 App 侧新增 `ProjectHost` 接口，有 `LocalHost`（包装现有实现）和 `SshHost`（走 RPC）两个实现。它提供：
   - 文件服务（实现 `IdeFileService`），包括 `readFileBytes`、`watchDirectory`
   - 项目文件遍历（远端在 server 侧遍历，不能用 `list()` 逐层递归，见 file_service.dart 里 `listProjectFiles` 的 `is LocalIdeFileService` 判断）
   - `IdeGitRunner` / `IdeGitWatcher`、`IdeTextSearch`
   - 启动 Claude（返回 `ClaudeCodeTransport`）、会话目录与历史（替代 `ClaudeStorage`，见 lib/kernel/kernel_registry.dart）
   - `openReviewStore`、启动 PTY
   - LSP 相关：`LspProcessStarter`、`LspDirectoryWatcher`、路径存在判断和目录列举、语言服务器的安装与定位、发给语言服务器的 processId
   - `path.Context`：远端一律用 `p.posix`，Windows 客户端连 Linux 时尤其要注意

   需要替换的调用点：lib/ide/ide_workbench.dart、lib/ide/ide_workspace.dart、lib/ide/search/ide_search_view.dart、lib/ide/lsp/lsp_manager.dart、lib/kernel/kernel_registry.dart、lib/workbench.dart、lib/main.dart 等，用 grep 找全。
6. **项目身份**：`Project` 增加 host 字段（本机，或 ssh 别名），相等判断改为 (host, path)。持久化要兼容旧数据（旧记录一律视为本机）。侧边栏和标题显示主机标记。

## Claude Code 在远端
- 用 server 侧的 cli_locator 查找 claude。找不到时 UI 给出安装指引（显示官方安装命令，用户确认后在远端执行）。**不要**把 Claude Code 二进制打包进 App。
- `ClaudeLaunch` 的参数和 env 通过 RPC 传给 server，由 server 启动进程。**凭据只放在进程 env 里，绝不写入远端磁盘。**
  `settingsPath` 对应的设置优先用 `--settings` 传 JSON 字符串；必须用文件时，权限设为 0600，进程退出后删除。
- **模型 proxy 转发**：如果 env 里的 `ANTHROPIC_BASE_URL` 指向本机（localhost 或 127.0.0.1），就在 RPC 层做反向端口转发：server 在远端 127.0.0.1 监听一个随机端口，TCP 流经 RPC 送回客户端，再由客户端连本地 proxy。然后把 env 里的地址改写成远端端口。不依赖 ssh -R，Windows 上也能用。非本机地址原样透传。
- 会话列表和历史读远端的 `~/.claude`（遵守 `CLAUDE_CONFIG_DIR`）。会话标题用的 Haiku 调用（lib/kernel/claude_code/claude_haiku_io.dart）同样在该项目所在的 host 上执行。
- **Keep/Undo 审阅**：shadow git 仓库放在远端 `~/.baocode-server/data/checkpoints/`，布局和本机一致。远端没有 git 时，像现在一样优雅禁用。**绝不读写用户项目的 .git，Keep 永远不 stage。**

## LSP 在远端
- **分工**：LSP 协议客户端（lsp_client.dart、lsp_manager.dart、json_rpc.dart、lib/ide/lsp_ui/）留在 App。server 只负责启动语言服务器进程，并转发它的 stdin/stdout/stderr 字节。
  App 侧用 RPC 流实现 `LspProcess` 接口（lib/ide/lsp/lsp_process.dart）：`pid` 是远端 pid，`kill(force:)` 和 `stopRequested` 语义与本机一致。
- **processId**：现在发给语言服务器的是本机 pid（`lspClientProcessId`），远端要改发 server 自己的 pid。server 随连接断开而退出，语言服务器也就跟着退出。
- **URI 与路径**：远端的 file URI 和路径互转一律按 POSIX 处理（`p.posix.toUri`、`Uri.file(path, windows: false)`、`toFilePath(windows: false)`），Windows 客户端上也一样。要排查的地方：
  - lsp_client.dart 里的 `_rootUri`
  - lib/ide/lsp_ui/ 里的文档 URI、诊断
  - 跳转到定义或引用：目标在项目外时（远端的标准库、依赖缓存，如 ~/.cargo、/usr/include），要通过远端文件服务以只读方式打开
- **同步接口要改成异步**：`lspPathExists`、`lspListDirectory` 是同步函数，LspManager 用它们找项目根标记。远端没法同步调用，所以把 LspManager 的这两个注入点改成异步（或由 server 端做根目录探测），本机行为保持不变。
- **递归监听**：先确认 Dart 的递归 `Directory.watch` 在 Linux 上的实际表现。如果不支持或不可靠，就在 server 端按目录逐个 inotify 监听，跳过 `ideIndexExcludedDirectories`。达到 `fs.inotify.max_user_watches` 上限时降级并写日志，不能崩溃。文件监听和 git 监听共用这套实现。
- **安装语言服务器**：
  - mason_registry.dart 通过 `rootBundle`（Flutter）加载 registry，这部分留在 App。
  - App 用远端平台（来自 initialize，替代 mason_server_provider.dart 里的 `Abi.current()`）计算 `MasonInstallPlan`，把计划交给 server 执行（下载、解压、npm/pip/go/cargo 等命令、链接），进度通过流回传。
  - 远端安装目录：`~/.baocode-server/data/lsp/`。`which` 和定位用远端登录 shell 的环境。
  - UI 里的安装状态按 host 区分（例如"已安装于 dev-box"）。
  - 远端无法联网时给出明确报错。
- **用户设置**：用户的 LSP 设置（lib/ide/lsp/packs/lsp_user_settings.dart、lsp_files）存在本机，同样作用于远程项目；设置里写的可执行文件路径在远程项目里按远端路径理解。
- **生命周期**：断线时语言服务器随 server 一起结束。重连后，LspManager 重启语言服务器，并对所有打开的文档重新发送 didOpen，内容取编辑器当前文本（包括未保存的修改）。尽量复用现有的崩溃重启逻辑。

## 范围
**做**：
- 连接、部署、协议
- 远程文件增删改查和冲突检测、文件监听、Quick Open 遍历、文本搜索、图片预览
- git 和 SCM 视图
- Claude Code 会话（新建、resume、历史列表、标题）
- Keep/Undo、终端（远端默认 $SHELL，shell integration 脚本由 server 自带）
- 远程 LSP（含语言服务器的安装、定位、跳转到项目外文件）
- 模型 proxy 转发、项目持久化
- 连接状态 UI 和重连

**不做**（相关入口在远程项目里隐藏或禁用，并给出提示）：
- Codex
- 远端是 macOS 或 Windows
- 密码或 2FA 输入（BatchMode 失败时提示配置密钥或 ssh-agent；host key 未知时提示先在终端执行一次 `ssh <别名>`）
- 断线后进程保活
- 在 Finder 中显示、用外部编辑器打开、拖入本地文件
- 远端断网时由本机下载语言服务器再上传

## UI
- 欢迎页和命令面板加"打开远程项目"：
  - 主机输入框：从 ~/.ssh/config 读取 Host 列表作为建议，排除通配符项，也允许手输 `user@host`
  - 连接后用 RPC 浏览远端目录，选择文件夹
- 状态栏显示 `SSH: <别名>` 和连接状态（连接中 / 已连接 / 已断开）。
- 断线后：
  - 运行中的会话标记为已结束并显示原因
  - 文件操作报错
  - 按指数退避自动重连，同时提供手动重连按钮
  - 重连后会话可以通过 resume 继续，语言服务器自动恢复
- 客户端断开时，server 结束它启动的所有子进程（Claude、PTY、语言服务器、安装命令）并退出。退出确认（lib/workspace/quit_confirmation.dart）要把远端运行中的会话和终端算进去。
- 新增的文案同时加到 lib/l10n/app_en.arb 和 app_zh.arb，然后运行 `flutter gen-l10n`。

## 建议顺序（每步都要能编译、相关测试通过）
1. 引入 `ProjectHost`，只接 `LocalHost`，`Project` 加 host 字段，LspManager 的同步注入点改成异步，做到行为完全不变。
2. 建 `packages/bao_remote`：协议、server 分发器、抽出的纯 Dart 实现。
3. `SshHost` 实现：文件、监听（含 Linux 递归监听）、遍历、搜索、git、图片字节。
4. Claude 启动、会话目录、端口转发、审阅仓库。
5. PTY。
6. LSP：进程转发、URI 处理、项目外文件、安装计划在远端执行、重连恢复。
7. 连接管理、部署引导、UI、l10n、打包脚本。

## 测试（硬性约束）
- **绝对不要运行真实的 Claude Code、Codex、真实的语言服务器或真实的 ssh 连接**，只用 mock 和 fixture（参考 lib/kernel/claude_code/mock_claude_code_transport.dart、test/fixtures）。不要运行带 `e2e`、`lsp-smoke` tag 的测试。
- 主力测试：在进程内用一对内存流把 client 和 server 分发器连起来，对临时目录测：
  - 文件增删改查和冲突
  - 监听（含递归）、搜索
  - git（临时仓库）
  - 审阅快照和 diff
  - 用假可执行文件模拟 Claude 的 stream-json
  - 端口转发（本地 echo server）
  - 取消请求、版本不匹配
- LSP 测试：
  - 写一个纯 Dart 的假语言服务器 fixture（只实现 initialize、didOpen 后发 publishDiagnostics、definition），经 server 转发后验证 LspProcess 的读写、退出和 kill
  - Windows 客户端连 POSIX 远端时的 URI 和路径互转
  - 异步根目录探测
  - 以 linux 平台生成的安装计划由 server 执行：用本地 fixture 归档文件或本地 HTTP server，不联网
  - 重连后重新发送 didOpen，内容包含未保存的修改
- 另外覆盖：引导脚本和 ssh 参数生成、ssh config 解析、`Project` 持久化的旧数据兼容、远程项目对话框的 widget 测试（用 fake host）。
- 只运行和改动相关的测试，**不要跑全量测试**（太慢）。`flutter analyze` 必须无报错。

## 工作方式约束
- 工作区是共享的，别人正在同时修改这份 checkout。**在新的 git worktree 和分支上开发**，不要碰、不要提交、不要 stash 或 reset 主工作区里别人的改动。
- 代码风格和周边保持一致：注释密度、`///` 文档注释的写法、命名、`*_io.dart` / `*_stub.dart` 的分层方式。
- 在自己的分支上分步提交，commit message 末尾加：
  `Co-Authored-By: BaoCode <noreply@baocode.dev>`

## 合并进 main（完成并通过测试后）
main 的工作区里有别人未提交的改动，`git merge` 会拒绝，**不要 stash、不要 reset --hard**：
1. 确认 main 的 HEAD 仍是本分支的基点（不是的话，先在分支上 rebase 到新的 main 并重新跑相关测试）。
2. 对双方都改过的文件（分支改了、main 工作区也有未提交改动），用三方 `git merge-file` 合进 main 的工作区文件；解决冲突，并确认合并期间文件没有被别人再次修改。
3. `git update-ref refs/heads/main <分支> <基点>`，然后 `git reset -q`（只重置 index）。
4. `git checkout <分支> -- <只属于自己改动或新增的文件>`，再运行 `flutter gen-l10n`。
5. 别人未提交的改动可能需要为本功能补一行（例如列出设置页的枚举），如有，要在汇报里说明。

完成后汇报：
- 做了什么、没做什么，以及原因
- 运行了哪些测试，结果如何（失败的要附上输出）
- 合并时处理了哪些文件、有哪些冲突
- 需要人工在真实环境验证的步骤：真实 ssh 主机、真实 Claude、真实语言服务器、Windows 客户端
