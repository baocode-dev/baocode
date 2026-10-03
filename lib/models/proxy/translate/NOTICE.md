# Third-party notice: CLIProxyAPI

The translators in this folder, which turn Anthropic Messages requests into
OpenAI Chat Completions and Responses requests and their replies back, are
ported to Dart from [CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI)
at commit `2044a01f422998de79a5da8015141b878886534d`:

| Here | There |
|---|---|
| `openai_chat_request.dart` | `internal/translator/openai/claude/openai_claude_request.go` |
| `openai_chat_response.dart` | `internal/translator/openai/claude/openai_claude_response.go` |
| `responses_request.dart` | `internal/translator/codex/claude/codex_claude_request.go` |
| `responses_response.dart` | `internal/translator/codex/claude/codex_claude_response.go`, `codex_claude_response_web_search.go` |
| `common.dart` | `internal/translator/common/` (what the above use) |
| `util.dart` | `internal/util/` (what the above use) |
| `thinking.dart` | `internal/thinking/` (what the above use) |
| `signature.dart` | `internal/signature/` (the GPT, Grok and Kimi checks) |

Their tests are ported beside them, under `test/models/proxy/translate/`.

What differs from the original:

- The Responses translator targets the standard OpenAI Responses API, not
  ChatGPT's Codex backend: no empty `instructions`, and `reasoning` and the
  encrypted reasoning it carries are only asked for of models that think
  (`ResponsesRequestOptions`).
- Signature detection keeps only what a GPT target needs: GPT reasoning
  signatures are recognized, others are not. The Grok and Kimi shape checks
  skip the Claude and Gemini envelope probes.
- JSON is built as Dart maps rather than spliced as bytes; key order is the
  same.

## License

```
MIT License

Copyright (c) 2025-2005.9 Luis Pater
Copyright (c) 2025.9-present Router-For.ME

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
