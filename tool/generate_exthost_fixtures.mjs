// Runs the pinned upstream TypeScript, not the Dart port, to record the bytes
// the extension host's protocols put on the wire: IPC serialization
// (base/parts/ipc/common/ipc.ts), RPC requests and replies
// (workbench/services/extensions/common/rpcProtocol.ts) and PersistentProtocol
// framing (base/parts/ipc/common/ipc.net.ts). packages/bao_exthost/test/
// protocol_fixtures_test.dart decodes and re-encodes them byte for byte.
//
// Usage (after `npm ci --prefix tool/exthost_codegen`):
//   node tool/generate_exthost_fixtures.mjs <vscode-checkout> \
//     packages/bao_exthost/test/fixtures/protocol.json
//
// Values are described as JSON with tags: {"$undefined":true},
// {"$buffer":"<hex>"} (a VSBuffer), {"$nodeBuffer":"<hex>"},
// {"$uri":{...components}}, {"$objectWithBuffers":<value>},
// {"$token":true} (a CancellationToken), {"$error":{"name","message"}}.

import { execFileSync } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const require = createRequire(new URL('./exthost_codegen/package.json', import.meta.url));
const esbuild = require('esbuild');

const revision = '08d4889f9ec4a1685d257b9b95de036c8e1ce1e5';
const [checkout, output] = process.argv.slice(2);
if (!checkout || !output) {
  console.error('Usage: node tool/generate_exthost_fixtures.mjs <vscode-checkout> <output.json>');
  process.exit(64);
}
const head = execFileSync('git', ['-C', checkout, 'rev-parse', 'HEAD'], { encoding: 'utf8' }).trim();
if (head !== revision) throw new Error(`${checkout} is at ${head}; expected ${revision}`);

// Bundle the upstream modules, unchanged, into one ES module.
const temporary = mkdtempSync(path.join(tmpdir(), 'baocode-exthost-fixtures-'));
let upstream;
try {
  const bundle = path.join(temporary, 'upstream.mjs');
  await esbuild.build({
    stdin: {
      contents: `
        export { serialize, deserialize, BufferReader, BufferWriter } from './base/parts/ipc/common/ipc.js';
        export { PersistentProtocol } from './base/parts/ipc/common/ipc.net.js';
        export { RPCProtocol } from './workbench/services/extensions/common/rpcProtocol.js';
        export { SerializableObjectWithBuffers } from './workbench/services/extensions/common/proxyIdentifier.js';
        export { VSBuffer } from './base/common/buffer.js';
        export { URI } from './base/common/uri.js';
        export { CancellationTokenSource, CancellationToken } from './base/common/cancellation.js';
        export { CancellationError } from './base/common/errors.js';
        export { Emitter } from './base/common/event.js';
      `,
      resolveDir: path.join(checkout, 'src/vs'),
      loader: 'ts',
      sourcefile: 'fixtures-entry.ts',
    },
    bundle: true,
    format: 'esm',
    platform: 'node',
    target: 'node22',
    outfile: bundle,
    logLevel: 'warning',
    tsconfig: path.join(checkout, 'src/tsconfig.json'),
  });
  upstream = await import(pathToFileURL(bundle).href);
} finally {
  rmSync(temporary, { recursive: true, force: true });
}
const {
  serialize, deserialize, BufferReader, BufferWriter, PersistentProtocol, RPCProtocol,
  SerializableObjectWithBuffers, VSBuffer, URI, CancellationTokenSource, CancellationToken, CancellationError,
  Emitter,
} = upstream;

const hex = (bytes) => Buffer.from(bytes.buffer, bytes.byteOffset, bytes.byteLength).toString('hex');
const unhex = (s) => VSBuffer.wrap(Uint8Array.from(Buffer.from(s, 'hex')));
const tick = () => new Promise((resolve) => setTimeout(resolve, 0));

/** A tagged description -> a JavaScript value. */
function value(d) {
  if (Array.isArray(d)) return d.map(value);
  if (d && typeof d === 'object') {
    if (d.$undefined) return undefined;
    if ('$buffer' in d) return unhex(d.$buffer);
    if ('$nodeBuffer' in d) return Buffer.from(d.$nodeBuffer, 'hex');
    if ('$uri' in d) return URI.revive(d.$uri);
    if ('$objectWithBuffers' in d) return new SerializableObjectWithBuffers(value(d.$objectWithBuffers));
    if (d.$token) return new CancellationTokenSource().token;
    if ('$error' in d) {
      const e = d.$error.name === 'Canceled' ? new CancellationError() : new Error(d.$error.message);
      e.name = d.$error.name;
      // Stacks name the machine's paths: keep them out of the fixtures.
      e.stack = '<stack>';
      return e;
    }
    return Object.fromEntries(Object.entries(d).map(([k, v]) => [k, value(v)]));
  }
  return d;
}

/** A JavaScript value -> a tagged description. */
function describe(v) {
  if (v === undefined) return { $undefined: true };
  if (v instanceof VSBuffer) return { $buffer: hex(v.buffer) };
  if (v instanceof Uint8Array) return { $buffer: hex(v) };
  if (v instanceof SerializableObjectWithBuffers) return { $objectWithBuffers: describe(v.value) };
  if (CancellationToken.isCancellationToken(v)) return { $token: true };
  if (Array.isArray(v)) return v.map(describe);
  if (v && typeof v === 'object') {
    return Object.fromEntries(Object.entries(v).map(([k, e]) => [k, describe(e)]));
  }
  return v;
}

// --- IPC serialization ----------------------------------------------------------

const longString = 'x'.repeat(200) + 'é';
const ipcCases = [
  ['undefined', { $undefined: true }],
  ['null', null, false],
  ['empty string', ''],
  ['string', 'hello'],
  ['unicode string', 'héllo wörld 日本語 🎉'],
  ['long string (two-byte length)', longString],
  ['int 0', 0], ['int 1', 1], ['int 127', 127], ['int 128', 128], ['int 300', 300],
  ['int 16384', 16384], ['int max', 2147483647], ['int -1', -1], ['int min', -2147483648],
  ['int 2^31 as JSON', 2147483648], ['int 2^53 as JSON', 9007199254740992],
  ['double', 1.5], ['true', true], ['false', false],
  ['array', [1, 'a', [2, []], { $undefined: true }]],
  ['object', { a: 1, b: 'x', c: [true, null], d: { e: 'é' } }],
  ['object with escapes', { s: 'quote" backslash\\ newline\n tab\t ctrl\u0001 \u007f sep  slash/ <tag>' }],
  ['vsbuffer', { $buffer: '0001ff' }],
  ['empty vsbuffer', { $buffer: '' }],
  ['node buffer', { $nodeBuffer: 'cafe' }, false],
  ['uri', { $uri: { scheme: 'file', authority: '', path: '/a b/c#d', query: '', fragment: '' } }],
  ['request message', [100, 3, 'remoteextensionsenvironment', 'whenExtensionsReady']],
];
const ipc = ipcCases.map(([name, d, encode = true]) => {
  const writer = new BufferWriter();
  serialize(writer, value(d));
  const bytes = writer.buffer;
  return { name, value: d, encode, bytes: hex(bytes.buffer), decoded: describe(deserialize(new BufferReader(bytes))) };
});

// --- RPC ----------------------------------------------------------------------------

/** An RPCProtocol over a protocol that records what it sends. */
function rpcPair() {
  const onMessage = new Emitter();
  const sent = [];
  const protocol = { send: (b) => sent.push(hex(b.buffer)), onMessage: onMessage.event };
  const rpc = new RPCProtocol(protocol);
  return { rpc, sent, receive: (h) => onMessage.fire(unhex(h)) };
}

const uriA = { scheme: 'file', authority: '', path: '/tmp/x y', query: '', fragment: '' };
const uriB = { scheme: 'vscode-remote', authority: 'host:1', path: '/p', query: 'q=1', fragment: 'f' };
const requestCases = [
  ['json args', 9, '$executeCommand', ['cmd', [1, 'two', { x: null }], true]],
  ['no args', 9, '$getCommands', []],
  ['unicode', 120, '$ünïcödé', ['日本語 🎉', { 'ключ': 'значение' }]],
  ['uris', 30, '$acceptUris', [{ $uri: uriA }, [{ $uri: uriB }]]],
  ['cancellation', 40, '$provide', ['a', 7, { $token: true }]],
  ['cancelled', 40, '$provide', ['a', { $token: true }], true],
  ['buffer arg (mixed)', 50, '$write', ['x', { $buffer: '627566' }, 42]],
  ['undefined arg (mixed)', 50, '$maybe', ['x', { $undefined: true }, null]],
  ['object with buffers (mixed)', 50, '$withBuffers', [{
    $objectWithBuffers: { a: { $buffer: '01' }, b: [{ $buffer: '0203' }], c: { $undefined: true }, d: 'x' },
  }]],
  ['buffer and token (mixed)', 51, '$both', [{ $buffer: '' }, { $token: true }]],
];
const rpcRequests = [];
for (const [name, rpcId, method, args, cancel = false] of requestCases) {
  const { rpc, sent } = rpcPair();
  const values = value(args);
  const token = values.at(-1) && CancellationToken.isCancellationToken(values.at(-1)) ? values.at(-1) : undefined;
  let source;
  if (token && cancel) {
    source = new CancellationTokenSource();
    values[values.length - 1] = source.token;
  }
  rpc._remoteCall(rpcId, method, values).then(undefined, () => { });
  source?.cancel();
  await tick();
  rpcRequests.push({ name, rpcId, method, args, cancel, messages: [...sent] });
  rpc.dispose();
}

// Replies: an upstream main thread's request, served by an upstream actor.
const replyCases = [
  ['undefined (ReplyOKEmpty)', { $undefined: true }],
  ['null (ReplyOKJSON)', null],
  ['string', 'ok'],
  ['object', { label: 'é', items: [1, 2.5, false, null], uri: { $uri: uriB } }],
  ['buffer (ReplyOKVSBuffer)', { $buffer: '00ff10' }],
  ['object with buffers (ReplyOKJSONWithBuffers)', { $objectWithBuffers: { data: { $buffer: 'abcd' }, none: { $undefined: true }, n: 1 } }],
  ['error (ReplyErrError)', undefined, { $error: { name: 'Error', message: 'boom' } }],
  ['named error', undefined, { $error: { name: 'FileNotFound', message: 'no such file' } }],
  ['cancelled (Canceled)', undefined, { $error: { name: 'Canceled', message: 'Canceled' } }],
  ['rejected with undefined (ReplyErrEmpty)', undefined, { $undefined: true }],
];
const replyRequests = [
  ['json request', 9, '$executeCommand', ['cmd', [1, { a: null }], true]],
  ['request with token', 40, '$provide', [{ $uri: uriA }, { $token: true }]],
  ['mixed request', 50, '$write', [{ $buffer: '6869' }, { $undefined: true }, { $objectWithBuffers: { b: { $buffer: '01' } } }]],
];
const rpcReplies = [];
for (const [rname, rpcId, method, args] of replyRequests) {
  for (const [name, result, error] of replyCases) {
    // The request, as an upstream main thread sends it.
    const caller = rpcPair();
    caller.rpc._remoteCall(rpcId, method, value(args)).then(undefined, () => { });
    const request = caller.sent[0];
    caller.rpc.dispose();
    // An upstream actor serving it.
    const server = rpcPair();
    let received;
    server.rpc._locals[rpcId] = {
      [method]: (...a) => {
        received = describe(a);
        if (error) {
          // eslint-disable-next-line no-throw-literal
          return Promise.reject(error.$undefined ? undefined : value(error));
        }
        return value(result);
      },
    };
    server.receive(request);
    await tick();
    rpcReplies.push({
      name: `${rname}: ${name}`, rpcId, method, request, received,
      result: error ? undefined : result, error,
      messages: [...server.sent],
    });
    server.rpc.dispose();
  }
}

// --- PersistentProtocol framing ------------------------------------------------------

function fakeSocket() {
  const onData = new Emitter();
  const written = [];
  const none = { dispose() { } };
  return {
    written,
    data: (h) => onData.fire(unhex(h)),
    socket: {
      onData: (l) => onData.event(l), onClose: () => none, onEnd: () => none,
      write: (b) => written.push(hex(b.buffer)), end() { }, drain: async () => { },
      traceSocketEvent() { }, dispose() { },
    },
  };
}

// The other side's messages, framed as upstream frames them.
function frame(type, id, ack, bodyHex) {
  const body = Buffer.from(bodyHex, 'hex');
  const h = Buffer.alloc(13);
  h.writeUInt8(type, 0); h.writeUInt32BE(id, 1); h.writeUInt32BE(ack, 5); h.writeUInt32BE(body.length, 9);
  return Buffer.concat([h, body]).toString('hex');
}

const ops = [
  ['send', '6f6e65'],
  ['send', ''],
  ['sendControl', '7b7d'],
  ['receive', frame(1, 1, 1, '696e')],
  ['receive', frame(1, 2, 2, '')],
  ['send', '74776f'],
  ['sendPause'],
  ['sendResume'],
  ['receive', frame(2, 0, 0, '6374726c')],
  ['send', 'ff'.repeat(300)],
  ['sendDisconnect'],
];
const persistent = await (async () => {
  const s = fakeSocket();
  const p = new PersistentProtocol({ socket: s.socket, sendKeepAlive: false });
  const messages = [];
  const controls = [];
  p.onMessage((m) => messages.push(hex(m.buffer)));
  p.onControlMessage((m) => controls.push(hex(m.buffer)));
  for (const [op, arg] of ops) {
    if (op === 'receive') s.data(arg);
    else if (arg !== undefined) p[op](unhex(arg));
    else p[op]();
    await tick();
  }
  p.dispose();
  return { ops, written: s.written.join(''), messages, controls };
})();

writeFileSync(output, JSON.stringify({
  revision,
  attribution: 'Generated by tool/generate_exthost_fixtures.mjs from VS Code (Copyright (c) Microsoft Corporation, MIT License).',
  ipc, rpcRequests, rpcReplies, persistent,
}, null, 1) + '\n');
console.log(`${ipc.length} IPC values, ${rpcRequests.length} RPC requests, ${rpcReplies.length} RPC replies, ${ops.length} framing steps`);
// Upstream timers (LoadEstimator, RPC unresponsiveness checks) keep Node alive.
process.exit(0);
