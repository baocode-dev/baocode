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

1. Call `mcp__baocode__model_prices` with nothing to list the models called lately, the upstream each is on (name and base URL) and their prices.
2. Find each upstream's own pricing page (its site, from the base URL or name) and read the prices there; any way you can read a web page will do. Never guess a price, nor take it from another upstream.
3. Prices are a million tokens: input, output, cache read, cache write, and the currency the page uses (e.g. USD, CNY). Leave a cache price out when the page gives none.
4. Set them with `model_prices`' `set`, each with its `upstream` id and the page as `source`; then tell the user what changed, old and new.
''';
  }
}
