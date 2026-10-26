import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path/path.dart' as p;

import '../chat/chat_models.dart' show ToolKind;
import '../kernel/claude_code/claude_sdk_tools.dart';
import '../platform/data_dir.dart';
import 'browser_analysis.dart';
import 'browser_bridge.dart';
import 'browser_records.dart';
import 'browser_steps.dart';
import 'source_map.dart';

part 'browser_actions.dart';
part 'browser_debug_tools.dart';
part 'browser_history.dart';
part 'browser_inspect.dart';
part 'browser_intercept.dart';
part 'browser_page.dart';
part 'browser_sources.dart';
part 'browser_watch.dart';

/// The agents' tools for the user's browser (see browser_bridge.dart): the
/// tabs shared with BaoCode (its tab group's) alone, through the DevTools
/// protocol. Their names are `mcp__baocode__browser_…` to an agent.
abstract final class BrowserTools {
  static bool _registered = false;

  /// The tab an agent last used: the side panel's page shows it.
  static final lastTab = ValueNotifier<BrowserTab?>(null);

  static final _shown = StreamController<BrowserTab>.broadcast();

  /// The tabs asked to show in the side panel ([show]), for the panel to
  /// open its browser page.
  static Stream<BrowserTab> get shown => _shown.stream;

  /// Shows [tabId] in the side panel (a step of the conversation clicked):
  /// as the tab an agent used last, over the one the user picked there.
  static void show(int tabId) {
    final browsers = BrowserBridge.instance.browsers;
    if (browsers.isEmpty) return;
    final tab = BrowserTab(browsers.first, tabId);
    lastTab.value = tab;
    _shown.add(tab);
  }

  /// Starts the bridge to the user's browsers; gives the agents the tools
  /// while one has connected and the user lets them ([BrowserBridge.used]).
  static Future<void> start() async {
    final bridge = BrowserBridge.instance;
    // Not an app's test's: the socket and the browsers are the user's.
    if (!bridge.supported || Platform.environment.containsKey('FLUTTER_TEST')) {
      return;
    }
    void sync() => bridge.used ? register() : unregister();
    sync();
    bridge.addListener(sync);
    // What the shared tabs do, kept from the moment they are shared.
    BrowserHistory.instance.start();
    await bridge.start();
  }

  static List<ClaudeSdkTool> get _all => [
    ..._tools,
    ..._actionTools,
    ..._debugTools,
    ..._inspectTools,
    ..._sourceTools,
    _interceptTool,
    _watchTool,
    _historyTool,
  ];

  /// Takes the tools from the agents (Settings → Browser turned off).
  static void unregister() {
    if (!_registered) return;
    _registered = false;
    for (final tool in _all) {
      ClaudeSdkTools.unregister(tool.name);
    }
    ClaudeSdkTools.instruct('browser', null);
  }

  /// Gives the agents the tools.
  static void register() {
    if (_registered) return;
    _registered = true;
    ClaudeSdkTools.instruct('browser', rules);
    for (final tool in _all) {
      ClaudeSdkTools.register(
        ClaudeSdkTool(
          name: tool.name,
          description: tool.description,
          inputSchema: {
            ...tool.inputSchema,
            'properties': {
              ...?tool.inputSchema['properties'] as Map<String, Object?>?,
              'description': _description,
            },
          },
          kind: ToolKind.browser,
          summary: (input, output) =>
              browserStepSummary(tool.name, input, output),
          run: (raw, call) async {
            final input = numbersAsSchemaSays(tool.inputSchema, raw);
            final tabId = input['tabId'];
            if (tabId is! int) return tool.run(input, call);
            // What the page logs and loads, kept from now on.
            await _watch(tabId);
            final tab = BrowserTab(_browser(), tabId);
            _blocked(tool.name, tab);
            // The dialogs its page opens meanwhile answered (see
            // BrowserRecords.acting).
            final answer = await BrowserRecords.instance.acting(
              tab,
              () => tool.run(input, call),
            );
            if (tool.name != 'browser_close') _used(tabId);
            return answer;
          },
        ),
      );
    }
  }

  /// [input] with the numbers [schema] asks for that a model sent as text
  /// (`"406885479"` for a tab's id) as numbers, at any depth (a step of
  /// browser_act's); text that is no number left as it is, for the tool
  /// to refuse, and text where text is asked for (what is typed) too (#274).
  @visibleForTesting
  static Map<String, Object?> numbersAsSchemaSays(
    Map<String, Object?> schema,
    Map<String, Object?> input,
  ) => _asSchemaSays(schema, input) as Map<String, Object?>;

  static Object? _asSchemaSays(Object? schema, Object? value) {
    if (schema is! Map) return value;
    switch ((schema['type'], value)) {
      case ('integer', final String text)
          when int.tryParse(text.trim()) != null:
        return int.parse(text.trim());
      case ('integer', final double number)
          when number == number.roundToDouble():
        return number.toInt();
      case ('number', final String text) when num.tryParse(text.trim()) != null:
        return num.parse(text.trim());
      case (_, final Map<Object?, Object?> object):
        final properties = schema['properties'];
        if (properties is! Map) return value;
        return <String, Object?>{
          for (final MapEntry(:key, :value) in object.entries)
            '$key': _asSchemaSays(properties[key], value),
        };
      case (_, final List<Object?> list):
        return [for (final item in list) _asSchemaSays(schema['items'], item)];
    }
    return value;
  }

  static Future<void> _watch(int tabId) async {
    final browsers = BrowserBridge.instance.browsers;
    if (browsers.isEmpty) return;
    try {
      await BrowserRecords.instance.watch(BrowserTab(browsers.first, tabId));
    } on Object {
      // Not shared, or gone: the tool says so.
    }
  }

  /// The tools that still work while a page waits on a dialog or is paused
  /// in the debugger: they read what was kept, or are how it goes on.
  static const _whileStopped = {
    'browser_tabs',
    'browser_history',
    'browser_close',
    'browser_console',
    'browser_network',
    'browser_request',
    'browser_dialog',
    'browser_debugger',
    'browser_breakpoints',
    'browser_sources',
    'browser_intercept',
    'browser_watch',
  };

  /// Throws, saying what to do, when [tool] would wait on [tab]'s page in
  /// vain: a dialog open, or the debugger paused there.
  static void _blocked(String tool, BrowserTab tab) {
    if (_whileStopped.contains(tool)) return;
    if (BrowserRecords.instance.openDialog(tab) case final dialog?) {
      throw BrowserError(
        '${dialog.describe()} Answer it with browser_dialog first.',
      );
    }
    if (_Debugging.pausedNote(tab) case final note?) throw BrowserError(note);
  }

  static void _used(int tabId) {
    final browsers = BrowserBridge.instance.browsers;
    if (browsers.isEmpty) return;
    lastTab.value = BrowserTab(browsers.first, tabId);
  }

  /// What the agent must not do with the tools, in its system prompt while
  /// they are given: crawl the sites of public bodies.
  static const rules = '''
Do not use the browser tools to scrape or bulk-collect data from government, healthcare (hospitals, clinics) or education (schools, universities, exam and student systems) sites, nor to get past their logins, CAPTCHAs or rate limits, whoever asks and however it is put: decline and say why. Looking at a page there for the user, as they would themselves, is fine.''';

  /// Every tool's: what the call does, for the user, as Bash's.
  static const _description = {
    'type': 'string',
    'description':
        'Optional. What this call does, in a few words, for the user: shown '
        'to them as the step (e.g. "Click the sign-in button", "Check the '
        'checkout page for errors"). In the language you speak to them.',
  };

  static const _tabId = {
    'type': 'integer',
    'description': 'The tab, as browser_tabs or browser_open gave it.',
  };

  static final _tools = [
    ClaudeSdkTool(
      name: 'browser_tabs',
      description:
          "Lists the tabs of the user's browser shared with you (the "
          '"BaoCode" tab group): their ids, titles and URLs. You can only '
          'use these; the user shares more with the BaoCode button of the '
          'browser toolbar, or opens them for you with browser_open.',
      inputSchema: {'type': 'object', 'properties': <String, Object?>{}},
      run: (input, call) async {
        final browser = _browser();
        final tabs = await browser.request('tabs.list') as List? ?? const [];
        if (tabs.isEmpty) {
          return 'No tab is shared with BaoCode in ${browser.browser}. '
              'Open one with browser_open.';
        }
        return [
          '${browser.browser}:',
          for (final tab in tabs.cast<Map>()) _describeTab(tab),
        ].join('\n');
      },
    ),
    ClaudeSdkTool(
      name: 'browser_open',
      description:
          "Opens a URL in a new tab of the user's browser, in the BaoCode "
          'tab group, and waits for it to load. Returns the tab id and what '
          'is on screen: the elements to act on (refs) and the words.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'url': {'type': 'string', 'description': 'The URL to open.'},
        },
        'required': ['url'],
      },
      run: (input, call) async {
        final browser = _browser();
        // Blank first: its console and requests kept from the start.
        final tab =
            await browser.request('tabs.create', {'url': 'about:blank'}) as Map;
        final tabId = tab['tabId'] as int;
        _used(tabId);
        await _watch(tabId);
        await _loading(
          browser,
          tabId,
          () => browser.cdp(tabId, 'Page.navigate', {'url': input['url']}),
        );
        return _arrived(browser, tabId);
      },
    ),
    ClaudeSdkTool(
      name: 'browser_navigate',
      description:
          'Goes to a URL in a shared tab, or back, forward, or reloads it; '
          'waits for the page to load, and says what is on screen.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'tabId': _tabId,
          'url': {'type': 'string', 'description': 'Where to go.'},
          'action': {
            'type': 'string',
            'enum': ['back', 'forward', 'reload'],
            'description': 'Instead of a URL.',
          },
        },
        'required': ['tabId'],
      },
      run: (input, call) async {
        final browser = _browser();
        final tabId = input['tabId'] as int;
        await _go(
          browser,
          tabId,
          input['url'] as String?,
          input['action'] as String?,
        );
        return _arrived(browser, tabId);
      },
    ),
    ClaudeSdkTool(
      name: 'browser_evaluate',
      description:
          "Runs JavaScript in a shared tab's page and returns its value (as "
          'JSON; a promise is awaited). The user cannot read the script: '
          'say what it does in description.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'tabId': _tabId,
          'expression': {'type': 'string'},
        },
        'required': ['tabId', 'expression'],
      },
      run: (input, call) async {
        final value = await _evaluate(
          _browser(),
          input['tabId'] as int,
          input['expression'] as String,
        );
        return jsonEncode(value);
      },
    ),
    ClaudeSdkTool(
      name: 'browser_close',
      description: 'Closes a shared tab.',
      inputSchema: {
        'type': 'object',
        'properties': {'tabId': _tabId},
        'required': ['tabId'],
      },
      run: (input, call) async {
        await _browser().request('tabs.close', {'tabId': input['tabId']});
        return 'Closed.';
      },
    ),
  ];

  /// The browser to use: the last connected.
  static BrowserConnection _browser() {
    final bridge = BrowserBridge.instance;
    final browsers = bridge.browsers;
    if (browsers.isNotEmpty) return browsers.first;
    if (bridge.otherApp) {
      throw StateError(
        'Another BaoCode is connected to the browser: quit it first.',
      );
    }
    if (bridge.mismatched case [final browser, ...]) {
      throw StateError(
        browser.protocol < BrowserBridge.protocol
            ? "BaoCode's extension in ${browser.browser} is too old for "
                  'this BaoCode: the user needs to update it (Settings → '
                  'Browser says how).'
            : "BaoCode's extension in ${browser.browser} is newer than "
                  'this BaoCode: the user needs to update BaoCode.',
      );
    }
    throw StateError(
      "No browser is connected: the user needs BaoCode's extension in "
      'Chrome (or Edge, Brave, Arc), with the browser running.',
    );
  }

  /// A picture of what [tabId]'s page shows, for an agent: in CSS pixels,
  /// as it clicks (half as big as the screen's on a Retina one, as clear
  /// to read), as an MCP image.
  ///
  /// Taken as the screen has it, made smaller here: a screenshot's own
  /// scale (its clip's) has the browser draw the page that small in its
  /// window meanwhile, which the user sees flicker.
  static Future<Map<String, Object?>> screenshot(
    BrowserConnection browser,
    int tabId, {
    List<Map> marks = const [],
  }) async {
    final view = await viewport(browser, tabId);
    final shot = await browser.cdp(tabId, 'Page.captureScreenshot', {
      'format': 'jpeg',
      'quality': 75,
    });
    final data = shot['data'] as String;
    final width = view.rect.width.round();
    if ((view.ratio <= 1 && marks.isEmpty) || width <= 0) {
      return claudeSdkImage(data, 'image/jpeg');
    }
    final codec = await ui.instantiateImageCodec(
      base64Decode(data),
      targetWidth: width,
    );
    final frame = await codec.getNextFrame();
    codec.dispose();
    var image = frame.image;
    if (marks.isNotEmpty) {
      final marked = await _mark(image, marks);
      image.dispose();
      image = marked;
    }
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (png == null) return claudeSdkImage(data, 'image/jpeg');
    return claudeSdkImage(
      base64Encode(
        png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
      ),
      'image/png',
    );
  }

  /// [image] (CSS pixels) with each of [elements] boxed, its ref on it.
  static Future<ui.Image> _mark(ui.Image image, List<Map> elements) async {
    const color = Color(0xFFE8A33D);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..drawImage(image, Offset.zero, Paint());
    final box = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = color;
    final tag = Paint()..color = color;
    for (final element in elements) {
      final r = (element['rect'] as List).cast<num>();
      final rect = Rect.fromLTWH(
        r[0].toDouble(),
        r[1].toDouble(),
        r[2].toDouble(),
        r[3].toDouble(),
      );
      canvas.drawRect(rect, box);
      final label =
          (ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: 11))
                ..pushStyle(
                  ui.TextStyle(
                    color: const Color(0xFF000000),
                    fontWeight: FontWeight.w700,
                  ),
                )
                ..addText('${element['ref']}'))
              .build()
            ..layout(const ui.ParagraphConstraints(width: 60));
      // Above its box's corner, or in it at the top.
      final size = Size(label.maxIntrinsicWidth + 4, label.height);
      final at = Offset(
        rect.left.clamp(0, image.width - size.width),
        rect.top >= size.height ? rect.top - size.height : rect.top,
      );
      canvas
        ..drawRect(at & size, tag)
        ..drawParagraph(label, at + const Offset(2, 0));
      label.dispose();
    }
    final picture = recorder.endRecording();
    final marked = await picture.toImage(image.width, image.height);
    picture.dispose();
    return marked;
  }

  /// What a tab's page shows now: for a screenshot of it.
  static Future<BrowserViewport> viewport(
    BrowserConnection browser,
    int tabId,
  ) async {
    final metrics = await browser.cdp(tabId, 'Page.getLayoutMetrics');
    final css = (metrics['cssVisualViewport'] as Map).cast<String, Object?>();
    // In device pixels.
    final device = (metrics['visualViewport'] as Map?)?.cast<String, Object?>();
    double number(Map<String, Object?>? map, String key) =>
        (map?[key] as num?)?.toDouble() ?? 0;
    final width = number(css, 'clientWidth');
    final deviceWidth = number(device, 'clientWidth');
    return BrowserViewport(
      Rect.fromLTWH(
        number(css, 'pageX'),
        number(css, 'pageY'),
        width,
        number(css, 'clientHeight'),
      ),
      width > 0 && deviceWidth > 0 ? deviceWidth / width : 1,
    );
  }

  /// Goes to [url] in [tabId], or back, forward, or reloads ([action]);
  /// once the page is loaded.
  static Future<void> _go(
    BrowserConnection browser,
    int tabId,
    String? url,
    String? action,
  ) async {
    if (url != null) {
      await _loading(
        browser,
        tabId,
        () => browser.cdp(tabId, 'Page.navigate', {'url': url}),
      );
    } else if (action == 'reload') {
      await _loading(browser, tabId, () => browser.cdp(tabId, 'Page.reload'));
    } else if (action == 'back' || action == 'forward') {
      await _evaluate(browser, tabId, 'history.$action()');
    } else {
      throw const BrowserError('Give a url, or back, forward or reload.');
    }
    if (_Debugging.pausedNow(BrowserTab(browser, tabId))) return;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await _waitForLoad(browser, tabId);
  }

  /// The tab, and what its page has on screen: what an agent sees first.
  static Future<String> _arrived(BrowserConnection browser, int tabId) async {
    if (_Debugging.pausedNote(BrowserTab(browser, tabId)) case final note?) {
      return note;
    }
    await _settle(browser, tabId, DateTime.now());
    final tab = await _tab(browser, tabId);
    final page = await _stateOf(browser, tabId);
    return [
      if (tab != null) 'Tab ${_describeTab(tab)}',
      if (page != null) ..._overview(page),
    ].join('\n');
  }

  static String _describeTab(Map tab) =>
      '[${tab['tabId']}] ${tab['title']} — ${tab['url']}'
      '${tab['loading'] == true ? ' (loading)' : ''}';

  static Future<Map?> _tab(BrowserConnection browser, int tabId) async {
    final tabs = await browser.request('tabs.list') as List? ?? const [];
    for (final tab in tabs.cast<Map>()) {
      if (tab['tabId'] == tabId) return tab;
    }
    return null;
  }

  /// Runs [go] (a navigation) and waits for the page it leads to to load
  /// (its load event: the tab's Page domain is on, see BrowserRecords).
  static Future<void> _loading(
    BrowserConnection browser,
    int tabId,
    Future<void> Function() go, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final loaded = Completer<void>();
    // Loaded, or stopped on its way: paused in the debugger (a breakpoint
    // of its scripts'), or a dialog waiting.
    final subscription = BrowserBridge.instance.events.listen((event) {
      if (event.event == 'cdp' &&
          identical(event.connection, browser) &&
          event.tabId == tabId &&
          event.message['sessionId'] == null &&
          const {
            'Page.loadEventFired',
            'Debugger.paused',
            'Page.javascriptDialogOpening',
          }.contains(event.message['method']) &&
          !loaded.isCompleted) {
        loaded.complete();
      }
    });
    try {
      await go();
      await loaded.future.timeout(timeout, onTimeout: () {});
    } finally {
      await subscription.cancel();
    }
  }

  static Future<void> _waitForLoad(
    BrowserConnection browser,
    int tabId, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      try {
        final state = await _evaluate(browser, tabId, 'document.readyState');
        if (state == 'complete') return;
      } on Object {
        // Between pages.
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  /// [expression]'s value in the page, a promise's awaited; thrown, what
  /// it threw.
  static Future<Object?> _evaluate(
    BrowserConnection browser,
    int tabId,
    String expression,
  ) async {
    final result = await browser.cdp(tabId, 'Runtime.evaluate', {
      'expression': expression,
      'returnByValue': true,
      'awaitPromise': true,
      'userGesture': true,
    });
    if (result['exceptionDetails'] case final Map details) {
      final exception = details['exception'] as Map?;
      throw BrowserError(
        '${exception?['description'] ?? details['text'] ?? 'The script failed.'}',
      );
    }
    return (result['result'] as Map?)?['value'];
  }

  /// Keys by name: their `code`, `key` and Windows key code.
  static const _keys = <String, (String, String, int)>{
    'Enter': ('Enter', 'Enter', 13),
    'Tab': ('Tab', 'Tab', 9),
    'Escape': ('Escape', 'Escape', 27),
    'Backspace': ('Backspace', 'Backspace', 8),
    'Delete': ('Delete', 'Delete', 46),
    'ArrowUp': ('ArrowUp', 'ArrowUp', 38),
    'ArrowDown': ('ArrowDown', 'ArrowDown', 40),
    'ArrowLeft': ('ArrowLeft', 'ArrowLeft', 37),
    'ArrowRight': ('ArrowRight', 'ArrowRight', 39),
    'Home': ('Home', 'Home', 36),
    'End': ('End', 'End', 35),
    'PageUp': ('PageUp', 'PageUp', 33),
    'PageDown': ('PageDown', 'PageDown', 34),
    'Space': ('Space', ' ', 32),
  };

  static Future<void> _press(
    BrowserConnection browser,
    int tabId,
    String combo,
  ) async {
    final parts = combo.split('+');
    final name = parts.removeLast();
    var modifiers = 0;
    for (final modifier in parts) {
      modifiers |= switch (modifier.toLowerCase()) {
        'alt' || 'option' => 1,
        'control' || 'ctrl' => 2,
        'meta' || 'cmd' || 'command' => 4,
        'shift' => 8,
        _ => throw ArgumentError('Unknown modifier $modifier.'),
      };
    }
    final String code;
    final String key;
    final int keyCode;
    String? text;
    if (_keys[name] case (final c, final k, final n)) {
      (code, key, keyCode) = (c, k, n);
      if (name == 'Enter') text = '\r';
      if (name == 'Space') text = ' ';
    } else if (name.length == 1) {
      final upper = name.toUpperCase();
      final letter = RegExp('[A-Z]').hasMatch(upper);
      final digit = RegExp('[0-9]').hasMatch(name);
      code = letter
          ? 'Key$upper'
          : digit
          ? 'Digit$name'
          : '';
      key = (modifiers & 8) != 0 ? upper : name;
      keyCode = letter || digit ? upper.codeUnitAt(0) : 0;
      text = key;
    } else {
      throw ArgumentError('Unknown key $name.');
    }
    // With Control, Alt or Meta, a key types nothing: a command's.
    if ((modifiers & 7) != 0) text = null;
    Future<void> key0(String type) =>
        browser.cdp(tabId, 'Input.dispatchKeyEvent', {
          'type': type,
          'modifiers': modifiers,
          'code': code,
          'key': key,
          'windowsVirtualKeyCode': keyCode,
          if (type == 'keyDown' && text != null) 'text': text,
          if (type == 'keyDown' && text != null) 'unmodifiedText': text,
          // macOS's editing commands (select all, copy…) follow Meta keys.
          if (type == 'keyDown' && (modifiers & 4) != 0)
            'commands': ?_commands[key.toLowerCase()],
        });
    await key0(text == null ? 'rawKeyDown' : 'keyDown');
    await key0('keyUp');
  }

  /// Meta's editing keys, as macOS's commands: the page has them so alone.
  static const _commands = <String, List<String>>{
    'a': ['selectAll'],
    'c': ['copy'],
    'x': ['cut'],
    'v': ['paste'],
    'z': ['undo'],
  };
}

/// What a tab's page shows: [rect] of the page (CSS pixels, the page's
/// coordinates), at [ratio] device pixels to each.
class BrowserViewport {
  const BrowserViewport(this.rect, this.ratio);

  final Rect rect;
  final double ratio;
}
