# SSH 远程项目

用 SSH 打开另一台机器上的项目，体验和 VS Code 的 Remote-SSH 一样：界面留在本机；文件、Git、搜索、终端、语言服务器和 Claude Code 都在远端主机上运行。本文说明它怎么工作、怎么构建和发布、出了问题怎么查，以及以后改代码时要注意什么。

- 远端要求：Linux x64 / arm64（glibc），能用密钥或 ssh-agent 免密登录
- 本机要求：系统自带的 OpenSSH 客户端（`ssh`）
- 代码：应用侧 `lib/remote/`，服务端和协议 `packages/bao_remote/`，构建工具 `tool/build_remote_server.dart`
- 测试：`test/remote/`

## 目录

1. [现状一览](#1-现状一览)
2. [用户看到的行为](#2-用户看到的行为)
3. [整体结构](#3-整体结构)
4. [一次连接的完整流程](#4-一次连接的完整流程)
5. [各功能怎么走到远端](#5-各功能怎么走到远端)
6. [远端的 Claude Code](#6-远端的-claude-code)
7. [远端主机上的文件](#7-远端主机上的文件)
8. [协议](#8-协议)
9. [构建与打包](#9-构建与打包)
10. [环境变量](#10-环境变量)
11. [测试](#11-测试)
12. [故障排查](#12-故障排查)
13. [真机验证清单](#13-真机验证清单)
14. [修改指南](#14-修改指南)
15. [已知限制与待办](#15-已知限制与待办)

---

## 1. 现状一览

| 项目 | 状态 |
| --- | --- |
| 连接、引导安装服务端、断线重连 | 已完成，有内存服务端的集成测试 |
| 文件、搜索、Git、终端 | 已完成 |
| 语言服务器（LSP） | 已完成：服务器在远端运行，客户端在本机 |
| Claude Code：对话、会话列表、标题、Keep/Undo、提交信息 | 已完成 |
| 远端没有 Claude Code 时自动安装 | 已完成：远端自己下载；远端不能上网时由本机下载后传上去 |
| 本机模型代理转发到远端 | 已完成 |
| 打开入口、状态栏、侧栏徽标、退出确认、中英文 | 已完成 |
| Windows 打包带上服务端 | 已完成：`tool/build_windows.dart` |
| macOS 打包带上服务端 | 写在 `tool/build_macos.dart` 里，**还没实际跑过** |
| Windows 客户端打开远程项目 | **有已知问题**：见第 15 节 |
| 真实主机端到端验证 | **未做**：见第 13 节 |

不在范围内：Codex、macOS/Windows 远端、密码和二次验证登录、在访达中显示、用外部编辑器打开、往远程项目里拖文件。

---

## 2. 用户看到的行为

### 2.1 打开远程项目

入口：

- 欢迎页（还没有项目时）的“打开远程项目...”按钮
- 命令面板：“打开远程项目...”（命令 id `baocode.remote.openFolder`），聊天布局和 IDE 都有
- IDE 起始页
- 新对话输入框上方的“在哪个文件夹中工作”菜单：远程项目单独列在小字“远程”（英文界面为“Remote”）分组下，每项下面写 `主机:路径`；分组最后是“打开远程项目...”，选好文件夹后，这个新对话直接在那个远程项目里开始（`lib/workspace/new_chat_folder_bar.dart`）

流程（都在同一个快速选择框里完成）：

1. **选主机**：列出 `~/.ssh/config` 里的 `Host`（会跟着 `Include` 读，带通配符的条目不列），已连上的主机会标出来。也可以直接输入 `user@host`、`host:2222` 这类地址；含空格或以 `-` 开头的输入会被拒绝，防止把输入当成 ssh 参数。
2. **连接**：显示“正在连接 xxx...”。失败时显示原因、ssh 的最后一行输出和“重试”。
3. **选文件夹**：从远端的家目录开始浏览，可以“打开此文件夹”、进入子文件夹、回到上级，也可以直接输入以 `/` 或 `~` 开头的路径跳过去。
4. 打开后，这个项目和本地项目一样出现在侧栏里，下次启动还在。

### 2.2 远程项目的样子

- **侧栏**：项目名旁边有一个远程图标和主机名，悬停时显示远端路径和“位于 xxx（通过 SSH）”。
- **窗口标题**：`项目名 [SSH: 主机]`。
- **IDE 状态栏最左边**：

| 显示 | 含义 | 点击 |
| --- | --- | --- |
| `SSH: dev` | 已连接 | — |
| `SSH: dev（正在连接...）` | 第一次连接中，悬停显示当前步骤 | — |
| `SSH: dev（正在重连...）` | 断线后等待重连 | 立即重连 |
| `SSH: dev（已断开）`（红色） | 连接失败，且不会自动重试 | 重新连接 |
| `SSH: dev（正在安装 Claude Code 45%）` | 正在往这台主机装 Claude Code | — |

### 2.3 断线与重连

- 断线后马上重连一次；之后等待时间按 1、2、4、8… 秒递增，最长 1 分钟。
- **不会自动重试的失败**：认证失败、主机密钥未知或改变、远端系统不支持、本机没有 ssh。这些自动重试也没用，只能修好后点状态栏重连（或在打开流程里点“重试”）。
- **重连后自动恢复的**：文件和 Git 的监听（恢复后会先通知一次“可能变了”，界面会刷新）；语言服务器重启，并把打开的文件（包括未保存的修改）重新同步过去。
- **重连后不会恢复的**：断线那一刻在远端运行的进程都会结束，因为 sshd 断开会话时服务端会结束它启动的所有进程。
  - Claude Code 的对话会显示“The connection to the remote host was lost.”，下次发消息时会接着原会话继续（resume）。
  - 终端会退出。

### 2.4 退出确认

退出时，如果远端有正在运行的 Claude Code 会话或终端，确认框里会多一句“远程主机上的 N 个会话和终端也会结束。”。确认退出后，应用会先结束远端的会话，再关闭所有连接。

### 2.5 远程项目里不能用的功能

在 IDE 里对远程项目隐藏或禁用：移到废纸篓、用默认应用打开、在访达/资源管理器中显示。“用外部编辑器打开”按钮对远程项目只提供内置 IDE。

---

## 3. 整体结构

```
┌──────────── 本机（BaoCode 应用）────────────┐          ┌──────── 远端主机 ────────┐
│ 聊天 / IDE 界面                              │          │                          │
│   │  按项目路径找到所在主机                    │          │  ~/.baocode-server/      │
│   ▼                                          │          │    <VERSION>/baocode-server
│ ProjectHost.of(location)                     │   ssh    │        │                 │
│   ├─ LocalHost  → 本机文件/Git/终端/LSP        │  stdio   │        ▼                 │
│   └─ SshHost(dev) ── RemoteClient ───────────┼─────────┼──► RemoteServer          │
│         连接状态、重连、Claude 安装进度         │ JSON-RPC │     文件、Git、搜索、PTY  │
│                                              │          │     Claude Code 进程     │
│ LSP 客户端（本机）◄────── 语言服务器的字节 ─────┼─────────┼──── 语言服务器进程        │
│ 本机模型代理 ◄─────────── 端口转发 ────────────┼─────────┼──── 127.0.0.1:<随机端口>  │
└──────────────────────────────────────────────┘          └──────────────────────────┘
```

要点：

- **只有一条连接**：每台主机只建一条 `ssh` 连接，这台主机上所有项目、所有功能都复用它。
- **服务端是纯 Dart 程序**（`packages/bao_remote/bin/baocode_server.dart`），用 `dart compile exe` 交叉编译成 Linux 二进制，不依赖远端装任何东西。
- **项目的身份是 location 字符串**：远程项目的路径存成 `ssh://<主机>/<绝对路径>`，例如 `ssh://dev/home/me/app`、`ssh://me@10.0.0.2:2222/srv/x`。工作区里存的、侧栏显示的、会话归属的都是它。真正调用远端时再拆成“主机 + 远端路径”。
- **`bao_remote` 包不依赖 Flutter**，因为服务端要能用 `dart compile exe` 编译。本地项目用到的文件、Git、搜索、Claude 存储、终端 shell 集成等代码也放在这个包里，应用和服务端共用同一份实现。

### 3.1 文件

| 文件 | 作用 |
| --- | --- |
| `lib/remote/remote_location.dart` | `ssh://` 地址的解析和拼装：`isRemote`、`hostOf`、`pathOf`、`of`、`nameOf`、`pathsOf` |
| `lib/remote/project_host.dart` | `ProjectHost` 接口和 `LocalHost`：按 location 给出文件、Git、语言服务、终端 |
| `lib/remote/ssh_host.dart` | `SshHost`（一台主机的连接状态、重连、Claude 安装进度）和 `SshHosts`（全部主机） |
| `lib/remote/remote_services.dart` | IDE 各服务的远端实现：文件、Git、终端、LSP 进程，以及断线后自动重开的 `resilientStream` |
| `lib/remote/remote_lsp.dart` | 远端的 LSP 管理和 mason 安装 |
| `lib/remote/remote_claude.dart` | 远端的 Claude Code：启动、会话目录、历史、Haiku、模型代理转发 |
| `lib/remote/remote_claude_install.dart` | 远端没有 Claude Code 时的自动安装 |
| `lib/remote/remote_binaries.dart` | 找应用的服务端二进制：目录里的，或按 `servers.json` 下载的；开发时从源码编译 |
| `lib/remote/open_remote.dart` | “打开远程项目”的快速选择流程 |
| `lib/remote/remote_status.dart` | 状态栏的 `SSH: 主机`、聊天上方的 Claude 安装进度条 |
| `packages/bao_remote/lib/src/client/ssh_launcher.dart` | 调用 `ssh`：探测、上传、启动服务端；失败分类 |
| `packages/bao_remote/lib/src/client/ssh_config.dart` | 读 `~/.ssh/config` 里的主机 |
| `packages/bao_remote/lib/src/client/remote_client.dart` | 应用侧的类型化 RPC 调用 |
| `packages/bao_remote/lib/src/server/remote_server.dart` | 服务端的 RPC 处理 |
| `packages/bao_remote/lib/src/server/server_*.dart` | 服务端的终端、LSP、Claude 安装、Keep/Undo 快照、端口转发、流 |
| `packages/bao_remote/lib/src/claude/claude_release.dart` | 从官方地址下载 Claude Code 并校验；远端由 BaoCode 管理的那份 Claude |
| `packages/bao_remote/lib/src/protocol.dart` | 协议方法名、版本号和数据结构 |
| `packages/bao_remote/lib/src/rpc/` | JSON-RPC 收发（`rpc_peer.dart`），以及异常的跨端传递（`rpc_error.dart`） |
| `tool/build_remote_server.dart` | 编译 x64 和 arm64 两个服务端，生成 `VERSION`、两个 `.gz` 和 `servers.json` |

---

## 4. 一次连接的完整流程

代码：`SshLauncher.connect`（`ssh_launcher.dart`）、`SshHost._attempt`（`ssh_host.dart`）。

1. **找 ssh**：在本机 PATH 里找 `ssh`，找不到就是 `noSsh` 失败。
2. **找服务端二进制**：先找应用目录里的（见第 9 节）；安装包里只有 `servers.json` 时，第一次用到某个架构才从 dl.baocode.dev 下载；开发时没有就从源码编译。都没有就报错。
3. **探测**：执行 `ssh <参数> <主机> sh -s`，通过 stdin 送一段脚本，返回：
   - `uname -s` 和 `uname -m`：不是 Linux x64/arm64 就报 `unsupported`；
   - `~/.baocode-server/<VERSION>/baocode-server` 是否已经存在；
   - 远端有没有 `gzip`。
4. **上传**（只在远端还没有这个版本时）：经 ssh 的 stdin 发送二进制，有 gzip 时先压缩，先写到临时文件 `.upload-<随机串>`，`chmod 755` 后再改名就位。所以连接中途断开也不会留下半个文件。
5. **启动**：执行 `ssh <参数> <主机> ~/.baocode-server/<VERSION>/baocode-server`，之后这个进程的 stdin/stdout 就是 JSON-RPC 通道，stderr 只留最后 50 行，用来报错。
6. **握手**：发送 `initialize`，服务端回复 `RemoteHello`：协议版本、构建版本、平台（os/arch/libc）、pid、家目录、数据目录。协议版本不一致就断开。

ssh 参数固定为：

```
-T -o BatchMode=yes -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -o ConnectTimeout=20 -e none [-p <端口>] <目的地>
```

- `BatchMode=yes`：从不弹密码或主机密钥确认框，这类情况直接失败（`authentication` / `hostKey`）。所以必须先在终端里能 `ssh <主机>` 免密登录，并且主机密钥已经在 `known_hosts` 里。
- `ServerAliveInterval=15` 加 `ServerAliveCountMax=3`：约 45 秒内发现死连接。
- `-e none`：二进制数据里不处理转义字符。
- 其他配置（用户名、端口、跳板机 `ProxyJump`、身份文件……）都来自用户自己的 `~/.ssh/config`。

失败分类见 `SshFailure`：`noSsh`、`authentication`、`hostKey`、`unreachable`、`unsupported`、`server`。

---

## 5. 各功能怎么走到远端

总规则：**按项目的 location 找到所在主机**，用 `ProjectHost.of(location)` 或 `RemoteLocation.hostOf(location)`。IDE 和聊天内部用的是“主机上的路径”，服务对象在创建时就绑定了主机。

| 功能 | 远端怎么做 | 代码 |
| --- | --- | --- |
| 文件读写、列目录、新建/改名/复制/删除 | `fs/*` 方法 | `RemoteIdeFileService` |
| 文件监听 | `fs/watch` 流；断线后用 `resilientStream` 自动重开 | `remote_services.dart` |
| 快速打开的文件索引 | `fs/walk` | `IdeHostFiles.listProject` |
| 全文搜索 | `search/text` 流（服务端用和本地相同的搜索实现） | `IdeHostFiles.searchText` |
| 图片预览 | `fs/readBytes` | `IdeHostFiles.readBytes` |
| Git | `git/run` 在远端执行 git 命令；`git/watch` 监听仓库 | `remoteGitService` |
| 终端 | `pty/*`：远端开伪终端，shell 集成脚本也在远端注入（nonce 由应用生成，经环境变量 `VSCODE_NONCE` 传过去） | `remoteTerminalBackend` |
| 语言服务器 | 见下文 | `remote_lsp.dart` |
| Claude Code 对话 | `claude/start` 在远端启动 CLI | `RemoteClaudeTransport` |
| 会话列表、历史、删除 | `claude/projects`、`claude/read`、`claude/delete`，读的是远端的 `~/.claude` | `ClaudeCatalog`、`readClaudeHistory` |
| 自动起标题（Haiku）、提交信息 | 在远端运行 claude | `askRemoteHaiku` |
| Keep/Undo（改动审查） | `review/*`：影子 git 仓库放在远端的数据目录，不碰项目自己的 `.git` | `openReviewStore` |
| 用量提示 | `claude/usageOffBy` | `claudeUsageOffByAt` |

### 5.1 语言服务器

- **LSP 客户端留在本机**，服务端只负责启动语言服务器进程、转发它的 stdin/stdout 字节（`process/*`）。
- **processId** 告诉语言服务器的是服务端的 pid（`hello.pid`），服务端退出时语言服务器也会退出。
- **路径一律用 POSIX 格式**（`p.posix`），URI 是 `file:///home/...`。
- **项目根目录查找是异步的**：要逐级到远端看标记文件存不存在。
- **安装**：缺少的语言服务器用 mason 在远端安装，安装计划也由服务端计算（`lsp/install`，进度以流返回），装在远端数据目录的 `lsp/servers/` 下。同一台主机的同一个包同时只装一次。
- **重连后**会调用 `restartServers()`：重启语言服务器，并把打开的文件（含未保存的内容）重新发过去。

### 5.2 模型代理（端口转发）

如果会话用的是本机的模型代理（`ANTHROPIC_BASE_URL` 指向 `127.0.0.1` / `localhost` / `::1`），远端访问不到本机的地址。处理方式：

1. 应用请求服务端在远端监听一个随机端口（`tcp/listen`）；
2. 远端的连接经 `tcp/open`、`tcp/data` 转回本机代理的端口；
3. `ANTHROPIC_BASE_URL` 改写成 `http://127.0.0.1:<远端端口>/...`，路径保留。

同一条连接、同一个本机端口只转发一次；重连后会重新建立转发。不是本机地址的代理保持原样。

### 5.3 打开时就会连接

启动应用、载入工作区时，会去读远程项目的会话列表，所以**只要侧栏里有远程项目，启动时就会连这台主机**。连不上不影响本地项目。另外，只要存在远程项目，工作区就不会清理“已消失会话”的置顶和归档记录，避免远程会话还没列出来时被误删。

---

## 6. 远端的 Claude Code

### 6.1 找哪个 claude

服务端按这个顺序找（`ServerClaude.locate`）：

1. 远端环境变量 `BAOCODE_CLAUDE_PATH` 指定的路径（文件不存在就报错，不会去装）；
2. 用户自己装的：远端登录 shell 的 PATH，以及 `~/.claude/local/claude`、`~/.local/bin/claude`、`/opt/homebrew/bin/claude`、`/usr/local/bin/claude`；
3. BaoCode 自己装的那份：`~/.baocode-server/data/claude/` 里 `CURRENT` 指向的版本。

**优先用用户自己的**，因为他的登录状态、配置和版本都在那份上。

### 6.2 自动安装（像 VS Code 扩展那样）

开始对话时，如果远端上面三处都没有，服务端会抛出 `ClaudeNotInstalled`，应用随即自动安装（`installRemoteClaude`），装完重新启动对话。用户什么都不用做。

1. **远端自己下载**（`claude/install`，进度以流返回）：
   - 读 `https://downloads.claude.ai/claude-code-releases/stable` 得到版本号；
   - 读 `<版本>/manifest.json`，取出这个平台的 `checksum`（sha256）和 `size`。平台名是 `linux-x64`、`linux-arm64`，musl 系统是 `linux-x64-musl` 这类；
   - 下载 `<版本>/<平台>/claude`，边下载边算 sha256，大小和校验和都对上才安装；
   - 先写到 `.part-<版本>-<平台>`，`chmod 755`，再改名成 `claude-<版本>`，最后原子地更新 `CURRENT`，并删掉旧版本。
2. **远端不能上网时，由本机下载再传上去**：远端下载失败（`ClaudeDownloadFailed`）后，应用在本机下载同一个版本（同样校验），缓存在系统临时目录的 `baocode/claude-<版本>-<平台>`，同平台的其他主机可以复用；然后按每块 1 MB 用 `claude/upload` 传上去，服务端检查顺序、大小和校验和，都对了才安装。
3. **进度**：显示在 `SshHost.installingClaude`，对话框上方有进度条，IDE 状态栏也有。
4. **同一台主机同时只装一次**：几个对话同时启动也只下载一次。

**不碰用户自己的环境**：不改 PATH，不写 `~/.local/bin`、`~/.local/share/claude`，也不改 shell 配置文件。所以用这份 claude 时会设置 `DISABLE_AUTOUPDATER=1`，因为 claude 自带的自动更新会往 `~/.local` 里装东西。

**更新**：每次启动这份 claude 时，服务端在后台检查是否有新版（每天最多一次，用 `.checked` 文件的修改时间记录），有就下载安装，下次启动时生效。出错就静默放弃，第二天再试。

**装不上时**：报“无法在 xxx 上安装 Claude Code”，详情里写原因和手动安装命令 `curl -fsSL https://claude.ai/install.sh | bash`。

Haiku 起标题和提交信息**不会**触发自动安装，远端没有 claude 时它们就直接失败。

### 6.3 密钥不落远端磁盘

使用第三方模型服务时，会话的 settings 里带着 API key。处理方式：

- key **不放进命令行参数**，在远端用 `ps` 看不到。参数里去掉 `--settings`，把 settings 作为请求里的 `settings` 字段发给服务端。
- 服务端把它写进一个只有当前用户能读的临时文件（所在目录用随机名、权限 0700），再用 `--settings <文件>` 启动 claude；**进程一退出就删除这个文件**。
- 这个临时文件放在 `XDG_RUNTIME_DIR`（通常是 `/run/user/<uid>`，在内存里）。**远端没有 `XDG_RUNTIME_DIR` 时，会退回系统临时目录**，也就是会短暂落在磁盘上，进程退出后删除。
- 应用自己的模型相关环境变量会显式清空（`cleared`），避免远端 shell 里同名的变量干扰。

---

## 7. 远端主机上的文件

```
~/.baocode-server/
├── <VERSION>/                  每个应用构建一个目录，例如 1.0.0-1.a1b2c3d4e5f6
│   └── baocode-server          服务端二进制
└── data/                       服务端的数据目录（各版本共用）
    ├── checkpoints/            Keep/Undo 的影子 git 仓库
    ├── lsp/servers/            mason 装的语言服务器
    ├── claude/                 BaoCode 装的 Claude Code（只在用户自己没有时）
    │   ├── CURRENT             在用的版本号
    │   ├── claude-<版本>
    │   └── .checked            上次检查更新的时间
    └── claude-sessions.json    会话列表的缓存
```

- `VERSION` = 应用版本 + 两个二进制合起来的 sha256 前 12 位。所以同一个应用版本、源码不同的构建，也会是不同的目录。开发时从源码编译的版本叫 `dev-<源码哈希>`。
- 旧版本的 `<VERSION>/` 目录目前**不会自动清理**（见第 15 节）。
- 想彻底清掉：在远端 `rm -rf ~/.baocode-server`。下次连接会重新上传，影子仓库和 BaoCode 装的 claude 也会一起没掉。

---

## 8. 协议

- **传输**：服务端进程的 stdin/stdout，一行一条 JSON-RPC 2.0 消息（`RpcPeer`）。stderr 只用于日志。
- **版本**：`RemoteProtocol.version`（目前是 1），握手时检查。因为每个应用构建在远端都有自己的服务端目录，正常情况下版本不会对不上。
- **异常跨端传递**：服务端抛出的异常转成带 `data.type` 的错误（`RpcError.from`），应用侧再还原成同一种异常（`toException`）。例如 `IdeFileNotFoundException`、`IdeGitException`、`ClaudeUnavailable`、`ClaudeNotInstalled`、`ClaudeDownloadFailed`、`LspInstallException`。其他异常变成 `RemoteException`，只保留消息文本。
- **流**（监听、搜索、安装进度）：请求返回流 id，数据用 `stream/data` 通知发送，结束是 `stream/done` 或 `stream/error`，应用可以用 `stream/cancel` 提前结束。
- **进程**（Claude、语言服务器、命令）：`process/start` 返回 id 和 pid，输出用 `process/output`，退出用 `process/exit`。连接断开时，应用这边所有进程按退出码 `-1`（`RemoteProcess.lostExitCode`）处理。
- **字节**：用 base64 放在 JSON 里（`encodeBytes` / `decodeBytes`）。

方法分组（完整列表见 `protocol.dart`）：

| 分组 | 方法 |
| --- | --- |
| 握手 | `initialize`、`shutdown` |
| 文件 | `fs/list`、`read`、`write`、`create`、`rename`、`copy`、`delete`、`readBytes`、`walk`、`watch`、`stat`、`entries`、`realPath` |
| 搜索、Git | `search/text`、`git/run`、`git/watch` |
| 进程 | `process/start`、`run`、`write`、`closeStdin`、`kill`；通知 `output`、`exit` |
| Claude Code | `claude/start`、`locate`、`projects`、`read`、`delete`、`usageOffBy`、`install`、`upload` |
| 改动审查 | `review/open`、`review/call` |
| 终端 | `pty/start`、`write`、`resize`、`kill`、`profiles`；通知 `output`、`exit` |
| 语言服务器 | `lsp/locate`、`install`、`installed`、`uninstall` |
| 端口转发 | `tcp/listen`、`unlisten`、`open`、`data`、`close` |

---

## 9. 构建与打包

### 9.1 编译服务端

```sh
dart run tool/build_remote_server.dart              # 输出到 build/remote/
dart run tool/build_remote_server.dart --out <目录>
```

会生成 `baocode-server-linux-x64`、`baocode-server-linux-arm64` 和 `VERSION`。用的是 `dart compile exe --target-os linux` 交叉编译，在 macOS 或 Windows 上都能编出 Linux 二进制。版本号通过 `-Dbaocode.version=<pubspec 版本>` 传给服务端。

另外还会生成两个 gzip 后的 `baocode-server-linux-<arch>.gz`（约 3.3 MB，原文件约 8 MB），以及 `servers.json`：写明每个 `.gz` 的下载地址 `https://dl.baocode.dev/releases/remote/<VERSION>/<文件>`、大小和 SHA-256。

### 9.2 应用在哪里找服务端

按顺序（`bundledServerBinaries`），哪个目录里有合法的 `VERSION` 就用哪个。目录里有二进制本身就直接用（`DirectoryServerBinaries`）；只有 `servers.json` 就按需下载（`DownloadedServerBinaries`，见 9.3）：

1. 环境变量 `BAOCODE_REMOTE_SERVER_DIR`
2. macOS：`BaoCode.app/Contents/Resources/remote/`
3. 可执行文件旁边的 `remote/`（Windows 安装包）
4. 可执行文件旁边的 `data/remote/`
5. 当前目录下的 `build/remote/`
6. 可执行文件所在的、名为 `build` 的上级目录下的 `remote/`（debug 构建）

**都没有、但应用是从源码目录运行的**（`flutter run`）：第一次连接时会自动用 `dart compile exe` 编译远端需要的那个架构（`SourceServerBinaries`）。
- `dart` 的查找顺序：先找 `FLUTTER_ROOT/bin/dart`，再找登录 shell 的 PATH。
- 编译结果放在 `build/remote/dev/`，按源码哈希命名，改了 `packages/bao_remote` 下的代码会自动换新版本。
- 编译要几十秒，期间连接进度显示“Installing the BaoCode server”。

### 9.3 打包与按需下载

安装包**不带服务端二进制**，只带 `VERSION` 和 `servers.json`。两个二进制原本占 16 MB，大多数用户不连远程，而每台主机只需要其中一个架构。

- **打包**：`tool/build_macos.dart` 和 `tool/build_windows.dart` 先编译到 `build/remote/`（CI 里由单独的 `remote` 任务编译一次，并在 Docker 里的几个 Linux 发行版上各跑一遍 `tool/test_remote_server.sh`，两个脚本带 `--remote-built` 直接用它），再只把 `VERSION`、`servers.json` 放进 `BaoCode.app/Contents/Resources/remote/`（Windows 是 `<bundle>\remote\`），`.gz` 放到 `build/installers/remote/<VERSION>/`。
- **发布**：把 `build/installers/remote/<VERSION>/` 里的 `.gz` 上传到 `https://dl.baocode.dev/releases/remote/<VERSION>/`。**要在安装包发出去之前上传**，否则这个版本连不了远程（CI 会按这个顺序传，见 docs/release.md）。旧版本的目录要一直保留，因为装着旧版的用户还要下载。
- **下载**：第一次连某个架构的主机时，应用下载对应的 `.gz`，按 `servers.json` 校验大小和 SHA-256，存到数据目录的 `cache/remote-server/<VERSION>/`，之后照旧经 ssh 推送到主机（第 4 节第 4 步）。远端主机不需要能上网。下载完会删掉其他版本的缓存；同时连多台同架构的主机只下载一次。
- **安全**：`servers.json` 在安装包里，跟着应用一起签名，所以下载到的只能是这个版本编出来的那份；被替换的文件校验不过，连接报 `server` 失败。
- 下载失败或校验不过，连接失败，报错里带着下载地址；下次连接重试。

---

## 10. 环境变量

| 变量 | 在哪边 | 作用 |
| --- | --- | --- |
| `BAOCODE_REMOTE_SERVER_DIR` | 本机 | 指定服务端二进制所在目录（里面要有 `VERSION`，以及二进制或 `servers.json`） |
| `FLUTTER_ROOT` | 本机 | 开发时从源码编译服务端用哪个 `dart` |
| `BAOCODE_CLAUDE_PATH` | 远端（登录 shell） | 指定远端要运行的 claude；设置了就不会自动安装 |
| `XDG_RUNTIME_DIR` | 远端 | 存放带密钥的临时 settings 文件的目录（在内存里） |
| `DISABLE_AUTOUPDATER=1` | 远端（服务端自动设置） | 只对 BaoCode 装的那份 claude 设置 |
| `VSCODE_NONCE` | 远端（服务端自动设置） | 终端 shell 集成用的 nonce |

远端进程的环境取自远端用户的**登录 shell**（`ClaudeEnvironment.of()`），所以写在 `~/.profile`、`~/.bashrc`、`~/.zshrc` 里的 PATH 都能生效。

---

## 11. 测试

**规则：不要运行真实的 ssh、Claude Code、语言服务器**，只用 mock 和 fixture；也不要跑 `e2e`、`lsp-smoke` 标签的测试。

| 文件 | 覆盖内容 |
| --- | --- |
| `test/remote/rpc_peer_test.dart` | JSON-RPC 收发、异常按类型还原、断线时未完成的请求失败、协议版本不一致 |
| `test/remote/ssh_launcher_test.dart` | ssh 参数、探测、只上传一次、失败分类、不支持的系统、主机地址解析、`~/.ssh/config` 读取（用假的 ssh 进程） |
| `test/remote/remote_server_test.dart` | 服务端各方法（内存中直连） |
| `test/remote/remote_lsp_test.dart` | 远端 LSP 进程、mason 安装 |
| `test/remote/remote_project_test.dart` | 应用侧端到端：location、连接状态和重连、文件监听跨重连、Git、终端、LSP 跨重连、Claude 密钥处理、端口转发、会话、打开流程 |
| `test/remote/remote_claude_install_test.dart` | Claude 自动安装：远端下载、本机下载后上传、并发、校验失败、优先用用户自己的、进度界面；开发时编译服务端 |

测试工具（`test/remote/remote_harness.dart`）：

- `RemoteHarness`：在内存里起一个真实的 `RemoteServer` 和 `RemoteClient`。
- `MemoryConnector`：替代 ssh。用法是 `SshHosts.instance = SshHosts(connect: connector.call)`；`link.drop()` 模拟断线，`connector.failure` 模拟连接失败。
- `until(条件)`：轮询等待某个条件成立。
- Claude 用假的 shell 脚本代替（通过 `CliLocator.use` 和 `BAOCODE_CLAUDE_PATH` 指定）；测试“没有安装”的场景时，要设置 `CliLocator.candidatesOverride`，否则可能找到并运行本机真实的 claude。
- Claude 下载用本地的假发布服务器（`ClaudeRelease.baseOverride`）。在 flutter_test 里要先设置 `HttpOverrides.global = null`，否则所有 HTTP 请求都会返回 400。

只跑相关测试：

```sh
flutter test test/remote
flutter analyze
```

---

## 12. 故障排查

| 现象 / 报错 | 原因 | 处理 |
| --- | --- | --- |
| No ssh here | 本机没有 `ssh` | 安装 OpenSSH 客户端；Windows 上在“可选功能”里安装 |
| 认证失败（authentication） | 需要密码，或密钥没加载 | 先在终端里 `ssh <主机>` 确认能免密登录；把密钥加到 ssh-agent，或在 `~/.ssh/config` 里写 `IdentityFile` |
| 主机密钥问题（hostKey） | 主机还不在 `known_hosts` 里，或密钥变了 | 先在终端里 `ssh <主机>` 一次，接受密钥；密钥确实换过的话，用 `ssh-keygen -R <主机>` 删掉旧记录 |
| 不支持的系统（unsupported） | 远端不是 Linux x64/arm64 | 不支持 |
| This build of the app has no remote server | 应用里没带服务端，也不是从源码目录运行 | 执行 `dart run tool/build_remote_server.dart`，或设置 `BAOCODE_REMOTE_SERVER_DIR` |
| The BaoCode server could not be built | 开发时编译服务端失败 | 看详情里 `dart compile` 的输出 |
| The server could not be installed | 上传失败（家目录不可写、磁盘满） | 看详情里远端 stderr 的最后几行 |
| 连上后立刻断开 | 远端是 musl 系统（Alpine），服务端跑不起来 | 目前不支持，见第 15 节 |
| 一直“正在重连” | 网络断了，或主机关机了 | 恢复后会自动连上；也可以点状态栏立即重连 |
| 无法在 xxx 上安装 Claude Code | 远端和本机都下载不到，或校验不通过 | 检查 `downloads.claude.ai` 能不能访问（有地区限制）；或按详情里的命令在远端手动安装 |
| Claude Code is not at BAOCODE_CLAUDE_PATH | 远端设置了这个变量，但文件不存在 | 改对路径，或去掉这个变量 |
| The connection to the remote host was lost | 对话进行中断线了 | 重连后再发一条消息，会接着原会话继续 |
| 远端会话列表是空的 | 远端 `~/.claude/projects` 下没有这个路径的会话 | 确认远端的 claude 用的是同一个用户 |
| 语言服务器起不来 | 远端缺语言服务器的运行时（如 node），或 mason 安装失败 | 看语言状态里的提示；在远端装好对应的运行时 |

调试时可以在远端手动执行服务端：`~/.baocode-server/<VERSION>/baocode-server`。它从 stdin 读 JSON-RPC，可以手动发 `{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocol":1}}` 看回复。

---

## 13. 真机验证清单

自动化测试都是在内存里跑的，下面这些需要人工在真实环境里验证：

1. **准备**：一台 Linux x64 或 arm64 主机，`~/.ssh/config` 里配好别名，终端里 `ssh <别名>` 能免密登录。开发时直接 `flutter run`（会自动编译服务端），或先执行 `dart run tool/build_remote_server.dart`。
2. **连接和引导安装**：通过“打开远程项目”连接，确认远端出现了 `~/.baocode-server/<VERSION>/baocode-server`，状态栏显示 `SSH: <别名>`；第二次连接不会再上传。
3. **文件、Git、搜索、终端**：打开、编辑、保存文件；新建和删除文件；在远端另开 shell 改文件，界面会刷新；Git 面板的状态、暂存、提交；全文搜索；终端能输入，窗口大小和 shell 集成正常。
4. **断线和重连**：断开网络或杀掉本机的 ssh 进程：状态栏变成“正在重连”，恢复后自动连上；文件监听恢复，语言服务器重启，未保存的修改还在。
5. **失败场景**：需要密码的主机、`known_hosts` 里没有的主机：应直接报错，不会一直重试，点状态栏可以重连。
6. **Claude Code**：
   - 远端没装 claude 时，会出现安装进度，装完正常对话；远端 `~/.local/bin` 里没有多出文件；
   - 远端屏蔽 `downloads.claude.ai` 后，改成本机下载再上传；
   - 远端已装 claude 时，直接用用户自己的那份；
   - 用第三方模型服务对话时，在远端执行 `ps aux | grep claude`，参数里没有 key；对话结束后，`$XDG_RUNTIME_DIR/baocode-settings-*` 下没有残留文件；
   - 本机模型代理能通过端口转发使用；
   - 会话列表、删除会话、自动标题、Keep/Undo、提交信息都正常。
7. **语言服务器**：在远程项目里打开 `.dart`、`.ts` 文件，缺的语言服务器会装到远端；诊断、悬停、跳转都正常。
8. **退出**：远端有对话或终端在运行时退出应用，确认框里有远程的那一句；退出后远端没有残留的 `baocode-server` 和 claude 进程。
9. **打包**：用 `tool/build_windows.dart` / `tool/build_macos.dart` 打包，确认包里有 `remote/VERSION`，安装后不需要源码目录也能连接。
10. **Windows 客户端**：打开远程项目，重点检查文件树、标签页、搜索、Git 的路径（见第 15 节）。

---

## 14. 修改指南

### 14.1 加一个新的远端功能

1. 在 `packages/bao_remote/lib/src/protocol.dart` 里加方法名常量。方法或数据结构有**不兼容**的改动时，把 `RemoteProtocol.version` 加一。
2. 在服务端注册处理函数：放在 `remote_server.dart` 的 `_register()` 里，功能大的话新建 `server_xxx.dart`（参考 `server_claude.dart`、`server_lsp.dart`）。需要持续返回数据的，用 `ServerStreams.open` 返回流 id。
3. 在 `remote_client.dart` 里加对应的类型化方法。流用 `openStream`。
4. 要让应用侧捕获某种特定异常时，在 `rpc_error.dart` 的 `from` 和 `toException` 里都加上。**子类要写在父类前面**（比如 `ClaudeNotInstalled` 要在 `ClaudeUnavailable` 前面）。
5. 应用侧按 location 分流：本地走原来的实现，远程走 `SshHosts.instance[host]`。
6. 在 `test/remote/` 里用 `RemoteHarness` / `MemoryConnector` 写测试。

### 14.2 注意事项

- **`bao_remote` 不能依赖 Flutter**，否则服务端编不出来。改完后执行一下 `cd packages/bao_remote && dart analyze`。
- **路径**：远端一律是 POSIX 路径。应用里要处理远端路径时，用 `RemoteLocation.pathsOf(location)` 或 `ProjectHost.paths`，**不要直接用 `package:path` 的顶层函数**（Windows 客户端上会按 Windows 路径处理，见第 15 节）。
- **location 和主机上的路径**：存储和显示用 location（`ssh://...`）；传给远端服务和 IDE 内部用 `RemoteLocation.pathOf`。两者别混。
- **断线**：长连接类的功能（监听）要用 `resilientStream` 包一层；有状态的功能（语言服务器）要监听 `SshHost.reconnected` 自己恢复。
- **密钥**：任何带凭据的东西都不能进命令行参数，也不能长期写在远端磁盘上。要传就走 `claude/start` 的 `settings` 那条路，或者放环境变量。
- **改了服务端代码**，正式构建会生成新的 `VERSION`，开发构建会生成新的源码哈希，远端会自动换上新服务端，不需要手动清理。
- **l10n**：新文案加到 `lib/l10n/app_en.arb` 和 `app_zh.arb`，然后执行 `flutter gen-l10n`。

---

## 15. 已知限制与待办

1. **Windows 客户端打开远程项目可能有路径问题**：IDE 里很多地方直接调用 `package:path` 的顶层函数，在 Windows 上会按反斜杠和盘符处理远端的 POSIX 路径。目前只有 LSP 处理了 POSIX 路径；文件树、标签页、搜索、Git 需要逐个改成用 `ProjectHost.paths`。
2. **服务端只支持 glibc**：`dart compile exe` 编出的 Linux 二进制在 Alpine 这类 musl 系统上跑不了。Claude Code 本身有 musl 版本，已经能正确选择。
3. **旧版本服务端不会自动清理**：`~/.baocode-server/<旧VERSION>/` 会一直留着，每个约几十 MB。可以在连接成功后删掉其他版本的目录。
4. **Haiku 不会触发 Claude 自动安装**：远端没有 claude 时，标题和提交信息会失败，等到第一次对话装好后才正常。
5. **自动安装没有开关**：远端没有 claude 时总是自动装。如果有用户不希望自动下载，需要加一个设置项。
6. **不支持密码或二次验证登录**：用的是 `BatchMode=yes`。要支持的话，需要做一个让 ssh 弹窗询问的机制（`SSH_ASKPASS`）。
7. **启动时会连接所有远程项目的主机**（因为要读会话列表）。主机很多或很慢时，可以改成在展开项目时再连接。
8. **macOS 打包这一步还没实际跑过**，签名和公证也还没做（见 `tool/build_macos.dart` 里的 TODO）。
9. **断线时远端进程都会结束**：sshd 断开会话时会发 SIGHUP。以后如果想让对话在断线期间继续跑，需要把服务端改成常驻进程（类似 VS Code 的 server 那样），每次连接再重新接上。
