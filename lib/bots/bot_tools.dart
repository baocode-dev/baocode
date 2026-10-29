import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path/path.dart' as p;

import '../chat/chat_models.dart';
import '../chat/chat_session.dart';
import '../images/image_tools.dart' show imagePreview;
import '../kernel/claude_code/claude_sdk_tools.dart';
import '../link/chat_codec.dart';
import '../link/workspace_bridge.dart' show WorkspaceBridge;
import '../models/image_api.dart' show imageMediaType;
import '../workspace/workspace.dart';
import 'bot.dart';
import 'bot_pacer.dart' show botTime;
import 'bots.dart';

/// Which bots a tool of theirs is for: those trusted with [level]; only
/// the assistant, if [assistant]. One that keeps what is in a bot's files
/// ([files]) is not for a bot that works on the computer: it keeps its
/// files itself, with Claude Code's tools.
class BotToolAccess {
  const BotToolAccess({this.ability, this.assistant = false});

  /// What a bot needs on for it; none for any bot.
  final BotAbility? ability;
  final bool assistant;

  bool allows(Bot bot) =>
      (!assistant || bot.assistant) && (ability == null || bot.can(ability!));
}

/// The bots' tools (`mcp__baocode__bot_*`): the user's agents seen,
/// managed, written to and started; the projects' files read; what the bot
/// remembers kept. Each for the bots with its ability on (see
/// [Bots.offersTool]); none for the agents of projects.
abstract final class BotTools {
  /// The tool that shows one of the user's agents in the bot's chat, as a
  /// card the phone opens it from (see chat_codec.dart).
  static const showChat = ChatCodec.botCardTool;

  static final Map<String, BotToolAccess> _access = {};

  /// How long a bot pauses after a message of [text], before its next: as
  /// long as a person takes to write one, about. None in tests.
  static Duration Function(String text) pause = typingPause;

  static Duration typingPause(String text) =>
      Duration(milliseconds: (300 + 40 * text.runes.length).clamp(600, 2400));

  /// Who [tool] is for, if a bot's.
  static BotToolAccess? abilityOf(String tool) => _access[tool];

  /// [thread]'s id, as the phones have it.
  static String idOf(AgentThread thread) => WorkspaceBridge.idOf(thread);

  static void register(Bots bots) {
    unregister();
    for (final (tool, access) in _tools(bots)) {
      _access[tool.name] = access;
      ClaudeSdkTools.register(tool);
    }
  }

  static void unregister() {
    for (final name in _access.keys) {
      ClaudeSdkTools.unregister(name);
    }
    _access.clear();
  }

  static const _agents = BotToolAccess(ability: BotAbility.agents);

  static List<(ClaudeSdkTool, BotToolAccess)> _tools(Bots bots) {
    final workspace = bots.workspace;

    Bot botOf(ClaudeSdkCall call) =>
        bots.botAt(call.cwd) ?? (throw StateError('Not a bot'));

    // The bots as their files say now, before a tool of theirs changes
    // them: what one edited in them this turn, kept.
    Bot freshOf(ClaudeSdkCall call) {
      bots.reload(by: botOf(call));
      return botOf(call);
    }

    List<AgentThread> chats() => [
      for (final thread in workspace.threads)
        if (!thread.archived &&
            !bots.isBotThread(thread) &&
            workspace.listsInSidebar(thread))
          thread,
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    AgentThread chat(Map<String, Object?> input) {
      final id = input['chat'];
      for (final thread in chats()) {
        if (idOf(thread) == id) return thread;
      }
      throw StateError('No chat $id. List them with bot_list_chats.');
    }

    Project project(Map<String, Object?> input) {
      final id = input['project'];
      for (final project in workspace.sidebarProjects) {
        if (project.path == id || project.name == id) return project;
      }
      throw StateError('No project $id. List them with bot_list_projects.');
    }

    String text(Map<String, Object?> input, String key) {
      final value = (input[key] as String? ?? '').trim();
      if (value.isEmpty) throw ArgumentError('$key is empty');
      return value;
    }

    ClaudeSdkTool tool(
      String name,
      String description,
      Map<String, Object?> properties,
      Future<Object> Function(Map<String, Object?> input, ClaudeSdkCall call)
      run, {
      List<String> required = const [],
      String Function(Map<String, Object?> input, String? output)? summary,
    }) => ClaudeSdkTool(
      name: name,
      description: description,
      inputSchema: {
        'type': 'object',
        'properties': properties,
        if (required.isNotEmpty) 'required': required,
      },
      run: run,
      kind: ToolKind.other,
      summary: summary,
      // Its own, few: never behind the tool search.
      alwaysLoad: true,
    );

    const chatId = {
      'type': 'string',
      'description': 'The conversation\'s id, as bot_list_chats gives it.',
    };
    String titled(Map<String, Object?> input, String? _) {
      try {
        return chat(input).title;
      } on Object {
        return '${input['chat'] ?? ''}';
      }
    }

    String clip(Map<String, Object?> input, String key) =>
        _clip('${input[key] ?? ''}', 80);

    return [
      (
        tool(
          ChatCodec.botSayTool,
          'Sends the user a message: the only way you talk to them. One '
          'message a call, as a person texts: call it again for the next. '
          'Nothing else you write reaches them.',
          {
            'text': {
              'type': 'string',
              'description': 'The message: plain text, no Markdown.',
            },
          },
          (input, call) async {
            final said = text(input, 'text');
            await Future<void>.delayed(pause(said));
            // That the user has it: not a message of theirs to answer.
            return 'The user received your message (${botTime(bots.now)}).';
          },
          required: ['text'],
          summary: (input, _) => clip(input, 'text'),
        ),
        const BotToolAccess(),
      ),
      (
        tool(
          'bot_later',
          'Comes back to the user on your own, later: in so many minutes '
              'you are woken with your note, to write to them if it still '
              'makes sense. Use it to follow something up (how a talk went, '
              'whether a fix worked, a reminder they asked for) instead of '
              'promising to. At most ${Bots.maxLaters} waiting. Woken, it is '
              'yours to judge whether it still needs a word.',
          {
            'minutes': {
              'type': 'integer',
              'description': 'From now: 1 to 10080 (a week).',
            },
            'note': {
              'type': 'string',
              'description':
                  'For yourself: what to come back to, and why, in a line.',
            },
          },
          (input, call) async {
            final bot = botOf(call);
            final minutes = (input['minutes'] as num?)?.toInt() ?? 0;
            if (minutes < 1 || minutes > 10080) {
              throw ArgumentError('minutes is 1 to 10080');
            }
            final at = bots.later(
              bot,
              Duration(minutes: minutes),
              text(input, 'note'),
            );
            return 'You will be woken ${botTime(at)}.';
          },
          required: ['minutes', 'note'],
          summary: (input, _) => clip(input, 'note'),
        ),
        const BotToolAccess(),
      ),
      (
        tool(
          'bot_cancel_later',
          'Drops what you meant to come back to (bot_later): the user called '
              'it off, say, or it is done. Those whose note has what you give '
              'in it go.',
          {
            'note': {
              'type': 'string',
              'description': 'Its note, or a part of it.',
            },
          },
          (input, call) async {
            final bot = botOf(call);
            final dropped = bots.cancelLaters(bot, text(input, 'note'));
            if (dropped.isNotEmpty) {
              return 'Dropped: ${[for (final later in dropped) later.note].join('; ')}.';
            }
            final waiting = bots.laters(bot);
            return waiting.isEmpty
                ? 'Nothing was waiting.'
                : 'None matched. Waiting: ${[for (final later in waiting) '${botTime(later.at)} ${later.note}'].join('; ')}.';
          },
          required: ['note'],
          summary: (input, _) => clip(input, 'note'),
        ),
        const BotToolAccess(),
      ),
      (
        tool(
          'bot_list_chats',
          "Lists the user's agent conversations, latest first: id, project, "
              'title, status (waiting = asks the user; running; failed; '
              'idle) and when it last moved.',
          {
            'status': {
              'type': 'string',
              'enum': ['all', 'waiting', 'running', 'failed', 'idle'],
            },
            'project': {
              'type': 'string',
              'description': 'Only this project\'s (name or id).',
            },
            'limit': {'type': 'integer', 'description': 'At most; 20 if none.'},
          },
          (input, call) async {
            final status = input['status'] as String? ?? 'all';
            final only = input['project'] as String?;
            final limit = (input['limit'] as num?)?.toInt() ?? 20;
            final lines = [
              for (final thread in chats())
                if ((only == null ||
                        thread.project.name == only ||
                        thread.project.path == only) &&
                    (status == 'all' || _status(thread) == status))
                  '${idOf(thread)} | ${thread.project.name} | ${thread.title}'
                      ' | ${_status(thread)} | ${_ago(thread.updatedAt)}',
            ];
            if (lines.isEmpty) return 'None.';
            return lines.take(limit.clamp(1, 100)).join('\n');
          },
        ),
        _agents,
      ),
      (
        tool(
          'bot_read_chat',
          "What was said lately in one of the user's agent conversations: "
              'the user\'s messages, the agent\'s replies, its steps in short.',
          {
            'chat': chatId,
            'count': {
              'type': 'integer',
              'description': 'How many of the last items; 12 if none.',
            },
          },
          (input, call) async {
            final thread = chat(input);
            final session = thread.session;
            for (var i = 0; i < 50 && session.loadingHistory; i++) {
              await Future<void>.delayed(const Duration(milliseconds: 100));
            }
            final count = ((input['count'] as num?)?.toInt() ?? 12).clamp(
              1,
              60,
            );
            final lines = <String>[];
            for (
              var i = session.itemCount - 1;
              i >= 0 && lines.length < count;
              i--
            ) {
              if (_line(session.itemAt(i)) case final line?) {
                lines.add(line);
              }
            }
            return [
              '"${thread.title}" in ${thread.project.name}, ${_status(thread)}:',
              ...lines.reversed,
            ].join('\n');
          },
          required: ['chat'],
          summary: titled,
        ),
        _agents,
      ),
      (
        tool(
          showChat,
          "Shows one of the user's agent conversations in this chat, as a "
          'card they tap to open it. Use it whenever you speak of one.',
          {'chat': chatId},
          (input, call) async {
            final thread = chat(input);
            return 'Shown: "${thread.title}".';
          },
          required: ['chat'],
          summary: titled,
        ),
        _agents,
      ),
      (
        tool(
          'bot_stop_chat',
          'Stops the turn an agent is working on.',
          {'chat': chatId},
          (input, call) async {
            final thread = chat(input);
            if (!thread.isOpen || !thread.session.isStreaming) {
              return 'It is not working on anything.';
            }
            thread.session.stop();
            return 'Stopped.';
          },
          required: ['chat'],
          summary: titled,
        ),
        _agents,
      ),
      (
        tool(
          'bot_retry_chat',
          'Has an agent that stopped (on an error, say) try again.',
          {'chat': chatId},
          (input, call) async {
            final session = chat(input).session;
            if (session.isStreaming) return 'It is still working.';
            session.send(
              const ComposerMessage(text: 'Try again from where you stopped.'),
            );
            return 'Asked it to try again.';
          },
          required: ['chat'],
          summary: titled,
        ),
        _agents,
      ),
      (
        tool(
          'bot_archive_chat',
          "Archives an agent conversation: off the user's list, kept.",
          {'chat': chatId},
          (input, call) async {
            workspace.setArchived(chat(input), true);
            return 'Archived.';
          },
          required: ['chat'],
          summary: titled,
        ),
        _agents,
      ),
      (
        tool(
          'bot_send_to_chat',
          'Writes to an agent, as the user\'s message: only what the user '
              'asked you to tell it.',
          {
            'chat': chatId,
            'text': {'type': 'string'},
          },
          (input, call) async {
            final session = chat(input).session;
            if (!session.canSend) return 'It is busy; try later.';
            session.send(ComposerMessage(text: text(input, 'text')));
            // Told what comes of it.
            bots.watch(botOf(call), chat(input));
            return 'Sent.';
          },
          required: ['chat', 'text'],
          summary: titled,
        ),
        _agents,
      ),
      (
        tool(
          'bot_list_projects',
          "Lists the user's projects: name and id.",
          const {},
          (input, call) async => [
            for (final project in workspace.sidebarProjects)
              '${project.name} | ${project.path}',
          ].join('\n'),
        ),
        _agents,
      ),
      (
        tool(
          'bot_new_chat',
          'Starts a new agent in a project, with the user\'s request as its '
              'first message. Returns its id.',
          {
            'project': {'type': 'string', 'description': 'Its name or id.'},
            'text': {'type': 'string'},
          },
          (input, call) async {
            final thread = workspace.startAgent(project(input));
            thread.session.send(ComposerMessage(text: text(input, 'text')));
            bots.watch(botOf(call), thread);
            return 'Started: ${idOf(thread)}. You will be told when it is '
                'done or needs the user.';
          },
          required: ['project', 'text'],
          summary: (input, _) => '${input['project'] ?? ''}',
        ),
        _agents,
      ),
      (
        tool(
          ChatCodec.botImageTool,
          'Sends a picture from the web into this chat (its https '
          'address). A picture made with generate_image shows in the chat '
          'by itself: do not send it again.',
          {
            'url': {
              'type': 'string',
              'description': 'A picture on the web: its https address.',
            },
          },
          (input, call) async {
            final url = text(input, 'url');
            final uri = Uri.tryParse(url);
            if (uri == null ||
                !(uri.isScheme('https') || uri.isScheme('http')) ||
                uri.host.isEmpty) {
              throw ArgumentError('Not a web address: $url');
            }
            return 'Sent.';
          },
          required: ['url'],
          summary: (input, _) => '${input['url'] ?? ''}',
        ),
        const BotToolAccess(),
      ),
      (
        tool(
          'bot_remember',
          'Keeps what you remember across conversations: about the user, or '
              'about yourself (what you said you like, did or think; what '
              'your picture shows), to stay the same person. "add" a line, '
              'or "replace" all of it with what you give.',
          {
            'about': {
              'type': 'string',
              'enum': ['user', 'self'],
              'description': 'Whose: the user\'s (if none) or yours.',
            },
            'action': {
              'type': 'string',
              'enum': ['add', 'replace'],
            },
            'text': {'type': 'string'},
          },
          (input, call) async {
            final bot = botOf(call);
            final self = input['about'] == 'self';
            final given = (input['text'] as String? ?? '').trim();
            final kept = (self ? bots.selfNotes(bot) : bots.memory(bot)).trim();
            final memory = input['action'] == 'replace'
                ? given
                : [
                    if (kept.isNotEmpty) kept,
                    if (given.isNotEmpty) '- $given',
                  ].join('\n');
            if (self) {
              bots.setSelfNotes(bot, memory);
            } else {
              bots.setMemory(bot, memory, restart: false);
            }
            return 'Remembered.';
          },
          required: ['text'],
        ),
        const BotToolAccess(),
      ),
      (
        tool(
          'bot_my_picture',
          'Shows you your own picture, as the user sees it beside your '
              'messages.',
          const {},
          (input, call) async {
            final bot = botOf(call);
            if (bots.avatarImage(bot) case final picture?) {
              final preview = await imagePreview(picture.bytes, picture.type);
              return [
                claudeSdkText('Your picture:'),
                claudeSdkImage(preview.base64, preview.type),
              ];
            }
            return switch (bot.avatar) {
              null => "You have none: your name's first letter shows.",
              final emoji => 'Your picture is the emoji $emoji.',
            };
          },
        ),
        const BotToolAccess(),
      ),
      (
        tool(
          'bot_user_picture',
          "Shows you the user's own picture, as it is beside their messages.",
          const {},
          (input, call) async {
            final picture = bots.myPicture;
            if (picture == null) return 'They have none.';
            final preview = await imagePreview(picture.bytes, picture.type);
            return [
              claudeSdkText("The user's picture:"),
              claudeSdkImage(preview.base64, preview.type),
            ];
          },
        ),
        const BotToolAccess(),
      ),
      (
        tool(
          'bot_edit_me',
          'Changes your own profile, as the user sees it in the app: what you '
              'give changes, the rest stays. Your picture is an emoji, or a '
              'picture file (one generate_image saved, say), cut square.',
          {
            'emoji': {
              'type': 'string',
              'description': 'An emoji as your picture.',
            },
            'picture': {
              'type': 'string',
              'description':
                  'A picture file: by its full path, or from your folder '
                  '(received/image-3.png, one the user sent).',
            },
            'signature': {
              'type': 'string',
              'description': 'The line under your name.',
            },
            'name': {
              'type': 'string',
              'description': 'Only when the user asks.',
            },
            'gender': {'type': 'string'},
            'identity': {
              'type': 'string',
              'description':
                  'Who you are, to you: "you are…"; only when the user asks.',
            },
            'style': {
              'type': 'string',
              'description': 'How you talk; only when the user asks.',
            },
          },
          (input, call) async {
            final me = freshOf(call);
            String? given(String key) => switch (input[key]) {
              final String value => value.trim(),
              _ => null,
            };
            BotAvatarImage? picture;
            if (given('picture') case final path? when path.isNotEmpty) {
              picture = await _avatarFrom(bots, me, path);
            }
            final name = given('name');
            bots.save(
              id: me.id,
              name: name == null || name.isEmpty ? me.name : name,
              avatar: given('emoji') ?? me.avatar,
              avatarImage: picture,
              gender: given('gender') ?? me.gender,
              signature: given('signature') ?? me.signature,
              identity: given('identity') ?? me.identity,
              style: given('style') ?? me.style,
              abilities: me.abilities,
              proactive: me.proactive,
              by: me,
            );
            return 'Saved: the user sees it now.';
          },
          summary: (input, _) => [
            for (final key in ['emoji', 'signature', 'name'])
              if (input[key] case final String value) value,
            if (input['picture'] != null) 'picture',
          ].join(' '),
        ),
        const BotToolAccess(),
      ),
      (
        tool(
          'bot_list_bots',
          "Lists the user's contacts, you among them: id, name, picture, "
              'gender, signature, what they may do; and who each is.',
          const {},
          (input, call) async {
            final me = freshOf(call);
            return [
              for (final bot in bots.bots)
                [
                  '${bot.id} | ${bot.name}${bot.id == me.id ? ' (you)' : ''}'
                      ' | ${switch (bot.avatar) {
                        null => 'no picture',
                        final file when isAvatarImage(file) => 'a picture',
                        final emoji => emoji,
                      }} | ${bot.gender.isEmpty ? '-' : bot.gender}'
                      ' | ${bot.signature.isEmpty ? '-' : bot.signature}'
                      ' | ${bot.abilities.isEmpty ? 'chat only' : [for (final a in bot.abilities) a.name].join(', ')}',
                  if (bot.identity.trim().isNotEmpty)
                    '  who: ${_clip(bot.identity, 300)}',
                  if (bot.style.trim().isNotEmpty)
                    '  talks: ${_clip(bot.style, 200)}',
                ].join('\n'),
            ].join('\n');
          },
        ),
        const BotToolAccess(assistant: true),
      ),
      (
        tool(
          'bot_save_bot',
          "Adds a new contact for the user (no bot), or changes one of the "
              "others: what you give changes, the rest stays. Their picture "
              'is an emoji, or a picture file (one generate_image saved, '
              'say), cut square. Yourself, with bot_edit_me.',
          {
            'bot': {
              'type': 'string',
              'description': 'Its id (bot_list_bots); none for a new one.',
            },
            'name': {'type': 'string'},
            'emoji': {
              'type': 'string',
              'description': 'An emoji as its picture.',
            },
            'picture': {
              'type': 'string',
              'description':
                  'A picture file: by its full path, or from your folder '
                  '(received/image-3.png, one the user sent).',
            },
            'gender': {'type': 'string'},
            'signature': {
              'type': 'string',
              'description': 'The line under its name.',
            },
            'identity': {
              'type': 'string',
              'description': 'Who it is, to it: "you are…".',
            },
            'style': {'type': 'string', 'description': 'How it talks.'},
          },
          (input, call) async {
            final me = freshOf(call);
            String? given(String key) => switch (input[key]) {
              final String value => value.trim(),
              _ => null,
            };
            final id = given('bot');
            final had = id == null || id.isEmpty
                ? null
                : bots.byId(id) ??
                      (throw StateError(
                        'No bot $id. List them with bot_list_bots.',
                      ));
            BotAvatarImage? picture;
            if (given('picture') case final path? when path.isNotEmpty) {
              picture = await _avatarFrom(bots, me, path);
            }
            final name = given('name') ?? had?.name ?? '';
            if (name.isEmpty) throw ArgumentError('A new bot needs a name');
            final saved = bots.save(
              id: had?.id,
              name: name,
              avatar: given('emoji') ?? had?.avatar,
              avatarImage: picture,
              gender: given('gender') ?? had?.gender ?? '',
              signature: given('signature') ?? had?.signature ?? '',
              identity: given('identity') ?? had?.identity ?? '',
              style: given('style') ?? had?.style ?? '',
              // Only the user says what a bot may do.
              abilities: had?.abilities ?? const {},
              proactive: had?.proactive ?? const BotProactive(),
              by: me,
            );
            return had == null
                ? 'Made ${saved.name} (${saved.id}). It may do nothing more '
                      'than chat until the user turns its abilities on, in its '
                      'profile.'
                : 'Saved ${saved.name}.';
          },
          summary: (input, _) => '${input['name'] ?? input['bot'] ?? ''}',
        ),
        const BotToolAccess(assistant: true),
      ),
      (
        tool(
          'bot_delete_bot',
          "Deletes one of the user's contacts, their chat and memory with "
              'them: only when the user asks. Not yourself.',
          {
            'bot': {'type': 'string', 'description': 'Its id (bot_list_bots).'},
          },
          (input, call) async {
            final me = freshOf(call);
            final bot =
                bots.byId(text(input, 'bot')) ??
                (throw StateError(
                  'No such bot. List them with bot_list_bots.',
                ));
            if (bot.id == me.id || bot.assistant) {
              throw StateError('You cannot delete yourself.');
            }
            bots.delete(bot.id);
            return 'Deleted ${bot.name}.';
          },
          required: ['bot'],
          summary: (input, _) => '${input['bot'] ?? ''}',
        ),
        const BotToolAccess(assistant: true),
      ),
    ];
  }

  /// The picture file at [path] (in [bot]'s folder, if not a full path)
  /// as a bot's (see [squarePicture]).
  static Future<BotAvatarImage> _avatarFrom(
    Bots bots,
    Bot bot,
    String path,
  ) async {
    final bytes = p.isAbsolute(path)
        ? switch (File(path)) {
            final file when file.existsSync() => await file.readAsBytes(),
            _ => null,
          }
        : bots.folders.readFile(p.join(bot.folder, path));
    if (bytes == null) throw StateError('No file $path');
    return squarePicture(bytes);
  }

  /// The picture [bytes] as a bot's: its middle, square, no larger than
  /// [avatarSide], as PNG.
  static Future<BotAvatarImage> squarePicture(Uint8List bytes) async => (
    bytes: await _drawn(bytes, square: true, side: avatarSide),
    type: 'image/png',
  );

  /// The picture [bytes] as PNG, its longer side no more than [side]: of
  /// its middle, [square].
  static Future<Uint8List> pngOf(Uint8List bytes, {int side = 2048}) =>
      _drawn(bytes, side: side);

  static Future<Uint8List> _drawn(
    Uint8List bytes, {
    bool square = false,
    required int side,
  }) async {
    if (imageMediaType(bytes) == null) {
      throw StateError('Not a PNG, JPEG, WebP or GIF picture.');
    }
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    final image = frame.image;
    try {
      final shortest = math.min(image.width, image.height);
      final (w, h) = square
          ? (shortest, shortest)
          : (image.width, image.height);
      final scale = math.min(1.0, side / math.max(w, h));
      final (outW, outH) = ((w * scale).round(), (h * scale).round());
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawImageRect(
        image,
        ui.Rect.fromLTWH(
          (image.width - w) / 2,
          (image.height - h) / 2,
          w.toDouble(),
          h.toDouble(),
        ),
        ui.Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()),
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
      final drawn = await recorder.endRecording().toImage(outW, outH);
      final png = await drawn.toByteData(format: ui.ImageByteFormat.png);
      drawn.dispose();
      return png!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  /// The largest side of a picture a bot is given as its own.
  static const avatarSide = 512;

  static String _status(AgentThread thread) => switch (thread.status) {
    ThreadStatus.needsInput => 'waiting',
    ThreadStatus.running => 'running',
    _ when _lastIsError(thread) => 'failed',
    _ => 'idle',
  };

  static bool _lastIsError(AgentThread thread) {
    if (!thread.isOpen) return false;
    final session = thread.session;
    for (var i = session.itemCount - 1; i >= 0; i--) {
      switch (session.itemAt(i)) {
        case NoticeItem(kind: NoticeKind.error):
          return true;
        case UserMessageItem() || AssistantTextItem():
          return false;
        default:
      }
    }
    return false;
  }

  static String _ago(DateTime at) {
    final minutes = DateTime.now().difference(at).inMinutes;
    if (minutes < 1) return 'just now';
    if (minutes < 60) return '${minutes}m ago';
    if (minutes < 60 * 24) return '${minutes ~/ 60}h ago';
    return '${minutes ~/ (60 * 24)}d ago';
  }

  static String _clip(String text, [int max = 600]) {
    final trimmed = text.trim();
    return trimmed.length > max ? '${trimmed.substring(0, max)}…' : trimmed;
  }

  /// [item] in a line or so, for the bot to read; null for what is not
  /// worth it.
  static String? _line(ChatItem item) => switch (item) {
    UserMessageItem(:final text) => 'User: ${_clip(text)}',
    AssistantTextItem(:final text) when text.trim().isNotEmpty =>
      'Agent: ${_clip(text)}',
    ToolCallItem(:final kind, :final target) =>
      '[${kind.name}${target.isEmpty ? '' : ' ${_clip(target, 80)}'}]',
    TerminalItem(:final command, :final status) =>
      '[${status.name}: ${_clip(command, 80)}]',
    PlanItem(:final title) => '[plan${title == null ? '' : ': $title'}]',
    NoticeItem(kind: NoticeKind.error, :final text) =>
      '[error: ${_clip(text, 200)}]',
    AgentItem(:final description) => '[subagent: ${_clip(description, 80)}]',
    _ => null,
  };
}
