# 集成终端交接

目标：把 xterm.js 的终端内核移植成 Dart，并在 IDE 里做出 VS Code 那样的集成终端，要能跑交互式 shell 和 TUI 程序（vim、htop、claude 这类）。移植约定见 [PORTING.md](PORTING.md)，与 VS Code 的差异见 [PARITY.md](PARITY.md)。

## 发布计划

2026-10-01 起，终端和编辑器的移植是本仓库 pub workspace 里的三个本地包，应用用 path 依赖：

| 包 | 内容 | 依赖 |
|---|---|---|
| `packages/bao_xterm` | xterm.js 的无界面内核及 search、unicode11、unicode-graphemes 插件 | 纯 Dart，无依赖 |
| `packages/bao_pty` | 伪终端进程（forkpty／ConPTY），见 [bao_pty 的 HANDOFF](../bao_pty/HANDOFF.md) | 纯 Dart，build hook 编译 C |
| `packages/bao_editor` | Monaco 编辑器、Monarch 与 TextMate 高亮（含 Oniguruma）、VS Code 主题和配色，见 [bao_editor 的 HANDOFF](../bao_editor/HANDOFF.md) | Flutter，build hook 编译 C |

- **许可是 MIT**（各包的 `LICENSE`，Copyright (c) 2026 BaoCode）。应用本身是 GPL-3.0-only，把应用的代码搬进包等于以 MIT 放出，先问用户。上游声明留在原处：`bao_xterm/lib/LICENSE.txt` 和各插件目录的 `LICENSE`（xterm.js），`bao_editor/lib/monaco/LICENSE.txt`（VS Code），`bao_editor/assets/monaco/LICENSE.txt`（Monaco），`bao_editor/assets/textmate/LICENSE.txt`（语法和主题），`bao_editor/lib/textmate/vscode_textmate/LICENSE.md`，`bao_editor/native/oniguruma/`（Oniguruma）。
- **暂不发布**。用户以后会发到 pub.dev，包名就是 bao_editor、bao_xterm、bao_pty；在那之前保持 `publish_to: none`、版本 0.1.0，不要自行发布。
- 依赖只能从应用指向包，包不能 import `package:baocode`。包要用应用的东西时，包里定义接口、应用实现，比如 bao_editor 的 `TextMateThemeSource`（应用的 `WorkbenchThemeService`）、`MonacoLanguagePacks`（应用的 `LanguagePackRegistry`，`main()` 里设 `MonacoLanguageAssets.defaultPacks`）。
- 包里文档的路径相对于包根目录，`../../` 开头的是应用的文件。

发布前要做的：

1. 定公开 API。现在照上游目录排布，`lib/` 下每个文件都是公开库；决定哪些移进 `lib/src/`，每个包给一个入口库（bao_pty 已有 `lib/bao_pty.dart`）。`bao_xterm/lib/testing/` 是测试辅助，应用的测试也在用，要么作为公开的测试工具保留，要么移走。
2. bao_xterm 和 bao_pty 的库不用 Flutter，测试却用 `flutter_test`；改用 `package:test`，包就能直接 `dart test`。
3. 每个包写 README、CHANGELOG 和 example，pubspec 补 `repository`、`homepage`、`topics`。
4. 包里引用应用的地方（文档和注释里的 `../../`）在发布的内容里去掉或改成仓库链接；HANDOFF、PARITY、PORTING 是写给移植者的，用 `.pubignore` 排除或改写。
5. 控制体积：bao_editor 在仓库里约 25 MB，其中 `test/`（主要是 fixtures）13 MB、`assets/` 7.7 MB；用 `.pubignore` 排除 `test/fixtures` 和 `tool/` 之类，`dart pub publish --dry-run` 看大小和警告。
6. 去掉 `publish_to: none`。应用在同一仓库里，继续用 path 依赖即可。

## 分层

- **PTY**：[bao_pty](../bao_pty/HANDOFF.md) 包（`../bao_pty/lib/src/pty*.dart`），外加一层很薄的原生代码；应用在 `../../lib/ide/terminal/pty*.dart` 里加上进程登记、终端环境和 shell 配置。网页版没有 PTY。
  - macOS/Linux：`../bao_pty/native/bao_pty.c`（forkpty 之类的一小段 C），由 `../bao_pty/hook/build.dart` 用 Dart 的 build hook（native assets）编译成 `bao_pty.framework`。
  - Windows：ConPTY，直接用 `dart:ffi` 调 kernel32，没有原生库。输出和进程退出在 UI isolate 上轮询，没有 isolate 停在阻塞调用里（原因见“已知问题”里 Dart 分析器那条）。
- **内核**：`lib/`，是 xterm.js 无界面部分的纯 Dart 移植，网页版也能编译。
- **渲染和交互**：`../../lib/ide/terminal/`，用 Flutter 自己画。

## 版本

xterm.js commit `c58ea3637f3968e0e6e79cd92cf9aace7ef89ee2`（`@xterm/xterm` 6.1.0-beta.304，`@xterm/headless` 6.1.0-beta.303）。版本是从 VS Code `6a598d4a` 的 `package-lock.json` 和 npm 的 `gitHead` 查到的。

## 进度

| 里程碑 | 状态 |
| --- | --- |
| M1 内核 | 完成：解析器、InputHandler、Buffer/BufferLine/CircularList/reflow、Charsets、各 service、Marker、键盘、无界面 `Terminal` 及其公开 API、unicode11 和 graphemes 插件；上游测试全部移植（`test/` 现有 1543 个，含后来的搜索插件和浏览器部分） |
| M2 PTY | 完成：接口和假实现、macOS/Linux 原生层、Windows ConPTY、按 VS Code 设置环境变量和默认 shell、输出流控；macOS 实测通过，Windows 未实测 |
| M3 渲染和交互 | 完成：按行缓存的渲染器（每帧最多画一次，只画可见行）、宽字符和 emoji、自绘框线和 powerline 字形、光标样式和闪烁、失焦样式、拖选和双击三击、复制粘贴（含括号粘贴和多行警告）、键盘（macOptionIsMeta 默认关，同 VS Code）、鼠标上报、备用屏幕、输入法、滚轮遵守 WheelLatch、`terminal.*` 主题色、字体跟编辑器一致 |
| M4 IDE 集成 | 完成：编辑区下方的面板、分隔条、多标签（新建、关闭、重命名、退出状态）、⌃\` 开关、右键菜单；工作台的快捷键不进 shell |
| M5 上层功能 | 完成：查找（移植 addon-search，界面用 `IdeFindWidget`）；链接（移植 VS Code 的四种检测器，网址交给浏览器，`路径:行:列` 在编辑器里打开，⌘/Ctrl 点击）；shell 集成（注入 VS Code 的 zsh、bash、fish、pwsh 脚本，解析 OSC 633/133/7/1337，命令在左侧留白处标出成功或失败，点开可重新运行或复制；链接按每行的 cwd 解析）。sticky scroll 和补全不做，记在 PARITY |
| M6 聊天输出（可选） | 完成：聊天里命令的输出经内核解析后显示颜色，`\r` 进度条和光标上移改写收拢成最终结果；纯文本输出与以前完全一样（`../../lib/chat/widgets/terminal_output.dart`） |

## 决策

- 移植目标锁定在上面的 commit，不追 xterm.js 新版本。
- TypeScript 装饰器实现的依赖注入不移植。各 service 的依赖改由构造函数传入，由 `CoreTerminal` 负责组装（见 PORTING.md 的约定）。
- 渲染层用内部的 `Terminal`（`xterm/headless/terminal.dart`），和 xterm.js 浏览器版一样是 `CoreTerminal` 的子类；公开的 `Terminal` 给插件和照搬 VS Code 的代码用（`publicTerminal.core` 拿到内部对象）。
- 原生构建用 Dart build hook：bao_pty 的 `pubspec.yaml` 有 `hooks`、`code_assets`、`native_toolchain_c` 三个依赖（版本与 Flutter 工具自带的一致）。`../../tool/build_macos.dart` 会检查产物里有 `bao_pty.framework`。
- ⌘J 仍是聊天区的开关；VS Code 的“切换面板”命令保留但不绑快捷键，终端用 ⌃\` 开关。
- 标签列表照 VS Code 默认的 `terminal.integrated.tabs.focusMode`（`doubleClick`）：单击选中，双击把键盘交给终端；重命名用 F2（macOS 上是 Enter）或右键菜单。
- 每个 `TerminalInstance` 自己持有内核 `Terminal`、装饰服务、渲染数据源和键盘、鼠标、选择、剪贴板四个控制器；视图只在显示时接上它们。这样切到别的标签，后台终端照样解析输出，选区也保留。
- 输入法沿用编辑器的做法（`TextInput.attach`，把光标位置报给系统），没有复用编辑器的类：编辑器的输入法逻辑写在 `EditorSurface` 的 State 里，拆不出来。组字时按键全部交给输入法，组好的字通过 `handleTextInput` 发给进程。输入连接里的文字不在每次提交后清空：视图记着已经发给进程的长度，每次只发组字区之前新提交的部分（韩文每个音节提交后接着组下一个），文字超过 4096 个 UTF-16 单元、且没在组字时才清空一次，清空前引擎发出的更新靠开头仍是旧文字认出来。
- VS Code 的 `commandsToSkipShell` 只取了这里有的命令（`terminalCommandsToSkipShell`，在 `terminal_panel.dart`）：快速打开、命令面板、切换编辑器、终端的新建、关闭、切换、聚焦，以及 ⌘J（这里是聊天区）。macOS 上所有 ⌘ 组合键本来就交给 IDE。
- 进程退出的说明按 VS Code 的 `formatMessageForTerminal` 写进终端屏幕，不再是单独的文字控件。
- shell 集成脚本打包成 Dart 常量（`../../tool/generate_shell_integration_scripts.dart` 从 VS Code 源码原样生成），启动时写到临时目录：shell 本来就要一个真实路径，用常量省掉资源注册和异步的 `rootBundle`，纯单元测试也能用。有测试核对文件名、字节数和许可头。
- 每个终端都有 shell 集成的 nonce：注入时由启动参数带给 shell，没注入时随机生成一个（VS Code 也是每个终端一个），这样输出里伪造的 `633;E` 命令行不会被当真。
- 查找、链接和 shell 集成都挂在 `TerminalInstance` 上：查找第一次用时才创建，链接检测按需，shell 集成在知道启动参数后、进程启动前创建，保证看得到第一个提示符。
- 输出流控照 VS Code 的水位（100000 / 5000），但按字节计、由内核 `write` 的回调在解析完每块后确认。暂停在 macOS/Linux 上用一个原生内存里的标志，读输出的 isolate 每 10 ms 看一次；Windows 上轮询停止读取即可。不用 `SIGSTOP`，那样会连进程的输入处理一起停掉。内核的写缓冲超过 50 MB 会抛错，有了流控就到不了。
- 应用启动时调用 `reapPtyProcesses()`，退出前调用 `stopPtyProcesses()`（`../../lib/main.dart`）。

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

1. `TERM_PROGRAM` 设成 `baocode`，不是 `vscode`。有些程序会按 `vscode` 做特殊处理，好处是兼容，坏处是冒充。
2. Windows 上不设 `TERM`，与 VS Code、node-pty 一致。
3. 没有设 `TERM_PROGRAM_VERSION`，应用版本还没接进来（`terminalEnvironment(version:)` 已经能接收）。
4. native assets 要求 macOS 13，而 Runner 的最低版本是 12.0：在 macOS 12 上 `ptySupported` 为 false，没有终端。可以把最低版本提到 13，或者接受。
5. 进程退出：退出码为 0 或用户主动关闭时关掉终端；非 0 时保留终端，显示 “The terminal process "/bin/zsh '-l'" terminated with exit code: N.” 并在标签上加标记；启动失败也保留并显示原因。VS Code 对普通终端是直接关闭并弹通知，只有等待退出的终端（比如任务）才保留。

## 已知问题

- Windows 的 ConPTY 只在实机上手动用过，`../bao_pty/test/pty_windows_test.dart` 里真实进程的测试还没在 Windows 上跑过。
- Dart VM 的采样分析器在 Windows 上会让应用闪退（Flutter 3.47.5 引擎，调试模式；桌面端的 `flutter run` 总是带 `enable-dart-profiling=true`）。分析器定时挂起每个 isolate 线程，用 `RBP` 当帧指针回溯（`ProfilerNativeStackWalker::walk`，`runtime/vm/profiler.cc:275` 的 `fp = CallerFP(fp)`）。Windows x64 在系统调用里不保证 `RBP` 是帧指针，而检查只看指针是否落在 `GetCurrentThreadStackLimits` 给出的整段保留栈里、是否 8 字节对齐；读到还没提交的页就是 `0xc0000005`。原来每个 Windows 终端有两个 isolate 一直停在 `ReadFile`、`WaitForSingleObject` 里，`ClosePseudoConsole` 也在 isolate 里等，终端一多很快就崩。本地绕开：输出和退出改由 `ConsolePoll` 在 UI isolate 上轮询（`PeekNamedPipe` 后只读已有的字节，`WaitForSingleObject(process, 0)`），有输出或刚输入时 1 ms 后再看，安静时逐次加倍到 32 ms；`ClosePseudoConsole` 作为线程入口交给 `CreateThread` 起的系统线程，Dart VM 不认识这个线程，分析器不会碰它。写输入的 isolate 保留：空闲时不占线程，只在一次写入等管道时停在 `WriteFile` 里。没有向上游报告。
- Flutter 3.47.5 的 Windows 引擎（`text_input_plugin.cc`）：框架每次 `setEditingState` 都会结束引擎这边的组字（`SetText` 把组字标记清掉，组字区的 extent 也误读成 base），之后输入法再更新组字串，引擎会把它插两遍、并且不带组字区上报。输入法开始组字时引擎先报一个空的组字区，终端原先把它当成提交并清空输入，结果微软拼音打 “cd” 时 `c'dc'd` 直接进了 shell。本地绕开，没有向上游报告：终端不在组字期间碰输入（见“决策”里输入法一条），`../../test/ide/terminal/terminal_view_test.dart` 里的 `_WindowsInput` 照引擎的逻辑模拟。剩下一个很窄的时间窗：文字满 4096 后清空的那一刻，如果输入法恰好在清空消息到达引擎之前开始组字，这次组字仍会坏。
- Linux 上如果 Dart 自己的子进程回收抢先，退出码可能读成 0。
- fork 到 exec 之间会短暂阻塞 UI isolate。
- Flutter 3.47 的 `OverlayPortal` 把浮层的语义节点嫁接到锚点下（traversal parent），但锚点离开语义树再回来时（侧栏收起再展开、锚点滚出视野），浮层节点不会重发；桌面端引擎公共的 `AccessibilityBridge` 用 ui::AXTree，删锚点时连浮层节点一起删了，之后每次更新都报 “Failed to update ui::AXTree … Nodes left pending”，树从此对不上。Windows 上只要有 UI Automation 客户端（输入法、讲述人等）就会开无障碍，出现在闪退之前。本地绕开，没有向上游报告：`FloatingLayer`（聊天的浮层、侧栏菜单、标题栏菜单）只在打开和关闭动画期间显示浮层入口，打开时换一个事先 `show()` 过的控制器，同一帧就能显示；锚点被裁掉时，这一帧浮层保持原样（透明度设为 0，语义不变），帧后隐藏，锚点回来再显示。`../../test/flutter_test_config.dart` 让每个组件测试都按桌面引擎的规则应用语义更新（`../../test/semantics_tree.dart`），引擎会拒绝的更新会让测试失败。
- `CircularList` 按回滚上限一次性分配指针数组（上游是稀疏数组），回滚设得很大时会立刻占内存。
- 快捷键标签显示 “Ctrl+Page Down”，VS Code 是 “Ctrl+PageDown”。
- 根目录变化只影响之后新建的终端。

## 下一步

- 在 Windows 实机上跑 `../bao_pty/test/pty_windows_test.dart`（`cmd.exe` 的真实进程测试，含暂停和恢复），以及 shell 集成的 pwsh 脚本；用微软拼音和微软韩文输入法在终端里实际打一遍字。
- sticky scroll 和终端补全（suggest）没做，见 PARITY 的“暂不做”。
- 终端选项（光标样式、回滚行数、`macOptionIsMeta` 等）固定用 VS Code 的默认值（`vscodeTerminalOptions`），IDE 还没有设置入口。
- 待决事项里的几项定下来后改相应默认值。
