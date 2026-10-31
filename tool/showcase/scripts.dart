// What the showcase's agents do, message by message: the scripts
// [ShowTransport] plays. Their holds are where the scenes take pictures.

import 'dart:io';

import 'code.dart';
import 'show_transport.dart';
import 'story.dart';

String t(String en, String zh) => Story.t(en, zh);

/// The rate limiter, hono's fixed window (code.dart) to change, asked for.
String get rateLimitPrompt => t(
  'Move the `rateLimiter` middleware from a fixed window to a sliding-window counter: pluggable stores (in memory and Workers KV), the standard `RateLimit` headers instead of `X-RateLimit-*`, its tests with it. Research it in parallel with subagents first.',
  '把 `rateLimiter` 中间件从固定窗口改成滑动窗口计数：存储可替换（内存和 Workers KV），响应头从 `X-RateLimit-*` 换成标准的 `RateLimit`，测试一起改。先用子代理并行调研。',
);

String get rateLimitTitle => t('Rate limiter: a sliding window', '限流改成滑动窗口');

/// Why JSX streams slower on Bun, asked in hono.
String get jsxPrompt => t(
  'Why does streaming JSX with `renderToReadableStream` finish later on Bun than on Node? Look at src/jsx/streaming.ts.',
  '为什么用 `renderToReadableStream` 流式渲染 JSX，在 Bun 上比 Node 更晚结束？看一下 src/jsx/streaming.ts。',
);

String get jsxTitle => t('JSX streaming is slower on Bun', 'JSX 流式渲染在 Bun 上更慢');

/// The rate-limit algorithms compared, asked in hono: an answer in a
/// table, a formula, a diagram and code.
String get markdownPrompt => t(
  'Compare the rate-limiting algorithms we could use for `rateLimiter`. Which one, and why?',
  '对比一下 `rateLimiter` 可以用的几种限流算法，选哪个，为什么？',
);

/// The algorithms compared: no tools, just the answer, written out.
Future<void> markdownScript(ShowRun run) async {
  await run.think(
    t(
      'Four candidates: fixed window, sliding log, sliding-window counter, token bucket. Compare memory per key, accuracy at the window edge, and how well each fits a KV store.',
      '四个候选：固定窗口、滑动日志、滑动窗口计数、令牌桶。比较每个 key 的内存、窗口边界的准确度，以及放进 KV 存储合不合适。',
    ),
  );
  await run.say(
    t(
      '''Four algorithms fit a middleware like this one:

| Algorithm | Memory per key | At the window edge | Fits Workers KV |
|---|---|---|---|
| Fixed window | 1 counter | up to **2×** the limit | yes |
| Sliding log | 1 timestamp per request | exact | no, too many writes |
| Sliding-window counter | 2 counters | within ~1% | **yes** |
| Token bucket | tokens + last refill | smooth | needs atomic updates |

The sliding-window counter weights the previous window by how much of it still overlaps:

\$\$
\\text{count} = c_{\\text{prev}} \\cdot \\frac{w - t}{w} + c_{\\text{cur}}
\$\$

where \$w\$ is the window and \$t\$ the time into the current one.

```mermaid
flowchart LR
  A[Request] --> B{key}
  B --> C[(Store)]
  C --> D["count = prev × (w − t)/w + cur"]
  D -->|≤ limit| E[next]
  D -->|> limit| F[429 + RateLimit]
```

It is two numbers per key, so the store stays small:

```ts
export interface RateLimitStore {
  increment(key: string, window: number): Promise<{ previous: number; current: number }>
}
```

**I’d go with the sliding-window counter**: nearly exact, constant memory, and the same code works in memory and on Workers KV.''',
      '''这类中间件可以用四种算法：

| 算法 | 每个 key 的内存 | 窗口边界 | 适合 Workers KV |
|---|---|---|---|
| 固定窗口 | 1 个计数器 | 最多 **2 倍**限额 | 适合 |
| 滑动日志 | 每个请求一个时间戳 | 精确 | 不适合，写入太多 |
| 滑动窗口计数 | 2 个计数器 | 误差约 1% | **适合** |
| 令牌桶 | 令牌数 + 上次补充时间 | 平滑 | 需要原子更新 |

滑动窗口计数按上一个窗口还重叠的比例给它加权：

\$\$
\\text{count} = c_{\\text{prev}} \\cdot \\frac{w - t}{w} + c_{\\text{cur}}
\$\$

其中 \$w\$ 是窗口长度，\$t\$ 是进入当前窗口的时间。

```mermaid
flowchart LR
  A[请求] --> B{key}
  B --> C[(存储)]
  C --> D["count = prev × (w − t)/w + cur"]
  D -->|≤ 限额| E[放行]
  D -->|> 限额| F[429 + RateLimit]
```

每个 key 只要两个数字，存储接口可以很小：

```ts
export interface RateLimitStore {
  increment(key: string, window: number): Promise<{ previous: number; current: number }>
}
```

**建议用滑动窗口计数**：几乎精确、内存恒定，同一套代码在内存里和 Workers KV 上都能跑。''',
    ),
    charsPerSecond: Story.zh ? 80 : 160,
  );
}

/// The rate limiter: three subagents research it while the type-checker
/// runs in the background (the hold `agents`); then it and its tests are
/// edited (the hold `written`) and tested.
Future<void> rateLimitScript(ShowRun run, String root) async {
  String at(String path) => '$root/$path';
  await run.think(
    t(
      'rateLimiter keeps a Map of fixed windows per client: across a window’s edge a client gets twice the limit, and the Map is the only store. '
          'A sliding log costs memory per request; a sliding-window counter (what Cloudflare uses) is two counters per key, so a store interface stays small. '
          'Workers KV is eventually consistent, worth a note. Three independent questions: fan out.',
      'rateLimiter 现在按客户端存一个 Map 做固定窗口：跨过窗口边界时，一个客户端能发出两倍的请求，而且只能存在内存里。'
          '滑动日志每个请求都占内存；滑动窗口计数（Cloudflare 用的）每个 key 只要两个计数器，存储接口可以很小。'
          'Workers KV 是最终一致的，要说明一下。三个问题互不相关，可以并行。',
    ),
  );
  await run.say(
    t(
      'I’ll split this three ways: one agent surveys how Hono’s middleware are written, one compares sliding-window algorithms and the IETF `RateLimit` header draft, and one works out which tests change. The type-checker keeps running in the background meanwhile.',
      '我分三路进行：一个子代理梳理 Hono 中间件的写法，一个对比滑动窗口算法和 IETF 的 `RateLimit` 响应头草案，一个整理哪些测试要改。同时在后台持续跑类型检查。',
    ),
  );
  final survey = run.agent(
    t('Survey middleware conventions', '梳理中间件的写法'),
    t(
      'Read src/middleware/rate-limiter, timeout and cors. Report how options, errors and response headers are done.',
      '读 src/middleware/rate-limiter、timeout 和 cors，总结选项、错误和响应头各是怎么做的。',
    ),
    type: 'Explore',
    model: 'claude-haiku-5-5',
    background: true,
  );
  final research = run.agent(
    t('Compare sliding-window algorithms', '对比滑动窗口算法'),
    t(
      'Compare fixed window, sliding log and sliding-window counter for an edge runtime; summarize the IETF RateLimit header draft.',
      '在边缘运行时的前提下，对比固定窗口、滑动日志和滑动窗口计数；总结 IETF RateLimit 响应头草案。',
    ),
    background: true,
  );
  final tests = run.agent(
    t('Work out the test changes', '整理要改的测试'),
    t(
      'Read the rate limiter’s tests and how Hono’s middleware tests use fake timers; list which cases change for a sliding window.',
      '读限流中间件的测试，看看 Hono 的中间件测试怎么用假定时器，列出改成滑动窗口后哪些用例要改。',
    ),
    background: true,
  );
  final tsc = await run.background(
    'bunx tsc --noEmit --watch -p tsconfig.build.json',
    t('Type-check in watch mode', '持续类型检查'),
  );
  await Future.wait([
    () async {
      await survey.tool(
        'Read',
        {'file_path': at(rateLimiterPath)},
        activity: t(
          'Reading rate-limiter/index.ts',
          '读取 rate-limiter/index.ts',
        ),
        took: 700,
      );
      await survey.tool(
        'Read',
        {'file_path': at('src/middleware/cors/index.ts')},
        activity: t('Reading cors/index.ts', '读取 cors/index.ts'),
        took: 800,
      );
      await survey.tool(
        'Grep',
        {
          'pattern': 'throw new HTTPException',
          'path': 'src/middleware',
          'output_mode': 'files_with_matches',
        },
        result: [
          'Found 6 files',
          for (final name in [
            'basic-auth',
            'bearer-auth',
            'body-limit',
            'csrf',
            'ip-restriction',
            'jwt',
          ])
            at('src/middleware/$name/index.ts'),
        ].join('\n'),
        activity: t('Searching for HTTPException', '搜索 HTTPException'),
        took: 900,
      );
    }(),
    () async {
      await research.tool(
        'WebSearch',
        {'query': 'sliding window counter rate limiting edge'},
        activity: t('Searching the web', '网页搜索'),
        took: 1200,
      );
      await research.tool(
        'WebFetch',
        {
          'url': 'https://datatracker.ietf.org/doc/draft-ietf-httpapi-ratelimit-headers/',
        },
        activity: t(
          'Reading the RateLimit headers draft',
          '阅读 RateLimit 响应头草案',
        ),
        took: 1400,
      );
    }(),
    () async {
      await tests.tool(
        'Grep',
        {'pattern': 'useFakeTimers', 'path': 'src/middleware'},
        activity: t('Searching for fake timers', '搜索假定时器用法'),
        took: 800,
      );
      await tests.tool(
        'Read',
        {'file_path': at(rateLimiterTestPath)},
        activity: t(
          'Reading rate-limiter/index.test.ts',
          '读取 rate-limiter/index.test.ts',
        ),
        took: 900,
      );
    }(),
  ]);
  await run.hold('agents');

  survey.done(
    t(
      'Options are a typed object with defaults; errors are `HTTPException`s; headers go through `c.header()`. rateLimiter’s counts live in a `Map` inside the closure, so there’s no seam for another store.',
      '选项是带默认值的类型化对象；错误抛 `HTTPException`；响应头用 `c.header()` 设置。rateLimiter 的计数存在闭包里的 `Map` 中，没有地方接入别的存储。',
    ),
    durationMs: 9400,
  );
  await run.pause(500);
  tests.done(
    t(
      'Two of the four change: the first asserts `X-RateLimit-Remaining`, now `RateLimit`; “starts counting again in the next window” becomes the previous window weighted. 429 + Retry-After and per-client keys stay.',
      '四个用例里改两个：第一个断言的 `X-RateLimit-Remaining` 换成 `RateLimit`；“下一个窗口重新计数”改成上一窗口加权。429 + Retry-After 和按客户端区分保持不变。',
    ),
    durationMs: 11200,
  );
  await run.pause(600);
  research.done(
    t(
      'Sliding-window counter: two counters per key, error under 1% (Cloudflare’s measurements). Headers: `RateLimit: limit=…, remaining=…, reset=…` and `RateLimit-Policy: 100;w=60`.',
      '滑动窗口计数：每个 key 两个计数器，误差小于 1%（Cloudflare 的测量）。响应头：`RateLimit: limit=…, remaining=…, reset=…` 和 `RateLimit-Policy: 100;w=60`。',
    ),
    durationMs: 14800,
  );
  await run.pause(400);
  await run.say(
    t(
      'All three are back. Adding the store interface with the memory and KV stores, then switching the counting and the headers, then the tests.',
      '三个子代理都回来了。先加存储接口和内存、KV 两种存储，再改计数和响应头，最后改测试。',
    ),
  );
  Future<void> edits(
    String path,
    String source,
    List<(String, String)> edits,
  ) async {
    for (final (before, after) in edits) {
      await run.edit(
        at(path),
        before,
        after,
        start: lineOf(source, before),
        took: 500,
      );
      source = source.replaceFirst(before, after);
    }
  }

  await edits(rateLimiterPath, rateLimiterFixedSource, rateLimiterEdits);
  await edits(
    rateLimiterTestPath,
    rateLimiterFixedTestSource,
    rateLimiterTestEdits,
  );
  await run.hold('written');
  await run.tool(
    'Bash',
    {
      'command': 'bun test src/middleware/rate-limiter',
      'description': t('Run the rate limiter tests', '运行限流中间件的测试'),
    },
    result: bunTestOutput,
    structured: {'stdout': bunTestOutput, 'stderr': '', 'interrupted': false},
    took: 1400,
  );
  tsc.done(t('Found 0 errors. Watching for file changes.', '0 个错误，继续监听。'));
  await run.say(
    t(
      '''Done. `rateLimiter` now counts in a sliding window:

| File | What changed |
|---|---|
| `index.ts` | the `Map` of fixed windows is now a `RateLimitStore`: `MemoryStore` by default, `KVStore` for Workers KV (eventually consistent, noted in the doc); the last window’s hits weighted |
| `index.test.ts` | the new headers asserted; the next-window case now checks the weighting. 4 tests, all passing |

`X-RateLimit-*` gave way to `RateLimit` and `RateLimit-Policy`, `standardHeaders: false` turns them off; `Retry-After` still comes with the 429.''',
      '''完成了。`rateLimiter` 现在按滑动窗口计数：

| 文件 | 改了什么 |
|---|---|
| `index.ts` | 固定窗口的 `Map` 换成了 `RateLimitStore`：默认 `MemoryStore`，Workers KV 用 `KVStore`（最终一致，文档里有说明）；上一窗口的请求按比例加权 |
| `index.test.ts` | 断言改成新响应头；“下一窗口”的用例改成检查加权。4 个测试全部通过 |

`X-RateLimit-*` 换成了 `RateLimit` 和 `RateLimit-Policy`，可以用 `standardHeaders: false` 关掉；429 时照旧带 `Retry-After`。''',
    ),
    charsPerSecond: 420,
  );
}

const bunTestOutput = '''bun test v1.2.22

src/middleware/rate-limiter/index.test.ts:
✓ Rate Limiter Middleware > lets requests under the limit through [0.41ms]
✓ Rate Limiter Middleware > answers 429 past the limit, with Retry-After [0.22ms]
✓ Rate Limiter Middleware > weights the previous window by how much of it is left [0.19ms]
✓ Rate Limiter Middleware > counts each client on its own [0.31ms]

 4 pass
 0 fail
 9 expect() calls
Ran 4 tests across 1 file. [38.00ms]''';

/// JSX streaming on Bun: read, searched, answered at length (the hold
/// `answer` about two thirds in).
Future<void> jsxScript(ShowRun run, String root) async {
  await run.think(
    t(
      'renderToReadableStream enqueues the shell, then one chunk per resolved Suspense boundary, each with its replacement script. If Bun flushes every enqueue as its own write, many small chunks cost more than on Node, which coalesces them.',
      'renderToReadableStream 先推送外壳，然后每个 Suspense 边界解析完各推一块，带着替换脚本。如果 Bun 每次 enqueue 都单独写出，很多小块的开销就会比会合并写入的 Node 大。',
    ),
  );
  final source = File('$root/src/jsx/streaming.ts').readAsStringSync();
  await run.read('$root/src/jsx/streaming.ts', source, took: 400);
  await run.tool(
    'Grep',
    {
      'pattern': 'controller.enqueue',
      'path': 'src/jsx',
      'output_mode': 'content',
    },
    result:
        'src/jsx/streaming.ts:177:          controller.enqueue(textEncoder.encode(resolved))\n'
        'src/jsx/streaming.ts:204:                  controller.enqueue(textEncoder.encode(res))',
    took: 300,
  );
  final answer = t(
    '''Short version: every resolved `Suspense` boundary is a separate `controller.enqueue()` (`streaming.ts:204`), and Bun writes each one to the socket as it comes, where Node’s stream coalesces small writes. Many boundaries means many tiny writes.

### Where the time goes

Rendering the 200-row demo page locally:

| | Node 22 | Bun 1.2 |
|---|---|---|
| First byte | 3.1 ms | 2.4 ms |
| Chunks written | 14 | 212 |
| Last byte | 18 ms | 41 ms |

Bun is faster to the first byte, but each boundary’s HTML and its replacement `<script>` are encoded and written on their own.

### A fix

Buffer what resolves in the same microtask and enqueue it once:

```ts
let pending = ''
const flush = () => {
  controller.enqueue(textEncoder.encode(pending))
  pending = ''
}
const write = (html: string) => {
  if (!pending) queueMicrotask(flush)
  pending += html
}
```

With this, Bun writes 15 chunks and finishes at 17 ms; Node is unchanged. Want me to make the change and add a test that counts chunks?''',
    '''简单说：每个 `Suspense` 边界解析完都会单独 `controller.enqueue()` 一次（`streaming.ts:204`），Bun 每来一块就写一次 socket，而 Node 的流会把小块合并再写。边界一多，就是大量很小的写入。

### 时间花在哪

本地渲染 200 行的示例页面：

| | Node 22 | Bun 1.2 |
|---|---|---|
| 首字节 | 3.1 ms | 2.4 ms |
| 写出的块数 | 14 | 212 |
| 末字节 | 18 ms | 41 ms |

Bun 的首字节更快，但每个边界的 HTML 和它的替换 `<script>` 都是单独编码、单独写出的。

### 修法

把同一个微任务里解析完的内容先攒起来，一次性推送：

```ts
let pending = ''
const flush = () => {
  controller.enqueue(textEncoder.encode(pending))
  pending = ''
}
const write = (html: string) => {
  if (!pending) queueMicrotask(flush)
  pending += html
}
```

这样 Bun 只写 15 块，17 ms 就结束了；Node 不受影响。要我直接改，并加一个统计块数的测试吗？''',
  );
  await run.say(
    answer,
    charsPerSecond: 320,
    holdAt: ('answer', (answer.length * 0.62).round()),
  );
}

/// Toward the goal: the tests on each runtime, one failing on Deno, its
/// fix, and the runs again (the hold `goal` as they run).
Future<void> goalScript(ShowRun run, String root) async {
  await run.think(
    t(
      'The goal is all middleware tests green on three runtimes plus a clean type-check. Run each runtime’s suite, fix what fails, repeat until all pass.',
      '目标是三个运行时上的中间件测试全部通过，并且类型检查干净。逐个运行时跑测试，修掉失败的，重复直到全部通过。',
    ),
  );
  await run.say(
    t('Starting with a baseline on each runtime.', '先在每个运行时上跑一遍基线。'),
  );
  final bun = await run.background(
    'bun test src/middleware',
    t('Middleware tests on Bun', 'Bun 上的中间件测试'),
  );
  final node = await run.background(
    'npx vitest run --project node src/middleware',
    t('Middleware tests on Node', 'Node 上的中间件测试'),
  );
  final deno = await run.background(
    'deno test -A src/middleware',
    t('Middleware tests on Deno', 'Deno 上的中间件测试'),
  );
  await run.pause(1500);
  bun.done('412 pass, 0 fail');
  node.done('412 passed (412)');
  deno.done(
    'FAILED | 409 passed | 3 failed\n  compress: CompressionStream not defined for "deflate-raw"',
    failed: true,
  );
  await run.say(
    t(
      'Bun and Node are green. Deno fails 3 tests in `compress`: its `CompressionStream` doesn’t support `deflate-raw`. The middleware should fall back to `deflate` there.',
      'Bun 和 Node 都通过了。Deno 上 `compress` 有 3 个测试失败：它的 `CompressionStream` 不支持 `deflate-raw`。这种情况下中间件应该退回到 `deflate`。',
    ),
  );
  await run.read(
    '$root/src/middleware/compress/index.ts',
    File('$root/src/middleware/compress/index.ts').readAsStringSync(),
  );
  await run.tool(
    'Grep',
    {'pattern': 'deflate-raw', 'path': 'src', 'output_mode': 'content'},
    result: 'src/middleware/compress/index.ts:8:const ENCODING_TYPES = [\'gzip\', \'deflate\'] as const',
  );
  await run.say(
    t(
      'Adding a capability check and running Deno again, with the type-check alongside.',
      '加上能力检测，再跑一次 Deno，同时做类型检查。',
    ),
  );
  await run.background(
    'deno test -A src/middleware',
    t('Middleware tests on Deno', 'Deno 上的中间件测试'),
  );
  await run.background(
    'bunx tsc --noEmit -p tsconfig.build.json',
    t('Type-check', '类型检查'),
  );
  await run.hold('goal');
}
