# 集成终端交接

目标：把 xterm.js 的终端内核移植成 Dart，并在 IDE 里做出 VS Code 那样的集成终端，要能跑交互式 shell 和 TUI 程序（vim、htop、claude 这类）。移植约定见 [PORTING.md](PORTING.md)，与 VS Code 的差异见 [PARITY.md](PARITY.md)。

## 分层

- **PTY**：`lib/ide/terminal/pty*.dart`，外加一层很薄的原生代码。网页版没有 PTY。
  - macOS/Linux：`native/pty/monad_pty.c`（forkpty 之类的一小段 C），由 `hook/build.dart` 用 Dart 的 build hook（native assets）编译成 `monad_pty.framework`。
  - Windows：ConPTY，直接用 `dart:ffi` 调 kernel32，没有原生库。
- **内核**：`lib/ide/terminal/xterm/`，是 xterm.js 无界面部分的纯 Dart 移植，网页版也能编译。
- **渲染和交互**：`lib/ide/terminal/`，用 Flutter 自己画。

## 版本

xterm.js commit `c58ea3637f3968e0e6e79cd92cf9aace7ef89ee2`（`@xterm/xterm` 6.1.0-beta.304，`@xterm/headless` 6.1.0-beta.303）。版本是从 VS Code `6a598d4a` 的 `package-lock.json` 和 npm 的 `gitHead` 查到的。

## 进度

| 里程碑 | 状态 |
| --- | --- |
| M1 内核 | 完成：解析器、InputHandler、Buffer/BufferLine/CircularList/reflow、Charsets、各 service、Marker、键盘、无界面 `Terminal` 及其公开 API、unicode11 和 graphemes 插件；上游测试全部移植（`test/ide/terminal/xterm/`，1427 个） |
| M2 PTY | 完成：接口和假实现、macOS/Linux 原生层、Windows ConPTY、按 VS Code 设置环境变量和默认 shell；macOS 实测通过，Windows 未实测 |
| M3 渲染和交互 | 进行中 |
| M4 IDE 集成 | 面板、多标签、⌃\`、分隔条已完成；终端内容还是占位，等 M3 接入 |
| M5 上层功能 | 进行中：搜索、链接、shell 集成 |
| M6 聊天输出（可选） | 未开始 |

## 决策

- 移植目标锁定在上面的 commit，不追 xterm.js 新版本。
- TypeScript 装饰器实现的依赖注入不移植。各 service 的依赖改由构造函数传入，由 `CoreTerminal` 负责组装（见 PORTING.md 的约定）。
- 渲染层用内部的 `Terminal`（`xterm/headless/terminal.dart`），和 xterm.js 浏览器版一样是 `CoreTerminal` 的子类；公开的 `Terminal` 给插件和照搬 VS Code 的代码用（`publicTerminal.core` 拿到内部对象）。
- 原生构建用 Dart build hook：`pubspec.yaml` 加了 `hooks`、`code_assets`、`native_toolchain_c` 三个依赖（版本与 Flutter 工具自带的一致）。`tool/build_macos.dart` 会检查产物里有 `monad_pty.framework`。
- ⌘J 仍是聊天区的开关；VS Code 的“切换面板”命令保留但不绑快捷键，终端用 ⌃\` 开关。
- 标签列表照 VS Code 默认的 `terminal.integrated.tabs.focusMode`（`doubleClick`）：单击选中，双击把键盘交给终端；重命名用 F2（macOS 上是 Enter）或右键菜单。
- 应用启动时调用 `reapPtyProcesses()`，退出前调用 `stopPtyProcesses()`（`lib/main.dart`）。

## 性能

基准测试都在仓库根目录运行，数字是中位数（MB/s）。

- 解析器（`tool/xterm_parser_benchmark.dart`，4 MB 混合 UTF-8，空处理器）：JIT 374–404，AOT 457–488。
- 整个终端（`tool/xterm_terminal_benchmark.dart`，120×40，回滚 1000 行，每次写 16 KiB；字符串/UTF-8）：

| 负载 | `dart run` | AOT |
| --- | --- | --- |
| ls -la | 87 / 89 | 88 / 92 |
| cat | 78 / 80 | 84 / 87 |
| 大量 SGR | 60 / 61 | 71 / 73 |
| 光标移动 | 21 / 22 | 24 / 24 |
| 混合 4.8 MB | 45 / 46 | 51 / 50 |

光标移动里最慢的是滚动区域内换行加 IL/DL（AOT 23），这是上游算法本身的开销；进度条 149、多行重绘 63、全屏 TUI 帧 56。

## 待决事项

以下都先按合理的默认做了，需要时再改：

1. `TERM_PROGRAM` 设成 `monad`，不是 `vscode`。有些程序会按 `vscode` 做特殊处理，好处是兼容，坏处是冒充。
2. Windows 上不设 `TERM`，与 VS Code、node-pty 一致。
3. 没有设 `TERM_PROGRAM_VERSION`，应用版本还没接进来（`terminalEnvironment(version:)` 已经能接收）。
4. native assets 要求 macOS 13，而 Runner 的最低版本是 12.0：在 macOS 12 上 `ptySupported` 为 false，没有终端。可以把最低版本提到 13，或者接受。
5. 进程退出：退出码为 0 或用户主动关闭时关掉终端；非 0 时保留终端，显示 “The terminal process "/bin/zsh '-l'" terminated with exit code: N.” 并在标签上加标记；启动失败也保留并显示原因。VS Code 对普通终端是直接关闭并弹通知，只有等待退出的终端（比如任务）才保留。

## 已知问题

- Windows 的 ConPTY 没有实机跑过。
- Linux 上如果 Dart 自己的子进程回收抢先，退出码可能读成 0。
- fork 到 exec 之间会短暂阻塞 UI isolate。
- 还没有输出流控：进程输出很快时全部进内核排队解析。
- `CircularList` 按回滚上限一次性分配指针数组（上游是稀疏数组），回滚设得很大时会立刻占内存。
- 快捷键标签显示 “Ctrl+Page Down”，VS Code 是 “Ctrl+PageDown”。
- 根目录变化只影响之后新建的终端。

## 下一步

- M3 完成后接入：`TerminalInstance` 持有内核 `Terminal`，在收到 PTY 输出的地方喂给它；`TerminalView` 换成渲染控件加键盘、鼠标、选择、剪贴板控制器。
- M5：搜索接 `IdeFindWidget`，链接接编辑器和浏览器，shell 集成画命令装饰。
