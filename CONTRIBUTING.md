# Contributing to BaoCode

[English](#english) · [简体中文](#简体中文)

## English

Issues and pull requests are both welcome. To keep review manageable, pull
requests have to follow the rules below; one that does not is closed without
a detailed review.

### Talk first

Open an [issue](https://github.com/baocode-dev/baocode/issues) before you
write code for a new feature, a change in behavior or UI, a refactor, or a
new dependency, and wait until a maintainer agrees to the change and to how
it is done: they label the issue `accepted`. Link that issue in the pull
request, as `Issue: #123`.

These can go straight to a pull request: typos, translations, documentation,
and a bug fix that is small and obvious (a `fix(…)` title, about 100 changed
lines at most, not counting tests).

### Keep it small

- One pull request does one thing. Unrelated fixes, renames and reformatting
  go into pull requests of their own.
- About 400 changed lines at most, not counting tests and generated files.
  Split bigger work into steps that each build and pass their tests, and
  agree on the steps in the issue first.

**Large pull requests, and pull requests for changes not discussed first, are
not accepted.** A check (`PR gate`) comments on a pull request that is missing
an accepted issue, is too large, has a title not in `type(scope): summary` or
merge commits in its branch; one still without an accepted issue after seven
days is closed.

### Before you open it

- Match the code around your change: its naming, comment density and idiom.
  UI uses BaoCode's own components, not stock Material or Cupertino widgets.
- Run `dart format` and `flutter analyze`, and the tests for what you changed,
  for example `flutter test test/update`. The full suite is slow; you do not
  need to run all of it.
- Add or update tests for what you fixed or added.
- Commit messages follow `type(scope): summary`, for example
  `fix(ide): ...`; see `git log` for more.
- You understand and can explain every line, including any written with an
  AI tool.
- Your contribution is licensed under the license of the files it changes:
  [GPL-3.0-only](LICENSE) for the app, MIT for `packages/bao_editor`,
  `packages/bao_xterm` and `packages/bao_pty`.

## 简体中文

欢迎提交 Issue 和 Pull Request。为了让审阅跟得上，PR 需要遵守下面的规则；
不符合的会直接关闭，不做详细审阅。

### 先讨论

新功能、行为或界面的改动、重构、新增依赖，写代码之前先开
[Issue](https://github.com/baocode-dev/baocode/issues)，等维护者认可要不要改、
怎么改之后再动手（认可后维护者会给 Issue 打上 `accepted` 标签），并在 PR 里
关联这个 Issue，写成 `Issue: #123`。

以下可以直接提 PR：错别字、翻译、文档，以及小而明确的 bug 修复（标题为
`fix(…)`，改动约 100 行以内，不含测试）。

### 保持小

- 一个 PR 只做一件事。无关的修复、重命名、格式调整另开 PR。
- 改动不超过约 400 行（不含测试和生成文件）。更大的工作拆成几步，每一步都能
  单独编译、通过测试，并且先在 Issue 里商量好怎么拆。

**太大的 PR、未经讨论的 PR，不会被接受。** 自动检查（`PR gate`）会在 PR 下
留言指出：没有被认可的 Issue、改动太大、标题不是 `type(scope): summary`、分支
里有合并提交。7 天后仍没有被认可的 Issue 的 PR 会被自动关闭。

### 提交之前

- 跟周围代码保持一致：命名、注释密度、写法。界面用 BaoCode 自己的组件，
  不用 Flutter 自带的 Material / Cupertino 控件。
- 运行 `dart format`、`flutter analyze`，以及与改动相关的测试，例如
  `flutter test test/update`。完整测试很慢，不需要全部跑。
- 修复或新增的功能要补上或更新测试。
- 提交信息格式为 `type(scope): summary`，例如 `fix(ide): ...`，可参考 `git log`。
- 每一行你都理解、能解释，包括用 AI 工具写的部分。
- 你的贡献沿用所改文件的许可证：应用本体为 [GPL-3.0-only](LICENSE)，
  `packages/bao_editor`、`packages/bao_xterm`、`packages/bao_pty` 为 MIT。
