/// The skills the agent comes with: commands the user runs by `/name`,
/// most of which the model may load too (the Skill tool). `init`,
/// `security-review` and `insights` are commands, not skills: they are
/// listed among the agent's own.
library;

import '../config/extensions.dart';
import 'task_prompts.dart';

PromptCommand _skill(
  String name,
  String description,
  String body, {
  String argumentHint = '',
  String? whenToUse,
  bool modelInvocable = true,
  bool isSkill = true,
  List<String> aliases = const [],
}) => PromptCommand(
  name: name,
  description: description,
  body: body,
  path: '',
  source: 'bundled',
  isSkill: isSkill,
  argumentHint: argumentHint,
  whenToUse: whenToUse,
  modelInvocable: modelInvocable,
  aliases: aliases,
);

/// The bundled skills, in the order they are listed.
final List<PromptCommand> bundledSkills = [
  _skill(
    'dataviz',
    'Read this before making any chart, graph, plot, dashboard or other '
        'picture of data, in any medium: an HTML page or React component, an '
        'inline SVG, plotting code in any library (matplotlib, plotly, d3, '
        'Recharts…), or an image to render. Load it before the first line of '
        'chart code, before choosing chart colors, and before laying out a '
        'stat tile, a row of KPIs or a dashboard. It gives a way of working '
        'that makes charts read as one system, clear and accessible in light '
        'and dark alike: which form fits the data, how to build a palette '
        'and check it, how each kind of mark is drawn, and how charts '
        'respond to the pointer. Triggers: "chart", "graph", "plot", "data '
        'viz", "visualization", "dashboard", "analytics", "heatmap", '
        '"sparkline", "legend", "axis", "tooltip", "chart colors".',
    _dataviz,
  ),
  _skill(
    'update-config',
    'Use this to change how the agent itself is set up, in settings.json. '
        'Anything automatic ("from now on when X", "each time X", "whenever '
        'X", "before/after X") needs a hook in settings.json: the harness '
        'runs hooks, the model does not, so memory or a preference cannot '
        'do it. Also for permissions ("allow X", "add a permission", "move '
        'this permission to"), environment variables ("set X=Y"), fixing '
        'hooks, or any change to settings.json and settings.local.json. '
        'Examples: "allow npm commands", "add a bq permission to my global '
        'settings", "set DEBUG=true", "when the agent stops, show X".',
    _updateConfig,
  ),
  _skill(
    'verify',
    'Check that a change really does what it is meant to, by running it '
        'end to end and watching what it does: drive the flow it touches, '
        'not only its tests or the type checker. Run it before committing '
        'a change of any size; it starts this project\'s own verify skill if '
        'there is none yet. Not for a change only to tests, docs or other '
        'code that nothing runs.',
    _verify,
    modelInvocable: false,
  ),
  _skill(
    'debug',
    'Help find out why the agent misbehaves in this session: its settings, '
        'hooks, MCP servers, permissions and logs',
    _debug,
    argumentHint: '[issue description]',
    modelInvocable: false,
  ),
  _skill(
    'code-review',
    'Review the changes not committed (or a pull request, branch or path '
        'named) for bugs, and where it fits for code to reuse, simplify or '
        'make faster, at an effort level (low|medium|high|xhigh|max: from a '
        'few findings it is sure of to many, some of them less sure). '
        '--fix applies the findings to the working tree after the review; '
        '--comment posts them as comments on the pull request; '
        '--max-findings <n> (or all) sets how many to report.',
    _codeReview,
    argumentHint:
        '[low|medium|high|xhigh|max] [--fix] [--comment] '
        '[<pr#>|<branch>|<path>] [--max-findings <n>|all]',
    aliases: const ['review'],
  ),
  _skill(
    'simplify',
    'Review the code changed for what could be reused, made simpler, made '
        'faster or put at the right level, then make those changes. Quality '
        'only: it does not look for bugs (that is /code-review).',
    _simplify,
    argumentHint: '[<target>]',
  ),
  _skill(
    'batch',
    'Look into and plan a large change, then carry it out in parallel: '
        'agents in worktrees of their own, each opening a pull request.',
    _batch,
    argumentHint: '<instruction>',
    modelInvocable: false,
  ),
  _skill(
    'fewer-permission-prompts',
    'Go through the past sessions for the read-only Bash and MCP calls '
        'that keep being asked about, and add the most useful of them to an '
        'allow list in the project\'s .claude/settings.json, so that they are '
        'asked about less.',
    _fewerPermissionPrompts,
  ),
  _skill(
    'doctor',
    'Check how the agent is set up here and put right what is wrong: '
        'settings files that do not parse, agents, skills and commands whose '
        'header is broken or whose names clash, MCP servers that do not '
        'start, hooks that fail, and instructions files that contradict '
        'each other.',
    _doctor,
    modelInvocable: false,
    aliases: const ['checkup'],
  ),
  _skill(
    'loop',
    'Run a prompt or a slash command again and again, at an interval '
        '(/loop 5m /foo); with no interval, the agent picks the pace itself.',
    _loop,
    argumentHint: '[interval] [prompt]',
    whenToUse:
        'When the user wants something done on a schedule, something '
        'watched, or a command run over and over ("check the deploy every '
        '5 minutes", "keep running /babysit-prs"). Not for something done '
        'once.',
    aliases: const ['proactive'],
  ),
  _skill(
    'claude-api',
    'Reference for building on the Claude API and the Anthropic SDKs: model '
        'IDs, prices, parameters, streaming, tool use, MCP, agents, prompt '
        'caching, counting tokens, moving to a newer model.\n'
        'TRIGGER: load it before opening the file to change, even for what '
        'looks like one line, when the prompt names Claude or Anthropic in '
        'any form (Claude, Anthropic, Fable, Opus, Sonnet, Haiku, '
        '`anthropic`, `@anthropic-ai`, `claude-*`); when the user asks about '
        'a language model (prices, which model, limits, caching), never '
        'answering from memory; or when the task is built on a model and '
        'no provider is named (an agent, MCP, tool definitions, several '
        'agents together, RAG, a model as judge; generating, summarizing, '
        'extracting, classifying or rewriting text; refusals, cut-off '
        'answers, streaming, tool calls or tokens going wrong).\n'
        'SKIP it, whatever the above, when another provider is the one '
        'being worked on: OpenAI, GPT, Gemini, Llama, Mistral, Cohere or '
        'Ollama named in the request; or, with no provider named, `grep -rE '
        '\'openai|langchain_openai|google.generativeai|genai|mistralai|cohere|ollama\'` '
        'over the project finds any (run that grep first, rather than '
        'reading the file).',
    _claudeApi,
  ),
  _skill(
    'run',
    'Start this project\'s app and use it, to see a change at work. Use it '
        'when asked to run, start or take a screenshot of the app, or to make '
        'sure a change works in the real app and not only in tests. It looks '
        'first for a skill of the project\'s that says how to start the '
        'app; else it goes by the kind of project (a command-line tool, a '
        'server, a terminal UI, a desktop app, a web page, a library).',
    _run,
  ),
  _skill(
    'run-skill-generator',
    'Write or improve the project\'s own run skill: how to build, start and '
        'drive its app, for agents. Use it when the user asks to set the '
        'project up, get it running, write down how to run it, or check '
        'that it builds and runs from a clean checkout.',
    _runSkillGenerator,
    modelInvocable: false,
  ),
  _skill(
    'init',
    'Write a CLAUDE.md that tells agents how this codebase works',
    initPrompt,
    isSkill: false,
  ),
  _skill(
    'security-review',
    'Look for security holes in the changes on this branch',
    securityReviewPrompt,
    isSkill: false,
  ),
  _skill(
    'insights',
    'A report on how you have been working with the agent here, from your '
        'past sessions',
    _insights,
    modelInvocable: false,
    isSkill: false,
  ),
];

const _dataviz = r'''# Charts that read well

Make every chart, plot and dashboard of this task follow one method, so that they look like one family and say what the data says, in light and dark themes alike.

## 1. Choose the form from the question
Decide what the reader should see, then the form:
- A change over time: a line (an area only for one series whose total matters). Bars only for few, separate periods.
- Comparing amounts: bars, horizontal when the labels are long. Sort them, unless the categories have an order of their own.
- Part of a whole: a stacked bar, or a single bar split in parts. A pie only for two or three parts, never a donut of many.
- How values spread: a histogram, or a box or strip plot for several groups.
- Two measures against each other: a scatter plot; size or color for a third only if it is needed.
- One number that matters: a stat tile (the number, its unit, what it is compared with), not a chart.
- A table when the reader will look values up, not compare shapes.
Leave out what does not help: 3D, shadows, gradients, decorative icons, a legend for a single series, gridlines heavier than the data.

## 2. Build the palette, and check it
- Categories: at most six or seven colors, of similar lightness and clearly different hue. More categories than that: group the small ones as "Other", or use small multiples.
- Ordered values (low to high): one hue going from light to dark, lightness changing evenly. Values around a middle (below and above a target): two hues meeting at a neutral middle.
- Keep one meaning per color across all charts of the task: the same series has the same color everywhere.
- Check the palette in code before using it: each color against the background must reach a contrast ratio of at least 3:1 (WCAG relative luminance), and neighbouring categorical colors must stay apart for the common kinds of color blindness (simulate deuteranopia and protanopia, and keep their difference visible). Fix the colors that fail; do not drop the check.
- Define the palette once (as CSS variables, a theme object, a constants list) with a light and a dark value for each color, and take every color from it. If the project has a palette or brand colors already, use those, and check them the same way.

## 3. Draw the marks
- Lines: 2px, round joins; a point marker only where the reader needs single values. Label the lines at their ends instead of a legend when there are few.
- Bars: start at zero, always. Gaps of about a third of the bar width. Value labels inside or at the end of the bar rather than a dense axis.
- Axes: as few ticks as tell the range; units in the axis title or the tick labels, not both; numbers formatted (1.2k, 45%, 2026-03) and aligned.
- Text: the chart's own font is the page's. Titles say what the chart shows ("Sign-ups doubled after the launch"), not only what it is ("Sign-ups").
- Gridlines, axes and labels in a muted color; the data in the strongest one.

## 4. Make it respond
- A tooltip on hover or focus shows the exact values of what is under the pointer, with the series' color beside its name.
- Hovering a legend item or a series brings it forward and dims the others.
- Every interaction works by keyboard as well, and the chart has a text alternative (a caption, or a table to open).
- Animate only to show a change of data, briefly (under 300ms), and not at all when the user asks for reduced motion.

## 5. Dashboards and tiles
- One grid, one gap size, one corner radius, one card style.
- The most important number first (top left), then what explains it.
- Tiles in a row share their height and the alignment of their numbers.

## 6. Before you hand it over
Look at the result (render it, take a screenshot when you can) in light and dark: nothing overlaps, every label is legible, the colors match across charts, and the first thing the eye lands on is the point of the chart.

$ARGUMENTS''';

const _updateConfig = r'''# Changing the agent's settings

The user wants to change how the agent is set up. Settings live in JSON files, the later over the earlier:
- `~/.claude/settings.json`: the user's own, for every project.
- `.claude/settings.json`: the project's, kept in its repository and shared.
- `.claude/settings.local.json`: the user's own for this project, not committed.

Pick the file by who the change is for: the user everywhere, the team, or the user here. When it is not clear, ask. Read the file first, change only the keys concerned, keep the rest as it is, and write valid JSON. Say afterwards which file you changed and what you put in it.

## Automatic behaviour: hooks
What should happen by itself ("every time…", "whenever…", "after each edit…", "when the agent stops…") is a hook: a command the harness runs on an event. Memory and preferences cannot do it; the model may forget, the harness does not.

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [{ "type": "command", "command": "npx prettier --write \"$(jq -r '.tool_input.file_path')\"", "timeout": 30 }]
      }
    ]
  }
}
```

- Events: PreToolUse, PostToolUse, PostToolUseFailure, PostToolBatch, UserPromptSubmit, UserPromptExpansion, Notification, Stop, StopFailure, SubagentStart, SubagentStop, PreCompact, PostCompact, SessionStart, SessionEnd, PermissionRequest, PermissionDenied, PreModelSwitch, PostModelSwitch, Setup, TaskCreated, TaskCompleted, TeammateIdle, Elicitation, ElicitationResult, ConfigChange, InstructionsLoaded, CwdChanged, FileChanged, DirectoryAdded, WorktreeCreate, WorktreeRemove, MessageDisplay.
- `matcher` is a regular expression on the tool's name (for the tool events) or the event's source; left out, it matches all.
- Types: `command` (a shell command; the event comes as JSON on its standard input), `prompt` (a question a small model answers yes or no), `agent` (an agent that checks, with tools), `http` (a POST of the event to a URL), `mcp_tool` (a call of an MCP server's tool).
- A command hook that exits with code 2 blocks what it is about; what it prints on standard error is the reason, given to the model. Exit 0 with JSON on standard output can say more: `{"decision": "block", "reason": "…"}`, `{"continue": false, "stopReason": "…"}`, `{"systemMessage": "…"}`, or `hookSpecificOutput` (for PreToolUse: `permissionDecision` allow, deny or ask; for UserPromptSubmit and SessionStart: `additionalContext`).
- Test a command with a sample of the event's JSON before saving it, and quote paths that may hold spaces.

## Permissions
```json
{ "permissions": { "allow": ["Bash(npm run test:*)", "Read(~/notes/**)"], "deny": ["Bash(rm -rf:*)"], "ask": ["WebFetch"], "defaultMode": "acceptEdits", "additionalDirectories": ["../shared"] } }
```
- A rule is a tool's name, with what it applies to in parentheses: a command prefix for Bash (`npm run build`, or `git log:*` for all that starts so), a path pattern for Read and Edit (`/src/**` from the settings file's folder, `~/…` from home, `//abs/…` absolute), `domain:example.com` for WebFetch, `mcp__server` or `mcp__server__tool` for MCP.
- Deny wins over ask, ask over allow. "Move this permission" means taking it from one file and putting it in another.

## Environment and the rest
- `"env": {"KEY": "value"}` sets variables for every session (and for the commands it runs).
- Other keys: `model`, `effortLevel`, `outputStyle`, `alwaysThinkingEnabled`, `autoMemoryEnabled`, `autoCompactWindow`, `plansDirectory`, `attribution` (`{"commit": "…", "pr": "…"}`), `worktree` (`{"baseRef": "fresh" | "head" | a ref}`), `enabledPlugins`, `apiKeyHelper`, `disableAllHooks`.
- For a simple setting such as the model or the output style, the user can also use /config, /model or /output-style.

$ARGUMENTS''';

const _verify = r'''# Verify the change

Show that the change works by running it the way it will really be used, and watching it work. Tests passing and types checking are not enough on their own.

1. Find out what changed (`git status`, `git diff`, and the commits of the branch) and what it is meant to do. If that is not clear from the code and the conversation, ask.
2. Look for this project's own way of checking: a `verify` or `run-*` skill in `.claude/skills/`, or notes in CLAUDE.md or the README on running the app. Follow it when there is one.
3. If there is none, work one out from the project: how to build it, start it and reach the part that changed (a command to run, a request to send, a page to open, a function to call from a small script). Write it down as a project skill in `.claude/skills/verify/SKILL.md` (a header with `name` and `description`, then the steps), so the next check starts there.
4. Build, start it, and drive the flow the change touches: the main case, then the edges the change could break (empty input, errors, the case before the change). Watch the real output: what is printed, returned, stored or shown.
5. Run the tests that cover the change too, but only those, not the whole suite.
6. Stop what you started.

Report plainly: what you ran, what you saw, and whether the change works. If it does not, or you could not run it, say so and why; do not claim it works without having seen it.

$ARGUMENTS''';

const _debug = r'''# Find out what is wrong

The user has a problem with the agent in this session: $ARGUMENTS

Look into it from what is on this machine, and say what you find:
- Settings: read `~/.claude/settings.json`, `.claude/settings.json` and `.claude/settings.local.json`. Check that each parses as JSON, and look for keys that are misspelled, of the wrong type, or set in two files with different values.
- Hooks: list the hooks in those files and in the plugins switched on. Run a hook's command by hand with a sample of its event's JSON on standard input, and see what it prints and how it exits.
- Permissions: find the rules that bear on what was refused or asked about, and which file each comes from.
- MCP servers: read `.mcp.json` and the user's servers in `~/.claude.json`; for one that does not connect, try starting its command by hand and read what it says.
- Instructions: the CLAUDE.md files and rules that apply, and any that contradict the user's expectation.
- The session's own record: the conversation of this project is kept in `~/.claude/projects/<the project's path with every non-alphanumeric character a dash>/<session id>.jsonl`; its last lines show what was sent and what came back.

Change nothing without asking first. End with the cause, if you found it, and what to do about it.''';

const _codeReview = r'''# Code review

Arguments: $ARGUMENTS

Read the arguments:
- An effort level (low, medium, high, xhigh, max): how many findings to look for. low: only a few, each one certain. medium (the default): the real problems, few doubtful ones. high and above: also the likely problems, then the possible ones, marked as less sure.
- A target: a pull request number, a branch, or a path. With none, the changes not committed (staged or not), and the commits of this branch against the main branch.
- `--fix`: apply the findings to the working tree after the review.
- `--comment`: post the findings as comments on the pull request's lines (`gh api`), after the review.
- `--max-findings <n>` or `--max-findings all`: how many to report at most (10 unless given).

## How
1. Get the diff (`git diff`, `git diff <main>...HEAD`, or `gh pr diff <n>`), and read enough of the code around each change to understand what it does and what calls it.
2. Look for bugs first: wrong logic, cases not handled (empty, null, errors, limits, concurrency), wrong use of an API, security holes, data loss, resources not released, behaviour changed for callers. Then, where it applies, code that duplicates something already there, could be simpler, does needless work, or sits at the wrong level.
3. For each finding, check it before you report it: read the code it depends on, and when you can, make it happen (a test, a small script). Keep only those that hold up; mark the ones you could not confirm as plausible.
4. Rank them, the most serious first.

## Report
If the ReportFindings tool is offered, report with it, once: each finding with its file (relative to the repository), line, a one-sentence summary, a short summary of at most 60 characters, the failure scenario (the inputs or state, and what goes wrong), its category, and its verdict (CONFIRMED or PLAUSIBLE); and do not write them out again as text. Otherwise write them as a list in that order. With no findings, say so in a line.

With `--fix`, then make the changes for the findings, and report again with each finding's `outcome` (fixed, skipped, no_change_needed). With `--comment`, post each finding on its line of the pull request.''';

const _simplify = r'''# Simplify the code changed

Target: $ARGUMENTS (with none: the changes not committed, and the commits of this branch against the main branch).

Look only at the quality of the changed code, not at whether it is right (that is /code-review):
- Reuse: code that does what a function, type or helper already in the codebase does. Search for one before you write it off; use it instead.
- Simpler: logic that can be said in fewer steps, conditions that can be merged, state that need not be kept, abstractions with one user, options nobody passes, comments that say what the code says.
- Faster: work done again and again that could be done once, lookups in a loop, needless copies, reading what is not used.
- Level: code in the wrong place: a detail of one caller in a shared module, or logic every caller repeats that belongs below them.

Then make the changes, keeping behaviour exactly as it is. Match the code around them. Run the tests that cover what you touched. Say briefly what you changed and why; if nothing was worth changing, say so.''';

const _batch = r'''# A large change, in parallel

The change: $ARGUMENTS

1. Look into it: find every place it touches (search the codebase thoroughly, with Explore agents for wide searches), and how the code does such things now.
2. Plan it: split it into 5 to 30 pieces that can be done apart from each other, each small enough for one pull request and touching files the others do not. Write the plan down (the pieces, the files of each, what is done the same way in all) and show it to the user; wait for them to agree before going on.
3. Do it: for each piece, start an agent (Agent tool) with `isolation: "worktree"`, in the background, with a prompt that holds the shared approach and its own piece in full: what to change, how, how to check it (the tests to run), and to commit, push its branch and open a pull request with `gh pr create`, ending with the pull request's URL.
4. As each agent reports, note its pull request, or what went wrong. When all are done, give the user the list of pull requests, and the pieces that failed with why.''';

const _fewerPermissionPrompts = r'''# Fewer permission prompts

Find the calls the user keeps being asked to allow that only read, and allow them for this project.

1. Read the past sessions of this project: `~/.claude/projects/<the project's path with every non-alphanumeric character a dash>/*.jsonl`. Find the tool calls of Bash and of MCP tools, and the commands among them that were asked about (they have a permission result, or come after a `can_use_tool`).
2. Keep only those that change nothing: reading files, listing, searching, `git status`/`log`/`diff`/`show`, version and help commands, test runs that write nothing outside the project, MCP tools that only read. Never commands that write, delete, install, push, publish or reach the network to change something.
3. Turn them into rules, as general as is still safe: `Bash(git log:*)`, `Bash(npm run test:*)`, `mcp__server__read_thing`. Rank them by how often they came up.
4. Show the user the list, most frequent first, and add those they agree to the `permissions.allow` list of `.claude/settings.json` (keeping what is there). Say how many prompts that would have saved.

$ARGUMENTS''';

const _doctor = r'''# Check the setup

Check how the agent is set up for this user and project, from what is on this machine, and put right what is wrong (asking before each change).

- Settings files (`~/.claude/settings.json`, `.claude/settings.json`, `.claude/settings.local.json`): each must parse; look for unknown or misspelled keys and values of the wrong type.
- Agents (`~/.claude/agents/`, `.claude/agents/`), skills (`~/.claude/skills/*/SKILL.md`, `.claude/skills/*/SKILL.md`) and commands (`.claude/commands/`): each header must parse and have a description; two of one name in different places shadow each other.
- MCP servers (`.mcp.json`, and those in `~/.claude.json`): each must start; try the command of one that does not, and read its error.
- Hooks: each command must exist and run; try them with a sample event.
- Instructions (CLAUDE.md files and `.claude/rules/`): look for files that contradict each other, imports (`@path`) that point at nothing, and rules whose `paths` match no file.
- Skills, servers and plugins set up but never used in the past sessions (`~/.claude/projects/<project>/*.jsonl`): offer to switch them off.

End with a short list: what was wrong, what you fixed, and what is left for the user.

$ARGUMENTS''';

const _loop = r'''# Loop

Arguments: $ARGUMENTS

Read them as an optional interval, then the prompt to repeat:
- An interval is a number with a unit at the start: `30s`, `5m`, `2h`, `1d` (seconds are rounded up to a minute).
- The rest is the prompt: text, or a slash command such as `/babysit-prs`.

## With an interval
Schedule the prompt with CronCreate: turn the interval into a cron expression ("5m" → "*/5 * * * *", "2h" → "17 */2 * * *", "1d" → a time of day off :00 and :30), recurring, not durable unless the user asked for it to last. Then run the prompt once now. Tell the user the job's ID, how often it runs, that it stops after 7 days, and that CronDelete (or asking you) stops it sooner.

## Without an interval
Pace it yourself. Run the prompt now; at the end of each round, call ScheduleWakeup with the same prompt (`/loop <prompt>`) and a delay that fits what you are waiting for, and a short reason. When there is nothing left to watch or do, call ScheduleWakeup with `stop: true`.

## With no prompt either
Run the loop on your own judgment: each round, look at where the work of this session stands and do the next useful thing; schedule the next round with ScheduleWakeup and the prompt `<<autonomous-loop-dynamic>>`.

Each round, say in a line what you did or saw; a round with nothing new needs no more than that.''';

const _claudeApi = r'''# Building on the Claude API

## Models
The newest models, with their API IDs and prices per million tokens (input / output):
- Fable 5.1, `claude-fable-5-1`: the most capable, for the hardest and longest work. $10 / $50.
- Opus 5.5, `claude-opus-5-5`: the best fit for most complex work. $4 / $20.
- Sonnet 5.5, `claude-sonnet-5-5`: fast and capable for everyday work. $2 / $10.
- Haiku 5.5, `claude-haiku-5-5`: the fastest and cheapest. $0.10 / $0.50 ($0.50 / $2.50 for prompts over 100k tokens).
Use the newest model that fits unless the user chose another. Prices and limits change: when they matter, check them on the docs (docs.claude.com) with WebFetch rather than trusting this list.

## Calling it
- Python: `pip install anthropic`; `client = anthropic.Anthropic()` (reads `ANTHROPIC_API_KEY`); `client.messages.create(model=…, max_tokens=…, messages=[{"role": "user", "content": "…"}])`.
- TypeScript: `npm install @anthropic-ai/sdk`; `new Anthropic()`; `await client.messages.create({...})`.
- HTTP: `POST https://api.anthropic.com/v1/messages` with the headers `x-api-key`, `anthropic-version: 2023-06-01` and `content-type: application/json`.
- `system` is a top-level parameter, not a message. Messages alternate user and assistant, starting with the user.
- Always set `max_tokens`; an answer that reaches it ends with `stop_reason: "max_tokens"`.

## Streaming
Use streaming for long answers or anything a person watches (`client.messages.stream(...)`, or `"stream": true` and server-sent events: message_start, content_block_start/delta/stop, message_delta, message_stop). Long requests without streaming may time out.

## Thinking and effort
- `thinking: {"type": "adaptive"}` lets the model decide how much to think; `output_config: {"effort": "low" | "medium" | "high" | "xhigh" | "max"}` sets how hard it works. Keep thinking blocks unchanged when sending the conversation back during tool use.

## Tool use
- Describe tools in `tools` (name, description, `input_schema` as JSON Schema). The model answers with `tool_use` blocks and `stop_reason: "tool_use"`; run each and send back a user message with a `tool_result` block per call (same `tool_use_id`), then ask again, until it ends its turn.
- `tool_choice` can force a tool, or any tool. Results of calls go first in the user message that follows.
- Server tools (web search, web fetch, code execution) run on Anthropic's side: add them to `tools` by type.

## MCP and agents
- The Claude Agent SDK (`claude-agent-sdk` for Python, `@anthropic-ai/claude-agent-sdk` for TypeScript) gives a whole agent loop with tools, permissions, subagents and MCP servers; prefer it to writing a loop by hand for an agent.
- The API's MCP connector can call a remote MCP server's tools from a Messages request.

## Prompt caching
Mark the end of what stays the same across requests (tools, system prompt, the earlier conversation) with `cache_control: {"type": "ephemeral"}` (up to four marks). The cache lasts five minutes (one hour with `"ttl": "1h"`); reads cost a tenth of input, writes a quarter more. Put what changes after what does not: any change before a mark makes it miss.

## Tokens and limits
- `POST /v1/messages/count_tokens` counts a request's input before sending it.
- Rate limits are per minute, in requests and tokens; a 429 says when to retry (`retry-after`). Retry 429, 500, 529 and dropped connections with backoff.
- Batches (`/v1/messages/batches`) take many requests at half the price, answered within a day.

## Moving to a newer model
Change the model ID, then check what the code relies on: parameters removed or renamed (sampling parameters with thinking, budgets replaced by effort), how stop reasons and refusals are handled, and the length and style of answers. Run the prompts that matter against both and compare before switching.

$ARGUMENTS''';

const _run = r'''# Run the app

Start this project's app and use it, to see the change at work: $ARGUMENTS

1. Look for a project skill that already says how: `.claude/skills/run*/SKILL.md`, or a section on running in CLAUDE.md or the README. If there is one, follow it.
2. Otherwise go by the kind of project:
   - A command-line tool: build it, and run the command the change touches, with real arguments; read its output and exit code.
   - A server or API: start it in the background (Bash with run_in_background), wait until it listens, call the endpoints the change touches (curl), then stop it.
   - A terminal UI: run it under a pseudo-terminal you can drive (`script`, `expect`, or tmux with `send-keys` and `capture-pane`), and read the screen.
   - A desktop or mobile app: build and start it; take screenshots with the platform's tool (`screencapture` on macOS) and look at them; drive it through a test driver if the project has one.
   - A web page: start its dev server, open it in a browser you can drive if one is offered (a browser MCP server), or fetch the pages; take screenshots and look at them.
   - A library: write a small script outside the project that uses the changed API as a caller would, and run it.
3. Watch what really happens, and compare it with what the change should do.
4. Stop everything you started, and remove what you wrote for the check.

Say what you ran and what you saw. If it could not be run, say why.''';

const _runSkillGenerator = r'''# Write the project's run skill

Write, or improve, `.claude/skills/run/SKILL.md`: what an agent needs to build, start and drive this project's app, step by step.

1. Work it out from the project: the build files, scripts, README, CI configuration, Dockerfiles, environment examples. Find the dependencies to install, the services it needs (a database, a queue) and how to start them, the environment variables, the command to start the app, how to tell it is up, and how to reach the parts of it that matter (URLs, commands, screens).
2. Check every step by running it, from as clean a state as you can (a fresh clone in a temporary folder is best). Fix the steps that fail; note what cannot be done here and why.
3. Write the skill: a header (`name: run`, and a `description` saying when to use it), then the steps, the commands exactly as they run, how to stop it all, and the known problems. Keep it short and concrete.
4. If there are several apps (a server and a client, several services), give each a section, or a `run-<unit>` skill of its own.

Say what you wrote and what you could not check.

$ARGUMENTS''';

const _insights = r'''# How the work has been going

Write a report on how the user has been working with the agent in this project, from the past sessions in `~/.claude/projects/<the project's path with every non-alphanumeric character a dash>/*.jsonl` (each line a JSON message; `type` user or assistant; tool calls in the assistant messages' `tool_use` blocks).

Read a good sample (the most recent first), and report:
- What the sessions were about, grouped by kind of task, with how many of each.
- What went well: tasks done in few turns, ways of asking that worked.
- Where time went: tasks that took many turns, things asked again and again, corrections the user had to make, tools refused or failing often.
- Suggestions: instructions worth adding to CLAUDE.md, permissions worth allowing, skills or hooks that would save work, and ways of asking that would help.

Keep it to what the sessions show, with examples. Do not copy secrets or personal data from them into the report.

$ARGUMENTS''';
