# Language settings and language packs

The IDE decides a file's language, and the language servers that serve it,
from three layers; each overrides the one before:

1. **Bundled**: `assets/lsp/languages.json`, generated from Helix's
   `languages.toml` (`tool/generate_lsp_languages.mjs`).
2. **Language packs**: folders in `<data>/language-packs/`.
3. **User settings**: `<data>/lsp.json`.

`<data>` is the app data folder (`AppPaths.dataDir`):
`~/Library/Application Support/monad` on macOS, `~/.config/monad` on Linux,
`%APPDATA%\monad` on Windows. Installed servers go to `<data>/servers/`.

Entries that do not validate are skipped and reported
(`BundledLspCatalog.problems`, `LanguagePackRegistry.problems`); the rest
still applies. Settings and packs are read when the catalog loads.

## `lsp.json`

```json
{
  "servers": {
    "rust-analyzer": {
      "settings": { "rust-analyzer": { "check": { "command": "clippy" } } }
    },
    "my-server": {
      "command": "/opt/my-server/bin/my-server",
      "args": ["--stdio"],
      "environment": { "MY_SERVER_LOG": "info" },
      "initializationOptions": {},
      "rootMarkers": ["my.toml"],
      "requiredRoot": true,
      "onlyFeatures": ["hover", "goto-definition"]
    },
    "ruff": { "disabled": true }
  },
  "languages": {
    "python": { "servers": ["pyright", { "name": "ruff", "onlyFeatures": ["format", "diagnostics"] }] },
    "mylang": {
      "fileTypes": ["my", "my.in"],
      "fileNames": ["Myfile"],
      "globs": ["config/*.mycfg"],
      "shebangs": ["mylang"],
      "firstLine": "^#!.*\\bmylang\\b",
      "rootMarkers": ["my.toml"],
      "languageId": "mylang",
      "servers": ["my-server"]
    }
  }
}
```

A server entry changes only the fields it has; a new server needs
`command`. Fields:

| Field | Meaning |
| --- | --- |
| `command` | Executable: a bare name (looked up on the login shell's PATH, then among installed servers) or an absolute path. |
| `args`, `environment` | Arguments; extra environment variables. |
| `settings` | What `workspace/configuration` and `didChangeConfiguration` answer. |
| `initializationOptions` | Sent with `initialize`. |
| `config` | Helix's form: sets both of the above. |
| `rootMarkers`, `requiredRoot` | Files or folders marking the workspace root; whether the server needs one. |
| `masonPackage` | The mason-registry package that installs it (`null` clears it). |
| `onlyFeatures`, `exceptFeatures` | Helix feature names: `format`, `goto-definition`, `goto-reference`, `hover`, `completion`, `signature-help`, `rename-symbol`, `code-action`, `document-symbols`, `diagnostics`, `semantic-tokens`. |
| `disabled` | `true` removes the server from every language. |

A language entry replaces the lists it has. `fileTypes` are extensions
(with or without the dot, longest match first: `a.test.ts` tries `test.ts`,
then `ts`); `fileNames` exact base names; `globs` Helix globs, matched
against the whole path with a leading `*/` unless they start with `/`
(`*` also crosses `/`). A file is matched by exact name, then glob, then
extension, then the `#!` interpreter (`shebangs`, version digits ignored),
then `firstLine`. Later layers win a name or extension an earlier one
claims. A `servers` item is a server id or `{ "name", "onlyFeatures",
"exceptFeatures" }` (Helix's `only-features`/`except-features` spellings
work too).

## Language packs

A pack is a folder in `<data>/language-packs/`:

```
language-packs/toy/
  manifest.json        required
  grammar.json         Monarch grammar (syntax highlighting)
  configuration.json   language configuration (comments, brackets, …)
  server.json          optional language servers
```

### `manifest.json`

```json
{
  "name": "Toy",
  "languages": [
    {
      "id": "toy",
      "extensions": [".toy"],
      "filenames": ["Toyfile"],
      "aliases": ["Toy"],
      "firstLine": "^#!.*\\btoy\\b",
      "shebangs": ["toy"],
      "rootMarkers": ["toy.project"],
      "languageId": "toy",
      "grammar": "grammar.json",
      "configuration": "configuration.json"
    }
  ]
}
```

`id` is required. `extensions`, `filenames`, `aliases` and `firstLine` are
Monaco's language registration fields; `aliases[0]` is the name the status
bar shows. `grammar` and `configuration` default to the pack's
`grammar.json` and `configuration.json` (paths are relative to the pack), so
several languages can share or have their own. A language without a
grammar still counts for language servers but is not highlighted by the
pack.

For the editor, pack languages come before the bundled Monaco languages:
they win a file name, an extension at least as long as the bundled match,
and a first line. A pack language may reuse a bundled id (e.g. `ini`) to
replace its grammar. For language servers, a pack language is a language
entry as in `lsp.json` (with `extensions` as `fileTypes` and `filenames` as
`fileNames`).

### Packs and TextMate highlighting

On the desktop the editor highlights with VS Code's TextMate grammars
(`assets/textmate/`, `lib/ide/editor/textmate/`), which VS Code's language
detection picks from the file name, extension, glob or first line. Pack
grammars are Monarch grammars, and they still come first: a file a pack
language claims (as above) is highlighted by the pack, whatever grammar
VS Code has for it. A file no pack claims is highlighted by TextMate when a
VS Code language with a grammar matches it, and by the bundled Monarch
grammars otherwise (languages VS Code does not ship, e.g. Kotlin). On the
web, or when the native Oniguruma library does not load, everything is
Monarch, as before.

Language ids are separate matters: highlighting uses VS Code's ids
(`shellscript`, `typescriptreact`), Monarch uses Monaco's (`shell`),
language servers use this catalog's (`languageId`). Where a VS Code id
falls back to Monarch it is mapped (`monarchLanguageIdFor` in
`textmate_syntax.dart`); language servers never see highlighting ids.

### `grammar.json`

A Monarch definition (https://microsoft.github.io/monaco-editor/monarch.html)
as JSON: the same shape as `assets/monaco/languages/*.json`, either that
whole file (`{ "language": { … }, "configuration": { … } }`) or just the
definition. It needs a `tokenizer`. Regular expressions are strings, or
`{ "$regex": "…", "$flags": "i" }` objects as the bundled assets write them.
Token types are themed like the bundled languages' (`keyword`, `comment`,
`string`, `number`, `type`, …; the `tokenPostfix` is appended).

```json
{
  "tokenPostfix": ".toy",
  "keywords": ["let", "fn"],
  "tokenizer": {
    "root": [
      [";;.*$", "comment"],
      ["[a-z_]\\w*", { "cases": { "@keywords": "keyword", "@default": "identifier" } }],
      ["\\d+", "number"],
      ["\"", "string", "@string"]
    ],
    "string": [["[^\"]+", "string"], ["\"", "string", "@pop"]]
  }
}
```

### `configuration.json`

Monaco's language configuration, as the bundled assets' `configuration`,
or VS Code's `language-configuration.json`: `comments` (`lineComment`,
`blockComment`), `brackets`, `autoClosingPairs` (`[open, close]` or
`{ open, close, notIn }`), `surroundingPairs`, `autoCloseBefore`,
`wordPattern`, `indentationRules`, `onEnterRules` (`indentAction` as
Monaco's number or VS Code's name: `none`, `indent`, `indentOutdent`,
`outdent`), `folding` (`offSide`, `markers`). Patterns are strings,
`{ "pattern", "flags" }` or `{ "$regex", "$flags" }`. Comment toggling,
auto-closing, indentation on Enter and folding markers use it.

### `server.json`

```json
{
  "servers": [
    { "id": "toy-ls", "command": "toy-ls", "args": ["--stdio"],
      "settings": { "toy": { "strict": true } }, "languages": ["toy"] }
  ]
}
```

Each server takes the `lsp.json` server fields plus `id` and `languages`
(default: all the pack's languages); the languages it lists use the pack's
servers instead of the bundled ones. A single server object works too.

## Where this lives

- `lib/ide/lsp/catalog/`: `BundledLspCatalog` (the layers and matching),
  `loadStandardLsp()` (catalog + installer for the app).
- `lib/ide/lsp/packs/`: `LspUserSettings`, `LanguagePackRegistry` (its
  `instance` is what `MonacoLanguageAssets` uses by default).
- `lib/ide/lsp/install/`: `MasonServerProvider`, the mason-registry
  installer.
- `lib/ide/editor/monaco/flutter/language_assets.dart`: pack grammars and
  registrations for the editor.
- `lib/ide/editor/textmate/textmate_syntax.dart`: TextMate highlighting,
  which defers to packs (`TextMateSyntax.languageIdForPath`).
