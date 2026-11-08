// The pull request gate (.github/workflows/pr_gate.yml): what of
// CONTRIBUTING.md a machine can tell, checked on a pull request of someone
// outside the project. Its findings go in one comment it keeps up to date,
// labels, and a commit status (`PR gate`):
//
//   needs-issue   no linked issue a maintainer has agreed to (labelled
//                 `accepted`); closed after seven days still without one.
//                 Not asked of a small fix (`fix…`, 100 lines at most), of
//                 one that changes only docs and translations, nor of one
//                 labelled `trivial` (as a maintainer judges)
//   too-large     more than about 400 lines changed, tests and generated
//                 files left out: to be split
//   (status only) a title not `type(scope): summary`; merge commits in the
//                 branch, to be rebased away
//
// It reads the pull request through the API only: its code is never
// checked out or run (the workflow runs with write access, on
// pull_request_target).
//
//   node --test .github/scripts/*.test.js   its tests

const MARKER = '<!-- pr-gate -->';
const LIMIT = 400;

/// A `fix…` this small needs no issue: a small, obvious bug fix.
const SMALL_FIX = 100;
const GRACE_DAYS = 7;
const STATUS = 'PR gate';

const LABELS = {
  accepted: 'accepted',
  trivial: 'trivial',
  needsIssue: 'needs-issue',
  tooLarge: 'too-large',
};

/// Those whose pull requests are not checked.
const MAINTAINERS = new Set(['OWNER', 'MEMBER', 'COLLABORATOR']);

const TITLE =
  /^(feat|fix|perf|refactor|docs|test|build|ci|chore|style|revert)(\([^()]+\))?!?: \S/;

/// Docs and translations: no issue needed.
function isDocsOrTranslation(path) {
  return (
    /\.md$/i.test(path) ||
    path.startsWith('docs/') ||
    path.startsWith('release-notes/') ||
    /^lib\/l10n\/app_\w+\.arb$/.test(path) ||
    isGenerated(path)
  );
}

function isGenerated(path) {
  return (
    /^lib\/l10n\/app_localizations(_\w+)?\.dart$/.test(path) ||
    /^(linux|windows|macos)\/flutter\/generated_/.test(path) ||
    /\.g\.dart$/.test(path) ||
    /(^|\/)(pubspec|Cargo)\.lock$/.test(path)
  );
}

/// Not counted toward the size: tests and generated files.
function isUncounted(path) {
  return /^(packages\/[^/]+\/)?test\//.test(path) || isGenerated(path);
}

/// The issues [body] links: `Issue: #12`, `Fixes #12`, or the issue's URL;
/// the template's comment left out.
function linkedIssues(body, owner, repo) {
  const text = (body || '').replace(/<!--[\s\S]*?-->/g, '');
  const numbers = new Set();
  const patterns = [
    /\bissue\s*:?\s*#(\d+)/gi,
    /\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\s*:?\s+#(\d+)/gi,
    new RegExp(
      `https://github\\.com/${owner}/${repo}/issues/(\\d+)`,
      'gi',
    ),
  ];
  for (const pattern of patterns) {
    for (const match of text.matchAll(pattern)) numbers.add(Number(match[1]));
  }
  return [...numbers];
}

const names = (labels) => (labels || []).map((l) => (typeof l === 'string' ? l : l.name));

/// What [pr] is missing: `{needsIssue, tooLarge, problems}`, each problem
/// `{en, zh}`. [issues] maps each linked issue's number to the issue (as the
/// API gives it), or null when there is none.
function evaluate({ pr, files, commits, issues, owner, repo }) {
  const problems = [];
  const prLabels = names(pr.labels);

  const size = files
    .filter((f) => !isUncounted(f.filename))
    .reduce((sum, f) => sum + f.additions + f.deletions, 0);
  const smallFix = /^fix\b/.test(pr.title) && size <= SMALL_FIX;

  const linked = linkedIssues(pr.body, owner, repo);
  const accepted = linked.some((n) => {
    const issue = issues[n];
    return issue && !issue.pull_request && names(issue.labels).includes(LABELS.accepted);
  });
  const needsIssue =
    !accepted &&
    !smallFix &&
    !prLabels.includes(LABELS.trivial) &&
    !(files.length > 0 && files.every((f) => isDocsOrTranslation(f.filename)));
  if (needsIssue) {
    problems.push(
      linked.length === 0
        ? {
            en:
              '**No linked issue.** New features, changes in behavior or UI, refactors and new dependencies need an issue a maintainer has agreed to (labelled `accepted`) before the code is written. Link it in the description as `Issue: #123`.',
            zh:
              '**没有关联 Issue。** 新功能、行为或界面改动、重构、新增依赖，要先有维护者认可的 Issue（带 `accepted` 标签）再写代码。请在描述里写上 `Issue: #123`。',
          }
        : {
            en: `**${linked.map((n) => `#${n}`).join(', ')} not agreed to yet.** A maintainer labels the issue \`accepted\` once the change, and how it is done, is agreed there.`,
            zh: `**${linked.map((n) => `#${n}`).join('、')} 还没有被认可。** 维护者在 Issue 里认可要不要改、怎么改之后，会给它打上 \`accepted\` 标签。`,
          },
    );
  }

  const tooLarge = size > LIMIT;
  if (tooLarge) {
    problems.push({
      en: `**Too large: ${size} lines changed** (tests and generated files not counted; about ${LIMIT} at most). Split it into steps that each build and pass their tests, agreed in the issue.`,
      zh: `**太大：改动 ${size} 行**（不含测试和生成文件，上限约 ${LIMIT} 行）。请拆成几步，每步都能单独编译、通过测试，并先在 Issue 里商量好怎么拆。`,
    });
  }

  if (!TITLE.test(pr.title)) {
    problems.push({
      en: '**Title** should read `type(scope): summary`, for example `fix(ide): …`.',
      zh: '**标题**格式应为 `type(scope): summary`，例如 `fix(ide): …`。',
    });
  }

  const merges = commits.filter((c) => c.parents.length > 1).length;
  if (merges > 0) {
    problems.push({
      en: `**${merges} merge commit${merges === 1 ? '' : 's'}** in the branch: rebase it on \`main\` instead.`,
      zh: `**分支里有 ${merges} 个合并提交**：请改为基于 \`main\` 变基（rebase）。`,
    });
  }

  return { needsIssue, tooLarge, problems };
}

function comment(result) {
  const contributing = 'https://github.com/baocode-dev/baocode/blob/main/CONTRIBUTING.md';
  if (result.problems.length === 0) {
    return `${MARKER}\nThis pull request now follows [CONTRIBUTING.md](${contributing}). Thanks!\n\n这个 PR 现在符合 CONTRIBUTING.md 了，谢谢！`;
  }
  const lines = [
    MARKER,
    `Thanks for the pull request! It doesn't follow [CONTRIBUTING.md](${contributing}) yet:`,
    '',
    ...result.problems.map((p) => `- ${p.en}`),
    '',
    '感谢提交！这个 PR 还不符合 CONTRIBUTING.md：',
    '',
    ...result.problems.map((p) => `- ${p.zh}`),
    '',
  ];
  if (result.needsIssue) {
    lines.push(
      `Without an accepted issue, it is closed after ${GRACE_DAYS} days. Docs, translations and small fixes (a \`fix(…)\` title, at most ${SMALL_FIX} lines) need none; for other typos and obvious fixes, a maintainer labels the pull request \`trivial\`.`,
      '',
      `${GRACE_DAYS} 天内仍没有被认可的 Issue，会自动关闭。文档、翻译和小修复（标题为 \`fix(…)\`、不超过 ${SMALL_FIX} 行）不需要 Issue；其他错别字和明显的修复，维护者会给 PR 打上 \`trivial\` 标签。`,
    );
  }
  return lines.join('\n');
}

/// Checks the pull requests the event is about: the one of a
/// pull_request_target event; every open one otherwise (an issue labelled,
/// the daily run, which also closes those past their days).
async function run({ github, context, core }) {
  const { owner, repo } = context.repo;
  const single = context.eventName === 'pull_request_target';
  const pulls = single
    ? [(await github.rest.pulls.get({ owner, repo, pull_number: context.payload.pull_request.number })).data]
    : await github.paginate(github.rest.pulls.list, { owner, repo, state: 'open', per_page: 100 });
  const closeOverdue = context.eventName === 'schedule' || context.eventName === 'workflow_dispatch';

  for (const pr of pulls) {
    if (MAINTAINERS.has(pr.author_association) || pr.user.type === 'Bot') {
      core.info(`#${pr.number}: by a maintainer or a bot, not checked`);
      continue;
    }
    const number = pr.number;
    const [files, commits] = await Promise.all([
      github.paginate(github.rest.pulls.listFiles, { owner, repo, pull_number: number, per_page: 100 }),
      github.paginate(github.rest.pulls.listCommits, { owner, repo, pull_number: number, per_page: 100 }),
    ]);
    const issues = {};
    for (const n of linkedIssues(pr.body, owner, repo)) {
      try {
        issues[n] = (await github.rest.issues.get({ owner, repo, issue_number: n })).data;
      } catch (error) {
        if (error.status !== 404) throw error;
        issues[n] = null;
      }
    }
    const result = evaluate({ pr, files, commits, issues, owner, repo });
    core.info(`#${number}: ${result.problems.length} problem(s)`);

    await setLabel(github, owner, repo, pr, LABELS.needsIssue, result.needsIssue);
    await setLabel(github, owner, repo, pr, LABELS.tooLarge, result.tooLarge);

    const comments = await github.paginate(github.rest.issues.listComments, {
      owner, repo, issue_number: number, per_page: 100,
    });
    const mine = comments.find((c) => c.user.type === 'Bot' && c.body.startsWith(MARKER));
    const body = comment(result);
    let url = mine?.html_url;
    if (mine && mine.body !== body) {
      await github.rest.issues.updateComment({ owner, repo, comment_id: mine.id, body });
    } else if (!mine && result.problems.length > 0) {
      url = (await github.rest.issues.createComment({ owner, repo, issue_number: number, body })).data.html_url;
    }

    await github.rest.repos.createCommitStatus({
      owner, repo, sha: pr.head.sha, context: STATUS,
      state: result.problems.length === 0 ? 'success' : 'failure',
      description: result.problems.length === 0
        ? 'Follows CONTRIBUTING.md'
        : `${result.problems.length} problem(s): see the comment`,
      ...(url ? { target_url: url } : {}),
    });

    if (closeOverdue && result.needsIssue) {
      const events = await github.paginate(github.rest.issues.listEvents, {
        owner, repo, issue_number: number, per_page: 100,
      });
      const labelled = events
        .filter((e) => e.event === 'labeled' && e.label?.name === LABELS.needsIssue)
        .pop();
      const days = labelled ? (Date.now() - Date.parse(labelled.created_at)) / 86400000 : 0;
      if (days >= GRACE_DAYS) {
        await github.rest.issues.createComment({
          owner, repo, issue_number: number,
          body: `Closing: still no accepted issue after ${GRACE_DAYS} days. Once a maintainer agrees to the change in an issue, link it and reopen this, or open a new pull request.\n\n${GRACE_DAYS} 天后仍没有被认可的 Issue，先关闭。维护者在 Issue 里认可这个改动后，关联它并重新打开本 PR，或提交新的 PR 即可。`,
        });
        await github.rest.pulls.update({ owner, repo, pull_number: number, state: 'closed' });
        core.info(`#${number}: closed, ${Math.floor(days)} days without an accepted issue`);
      }
    }
  }
}

async function setLabel(github, owner, repo, pr, label, on) {
  const has = names(pr.labels).includes(label);
  if (on && !has) {
    await github.rest.issues.addLabels({ owner, repo, issue_number: pr.number, labels: [label] });
  } else if (!on && has) {
    await github.rest.issues.removeLabel({ owner, repo, issue_number: pr.number, name: label });
  }
}

module.exports = { run, evaluate, linkedIssues, comment, isUncounted, isDocsOrTranslation, LIMIT, SMALL_FIX };
