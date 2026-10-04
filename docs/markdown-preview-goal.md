# Goal：BaoCode 的 Markdown 预览、按块编辑和粘贴文件

## 背景
BaoCode 是 Flutter 桌面应用（macOS / Windows），给 Claude Code 做 UI，并自带 IDE。
现在打开 `.md` 只能看到 Monaco 里的源码，读起来很不方便。聊天里已经有一个 Markdown 渲染器 `MarkdownView`（lib/chat/widgets/markdown_view.dart，基于 `markdown` 包），但它是为聊天写的：
- 图片只显示成 `[alt]` 占位
- 字号紧凑
- 所有块放在一个 Column 里，不是懒加载
- 不带源码位置

目标：
1. `.md` 标签页可以在「预览 / Markdown」之间切换。
2. 预览里可以按块就地编辑。
3. 在源码和按块编辑里都能粘贴图片或文件：文件存到文档旁边，并自动插入链接。

本机项目和 SSH 远程项目都要支持。

## 核心架构（必须遵守）
1. **只有一份内容**：预览读的是 `IdeDocument.model`（lib/ide/ide_workspace.dart 里的 `EditorDocumentModel`），不是磁盘文件。
   - 预览里的所有修改都用 `model.applyEdit(range, text)` 写回这个 model，不能另存一份文本。
   - 这样未保存标记、撤销/重做、保存、冲突检测、LSP、Agent 改动审查（Keep/Undo）、源码视图看到的都是同一份内容。
   - 预览订阅 model 的变更流，稍等一会再刷新（防抖）。
2. **按块编辑只改对应的行**：
   - 预览按顶层块显示：段落、标题、列表（整个列表算一块）、表格、代码围栏、引用、分隔线、公式块、HTML 块。
   - 点一个块，它就地变成多行输入框（等宽字体），内容是该块的 Markdown 源码。
   - 失去焦点或按 Esc 时，用 `applyEdit` 只替换这个块原来的行范围，文件的其他部分必须一个字节都不变。不要做 Markdown ↔ 富文本的来回转换，不要用 flutter_quill。
   - 内容没变的话不产生编辑。
   - 一次块编辑在撤销栈里算一步。
3. **自己写分块器**：`markdown` 包不给源码位置（`BlockParser._pos` 是私有的），所以在 lib/ide/markdown/ 下新写一个按行扫描的分块器，输出每块的 `[startLine, endLine)`。
   - 必须正确识别：代码围栏（``` 和 ~~~，包括没闭合的）、缩进代码、列表与续行、懒续行、表格、引用、setext 标题、front matter（`---` 开头的 YAML 头）、HTML 块、公式块（与 MathBlockSyntax 一致）。
   - 每块的源码再单独交给 `markdown` 包渲染。
   - 引用式链接的定义（`[x]: url`）要在整篇范围内生效。
4. **复用渲染器**：把 `MarkdownView` 的块和行内渲染抽成可复用的部分，聊天和文档预览共用，聊天现有行为和测试保持不变。文档预览用自己的一套排版，参考 VS Code 或 GitHub 的预览：
   - h1/h2 更大，下面有分隔线
   - 正文宽度有上限并居中
5. **路径与文件读写都通过项目的文件服务**，这样远程项目也能用。
   - 读：图片用 `IdeHostFiles.readBytes`，本机项目用 `readFileBytes`，参考 lib/ide/ide_image_preview.dart 的做法。
   - 写：给 `IdeFileService` 加 `writeBytes(String path, Uint8List bytes)`，路径已存在时抛 `IdeFileExistsException`。
     - 本机：在 lib/ide/file_service_io.dart 里实现。
     - 远程：在 packages/bao_remote 的协议（src/protocol.dart）里加 `fs/writeBytes`（字节用 base64），并实现 server 分发和 client 调用，再接到 lib/remote/remote_services.dart。
   - 路径计算用项目对应的 `path.Context`，远程项目一律用 `p.posix`。

## 预览
- `.md` 和 `.markdown` 文件的标签页右上角（lib/ide/ide_tab_bar.dart 的 `_TabBarAction` 区域，`…` 按钮左边）显示「预览 | Markdown」两个按钮，样式参考 VS Code。
- 打开时默认显示预览。每个文件选的模式在工作区状态里记住，和其他打开的编辑器状态一起持久化。
- 加两个命令：`markdown.showPreview`、`markdown.showSource`。
  - 再加一个快捷键切换两种模式，用 VS Code 的 ⇧⌘V（Windows 上是 Ctrl+Shift+V），并检查和现有快捷键是否冲突。
- 在 lib/ide/ide_workbench.dart 选择编辑器视图的那段代码里（`isMedia` → `IdeImagePreview` 那一段附近），给 Markdown 加一个预览分支。
  - 切换模式时尽量保持位置：从预览切到源码，跳到当前视口顶部那一块的起始行；从源码切到预览，滚到光标所在的块。
- 只读文档（`readOnly`，例如 diff 或某个历史版本）显示预览，但不能编辑。
- 渲染内容：
  - GFM 全部内容，包括任务列表、表格、删除线、自动链接，以及代码块（有现成的高亮就复用）和 TeX 公式。
  - 图片：相对路径按文档所在目录解析，`http(s)` 图片直接从网络加载，加载失败时显示占位和 alt。
  - 链接：
    - 相对路径的文件链接在 IDE 里打开；
    - `#锚点` 滚动到对应标题，锚点规则和 GitHub 一样（转小写、空格变 `-`、去掉标点）；
    - 外部链接用系统浏览器打开。
  - HTML 块按原文显示成代码样式，不执行。
- 按块懒加载：长文档（几千行）滚动要流畅，可以用 `super_sliver_list`。
- 预览里的文字可以选中和复制（用 `SelectionArea`）。⌘A 只选中预览里的内容，参考 docs/macos-edit-commands.md。
- 点任务列表的复选框，直接把对应行的 `[ ]` 和 `[x]` 互相切换，同样通过 `applyEdit`。

## 按块编辑
- 单击块进入编辑。但点在链接、复选框、图片的链接上时，执行它们原本的操作，不进入编辑。
- 按 ⌘Enter 或 Esc，或者点到外面，都会提交并退出编辑。Esc 也是提交，不丢弃内容，和 Obsidian 的行为一致。
- 编辑中的块如果被别人从外部改了（model 在编辑期间发生了不是本输入框产生的变更）：放弃这次块编辑，重新分块，并给出提示，不能把旧内容写回去。
- 编辑中会话失效的情况都要处理：
  - 被 Agent 或文件监听重新加载；
  - 切换标签页；
  - 切到源码模式。

  处理规则：内容没冲突就先提交；有冲突就按上一条处理。
- 最后有一个「点这里添加内容」的空白区域，点了以后在文档末尾新建一个块。
- 撤销：按块编辑提交后，在预览里按 ⌘Z / ⇧⌘Z 撤销或重做 model 的改动，效果和在源码里一样。
- 块输入框里支持粘贴文件，规则和下一节一样。

## 粘贴文件
只在 Markdown 文档里生效，包括源码模式和按块编辑的输入框，并且文档不是只读。

**判断顺序**（顺序是故意的，不能改）：
1. 剪贴板里是文件（`WindowControls.readPasteboardFiles()`）：按下面的规则处理每个文件，并插入链接；多个文件之间用换行分隔。
2. 剪贴板里**只有**图片、没有文本（`readPasteboardImages()`，例如截图）：存成 `image.png`，按图片的实际格式取扩展名，并插入 `![](image.png)`。
3. 其他情况照常粘贴文本。从网页或 Word 复制时会同时带文本和图片，这时粘贴文本。

**文件放在哪**：放在文档所在目录（「旁边」）。
- 文件名保留原名；重名时改成 `name-1.ext`、`name-2.ext`，依次递增。
- 写入时如果遇到 `IdeFileExistsException`，就换下一个编号再试，不能覆盖已有文件。

**项目内的文件**（例如从 IDE 资源管理器复制的）：不复制，直接插入相对于文档的路径。
- 远程项目里剪贴板上的都是本机文件，一律读出字节再通过 `writeBytes` 上传。

**插入的链接**：
- 图片扩展名（png/jpg/jpeg/gif/webp/svg/bmp）插入 `![](path)`，其他文件插入 `[name](path)`。
- 路径有空格或括号时写成 `<path>`。
- 链接插在光标或选区的位置。先确定插入位置，再执行写文件这种异步操作；写完之后如果文档在这期间被改过，就把插入位置映射到新位置，映射不了就插在末尾并提示。

**限制**：
- 不支持粘贴文件夹（提示）。
- 单个文件超过 50MB 时先确认。
- 写入失败用 `localizedFileError` 报错，并且不插入链接。

**撤销**：⌘Z 只撤销插入的文本，已经写到磁盘的文件保留（和 VS Code 一样）。

**接入点**：
- 给 packages/bao_editor 加一个粘贴钩子（例如 `onPaste: Future<bool> Function()`，返回 true 表示已经处理，不再粘贴文本）。
- 钩子接到 `editor_surface.dart` 的 `_paste`，包括菜单「编辑 > 粘贴」和右键菜单，这几个入口都要经过它。非 Markdown 文档行为不变。
- 拖文件进 Markdown 编辑器（`FileDropRegion`，lib/chat/composer/file_drop.dart）也走同一套逻辑。插入位置在源码模式下是光标处，在预览里是当前块之后。

## 范围
**做**：上面全部内容；新增的文案同时加到 lib/l10n/app_en.arb 和 app_zh.arb，然后运行 `flutter gen-l10n`。
**不做**：
- 所见即所得的富文本编辑
- 左右分栏和滚动同步
- Mermaid 和 PlantUML 图
- 执行 HTML
- 导出 PDF
- 预览里的查找（⌘F 可以先切到源码再查找，要给出提示）
- 粘贴时图片压缩或改名对话框
- Codex 相关内容

## 建议顺序（每步都要能编译、相关测试通过）
1. 分块器和测试。
2. 抽出渲染器，加文档排版，做只读预览：模式切换、命令、记住模式、图片、链接和锚点、懒加载、选择和复制。
3. 任务列表复选框的切换，然后是按块编辑（提交、冲突、撤销）。
4. `writeBytes`：本机实现、远程 RPC 和测试。
5. 粘贴钩子、粘贴规则，再接入按块编辑的输入框和拖放。
6. l10n 收尾，跑 analyze。

## 测试（硬性约束）
- **绝对不要运行真实的 Claude Code、Codex 或真实的 ssh 连接**，只用 mock 和 fixture。不要运行带 `e2e`、`lsp-smoke` tag 的测试。
- 分块器：表驱动测试覆盖上面列出的所有边界情况。另外加一个往返检查：所有块按顺序拼起来必须和原文完全相同。
- 按块编辑：
  - 只改一块时，块外的文本保持原样（包括 CRLF 和行尾没有换行的情况）
  - 内容没变时不产生编辑
  - 编辑期间外部改了 model 的情况
  - 撤销和重做
  - 复选框切换
- 粘贴：用假的剪贴板和假的文件服务测：
  - 三种情况的判断顺序
  - 重名递增，包括写入时才发现文件已存在的竞态
  - 项目内的文件只插链接
  - 远程项目走 `writeBytes`
  - 路径有空格或括号
  - 写入失败时不插入
  - 非 Markdown 文档行为不变
- `writeBytes`：本机临时目录；远程用进程内的内存 client 和 server，复用现有的远程测试工具。
- Widget 测试：
  - 模式切换和记住模式
  - 预览显示相对路径的图片（假文件服务）
  - 锚点跳转
  - 点块进入编辑并提交
  - 只读文档不能编辑
  - 聊天 `MarkdownView` 的现有测试继续通过
- 只运行和改动相关的测试，**不要跑全量测试**（太慢）。`flutter analyze` 必须无报错。

## 工作方式约束
- 工作区是共享的，别人正在同时修改这份 checkout。**在新的 git worktree 和分支上开发**，不要碰、不要提交、不要 stash 或 reset 主工作区里别人的改动。
- 代码风格和周边保持一致：注释密度、`///` 文档注释的写法、命名、`*_io.dart` / `*_stub.dart` 的分层方式。
- 在自己的分支上分步提交，commit message 末尾加：
  `Co-Authored-By: BaoCode <noreply@baocode.dev>`

## 合并进 main（完成并通过测试后）
main 的工作区里有别人未提交的改动，`git merge` 会拒绝，**不要 stash、不要 reset --hard**：
1. 确认 main 的 HEAD 仍是本分支的基点（不是的话，先在分支上 rebase 到新的 main 并重新跑相关测试）。
2. 对双方都改过的文件，用三方 `git merge-file` 合进 main 的工作区文件；解决冲突，并确认合并期间文件没有被别人再次修改。
3. `git update-ref refs/heads/main <分支> <基点>`，然后 `git reset -q`（只重置 index）。
4. `git checkout <分支> -- <只属于自己改动或新增的文件>`，再运行 `flutter gen-l10n`。
5. 别人未提交的改动可能需要为本功能补一行，如有，要在汇报里说明。

完成后汇报：
- 做了什么、没做什么，以及原因
- 运行了哪些测试，结果如何（失败的要附上输出）
- 合并时处理了哪些文件、有哪些冲突
- 需要人工在真实环境验证的步骤：
  - macOS 和 Windows 上截图粘贴、从 Finder 和资源管理器复制文件后粘贴
  - 远程项目里的粘贴和图片预览
  - 长文档滚动
  - 中文输入法在块输入框里的表现
