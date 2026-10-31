part of 'browser_tools.dart';

// What the tabs shared with BaoCode did, kept on disk as it happens, an
// agent there or not, over the app's restarts: the pages they went to, the
// requests their pages made, the console's errors and warnings, dialogs,
// downloads. In detailed mode (Settings → Browser) the requests' and the
// responses' bodies too, every console message, and what the user did
// (clicks, typing; never a password). An agent reads it with
// browser_history ("what went wrong when I saved?"). A file a tab's
// capture, a line a record (JSON), in a folder a day.

/// The history of the shared tabs (see above): captured from the moment a
/// tab is shared, while the browsers may be used.
class BrowserHistory extends ChangeNotifier {
  BrowserHistory._();

  static final instance = BrowserHistory._();

  /// settings.json's `browser.history.detailed`: whether the bodies, every
  /// console message and the user's steps are kept too. Unset: off.
  static const detailedKey = 'browser.history.detailed';

  /// From this size on, the settings say to clear it.
  static const warnSize = 1 << 30;

  /// A test's own folder.
  @visibleForTesting
  static String? folderOverride;

  /// Where it is kept: the data folder's.
  String get folder =>
      folderOverride ?? p.join(DataDirectory.current.browserDir, 'history');

  /// Whether the bodies, every console message and the user's steps are
  /// kept too.
  bool get detailed => _detailed;
  bool _detailed = false;
  set detailed(bool value) {
    if (_detailed == value) return;
    _detailed = value;
    for (final tab in [..._capturing]) {
      unawaited(value ? _hookSteps(tab) : _unhookSteps(tab));
    }
    notifyListeners();
  }

  /// Sets [detailed] from [read] now and whenever [changes] notifies.
  void follow(Listenable changes, Object? Function() read) {
    void update() => detailed = read() == true;
    update();
    changes.addListener(update);
  }

  /// How much it takes on disk, in bytes; null till measured.
  int? get size => _size;
  int? _size;

  /// Whether it takes [warnSize] or more.
  bool get tooLarge => (_size ?? 0) >= warnSize;

  /// [size] as read: `1.2 GB`.
  static String sizeText(int size) => size >= 1 << 30
      ? '${(size / (1 << 30)).toStringAsFixed(1)} GB'
      : _bytes(size);

  bool _started = false;
  final Map<BrowserTab, _HistoryFile> _files = {};

  /// The files of the tabs gone, as they finish writing.
  final Set<Future<void>> _closing = {};

  /// Done when all queued so far is on disk.
  Future<void> _written() => Future.wait([
    for (final file in _files.values) file.written,
    ..._closing,
  ]);

  void _close(_HistoryFile file) {
    final closing = file.close();
    _closing.add(closing);
    unawaited(closing.whenComplete(() => _closing.remove(closing)));
  }

  /// The tabs captured (their records kept), and those the user stopped
  /// (cancelled the browser's debugging bar): left alone till shared again.
  final Set<BrowserTab> _capturing = {};
  final Set<BrowserTab> _declined = {};
  final Set<BrowserConnection> _browsers = {};

  /// Starts capturing the shared tabs: those there now, and each as it is
  /// shared.
  void start() {
    if (_started) return;
    _started = true;
    unawaited(_measure());
    BrowserRecords.instance.added.listen(_kept);
    BrowserBridge.instance.events.listen(_received);
    BrowserBridge.instance.addListener(_connections);
    _connections();
  }

  /// Stops writing (a test's end).
  @visibleForTesting
  Future<void> stop() async {
    for (final file in _files.values) {
      await file.close();
    }
    _files.clear();
    await _written();
  }

  void _connections() {
    final browsers = BrowserBridge.instance.browsers;
    _browsers.removeWhere((b) => !browsers.contains(b));
    for (final browser in browsers) {
      if (_browsers.add(browser)) unawaited(_captureShared(browser));
    }
  }

  Future<void> _captureShared(BrowserConnection browser) async {
    try {
      final tabs = await browser.request('tabs.list') as List? ?? const [];
      for (final tab in tabs.cast<Map>()) {
        if (tab['tabId'] case final int id) {
          final browserTab = BrowserTab(browser, id);
          await _capture(browserTab);
          _page(browserTab, tab);
        }
      }
    } on Object {
      // Not now: as each tab comes.
    }
  }

  Future<void> _capture(BrowserTab tab) async {
    if (!BrowserBridge.instance.enabled ||
        _declined.contains(tab) ||
        !_capturing.add(tab)) {
      return;
    }
    try {
      await BrowserRecords.instance.watch(tab);
      if (_detailed) await _hookSteps(tab);
    } on Object {
      // Not one to debug (the browser's own page): next time it changes.
      _capturing.remove(tab);
    }
  }

  void _received(BrowserEvent event) {
    final tabId = event.tabId;
    switch (event.event) {
      case 'tab':
        final info = event.message['tab'] as Map?;
        final id = info?['tabId'] as int?;
        if (info == null || id == null) return;
        final tab = BrowserTab(event.connection, id);
        unawaited(_capture(tab));
        _page(tab, info);
      case 'closed' || 'unshared' when tabId != null:
        final tab = BrowserTab(event.connection, tabId);
        _capturing.remove(tab);
        _declined.remove(tab);
        _stepScripts.remove(tab);
        final file = _files.remove(tab);
        if (file != null) {
          file.write({'t': 'end', 'why': event.event});
          _close(file);
        }
      case 'detached' when tabId != null:
        final tab = BrowserTab(event.connection, tabId);
        _capturing.remove(tab);
        _stepScripts.remove(tab);
        // The user's no to the debugging: not asked again by itself.
        if (event.message['reason'] == 'canceled_by_user') _declined.add(tab);
      case 'cdp' when tabId != null:
        final params = event.message['params'] as Map?;
        if (event.message['method'] != 'Runtime.bindingCalled' ||
            event.message['sessionId'] != null ||
            params?['name'] != _stepBinding) {
          return;
        }
        final tab = BrowserTab(event.connection, tabId);
        try {
          final step = jsonDecode(params?['payload'] as String) as Map;
          if (step['type'] == 'scroll') return;
          _write(tab, {
            't': 'step',
            'at': (step['time'] as num?)?.toInt() ?? _now,
            'kind': step['type'] ?? 'click',
            'target': step['target'],
            'selector': ?step['selector'],
            'value': ?step['value'],
            'by': BrowserRecords.instance.isActing(tab) ? 'agent' : 'user',
          });
        } on Object {
          // Not a step.
        }
    }
  }

  /// The last page written of each tab: one line for its URL and title.
  final Map<BrowserTab, String> _pages = {};

  void _page(BrowserTab tab, Map info) {
    if (info['loading'] == true || !_capturing.contains(tab)) return;
    final url = '${info['url'] ?? ''}';
    final title = '${info['title'] ?? ''}';
    if (url.isEmpty || _pages[tab] == '$url\n$title') return;
    _pages[tab] = '$url\n$title';
    _write(tab, {'t': 'page', 'at': _now, 'url': url, 'title': title});
  }

  static int get _now => DateTime.now().millisecondsSinceEpoch;

  void _kept((BrowserTab, Object) kept) {
    final (tab, record) = kept;
    switch (record) {
      case ConsoleEntry entry:
        if (!_detailed && entry.level != 'error' && entry.level != 'warning') {
          return;
        }
        List<Object?> frames(List<ScriptFrame> stack) => [
          for (final f in stack.take(10)) [f.function, f.url, f.line, f.column],
        ];
        _write(tab, {
          't': 'console',
          'at': entry.time.millisecondsSinceEpoch,
          'level': entry.level,
          'text': _clip(entry.text, 10000),
          'url': ?entry.url,
          'line': ?entry.line,
          if (entry.stack.isNotEmpty) 'stack': frames(entry.stack),
          if (entry.thrown.isNotEmpty) 'thrown': frames(entry.thrown),
          'from': ?entry.from,
        });
      case NetworkRequest request:
        unawaited(_request(tab, request));
      case BrowserDialog dialog:
        _write(tab, {
          't': 'dialog',
          'at': dialog.time.millisecondsSinceEpoch,
          'type': dialog.type,
          'message': _clip(dialog.message, 2000),
          'answer': ?dialog.answer,
          'by': ?dialog.by,
        });
      case BrowserDownload download:
        _write(tab, {
          't': 'download',
          'at': download.time.millisecondsSinceEpoch,
          'url': download.url,
          'name': download.name,
        });
    }
  }

  Future<void> _request(BrowserTab tab, NetworkRequest r) async {
    final initiator = r.initiator;
    final stack = ScriptFrame.stackOf(initiator?['stack'], max: 6);
    String? requestBody;
    if (_detailed && r.hasPostData) {
      requestBody = await BrowserRecords.instance.requestBody(tab, r);
    }
    final textual =
        !r.bodyBase64 &&
        RegExp(r'json|text|xml|javascript|html|csv|graphql|x-www-form')
            .hasMatch(r.mimeType ?? '');
    _write(tab, {
      't': 'request',
      'at': (r.wall * 1000).round(),
      'id': r.id,
      'method': r.method,
      'url': r.url,
      'type': r.type,
      'status': ?r.status,
      'statusText': ?r.statusText,
      'ms': ?r.duration,
      'size': ?r.size,
      'failure': ?r.failure,
      if (r.fromCache) 'cache': true,
      'protocol': ?r.protocol,
      'remote': ?r.remoteAddress,
      'mime': ?r.mimeType,
      if (stack.isNotEmpty)
        'initiator': [
          for (final f in stack) [f.function, f.url, f.line, f.column],
        ]
      else if (initiator?['url'] case final String url when url.isNotEmpty)
        'initiator': [
          ['', url, (initiator?['lineNumber'] as num?)?.toInt() ?? 0, 0],
        ],
      'requestHeaders': _redacted(r.sentHeaders),
      if (r.receivedHeaders case final headers?)
        'responseHeaders': _redacted(headers),
      if (_detailed && requestBody != null)
        'requestBody': _clip(requestBody, 1 << 20),
      if (_detailed && r.body != null && textual) 'responseBody': r.body,
      if (r.frames.isNotEmpty || r.framesDropped > 0)
        'messages': r.frames.length + r.framesDropped,
    });
  }

  /// The headers that give one's way in (cookies, tokens) are not kept.
  static Map<String, Object?> _redacted(Map<String, Object?> headers) => {
    for (final MapEntry(:key, :value) in headers.entries)
      key: _secretHeaders.contains(key.toLowerCase())
          ? '(not kept: ${'$value'.length} chars)'
          : value,
  };

  static const _secretHeaders = {
    'cookie',
    'set-cookie',
    'authorization',
    'proxy-authorization',
    'x-api-key',
    'x-auth-token',
    'x-csrf-token',
    'x-xsrf-token',
  };

  void _write(BrowserTab tab, Map<String, Object?> record) {
    if (!_capturing.contains(tab) && !BrowserRecords.instance.watching(tab)) {
      return;
    }
    final file = _files.putIfAbsent(tab, () => _HistoryFile.open(this, tab));
    final bytes = file.write(record);
    final before = _size ?? 0;
    _size = before + bytes;
    // Told as it crosses the line, or each megabyte.
    if ((before < warnSize) != (_size! < warnSize) ||
        before >> 20 != _size! >> 20) {
      notifyListeners();
    }
  }

  Future<void> _measure() async {
    var total = 0;
    final root = Directory(folder);
    try {
      if (root.existsSync()) {
        await for (final entity in root.list(recursive: true)) {
          if (entity is File) total += await entity.length();
        }
      }
    } on FileSystemException {
      // What could be read.
    }
    _size = (_size ?? 0) + total;
    notifyListeners();
  }

  /// Deletes all of it; what comes next is kept anew.
  Future<void> clear() async {
    for (final file in _files.values) {
      await file.close();
    }
    _files.clear();
    await _written();
    _pages.clear();
    try {
      final root = Directory(folder);
      if (root.existsSync()) await root.delete(recursive: true);
    } on FileSystemException catch (error) {
      debugPrint('browser history: $error');
    }
    _size = 0;
    notifyListeners();
  }

  // --- The user's steps (detailed): browser_watch's listeners, on their
  // own binding, in each document the tab loads.

  static const _stepBinding = '__baoHistoryStep';
  static final _stepScript = BrowserWatching._watchScript.replaceAll(
    '__baoWatch',
    '__baoHistory',
  );

  /// Each tab's script put in each document it loads.
  final Map<BrowserTab, String?> _stepScripts = {};

  Future<void> _hookSteps(BrowserTab tab) async {
    if (_stepScripts.containsKey(tab)) return;
    _stepScripts[tab] = null;
    final browser = tab.browser;
    try {
      await browser.cdp(tab.tabId, 'Runtime.addBinding', {
        'name': _stepBinding,
      });
      final added = await browser.cdp(
        tab.tabId,
        'Page.addScriptToEvaluateOnNewDocument',
        {'source': _stepScript},
      );
      _stepScripts[tab] = added['identifier'] as String?;
      await browser.cdp(tab.tabId, 'Runtime.evaluate', {
        'expression': _stepScript,
      });
    } on Object {
      _stepScripts.remove(tab);
    }
  }

  Future<void> _unhookSteps(BrowserTab tab) async {
    if (!_stepScripts.containsKey(tab)) return;
    final script = _stepScripts.remove(tab);
    for (final (method, params) in [
      ('Runtime.evaluate', {'expression': 'window.__baoHistory?.stop()'}),
      ('Runtime.removeBinding', {'name': _stepBinding}),
      if (script != null)
        ('Page.removeScriptToEvaluateOnNewDocument', {'identifier': script}),
    ]) {
      try {
        await tab.browser.cdp(tab.tabId, method, params);
      } on Object {
        // Gone with the tab.
      }
    }
  }

  // --- Read back.

  /// The records from [since] to [until], oldest first: of the files
  /// written meanwhile, each line that [keep] keeps.
  Future<List<Map<String, Object?>>> read(
    DateTime since,
    DateTime until,
    bool Function(Map<String, Object?> record) keep,
  ) async {
    await _written();
    final root = Directory(folder);
    if (!root.existsSync()) return const [];
    final out = <Map<String, Object?>>[];
    final from = since.millisecondsSinceEpoch;
    final to = until.millisecondsSinceEpoch;
    final days = [
      for (final entity in root.listSync())
        if (entity is Directory) entity,
    ];
    for (final day in days) {
      // A day's folder: of no use before since's day, nor after until's.
      final date = DateTime.tryParse(p.basename(day.path));
      if (date != null &&
          (date.add(const Duration(days: 1)).isBefore(since) ||
              date.isAfter(until))) {
        continue;
      }
      for (final file in day.listSync().whereType<File>()) {
        if (!file.path.endsWith('.jsonl')) continue;
        if (file.lastModifiedSync().isBefore(since)) continue;
        String? tab;
        await for (final line
            in file
                .openRead()
                .transform(utf8.decoder)
                .transform(const LineSplitter())) {
          Map<String, Object?> record;
          try {
            record = (jsonDecode(line) as Map).cast<String, Object?>();
          } on FormatException {
            continue;
          }
          if (record['t'] == 'tab') {
            tab = '${record['tabId']}';
            continue;
          }
          final at = (record['at'] as num?)?.toInt() ?? 0;
          if (at < from || at > to) continue;
          record['tab'] = tab;
          if (keep(record)) out.add(record);
        }
      }
    }
    out.sort(
      (a, b) => ((a['at'] as num?) ?? 0).compareTo((b['at'] as num?) ?? 0),
    );
    return out;
  }
}

/// A tab's capture, as a file of the history's: each record queued as it
/// comes and written off the main thread, those that came meanwhile
/// together (a busy page's records, megabytes a second, kept the UI from
/// its frames when written there); read back once [written].
class _HistoryFile {
  _HistoryFile._(this.file);

  factory _HistoryFile.open(BrowserHistory history, BrowserTab tab) {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final day = '${now.year}-${two(now.month)}-${two(now.day)}';
    final name =
        '${two(now.hour)}${two(now.minute)}${two(now.second)}-'
        '${(tab.browser.browser ?? 'browser').replaceAll(RegExp(r'[^\w]+'), '-')}-'
        '${tab.tabId}.jsonl';
    final path = File(p.join(history.folder, day, name))
      ..parent.createSync(recursive: true);
    final opened = _HistoryFile._(path.openSync(mode: FileMode.append));
    final bytes = opened.write({
      't': 'tab',
      'at': now.millisecondsSinceEpoch,
      'tabId': tab.tabId,
      'browser': tab.browser.browser,
    });
    history._size = (history._size ?? 0) + bytes;
    return opened;
  }

  final RandomAccessFile file;
  bool _closed = false;

  /// The lines not yet written, and the writing of those before.
  final _queued = BytesBuilder(copy: false);
  Future<void>? _writing;

  /// Done when the lines queued so far are on disk.
  Future<void> get written => _writing ?? Future.value();

  /// Queues [record], a line: its bytes.
  int write(Map<String, Object?> record) {
    if (_closed) return 0;
    final line = utf8.encode('${jsonEncode(record)}\n');
    _queued.add(line);
    _writing ??= _drain();
    return line.length;
  }

  Future<void> _drain() async {
    try {
      while (_queued.isNotEmpty) {
        await file.writeFrom(_queued.takeBytes());
      }
    } on FileSystemException catch (error) {
      debugPrint('browser history: $error');
      _queued.clear();
    } finally {
      _writing = null;
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await written;
    try {
      await file.close();
    } on FileSystemException {
      // Gone.
    }
  }
}

/// [text] as a time: `30m`, `2h`, `3d` ago, or a date and time; null if
/// it is neither.
DateTime? _historyTime(String? text, DateTime now) {
  if (text == null || text.trim().isEmpty) return null;
  final ago = RegExp(r'^(\d+)\s*([smhd])$').firstMatch(text.trim());
  if (ago != null) {
    final n = int.parse(ago[1]!);
    return now.subtract(switch (ago[2]) {
      's' => Duration(seconds: n),
      'm' => Duration(minutes: n),
      'h' => Duration(hours: n),
      _ => Duration(days: n),
    });
  }
  return DateTime.tryParse(text.trim());
}

final _historyTool = ClaudeSdkTool(
  name: 'browser_history',
  description:
      'What happened in the tabs shared with BaoCode, kept as it happened '
      'even when no agent was looking, over restarts and in closed tabs: '
      'the pages gone to, the requests (method, status, time, initiator, '
      'headers), console errors and warnings, dialogs, downloads; with '
      'detailed history on (Settings → Browser), also the request and '
      'response bodies, every console message, and what the user did '
      '(clicks, typing; by "user" or "agent"). For what the user did '
      'before asking ("it failed when I saved"): look back here first, '
      'rather than asking them to do it again. Oldest first; id reads a '
      "request whole. Cookies and tokens are not kept.",
  inputSchema: {
    'type': 'object',
    'properties': {
      'since': {
        'type': 'string',
        'description':
            'How far back: 10m, 2h, 3d, or a local time '
            '(2026-10-17T14:00). Default 30m.',
      },
      'until': {'type': 'string', 'description': 'Up to (as since).'},
      'tabId': {'type': 'integer', 'description': 'One tab\'s alone.'},
      'kinds': {
        'type': 'array',
        'items': {
          'type': 'string',
          'enum': ['page', 'request', 'console', 'step', 'dialog', 'download'],
        },
        'description': 'Which records (all by default).',
      },
      'url': {
        'type': 'string',
        'description': 'Those of a request or page whose URL has it.',
      },
      'failed': {
        'type': 'boolean',
        'description':
            'Requests that failed or got 400 or more, console errors.',
      },
      'query': {
        'type': 'string',
        'description': 'Those that have this text (a body too).',
      },
      'id': {
        'type': 'string',
        'description': 'A request\'s id: all of it (headers, bodies).',
      },
      'limit': {'type': 'integer', 'description': 'The last n. Default 200.'},
    },
  },
  run: (input, call) async {
    final history = BrowserHistory.instance;
    final now = DateTime.now();
    final since =
        _historyTime(input['since'] as String?, now) ??
        now.subtract(
          input['id'] != null
              ? const Duration(days: 30)
              : const Duration(minutes: 30),
        );
    final until = _historyTime(input['until'] as String?, now) ?? now;
    final tabId = input['tabId'] as int?;
    final kinds = {for (final k in input['kinds'] as List? ?? const []) '$k'};
    final url = input['url'] as String?;
    final failed = input['failed'] == true;
    final query = (input['query'] as String?)?.toLowerCase();
    final id = input['id'] as String?;
    final records = await history.read(since, until, (r) {
      if (tabId != null && r['tab'] != '$tabId') return false;
      if (id != null) return r['t'] == 'request' && r['id'] == id;
      if (kinds.isNotEmpty && !kinds.contains(r['t'])) return false;
      if (url != null &&
          !'${r['url'] ?? ''}'.contains(url) &&
          r['t'] != 'console' &&
          r['t'] != 'step') {
        return false;
      }
      if (failed) {
        final bad = switch (r['t']) {
          'request' =>
            r['failure'] != null || ((r['status'] as num?) ?? 0) >= 400,
          'console' => r['level'] == 'error',
          _ => false,
        };
        if (!bad) return false;
      }
      if (query != null && !jsonEncode(r).toLowerCase().contains(query)) {
        return false;
      }
      return true;
    });
    final browsers = BrowserBridge.instance.browsers;
    BrowserTab? live(Object? tab) {
      final id = int.tryParse('$tab');
      if (id == null || browsers.isEmpty) return null;
      final open = BrowserTab(browsers.first, id);
      return BrowserRecords.instance.watching(open) ? open : null;
    }

    if (id != null) {
      final r = records.lastOrNull;
      if (r == null) return 'No request $id kept in the last 30 days.';
      return _historyRequest(r, live(r['tab']));
    }
    final note = history.detailed
        ? null
        : '(Detailed history is off: bodies, every console message and the '
              "user's steps are not kept. Settings → Browser turns it on.)";
    if (records.isEmpty) {
      return [
        'Nothing kept from ${_historyClock(since)} to ${_historyClock(until)}'
            '${tabId == null ? '' : ' in tab $tabId'}.',
        ?note,
      ].join('\n');
    }
    final limit = (input['limit'] as int? ?? 200).clamp(1, 2000);
    final shown = records.length > limit
        ? records.sublist(records.length - limit)
        : records;
    final lines = <String>[
      if (shown.length < records.length)
        'The last ${shown.length} of ${records.length}:',
    ];
    for (final r in shown) {
      lines.addAll(await _historyLine(r, live(r['tab'])));
    }
    if (note != null) lines.add(note);
    return _clip(lines.join('\n'), 60000);
  },
);

String _historyClock(DateTime at) {
  String two(int n) => n.toString().padLeft(2, '0');
  final today = DateTime.now();
  final day =
      at.year == today.year && at.month == today.month && at.day == today.day
      ? ''
      : '${at.year}-${two(at.month)}-${two(at.day)} ';
  return '$day${two(at.hour)}:${two(at.minute)}:${two(at.second)}';
}

List<ScriptFrame> _historyFrames(Object? frames) => [
  for (final f in (frames as List? ?? const []).cast<List>())
    ScriptFrame(
      '${f[0]}',
      '${f[1]}',
      (f[2] as num).toInt(),
      (f[3] as num).toInt(),
    ),
];

/// [r]'s lines; its calls mapped to the sources where its [tab] is still
/// open (and so its scripts' maps).
Future<List<String>> _historyLine(
  Map<String, Object?> r,
  BrowserTab? tab,
) async {
  final at = _historyClock(
    DateTime.fromMillisecondsSinceEpoch((r['at'] as num?)?.toInt() ?? 0),
  );
  final head = '[$at] tab ${r['tab']}';
  Future<List<String>> stack(Object? frames, {int max = 3}) async {
    final list = _historyFrames(frames);
    if (list.isEmpty) return const [];
    if (tab != null) return _stackLines(tab, list, max: max);
    return [for (final f in list.take(max)) '    at $f'];
  }

  switch (r['t']) {
    case 'page':
      return [
        '$head page ${r['url']}${'${r['title'] ?? ''}'.isEmpty ? '' : ' — "${r['title']}"'}',
      ];
    case 'request':
      final status = r['failure'] ?? r['status'] ?? 'pending';
      return [
        '$head ${r['method']} $status ${r['type']}'
            '${r['ms'] == null ? '' : ' ${r['ms']} ms'} ${_clip('${r['url']}', 300)} (${r['id']})',
      ];
    case 'console':
      return [
        '$head console ${r['level']}${r['from'] == null ? '' : ' (${r['from']})'}: '
            '${_clip('${r['text']}', 1000)}',
        if (r['level'] == 'error') ...await stack(r['thrown'] ?? r['stack']),
      ];
    case 'step':
      final step = WatchedStep(
        kind: '${r['kind']}',
        at: Duration.zero,
        target: '${r['target'] ?? ''}',
        selector: r['selector'] as String?,
        value: r['value'] as String?,
      );
      return ['$head ${r['by'] ?? 'user'} ${step.describe()}'];
    case 'dialog':
      return [
        '$head ${r['type']} dialog "${_clip('${r['message']}', 200)}"'
            '${r['answer'] == null ? '' : ': ${r['answer']}${r['by'] == null ? '' : ' by ${r['by']}'}'}',
      ];
    case 'download':
      return [
        '$head downloaded ${r['name']} from ${_clip('${r['url']}', 200)}',
      ];
  }
  return const [];
}

/// A request kept, all of it.
Future<String> _historyRequest(Map<String, Object?> r, BrowserTab? tab) async {
  String headers(Object? map) => [
    for (final MapEntry(:key, :value)
        in ((map as Map?) ?? const {}).cast<String, Object?>().entries)
      '  $key: $value',
  ].join('\n');
  final initiator = _historyFrames(r['initiator']);
  return [
    '${r['method']} ${r['url']}',
    'Id: ${r['id']}, tab ${r['tab']}, type ${r['type']}, at '
        '${_historyClock(DateTime.fromMillisecondsSinceEpoch((r['at'] as num?)?.toInt() ?? 0))}'
        '${r['protocol'] == null ? '' : ', ${r['protocol']}'}'
        '${r['remote'] == null ? '' : ', from ${r['remote']}'}',
    if (initiator.isNotEmpty) ...[
      'Made by:',
      ...(tab != null
          ? await _stackLines(tab, initiator, indent: '  ')
          : [for (final f in initiator) '  at $f']),
    ],
    'Request headers:',
    headers(r['requestHeaders']),
    if (r['requestBody'] case final String body) ...[
      'Request body:',
      _clip(body, 20000),
    ],
    '',
    'Status: ${r['failure'] ?? '${r['status'] ?? '?'} ${r['statusText'] ?? ''}'}'
        '${r['ms'] == null ? '' : ', ${r['ms']} ms'}'
        '${r['size'] == null ? '' : ', ${_bytes((r['size'] as num).toInt())}'}',
    if (r['responseHeaders'] != null) ...[
      'Response headers:',
      headers(r['responseHeaders']),
    ],
    if (r['responseBody'] case final String body) ...[
      'Response body:',
      _clip(body, 20000),
    ] else
      BrowserHistory.instance.detailed
          ? '(No response body kept: not text, or too large.)'
          : '(No response body: detailed history was off.)',
    if (r['messages'] case final num n) 'Messages: $n',
  ].join('\n');
}
