import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

/// One transport under a [ResumableChannel]: an SSH connection's stdin and
/// stdout, a socket. Ends when [input] does, or when [close]d.
class ChannelLink {
  ChannelLink({
    required this.input,
    required this.write,
    required this.close,
    this.patient,
  });

  final Stream<List<int>> input;
  final void Function(List<int> bytes) write;
  final void Function() close;

  /// While true, silence does not end it: the user is being asked to sign
  /// in, say.
  final bool Function()? patient;
}

/// Why a [ResumableChannel] ended for good.
enum ChannelEnd {
  /// [ResumableChannel.close]d.
  closed,

  /// The other side has no such session any more (its grace ran out, or
  /// it was ended).
  gone,

  /// The two sides disagree on what each has had of the other: not the
  /// same session.
  mismatch,

  /// More was waiting for the other side, while unlinked, than is kept.
  overflow,
}

/// Lines of text between two sides that outlive the transport under them:
/// a link lost (a network cut, a silent one too), the next one attached
/// carries on where it stopped, nothing lost, nothing twice.
///
/// Each side counts the messages it has had. A link begins with each
/// saying its count (`H<n>`); each sends again what the other has not had,
/// kept until acknowledged (`A<n>`, every [heartbeat] and every so many
/// messages, which also tells the other side the link is alive). A link
/// heard nothing on for [silence] is dropped, as a lost one would be. A
/// message goes as `:<text>`; a line cut short by a lost link is never
/// taken for one.
class ResumableChannel {
  ResumableChannel({
    this.heartbeat = const Duration(seconds: 5),
    this.silence = const Duration(seconds: 30),
    this.maxUnlinked = 128 << 20,
    this.onLinkDrop,
  });

  final Duration heartbeat;
  final Duration silence;

  /// How many characters of messages, not yet acknowledged, are kept while
  /// unlinked; past it the channel ends ([ChannelEnd.overflow]).
  final int maxUnlinked;

  /// Called when an active or connecting link is dropped, with why (`eof`,
  /// `read_error`, `silence`, `bad_ack`, `write_error`, `replaced`, `detached`,
  /// `ended`) and how long since the last bytes arrived.
  final void Function(String reason, Duration silentFor, {required bool wasLive})?
  onLinkDrop;

  /// The bridge's word that it found no session to resume.
  static const goneLine = 'BAOCODE-GONE';

  /// How many messages may come in before they are acknowledged, beside
  /// [heartbeat].
  static const _ackEvery = 64;

  final StreamController<String> _messages = StreamController();
  final StreamController<bool> _links = StreamController.broadcast();
  final Completer<ChannelEnd> _ended = Completer();

  final Queue<String> _unacked = Queue();
  int _unackedLength = 0;

  /// How many of ours the other side has had.
  int _acked = 0;
  int get _sent => _acked + _unacked.length;

  /// How many of the other side's we have had, and said we had.
  int _received = 0;
  int _ackedReceived = 0;

  _Link? _link;

  /// The other side's messages, in order, each once; done when the channel
  /// ends. Single subscription.
  Stream<String> get messages => _messages.stream;

  /// Whether a link is up (its handshake done).
  bool get linked => _link?.live ?? false;

  /// [linked] as it changes.
  Stream<bool> get linkChanges => _links.stream;

  /// Completes, with why, once the channel has ended for good.
  Future<ChannelEnd> get ended => _ended.future;

  bool get isClosed => _ended.isCompleted;

  /// How many of the other side's messages have come.
  int get received => _received;

  /// Sends [message] (one line: no line break in it), now if linked, else
  /// once a link is.
  void send(String message) {
    if (isClosed) return;
    _unacked.add(message);
    _unackedLength += message.length;
    final link = _link;
    if (link != null && link.live) {
      link.writeMessage(message);
    } else {
      _checkOverflow();
    }
  }

  /// Carries on over [link], dropping the one before. Completes once it is
  /// gone (lost, silent, replaced, or the channel ended).
  Future<void> attach(ChannelLink link) {
    if (isClosed) {
      link.close();
      return Future.value();
    }
    _drop(reason: 'replaced');
    final attached = _Link(this, link);
    _link = attached;
    attached.start();
    return attached.gone.future;
  }

  /// Drops the link there is, as a lost one: the next [attach] carries on.
  void detach() => _drop(reason: 'detached');

  /// Ends the channel for good.
  void close() => _end(ChannelEnd.closed);

  void _drop({_Link? only, required String reason}) {
    final link = _link;
    if (link == null || (only != null && !identical(link, only))) return;
    _link = null;
    final wasLive = link.live;
    final silentFor = link.heardElapsed;
    link.stop();
    onLinkDrop?.call(reason, silentFor, wasLive: wasLive);
    if (wasLive && !_links.isClosed) _links.add(false);
    _checkOverflow();
  }

  void _checkOverflow() {
    if (!linked && _unackedLength > maxUnlinked) _end(ChannelEnd.overflow);
  }

  void _end(ChannelEnd why) {
    if (isClosed) return;
    _ended.complete(why);
    _drop(reason: 'ended:${why.name}');
    _unacked.clear();
    _unackedLength = 0;
    unawaited(_messages.close());
    unawaited(_links.close());
  }

  /// The other side has had [count] of ours: what it has had is let go.
  /// False for a count that cannot be.
  bool _ackTo(int count) {
    if (count < _acked || count > _sent) return false;
    while (_acked < count) {
      _unackedLength -= _unacked.removeFirst().length;
      _acked++;
    }
    return true;
  }

  /// [link]'s handshake: the other side has had [count] of ours.
  void _resumed(_Link link, int count) {
    if (!_ackTo(count)) {
      _end(ChannelEnd.mismatch);
      return;
    }
    link.live = true;
    // A copy: a write failing drops the link, which may end the channel.
    for (final message in [..._unacked]) {
      link.writeMessage(message);
    }
    if (!_links.isClosed) _links.add(true);
  }

  void _receive(_Link link, String line) {
    if (line.isEmpty) return;
    if (!link.live) {
      if (line == goneLine) {
        _end(ChannelEnd.gone);
      } else if (line.startsWith('H')) {
        final count = int.tryParse(line.substring(1));
        if (count != null) _resumed(link, count);
      }
      // Else what a shell's startup files said before the bridge started.
      return;
    }
    switch (line[0]) {
      case ':':
        _received++;
        _messages.add(line.substring(1));
        if (_received - _ackedReceived >= _ackEvery) link.writeAck();
      case 'A':
        final count = int.tryParse(line.substring(1));
        if (count == null || !_ackTo(count)) _drop(only: link, reason: 'bad_ack');
    }
  }
}

class _Link {
  _Link(this._channel, this._link);

  final ResumableChannel _channel;
  final ChannelLink _link;
  final Completer<void> gone = Completer();
  final Stopwatch _heard = Stopwatch();
  Duration get heardElapsed => _heard.elapsed;
  StreamSubscription<List<int>>? _subscription;
  Timer? _timer;
  BytesBuilder _partial = BytesBuilder(copy: false);
  bool live = false;
  bool _stopped = false;

  void start() {
    _heard.start();
    _subscription = _link.input.listen(
      _bytes,
      onDone: () => _channel._drop(only: this, reason: 'eof'),
      onError: (Object _) => _channel._drop(only: this, reason: 'read_error'),
      cancelOnError: true,
    );
    _write('H${_channel._received}\n');
    _timer = Timer.periodic(_channel.heartbeat, (_) => _tick());
  }

  void _tick() {
    if (_heard.elapsed > _channel.silence &&
        !(_link.patient?.call() ?? false)) {
      _channel._drop(only: this, reason: 'silence');
      return;
    }
    if (live) writeAck();
  }

  void _bytes(List<int> data) {
    _heard.reset();
    var start = 0;
    for (var i = 0; i < data.length; i++) {
      if (data[i] != 0x0A) continue;
      final Uint8List line;
      if (_partial.isEmpty) {
        line = Uint8List.sublistView(
          data is Uint8List ? data : Uint8List.fromList(data),
          start,
          i,
        );
      } else {
        _partial.add(data.sublist(start, i));
        line = _partial.takeBytes();
      }
      start = i + 1;
      _channel._receive(this, utf8.decode(line, allowMalformed: true));
      if (_stopped) return;
    }
    // What follows the last line break: the start of a line, kept until
    // its end comes (never, if the link is lost first).
    if (start < data.length) _partial.add(data.sublist(start));
  }

  void writeMessage(String message) {
    _write(':');
    _write(message);
    _write('\n');
  }

  void writeAck() {
    _channel._ackedReceived = _channel._received;
    _write('A${_channel._received}\n');
  }

  void _write(String text) {
    if (_stopped) return;
    try {
      _link.write(utf8.encode(text));
    } on Object {
      _channel._drop(only: this, reason: 'write_error');
    }
  }

  void stop() {
    if (_stopped) return;
    _stopped = true;
    _timer?.cancel();
    unawaited(_subscription?.cancel());
    _partial = BytesBuilder(copy: false);
    try {
      _link.close();
    } on Object {
      // Gone already.
    }
    gone.complete();
  }
}
