// What the showcase's pictures show: a developer's projects (well-known
// open-source repositories), their past conversations, and the work the
// agents do in the scenes, in English and in Chinese. Plain Dart: the
// runner writes the past conversations from it, the app plays the rest.

/// The language the showcase is in: `en` or `zh`.
abstract final class Story {
  static String locale = 'en';

  static bool get zh => locale == 'zh';

  /// [en], or [zh] in Chinese.
  static String t(String en, String zh) => Story.zh ? zh : en;

  /// The person whose machine it is.
  static String get author => zh ? 'Lin Chen' : 'Alex Chen';
  static const email = 'dev@example.com';

  /// The projects, each with its past conversations, newest first.
  static List<KeptProject> get projects => [
    KeptProject('hono', '🔥', [
      KeptSession(
        t(
          'Fix c.header() after the body is consumed',
          '修复读取 body 之后 c.header() 失效',
        ),
        t(
          'After `await c.req.json()` in a middleware, `c.header()` in the handler is ignored. Find out why and fix it.',
          '在中间件里 `await c.req.json()` 之后，handler 里的 `c.header()` 不生效了，查一下原因并修好。',
        ),
        t(
          'The response was finalized early: `#newResponse` cached headers when the body stream was read. I moved header merging to `c.res`’s getter and added a regression test in `context.test.ts`. All 412 tests pass.',
          '原因是读取 body 时 `#newResponse` 提前缓存了 header。我把 header 合并挪到了 `c.res` 的 getter 里，并在 `context.test.ts` 加了回归测试，412 个测试全部通过。',
        ),
        minutes: 14,
      ),
      KeptSession(
        t('Typed RPC client for nested routes', '嵌套路由的 RPC 客户端类型'),
        t(
          '`hc<typeof app>` loses the types of routes mounted with `app.route()` two levels deep. Can you make the client infer them?',
          '`hc<typeof app>` 对两层 `app.route()` 挂载的路由推断不出类型，能让客户端推断出来吗？',
        ),
        t(
          'Done: `MergeSchemaPath` now distributes over unions, so nested `route()` calls keep their schema. Added type tests in `src/client/client.test.ts`.',
          '改好了：`MergeSchemaPath` 现在会对联合类型分配展开，嵌套的 `route()` 能保留 schema。类型测试加在 `src/client/client.test.ts`。',
        ),
        minutes: 65,
      ),
      KeptSession(
        t('Explain the RegExpRouter trie', '讲讲 RegExpRouter 的前缀树'),
        t(
          'How does RegExpRouter build one regular expression out of all the routes? Walk me through `src/router/reg-exp-router/trie.ts`.',
          'RegExpRouter 是怎么把所有路由编成一个正则的？带我过一遍 `src/router/reg-exp-router/trie.ts`。',
        ),
        t(
          'Each route is inserted into a trie of path segments; `buildRegExp` walks it depth-first and emits one alternation, marking each leaf with an empty capture group whose index maps back to the handler.',
          '每条路由按路径片段插进前缀树；`buildRegExp` 深度优先遍历，拼出一个大的分支正则，每个叶子用一个空捕获组标记，捕获组的序号对应到 handler。',
        ),
        minutes: 60 * 26,
        pinned: true,
      ),
      KeptSession(
        t('Migrate router benchmarks to mitata', '把路由基准测试迁到 mitata'),
        t(
          'Move `benchmarks/routers` from benchmark.js to mitata and print a table comparing each router.',
          '把 `benchmarks/routers` 从 benchmark.js 迁到 mitata，输出各个路由器的对比表。',
        ),
        t(
          'Migrated. LinearRouter is fastest on a cold start; RegExpRouter wins once routes are registered (2.1× SmartRouter on the GitHub API set).',
          '迁好了。冷启动时 LinearRouter 最快；路由注册完之后 RegExpRouter 最快（GitHub API 路由集上是 SmartRouter 的 2.1 倍）。',
        ),
        minutes: 60 * 5,
      ),
      KeptSession(
        t(
          'Review PR #5590: escape the auth realm',
          '审查 PR #5590：转义 auth realm',
        ),
        t(
          'Review the changes in PR #5590 for basic-auth and bearer-auth.',
          '审查 PR #5590 对 basic-auth 和 bearer-auth 的改动。',
        ),
        t(
          'Looks good. One nit: `escapeRealm` should also escape `"` in bearer-auth’s `error_description`.',
          '整体没问题。一个小建议：bearer-auth 的 `error_description` 里的 `"` 也应该转义。',
        ),
        minutes: 60 * 30,
      ),
      KeptSession(
        t('Workers adapter: typed env bindings', 'Workers 适配器：env 绑定的类型'),
        t(
          'Show how to type `c.env` for KV, D1 and R2 bindings in a Cloudflare Workers app.',
          '演示一下在 Cloudflare Workers 应用里怎么给 KV、D1、R2 绑定的 `c.env` 加类型。',
        ),
        t(
          'Pass `Bindings` to `new Hono<{ Bindings: Env }>()`; `wrangler types` generates `Env` from `wrangler.jsonc`.',
          '把 `Bindings` 传给 `new Hono<{ Bindings: Env }>()`；`Env` 可以用 `wrangler types` 从 `wrangler.jsonc` 生成。',
        ),
        minutes: 60 * 24 * 4,
      ),
    ]),
    KeptProject('fastapi', '⚡', [
      KeptSession(
        t('Dependency overrides leak between tests', '依赖覆盖在测试之间串了'),
        t(
          '`app.dependency_overrides` set in one test still applies in the next. Why, and what’s the cleanest fix?',
          '一个测试里设置的 `app.dependency_overrides` 在下一个测试里还生效，为什么？最干净的修法是什么？',
        ),
        t(
          'The app is module-level, so overrides persist. Use a fixture that yields and calls `app.dependency_overrides.clear()` in teardown.',
          'app 是模块级的，覆盖会一直保留。用一个 yield 的 fixture，在清理时调用 `app.dependency_overrides.clear()`。',
        ),
        minutes: 25,
        unread: true,
      ),
      KeptSession(
        t('OpenAPI examples for webhooks', '给 webhooks 加 OpenAPI 示例'),
        t(
          'Add request examples to the webhook docs in `docs_src/openapi_webhooks`.',
          '给 `docs_src/openapi_webhooks` 里的 webhook 文档加上请求示例。',
        ),
        t(
          'Added `openapi_examples` to both webhook models and regenerated the docs snapshot.',
          '两个 webhook 模型都加了 `openapi_examples`，并重新生成了文档快照。',
        ),
        minutes: 60 * 7,
      ),
      KeptSession(
        t('Profile pydantic v2 validation', '分析 pydantic v2 的校验耗时'),
        t(
          'Requests with large nested bodies are slow. Profile where validation spends its time.',
          '嵌套很深的大请求体很慢，分析一下校验时间花在哪里。',
        ),
        t(
          '68% is in `TypeAdapter` construction per request; caching the adapter per route cut p95 from 41 ms to 9 ms.',
          '68% 的时间花在每个请求都新建 `TypeAdapter` 上；按路由缓存之后 p95 从 41 ms 降到 9 ms。',
        ),
        minutes: 60 * 48,
      ),
    ]),
    KeptProject('excalidraw', '✏️', [
      KeptSession(
        t('Arrow binding jitters when zoomed out', '缩小时箭头绑定抖动'),
        t(
          'Below 30% zoom, arrows bound to a rectangle jitter while dragging. Find the cause.',
          '缩放小于 30% 时，拖动绑定在矩形上的箭头会抖，找一下原因。',
        ),
        t(
          'The binding gap is in scene units but the hit test uses screen pixels; dividing by `zoom.value` in `getHoverElementForPoint` fixes it.',
          '绑定间距用的是场景单位，命中测试却用屏幕像素；在 `getHoverElementForPoint` 里除以 `zoom.value` 就好了。',
        ),
        minutes: 40,
      ),
      KeptSession(
        t('Collaborator cursors in dark mode', '暗色模式下的协作者光标'),
        t(
          'Collaborator cursor labels are unreadable in dark mode. Pick colors that work in both themes.',
          '暗色模式下协作者光标的名字看不清，选一组两种主题都清楚的颜色。',
        ),
        t(
          'Switched to OKLCH with fixed lightness per theme; contrast is now ≥ 4.5:1 in both.',
          '改用 OKLCH，按主题固定亮度；两种主题下对比度都 ≥ 4.5:1。',
        ),
        minutes: 60 * 28,
      ),
    ]),
    KeptProject('ollama', '🦙', [
      KeptSession(
        t('Stream tool calls from llama3.3', '让 llama3.3 流式返回工具调用'),
        t(
          'Tool calls only arrive at the end of the stream. Make `/api/chat` stream them as soon as they parse.',
          '工具调用要等流结束才返回，让 `/api/chat` 一解析出来就流式发出。',
        ),
        t(
          'Added an incremental JSON parser to `server/routes.go`; tool calls now stream about 1.8 s earlier on average.',
          '在 `server/routes.go` 加了增量 JSON 解析，工具调用平均提前 1.8 秒发出。',
        ),
        minutes: 60 * 3,
      ),
      KeptSession(
        t('Metal OOM on 70B models', '70B 模型在 Metal 上爆显存'),
        t(
          '70B q4 runs out of memory on a 64 GB Mac. Estimate what fits.',
          '70B q4 在 64 GB 的 Mac 上内存不够，估算一下能放下多少。',
        ),
        t(
          'With 8K context it needs ~43 GB; the default 32K KV cache adds 10 GB. Setting `OLLAMA_CONTEXT_LENGTH=8192` fits.',
          '8K 上下文需要约 43 GB；默认 32K 的 KV 缓存要再多 10 GB。设置 `OLLAMA_CONTEXT_LENGTH=8192` 就能放下。',
        ),
        minutes: 60 * 24 * 3,
      ),
    ]),
    KeptProject('ripgrep', '🔍', [
      KeptSession(
        t('JSON output for multiline matches', '多行匹配的 JSON 输出'),
        t(
          '`rg --json -U` splits a multiline match into several `match` events. Should it?',
          '`rg --json -U` 会把一个多行匹配拆成几个 `match` 事件，这样对吗？',
        ),
        t(
          'It’s by design: one event per line keeps the stream line-oriented. `submatches` carry the byte offsets to join them.',
          '这是有意的：每行一个事件，保证输出按行。`submatches` 里有字节偏移，可以拼回去。',
        ),
        minutes: 60 * 24 * 6,
      ),
    ]),
  ];

  /// The skills in `~/.claude/skills`, for Customize: name, description.
  static List<(String, String)> get skills => [
    (
      'changelog',
      t(
        'Drafts CHANGELOG entries from the commits since the last tag.',
        '根据上个 tag 以来的提交起草 CHANGELOG 条目。',
      ),
    ),
    (
      'frontend-design',
      t(
        'Builds distinctive, production-grade web interfaces.',
        '做出有辨识度、可直接上线的网页界面。',
      ),
    ),
    ('pdf', t('Reads, fills and merges PDF files.', '读取、填写和合并 PDF 文件。')),
    (
      'release-notes',
      t('Writes release notes in the project’s voice.', '用项目自己的口吻写发布说明。'),
    ),
    (
      'security-review',
      t(
        'Reviews a change for injection, auth and secrets mistakes.',
        '检查改动里的注入、鉴权和密钥问题。',
      ),
    ),
  ];

  /// The skills in hono's own `.claude/skills`.
  static List<(String, String)> get honoSkills => [
    (
      'hono-middleware',
      t(
        'Scaffolds a Hono middleware with tests, docs and exports.',
        '生成带测试、文档和导出的 Hono 中间件骨架。',
      ),
    ),
    (
      'runtime-matrix',
      t(
        'Runs the tests on Bun, Node, Deno and Workers and sums up what fails where.',
        '在 Bun、Node、Deno 和 Workers 上跑测试，汇总各自失败的地方。',
      ),
    ),
  ];
}

class KeptProject {
  const KeptProject(this.name, this.emoji, this.sessions);

  /// Its folder's name, in `~/code`.
  final String name;

  /// Its icon in the sidebar.
  final String emoji;
  final List<KeptSession> sessions;
}

/// A past conversation: its title, what was asked and answered, and how
/// long ago.
class KeptSession {
  const KeptSession(
    this.title,
    this.prompt,
    this.answer, {
    required this.minutes,
    this.pinned = false,
    this.unread = false,
  });

  final String title;
  final String prompt;
  final String answer;
  final int minutes;
  final bool pinned;
  final bool unread;
}
