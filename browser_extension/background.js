// BaoCode's browser extension: lets BaoCode's agents use the tabs shared
// with them, those of the "BaoCode" tab group (theirs, and any the user
// puts there or shares with the toolbar button). BaoCode is reached through
// its native messaging host (macos/BrowserBridge/host.c), which passes
// messages to BaoCode (lib/browser/browser_bridge.dart) and back.
//
// BaoCode asks {id, method, params} and is answered {id, result} or
// {id, error}; what happens is told as {type: "event", event, ...}.
//
// Kept thin, so that BaoCode grows without it: what an agent does in a page
// is BaoCode's, through the DevTools protocol passed on as it is (cdp, with
// the sessions of a page's frames and workers, and their events); the
// browser's tabs and windows through their APIs passed on too (call,
// subscribe). This keeps alone what only it can: the line round the tabs
// shared, which nothing BaoCode asks crosses, and the toolbar button. A
// new method here is said in CAPABILITIES; BRIDGE goes up only for a change
// an older BaoCode would get wrong.

const HOST = 'dev.baocode.browser';
const GROUP = 'BaoCode';
const PROTOCOL = '1.3';
// What BaoCode and this extension say to each other: one more with each
// change the other has to know of (lib/browser/browser_bridge.dart).
const BRIDGE = 1;
// What BaoCode may ask of this version, beyond BRIDGE 1's first methods
// (tabs.*, cdp, detach, watch): told in the hello.
const CAPABILITIES = ['cdp.session', 'call', 'subscribe', 'configure'];
// What the toolbar button opens while BaoCode is not there to connect to.
const HELP = 'https://baocode.dev/download#browser';

let port = null;
let connected = false; // To BaoCode, not just its host.
const attached = new Set(); // Tabs the debugger is attached to.
let watching = null; // The tab BaoCode watches the user in, recording.
// How BaoCode wants it (configure), as long as it is connected.
const DEFAULTS = { followOpeners: true };
let config = { ...DEFAULTS };
const subscribed = new Set(); // The browser's events BaoCode is told of.

// --- The connection.

function connect() {
  if (port) return;
  try {
    port = chrome.runtime.connectNative(HOST);
  } catch (error) {
    port = null;
    return;
  }
  port.onMessage.addListener(received);
  port.onDisconnect.addListener(() => {
    // The host is not installed, or the browser let it go.
    port = null;
    setConnected(false);
  });
}

function setConnected(value) {
  if (connected === value) return;
  connected = value;
  // BaoCode gone: nothing watches any more, and the next one says again
  // what it wants.
  if (!value) {
    watching = null;
    config = { ...DEFAULTS };
    subscribed.clear();
  }
  showState();
  if (value) hello();
}

async function hello() {
  // Whether the user let it reach file:// pages and local files (to open an
  // HTML file, to choose files for a page's input): "Allow access to file
  // URLs", off till they turn it on, the extension reloaded when they do.
  // The browser shows that switch only to an extension that could want it:
  // activeTab, in the manifest for that alone, makes this one such.
  const fileAccess = await chrome.extension.isAllowedFileSchemeAccess().catch(() => null);
  if (!connected) return;
  send({
    type: 'hello',
    protocol: BRIDGE,
    capabilities: CAPABILITIES,
    browser: browserName(),
    version: chrome.runtime.getManifest().version,
    fileAccess,
  });
}

// The toolbar button's badge and title: recording, connected, or not.
function showState() {
  chrome.action.setBadgeBackgroundColor({ color: '#c0392b' });
  chrome.action.setBadgeText({ text: watching !== null ? 'REC' : connected ? '' : '!' });
  chrome.action.setTitle({
    title:
      watching !== null
        ? 'BaoCode is watching: click when you are done'
        : connected
          ? 'BaoCode: connected'
          : 'BaoCode: not running',
  });
}

// Whether BaoCode is connected, given a moment to: a worker just woken has
// its host to start, which then finds BaoCode.
async function connection() {
  for (let waited = 0; !connected && port && waited < 1500; waited += 100) {
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  return connected;
}

function browserName() {
  const brands = navigator.userAgentData?.brands ?? [];
  const named = brands.find((b) => !/Not.A.Brand|Chromium/i.test(b.brand));
  return named?.brand ?? brands.find((b) => /Chromium/i.test(b.brand))?.brand ?? 'Chromium';
}

function send(message) {
  if (!port) return;
  try {
    port.postMessage(message);
  } catch (error) {
    // Gone: onDisconnect says so.
  }
}

function event(name, fields) {
  if (connected) send({ type: 'event', event: name, ...fields });
}

async function received(message) {
  if (message.type === 'bridge') {
    setConnected(message.connected === true);
    return;
  }
  if (message.id === undefined) return;
  try {
    const result = await handle(message.method, message.params ?? {});
    send({ id: message.id, result: result ?? null });
  } catch (error) {
    send({ id: message.id, error: String(error?.message ?? error) });
  }
}

// --- What BaoCode asks.

async function handle(method, params) {
  switch (method) {
    case 'tabs.list':
      // The shared ones alone: the others are the user's own.
      return (await sharedTabs()).map(describe);
    case 'tabs.create':
      return describe(await createTab(params.url, params.active !== false));
    case 'tabs.close':
      await sharedTab(params.tabId);
      await chrome.tabs.remove(params.tabId);
      return null;
    case 'tabs.activate': {
      const tab = await sharedTab(params.tabId);
      await chrome.tabs.update(tab.id, { active: true });
      await chrome.windows.update(tab.windowId, { focused: true });
      return null;
    }
    case 'cdp': {
      await sharedTab(params.tabId);
      await attach(params.tabId);
      // A session of the tab's (a frame's, a worker's, attached to with
      // Target.setAutoAttach, flatten) is asked through the tab's.
      const target = params.sessionId
        ? { tabId: params.tabId, sessionId: params.sessionId }
        : { tabId: params.tabId };
      return await chrome.debugger.sendCommand(target, params.method, params.params ?? {});
    }
    case 'call':
      return await call(params.api, params.args ?? []);
    case 'subscribe':
      // Those not passed on are left out: said back.
      subscribed.clear();
      for (const name of params.events ?? []) {
        if (EVENTS.includes(name)) subscribed.add(name);
      }
      return [...subscribed];
    case 'configure':
      config = { ...DEFAULTS, ...(params ?? {}) };
      return config;
    case 'detach':
      await detach(params.tabId);
      return null;
    case 'watch':
      // Recording what the user does in a tab: the button finishes it.
      watching = params.tabId ?? null;
      showState();
      return null;
    default:
      throw new Error(`Unknown method ${method}`);
  }
}

function describe(tab) {
  return {
    tabId: tab.id,
    windowId: tab.windowId,
    title: tab.title ?? '',
    url: tab.url ?? tab.pendingUrl ?? '',
    active: tab.active,
    loading: tab.status === 'loading',
  };
}

// --- The browser's APIs, passed on: tabs, windows and tab groups, within
// the line round the tabs shared.

const APIS = ['tabs', 'windows', 'tabGroups'];

// Calls chrome.<api> (`tabs.update`, `windows.get`…) with [args]: a tab it
// names (a number first, or tabIds) has to be shared, a window one with a
// shared tab, a group BaoCode's. What it answers keeps to the same: the
// shared tabs alone, BaoCode's groups alone. A tab it makes is shared.
async function call(api, args) {
  const [space, name, ...rest] = String(api).split('.');
  const fn = chrome[space]?.[name];
  if (!APIS.includes(space) || rest.length || typeof fn !== 'function' || name.startsWith('on')) {
    throw new Error(`Not a method BaoCode may call: ${api}`);
  }
  if (!Array.isArray(args)) throw new Error('args is a list');
  await guard(space, name, args);
  const result = await fn.apply(chrome[space], args);
  if (space === 'tabs' && name === 'create' && result?.id !== undefined) {
    await share(result);
    return describe(await chrome.tabs.get(result.id));
  }
  if (space === 'windows' && name === 'create') {
    for (const tab of result?.tabs ?? []) await share(tab);
    return await chrome.windows.get(result.id, { populate: true });
  }
  return await within(result);
}

async function guard(space, name, args) {
  const [first, second] = args;
  if (space === 'tabs') {
    const ids =
      typeof first === 'number'
        ? [first]
        : Array.isArray(first)
          ? first
          : typeof first?.tabIds === 'number'
            ? [first.tabIds]
            : (first?.tabIds ?? []);
    for (const tabId of ids) await sharedTab(tabId);
    // A tab put in a group: BaoCode's.
    if (first?.groupId !== undefined) await ourGroup(first.groupId);
    if (name === 'move' && second?.windowId !== undefined) await sharedWindow(second.windowId);
    if (['query', 'create', 'getCurrent'].includes(name)) return;
    if (!ids.length && name !== 'create') throw new Error(`tabs.${name} needs a shared tab`);
  } else if (space === 'windows') {
    if (typeof first === 'number') await sharedWindow(first);
    // Closing a window closes the user's tabs in it too: one of BaoCode's
    // alone.
    if (name === 'remove') {
      for (const tab of await chrome.tabs.query({ windowId: first })) await sharedTab(tab.id);
    }
  } else if (space === 'tabGroups') {
    if (typeof first === 'number') await ourGroup(first);
  }
}

// [value] with what is not BaoCode's left out: tabs not shared, groups not
// its own, a window's tabs.
async function within(value) {
  if (Array.isArray(value)) {
    const kept = [];
    for (const item of value) {
      const inside = await within(item);
      if (inside !== undefined) kept.push(inside);
    }
    return kept;
  }
  if (value === null || typeof value !== 'object') return value;
  if (typeof value.index === 'number' && typeof value.windowId === 'number' && 'pinned' in value) {
    return (await isShared(value)) ? value : undefined; // A tab.
  }
  if ('collapsed' in value && 'color' in value && 'title' in value) {
    return value.title === GROUP ? value : undefined; // A group.
  }
  if (Array.isArray(value.tabs)) return { ...value, tabs: await within(value.tabs) }; // A window.
  return value;
}

async function sharedWindow(windowId) {
  const tabs = await sharedTabs();
  if (!tabs.some((tab) => tab.windowId === windowId)) {
    throw new Error(`Window ${windowId} has no tab shared with BaoCode.`);
  }
}

async function ourGroup(groupId) {
  const group = await chrome.tabGroups.get(groupId);
  if (group.title !== GROUP) throw new Error(`Group ${groupId} is not BaoCode's.`);
}

// The browser's events BaoCode may be told of (subscribe), as
// {event: "chrome", name, args}: of the shared tabs alone.
const EVENTS = [
  'tabs.onCreated',
  'tabs.onUpdated',
  'tabs.onActivated',
  'tabs.onMoved',
  'tabs.onRemoved',
  'tabs.onReplaced',
  'tabs.onAttached',
  'tabs.onDetached',
  'tabs.onZoomChange',
  'windows.onCreated',
  'windows.onRemoved',
  'windows.onFocusChanged',
  'windows.onBoundsChanged',
  'tabGroups.onUpdated',
];

// Tabs of the group once, for the events of one closed since (onRemoved
// can no longer tell).
const shared = new Set();

for (const name of EVENTS) {
  const [space, on] = name.split('.');
  chrome[space][on].addListener(async (...args) => {
    if (!connected || !subscribed.has(name)) return;
    if (!(await concerns(space, on, args))) return;
    event('chrome', { name, args: await within(args) });
  });
}

async function concerns(space, on, args) {
  if (space === 'windows') return true;
  if (space === 'tabGroups') return args[0]?.title === GROUP;
  const [first] = args;
  if (typeof first === 'object' && first !== null) {
    // A tab, or {tabId, windowId} of onActivated / onZoomChange.
    if (typeof first.tabId === 'number') return shared.has(first.tabId) || (await sharedTabIs(first.tabId));
    return await isShared(first);
  }
  if (typeof first === 'number') {
    return shared.has(first) || (await sharedTabIs(first));
  }
  return false;
}

async function sharedTabIs(tabId) {
  try {
    return await isShared(await chrome.tabs.get(tabId));
  } catch (error) {
    return false;
  }
}

// A tab a shared one opened (a link to a new tab, a popup) is shared too:
// what the agent clicked opened it.
chrome.tabs.onCreated.addListener(async (tab) => {
  if (!config.followOpeners || tab.openerTabId === undefined) return;
  if (!(await sharedTabIs(tab.openerTabId))) return;
  try {
    await share(tab);
    event('tab', { tab: describe(await chrome.tabs.get(tab.id)) });
  } catch (error) {
    // Closed already, or in a window of its own (a popup) with no group.
  }
});

// --- The tabs shared: the "BaoCode" group's, in any window.

async function groups() {
  return chrome.tabGroups.query({ title: GROUP });
}

async function sharedTabs() {
  const tabs = [];
  for (const group of await groups()) {
    tabs.push(...(await chrome.tabs.query({ groupId: group.id })));
  }
  for (const tab of tabs) shared.add(tab.id);
  return tabs;
}

async function isShared(tab) {
  if (tab.groupId === undefined || tab.groupId < 0) return false;
  try {
    const yes = (await chrome.tabGroups.get(tab.groupId)).title === GROUP;
    if (yes) shared.add(tab.id);
    return yes;
  } catch (error) {
    return false;
  }
}

async function sharedTab(tabId) {
  const tab = await chrome.tabs.get(tabId);
  if (!(await isShared(tab))) {
    throw new Error(`Tab ${tabId} is not shared with BaoCode.`);
  }
  return tab;
}

// A tab of the group's: in the window the group is in, else in the last
// focused one, else in a new window.
async function createTab(url, active) {
  const [group] = await groups();
  let windowId = group?.windowId;
  if (windowId === undefined) {
    try {
      windowId = (await chrome.windows.getLastFocused({ windowTypes: ['normal'] })).id;
    } catch (error) {
      windowId = undefined;
    }
  }
  let tab;
  if (windowId === undefined) {
    const window = await chrome.windows.create({ url: url || 'about:blank', focused: active });
    tab = window.tabs[0];
  } else {
    tab = await chrome.tabs.create({ url: url || 'about:blank', windowId, active });
  }
  await share(tab, group);
  return chrome.tabs.get(tab.id);
}

async function share(tab, group) {
  shared.add(tab.id);
  group ??= (await groups()).find((g) => g.windowId === tab.windowId);
  if (group && group.windowId === tab.windowId) {
    await chrome.tabs.group({ tabIds: tab.id, groupId: group.id });
    return;
  }
  const groupId = await chrome.tabs.group({
    tabIds: tab.id,
    createProperties: { windowId: tab.windowId },
  });
  await chrome.tabGroups.update(groupId, { title: GROUP, color: 'yellow' });
}

// The toolbar button: shares the tab in front with BaoCode, or stops; while
// BaoCode watches the user, says they are done. Without BaoCode, tells how
// to get it.
chrome.action.onClicked.addListener(async (tab) => {
  connect();
  if (!(await connection())) {
    await chrome.tabs.create({ url: HELP, index: tab.index + 1 });
    return;
  }
  if (watching !== null) {
    event('watchDone', { tabId: watching });
    return;
  }
  if (await isShared(tab)) {
    await chrome.tabs.ungroup(tab.id);
    await detach(tab.id);
  } else {
    await share(tab);
  }
});

// --- The debugger, attached to a shared tab the first time BaoCode asks
// it something; what it tells goes to BaoCode.

async function attach(tabId) {
  if (attached.has(tabId)) return;
  try {
    await chrome.debugger.attach({ tabId }, PROTOCOL);
  } catch (error) {
    // Attached already (by this extension, before the worker restarted).
    if (!/already attached/i.test(String(error?.message))) throw error;
  }
  attached.add(tabId);
}

async function detach(tabId) {
  if (!attached.delete(tabId)) return;
  try {
    await chrome.debugger.detach({ tabId });
  } catch (error) {
    // Gone already.
  }
}

chrome.debugger.onEvent.addListener((source, method, params) => {
  if (source.tabId === undefined) return;
  event('cdp', {
    tabId: source.tabId,
    // A frame's or a worker's, of the tab's (see cdp).
    ...(source.sessionId ? { sessionId: source.sessionId } : {}),
    method,
    params: params ?? {},
  });
});

chrome.debugger.onDetach.addListener((source, reason) => {
  if (source.tabId === undefined) return;
  attached.delete(source.tabId);
  event('detached', { tabId: source.tabId, reason });
});

// --- Shared tabs' changes.

chrome.tabs.onUpdated.addListener(async (tabId, change, tab) => {
  if (!('url' in change || 'title' in change || 'status' in change || 'groupId' in change)) return;
  if ('groupId' in change && !(await isShared(tab))) {
    // Out of the group: no longer BaoCode's.
    await detach(tabId);
    event('unshared', { tabId });
    return;
  }
  if (await isShared(tab)) event('tab', { tab: describe(tab) });
});

chrome.tabs.onRemoved.addListener((tabId) => {
  attached.delete(tabId);
  // After the subscribed events' listeners have looked.
  setTimeout(() => shared.delete(tabId), 0);
  event('closed', { tabId });
});

// --- Kept connected: at start, and now and then while BaoCode is away
// (the host waits for it, which keeps this worker running).

chrome.action.setBadgeText({ text: '!' });
chrome.action.setBadgeBackgroundColor({ color: '#c0392b' });
chrome.runtime.onStartup.addListener(connect);
chrome.runtime.onInstalled.addListener(connect);
chrome.alarms.create('connect', { periodInMinutes: 1 });
chrome.alarms.onAlarm.addListener(connect);
connect();
