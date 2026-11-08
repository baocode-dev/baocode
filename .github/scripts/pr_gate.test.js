// node --test .github/scripts/*.test.js

const test = require('node:test');
const assert = require('node:assert/strict');
const gate = require('./pr_gate.js');

const repo = { owner: 'baocode-dev', repo: 'baocode' };
const file = (filename, additions = 10, deletions = 0) => ({ filename, additions, deletions });
const commit = (parents = 1) => ({ parents: Array.from({ length: parents }, () => ({})) });
const accepted = { labels: [{ name: 'accepted' }] };

function pr(overrides = {}) {
  return {
    number: 1,
    title: 'feat(ide): something',
    body: 'Issue: #10',
    labels: [],
    author_association: 'CONTRIBUTOR',
    user: { type: 'User' },
    head: { sha: 'abc' },
    ...overrides,
  };
}

function check({ pr: p = pr(), files = [file('lib/a.dart')], commits = [commit()], issues = { 10: accepted } } = {}) {
  return gate.evaluate({ pr: p, files, commits, issues, ...repo });
}

test('the issues a description links, the template comment left out', () => {
  const body = [
    '<!-- Issue: #1 in the template comment -->',
    'Issue: #12',
    'Fixes #13, closes: #14',
    'See https://github.com/baocode-dev/baocode/issues/15 and #16',
  ].join('\n');
  assert.deepEqual(gate.linkedIssues(body, 'baocode-dev', 'baocode').sort(), [12, 13, 14, 15]);
  assert.deepEqual(gate.linkedIssues('Issue: #', 'baocode-dev', 'baocode'), []);
  assert.deepEqual(gate.linkedIssues(null, 'baocode-dev', 'baocode'), []);
});

test('an accepted issue, a small change, a good title: nothing missing', () => {
  assert.deepEqual(check(), { needsIssue: false, tooLarge: false, problems: [] });
});

test('no issue, or one not accepted, or a pull request linked instead', () => {
  assert.equal(check({ pr: pr({ body: 'What and why' }) }).needsIssue, true);
  assert.match(check({ pr: pr({ body: '' }) }).problems[0].en, /No linked issue/);
  const notAccepted = check({ issues: { 10: { labels: [{ name: 'enhancement' }] } } });
  assert.equal(notAccepted.needsIssue, true);
  assert.match(notAccepted.problems[0].en, /#10 not agreed to yet/);
  assert.equal(check({ issues: { 10: { ...accepted, pull_request: {} } } }).needsIssue, true);
  assert.equal(check({ issues: { 10: null } }).needsIssue, true);
});

test('trivial, or only docs and translations: no issue needed', () => {
  assert.equal(check({ pr: pr({ body: '', labels: [{ name: 'trivial' }] }) }).needsIssue, false);
  const docs = [file('docs/ssh-remote.md'), file('README.md'), file('lib/l10n/app_zh.arb'), file('lib/l10n/app_localizations_zh.dart')];
  assert.equal(check({ pr: pr({ body: '' }), files: docs }).needsIssue, false);
  assert.equal(check({ pr: pr({ body: '' }), files: [...docs, file('lib/a.dart')] }).needsIssue, true);
});

test('a small fix needs no issue; a larger one, or a feature, does', () => {
  const noIssue = { body: '' };
  assert.equal(check({ pr: pr({ ...noIssue, title: 'fix(chat): x' }), files: [file('lib/a.dart', 60, 40), file('test/a_test.dart', 300)] }).needsIssue, false);
  assert.equal(check({ pr: pr({ ...noIssue, title: 'fix(chat): x' }), files: [file('lib/a.dart', 60, 41)] }).needsIssue, true);
  assert.equal(check({ pr: pr({ ...noIssue, title: 'feat(chat): x' }), files: [file('lib/a.dart', 5)] }).needsIssue, true);
  assert.equal(check({ pr: pr({ ...noIssue, title: 'fixup: x' }), files: [file('lib/a.dart', 5)] }).needsIssue, true);
});

test('size: tests and generated files left out', () => {
  const big = [file('lib/a.dart', 300, 50), file('test/a_test.dart', 900), file('packages/bao_remote/test/b_test.dart', 500),
    file('lib/l10n/app_localizations_en.dart', 200), file('pubspec.lock', 80)];
  assert.equal(check({ files: big }).tooLarge, false);
  const result = check({ files: [...big, file('lib/b.dart', 51)] });
  assert.equal(result.tooLarge, true);
  assert.match(result.problems[0].en, /401 lines changed/);
});

test('titles', () => {
  for (const title of ['fix(ide): x', 'feat: x', 'perf(chat)!: x', 'docs(site): x']) {
    assert.equal(check({ pr: pr({ title }) }).problems.length, 0, title);
  }
  for (const title of ['Feat/explorer problems', 'fix(ide):x', 'Fix(ide): x', 'update stuff']) {
    assert.equal(check({ pr: pr({ title }) }).problems.length, 1, title);
  }
});

test('merge commits', () => {
  const result = check({ commits: [commit(), commit(2), commit(2)] });
  assert.match(result.problems[0].en, /2 merge commits/);
});

test('the comment: problems in both languages, the days when an issue is missing', () => {
  const text = gate.comment(check({ pr: pr({ body: '', title: 'x' }) }));
  assert.ok(text.startsWith('<!-- pr-gate -->'));
  assert.match(text, /No linked issue/);
  assert.match(text, /没有关联 Issue/);
  assert.match(text, /closed after 7 days/);
  assert.doesNotMatch(gate.comment(check({ pr: pr({ title: 'x' }) })), /closed after/);
  assert.match(gate.comment(check()), /now follows/);
});

/// A GitHub of [pulls] (each with its files, commits, comments, events) and
/// [issues], recording what is done to it.
function fakeGitHub({ pulls, issues = {} }) {
  const done = [];
  const byNumber = Object.fromEntries(pulls.map((p) => [p.pr.number, p]));
  const rest = {
    pulls: {
      get: async ({ pull_number }) => ({ data: byNumber[pull_number].pr }),
      list: async () => ({ data: pulls.map((p) => p.pr) }),
      listFiles: async ({ pull_number }) => ({ data: byNumber[pull_number].files }),
      listCommits: async ({ pull_number }) => ({ data: byNumber[pull_number].commits }),
      update: async (args) => { done.push(['update', args.pull_number, args.state]); },
    },
    issues: {
      get: async ({ issue_number }) => {
        if (!(issue_number in issues)) throw Object.assign(new Error('Not Found'), { status: 404 });
        return { data: issues[issue_number] };
      },
      listComments: async ({ issue_number }) => ({ data: byNumber[issue_number].comments || [] }),
      listEvents: async ({ issue_number }) => ({ data: byNumber[issue_number].events || [] }),
      addLabels: async (args) => { done.push(['label', args.issue_number, ...args.labels]); },
      removeLabel: async (args) => { done.push(['unlabel', args.issue_number, args.name]); },
      createComment: async (args) => { done.push(['comment', args.issue_number, args.body]); return { data: { html_url: 'url' } }; },
      updateComment: async (args) => { done.push(['edit', args.comment_id, args.body]); },
    },
    repos: {
      createCommitStatus: async (args) => { done.push(['status', args.sha, args.state]); },
    },
  };
  return {
    done,
    github: { rest, paginate: async (fn, args) => (await fn(args)).data },
  };
}

const core = { info() {} };
const context = (eventName, number) => ({
  eventName,
  repo,
  payload: number ? { pull_request: { number } } : {},
});

test('a pull request without an issue: labelled, told once, its status failed', async () => {
  const { github, done } = fakeGitHub({
    pulls: [{ pr: pr({ number: 7, body: '' }), files: [file('lib/a.dart')], commits: [commit()] }],
  });
  await gate.run({ github, context: context('pull_request_target', 7), core });
  assert.deepEqual(done.map((d) => d.slice(0, 3)), [
    ['label', 7, 'needs-issue'],
    ['comment', 7, done[1][2]],
    ['status', 'abc', 'failure'],
  ]);
  assert.match(done[1][2], /No linked issue/);
});

test('fixed since: the label off, the comment says so, the status passes', async () => {
  const { github, done } = fakeGitHub({
    pulls: [{
      pr: pr({ number: 7, labels: [{ name: 'needs-issue' }] }),
      files: [file('lib/a.dart')],
      commits: [commit()],
      comments: [{ id: 99, user: { type: 'Bot' }, body: '<!-- pr-gate -->\nold', html_url: 'u' }],
    }],
    issues: { 10: accepted },
  });
  await gate.run({ github, context: context('pull_request_target', 7), core });
  assert.deepEqual(done.map((d) => d.slice(0, 2)), [['unlabel', 7], ['edit', 99], ['status', 'abc']]);
  assert.match(done[1][2], /now follows/);
  assert.equal(done[2][2], 'success');
});

test("maintainers' and bots' pull requests are not checked", async () => {
  const { github, done } = fakeGitHub({
    pulls: [
      { pr: pr({ number: 1, body: '', author_association: 'OWNER' }) },
      { pr: pr({ number: 2, body: '', user: { type: 'Bot' } }) },
    ],
  });
  await gate.run({ github, context: context('schedule'), core });
  assert.deepEqual(done, []);
});

test('the daily run closes one labelled needs-issue seven days ago, not one labelled six', async () => {
  const daysAgo = (days) => new Date(Date.now() - days * 86400000).toISOString();
  const labelled = (days) => [{ event: 'labeled', label: { name: 'needs-issue' }, created_at: daysAgo(days) }];
  const comments = [{ id: 1, user: { type: 'Bot' }, body: gate.comment(check({ pr: pr({ body: '' }) })), html_url: 'u' }];
  const { github, done } = fakeGitHub({
    pulls: [
      { pr: pr({ number: 8, body: '', labels: [{ name: 'needs-issue' }] }), files: [file('lib/a.dart')], commits: [commit()], comments, events: labelled(7.1) },
      { pr: pr({ number: 9, body: '', labels: [{ name: 'needs-issue' }] }), files: [file('lib/a.dart')], commits: [commit()], comments, events: labelled(6) },
    ],
  });
  await gate.run({ github, context: context('schedule'), core });
  assert.deepEqual(done.filter((d) => d[0] === 'update'), [['update', 8, 'closed']]);
  assert.match(done.find((d) => d[0] === 'comment' && d[1] === 8)[2], /^Closing: still no accepted issue/);
  assert.equal(done.filter((d) => d[1] === 9 && d[0] !== 'status').length, 0);
});

test('a pull_request_target run closes nothing', async () => {
  const { github, done } = fakeGitHub({
    pulls: [{
      pr: pr({ number: 8, body: '', labels: [{ name: 'needs-issue' }] }), files: [file('lib/a.dart')], commits: [commit()],
      events: [{ event: 'labeled', label: { name: 'needs-issue' }, created_at: '2020-01-01T00:00:00Z' }],
    }],
  });
  await gate.run({ github, context: context('pull_request_target', 8), core });
  assert.equal(done.some((d) => d[0] === 'update'), false);
});
