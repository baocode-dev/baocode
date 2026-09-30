/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Terminal sessions recorded with VS Code's `Developer: Record Terminal
// Session`, as its shell integration recordings test replays them.
//
// Converted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/contrib/terminal/test/browser/xterm/recordings/ (each
// file's `events`, in order; the comments are the files').

/// An event: `type` is `resize` (with `cols` and `rows`), `output`,
/// `input`, `sendText` or `promptInputChange` (with `data`), `command`
/// (with `id`), or one of `commandDetection.*` (with `data`, ignored).
typedef RecordedSessionEvent = Map<String, Object>;

// macOS 15.5
// zsh 5.9
// powerlevel10k 8fa10f4
// Steps:
// - Open terminal
// - Type ls
// - Press enter
const basicMacosZshP10kLsOneTime = <RecordedSessionEvent>[
  {'type': 'resize', 'cols': 107, 'rows': 24},
  {
    'type': 'output',
    'data': '\x1b[1m\x1b[7m%\x1b[27m\x1b[1m\x1b[0m                                                                                                          \r \r',
  },
  {
    'type': 'output',
    'data': '\r\x1b[0m\x1b[27m\x1b[24m\x1b[J\x1b[0m\x1b[38;5;238m\x1b[49m\x1b[39m\x1b]133;A\x07\r\n\x1b[A\x1b[38;5;238m╭─\x1b[0m\x1b[38;5;238m\x1b[48;5;234m\x1b[38;5;31m \x1b[1m\x1b[38;5;31m\x1b[48;5;234m\x1b[38;5;39m~\x1b[0m\x1b[38;5;39m\x1b[48;5;234m\x1b[48;5;234m\x1b[38;5;31m/playground/\x1b[1m\x1b[38;5;31m\x1b[48;5;234m\x1b[38;5;39mtest1\x1b[0m\x1b[38;5;39m\x1b[48;5;234m\x1b[48;5;234m\x1b[38;5;31m\x1b[0m\x1b[38;5;31m\x1b[48;5;234m\x1b[48;5;234m\x1b[38;5;31m \x1b[0m\x1b[38;5;31m\x1b[48;5;234m\x1b[49m\x1b[38;5;234m▓▒░\x1b[0m\x1b[38;5;234m\x1b[49m\x1b[39m                                                              \x1b[0m\x1b[49m\x1b[38;5;234m░▒▓\x1b[0m\x1b[38;5;234m\x1b[48;5;234m\x1b[38;5;70m \x1b[0m\x1b[38;5;70m\x1b[48;5;234m\x1b[48;5;234m\x1b[38;5;70m✔\x1b[0m\x1b[38;5;70m\x1b[48;5;234m\x1b[48;5;234m\x1b[38;5;70m \x1b[0m\x1b[38;5;70m\x1b[48;5;234m\x1b[48;5;234m\x1b[38;5;70m\x1b[0m\x1b[38;5;70m\x1b[48;5;234m\x1b[48;5;234m\x1b[38;5;66m\x1b[38;5;242m│\x1b[0m\x1b[38;5;242m\x1b[48;5;234m\x1b[48;5;234m\x1b[38;5;66m 07:26:58\x1b[0m\x1b[38;5;66m\x1b[48;5;234m\x1b[48;5;234m\x1b[38;5;66m\x1b[0m\x1b[38;5;66m\x1b[48;5;234m\x1b[48;5;234m\x1b[38;5;66m \x1b[0m\x1b[38;5;66m\x1b[48;5;234m\x1b[49m\x1b[39m\x1b[38;5;238m─╮\r\n\x1b[38;5;238m╰─\x1b[0m\x1b[38;5;238m\x1b[49m\x1b[39m\x1b[0m\x1b[49m\x1b[39m \x1b[0m\x1b[49m\x1b[39m\x1b]133;B\x07\x1b[K\x1b[101C\x1b[0m\x1b[49m\x1b[39m\x1b[38;5;238m─╯\x1b[39m\x1b[103D\x1b[?2004h',
  },
  {'type': 'promptInputChange', 'data': '|'},
  {
    'type': 'promptInputChange',
    'data': '|                                                                                                     ─╯',
  },
  {
    'type': 'promptInputChange',
    'data': '|                                                                                                     ─╯',
  },
  {'type': 'input', 'data': 'l'},
  {'type': 'output', 'data': 'l'},
  {
    'type': 'promptInputChange',
    'data': 'l|                                                                                                    ─╯',
  },
  {'type': 'input', 'data': 's'},
  {'type': 'output', 'data': '\x08ls'},
  {
    'type': 'promptInputChange',
    'data': 'ls|                                                                                                   ─╯',
  },
  {'type': 'input', 'data': '\r'},
  {
    'type': 'output',
    'data': '\x1b[?25l\x1b[?2004l\r\r\x1b[A\x1b[0m\x1b[27m\x1b[24m\x1b[J\x1b]133;A\x07\x1b[0m\x1b[49m\x1b[27m\x1b[24m\x1b[38;5;76m❯\x1b[0m\x1b[38;5;76m\x1b[49m\x1b[39m\x1b[27m\x1b[24m \x1b]133;B\x07ls\x1b[K\x1b[?25h\r\r\n\x1b]133;C;\x07',
  },
  {
    'type': 'promptInputChange',
    'data': 'ls                                                                                                   ─╯',
  },
  {
    'type': 'output',
    'data': 'test\r\n\x1b[1m\x1b[7m%\x1b[27m\x1b[1m\x1b[0m                                                                                                          \r \r',
  },
  {'type': 'output', 'data': '\x1b]133;D;0\x07'},
  {
    'type': 'output',
    'data': '\r\x1b[0m\x1b[27m\x1b[24m\x1b[J\x1b[0m\x1b[38;5;238m\x1b[49m\x1b[39m\x1b]133;A\x07\r\n\r\n\x1b[A\x1b[38;5;238m╭─\x1b[0m\x1b[38;5;238m\x1b[48;5;234m\x1b[38;5;31m \x1b[1m\x1b[38;5;31m\x1b[48;5;234m\x1b[38;5;39m~\x1b[0m\x1b[38;5;39m\x1b[48;5;234m\x1b[48;5;234m\x1b[38;5;31m/playground/\x1b[1m\x1b[38;5;31m\x1b[48;5;234m\x1b[38;5;39mtest1\x1b[0m\x1b[38;5;39m\x1b[48;5;234m\x1b[48;5;234m\x1b[38;5;31m\x1b[0m\x1b[38;5;31m\x1b[48;5;234m\x1b[48;5;234m\x1b[38;5;31m \x1b[0m\x1b[38;5;31m\x1b[48;5;234m\x1b[49m\x1b[38;5;234m▓▒░\x1b[0m\x1b[38;5;234m\x1b[49m\x1b[39m                                                              \x1b[0m\x1b[49m\x1b[38;5;234m░▒▓\x1b[0m\x1b[38;5;234m\x1b[48;5;234m\x1b[38;5;70m \x1b[0m\x1b[38;5;70m\x1b[48;5;234m\x1b[48;5;234m\x1b[38;5;70m✔\x1b[0m\x1b[38;5;70m\x1b[48;5;234m\x1b[48;5;234m\x1b[38;5;70m \x1b[0m\x1b[38;5;70m\x1b[48;5;234m\x1b[48;5;234m\x1b[38;5;70m\x1b[0m\x1b[38;5;70m\x1b[48;5;234m\x1b[48;5;234m\x1b[38;5;66m\x1b[38;5;242m│\x1b[0m\x1b[38;5;242m\x1b[48;5;234m\x1b[48;5;234m\x1b[38;5;66m 07:27:00\x1b[0m\x1b[38;5;66m\x1b[48;5;234m\x1b[48;5;234m\x1b[38;5;66m\x1b[0m\x1b[38;5;66m\x1b[48;5;234m\x1b[48;5;234m\x1b[38;5;66m \x1b[0m\x1b[38;5;66m\x1b[48;5;234m\x1b[49m\x1b[39m\x1b[38;5;238m─╮\r\n\x1b[38;5;238m╰─\x1b[0m\x1b[38;5;238m\x1b[49m\x1b[39m\x1b[0m\x1b[49m\x1b[39m \x1b[0m\x1b[49m\x1b[39m\x1b]133;',
  },
  {
    'type': 'output',
    'data': 'B\x07\x1b[K\x1b[101C\x1b[0m\x1b[49m\x1b[39m\x1b[38;5;238m─╯\x1b[39m\x1b[103D\x1b[?2004h',
  },
  {'type': 'promptInputChange', 'data': '|'},
  {
    'type': 'promptInputChange',
    'data': '|                                                                                                     ─╯',
  },
];

// macOS 15.5
// zsh 5.9
// oh-my-zsh fa396ad
// Steps:
// - Open terminal
// - Type echo a
// - Press enter
// - Type echo b
// - Press enter
// - Type echo c
// - Press enter
const richMacosZshOmzEcho3Times = <RecordedSessionEvent>[
  {'type': 'resize', 'cols': 107, 'rows': 24},
  {
    'type': 'output',
    'data': '\x1b]633;P;ContinuationPrompt=%_> \x07\x1b]633;P;PromptType=p10k\x07\x1b]633;P;HasRichCommandDetection=True\x07\x1b[1m\x1b[7m%\x1b[27m\x1b[1m\x1b[0m                                                                                                          \r \r',
  },
  {'type': 'output', 'data': '\x1b]633;D\x07'},
  {'type': 'output', 'data': ''},
  {
    'type': 'output',
    'data': '\x1b]633;P;Cwd=/Users/tyriar/playground/test1\x07\x1b]633;EnvSingleStart;0;448d50d0-70fe-4ab5-842e-132f3b1c159a;\x07\x1b]633;EnvSingleEnd;448d50d0-70fe-4ab5-842e-132f3b1c159a;\x07\r\x1b[0m\x1b[27m\x1b[24m\x1b[J\x1b]633;A\x07tyriar@Mac test1 % \x1b]633;B\x07\x1b[K\x1b[?2004h',
  },
  {'type': 'promptInputChange', 'data': '|'},
  {'type': 'input', 'data': 'e'},
  {'type': 'output', 'data': 'e'},
  {'type': 'promptInputChange', 'data': 'e|'},
  {'type': 'input', 'data': 'c'},
  {'type': 'output', 'data': '\x08ec'},
  {'type': 'promptInputChange', 'data': 'ec|'},
  {'type': 'input', 'data': 'h'},
  {'type': 'output', 'data': 'h'},
  {'type': 'promptInputChange', 'data': 'ech|'},
  {'type': 'input', 'data': 'o'},
  {'type': 'output', 'data': 'o'},
  {'type': 'promptInputChange', 'data': 'echo|'},
  {'type': 'input', 'data': ' '},
  {'type': 'output', 'data': ' '},
  {'type': 'promptInputChange', 'data': 'echo |'},
  {'type': 'input', 'data': 'a'},
  {'type': 'output', 'data': 'a'},
  {'type': 'promptInputChange', 'data': 'echo a|'},
  {'type': 'input', 'data': '\r'},
  {
    'type': 'output',
    'data': '\x1b[?2004l\r\r\n\x1b]633;E;echo a;448d50d0-70fe-4ab5-842e-132f3b1c159a\x07',
  },
  {'type': 'output', 'data': '\x1b]633;C\x07'},
  {
    'type': 'output',
    'data': 'a\r\n\x1b[1m\x1b[7m%\x1b[27m\x1b[1m\x1b[0m                                                                                                          \r \r',
  },
  {'type': 'output', 'data': '\x1b]633;D;0\x07'},
  {'type': 'output', 'data': ''},
  {
    'type': 'output',
    'data': '\x1b]633;P;Cwd=/Users/tyriar/playground/test1\x07\x1b]633;EnvSingleStart;0;448d50d0-70fe-4ab5-842e-132f3b1c159a;\x07\x1b]633;EnvSingleEnd;448d50d0-70fe-4ab5-842e-132f3b1c159a;\x07\r\x1b[0m\x1b[27m\x1b[24m\x1b[J\x1b]633;A\x07tyriar@Mac test1 % \x1b]633;B\x07\x1b[K\x1b[?2004h',
  },
  {'type': 'promptInputChange', 'data': '|'},
  {'type': 'input', 'data': 'e'},
  {'type': 'output', 'data': 'e'},
  {'type': 'promptInputChange', 'data': 'e|'},
  {'type': 'input', 'data': 'c'},
  {'type': 'output', 'data': '\x08ec'},
  {'type': 'promptInputChange', 'data': 'ec|'},
  {'type': 'input', 'data': 'h'},
  {'type': 'output', 'data': 'h'},
  {'type': 'promptInputChange', 'data': 'ech|'},
  {'type': 'input', 'data': 'o'},
  {'type': 'output', 'data': 'o'},
  {'type': 'promptInputChange', 'data': 'echo|'},
  {'type': 'input', 'data': ' '},
  {'type': 'output', 'data': ' '},
  {'type': 'promptInputChange', 'data': 'echo |'},
  {'type': 'input', 'data': 'b'},
  {'type': 'output', 'data': 'b'},
  {'type': 'promptInputChange', 'data': 'echo b|'},
  {'type': 'input', 'data': '\r'},
  {
    'type': 'output',
    'data': '\x1b[?2004l\r\r\n\x1b]633;E;echo b;448d50d0-70fe-4ab5-842e-132f3b1c159a\x07',
  },
  {'type': 'output', 'data': '\x1b]633;C\x07'},
  {
    'type': 'output',
    'data': 'b\r\n\x1b[1m\x1b[7m%\x1b[27m\x1b[1m\x1b[0m                                                                                                          \r \r',
  },
  {'type': 'output', 'data': '\x1b]633;D;0\x07'},
  {'type': 'output', 'data': ''},
  {
    'type': 'output',
    'data': '\x1b]633;P;Cwd=/Users/tyriar/playground/test1\x07\x1b]633;EnvSingleStart;0;448d50d0-70fe-4ab5-842e-132f3b1c159a;\x07\x1b]633;EnvSingleEnd;448d50d0-70fe-4ab5-842e-132f3b1c159a;\x07\r\x1b[0m\x1b[27m\x1b[24m\x1b[J\x1b]633;A\x07tyriar@Mac test1 % \x1b]633;B\x07\x1b[K\x1b[?2004h',
  },
  {'type': 'promptInputChange', 'data': '|'},
  {'type': 'input', 'data': 'e'},
  {'type': 'output', 'data': 'e'},
  {'type': 'promptInputChange', 'data': 'e|'},
  {'type': 'input', 'data': 'c'},
  {'type': 'output', 'data': '\x08ec'},
  {'type': 'promptInputChange', 'data': 'ec|'},
  {'type': 'input', 'data': 'h'},
  {'type': 'output', 'data': 'h'},
  {'type': 'promptInputChange', 'data': 'ech|'},
  {'type': 'input', 'data': 'o'},
  {'type': 'output', 'data': 'o'},
  {'type': 'promptInputChange', 'data': 'echo|'},
  {'type': 'input', 'data': ' '},
  {'type': 'output', 'data': ' '},
  {'type': 'promptInputChange', 'data': 'echo |'},
  {'type': 'input', 'data': 'c'},
  {'type': 'output', 'data': 'c'},
  {'type': 'promptInputChange', 'data': 'echo c|'},
  {'type': 'input', 'data': '\r'},
  {'type': 'output', 'data': '\x1b[?2004l\r\r\n'},
  {
    'type': 'output',
    'data': '\x1b]633;E;echo c;448d50d0-70fe-4ab5-842e-132f3b1c159a\x07',
  },
  {'type': 'output', 'data': '\x1b]633;C\x07'},
  {
    'type': 'output',
    'data': 'c\r\n\x1b[1m\x1b[7m%\x1b[27m\x1b[1m\x1b[0m                                                                                                          \r \r',
  },
  {'type': 'output', 'data': '\x1b]633;D;0\x07'},
  {'type': 'output', 'data': ''},
  {
    'type': 'output',
    'data': '\x1b]633;P;Cwd=/Users/tyriar/playground/test1\x07\x1b]633;EnvSingleStart;0;448d50d0-70fe-4ab5-842e-132f3b1c159a;\x07\x1b]633;EnvSingleEnd;448d50d0-70fe-4ab5-842e-132f3b1c159a;\x07\r\x1b[0m\x1b[27m\x1b[24m\x1b[J\x1b]633;A\x07tyriar@Mac test1 % \x1b]633;B\x07\x1b[K\x1b[?2004h',
  },
  {'type': 'promptInputChange', 'data': '|'},
];

// macOS 15.5
// zsh 5.9
// oh-my-zsh fa396ad
// Steps:
// - Open terminal
// - Type ls
// - Press enter
const richMacosZshOmzLsOneTime = <RecordedSessionEvent>[
  {'type': 'resize', 'cols': 137, 'rows': 24},
  {
    'type': 'output',
    'data': '\x1b]633;P;ContinuationPrompt=%_> \x07\x1b]633;P;PromptType=p10k\x07\x1b]633;P;HasRichCommandDetection=True\x07\x1b[1m\x1b[7m%\x1b[27m\x1b[1m\x1b[0m                                                                                                                                        \r \r',
  },
  {'type': 'output', 'data': '\x1b]633;D\x07'},
  {'type': 'output', 'data': ''},
  {
    'type': 'output',
    'data': '\x1b]633;P;Cwd=/Users/tyriar/playground/test1\x07\x1b]633;EnvSingleStart;0;f249ba4c-3c40-4fdb-b658-ef7141d0d883;\x07\x1b]633;EnvSingleEnd;f249ba4c-3c40-4fdb-b658-ef7141d0d883;\x07\r\x1b[0m\x1b[27m\x1b[24m\x1b[J\x1b]633;A\x07tyriar@Mac test1 % \x1b]633;B\x07\x1b[K\x1b[?2004h',
  },
  {'type': 'promptInputChange', 'data': '|'},
  {'type': 'input', 'data': 'l'},
  {'type': 'output', 'data': 'l'},
  {'type': 'promptInputChange', 'data': 'l|'},
  {'type': 'input', 'data': 's'},
  {'type': 'output', 'data': '\x08ls'},
  {'type': 'promptInputChange', 'data': 'ls|'},
  {'type': 'input', 'data': '\r'},
  {
    'type': 'output',
    'data': '\x1b[?2004l\r\r\n\x1b]633;E;ls;f249ba4c-3c40-4fdb-b658-ef7141d0d883\x07',
  },
  {'type': 'output', 'data': '\x1b]633;C\x07'},
  {'type': 'output', 'data': ''},
  {'type': 'promptInputChange', 'data': 'ls'},
  {
    'type': 'output',
    'data': 'test\r\n\x1b[1m\x1b[7m%\x1b[27m\x1b[1m\x1b[0m                                                                                                                                        \r \r',
  },
  {'type': 'output', 'data': '\x1b]633;D;0\x07'},
  {'type': 'output', 'data': ''},
  {
    'type': 'output',
    'data': '\x1b]633;P;Cwd=/Users/tyriar/playground/test1\x07\x1b]633;EnvSingleStart;0;f249ba4c-3c40-4fdb-b658-ef7141d0d883;\x07\x1b]633;EnvSingleEnd;f249ba4c-3c40-4fdb-b658-ef7141d0d883;\x07\r\x1b[0m\x1b[27m\x1b[24m\x1b[J\x1b]633;A\x07tyriar@Mac test1 % \x1b]633;B\x07\x1b[K\x1b[?2004h',
  },
  {'type': 'promptInputChange', 'data': '|'},
];

// Windows 24H2
// PowerShell 7.5.2
// Steps:
// - Open terminal
// - Type echo a
// - Press enter
// - Type echo b
// - Press enter
// - Type echo c
// - Press enter
const richWindows11Pwsh7Echo3Times = <RecordedSessionEvent>[
  {'type': 'resize', 'cols': 167, 'rows': 22},
  {
    'type': 'output',
    'data': '\x1b[?9001h\x1b[?1004h\x1b[?25l\x1b[2J\x1b[m\x1b[H\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\x1b[H\x1b]0;C:\\Program Files\\WindowsApps\\Microsoft.PowerShell_7.5.2.0_x64__8wekyb3d8bbwe\\pwsh.exe\x07\x1b[?25h',
  },
  {'type': 'input', 'data': '\x1b[I'},
  {
    'type': 'output',
    'data': '\x1b[?25l\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\x1b[H\x1b[?25h',
  },
  {
    'type': 'output',
    'data': '\x1b]633;P;PromptType=posh-git\x07\x1b]633;P;HasRichCommandDetection=True\x07',
  },
  {
    'type': 'output',
    'data':
        '\x1b]633;P;ContinuationPrompt=>> \x07\x1b]633;P;IsWindows=True\x07',
  },
  {
    'type': 'output',
    'data': '\x1b]0;C:\\Program Files\\WindowsApps\\Microsoft.PowerShell_7.5.2.0_x64__8wekyb3d8bbwe\\pwsh.exe \x07\x1b]0;xterm.js [master] - PowerShell 7.5 (45808)\x07\x1b]633;A\x07\x1b]633;P;Cwd=C:\\x5cGithub\\x5cTyriar\\x5cxterm.js\x07\x1b]633;EnvJson;{"PATH":"C:\\x5c\\x5cProgram Files\\x5c\\x5cWindowsApps\\x5c\\x5cMicrosoft.PowerShell_7.5.2.0_x64__8wekyb3d8bbwe\\x3bC:\\x5c\\x5cProgram Files (x86)\\x5c\\x5coh-my-posh\\x5c\\x5cbin\\x5c\\x5c\\x3bC:\\x5c\\x5cPython312\\x5c\\x5cScripts\\x5c\\x5c\\x3bC:\\x5c\\x5cPython312\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cMicrosoft SDKs\\x5c\\x5cAzure\\x5c\\x5cCLI2\\x5c\\x5cwbin\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cEclipse Adoptium\\x5c\\x5cjdk-8.0.345.1-hotspot\\x5c\\x5cbin\\x3bC:\\x5c\\x5cWINDOWS\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5csystem32\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5cSystem32\\x5c\\x5cWbem\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5cSystem32\\x5c\\x5cWindowsPowerShell\\x5c\\x5cv1.0\\x5c\\x5c\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5cSystem32\\x5c\\x5cOpenSSH\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files (x86)\\x5c\\x5cNVIDIA Corporation\\x5c\\x5cPhysX\\x5c\\x5cCommon\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cGit LFS\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cnu\\x5c\\x5cbin\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cstarship\\x5c\\x5cbin\\x5c\\x5c\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5csystem32\\x3bC:\\x5c\\x5cWINDOWS\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5cSystem32\\x5c\\x5cWbem\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5cSystem32\\x5c\\x5cWindowsPowerShell\\x5c\\x5cv1.0\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cNVIDIA Corporation\\x5c\\x5cNVIDIA NvDLISR\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cGitHub CLI\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files (x86)\\x5c\\x5cWindows Kits\\x5c\\x5c10\\x5c\\x5cWindows Performance Toolkit\\x5c\\x5c\\x3bC:\\x5c\\x5cProgramData\\x5c\\x5cchocolatey\\x5c\\x5cbin\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cdotnet\\x5c\\x5c\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5cSystem32\\x5c\\x5cOpenSSH\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cGnuPG\\x5c\\x5cbin\\x3bC:\\x5c\\x5cProgram Files (x86)\\x5c\\x5cGpg4win\\x5c\\x5c..\\x5c\\x5cGnuPG\\x5c\\x5cbin\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cnodejs\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cGit\\x5c\\x5ccmd\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cPython\\x5c\\x5cPython312\\x5c\\x5cScripts\\x5c\\x5c\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cPython\\x5c\\x5cPython312\\x5c\\x5c\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5coh-my-posh\\x5c\\x5cbin\\x5c\\x5c\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5c.cargo\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cRoaming\\x5c\\x5cPython\\x5c\\x5cScripts\\x5c\\x5c\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cPython\\x5c\\x5cPython310\\x5c\\x5cScripts\\x5c\\x5c\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cPython\\x5c\\x5cPython310\\x5c\\x5c\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cMicrosoft\\x5c\\x5cWindowsApps\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5coh-my-posh\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5coh-my-posh\\x5c\\x5cthemes\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5c.vscode-cli\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cMicrosoft\\x5c\\x5cWindowsApps\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cJetBrains\\x5c\\x5cToolbox\\x5c\\x5cscripts\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cnvs\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files (x86)\\x5c\\x5cMicrosoft Visual Studio\\x5c\\x5c2017\\x5c\\x5cBuildTools\\x5c\\x5cMSBuild\\x5c\\x5c15.0\\x5c\\x5cBin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cMicrosoft\\x5c\\x5cWinGet\\x5c\\x5cPackages\\x5c\\x5cBurntSushi.ripgrep.MSVC_Microsoft.Winget.Source_8wekyb3d8bbwe\\x5c\\x5cripgrep-13.0.0-x86_64-pc-windows-msvc\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cMicrosoft\\x5c\\x5cWinGet\\x5c\\x5cPackages\\x5c\\x5cSchniz.fnm_Microsoft.Winget.Source_8wekyb3d8bbwe\\x3bc:\\x5c\\x5cusers\\x5c\\x5cdaniel\\x5c\\x5c.local\\x5c\\x5cbin\\x3bC:\\x5c\\x5cTools\\x5c\\x5cHandle\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cMicrosoft VS Code Insiders\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cJulia-1.11.1\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cMicrosoft VS Code\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPackages\\x5c\\x5cPythonSoftwareFoundation.Python.3.9_qbz5n2kfra8p0\\x5c\\x5cLocalCache\\x5c\\x5clocal-packages\\x5c\\x5cPython39\\x5c\\x5cScripts\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cWindsurf\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5ccursor\\x5c\\x5cresources\\x5c\\x5capp\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cRoaming\\x5c\\x5cnpm\\x3bc:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5c.vscode-oss-dev\\x5c\\x5cUser\\x5c\\x5cglobalStorage\\x5c\\x5cgithub.copilot-chat\\x5c\\x5cdebugCommand"};d970493f-becd-4c84-a4e9-8d7017bac9af\x07C:\\Github\\Tyriar\\xterm.js \x1b[93m[\x1b[92mmaster ↑2\x1b[93m]\x1b[m> \x1b]633;P;Prompt=C:\\x5cGithub\\x5cTyriar\\x5cxterm.js \\x1b[93m[\\x1b[39m\\x1b[92mmaster\\x1b[39m\\x1b[92m ↑2\\x1b[39m\\x1b[93m]\\x1b[39m> \x07\x1b]633;B\x07',
  },
  {'type': 'promptInputChange', 'data': '|'},
  {'type': 'commandDetection.onCommandStarted'},
  {'type': 'command', 'id': '_setContext'},
  {'type': 'input', 'data': 'e'},
  {'type': 'output', 'data': '\x1b[?25l'},
  {
    'type': 'output',
    'data': '\x1b[93me\x1b[97m\x1b[2m\x1b[3mcho b\x1b[1;41H\x1b[?25h',
  },
  {'type': 'promptInputChange', 'data': 'e|cho b'},
  {'type': 'promptInputChange', 'data': 'e|[cho b]'},
  {'type': 'input', 'data': 'c'},
  {'type': 'output', 'data': '\x1b[m\x1b[?25l'},
  {
    'type': 'output',
    'data': '\x1b[93m\x08ec\x1b[97m\x1b[2m\x1b[3mho b\x1b[1;42H\x1b[?25h',
  },
  {'type': 'promptInputChange', 'data': 'ec|[ho b]'},
  {'type': 'input', 'data': 'h'},
  {'type': 'input', 'data': 'o'},
  {'type': 'output', 'data': '\x1b[m\x1b[?25l'},
  {
    'type': 'output',
    'data': '\x1b[93m\x1b[1;40Hecho\x1b[97m\x1b[2m\x1b[3m b\x1b[1;44H\x1b[?25h',
  },
  {'type': 'promptInputChange', 'data': 'echo|[ b]'},
  {'type': 'input', 'data': ' '},
  {
    'type': 'output',
    'data': '\x1b[m\x1b[?25l\x1b[93m\x1b[1;40Hecho \x1b[97m\x1b[2m\x1b[3mb\x08\x1b[?25h',
  },
  {'type': 'promptInputChange', 'data': 'echo |[b]'},
  {'type': 'input', 'data': 'a'},
  {'type': 'output', 'data': '\x1b[m\x1b[?25l'},
  {
    'type': 'output',
    'data': '\x1b[93m\x1b[1;40Hecho \x1b[37ma\x1b[97m\x1b[2m\x1b[3mbc\x1b[1;46H\x1b[?25h',
  },
  {'type': 'promptInputChange', 'data': 'echo a|[bc]'},
  {'type': 'sendText', 'data': '\x1b[24~e'},
  {'type': 'output', 'data': '\x1b[m\x1b]633;Completions;0;5;5;[]\x07'},
  {'type': 'input', 'data': '\r'},
  {'type': 'output', 'data': '\x1b[K'},
  {'type': 'promptInputChange', 'data': 'echo a|'},
  {
    'type': 'output',
    'data': '\r\n\x1b]633;E;echo a;d970493f-becd-4c84-a4e9-8d7017bac9af\x07',
  },
  {'type': 'output', 'data': '\x1b]633;C\x07'},
  {'type': 'output', 'data': ''},
  {'type': 'promptInputChange', 'data': 'echo a|[]'},
  {'type': 'promptInputChange', 'data': 'echo a'},
  {'type': 'commandDetection.onCommandExecuted', 'commandLine': 'echo a'},
  {'type': 'commandDetection.onCommandExecuted', 'commandLine': 'echo a'},
  {'type': 'output', 'data': 'a\r\n'},
  {'type': 'output', 'data': ''},
  {'type': 'output', 'data': '\x1b]633;D;0\x07'},
  {
    'type': 'output',
    'data': '\x1b]633;A\x07\x1b]633;P;Cwd=C:\\x5cGithub\\x5cTyriar\\x5cxterm.js\x07\x1b]633;EnvJson;{"PATH":"C:\\x5c\\x5cProgram Files\\x5c\\x5cWindowsApps\\x5c\\x5cMicrosoft.PowerShell_7.5.2.0_x64__8wekyb3d8bbwe\\x3bC:\\x5c\\x5cProgram Files (x86)\\x5c\\x5coh-my-posh\\x5c\\x5cbin\\x5c\\x5c\\x3bC:\\x5c\\x5cPython312\\x5c\\x5cScripts\\x5c\\x5c\\x3bC:\\x5c\\x5cPython312\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cMicrosoft SDKs\\x5c\\x5cAzure\\x5c\\x5cCLI2\\x5c\\x5cwbin\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cEclipse Adoptium\\x5c\\x5cjdk-8.0.345.1-hotspot\\x5c\\x5cbin\\x3bC:\\x5c\\x5cWINDOWS\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5csystem32\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5cSystem32\\x5c\\x5cWbem\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5cSystem32\\x5c\\x5cWindowsPowerShell\\x5c\\x5cv1.0\\x5c\\x5c\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5cSystem32\\x5c\\x5cOpenSSH\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files (x86)\\x5c\\x5cNVIDIA Corporation\\x5c\\x5cPhysX\\x5c\\x5cCommon\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cGit LFS\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cnu\\x5c\\x5cbin\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cstarship\\x5c\\x5cbin\\x5c\\x5c\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5csystem32\\x3bC:\\x5c\\x5cWINDOWS\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5cSystem32\\x5c\\x5cWbem\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5cSystem32\\x5c\\x5cWindowsPowerShell\\x5c\\x5cv1.0\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cNVIDIA Corporation\\x5c\\x5cNVIDIA NvDLISR\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cGitHub CLI\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files (x86)\\x5c\\x5cWindows Kits\\x5c\\x5c10\\x5c\\x5cWindows Performance Toolkit\\x5c\\x5c\\x3bC:\\x5c\\x5cProgramData\\x5c\\x5cchocolatey\\x5c\\x5cbin\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cdotnet\\x5c\\x5c\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5cSystem32\\x5c\\x5cOpenSSH\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cGnuPG\\x5c\\x5cbin\\x3bC:\\x5c\\x5cProgram Files (x86)\\x5c\\x5cGpg4win\\x5c\\x5c..\\x5c\\x5cGnuPG\\x5c\\x5cbin\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cnodejs\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cGit\\x5c\\x5ccmd\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cPython\\x5c\\x5cPython312\\x5c\\x5cScripts\\x5c\\x5c\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cPython\\x5c\\x5cPython312\\x5c\\x5c\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5coh-my-posh\\x5c\\x5cbin\\x5c\\x5c\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5c.cargo\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cRoaming\\x5c\\x5cPython\\x5c\\x5cScripts\\x5c\\x5c\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cPython\\x5c\\x5cPython310\\x5c\\x5cScripts\\x5c\\x5c\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cPython\\x5c\\x5cPython310\\x5c\\x5c\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cMicrosoft\\x5c\\x5cWindowsApps\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5coh-my-posh\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5coh-my-posh\\x5c\\x5cthemes\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5c.vscode-cli\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cMicrosoft\\x5c\\x5cWindowsApps\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cJetBrains\\x5c\\x5cToolbox\\x5c\\x5cscripts\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cnvs\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files (x86)\\x5c\\x5cMicrosoft Visual Studio\\x5c\\x5c2017\\x5c\\x5cBuildTools\\x5c\\x5cMSBuild\\x5c\\x5c15.0\\x5c\\x5cBin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cMicrosoft\\x5c\\x5cWinGet\\x5c\\x5cPackages\\x5c\\x5cBurntSushi.ripgrep.MSVC_Microsoft.Winget.Source_8wekyb3d8bbwe\\x5c\\x5cripgrep-13.0.0-x86_64-pc-windows-msvc\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cMicrosoft\\x5c\\x5cWinGet\\x5c\\x5cPackages\\x5c\\x5cSchniz.fnm_Microsoft.Winget.Source_8wekyb3d8bbwe\\x3bc:\\x5c\\x5cusers\\x5c\\x5cdaniel\\x5c\\x5c.local\\x5c\\x5cbin\\x3bC:\\x5c\\x5cTools\\x5c\\x5cHandle\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cMicrosoft VS Code Insiders\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cJulia-1.11.1\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cMicrosoft VS Code\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPackages\\x5c\\x5cPythonSoftwareFoundation.Python.3.9_qbz5n2kfra8p0\\x5c\\x5cLocalCache\\x5c\\x5clocal-packages\\x5c\\x5cPython39\\x5c\\x5cScripts\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cWindsurf\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5ccursor\\x5c\\x5cresources\\x5c\\x5capp\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cRoaming\\x5c\\x5cnpm\\x3bc:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5c.vscode-oss-dev\\x5c\\x5cUser\\x5c\\x5cglobalStorage\\x5c\\x5cgithub.copilot-chat\\x5c\\x5cdebugCommand"};d970493f-becd-4c84-a4e9-8d7017bac9af\x07C:\\Github\\Tyriar\\xterm.js \x1b[93m[\x1b[92mmaster ↑2\x1b[93m]\x1b[m> \x1b]633;P;Prompt=C:\\x5cGithub\\x5cTyriar\\x5cxterm.js \\x1b[93m[\\x1b[39m\\x1b[92mmaster\\x1b[39m\\x1b[92m ↑2\\x1b[39m\\x1b[93m]\\x1b[39m> \x07\x1b]633;B\x07',
  },
  {'type': 'commandDetection.onCommandFinished', 'commandLine': 'echo a'},
  {'type': 'promptInputChange', 'data': '|'},
  {'type': 'commandDetection.onCommandStarted'},
  {'type': 'input', 'data': 'e'},
  {'type': 'output', 'data': '\x1b[?25l'},
  {
    'type': 'output',
    'data': '\x1b[93me\x1b[97m\x1b[2m\x1b[3mcho a\x1b[3;41H\x1b[?25h',
  },
  {'type': 'promptInputChange', 'data': 'e|cho a'},
  {'type': 'promptInputChange', 'data': 'e|[cho a]'},
  {'type': 'input', 'data': 'c'},
  {'type': 'output', 'data': '\x1b[m\x1b[?25l'},
  {
    'type': 'output',
    'data': '\x1b[93m\x08ec\x1b[97m\x1b[2m\x1b[3mho a\x1b[3;42H\x1b[?25h',
  },
  {'type': 'promptInputChange', 'data': 'ec|[ho a]'},
  {'type': 'input', 'data': 'h'},
  {'type': 'output', 'data': '\x1b[m\x1b[?25l'},
  {
    'type': 'output',
    'data': '\x1b[93m\x1b[3;40Hech\x1b[97m\x1b[2m\x1b[3mo a\x1b[3;43H\x1b[?25h',
  },
  {'type': 'promptInputChange', 'data': 'ech|[o a]'},
  {'type': 'input', 'data': 'o'},
  {
    'type': 'output',
    'data': '\x1b[?25l\x1b[m\x1b[93m\x1b[3;40Hecho\x1b[97m\x1b[2m\x1b[3m a\x1b[3;44H\x1b[?25h',
  },
  {'type': 'promptInputChange', 'data': 'echo|[ a]'},
  {'type': 'input', 'data': ' '},
  {
    'type': 'output',
    'data': '\x1b[m\x1b[?25l\x1b[93m\x1b[3;40Hecho \x1b[97m\x1b[2m\x1b[3ma\x08\x1b[?25h',
  },
  {'type': 'promptInputChange', 'data': 'echo |[a]'},
  {'type': 'input', 'data': 'b'},
  {
    'type': 'output',
    'data': '\x1b[m\x1b[?25l\x1b[93m\x1b[3;40Hecho \x1b[37mb\x1b[97m\x1b[2m\x1b[3mar\x1b[3;46H\x1b[?25h',
  },
  {'type': 'promptInputChange', 'data': 'echo b|[ar]'},
  {'type': 'sendText', 'data': '\x1b[24~e'},
  {'type': 'output', 'data': '\x1b[m\x1b]633;Completions;0;5;5;[]\x07'},
  {'type': 'input', 'data': '\r'},
  {
    'type': 'output',
    'data':
        '\x1b[K\r\n\x1b]633;E;echo b;d970493f-becd-4c84-a4e9-8d7017bac9af\x07',
  },
  {'type': 'promptInputChange', 'data': 'echo b'},
  {'type': 'promptInputChange', 'data': 'echo b|[]'},
  {'type': 'output', 'data': '\x1b]633;C\x07'},
  {'type': 'output', 'data': 'b\r\n'},
  {'type': 'sendText', 'data': '\x1b[24~e'},
  {'type': 'promptInputChange', 'data': 'echo b'},
  {'type': 'commandDetection.onCommandExecuted', 'commandLine': 'echo b'},
  {'type': 'commandDetection.onCommandExecuted', 'commandLine': 'echo b'},
  {'type': 'output', 'data': ''},
  {'type': 'output', 'data': '\x1b]633;D;0\x07'},
  {
    'type': 'output',
    'data': '\x1b]633;A\x07\x1b]633;P;Cwd=C:\\x5cGithub\\x5cTyriar\\x5cxterm.js\x07\x1b]633;EnvJson;{"PATH":"C:\\x5c\\x5cProgram Files\\x5c\\x5cWindowsApps\\x5c\\x5cMicrosoft.PowerShell_7.5.2.0_x64__8wekyb3d8bbwe\\x3bC:\\x5c\\x5cProgram Files (x86)\\x5c\\x5coh-my-posh\\x5c\\x5cbin\\x5c\\x5c\\x3bC:\\x5c\\x5cPython312\\x5c\\x5cScripts\\x5c\\x5c\\x3bC:\\x5c\\x5cPython312\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cMicrosoft SDKs\\x5c\\x5cAzure\\x5c\\x5cCLI2\\x5c\\x5cwbin\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cEclipse Adoptium\\x5c\\x5cjdk-8.0.345.1-hotspot\\x5c\\x5cbin\\x3bC:\\x5c\\x5cWINDOWS\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5csystem32\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5cSystem32\\x5c\\x5cWbem\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5cSystem32\\x5c\\x5cWindowsPowerShell\\x5c\\x5cv1.0\\x5c\\x5c\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5cSystem32\\x5c\\x5cOpenSSH\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files (x86)\\x5c\\x5cNVIDIA Corporation\\x5c\\x5cPhysX\\x5c\\x5cCommon\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cGit LFS\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cnu\\x5c\\x5cbin\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cstarship\\x5c\\x5cbin\\x5c\\x5c\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5csystem32\\x3bC:\\x5c\\x5cWINDOWS\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5cSystem32\\x5c\\x5cWbem\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5cSystem32\\x5c\\x5cWindowsPowerShell\\x5c\\x5cv1.0\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cNVIDIA Corporation\\x5c\\x5cNVIDIA NvDLISR\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cGitHub CLI\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files (x86)\\x5c\\x5cWindows Kits\\x5c\\x5c10\\x5c\\x5cWindows Performance Toolkit\\x5c\\x5c\\x3bC:\\x5c\\x5cProgramData\\x5c\\x5cchocolatey\\x5c\\x5cbin\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cdotnet\\x5c\\x5c\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5cSystem32\\x5c\\x5cOpenSSH\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cGnuPG\\x5c\\x5cbin\\x3bC:\\x5c\\x5cProgram Files (x86)\\x5c\\x5cGpg4win\\x5c\\x5c..\\x5c\\x5cGnuPG\\x5c\\x5cbin\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cnodejs\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cGit\\x5c\\x5ccmd\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cPython\\x5c\\x5cPython312\\x5c\\x5cScripts\\x5c\\x5c\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cPython\\x5c\\x5cPython312\\x5c\\x5c\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5coh-my-posh\\x5c\\x5cbin\\x5c\\x5c\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5c.cargo\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cRoaming\\x5c\\x5cPython\\x5c\\x5cScripts\\x5c\\x5c\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cPython\\x5c\\x5cPython310\\x5c\\x5cScripts\\x5c\\x5c\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cPython\\x5c\\x5cPython310\\x5c\\x5c\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cMicrosoft\\x5c\\x5cWindowsApps\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5coh-my-posh\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5coh-my-posh\\x5c\\x5cthemes\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5c.vscode-cli\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cMicrosoft\\x5c\\x5cWindowsApps\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cJetBrains\\x5c\\x5cToolbox\\x5c\\x5cscripts\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cnvs\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files (x86)\\x5c\\x5cMicrosoft Visual Studio\\x5c\\x5c2017\\x5c\\x5cBuildTools\\x5c\\x5cMSBuild\\x5c\\x5c15.0\\x5c\\x5cBin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cMicrosoft\\x5c\\x5cWinGet\\x5c\\x5cPackages\\x5c\\x5cBurntSushi.ripgrep.MSVC_Microsoft.Winget.Source_8wekyb3d8bbwe\\x5c\\x5cripgrep-13.0.0-x86_64-pc-windows-msvc\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cMicrosoft\\x5c\\x5cWinGet\\x5c\\x5cPackages\\x5c\\x5cSchniz.fnm_Microsoft.Winget.Source_8wekyb3d8bbwe\\x3bc:\\x5c\\x5cusers\\x5c\\x5cdaniel\\x5c\\x5c.local\\x5c\\x5cbin\\x3bC:\\x5c\\x5cTools\\x5c\\x5cHandle\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cMicrosoft VS Code Insiders\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cJulia-1.11.1\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cMicrosoft VS Code\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPackages\\x5c\\x5cPythonSoftwareFoundation.Python.3.9_qbz5n2kfra8p0\\x5c\\x5cLocalCache\\x5c\\x5clocal-packages\\x5c\\x5cPython39\\x5c\\x5cScripts\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cWindsurf\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5ccursor\\x5c\\x5cresources\\x5c\\x5capp\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cRoaming\\x5c\\x5cnpm\\x3bc:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5c.vscode-oss-dev\\x5c\\x5cUser\\x5c\\x5cglobalStorage\\x5c\\x5cgithub.copilot-chat\\x5c\\x5cdebugCommand"};d970493f-becd-4c84-a4e9-8d7017bac9af\x07C:\\Github\\Tyriar\\xterm.js \x1b[93m[\x1b[92mmaster ↑2\x1b[93m]\x1b[m> \x1b]633;P;Prompt=C:\\x5cGithub\\x5cTyriar\\x5cxterm.js \\x1b[93m[\\x1b[39m\\x1b[92mmaster\\x1b[39m\\x1b[92m ↑2\\x1b[39m\\x1b[93m]\\x1b[39m> \x07\x1b]633;B\x07\x1b]633;Completions\x07',
  },
  {'type': 'commandDetection.onCommandFinished', 'commandLine': 'echo b'},
  {'type': 'promptInputChange', 'data': '|'},
  {'type': 'commandDetection.onCommandStarted'},
  {'type': 'input', 'data': 'e'},
  {'type': 'output', 'data': '\x1b[?25l'},
  {
    'type': 'output',
    'data': '\x1b[93me\x1b[97m\x1b[2m\x1b[3mcho b\x1b[5;41H\x1b[?25h',
  },
  {'type': 'promptInputChange', 'data': 'e|cho b'},
  {'type': 'promptInputChange', 'data': 'e|[cho b]'},
  {'type': 'input', 'data': 'c'},
  {'type': 'output', 'data': '\x1b[m\x1b[?25l'},
  {
    'type': 'output',
    'data': '\x1b[93m\x08ec\x1b[97m\x1b[2m\x1b[3mho b\x1b[5;42H\x1b[?25h',
  },
  {'type': 'promptInputChange', 'data': 'ec|[ho b]'},
  {'type': 'input', 'data': 'h'},
  {'type': 'output', 'data': '\x1b[m\x1b[?25l'},
  {
    'type': 'output',
    'data': '\x1b[93m\x1b[5;40Hech\x1b[97m\x1b[2m\x1b[3mo b\x1b[5;43H\x1b[?25h',
  },
  {'type': 'promptInputChange', 'data': 'ech|[o b]'},
  {'type': 'input', 'data': 'o'},
  {'type': 'output', 'data': '\x1b[m\x1b[?25l'},
  {
    'type': 'output',
    'data': '\x1b[93m\x1b[5;40Hecho\x1b[97m\x1b[2m\x1b[3m b\x1b[5;44H\x1b[?25h',
  },
  {'type': 'promptInputChange', 'data': 'echo|[ b]'},
  {'type': 'input', 'data': ' '},
  {'type': 'output', 'data': '\x1b[m\x1b[?25l'},
  {
    'type': 'output',
    'data': '\x1b[93m\x1b[5;40Hecho \x1b[97m\x1b[2m\x1b[3mb\x08\x1b[?25h',
  },
  {'type': 'promptInputChange', 'data': 'echo |[b]'},
  {'type': 'input', 'data': 'c'},
  {'type': 'output', 'data': '\x1b[m\x1b[?25l'},
  {'type': 'output', 'data': '\x1b[93m\x1b[5;40Hecho \x1b[37mc\x1b[?25h'},
  {'type': 'promptInputChange', 'data': 'echo c|'},
  {'type': 'sendText', 'data': '\x1b[24~e'},
  {'type': 'output', 'data': '\x1b[m\x1b]633;Completions;0;5;5;[]\x07'},
  {'type': 'input', 'data': '\r'},
  {
    'type': 'output',
    'data': '\r\n\x1b]633;E;echo c;d970493f-becd-4c84-a4e9-8d7017bac9af\x07',
  },
  {'type': 'promptInputChange', 'data': 'echo c|[]'},
  {'type': 'output', 'data': '\x1b]633;C\x07'},
  {'type': 'output', 'data': ''},
  {'type': 'promptInputChange', 'data': 'echo c'},
  {'type': 'commandDetection.onCommandExecuted', 'commandLine': 'echo c'},
  {'type': 'commandDetection.onCommandExecuted', 'commandLine': 'echo c'},
  {'type': 'output', 'data': 'c\r\n'},
  {'type': 'output', 'data': ''},
  {'type': 'output', 'data': '\x1b]633;D;0\x07'},
  {
    'type': 'output',
    'data': '\x1b]633;A\x07\x1b]633;P;Cwd=C:\\x5cGithub\\x5cTyriar\\x5cxterm.js\x07\x1b]633;EnvJson;{"PATH":"C:\\x5c\\x5cProgram Files\\x5c\\x5cWindowsApps\\x5c\\x5cMicrosoft.PowerShell_7.5.2.0_x64__8wekyb3d8bbwe\\x3bC:\\x5c\\x5cProgram Files (x86)\\x5c\\x5coh-my-posh\\x5c\\x5cbin\\x5c\\x5c\\x3bC:\\x5c\\x5cPython312\\x5c\\x5cScripts\\x5c\\x5c\\x3bC:\\x5c\\x5cPython312\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cMicrosoft SDKs\\x5c\\x5cAzure\\x5c\\x5cCLI2\\x5c\\x5cwbin\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cEclipse Adoptium\\x5c\\x5cjdk-8.0.345.1-hotspot\\x5c\\x5cbin\\x3bC:\\x5c\\x5cWINDOWS\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5csystem32\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5cSystem32\\x5c\\x5cWbem\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5cSystem32\\x5c\\x5cWindowsPowerShell\\x5c\\x5cv1.0\\x5c\\x5c\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5cSystem32\\x5c\\x5cOpenSSH\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files (x86)\\x5c\\x5cNVIDIA Corporation\\x5c\\x5cPhysX\\x5c\\x5cCommon\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cGit LFS\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cnu\\x5c\\x5cbin\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cstarship\\x5c\\x5cbin\\x5c\\x5c\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5csystem32\\x3bC:\\x5c\\x5cWINDOWS\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5cSystem32\\x5c\\x5cWbem\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5cSystem32\\x5c\\x5cWindowsPowerShell\\x5c\\x5cv1.0\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cNVIDIA Corporation\\x5c\\x5cNVIDIA NvDLISR\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cGitHub CLI\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files (x86)\\x5c\\x5cWindows Kits\\x5c\\x5c10\\x5c\\x5cWindows Performance Toolkit\\x5c\\x5c\\x3bC:\\x5c\\x5cProgramData\\x5c\\x5cchocolatey\\x5c\\x5cbin\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cdotnet\\x5c\\x5c\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5cSystem32\\x5c\\x5cOpenSSH\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cGnuPG\\x5c\\x5cbin\\x3bC:\\x5c\\x5cProgram Files (x86)\\x5c\\x5cGpg4win\\x5c\\x5c..\\x5c\\x5cGnuPG\\x5c\\x5cbin\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cnodejs\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cGit\\x5c\\x5ccmd\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cPython\\x5c\\x5cPython312\\x5c\\x5cScripts\\x5c\\x5c\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cPython\\x5c\\x5cPython312\\x5c\\x5c\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5coh-my-posh\\x5c\\x5cbin\\x5c\\x5c\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5c.cargo\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cRoaming\\x5c\\x5cPython\\x5c\\x5cScripts\\x5c\\x5c\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cPython\\x5c\\x5cPython310\\x5c\\x5cScripts\\x5c\\x5c\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cPython\\x5c\\x5cPython310\\x5c\\x5c\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cMicrosoft\\x5c\\x5cWindowsApps\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5coh-my-posh\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5coh-my-posh\\x5c\\x5cthemes\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5c.vscode-cli\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cMicrosoft\\x5c\\x5cWindowsApps\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cJetBrains\\x5c\\x5cToolbox\\x5c\\x5cscripts\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cnvs\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files (x86)\\x5c\\x5cMicrosoft Visual Studio\\x5c\\x5c2017\\x5c\\x5cBuildTools\\x5c\\x5cMSBuild\\x5c\\x5c15.0\\x5c\\x5cBin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cMicrosoft\\x5c\\x5cWinGet\\x5c\\x5cPackages\\x5c\\x5cBurntSushi.ripgrep.MSVC_Microsoft.Winget.Source_8wekyb3d8bbwe\\x5c\\x5cripgrep-13.0.0-x86_64-pc-windows-msvc\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cMicrosoft\\x5c\\x5cWinGet\\x5c\\x5cPackages\\x5c\\x5cSchniz.fnm_Microsoft.Winget.Source_8wekyb3d8bbwe\\x3bc:\\x5c\\x5cusers\\x5c\\x5cdaniel\\x5c\\x5c.local\\x5c\\x5cbin\\x3bC:\\x5c\\x5cTools\\x5c\\x5cHandle\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cMicrosoft VS Code Insiders\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cJulia-1.11.1\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cMicrosoft VS Code\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPackages\\x5c\\x5cPythonSoftwareFoundation.Python.3.9_qbz5n2kfra8p0\\x5c\\x5cLocalCache\\x5c\\x5clocal-packages\\x5c\\x5cPython39\\x5c\\x5cScripts\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cWindsurf\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5ccursor\\x5c\\x5cresources\\x5c\\x5capp\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cRoaming\\x5c\\x5cnpm\\x3bc:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5c.vscode-oss-dev\\x5c\\x5cUser\\x5c\\x5cglobalStorage\\x5c\\x5cgithub.copilot-chat\\x5c\\x5cdebugCommand"};d970493f-becd-4c84-a4e9-8d7017bac9af\x07C:\\Github\\Tyriar\\xterm.js \x1b[93m[\x1b[92mmaster ↑2\x1b[93m]\x1b[m> \x1b]633;P;Prompt=C:\\x5cGithub\\x5cTyriar\\x5cxterm.js \\x1b[93m[\\x1b[39m\\x1b[92mmaster\\x1b[39m\\x1b[92m ↑2\\x1b[39m\\x1b[93m]\\x1b[39m> \x07\x1b]633;B\x07',
  },
  {'type': 'commandDetection.onCommandFinished', 'commandLine': 'echo c'},
  {'type': 'promptInputChange', 'data': '|'},
  {'type': 'commandDetection.onCommandStarted'},
];

// Windows 24H2
// PowerShell 7.5.2
// Steps:
// - Open terminal
// - Type ls
// - Press enter
const richWindows11Pwsh7LsOneTime = <RecordedSessionEvent>[
  {'type': 'resize', 'cols': 193, 'rows': 22},
  {
    'type': 'output',
    'data': '\x1b[?9001h\x1b[?1004h\x1b[?25l\x1b[2J\x1b[m\x1b[H\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\x1b[H\x1b]0;C:\\Program Files\\WindowsApps\\Microsoft.PowerShell_7.5.2.0_x64__8wekyb3d8bbwe\\pwsh.exe\x07\x1b[?25h',
  },
  {'type': 'input', 'data': '\x1b[I'},
  {
    'type': 'output',
    'data': '\x1b[?25l\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\x1b[H\x1b[?25h',
  },
  {
    'type': 'output',
    'data': '\x1b]633;P;PromptType=posh-git\x07\x1b]633;P;HasRichCommandDetection=True\x07',
  },
  {'type': 'command', 'id': '_setContext'},
  {
    'type': 'output',
    'data':
        '\x1b]633;P;ContinuationPrompt=>> \x07\x1b]633;P;IsWindows=True\x07',
  },
  {
    'type': 'output',
    'data': '\x1b]0;C:\\Program Files\\WindowsApps\\Microsoft.PowerShell_7.5.2.0_x64__8wekyb3d8bbwe\\pwsh.exe \x07',
  },
  {
    'type': 'output',
    'data': '\x1b]0;xterm.js [master] - PowerShell 7.5 (41208)\x07\x1b]633;A\x07\x1b]633;P;Cwd=C:\\x5cGithub\\x5cTyriar\\x5cxterm.js\x07\x1b]633;EnvJson;{"PATH":"C:\\x5c\\x5cProgram Files\\x5c\\x5cWindowsApps\\x5c\\x5cMicrosoft.PowerShell_7.5.2.0_x64__8wekyb3d8bbwe\\x3bC:\\x5c\\x5cProgram Files (x86)\\x5c\\x5coh-my-posh\\x5c\\x5cbin\\x5c\\x5c\\x3bC:\\x5c\\x5cPython312\\x5c\\x5cScripts\\x5c\\x5c\\x3bC:\\x5c\\x5cPython312\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cMicrosoft SDKs\\x5c\\x5cAzure\\x5c\\x5cCLI2\\x5c\\x5cwbin\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cEclipse Adoptium\\x5c\\x5cjdk-8.0.345.1-hotspot\\x5c\\x5cbin\\x3bC:\\x5c\\x5cWINDOWS\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5csystem32\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5cSystem32\\x5c\\x5cWbem\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5cSystem32\\x5c\\x5cWindowsPowerShell\\x5c\\x5cv1.0\\x5c\\x5c\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5cSystem32\\x5c\\x5cOpenSSH\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files (x86)\\x5c\\x5cNVIDIA Corporation\\x5c\\x5cPhysX\\x5c\\x5cCommon\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cGit LFS\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cnu\\x5c\\x5cbin\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cstarship\\x5c\\x5cbin\\x5c\\x5c\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5csystem32\\x3bC:\\x5c\\x5cWINDOWS\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5cSystem32\\x5c\\x5cWbem\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5cSystem32\\x5c\\x5cWindowsPowerShell\\x5c\\x5cv1.0\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cNVIDIA Corporation\\x5c\\x5cNVIDIA NvDLISR\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cGitHub CLI\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files (x86)\\x5c\\x5cWindows Kits\\x5c\\x5c10\\x5c\\x5cWindows Performance Toolkit\\x5c\\x5c\\x3bC:\\x5c\\x5cProgramData\\x5c\\x5cchocolatey\\x5c\\x5cbin\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cdotnet\\x5c\\x5c\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5cSystem32\\x5c\\x5cOpenSSH\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cGnuPG\\x5c\\x5cbin\\x3bC:\\x5c\\x5cProgram Files (x86)\\x5c\\x5cGpg4win\\x5c\\x5c..\\x5c\\x5cGnuPG\\x5c\\x5cbin\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cnodejs\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cGit\\x5c\\x5ccmd\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cPython\\x5c\\x5cPython312\\x5c\\x5cScripts\\x5c\\x5c\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cPython\\x5c\\x5cPython312\\x5c\\x5c\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5coh-my-posh\\x5c\\x5cbin\\x5c\\x5c\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5c.cargo\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cRoaming\\x5c\\x5cPython\\x5c\\x5cScripts\\x5c\\x5c\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cPython\\x5c\\x5cPython310\\x5c\\x5cScripts\\x5c\\x5c\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cPython\\x5c\\x5cPython310\\x5c\\x5c\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cMicrosoft\\x5c\\x5cWindowsApps\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5coh-my-posh\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5coh-my-posh\\x5c\\x5cthemes\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5c.vscode-cli\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cMicrosoft\\x5c\\x5cWindowsApps\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cJetBrains\\x5c\\x5cToolbox\\x5c\\x5cscripts\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cnvs\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files (x86)\\x5c\\x5cMicrosoft Visual Studio\\x5c\\x5c2017\\x5c\\x5cBuildTools\\x5c\\x5cMSBuild\\x5c\\x5c15.0\\x5c\\x5cBin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cMicrosoft\\x5c\\x5cWinGet\\x5c\\x5cPackages\\x5c\\x5cBurntSushi.ripgrep.MSVC_Microsoft.Winget.Source_8wekyb3d8bbwe\\x5c\\x5cripgrep-13.0.0-x86_64-pc-windows-msvc\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cMicrosoft\\x5c\\x5cWinGet\\x5c\\x5cPackages\\x5c\\x5cSchniz.fnm_Microsoft.Winget.Source_8wekyb3d8bbwe\\x3bc:\\x5c\\x5cusers\\x5c\\x5cdaniel\\x5c\\x5c.local\\x5c\\x5cbin\\x3bC:\\x5c\\x5cTools\\x5c\\x5cHandle\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cMicrosoft VS Code Insiders\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cJulia-1.11.1\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cMicrosoft VS Code\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPackages\\x5c\\x5cPythonSoftwareFoundation.Python.3.9_qbz5n2kfra8p0\\x5c\\x5cLocalCache\\x5c\\x5clocal-packages\\x5c\\x5cPython39\\x5c\\x5cScripts\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cWindsurf\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5ccursor\\x5c\\x5cresources\\x5c\\x5capp\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cRoaming\\x5c\\x5cnpm\\x3bc:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5c.vscode-oss-dev\\x5c\\x5cUser\\x5c\\x5cglobalStorage\\x5c\\x5cgithub.copilot-chat\\x5c\\x5cdebugCommand"};0af95031-b24c-434e-8c6d-540ab6a9dd37\x07C:\\Github\\Tyriar\\xterm.js \x1b[93m[\x1b[92mmaster ↑2\x1b[93m]\x1b[m> \x1b]633;P;Prompt=C:\\x5cGithub\\x5cTyriar\\x5cxterm.js \\x1b[93m[\\x1b[39m\\x1b[92mmaster\\x1b[39m\\x1b[92m ↑2\\x1b[39m\\x1b[93m]\\x1b[39m> \x07\x1b]633;B\x07',
  },
  {'type': 'promptInputChange', 'data': '|'},
  {'type': 'input', 'data': 'l'},
  {'type': 'output', 'data': '\x1b[?25l'},
  {'type': 'output', 'data': '\x1b[93ml\x1b[97m\x1b[2m\x1b[3ms\x08\x1b[?25h'},
  {'type': 'promptInputChange', 'data': 'l|s'},
  {'type': 'promptInputChange', 'data': 'l|[s]'},
  {'type': 'input', 'data': 's'},
  {'type': 'output', 'data': '\x1b[m\x1b[?25l'},
  {
    'type': 'output',
    'data':
        '\x1b[93m\x08ls\x1b[97m\x1b[2m\x1b[3m; echo hello\x1b[1;42H\x1b[?25h',
  },
  {'type': 'promptInputChange', 'data': 'ls|[; echo hello]'},
  {'type': 'input', 'data': '\r'},
  {
    'type': 'output',
    'data': '\x1b[m\x1b[K\r\n\x1b]633;E;ls;0af95031-b24c-434e-8c6d-540ab6a9dd37\x07',
  },
  {'type': 'promptInputChange', 'data': 'ls'},
  {'type': 'promptInputChange', 'data': 'ls|'},
  {'type': 'output', 'data': '\x1b]633;C\x07'},
  {'type': 'output', 'data': ''},
  {'type': 'promptInputChange', 'data': 'ls'},
  {'type': 'output', 'data': '\r\n'},
  {
    'type': 'output',
    'data': '\x1b[?25l    Directory: C:\\Github\\Tyriar\\xterm.js\x1b[32m\x1b[1m\x1b[5;1HMode                 LastWriteTime\x1b[m \x1b[32m\x1b[1m\x1b[3m        Length\x1b[23m Name\r\n----   \x1b[m \x1b[32m\x1b[1m             -------------\x1b[m \x1b[32m\x1b[1m        ------\x1b[m \x1b[32m\x1b[1m----\x1b[m\r\nd----          29/08/2024  7:52 AM\x1b[16X\x1b[44m\x1b[1m\x1b[16C.devcontainer\x1b[m\r\nd----          21/07/2025  7:23 AM\x1b[16X\x1b[44m\x1b[1m\x1b[16C.github\x1b[m\r\nd----          25/03/2025 11:49 AM\x1b[16X\x1b[44m\x1b[1m\x1b[16C.venv2\x1b[m\r\nd----          21/07/2025  7:13 AM\x1b[16X\x1b[44m\x1b[1m\x1b[16C.vscode\x1b[m\r\nd----          21/06/2025 10:54 AM\x1b[16X\x1b[44m\x1b[1m\x1b[16Caddons\x1b[m\r\nd----          21/06/2025 10:54 AM\x1b[16X\x1b[44m\x1b[1m\x1b[16Cbin\x1b[m\r\nd----          21/06/2025 10:54 AM\x1b[16X\x1b[44m\x1b[1m\x1b[16Ccss\x1b[m\r\nd----          21/06/2025 10:54 AM\x1b[16X\x1b[44m\x1b[1m\x1b[16Cdemo\x1b[m\r\nd----           8/12/2021  4:36 AM\x1b[16X\x1b[44m\x1b[1m\x1b[16Cfixtures\x1b[m\r\nd----          21/06/2025 10:54 AM\x1b[16X\x1b[44m\x1b[1m\x1b[16Cheadless\x1b[m\r\nd----          21/06/2025 10:54 AM\x1b[16X\x1b[44m\x1b[1m\x1b[16Cimages\x1b[m\r\nd----          18/02/2025  7:49 AM\x1b[16X\x1b[44m\x1b[1m\x1b[16Clib\x1b[m\r\nd----          14/03/2025 10:35 AM\x1b[16X\x1b[44m\x1b[1m\x1b[16Cnode_modules\x1b[m\r\nd----          18/02/2025  7:49 AM\x1b[16X\x1b[44m\x1b[1m\x1b[16Cout\x1b[m\r\nd----          18/02/2025  7:49 AM\x1b[16X\x1b[44m\x1b[1m\x1b[16Cout-esbuild\x1b[m\r\nd----          18/02/2025  7:49 AM\x1b[16X\x1b[44m\x1b[1m\x1b[16Cout-esbuild-test\r\x1b[?25h\x1b[m\nd----          18/02/2025  7:49 AM\x1b[44m\x1b[1m\x1b[16Cout-test\x1b[m\x1b[K\r\nd----          21/06/2025 10:54 AM\x1b[44m\x1b[1m\x1b[16Csrc\x1b[m\x1b[K\r\nd----          29/08/2024  7:52 AM\x1b[44m\x1b[1m\x1b[16Ctest\x1b[m\x1b[K\r\nd----          21/06/2025 10:54 AM\x1b[44m\x1b[1m\x1b[16Ctypings\x1b[m\x1b[K\r',
  },
  {
    'type': 'output',
    'data':
        '\n-a---           8/12/2021  4:36 AM            248 .editorconfig\r',
  },
  {
    'type': 'output',
    'data': '\n-a---          21/06/2025 10:54 AM           8424 .eslintrc.json\r\n-a---          29/08/2024  7:52 AM           2298 .eslintrc.json.typings\r\n-a---           8/12/2021  4:36 AM             13 .gitattributes\r\n-a---          21/06/2025 10:54 AM            360 .gitignore\r\n-a---           1/07/2024  7:08 AM              0 .gitmodules\r\n-a---           8/12/2021  4:36 AM            369 .mailmap\r\n-a---           8/12/2021  4:36 AM             17 .mocha.env\r\n-a---          29/11/2022  9:37 AM             91 .mocharc.yml\r\n-a---          21/06/2025 10:54 AM            686 .npmignore\r\n-a---           8/12/2021  4:36 AM             18 .npmrc\r\n-a---          29/08/2024  7:52 AM              4 .nvmrc\r\n-a---           8/12/2021  4:36 AM           3358 CODE_OF_CONDUCT.md\r\n-a---          21/06/2025 10:54 AM           4525 CONTRIBUTING.md\r\n-a---           8/12/2021  4:36 AM           1282 LICENSE\r',
  },
  {
    'type': 'output',
    'data': '\n-a---          21/06/2025 10:55 AM           4439 package.json\r\n-a---          21/06/2025 10:54 AM          22466 README.md\r\n-a---          21/06/2025 10:54 AM            734 tsconfig.all.json\r\n-a---          21/06/2025 10:54 AM           1400 \x1b[32m\x1b[1mwebpack.config.headless.js\x1b[m\x1b[K\r\n-a---          21/06/2025 10:54 AM           1348 \x1b[32m\x1b[1mwebpack.config.js\x1b[m\x1b[K\r\n-a---          21/06/2025 10:55 AM         216246 yarn.lock\r\n',
  },
  {'type': 'output', 'data': '\n'},
  {'type': 'output', 'data': ''},
  {'type': 'output', 'data': '\x1b]633;D;0\x07'},
  {
    'type': 'output',
    'data': '\x1b]633;A\x07\x1b]633;P;Cwd=C:\\x5cGithub\\x5cTyriar\\x5cxterm.js\x07\x1b]633;EnvJson;{"PATH":"C:\\x5c\\x5cProgram Files\\x5c\\x5cWindowsApps\\x5c\\x5cMicrosoft.PowerShell_7.5.2.0_x64__8wekyb3d8bbwe\\x3bC:\\x5c\\x5cProgram Files (x86)\\x5c\\x5coh-my-posh\\x5c\\x5cbin\\x5c\\x5c\\x3bC:\\x5c\\x5cPython312\\x5c\\x5cScripts\\x5c\\x5c\\x3bC:\\x5c\\x5cPython312\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cMicrosoft SDKs\\x5c\\x5cAzure\\x5c\\x5cCLI2\\x5c\\x5cwbin\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cEclipse Adoptium\\x5c\\x5cjdk-8.0.345.1-hotspot\\x5c\\x5cbin\\x3bC:\\x5c\\x5cWINDOWS\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5csystem32\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5cSystem32\\x5c\\x5cWbem\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5cSystem32\\x5c\\x5cWindowsPowerShell\\x5c\\x5cv1.0\\x5c\\x5c\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5cSystem32\\x5c\\x5cOpenSSH\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files (x86)\\x5c\\x5cNVIDIA Corporation\\x5c\\x5cPhysX\\x5c\\x5cCommon\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cGit LFS\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cnu\\x5c\\x5cbin\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cstarship\\x5c\\x5cbin\\x5c\\x5c\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5csystem32\\x3bC:\\x5c\\x5cWINDOWS\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5cSystem32\\x5c\\x5cWbem\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5cSystem32\\x5c\\x5cWindowsPowerShell\\x5c\\x5cv1.0\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cNVIDIA Corporation\\x5c\\x5cNVIDIA NvDLISR\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cGitHub CLI\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files (x86)\\x5c\\x5cWindows Kits\\x5c\\x5c10\\x5c\\x5cWindows Performance Toolkit\\x5c\\x5c\\x3bC:\\x5c\\x5cProgramData\\x5c\\x5cchocolatey\\x5c\\x5cbin\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cdotnet\\x5c\\x5c\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5cSystem32\\x5c\\x5cOpenSSH\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cGnuPG\\x5c\\x5cbin\\x3bC:\\x5c\\x5cProgram Files (x86)\\x5c\\x5cGpg4win\\x5c\\x5c..\\x5c\\x5cGnuPG\\x5c\\x5cbin\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cnodejs\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cGit\\x5c\\x5ccmd\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cPython\\x5c\\x5cPython312\\x5c\\x5cScripts\\x5c\\x5c\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cPython\\x5c\\x5cPython312\\x5c\\x5c\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5coh-my-posh\\x5c\\x5cbin\\x5c\\x5c\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5c.cargo\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cRoaming\\x5c\\x5cPython\\x5c\\x5cScripts\\x5c\\x5c\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cPython\\x5c\\x5cPython310\\x5c\\x5cScripts\\x5c\\x5c\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cPython\\x5c\\x5cPython310\\x5c\\x5c\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cMicrosoft\\x5c\\x5cWindowsApps\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5coh-my-posh\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5coh-my-posh\\x5c\\x5cthemes\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5c.vscode-cli\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cMicrosoft\\x5c\\x5cWindowsApps\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cJetBrains\\x5c\\x5cToolbox\\x5c\\x5cscripts\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cnvs\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files (x86)\\x5c\\x5cMicrosoft Visual Studio\\x5c\\x5c2017\\x5c\\x5cBuildTools\\x5c\\x5cMSBuild\\x5c\\x5c15.0\\x5c\\x5cBin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cMicrosoft\\x5c\\x5cWinGet\\x5c\\x5cPackages\\x5c\\x5cBurntSushi.ripgrep.MSVC_Microsoft.Winget.Source_8wekyb3d8bbwe\\x5c\\x5cripgrep-13.0.0-x86_64-pc-windows-msvc\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cMicrosoft\\x5c\\x5cWinGet\\x5c\\x5cPackages\\x5c\\x5cSchniz.fnm_Microsoft.Winget.Source_8wekyb3d8bbwe\\x3bc:\\x5c\\x5cusers\\x5c\\x5cdaniel\\x5c\\x5c.local\\x5c\\x5cbin\\x3bC:\\x5c\\x5cTools\\x5c\\x5cHandle\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cMicrosoft VS Code Insiders\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cJulia-1.11.1\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cMicrosoft VS Code\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPackages\\x5c\\x5cPythonSoftwareFoundation.Python.3.9_qbz5n2kfra8p0\\x5c\\x5cLocalCache\\x5c\\x5clocal-packages\\x5c\\x5cPython39\\x5c\\x5cScripts\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cWindsurf\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5ccursor\\x5c\\x5cresources\\x5c\\x5capp\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cRoaming\\x5c\\x5cnpm\\x3bc:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5c.vscode-oss-dev\\x5c\\x5cUser\\x5c\\x5cglobalStorage\\x5c\\x5cgithub.copilot-chat\\x5c\\x5cdebugCommand"};0af95031-b24c-434e-8c6d-540ab6a9dd37\x07C:\\Github\\Tyriar\\xterm.js \x1b[93m[\x1b[92mmaster ↑2\x1b[93m]\x1b[m> \x1b]633;P;Prompt=C:\\x5cGithub\\x5cTyriar\\x5cxterm.js \\x1b[93m[\\x1b[39m\\x1b[92mmaster\\x1b[39m\\x1b[92m ↑2\\x1b[39m\\x1b[93m]\\x1b[39m> \x07\x1b]633;B\x07',
  },
  {'type': 'promptInputChange', 'data': '|'},
];

// Windows 24H2
// PowerShell 7.5.2
// Steps:
// - Open terminal
// - Type foo
const richWindows11Pwsh7TypeFoo = <RecordedSessionEvent>[
  {'type': 'resize', 'cols': 167, 'rows': 22},
  {'type': 'output', 'data': '\x1b[?9001h\x1b[?1004h'},
  {'type': 'input', 'data': '\x1b[I'},
  {
    'type': 'output',
    'data': '\x1b[?25l\x1b[2J\x1b[m\x1b[H\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\x1b[H\x1b]0;C:\\Program Files\\WindowsApps\\Microsoft.PowerShell_7.5.2.0_x64__8wekyb3d8bbwe\\pwsh.exe\x07\x1b[?25h',
  },
  {
    'type': 'output',
    'data': '\x1b[?25l\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\x1b[H\x1b[?25h',
  },
  {
    'type': 'output',
    'data': '\x1b]633;P;PromptType=posh-git\x07\x1b]633;P;HasRichCommandDetection=True\x07',
  },
  {
    'type': 'output',
    'data':
        '\x1b]633;P;ContinuationPrompt=>> \x07\x1b]633;P;IsWindows=True\x07',
  },
  {'type': 'command', 'id': '_setContext'},
  {
    'type': 'output',
    'data': '\x1b]0;C:\\Program Files\\WindowsApps\\Microsoft.PowerShell_7.5.2.0_x64__8wekyb3d8bbwe\\pwsh.exe \x07\x1b]0;xterm.js [master] - PowerShell 7.5 (24772)\x07\x1b]633;A\x07\x1b]633;P;Cwd=C:\\x5cGithub\\x5cTyriar\\x5cxterm.js\x07\x1b]633;EnvJson;{"PATH":"C:\\x5c\\x5cProgram Files\\x5c\\x5cWindowsApps\\x5c\\x5cMicrosoft.PowerShell_7.5.2.0_x64__8wekyb3d8bbwe\\x3bC:\\x5c\\x5cProgram Files (x86)\\x5c\\x5coh-my-posh\\x5c\\x5cbin\\x5c\\x5c\\x3bC:\\x5c\\x5cPython312\\x5c\\x5cScripts\\x5c\\x5c\\x3bC:\\x5c\\x5cPython312\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cMicrosoft SDKs\\x5c\\x5cAzure\\x5c\\x5cCLI2\\x5c\\x5cwbin\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cEclipse Adoptium\\x5c\\x5cjdk-8.0.345.1-hotspot\\x5c\\x5cbin\\x3bC:\\x5c\\x5cWINDOWS\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5csystem32\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5cSystem32\\x5c\\x5cWbem\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5cSystem32\\x5c\\x5cWindowsPowerShell\\x5c\\x5cv1.0\\x5c\\x5c\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5cSystem32\\x5c\\x5cOpenSSH\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files (x86)\\x5c\\x5cNVIDIA Corporation\\x5c\\x5cPhysX\\x5c\\x5cCommon\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cGit LFS\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cnu\\x5c\\x5cbin\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cstarship\\x5c\\x5cbin\\x5c\\x5c\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5csystem32\\x3bC:\\x5c\\x5cWINDOWS\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5cSystem32\\x5c\\x5cWbem\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5cSystem32\\x5c\\x5cWindowsPowerShell\\x5c\\x5cv1.0\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cNVIDIA Corporation\\x5c\\x5cNVIDIA NvDLISR\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cGitHub CLI\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files (x86)\\x5c\\x5cWindows Kits\\x5c\\x5c10\\x5c\\x5cWindows Performance Toolkit\\x5c\\x5c\\x3bC:\\x5c\\x5cProgramData\\x5c\\x5cchocolatey\\x5c\\x5cbin\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cdotnet\\x5c\\x5c\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5cSystem32\\x5c\\x5cOpenSSH\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cGnuPG\\x5c\\x5cbin\\x3bC:\\x5c\\x5cProgram Files (x86)\\x5c\\x5cGpg4win\\x5c\\x5c..\\x5c\\x5cGnuPG\\x5c\\x5cbin\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cnodejs\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cGit\\x5c\\x5ccmd\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cPython\\x5c\\x5cPython312\\x5c\\x5cScripts\\x5c\\x5c\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cPython\\x5c\\x5cPython312\\x5c\\x5c\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5coh-my-posh\\x5c\\x5cbin\\x5c\\x5c\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5c.cargo\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cRoaming\\x5c\\x5cPython\\x5c\\x5cScripts\\x5c\\x5c\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cPython\\x5c\\x5cPython310\\x5c\\x5cScripts\\x5c\\x5c\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cPython\\x5c\\x5cPython310\\x5c\\x5c\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cMicrosoft\\x5c\\x5cWindowsApps\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5coh-my-posh\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5coh-my-posh\\x5c\\x5cthemes\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5c.vscode-cli\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cMicrosoft\\x5c\\x5cWindowsApps\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cJetBrains\\x5c\\x5cToolbox\\x5c\\x5cscripts\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cnvs\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files (x86)\\x5c\\x5cMicrosoft Visual Studio\\x5c\\x5c2017\\x5c\\x5cBuildTools\\x5c\\x5cMSBuild\\x5c\\x5c15.0\\x5c\\x5cBin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cMicrosoft\\x5c\\x5cWinGet\\x5c\\x5cPackages\\x5c\\x5cBurntSushi.ripgrep.MSVC_Microsoft.Winget.Source_8wekyb3d8bbwe\\x5c\\x5cripgrep-13.0.0-x86_64-pc-windows-msvc\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cMicrosoft\\x5c\\x5cWinGet\\x5c\\x5cPackages\\x5c\\x5cSchniz.fnm_Microsoft.Winget.Source_8wekyb3d8bbwe\\x3bc:\\x5c\\x5cusers\\x5c\\x5cdaniel\\x5c\\x5c.local\\x5c\\x5cbin\\x3bC:\\x5c\\x5cTools\\x5c\\x5cHandle\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cMicrosoft VS Code Insiders\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cJulia-1.11.1\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cMicrosoft VS Code\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPackages\\x5c\\x5cPythonSoftwareFoundation.Python.3.9_qbz5n2kfra8p0\\x5c\\x5cLocalCache\\x5c\\x5clocal-packages\\x5c\\x5cPython39\\x5c\\x5cScripts\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cWindsurf\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5ccursor\\x5c\\x5cresources\\x5c\\x5capp\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cRoaming\\x5c\\x5cnpm\\x3bc:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5c.vscode-oss-dev\\x5c\\x5cUser\\x5c\\x5cglobalStorage\\x5c\\x5cgithub.copilot-chat\\x5c\\x5cdebugCommand"};4638516d-26e2-4016-9298-62b0ddca0bd6\x07C:\\Github\\Tyriar\\xterm.js \x1b[93m[\x1b[92mmaster ↑2\x1b[93m]\x1b[m> \x1b]633;P;Prompt=C:\\x5cGithub\\x5cTyriar\\x5cxterm.js \\x1b[93m[\\x1b[39m\\x1b[92mmaster\\x1b[39m\\x1b[92m ↑2\\x1b[39m\\x1b[93m]\\x1b[39m> \x07\x1b]633;B\x07',
  },
  {'type': 'promptInputChange', 'data': '|'},
  {'type': 'commandDetection.onCommandStarted'},
  {'type': 'input', 'data': 'f'},
  {'type': 'output', 'data': '\x1b[?25l'},
  {
    'type': 'output',
    'data': '\x1b[93mf\x1b[97m\x1b[2m\x1b[3mor (\$i=40; \$i -le 101; \$i++) { \$branch = "origin/release/1.\$i"; if (git rev-parse --verify \$branch 2>\$null) { \$count = git rev-list --count --first-parent \$branch "^main" 2>\$null; if (\$count) { Write-Host "release/1.\$i : \$count first-parent commits" } else { Write-Host "release/1.\$i : 0 first-parent commits" } } else { Write-Host "release/1.\$i : branch not found" } }\x1b[1;41H\x1b[?25h',
  },
  {
    'type': 'promptInputChange',
    'data': 'f|or (\$i=40; \$i -le 101; \$i++) { \$branch = "origin/release/1.\$i"; if (git rev-parse --verify \$branch 2>\$null) { \$count = git rev-list --count --first-parent \$branch "^main" 2>\$null; if (\$count) { Write-Host "release/1.\$i : \$count first-parent commits" } else { Write-Host "release/1.\$i : 0 first-parent commits" } } else { Write-Host "release/1.\$i : branch not found" } }',
  },
  {
    'type': 'promptInputChange',
    'data': 'f|[or (\$i=40; \$i -le 101; \$i++) { \$branch = "origin/release/1.\$i"; if (git rev-parse --verify \$branch 2>\$null) { \$count = git rev-list --count --first-parent \$branch "^main" 2>\$null; if (\$count) { Write-Host "release/1.\$i : \$count first-parent commits" } else { Write-Host "release/1.\$i : 0 first-parent commits" } } else { Write-Host "release/1.\$i : branch not found" } }]',
  },
  {'type': 'input', 'data': 'o'},
  {'type': 'output', 'data': '\x1b[m\x1b[?25l'},
  {
    'type': 'output',
    'data': '\x1b[93m\x08fo\x1b[97m\x1b[2m\x1b[3mr (\$i=40; \$i -le 101; \$i++) { \$branch = "origin/release/1.\$i"; if (git rev-parse --verify \$branch 2>\$null) { \$count = git rev-list --count --first-parent \$branch "^main" 2>\$null; if (\$count) { Write-Host "release/1.\$i : \$count first-parent commits" } else { Write-Host "release/1.\$i : 0 first-parent commits" } } else { Write-Host "release/1.\$i : branch not found" } }\x1b[1;42H\x1b[?25h',
  },
  {
    'type': 'promptInputChange',
    'data': 'fo|[r (\$i=40; \$i -le 101; \$i++) { \$branch = "origin/release/1.\$i"; if (git rev-parse --verify \$branch 2>\$null) { \$count = git rev-list --count --first-parent \$branch "^main" 2>\$null; if (\$count) { Write-Host "release/1.\$i : \$count first-parent commits" } else { Write-Host "release/1.\$i : 0 first-parent commits" } } else { Write-Host "release/1.\$i : branch not found" } }]',
  },
  {'type': 'input', 'data': 'o'},
  {'type': 'output', 'data': '\x1b[m\x1b[?25l'},
  {
    'type': 'output',
    'data': '\x1b[93m\x1b[1;40Hfoo                                                                                                                             \x1b[m                                                                                                                                                                       \r\n\x1b[75X\x1b[1;43H\x1b[?25h',
  },
  {'type': 'promptInputChange', 'data': 'foo|'},
];

// Windows 24H2
// PowerShell 7.5.2
// Steps:
// - Open terminal
// - Type foo
// - Left arrow twice
const richWindows11Pwsh7TypeFooLeftTwice = <RecordedSessionEvent>[
  {'type': 'resize', 'cols': 167, 'rows': 22},
  {'type': 'output', 'data': '\x1b[?9001h\x1b[?1004h'},
  {'type': 'input', 'data': '\x1b[I'},
  {
    'type': 'output',
    'data': '\x1b[?25l\x1b[2J\x1b[m\x1b[H\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\x1b[H\x1b]0;C:\\Program Files\\WindowsApps\\Microsoft.PowerShell_7.5.2.0_x64__8wekyb3d8bbwe\\pwsh.exe\x07\x1b[?25h',
  },
  {
    'type': 'output',
    'data': '\x1b[?25l\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\r\n\x1b[K\x1b[H\x1b[?25h',
  },
  {
    'type': 'output',
    'data': '\x1b]633;P;PromptType=posh-git\x07\x1b]633;P;HasRichCommandDetection=True\x07',
  },
  {
    'type': 'output',
    'data':
        '\x1b]633;P;ContinuationPrompt=>> \x07\x1b]633;P;IsWindows=True\x07',
  },
  {'type': 'command', 'id': '_setContext'},
  {
    'type': 'output',
    'data': '\x1b]0;C:\\Program Files\\WindowsApps\\Microsoft.PowerShell_7.5.2.0_x64__8wekyb3d8bbwe\\pwsh.exe \x07',
  },
  {
    'type': 'output',
    'data': '\x1b]0;C:\\Program Files\\WindowsApps\\Microsoft.PowerShell_7.5.2.0_x64__8wekyb3d8bbwe\\pwsh.exe\x07\x1b]0;xterm.js [master] - PowerShell 7.5 (30016)\x07\x1b]633;A\x07\x1b]633;P;Cwd=C:\\x5cGithub\\x5cTyriar\\x5cxterm.js\x07\x1b]633;EnvJson;{"PATH":"C:\\x5c\\x5cProgram Files\\x5c\\x5cWindowsApps\\x5c\\x5cMicrosoft.PowerShell_7.5.2.0_x64__8wekyb3d8bbwe\\x3bC:\\x5c\\x5cProgram Files (x86)\\x5c\\x5coh-my-posh\\x5c\\x5cbin\\x5c\\x5c\\x3bC:\\x5c\\x5cPython312\\x5c\\x5cScripts\\x5c\\x5c\\x3bC:\\x5c\\x5cPython312\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cMicrosoft SDKs\\x5c\\x5cAzure\\x5c\\x5cCLI2\\x5c\\x5cwbin\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cEclipse Adoptium\\x5c\\x5cjdk-8.0.345.1-hotspot\\x5c\\x5cbin\\x3bC:\\x5c\\x5cWINDOWS\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5csystem32\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5cSystem32\\x5c\\x5cWbem\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5cSystem32\\x5c\\x5cWindowsPowerShell\\x5c\\x5cv1.0\\x5c\\x5c\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5cSystem32\\x5c\\x5cOpenSSH\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files (x86)\\x5c\\x5cNVIDIA Corporation\\x5c\\x5cPhysX\\x5c\\x5cCommon\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cGit LFS\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cnu\\x5c\\x5cbin\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cstarship\\x5c\\x5cbin\\x5c\\x5c\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5csystem32\\x3bC:\\x5c\\x5cWINDOWS\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5cSystem32\\x5c\\x5cWbem\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5cSystem32\\x5c\\x5cWindowsPowerShell\\x5c\\x5cv1.0\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cNVIDIA Corporation\\x5c\\x5cNVIDIA NvDLISR\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cGitHub CLI\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files (x86)\\x5c\\x5cWindows Kits\\x5c\\x5c10\\x5c\\x5cWindows Performance Toolkit\\x5c\\x5c\\x3bC:\\x5c\\x5cProgramData\\x5c\\x5cchocolatey\\x5c\\x5cbin\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cdotnet\\x5c\\x5c\\x3bC:\\x5c\\x5cWINDOWS\\x5c\\x5cSystem32\\x5c\\x5cOpenSSH\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cGnuPG\\x5c\\x5cbin\\x3bC:\\x5c\\x5cProgram Files (x86)\\x5c\\x5cGpg4win\\x5c\\x5c..\\x5c\\x5cGnuPG\\x5c\\x5cbin\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cnodejs\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files\\x5c\\x5cGit\\x5c\\x5ccmd\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cPython\\x5c\\x5cPython312\\x5c\\x5cScripts\\x5c\\x5c\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cPython\\x5c\\x5cPython312\\x5c\\x5c\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5coh-my-posh\\x5c\\x5cbin\\x5c\\x5c\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5c.cargo\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cRoaming\\x5c\\x5cPython\\x5c\\x5cScripts\\x5c\\x5c\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cPython\\x5c\\x5cPython310\\x5c\\x5cScripts\\x5c\\x5c\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cPython\\x5c\\x5cPython310\\x5c\\x5c\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cMicrosoft\\x5c\\x5cWindowsApps\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5coh-my-posh\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5coh-my-posh\\x5c\\x5cthemes\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5c.vscode-cli\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cMicrosoft\\x5c\\x5cWindowsApps\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cJetBrains\\x5c\\x5cToolbox\\x5c\\x5cscripts\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cnvs\\x5c\\x5c\\x3bC:\\x5c\\x5cProgram Files (x86)\\x5c\\x5cMicrosoft Visual Studio\\x5c\\x5c2017\\x5c\\x5cBuildTools\\x5c\\x5cMSBuild\\x5c\\x5c15.0\\x5c\\x5cBin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cMicrosoft\\x5c\\x5cWinGet\\x5c\\x5cPackages\\x5c\\x5cBurntSushi.ripgrep.MSVC_Microsoft.Winget.Source_8wekyb3d8bbwe\\x5c\\x5cripgrep-13.0.0-x86_64-pc-windows-msvc\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cMicrosoft\\x5c\\x5cWinGet\\x5c\\x5cPackages\\x5c\\x5cSchniz.fnm_Microsoft.Winget.Source_8wekyb3d8bbwe\\x3bc:\\x5c\\x5cusers\\x5c\\x5cdaniel\\x5c\\x5c.local\\x5c\\x5cbin\\x3bC:\\x5c\\x5cTools\\x5c\\x5cHandle\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cMicrosoft VS Code Insiders\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cJulia-1.11.1\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cMicrosoft VS Code\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPackages\\x5c\\x5cPythonSoftwareFoundation.Python.3.9_qbz5n2kfra8p0\\x5c\\x5cLocalCache\\x5c\\x5clocal-packages\\x5c\\x5cPython39\\x5c\\x5cScripts\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5cWindsurf\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cLocal\\x5c\\x5cPrograms\\x5c\\x5ccursor\\x5c\\x5cresources\\x5c\\x5capp\\x5c\\x5cbin\\x3bC:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5cAppData\\x5c\\x5cRoaming\\x5c\\x5cnpm\\x3bc:\\x5c\\x5cUsers\\x5c\\x5cDaniel\\x5c\\x5c.vscode-oss-dev\\x5c\\x5cUser\\x5c\\x5cglobalStorage\\x5c\\x5cgithub.copilot-chat\\x5c\\x5cdebugCommand"};a379e16d-df58-451e-8d2c-ad6e2b161777\x07C:\\Github\\Tyriar\\xterm.js \x1b[93m[\x1b[92mmaster ↑2\x1b[93m]\x1b[m> \x1b]633;P;Prompt=C:\\x5cGithub\\x5cTyriar\\x5cxterm.js \\x1b[93m[\\x1b[39m\\x1b[92mmaster\\x1b[39m\\x1b[92m ↑2\\x1b[39m\\x1b[93m]\\x1b[39m> \x07\x1b]633;B\x07',
  },
  {'type': 'promptInputChange', 'data': '|'},
  {'type': 'commandDetection.onCommandStarted'},
  {'type': 'input', 'data': 'f'},
  {'type': 'output', 'data': '\x1b[?25l'},
  {
    'type': 'output',
    'data': '\x1b[93mf\x1b[97m\x1b[2m\x1b[3mor (\$i=40; \$i -le 101; \$i++) { \$branch = "origin/release/1.\$i"; if (git rev-parse --verify \$branch 2>\$null) { \$count = git rev-list --count --first-parent \$branch "^main" 2>\$null; if (\$count) { Write-Host "release/1.\$i : \$count first-parent commits" } else { Write-Host "release/1.\$i : 0 first-parent commits" } } else { Write-Host "release/1.\$i : branch not found" } }\x1b[1;41H\x1b[?25h',
  },
  {
    'type': 'promptInputChange',
    'data': 'f|or (\$i=40; \$i -le 101; \$i++) { \$branch = "origin/release/1.\$i"; if (git rev-parse --verify \$branch 2>\$null) { \$count = git rev-list --count --first-parent \$branch "^main" 2>\$null; if (\$count) { Write-Host "release/1.\$i : \$count first-parent commits" } else { Write-Host "release/1.\$i : 0 first-parent commits" } } else { Write-Host "release/1.\$i : branch not found" } }',
  },
  {
    'type': 'promptInputChange',
    'data': 'f|[or (\$i=40; \$i -le 101; \$i++) { \$branch = "origin/release/1.\$i"; if (git rev-parse --verify \$branch 2>\$null) { \$count = git rev-list --count --first-parent \$branch "^main" 2>\$null; if (\$count) { Write-Host "release/1.\$i : \$count first-parent commits" } else { Write-Host "release/1.\$i : 0 first-parent commits" } } else { Write-Host "release/1.\$i : branch not found" } }]',
  },
  {'type': 'input', 'data': 'o'},
  {'type': 'output', 'data': '\x1b[m\x1b[?25l'},
  {
    'type': 'output',
    'data': '\x1b[93m\x08fo\x1b[97m\x1b[2m\x1b[3mr (\$i=40; \$i -le 101; \$i++) { \$branch = "origin/release/1.\$i"; if (git rev-parse --verify \$branch 2>\$null) { \$count = git rev-list --count --first-parent \$branch "^main" 2>\$null; if (\$count) { Write-Host "release/1.\$i : \$count first-parent commits" } else { Write-Host "release/1.\$i : 0 first-parent commits" } } else { Write-Host "release/1.\$i : branch not found" } }\x1b[1;42H\x1b[?25h',
  },
  {
    'type': 'promptInputChange',
    'data': 'fo|[r (\$i=40; \$i -le 101; \$i++) { \$branch = "origin/release/1.\$i"; if (git rev-parse --verify \$branch 2>\$null) { \$count = git rev-list --count --first-parent \$branch "^main" 2>\$null; if (\$count) { Write-Host "release/1.\$i : \$count first-parent commits" } else { Write-Host "release/1.\$i : 0 first-parent commits" } } else { Write-Host "release/1.\$i : branch not found" } }]',
  },
  {'type': 'input', 'data': 'o'},
  {'type': 'output', 'data': '\x1b[m\x1b[?25l'},
  {
    'type': 'output',
    'data': '\x1b[93m\x1b[1;40Hfoo                                                                                                                             \x1b[m                                                                                                                                                                       \r\n\x1b[75X\x1b[1;43H\x1b[?25h',
  },
  {'type': 'promptInputChange', 'data': 'foo|'},
  {'type': 'input', 'data': '\x1b[D'},
  {'type': 'output', 'data': '\x08'},
  {'type': 'promptInputChange', 'data': 'fo|o'},
  {'type': 'input', 'data': '\x1b[D'},
  {'type': 'output', 'data': '\x08'},
  {'type': 'promptInputChange', 'data': 'f|oo'},
];
