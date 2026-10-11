# BaoCode

**English** · [简体中文](README_CN.md) · [日本語](README_JA.md) · [Français](README_FR.md) · [Español](README_ES.md)

An awesome, easy-to-use desktop UI for [Claude Code](https://github.com/anthropics/claude-code), with a millisecond-fast IDE built in.

[Website](https://baocode.dev) · [Download](https://baocode.dev/download) · [Changelog](https://baocode.dev/changelog)

![BaoCode's main window: agents grouped by project, two conversations side by side, and the model picker](site/shots/main.png)

## Why

We use Claude Code every day. The terminal is a fine place to run it, but a poor place to read it: long diffs scroll out of view, earlier steps are hard to find again, and reviewing what changed means switching to another app. BaoCode is the window we wanted around it.

BaoCode has no agent of its own, by design. Claude Code is the agent, and its ecosystem is unmatched: its tools, skills, plugins, MCP servers, subagents and hooks. BaoCode gives it the interface it deserves and makes everything around it work out of the box. It runs the Claude Code you already have, with your settings and your `CLAUDE.md`.

## Features

- **An interface made for reading.** Reads, searches and commands fold into single lines. Keep or Undo each change Claude made, file by file; checkpoints live in BaoCode's own data folder, never in your repository's `.git`.
- **Goals.** Type `/goal` and what you want done, and Claude keeps working until it is met, with the goal and its progress above the input.
- **A rich-text input.** Code copied from the editor arrives as a reference to its file and lines; pasted images and dropped files sit where you put them in the sentence.
- **Fast IDE.** An editor, a terminal and Source Control with a commit graph, built in. Claude Code drafts your commit messages. VS Code, IntelliJ, Sublime and Atom keymaps, and language servers.
- **Your VS Code themes.** The editor, the conversation and the sidebar all follow them.
- **Skills, MCP servers and more.** Plugins, MCP servers, skills, subagents, rules, commands and hooks in one place, for you or for a single project.
- **Any model.** Add an upstream that speaks Anthropic's API, OpenAI's Chat Completions or OpenAI's Responses; a local proxy translates between it and Claude Code. Keys stay in the system keychain.
- **Remote projects over SSH.** The window stays on your machine; files, Git, search, terminals, language servers and Claude Code run on the remote host (Linux, x64 or arm64).
- **Notifications.** A system notification, a sound and a badge when an agent needs you or finishes. Close the window and the agents keep running in the menu bar or tray.
- **Updates itself** in the background, or manually, or not at all.

## Speed

VS Code and Cursor are built on Electron: each window is a web page, and every copy carries its own Chromium and Node.js. BaoCode is a native app that draws its own interface straight to the GPU.

| | BaoCode | VS Code | Cursor |
| --- | --- | --- | --- |
| Launch | ≈ 0.18 s | ≈ 2–3 s | ≈ 2–3 s |
| Memory, one window idle | ≈ 120 MB | ≈ 970 MB | ≈ 1.9 GB |
| Processes, one window | 2 | 8 | 13 |
| Download size, Windows | ≈ 16 MB | ≈ 244 MB | ≈ 214 MB |

## Requirements

- macOS 12 or later (Apple silicon or Intel, one download each), or Windows 10 or later (x64).
- [Claude Code](https://github.com/anthropics/claude-code), installed.

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
dart run tool/build_remote_server.dart    # the SSH remote server, for Linux x64 and arm64
```

The full test suite is slow; run the tests for what you changed, for example `flutter test test/update`.

Releases are built and published by CI when a `v*` tag is pushed; versions, signing and where releases go are in [docs/release.md](docs/release.md). More in [docs/](docs): [auto-update](docs/auto-update.md), [SSH remote](docs/ssh-remote.md), [Windows](docs/windows.md) (some are in Chinese).

## Repository

| Path | What it is |
| --- | --- |
| [lib/](lib) | The app |
| [packages/bao_editor](packages/bao_editor) | Monaco, ported to Flutter: the editor, its highlighting, VS Code's themes and keybindings |
| [packages/bao_xterm](packages/bao_xterm) | A Dart port of xterm.js |
| [packages/bao_pty](packages/bao_pty) | Pseudo terminals for Dart: forkpty on macOS and Linux, ConPTY on Windows |
| [packages/bao_remote](packages/bao_remote) | The remote host served over SSH |
| [macos/](macos), [windows/](windows) | The native runners |
| [tool/](tool) | Build, packaging and release scripts |
| [site/](site) | The website, [baocode.dev](https://baocode.dev) |
| [docs/](docs) | Design notes |

## Feedback

Issues are welcome. Pull requests are not accepted.

## License

BaoCode is licensed under the [GNU General Public License v3.0](LICENSE)
(GPL-3.0-only). The editor and terminal packages in [packages/](packages)
(bao_editor, bao_xterm, bao_pty) are MIT. Third-party components keep their
own licenses, found next to them in the source tree.

BaoCode is an independent project, not affiliated with or endorsed by
Anthropic.
