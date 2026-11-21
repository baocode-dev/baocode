# Third-party notice: CLIProxyAPI, magpie

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

The ChatGPT (Codex) provider, in `lib/models/codex/`, follows the same
project's Codex support (its Codex executor and Codex OAuth), written anew
rather than ported line by line: the request as the backend takes it and
its headers, a usage limit reached and the failover from it (`codex_api.dart`),
signing in with PKCE and the ID token's claims (`codex_oauth.dart`).

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

## Antigravity

The Antigravity provider (`lib/models/antigravity/`) and its translators
here follow [magpie](https://github.com/yetone/magpie) at commit
`1ee91da9373be41c27a3f20067f019f7851dee97` and CLIProxyAPI at commit
`f5c5681a8361c9da53e93c60b6507816eee7468b`, written anew in Dart after them:

| Here | There |
|---|---|
| `antigravity_request.dart` | magpie `internal/gateway/codeassist.go` (`buildCodeAssistSent`, `pairFunctionTurns`, `dropSecondAnswers`, `thinkingConfig`); CLIProxyAPI `internal/translator/antigravity/claude/antigravity_claude_request.go` |
| `antigravity_response.dart` | magpie `internal/gateway/codeassist.go` (`codeAssistDecoder`, the calls written out as text); CLIProxyAPI `internal/translator/antigravity/claude/antigravity_claude_response.go` |
| `antigravity_schema.dart` | magpie `internal/gateway/codeassist.go` (`plainSchema`, `foldUnion`) |
| `antigravity_cloak.dart` | magpie `internal/gateway/codeassist.go` (`antigravityCloak`) |
| `antigravity_signature.dart` | magpie `internal/gateway/gemini_signature.go`, `gemini_sigstore.go` |
| `lib/models/antigravity/antigravity_api.dart` | magpie `internal/provider/google.go`, `antigravity_models.go`; CLIProxyAPI `internal/auth/antigravity/`, `internal/runtime/executor/antigravity_executor_credits.go` |

What differs: requests are built from Anthropic Messages only; a thought
signature is kept under `cache/gemini-signatures` in the app's data folder;
quota windows of a group name the models drawing on them, so an account out
of one group's quota still takes the others' models.

magpie's license:

```
MIT License

Copyright (c) 2026 yetone

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

## CLIProxyAPI's license

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
