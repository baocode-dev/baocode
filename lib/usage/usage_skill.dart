import 'dart:convert';

/// The Claude Code skill that tells agents of the usage BaoCode keeps and
/// the models' prices (UsageTools). It is the user's as any skill is
/// (`<config>/skills/baocode-usage/`), to read, change or delete; BaoCode
/// writes it anew only while its [marker] is in it.
abstract final class UsageSkill {
  static const name = 'baocode-usage';

  /// Its line that says BaoCode wrote it; a skill without it is left as
  /// it is.
  static const marker =
      '<!-- Written by BaoCode, which keeps it up to date. '
      'Delete this line to keep your own changes. -->';

  /// Whether [existing] (its file's text, null for none) is to be written
  /// as [text]: none, or BaoCode's and not the same.
  static bool stale(String? existing, String text) =>
      existing == null || (existing.contains(marker) && existing != text);

  static String text() {
    const description =
        "BaoCode's record of the model calls in the user's conversations "
        'and the models\' prices. Use it when the user asks how much a '
        'conversation (this one or another) used or cost: its context, '
        'cache hits, time to first token, speed, tokens by model or agent; '
        'or asks to check, set or update the models\' prices.';
    return '''
---
name: $name
description: ${jsonEncode(description)}
---
$marker

# Usage and prices in BaoCode

BaoCode keeps every call to a model in the user's conversations: to Claude Code's own models (a Claude plan or Anthropic's API, with the plan's limits as they stood after each call) and to custom upstreams. It works out what they cost from the prices in Settings → Usage → Model prices; Claude Code's own models are at Anthropic's API prices unless set (for a plan, what its use would have cost on the API).

## Looking at usage

Call `mcp__baocode__usage_report`:

- no `session`: this conversation; a conversation's id for another; `"all"` with `days` for every conversation lately.
- It answers with totals, by model, by agent, what filled the latest context and the latest calls (tokens, cache read and write, first token, duration, tok/s, cost).

Answer in the user's words and numbers they can act on: e.g. a low cache hit rate, a context that grows fast, a slow first token on one upstream, what costs most. Do not paste the JSON.

## Keeping the prices

1. Call `mcp__baocode__model_prices` with nothing to list the models called lately, the upstream each is on (name and base URL), what their calls had (`serviceTiersSeen`, `geosSeen`, `serverToolsSeen`), their prices (`pricedAs` says whose) and the upstreams' rates.
2. Find each upstream's own pricing page (its site, from the base URL or name) and read the prices there; any way you can read a web page will do. Never guess a price, nor take it from another upstream.
3. Prices are a million tokens: `input`, `output`, `cache_read`, `cache_write` (`cache_write_1h` for an hour's cache where it is priced apart), and the `currency` the page uses (e.g. USD, CNY). Leave a cache price out when the page gives none.
4. Set them with `model_prices`' `set`, each with its `upstream` id and the page as `source`; then tell the user what changed, old and new.

The user does not set these by hand: read the whole page, footnotes too, and set every rule it gives, as below.

### Rules beyond a flat price

- **By the prompt's length** (Qwen's 0–32K/32K–128K/…, Doubao's, Gemini Pro over 200K, OpenAI over 272K, Claude Haiku over 100K): the price's own fields are the first band's; `tiers` the others, each with `over` (prompt tokens more than) and/or `up_to` (at most), and its `input`/`output` (cache prices where given, else they follow the input's ratio). The prompt counts all input tokens, cache reads and writes too. The last tier a call is within prices all of its tokens: list them from the lowest up. Where the page prices by the answer's length too (Doubao's "output ≤ 200 tokens"), add `output_over`/`output_up_to`, the more specific tier after the broader one. If the page says only the tokens past the line pay more, say so to the user: that is not supported, and the tier is the closest.
  `{"model":"qwen3-coder-plus","upstream":"<id>","currency":"CNY","input":4,"output":16,"tiers":[{"over":32000,"up_to":128000,"input":6,"output":24},{"over":128000,"up_to":256000,"input":10,"output":40},{"over":256000,"input":20,"output":200}]}`
- **By the time of the week** (DeepSeek's off-peak half price, a plan's peak hours): `schedule` with the page's `timezone`, `windows` (`days` 1 Monday … 7 Sunday, `from`/`to` "HH:MM", their `factor`), `otherwise` for the rest, and `except`: the dates priced as `otherwise` all day (e.g. "excluding Chinese public holidays": list this year's holiday dates, adjusted working weekends left out, and tell the user to have them updated next year). Give the price's fields as the page's base (say the peak price) and factors relative to it.
  `"schedule":{"timezone":"UTC","windows":[{"days":[1,2,3,4,5],"from":"01:00","to":"04:00","factor":1},{"days":[1,2,3,4,5],"from":"06:00","to":"10:00","factor":1}],"otherwise":0.5,"except":["2026-10-01","2026-10-02"]}`
- **Fast mode, service tiers, regions**: `fast` (e.g. 2), `service_tiers` by the name the upstream answers with (OpenAI's `{"priority":2,"flex":0.5}`; the names a model's calls had are in `serviceTiersSeen`), `geo` by region (Anthropic's `{"us":1.1}`). Batch prices do not apply: these calls are not batched.
- **Fees**: `per_call` for a price a request (a relay's per-call model); `tools` for the upstream's own tools a use, by the name in `serverToolsSeen` (`{"web_search":0.01}` for \$10 a thousand searches). Free allowances are not tracked: leave the fee out while it is free and say so.
- **A relay or reseller** (new-api and the like: a discount, a group rate, "0.3x"): `set_upstream_rates` with its `multiplier` instead of a price each model; its models are priced as the same model elsewhere (the price set for any upstream, or Anthropic's built in for Claude's) times it, in its `currency` where it charges in another (fold the exchange rate it uses into the multiplier). A model priced on its own on that upstream is not.
- **A price that changes on a date** (a promotion ending, a new price): set the new one with `from` ("YYYY-MM-DD"); the calls before keep the price before. Without `from` a price is the model's only one, and prices all of its calls.
- Not priced: a cache's storage by the hour, plans' credits (Coding Plans; the Claude plan's limits are in the report).

After setting, call `model_prices` again and check `pricedAs` and the prices are what the page says; `usage_report`'s calls tell `pricedBy` (the tier, the factors, the fees) for each.
''';
  }
}
