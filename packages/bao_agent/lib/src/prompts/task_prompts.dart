/// The prompts of the agent's own errands: summaries, titles, checks.
library;

/// Asks for the conversation so far, summed up to go on from.
String compactPrompt([String? instructions]) {
  final extra = instructions == null || instructions.trim().isEmpty
      ? ''
      : '\n\nThe user asks this of the summary:\n${instructions.trim()}';
  return '''The conversation above is about to be cleared, and the work will go on from a summary of it alone. Write that summary now: all that whoever picks the work up needs, so that nothing has to be asked again or found out twice.

First go through the conversation from start to end in <analysis> tags, as notes for yourself: what the user asked for, word by word where it matters; what was decided and why; the files read and changed; the code that matters; what went wrong and how it was put right; anything the user corrected or asked to be done otherwise.

Then the summary itself, in <summary> tags, under these headings:

- The task: what the user wants, all of it, with the limits and preferences they set.
- What is known: the technical facts, tools and ideas the work rests on.
- Files: each file that was read, changed or made, why it matters, what was changed, and the code worth keeping in full.
- Problems: what failed, how it was fixed, and what the user said of it.
- The user's words: each thing the user wrote (not tool results), as nearly as it was written.
- Still to do: what the user asked for and is not done.
- Where it stopped: exactly what was being done last, with files and code.
- Next: the one step that comes next, if it follows from what the user asked last; quote the last messages to show where things stood. Leave it out if there is none.$extra

Write only the <analysis> and the <summary>, and call no tools.''';
}

/// The message the conversation goes on from after it is compacted.
String compactedSummary(String summary, {String? transcriptPath}) {
  final cleaned = summary
      .replaceAll(RegExp(r'<analysis>[\s\S]*?</analysis>'), '')
      .replaceAllMapped(
        RegExp(r'<summary>([\s\S]*?)</summary>'),
        (m) => m[1]!.trim(),
      )
      .trim();
  return [
    'The conversation before this point grew too long and was cleared. '
        'This is the summary of it that the work goes on from.',
    '',
    cleaned,
    if (transcriptPath != null) ...[
      '',
      'The whole of it is kept at $transcriptPath: read it there for '
          'anything the summary leaves out (exact code, error output, what '
          'you wrote).',
    ],
    '',
    'Go on with the work where it stopped, without asking the user anything '
        'first. Do not mention this summary or retell it, and do not '
        'announce that you are going on: just take the next step, as though '
        'nothing had come between.',
  ].join('\n');
}

/// Asks for a title for the conversation.
const titleSystem =
    'You name conversations between a user and a coding agent. Answer with '
    'a title only: 3 to 7 words, in the language the user writes in, '
    'sentence case, no quotes, no trailing punctuation.';

String titlePrompt(String conversation) =>
    'Name this conversation:\n\n$conversation';

/// Asks for the session summed up in a line (`/recap`).
const recapSystem =
    'You sum up where a session between a user and a coding agent stands, '
    'for the user coming back to it. Answer with one sentence of at most '
    '30 words, in the language the user writes in: what was being done, '
    'and what is done or left. No preamble, no quotes.';

String recapPrompt(String conversation) =>
    'The session so far (most recent last):\n\n$conversation\n\n'
    'Where does it stand?';

/// Asks what the user is likely to say next.
const suggestionSystem =
    'You predict the next message a user will send to their coding agent. '
    'Answer with that message only, as the user would type it: at most 12 '
    'words, in the language the user writes in, no quotes. Suggest only a '
    'natural, obvious next step the agent itself proposed or that clearly '
    'follows (such as running the tests, or committing the change). If '
    'there is none, answer with nothing at all.';

String suggestionPrompt(String conversation) =>
    'The conversation so far (most recent last):\n\n$conversation\n\n'
    'What will the user most likely send next?';

/// Asks whether a goal is met.
const goalCheckSystem =
    'You check whether a coding agent has met the goal its user set, from '
    'the conversation. Answer with a JSON object only: {"ok": true, '
    '"reason": "the evidence"} when the goal is met, or {"ok": false, '
    '"reason": "what is still missing"} when it is not. Be strict: the goal '
    'is met only when the conversation shows it plainly.';

String goalCheckPrompt(String condition, String conversation) =>
    'The goal:\n$condition\n\nThe conversation (most recent last):\n\n'
    '$conversation\n\nIs the goal met?';

/// Has auto mode's classifier judge an action.
const classifierSystem =
    'You review actions a coding agent wants to take on its user\'s machine, '
    'in auto mode: the user lets it act without asking, unless an action is '
    'risky. Allow what is plainly part of the task the user asked for and '
    'can be undone, or does not reach beyond the project (reading, building, '
    'testing, editing project files, local git commits). Block what could '
    'cause harm the user did not ask for: deleting or overwriting data '
    'outside the project, force-pushing, pushing to shared branches, '
    'publishing or deploying, sending data to unknown destinations, '
    'changing system or credential settings, installing software globally, '
    'running code downloaded from the internet, or anything the user said '
    'not to do. Answer with a JSON object only: {"decision": "allow"} or '
    '{"decision": "block", "reason": "why, briefly"}.';

String classifierPrompt(String transcript, String action) =>
    'What the user asked, and what the agent did so far (most recent '
    'last):\n\n$transcript\n\nThe action the agent wants to take now:\n\n'
    '$action\n\nAllow or block?';

/// The command that has the agent write the project's CLAUDE.md.
const initPrompt = '''Write a CLAUDE.md for this repository: the file coding agents read before they work here, so that they can get going without finding everything out again.

Look through the codebase first, then put in it:
1. The commands needed day to day: build, lint, test, and how to run a single test.
2. How the code is laid out at a high level: the architecture you only see by reading several files, not what one listing shows.

- If there is a CLAUDE.md already, propose what to change in it instead.
- Bring in what matters from a README.md, and from editor rules for agents if there are any (.cursor/rules/, .cursorrules, .github/copilot-instructions.md).
- Leave out what any project would say ("write tests", "handle errors"), lists of every file or component that a glance finds, and anything said twice.
- Do not invent sections such as tips or support that nothing in the repository backs.
- Start the file with:

```
# CLAUDE.md

Notes for coding agents working in this repository.
```''';

/// The command that has the agent review the branch for security issues.
const securityReviewPrompt = '''Look for security holes in what this branch changes: its diff against the main branch, and what is not committed yet.

Report only holes these changes open that someone could really exploit, such as injection (SQL, shell, path, template), broken authentication or authorization, unsafe deserialization, secrets in the code, cryptography used wrongly, data exposed, XSS or SSRF. Leave out style, denial of service, and what is only possible in theory.

For each one: the file and line, what kind of hole it is, how serious (high, medium, low), how it could be exploited, and how to fix it. If there are none, say so.''';
