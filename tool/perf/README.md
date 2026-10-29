# End-to-end performance tests

The whole app (sidebar, chat, Fast Ide), in profile mode, under what users do
to it: agents streaming markdown and code, typing and scrolling in big files,
several agents at once. Each scenario is measured as it runs, and its figures
are compared with a baseline, to see what a change does to them.

```sh
dart run tool/perf/run.dart --save-baseline      # on main: what to compare with
# ...change something...
dart run tool/perf/run.dart                      # all scenarios, 3 rounds each
dart run tool/perf/run.dart chat. ide.typing     # some (names or prefixes)
dart run tool/perf/run.dart stress.              # the limits only
dart run tool/perf/run.dart --check              # exit 1 on a regression,
                                                 # or memory over budget
dart run tool/perf/run.dart drag. select. caret. # the hands' scenarios
dart run tool/perf/run.dart --trace ide.typing   # where the time goes
dart run tool/perf/run.dart --list
```

The runner builds the app once (`flutter build <platform> --profile -t
tool/perf/perf_app.dart`; `--no-build` reuses it), runs every scenario in a
process of its own, round after round, and reports each figure's median. The
results go to `build/perf/<time>/`: `summary.json` (medians), `report.md` (a
table to paste in a PR), and `runs/` (each run's JSON and log). The baseline
is `build/perf/baseline.json` unless `--baseline` says otherwise. It is the
machine's own: figures from another machine, or another refresh rate, do not
compare.

While it runs, leave the machine alone: the window must stay in sight (a
window out of sight gets no frames), on the power adapter, with nothing heavy
running beside it. The app ignores the real mouse and stays focused as far
as it can tell, but when another app comes to the front it marks the phase
`disturbed`; the runner says so, and leaves those runs out of the medians
when others were not.

## The scenarios

`--list` lists them. In these groups:

- `chat.*`: an agent streaming at a model's usual pace, a fast one's and
  more (`stream`, `stream_fast`, `stream_flood`), below a long conversation
  (`long_history`), at work with many tools (`tools`), four side by side
  (`grid`) or out of sight (`background`); scrolling (`scroll`).
- `ide.*`: Fast Ide on a 9,000-line TypeScript file: opening it and
  switching files (`open`), typing (`typing`), scrolling (`scroll`).
- `mix.*`: the two at once: typing while agents stream
  (`type_while_streaming`), switching between the chat and the IDE
  (`layout_switch`) and between agents (`agent_switch`).
- `stress.*` ([perf_stress.dart](perf_stress.dart)): the limits, where the
  app is most sensitive: a 60k-character thought at 12,000 chars/s
  (`thinking`); a 240k-character answer, measured by thirds to show whether
  a delta costs more as the message grows (`huge_reply`); a 150-turn
  conversation spun through and jumped about by its minimap
  (`huge_history`); sixteen agents at once (`agents`); a 90,000-line file
  opened, jumped across, spun and flung through, typed into (`huge_file`);
  lines of 2,000+ characters (`long_lines`); forty files switched as fast as
  they show (`file_churn`); and all of it together (`everything`).
- The hands ([perf_interaction.dart](perf_interaction.dart)):
  - `drag.*`: what is dragged wider and narrower, at a mouse's pace: the
    sidebar's edge (`sidebar`), the side panel's (`side_panel`), the line
    between the stashes' cards and the stash shown (`stash`), the grid's
    lines, also while four agents answer (`grid`), the IDE's sashes
    (`ide`); and agents dragged from the sidebar into the grid
    (`agent_into_grid`).
  - `select.*`: text selected in the chat (`chat`: dragged over, a drag
    held past the top as the list scrolls, double and triple clicks, Cmd+A,
    a selection kept while an answer streams below it) and in the editor
    (`editor`: the same, and Shift+Down held; `huge_file`: Cmd+A and
    Cmd+C on 90,000 lines, Shift+Page Down), and in a stash (`stash`: the
    same, and a drag held past the bottom; `stash_huge`: 50,000 characters
    dragged over, its frames' build checked against a short stash's), and
    in a markdown file's preview (`markdown_huge`: 50,000 characters
    dragged over, against 2,000, then the wheel and flings).
  - `caret.*`: the editor's caret moved by the arrows, pages, to the ends
    (`editor`); the chat's input typed into, also while the agent answers
    (`composer`); both then left alone, to see the app at rest.
  - `idle.app`: the app left alone, nothing focused, on the chat and on
    the IDE: it should draw nothing.
  - `scroll.*`: a sidebar of 60 agents (`sidebar`), the stashes' cards
    (`stash`).
  - `memory.soak`: six rounds of a session's work (an agent answering, the
    IDE, the stashes), the footprint after each: whether memory comes back.
- `a11y.*`: long conversations (`long_history`, `huge_history`) with the
  semantics tree on, as Windows has it whenever something reads the window
  (an input method, a screen reader); the tree's size logged.
  `BAOCODE_PERF_SEMANTICS=1` turns it on for any scenario.
- `real.history` ([perf_transcript.dart](perf_transcript.dart)): a real
  session, a Claude Code transcript (`BAOCODE_PERF_TRANSCRIPT=<.jsonl>`;
  `BAOCODE_PERF_TRANSCRIPT_TURNS=n`, its first turns only) loaded turn by
  turn, spun through, and a reply streamed below it. Run it on the whole
  transcript and on one turn of it: the difference is what the history
  costs each frame.
- `hang.ui`: the UI thread held 7 s, past the hang watchdog's 6 on Windows
  (its report in the data folder's `logs\hangs`) or 4 on macOS
  (macos/Runner/HangWatchdog.swift: `[hang]` lines in the event log, a
  `/usr/bin/sample` in `hangs/` beside it, which
  `tool/symbolize_jank_sample.dart` reads). The Windows report, read with the symbols
  (`--extra-gen-snapshot-options=--save-debugging-info=<file>` as the app
  is built, then `--no-build`), should name `_holdUiThread`; and the event
  log a 7 s frame. `BAOCODE_PERF_EVENTS=<folder>` keeps the event log
  there; `BAOCODE_PERF_SLOW_MS` sets what it counts as a slow frame.
- `bench.text_layout`: what a paragraph costs to lay out, font by font
  (no cache): to compare machines and renderers.

## How it works

- **The app** ([perf_app.dart](perf_app.dart)) is `BaoCodeApp` itself, laid
  out in 1024×760 (the main window's default size; `--size` to change)
  whatever the window's size, on a temporary data folder and project.
- **The agents** ([perf_transport.dart](perf_transport.dart)) are Claude
  Code's adapter (`ClaudeCodeKernel`) over a transport that prints what a
  scenario wrote, line by line as the CLI prints it, at the pace it set
  (`PerfPace`: 400 chars/s typical, 1500 fast, 6000 flood). Each line is
  decoded from JSON on the UI isolate, as the process's output is; lines
  that fall due while the isolate is busy come at once after, as from a pipe.
  What they say ([perf_content.dart](perf_content.dart)) is generated from a
  seed: the same text every run.
- **Input** ([perf_input.dart](perf_input.dart)) goes in where the engine's
  does: pointer events (clicks, drags, mouse wheel notches, trackpad pan/zoom
  gestures) into the gesture binding; keys into `HardwareKeyboard` and the
  focus tree, through shortcuts and the editor's handling; and the characters a
  key that is not handled types, into the focused text input client as the
  input method would (`TextInput.updateEditingValue`).
- **Measuring** ([perf_probe.dart](perf_probe.dart)) is in the app; see below.
- **Checking**: what the hands did must have had its effect, whatever the
  frames: a sash where the pointer took it, a drag that selects what it went
  over and copies it, a selection that stays as an answer streams, the
  caret where the keys took it and on screen, every key typed in the input,
  the app at rest when left alone. A scenario says what it saw not happen
  (`c.check`); the runner lists it under `Failed checks`, and exits 1.

## The figures

For each phase of each scenario:

| Figure | What it is |
|---|---|
| `frames.buildMs` | The UI isolate's work per frame: build, layout, paint, composite (`FrameTiming.buildDuration`). |
| `frames.rasterMs` | The raster thread's per frame. |
| `frames.janky` | Frames whose build or raster alone took longer than the display's frame budget (6.9ms at 144Hz): each missed a refresh. |
| `uiIsolate.lateMs` | How late a timer due every 4ms fired: what holds the UI isolate, in frames or out of them (parsing, the transcript, timers). macOS fires timers ~2ms late at rest. |
| `uiIsolate.stalledMs` | The total of those delays longer than a frame: hitches the user feels. |
| `toSceneMs.<mark>` | From something happening to the end of the next frame on the UI isolate (the scene handed to the raster thread). |
| `toRasterMs.<mark>` | From it to that frame's raster finishing: on screen at the next refresh. Only where the engine's clock is the timeline's (`app.clockShared`), as it is. |
| `cpu.pctOfCore` | The process's CPU time (all threads) over the phase, in % of one core. |
| `memoryMb` | The physical footprint (Activity Monitor's memory, the GPU's for the app in it): at the start, its peak, at the end; and, on macOS, the end's parts, by `footprint`: `gpu` (Metal textures, IOSurfaces), `malloc` (the engine, Skia, fonts), `vmAllocate` (mostly the Dart heap). |

The marks: `delta` (streamed text read from the CLI), `key` (a key typed),
`scroll` (a wheel notch, a trackpad move), `drag` (a mouse move with the
button held: a sash, a selection, an agent), `action` (something a scenario
does and waits to see: a file opened, the layout switched, an agent picked).
Some scenarios add their own: `coloredMs` (a file opened until colored),
`switchMs`, `streamedChars`, `typedChars`.

The report compares the figures it shows with the baseline's: one more than
`--threshold` (10%) worse, and by more than the figure's noise floor (0.5ms
for a build p90, 20MB of memory...; see `_figures` in [run.dart](run.dart)),
is a regression.

Memory has a budget: **100–500MB, always**, whatever the scenario. Each
scenario's highest footprint (sampled every 100ms, its setting up too) is in
its results (`memoryPeakMb`) and beside each run as it ends; one over
`--memory-budget` (500) is listed under `Over the memory budget`, and fails
`--check`.

The app runs with the environment macOS gives it as it is opened (its
Info.plist's `LSEnvironment`: `MallocLargeCache=0`), which running its
executable does not give it by itself. `BAOCODE_PERF_FOOTPRINT=1` logs the
footprint's every part after each phase, and `BAOCODE_PERF_HEAP=1` the Dart
heaps and their largest classes (with the VM service's own 30MB in the
footprint).

## Finding where the time goes

`--trace` records each phase's timeline from the app's own VM service, with
every widget build, layout and paint in it, and writes it to
`build/perf/<time>/traces/<scenario>.<phase>.json`: open it in
<https://ui.perfetto.dev>. `--trace-detail` adds every layout and paint
(files of hundreds of MB). Recording costs time, so a traced run's figures
are not to compare. `--shots` saves a picture of the window after each phase, to
check the scenario showed what it meant to.

To look at one scenario in DevTools instead:

```sh
flutter run --profile -d macos -t tool/perf/perf_app.dart \
  --dart-define=BAOCODE_PERF_SCENARIOS=ide.typing \
  --dart-define=BAOCODE_PERF_REPO=$PWD
```

## Adding a scenario

Add a `PerfScenario` to `perfScenarios` in
[perf_scenarios.dart](perf_scenarios.dart): a name (`area.what`), what it
does, and its body. Set up first (history, files opened, `c.settle()`), then
measure in `c.phase('name', (r) async {...})`; `r.extra` takes figures of the
scenario's own. `PerfContext` has what the others use: agents and turns
(`c.history`, `c.agents`, `c.run`, `c.start`, `c.reply`), the IDE
(`c.openIde`, `c.openFile`, `c.focusEditor`, `c.editorSelection`,
`c.caretShown`), input (`c.input`: clicks, drags, the wheel, the trackpad,
keys, typing; `c.copy()`), finding widgets (`c.find`, `c.findKeyed`,
`c.rectOf`, `c.scrolledIn`), and `c.check(ok, what)` for what the user must
see happen.

## Caveats

- On macOS the app is the profile build of BaoCode itself, with its bundle
  id: it shares the installed app's user defaults. It leaves alone what
  would reach past its window ([perf_app.dart](perf_app.dart)'s binding):
  it does not move, resize or restyle the window, whose frame and
  appearance are kept there, nor copy to the clipboard (what it would
  copy, the scenarios check), nor touch the recent files or the trash.
- No language servers, Git or terminals: what they cost depends on the
  machine's.
- Windows and Linux builds run it too (the runner knows where their builds
  are), but have not been measured yet.
