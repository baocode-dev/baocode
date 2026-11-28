# 上游一键导入与推荐上游

上游站点（多为 new-api / sub2api）在自己的令牌页放一个「导入到 BaoCode」的链接，
用户点一下，上游连同密钥就加进 BaoCode。作为回报，BaoCode 在 设置 → 模型 顶部
用小卡片免费展示接入了的站点。

```
站点令牌页「导入到 BaoCode」
  → https://baocode.dev/import#v=1&name=…&protocol=…&url=…&key=…   (site/import.js)
      参数在 # 后：浏览器不发给服务器；页面读完即从地址栏清除
  → baocode://provider/import?v=1&name=…&protocol=…&url=…&key=…
      macOS：Info.plist 注册，AppDelegate.swift → OpenRequests
      Windows：tool/baocode.iss 注册，--baocode-link → open_requests.cpp
  → Flutter：code_args.dart 的 importRequestMarker → workbench._importUpstream
      → upstream_import_dialog.dart 确认（可改名）→ ModelProviders 写入 + 钥匙串
      → 打开 设置 → 模型 中这个上游的页面
```

## 链接参数

| 参数 | 必填 | 说明 |
| --- | --- | --- |
| `v` | 否 | 版本，目前只有 `1`；其他值拒绝 |
| `url` | 是 | Base URL，http 或 https。new-api 用 `{address}` 即可：Anthropic 协议 Claude Code 自己加 `/v1`，OpenAI 协议缺版本时 BaoCode 补 `/v1`，Gemini 协议裸域名补 `/v1beta`（`UpstreamUrls`） |
| `protocol` | 否 | `anthropic`（默认）、`openai-chat`、`openai-responses`、`gemini`。不接受 `codex`（它用账号登录，没有 key） |
| `name` | 否 | 显示名，最长 64；缺省用 host |
| `key` | 否 | API key，最长 512；缺省时导入后再填 |

只接受这几个字段，这是安全边界：上游的 `env`（会成为 Claude Code 的环境变量，
能用来执行代码）、认证方式、模型列表等都不能经链接写入。未知参数忽略。

同一协议、同一 Base URL 的上游已存在时，确认框给「更新它的密钥」和「另存为新上游」。

## 推荐上游（卡片）

收录表：`site/featured/upstreams.json`，Logo 放在同目录，`logo` 只写文件名（不能带路径）。
它随官网部署在 `https://baocode.dev/featured/upstreams.json`（缓存 5 分钟），不随应用发布：
合并到 main、官网部署完，新收录就出现在用户的 设置 → 模型 里。应用打开该页时拉取
（`lib/models/featured_upstreams_io.dart`，走应用代理，一小时内不重复拉），连同 Logo 存在
数据目录的 `cache/featured/`；拉不到时用上次存下的，第一次就拉不到则不显示卡片。

```json
{
  "version": 1,
  "upstreams": [
    {
      "id": "example",
      "name": "Example",
      "url": "https://example.com/register?aff=xxxx",
      "logo": "example.svg",
      "description": { "en": "Claude and GPT at cost price", "zh": "Claude、GPT 成本价直供" },
      "hosts": ["api.example.com", "example.com"]
    }
  ]
}
```

- `url`：点卡片打开的地址，允许带推广参数。
- `logo`：SVG 或 PNG（建议 64×64 以上、正方形、自带底色，深浅主题都能看清）；
  缺省显示名称首字母。
- `hosts`：从这些域名导入时，确认框写「已收录在 BaoCode：名称」。只是提示，
  未收录的站点导入不受任何限制。
- 卡片顺序每次打开页面随机；最后一张固定为「展示你的站点」，指向 /upstreams。
- 用户已有某个收录站点的上游（上游的域名在该站点的 `hosts` 里，比如从它的令牌页导入过），
  这些站点始终排在最前，其他站点照常随机排在后面，「展示你的站点」也照常在最后；「为什么我
  看到这个？」换成说明这一点的版本。这是给站长的承诺：从您站点来的用户，您始终在首位。

## 收录流程

1. 站长按 https://baocode.dev/upstreams 接入一键导入。
2. 站长用 issue 模板「收录我的上游」（`.github/ISSUE_TEMPLATE/upstream-listing.yml`）提交。
3. 维护者：
   - 注册一个账号，在令牌页实际点一次导入，确认能成功添加并列出模型；
   - 核对 `hosts` 确实是该站的 API 域名；
   - 通过 issue 里的联系方式要 Logo，处理成正方形放进 `site/featured/`；
   - 往 `site/featured/upstreams.json` 加一条，PR 引用 issue；合并后官网部署完即上线，
     不用等应用发版。
4. 下架：导入失效、域名易主、误导用户（例如冒充官方），删掉条目即可，在 issue 里说明。

## 给站长的接入提示词

放在官网 /upstreams 页面最上面，站长复制后直接丢给 AI 编程助手：
`site/upstreams.html` 和 `site/zh/upstreams.html` 的「交给 AI 来做」一节，两边要一起改。
它让 AI 先判断站点是 new-api 系（只给配置，不改代码）还是 sub2api / 自研（在令牌列表加按钮），
链接参数、`#` 不能换成 `?`、图标怎么选、验证方法都写在里面。

提示词下面是一排按钮样式（内联 style，CSP 为此放开了 `style-src-attr`），点哪个按钮就复制
带它的提示词：第 3、4 条之间多一段，照 `/upstreams#style-<id>` 上的这个按钮做，附上它的
HTML（图片换成 baocode.dev 的绝对地址，href 是第 2 条导入链接的占位）。拼接逻辑在 `site/site.js`。

提示词第 5 条是通知 BaoCode 收录：按 issue 表单的小标题写正文，有 gh 就用 `gh issue create` 提交，
Logo 和截图提醒站长事后拖进评论。第 2 节「通知 BaoCode 收录」单独放了同样内容的提示词，给手动接入的站长。
改 issue 模板（`.github/ISSUE_TEMPLATE/upstream-listing.yml`）的字段时，两份提示词里的小标题要一起改。

按钮用的图标放在 `site/brand/`，由 `tool/make_brand_assets.py` 生成，接入方直接引用
`https://baocode.dev/brand/...` 的在线地址，不下载、不拿 SVG：

- 标志：`baocode-mark-<black|white>-<高度>.webp`，无损 WebP，4:3。显示 16×12 / 24×18 / 32×24
  三档（对应 13–14px / 15–16px / 18px 以上的按钮文字），每档 1x、2x、3x，所以高度有
  12、18、24、36、48、54、72。
- 应用图标：`baocode-icon-<尺寸>.png`，16、24、32、48、64、96、128、256、512。

这些文件名接入方会写死在页面里，只能加不能改名或删除。`/brand/*` 允许跨站引用（`_headers`）。

new-api 不用改代码：系统设置 → 聊天设置 里加一行即可（`{address}`、`{key}` 由
new-api 替换）：

```json
{ "BaoCode": "https://baocode.dev/import#v=1&name=站点名&protocol=anthropic&url={address}&key={key}" }
```

key 原样传、原样存，不加也不去任何前缀：不是所有站点的 key 都以 `sk-` 开头。确认收录前在
真实站点上用普通用户账号点一次，确认导入的 key 和站点上的完整 key 一致、能用。
