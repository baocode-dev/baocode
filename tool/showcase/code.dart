// The code the showcase's agents change in hono: a rate-limit middleware,
// committed counting in a fixed window (run.dart puts it there), that the
// agent moves to a sliding-window counter with pluggable stores, its tests
// with it, as edits of what is there. Plain Dart, for the runner and the
// app alike.

const rateLimiterPath = 'src/middleware/rate-limiter/index.ts';
const rateLimiterTestPath = 'src/middleware/rate-limiter/index.test.ts';

/// The middleware as committed: a window per client, the `X-RateLimit-*`
/// headers.
const rateLimiterFixedSource = r'''/**
 * @module
 * Rate Limiter Middleware for Hono.
 */

import type { Context } from '../../context'
import { HTTPException } from '../../http-exception'
import type { MiddlewareHandler } from '../../types'

export type RateLimiterOptions = {
  /** Requests allowed per window. */
  limit: number
  /** The window's length in milliseconds. Default: 60_000. */
  windowMs?: number
  /** Who a request counts against. Default: the client's IP address. */
  keyGenerator?: (c: Context) => string | Promise<string>
}

/** Hits per client, in a window that starts at the client's first hit. */
class FixedWindowCounter {
  #windows = new Map<string, { count: number; resetAt: number }>()

  hit(key: string, now: number, windowMs: number) {
    let window = this.#windows.get(key)
    if (!window || window.resetAt <= now) {
      window = { count: 0, resetAt: now + windowMs }
      this.#windows.set(key, window)
    }
    window.count++
    return window
  }
}

/**
 * Rate Limiter Middleware for Hono: a fixed window per client.
 *
 * @example
 * ```ts
 * const app = new Hono()
 *
 * app.use('/api/*', rateLimiter({ limit: 100, windowMs: 60_000 }))
 * ```
 */
export const rateLimiter = (options: RateLimiterOptions): MiddlewareHandler => {
  const windowMs = options.windowMs ?? 60_000
  const keyGenerator = options.keyGenerator ?? clientAddress
  const counter = new FixedWindowCounter()

  return async function rateLimiter(c, next) {
    const now = Date.now()
    const key = await keyGenerator(c)
    const { count, resetAt } = counter.hit(key, now, windowMs)
    const remaining = Math.max(0, options.limit - count)
    const reset = Math.ceil((resetAt - now) / 1000)

    c.header('X-RateLimit-Limit', String(options.limit))
    c.header('X-RateLimit-Remaining', String(remaining))
    c.header('X-RateLimit-Reset', String(reset))
    if (count > options.limit) {
      c.header('Retry-After', String(reset))
      throw new HTTPException(429, { message: 'Too Many Requests' })
    }
    await next()
  }
}

const clientAddress = (c: Context): string =>
  c.req.header('cf-connecting-ip') ??
  c.req.header('x-forwarded-for')?.split(',')[0].trim() ??
  'anonymous'
''';

/// The agent's edits of the middleware: the stores and the options for
/// them, then the counting and the headers.
const rateLimiterEdits = [
  (
    r'''export type RateLimiterOptions = {
  /** Requests allowed per window. */
  limit: number
  /** The window's length in milliseconds. Default: 60_000. */
  windowMs?: number
  /** Who a request counts against. Default: the client's IP address. */
  keyGenerator?: (c: Context) => string | Promise<string>
}

/** Hits per client, in a window that starts at the client's first hit. */
class FixedWindowCounter {
  #windows = new Map<string, { count: number; resetAt: number }>()

  hit(key: string, now: number, windowMs: number) {
    let window = this.#windows.get(key)
    if (!window || window.resetAt <= now) {
      window = { count: 0, resetAt: now + windowMs }
      this.#windows.set(key, window)
    }
    window.count++
    return window
  }
}

/**
 * Rate Limiter Middleware for Hono: a fixed window per client.''',
    r'''export interface RateLimitStore {
  /**
   * Counts a hit for `key` in the window starting at `windowStart`, and
   * returns the hits in it and in the window before.
   */
  increment(
    key: string,
    windowStart: number,
    windowMs: number
  ): Promise<{ current: number; previous: number }>
}

export type RateLimiterOptions = {
  /** Requests allowed per window. */
  limit: number
  /** The window's length in milliseconds. Default: 60_000. */
  windowMs?: number
  /** Who a request counts against. Default: the client's IP address. */
  keyGenerator?: (c: Context) => string | Promise<string>
  /** Where the counts are kept. Default: in memory. */
  store?: RateLimitStore
  /** Sends the IETF `RateLimit` and `RateLimit-Policy` headers. Default: true. */
  standardHeaders?: boolean
}

/** Counts kept in memory: for a single process, and for tests. */
export class MemoryStore implements RateLimitStore {
  #counts = new Map<string, number>()

  async increment(key: string, windowStart: number, windowMs: number) {
    const id = `${key}:${windowStart}`
    const current = (this.#counts.get(id) ?? 0) + 1
    this.#counts.set(id, current)
    this.#counts.delete(`${key}:${windowStart - 2 * windowMs}`)
    const previous = this.#counts.get(`${key}:${windowStart - windowMs}`) ?? 0
    return { current, previous }
  }
}

/**
 * Counts kept in Workers KV. KV is eventually consistent: at the edges of
 * a window, a few requests over the limit may pass.
 */
export class KVStore implements RateLimitStore {
  constructor(
    private kv: KVNamespace,
    private prefix = 'rl:'
  ) {}

  async increment(key: string, windowStart: number, windowMs: number) {
    const id = `${this.prefix}${key}:${windowStart}`
    const [current, previous] = await Promise.all([
      this.kv.get(id).then((n) => (Number(n) || 0) + 1),
      this.kv.get(`${this.prefix}${key}:${windowStart - windowMs}`).then((n) => Number(n) || 0),
    ])
    await this.kv.put(id, String(current), {
      expirationTtl: Math.max(60, Math.ceil((2 * windowMs) / 1000)),
    })
    return { current, previous }
  }
}

/**
 * Rate Limiter Middleware for Hono: a sliding-window counter, as
 * Cloudflare's own rate limiting counts.''',
  ),
  (
    r'''  const keyGenerator = options.keyGenerator ?? clientAddress
  const counter = new FixedWindowCounter()

  return async function rateLimiter(c, next) {
    const now = Date.now()
    const key = await keyGenerator(c)
    const { count, resetAt } = counter.hit(key, now, windowMs)
    const remaining = Math.max(0, options.limit - count)
    const reset = Math.ceil((resetAt - now) / 1000)

    c.header('X-RateLimit-Limit', String(options.limit))
    c.header('X-RateLimit-Remaining', String(remaining))
    c.header('X-RateLimit-Reset', String(reset))
    if (count > options.limit) {''',
    r'''  const store = options.store ?? new MemoryStore()
  const keyGenerator = options.keyGenerator ?? clientAddress
  const standardHeaders = options.standardHeaders ?? true

  return async function rateLimiter(c, next) {
    const now = Date.now()
    const windowStart = now - (now % windowMs)
    const key = await keyGenerator(c)
    const { current, previous } = await store.increment(key, windowStart, windowMs)

    // The last window's hits, weighted by how much of it is still in view.
    const weight = 1 - (now - windowStart) / windowMs
    const hits = Math.floor(previous * weight) + current
    const remaining = Math.max(0, options.limit - hits)
    const reset = Math.ceil((windowStart + windowMs - now) / 1000)

    if (standardHeaders) {
      c.header('RateLimit-Policy', `${options.limit};w=${windowMs / 1000}`)
      c.header('RateLimit', `limit=${options.limit}, remaining=${remaining}, reset=${reset}`)
    }
    if (hits > options.limit) {''',
  ),
];

/// The middleware as the agent leaves it.
final rateLimiterSource = _edited(rateLimiterFixedSource, rateLimiterEdits);

/// Its tests as committed.
const rateLimiterFixedTestSource = r'''import { Hono } from '../../hono'
import { rateLimiter } from '.'

describe('Rate Limiter Middleware', () => {
  let app: Hono

  beforeEach(() => {
    vi.useFakeTimers({ now: 0 })
    app = new Hono()
    app.use('/api/*', rateLimiter({ limit: 3, windowMs: 1000 }))
    app.get('/api/hello', (c) => c.text('hello'))
  })

  afterEach(() => {
    vi.useRealTimers()
  })

  it('lets requests under the limit through', async () => {
    const res = await app.request('/api/hello')
    expect(res.status).toBe(200)
    expect(res.headers.get('X-RateLimit-Remaining')).toBe('2')
  })

  it('answers 429 past the limit, with Retry-After', async () => {
    for (let i = 0; i < 3; i++) {
      await app.request('/api/hello')
    }
    const res = await app.request('/api/hello')
    expect(res.status).toBe(429)
    expect(res.headers.get('Retry-After')).toBe('1')
  })

  it('starts counting again in the next window', async () => {
    for (let i = 0; i < 3; i++) {
      await app.request('/api/hello')
    }
    vi.setSystemTime(1000)
    const res = await app.request('/api/hello')
    expect(res.status).toBe(200)
    expect(res.headers.get('X-RateLimit-Remaining')).toBe('2')
  })

  it('counts each client on its own', async () => {
    const from = (ip: string) =>
      app.request('/api/hello', { headers: { 'cf-connecting-ip': ip } })
    for (let i = 0; i < 3; i++) {
      await from('203.0.113.7')
    }
    expect((await from('203.0.113.7')).status).toBe(429)
    expect((await from('198.51.100.4')).status).toBe(200)
  })
})
''';

/// The agent's edits of the tests: the new headers, and the window's
/// edge, where a fixed window lets a burst through, weighted instead.
const rateLimiterTestEdits = [
  (
    r'''  it('lets requests under the limit through', async () => {
    const res = await app.request('/api/hello')
    expect(res.status).toBe(200)
    expect(res.headers.get('X-RateLimit-Remaining')).toBe('2')''',
    r'''  it('lets requests under the limit through', async () => {
    const res = await app.request('/api/hello')
    expect(res.status).toBe(200)
    expect(res.headers.get('RateLimit')).toBe('limit=3, remaining=2, reset=1')
    expect(res.headers.get('RateLimit-Policy')).toBe('3;w=1')''',
  ),
  (
    r'''  it('starts counting again in the next window', async () => {
    for (let i = 0; i < 3; i++) {
      await app.request('/api/hello')
    }
    vi.setSystemTime(1000)
    const res = await app.request('/api/hello')
    expect(res.status).toBe(200)
    expect(res.headers.get('X-RateLimit-Remaining')).toBe('2')''',
    r'''  it('weights the previous window by how much of it is left', async () => {
    for (let i = 0; i < 3; i++) {
      await app.request('/api/hello')
    }
    vi.setSystemTime(1500)
    // Half of the last window's 3 hits still count: 1 + 1 = 2.
    const res = await app.request('/api/hello')
    expect(res.status).toBe(200)
    expect(res.headers.get('RateLimit')).toBe('limit=3, remaining=1, reset=1')''',
  ),
];

/// The tests as the agent leaves them.
final rateLimiterTestSource = _edited(
  rateLimiterFixedTestSource,
  rateLimiterTestEdits,
);

/// The line of [source] that [text] starts on, from 1.
int lineOf(String source, String text) {
  final at = source.indexOf(text);
  if (at < 0) throw StateError('not in the source: $text');
  return '\n'.allMatches(source.substring(0, at)).length + 1;
}

String _edited(String source, List<(String, String)> edits) {
  for (final (before, after) in edits) {
    if (!source.contains(before)) throw StateError('no edit: $before');
    source = source.replaceFirst(before, after);
  }
  return source;
}

/// The export of the rate limiter in package.json, after timeout's, as
/// committed.
const packageJsonBefore = r'''    "./timeout": {
      "types": "./dist/types/middleware/timeout/index.d.ts",
      "import": "./dist/middleware/timeout/index.js",
      "require": "./dist/cjs/middleware/timeout/index.js"
    },''';

const packageJsonAfter = r'''    "./timeout": {
      "types": "./dist/types/middleware/timeout/index.d.ts",
      "import": "./dist/middleware/timeout/index.js",
      "require": "./dist/cjs/middleware/timeout/index.js"
    },
    "./rate-limiter": {
      "types": "./dist/types/middleware/rate-limiter/index.d.ts",
      "import": "./dist/middleware/rate-limiter/index.js",
      "require": "./dist/cjs/middleware/rate-limiter/index.js"
    },''';

const jsrJsonBefore =
    '''    "./timeout": "./src/middleware/timeout/index.ts",''';
const jsrJsonAfter = '''    "./timeout": "./src/middleware/timeout/index.ts",
    "./rate-limiter": "./src/middleware/rate-limiter/index.ts",''';
