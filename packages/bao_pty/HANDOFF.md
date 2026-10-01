# bao_pty 交接

在伪终端里跑进程：macOS/Linux 用 forkpty（`native/bao_pty.c`，由 `hook/build.dart` 通过 Dart 的 build hook 编译成 `bao_pty.framework`／`libbao_pty.so`），Windows 用 ConPTY（`lib/src/pty_windows.dart`，直接用 `dart:ffi` 调 kernel32，没有原生库）。库里没有 Flutter；网页上 `ptySupported` 为 false，`spawnPty` 抛 `PtyException`。

本文里的路径相对于包根目录；`../../` 开头的是 BaoCode 应用的文件。

## 边界

- 包里只有“起一个伪终端进程”：`spawnPty`、`Pty`（输出、写入、改大小、发信号、退出码）、`PtyLaunch`、`PtySignal`、`PtyException`。
- 应用自己的部分留在 `../../lib/ide/terminal/pty*.dart`：子进程登记（崩溃后清理残留进程）、`stopPtyProcesses`、终端环境变量（`TERM_PROGRAM=baocode` 等）和 shell 配置。不要把这些搬进包。
- 终端内核在 [bao_xterm](../bao_xterm/HANDOFF.md)，两个包互不依赖。

## 测试

- `test/pty_test.dart`：只在 macOS/Linux 跑，用 `/bin/sh -c` 和固定命令，在测试自己的临时目录里。
- `test/pty_windows_test.dart`：`ConsolePoll`、命令行引号（照 node-pty）、环境块这些纯逻辑各平台都跑；`ConPTY` 一组是 `cmd.exe` 的真实进程，只在 Windows 上跑，还没在 Windows 实机上跑过。
- 平台上的已知问题（Windows 上 Dart 分析器闪退的绕法、Linux 上退出码可能读成 0）记在 [bao_xterm 的 HANDOFF](../bao_xterm/HANDOFF.md#已知问题)。

## 发布计划

见 [bao_xterm 的 HANDOFF](../bao_xterm/HANDOFF.md#发布计划)，三个包一起发布。本包另有：

- 发布前在 Linux 和 Windows 实机上各跑一遍本包的测试。
