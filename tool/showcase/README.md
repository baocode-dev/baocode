# The showcase

The website's pictures and short videos of BaoCode, made by the app
itself: no one takes them by hand, and nothing in them is anyone's real
data. `run.dart` sets up a made-up developer's machine, builds the
showcase app, plays its scenes and turns what they took into the files
in `site/shots/<lang>/`.

```sh
dart run tool/showcase/run.dart                 # all scenes, en and zh
dart run tool/showcase/run.dart main ide        # some scenes
dart run tool/showcase/run.dart --locale zh     # one language
dart run tool/showcase/run.dart --no-build      # the app as last built
dart run tool/showcase/run.dart --no-video      # pictures only
dart run tool/showcase/run.dart --publish       # into site/shots/<lang>/
```

macOS only, with `ffmpeg` and `cwebp` (Homebrew's `ffmpeg` and `webp`).
The pictures are taken from what the app draws, laid out at a fixed size
and pixel ratio, then framed on a wallpaper of their own
(`show_camera.dart`), so they don't depend on the display, the desktop or
the windows around it. The app's window shows while it runs; the mouse
over it changes nothing.

## What is made up

- **The machine** (`run.dart`): a home folder per language in
  `/Users/Shared/bao-showcase/<lang>/`, outside the user's own, so no path
  of theirs can show: a Git identity, a zsh prompt, a `bun` that prints
  the tests' results, the projects in `~/code` (hono, a real clone, fetched
  once into `build/showcase/repos/`; the others small repositories), their
  past Claude Code sessions in `~/.claude/projects/`, and skills.
- **The story** (`story.dart`): the projects, well-known open-source
  repositories, with their past conversations; the skills; in English and
  in Chinese.
- **The agents** (`show_transport.dart`, `scripts.dart`, `code.dart`): the
  app's own Claude Code adapter, talking to a scripted stand-in for the
  CLI that answers each message with a script: text streamed, tools
  called (files really written, so that the app's checkpoints and Git
  see them), subagents and background tasks started and done, holds where
  a scene takes its picture. No model is asked anything, and nothing goes
  over the network but the one clone of hono.

## The scenes

`scenes.dart`: each a fresh `BaoCodeApp` on the same machine, driven as a
user would (clicks on text, keys, commands), ending in pictures
(`ShowScene.shot`) or a video (`ShowScene.record`). While a video is
recorded the app runs four times slower and each frame is taken at its
own time, so the video is smooth however long a frame takes to draw.

`run.dart` then makes each picture a WebP 1568 pixels wide, a poster for
each video, and the home page's tiles: parts of some pictures, closer
(`_tiles`).

| Scene | Makes |
| --- | --- |
| `main` | `main`: two agents side by side, subagents, background tasks |
| `ide` | `main-ide`, `ide`: Fast IDE with the agent beside; Source Control |
| `review` | `review`: the agent's changes beside the chat, to keep or undo |
| `goal` | `goal`: a `/goal` in progress |
| `composer` | `composer`: pictures and a code reference in the input, a message queued |
| `models` | `models`, `model-picker`: the upstreams; the model picker |
| `customize` | `customize`: the skills |
| `notifications` | `notifications` |
| `themes-light` | `themes-light`: Bao Light, search open |
| `themes-dark` | `themes-dark`: Fast IDE in Kimbie Dark, the theme list open |
| `video-agents` | `agents.mp4` |
| `video-ide` | `ide.mp4` |
| `video-themes` | `themes.mp4` |

A run's log is `build/showcase/showcase-<lang>.log`; the pictures before
they are converted are in `build/showcase/out/<lang>/`.
