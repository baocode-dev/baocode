# 与 VS Code 终端的差异

这里记录集成终端与 VS Code（`6a598d4a`，xterm.js `c58ea36`）的行为差异：没做的、做法不同的，以及原因。

## 暂不做

- sticky scroll。
- 终端补全（terminal suggest）。

## 面板和标签

- 没有拆分终端：每个终端各自一组，标题仍沿用 VS Code 的 “Terminal Group” 说法。
- 没有终端配置（profile）下拉菜单，也没有拆分、改图标、改颜色、移动到编辑区这些操作。
- 中键点标签不会关闭终端；标签列表里不能用方向键切换。
- 两个以上终端时右侧标签列表固定 120 像素宽，没有分隔条，也没有窄模式。
- 只有一个终端时，关闭按钮和终端名称才显示在面板标题栏上。
- 标题是可执行文件的名字，还不跟随前台进程或 OSC 标题。
- 重命名是在标签上原地编辑，不是 VS Code 的快速输入框。
- 被信号结束的进程安静地关闭（node-pty 对这种情况也报 0）。
- 已退出的终端，标签上用错误色的错误图标标记。
- 进程退出的处理与 VS Code 不同，见 HANDOFF.md 的待决事项。

## PTY 和环境变量

- `TERM_PROGRAM` 是 `baocode`，没有 `TERM_PROGRAM_VERSION`。
- 直接启动 `$SHELL` 本身；VS Code 是按名字在 PATH 里找对应的配置。不查 `/etc/passwd`。
- Linux 上启动 shell 不加登录参数；macOS 上 bash、zsh、fish 加 `-l`，tmux、pwsh 不加，其他名字里带 zsh 或 bash 的加 `--login`。
- Windows 按 VS Code 的顺序找 PowerShell，找不到再用 `ComSpec`，最后是 `cmd.exe`。
- Windows 上 ConPTY 的输出靠轮询读取（有输出或刚输入时 1 ms 后再看，安静时最长 32 ms），node-pty 是事件驱动的命名管道。空闲后第一次输出最多晚 32 ms 左右。
- 输出流控照 VS Code 的 `FlowControlConstants`：没解析完的超过 100000 就暂停进程的输出，降到 5000 以下再恢复。VS Code 按字符数算，由渲染进程每 5000 字符分批确认给 pty host；这里在同一进程里，按字节算，内核每解析完一块就确认。暂停时 macOS/Linux 上读输出的 isolate 每 10 ms 看一次标志，Windows 上轮询停止读取（node-pty 是停掉 socket 的读取），进程写满 PTY 缓冲区后就会阻塞等待。

## 绘制

- 自定义字形没有 octant（上游这个 commit 也没有）；sextant 的边缘和上游一样有半像素。
- 阴影字形（░▒▓）保留颜色自身的透明度；上游对 `#rrggbbaa` 会强制不透明，看起来是上游的 bug。
- 半透明的主题色用的是精确的十六进制值；VS Code 用 `rgba()` 两位小数，透明度可能差一级。
- 对齐的是 VS Code 用的 WebGL 渲染器。没有做：下划线在字母下伸部分断开的描边（12 像素以上字号）、下划线字符上移、连字、平滑滚动、滚动条两端的箭头。
- 重叠字形的缩放按字形的步进宽度算，上游按实际墨迹范围。
- 光标闪烁重启时立即重新计时，上游等到下一拍。
- 有回滚内容时，触控板拖动总是归终端，即使已经滚到底（与 WheelLatch 的约定一致：内层视图保留触控板拖动）。

## 键盘、鼠标和剪贴板

- 没有 VS Code 的快捷键服务：macOS 上所有 ⌘ 组合键都交给 IDE，包括 IDE 没有绑定的。
- ⌘K 清屏、跳到上一条命令、PowerShell 的发送序列这些快捷键还没有做。
- Linux 的主选区（中键粘贴）只在应用内部有效：Flutter 拿不到 X11 的选区。
- 没有触摸手势。
- 用输入法组字时，所有按键都交给输入法；读屏用的 textarea 回显没有保留。
- kitty 键盘协议只在打开 `vtExtensions.kittyKeyboard` 且程序推了标志时才用；被 IDE 拿走的按键，抬起时不报告。

## 终端视图

- 右键菜单只有复制、粘贴、全选、清屏、关闭终端；没有 “Copy as HTML” 和 “Size to Content Width”。
- 多行粘贴警告的对话框没有 “Do not ask me again” 复选框（`showIdeDialog` 不支持复选框）。
- 字体固定为编辑器的等宽字体和 13 像素；还没有 `terminal.integrated.fontFamily`、`fontSize` 这类设置。
- `commandsToSkipShell` 只包含这里已有的命令，见 HANDOFF.md 的决策。

## 终端查找

- 查找框的选项开关（Aa、ab、.*）按 VS Code 的切换命令处理：从最底下的匹配重新找。VS Code 用鼠标点开关按钮时还会再做一次增量查找，当前匹配会上移一个。
- 主题变化时不重新查找，新颜色从下一次查找起生效；VS Code 会重新查找（当前匹配上移一个，而且只有当前匹配换色）。
- 匹配的边框色（`terminal.findMatchBorder`、`terminal.findMatchHighlightBorder`）不画：xterm.js 用装饰 DOM 元素的 outline 画，这里没有元素。暗色主题里这两个颜色本来就没有设置。
- 查找框用的是编辑器的 `IdeFindWidget`（去掉替换行），按键照 VS Code 的终端：输入框里 Enter 找上一个、⇧Enter 找下一个，F3/⌘G 下一个，⇧F3/⇧⌘G 上一个，⌘F（其他平台 Ctrl+F）打开，Escape 关闭并把键盘还给终端。
- 查找时没有临时关掉 `copyOnSelection`（VS Code 会）：这里 `copyOnSelection` 默认关，也没有设置项。

## 链接

- 没有链接的快速选择（“Open Detected Link…”、“Open Last Link”）。
- 悬停没有提示框：没有 “Follow link (cmd + click)”，没有按 `editor.multiCursorModifier` 换成 alt 的说法，也没有 “Follow link using forwarded port”。
- 不支持远程终端：`vscode-remote` 路径不解析；WSL 的 `/mnt/` 路径不转换（上游要问后端的 `wslpath`）。`\\wsl$\` 路径是否原样保留，按终端进程的系统判断，上游按应用所在的系统。
- `terminal.integrated.enableFileLinks` 和 `wordSeparators` 只是构造参数，还没有设置项；`enableFileLinks` 没有 `notRemote` 这一档。
- 不支持 OSC 8 超链接（xterm.js 的 `linkHandler`、`terminal.integrated.allowedLinkSchemes`），也没有扩展提供的链接。
- 单词链接只算出搜索文本；上游会先在工作区里找，找到唯一的文件就直接打开，找不到才打开快速打开。
- 每行的 cwd 要由 shell 集成通过 `cwdForLine` 提供，没有接上时一律用初始 cwd。
- 路径解析的缓存按 cwd 和链接一起作键（上游只按链接，cwd 变了会拿到旧结果）；10 秒的过期按时钟算，不用计时器。
- `file:` URI 用 Dart 的 `Uri` 表示：主机名转成小写，`file://c:/foo` 的空端口会被丢掉，变成主机 `c`。
- 打开方式：URL 交给系统浏览器，文件在编辑器里打开并跳到行列，工作区里的文件夹在资源管理器里展开；工作区外的文件夹交给系统的文件管理器（VS Code 是开新窗口），单词在快速打开里搜索。
- ⌘ 点击（其他平台 Ctrl 点击）才打开，按下和松开都要在同一个链接上。确定的链接（URL、存在的路径）悬停就有下划线，单词只在按住修饰键时才有。

## 聊天里的命令输出（M6）

聊天里命令的输出（`TerminalItem`）交给终端内核解析后只读显示（`lib/chat/widgets/terminal_output.dart`），VS Code 没有对应的功能，这里记下它的限制：

- 没有 ESC、`\r`、退格的输出原样显示，和以前完全一样。
- 没有最小对比度调整（VS Code 终端是 4.5），深色底上的黑字会看不清。
- 不画下划线样式和下划线颜色、上划线、闪烁；OSC 8 超链接只显示文字，不能点。
- 制表符变成空格；宽字符被挤到折行的下一行时可能多出一个空格。
- 带转义序列的输出超过约 1 万行时只留最后一段，和终端的回滚一样。
- 屏幕宽度按最长的行估算，在 80 到 500 列之间；高度最多 50 行，程序往上改写最多只能回到 50 行以内。
- 字符宽度用内核默认的 Unicode 6 表，没有加 unicode11 插件。
- 命令还在输出时展开，每次更新都会重新解析全部输出。

## Shell 集成

- VS Code 的 shell 集成脚本原样打包成 Dart 常量（由 `tool/generate_shell_integration_scripts.dart` 生成），每次运行时写到临时目录里新建的 0700 文件夹；VS Code 用安装目录里的脚本。
- zsh 的 ZDOTDIR 是这个文件夹下的 `zsh/`，不是 VS Code 的 `<tmp>/<用户>-<应用>-zsh` 加 sticky bit（Dart 不能 chmod）。
- `TERM_PROGRAM` 是 `baocode`，而 fish 的脚本只在 `vscode` 下运行：fish 的启动命令在 source 脚本期间把它临时改成 `vscode`，之后还原。
- 没有扩展的环境变量集合，`VSCODE_PATH_PREFIX` 从不设置。
- 没有 `terminal.integrated.shellIntegration.*` 设置项：注入由 `terminalLaunch` 的 `shellIntegration` 参数控制（默认开），装饰的显示由 `DecorationAddon` 的构造参数和 `setDecorationsEnabled` 控制。
- 命令检测只移植了 Unix 的启发式；`WindowsPtyHeuristics`（ConPTY 下调整提示符和命令位置）没有移植，`P;IsWindows=True` 只记下标志。录制的 Windows pwsh 会话测试照样通过。
- 没有遥测，所以也没有 shell 集成的激活超时。
- `NaiveCwdDetection`（没有 shell 集成时向进程查 cwd）没有实现，只有能力类型；命令检测的 `getLinesForCommand`（快速修复用）和 addon 的 `getMarkerId` 没有移植。
- 退出码不是数字（`parseInt` 得到 NaN）时记为没有退出码。
- 提示符输入模型完整移植，包括幽灵文本；上游 `_sync` 的 `@throttle(0)` 实际是立即执行，这里直接同步调用。幽灵文本检测里上游有一段永远不会拒绝的检查，省略了，结果相同。
- `ShellIntegration.recentCommands` 只有本次会话的命令；没有 VS Code 跨会话保存的命令历史，也不读 shell 的历史文件。
- 命令装饰是模型（`ShellIntegration.decorations`），由终端视图绘制，不是 xterm.js 的 DOM 元素；概览标尺的标记照 VS Code 注册到终端的装饰服务。
- 装饰画在网格左边 20 像素的留白里，悬停显示提示文字（markdown 的分隔线当作空行，不渲染 markdown），点击打开的菜单只有 “Rerun Command”、“Copy Command”、“Copy Output”；VS Code 还有 “Copy Output as HTML”、“Run Recent Command”、“Go To Recent Directory”、“Learn About Shell Integration” 和聊天相关的项。没有无障碍提示音，也不监听设置变化。备用屏幕上不显示装饰。
- 重新运行直接把命令加回车发给进程；VS Code 的 `runCommand` 会先处理提示符里已经输入的内容。
- 悬停里的开始时间近似上游的 `toLocaleString()`，写成 `yyyy-MM-dd HH:mm:ss`；“多久以前” 用 IDE 的 `ideFromNow`。`getDurationString` 只有短单位。
