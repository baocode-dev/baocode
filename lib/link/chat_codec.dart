import 'dart:convert';

import '../chat/chat_models.dart';

/// The history's items as JSON, for the phones paired with the desktop
/// (see `package:bao_link`). The phone has this file as it is (its
/// lib/link/chat_codec.dart), over its copy of chat_models.dart.
abstract final class ChatCodec {
  /// What a tool's or a command's output keeps, at most: the phone shows it
  /// on demand, and a build's log would weigh on every update.
  static const maxOutput = 64 * 1024;

  // --- Bots ------------------------------------------------------------------

  /// The tag the app's messages to a bot are wrapped in: what happened to
  /// the user's agents, for it to tell of. Not the user's words: shown as
  /// a note.
  static const botEventTag = 'bao-event';

  /// The bot's tool that shows one of the user's agents in its chat (its
  /// input's `chat`), as a card that opens it.
  static const botCardTool = 'bot_show_chat';

  /// The bot's tool that sends a picture: a file's, which it answers with
  /// (the item's images), or one on the web (its input's `url`).
  static const botImageTool = 'bot_send_image';

  /// The tag a bot wraps each message of its reply in: what it says to the
  /// user. What it writes outside them is not for the user.
  static const botSayTag = 'bot_say';

  /// The tag a bot wraps narration in: what it does or what goes on, told
  /// beside its messages, not said to the user.
  static const botNarrateTag = 'bot_narrate';

  /// What the app told a bot in [item], if it is such a note.
  static String? botEvent(UserMessageItem item) {
    // The pictures that came with it referred to after it, if they are.
    final text = item.text.replaceAll(imageReferencePattern, '').trim();
    const open = '<$botEventTag>', close = '</$botEventTag>';
    if (!text.startsWith(open) || !text.endsWith(close)) return null;
    return text.substring(open.length, text.length - close.length).trim();
  }

  /// [text] (a message of the user's to a bot) without the app's notes
  /// in it: taken up with one, the two are one message.
  static String withoutBotEvents(String text) =>
      text.replaceAll(_botEvents, '').trim();

  static final _botEvents = RegExp(
    '<$botEventTag>.*?</$botEventTag>',
    dotAll: true,
  );

  /// The agent [item] shows as a card, if it is the bot's tool that does.
  static String? botCard(ToolCallItem item) =>
      _botInput(item, botCardTool, 'chat');

  /// The messages a bot's reply [text] has, in order: each `<bot_say>`'s,
  /// once closed (one still being written shows when it is whole).
  static List<String> botSays(String text) => [
    for (final (said, narration) in botParts(text))
      if (!narration) said,
  ];

  /// What a bot's reply [text] shows, in order: its messages, and its
  /// narration (`<bot_narrate>`, [narration] true); each once closed.
  static List<(String text, bool narration)> botParts(String text) => [
    for (final match in _botParts.allMatches(text))
      if (match[2]!.trim() case final part when part.isNotEmpty)
        (part, match[1] == botNarrateTag),
  ];

  static final _botParts = RegExp(
    '<($botSayTag|$botNarrateTag)>(.*?)</\\1>',
    dotAll: true,
  );

  /// Whether [item] is something a bot sent into its chat: a card, a
  /// picture (one being made too). Its messages are in its texts (see
  /// [botSays]).
  static bool botSent(ChatItem item) =>
      item is ToolCallItem &&
      item.status != ToolStatus.failed &&
      (botCard(item) != null ||
          botImageUrl(item) != null ||
          item.kind == ToolKind.image ||
          item.images.isNotEmpty);

  /// The picture on the web [item] sent, if it is the bot's tool that did.
  static String? botImageUrl(ToolCallItem item) =>
      switch (_botInput(item, botImageTool, 'url')) {
        final String url
            when item.status != ToolStatus.failed &&
                (url.startsWith('https://') || url.startsWith('http://')) =>
          url,
        _ => null,
      };

  static String? _botInput(ToolCallItem item, String tool, String key) =>
      switch (item) {
        ToolCallItem(tool: final named, :final input) when named == tool =>
          switch (input[key]) {
            final String value when value.isNotEmpty => value,
            _ => null,
          },
        _ => null,
      };

  /// What the user's message says when it is a sticker: [id]'s (its
  /// picture goes with it).
  static String stickerText(String id) => '[Sticker: $id]';

  /// The sticker a message of the user's ([text], its pictures' references
  /// aside) is, if it is one.
  static String? sticker(String text) => _stickerText.firstMatch(
    text.replaceAll(imageReferencePattern, '').trim(),
  )?[1];

  static final _stickerText = RegExp(r'^\[Sticker: ([\w-]+)\]$');

  static Map<String, Object?> encode(ChatItem item) => switch (item) {
    UserMessageItem() => {
      't': 'user',
      'text': item.text,
      if (item.queued) 'queued': true,
      if (item.images.isNotEmpty) 'images': _images(item.images),
      'worked': ?item.worked?.inMilliseconds,
      'at': ?item.sentAt?.millisecondsSinceEpoch,
      if (item.usage case final usage?)
        'usage': {
          'in': ?usage.inputTokens,
          'out': ?usage.outputTokens,
          'speed': ?usage.tokensPerSecond,
          'cost': ?usage.costUsd,
        },
    },
    AssistantTextItem() => {'t': 'text', 'text': item.text},
    ThinkingItem() => {
      't': 'thinking',
      'text': item.text,
      'tokens': item.tokens,
      'seconds': ?item.seconds,
      'startedAt': ?item.startedAt?.millisecondsSinceEpoch,
    },
    ToolCallItem() => {
      't': 'tool',
      'kind': item.kind.name,
      'target': item.target,
      'detail': ?item.detail,
      'path': ?item.path,
      if (item.results.isNotEmpty) 'results': item.results,
      'label': ?item.label,
      'status': item.status.name,
      'output': ?_head(item.output),
      'tool': ?item.tool,
      'card': ?botCard(item),
      'url': ?botImageUrl(item),
      // What a browser's call does, for its line to say.
      if (item.kind == ToolKind.browser)
        'browse': {
          'action': ?(item.input['action'] as String?),
          if (item.input['url'] != null) 'url': true,
        },
      // The pictures it returned (an image model's, a file read), but for
      // a failed call's.
      if (item.images.isNotEmpty && item.status != ToolStatus.failed)
        'images': _images(item.images),
      // Pictures under way: how many, and of what shape, for their places
      // to show as big as they will be; once its input has come.
      if (item.kind == ToolKind.image && item.input.containsKey('prompt'))
        'making': {
          'count': switch (item.input['count']) {
            final num count => count.toInt().clamp(1, 4),
            _ => 1,
          },
          'size': ?(item.input['size'] as String?),
          'aspect': ?(item.input['aspect_ratio'] as String?),
        },
    },
    AgentItem() => {
      't': 'agent',
      'description': item.description,
      'id': ?item.id,
      'agentType': ?item.agentType,
      'prompt': ?item.prompt,
      'status': item.status.name,
      'tokens': ?item.tokens,
      'toolUses': ?item.toolUses,
      'lastTool': ?item.lastTool,
      'activity': ?item.activity,
      'startedAt': ?item.startedAt?.millisecondsSinceEpoch,
      'duration': ?item.duration?.inMilliseconds,
      'model': ?item.model,
      if (item.children.isNotEmpty)
        'children': [for (final child in item.children) encode(child)],
      'result': ?item.result,
      if (item.background) 'background': true,
    },
    NoticeItem() => {'t': 'notice', 'kind': item.kind.name, 'text': item.text},
    PlanItem() => {
      't': 'plan',
      'path': item.path,
      'round': item.round,
      'title': ?item.title,
      'text': ?item.text,
      'status': item.status.name,
      'writes': item.writes,
      'feedback': ?item.feedback,
    },
    TerminalItem() => {
      't': 'terminal',
      'command': item.command,
      'output': _tail(item.output),
      'description': ?item.description,
      'status': item.status.name,
      if (item.background) 'background': true,
      'startedAt': ?item.startedAt?.millisecondsSinceEpoch,
    },
    CodeDiffItem() => {
      't': 'diff',
      'fileName': item.fileName,
      'directory': item.directory,
      'lines': [
        for (final line in item.lines)
          [line.type.index, line.lineNumber, line.text],
      ],
      'added': item.added,
      'removed': item.removed,
    },
    LiveStatusItem() => {
      't': 'live',
      'label': item.label,
      if (item.whimsical) 'whimsical': true,
      if (!item.visible) 'visible': false,
      // For the phone's line of figures under it, as the footer's here.
      'startedAt': ?item.startedAt?.millisecondsSinceEpoch,
      'tokens': ?item.output?.tokens,
      'speed': ?item.output?.tokensPerSecond,
    },
  };

  /// The item [json] is; null for one of a kind this side does not know
  /// (a newer desktop's).
  static ChatItem? decode(Object? json) {
    if (json is! Map<String, Object?>) return null;
    String text(String key) => json[key] as String? ?? '';
    String? optional(String key) => json[key] as String?;
    int? number(String key) => (json[key] as num?)?.toInt();
    DateTime? time(String key) => switch (number(key)) {
      final ms? => DateTime.fromMillisecondsSinceEpoch(ms),
      null => null,
    };
    Duration? duration(String key) => switch (number(key)) {
      final ms? => Duration(milliseconds: ms),
      null => null,
    };
    T named<T extends Enum>(List<T> values, String key, T fallback) =>
        values.asNameMap()[json[key]] ?? fallback;
    return switch (json['t']) {
      'user' => UserMessageItem(
        text: text('text'),
        queued: json['queued'] == true,
        images: _decodeImages(json['images']),
        worked: duration('worked'),
        sentAt: time('at'),
        usage: switch (json['usage']) {
          final Map<String, Object?> usage => TurnUsage(
            inputTokens: (usage['in'] as num?)?.toInt(),
            outputTokens: (usage['out'] as num?)?.toInt(),
            tokensPerSecond: (usage['speed'] as num?)?.toDouble(),
            costUsd: (usage['cost'] as num?)?.toDouble(),
          ),
          _ => null,
        },
      ),
      'text' => AssistantTextItem(text('text')),
      'thinking' => ThinkingItem(
        text: text('text'),
        tokens: number('tokens') ?? 0,
        seconds: number('seconds'),
        startedAt: time('startedAt'),
      ),
      'tool' => ToolCallItem(
        kind: named(ToolKind.values, 'kind', ToolKind.other),
        target: text('target'),
        detail: optional('detail'),
        path: optional('path'),
        results: [...?(json['results'] as List?)?.whereType<String>()],
        label: optional('label'),
        status: named(ToolStatus.values, 'status', ToolStatus.succeeded),
        output: optional('output'),
        tool: optional('tool'),
        images: _decodeImages(json['images']),
        input: switch ((json['making'], json['browse'], json['card'])) {
          (_, _, final String card) => {'chat': card},
          _ when json['sticker'] is String => {'sticker': json['sticker']},
          _ when json['url'] is String => {'url': json['url']},
          (final Map<String, Object?> making, _, _) => {
            'prompt': '',
            'count': ?making['count'],
            'size': ?making['size'],
            'aspect_ratio': ?making['aspect'],
          },
          (_, final Map<String, Object?> browse, _) => {
            'action': ?browse['action'],
            if (browse['url'] == true) 'url': '',
          },
          _ => const {},
        },
      ),
      'agent' => AgentItem(
        description: text('description'),
        id: optional('id'),
        agentType: optional('agentType'),
        prompt: optional('prompt'),
        status: named(CommandStatus.values, 'status', CommandStatus.running),
        tokens: number('tokens'),
        toolUses: number('toolUses'),
        lastTool: optional('lastTool'),
        activity: optional('activity'),
        startedAt: time('startedAt'),
        duration: duration('duration'),
        model: optional('model'),
        children: [
          for (final child in (json['children'] as List?) ?? const [])
            ?decode(child),
        ],
        result: optional('result'),
        background: json['background'] == true,
      ),
      'notice' => NoticeItem(
        named(NoticeKind.values, 'kind', NoticeKind.info),
        text('text'),
      ),
      'plan' => PlanItem(
        path: text('path'),
        round: number('round') ?? 1,
        title: optional('title'),
        text: optional('text'),
        status: named(PlanStatus.values, 'status', PlanStatus.drafting),
        writes: number('writes') ?? 0,
        feedback: optional('feedback'),
      ),
      'terminal' => TerminalItem(
        command: text('command'),
        output: text('output'),
        description: optional('description'),
        status: named(CommandStatus.values, 'status', CommandStatus.succeeded),
        background: json['background'] == true,
        startedAt: time('startedAt'),
      ),
      'diff' => CodeDiffItem(
        fileName: text('fileName'),
        directory: text('directory'),
        lines: [
          for (final line in (json['lines'] as List?) ?? const [])
            if (line case [final int type, final int number, final String text]
                when type >= 0 && type < DiffLineType.values.length)
              DiffLine(DiffLineType.values[type], number, text),
        ],
        added: number('added'),
        removed: number('removed'),
      ),
      'live' => LiveStatusItem(
        text('label'),
        whimsical: json['whimsical'] == true,
        visible: json['visible'] != false,
        startedAt: time('startedAt'),
        output: switch (json['tokens']) {
          final num tokens => TurnOutput(
            tokens: tokens.toInt(),
            tokensPerSecond: (json['speed'] as num?)?.toDouble(),
          ),
          _ => null,
        },
      ),
      _ => null,
    };
  }

  static List<Map<String, Object?>> _images(List<ImageAttachment> images) => [
    for (final image in images)
      {
        'data': base64.encode(image.bytes),
        'type': image.mediaType,
        'name': ?image.name,
        'n': ?image.number,
      },
  ];

  static List<ImageAttachment> _decodeImages(Object? json) => [
    for (final image in (json as List?) ?? const [])
      if (image case {'data': final String data, 'type': final String type})
        ImageAttachment(
          bytes: base64.decode(data),
          mediaType: type,
          name: image['name'] as String?,
          number: (image['n'] as num?)?.toInt(),
        ),
  ];

  static String? _head(String? text) => text == null || text.length <= maxOutput
      ? text
      : '${text.substring(0, maxOutput)}\n…';

  static String _tail(String text) => text.length <= maxOutput
      ? text
      : '…\n${text.substring(text.length - maxOutput)}';
}
