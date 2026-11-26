// What the welcome demo's agent does (export_test.dart records it): the
// showcase's rate limiter (tool/showcase/code.dart), told in plain words,
// with what the app draws best: the web searched, a table, a formula, a
// diagram and code; subagents at work beside a background task, each
// step of theirs under its card; edits, and the tests run.

import 'dart:convert';

import '../showcase/code.dart';
import '../showcase/show_transport.dart';
import '../showcase/story.dart';

String t(String en, String zh) => Story.t(en, zh);

String get comparePrompt => t(
  'Compare the algorithms we could use for our rate-limiting middleware. Which one, and why?',
  '对比一下限流中间件可以用的几种算法，选哪个，为什么？',
);

String get rewritePrompt => t(
  'Go with the sliding-window counter. Make the store swappable (in memory and Workers KV), switch to the standard RateLimit headers, and update the tests. Research it with a few subagents in parallel first.',
  '就按滑动窗口计数改吧：存储做成可替换的（内存和 Workers KV 两种），响应头换成 IETF 标准的 RateLimit，测试一起改。先派几个子代理并行调研。',
);

/// What WebSearch answers: its links, then what they say.
String _searchResult(String query, List<(String, String)> links, String text) =>
    'Web search results for query: "$query"\n\n'
    'Links: ${jsonEncode([
      for (final (title, url) in links) {'title': title, 'url': url},
    ])}\n\n$text';

/// The algorithms compared: looked up, then the answer, written out.
Future<void> compareScript(ShowRun run) async {
  await run.think(
    t(
      'Four candidates: fixed window, sliding log, sliding-window counter, token bucket. Worth checking what Cloudflare measured for the sliding-window counter before recommending it.',
      '四个候选：固定窗口、滑动日志、滑动窗口计数、令牌桶。推荐滑动窗口计数之前，先查一下 Cloudflare 实测的误差。',
    ),
  );
  await run.tool(
    'WebSearch',
    {'query': 'sliding window counter rate limiting accuracy'},
    result: _searchResult(
      'sliding window counter rate limiting accuracy',
      [
        (
          'How we built rate limiting capable of scaling to millions of domains',
          'https://blog.cloudflare.com/counting-things-a-lot-of-different-things/',
        ),
        ('Rate limiting', 'https://en.wikipedia.org/wiki/Rate_limiting'),
        (
          'Rate limiting algorithms explained',
          'https://redis.io/glossary/rate-limiting/',
        ),
        (
          'RateLimit header fields for HTTP',
          'https://datatracker.ietf.org/doc/draft-ietf-httpapi-ratelimit-headers/',
        ),
      ],
      'Cloudflare reports the sliding-window approximation was wrong for 0.003% of requests across 400 million, with an average difference of 6% from the real rate.',
    ),
    took: 1300,
  );
  await run.tool(
    'WebFetch',
    {
      'url': 'https://blog.cloudflare.com/counting-things-a-lot-of-different-things/',
      'prompt': 'How accurate is the sliding window counter?',
    },
    result: 'Two counters per key: the previous window weighted by how much of it still overlaps, plus the current one. 0.003% of requests were wrongly allowed or limited.',
    took: 1500,
  );
  await run.say(
    t(
      '''Four algorithms fit a middleware like this one:

| Algorithm | Memory per key | At the window edge | Fits Workers KV |
|---|---|---|---|
| Fixed window | 1 counter | up to **2×** the limit | yes |
| Sliding log | 1 timestamp per request | exact | no, too many writes |
| Sliding-window counter | 2 counters | 0.003% off (Cloudflare) | **yes** |
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
| 滑动窗口计数 | 2 个计数器 | 误差 0.003%（Cloudflare 实测） | **适合** |
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
    charsPerSecond: Story.zh ? 55 : 120,
  );
}

/// The rewrite: three subagents research it while the type-checker runs
/// in the background; then the middleware and its tests are edited, and
/// tested.
Future<void> rewriteScript(ShowRun run, String root) async {
  String at(String path) => '$root/$path';
  await run.think(
    t(
      'The middleware keeps a map of fixed windows per client, and memory is its only store. Three independent questions: how middleware here are written, what the header draft says, which tests change. Fan out.',
      '现在的中间件按客户端存固定窗口，而且只能存在内存里。三个问题互不相关：这里的中间件怎么写、响应头草案怎么规定、哪些测试要改。可以并行。',
    ),
  );
  await run.say(
    t(
      'I’ll split this three ways: one subagent reads how the other middleware are written, one looks up the RateLimit header draft, and one works out which tests change. The type-checker keeps running in the background meanwhile.',
      '我分三路进行：一个子代理看看其他中间件是怎么写的，一个去查 RateLimit 响应头草案，一个整理哪些测试要改。同时在后台持续跑类型检查。',
    ),
  );
  final survey = run.agent(
    t('Survey middleware conventions', '梳理中间件的写法'),
    t(
      'Read the rate limiter, timeout and cors middleware. Report how options, errors and response headers are done.',
      '读限流、timeout 和 cors 这几个中间件，总结选项、错误和响应头各是怎么做的。',
    ),
    type: 'Explore',
    model: 'claude-haiku-5-5',
    background: true,
  );
  final research = run.agent(
    t('Look up the RateLimit headers', '查 RateLimit 响应头'),
    t(
      'Summarize the IETF RateLimit header draft: the fields, their syntax, and what to send with a 429.',
      '总结 IETF 的 RateLimit 响应头草案：有哪些字段、怎么写、429 时要带什么。',
    ),
    background: true,
  );
  final tests = run.agent(
    t('Work out the test changes', '整理要改的测试'),
    t(
      'Read the rate limiter’s tests and how the other middleware tests fake time; list which cases change for a sliding window.',
      '读限流中间件的测试，看看其他中间件的测试怎么模拟时间，列出改成滑动窗口后哪些用例要改。',
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
      await survey.say(
        t(
          'All of them take a typed options object with defaults and throw an HTTPException on errors.',
          '这些中间件都用带默认值的选项对象，出错时抛 HTTPException。',
        ),
      );
    }(),
    () async {
      await research.tool(
        'WebSearch',
        {'query': 'IETF RateLimit header fields draft'},
        result: _searchResult(
          'IETF RateLimit header fields draft',
          [
            (
              'RateLimit header fields for HTTP',
              'https://datatracker.ietf.org/doc/draft-ietf-httpapi-ratelimit-headers/',
            ),
            (
              'RateLimit headers on GitHub',
              'https://github.com/ietf-wg-httpapi/ratelimit-headers',
            ),
            (
              'Retry-After - HTTP | MDN',
              'https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Retry-After',
            ),
          ],
          'The draft defines RateLimit-Policy for the quota and RateLimit for what is left of it.',
        ),
        activity: t('Searching the web', '网页搜索'),
        took: 1200,
      );
      await research.tool(
        'WebFetch',
        {
          'url': 'https://datatracker.ietf.org/doc/draft-ietf-httpapi-ratelimit-headers/',
        },
        result: 'RateLimit-Policy: "default";q=100;w=60 and RateLimit: "default";r=42;t=18. A 429 should come with Retry-After.',
        activity: t(
          'Reading the RateLimit headers draft',
          '阅读 RateLimit 响应头草案',
        ),
        took: 1400,
      );
      // A question for the agent, and its answer: the two talking.
      final ask = t(
        'The draft has two syntaxes: the older limit, remaining and reset, and the current structured fields. Which one should I write up?',
        '草案有两种写法：旧的 limit、remaining、reset，和现在的结构化字段。按哪种整理？',
      );
      await research.tool(
        'SendMessage',
        {'to': 'main', 'summary': t('Which syntax?', '按哪种写法？'), 'message': ask},
        result: 'Message sent to main',
        activity: t('Asking the agent', '询问主代理'),
        took: 400,
      );
      run.raw({
        'type': 'user',
        'uuid': '00000000-0000-4000-a000-00000000a5c0',
        'message': {
          'role': 'user',
          'content':
              '<agent-message from="${research.task}">$ask</agent-message>',
        },
        'parent_tool_use_id': null,
      });
      await run.pause(900);
      await run.tool(
        'SendMessage',
        {
          'to': research.task,
          'message': t(
            'The current one: quota and window in RateLimit-Policy, what is left and the reset in RateLimit.',
            '按现在的：配额和窗口写在 RateLimit-Policy 里，剩余次数和重置时间写在 RateLimit 里。',
          ),
        },
        result: 'Message sent to ${research.task}',
        took: 300,
      );
      await run.pause(500);
      await research.say(
        t(
          'Two fields: one for the policy, one for what is left and when it resets.',
          '一共两个字段：一个说明配额策略，一个说明还剩多少、多久重置。',
        ),
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
      await tests.say(
        t(
          'Four cases; two assert the old headers or the old window.',
          '一共四个用例，其中两个断言了旧响应头或旧的窗口行为。',
        ),
      );
    }(),
  ]);

  survey.done(
    t(
      'Options are a typed object with defaults, errors are HTTPExceptions, and headers are set on the context. The rate limiter keeps its counts in a map inside the closure, so there is no seam for another store yet.',
      '选项是带默认值的对象，出错抛 HTTPException，响应头直接设置在上下文上。限流中间件把计数存在闭包里的一个 Map 中，目前没有地方接入别的存储。',
    ),
    durationMs: 9400,
  );
  await run.pause(500);
  tests.done(
    t(
      'Two of the four change: the header assertion, and “starts counting again in the next window”, which now weighs the previous window. The 429 with Retry-After and the per-client keys stay.',
      '四个用例里改两个：断言响应头的那个，和“下一个窗口重新计数”那个，后者要改成上一窗口加权。429 带 Retry-After、按客户端区分这两个不变。',
    ),
    durationMs: 11200,
  );
  await run.pause(600);
  research.done(
    t(
      'Send RateLimit-Policy with the quota and window, and RateLimit with what is left and the seconds to reset; keep Retry-After on a 429.',
      '用 RateLimit-Policy 说明配额和窗口，用 RateLimit 说明剩余次数和重置秒数；429 时继续带 Retry-After。',
    ),
    durationMs: 14800,
  );
  await run.pause(400);
  await run.say(
    t(
      'All three are back. First the store interface with its two stores, then the counting and the headers, then the tests.',
      '三个子代理都回来了。先加存储接口和两种存储，再改计数和响应头，最后改测试。',
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
  await run.tool(
    'Bash',
    {
      'command': 'bun test src/middleware/rate-limiter',
      'description': t('Run the rate limiter tests', '运行限流中间件的测试'),
    },
    result: _bunTestOutput,
    structured: {'stdout': _bunTestOutput, 'stderr': '', 'interrupted': false},
    took: 1400,
  );
  tsc.done(t('Found 0 errors. Watching for file changes.', '0 个错误，继续监听。'));
  await run.say(
    t(
      '''Done. The rate limiter now counts in a sliding window:

| File | What changed |
|---|---|
| index.ts | the store is swappable: in memory by default, Workers KV as the other (eventually consistent, noted in the docs); the previous window is weighted |
| index.test.ts | the new headers asserted, and the next-window case checks the weighting. 4 tests, all passing |

The old X-RateLimit headers gave way to the standard RateLimit ones, which an option turns off; a 429 still comes with Retry-After.

<reply_suggestion>Add tests for the KV store too</reply_suggestion>
<reply_suggestion>Explain the weighting formula</reply_suggestion>
<reply_suggestion>Commit it</reply_suggestion>''',
      '''完成了。限流中间件现在按滑动窗口计数：

| 文件 | 改了什么 |
|---|---|
| index.ts | 存储可以替换：默认存在内存里，也可以用 Workers KV（最终一致，文档里有说明）；上一窗口的请求按比例加权 |
| index.test.ts | 断言改成新的响应头，“下一窗口”的用例改成检查加权。4 个测试全部通过 |

旧的 X-RateLimit 响应头换成了标准的 RateLimit，可以用选项关掉；429 时照旧带 Retry-After。

<reply_suggestion>KV 存储也补上测试</reply_suggestion>
<reply_suggestion>解释一下加权公式</reply_suggestion>
<reply_suggestion>提交吧</reply_suggestion>''',
    ),
    charsPerSecond: Story.zh ? 90 : 200,
  );
}

const _bunTestOutput = '''bun test v1.2.22

src/middleware/rate-limiter/index.test.ts:
✓ Rate Limiter Middleware > lets requests under the limit through, with the RateLimit headers [1.20ms]
✓ Rate Limiter Middleware > refuses one over the limit with 429 and Retry-After [0.41ms]
✓ Rate Limiter Middleware > weighs the previous window as the next begins [0.38ms]
✓ Rate Limiter Middleware > counts each client apart [0.29ms]

 4 pass
 0 fail
 9 expect() calls
Ran 4 tests across 1 file. [38.00ms]''';
