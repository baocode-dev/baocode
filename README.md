# BaoCode
<a href="https://trendshift.io/repositories/289180?utm_source=trendshift-badge&amp;utm_medium=badge&amp;utm_campaign=badge-trendshift-289180" target="_blank" rel="noopener noreferrer"><img src="https://trendshift.io/api/badge/trendshift/repositories/289180/daily?language=Dart" alt="baocode-dev%2Fbaocode | Trendshift" width="250" height="55"/></a>

**English** · [简体中文](README_CN.md) · [日本語](README_JA.md) · [Français](README_FR.md) · [Español](README_ES.md)

**The open-source control plane for [Claude Code](https://github.com/anthropics/claude-code). More than an interface.**

Beyond a detail-rich 360 FPS interface: Claude Code on your other machines, control from your phone, deep Windows tuning, 10× faster browser control, a full code editor, any custom API, usage insights, conversation orchestration and Bots.

[Website](https://baocode.dev) · [Download](https://baocode.dev/download) · [Changelog](https://baocode.dev/changelog)

![BaoCode in Agent mode: agents on several machines, a conversation at work and its usage](https://baocode.dev/readme/agent.webp)

![BaoCode in IDE mode: the file tree and the editor, with the conversation beside them](https://baocode.dev/readme/ide.webp)

![What BaoCode does: 360 FPS rendering, Claude Code over SSH, the browser, any model, Windows, usage and cost](https://baocode.dev/readme/features-en.webp)

## No reinvented wheels, just what works

Claude Code is already good; BaoCode adds only what it lacks. It works out of the box, with nothing new to learn, and feels the way it always should have.

**Why Claude Code?** Customize any agent core far enough and it ends up shaped like Claude Code: the same tools, the same context handling, the same skills and MCP. Rather than rebuild it the long way round, BaoCode uses it directly and bridges other models at the protocol layer, so one setup works with all of them. It runs the Claude Code you already have, with your settings, your sign-in and your `CLAUDE.md`; where Claude Code isn't installed, BaoCode's built-in agent reads the same settings and runs on a model provider you add.

**One conversation runs the rest.** No orchestration canvas. Through built-in MCP, the main conversation directs other sessions and subagents, across servers too; describe a complex flow once, or write it as a skill to reuse.

## Features

### GPU 360 FPS native rendering

No Electron, no DOM reflow. BaoCode is a native app that draws its interface straight on the GPU: fast token streams keep pace with your display's refresh rate, scrolling follows your hand, and it throttles itself down while it waits.

| | BaoCode | VS Code | Cursor |
| --- | --- | --- | --- |
| Launch | ≈ 0.18 s | ≈ 2–3 s | ≈ 2–3 s |
| Memory, one window idle | ≈ 120 MB | ≈ 970 MB | ≈ 1.9 GB |
| Processes, one window | 2 | 8 | 13 |
| Download size, Windows | ≈ 16 MB | ≈ 244 MB | ≈ 214 MB |

### Claude Code over SSH, on any machine

Attach to any Linux, macOS or Windows host and use the Claude Code installed there, while it reaches straight back to your own machine: the Android phone on your USB-C port, your local Chrome, your ports. The window stays with you; files, Git, search, terminals, language servers and Claude Code run on the host. On Windows, WSL distributions open the same way.

### 10× faster browser control

With the BaoCode extension (Chrome, Edge, Brave, Arc), agents work in your live, signed-in browser rather than in a loop of blind screenshots: stylus-grade input, React and Vue state, WebSocket tracing, source breakpoints and 1 ms performance profiling. They only see the tabs you share with them, and everything stays on your computer.

### Every model, plugged in

DeepSeek, Kimi, ChatGPT, Gemini and the other leading models, and platforms like OpenRouter and Ollama, plug straight in. BaoCode adapts each protocol (Anthropic Messages, OpenAI Chat Completions and Responses, Codex, Gemini) in a local proxy, without touching `~/.claude`, so every one of them performs just as well in Claude Code. Keys stay in the system keychain.

### Usage and pricing

See where the tokens go: input, output, cache reads and writes, the cache hit rate and what it saved. Prices follow each provider's rules, peak and off-peak hours, holidays and tiered context included.

### Made for Windows

[bash.exe](https://github.com/baocode-dev/bash-exe) smooths over your Windows' platform differences, so it works much like WSL, and the interface renders on Skia's GPU path just as smoothly as on macOS. x64 and Arm64.

### Your phone, the same sessions

The exact same live sessions, 400K context breakdowns, model quotas and SSH remote codebases, mirrored natively to iOS and Android. Pair by QR code; the connection is end-to-end encrypted, direct or through BaoCode's relays.

### A full code editor

An editor (Monaco, ported to Flutter), a terminal and Source Control with a commit graph, built in, with language servers and VS Code, IntelliJ, Sublime and Atom keymaps. Claude Code drafts your commit messages. Your VS Code themes color the editor, the conversation and the sidebar alike.

### And

- **Keep or Undo** each change Claude made, file by file; checkpoints live in BaoCode's own data folder, never in your repository's `.git`.
- **Goals.** Type `/goal` and what you want done, and Claude keeps working until it is met.
- **A rich-text input.** Code copied from the editor arrives as a reference to its file and lines; pasted images and dropped files sit where you put them in the sentence.
- **Plugins, MCP servers, skills,** subagents, rules, commands and hooks in one place, for you or for a single project.
- **Notifications** when an agent needs you or finishes. Close the window and the agents keep running in the menu bar or tray.
- **Updates itself** in the background, or manually, or not at all.

## Requirements

- **Desktop:** macOS 12 or later (Apple silicon or Intel), Windows 10 or later (x64 or Arm64), or Linux: Ubuntu 22.04 or later and other Debian-based distributions (x64 or arm64).
- **Phone:** Android 7.0 or later, or iOS 15 or later (beta on TestFlight), paired with BaoCode on a computer.
- **Browser extension:** Chrome, Edge, Brave or Arc, on macOS or Windows.
- [Claude Code](https://github.com/anthropics/claude-code), if you have it; without it, a model provider you add.

All of it is on the [download page](https://baocode.dev/download).

## Building from source

BaoCode is a Flutter app (Dart SDK `^3.13.4`).

```sh
flutter pub get
flutter run -d macos        # or: flutter run -d windows
```

To build what is released, into `build/installers/`:

```sh
dart run tool/build_macos.dart            # BaoCode-<version>-{arm64,x64}.dmg and BaoCode-<version>-mac-{arm64,x64}.zip
dart run tool/build_windows.dart          # BaoCode-<version>-setup.exe (needs Inno Setup)
flutter build linux --release && sh tool/package_linux_deb.sh   # BaoCode-<version>-linux-{amd64,arm64}.deb and .tar.gz, on Ubuntu
dart run tool/build_remote_server.dart    # the SSH remote server, for Linux, macOS and Windows hosts
```

The full test suite is slow; run the tests for what you changed, for example `flutter test test/update`.

Releases are built and published by CI when a `v*` tag is pushed; versions, signing and where releases go are in [docs/release.md](docs/release.md). More in [docs/](docs): [auto-update](docs/auto-update.md), [SSH remote](docs/ssh-remote.md), [Windows](docs/windows.md), [the phone link](docs/mobile-link.md) (some are in Chinese).

## Repository

| Path | What it is |
| --- | --- |
| [lib/](lib) | The app |
| [packages/bao_agent](packages/bao_agent) | The built-in agent, speaking Claude Code's stream-json protocol |
| [packages/bao_editor](packages/bao_editor) | Monaco, ported to Flutter: the editor, its highlighting, VS Code's themes and keybindings |
| [packages/bao_xterm](packages/bao_xterm) | A Dart port of xterm.js |
| [packages/bao_pty](packages/bao_pty), [bao_conpty](packages/bao_conpty) | Pseudo terminals for Dart: forkpty on macOS and Linux, ConPTY on Windows |
| [packages/bao_remote](packages/bao_remote) | The remote host served over SSH |
| [packages/bao_link](packages/bao_link), [bao_iroh](packages/bao_iroh) | The link to your phone: QR pairing, end-to-end encrypted connections over iroh |
| [packages/bao_markdown](packages/bao_markdown) | A markdown editor that renders as you type |
| [packages/bao_websearch](packages/bao_websearch) | Web search for any model, without a search API |
| [browser_extension/](browser_extension) | The browser extension |
| [macos/](macos), [windows/](windows), [linux/](linux) | The native runners |
| [tool/](tool) | Build, packaging and release scripts |
| [site/](site) | The website, [baocode.dev](https://baocode.dev) |
| [docs/](docs) | Design notes |

## Feedback

Issues and pull requests are welcome. Discuss a change in an issue before you write it; large pull requests, and pull requests for changes not discussed first, are not accepted. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

BaoCode is licensed under the [GNU General Public License v3.0](LICENSE)
(GPL-3.0-only). The editor and terminal packages in [packages/](packages)
(bao_editor, bao_xterm, bao_pty) are MIT. Third-party components keep their
own licenses, found next to them in the source tree.

BaoCode is an independent project, not affiliated with or endorsed by
Anthropic.

<img width="720" height="1094" alt="image" src="https://github.com/user-attachments/assets/317028c7-4baa-4009-9ca4-6a900ba200a8" />
