import 'dart:async';
import 'dart:math' show max;

import 'package:flutter/foundation.dart';

import '../forge/forge_accounts.dart';
import '../forge/forge_api.dart';
import '../forge/forge_io_stub.dart'
    if (dart.library.io) '../forge/forge_io.dart'
    as io;
import '../forge/forge_ref.dart';
import '../remote/remote_location.dart';
import '../workspace/workspace.dart';
import 'stash_settings.dart';
import 'stash_note.dart';
import 'stash_store.dart';

/// The stashes' issues and pull requests (docs/stash.md): linked from
/// their text (a link pasted, an issue imported) and from their
/// conversations (see StashThreads); how each is now, asked of its forge
/// as the user (see [ForgeAccounts]) and kept with the link for when it
/// cannot be; what that asks of the user (an issue closed: is the stash
/// done? the stash done: say so on the issue?); and what the user then
/// writes there, only once they confirm it.
class StashForge extends ChangeNotifier {
  StashForge({
    required this.store,
    required this.workspace,
    required this.accounts,
    DateTime Function()? clock,
    Future<List<String>> Function(String folder)? remotes,
    StashIssueSync Function()? issueSync,
  }) : _clock = clock ?? DateTime.now,
       _remotes = remotes ?? io.gitRemoteUrls,
       _issueSync = issueSync ?? (() => StashIssueSync.all);

  /// The app's, once main() has made it.
  static StashForge? current;

  final StashStore store;
  final Workspace workspace;
  final ForgeAccounts accounts;
  final DateTime Function() _clock;
  final Future<List<String>> Function(String folder) _remotes;
  final StashIssueSync Function() _issueSync;

  bool _started = false;
  bool _disposed = false;
  Timer? _timer;

  /// How often what is linked is asked again while the app runs.
  static const refreshEvery = Duration(minutes: 5);

  /// How long an answer is taken as current.
  static const fresh = Duration(seconds: 60);

  void start() {
    if (_started) return;
    _started = true;
    store.addListener(_storeChanged);
    accounts.addListener(_accountsChanged);
    _timer = Timer.periodic(refreshEvery, (_) {
      unawaited(refresh());
      unawaited(sync());
    });
    _storeChanged();
    unawaited(store.load().then((_) => sync()));
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    if (_started) {
      store.removeListener(_storeChanged);
      accounts.removeListener(_accountsChanged);
    }
    super.dispose();
  }

  /// [url]'s issue or pull request, if it is one (on a host known).
  ForgeRef? refOf(String url) => ForgeRef.parse(url, kindOf: accounts.kindOf);

  /// [url]'s issue or pull request as last asked this run; null before.
  ForgeItem? itemOf(String url) => _items[url];
  final Map<String, ForgeItem> _items = {};

  /// Why [url] could not be asked last time, if it could not.
  ForgeException? failureOf(String url) => _failures[url];
  final Map<String, ForgeException> _failures = {};

  /// When each link was last asked.
  final Map<String, DateTime> _asked = {};

  /// Whether [url]'s forge has an account to ask it with.
  bool canAsk(String url) => switch (refOf(url)) {
    final ref? => accounts.apiOf(ref) != null,
    null => false,
  };

  // --- Linked from the text ------------------------------------------------------

  bool _collecting = false;

  void _storeChanged() {
    if (_disposed || !store.loaded || _collecting) return;
    unawaited(_collect());
  }

  void _accountsChanged() {
    _failures.clear();
    _asked.clear();
    _syncedAt.clear();
    _syncFailures.clear();
    notifyListeners();
    unawaited(_collect());
    unawaited(sync());
  }

  /// Links each stash to the issues and pull requests its text links to,
  /// then asks those not asked lately.
  Future<void> _collect() async {
    _collecting = true;
    try {
      final adding = <int, List<String>>{};
      for (final note in store.notes) {
        for (final ref in ForgeRef.allIn(note.body, kindOf: accounts.kindOf)) {
          final url = ref.url.toString();
          if (note.issueOf(url) == null) (adding[note.id] ??= []).add(url);
        }
      }
      if (adding.isNotEmpty) {
        // What an agent wrote meanwhile, read before it is written over.
        await store.reload();
        for (final MapEntry(key: id, value: urls) in adding.entries) {
          final note = store.byId(id);
          if (note == null) continue;
          for (final url in urls) {
            if (note.issueOf(url) == null) {
              note.issues.add(StashIssueLink(url: url));
            }
          }
          await store.save(note, touch: false);
        }
      }
    } finally {
      _collecting = false;
    }
    await refresh();
  }

  // --- How they are now ----------------------------------------------------------

  Future<void>? _refreshing;

  /// Asks the forges how the linked issues and pull requests are now: of
  /// stashes not done, and of those done that are still open (to ask the
  /// user about them); each at most once in [fresh] unless [force]d.
  Future<void> refresh({bool force = false}) => force
      ? _refresh(true)
      : _refreshing ??= _refresh(false).whenComplete(() => _refreshing = null);

  /// Asks [id]'s stash's again, now (shown, it should be current); even
  /// those asked lately when [force]d.
  Future<void> refreshNote(int id, {bool force = false}) async {
    final note = store.byId(id);
    if (note == null) return;
    await _ask([for (final link in note.issues) link.url], force: force);
  }

  Future<void> _refresh(bool force) => _ask([
    for (final note in store.notes)
      for (final link in note.issues)
        if (note.status != StashStatus.done ||
            !link.answered &&
                (link.state != 'closed' && link.state != 'merged'))
          link.url,
  ], force: force);

  Future<void> _ask(List<String> urls, {required bool force}) async {
    final now = _clock();
    final asking = {
      for (final url in urls)
        if (force || !(_asked[url]?.isAfter(now.subtract(fresh)) ?? false)) url,
    };
    final answers = <String, ForgeItem>{};
    final started = asking.difference(_inFlight);
    if (started.isNotEmpty) {
      _inFlight.addAll(started);
      notifyListeners();
    }
    await _eachAtOnce(
      [
        for (final url in asking)
          if (refOf(url) case final ref?)
            if (accounts.apiOf(ref) case final api?) (url, ref, api),
      ],
      (each) async {
        final (url, ref, api) = each;
        try {
          answers[url] = await api.item(ref);
          _failures.remove(url);
        } on Object catch (error) {
          _failures[url] = error is ForgeException
              ? error
              : ForgeException('$error');
        } finally {
          _asked[url] = now;
        }
      },
    );
    _inFlight.removeAll(started);
    if (_disposed) return;
    _items.addAll(answers);
    notifyListeners();
    await _keep(answers);
  }

  /// How many requests go to the forges at once: the stashes link many
  /// issues (more than a thousand, some), and asked all at once a forge
  /// refuses them (GitHub's secondary rate limit).
  static const atOnce = 6;

  /// [ask]s each of [items], [atOnce] of them at a time; the rest let be
  /// once disposed. [ask] throws nothing.
  Future<void> _eachAtOnce<T>(
    List<T> items,
    Future<void> Function(T item) ask,
  ) async {
    final next = items.iterator;
    Future<void> asking() async {
      while (!_disposed && next.moveNext()) {
        await ask(next.current);
      }
    }

    await Future.wait([
      for (var i = 0; i < atOnce && i < items.length; i++) asking(),
    ]);
  }

  /// Whether [url] is being asked now (its row shows it loading).
  bool asking(String url) => _inFlight.contains(url);
  final Set<String> _inFlight = {};

  /// Keeps what [answers] say with the links (their title, state and
  /// checks), for when they cannot be asked; and a stash's own issue's
  /// with the stash (see [_takeOwn]).
  Future<void> _keep(Map<String, ForgeItem> answers) async {
    if (answers.isEmpty) return;
    bool differs(StashIssueLink link, ForgeItem item) =>
        link.title != item.title ||
        link.state != item.state.name ||
        link.checks != item.checks?.name ||
        link.review != item.review?.name ||
        link.comments != item.comments ||
        link.updated != item.updated?.toIso8601String();
    bool ownDiffers(StashNote note) => switch (note.ownIssue) {
      final url? => switch (answers[url]) {
        final item? => _remoteHash(item) != note.syncedRemote,
        null => false,
      },
      null => false,
    };
    if (!store.notes.any(
      (note) =>
          ownDiffers(note) ||
          note.issues.any(
            (link) => switch (answers[link.url]) {
              final item? => differs(link, item),
              null => false,
            },
          ),
    )) {
      return;
    }
    // Who wrote what is new on them, whether it names the user: asked
    // before the stashes are read anew, not while they are.
    final said = await _newComments(answers);
    await store.reload();
    for (final note in store.notes) {
      var changed = false;
      final own = note.ownIssue;
      for (final (i, link) in note.issues.indexed) {
        final item = answers[link.url];
        if (item == null || !differs(link, item)) continue;
        // The user's own doing, here: not news to them.
        final writing = _writing.contains(link.url);
        final about = _aboutMe(item, session: link.session);
        // Its own issue closed or opened again: so is it.
        if (link.url == own && link.state != null) {
          final was = ForgeState.parse(link.state)?.isOpen;
          if (was == true && !item.state.isOpen) {
            note.status = StashStatus.done;
            if (!writing) note.tell(StashNews.closed, mine: about);
          } else if (was == false && item.state.isOpen) {
            if (note.status == StashStatus.done) {
              note.status = note.threads.isNotEmpty
                  ? StashStatus.implementing
                  : StashStatus.collected;
            }
            if (!writing) note.tell(StashNews.reopened, mine: about);
          }
        }
        // A pull request of it: merged, closed, failing, changes asked.
        if (item.ref.kind == ForgeItemKind.pull &&
            link.state != null &&
            !writing) {
          final was = ForgeState.parse(link.state);
          if (was != ForgeState.merged && item.state == ForgeState.merged) {
            note.tell(StashNews.merged, mine: about);
          } else if ((was?.isOpen ?? false) &&
              item.state == ForgeState.closed) {
            note.tell(StashNews.closed, mine: about);
          }
          if (item.checks == ForgeChecks.failure &&
              link.checks != ForgeChecks.failure.name) {
            note.tell(StashNews.checksFailed, mine: about);
          }
          if (item.review == ForgeReview.changesRequested &&
              link.review != ForgeReview.changesRequested.name) {
            note.tell(StashNews.changesRequested, mine: about);
          }
        }
        // Said more about: by others (theirs as far as known).
        final comments = said[link.url];
        if (!writing && _followed(note, link)) {
          if (comments != null) {
            if (comments.others.isNotEmpty) {
              final me = _me(item.ref);
              note.tell(
                StashNews.commented,
                mine:
                    about ||
                    me != null &&
                        comments.others.any(
                          (comment) => _names(comment.body, me),
                        ),
              );
            }
          } else if (link.comments != null && item.comments > link.comments!) {
            note.tell(StashNews.commented, mine: about);
          }
        }
        note.issues[i] = StashIssueLink(
          url: link.url,
          title: item.title,
          state: item.state.name,
          checks: item.checks?.name,
          session: link.session,
          // What it asks, changed, asks anew.
          answered:
              link.state == item.state.name &&
              link.checks == item.checks?.name &&
              link.review == item.review?.name &&
              link.answered,
          comments: item.comments,
          mergedFrom: link.mergedFrom,
          review: item.review?.name,
          updated: item.updated?.toIso8601String(),
          commentAt: comments?.latest?.toIso8601String() ?? link.commentAt,
        );
        changed = true;
      }
      if (own != null) {
        if (answers[own] case final item?) changed |= _takeOwn(note, item);
      }
      if (changed) await store.save(note, touch: false);
    }
  }

  /// Whether what is new on [link] is told: [note]'s own issue's, its
  /// pull requests'.
  bool _followed(StashNote note, StashIssueLink link) =>
      link.url == note.ownIssue || refOf(link.url)?.kind == ForgeItemKind.pull;

  /// The user, as [ref]'s forge knows them.
  String? _me(ForgeRef ref) => accounts.accountFor(ref.repo.host)?.login;

  /// Whether [item] is the user's: theirs, assigned to them, or (a pull
  /// request) opened from their conversation, [session].
  bool _aboutMe(ForgeItem item, {String? session}) {
    if (session != null) return true;
    final me = _me(item.ref);
    if (me == null) return false;
    bool same(String? login) => login?.toLowerCase() == me.toLowerCase();
    return same(item.author) || item.assignees.any(same);
  }

  /// Whether [text] names [me]: `@me`.
  static bool _names(String text, String me) => RegExp(
    '(?:^|[^\\w@/])@${RegExp.escape(me)}(?![\\w-])',
    caseSensitive: false,
  ).hasMatch(text);

  /// The comments new on the links [answers] are of that are followed
  /// (see [_followed]): more of them than kept, or (as many) it changed
  /// otherwise unseen, one perhaps gone and another written. Those not by
  /// the user, and when the latest was written; none where they could
  /// not be asked (then told by their number).
  Future<Map<String, ({List<ForgeComment> others, DateTime? latest})>>
  _newComments(Map<String, ForgeItem> answers) async {
    final asking = <String, StashIssueLink>{};
    for (final note in store.notes) {
      for (final link in note.issues) {
        final item = answers[link.url];
        final known = link.comments;
        if (item == null ||
            known == null ||
            item.comments == 0 ||
            _writing.contains(link.url) ||
            !_followed(note, link)) {
          continue;
        }
        final more = item.comments > known;
        final unseen =
            item.comments == known &&
            link.commentAt != null &&
            link.updated != null &&
            link.updated != item.updated?.toIso8601String() &&
            link.title == item.title &&
            link.state == item.state.name &&
            (link.url != note.ownIssue ||
                _remoteHash(item) == note.syncedRemote);
        if (more || unseen) asking[link.url] = link;
      }
    }
    final said = <String, ({List<ForgeComment> others, DateTime? latest})>{};
    await _eachAtOnce(
      [
        for (final MapEntry(key: url, value: link) in asking.entries)
          if (refOf(url) case final ref?)
            if (accounts.apiOf(ref) case final api?) (url, link, ref, api),
      ],
      (each) async {
        final (url, link, ref, api) = each;
        final item = answers[url]!;
        try {
          final comments = await api.comments(ref, total: item.comments);
          _comments[url] = (
            at: _clock(),
            total: item.comments,
            comments: Future.value(comments),
          );
          final after = DateTime.tryParse(link.commentAt ?? '');
          final fresh = after == null
              ? comments.sublist(
                  max(0, comments.length - (item.comments - link.comments!)),
                )
              : [
                  for (final comment in comments)
                    if (comment.created?.isAfter(after) ?? false) comment,
                ];
          final me = _me(ref)?.toLowerCase();
          said[url] = (
            others: [
              for (final comment in fresh)
                if (comment.author.toLowerCase() != me) comment,
            ],
            latest: comments.lastOrNull?.created ?? after,
          );
        } on Object {
          // Told by their number.
        }
      },
    );
    return said;
  }

  static String _remoteHash(ForgeItem item) =>
      StashNote.syncHash(item.title, item.body);

  /// [note] as its own issue [item] is, if the issue changed since they
  /// were last the same and the stash did not; else as it was (the two
  /// the same since, it is noted; both changed, the user chooses: see
  /// [remoteChanged]). Whether it changed.
  bool _takeOwn(StashNote note, ForgeItem item) {
    final remote = _remoteHash(item);
    if (remote == note.syncedRemote) return false;
    final local = StashNote.syncHash(note.title, note.issueText);
    if (local == remote) {
      note
        ..synced = local
        ..syncedRemote = remote;
      return true;
    }
    if (note.changedHere) return false;
    // Changed since it was last seen the same: news (not the first time).
    if (note.syncedRemote != null) {
      note.tell(StashNews.changed, mine: _aboutMe(item));
    }
    note
      ..title = item.title
      ..body = note.withIssueText(item.body)
      ..synced = StashNote.syncHash(item.title, note.issueText)
      ..syncedRemote = remote;
    return true;
  }

  /// Whether [note]'s issue changed since they were last the same (as last
  /// asked): with [StashNote.changedHere], the two to be chosen between.
  bool remoteChanged(StashNote note) {
    final own = note.ownIssue;
    if (own == null || note.syncedRemote == null) return false;
    final item = _items[own];
    return item != null && _remoteHash(item) != note.syncedRemote;
  }

  /// [link]'s state: as just asked, else as kept.
  ForgeState? stateOf(StashIssueLink link) =>
      _items[link.url]?.state ?? ForgeState.parse(link.state);

  // --- What they ask of the user -------------------------------------------------

  /// [note]'s issues closed while it is not done: is it? (Not its own:
  /// it follows that one.)
  List<StashIssueLink> closedIssues(StashNote note) => [
    if (note.status != StashStatus.done)
      for (final link in note.issues)
        if (!link.answered &&
            link.url != note.ownIssue &&
            refOf(link.url)?.kind == ForgeItemKind.issue &&
            stateOf(link) == ForgeState.closed)
          link,
  ];

  /// [note]'s issues still open though it is done: say so there?
  List<StashIssueLink> openIssues(StashNote note) => [
    if (note.status == StashStatus.done)
      for (final link in note.issues)
        if (!link.answered &&
            // Asked of as duplicates, by [duplicateIssues].
            (link.mergedFrom == null || link.url == note.ownIssue) &&
            refOf(link.url)?.kind == ForgeItemKind.issue &&
            (stateOf(link)?.isOpen ?? false) &&
            canAsk(link.url))
          link,
  ];

  /// [note]'s pull requests still open whose checks failed, or of which
  /// changes were asked: to be fixed, where they were made?
  List<StashIssueLink> pullsToFix(StashNote note) => [
    for (final link in note.issues)
      if (!link.answered &&
          refOf(link.url)?.kind == ForgeItemKind.pull &&
          (stateOf(link)?.isOpen ?? false) &&
          (checksOf(link) == ForgeChecks.failure ||
              reviewOf(link) == ForgeReview.changesRequested))
        link,
  ];

  /// [note]'s pull requests merged while it is not done: is it?
  List<StashIssueLink> mergedPulls(StashNote note) => [
    if (note.status != StashStatus.done)
      for (final link in note.issues)
        if (!link.answered &&
            refOf(link.url)?.kind == ForgeItemKind.pull &&
            stateOf(link) == ForgeState.merged)
          link,
  ];

  /// [link]'s checks, [review]: as just asked, else as kept.
  ForgeChecks? checksOf(StashIssueLink link) => _items.containsKey(link.url)
      ? _items[link.url]!.checks
      : ForgeChecks.parse(link.checks);
  ForgeReview? reviewOf(StashIssueLink link) => _items.containsKey(link.url)
      ? _items[link.url]!.review
      : ForgeReview.parse(link.review);

  /// The conversation [session] is, if it is listed.
  AgentThread? threadOf(String session) {
    for (final thread in workspace.threads) {
      if (thread.id == session) return thread;
    }
    return null;
  }

  /// [note]'s issues that were those of stashes merged into it, still
  /// open: the same thing, to close as its duplicates? (Asked once.)
  List<StashIssueLink> duplicateIssues(StashNote note) => [
    for (final link in note.issues)
      if (link.mergedFrom != null &&
          !link.answered &&
          link.url != note.ownIssue &&
          refOf(link.url)?.kind == ForgeItemKind.issue &&
          (stateOf(link)?.isOpen ?? false) &&
          canAsk(link.url))
        link,
  ];

  /// [url]'s last comments, as asked lately (in [fresh]); asked again when
  /// [force]d, or when it has more than then. [total], how many it has as
  /// last synced, where it was not asked since.
  Future<List<ForgeComment>> commentsOf(
    String url, {
    bool force = false,
    int? total,
  }) {
    final ref = refOf(url);
    final api = ref == null ? null : accounts.apiOf(ref);
    if (ref == null || api == null) {
      return Future.error(const ForgeException('Not signed in.', status: 401));
    }
    total = _items[url]?.comments ?? total;
    final known = _comments[url];
    if (!force &&
        known != null &&
        known.total == total &&
        _clock().difference(known.at) < fresh) {
      return known.comments;
    }
    final asked = api.comments(ref, total: total);
    _comments[url] = (at: _clock(), total: total, comments: asked);
    // Failed: asked again next time.
    unawaited(
      asked.then<void>(
        (_) {},
        onError: (Object _) {
          if (identical(_comments[url]?.comments, asked)) {
            _comments.remove(url);
          }
        },
      ),
    );
    return asked;
  }

  final Map<
    String,
    ({DateTime at, int? total, Future<List<ForgeComment>> comments})
  >
  _comments = {};

  /// [id]'s stash's news seen (its detail shown).
  Future<void> seen(int id) async {
    if (store.byId(id)?.news == null) return;
    await store.update(id, (note) => note.seen(), touch: false);
  }

  /// [id]'s stash marked as having news, to come back to.
  Future<void> markUnseen(int id) => store.update(
    id,
    (note) => note.tell(StashNews.marked, mine: true),
    touch: false,
  );

  /// What [links] of [id]'s stash asked was answered (or set aside).
  Future<void> answer(int id, Iterable<String> links) async {
    final urls = links.toSet();
    await store.reload();
    await store.update(id, (note) {
      for (final (i, link) in note.issues.indexed) {
        if (urls.contains(link.url)) {
          note.issues[i] = link.copyWith(answered: true);
        }
      }
    }, touch: false);
  }

  /// Unlinks [url] from [id]'s stash (its link in the text stays, and
  /// would link it again: taken out of the text too).
  Future<void> unlink(int id, String url) async {
    await store.reload();
    await store.update(id, (note) {
      note.issues.removeWhere((link) => link.url == url);
    }, touch: false);
  }

  // --- Written there, once confirmed ---------------------------------------------

  /// Comments [text] on [url]'s issue or pull request (when not empty),
  /// then closes it when [close] (an issue); as the user, who confirmed
  /// it. Throws [ForgeException].
  Future<void> write(
    int id,
    String url, {
    String text = '',
    bool close = false,
    bool duplicate = false,
  }) async {
    final ref = refOf(url);
    final api = ref == null ? null : accounts.apiOf(ref);
    if (ref == null || api == null) {
      throw const ForgeException('Not signed in.', status: 401);
    }
    // What changes there, from here till it is asked anew, the user's:
    // not news to them (a sync between asking too).
    _writing.add(url);
    try {
      if (text.trim().isNotEmpty) await api.comment(ref, text.trim());
      if (close && ref.kind == ForgeItemKind.issue) {
        await api.close(ref, duplicate: duplicate);
      }
      // As it is now first: a state changed asks anew, but this one the
      // user just answered.
      await _ask([url], force: true);
    } finally {
      _writing.remove(url);
    }
    await answer(id, [url]);
  }

  /// What the user is writing on: its changes theirs, not news.
  final Set<String> _writing = {};

  /// What should not go out in [text] before the user says so: paths on
  /// this machine, and what looks like a secret (an API key, a token, a
  /// private key).
  static List<String> sensitive(String text) => [
    for (final pattern in _sensitive)
      for (final match in pattern.allMatches(text)) match[0]!,
  ];

  static final _sensitive = [
    RegExp(
      r'(?:/Users|/home)/[^\s`"'
      ')]+',
    ),
    RegExp(
      r'[A-Za-z]:\\Users\\[^\s`"'
      ')]+',
    ),
    RegExp(r'\b(?:sk|pk|rk)-[A-Za-z0-9_-]{16,}'),
    RegExp(r'\b(?:ghp|gho|ghu|ghs|ghr|github_pat|glpat)[-_][A-Za-z0-9_]{16,}'),
    RegExp(r'\bAKIA[0-9A-Z]{16}\b'),
    RegExp(r'-----BEGIN [A-Z ]*PRIVATE KEY-----'),
  ];

  // --- Imported ------------------------------------------------------------------

  /// The folders [project] is: its own, or a workspace's (each of them
  /// may be a Git repository).
  List<String> foldersOf(String project) => [
    if (workspace.workspaceAt(project) case final workspace?)
      ...workspace.folders
    else
      project,
  ];

  /// The repositories [folder]'s Git remotes are (on hosts known): asked
  /// of Git once in [refreshEvery].
  Future<List<ForgeRepo>> _reposIn(String folder) async {
    if (RemoteLocation.isRemote(folder)) return const [];
    final now = _clock();
    final known = _remotesOf[folder];
    if (known != null && now.difference(known.at) < refreshEvery) {
      return known.repos;
    }
    final repos = <ForgeRepo>{};
    try {
      for (final remote in await _remotes(folder)) {
        if (ForgeRepo.fromRemote(remote, kindOf: accounts.kindOf)
            case final repo?) {
          repos.add(repo);
        }
      }
    } on Object catch (error) {
      debugPrint('stash: remotes of $folder: $error');
    }
    _remotesOf[folder] = (at: now, repos: repos.toList());
    return repos.toList();
  }

  final Map<String, ({DateTime at, List<ForgeRepo> repos})> _remotesOf = {};

  /// The repositories [project] is of (its folders' remotes): none where
  /// it is no Git repository (its stashes kept here).
  Future<List<ForgeRepo>> reposOf(String project) async =>
      {for (final folder in foldersOf(project)) ...await _reposIn(folder)}
          .toList();

  /// [project]'s repositories as last found, for what shows them at once:
  /// null till they are (asked then, and told when found).
  List<ForgeRepo>? knownReposOf(String project) {
    final folders = foldersOf(project);
    final now = _clock();
    final known = [
      for (final folder in folders)
        if (_remotesOf[folder] case final found?
            when now.difference(found.at) < refreshEvery)
          found.repos,
    ];
    if (known.length == folders.length) {
      return {for (final repos in known) ...repos}.toList();
    }
    if (_findingRepos.add(project)) {
      unawaited(
        reposOf(project).whenComplete(() {
          _findingRepos.remove(project);
          if (!_disposed) notifyListeners();
        }),
      );
    }
    return null;
  }

  final Set<String> _findingRepos = {};

  /// The repositories the projects are of (by their folders' Git remotes,
  /// on hosts known), each with its project: a folder's own, before a
  /// workspace it is in; those with an account first.
  Future<List<({ForgeRepo repo, Project project})>> repositories() async {
    final found = <ForgeRepo, Project>{};
    final projects = workspace.projects;
    for (final workspaces in [false, true]) {
      for (final project in projects) {
        if ((workspace.workspaceOf(project) != null) != workspaces) continue;
        for (final repo in await reposOf(project.path)) {
          found.putIfAbsent(repo, () => project);
        }
      }
    }
    final list = [
      for (final MapEntry(key: repo, value: project) in found.entries)
        (repo: repo, project: project),
    ];
    list.sort((a, b) {
      final signed =
          (accounts.accountFor(b.repo.host) != null ? 1 : 0) -
          (accounts.accountFor(a.repo.host) != null ? 1 : 0);
      return signed != 0 ? signed : a.repo.path.compareTo(b.repo.path);
    });
    return list;
  }

  // --- The projects' issues, as stashes ----------------------------------------

  Future<void>? _syncing;

  /// Whether [sync] is going on; [syncProgress] how far.
  bool get syncing => _syncing != null;

  /// The repositories [sync] went through, of how many, while it goes.
  ({int done, int total, ForgeRepo? repo})? get syncProgress => _progress;
  ({int done, int total, ForgeRepo? repo})? _progress;

  /// When [sync] last went through every repository.
  DateTime? get lastSynced => _lastSynced;
  DateTime? _lastSynced;

  /// Why each repository could not be synced last time, if it could not.
  Map<ForgeRepo, ForgeException> get syncFailures =>
      Map.unmodifiable(_syncFailures);
  final Map<ForgeRepo, ForgeException> _syncFailures = {};

  /// The projects' repositories on a forge the user is not signed in to:
  /// their issues not stashes till they are.
  List<ForgeRepo> get unsignedRepos => List.unmodifiable(_unsigned);
  List<ForgeRepo> _unsigned = const [];

  /// When each repository was last synced whole: after that, only what
  /// changed since is asked (closed ones among it).
  final Map<ForgeRepo, DateTime> _syncedAt = {};

  /// Makes the projects' open issues stashes (those the settings say: see
  /// [StashIssueSync]), each once: the stash its issue is, else one that
  /// links it, else a new one; never one whose stash was deleted, or that
  /// was unlinked from it ([StashStore.ignoredIssues]). Those already
  /// stashes are kept in step (see [_keep]). Every open one asked the
  /// first time, then those changed since; all again when [full].
  Future<void> sync({bool full = false}) {
    if (full) _syncedAt.clear();
    return _syncing ??= _sync().whenComplete(() {
      _syncing = null;
      _progress = null;
      if (!_disposed) notifyListeners();
    });
  }

  Future<void> _sync() async {
    final mode = _issueSync();
    if (_disposed || mode == StashIssueSync.off || !store.loaded) return;
    final repos = await repositories();
    final signed = [
      for (final entry in repos)
        if (accounts.apiFor(entry.repo.host) != null) entry,
    ];
    _unsigned = [
      for (final (:repo, project: _) in repos)
        if (accounts.apiFor(repo.host) == null) repo,
    ];
    _progress = (done: 0, total: signed.length, repo: null);
    notifyListeners();
    final answers = <String, ForgeItem>{};
    for (final (i, (:repo, :project)) in signed.indexed) {
      if (_disposed) return;
      final api = accounts.apiFor(repo.host)!;
      _progress = (done: i, total: signed.length, repo: repo);
      notifyListeners();
      final started = _clock();
      try {
        final since = _syncedAt[repo];
        final items = <String, ForgeItem>{};
        if (mode == StashIssueSync.all) {
          for (final item in await api.allIssues(
            repo,
            // A minute back: what changed as it was asked.
            since: since?.subtract(const Duration(minutes: 1)),
          )) {
            items[item.ref.url.toString()] = item;
          }
        } else {
          for (final filter in const [
            ForgeIssueFilter.assigned,
            ForgeIssueFilter.created,
          ]) {
            for (final item in await api.issues(repo, filter: filter)) {
              items[item.ref.url.toString()] = item;
            }
          }
        }
        for (final MapEntry(key: url, value: item) in items.entries) {
          if (_disposed) return;
          if (store.ignoredIssues.contains(url)) continue;
          if (stashOf(url) case final note?) {
            answers[url] = item;
            // Imported before it was kept: it is the issue.
            if (note.issue == null && note.ownIssue == url) {
              // Each as it is now: what changes after is kept in step
              // (what differs already, left as it is).
              await store.update(note.id, (note) {
                note
                  ..issue = url
                  ..synced = StashNote.syncHash(note.title, note.issueText)
                  ..syncedRemote = _remoteHash(item);
              }, touch: false);
            }
            continue;
          }
          // Closed before it was a stash: none.
          if (!item.state.isOpen) continue;
          // Not the first time: one opened since, news to the user.
          await _create(item, project: project.path, news: since != null);
        }
        _syncedAt[repo] = started;
        _syncFailures.remove(repo);
      } on ForgeException catch (error) {
        _syncFailures[repo] = error;
        debugPrint('stash: issues of ${repo.path}: ${error.message}');
      }
    }
    if (_disposed) return;
    _lastSynced = _clock();
    _items.addAll(answers);
    final now = _clock();
    for (final url in answers.keys) {
      _asked[url] = now;
    }
    notifyListeners();
    await _keep(answers);
  }

  /// A stash that is [item]'s issue, about [project]: its title and text
  /// the issue's.
  Future<StashNote> _create(
    ForgeItem item, {
    String? project,
    bool news = false,
  }) async {
    final url = item.ref.url.toString();
    final note = await store.create(body: item.body.trim(), project: project);
    await store.update(note.id, (note) {
      note
        ..title = item.title
        ..issue = url
        ..synced = StashNote.syncHash(item.title, item.body)
        ..syncedRemote = _remoteHash(item);
      if (news) {
        final me = _me(item.ref);
        note.tell(
          StashNews.opened,
          mine: _aboutMe(item) || me != null && _names(item.body, me),
        );
      }
      note.issues.add(
        StashIssueLink(
          url: url,
          title: item.title,
          state: item.state.name,
          comments: item.comments,
          updated: item.updated?.toIso8601String(),
        ),
      );
    }, touch: false);
    _items[url] = item;
    _asked[url] = _clock();
    return store.byId(note.id)!;
  }

  // --- Its issue, from the stash -------------------------------------------------

  /// [id]'s stash made an issue of [repo], as the user (who confirmed it):
  /// its pictures put where the issue can show them, links to its other
  /// files left as their names. Throws [ForgeException].
  Future<void> publish(int id, ForgeRepo repo) async {
    final api = accounts.apiFor(repo.host);
    final note = store.byId(id);
    if (api == null) throw const ForgeException('Not signed in.', status: 401);
    if (note == null || note.ownIssue != null) return;
    final title = note.displayTitle;
    final item = await api.createIssue(
      repo,
      title: title,
      body: await _outgoing(api, repo, note.issueText),
    );
    final url = item.ref.url.toString();
    _items[url] = item;
    _asked[url] = _clock();
    await store.reload();
    await store.update(id, (note) {
      note
        ..title = title
        ..issue = url
        ..local = false
        ..synced = StashNote.syncHash(title, note.issueText)
        ..syncedRemote = _remoteHash(item);
      note.issues.removeWhere((link) => link.url == url);
      note.issues.insert(
        0,
        StashIssueLink(url: url, title: item.title, state: item.state.name),
      );
    }, touch: false);
    notifyListeners();
  }

  /// [id]'s stash's title and text, changed here, made its issue's, as
  /// the user (who confirmed it). Throws [ForgeException].
  Future<void> pushEdits(int id) async {
    final note = store.byId(id);
    final url = note?.ownIssue;
    final ref = url == null ? null : refOf(url);
    final api = ref == null ? null : accounts.apiOf(ref);
    if (note == null || ref == null || url == null) return;
    if (api == null) throw const ForgeException('Not signed in.', status: 401);
    final title = note.displayTitle;
    final item = await api.editIssue(
      ref,
      title: title,
      body: await _outgoing(api, ref.repo, note.issueText),
    );
    _items[url] = item;
    _asked[url] = _clock();
    await store.reload();
    await store.update(id, (note) {
      note
        ..title = title
        ..issue = url
        ..synced = StashNote.syncHash(title, note.issueText)
        ..syncedRemote = _remoteHash(item);
    }, touch: false);
    notifyListeners();
  }

  /// [id]'s stash made as its issue is (what was changed here let go).
  Future<void> takeRemote(int id) async {
    final url = store.byId(id)?.ownIssue;
    if (url == null) return;
    var item = _items[url];
    if (refOf(url) case final ref?) {
      if (accounts.apiOf(ref) case final api?) item = await api.item(ref);
    }
    if (item == null) return;
    _items[url] = item;
    await store.reload();
    await store.update(id, (note) {
      note.syncedRemote = null;
      note.synced = null;
      _takeOwn(note, item!);
      // Asked for: not news.
      note.seen();
    });
    notifyListeners();
  }

  /// [id]'s stash no more its issue, nor made one: kept here. The issue is
  /// not made a stash again.
  Future<void> keepLocal(int id) async {
    final note = store.byId(id);
    if (note == null) return;
    final own = note.ownIssue;
    if (own != null) await store.ignoreIssue(own);
    await store.reload();
    await store.update(id, (note) {
      note
        ..issue = null
        ..local = true
        ..synced = null
        ..syncedRemote = null;
      if (own != null) note.issues.removeWhere((link) => link.url == own);
    }, touch: false);
  }

  /// [id]'s stash may be made an issue again (see [keepLocal]).
  Future<void> allowIssue(int id) =>
      store.update(id, (note) => note.local = false, touch: false);

  /// [text] as it goes to [repo]'s issue: its pictures (in the stash's
  /// folder) put there and linked by their address, its other files'
  /// links their names.
  Future<String> _outgoing(ForgeApi api, ForgeRepo repo, String text) async {
    final out = StringBuffer();
    var at = 0;
    for (final match in _links.allMatches(text)) {
      final target = _targetOf(match);
      if (_remote(target)) continue;
      out.write(text.substring(at, match.start));
      at = match.end;
      final bytes = await store.disk.readAsset(_decoded(target));
      final image = match[1]!.isNotEmpty || _isImage(target);
      if (bytes != null && image) {
        final address = await api.uploadImage(
          repo,
          target.split('/').last,
          bytes,
        );
        out.write('${match[1]}[${match[2]}]($address${match[4]})');
      } else {
        out.write(match[2]!.isEmpty ? target.split('/').last : match[2]);
      }
    }
    out.write(text.substring(at));
    return out.toString();
  }

  /// A Markdown link or picture: `!`, its text, its address, its title.
  static final _links = RegExp(
    r'(!?)\[([^\]\n]*)\]\((<[^>\n]+>|[^)\s]+)((?:\s+"[^"\n]*")?)\)',
  );

  static String _targetOf(Match match) {
    final target = match[3]!;
    return target.startsWith('<')
        ? target.substring(1, target.length - 1)
        : target;
  }

  /// How many pictures in [text] are this machine's (to be put where its
  /// issue can show them).
  static int localPictures(String text) => {
    for (final match in _links.allMatches(text))
      if (_targetOf(match) case final target
          when !_remote(target) && (match[1]!.isNotEmpty || _isImage(target)))
        target,
  }.length;

  static String _decoded(String target) {
    try {
      return Uri.decodeFull(target);
    } on FormatException {
      return target;
    }
  }

  static bool _remote(String target) =>
      RegExp(r'^[a-z][a-z0-9+.-]*:', caseSensitive: false).hasMatch(target) ||
      target.startsWith('#');

  static bool _isImage(String target) => RegExp(
    r'\.(png|jpe?g|gif|webp|svg|bmp)$',
    caseSensitive: false,
  ).hasMatch(target);

  // --- Imported ------------------------------------------------------------------

  /// The stash [url]'s issue is in, if one is.
  StashNote? stashOf(String url) {
    for (final note in store.notes) {
      if (note.issueOf(url) != null) return note;
    }
    return null;
  }

  /// A stash for each of [items] not in one yet, about [project]: the
  /// issue, kept in step with it (picked by the user: made a stash again
  /// though it was deleted). The stashes, those already there among them.
  Future<List<StashNote>> import(
    List<ForgeItem> items, {
    String? project,
  }) async {
    final notes = <StashNote>[];
    for (final item in items) {
      final url = item.ref.url.toString();
      if (stashOf(url) case final known?) {
        notes.add(known);
        continue;
      }
      await store.unignoreIssue(url);
      notes.add(await _create(item, project: project));
    }
    notifyListeners();
    return notes;
  }
}
