import 'dart:typed_data';

import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/forge/forge_accounts.dart';
import 'package:baocode/forge/forge_api.dart';
import 'package:baocode/forge/forge_ref.dart';
import 'package:baocode/models/secret_store.dart';
import 'package:baocode/stash/stash_disk.dart';
import 'package:baocode/stash/stash_forge.dart';
import 'package:baocode/stash/stash_note.dart';
import 'package:baocode/stash/stash_settings.dart';
import 'package:baocode/stash/stash_store.dart';
import 'package:baocode/stash/stash_threads.dart';
import 'package:baocode/workspace/workspace.dart';
import 'package:flutter_test/flutter_test.dart';

import '../forge/forge_test.dart' show FakeForgeHttp;
import '../workspace/project_workspace_test.dart' show FakeWorkspaceDirectories;

/// [inner], each request answered a turn later, and how many were asked at
/// once at the most.
class _CountingHttp implements ForgeHttp {
  _CountingHttp(this.inner);

  final ForgeHttp inner;
  int _asking = 0;
  int most = 0;

  @override
  Future<ForgeResponse> send(
    String method,
    Uri url, {
    Map<String, String> headers = const {},
    Object? json,
    Map<String, String>? form,
    List<int>? bytes,
  }) async {
    _asking++;
    if (_asking > most) most = _asking;
    try {
      await Future<void>.delayed(Duration.zero);
      return await inner.send(
        method,
        url,
        headers: headers,
        json: json,
        form: form,
        bytes: bytes,
      );
    } finally {
      _asking--;
    }
  }
}

const issueUrl = 'https://github.com/o/r/issues/3';
const pullUrl = 'https://github.com/o/r/pull/7';

void main() {
  late FakeForgeHttp http;
  late ForgeAccounts accounts;
  late StashStore store;
  late StashForge forge;
  var issueState = 'open';

  setUp(() async {
    issueState = 'open';
    http = FakeForgeHttp()
      ..on('GET', 'https://api.github.com/user', (_) => {'login': 'leo'})
      ..on(
        'GET',
        'https://api.github.com/repos/o/r/issues/3',
        (_) => {
          'number': 3,
          'title': 'Uploads fail',
          'state': issueState,
          'labels': [
            {'name': 'bug', 'color': 'd73a4a'},
          ],
        },
      )
      ..on(
        'GET',
        'https://api.github.com/repos/o/r/pulls/7',
        (_) => {
          'number': 7,
          'title': 'Retry uploads',
          'state': 'open',
          'draft': false,
        },
      )
      ..on(
        'POST',
        'https://api.github.com/repos/o/r/issues/3/comments',
        (_) => {},
      )
      ..on('PATCH', 'https://api.github.com/repos/o/r/issues/3', (request) {
        issueState = 'closed';
        return {};
      });
    accounts = ForgeAccounts(http: http, secrets: MemorySecretStore());
    await accounts.signInWithToken(ForgeKind.github, 'github.com', 't');
    store = StashStore(MemoryStashDisk());
    await store.load();
    forge = StashForge(
      store: store,
      workspace: Workspace.mock(),
      accounts: accounts,
      remotes: (folder) async => switch (folder) {
        '~/code/baocode' => ['git@github.com:o/r.git'],
        _ => const [],
      },
    );
  });

  tearDown(() => forge.dispose());

  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('a link in its text links the stash to the issue, asked of GitHub '
      'and kept with the link', () async {
    final note = await store.create(body: 'Fix this: $issueUrl please');
    forge.start();
    await settle();
    final link = store.byId(note.id)!.issues.single;
    expect(link.url, issueUrl);
    expect(link.title, 'Uploads fail');
    expect(link.state, 'open');
    expect(forge.itemOf(issueUrl)?.labels.single.name, 'bug');
    // In its file too, for when it cannot be asked.
    expect(StashNote.decode(note.id, store.byId(note.id)!.encode()).issues, [
      link,
    ]);
  });

  test('closed while the stash is not done, it asks; done with the issue '
      'still open, it asks to say so there, and writes only then', () async {
    final note = await store.create(body: issueUrl);
    forge.start();
    await settle();
    expect(forge.closedIssues(store.byId(note.id)!), isEmpty);

    issueState = 'closed';
    await forge.refresh(force: true);
    await settle();
    expect(forge.closedIssues(store.byId(note.id)!).single.url, issueUrl);
    await forge.answer(note.id, [issueUrl]);
    expect(forge.closedIssues(store.byId(note.id)!), isEmpty);

    // Opened again: the question is new.
    issueState = 'open';
    await forge.refresh(force: true);
    await settle();
    await store.update(note.id, (note) => note.status = StashStatus.done);
    expect(forge.openIssues(store.byId(note.id)!).single.url, issueUrl);
    final writes = http.requests.where((r) => r.method != 'GET').length;
    expect(writes, 0);

    await forge.write(note.id, issueUrl, text: 'Fixed in #7', close: true);
    final sent = http.requests.where((r) => r.method != 'GET').toList();
    expect(sent.map((r) => r.method), ['POST', 'PATCH']);
    expect(sent.first.json, {'body': 'Fixed in #7'});
    await settle();
    expect(forge.openIssues(store.byId(note.id)!), isEmpty);
    expect(store.byId(note.id)!.issueOf(issueUrl)?.state, 'closed');
  });

  test('what should not go out is found', () {
    expect(
      StashForge.sensitive(
        'see /Users/leo/app/a.dart with sk-ant-0123456789abcdefghij',
      ),
      ['/Users/leo/app/a.dart', 'sk-ant-0123456789abcdefghij'],
    );
    expect(StashForge.sensitive('Fixed in #7.'), isEmpty);
  });

  test(
    'imported: a stash each, the issue, titled and its text; once',
    () async {
      final repos = await forge.repositories();
      expect(repos.single.repo.path, 'o/r');
      expect(repos.single.project.path, '~/code/baocode');
      final item = ForgeItem(
        ref: ForgeRef.parse(issueUrl)!,
        title: 'Uploads fail [503]',
        state: ForgeState.open,
        body: 'They fail on 503.',
      );
      final notes = await forge.import([item], project: '~/code/baocode');
      final note = notes.single;
      expect(note.title, 'Uploads fail [503]');
      expect(note.project, '~/code/baocode');
      expect(note.body, 'They fail on 503.');
      expect(note.issue, issueUrl);
      expect(note.issues.single.url, issueUrl);
      expect(note.changedHere, isFalse);
      expect(forge.stashOf(issueUrl)?.id, note.id);
      expect((await forge.import([item])).single.id, note.id);
      expect(store.notes, hasLength(1));
    },
  );

  group('kept in step with the projects\' issues', () {
    late List<Map<String, Object?>> open;

    /// The lists asked for, by their `since`.
    late List<String?> listed;
    Map<String, Object?> issue(int number, String title, String body) => {
      'number': number,
      'title': title,
      'body': body,
      'state': 'open',
    };

    setUp(() {
      listed = [];
      open = [issue(3, 'Uploads fail', 'On 503.'), issue(4, 'Dark mode', '')];
      http
        ..on('GET', 'https://api.github.com/repos/o/r/issues', (request) {
          listed.add(request.url.queryParameters['since']);
          return [
            ...open,
            // A pull request, as GitHub lists them among issues.
            {...issue(7, 'Retry', ''), 'pull_request': {}},
          ];
        })
        ..on('GET', 'https://api.github.com/search/issues', (request) {
          final q = request.url.queryParameters['q']!;
          if (q.contains('author:@me')) return {'items': open.take(1).toList()};
          if (q.contains('assignee:@me')) return {'items': <Object>[]};
          return {'items': open};
        });
    });

    test('each open issue a stash, once; one deleted never again', () async {
      await forge.sync();
      expect(
        [for (final note in store.notes) (note.title, note.issue)],
        unorderedEquals([
          ('Uploads fail', issueUrl),
          ('Dark mode', 'https://github.com/o/r/issues/4'),
        ]),
      );
      final uploads = forge.stashOf(issueUrl)!;
      expect(uploads.body, 'On 503.');
      expect(uploads.project, '~/code/baocode');

      await forge.sync();
      expect(store.notes, hasLength(2));

      await store.delete(uploads.id);
      expect(store.ignoredIssues, contains(issueUrl));
      await forge.sync();
      expect(store.notes, hasLength(1));
      expect(forge.stashOf(issueUrl), isNull);
    });

    test('every open one by default, the first time; then those changed '
        'since, a closed one closing its stash, none made of it', () async {
      await forge.sync();
      expect(store.notes, hasLength(2));
      expect(listed, [null]);
      open = [
        {...issue(4, 'Dark mode', ''), 'state': 'closed'},
        {...issue(5, 'Old one', ''), 'state': 'closed'},
      ];
      await forge.sync();
      expect(listed, hasLength(2));
      expect(listed.last, isNotNull);
      expect(store.notes, hasLength(2));
      final dark = forge.stashOf('https://github.com/o/r/issues/4')!;
      expect(dark.status, StashStatus.done);
      expect(forge.lastSynced, isNotNull);
      expect(forge.syncFailures, isEmpty);
      // All again when asked.
      await forge.sync(full: true);
      expect(listed.last, isNull);
    });

    test('only the user\'s when the settings say', () async {
      forge.dispose();
      forge = StashForge(
        store: store,
        workspace: Workspace.mock(),
        accounts: accounts,
        remotes: (folder) async => switch (folder) {
          '~/code/baocode' => ['git@github.com:o/r.git'],
          _ => const [],
        },
        issueSync: () => StashIssueSync.mine,
      );
      await forge.sync();
      expect([for (final note in store.notes) note.issue], [issueUrl]);
    });

    test(
      'a repository that fails, or a forge not signed in to, is told',
      () async {
        http.on(
          'GET',
          'https://api.github.com/repos/o/r/issues',
          (_) => const ForgeResponse(403, '{"message":"rate limited"}'),
        );
        forge.dispose();
        forge = StashForge(
          store: store,
          workspace: Workspace.mock(),
          accounts: accounts,
          remotes: (folder) async => switch (folder) {
            '~/code/baocode' => ['git@github.com:o/r.git'],
            '~/code/cursor-docs' => ['git@gitlab.com:g/docs.git'],
            _ => const [],
          },
        );
        await forge.sync();
        expect(forge.syncFailures.values.single.message, 'rate limited');
        expect([for (final repo in forge.unsignedRepos) repo.path], ['g/docs']);
        expect(forge.syncing, isFalse);
      },
    );

    test('none when turned off', () async {
      forge.dispose();
      forge = StashForge(
        store: store,
        workspace: Workspace.mock(),
        accounts: accounts,
        remotes: (folder) async => ['git@github.com:o/r.git'],
        issueSync: () => StashIssueSync.off,
      );
      await forge.sync();
      expect(store.notes, isEmpty);
    });

    test('a stash that links it, or was imported before, is the one', () async {
      final linked = await store.create(body: 'See $issueUrl');
      await store.update(
        linked.id,
        (note) => note.issues.add(StashIssueLink(url: issueUrl)),
      );
      final imported = await store.create(
        body:
            '[o/r#4 Dark mode](https://github.com/o/r/issues/4 "card")\n\n'
            'Mine now.',
      );
      await store.update(imported.id, (note) {
        note.title = 'Dark mode';
        note.issues.add(StashIssueLink(url: 'https://github.com/o/r/issues/4'));
      });
      await forge.sync();
      expect(store.notes, hasLength(2));
      final adopted = store.byId(imported.id)!;
      expect(adopted.issue, 'https://github.com/o/r/issues/4');
      // Not taken over: what differs stays till either changes.
      expect(adopted.issueText, 'Mine now.');
      expect(adopted.changedHere, isFalse);
    });

    test('changed there, it changes here; changed here, it waits to be '
        'pushed; both, the user chooses', () async {
      await forge.sync();
      final id = forge.stashOf(issueUrl)!.id;

      open[0] = issue(3, 'Uploads fail on 503', 'Every time.');
      await forge.sync();
      expect(store.byId(id)!.title, 'Uploads fail on 503');
      expect(store.byId(id)!.body, 'Every time.');
      expect(store.byId(id)!.changedHere, isFalse);

      await store.update(id, (note) => note.body = 'Every time, on Wi-Fi.');
      expect(store.byId(id)!.changedHere, isTrue);
      await forge.sync();
      expect(store.byId(id)!.body, 'Every time, on Wi-Fi.');
      expect(forge.remoteChanged(store.byId(id)!), isFalse);

      open[0] = issue(3, 'Uploads fail on 503', 'Every time, on 4G too.');
      await forge.sync();
      expect(store.byId(id)!.body, 'Every time, on Wi-Fi.');
      expect(forge.remoteChanged(store.byId(id)!), isTrue);

      http.on('PATCH', 'https://api.github.com/repos/o/r/issues/3', (request) {
        final json = request.json! as Map;
        return issue(3, json['title'] as String, json['body'] as String);
      });
      await forge.pushEdits(id);
      final patch = http.requests.lastWhere((r) => r.method == 'PATCH');
      expect(patch.json, {
        'title': 'Uploads fail on 503',
        'body': 'Every time, on Wi-Fi.',
      });
      expect(store.byId(id)!.changedHere, isFalse);
      expect(forge.remoteChanged(store.byId(id)!), isFalse);
    });

    test('its issue closed, it is done; opened again, it is not', () async {
      await forge.sync();
      final id = forge.stashOf(issueUrl)!.id;
      forge.start();
      await settle();

      issueState = 'closed';
      await forge.refresh(force: true);
      await settle();
      expect(store.byId(id)!.status, StashStatus.done);
      // Followed, not asked about.
      expect(forge.closedIssues(store.byId(id)!), isEmpty);

      // Found among the open ones again.
      issueState = 'open';
      await forge.sync();
      expect(store.byId(id)!.status, StashStatus.collected);
    });

    test(
      'what is about the user told as theirs, the rest quieter; their '
      'own comments not news; one gone and another written still is',
      () async {
        Map<String, Object?> by(String login, Map<String, Object?> issue) => {
          ...issue,
          'user': {'login': login},
        };
        var said = <String, List<Map<String, Object?>>>{};
        Map<String, Object?> comment(String login, String body, int minute) => {
          'user': {'login': login},
          'body': body,
          'created_at': '2026-10-23T10:${'$minute'.padLeft(2, '0')}:00Z',
        };
        for (final number in [3, 4]) {
          http.on(
            'GET',
            'https://api.github.com/repos/o/r/issues/$number/comments',
            (_) => said['$number'] ?? const [],
          );
        }
        open = [
          by('leo', issue(3, 'Uploads fail', 'On 503.')),
          by('ana', issue(4, 'Dark mode', '')),
        ];
        await forge.sync();
        final mine = forge.stashOf(issueUrl)!.id;
        final theirs = forge.stashOf('https://github.com/o/r/issues/4')!.id;

        // The user's own comment; another's on another's issue.
        said = {
          '3': [comment('leo', 'Looking into it.', 1)],
          '4': [comment('bob', 'Same here.', 2)],
        };
        open = [
          {...open[0], 'comments': 1, 'updated_at': '2026-10-23T10:01:00Z'},
          {...open[1], 'comments': 1, 'updated_at': '2026-10-23T10:02:00Z'},
        ];
        await forge.sync();
        expect(store.byId(mine)!.news, isNull);
        expect(store.byId(theirs)!.news, StashNews.commented);
        expect(store.byId(theirs)!.newsMine, isFalse);
        await forge.seen(theirs);

        // Naming the user: theirs.
        said['4'] = [...said['4']!, comment('bob', 'cc @leo', 3)];
        open[1] = {
          ...open[1],
          'comments': 2,
          'updated_at': '2026-10-23T10:03:00Z',
        };
        await forge.sync();
        expect(store.byId(theirs)!.news, StashNews.commented);
        expect(store.byId(theirs)!.newsMine, isTrue);
        expect(
          StashNote.decode(theirs, store.byId(theirs)!.encode()).newsMine,
          isTrue,
        );
        await forge.seen(theirs);
        expect(store.byId(theirs)!.newsMine, isFalse);

        // Another's on the user's issue: theirs; one gone and another
        // written, as many as before.
        said['3'] = [...said['3']!, comment('carl', 'Fails for me too.', 4)];
        open[0] = {
          ...open[0],
          'comments': 2,
          'updated_at': '2026-10-23T10:04:00Z',
        };
        await forge.sync();
        expect(store.byId(mine)!.news, StashNews.commented);
        expect(store.byId(mine)!.newsMine, isTrue);
        await forge.seen(mine);
        said['3'] = [said['3']!.last, comment('dan', 'And here.', 5)];
        open[0] = {...open[0], 'updated_at': '2026-10-23T10:05:00Z'};
        await forge.sync();
        expect(store.byId(mine)!.news, StashNews.commented);

        // Marked to come back to, and seen.
        await forge.seen(mine);
        await forge.markUnseen(mine);
        expect(store.byId(mine)!.news, StashNews.marked);
        expect(store.byId(mine)!.newsMine, isTrue);
      },
    );

    test('what is new about them is told till seen: one opened since, '
        'changed there, commented on, closed; not what the user did', () async {
      await forge.sync();
      expect([for (final note in store.notes) note.news], [null, null]);
      final id = forge.stashOf(issueUrl)!.id;

      open = [...open, issue(5, 'New one', '')];
      await forge.sync();
      expect(
        forge.stashOf('https://github.com/o/r/issues/5')!.news,
        StashNews.opened,
      );
      expect(store.byId(id)!.news, isNull);

      open[0] = issue(3, 'Uploads fail on 503', 'On 503.');
      await forge.sync();
      expect(store.byId(id)!.news, StashNews.changed);
      await forge.seen(id);
      expect(store.byId(id)!.news, isNull);
      // In its file too.
      expect(StashNote.decode(id, store.byId(id)!.encode()).news, isNull);

      open[0] = {...issue(3, 'Uploads fail on 503', 'On 503.'), 'comments': 2};
      await forge.sync();
      expect(store.byId(id)!.news, StashNews.commented);
      expect(store.byId(id)!.issueOf(issueUrl)!.comments, 2);
      expect(
        StashNote.decode(id, store.byId(id)!.encode()).news,
        StashNews.commented,
      );
      await forge.seen(id);

      open[0] = {...open[0], 'state': 'closed'};
      await forge.sync();
      expect(store.byId(id)!.status, StashStatus.done);
      expect(store.byId(id)!.news, StashNews.closed);
      await forge.seen(id);

      // Opened again, then closed by the user here: theirs, not news.
      open[0] = {...open[0], 'state': 'open'};
      await forge.sync();
      expect(store.byId(id)!.news, StashNews.reopened);
      await forge.seen(id);
      issueState = 'open';
      http.on(
        'GET',
        'https://api.github.com/repos/o/r/issues/3',
        (_) => {...open[0], 'state': issueState},
      );
      await forge.write(id, issueUrl, text: 'Done.', close: true);
      expect(store.byId(id)!.issueOf(issueUrl)!.state, 'closed');
      expect(store.byId(id)!.news, isNull);
    });

    test('merged into another, its issue is offered to be closed as that '
        'one\'s duplicate, and so closed', () async {
      await forge.sync();
      final kept = forge.stashOf(issueUrl)!.id;
      final merged = forge.stashOf('https://github.com/o/r/issues/4')!.id;
      await store.merge([kept, merged]);
      final note = store.byId(kept)!;
      final link = note.issueOf('https://github.com/o/r/issues/4')!;
      expect(link.mergedFrom, merged);
      expect(forge.duplicateIssues(note), [link]);
      // Not asked twice, as done.
      await store.update(kept, (note) => note.status = StashStatus.done);
      expect(forge.openIssues(store.byId(kept)!).map((l) => l.url), [issueUrl]);

      var closed = false;
      http
        ..on(
          'POST',
          'https://api.github.com/repos/o/r/issues/4/comments',
          (_) => {},
        )
        ..on('PATCH', 'https://api.github.com/repos/o/r/issues/4', (_) {
          closed = true;
          return {};
        })
        ..on(
          'GET',
          'https://api.github.com/repos/o/r/issues/4',
          (_) => {
            ...issue(4, 'Dark mode', ''),
            'state': closed ? 'closed' : 'open',
          },
        );
      await forge.write(
        kept,
        link.url,
        text: 'Duplicate of #3',
        close: true,
        duplicate: true,
      );
      final patch = http.requests.lastWhere((r) => r.method == 'PATCH');
      expect(patch.url.path, '/repos/o/r/issues/4');
      expect(patch.json, {'state': 'closed', 'state_reason': 'not_planned'});
      expect(forge.duplicateIssues(store.byId(kept)!), isEmpty);
    });

    test(
      'its issue\'s last comments, the latest page and the one before',
      () async {
        open[0] = {...open[0], 'comments': 7};
        await forge.sync();
        final pages = <String?>[];
        http.on(
          'GET',
          '$issueUrl/comments'.replaceFirst(
            'https://github.com/',
            'https://api.github.com/repos/',
          ),
          (request) {
            final page = request.url.queryParameters['page'];
            pages.add(page);
            final numbers = page == '2' ? [6, 7] : [1, 2, 3, 4, 5];
            return [
              for (final n in numbers)
                {
                  'user': {'login': 'u$n'},
                  'body': 'Comment $n',
                  'created_at': '2026-10-0${n}T10:00:00Z',
                  'html_url': '$issueUrl#issuecomment-$n',
                },
            ];
          },
        );
        final comments = await forge.commentsOf(issueUrl);
        expect(pages, ['2', '1']);
        expect(
          [for (final c in comments) c.author],
          ['u3', 'u4', 'u5', 'u6', 'u7'],
        );
        // Asked lately: not again.
        await forge.commentsOf(issueUrl);
        expect(pages, hasLength(2));
      },
    );

    test('kept local: no issue, and not made one again', () async {
      await forge.sync();
      final id = forge.stashOf(issueUrl)!.id;
      await forge.keepLocal(id);
      final note = store.byId(id)!;
      expect(note.ownIssue, isNull);
      expect(note.local, isTrue);
      expect(note.issues, isEmpty);
      await forge.sync();
      expect(store.notes, hasLength(2));
    });
  });

  test('published: its pictures put where the issue shows them, its other '
      'files their names', () async {
    final note = await store.create(body: 'x', project: '~/code/baocode');
    final picture = await store.disk.writeAsset(
      note.id,
      'shot.png',
      Uint8List.fromList([1, 2, 3]),
    );
    final file = await store.disk.writeAsset(
      note.id,
      'log.txt',
      Uint8List.fromList([4]),
    );
    await store.update(note.id, (note) {
      note
        ..title = 'Crash on save'
        ..body =
            'It crashes.\n\n![]($picture)\n\nSee [the log]($file) and '
            '[docs](https://example.com/d).';
    });
    expect(StashForge.localPictures(store.byId(note.id)!.body), 1);
    expect(await forge.reposOf('~/code/baocode'), [
      ForgeRepo(kind: ForgeKind.github, host: 'github.com', path: 'o/r'),
    ]);
    http
      ..on(
        'GET',
        'https://api.github.com/repos/o/r/branches/baocode-stash-assets',
        (_) => {},
      )
      ..on('POST', 'https://api.github.com/repos/o/r/issues', (request) {
        final json = request.json! as Map;
        return {
          'number': 9,
          'title': json['title'],
          'body': json['body'],
          'state': 'open',
        };
      })
      ..fallback = (request) => request.method == 'PUT'
          ? {'content': {}}
          : const ForgeResponse(404, '{}');
    await forge.publish(
      note.id,
      const ForgeRepo(kind: ForgeKind.github, host: 'github.com', path: 'o/r'),
    );
    final put = http.requests.singleWhere((r) => r.method == 'PUT');
    expect(put.url.path, startsWith('/repos/o/r/contents/stash/'));
    final post = http.requests.singleWhere((r) => r.method == 'POST');
    final body = (post.json! as Map)['body'] as String;
    expect(
      body,
      contains('![](https://github.com/o/r/blob/baocode-stash-assets/stash/'),
    );
    expect(body, contains('See the log and [docs](https://example.com/d).'));
    final published = store.byId(note.id)!;
    expect(published.issue, 'https://github.com/o/r/issues/9');
    expect(published.issues.first.url, 'https://github.com/o/r/issues/9');
    // Its text here as it was, pictures and all.
    expect(published.body, contains('![]($picture)'));
    expect(published.changedHere, isFalse);
  });

  test('a workspace\'s folders are its repositories; a folder\'s own '
      'project has its issues first', () async {
    final workspace = Workspace(
      projects: const [Project('api', '/code/api')],
      workspaceDirectories: FakeWorkspaceDirectories(),
    );
    final made = workspace.createWorkspace('web', ['/code/site', '/code/api'])!;
    forge.dispose();
    forge = StashForge(
      store: store,
      workspace: workspace,
      accounts: accounts,
      remotes: (folder) async => switch (folder) {
        '/code/site' => ['https://github.com/o/site.git'],
        '/code/api' => ['git@github.com:o/api.git'],
        _ => const [],
      },
    );
    expect(forge.foldersOf(made.path), ['/code/site', '/code/api']);
    expect(
      [for (final repo in await forge.reposOf(made.path)) repo.path],
      ['o/site', 'o/api'],
    );
    expect(
      {
        for (final (:repo, :project) in await forge.repositories())
          repo.path: project.path,
      },
      {'o/site': made.path, 'o/api': '/code/api'},
    );
  });

  test('all of a repository\'s issues, page by page', () async {
    http.on('GET', 'https://api.github.com/repos/o/r/issues', (request) {
      final page = int.parse(request.url.queryParameters['page']!);
      return [
        for (var i = 0; i < (page == 1 ? ForgeApi.pageSize : 3); i++)
          {'number': page * 1000 + i, 'title': 'T', 'state': 'open'},
      ];
    });
    final items = await accounts
        .apiFor('github.com')!
        .allIssues(
          const ForgeRepo(
            kind: ForgeKind.github,
            host: 'github.com',
            path: 'o/r',
          ),
        );
    expect(items, hasLength(ForgeApi.pageSize + 3));
  });

  test('a pull request of it failing, changes asked of it, merged: told, '
      'and asked about', () async {
    var checks = 'success';
    var review = 'APPROVED';
    var merged = false;
    http
      ..on(
        'GET',
        'https://api.github.com/repos/o/r/pulls/7',
        (_) => {
          'number': 7,
          'title': 'Retry uploads',
          'state': merged ? 'closed' : 'open',
          'merged_at': merged ? '2026-10-23T10:00:00Z' : null,
          'user': {'login': 'leo'},
          'head': {'sha': 'abc', 'ref': 'retry'},
        },
      )
      ..on(
        'GET',
        'https://api.github.com/repos/o/r/commits/abc/check-runs',
        (_) => {
          'check_runs': [
            {'status': 'completed', 'conclusion': checks},
          ],
        },
      )
      ..on(
        'GET',
        'https://api.github.com/repos/o/r/pulls/7/reviews',
        (_) => [
          {
            'state': review,
            'user': {'login': 'ana'},
          },
        ],
      );
    final note = await store.create(body: 'Fixed in $pullUrl');
    forge.start();
    await settle();
    expect(store.byId(note.id)!.news, isNull);
    expect(forge.pullsToFix(store.byId(note.id)!), isEmpty);

    checks = 'failure';
    await forge.refresh(force: true);
    await settle();
    expect(store.byId(note.id)!.news, StashNews.checksFailed);
    expect(store.byId(note.id)!.newsMine, isTrue);
    expect(forge.pullsToFix(store.byId(note.id)!).single.url, pullUrl);
    await forge.seen(note.id);
    await forge.answer(note.id, [pullUrl]);
    expect(forge.pullsToFix(store.byId(note.id)!), isEmpty);

    // Asked anew: changes asked for now.
    review = 'CHANGES_REQUESTED';
    await forge.refresh(force: true);
    await settle();
    expect(store.byId(note.id)!.news, StashNews.changesRequested);
    expect(forge.pullsToFix(store.byId(note.id)!), hasLength(1));
    await forge.seen(note.id);

    merged = true;
    await forge.refresh(force: true);
    await settle();
    expect(store.byId(note.id)!.news, StashNews.merged);
    expect(forge.pullsToFix(store.byId(note.id)!), isEmpty);
    expect(forge.mergedPulls(store.byId(note.id)!).single.url, pullUrl);
  });

  test('the linked issues asked a few at a time, not all at once', () async {
    http.fallback = (request) {
      final number = int.parse(request.url.pathSegments.last);
      return {'number': number, 'title': 'Issue $number', 'state': 'open'};
    };
    final counting = _CountingHttp(http);
    final accounts = ForgeAccounts(
      http: counting,
      secrets: MemorySecretStore(),
    );
    await accounts.signInWithToken(ForgeKind.github, 'github.com', 't');
    final forge = StashForge(
      store: store,
      workspace: Workspace.mock(),
      accounts: accounts,
      remotes: (_) async => const [],
    );
    addTearDown(forge.dispose);
    final urls = [
      for (var i = 101; i <= 120; i++) 'https://github.com/o/r/issues/$i',
    ];
    final note = await store.create(body: 'Many');
    await store.update(note.id, (note) {
      note.issues.addAll([for (final url in urls) StashIssueLink(url: url)]);
    });
    counting.most = 0;
    await forge.refresh();
    expect(counting.most, StashForge.atOnce);
    for (final url in urls) {
      expect(forge.itemOf(url)?.title, startsWith('Issue '), reason: url);
    }
  });

  test('the pull requests a conversation links to', () {
    expect(
      stashPullsIn([
        const UserMessageItem(text: 'see $pullUrl'),
        const AssistantTextItem('Opened $pullUrl and read $issueUrl.'),
        const ToolCallItem(
          kind: ToolKind.command,
          target: 'gh pr create',
          output: 'https://gitlab.com/g/app/-/merge_requests/4\n',
        ),
      ]),
      [pullUrl, 'https://gitlab.com/g/app/-/merge_requests/4'],
    );
  });
}
