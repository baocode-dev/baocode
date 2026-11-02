// What BaoCode asks a forge, signed in as the user (see forge_accounts):
// GitHub's REST API (api.github.com, a GitHub Enterprise's /api/v3) and
// GitLab's (/api/v4). Over [ForgeHttp], which tests answer themselves.

import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart' show sha1;
import 'package:flutter/foundation.dart';

import 'forge_address.dart';
import 'forge_ref.dart';

/// A response: its status and its body, as text.
@immutable
class ForgeResponse {
  const ForgeResponse(this.status, this.body);

  final int status;
  final String body;

  bool get ok => status >= 200 && status < 300;

  Object? get json => body.isEmpty ? null : jsonDecode(body);
}

/// Sends a request: [form] as a form, else [json] as JSON, else [bytes]
/// as they are (their type in [headers]). Throws [ForgeException] when
/// there is no answer.
abstract interface class ForgeHttp {
  Future<ForgeResponse> send(
    String method,
    Uri url, {
    Map<String, String> headers = const {},
    Object? json,
    Map<String, String>? form,
    List<int>? bytes,
  });
}

/// Takes a server's certificate the user confirmed, by its SHA-256, for
/// the host it is served from: a self-signed one, or a private CA's. Every
/// other certificate is checked as usual.
abstract interface class ForgeCertificateTrust {
  void trustCertificate(String host, String sha256);
}

/// A forge did not do what was asked: no answer ([status] null), a token
/// it does not take (401), something not there or not to be seen (404).
class ForgeException implements Exception {
  const ForgeException(this.message, {this.status});

  final String message;
  final int? status;

  bool get unauthorized => status == 401;

  @override
  String toString() => message;
}

/// A forge's certificate cannot be verified: the one it presents, for the
/// user to confirm (it is then trusted by [sha256], and only it).
class ForgeCertificateException extends ForgeException {
  const ForgeCertificateException(
    super.message, {
    required this.host,
    required this.sha256,
    this.subject = '',
    this.issuer = '',
  });

  /// The server's authority (`gitlab.corp:8080`).
  final String host;

  /// The fingerprint of the certificate it presented, in hex.
  final String sha256;

  /// Whom the certificate is for, and who issued it, as it says.
  final String subject;
  final String issuer;
}

/// The message in a forge's error response, if it has one.
String? forgeErrorMessage(ForgeResponse response) {
  try {
    return switch (response.json) {
      {'error_description': final String message} => message,
      {'message': final String message} => message,
      {'error': final String message} => message,
      _ => null,
    };
  } on FormatException {
    return null;
  }
}

/// Where an issue or pull request is.
enum ForgeState {
  open,

  /// A pull request not ready for review yet.
  draft,
  closed,

  /// A pull request merged.
  merged;

  static ForgeState? parse(Object? value) =>
      values.where((state) => state.name == value).firstOrNull;

  bool get isOpen => this == open || this == draft;
}

/// How a pull request's checks (CI) went, all of them together.
enum ForgeChecks {
  pending,
  success,
  failure;

  static ForgeChecks? parse(Object? value) =>
      values.where((checks) => checks.name == value).firstOrNull;
}

/// What a pull request's reviewers say, together: changes asked for while
/// any's latest review asks for them; else approved when any approved.
enum ForgeReview {
  approved,
  changesRequested;

  static ForgeReview? parse(Object? value) =>
      values.where((review) => review.name == value).firstOrNull;
}

@immutable
class ForgeLabel {
  const ForgeLabel(this.name, {this.color});

  final String name;

  /// `#rrggbb`, when the forge said.
  final String? color;

  @override
  bool operator ==(Object other) =>
      other is ForgeLabel && other.name == name && other.color == color;

  @override
  int get hashCode => Object.hash(name, color);
}

/// An issue or pull request as the forge has it now.
@immutable
class ForgeItem {
  const ForgeItem({
    required this.ref,
    required this.title,
    required this.state,
    this.body = '',
    this.author,
    this.labels = const [],
    this.assignees = const [],
    this.comments = 0,
    this.updated,
    this.checks,
    this.review,
    this.branch,
  });

  final ForgeRef ref;
  final String title;
  final ForgeState state;

  /// Its description, as Markdown.
  final String body;
  final String? author;
  final List<ForgeLabel> labels;
  final List<String> assignees;
  final int comments;
  final DateTime? updated;

  /// A pull request's, when it has any.
  final ForgeChecks? checks;

  /// A pull request's, when it was reviewed.
  final ForgeReview? review;

  /// A pull request's branch.
  final String? branch;
}

/// Whose issues a list is of.
enum ForgeIssueFilter { assigned, created, all }

/// A comment on an issue or pull request.
@immutable
class ForgeComment {
  const ForgeComment({
    required this.author,
    required this.body,
    this.created,
    this.url,
  });

  final String author;

  /// As Markdown.
  final String body;
  final DateTime? created;
  final String? url;
}

/// Who the token is of.
@immutable
class ForgeUser {
  const ForgeUser({required this.login, this.name});

  final String login;
  final String? name;
}

/// A forge's API, signed in.
abstract class ForgeApi {
  ForgeApi({
    required this.host,
    this.scheme = 'https',
    required this.http,
    required this.token,
  });

  /// The forge's authority (`github.com`, `gitlab.example.com:8080`).
  final String host;

  /// `http`, for a self-hosted forge served so; `https` otherwise.
  final String scheme;

  final ForgeHttp http;

  /// The API at [path] on the forge.
  Uri _at(String path, {Map<String, String>? query}) =>
      forgeUri(scheme, host, path, query: query);

  /// Its token, asked for when needed (it may be refreshed meanwhile).
  final Future<String> Function() token;

  ForgeKind get kind;

  /// Who is signed in.
  Future<ForgeUser> me();

  /// [ref] as it is now.
  Future<ForgeItem> item(ForgeRef ref);

  /// [repo]'s open issues: [filter]'s, matching [query] when given; the
  /// most recently updated first.
  Future<List<ForgeItem>> issues(
    ForgeRepo repo, {
    ForgeIssueFilter filter = ForgeIssueFilter.assigned,
    String query = '',
  });

  /// Comments [body] on [ref].
  Future<void> comment(ForgeRef ref, String body);

  /// Closes the issue [ref]; as not planned when [duplicate] (its
  /// comment says of which).
  Future<void> close(ForgeRef ref, {bool duplicate = false});

  /// [ref]'s last comments (up to [most]), the oldest first; [total] how
  /// many it has, where known (to ask for the last of them).
  Future<List<ForgeComment>> comments(ForgeRef ref, {int? total, int most = 5});

  /// [repo]'s issues, the most recently updated first, page by page up to
  /// [most]: the open ones, or (since [since]) all changed since, closed
  /// ones too. Not its pull requests.
  Future<List<ForgeItem>> allIssues(
    ForgeRepo repo, {
    DateTime? since,
    int most = 1000,
  });

  /// How many a page of [allIssues] asks for.
  static const pageSize = 100;

  /// Opens an issue in [repo], as the user: [title], [body] its
  /// description.
  Future<ForgeItem> createIssue(
    ForgeRepo repo, {
    required String title,
    required String body,
  });

  /// Changes the issue [ref]'s title and description.
  Future<ForgeItem> editIssue(
    ForgeRef ref, {
    required String title,
    required String body,
  });

  /// Puts [bytes], a picture named [name], where [repo]'s issues can show
  /// it; its address. The same picture is put there once.
  Future<String> uploadImage(ForgeRepo repo, String name, List<int> bytes);

  Uri get _base;

  Map<String, String> _headers(String token);

  Future<Object?> _call(
    String method,
    String path, {
    Map<String, String>? query,
    Object? json,
    List<int>? bytes,
    String? contentType,
  }) async {
    final url = _base.replace(
      path: '${_base.path}$path',
      queryParameters: query,
    );
    final response = await http.send(
      method,
      url,
      headers: {..._headers(await token()), 'Content-Type': ?contentType},
      json: json,
      bytes: bytes,
    );
    if (!response.ok) {
      throw ForgeException(
        forgeErrorMessage(response) ?? 'HTTP ${response.status}',
        status: response.status,
      );
    }
    return response.json;
  }

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toLocal() : null;

  /// A picture's name by what it is: the same picture, the same name.
  static String _assetName(String name, List<int> bytes) {
    final dot = name.lastIndexOf('.');
    final extension = dot < 0 ? '.png' : name.substring(dot).toLowerCase();
    return '${sha1.convert(bytes).toString().substring(0, 20)}$extension';
  }

  static String _mimeOf(String name) =>
      switch (name.substring(name.lastIndexOf('.') + 1).toLowerCase()) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'gif' => 'image/gif',
        'webp' => 'image/webp',
        'svg' => 'image/svg+xml',
        _ => 'image/png',
      };
}

/// GitHub's REST API.
class GitHubApi extends ForgeApi {
  GitHubApi({
    required super.host,
    super.scheme,
    required super.http,
    required super.token,
  });

  @override
  ForgeKind get kind => ForgeKind.github;

  @override
  Uri get _base =>
      host == 'github.com' ? Uri.https('api.github.com', '') : _at('/api/v3');

  @override
  Map<String, String> _headers(String token) => {
    'Authorization': 'Bearer $token',
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
  };

  @override
  Future<ForgeUser> me() async {
    final json = await _call('GET', '/user') as Map;
    return ForgeUser(
      login: json['login'] as String,
      name: json['name'] as String?,
    );
  }

  @override
  Future<ForgeItem> item(ForgeRef ref) async {
    final repo = '/repos/${ref.repo.path}';
    if (ref.kind == ForgeItemKind.issue) {
      final json = await _call('GET', '$repo/issues/${ref.number}') as Map;
      // A pull request's number, linked as an issue's.
      if (json['pull_request'] != null) {
        return item(
          ForgeRef(
            repo: ref.repo,
            kind: ForgeItemKind.pull,
            number: ref.number,
          ),
        );
      }
      return _issue(ref.repo, json);
    }
    final json = await _call('GET', '$repo/pulls/${ref.number}') as Map;
    final sha = (json['head'] as Map?)?['sha'] as String?;
    return _issue(
      ref.repo,
      json,
      kind: ForgeItemKind.pull,
      state: json['merged_at'] != null
          ? ForgeState.merged
          : json['state'] == 'closed'
          ? ForgeState.closed
          : json['draft'] == true
          ? ForgeState.draft
          : ForgeState.open,
      checks: sha == null ? null : await _checks(repo, sha),
      review: await _review(repo, ref.number),
      branch: (json['head'] as Map?)?['ref'] as String?,
    );
  }

  /// Pull request [number]'s reviews, together (see [ForgeReview]): each
  /// reviewer's latest that approves, asks for changes or was dismissed.
  Future<ForgeReview?> _review(String repo, int number) async {
    try {
      final json = await _call(
        'GET',
        '$repo/pulls/$number/reviews',
        query: {'per_page': '100'},
      ) as List;
      final latest = <String, String>{};
      for (final review in json.whereType<Map>()) {
        final state = review['state'] as String?;
        final user = (review['user'] as Map?)?['login'] as String?;
        if (user == null ||
            !const {
              'APPROVED',
              'CHANGES_REQUESTED',
              'DISMISSED',
            }.contains(state)) {
          continue;
        }
        latest[user] = state!;
      }
      if (latest.values.contains('CHANGES_REQUESTED')) {
        return ForgeReview.changesRequested;
      }
      return latest.values.contains('APPROVED') ? ForgeReview.approved : null;
    } on ForgeException {
      return null;
    }
  }

  /// The commit [sha]'s check runs, together: failed when any failed,
  /// pending while any runs; none when it has none.
  Future<ForgeChecks?> _checks(String repo, String sha) async {
    try {
      final json = await _call(
        'GET',
        '$repo/commits/$sha/check-runs',
        query: {'per_page': '100'},
      ) as Map;
      final runs = (json['check_runs'] as List?)?.cast<Map>() ?? const [];
      if (runs.isEmpty) return null;
      if (runs.any((run) => run['status'] != 'completed')) {
        return ForgeChecks.pending;
      }
      const failed = {'failure', 'timed_out', 'cancelled', 'action_required'};
      return runs.any((run) => failed.contains(run['conclusion']))
          ? ForgeChecks.failure
          : ForgeChecks.success;
    } on ForgeException {
      // Not to be seen with this token: no checks shown.
      return null;
    }
  }

  ForgeItem _issue(
    ForgeRepo repo,
    Map json, {
    ForgeItemKind kind = ForgeItemKind.issue,
    ForgeState? state,
    ForgeChecks? checks,
    ForgeReview? review,
    String? branch,
  }) => ForgeItem(
    ref: ForgeRef(repo: repo, kind: kind, number: json['number'] as int),
    title: json['title'] as String? ?? '',
    state:
        state ??
        (json['state'] == 'closed' ? ForgeState.closed : ForgeState.open),
    body: json['body'] as String? ?? '',
    author: (json['user'] as Map?)?['login'] as String?,
    labels: [
      for (final label in (json['labels'] as List?) ?? const [])
        if (label is Map)
          ForgeLabel(
            label['name'] as String? ?? '',
            color: switch (label['color']) {
              final String color when color.isNotEmpty => '#$color',
              _ => null,
            },
          ),
    ],
    assignees: [
      for (final user in (json['assignees'] as List?) ?? const [])
        if (user is Map) ?user['login'] as String?,
    ],
    comments: json['comments'] as int? ?? 0,
    updated: ForgeApi._date(json['updated_at']),
    checks: checks,
    review: review,
    branch: branch,
  );

  @override
  Future<List<ForgeItem>> issues(
    ForgeRepo repo, {
    ForgeIssueFilter filter = ForgeIssueFilter.assigned,
    String query = '',
  }) async {
    final terms = [
      'repo:${repo.path}',
      'is:issue',
      'is:open',
      switch (filter) {
        ForgeIssueFilter.assigned => 'assignee:@me',
        ForgeIssueFilter.created => 'author:@me',
        ForgeIssueFilter.all => '',
      },
      query.trim(),
    ].where((term) => term.isNotEmpty).join(' ');
    final json = await _call(
      'GET',
      '/search/issues',
      query: {'q': terms, 'sort': 'updated', 'order': 'desc', 'per_page': '50'},
    ) as Map;
    return [
      for (final issue in (json['items'] as List?) ?? const [])
        if (issue is Map) _issue(repo, issue),
    ];
  }

  @override
  Future<void> comment(ForgeRef ref, String body) => _call(
    'POST',
    '/repos/${ref.repo.path}/issues/${ref.number}/comments',
    json: {'body': body},
  );

  @override
  Future<void> close(ForgeRef ref, {bool duplicate = false}) => _call(
    'PATCH',
    '/repos/${ref.repo.path}/issues/${ref.number}',
    json: {'state': 'closed', if (duplicate) 'state_reason': 'not_planned'},
  );

  @override
  Future<List<ForgeComment>> comments(
    ForgeRef ref, {
    int? total,
    int most = 5,
  }) async {
    Future<List<ForgeComment>> page(int page) async {
      final json = await _call(
        'GET',
        '/repos/${ref.repo.path}/issues/${ref.number}/comments',
        query: {'per_page': '$most', 'page': '$page'},
      ) as List;
      return [
        for (final comment in json)
          if (comment is Map)
            ForgeComment(
              author: (comment['user'] as Map?)?['login'] as String? ?? '',
              body: comment['body'] as String? ?? '',
              created: ForgeApi._date(comment['created_at']),
              url: comment['html_url'] as String?,
            ),
      ];
    }

    // The oldest first: the last page is the latest.
    final last = total == null || total <= 0 ? 1 : (total + most - 1) ~/ most;
    final comments = await page(last);
    if (comments.length < most && last > 1) {
      comments.insertAll(0, await page(last - 1));
    }
    return comments.length > most
        ? comments.sublist(comments.length - most)
        : comments;
  }

  @override
  Future<List<ForgeItem>> allIssues(
    ForgeRepo repo, {
    DateTime? since,
    int most = 1000,
  }) async {
    final items = <ForgeItem>[];
    for (var page = 1; items.length < most; page++) {
      final json = await _call(
        'GET',
        '/repos/${repo.path}/issues',
        query: {
          'state': since == null ? 'open' : 'all',
          'since': ?since?.toUtc().toIso8601String(),
          'sort': 'updated',
          'direction': 'desc',
          'per_page': '${ForgeApi.pageSize}',
          'page': '$page',
        },
      ) as List;
      for (final issue in json) {
        // Pull requests are issues to GitHub.
        if (issue is Map && issue['pull_request'] == null) {
          items.add(_issue(repo, issue));
        }
      }
      if (json.length < ForgeApi.pageSize) break;
    }
    return items.take(most).toList();
  }

  @override
  Future<ForgeItem> createIssue(
    ForgeRepo repo, {
    required String title,
    required String body,
  }) async {
    final json = await _call(
      'POST',
      '/repos/${repo.path}/issues',
      json: {'title': title, 'body': body},
    ) as Map;
    return _issue(repo, json);
  }

  @override
  Future<ForgeItem> editIssue(
    ForgeRef ref, {
    required String title,
    required String body,
  }) async {
    final json = await _call(
      'PATCH',
      '/repos/${ref.repo.path}/issues/${ref.number}',
      json: {'title': title, 'body': body},
    ) as Map;
    return _issue(ref.repo, json);
  }

  /// The branch the pictures go in: one of their own, with no history of
  /// the code's, made the first time.
  static const assetsBranch = 'baocode-stash-assets';

  /// GitHub has no API for an issue's attachments: the picture is a file
  /// of [assetsBranch] (`stash/<its hash>.png`), shown from there.
  @override
  Future<String> uploadImage(
    ForgeRepo repo,
    String name,
    List<int> bytes,
  ) async {
    final path = 'stash/${ForgeApi._assetName(name, bytes)}';
    await _ensureAssetsBranch(repo);
    try {
      await _call(
        'PUT',
        '/repos/${repo.path}/contents/$path',
        json: {
          'message': 'Add a picture from BaoCode Stash',
          'content': base64Encode(bytes),
          'branch': assetsBranch,
        },
      );
    } on ForgeException catch (error) {
      // There already: put there before.
      if (error.status != 422) rethrow;
    }
    return repo.url
        .replace(
          path: '/${repo.path}/blob/$assetsBranch/$path',
          queryParameters: {'raw': 'true'},
        )
        .toString();
  }

  final Set<ForgeRepo> _branched = {};

  Future<void> _ensureAssetsBranch(ForgeRepo repo) async {
    if (_branched.contains(repo)) return;
    final at = '/repos/${repo.path}';
    try {
      await _call('GET', '$at/branches/$assetsBranch');
    } on ForgeException catch (error) {
      if (error.status != 404) rethrow;
      final tree = await _call(
        'POST',
        '$at/git/trees',
        json: {
          'tree': [
            {
              'path': 'README.md',
              'mode': '100644',
              'type': 'blob',
              'content':
                  'Pictures of the issues opened from BaoCode\'s '
                  'Stash (https://baocode.dev).\n',
            },
          ],
        },
      ) as Map;
      final commit = await _call(
        'POST',
        '$at/git/commits',
        json: {
          'message': 'BaoCode Stash pictures',
          'tree': tree['sha'],
          'parents': const <String>[],
        },
      ) as Map;
      await _call(
        'POST',
        '$at/git/refs',
        json: {'ref': 'refs/heads/$assetsBranch', 'sha': commit['sha']},
      );
    }
    _branched.add(repo);
  }
}

/// GitLab's REST API (v4).
class GitLabApi extends ForgeApi {
  GitLabApi({
    required super.host,
    super.scheme,
    required super.http,
    required super.token,
  });

  @override
  ForgeKind get kind => ForgeKind.gitlab;

  @override
  Uri get _base => _at('/api/v4');

  @override
  Map<String, String> _headers(String token) => {
    'Authorization': 'Bearer $token',
    'Accept': 'application/json',
  };

  /// A project's path as the API takes it in place of its id.
  static String _project(ForgeRepo repo) =>
      '/projects/${Uri.encodeComponent(repo.path)}';

  @override
  Future<ForgeUser> me() async {
    final json = await _call('GET', '/user') as Map;
    return ForgeUser(
      login: json['username'] as String,
      name: json['name'] as String?,
    );
  }

  @override
  Future<ForgeItem> item(ForgeRef ref) async {
    final project = _project(ref.repo);
    if (ref.kind == ForgeItemKind.issue) {
      final json = await _call('GET', '$project/issues/${ref.number}') as Map;
      return _item(ref.repo, json);
    }
    final json =
        await _call('GET', '$project/merge_requests/${ref.number}') as Map;
    return _item(
      ref.repo,
      json,
      kind: ForgeItemKind.pull,
      state: switch (json['state']) {
        'merged' => ForgeState.merged,
        'closed' || 'locked' => ForgeState.closed,
        _ when json['draft'] == true || json['work_in_progress'] == true =>
          ForgeState.draft,
        _ => ForgeState.open,
      },
      checks: switch ((json['head_pipeline'] as Map?)?['status']) {
        'success' => ForgeChecks.success,
        'failed' || 'canceled' => ForgeChecks.failure,
        null || 'skipped' || 'manual' => null,
        _ => ForgeChecks.pending,
      },
      review: switch (json['detailed_merge_status']) {
        'requested_changes' => ForgeReview.changesRequested,
        _ => null,
      },
      branch: json['source_branch'] as String?,
    );
  }

  ForgeItem _item(
    ForgeRepo repo,
    Map json, {
    ForgeItemKind kind = ForgeItemKind.issue,
    ForgeState? state,
    ForgeChecks? checks,
    ForgeReview? review,
    String? branch,
  }) => ForgeItem(
    ref: ForgeRef(repo: repo, kind: kind, number: json['iid'] as int),
    title: json['title'] as String? ?? '',
    state:
        state ??
        (json['state'] == 'closed' ? ForgeState.closed : ForgeState.open),
    body: json['description'] as String? ?? '',
    author: (json['author'] as Map?)?['username'] as String?,
    labels: [
      for (final label in (json['labels'] as List?) ?? const [])
        switch (label) {
          final String name => ForgeLabel(name),
          // With_labels_details: their colors too.
          final Map label => ForgeLabel(
            label['name'] as String? ?? '',
            color: label['color'] as String?,
          ),
          _ => const ForgeLabel(''),
        },
    ].where((label) => label.name.isNotEmpty).toList(),
    assignees: [
      for (final user in (json['assignees'] as List?) ?? const [])
        if (user is Map) ?user['username'] as String?,
    ],
    comments: json['user_notes_count'] as int? ?? 0,
    updated: ForgeApi._date(json['updated_at']),
    checks: checks,
    review: review,
    branch: branch,
  );

  @override
  Future<List<ForgeItem>> issues(
    ForgeRepo repo, {
    ForgeIssueFilter filter = ForgeIssueFilter.assigned,
    String query = '',
  }) async {
    final json = await _call(
      'GET',
      '${_project(repo)}/issues',
      query: {
        'state': 'opened',
        'scope': switch (filter) {
          ForgeIssueFilter.assigned => 'assigned_to_me',
          ForgeIssueFilter.created => 'created_by_me',
          ForgeIssueFilter.all => 'all',
        },
        'search': ?(query.trim().isEmpty ? null : query.trim()),
        'with_labels_details': 'true',
        'order_by': 'updated_at',
        'sort': 'desc',
        'per_page': '50',
      },
    ) as List;
    return [
      for (final issue in json)
        if (issue is Map) _item(repo, issue),
    ];
  }

  @override
  Future<void> comment(ForgeRef ref, String body) => _call(
    'POST',
    '${_project(ref.repo)}/${ref.kind == ForgeItemKind.pull ? 'merge_requests' : 'issues'}/${ref.number}/notes',
    json: {'body': body},
  );

  @override
  Future<void> close(ForgeRef ref, {bool duplicate = false}) => _call(
    'PUT',
    '${_project(ref.repo)}/issues/${ref.number}',
    json: {'state_event': 'close'},
  );

  @override
  Future<List<ForgeComment>> comments(
    ForgeRef ref, {
    int? total,
    int most = 5,
  }) async {
    final kind = ref.kind == ForgeItemKind.pull ? 'merge_requests' : 'issues';
    final json = await _call(
      'GET',
      '${_project(ref.repo)}/$kind/${ref.number}/notes',
      query: {
        'sort': 'desc',
        'order_by': 'created_at',
        'per_page': '${most * 4}',
      },
    ) as List;
    return [
      for (final note in json)
        // Not those GitLab writes itself (labels changed, mentioned…).
        if (note is Map && note['system'] != true)
          ForgeComment(
            author: (note['author'] as Map?)?['username'] as String? ?? '',
            body: note['body'] as String? ?? '',
            created: ForgeApi._date(note['created_at']),
          ),
    ].take(most).toList().reversed.toList();
  }

  @override
  Future<List<ForgeItem>> allIssues(
    ForgeRepo repo, {
    DateTime? since,
    int most = 1000,
  }) async {
    final items = <ForgeItem>[];
    for (var page = 1; items.length < most; page++) {
      final json = await _call(
        'GET',
        '${_project(repo)}/issues',
        query: {
          if (since == null) 'state': 'opened',
          'updated_after': ?since?.toUtc().toIso8601String(),
          'scope': 'all',
          'with_labels_details': 'true',
          'order_by': 'updated_at',
          'sort': 'desc',
          'per_page': '${ForgeApi.pageSize}',
          'page': '$page',
        },
      ) as List;
      for (final issue in json) {
        if (issue is Map) items.add(_item(repo, issue));
      }
      if (json.length < ForgeApi.pageSize) break;
    }
    return items.take(most).toList();
  }

  @override
  Future<ForgeItem> createIssue(
    ForgeRepo repo, {
    required String title,
    required String body,
  }) async {
    final json = await _call(
      'POST',
      '${_project(repo)}/issues',
      json: {'title': title, 'description': body},
    ) as Map;
    return _item(repo, json);
  }

  @override
  Future<ForgeItem> editIssue(
    ForgeRef ref, {
    required String title,
    required String body,
  }) async {
    final json = await _call(
      'PUT',
      '${_project(ref.repo)}/issues/${ref.number}',
      json: {'title': title, 'description': body},
    ) as Map;
    return _item(ref.repo, json);
  }

  /// The project's uploads, as a picture pasted into an issue is.
  @override
  Future<String> uploadImage(
    ForgeRepo repo,
    String name,
    List<int> bytes,
  ) async {
    final file = ForgeApi._assetName(name, bytes);
    final boundary =
        'baocode-${math.Random().nextInt(1 << 32).toRadixString(16)}';
    final body = <int>[
      ...utf8.encode(
        '--$boundary\r\n'
        'Content-Disposition: form-data; name="file"; filename="$file"\r\n'
        'Content-Type: ${ForgeApi._mimeOf(file)}\r\n\r\n',
      ),
      ...bytes,
      ...utf8.encode('\r\n--$boundary--\r\n'),
    ];
    final json = await _call(
      'POST',
      '${_project(repo)}/uploads',
      bytes: body,
      contentType: 'multipart/form-data; boundary=$boundary',
    ) as Map;
    return switch ((json['full_path'], json['url'])) {
      (final String full, _) => 'https://$host$full',
      (_, final String url) => 'https://$host/${repo.path}$url',
      _ => throw const ForgeException('The picture was not taken.'),
    };
  }
}
