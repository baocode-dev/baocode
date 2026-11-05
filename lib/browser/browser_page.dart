part of 'browser_tools.dart';

// What the agents' tools know of a page, from a helper put in it
// (window.__bao, _pageScript): the elements one can act on, numbered for
// good (a number stays its element's while it is there), found again by
// their words, and the page's state, to say what an action changed.

/// The page's state, as an action's before and after: where it is, what is
/// focused, the elements and the text on screen.
class _PageState {
  _PageState(Map value)
    : url = value['url'] as String? ?? '',
      title = value['title'] as String? ?? '',
      focus = (value['focus'] as Map?)?.cast<String, Object?>(),
      elements = [
        for (final e in (value['elements'] as List? ?? const []).cast<Map>())
          e.cast<String, Object?>(),
      ],
      lines = (value['lines'] as List? ?? const []).cast<String>();

  final String url;
  final String title;
  final Map<String, Object?>? focus;
  final List<Map<String, Object?>> elements;
  final List<String> lines;
}

/// The page helper's [call] (`find({...})`, `state()`…) in [tabId]'s page,
/// put there first if it is not.
Future<Object?> _bao(BrowserConnection browser, int tabId, String call) =>
    BrowserTools._evaluate(
      browser,
      tabId,
      '(() => { $_pageScript; return window.__bao.$call; })()',
    );

/// An element as a line the agent reads: `[12] button "Reply"`, with its
/// value and state.
String _elementLine(Map<String, Object?> e) => [
  '[${e['ref']}] ${e['kind']}',
  if (e['name'] case final String name when name.isNotEmpty) jsonEncode(name),
  if (e['value'] case final String value when value.isNotEmpty)
    'value=${jsonEncode(value)}',
  if (e['checked'] == true) 'checked',
  if (e['checked'] == false) 'unchecked',
  if (e['expanded'] == true) 'expanded',
  if (e['selected'] == true) 'selected',
  if (e['disabled'] == true) 'disabled',
  if (e['inView'] == false) '(off screen)',
].join(' ');

/// An element as an action names it: `button "Reply" [12]`.
String _elementName(Map<String, Object?> e) => [
  e['kind'],
  if (e['name'] case final String name when name.isNotEmpty) jsonEncode(name),
  '[${e['ref']}]',
].join(' ');

/// Where an action is aimed, as its input says: an element's ref, or its
/// words (text, role, near, nth); null for none.
Map<String, Object?>? _targetOf(Map<String, Object?> input) {
  final target = {
    for (final key in ['ref', 'selector', 'text', 'role', 'near', 'nth'])
      if (input[key] case final value?
          when value is! String || value.isNotEmpty)
        key: value,
  };
  return target.isEmpty ? null : target;
}

/// The input properties that aim an action at an element.
const _targetProperties = {
  'ref': {
    'type': 'integer',
    'description':
        "The element's number, as a snapshot or an action's answer gave it "
        '(they stay while the element is there).',
  },
  'text': {
    'type': 'string',
    'description':
        'Instead of a ref: the words the element shows or is labeled with '
        '(its text, aria-label, placeholder, title), e.g. "Reply".',
  },
  'role': {
    'type': 'string',
    'description':
        'With text, or alone: the kind of element, e.g. button, link, '
        'textbox, checkbox, combobox.',
  },
  'near': {
    'type': 'string',
    'description':
        'With text: words close to it on the page, to tell it from others '
        'alike, e.g. the author of the comment whose "Reply" it is.',
  },
  'nth': {
    'type': 'integer',
    'description':
        'With text or selector: which of the matches (1 the first), when '
        'several are alike.',
  },
  'selector': {
    'type': 'string',
    'description':
        'Instead of a ref or text: a CSS selector (its first match shown, '
        'else its first), e.g. input[type=file].',
  },
};

/// The element [target] names, waited for while it is not there yet (up
/// to [wait]); throws, saying why, when it is not found or not alone.
Future<Map<String, Object?>> _find(
  BrowserConnection browser,
  int tabId,
  Map<String, Object?> target, {
  Duration wait = const Duration(seconds: 3),
}) async {
  final end = DateTime.now().add(wait);
  while (true) {
    Map? result;
    try {
      result =
          await _bao(browser, tabId, 'find(${jsonEncode(target)})') as Map?;
    } on BrowserError {
      rethrow;
    } on Object {
      // Between pages: tried again.
    }
    if (result?['found'] case final Map found) {
      return found.cast<String, Object?>();
    }
    if (result?['ambiguous'] case final List candidates) {
      throw BrowserError(
        [
          '${candidates.length} elements match: say which with ref, near or nth.',
          for (final c in candidates.cast<Map>())
            switch (c['context']) {
              final String context when context.isNotEmpty =>
                '${_elementLine(c.cast())} — in ${jsonEncode(context)}',
              _ => _elementLine(c.cast()),
            },
        ].join('\n'),
      );
    }
    if (DateTime.now().isAfter(end)) {
      throw BrowserError(
        [
          result?['error'] as String? ?? 'Not found: ${jsonEncode(target)}.',
          if (result?['onScreen'] case final List elements
              when elements.isNotEmpty) ...[
            'On screen:',
            for (final e in elements.cast<Map>()) _elementLine(e.cast()),
          ],
        ].join('\n'),
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
}

/// The page's state now; null between pages.
Future<_PageState?> _stateOf(BrowserConnection browser, int tabId) async {
  final tab = BrowserTab(browser, tabId);
  if (_Debugging.pausedNow(tab) ||
      BrowserRecords.instance.openDialog(tab) != null) {
    return null;
  }
  try {
    return _PageState(await _bao(browser, tabId, 'state()') as Map);
  } on Object {
    return null;
  }
}

/// Waits for the page to settle after an action [since]: loaded, its
/// requests answered, its document still a moment; at most a couple of
/// seconds (more for a new page).
Future<void> _settle(
  BrowserConnection browser,
  int tabId,
  DateTime since, {
  String? url,
}) async {
  await Future<void>.delayed(const Duration(milliseconds: 150));
  final tab = BrowserTab(browser, tabId);
  var limit = const Duration(seconds: 2);
  while (DateTime.now().difference(since) < limit) {
    // Stopped: nothing settles till it goes on.
    if (_Debugging.pausedNow(tab) ||
        BrowserRecords.instance.openDialog(tab) != null) {
      return;
    }
    try {
      final state =
          await _bao(browser, tabId, 'settling()') as List? ?? const [];
      if (url != null && state[2] != url) {
        // A new page: given its time to load.
        limit = const Duration(seconds: 8);
      }
      final pending = BrowserRecords.instance
          .requests(tab)
          .where(
            (r) =>
                !r.finished &&
                r.wall * 1000 >= since.millisecondsSinceEpoch &&
                // Long-lived: never done.
                r.type != 'WebSocket' &&
                r.type != 'EventSource',
          );
      if (state[0] == 'complete' &&
          (state[1] as num) >= 300 &&
          pending.isEmpty) {
        return;
      }
    } on Object {
      // Between pages.
      limit = const Duration(seconds: 8);
    }
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }
}

/// What changed from [before] to [after], for the agent: a new page's
/// overview, else the focus, the elements that came, went or changed, the
/// new words on screen; and what went wrong meanwhile ([since]).
String _changes(
  _PageState? before,
  _PageState? after,
  BrowserTab tab,
  DateTime since,
) {
  final lines = <String>[];
  String bare(String url) => url.split('#').first;
  if (after == null) {
    // Stopped (the debugger, a dialog): said below.
    if (!_Debugging.pausedNow(tab) &&
        BrowserRecords.instance.openDialog(tab) == null) {
      lines.add('The page is still loading.');
    }
  } else if (before == null || bare(before.url) != bare(after.url)) {
    lines.addAll(_overview(after));
  } else {
    if (after.title != before.title) lines.add('Title: ${after.title}');
    if (after.url != before.url) lines.add('URL: ${after.url}');
    // Where typing goes: a field focused (a button clicked is too, which
    // says nothing).
    bool typed(Map<String, Object?>? e) =>
        const {'textbox', 'searchbox', 'combobox'}.contains(e?['kind']);
    final focus = after.focus;
    final focused = typed(focus) && focus!['ref'] != before.focus?['ref']
        ? focus
        : null;
    if (focused != null) lines.add('Focused: ${_elementLine(focused)}');
    final was = {for (final e in before.elements) e['ref']: e};
    final now = {for (final e in after.elements) e['ref']};
    final came = [
      for (final e in after.elements)
        if (!was.containsKey(e['ref'])) e,
    ];
    final changed = [
      for (final e in after.elements)
        if (was[e['ref']] case final old?
            when (old['name'] != e['name'] || old['value'] != e['value']) &&
                e['ref'] != focused?['ref'])
          (e, old),
    ];
    final gone = [
      for (final e in before.elements)
        if (!now.contains(e['ref'])) e,
    ];
    if (came.isNotEmpty) {
      lines.add('Appeared:');
      for (final e in came.take(15)) {
        lines.add('  ${_elementLine(e)}');
      }
      if (came.length > 15) lines.add('  and ${came.length - 15} more');
    }
    for (final (e, old) in changed.take(8)) {
      final was = old['value'] != e['value'] ? old['value'] ?? '' : old['name'];
      lines.add('Changed: ${_elementLine(e)} (was ${jsonEncode(was)})');
    }
    if (gone.isNotEmpty) {
      lines.add(
        gone.length <= 5
            ? 'Gone: ${gone.map(_elementName).join(', ')}'
            : 'Gone: ${gone.length} elements',
      );
    }
    // New words: a message, a toast, what an element's change says not.
    final said = {
      for (final e in [...came, for (final (e, _) in changed) e, ?focused]) ...[
        e['name'],
        e['value'],
      ],
    };
    final seen = before.lines.toSet();
    final words = [
      for (final line in after.lines)
        if (!seen.contains(line) && !said.contains(line)) line,
    ];
    if (words.isNotEmpty) {
      lines.add(
        'New text: ${words.take(8).map(jsonEncode).join(' | ')}'
        '${words.length > 8 ? ' and ${words.length - 8} more' : ''}',
      );
    }
  }
  lines.addAll(_troubles(tab, since));
  return lines.isEmpty ? 'Nothing changed on screen.' : lines.join('\n');
}

/// A page as a new one is told: where, the elements and words on screen.
List<String> _overview(_PageState page, {int elements = 40, int words = 25}) =>
    [
      'Page: ${page.title} — ${page.url}',
      if (page.elements.isEmpty) 'Nothing to act on on screen.',
      if (page.elements.isNotEmpty) 'On screen:',
      for (final e in page.elements.take(elements)) '  ${_elementLine(e)}',
      if (page.elements.length > elements)
        '  and ${page.elements.length - elements} more (browser_snapshot)',
      if (page.lines.isNotEmpty)
        'Text: ${page.lines.take(words).join(' | ')}'
            '${page.lines.length > words ? ' …' : ''}',
    ];

/// What happened in [tab] [since] besides the screen: the requests to its
/// server (XHR, fetch, sockets), errors logged, requests failed, dialogs,
/// downloads; and the debugger paused.
List<String> _troubles(BrowserTab tab, DateTime since) {
  final records = BrowserRecords.instance;
  final after = since.millisecondsSinceEpoch;
  final requests = [
    for (final r in records.requests(tab))
      if (r.wall * 1000 >= after) r,
  ];
  final calls = [
    for (final r in requests)
      if (const {'XHR', 'Fetch', 'WebSocket', 'EventSource'}.contains(r.type))
        r,
  ];
  return [
    if (calls.isNotEmpty)
      'Requests: ${calls.take(6).map((r) => '${r.method} ${_clip(r.url.split('?').first, 100)} ${r.status ?? r.failure ?? 'pending'} (${r.id})').join('; ')}'
          '${calls.length > 6 ? '; and ${calls.length - 6} more' : ''}',
    ...[
      for (final entry in records.console(tab))
        if (!entry.time.isBefore(since) && entry.level == 'error')
          'Console error: ${_clip(entry.text.split('\n').first, 200)}',
      for (final r in requests)
        if (!calls.contains(r) && (r.failure != null || (r.status ?? 0) >= 400))
          'Request failed: ${r.method} ${r.status ?? r.failure} '
              '${_clip(r.url, 150)}',
    ].take(6),
    for (final dialog in records.dialogs(tab))
      if (!dialog.time.isBefore(since))
        '${dialog.describe()}${dialog.answer == 'dismissed' && dialog.by == 'BaoCode' ? ' To accept it: browser_dialog accept, then again.' : ''}',
    for (final download in records.downloads(tab))
      if (!download.time.isBefore(since))
        'Download: ${download.name} (${_clip(download.url, 120)}): '
            '${download.state == 'completed' ? 'done, ${_bytes(download.total)}, in the browser\'s download folder' : download.state}.',
    ?_Debugging.pausedNote(tab),
  ];
}

/// The page helper, put in a page once (window.__bao).
const _pageScript = r'''
if (!window.__bao || window.__bao.v !== 3) (() => {
  let next = 0;
  for (const e of document.querySelectorAll('[data-bao-ref]')) next = Math.max(next, Number(e.getAttribute('data-bao-ref')) || 0);
  const B = window.__bao = { v: 3, next, changed: Date.now() };
  try {
    new MutationObserver((records) => {
      for (const r of records) {
        if (r.type !== 'attributes' || r.attributeName !== 'data-bao-ref') { B.changed = Date.now(); return; }
      }
    }).observe(document, { subtree: true, childList: true, attributes: true, characterData: true });
  } catch (e) {}
  const ACTIONABLE = 'a[href], button, input:not([type=hidden]), select, textarea, summary, ' +
    '[role=button], [role=link], [role=checkbox], [role=radio], [role=tab], [role=menuitem], ' +
    '[role=option], [role=switch], [role=combobox], [role=textbox], [role=searchbox], ' +
    '[contenteditable=""], [contenteditable=true], [onclick], [tabindex]:not([tabindex="-1"])';
  const norm = (t) => (t || '').replace(/\s+/g, ' ').trim();
  const clip = (t, n) => { t = norm(t); return t.length > n ? t.slice(0, n) + '…' : t; };
  const style = (e) => getComputedStyle(e);
  const shown = (e) => {
    const r = e.getBoundingClientRect();
    if (r.width <= 0 || r.height <= 0) return false;
    const s = style(e);
    return s.visibility !== 'hidden' && s.display !== 'none' && s.opacity !== '0';
  };
  const inView = (e) => {
    const r = e.getBoundingClientRect();
    return r.bottom > 0 && r.right > 0 && r.top < innerHeight && r.left < innerWidth;
  };
  const field = (e) => e.tagName === 'INPUT' || e.tagName === 'TEXTAREA' || e.tagName === 'SELECT';
  const editableRoot = (e) => e.isContentEditable && !(e.parentElement && e.parentElement.isContentEditable);
  // What the page made to click: the hand cursor, where it starts.
  const pointerRoot = (e) => style(e).cursor === 'pointer' &&
    !(e.parentElement && style(e.parentElement).cursor === 'pointer');
  const actionable = (e) => e.matches(ACTIONABLE) || editableRoot(e) || pointerRoot(e);
  const kind = (e) => {
    const role = e.getAttribute('role');
    if (role) return role;
    const tag = e.tagName.toLowerCase();
    if (tag === 'input') {
      if (e.type === 'checkbox' || e.type === 'radio' || e.type === 'file') return e.type;
      if (['button', 'submit', 'reset', 'image'].includes(e.type)) return 'button';
      if (e.type === 'color') return 'color';
      return e.type === 'range' ? 'slider' : 'textbox';
    }
    if (tag === 'textarea' || e.isContentEditable) return 'textbox';
    if (tag === 'select') return 'combobox';
    if (tag === 'a') return 'link';
    if (tag === 'button' || tag === 'summary') return 'button';
    return 'clickable';
  };
  // Its words, whole: what it is labeled, else what it shows.
  const words = (e) => {
    let t = e.getAttribute('aria-label') || '';
    if (!t && field(e)) t = (e.labels && e.labels[0] && e.labels[0].innerText) || e.getAttribute('placeholder') || e.getAttribute('name') || '';
    if (!t && e.isContentEditable) {
      t = e.getAttribute('aria-placeholder') || e.getAttribute('data-placeholder') || '';
      for (let n = e.parentElement, i = 0; n && i < 3 && !t; n = n.parentElement, i++) {
        const ph = n.querySelector('[class*="placeholder" i]');
        if (ph && ph !== e && !e.contains(ph)) t = ph.innerText;
      }
    }
    if (!t && !field(e) && !e.isContentEditable) t = e.innerText;
    if (!t) t = e.getAttribute('title') || e.getAttribute('alt') || '';
    if (!t) {
      const i = e.querySelector('img[alt], svg[aria-label], [title], [aria-label]');
      if (i) t = i.getAttribute('alt') || i.getAttribute('aria-label') || i.getAttribute('title') || '';
    }
    return norm(t);
  };
  const ref = (e) => {
    let r = e.getAttribute('data-bao-ref');
    if (!r) { r = String(++B.next); e.setAttribute('data-bao-ref', r); }
    return Number(r);
  };
  const describe = (e) => {
    const d = { ref: ref(e), kind: kind(e), name: clip(words(e), 80) };
    if (field(e) && e.type !== 'password' && e.type !== 'checkbox' && e.type !== 'radio') {
      const v = e.tagName === 'SELECT' ? (e.selectedOptions[0] ? e.selectedOptions[0].text : '') : e.value;
      if (v) d.value = clip(v, 60);
    } else if (e.isContentEditable) {
      const v = clip(e.innerText, 60);
      if (v && v !== d.name) d.value = v;
    }
    if (e.type === 'checkbox' || e.type === 'radio') d.checked = e.checked;
    else if (e.getAttribute('aria-checked')) d.checked = e.getAttribute('aria-checked') === 'true';
    if (e.disabled || e.getAttribute('aria-disabled') === 'true') d.disabled = true;
    if (e.getAttribute('aria-expanded')) d.expanded = e.getAttribute('aria-expanded') === 'true';
    if (e.getAttribute('aria-selected') === 'true' || e.getAttribute('aria-pressed') === 'true') d.selected = true;
    const r = e.getBoundingClientRect();
    d.rect = [Math.round(r.left), Math.round(r.top), Math.round(r.width), Math.round(r.height)];
    d.inView = inView(e);
    return d;
  };
  const all = () => {
    const out = [];
    if (!document.body) return out;
    for (const e of document.body.getElementsByTagName('*')) if (actionable(e) && shown(e)) out.push(e);
    return out;
  };
  B.elements = (scope) => {
    const out = [];
    const max = scope === 'page' ? 500 : 300;
    for (const e of all()) {
      if (out.length >= max) break;
      if (scope !== 'page' && !inView(e)) continue;
      out.push(describe(e));
    }
    return out;
  };
  // The words shown, a piece each, as they come.
  B.lines = (scope, max) => {
    const out = [];
    const seen = new Set();
    if (!document.body) return out;
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
    const ok = new Map();
    let size = 0;
    for (let n = walker.nextNode(); n && out.length < max && size < 20000; n = walker.nextNode()) {
      const t = norm(n.nodeValue);
      if (!t) continue;
      const p = n.parentElement;
      if (!p) continue;
      let v = ok.get(p);
      if (v === undefined) {
        v = !['SCRIPT', 'STYLE', 'NOSCRIPT', 'TEMPLATE'].includes(p.tagName) && shown(p) && (scope === 'page' || inView(p));
        ok.set(p, v);
      }
      if (!v) continue;
      const line = clip(t, 160);
      if (seen.has(line)) continue;
      seen.add(line);
      out.push(line);
      size += line.length;
    }
    return out;
  };
  B.state = () => {
    const a = document.activeElement;
    return {
      url: location.href,
      title: document.title,
      focus: a && a !== document.body && a !== document.documentElement ? describe(a) : null,
      elements: B.elements('viewport').map(({ ref, kind, name, value, checked, disabled, expanded, selected }) =>
        ({ ref, kind, name, value, checked, disabled, expanded, selected })),
      lines: B.lines('viewport', 600),
    };
  };
  B.overview = (scope) => ({
    url: location.href,
    title: document.title,
    scrolled: Math.round(scrollY),
    scrollMax: Math.max(0, Math.round(document.documentElement.scrollHeight - innerHeight)),
    elements: B.elements(scope),
    lines: B.lines(scope, scope === 'page' ? 1500 : 600),
  });
  B.settling = () => [document.readyState, Date.now() - B.changed, location.href];
  // The text of the smallest of [e]'s ancestors saying more than it: where
  // it is, for the agent to tell it from others alike.
  const context = (e) => {
    const own = norm(e.innerText);
    for (let n = e.parentElement; n && n !== document.body; n = n.parentElement) {
      const t = norm(n.innerText);
      if (t.length > own.length + 8) return clip(t, 100);
    }
    return '';
  };
  B.find = (spec) => {
    if (spec.ref != null) {
      const e = document.querySelector(`[data-bao-ref="${Number(spec.ref)}"]`);
      return e && e.isConnected
        ? { found: describe(e) }
        : { error: `No element [${spec.ref}] on the page now: it went, or the page changed. Look again (browser_snapshot), or aim by text.` };
    }
    if (spec.selector) {
      let list;
      try { list = Array.from(document.querySelectorAll(spec.selector)); } catch (e) { return { error: `Not a CSS selector: ${spec.selector}` }; }
      if (spec.nth) list = list.slice(Number(spec.nth) - 1, Number(spec.nth));
      if (!list.length) return { error: `Nothing on the page matches ${spec.selector}.` };
      return { found: describe(list.find(shown) || list[0]) };
    }
    const want = norm(spec.text).toLowerCase();
    const role = spec.role ? String(spec.role).toLowerCase() : null;
    const roleOk = (k) => !role || k === role ||
      (role === 'button' && (k === 'clickable' || k === 'menuitem' || k === 'tab')) ||
      (role === 'textbox' && (k === 'searchbox' || k === 'combobox')) ||
      (role === 'link' && k === 'clickable');
    const pool = all().filter((e) => roleOk(kind(e)));
    let matches = pool;
    if (want) {
      const tiers = [[], [], []];
      for (const e of pool) {
        const names = [words(e), e.getAttribute('title'), e.getAttribute('placeholder'), field(e) ? e.value : '']
          .map((t) => norm(t).toLowerCase()).filter(Boolean);
        if (names.some((t) => t === want)) tiers[0].push(e);
        else if (names.some((t) => t.startsWith(want))) tiers[1].push(e);
        else if (names.some((t) => t.includes(want))) tiers[2].push(e);
      }
      matches = tiers.find((t) => t.length) || [];
      // Words not on anything made to click: the smallest element showing
      // them (a click there reaches what holds it).
      if (!matches.length && !role) {
        const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
        for (let n = walker.nextNode(); n && matches.length < 20; n = walker.nextNode()) {
          if (norm(n.nodeValue).toLowerCase() === want && n.parentElement && shown(n.parentElement)) matches.push(n.parentElement);
        }
      }
    }
    if (!matches.length) {
      return {
        error: want ? `Nothing on the page says ${JSON.stringify(spec.text)}${role ? ` as a ${role}` : ''}.` : `No ${role} on the page.`,
        onScreen: B.elements('viewport').filter((d) => roleOk(d.kind)).slice(0, 25),
      };
    }
    if (spec.near && matches.length > 1) {
      const near = norm(spec.near).toLowerCase();
      const anchors = [];
      const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
      for (let n = walker.nextNode(); n && anchors.length < 50; n = walker.nextNode()) {
        if (norm(n.nodeValue).toLowerCase().includes(near) && n.parentElement && shown(n.parentElement)) anchors.push(n.parentElement);
      }
      if (!anchors.length) return { error: `Nothing on the page says ${JSON.stringify(spec.near)} (near).` };
      // Closest: the smallest box holding both, then the shortest way.
      const score = (e) => {
        let best = [Infinity, Infinity];
        const r = e.getBoundingClientRect();
        for (const a of anchors) {
          let n = e;
          while (n && !n.contains(a)) n = n.parentElement;
          const box = n ? n.getBoundingClientRect() : { width: 1e9, height: 1e9 };
          const q = a.getBoundingClientRect();
          const s = [box.width * box.height, Math.hypot(r.left - q.left, r.top - q.top)];
          if (s[0] < best[0] || (s[0] === best[0] && s[1] < best[1])) best = s;
        }
        return best;
      };
      const scored = matches.map((e) => [e, score(e)]).sort((a, b) => a[1][0] - b[1][0] || a[1][1] - b[1][1]);
      matches = scored.map((s) => s[0]);
      if (!spec.nth && scored[0][1][0] < scored[1][1][0]) return { found: describe(matches[0]) };
    }
    if (spec.nth) {
      const e = matches[Number(spec.nth) - 1];
      return e ? { found: describe(e) } : { error: `Only ${matches.length} match.` };
    }
    if (matches.length === 1) return { found: describe(matches[0]) };
    const seen = matches.filter(inView);
    if (seen.length === 1 && !spec.near) return { found: describe(seen[0]) };
    return { ambiguous: matches.slice(0, 8).map((e) => ({ ...describe(e), context: context(e) })) };
  };
  // Where to click [ref]: its middle, brought on screen; unless something
  // covers it (a dialog, a banner), said with what closes that.
  B.point = (r) => {
    const e = document.querySelector(`[data-bao-ref="${Number(r)}"]`);
    if (!e) return { error: `No element [${r}] on the page now.` };
    const b = e.getBoundingClientRect();
    if (b.top < 0 || b.left < 0 || b.bottom > innerHeight || b.right > innerWidth) {
      e.scrollIntoView({ block: 'center', inline: 'center', behavior: 'instant' });
    }
    const q = e.getBoundingClientRect();
    const x = q.left + q.width / 2;
    const y = q.top + q.height / 2;
    const hit = document.elementFromPoint(x, y);
    if (hit && hit !== e && !e.contains(hit) && !hit.contains(e)) {
      let cover = hit;
      while (cover.parentElement && cover.parentElement !== document.body && !cover.parentElement.contains(e)) cover = cover.parentElement;
      const close = [];
      for (const c of cover.getElementsByTagName('*')) {
        if (close.length >= 3) break;
        if (actionable(c) && shown(c) && /关闭|close|^[×✕✖x]$|取消|知道了|跳过|skip|dismiss|not now|稍后|later|no thanks/i.test(words(c))) close.push(describe(c));
      }
      return { covered: { name: clip(cover.innerText || words(cover), 80), close } };
    }
    return { x, y };
  };
  // The focused element's text, selected: what is typed replaces it.
  B.selectFocused = () => {
    const a = document.activeElement;
    if (!a) return false;
    if ('value' in a && typeof a.select === 'function') { a.select(); return true; }
    if (a.isContentEditable) { getSelection().selectAllChildren(a); return true; }
    return false;
  };
  // Inputs the browser's own chooser picks for (a color, a date, a
  // slider's value), which no input of the protocol reaches: their value
  // set, as choosing it would, with its events. Null for other elements.
  const CHOSEN = {
    color: 'a color: #rrggbb, or as CSS says it', date: '2026-11-05', time: '14:30',
    'datetime-local': '2026-11-05T14:30', month: '2026-11', week: '2026-W45', range: 'a number',
  };
  B.choose = (r, text) => {
    const e = document.querySelector('[data-bao-ref="' + r + '"]');
    if (!e || e.tagName !== 'INPUT' || !(e.type in CHOSEN)) return null;
    let v = String(text).trim();
    if (e.type === 'color') {
      // As a canvas reads a CSS color: #rrggbb when it is opaque.
      const c = document.createElement('canvas').getContext('2d');
      c.fillStyle = '#010203';
      c.fillStyle = v;
      const read = c.fillStyle;
      if ((read === '#010203' && !/^#?010203$/i.test(v)) || !read.startsWith('#')) return { error: 'Not ' + CHOSEN.color + ', opaque.' };
      v = read;
    }
    const wrong = e.type === 'range' ? isNaN(parseFloat(v)) : !v;
    const set = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
    const was = e.value;
    if (!wrong) set.call(e, v);
    if (wrong || (e.type !== 'range' && e.value === '')) {
      set.call(e, was);
      return { error: 'It takes ' + CHOSEN[e.type] + '.' };
    }
    e.focus();
    e.dispatchEvent(new Event('input', { bubbles: true }));
    e.dispatchEvent(new Event('change', { bubbles: true }));
    return { value: e.value };
  };
  B.focused = () => {
    const a = document.activeElement;
    return a && a !== document.body && a !== document.documentElement ? describe(a) : null;
  };
  B.says = (text) => !!document.body && norm(document.body.innerText).toLowerCase().includes(norm(text).toLowerCase());
})();
''';
