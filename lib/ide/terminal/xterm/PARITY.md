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

- `TERM_PROGRAM` 是 `monad`，没有 `TERM_PROGRAM_VERSION`。
- 直接启动 `$SHELL` 本身；VS Code 是按名字在 PATH 里找对应的配置。不查 `/etc/passwd`。
- Linux 上启动 shell 不加登录参数；macOS 上 bash、zsh、fish 加 `-l`，tmux、pwsh 不加，其他名字里带 zsh 或 bash 的加 `--login`。
- Windows 按 VS Code 的顺序找 PowerShell，找不到再用 `ComSpec`，最后是 `cmd.exe`。

## 绘制

- 自定义字形没有 octant（上游这个 commit 也没有）；sextant 的边缘和上游一样有半像素。
- 阴影字形（░▒▓）保留颜色自身的透明度；上游对 `#rrggbbaa` 会强制不透明，看起来是上游的 bug。
- 半透明的主题色用的是精确的十六进制值；VS Code 用 `rgba()` 两位小数，透明度可能差一级。
