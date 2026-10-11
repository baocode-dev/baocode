# BaoCode

[English](README.md) · **简体中文** · [日本語](README_JA.md) · [Français](README_FR.md) · [Español](README_ES.md)

一个出色、易用的 [Claude Code](https://github.com/anthropics/claude-code) 桌面界面，内置毫秒级响应的快速 IDE。

[官网](https://baocode.dev) · [下载](https://baocode.dev/download) · [更新日志](https://baocode.dev/changelog)

![BaoCode 主窗口：按项目分组的智能体、并排显示的两个对话，以及模型选择器](site/shots/main.png)

> 本文是英文 README 的中文介绍；如内容有差异，以 [English](README.md) 为准。链接指向的文档和网站不一定提供中文版本。

## 为什么做 BaoCode

我们每天都在使用 Claude Code。终端适合运行它，却不适合阅读它：长篇 diff 很容易滚出视野，先前的步骤难以重新找到，审查修改又需要切换应用。BaoCode 就是我们希望为它提供的那个窗口。

BaoCode 有意不包含自己的智能体。Claude Code 才是智能体，它拥有工具、技能、插件、MCP 服务器、子智能体和 hooks 生态。BaoCode 为它提供易于阅读的界面，并让周边功能开箱即用。它运行你已经安装的 Claude Code，沿用你的设置和 `CLAUDE.md`。

## 功能

- **为阅读而生的界面。** 文件读取、搜索和命令可以折叠为单行。Claude 做出的修改可以逐文件保留或撤销；检查点保存在 BaoCode 自己的数据目录中，不会写入仓库的 `.git`。
- **目标。** 输入 `/goal` 和你希望完成的任务，Claude 会持续工作直到达成目标，输入框上方会显示目标及进度。
- **富文本输入。** 从编辑器复制的代码会以文件和行号引用的形式加入输入；粘贴的图片和拖入的文件可以放在句子中指定的位置。
- **快速 IDE。** 内置编辑器、终端，以及带提交图的源代码管理。Claude Code 可以起草提交信息，并支持快捷键映射和语言服务器。
- **统一主题。** 编辑器、对话和侧边栏采用一致的主题样式。
- **技能、MCP 服务器及更多扩展。** 在同一处管理插件、MCP 服务器、技能、子智能体、规则、命令和 hooks，可供个人使用或限定于某个项目。
- **多种模型。** 可以添加兼容 Anthropic API、OpenAI Chat Completions 或 OpenAI Responses 的供应商，本地代理负责与 Claude Code 之间的协议转换。密钥保存在系统密钥环中。
- **通过 SSH 使用远程项目。** 窗口留在本机，文件、Git、搜索、终端、语言服务器和 Claude Code 则运行在远程主机上（Linux，x64 或 arm64）。
- **通知。** 智能体需要你的操作或完成任务时，会通过系统通知、声音和角标提醒。关闭窗口后，智能体可以继续在菜单栏或系统托盘中运行。
- **自动更新。** 可选择后台自动更新、手动更新，或关闭更新。

## 速度

BaoCode 是原生应用，直接通过 GPU 绘制界面。以下为英文 README 中列出的 BaoCode 数值，并非本翻译重新测量的结果；实际表现取决于硬件、版本和使用场景。

| 指标 | BaoCode |
| --- | --- |
| 启动时间 | 约 0.18 秒 |
| 单窗口空闲内存占用 | 约 120 MB |
| 单窗口进程数 | 2 |
| Windows 下载大小 | 约 16 MB |

## 系统要求

- macOS 12 或更新版本（Apple 芯片和 Intel 各提供一个下载版本），或 Windows 10 或更新版本（x64）。
- 已安装 [Claude Code](https://github.com/anthropics/claude-code)。

## 从源码构建

BaoCode 使用 Flutter 开发，Dart SDK 要求为 `^3.13.4`。

```sh
flutter pub get
flutter run -d macos        # Windows 使用：flutter run -d windows
```

构建发行版本，产物写入 `build/installers/`：

```sh
dart run tool/build_macos.dart            # BaoCode-<version>-{arm64,x64}.dmg 和 BaoCode-<version>-mac-{arm64,x64}.zip
dart run tool/build_windows.dart          # BaoCode-<version>-setup.exe（需要 Inno Setup）
dart run tool/build_remote_server.dart    # 用于 Linux x64 和 arm64 的 SSH 远程服务器
```

完整测试套件运行较慢，开发时应只运行与修改相关的测试，例如 `flutter test test/update`。

推送 `v*` 标签后，CI 会构建并发布发行版本。版本号、签名及发布位置的说明见 [docs/release.md](docs/release.md)。更多文档位于 [docs/](docs)，包括[自动更新](docs/auto-update.md)、[SSH 远程](docs/ssh-remote.md)和 [Windows](docs/windows.md)，其中部分文档为中文。

## 仓库结构

| 路径 | 内容 |
| --- | --- |
| [lib/](lib) | 应用代码 |
| [packages/bao_editor](packages/bao_editor) | 编辑器，以及语法高亮、主题和快捷键支持 |
| [packages/bao_xterm](packages/bao_xterm) | xterm.js 的 Dart 移植版本 |
| [packages/bao_pty](packages/bao_pty) | Dart 伪终端支持：macOS、Linux 使用 forkpty，Windows 使用 ConPTY |
| [packages/bao_remote](packages/bao_remote) | 通过 SSH 提供服务的远程端 |
| [macos/](macos)、[windows/](windows) | 原生平台启动器 |
| [tool/](tool) | 构建、打包及发布脚本 |
| [site/](site) | 官网 [baocode.dev](https://baocode.dev) 的源码 |
| [docs/](docs) | 设计文档 |

## 反馈

欢迎提交 Issue。项目上游不接受 Pull Request。

## 许可证

BaoCode 使用 [GNU General Public License v3.0](LICENSE)（GPL-3.0-only）许可证。[packages/](packages) 中的编辑器和终端相关包（bao_editor、bao_xterm、bao_pty）使用 MIT 许可证。第三方组件保留其自身许可证，具体文件位于对应源码旁。

BaoCode 是独立项目，与 Anthropic 无隶属关系，也未获得其背书。
