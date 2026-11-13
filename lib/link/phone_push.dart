import 'dart:async';
import 'dart:convert';

import 'package:bao_link/bao_link.dart';
import 'package:flutter/foundation.dart' show VoidCallback;

import '../bots/bots.dart';
import '../chat/chat_session.dart';
import '../workspace/workspace.dart';
import 'workspace_bridge.dart';

/// Where pushes go: baocode.dev's, which holds Apple's key and passes them
/// on to APNs, keeping nothing of them.
final pushEndpoint = Uri.parse('https://push.baocode.dev/v1/push');

/// What a phone asked to be pushed ([LinkMethods.push]): its token, and
/// what it says of each kind in its own words, `{device}` and `{title}` in
/// them filled in here. A kind with no words is not pushed.
class PhonePush {
  const PhonePush({
    required this.token,
    this.sandbox = false,
    this.needsInput,
    this.done,
    this.bots = false,
    this.notices = const {},
  });

  /// From what the phone sent, or kept; null without a token.
  static PhonePush? fromJson(Map<String, Object?> json) {
    final token = json['token'];
    if (token is! String || !RegExp(r'^[0-9a-f]{64,200}$').hasMatch(token)) {
      return null;
    }
    String? text(Object? value) =>
        value is String && value.isNotEmpty ? value : null;
    return PhonePush(
      token: token,
      sandbox: json['sandbox'] == true,
      needsInput: text(json['needsInput']),
      done: text(json['done']),
      bots: json['bots'] == true,
      notices: {
        if (json['notices'] case final Map<String, Object?> notices)
          for (final MapEntry(:key, :value) in notices.entries)
            key: ?text(value),
      },
    );
  }

  /// The phone's, as APNs knows it (hex).
  final String token;

  /// Of a build Xcode signed for development: APNs' sandbox.
  final bool sandbox;

  /// An agent asking, `{device}` the computer's name; none, not told.
  final String? needsInput;

  /// An agent done with its turn, as [needsInput].
  final String? done;

  /// A bot writing: its words, under its name.
  final bool bots;

  /// A bot's notice ([LinkBotNotice.kind]: `waiting`, `failed`, `done`,
  /// `running`), `{title}` its agent's.
  final Map<String, String> notices;

  Map<String, Object?> toJson() => {
    'token': token,
    if (sandbox) 'sandbox': true,
    'needsInput': ?needsInput,
    'done': ?done,
    if (bots) 'bots': true,
    if (notices.isNotEmpty) 'notices': notices,
  };
}

/// A notification's number, as the phone counts it for [key] too (FNV-1a
/// of its UTF-8, 31 bits): the next of an agent's takes the place of the
/// last, and the phone takes back the one it pushed once it is seen.
int notificationIdOf(String key) {
  var hash = 0x811c9dc5;
  for (final byte in utf8.encode(key)) {
    hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
  }
  return hash & 0x7fffffff;
}

/// One notification, for one phone.
typedef PushMessage = ({String key, String title, String body});

/// A push sent for [phone]; whether its token is still its: false when
/// APNs says it is gone (the app removed), for it to be forgotten.
typedef PushSender = Future<bool> Function(
  PhonePush phone,
  PushMessage message,
);

/// The agents and bots of this desktop told of to the phones that are away
/// (their app in the background, or not connected), as the phone tells of
/// them itself while it is in front: an agent asking or done, a bot writing
/// or noticing something. Looks [every] so often while there is a phone to
/// tell.
class PushWatcher {
  PushWatcher({
    required this.workspace,
    required this.bots,
    required this.desktopId,
    required this.desktopName,
    required this.away,
    required this.send,
    this.every = const Duration(seconds: 1),
  });

  final Workspace workspace;
  final Bots? bots;

  /// This desktop's id, as the phones know it: their keys begin with it.
  final String Function() desktopId;

  /// What the phones call it.
  final String Function() desktopName;

  /// The phones to tell now: away, with a token.
  final List<PhonePush> Function() away;

  final PushSender send;
  final Duration every;

  Timer? _timer;
  bool _started = false;

  /// The agents' conversations open, listened to: how each stands changes
  /// in it, not in the workspace.
  final Map<ChatSession, VoidCallback> _listened = {};

  /// The agents seen running since the last look: a turn shorter than
  /// [every] is done all the same.
  final Set<String> _ran = {};

  /// What each agent and bot was when last looked at; null before the
  /// first look (nothing is told of what was before).
  Map<String, ThreadStatus>? _sessions;
  Map<String, _BotSeen>? _bots;

  void start() {
    if (_started) return;
    _started = true;
    workspace.addListener(_changed);
    bots?.addListener(_changed);
    _look();
  }

  void dispose() {
    if (!_started) return;
    _started = false;
    workspace.removeListener(_changed);
    bots?.removeListener(_changed);
    for (final MapEntry(key: session, value: listener) in _listened.entries) {
      session.removeListener(listener);
    }
    _listened.clear();
    _timer?.cancel();
    _timer = null;
  }

  void _changed() {
    if (!_started || _timer != null) return;
    _timer = Timer(every, () {
      _timer = null;
      if (_started) _look();
    });
  }

  /// What changed since last time, told to the phones away.
  void _look() {
    final events = <_Event>[];
    final phones = away();
    final desktop = desktopId();
    final l10n = workspace.l10n();

    final botThreads = {
      if (bots case final bots?)
        for (final bot in bots.bots) ?bots.threadOf(bot),
    };
    final listed = workspace.sidebarProjects.toSet();
    final sessions = <String, ThreadStatus>{};
    final had = _sessions;
    final open = {
      for (final thread in workspace.threads)
        if (thread.isOpen) thread.session: thread,
    };
    for (final session in [..._listened.keys]) {
      if (!open.containsKey(session)) {
        session.removeListener(_listened.remove(session)!);
      }
    }
    for (final MapEntry(key: session, value: thread) in open.entries) {
      if (_listened.containsKey(session)) continue;
      void listener() {
        if (thread.shownStatus == ThreadStatus.running) {
          _ran.add(WorkspaceBridge.idOf(thread));
        }
        _changed();
      }

      session.addListener(listener);
      _listened[session] = listener;
    }
    for (final thread in workspace.threads) {
      if (thread.archived ||
          botThreads.contains(thread) ||
          !listed.contains(thread.project) ||
          !workspace.listsInSidebar(thread)) {
        continue;
      }
      final id = WorkspaceBridge.idOf(thread);
      final status = switch (thread.shownStatus) {
        ThreadStatus.unread => ThreadStatus.idle,
        final status => status,
      };
      sessions[id] = status;
      final was = _ran.contains(id) && status != ThreadStatus.running
          ? ThreadStatus.running
          : had?[id];
      if (had == null || was == status) continue;
      final asking = status == ThreadStatus.needsInput;
      if (!asking &&
          !(status == ThreadStatus.idle && was == ThreadStatus.running)) {
        continue;
      }
      final title = thread.localizedTitle(l10n);
      events.add(
        _AgentEvent(
          '$desktop/$id',
          title.isEmpty ? 'BaoCode' : title,
          asking: asking,
        ),
      );
    }
    _sessions = sessions;
    _ran.clear();

    final botsSeen = <String, _BotSeen>{};
    final hadBots = _bots;
    if (bots case final bots?) {
      for (final bot in bots.bots) {
        final notices = bots.notices(bot);
        final seen = botsSeen[bot.id] = _BotSeen(
          unread: bots.unread(bot),
          typing: bots.typing(bot),
          last: bots.lastLine(bot),
          notice: notices.lastOrNull?.id ?? 0,
        );
        final before = hadBots?[bot.id];
        if (before == null) continue;
        final wrote =
            seen.unread > before.unread ||
            (before.typing && !seen.typing && seen.last != before.last);
        if (wrote && (seen.last?.isNotEmpty ?? false)) {
          events.add(_BotWrote('bot:$desktop/${bot.id}', bot.name, seen.last!));
        }
        for (final notice in notices) {
          if (notice.id <= before.notice) continue;
          events.add(_BotNoticed('$desktop/${notice.chat}', bot.name, notice));
        }
      }
    }
    _bots = botsSeen;

    if (events.isEmpty || phones.isEmpty) return;
    final device = desktopName();
    for (final phone in phones) {
      for (final event in events) {
        final body = event.bodyFor(phone, device);
        if (body == null) continue;
        unawaited(
          send(phone, (key: event.key, title: event.title, body: body)),
        );
      }
    }
  }
}

/// What happened, told to each phone in its words.
sealed class _Event {
  const _Event(this.key, this.title);

  /// What the notification opens ([notificationIdOf] its number).
  final String key;
  final String title;

  /// As [phone] says it, [device] this computer's name; null when it is
  /// not to be told of it.
  String? bodyFor(PhonePush phone, String device);
}

/// An agent asking, or done with its turn.
class _AgentEvent extends _Event {
  const _AgentEvent(super.key, super.title, {required this.asking});

  final bool asking;

  @override
  String? bodyFor(PhonePush phone, String device) =>
      (asking ? phone.needsInput : phone.done)?.replaceAll('{device}', device);
}

/// A bot wrote [text].
class _BotWrote extends _Event {
  const _BotWrote(super.key, super.title, this.text);

  final String text;

  @override
  String? bodyFor(PhonePush phone, String device) => phone.bots ? text : null;
}

/// A bot's [notice] of an agent it watches.
class _BotNoticed extends _Event {
  const _BotNoticed(super.key, super.title, this.notice);

  final LinkBotNotice notice;

  @override
  String? bodyFor(PhonePush phone, String device) {
    if (!phone.bots) return null;
    final said = (phone.notices[notice.kind] ?? phone.notices['done'])
        ?.replaceAll('{title}', notice.title);
    if (said == null) return null;
    return [
      '${notice.project} · $said',
      if (notice.detail case final detail? when detail.isNotEmpty) detail,
    ].join('\n');
  }
}

class _BotSeen {
  const _BotSeen({
    required this.unread,
    required this.typing,
    required this.last,
    required this.notice,
  });

  final int unread;
  final bool typing;
  final String? last;

  /// Its latest notice's id.
  final int notice;
}
