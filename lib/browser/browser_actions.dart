part of 'browser_tools.dart';

// The agents' hands in a page: they aim at an element by its number or
// its words (browser_page.dart finds it, waiting for it a moment), act as
// the user would (the DevTools protocol's input, trusted), wait for the
// page to settle, and are told what changed: no second look needed.
// browser_act does several at once.

/// The input properties of an action, for the agent to aim it.
const _clickProperties = {
  ..._targetProperties,
  'x': {
    'type': 'number',
    'description':
        'Instead of an element: a point, CSS pixels, as in a '
        'screenshot.',
  },
  'y': {'type': 'number'},
  'button': {
    'type': 'string',
    'enum': ['left', 'right', 'middle'],
  },
  'clickCount': {'type': 'integer', 'description': '2 for a double click.'},
  'modifiers': _modifiersProperty,
};

const _modifiersProperty = {
  'type': 'string',
  'description': 'Keys held meanwhile, as "Shift" or "Alt+Shift".',
};

const _typeProperties = {
  'clear': {
    'type': 'boolean',
    'description':
        "With an element: replace what is in it (the default), or add to "
        'it (false).',
  },
  'submit': {'type': 'boolean', 'description': 'Press Enter after.'},
};

// The aim's own "text" is the words typed in a type step: its element is
// named by `into`.
const _typeStepProperties = {
  'into': {
    'type': 'string',
    'description':
        "The field's words (label, placeholder) when typing; or give ref.",
  },
};

const _screenshotProperty = {
  'type': 'boolean',
  'description': 'Add a screenshot of the page after (the words say most).',
};

final _actionTools = [
  ClaudeSdkTool(
    name: 'browser_snapshot',
    description:
        "Reads a shared tab's page: its title, URL, the elements you can "
        'act on (each with its ref, as [12], kept while it is there) and '
        'its words. What is on screen (the default), or the whole page. '
        'Actions already say what they change: look again only to read '
        'more.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'tabId': BrowserTools._tabId,
        'scope': {
          'type': 'string',
          'enum': ['screen', 'page'],
        },
      },
      'required': ['tabId'],
    },
    run: (input, call) async {
      final browser = BrowserTools._browser();
      final tabId = input['tabId'] as int;
      final scope = input['scope'] == 'page' ? 'page' : 'viewport';
      final page = await _bao(browser, tabId, "overview('$scope')") as Map;
      final elements = (page['elements'] as List).cast<Map>();
      final words = (page['lines'] as List).cast<String>();
      return [
        'Title: ${page['title']}',
        'URL: ${page['url']}',
        'Scrolled: ${page['scrolled']} of ${page['scrollMax']}',
        '',
        scope == 'page' ? 'Elements (all):' : 'Elements (on screen):',
        for (final e in elements) _elementLine(e.cast()),
        '',
        scope == 'page' ? 'Text:' : 'Text (on screen):',
        _clip(words.join('\n'), scope == 'page' ? 15000 : 8000),
      ].join('\n');
    },
  ),
  ClaudeSdkTool(
    name: 'browser_screenshot',
    description:
        'Takes a picture of what a shared tab shows (CSS pixels, as x and y '
        'are). With marks, each element you can act on is boxed with its '
        'ref: for pages whose words say little (canvas, icons).',
    inputSchema: {
      'type': 'object',
      'properties': {
        'tabId': BrowserTools._tabId,
        'marks': {'type': 'boolean'},
      },
      'required': ['tabId'],
    },
    run: (input, call) async {
      final browser = BrowserTools._browser();
      final tabId = input['tabId'] as int;
      if (input['marks'] == true) {
        final elements = (await _bao(
          browser,
          tabId,
          "elements('viewport')",
        ) as List).cast<Map>();
        return [
          await BrowserTools.screenshot(browser, tabId, marks: elements),
          claudeSdkText(elements.map((e) => _elementLine(e.cast())).join('\n')),
        ];
      }
      return [await BrowserTools.screenshot(browser, tabId)];
    },
  ),
  ClaudeSdkTool(
    name: 'browser_click',
    description:
        'Clicks an element of a shared tab, by ref or by its words (text, '
        'with role and near to tell it from others alike), waiting for it '
        'to appear; or a point. Then says what changed: what appeared, '
        'what is focused, a new page.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'tabId': BrowserTools._tabId,
        ..._clickProperties,
        'screenshot': _screenshotProperty,
      },
      'required': ['tabId'],
    },
    run: (input, call) => _acting(input, [
      {...input, 'action': 'click'},
    ]),
  ),
  ClaudeSdkTool(
    name: 'browser_type',
    description:
        'Types text into a shared tab: into an element (by ref, or text, '
        'role, near: clicked first, as the user would, and what is in it '
        'replaced unless clear is false) or where the focus is; then '
        'presses Enter if submit. A color, date or slider input is set to '
        'the text (a color as #rrggbb or CSS says it), its chooser not '
        'opened: no click reaches the browser\'s own. Says what changed.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'tabId': BrowserTools._tabId,
        ..._targetProperties,
        'text': {'type': 'string', 'description': 'What to type.'},
        'into': _typeStepProperties['into'],
        'clear': _typeProperties['clear'],
        'submit': _typeProperties['submit'],
        'screenshot': _screenshotProperty,
      },
      'required': ['tabId', 'text'],
    },
    run: (input, call) => _acting(input, [
      {...input, 'action': 'type'},
    ]),
  ),
  ClaudeSdkTool(
    name: 'browser_press',
    description:
        'Presses a key in a shared tab: Enter, Tab, Escape, Backspace, '
        'Delete, ArrowUp, ArrowDown, ArrowLeft, ArrowRight, Home, End, '
        'PageUp, PageDown, Space, or a character; with modifiers as '
        '"Shift+Tab" or "Meta+A". Says what changed.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'tabId': BrowserTools._tabId,
        'key': {'type': 'string'},
        'screenshot': _screenshotProperty,
      },
      'required': ['tabId', 'key'],
    },
    run: (input, call) => _acting(input, [
      {...input, 'action': 'press'},
    ]),
  ),
  ClaudeSdkTool(
    name: 'browser_scroll',
    description:
        'Scrolls a shared tab: by deltaY (down positive) and deltaX CSS '
        'pixels, at a point (x, y) or the middle; or to an element (ref, '
        'or text, role, near). Says what came on screen.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'tabId': BrowserTools._tabId,
        'deltaY': {'type': 'number'},
        'deltaX': {'type': 'number'},
        'x': {'type': 'number'},
        'y': {'type': 'number'},
        ..._targetProperties,
      },
      'required': ['tabId'],
    },
    run: (input, call) => _acting(input, [
      {...input, 'action': 'scroll'},
    ]),
  ),
  ClaudeSdkTool(
    name: 'browser_act',
    description:
        'Does several actions in a shared tab, one after the other, as '
        'one: e.g. click "Reply" near "boysmen", type into the box, press '
        'Enter. Each waits for its element and for the page to settle; it '
        'stops at the first that fails, saying why. Then says what changed '
        'overall. Steps: {action: "click", ref | text, role, near, nth | x, '
        'y}; {action: "type", text, ref | into (the field\'s words), role, '
        'near, clear, submit; sets a color, date or slider input too}; '
        '{action: "press", key}; {action: "scroll", '
        'deltaY | ref | text}; {action: "wait", text (until the page says '
        'it) | ms}; {action: "navigate", url | back | forward | reload: '
        'true}; {action: "upload", files (paths), ref | text | selector: a '
        'file input, or what opens the file chooser}; {action: "drag", ref '
        '| text | x, y: where it starts, to: {ref | text | x, y} or path: '
        '[[x, y], …] (to draw, to move a slider or a card); pressure (0–1: '
        'a pen, for brushes that heed it), or [x, y, pressure] points}; '
        '{action: "hover", ref | text | x, y}. Click and drag take '
        'modifiers, keys held meanwhile ("Shift", "Alt+Shift"). For many '
        'strokes, write the steps to a file. Elements may be aimed by '
        'selector (CSS) too. Or file: a .json of steps kept to do again '
        '(a recording\'s, from browser_watch), its paths beside it.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'tabId': BrowserTools._tabId,
        'steps': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'action': {
                'type': 'string',
                'enum': [
                  'click',
                  'type',
                  'press',
                  'scroll',
                  'wait',
                  'navigate',
                  'upload',
                  'drag',
                  'hover',
                ],
              },
            },
            'required': ['action'],
          },
        },
        'file': {
          'type': 'string',
          'description':
              'Instead of steps: a .json file of them (an array, or '
              '{steps: [...]}).',
        },
        'screenshot': _screenshotProperty,
      },
      'required': ['tabId'],
    },
    run: (input, call) async {
      var steps = input['steps'] as List? ?? const [];
      // Files from the agent's folder, or from beside the steps' file.
      var folder = call.cwd;
      if (input['file'] case final String name when steps.isEmpty) {
        final file = File(_path(name, call.cwd));
        if (!file.existsSync()) throw BrowserError('No file ${file.path}.');
        try {
          steps = switch (jsonDecode(await file.readAsString())) {
            final List list => list,
            {'steps': final List list} => list,
            _ => throw const FormatException('neither an array nor {steps}'),
          };
        } on FormatException catch (error) {
          throw BrowserError('${file.path} is not steps: ${error.message}');
        }
        folder = file.parent.path;
      }
      return _acting(input, [
        for (final step in steps.cast<Map>())
          {
            ...step.cast<String, Object?>(),
            if (step['files'] case final List files)
              'files': [for (final f in files) _path('$f', folder)],
          },
      ]);
    },
  ),
];

/// Does [steps] in [input]'s tab, and says what they did and changed (and
/// shows it, if asked); throws, saying as much, at a step that fails.
Future<Object> _acting(
  Map<String, Object?> input,
  List<Map<String, Object?>> steps,
) async {
  if (steps.isEmpty) throw const BrowserError('No step to do.');
  final browser = BrowserTools._browser();
  final tabId = input['tabId'] as int;
  final tab = BrowserTab(browser, tabId);
  final since = DateTime.now();
  final before = await _stateOf(browser, tabId);
  final many = steps.length > 1;
  final said = <String>[];
  // The run of drags going on: its first step, and its line in said.
  (int, int)? strokes;
  String? failed;
  for (final (i, step) in steps.indexed) {
    final at = DateTime.now();
    try {
      // A breakpoint the step runs into stops it there: the browser holds
      // its input till the page goes on.
      final doing = _step(browser, tabId, step);
      final paused = _Debugging.whenPaused(tab).then((_) => null);
      final did = await Future.any<String?>([doing, paused]);
      if (did == null) {
        doing.ignore();
        said.add(
          '${many ? '${i + 1}. ' : ''}${step['action']}: paused in the debugger.',
        );
        break;
      }
      // A run of strokes (a drawing's) said as one.
      if (step['action'] == 'drag' &&
          i > 0 &&
          steps[i - 1]['action'] == 'drag') {
        strokes ??= (i - 1, said.length - 1);
      } else {
        strokes = null;
      }
      if (strokes case (final first, final line) when i - first >= 2) {
        said
          ..length = line
          ..add('${first + 1}–${i + 1}. Dragged ${i - first + 1} strokes.');
      } else {
        said.add(many ? '${i + 1}. $did' : did);
      }
      // Strokes one after another (a drawing's) are not waited between.
      final stroke =
          step['action'] == 'drag' &&
          i + 1 < steps.length &&
          steps[i + 1]['action'] == 'drag';
      if (step['action'] != 'wait' && !stroke) {
        await _settle(browser, tabId, at, url: before?.url);
      }
    } on Object catch (error) {
      final why = error is BrowserError ? error.message : '$error';
      failed = many
          ? 'Step ${i + 1} failed: $why'
                '${i + 1 < steps.length ? '\n(The steps after it were not done.)' : ''}'
          : why;
      break;
    }
  }
  final after = await _stateOf(browser, tabId);
  final changes = _changes(before, after, tab, since);
  final text = [
    ...said,
    ?failed,
    if (said.isNotEmpty) ...[if (many || failed != null) 'Now:', changes],
  ].join('\n');
  if (failed != null) throw BrowserError(text);
  if (input['screenshot'] == true) {
    return [claudeSdkText(text), await BrowserTools.screenshot(browser, tabId)];
  }
  return text;
}

/// One step, done: what it did, in a few words.
Future<String> _step(
  BrowserConnection browser,
  int tabId,
  Map<String, Object?> step,
) => switch (step['action']) {
  'click' => _click(browser, tabId, step),
  'type' => _type(browser, tabId, step),
  'press' => _pressStep(browser, tabId, step),
  'scroll' => _scroll(browser, tabId, step),
  'wait' => _wait(browser, tabId, step),
  'navigate' => _navigate(browser, tabId, step),
  'upload' => _upload(browser, tabId, step),
  'drag' => _drag(browser, tabId, step),
  'hover' => _hover(browser, tabId, step),
  final action => throw BrowserError('No action ${jsonEncode(action)}.'),
};

/// Gives a file input [step]'s files: the input itself, or what opens the
/// file chooser (a button), the chooser caught and answered.
Future<String> _upload(
  BrowserConnection browser,
  int tabId,
  Map<String, Object?> step,
) async {
  final files = [for (final f in (step['files'] as List? ?? const [])) '$f'];
  if (files.isEmpty) throw const BrowserError('Say the files: files.');
  for (final file in files) {
    if (!File(file).existsSync()) throw BrowserError('No file $file.');
  }
  if (browser.fileAccess == false) {
    throw const BrowserError(BrowserConnection.fileAccessHelp);
  }
  final target = _targetOf(step);
  if (target == null) {
    throw const BrowserError(
      'Aim it: the file input or the button that opens the file chooser '
      '(ref, text, selector).',
    );
  }
  final element = await _find(browser, tabId, target);
  final selector = '[data-bao-ref="${element['ref']}"]';
  final names = files.map(p.basename).join(', ');
  final result = await browser.cdp(tabId, 'Runtime.evaluate', {
    'expression': 'document.querySelector(\'$selector\')',
  });
  final objectId = (result['result'] as Map?)?['objectId'] as String?;
  final isInput = await BrowserTools._evaluate(
    browser,
    tabId,
    '(() => { const e = document.querySelector(\'$selector\'); '
    'return !!e && e.tagName === "INPUT" && e.type === "file"; })()',
  );
  if (isInput == true && objectId != null) {
    await browser.cdp(tabId, 'DOM.setFileInputFiles', {
      'files': files,
      'objectId': objectId,
    });
    return 'Chose $names in ${_elementName(element)}.';
  }
  final opened = Completer<int>();
  final subscription = BrowserBridge.instance.events.listen((event) {
    if (event.event == 'cdp' &&
        identical(event.connection, browser) &&
        event.tabId == tabId &&
        event.message['method'] == 'Page.fileChooserOpened' &&
        !opened.isCompleted) {
      final node = (event.message['params'] as Map?)?['backendNodeId'];
      if (node is int) opened.complete(node);
    }
  });
  await browser.cdp(tabId, 'Page.setInterceptFileChooserDialog', {
    'enabled': true,
  });
  try {
    await _click(browser, tabId, {'ref': element['ref']});
    final node = await opened.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => throw BrowserError(
        '${_elementName(element)} opened no file chooser: aim at the file '
        'input (selector input[type=file]).',
      ),
    );
    await browser.cdp(tabId, 'DOM.setFileInputFiles', {
      'files': files,
      'backendNodeId': node,
    });
    return 'Chose $names through ${_elementName(element)}.';
  } finally {
    await subscription.cancel();
    await browser
        .cdp(tabId, 'Page.setInterceptFileChooserDialog', {'enabled': false})
        .catchError((Object _) => <String, Object?>{});
  }
}

/// The point [step] aims at, its element's or its x and y, and what it is
/// called. An element covered is an error, unless [covered] lets it be (a
/// drag's end, under what is dragged).
Future<(double, double, String)> _aim(
  BrowserConnection browser,
  int tabId,
  Map<String, Object?> step, {
  bool covered = false,
}) async {
  if (_targetOf(step) case final target?) {
    final element = await _find(browser, tabId, target);
    final point = await _bao(browser, tabId, 'point(${element['ref']})') as Map;
    if (point['covered'] case final Map over when !covered) {
      final close = (over['close'] as List? ?? const []).cast<Map>();
      throw BrowserError(
        '${_elementName(element)} is covered by ${jsonEncode(over['name'])}'
        '${close.isEmpty ? '.' : ': to close it, ${close.map((c) => _elementName(c.cast())).join(' or ')}.'}',
      );
    }
    if (point['error'] case final String error) throw BrowserError(error);
    return (
      (point['x'] as num).toDouble(),
      (point['y'] as num).toDouble(),
      _elementName(element),
    );
  }
  if ((step['x'], step['y']) case (final num x, final num y)) {
    return (x.toDouble(), y.toDouble(), '(${x.round()}, ${y.round()})');
  }
  throw const BrowserError('Aim it: ref, text (role, near), or x and y.');
}

Future<String> _click(
  BrowserConnection browser,
  int tabId,
  Map<String, Object?> step,
) async {
  final (x, y, name) = await _aim(browser, tabId, step);
  final what = _targetOf(step) == null ? 'at $name' : name;
  final button = step['button'] as String? ?? 'left';
  final count = step['clickCount'] as int? ?? 1;
  final keys = _Held(browser, tabId, step['modifiers'] as String?);
  Future<void> mouse(String type, [int clicks = 0]) =>
      browser.cdp(tabId, 'Input.dispatchMouseEvent', {
        'type': type,
        'x': x,
        'y': y,
        'button': type == 'mouseMoved' ? 'none' : button,
        'clickCount': clicks,
        'modifiers': keys.mask,
      });
  await keys.down();
  try {
    await mouse('mouseMoved');
    for (var i = 1; i <= count; i++) {
      await mouse('mousePressed', i);
      await mouse('mouseReleased', i);
    }
  } finally {
    await keys.up();
  }
  return 'Clicked $what${keys.said}.';
}

/// The mouse moved over [step]'s element or point, no button down: what
/// opens on hovering (a menu, a tooltip) opens.
Future<String> _hover(
  BrowserConnection browser,
  int tabId,
  Map<String, Object?> step,
) async {
  final (x, y, name) = await _aim(browser, tabId, step);
  await browser.cdp(tabId, 'Input.dispatchMouseEvent', {
    'type': 'mouseMoved',
    'x': x,
    'y': y,
    'button': 'none',
  });
  return 'Hovered over ${_targetOf(step) == null ? 'the point ' : ''}$name.';
}

/// Modifier keys held through a click or a drag: pressed before, let go
/// after, and in each mouse event's mask (what pages read of it).
class _Held {
  _Held(this.browser, this.tabId, String? combo)
    : keys = [
        for (final name in (combo ?? '').split('+'))
          if (name.trim().isNotEmpty)
            switch (name.trim().toLowerCase()) {
              'alt' || 'option' => ('Alt', 'AltLeft', 18, 1),
              'control' || 'ctrl' => ('Control', 'ControlLeft', 17, 2),
              'meta' || 'cmd' || 'command' => ('Meta', 'MetaLeft', 91, 4),
              'shift' => ('Shift', 'ShiftLeft', 16, 8),
              _ => throw BrowserError('Unknown modifier ${name.trim()}.'),
            },
      ];

  final BrowserConnection browser;
  final int tabId;

  /// Each key's name, code, key code and bit of the mask.
  final List<(String, String, int, int)> keys;

  int get mask => keys.fold(0, (mask, k) => mask | k.$4);

  String get said =>
      keys.isEmpty ? '' : ', holding ${keys.map((k) => k.$1).join('+')}';

  Future<void> down() async {
    var mask = 0;
    for (final (key, code, keyCode, bit) in keys) {
      mask |= bit;
      await _key('rawKeyDown', key, code, keyCode, mask);
    }
  }

  /// Let go, the last first; a tab gone meanwhile is no matter.
  Future<void> up() async {
    var mask = this.mask;
    for (final (key, code, keyCode, bit) in keys.reversed) {
      mask &= ~bit;
      await _key('keyUp', key, code, keyCode, mask).catchError((Object _) {});
    }
  }

  Future<void> _key(
    String type,
    String key,
    String code,
    int keyCode,
    int mask,
  ) => browser.cdp(tabId, 'Input.dispatchKeyEvent', {
    'type': type,
    'key': key,
    'code': code,
    'windowsVirtualKeyCode': keyCode,
    'modifiers': mask,
  });
}

/// Drags from [step]'s element or point to `to`'s (aimed the same way), or
/// along `path` ([x, y] points): the left button held all the way, through
/// the points between, as a hand moves; to draw on a canvas, to move a
/// slider or a card. What the page lets drag and drop (draggable) is
/// dropped where it ends.
Future<String> _drag(
  BrowserConnection browser,
  int tabId,
  Map<String, Object?> step,
) async {
  final (x, y, from) = await _aim(browser, tabId, step);
  // A pen's, pressed so hard: brushes that heed it draw thick or thin.
  final pressure = (step['pressure'] as num?)?.toDouble().clamp(0.0, 1.0);
  final points = <(double, double, double?)>[];
  var to = '';
  if (step['to'] case final Map end) {
    final (ex, ey, name) = await _aim(
      browser,
      tabId,
      end.cast(),
      covered: true,
    );
    points.add((ex, ey, pressure));
    to = ' to $name';
  } else if (step['path'] case final List path when path.isNotEmpty) {
    for (final point in path) {
      if (point case [final num px, final num py, ...final rest]
          when rest.length <= 1) {
        final force = rest.isEmpty
            ? pressure
            : (rest.first as num?)?.toDouble();
        points.add((px.toDouble(), py.toDouble(), force?.clamp(0.0, 1.0)));
      } else {
        throw const BrowserError(
          'A path is [x, y] or [x, y, pressure] points.',
        );
      }
    }
    final (ex, ey, _) = points.last;
    to = ' along ${points.length} points to (${ex.round()}, ${ey.round()})';
  } else {
    throw const BrowserError(
      'Say where to: to (ref, text, or x and y), or path ([x, y] points).',
    );
  }
  // The page's own drag and drop, caught as it starts: done then with its
  // data, as the browser would.
  Map? dragged;
  final subscription = BrowserBridge.instance.events.listen((event) {
    if (event.event == 'cdp' &&
        identical(event.connection, browser) &&
        event.tabId == tabId &&
        event.message['method'] == 'Input.dragIntercepted') {
      dragged = (event.message['params'] as Map?)?['data'] as Map?;
    }
  });
  // With a pressure, a pen's events: pointerType "pen", their pressure the
  // force.
  final pen = points.any((p) => p.$3 != null);
  final keys = _Held(browser, tabId, step['modifiers'] as String?);
  Future<void> mouse(
    String type,
    double x,
    double y, {
    bool held = true,
    double? force,
  }) => browser.cdp(tabId, 'Input.dispatchMouseEvent', {
    'type': type,
    'x': x,
    'y': y,
    'button': held ? 'left' : 'none',
    'buttons': held && type != 'mouseReleased' ? 1 : 0,
    'clickCount': type == 'mouseMoved' ? 0 : 1,
    'modifiers': keys.mask,
    if (pen) 'pointerType': 'pen',
    if (pen && held && type != 'mouseReleased') 'force': force ?? 0.5,
  });
  var (px, py, pf) = (x, y, points.first.$3);
  try {
    await browser.cdp(tabId, 'Input.setInterceptDrags', {'enabled': true});
    await keys.down();
    await mouse('mouseMoved', x, y, held: false);
    await mouse('mousePressed', x, y, force: pf);
    moving:
    for (final (nx, ny, nf) in points) {
      final distance = sqrt((nx - px) * (nx - px) + (ny - py) * (ny - py));
      final moves = (distance / 8).ceil().clamp(1, 30);
      final (sx, sy, sf) = (px, py, pf);
      for (var i = 1; i <= moves; i++) {
        final t = i / moves;
        (px, py) = (sx + (nx - sx) * t, sy + (ny - sy) * t);
        pf = sf == null || nf == null ? nf ?? sf : sf + (nf - sf) * t;
        await mouse('mouseMoved', px, py, force: pf);
        if (dragged != null) break moving;
      }
    }
    if (dragged case final data?) {
      final (ex, ey, _) = points.last;
      for (final type in ['dragEnter', 'dragOver', 'drop']) {
        await browser.cdp(tabId, 'Input.dispatchDragEvent', {
          'type': type,
          'x': ex,
          'y': ey,
          'data': data,
        });
      }
      (px, py) = (ex, ey);
    }
    await mouse('mouseReleased', px, py);
  } finally {
    await keys.up();
    await subscription.cancel();
    await browser
        .cdp(tabId, 'Input.setInterceptDrags', {'enabled': false})
        .catchError((Object _) => <String, Object?>{});
  }
  return '${dragged == null ? 'Dragged' : 'Dragged and dropped'} '
      '${_targetOf(step) == null ? 'from ' : ''}$from$to${keys.said}.';
}

Future<String> _type(
  BrowserConnection browser,
  int tabId,
  Map<String, Object?> step,
) async {
  final text = step['text'] as String? ?? '';
  // Its element: by ref, or by the field's words (`into`).
  final target = _targetOf({...step, 'text': step['into']});
  var into = '';
  if (target != null) {
    final element = await _find(browser, tabId, target);
    // A color, a date: the browser's own chooser, left shut, the value
    // given as choosing it would.
    final ref = element['ref'];
    if (await _bao(browser, tabId, 'choose($ref, ${jsonEncode(text)})')
        case final Map chosen) {
      if (chosen['error'] case final String error) {
        throw BrowserError('${_elementName(element)}: $error');
      }
      return 'Set ${_elementName(element)} to ${chosen['value']}.';
    }
    // Clicked, as the user would: a box may become a field only then.
    await _click(browser, tabId, {'ref': element['ref']});
    var focused = await _bao(browser, tabId, 'focused()') as Map?;
    if (focused == null) {
      await BrowserTools._evaluate(
        browser,
        tabId,
        'document.querySelector(\'[data-bao-ref="${element['ref']}"]\')?.focus()',
      );
      focused = await _bao(browser, tabId, 'focused()') as Map?;
    }
    if (step['clear'] != false) await _bao(browser, tabId, 'selectFocused()');
    into = ' into ${_elementName((focused ?? element).cast())}';
  }
  await browser.cdp(tabId, 'Input.insertText', {'text': text});
  if (step['submit'] == true) {
    await BrowserTools._press(browser, tabId, 'Enter');
  }
  return 'Typed$into${step['submit'] == true ? ', then pressed Enter' : ''}.';
}

Future<String> _pressStep(
  BrowserConnection browser,
  int tabId,
  Map<String, Object?> step,
) async {
  final key = step['key'] as String? ?? '';
  if (key.isEmpty) throw const BrowserError('Say the key.');
  await BrowserTools._press(browser, tabId, key);
  return 'Pressed $key.';
}

Future<String> _scroll(
  BrowserConnection browser,
  int tabId,
  Map<String, Object?> step,
) async {
  if (_targetOf(step) case final target?) {
    final element = await _find(browser, tabId, target);
    await BrowserTools._evaluate(
      browser,
      tabId,
      'document.querySelector(\'[data-bao-ref="${element['ref']}"]\')'
      '?.scrollIntoView({block: "center", behavior: "instant"})',
    );
    return 'Scrolled to ${_elementName(element)}.';
  }
  var x = (step['x'] as num?)?.toDouble();
  var y = (step['y'] as num?)?.toDouble();
  if (x == null || y == null) {
    final view = await BrowserTools._evaluate(
      browser,
      tabId,
      '[innerWidth, innerHeight]',
    ) as List;
    x ??= (view[0] as num) / 2;
    y ??= (view[1] as num) / 2;
  }
  final dy = step['deltaY'] as num? ?? 0;
  final dx = step['deltaX'] as num? ?? 0;
  if (dy == 0 && dx == 0) throw const BrowserError('Say deltaY, or where to.');
  await browser.cdp(tabId, 'Input.dispatchMouseEvent', {
    'type': 'mouseWheel',
    'x': x,
    'y': y,
    'deltaX': dx,
    'deltaY': dy,
  });
  return 'Scrolled ${dy > 0
          ? 'down'
          : dy < 0
          ? 'up'
          : dx > 0
          ? 'right'
          : 'left'} '
      '${(dy != 0 ? dy : dx).abs().round()}.';
}

Future<String> _wait(
  BrowserConnection browser,
  int tabId,
  Map<String, Object?> step,
) async {
  if (step['text'] case final String text when text.isNotEmpty) {
    final timeout = Duration(
      milliseconds: ((step['ms'] as num?)?.toInt() ?? 10000).clamp(0, 30000),
    );
    final end = DateTime.now().add(timeout);
    while (true) {
      try {
        if (await _bao(browser, tabId, 'says(${jsonEncode(text)})') == true) {
          return 'The page says ${jsonEncode(text)}.';
        }
      } on Object {
        // Between pages.
      }
      if (DateTime.now().isAfter(end)) {
        throw BrowserError(
          'The page did not say ${jsonEncode(text)} in '
          '${timeout.inSeconds} s.',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }
  final ms = ((step['ms'] as num?)?.toInt() ?? 1000).clamp(0, 30000);
  await Future<void>.delayed(Duration(milliseconds: ms));
  return 'Waited $ms ms.';
}

Future<String> _navigate(
  BrowserConnection browser,
  int tabId,
  Map<String, Object?> step,
) async {
  final action = step['url'] != null
      ? null
      : step['back'] == true
      ? 'back'
      : step['forward'] == true
      ? 'forward'
      : step['reload'] == true
      ? 'reload'
      : step['to'] as String?;
  await BrowserTools._go(browser, tabId, step['url'] as String?, action);
  return switch (action) {
    null => 'Went to ${step['url']}.',
    'reload' => 'Reloaded.',
    final action => 'Went $action.',
  };
}
