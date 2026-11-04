import 'dart:async';
import 'dart:convert';

import 'package:baocode/forge/forge_accounts.dart';
import 'package:baocode/forge/forge_api.dart';
import 'package:baocode/forge/forge_ref.dart';
import 'package:baocode/models/secret_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers requests by method and URL (its path and query), and keeps
/// them.
class FakeForgeHttp implements ForgeHttp {
  final Map<String, Object? Function(FakeRequest request)> routes = {};
  final List<FakeRequest> requests = [];

  void on(String method, String url, Object? Function(FakeRequest) answer) =>
      routes['$method $url'] = answer;

  /// What answers a request no route is for (else 404).
  Object? Function(FakeRequest request)? fallback;

  @override
  Future<ForgeResponse> send(
    String method,
    Uri url, {
    Map<String, String> headers = const {},
    Object? json,
    Map<String, String>? form,
    List<int>? bytes,
  }) async {
    final request = FakeRequest(method, url, headers, json, form, bytes);
    requests.add(request);
    final key = '$method ${url.toString()}';
    final route =
        routes[key] ??
        routes['$method ${url.replace(query: '').toString().replaceAll('?', '')}'];
    final answer = route ?? fallback;
    if (answer == null) {
      return const ForgeResponse(404, '{"message":"Not Found"}');
    }
    return switch (answer(request)) {
      final ForgeResponse response => response,
      final answer => ForgeResponse(200, jsonEncode(answer)),
    };
  }
}

/// A [FakeForgeHttp] that takes certificates, as the app's client does.
class TrustingFakeForgeHttp extends FakeForgeHttp
    implements ForgeCertificateTrust {
  final Map<String, String> trusted = {};

  @override
  void trustCertificate(String host, String sha256) => trusted[host] = sha256;
}

/// A [SecretStore] that counts the reads: on Windows each read of the real
/// one runs a program (PowerShell, DPAPI), so how many a burst of requests
/// starts is what the hang was made of.
class CountingSecretStore implements SecretStore {
  CountingSecretStore({this.value, this.failing = false, this.gate});

  String? value;
  bool failing;

  /// Held open, when given, to have the reads that arrive overlap.
  Completer<void>? gate;

  int reads = 0;

  @override
  Future<String?> read(String id) async {
    reads++;
    final gate = this.gate;
    if (gate != null) await gate.future;
    if (failing) throw const SecretStoreException('no keychain here');
    return value;
  }

  @override
  Future<void> write(String id, String value) async => this.value = value;

  @override
  Future<void> delete(String id) async => value = null;
}

class FakeRequest {
  FakeRequest(
    this.method,
    this.url,
    this.headers,
    this.json,
    this.form, [
    this.bytes,
  ]);

  final String method;
  final Uri url;
  final Map<String, String> headers;
  final Object? json;
  final Map<String, String>? form;
  final List<int>? bytes;
}

void main() {
  group('ForgeRef', () {
    test('GitHub and GitLab issues and pull requests, from their pages', () {
      final issue = ForgeRef.parse(
        'https://github.com/baocode-dev/baocode/issues/92#issuecomment-1',
      )!;
      expect(issue.repo.kind, ForgeKind.github);
      expect(issue.repo.path, 'baocode-dev/baocode');
      expect(issue.kind, ForgeItemKind.issue);
      expect(issue.number, 92);
      expect(issue.fullTag, 'baocode-dev/baocode#92');

      final pull = ForgeRef.parse('https://github.com/o/r/pull/7/files')!;
      expect(pull.kind, ForgeItemKind.pull);
      expect(pull.url.toString(), 'https://github.com/o/r/pull/7');

      final mr = ForgeRef.parse(
        'https://git.example.com/group/sub/app/-/merge_requests/12/diffs',
      )!;
      expect(mr.repo.kind, ForgeKind.gitlab);
      expect(mr.repo.host, 'git.example.com');
      expect(mr.repo.path, 'group/sub/app');
      expect(mr.tag, '!12');
      expect(
        mr.url.toString(),
        'https://git.example.com/group/sub/app/-/merge_requests/12',
      );

      // A GitHub Enterprise's, once its account says what it is.
      expect(ForgeRef.parse('https://ghe.corp/o/r/issues/3'), isNull);
      expect(
        ForgeRef.parse(
          'https://ghe.corp/o/r/issues/3',
          kindOf: (host) => host == 'ghe.corp' ? ForgeKind.github : null,
        )?.repo.kind,
        ForgeKind.github,
      );
      expect(ForgeRef.parse('https://github.com/o/r/blob/main/a.dart'), isNull);
      expect(ForgeRef.parse('not a link'), isNull);
    });

    test('every one a text links to, once each', () {
      final refs = ForgeRef.allIn(
        'Opened https://github.com/o/r/pull/7. See '
        '(https://github.com/o/r/issues/3) and https://github.com/o/r/pull/7',
      );
      expect(refs.map((ref) => ref.fullTag), ['o/r#7', 'o/r#3']);
    });

    test('a repository from its Git remote', () {
      expect(
        ForgeRepo.fromRemote('git@github.com:baocode-dev/baocode.git'),
        const ForgeRepo(
          kind: ForgeKind.github,
          host: 'github.com',
          path: 'baocode-dev/baocode',
        ),
      );
      expect(
        ForgeRepo.fromRemote('https://gitlab.com/g/sub/app.git')?.path,
        'g/sub/app',
      );
      expect(
        ForgeRepo.fromRemote(
          'ssh://git@git.corp:2222/team/app.git',
          kindOf: (host) => ForgeKind.gitlab,
        )?.host,
        'git.corp',
      );
      expect(ForgeRepo.fromRemote('git@unknown.host:o/r.git'), isNull);
    });

    test('a self-hosted forge over http, with its port', () {
      final repo = ForgeRepo.fromRemote(
        'http://gitlab.corp:8080/team/app.git',
        kindOf: (host) => host == 'gitlab.corp:8080' ? ForgeKind.gitlab : null,
      )!;
      expect(repo.host, 'gitlab.corp:8080');
      expect(repo.scheme, 'http');
      expect(repo.url.toString(), 'http://gitlab.corp:8080/team/app');

      final ref = ForgeRef.parse(
        'http://gitlab.corp:8080/team/app/-/issues/5',
      )!;
      expect(ref.repo.host, 'gitlab.corp:8080');
      expect(ref.repo.scheme, 'http');
      expect(ref.url.toString(), 'http://gitlab.corp:8080/team/app/-/issues/5');
    });

    test('Gitee issues (their numbers letters) and pull requests', () {
      final issue = ForgeRef.parse(
        'https://gitee.com/baocode/app/issues/I8ABCD?from=project-issue',
      )!;
      expect(issue.repo.kind, ForgeKind.gitee);
      expect(issue.repo.path, 'baocode/app');
      expect(issue.kind, ForgeItemKind.issue);
      expect(issue.code, 'I8ABCD');
      expect(issue.fullTag, 'baocode/app#I8ABCD');
      expect(
        issue.url.toString(),
        'https://gitee.com/baocode/app/issues/I8ABCD',
      );
      // Its case matters.
      expect(
        issue,
        isNot(ForgeRef.parse('https://gitee.com/baocode/app/issues/i8abcd')),
      );

      final pull = ForgeRef.parse('https://gitee.com/o/r/pulls/12/files')!;
      expect(pull.kind, ForgeItemKind.pull);
      expect(pull.number, 12);
      expect(pull.tag, '#12');
      expect(pull.url.toString(), 'https://gitee.com/o/r/pulls/12');

      expect(ForgeRef.parse('https://gitee.com/o/r/tree/master'), isNull);
      expect(
        ForgeRepo.fromRemote('git@gitee.com:baocode/app.git'),
        const ForgeRepo(
          kind: ForgeKind.gitee,
          host: 'gitee.com',
          path: 'baocode/app',
        ),
      );
      expect(ForgeRepo.fromRemote('https://gitee.com/a/b/c.git'), isNull);
    });
  });

  group('GitHubApi', () {
    late FakeForgeHttp http;
    late GitHubApi api;
    final repo = const ForgeRepo(
      kind: ForgeKind.github,
      host: 'github.com',
      path: 'o/r',
    );

    setUp(() {
      http = FakeForgeHttp();
      api = GitHubApi(host: 'github.com', http: http, token: () async => 't');
    });

    test('an issue, its labels and assignees', () async {
      http.on(
        'GET',
        'https://api.github.com/repos/o/r/issues/3',
        (_) => {
          'number': 3,
          'title': 'Uploads fail',
          'state': 'open',
          'body': 'On 503',
          'user': {'login': 'ann'},
          'labels': [
            {'name': 'bug', 'color': 'd73a4a'},
          ],
          'assignees': [
            {'login': 'leo'},
          ],
          'comments': 2,
          'updated_at': '2026-10-15T10:00:00Z',
        },
      );
      final item = await api.item(
        ForgeRef(repo: repo, kind: ForgeItemKind.issue, number: 3),
      );
      expect(item.title, 'Uploads fail');
      expect(item.state, ForgeState.open);
      expect(item.labels, [const ForgeLabel('bug', color: '#d73a4a')]);
      expect(item.assignees, ['leo']);
      expect(item.comments, 2);
      expect(http.requests.single.headers['Authorization'], 'Bearer t');
    });

    test('a pull request: merged, draft, its checks together', () async {
      http
        ..on(
          'GET',
          'https://api.github.com/repos/o/r/pulls/7',
          (_) => {
            'number': 7,
            'title': 'Retry uploads',
            'state': 'open',
            'draft': false,
            'merged_at': null,
            'head': {'sha': 'abc', 'ref': 'retry-uploads'},
          },
        )
        ..on(
          'GET',
          'https://api.github.com/repos/o/r/commits/abc/check-runs?per_page=100',
          (_) => {
            'check_runs': [
              {'status': 'completed', 'conclusion': 'success'},
              {'status': 'completed', 'conclusion': 'failure'},
            ],
          },
        );
      final item = await api.item(
        ForgeRef(repo: repo, kind: ForgeItemKind.pull, number: 7),
      );
      expect(item.state, ForgeState.open);
      expect(item.checks, ForgeChecks.failure);
      expect(item.branch, 'retry-uploads');
    });

    test('a pull request linked as an issue is read as one', () async {
      http
        ..on(
          'GET',
          'https://api.github.com/repos/o/r/issues/7',
          (_) => {'number': 7, 'title': 'x', 'pull_request': {}},
        )
        ..on(
          'GET',
          'https://api.github.com/repos/o/r/pulls/7',
          (_) => {
            'number': 7,
            'title': 'Retry uploads',
            'state': 'closed',
            'merged_at': '2026-10-15T10:00:00Z',
          },
        );
      final item = await api.item(
        ForgeRef(repo: repo, kind: ForgeItemKind.issue, number: 7),
      );
      expect(item.ref.kind, ForgeItemKind.pull);
      expect(item.state, ForgeState.merged);
    });

    test('my open issues, searched; comments and closes', () async {
      http
        ..on(
          'GET',
          'https://api.github.com/search/issues',
          (_) => {
            'items': [
              {'number': 3, 'title': 'Uploads fail', 'state': 'open'},
            ],
          },
        )
        ..on(
          'POST',
          'https://api.github.com/repos/o/r/issues/3/comments',
          (_) => {},
        )
        ..on('PATCH', 'https://api.github.com/repos/o/r/issues/3', (_) => {});
      final issues = await api.issues(repo, query: 'upload');
      expect(issues.single.ref.number, 3);
      expect(
        http.requests.last.url.queryParameters['q'],
        'repo:o/r is:issue is:open assignee:@me upload',
      );
      final ref = issues.single.ref;
      await api.comment(ref, 'Fixed in #7');
      expect(http.requests.last.json, {'body': 'Fixed in #7'});
      await api.close(ref);
      expect(http.requests.last.json, {'state': 'closed'});
    });

    test('what it says when it refuses', () async {
      http.on(
        'GET',
        'https://api.github.com/user',
        (_) => const ForgeResponse(401, '{"message":"Bad credentials"}'),
      );
      await expectLater(
        api.me(),
        throwsA(
          isA<ForgeException>()
              .having((e) => e.message, 'message', 'Bad credentials')
              .having((e) => e.unauthorized, 'unauthorized', isTrue),
        ),
      );
    });

    test("a GitHub Enterprise's API is under /api/v3", () async {
      final enterprise = GitHubApi(
        host: 'ghe.corp',
        http: http,
        token: () async => 't',
      );
      http.on('GET', 'https://ghe.corp/api/v3/user', (_) => {'login': 'leo'});
      expect((await enterprise.me()).login, 'leo');
    });
  });

  group('GitLabApi', () {
    late FakeForgeHttp http;
    late GitLabApi api;
    final repo = const ForgeRepo(
      kind: ForgeKind.gitlab,
      host: 'gitlab.com',
      path: 'g/sub/app',
    );

    setUp(() {
      http = FakeForgeHttp();
      api = GitLabApi(host: 'gitlab.com', http: http, token: () async => 't');
    });

    test('a self-hosted GitLab over http, with its port', () async {
      final api = GitLabApi(
        host: 'gitlab.corp:8080',
        scheme: 'http',
        http: http,
        token: () async => 't',
      );
      http.on(
        'GET',
        'http://gitlab.corp:8080/api/v4/user',
        (_) => {'username': 'leo'},
      );
      expect((await api.me()).login, 'leo');
    });

    test('a merge request: its pipeline, by the project\'s path', () async {
      http.on(
        'GET',
        'https://gitlab.com/api/v4/projects/g%2Fsub%2Fapp/merge_requests/12',
        (_) => {
          'iid': 12,
          'title': 'Retry uploads',
          'state': 'opened',
          'draft': true,
          'labels': ['backend'],
          'head_pipeline': {'status': 'running'},
          'source_branch': 'retry',
        },
      );
      final item = await api.item(
        ForgeRef(repo: repo, kind: ForgeItemKind.pull, number: 12),
      );
      expect(item.state, ForgeState.draft);
      expect(item.checks, ForgeChecks.pending);
      expect(item.labels.single.name, 'backend');
      expect(item.ref.tag, '!12');
    });

    test('issues assigned to me; a note; closed', () async {
      http
        ..on(
          'GET',
          'https://gitlab.com/api/v4/projects/g%2Fsub%2Fapp/issues',
          (_) => [
            {
              'iid': 4,
              'title': 'Crash',
              'state': 'opened',
              'labels': [
                {'name': 'bug', 'color': '#ff0000'},
              ],
            },
          ],
        )
        ..on(
          'POST',
          'https://gitlab.com/api/v4/projects/g%2Fsub%2Fapp/issues/4/notes',
          (_) => {},
        )
        ..on(
          'PUT',
          'https://gitlab.com/api/v4/projects/g%2Fsub%2Fapp/issues/4',
          (_) => {},
        );
      final issues = await api.issues(repo);
      expect(issues.single.labels.single.color, '#ff0000');
      expect(http.requests.last.url.queryParameters['scope'], 'assigned_to_me');
      await api.comment(issues.single.ref, 'Done');
      expect(http.requests.last.json, {'body': 'Done'});
      await api.close(issues.single.ref);
      expect(http.requests.last.json, {'state_event': 'close'});
    });
  });

  group('GiteeApi', () {
    late FakeForgeHttp http;
    late GiteeApi api;
    const repo = ForgeRepo(
      kind: ForgeKind.gitee,
      host: 'gitee.com',
      path: 'o/r',
    );
    const base = 'https://gitee.com/api/v5';

    setUp(() {
      http = FakeForgeHttp();
      api = GiteeApi(host: 'gitee.com', http: http, token: () async => 't');
    });

    test('an issue by its letters, the token in the query', () async {
      http.on(
        'GET',
        '$base/repos/o/r/issues/I8ABCD',
        (_) => {
          'number': 'I8ABCD',
          'title': 'Uploads fail',
          'state': 'progressing',
          'body': 'On 503',
          'user': {'login': 'ann'},
          'labels': [
            {'name': 'bug', 'color': 'd73a4a'},
          ],
          'assignee': {'login': 'leo'},
          'comments': 2,
          'updated_at': '2026-10-15T10:00:00+08:00',
        },
      );
      final item = await api.item(
        const ForgeRef(repo: repo, kind: ForgeItemKind.issue, code: 'I8ABCD'),
      );
      expect(item.ref.code, 'I8ABCD');
      expect(item.title, 'Uploads fail');
      expect(item.state, ForgeState.open);
      expect(item.labels, [const ForgeLabel('bug', color: '#d73a4a')]);
      expect(item.assignees, ['leo']);
      expect(item.comments, 2);
      final request = http.requests.single;
      expect(request.url.queryParameters['access_token'], 't');
      expect(request.headers.containsKey('Authorization'), isFalse);
    });

    test('a pull request: merged, its checks', () async {
      http
        ..on(
          'GET',
          '$base/repos/o/r/pulls/7',
          (_) => {
            'number': 7,
            'title': 'Retry uploads',
            'state': 'merged',
            'head': {'sha': 'abc', 'ref': 'retry-uploads'},
          },
        )
        ..on(
          'GET',
          '$base/repos/o/r/commits/abc/check-runs',
          (_) => [
            {'status': 'completed', 'conclusion': 'success'},
          ],
        );
      final item = await api.item(
        const ForgeRef(repo: repo, kind: ForgeItemKind.pull, number: 7),
      );
      expect(item.state, ForgeState.merged);
      expect(item.checks, ForgeChecks.success);
      expect(item.branch, 'retry-uploads');
    });

    test(
      'my open issues; comments, closes, opens and edits as forms',
      () async {
        http
          ..on('GET', '$base/user', (_) => {'login': 'leo', 'name': 'Leo'})
          ..on(
            'GET',
            '$base/repos/o/r/issues',
            (_) => [
              {'number': 'I1', 'title': 'Uploads fail', 'state': 'open'},
            ],
          )
          ..on('POST', '$base/repos/o/r/issues/I1/comments', (_) => {})
          ..on('PATCH', '$base/repos/o/issues/I1', (request) {
            return {'number': 'I1', 'title': request.form?['title'] ?? 'x'};
          })
          ..on(
            'POST',
            '$base/repos/o/issues',
            (_) => {'number': 'I2', 'title': 'New', 'state': 'open'},
          );
        final issues = await api.issues(repo, query: 'upload');
        final query = http.requests.last.url.queryParameters;
        expect(query['assignee'], 'leo');
        expect(query['q'], 'upload');
        expect(query['state'], 'open');
        final ref = issues.single.ref;
        expect(ref.url.toString(), 'https://gitee.com/o/r/issues/I1');

        await api.comment(ref, 'Fixed in #7');
        expect(http.requests.last.form, {'body': 'Fixed in #7'});
        await api.close(ref);
        expect(http.requests.last.form, {'repo': 'r', 'state': 'closed'});
        final created = await api.createIssue(repo, title: 'New', body: 'b');
        expect(created.ref.code, 'I2');
        expect(http.requests.last.form, {
          'repo': 'r',
          'title': 'New',
          'body': 'b',
        });
        final edited = await api.editIssue(ref, title: 'Renamed', body: 'b');
        expect(edited.title, 'Renamed');
      },
    );

    test('an issue\'s last comments, the oldest first', () async {
      http.on(
        'GET',
        '$base/repos/o/r/issues/I1/comments',
        (_) => [
          {
            'user': {'login': 'b'},
            'body': 'second',
          },
          {
            'user': {'login': 'a'},
            'body': 'first',
          },
        ],
      );
      final comments = await api.comments(
        const ForgeRef(repo: repo, kind: ForgeItemKind.issue, code: 'I1'),
        most: 2,
      );
      expect(comments.map((comment) => comment.body), ['first', 'second']);
      expect(http.requests.single.url.queryParameters['order'], 'desc');
    });

    test('a picture put on a branch of its own, made the first time', () async {
      http
        ..on('GET', '$base/repos/o/r', (_) => {'default_branch': 'main'})
        ..on('POST', '$base/repos/o/r/branches', (_) => {})
        ..fallback = (request) =>
            request.method == 'POST' && request.url.path.contains('/contents/')
            ? {}
            : const ForgeResponse(404, '{"message":"Not Found"}');
      final url = await api.uploadImage(repo, 'shot.png', [1, 2, 3]);
      expect(
        http.requests
            .firstWhere((request) => request.url.path.endsWith('/branches'))
            .form,
        {'refs': 'main', 'branch_name': GitHubApi.assetsBranch},
      );
      expect(
        url,
        startsWith(
          'https://gitee.com/o/r/raw/${GitHubApi.assetsBranch}/stash/',
        ),
      );
      expect(url, endsWith('.png'));
    });
  });

  group('ForgeAccounts', () {
    test('signed in to Gitee with a token, sent in the query', () async {
      final http = FakeForgeHttp()
        ..on('GET', 'https://gitee.com/api/v5/user', (request) {
          expect(request.url.queryParameters['access_token'], 'abc');
          return {'login': 'leo', 'name': 'Leo'};
        });
      final accounts = ForgeAccounts(http: http, secrets: MemorySecretStore());
      final account = await accounts.signInWithToken(
        ForgeKind.gitee,
        'gitee.com',
        'abc',
      );
      expect(account.login, 'leo');
      expect(accounts.kindOf('gitee.com'), ForgeKind.gitee);
      expect(accounts.apiFor('gitee.com'), isA<GiteeApi>());
    });

    test('signed in with a token: who it is of, kept in the keychain, the '
        'account in storage; signed out, both gone', () async {
      final http = FakeForgeHttp()
        ..on('GET', 'https://gitlab.corp/api/v4/user', (request) {
          expect(request.headers['Authorization'], 'Bearer glpat-x');
          return {'username': 'leo', 'name': 'Leo'};
        });
      final secrets = MemorySecretStore();
      Object? kept;
      final accounts = ForgeAccounts(
        http: http,
        secrets: secrets,
        write: (json) async => kept = json,
      );
      final account = await accounts.signInWithToken(
        ForgeKind.gitlab,
        'https://gitlab.corp/',
        ' glpat-x ',
      );
      expect(account.host, 'gitlab.corp');
      expect(account.login, 'leo');
      expect(await secrets.read('forge.gitlab.corp'), contains('glpat-x'));
      expect(accounts.kindOf('gitlab.corp'), ForgeKind.gitlab);
      expect(accounts.apiFor('gitlab.corp'), isA<GitLabApi>());

      // Read back as the app starts again.
      final again = ForgeAccounts(
        http: http,
        secrets: secrets,
        read: () => kept,
      );
      expect(again.accountFor('gitlab.corp')?.login, 'leo');

      await accounts.signOut('gitlab.corp');
      expect(accounts.accounts, isEmpty);
      expect(await secrets.read('forge.gitlab.corp'), isNull);
      expect(kept, isEmpty);
    });

    test('a self-hosted GitLab over http: its address kept, and spoken to '
        'so', () async {
      final http = FakeForgeHttp()
        ..on(
          'GET',
          'http://gitlab.corp:8080/api/v4/user',
          (_) => {'username': 'leo'},
        );
      final secrets = MemorySecretStore();
      Object? kept;
      final accounts = ForgeAccounts(
        http: http,
        secrets: secrets,
        write: (json) async => kept = json,
      );
      final account = await accounts.signInWithToken(
        ForgeKind.gitlab,
        'http://gitlab.corp:8080/',
        'glpat-x',
      );
      expect(account.host, 'gitlab.corp:8080');
      expect(account.scheme, 'http');
      expect(await secrets.read('forge.gitlab.corp:8080'), contains('glpat-x'));
      expect(kept, [
        {
          'kind': 'gitlab',
          'host': 'gitlab.corp:8080',
          'login': 'leo',
          'via': 'token',
          'scheme': 'http',
        },
      ]);
      expect(accounts.apiFor('gitlab.corp:8080'), isA<GitLabApi>());
    });

    test('a certificate the user trusts is kept, and taken again on start', () {
      final http = TrustingFakeForgeHttp();
      Object? kept;
      final accounts = ForgeAccounts(
        http: http,
        secrets: MemorySecretStore(),
        readCertificates: () => kept,
        writeCertificates: (json) async => kept = json,
      );
      accounts.trustCertificate('GitLab.Corp:8080', 'AB');
      expect(http.trusted['gitlab.corp:8080'], 'ab');
      expect(kept, {'gitlab.corp:8080': 'ab'});

      final again = TrustingFakeForgeHttp();
      ForgeAccounts(
        http: again,
        secrets: MemorySecretStore(),
        readCertificates: () => kept,
      );
      expect(again.trusted['gitlab.corp:8080'], 'ab');
    });

    test('a token that is not taken is not kept', () async {
      final http = FakeForgeHttp()
        ..on(
          'GET',
          'https://api.github.com/user',
          (_) => const ForgeResponse(401, '{"message":"Bad credentials"}'),
        );
      final secrets = MemorySecretStore();
      final accounts = ForgeAccounts(http: http, secrets: secrets);
      await expectLater(
        accounts.signInWithToken(ForgeKind.github, 'github.com', 'nope'),
        throwsA(isA<ForgeException>()),
      );
      expect(accounts.accounts, isEmpty);
      expect(await secrets.read('forge.github.com'), isNull);
    });

    test('from the browser: the code, waited on (slower when asked), then '
        'signed in', () async {
      var polls = 0;
      final http = FakeForgeHttp()
        ..on('POST', 'https://github.com/login/device/code', (request) {
          expect(request.form, {
            'client_id': 'Iv1.app',
            'scope': 'repo read:user',
          });
          return {
            'device_code': 'dc',
            'user_code': 'ABCD-1234',
            'verification_uri': 'https://github.com/login/device',
            'interval': 5,
            'expires_in': 900,
          };
        })
        ..on('POST', 'https://github.com/login/oauth/access_token', (request) {
          expect(request.form?['device_code'], 'dc');
          return switch (++polls) {
            1 => {'error': 'authorization_pending'},
            2 => {'error': 'slow_down'},
            _ => {'access_token': 'gho_x', 'token_type': 'bearer'},
          };
        })
        ..on('GET', 'https://api.github.com/user', (_) => {'login': 'leo'});
      final accounts = ForgeAccounts(
        http: http,
        secrets: MemorySecretStore(),
        githubClient: 'Iv1.app',
      );
      expect(
        accounts.canSignInFromBrowser(ForgeKind.github, 'github.com'),
        isTrue,
      );
      expect(
        accounts.canSignInFromBrowser(ForgeKind.gitlab, 'gitlab.com'),
        isFalse,
      );
      expect(
        accounts.canSignInFromBrowser(ForgeKind.gitee, 'gitee.com'),
        isFalse,
      );
      final code = await accounts.startDeviceFlow(ForgeKind.github);
      expect(code.userCode, 'ABCD-1234');
      final waits = <Duration>[];
      final account = await accounts.finishDeviceFlow(
        code,
        wait: (duration) async => waits.add(duration),
      );
      expect(account.login, 'leo');
      expect(account.via, ForgeSignIn.browser);
      expect(waits, const [
        Duration(seconds: 5),
        Duration(seconds: 5),
        Duration(seconds: 10),
      ]);
    });

    test("GitLab's token, once it is about to expire, is renewed", () async {
      var now = DateTime(2026, 10, 15, 9);
      final http = FakeForgeHttp()
        ..on(
          'POST',
          'https://gitlab.com/oauth/token',
          (request) => request.form?['grant_type'] == 'refresh_token'
              ? {
                  'access_token': 'new',
                  'refresh_token': 'r2',
                  'expires_in': 7200,
                }
              : {
                  'access_token': 'old',
                  'refresh_token': 'r1',
                  'expires_in': 7200,
                },
        )
        ..on(
          'POST',
          'https://gitlab.com/oauth/authorize_device',
          (_) => {
            'device_code': 'dc',
            'user_code': 'U',
            'verification_uri': 'https://gitlab.com/oauth/device',
          },
        )
        ..on(
          'GET',
          'https://gitlab.com/api/v4/user',
          (request) => {
            'username': request.headers['Authorization']!.substring(7),
          },
        );
      final accounts = ForgeAccounts(
        http: http,
        secrets: MemorySecretStore(),
        clock: () => now,
        gitlabClient: 'app',
      );
      await accounts.finishDeviceFlow(
        await accounts.startDeviceFlow(ForgeKind.gitlab),
        wait: (_) async {},
      );
      final api = accounts.apiFor('gitlab.com')!;
      expect((await api.me()).login, 'old');
      now = now.add(const Duration(hours: 2));
      expect((await api.me()).login, 'new');
    });

    test("GitLab's token renewed once for the requests that find it expired "
        'together: its refresh token is good for one refresh', () async {
      var now = DateTime(2026, 10, 15, 9);
      final http = FakeForgeHttp()
        ..on(
          'POST',
          'https://gitlab.com/oauth/token',
          (request) => request.form?['grant_type'] == 'refresh_token'
              ? {
                  'access_token': 'new',
                  'refresh_token': 'r2',
                  'expires_in': 7200,
                }
              : {
                  'access_token': 'old',
                  'refresh_token': 'r1',
                  'expires_in': 7200,
                },
        )
        ..on(
          'POST',
          'https://gitlab.com/oauth/authorize_device',
          (_) => {
            'device_code': 'dc',
            'user_code': 'U',
            'verification_uri': 'https://gitlab.com/oauth/device',
          },
        )
        ..on(
          'GET',
          'https://gitlab.com/api/v4/user',
          (request) => {
            'username': request.headers['Authorization']!.substring(7),
          },
        );
      final accounts = ForgeAccounts(
        http: http,
        secrets: MemorySecretStore(),
        clock: () => now,
        gitlabClient: 'app',
      );
      await accounts.finishDeviceFlow(
        await accounts.startDeviceFlow(ForgeKind.gitlab),
        wait: (_) async {},
      );
      final api = accounts.apiFor('gitlab.com')!;
      now = now.add(const Duration(hours: 2));
      final users = await Future.wait([api.me(), api.me(), api.me()]);
      expect(users.map((user) => user.login), ['new', 'new', 'new']);
      bool refresh(FakeRequest request) =>
          request.form?['grant_type'] == 'refresh_token';
      expect(http.requests.where(refresh), hasLength(1));
      // Kept: the next one does not renew it.
      expect((await api.me()).login, 'new');
      expect(http.requests.where(refresh), hasLength(1));
    });

    test('a token read once: the requests that arrive while the keychain is '
        'answering it wait on that read, not on one of their own', () async {
      final gate = Completer<void>();
      final secrets = CountingSecretStore(value: 'gho-t', gate: gate);
      final accounts = ForgeAccounts(
        http: FakeForgeHttp(),
        secrets: secrets,
        read: () => [
          ForgeAccount(
            kind: ForgeKind.github,
            host: 'github.com',
            login: 'leo',
          ).toJson(),
        ],
      );
      final api = accounts.apiFor('github.com')!;

      // Every linked issue asks for the token as its request goes out, all
      // of them at once (see the stash's refresh).
      final asking = [
        api.me().catchError((Object _) => const ForgeUser(login: '')),
        api.me().catchError((Object _) => const ForgeUser(login: '')),
        api.me().catchError((Object _) => const ForgeUser(login: '')),
      ];
      expect(secrets.reads, 1, reason: 'one read for all of them');
      gate.complete();
      await Future.wait(asking);
      expect(secrets.reads, 1, reason: 'kept: not read again');
    });

    test('a token read that fails is answered, and read again the next '
        'time: one program, never one for each request', () async {
      final gate = Completer<void>();
      final secrets = CountingSecretStore(failing: true, gate: gate);
      final accounts = ForgeAccounts(
        http: FakeForgeHttp(),
        secrets: secrets,
        read: () => [
          ForgeAccount(
            kind: ForgeKind.github,
            host: 'github.com',
            login: 'leo',
          ).toJson(),
        ],
      );
      final api = accounts.apiFor('github.com')!;

      final failing = [
        api.me().catchError((Object _) => const ForgeUser(login: '')),
        api.me().catchError((Object _) => const ForgeUser(login: '')),
      ];
      expect(secrets.reads, 1, reason: 'one read for all of them');
      gate.complete();
      await Future.wait(failing);
      expect(secrets.reads, 1);

      // Not poisonous: a token the keychain has meanwhile is read again.
      secrets.failing = false;
      secrets.value = 'gho-t2';
      await api.me().catchError((Object _) => const ForgeUser(login: ''));
      expect(secrets.reads, 2, reason: 'the failure was not kept');
    });
  });
}
