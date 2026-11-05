part of 'browser_tools.dart';

// The agents' Sources panel: a tab's scripts and the sources they were built
// of (their source maps), breakpoints of every kind, and the page paused
// there: its calls, their variables, a step at a time. The Debugger domain
// is on from the first time a tab's scripts are asked about, its pauses
// skipped (a `debugger;` statement too) until an agent asks for one.

/// A script of a tab's page, as the Debugger domain told it.
class _Script {
  _Script(this.id, this.url, this.sourceMapUrl, this.lines);

  final String id;
  final String url;
  final String? sourceMapUrl;
  final int lines;
}

/// A breakpoint an agent set, of any kind.
class _Breakpoint {
  _Breakpoint(this.id, this.kind, this.description, {this.cdpId, this.undo});

  /// Ours: `b1`…
  final String id;

  /// `line`, `xhr`, `event`, `dom`.
  final String kind;
  final String description;

  /// A line's, the protocol's.
  final String? cdpId;

  /// How it is taken out.
  final Future<void> Function()? undo;
  int resolved = 0;
}

/// A tab's debugging: its scripts, their source maps, the breakpoints, and
/// whether (and where) it is paused.
class _Debugging {
  _Debugging._(this.tab) {
    _subscription = BrowserBridge.instance.events.listen(_received);
  }

  static final Map<BrowserTab, _Debugging> _tabs = {};

  static _Debugging of(BrowserTab tab) =>
      _tabs.putIfAbsent(tab, () => _Debugging._(tab));

  final BrowserTab tab;
  StreamSubscription<BrowserEvent>? _subscription;
  Future<void>? _enabled;
  final Map<String, _Script> scripts = {};
  final Map<String, Future<SourceMap?>> _maps = {};
  final Map<String, Future<String?>> _sources = {};
  final List<_Breakpoint> breakpoints = [];
  int _next = 0;

  /// `none`, `uncaught`, `all`.
  String exceptions = 'none';

  /// Asked to pause (browser_debugger pause): pauses not skipped meanwhile.
  bool _pausing = false;

  /// The pause now (Debugger.paused's), if paused.
  Map<String, Object?>? paused;

  /// Where, as an agent is told first (mapped once known).
  String? pausedAt;
  final _changes = StreamController<void>.broadcast();

  bool get isPaused => paused != null;

  /// Whether [tab] is paused in the debugger now.
  static bool pausedNow(BrowserTab tab) => _tabs[tab]?.isPaused ?? false;

  /// What an agent is told of [tab] paused: where, and what to do.
  static String? pausedNote(BrowserTab tab) {
    final debugging = _tabs[tab];
    if (debugging == null || !debugging.isPaused) return null;
    return 'The page is paused in the debugger${debugging.pausedAt == null ? '' : ' (${debugging.pausedAt})'}: '
        'nothing runs in it till it goes on. Look with browser_debugger '
        '(state), step or resume it there.';
  }

  /// Completes when [tab] pauses (now, if it is).
  static Future<void> whenPaused(BrowserTab tab) {
    final debugging = _tabs[tab];
    if (debugging == null) return Completer<void>().future;
    if (debugging.isPaused) return Future.value();
    return debugging._changes.stream.firstWhere((_) => debugging.isPaused);
  }

  Future<void> enable() => _enabled ??= () async {
    final browser = tab.browser;
    try {
      await browser.cdp(tab.tabId, 'Debugger.enable', {
        'maxScriptsCacheSize': 100000000,
      });
      await _sync();
      await browser.cdp(tab.tabId, 'Debugger.setAsyncCallStackDepth', {
        'maxDepth': 16,
      });
    } on Object {
      _enabled = null;
      rethrow;
    }
    // For the banner while paused (see [_banner]).
    try {
      await browser.cdp(tab.tabId, 'DOM.enable');
      await browser.cdp(tab.tabId, 'Overlay.enable');
    } on Object {
      // No banner.
    }
  }();

  /// The page's own banner while paused, with its resume button: the user is
  /// not stuck. Only then, as DevTools does: set, Chrome lets no mouse move
  /// with a button held through to the page, paused or not, and a drag
  /// draws nothing.
  void _banner(bool shown) => unawaited(
    tab.browser
        .cdp(tab.tabId, 'Overlay.setPausedInDebuggerMessage', {
          if (shown) 'message': 'Paused in debugger (BaoCode)',
        })
        .then<void>((_) {}, onError: (_) {}),
  );

  /// Pauses skipped unless asked for: a breakpoint, exceptions, a pause.
  Future<void> _sync() async {
    final wanted = _pausing || exceptions != 'none' || breakpoints.isNotEmpty;
    await tab.browser.cdp(tab.tabId, 'Debugger.setSkipAllPauses', {
      'skip': !wanted,
    });
    await tab.browser.cdp(tab.tabId, 'Debugger.setPauseOnExceptions', {
      'state': exceptions,
    });
  }

  void _received(BrowserEvent event) {
    if (!identical(event.connection, tab.browser) || event.tabId != tab.tabId) {
      return;
    }
    switch (event.event) {
      case 'closed' || 'unshared':
        _tabs.remove(tab);
        unawaited(_subscription?.cancel());
        if (isPaused) {
          paused = null;
          _changes.add(null);
        }
        return;
      case 'detached':
        // All of it gone with the debugger: on again as asked.
        _enabled = null;
        scripts.clear();
        breakpoints.clear();
        exceptions = 'none';
        _pausing = false;
        if (isPaused) {
          paused = null;
          _changes.add(null);
        }
        return;
      case 'cdp':
        break;
      default:
        return;
    }
    if (event.message['sessionId'] != null) return;
    final params =
        (event.message['params'] as Map?)?.cast<String, Object?>() ?? {};
    switch (event.message['method']) {
      case 'Debugger.scriptParsed':
        final url = params['url'] as String? ?? '';
        final map = params['sourceMapURL'] as String?;
        scripts[params['scriptId'] as String] = _Script(
          params['scriptId'] as String,
          url,
          map == null || map.isEmpty ? null : map,
          ((params['endLine'] as num?)?.toInt() ?? 0) + 1,
        );
      case 'Runtime.executionContextsCleared':
        scripts.clear();
        _sources.clear();
      case 'Debugger.breakpointResolved':
        for (final b in breakpoints) {
          if (b.cdpId == params['breakpointId']) b.resolved++;
        }
      case 'Debugger.paused':
        paused = params;
        _pausing = false;
        pausedAt = _reason(params);
        _changes.add(null);
        _banner(true);
        unawaited(_locate(params));
      case 'Debugger.resumed':
        paused = null;
        pausedAt = null;
        _changes.add(null);
        _banner(false);
    }
  }

  Future<void> _locate(Map<String, Object?> params) async {
    final frames = (params['callFrames'] as List? ?? const []).cast<Map>();
    if (frames.isEmpty) return;
    try {
      final at = await _frameWhere(frames.first)
          .timeout(const Duration(seconds: 3));
      if (identical(paused, params)) pausedAt = '${_reason(params)} at $at';
    } on Object {
      // As it is.
    }
  }

  /// Why the page paused, in a few words.
  String _reason(Map<String, Object?> params) {
    final data = (params['data'] as Map?) ?? const {};
    final hit = (params['hitBreakpoints'] as List? ?? const []).cast<String>();
    final ours = [
      for (final b in breakpoints)
        if (hit.contains(b.cdpId)) b.id,
    ];
    return switch (params['reason']) {
      _ when ours.isNotEmpty => 'breakpoint ${ours.join(', ')}',
      'exception' || 'promiseRejection' =>
        '${params['reason'] == 'promiseRejection' ? 'promise rejection' : 'exception'}: '
            '${_clip('${data['description'] ?? data['value'] ?? ''}'.split('\n').first, 160)}',
      'XHR' => 'XHR/fetch breakpoint: ${data['url'] ?? ''}',
      'DOM' => 'DOM breakpoint: ${data['type'] ?? ''}',
      'EventListener' =>
        'event breakpoint: ${data['eventName'] ?? ''}'.replaceFirst(
          'listener:',
          '',
        ),
      'debugCommand' => 'paused (asked)',
      'other' when hit.isEmpty => 'a debugger statement, or asked',
      final reason => '$reason',
    };
  }

  /// The pause's calls.
  List<Map> get callFrames =>
      (paused?['callFrames'] as List? ?? const []).cast<Map>();

  /// Where [frame] (a call frame's) is: its script's place, and its
  /// source's.
  Future<String> _frameWhere(Map frame) async {
    final location = frame['location'] as Map;
    final script = scripts[location['scriptId']];
    return where(
      script?.url ?? frame['url'] as String? ?? '',
      (location['lineNumber'] as num).toInt(),
      (location['columnNumber'] as num?)?.toInt() ?? 0,
    );
  }

  /// [url]'s [line] and [column] (from 0) as an agent reads them: the
  /// source's place, if a map tells it, else the script's.
  Future<String> where(String url, int line, int column) async =>
      (await place(url, line, column)).text;

  /// Where [url]'s [line] and [column] (from 0) are, and the library
  /// (package) they are of, if one's: its calls are run together, as
  /// DevTools hides them. With the name of the [function] there as the
  /// source has it, where the script's is minified: the one it is in, or
  /// the one it is the start of ([definition]: a profile's, a listener's).
  Future<({String text, String? library, String? function})> place(
    String url,
    int line,
    int column, {
    String? function,
    bool definition = false,
  }) async {
    SourceMap? map;
    if (url.isNotEmpty) {
      try {
        map = await mapOf(url).timeout(const Duration(seconds: 5));
      } on Object {
        // Unmapped.
      }
    }
    final original = map?.original(line, column);
    if (original != null) {
      return (
        text: '$original',
        library: map!.ignored(original.source)
            ? _libraryOf(original.url) ?? 'a library'
            : _libraryOf(original.url),
        function: function == null
            ? null
            : _sourceName(
                function,
                map.content(original.source),
                original,
                definition: definition,
              ),
      );
    }
    return (
      text: '${url.isEmpty ? '(no url)' : url}:${line + 1}:${column + 1}',
      library: _libraryOf(url),
      function: function,
    );
  }

  Future<SourcePosition?> original(String url, int line, int column) async {
    if (url.isEmpty) return null;
    try {
      final map = await mapOf(url).timeout(const Duration(seconds: 5));
      return map?.original(line, column);
    } on Object {
      return null;
    }
  }

  /// [url]'s script's source map, if it has one.
  Future<SourceMap?> mapOf(String url) {
    _Script? script;
    for (final s in scripts.values) {
      if (s.url == url && s.sourceMapUrl != null) script = s;
    }
    if (script == null) return Future.value();
    final mapUrl = _resolveUrl(script.url, script.sourceMapUrl!);
    return _maps.putIfAbsent('$url\n$mapUrl', () async {
      final text = await _fetchText(mapUrl);
      if (text == null) return null;
      return SourceMap.parse(
        text,
        url: mapUrl.startsWith('data:') ? url : mapUrl,
      );
    });
  }

  /// The maps of all the scripts that have one: loaded (a few at a time).
  Future<List<(_Script, SourceMap)>> allMaps() async {
    final seen = <String>{};
    final mapped = [
      for (final s in scripts.values)
        if (s.sourceMapUrl != null && seen.add(s.url)) s,
    ];
    final out = <(_Script, SourceMap)>[];
    for (var i = 0; i < mapped.length; i += 6) {
      final batch = mapped.skip(i).take(6).toList();
      final maps = await Future.wait([
        for (final s in batch)
          mapOf(s.url)
              .timeout(const Duration(seconds: 10))
              .catchError((Object _) => null),
      ]);
      for (final (j, map) in maps.indexed) {
        if (map != null) out.add((batch[j], map));
      }
    }
    return out;
  }

  /// A script's text.
  Future<String?> sourceOf(String scriptId) =>
      _sources.putIfAbsent(scriptId, () async {
        try {
          final result = await tab.browser.cdp(
            tab.tabId,
            'Debugger.getScriptSource',
            {'scriptId': scriptId},
          );
          return result['scriptSource'] as String?;
        } on Object {
          return null;
        }
      });

  /// [url]'s text: a data URL's, else through the browser (its cookies,
  /// any origin), else asked as anyone would, else by the page.
  Future<String?> _fetchText(String url) async {
    if (url.startsWith('data:')) {
      final comma = url.indexOf(',');
      if (comma < 0) return null;
      final head = url.substring(5, comma);
      final data = url.substring(comma + 1);
      try {
        return head.endsWith(';base64')
            ? utf8.decode(base64Decode(data))
            : Uri.decodeComponent(data);
      } on Object {
        return null;
      }
    }
    final browser = tab.browser;
    try {
      final tree = await browser.cdp(tab.tabId, 'Page.getFrameTree');
      final frame = ((tree['frameTree'] as Map)['frame'] as Map)['id'];
      final loaded = await browser.cdp(
        tab.tabId,
        'Network.loadNetworkResource',
        {
          'frameId': frame,
          'url': url,
          'options': {'disableCache': false, 'includeCredentials': true},
        },
      );
      final resource = (loaded['resource'] as Map?) ?? const {};
      if (resource['success'] == true && resource['stream'] is String) {
        final handle = resource['stream'] as String;
        final out = StringBuffer();
        try {
          final bytes = <int>[];
          while (true) {
            final chunk = await browser.cdp(tab.tabId, 'IO.read', {
              'handle': handle,
              'size': 1 << 20,
            });
            final data = chunk['data'] as String? ?? '';
            if (chunk['base64Encoded'] == true) {
              bytes.addAll(base64Decode(data));
            } else {
              out.write(data);
            }
            if (chunk['eof'] == true) break;
          }
          if (bytes.isNotEmpty) {
            out.write(utf8.decode(bytes, allowMalformed: true));
          }
        } finally {
          unawaited(
            browser
                .cdp(tab.tabId, 'IO.close', {'handle': handle})
                .catchError((Object _) => <String, Object?>{}),
          );
        }
        return out.toString();
      }
    } on Object {
      // Not through the browser: as anyone.
    }
    if (url.startsWith('http')) {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5);
      try {
        final request = await client.getUrl(Uri.parse(url));
        final response = await request.close().timeout(
          const Duration(seconds: 10),
        );
        if (response.statusCode == 200) {
          return await utf8
              .decodeStream(response)
              .timeout(const Duration(seconds: 20));
        }
      } on Object {
        // Not reachable from here.
      } finally {
        client.close(force: true);
      }
    }
    if (isPaused) return null;
    try {
      final text = await BrowserTools._evaluate(
        browser,
        tab.tabId,
        'fetch(${jsonEncode(url)}, {credentials: "include"}).then((r) => r.ok ? r.text() : null)',
      );
      return text as String?;
    } on Object {
      return null;
    }
  }

  /// A script whose URL is [url], or ends with it, or has it; the last
  /// loaded first.
  _Script? scriptFor(String url) {
    final all = scripts.values.where((s) => s.url.isNotEmpty).toList().reversed;
    return all.where((s) => s.url == url).firstOrNull ??
        all.where((s) => s.url.endsWith(url)).firstOrNull ??
        all.where((s) => s.url.contains(url)).firstOrNull;
  }

  /// A source (of a map) [path] names: its script, map and index.
  Future<(_Script, SourceMap, int)?> originalFor(String path) async {
    for (final (script, map) in await allMaps()) {
      if (map.find(path) case final index?) return (script, map, index);
    }
    return null;
  }

  Future<_Breakpoint> addLine(
    String path,
    int line,
    int? column,
    String? condition,
  ) async {
    await enable();
    final browser = tab.browser;
    String description;
    Map<String, Object?> result;
    final original = await originalFor(path);
    if (original != null) {
      final (script, map, index) = original;
      final at = map.generated(index, line - 1);
      if (at == null) {
        throw BrowserError(
          'Nothing of ${shortSource(map.sources[index])} at line $line runs: '
          'try a line with code on it.',
        );
      }
      result = await browser.cdp(tab.tabId, 'Debugger.setBreakpointByUrl', {
        'url': script.url,
        'lineNumber': at.line,
        'columnNumber': at.column,
        'condition': ?condition,
      });
      description =
          '${shortSource(map.sources[index])}:$line '
          '(${script.url}:${at.line + 1}:${at.column + 1})';
    } else {
      result = await browser.cdp(tab.tabId, 'Debugger.setBreakpointByUrl', {
        'urlRegex': _escapeRegex(path),
        'lineNumber': line - 1,
        if (column != null) 'columnNumber': column - 1,
        'condition': ?condition,
      });
      description = '$path:$line${column == null ? '' : ':$column'}';
    }
    final cdpId = result['breakpointId'] as String;
    final b = _Breakpoint(
      'b${++_next}',
      'line',
      description,
      cdpId: cdpId,
      undo: () => browser.cdp(tab.tabId, 'Debugger.removeBreakpoint', {
        'breakpointId': cdpId,
      }),
    )..resolved = (result['locations'] as List? ?? const []).length;
    breakpoints.add(b);
    await _sync();
    return b;
  }

  Future<_Breakpoint> addOther(
    String kind,
    String description,
    Future<void> Function() set,
    Future<void> Function() undo,
  ) async {
    await enable();
    await set();
    final b = _Breakpoint('b${++_next}', kind, description, undo: undo);
    breakpoints.add(b);
    await _sync();
    return b;
  }

  Future<void> remove(_Breakpoint b) async {
    breakpoints.remove(b);
    try {
      await b.undo?.call();
    } on Object {
      // Gone with its page.
    }
    await _sync();
  }

  Future<void> setExceptions(String state) async {
    await enable();
    exceptions = state;
    await _sync();
  }

  Future<void> pause() async {
    await enable();
    _pausing = true;
    await _sync();
    await tab.browser.cdp(tab.tabId, 'Debugger.pause');
  }

  /// Waits up to [wait] for a pause; whether it is paused.
  Future<bool> waitPaused(Duration wait) async {
    if (isPaused) return true;
    try {
      await whenPaused(tab).timeout(wait);
    } on TimeoutException {
      return false;
    }
    return isPaused;
  }

  /// The pause as an agent reads it: why, the calls, the code there, and
  /// the variables of [frame]'s scopes.
  Future<String> describe({int frame = 0, bool scopes = true}) async {
    final params = paused;
    if (params == null) {
      return [
        'Not paused.',
        if (breakpoints.isNotEmpty || exceptions != 'none') ...[
          'Breakpoints:',
          ...listed(),
        ],
      ].join('\n');
    }
    final frames = callFrames;
    final lines = <String>['Paused: ${_reason(params)}'];
    if (params['reason'] == 'exception' ||
        params['reason'] == 'promiseRejection') {
      final data = (params['data'] as Map?) ?? const {};
      if (data['description'] case final String text when text.contains('\n')) {
        lines.add(_clip(text, 1500));
      }
    }
    lines
      ..add('Calls:')
      ..addAll(
        await _callLines(
          this,
          [
            for (final f in frames)
              ScriptFrame(
                f['functionName'] as String? ?? '',
                scripts[(f['location'] as Map)['scriptId']]?.url ??
                    f['url'] as String? ??
                    '',
                ((f['location'] as Map)['lineNumber'] as num).toInt(),
                ((f['location'] as Map)['columnNumber'] as num?)?.toInt() ?? 0,
              ),
          ],
          max: 20,
          call: (i, name, at) => '  #$i $name at $at',
          library: (from, to, library) =>
              '  #$from${to > from ? '–#$to' : ''}: ${to - from + 1} '
              'call${to > from ? 's' : ''} in $library',
        ),
      );
    // What scheduled them: a timer's, a promise's.
    var async = params['asyncStackTrace'] as Map?;
    var shown = 0;
    while (async != null && shown < 8) {
      final described = async['description'] as String? ?? 'async';
      final called = ScriptFrame.stackOf({
        'callFrames': async['callFrames'],
      }, max: 30);
      final listed = await _callLines(
        this,
        called,
        max: 8 - shown,
        call: (_, name, at) => '    $name at $at',
        library: (from, to, library) =>
            '    … ${to - from + 1} call${to > from ? 's' : ''} in $library',
      );
      shown += listed.length;
      lines
        ..add('  ($described)')
        ..addAll(listed);
      async = async['parent'] as Map?;
    }
    if (frame < frames.length) {
      final f = frames[frame];
      lines
        ..add('')
        ..addAll(await _code(f));
      if (scopes) {
        lines
          ..add('')
          ..addAll(await _scopes(f, frame));
      }
    }
    return lines.join('\n');
  }

  /// The code around [frame]'s place: its source's, if a map has it.
  Future<List<String>> _code(Map frame) async {
    final location = frame['location'] as Map;
    final line = (location['lineNumber'] as num).toInt();
    final column = (location['columnNumber'] as num?)?.toInt() ?? 0;
    final script = scripts[location['scriptId']];
    if (script != null) {
      final map = await mapOf(script.url).catchError((Object _) => null);
      final at = map?.original(line, column);
      final content = at == null ? null : map!.content(at.source);
      if (at != null && content != null) {
        return [
          'Code (${shortSource(at.url)}):',
          ..._around(content, at.line, at.column),
        ];
      }
    }
    final source = await sourceOf(location['scriptId'] as String);
    if (source == null) return const [];
    return [
      'Code (${script?.url.isNotEmpty == true ? script!.url : 'script ${location['scriptId']}'}):',
      ..._around(source, line, column),
    ];
  }

  /// [source]'s lines around [line] (from 0), [line] marked; a long one
  /// (minified) as the part around [column].
  static List<String> _around(String source, int line, int column) {
    final lines = source.split('\n');
    final out = <String>[];
    for (var i = line - 4; i <= line + 4; i++) {
      if (i < 0 || i >= lines.length) continue;
      var text = lines[i];
      if (text.length > 240) {
        final at = i == line ? column : 0;
        final start = (at - 120).clamp(0, text.length);
        final end = (at + 120).clamp(0, text.length);
        text =
            '${start > 0 ? '…' : ''}${text.substring(start, end)}${end < text.length ? '…' : ''}';
      }
      out.add('${i == line ? '>' : ' '}${'${i + 1}'.padLeft(6)} | $text');
    }
    return out;
  }

  /// The variables of [scope] (a call frame's) named otherwise in the
  /// source than in the minified script: theirs (the script's) to the
  /// source's, as its map's names at them say.
  Future<Map<String, String>> sourceNames(
    Map scope,
    Iterable<String> variables,
  ) async {
    final start = scope['startLocation'] as Map?;
    final end = scope['endLocation'] as Map?;
    // A module's are read off too far apart to be told right.
    if (start == null ||
        end == null ||
        scope['type'] == 'module' ||
        scope['type'] == 'global') {
      return const {};
    }
    final script = scripts[start['scriptId']];
    if (script == null) return const {};
    final map = await mapOf(script.url).catchError((Object _) => null);
    final text = map == null ? null : await sourceOf(script.id);
    if (map == null || text == null) return const {};
    final lines = text.split('\n');
    final wanted = variables.toSet();
    final from = (
      line: start['lineNumber'] as int,
      column: start['columnNumber'] as int? ?? 0,
    );
    final to = (
      line: end['lineNumber'] as int,
      column: end['columnNumber'] as int? ?? 1 << 30,
    );
    final out = <String, String>{};
    final identifier = RegExp(r'[\w$]+');
    for (final n in map.named(from.line, to.line)) {
      if ((n.line == from.line && n.column < from.column) ||
          (n.line == to.line && n.column > to.column) ||
          n.line >= lines.length) {
        continue;
      }
      final id = identifier.matchAsPrefix(lines[n.line], n.column)?[0];
      if (id == null || !wanted.contains(id) || out.containsKey(id)) continue;
      out[id] = n.name;
    }
    out.removeWhere((generated, original) => generated == original);
    return out;
  }

  /// The source's names of [frame]'s variables, to the script's: the
  /// innermost scope's first.
  Future<Map<String, String>> variablesOf(Map frame) async {
    final names = <String, String>{};
    for (final scope
        in (frame['scopeChain'] as List? ?? const []).cast<Map>()) {
      final id = (scope['object'] as Map?)?['objectId'] as String?;
      if (id == null ||
          scope['type'] == 'global' ||
          scope['type'] == 'module') {
        continue;
      }
      try {
        final result = await tab.browser.cdp(
          tab.tabId,
          'Runtime.getProperties',
          {'objectId': id, 'ownProperties': true},
        );
        final variables = [
          for (final p in (result['result'] as List? ?? const []).cast<Map>())
            '${p['name']}',
        ];
        for (final MapEntry(:key, :value) in (await sourceNames(
          scope,
          variables,
        )).entries) {
          names.putIfAbsent(value, () => key);
        }
      } on Object {
        // Not readable.
      }
    }
    return names;
  }

  Future<List<String>> _scopes(Map frame, int index) async {
    final out = <String>['Variables (#$index):'];
    // Its function's name as written (a minified script's is not).
    final function = frame['functionName'] as String? ?? '';
    final location = frame['location'] as Map;
    final written = (await place(
      scripts[location['scriptId']]?.url ?? '',
      (location['lineNumber'] as num).toInt(),
      (location['columnNumber'] as num?)?.toInt() ?? 0,
      function: function,
    )).function;
    for (final scope
        in (frame['scopeChain'] as List? ?? const []).cast<Map>()) {
      final type = scope['type'] as String? ?? '';
      if (type == 'global') continue;
      final object = scope['object'] as Map?;
      final id = object?['objectId'] as String?;
      if (id == null) continue;
      try {
        final result = await tab.browser.cdp(
          tab.tabId,
          'Runtime.getProperties',
          {'objectId': id, 'ownProperties': true, 'generatePreview': true},
        );
        final properties = (result['result'] as List? ?? const []).cast<Map>();
        // A minified script's: by the source's names, theirs after.
        final renamed = await sourceNames(scope, [
          for (final p in properties) '${p['name']}',
        ]);
        String named(Map p) => switch (renamed['${p['name']}']) {
          final original? => '$original (${p['name']})',
          _ => '${p['name']}',
        };
        final name = function.isNotEmpty && scope['name'] == function
            ? written ?? function
            : scope['name'] as String?;
        out.add(
          '  ${type[0].toUpperCase()}${type.substring(1)}'
          '${name == null || name.isEmpty ? '' : ' ($name)'}:',
        );
        if (properties.isEmpty) out.add('    (none)');
        // The values first; a module's or a closure's functions after,
        // by name.
        final values = properties
            .where((p) => (p['value'] as Map?)?['type'] != 'function')
            .toList();
        final functions = [
          for (final p in properties)
            if ((p['value'] as Map?)?['type'] == 'function') named(p),
        ];
        for (final p in values.take(30)) {
          out.add(
            '    ${named(p)} = ${_clip(_remoteText(p['value'] as Map?), 300)}',
          );
        }
        if (values.length > 30) out.add('    … ${values.length - 30} more');
        if (functions.isNotEmpty) {
          out.add('    functions: ${_clip(functions.join(', '), 400)}');
        }
      } on Object {
        // Not readable.
      }
      if (index == 0 && frame['this'] is Map && type == 'local') {
        out.add('    this = ${_clip(_remoteText(frame['this'] as Map), 200)}');
      }
    }
    return out;
  }

  List<String> listed() => [
    if (exceptions != 'none')
      '  pauses on ${exceptions == 'all' ? 'all exceptions' : 'uncaught exceptions'}',
    for (final b in breakpoints)
      '  ${b.id} ${b.kind == 'line' ? '' : '${b.kind} '}${b.description}'
          '${b.kind == 'line' && b.resolved == 0 ? ' (not in a script loaded yet: bound when one is)' : ''}',
  ];
}

/// A value of the page's (a RemoteObject), as the console writes it.
String _remoteText(Map? value) {
  if (value == null) return 'undefined';
  if (value.containsKey('value')) {
    final v = value['value'];
    return v is String ? jsonEncode(v) : jsonEncode(v);
  }
  if (value['unserializableValue'] case final String v) return v;
  if (value['type'] == 'undefined') return 'undefined';
  if (value['type'] == 'function') {
    // Its head, not its body.
    final head = '${value['description'] ?? 'function'}'
        .split('\n')
        .first
        .replaceFirst(RegExp(r'\s*\{.*$'), '');
    return 'ƒ ${_clip(head.replaceFirst(RegExp(r'^(async )?function\s*'), r'$1'), 120)}';
  }
  if (value['preview'] case final Map preview
      when value['type'] == 'object' && value['subtype'] != 'node') {
    final prefix = switch (value['className']) {
      final String c when c != 'Object' && c != 'Array' => '$c ',
      _ => '',
    };
    return '$prefix${ConsoleEntry.previewText(preview)}';
  }
  return '${value['description'] ?? value['className'] ?? value['type']}';
}

String _escapeRegex(String text) =>
    text.replaceAllMapped(RegExp(r'[.*+?^${}()|[\]\\/]'), (m) => '\\${m[0]}');

String _resolveUrl(String base, String url) {
  if (url.startsWith('data:')) return url;
  try {
    return Uri.parse(base).resolve(url).toString();
  } on FormatException {
    return url;
  }
}

/// [tab]'s debugging, on: its scripts known.
Future<_Debugging> _debugging(BrowserTab tab) async {
  final debugging = _Debugging.of(tab);
  await debugging.enable();
  return debugging;
}

/// [function] at [url]'s [line] and [column] (from 0) in [tab], as an agent
/// reads them: its name as written, where.
Future<({String name, String at})> _locatedCall(
  BrowserTab tab,
  String function,
  String url,
  int line,
  int column, {
  bool definition = false,
}) async {
  try {
    final debugging = await _debugging(tab).timeout(const Duration(seconds: 5));
    final place = await debugging
        .place(url, line, column, function: function, definition: definition)
        .timeout(const Duration(seconds: 6));
    return (name: place.function ?? function, at: place.text);
  } on Object {
    return (
      name: function,
      at: '${url.isEmpty ? '(no url)' : url}:${line + 1}:${column + 1}',
    );
  }
}

/// [frames] as lines: `at fn (src/App.tsx:12:5)`; a library's calls run
/// together.
Future<List<String>> _stackLines(
  BrowserTab tab,
  List<ScriptFrame> frames, {
  String indent = '    ',
  int max = 6,
  bool libraries = true,
}) async {
  try {
    final debugging = await _debugging(tab).timeout(const Duration(seconds: 5));
    return await _callLines(
      debugging,
      frames,
      max: max,
      call: (_, name, at) => '${indent}at $name ($at)',
      library: libraries
          ? (from, to, library) =>
                '$indent… ${to - from + 1} call${to > from ? 's' : ''} in $library'
          : null,
    );
  } on Object {
    return [
      for (final f in frames.take(max))
        '${indent}at ${f.function.isEmpty ? '(anonymous)' : f.function} ($f)',
    ];
  }
}

/// [frames] as [call] lines, up to [max] of them; a library's calls in a
/// row as one [library] line (the first call shown still: where it is),
/// or left out without [library].
Future<List<String>> _callLines(
  _Debugging debugging,
  List<ScriptFrame> frames, {
  required int max,
  required String Function(int index, String function, String at) call,
  required String Function(int from, int to, String library)? library,
}) async {
  final out = <String>[];
  var shown = 0;
  (int, int, String)? run;
  void flush() {
    if (run case (final from, final to, final name) when library != null) {
      out.add(library(from, to, name));
    }
    run = null;
  }

  for (final (i, f) in frames.indexed) {
    final place = await debugging
        .place(f.url, f.line, f.column, function: f.function)
        .timeout(
          const Duration(seconds: 6),
          onTimeout: () => (
            text: '${f.url}:${f.line + 1}:${f.column + 1}',
            library: null,
            function: f.function,
          ),
        );
    if (place.library case final name? when i > 0 || library == null) {
      if (run case (final from, _, final was) when was == name) {
        run = (from, i, name);
      } else {
        flush();
        run = (i, i, name);
      }
      continue;
    }
    flush();
    if (shown >= max) {
      if (library != null) {
        out.add(call(i, '…', '${frames.length - i} more calls'));
      }
      return out;
    }
    final name = place.function ?? f.function;
    out.add(call(i, name.isEmpty ? '(anonymous)' : name, place.text));
    shown++;
  }
  flush();
  return out;
}

/// A minified [function]'s name as [source] (its text, if the map has it)
/// writes it, around [at]: the function's there, if the minified one is
/// nowhere in it.
String _sourceName(
  String function,
  String? source,
  SourcePosition at, {
  bool definition = false,
}) {
  final bare = function.split('.').last;
  // An anonymous one's stays so.
  if (source == null || bare.isEmpty) return function;
  if (bare.isNotEmpty &&
      RegExp(r'(^|[^\w$])' + RegExp.escape(bare) + r'($|[^\w$])')
          .hasMatch(source)) {
    return function;
  }
  if (definition) {
    // Its head: from its line's start to its body.
    final lines = source.split('\n');
    if (at.line < lines.length) {
      final text = lines[at.line];
      final body = text.indexOf(RegExp(r'\{|=>'), at.column);
      final head = body < 0
          ? text
          : text.substring(0, text.startsWith('=>', body) ? body + 2 : body);
      if (functionName(head) case final name? when name.isNotEmpty) {
        return name;
      }
    }
    if (at.name case final name? when name.isNotEmpty) return name;
  }
  return enclosingFunction(source, at.line, at.column) ?? function;
}

/// The library (its package) [url] (a script's, or a source's) is of: a
/// path in node_modules, a dev server's own; null for the app's.
String? _libraryOf(String url) {
  final modules = url.lastIndexOf('node_modules/');
  if (modules >= 0) {
    final parts = url.substring(modules + 13).split('/');
    return parts.first.startsWith('@') && parts.length > 1
        ? '${parts[0]}/${parts[1]}'
        : parts.first;
  }
  if (url.contains('/.vite/deps/')) return 'a dependency';
  if (RegExp(r'(^|/)@(vite|react-refresh)\b').hasMatch(url)) return 'vite';
  if (url.startsWith('webpack/') || url.contains('://webpack/')) {
    return 'webpack';
  }
  return null;
}

final _sourceTools = [
  ClaudeSdkTool(
    name: 'browser_sources',
    description:
        "A shared tab's scripts, as DevTools' Sources panel has them, and "
        'the sources they were built of where they have a source map '
        '(src/App.tsx of a bundle): "list" them (filter), "read" one '
        '(url: a script\'s URL or a source\'s path, or part of it; from '
        'line), "search" them all (query).',
    inputSchema: {
      'type': 'object',
      'properties': {
        'tabId': BrowserTools._tabId,
        'action': {
          'type': 'string',
          'enum': ['list', 'read', 'search'],
        },
        'filter': {
          'type': 'string',
          'description': 'list: those whose URL or path has it.',
        },
        'url': {'type': 'string', 'description': 'read: which.'},
        'line': {
          'type': 'integer',
          'description': 'read: from this line (1 the first). Default 1.',
        },
        'column': {
          'type': 'integer',
          'description':
              'read, of a minified line: the part around this column.',
        },
        'lines': {
          'type': 'integer',
          'description': 'read: how many. Default 150.',
        },
        'query': {'type': 'string', 'description': 'search: what.'},
        'regex': {'type': 'boolean'},
        'caseSensitive': {'type': 'boolean'},
      },
      'required': ['tabId', 'action'],
    },
    run: (input, call) async {
      final tab = BrowserTab(BrowserTools._browser(), input['tabId'] as int);
      final debugging = await _debugging(tab);
      return switch (input['action']) {
        'read' => _readSource(debugging, input),
        'search' => _searchSources(debugging, input),
        _ => _listSources(debugging, input['filter'] as String?),
      };
    },
  ),
  ClaudeSdkTool(
    name: 'browser_breakpoints',
    description:
        "Sets a shared tab's breakpoints, as DevTools' Sources panel does: "
        'on a line (url: a script\'s URL or a source\'s path, as '
        'src/App.tsx, mapped to the bundle; line; condition; or log: a '
        'logpoint, its expression logged to the console, no pause); on '
        'exceptions (all, uncaught, none); on a request whose URL has xhr '
        '("" for any); on an event (click, keydown, setTimeout…); on an '
        "element's changes (dom: subtree-modified, attribute-modified, "
        'node-removed, with ref, text or selector). They stay over '
        'reloads. When the page pauses, the action that led there says '
        'so: browser_debugger shows it.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'tabId': BrowserTools._tabId,
        'action': {
          'type': 'string',
          'enum': ['add', 'remove', 'list', 'clear'],
        },
        'url': {'type': 'string'},
        'line': {'type': 'integer', 'description': 'From 1.'},
        'column': {'type': 'integer', 'description': 'From 1.'},
        'condition': {
          'type': 'string',
          'description': 'Pauses only when this expression is true there.',
        },
        'log': {
          'type': 'string',
          'description':
              'A logpoint: what to log there (as console.log\'s arguments, '
              'e.g. "\'user\', user.id"), without pausing.',
        },
        'exceptions': {
          'type': 'string',
          'enum': ['all', 'uncaught', 'none'],
        },
        'xhr': {'type': 'string'},
        'event': {'type': 'string'},
        'dom': {
          'type': 'string',
          'enum': ['subtree-modified', 'attribute-modified', 'node-removed'],
        },
        ..._targetProperties,
        'id': {'type': 'string', 'description': 'remove: which (b1…).'},
      },
      'required': ['tabId', 'action'],
    },
    run: (input, call) async {
      final browser = BrowserTools._browser();
      final tab = BrowserTab(browser, input['tabId'] as int);
      final debugging = await _debugging(tab);
      switch (input['action']) {
        case 'list':
          final listed = debugging.listed();
          return listed.isEmpty ? 'No breakpoint.' : listed.join('\n');
        case 'clear':
          for (final b in [...debugging.breakpoints]) {
            await debugging.remove(b);
          }
          await debugging.setExceptions('none');
          return 'All taken out.';
        case 'remove':
          final id = input['id'] as String?;
          final b = debugging.breakpoints.where((b) => b.id == id).firstOrNull;
          if (b == null) throw BrowserError('No breakpoint $id.');
          await debugging.remove(b);
          return 'Took out $id.';
      }
      if (input['exceptions'] case final String state) {
        await debugging.setExceptions(state);
        return state == 'none'
            ? 'Exceptions do not pause.'
            : 'Pauses on ${state == 'all' ? 'all exceptions (caught too)' : 'uncaught exceptions'}.';
      }
      if (input['xhr'] case final String url) {
        final b = await debugging.addOther(
          'xhr',
          url.isEmpty ? 'any request' : 'requests whose URL has "$url"',
          () => browser.cdp(tab.tabId, 'DOMDebugger.setXHRBreakpoint', {
            'url': url,
          }),
          () => browser.cdp(tab.tabId, 'DOMDebugger.removeXHRBreakpoint', {
            'url': url,
          }),
        );
        return 'Set ${b.id}: pauses as ${b.description} are sent.';
      }
      if (input['event'] case final String name when name.isNotEmpty) {
        final b = await debugging.addOther(
          'event',
          name,
          () => browser.cdp(
            tab.tabId,
            'DOMDebugger.setEventListenerBreakpoint',
            {'eventName': name},
          ),
          () => browser.cdp(
            tab.tabId,
            'DOMDebugger.removeEventListenerBreakpoint',
            {'eventName': name},
          ),
        );
        return 'Set ${b.id}: pauses in the page\'s $name listeners.';
      }
      if (input['dom'] case final String type) {
        final element = await _element(browser, tab.tabId, input);
        final node = await _nodeId(browser, tab.tabId, element.objectId);
        final b = await debugging.addOther(
          'dom',
          '$type of ${element.name}',
          () => browser.cdp(tab.tabId, 'DOMDebugger.setDOMBreakpoint', {
            'nodeId': node,
            'type': type,
          }),
          () => browser.cdp(tab.tabId, 'DOMDebugger.removeDOMBreakpoint', {
            'nodeId': node,
            'type': type,
          }),
        );
        return 'Set ${b.id}: pauses on ${b.description}.';
      }
      final url = input['url'] as String?;
      final line = input['line'] as int?;
      if (url == null || url.isEmpty || line == null) {
        throw const BrowserError(
          'Say where: url and line; or exceptions, xhr, event, or dom.',
        );
      }
      final log = input['log'] as String?;
      final condition = log != null && log.isNotEmpty
          ? '(console.log($log), false)'
          : input['condition'] as String?;
      final b = await debugging.addLine(
        url,
        line,
        input['column'] as int?,
        condition,
      );
      return [
        'Set ${b.id}${log != null ? ' (logpoint: browser_console shows it)' : ''} at ${b.description}.',
        if (b.resolved == 0)
          'No script loaded has it yet: it binds when one does (reload, or '
              'do what loads it). Check the path with browser_sources.',
      ].join('\n');
    },
  ),
  ClaudeSdkTool(
    name: 'browser_debugger',
    description:
        "A shared tab paused in the debugger (a breakpoint's, an "
        'exception\'s): "state" shows why, the calls (mapped to the '
        'sources), the code there and the variables of each scope (frame: '
        'which call, 0 the top); "eval" runs an expression there (frame); '
        '"stepOver", "stepInto", "stepOut", "resume"; "pause" it now; '
        '"wait" for it to pause (timeout, seconds: the user or a timer '
        'gets it there).',
    inputSchema: {
      'type': 'object',
      'properties': {
        'tabId': BrowserTools._tabId,
        'action': {
          'type': 'string',
          'enum': [
            'state',
            'eval',
            'stepOver',
            'stepInto',
            'stepOut',
            'resume',
            'pause',
            'wait',
          ],
        },
        'frame': {'type': 'integer'},
        'expression': {'type': 'string'},
        'timeout': {'type': 'integer', 'description': 'wait: seconds, 30.'},
      },
      'required': ['tabId', 'action'],
    },
    run: (input, call) async {
      final browser = BrowserTools._browser();
      final tab = BrowserTab(browser, input['tabId'] as int);
      final debugging = await _debugging(tab);
      final frame = input['frame'] as int? ?? 0;
      switch (input['action']) {
        case 'eval':
          final expression = input['expression'] as String? ?? '';
          if (!debugging.isPaused) {
            final value = await BrowserTools._evaluate(
              browser,
              tab.tabId,
              expression,
            );
            return 'Not paused: in the page, ${jsonEncode(value)}';
          }
          final frames = debugging.callFrames;
          if (frame >= frames.length) throw BrowserError('No call #$frame.');
          Future<Map<String, Object?>> evaluate(String expression) =>
              browser.cdp(tab.tabId, 'Debugger.evaluateOnCallFrame', {
                'callFrameId': frames[frame]['callFrameId'],
                'expression': expression,
                'generatePreview': true,
              });
          // In a minified script, by the source's names too.
          final renamed = renameVariables(
            expression,
            await debugging.variablesOf(frames[frame]),
          );
          var result = await evaluate(renamed);
          if (renamed != expression && result['exceptionDetails'] != null) {
            result = await evaluate(expression);
          }
          if (result['exceptionDetails'] case final Map details) {
            final exception = details['exception'] as Map?;
            throw BrowserError(
              '${exception?['description'] ?? details['text'] ?? 'It threw.'}',
            );
          }
          final value = (result['result'] as Map?) ?? const {};
          // An object whole, as JSON, where it is one.
          if (value['objectId'] case final String id) {
            try {
              final json = await browser.cdp(
                tab.tabId,
                'Runtime.callFunctionOn',
                {
                  'objectId': id,
                  'functionDeclaration':
                      'function () { return JSON.stringify(this, null, 1); }',
                  'returnByValue': true,
                },
              );
              final text = (json['result'] as Map?)?['value'];
              if (text is String) return _clip(text, 20000);
            } on Object {
              // As the console writes it.
            }
          }
          return _remoteText(value);
        case 'stepOver' || 'stepInto' || 'stepOut' || 'resume':
          if (!debugging.isPaused) return 'Not paused.';
          final method = input['action'] as String;
          final resumed = debugging._changes.stream.first;
          await browser.cdp(tab.tabId, 'Debugger.$method');
          await resumed.timeout(const Duration(seconds: 5), onTimeout: () {});
          final again = await debugging.waitPaused(
            Duration(seconds: method == 'resume' ? 2 : 5),
          );
          if (!again) {
            return method == 'resume'
                ? 'Going on.'
                : 'Going on: it left the calls paused in (nothing more to step).';
          }
          return debugging.describe(frame: 0);
        case 'pause':
          if (!debugging.isPaused) {
            await debugging.pause();
            if (!await debugging.waitPaused(const Duration(seconds: 5))) {
              return 'Asked to pause: it will, as soon as script runs.';
            }
          }
          return debugging.describe(frame: frame);
        case 'wait':
          final seconds = ((input['timeout'] as int?) ?? 30).clamp(1, 600);
          if (!await debugging.waitPaused(Duration(seconds: seconds))) {
            return 'Not paused in $seconds s.';
          }
          return debugging.describe(frame: frame);
        default:
          return debugging.describe(frame: frame);
      }
    },
  ),
];

Future<String> _listSources(_Debugging debugging, String? filter) async {
  final scripts = [
    for (final s in debugging.scripts.values)
      if (s.url.isNotEmpty && !s.url.startsWith('chrome-extension://')) s,
  ];
  if (scripts.isEmpty) return 'No script on the page.';
  final maps = {for (final (s, map) in await debugging.allMaps()) s.url: map};
  final lines = <String>[];
  final seen = <String>{};
  bool matches(String text) =>
      filter == null || filter.isEmpty || text.contains(filter);
  for (final s in scripts) {
    if (!seen.add(s.url)) continue;
    final map = maps[s.url];
    final sources = [
      if (map != null)
        for (final source in map.sources)
          if (!source.contains('/node_modules/') && matches(source))
            shortSource(source),
    ];
    if (!matches(s.url) && sources.isEmpty) continue;
    lines.add(
      '${s.url} (${s.lines} lines'
      '${map == null ? (s.sourceMapUrl != null ? ', its source map not loaded' : '') : ', ${map.sources.length} sources'})',
    );
    for (final source in sources.take(40)) {
      lines.add('  $source');
    }
    if (sources.length > 40) lines.add('  … ${sources.length - 40} more');
    if (lines.length > 400) {
      lines.add('… (more: give a filter)');
      break;
    }
  }
  return lines.isEmpty ? 'Nothing has "$filter".' : lines.join('\n');
}

Future<String> _readSource(
  _Debugging debugging,
  Map<String, Object?> input,
) async {
  final url = input['url'] as String? ?? '';
  if (url.isEmpty) throw const BrowserError('Say which: url.');
  final from = ((input['line'] as int?) ?? 1).clamp(1, 1 << 30);
  final count = ((input['lines'] as int?) ?? 150).clamp(1, 500);
  final column = input['column'] as int?;
  String? text;
  String? name;
  final script = debugging.scriptFor(url);
  // A script's URL whole: that script; else what was written (a map's
  // source) over what was served of it (a dev server's own build of it).
  if (script != null && script.url == url) {
    text = await debugging.sourceOf(script.id);
    name = script.url;
  }
  String? textless;
  if (text == null) {
    if (await debugging.originalFor(url) case (_, final map, final index)?) {
      text = map.content(index);
      name = shortSource(map.sources[index]);
      if (text == null) textless = name;
    }
  }
  if (text == null && script != null) {
    text = await debugging.sourceOf(script.id);
    name = script.url;
  }
  if (text == null) {
    throw BrowserError(
      textless != null
          ? '$textless: its source map does not carry its text '
                '(sourcesContent).'
          : 'No script or source has "$url": list them with browser_sources.',
    );
  }
  final lines = text.split('\n');
  final out = ['$name (${lines.length} lines):'];
  for (var i = from - 1; i < lines.length && i < from - 1 + count; i++) {
    var line = lines[i];
    if (line.length > 500) {
      final at = column == null ? 0 : column - 1;
      final start = (at - 250).clamp(0, line.length);
      final end = (start + 500).clamp(0, line.length);
      line =
          '${start > 0 ? '…' : ''}${line.substring(start, end)}'
          '${end < line.length ? '… (${line.length} chars; column picks the part)' : ''}';
    }
    out.add('${'${i + 1}'.padLeft(6)} | $line');
  }
  if (from - 1 + count < lines.length) {
    out.add('… to line ${lines.length} (line: ${from + count} goes on)');
  }
  return out.join('\n');
}

Future<String> _searchSources(
  _Debugging debugging,
  Map<String, Object?> input,
) async {
  final query = input['query'] as String? ?? '';
  if (query.isEmpty) throw const BrowserError('Say what: query.');
  final regex = input['regex'] == true;
  final caseSensitive = input['caseSensitive'] == true;
  final pattern = RegExp(
    regex ? query : RegExp.escape(query),
    caseSensitive: caseSensitive,
  );
  final hits = <String>[];
  String clipAround(String line) {
    final match = pattern.firstMatch(line);
    if (line.length <= 200 || match == null) return _clip(line.trim(), 200);
    final start = (match.start - 80).clamp(0, line.length);
    final end = (match.end + 80).clamp(0, line.length);
    return '…${line.substring(start, end)}…';
  }

  // The sources first: what was written.
  final mapped = <String>{};
  for (final (script, map) in await debugging.allMaps()) {
    mapped.add(script.url);
    for (final (i, source) in map.sources.indexed) {
      if (source.contains('/node_modules/')) continue;
      final content = map.content(i);
      if (content == null) continue;
      for (final (n, line) in content.split('\n').indexed) {
        if (!pattern.hasMatch(line)) continue;
        hits.add('${shortSource(source)}:${n + 1}: ${clipAround(line)}');
        if (hits.length >= 60) break;
      }
      if (hits.length >= 60) break;
    }
    if (hits.length >= 60) break;
  }
  final seen = <String>{};
  for (final script in debugging.scripts.values) {
    if (hits.length >= 60) break;
    if (script.url.isEmpty ||
        script.url.startsWith('chrome-extension://') ||
        mapped.contains(script.url) ||
        !seen.add(script.url)) {
      continue;
    }
    try {
      final result = await debugging.tab.browser.cdp(
        debugging.tab.tabId,
        'Debugger.searchInContent',
        {
          'scriptId': script.id,
          'query': query,
          'caseSensitive': caseSensitive,
          'isRegex': regex,
        },
      );
      for (final m in (result['result'] as List? ?? const []).cast<Map>()) {
        hits.add(
          '${script.url}:${(m['lineNumber'] as num).toInt() + 1}: '
          '${clipAround(m['lineContent'] as String? ?? '')}',
        );
        if (hits.length >= 60) break;
      }
    } on Object {
      // Gone.
    }
  }
  if (hits.isEmpty) return 'Nothing has "$query".';
  return [...hits, if (hits.length >= 60) '… (the first 60)'].join('\n');
}
