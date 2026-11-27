# BaoCode


[English](README.md) · **简体中文** · [日本語](README_JA.md) · [Français](README_FR.md) · [Español](README_ES.md)

**开源 [Claude Code](https://github.com/anthropics/claude-code) 控制面，不仅仅是界面。**

细节拉满的 360FPS 界面之外，还有远程其他电脑的 Claude Code、手机随时接管、Windows 深度优化、10 倍效率的浏览器操控、完整代码编辑器、任意自定义 API、用量洞察、对话编排与 Bot。

[官网](https://baocode.dev/zh/) · [下载](https://baocode.dev/zh/download) · [更新日志](https://baocode.dev/zh/changelog)

![BaoCode 的 Agent 模式：多台机器上的智能体、进行中的对话及其用量](https://baocode.dev/readme/agent.webp)

![BaoCode 的 IDE 模式：文件树和编辑器，旁边是对话](https://baocode.dev/readme/ide.webp)

![BaoCode 能做什么：360 FPS 渲染、SSH 远程 Claude Code、浏览器操控、全模型接入、Windows 优化、用量与费用](https://baocode.dev/readme/features-zh.webp)

## 不重复造轮子，简单自然才好用

Claude Code 已经足够好，BaoCode 只补它缺的那部分。开箱即用，不用学新概念，用起来就像它本该如此。

**为什么是 Claude Code？** 无论基于哪个内核定制，做到最后都会长成 Claude Code 的样子：同样的工具、同样的上下文管理、同样的 Skill 与 MCP。与其绕一圈重造，不如直接用它，再在协议层接入其他模型，一套配置通用全部。BaoCode 运行你已经装好的 Claude Code，沿用你的设置、登录和 `CLAUDE.md`；没装 Claude Code 的地方，由 BaoCode 内置的智能体读取同样的设置，跑在你添加的模型供应商上。

**一个对话就能调度全部。** 不做复杂的编排画布。主对话通过内置 MCP 直接调度其他会话和子代理，跨服务器也一样；复杂的流程口述一遍，或写成 Skill 就能反复用。

## 功能

### GPU 360FPS 原生绘制

彻底放弃 Electron 与 DOM 重排。BaoCode 是原生应用，界面直接用 GPU 绘制：高吞吐流式输出稳锁高刷，滚动跟手，思考等待时自动降频。

| | BaoCode | VS Code | Cursor |
| --- | --- | --- | --- |
| 启动 | 约 0.18 秒 | 约 2–3 秒 | 约 2–3 秒 |
| 单窗口空闲内存 | 约 120 MB | 约 970 MB | 约 1.9 GB |
| 单窗口进程数 | 2 | 8 | 13 |
| Windows 下载大小 | 约 16 MB | 约 244 MB | 约 214 MB |

### 全平台 SSH 远程 Claude Code

任意连接多台 Linux、macOS 或 Windows 主机并使用其自身的 Claude Code，同时无缝打通本机：云端编译，直接调试插在本机 Type-C 上的安卓真机和本机 Chrome，端口也一样转回来。窗口留在本机，文件、Git、搜索、终端、语言服务器和 Claude Code 都在远端运行。Windows 上的 WSL 发行版也能这样打开。

### 10 倍浏览器操作效率

装上 BaoCode 浏览器扩展（Chrome、Edge、Brave、Arc），智能体直接接管你已登录的 Chrome，不再靠盲目截屏：渐进暴露压感微操、React/Vue 组件 State、WebSocket 透视、源码断点与 1ms 性能剖析。它只看得到你分享给它的标签页，数据都留在你的电脑上。

### 全模型接入，换谁都好用

DeepSeek、Kimi、ChatGPT、Gemini 等主流模型与 OpenRouter、Ollama 等平台直接接入。协议差异（Anthropic Messages、OpenAI Chat Completions 与 Responses、Codex、Gemini）由 BaoCode 的本地代理适配，不改动 `~/.claude`、无需额外代理工具，在 Claude Code 里一样表现出色。密钥存在系统钥匙串里。

### 用量与精确计费

看清 token 花在哪：输入、输出、缓存读写、缓存命中率和省下的钱。价格按各家规则计算，峰谷时段、节假日、阶梯上下文都算在内。

### 深度 Windows 终端与渲染优化

[bash.exe](https://github.com/baocode-dev/bash-exe) 为你的 Windows 抹平了平台差异，用起来与 WSL 差不多；界面与 macOS 同走 Skia GPU 渲染，一样顺滑。支持 x64 和 Arm64。

### 移动端无损同屏

同一份实时会话、400K 上下文明细、多模型切换与全部 SSH 远程代码库，完整延伸到 iOS 与 Android。扫码配对，直连或经 BaoCode 中继，全程端到端加密。

### 完整代码编辑器

内置编辑器（Monaco 移植到 Flutter）、终端，以及带提交图的源代码管理，支持语言服务器和 VS Code、IntelliJ、Sublime、Atom 快捷键。Claude Code 帮你写提交信息。编辑器、对话和侧边栏统一跟随你的 VS Code 主题。

### 还有

- **逐文件保留或撤销** Claude 做的修改；检查点存在 BaoCode 自己的数据目录里，不碰仓库的 `.git`。
- **目标。** 输入 `/goal` 和你要完成的事，Claude 会一直干到达成为止。
- **富文本输入。** 从编辑器复制的代码以文件和行号引用的形式进入输入框；粘贴的图片、拖入的文件就停在句子里你放的位置。
- **插件、MCP 服务器、Skill**、子代理、规则、命令和 hooks 集中管理，可以全局用，也可以只给某个项目。
- **通知。** 智能体需要你或完成任务时提醒你。关掉窗口，智能体继续在菜单栏或托盘里运行。
- **自动更新**，可以后台更新、手动更新，或者关掉。

## 系统要求

- **电脑：** macOS 12 或更高版本（Apple 芯片或 Intel），Windows 10 或更高版本（x64 或 Arm64），或 Linux：Ubuntu 22.04 或更高版本及其他基于 Debian 的发行版（x64 或 arm64）。
- **手机：** Android 7.0 或更高版本，或 iOS 15 或更高版本（TestFlight 测试版），需要和电脑上的 BaoCode 配对。
- **浏览器扩展：** Chrome、Edge、Brave 或 Arc，macOS 或 Windows 上。
- 装了 [Claude Code](https://github.com/anthropics/claude-code) 就用它；没装的话，添加一个模型供应商即可。

全部安装包见[下载页](https://baocode.dev/zh/download)。

## 从源码构建

BaoCode 是 Flutter 应用（Dart SDK `^3.13.4`）。

```sh
flutter pub get
flutter run -d macos        # Windows 用：flutter run -d windows
```

构建发行版本，产物写入 `build/installers/`：

```sh
dart run tool/build_macos.dart            # BaoCode-<version>-{arm64,x64}.dmg 和 BaoCode-<version>-mac-{arm64,x64}.zip
dart run tool/build_windows.dart          # BaoCode-<version>-setup.exe（需要 Inno Setup）
flutter build linux --release && sh tool/package_linux_deb.sh   # BaoCode-<version>-linux-{amd64,arm64}.deb 和 .tar.gz，在 Ubuntu 上
dart run tool/build_remote_server.dart    # SSH 远程服务端，用于 Linux、macOS 和 Windows 主机
```

完整测试套件很慢，只跑和改动相关的测试，例如 `flutter test test/update`。

推送 `v*` 标签后，CI 会构建并发布。版本号、签名和发布位置见 [docs/release.md](docs/release.md)。更多文档在 [docs/](docs)：[自动更新](docs/auto-update.md)、[SSH 远程](docs/ssh-remote.md)、[Windows](docs/windows.md)、[手机连接](docs/mobile-link.md)。

## 仓库结构

| 路径 | 内容 |
| --- | --- |
| [lib/](lib) | 应用代码 |
| [packages/bao_agent](packages/bao_agent) | 内置智能体，使用 Claude Code 的 stream-json 协议 |
| [packages/bao_editor](packages/bao_editor) | 移植到 Flutter 的 Monaco：编辑器、语法高亮、VS Code 主题和快捷键 |
| [packages/bao_xterm](packages/bao_xterm) | xterm.js 的 Dart 移植 |
| [packages/bao_pty](packages/bao_pty)、[bao_conpty](packages/bao_conpty) | Dart 伪终端：macOS、Linux 用 forkpty，Windows 用 ConPTY |
| [packages/bao_remote](packages/bao_remote) | 通过 SSH 提供服务的远程端 |
| [packages/bao_link](packages/bao_link)、[bao_iroh](packages/bao_iroh) | 和手机的连接：扫码配对，经 iroh 端到端加密 |
| [packages/bao_markdown](packages/bao_markdown) | 所见即所得的 Markdown 编辑器 |
| [packages/bao_websearch](packages/bao_websearch) | 不用搜索 API 的网页搜索，任何模型都能用 |
| [browser_extension/](browser_extension) | 浏览器扩展 |
| [macos/](macos)、[windows/](windows)、[linux/](linux) | 原生平台启动器 |
| [tool/](tool) | 构建、打包及发布脚本 |
| [site/](site) | 官网 [baocode.dev](https://baocode.dev/zh/) 的源码 |
| [docs/](docs) | 设计文档 |

## 反馈

欢迎提交 Issue 和 Pull Request。改动请先在 Issue 里讨论；太大的 PR、未经讨论的 PR，不会被接受。详见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 许可证

BaoCode 使用 [GNU General Public License v3.0](LICENSE)（GPL-3.0-only）许可证。[packages/](packages) 中的编辑器和终端相关包（bao_editor、bao_xterm、bao_pty）使用 MIT 许可证。第三方组件保留其自身许可证，具体文件位于对应源码旁。

BaoCode 是独立项目，与 Anthropic 无隶属关系，也未获得其背书。

<img width="480" alt="扫码加入 BaoCode 微信交流群" src="site/readme/wechat-group.jpg" />
