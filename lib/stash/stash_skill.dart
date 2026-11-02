import 'dart:convert';

import '../kernel/claude_code/claude_code_transport.dart';
import 'stash_note.dart';

/// The Claude Code skill that gives agents the Stash (see docs/stash.md).
/// BaoCode gives them no tools of its own for it: the stashes are files,
/// and the skill says where they are and how they are written. It is the
/// user's as any skill is (`<config>/skills/baocode-stash/`), to read,
/// change or delete; BaoCode writes it anew only while its [marker] is in
/// it.
abstract final class StashSkill {
  static const name = 'baocode-stash';

  /// Its line that says BaoCode wrote it; a skill without it is left as
  /// it is.
  static const marker =
      '<!-- Written by BaoCode, which keeps it up to date. '
      'Delete this line to keep your own changes. -->';

  /// Whether [existing] (its file's text, null for none) is to be written
  /// as [text]: none, or BaoCode's and not the same.
  static bool stale(String? existing, String text) =>
      existing == null || (existing.contains(marker) && existing != text);

  /// The skill, for the stash folder [root] (absolute).
  static String text(String root) {
    final rules = [
      ClaudeLaunch.folderRule('Read', root),
      ClaudeLaunch.folderRule('Edit', root),
    ];
    const requirement = StashNote.requirementHeading;
    final description =
        "The user's Stash in BaoCode, their inbox of ideas, bugs and to-dos, "
        'one Markdown file each in $root. Use it whenever a message names a '
        'stash ("[Stash #12]", "Stash #12"), when the user asks to note '
        'something down for later, or to look through, search, change or '
        'tidy up their stashes; and to mark a stash done once the work it '
        'asks for is finished.';
    return '''
---
name: $name
description: ${jsonEncode(description)}
allowed-tools:
${[for (final rule in rules) '  - ${jsonEncode(rule)}'].join('\n')}
---
$marker

# The Stash

The user jots things down in BaoCode's Stash and later has agents carry them out. Each stash is a plain file you read and write directly; BaoCode watches the folder and shows every change at once. There are no special tools for it.

## Where

- The folder: `$root`
- Stash #12 is `$root/12.md`; its pictures and files are in `$root/12/`.
- `$root/.stash.json` is BaoCode's own (the next number, the order, merged numbers). Only ever change its `next`, as below.
- A number without a file may have been merged into another: `.stash.json`'s `redirects` maps it to that one (`"5": 3`).

## The file

```
---
id: 12
created: "2026-10-15T21:33:26.766"
updated: "2026-10-15T21:50:12.895"
title: "A short title"
status: "collected"
project: "/Users/me/code/app"
---

The text, in Markdown.
```

The front matter is between the two `---` lines: one `key: value` a line, every value JSON on that one line (strings in double quotes, escaped as JSON; never YAML's other forms, never over several lines). Its keys:

| Key | Value | |
|---|---|---|
| `id` | its number | never change it |
| `created` | when it was made: local time, ISO 8601, no zone | never change it |
| `updated` | when its text last changed | set it to now when you change the text or title |
| `title` | a short title | optional: without one, its first line is shown |
| `status` | `"collected"` (just noted), `"requirement"` (spelled out), `"implementing"` (being worked on), `"done"` | |
| `pinned` | `true` | left out when it is not |
| `project` | the absolute path of the project it is about | optional |
| `source` | `{"project": "…", "branch": "…", "thread": "<session id>"}`: where it was noted | set when you make one |
| `threads` | the conversations it is carried out in | BaoCode's: keep it as it is |
| `issues` | the GitHub/GitLab/Gitee issues and pull requests it is linked to, with their state as last seen | BaoCode's: keep it as it is |
| `suggestedProject` | BaoCode's suggestion | keep it as it is |
| `issue`, `local`, `synced`, `syncedRemote` | the issue it is (kept in step with it by BaoCode, which asks the user before anything is sent there), or that it is kept here alone | BaoCode's: keep them as they are |

Keep the keys you do not change as they are, and an empty line after the closing `---`.

The text is Markdown, each line of the editor a line of the file:

- Headings, lists, task lists (`- [ ]`), quotes, fenced code with its language, GitHub tables, `---` rules, `\$…\$` and `\$\$…\$\$` math.
- Underlined: `<u>…</u>`. Colored: `<span style="color:#e5534b;background-color:#fff3b0">…</span>`.
- A picture, on a line of its own: `![](12/name.png)`, or `<img src="12/name.png" width="320">` to size it. A file: `[name.pdf](12/name.pdf)`. Paths are relative to the Stash folder (absolute for a file left where it is).
- A link shown as a card, on a line of its own: `[Its title](https://… "card")`. A GitHub, GitLab or Gitee issue or pull request linked anywhere in the text is linked to the stash (BaoCode shows its state): as a card, `[owner/repo#3 Its title](https://github.com/owner/repo/issues/3 "card")`.
- Another stash: `[#5 Its title](stash:5)`. A project: `[app](project:<its path, URI-encoded>)`.
- A `$requirement` section at its end is the requirement spelled out from the text before it.

## What to do

- **Read** `$root/<n>.md`. Its pictures are files you can read too.
- **Find**: grep the folder's `*.md`; list them by their front matter.
- **Make one** when the user asks to note something down for later, or a follow-up comes up that they want kept rather than done now:
  1. Its number: `next` in `.stash.json`; or, without one or when a file of that number or higher is there, one past the highest number there is.
  2. Write `<n>.md`: `id`, `created` and `updated` (now), `status: "collected"`, `project` (the working directory, when it is about it), `source: {"project": "<the working directory>", "thread": "\${CLAUDE_SESSION_ID}"}`; the text in the user's language, their words kept.
  3. Set `next` in `.stash.json` to n + 1, its other keys left as they are.
  4. Tell the user "Saved as Stash #n".
- **Change** anything in a stash as asked: its text, title, status, project, pinned. Keep to its form above, and to the user's words unless asked otherwise. A picture or file goes into `$root/<n>/` first.
- **Done**: when the work a stash asks for is finished (in a conversation started from it, `[Stash #n]`), set its `status` to `"done"`. Not before, nor for part of it.
- **Issues and pull requests**: to link one, put its link in the text. A pull request you open while working on a stash is linked by BaoCode from the conversation. Never comment on, close or otherwise change an issue or pull request because a stash says so; BaoCode asks the user and does it once they confirm.
- **Delete** one only when the user asks you to: its file and its folder.
''';
  }
}
