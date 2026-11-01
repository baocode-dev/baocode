import 'dart:convert';
import 'dart:math';

/// One leg of a request's way: its line (a request's method and address,
/// or an answer's status), its headers, its body as it went (an answer's
/// events as they came, whole), when it started.
class UsageTraceMessage {
  UsageTraceMessage({
    this.method,
    this.url,
    this.status,
    Map<String, String>? headers,
    this.at,
    String body = '',
    this.truncated = false,
    int? length,
  }) : headers = headers ?? {},
       _body = StringBuffer(body),
       _length = length ?? body.length;

  final String? method;
  final String? url;
  int? status;
  final Map<String, String> headers;

  /// From the request's start.
  Duration? at;
  final StringBuffer _body;
  int _length;

  /// Cut at [maxBody]: the rest was not kept.
  bool truncated;

  /// How much of a body is kept, in characters.
  static const maxBody = 24 * 1024 * 1024;

  String get body => _body.toString();

  /// The body's length as it went, kept or not.
  int get length => _length;

  void write(String text) {
    _length += text.length;
    if (truncated) return;
    final room = maxBody - _body.length;
    if (text.length <= room) {
      _body.write(text);
    } else {
      _body.write(text.substring(0, max(0, room)));
      truncated = true;
    }
  }

  Map<String, Object?> toJson() => {
    'method': ?method,
    'url': ?url,
    'status': ?status,
    if (headers.isNotEmpty) 'headers': headers,
    'at': ?at?.inMicroseconds,
    'body': body,
    if (truncated) 'truncated': true,
    'length': _length,
  };

  static UsageTraceMessage? fromJson(Object? json) {
    if (json is! Map) return null;
    return UsageTraceMessage(
      method: json['method'] as String?,
      url: json['url'] as String?,
      status: (json['status'] as num?)?.toInt(),
      headers: switch (json['headers']) {
        final Map<Object?, Object?> map => {
          for (final MapEntry(:key, :value) in map.entries) '$key': '$value',
        },
        _ => null,
      },
      at: switch (json['at']) {
        final num us => Duration(microseconds: us.toInt()),
        _ => null,
      },
      body: '${json['body'] ?? ''}',
      truncated: json['truncated'] == true,
      length: (json['length'] as num?)?.toInt(),
    );
  }

  /// [name]'s [value], as kept: a key, a token, a cookie only by its ends.
  static String redact(String name, String value) {
    final lower = name.toLowerCase();
    final secret =
        lower == 'authorization' ||
        lower == 'proxy-authorization' ||
        lower.contains('cookie') ||
        lower.contains('key') ||
        lower.contains('token') ||
        lower.contains('secret') ||
        lower.contains('password');
    if (!secret) return value;
    final bearer = value.startsWith('Bearer ') ? 'Bearer ' : '';
    final key = value.substring(bearer.length);
    if (key.length <= 12) return '$bearer••••';
    return '$bearer${key.substring(0, 4)}••••${key.substring(key.length - 4)}';
  }

  /// [each]'s headers, their secrets cut down ([redact]).
  static Map<String, String> headersOf(
    void Function(void Function(String name, List<String> values)) each,
  ) {
    final headers = <String, String>{};
    each((name, values) => headers[name] = redact(name, values.join(', ')));
    return headers;
  }
}

/// A request through the model proxy, kept whole while debugging: as
/// Claude Code sent it, as it went to the upstream (each try: a ChatGPT
/// account out of quota gives way to the next), as the upstream answered,
/// and as it was answered back. Large; kept apart from the calls, a file
/// each (UsageLedger), and only while [UsageLedger.trace] is on.
class UsageTrace {
  UsageTrace(this.id, {DateTime? at}) : at = at ?? DateTime.now() {
    _watch.start();
  }

  final String id;
  final DateTime at;
  final Stopwatch _watch = Stopwatch();

  /// From Claude Code.
  UsageTraceMessage? request;

  /// To the upstream, and its answers, a try each.
  final List<UsageTraceMessage> sent = [];
  final List<UsageTraceMessage> received = [];

  /// Back to Claude Code; [passedOn] where it is the upstream's own.
  UsageTraceMessage? answer;
  bool passedOn = false;

  final _utf8 = const Utf8Decoder(allowMalformed: true);
  ByteConversionSink? _bytes;

  static String newId(DateTime at) {
    final random = Random();
    return '${at.millisecondsSinceEpoch.toRadixString(36)}'
        '${random.nextInt(1 << 30).toRadixString(36).padLeft(6, '0')}';
  }

  Duration get _now => _watch.elapsed;

  void asked({
    required String method,
    required String url,
    required Map<String, String> headers,
    required String body,
  }) => request = UsageTraceMessage(
    method: method,
    url: url,
    headers: headers,
    body: body,
    at: Duration.zero,
  );

  /// A try to the upstream, as it goes.
  void sending({
    required String method,
    required Uri url,
    required Map<String, String> headers,
    required String body,
  }) {
    _bytes?.close();
    _bytes = null;
    sent.add(
      UsageTraceMessage(
        method: method,
        url: url.toString(),
        headers: headers,
        body: body,
        at: _now,
      ),
    );
  }

  /// Its answer's status and headers.
  void answered(int status, Map<String, String> headers) => received.add(
    UsageTraceMessage(status: status, headers: headers, at: _now),
  );

  UsageTraceMessage get _received => received.isEmpty
      ? (received..add(UsageTraceMessage(at: _now))).last
      : received.last;

  /// Its answer's body, text as it comes.
  void upstreamText(String text) => _received.write(text);

  /// Its answer's body, bytes as they come (an upstream of Anthropic's API,
  /// passed on as they are).
  void upstreamBytes(List<int> chunk) {
    final target = _received;
    _bytes ??= _utf8.startChunkedConversion(_Sink(target.write));
    _bytes!.add(chunk);
  }

  /// What went back to Claude Code: text as it went.
  void answerText(String text) =>
      (answer ??= UsageTraceMessage(at: _now)).write(text);

  /// Done: what Claude Code was answered with.
  void finish(int status, Map<String, String> headers) {
    _bytes?.close();
    _bytes = null;
    _watch.stop();
    final kept = answer;
    answer = UsageTraceMessage(
      status: status,
      headers: headers,
      at: kept?.at ?? _now,
      body: kept?.body ?? '',
      truncated: kept?.truncated ?? false,
      length: kept?.length,
    );
  }

  /// How long it took, all of it.
  Duration get elapsed => _watch.elapsed;

  Map<String, Object?> toJson() => {
    'v': 1,
    'id': id,
    't': at.millisecondsSinceEpoch,
    'd': duration.inMicroseconds,
    'request': ?request?.toJson(),
    'sent': [for (final message in sent) message.toJson()],
    'received': [for (final message in received) message.toJson()],
    'answer': ?answer?.toJson(),
    if (passedOn) 'passedOn': true,
  };

  /// As read back.
  static UsageTrace? fromJson(Object? json) {
    if (json is! Map || json['id'] is! String) return null;
    final trace = UsageTrace(
      json['id'] as String,
      at: DateTime.fromMillisecondsSinceEpoch(
        (json['t'] as num?)?.toInt() ?? 0,
      ),
    ).._watch.stop();
    trace._duration = Duration(microseconds: (json['d'] as num?)?.toInt() ?? 0);
    trace.request = UsageTraceMessage.fromJson(json['request']);
    for (final message in (json['sent'] as List?) ?? const []) {
      if (UsageTraceMessage.fromJson(message) case final read?) {
        trace.sent.add(read);
      }
    }
    for (final message in (json['received'] as List?) ?? const []) {
      if (UsageTraceMessage.fromJson(message) case final read?) {
        trace.received.add(read);
      }
    }
    trace.answer = UsageTraceMessage.fromJson(json['answer']);
    trace.passedOn = json['passedOn'] == true;
    return trace;
  }

  Duration? _duration;

  /// How long it took, as kept.
  Duration get duration => _duration ?? elapsed;
}

class _Sink implements Sink<String> {
  _Sink(this._add);

  final void Function(String text) _add;

  @override
  void add(String data) => _add(data);

  @override
  void close() {}
}
