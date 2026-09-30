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
| M1 内核 | 完成：解析器、InputHandler、Buffer/BufferLine/CircularList/reflow、Charsets、各 service、Marker、键盘、无界面 `Terminal` 及其公开 API、unicode11 和 graphemes 插件；上游测试全部移植（`test/ide/terminal/xterm/` 现有 1543 个，含后来的搜索插件和浏览器部分） |
| M2 PTY | 完成：接口和假实现、macOS/Linux 原生层、Windows ConPTY、按 VS Code 设置环境变量和默认 shell、输出流控；macOS 实测通过，Windows 未实测 |
| M3 渲染和交互 | 完成：按行缓存的渲染器（每帧最多画一次，只画可见行）、宽字符和 emoji、自绘框线和 powerline 字形、光标样式和闪烁、失焦样式、拖选和双击三击、复制粘贴（含括号粘贴和多行警告）、键盘（macOptionIsMeta 默认关，同 VS Code）、鼠标上报、备用屏幕、输入法、滚轮遵守 WheelLatch、`terminal.*` 主题色、字体跟编辑器一致 |
| M4 IDE 集成 | 完成：编辑区下方的面板、分隔条、多标签（新建、关闭、重命名、退出状态）、⌃\` 开关、右键菜单；工作台的快捷键不进 shell |
| M5 上层功能 | 完成：查找（移植 addon-search，界面用 `IdeFindWidget`）；链接（移植 VS Code 的四种检测器，网址交给浏览器，`路径:行:列` 在编辑器里打开，⌘/Ctrl 点击）；shell 集成（注入 VS Code 的 zsh、bash、fish、pwsh 脚本，解析 OSC 633/133/7/1337，命令在左侧留白处标出成功或失败，点开可重新运行或复制；链接按每行的 cwd 解析）。sticky scroll 和补全不做，记在 PARITY |
| M6 聊天输出（可选） | 完成：聊天里命令的输出经内核解析后显示颜色，`\r` 进度条和光标上移改写收拢成最终结果；纯文本输出与以前完全一样（`lib/chat/widgets/terminal_output.dart`） |

## 决策

- 移植目标锁定在上面的 commit，不追 xterm.js 新版本。
- TypeScript 装饰器实现的依赖注入不移植。各 service 的依赖改由构造函数传入，由 `CoreTerminal` 负责组装（见 PORTING.md 的约定）。
- 渲染层用内部的 `Terminal`（`xterm/headless/terminal.dart`），和 xterm.js 浏览器版一样是 `CoreTerminal` 的子类；公开的 `Terminal` 给插件和照搬 VS Code 的代码用（`publicTerminal.core` 拿到内部对象）。
- 原生构建用 Dart build hook：`pubspec.yaml` 加了 `hooks`、`code_assets`、`native_toolchain_c` 三个依赖（版本与 Flutter 工具自带的一致）。`tool/build_macos.dart` 会检查产物里有 `monad_pty.framework`。
- ⌘J 仍是聊天区的开关；VS Code 的“切换面板”命令保留但不绑快捷键，终端用 ⌃\` 开关。
- 标签列表照 VS Code 默认的 `terminal.integrated.tabs.focusMode`（`doubleClick`）：单击选中，双击把键盘交给终端；重命名用 F2（macOS 上是 Enter）或右键菜单。
- 每个 `TerminalInstance` 自己持有内核 `Terminal`、装饰服务、渲染数据源和键盘、鼠标、选择、剪贴板四个控制器；视图只在显示时接上它们。这样切到别的标签，后台终端照样解析输出，选区也保留。
- 输入法沿用编辑器的做法（`TextInput.attach`，把光标位置报给系统），没有复用编辑器的类：编辑器的输入法逻辑写在 `EditorSurface` 的 State 里，拆不出来。组字时按键全部交给输入法，组好的字通过 `handleTextInput` 发给进程。
- VS Code 的 `commandsToSkipShell` 只取了这里有的命令（`terminalCommandsToSkipShell`，在 `terminal_panel.dart`）：快速打开、命令面板、切换编辑器、终端的新建、关闭、切换、聚焦，以及 ⌘J（这里是聊天区）。macOS 上所有 ⌘ 组合键本来就交给 IDE。
- 进程退出的说明按 VS Code 的 `formatMessageForTerminal` 写进终端屏幕，不再是单独的文字控件。
- shell 集成脚本打包成 Dart 常量（`tool/generate_shell_integration_scripts.dart` 从 VS Code 源码原样生成），启动时写到临时目录：shell 本来就要一个真实路径，用常量省掉资源注册和异步的 `rootBundle`，纯单元测试也能用。有测试核对文件名、字节数和许可头。
- 每个终端都有 shell 集成的 nonce：注入时由启动参数带给 shell，没注入时随机生成一个（VS Code 也是每个终端一个），这样输出里伪造的 `633;E` 命令行不会被当真。
- 查找、链接和 shell 集成都挂在 `TerminalInstance` 上：查找第一次用时才创建，链接检测按需，shell 集成在知道启动参数后、进程启动前创建，保证看得到第一个提示符。
- 输出流控照 VS Code 的水位（100000 / 5000），但按字节计、由内核 `write` 的回调在解析完每块后确认。暂停用一个原生内存里的标志，读输出的 isolate 每 10 ms 看一次；不用 `SIGSTOP`，那样会连进程的输入处理一起停掉。内核的写缓冲超过 50 MB 会抛错，有了流控就到不了。
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

大量输出时界面不卡：内核每次最多连续解析 12 ms 就让出事件循环（上游 WriteBuffer 的做法），渲染每帧最多画一次、只画可见行；没解析完的输出超过 100 KB 就暂停读 PTY，进程随之阻塞，内存不会无限涨。

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
- `CircularList` 按回滚上限一次性分配指针数组（上游是稀疏数组），回滚设得很大时会立刻占内存。
- 快捷键标签显示 “Ctrl+Page Down”，VS Code 是 “Ctrl+PageDown”。
- 根目录变化只影响之后新建的终端。

## 下一步

- 在 Windows 实机上跑 ConPTY：`test/ide/terminal/pty_test.dart` 里 `cmd.exe` 的测试，以及 shell 集成的 pwsh 脚本。
- sticky scroll 和终端补全（suggest）没做，见 PARITY 的“暂不做”。
- 终端选项（光标样式、回滚行数、`macOptionIsMeta` 等）固定用 VS Code 的默认值（`vscodeTerminalOptions`），IDE 还没有设置入口。
- 待决事项里的几项定下来后改相应默认值。
