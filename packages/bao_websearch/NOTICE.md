# Third-party notice: cursor-byok

The search here is ported to Dart from
[cursor-byok](https://github.com/leookun/cursor-byok) at commit
`31e9f5cbc98a7d28cffcb5efbb9323cd3e143354`:

| Here | There |
|---|---|
| `lib/src/engine.dart` | `server/src/search/engine.rs` |
| `lib/src/catalog.dart` | `server/src/search/catalog.rs` |
| `lib/src/federation.dart` | `server/src/search/federation.rs` |
| `searchResultsText` in `lib/src/anthropic.dart` | `complete_web_search` in `server/src/cursor/tools/tool_call_result/interaction.rs` |
| `test/federation_test.dart` (the merge's tests) | the tests in `server/src/search/federation.rs` |

What differs from the original:

- Pages are parsed by `package:html` and its CSS selectors, on an isolate
  of their own; an element's text is its text nodes joined as they are,
  not with a space between each.
- A search does not wait for every engine: once one has results, the
  others are waited for [WebSearch.settle] (3 seconds) more.
- `allowed_domains` and `blocked_domains` (Anthropic's tool's) are kept
  to: the query asks the engines with `site:`, and the results are
  filtered.
- The user agent is BaoCode's.
- New here, not in cursor-byok: answering Anthropic's `web_search` tool
  with a search (`lib/src/anthropic.dart`), and what is known of which
  APIs run that tool themselves (`lib/src/native_support.dart`).

cursor-byok's license:

```
MIT License

Copyright (c) 2026 leookun

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
