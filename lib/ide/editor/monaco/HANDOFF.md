# Monaco → Flutter 移植交接（2026-09-29）

## 目标、边界与当前结论

用户的目标是**在当前 Monad Flutter 仓库中完整移植 Monaco Editor**，不是另起项目、嵌入 WebView 或只复刻外观。目录采用上游相对路径 `lib/ide/editor/monaco/vs/`，Flutter 平台适配在 `lib/ide/editor/monaco/flutter/`；应用接入层是 `lib/ide/ide_editor.dart`。目标尚未完成，**不能宣称 100% 兼容**。详细的源码映射、偏差及未完成项分别见同目录的 [PORTING.md](PORTING.md) 和 [PARITY.md](PARITY.md)。

**2026-09-29 起自绘 Monaco 编辑器是 Fast IDE 默认编辑器**；`--dart-define=MONAD_NATIVE_EDITOR=false` 回退到 Flutter `TextField`（`IdeWorkbench`/`IdeEditor` 的 `nativeEditorEnabled` 参数同理）。IME、原生菜单与辅助功能仍缺平台验收，保留回退。用户已看过 macOS 实验效果并表示满意，明确要求后续**不要再观察/操作 GUI**；可以继续静态分析、自动测试及构建，但不需要重新打开预览。

## 固定上游与许可

- Monaco Editor **v0.57.0**，commit `d61824269f1377111d34306e4a47172327777083`。
- 其 `package.json` 指向 VS Code 源码 commit `6a598d4a13031703d483d103c1d934a36ad27971`。编辑器核心应对照这一版 VS Code 的 `src/vs/editor/`，而不是编译后浏览器 bundle。
- 本机可用临时 checkout：`/tmp/monad-monaco-v0.57.0` 和 `/private/tmp/monad-vscode-6a598d4a`（后者曾验证 HEAD 与工作树干净）。**这些 `/tmp` 路径非持久依赖，不要纳入仓库；换环境需按上述 commit 重新 checkout。**
- `lib/ide/editor/monaco/LICENSE.txt` 保留 VS Code MIT 许可；`assets/monaco/LICENSE.txt` 保留 Monaco 语言资源许可；译写源码保留 Microsoft 声明。不要提交完整上游树或压缩后的 JS。

## 当前工作树：交接时最重要的事

- Git 分支 `feature/ide`，当前 HEAD `a54a147931b2ea049ff8e3d4b1d4554998871a25`；**没有为这次移植创建提交**。
- `lib/ide/`、`test/ide/`、`assets/`、`test/fixtures/monaco/`、三个 `tool/generate_monaco_*.mjs` 均显示为**未跟踪**；`pubspec.yaml` 和一些 `lib/workbench.dart`、`lib/workspace/`、`lib/chat/chat_screen.dart` 文件已修改。前述目录/文件包含移植与原有用户改动，**不要 `git clean`、重置或用干净 checkout 覆盖**。
- 如果在另一个机器/隔离工作树继续，**仅切换同名分支不会带去这些未提交、未跟踪文件**；需要先安全复制完整工作树（包括未跟踪文件）或由用户明确决定如何提交/打包。没有获得提交或推送授权。

## 已有实现与入口

1. **文件、标签与原始内容**：`lib/ide/ide_workspace.dart` 持有文档、文件服务、保存基线及通知；`flutter/editor_document_model.dart` 封装 piece tree、范围编辑、原始文本和独立撤销历史。已打开的文档保留解码后 BOM、混合 CR/LF/CRLF 和 UTF-16 偏移。异步保存按调用时的文本更新基线；**不要直接换为单独的 `TextModel`**，它会规范化换行/BOM，破坏文件边界。
2. **源码移植子集**：`vs/editor/common/core/` 的 Position/Range/Selection、编辑与 EOL 原语；`model/piece_tree_text_buffer/` 的树与构造器（小编辑共享 append-only change buffer）；搜索、interval tree、`TextModel` 子集、edit stack 与 per-resource undo service；commands、view layout、diff 子集、Monarch 编译/词法与 token theme。`TextModel.bindUndoRedo(...)` 是**独立 opt-in、单资源绑定**，尚未进入应用文档。它的 EOL 分组、历史生命周期和一些事件行为与上游不同，见文件头及 PORTING/PARITY。
3. **Flutter 自绘层**：`flutter/editor_surface.dart`、`editor_surface_controller.dart` 管输入、单光标、滚动及基本语义；`viewport_layout.dart` 用精确 TextPainter 度量，跨编辑复用相同文本/样式的 shape，仍需遍历所有行重建 row 坐标，首次全异行仍需逐行 shape，不是完整虚拟化。50,001 行及几何一致性测试已加入。
4. **语法/主题**：`assets/monaco/languages/` 包含 86 种固定 grammar 变体、89 项注册，`themes.json` 包含四套内置主题；`flutter/monaco_syntax.dart` 识别路径及首行（BOM 处理），复用不变前缀及状态收敛后的后缀 token；仅实验层显示 `vs-dark` 的 token spans。语义 token、provider/workers 与完整增量 view 尚不存在。
5. **查找/替换**：`vs/editor/common/model/search/piece_tree_search.dart` 是独立的源码派生服务，提供方向查找与换行/UTF-16 映射；`vs/editor/contrib/find/browser/replace_pattern.dart` 移植替换表达式/大小写规则。`lib/ide/ide_editor.dart` 的折叠式查找栏支持大小写、全词、正则、上/下个匹配、单个/全部替换，并调用共享文档模型。这只是 Monaco FindController 的子集；Dart 与 JS 的正则/Unicode 行为仍可能不同。全量匹配高亮仍有 999 项上限，替换全部另外请求完整结果。
6. **生成工具**：`tool/generate_monaco_languages.mjs <monaco-checkout> <output-dir>`、`tool/generate_monaco_themes.mjs <vscode-checkout> <output.json>`、`tool/generate_monaco_core_fixtures.mjs <vscode-checkout> <output.json>`。脚本会核验上游 HEAD。Node 22 使用 `--experimental-transform-types`；fixture 在 `test/fixtures/monaco/core.json`，与 Dart 基础类型做对照。

## 验证基线（本次交接前）

- `flutter analyze --no-pub`：**No issues found**。
- `flutter test --no-pub --reporter expanded`：**1138 通过，1 个既有条件性测试跳过**（结尾 `+1138 ~1: All tests passed!`）。覆盖了刚增加的零宽正则导航、正则分组替换、原始 CRLF 保留、自绘编辑器替换/撤销、随机增量 token 对照等。
- `flutter build macos --debug --dart-define=MONAD_NATIVE_EDITOR=true` 曾成功，**那次构建早于最后几次查找/替换 UI 修改**；交接后的新改动若涉及 macOS，应重新构建。用户不希望再次观看 GUI，不要自动启动应用。
- 关键聚焦测试：`flutter test --no-pub test/ide/editor_status_test.dart test/ide/native_editor_integration_test.dart`；`flutter test --no-pub test/ide/editor/monaco/`；完整 suite 如上。生成资源已经纳入 `pubspec.yaml`。

## 推荐的后续路线与注意事项

1. 先读 `PARITY.md` 的功能矩阵及 `PORTING.md` 的源路径和偏差。新增源码移植时写明上游 commit/path、保留许可声明、以对应上游用例与随机边界测试验证；不要为了覆盖率制造空实现。
2. 优先建立**原始文件模型与 source-derived `TextModel` 的明确映射**：BOM、混合 EOL、UTF-16/selection、保存基线、版本/事件、decorations 与撤销组都不能丢。当前自绘控制器的 undo 在部分路径只 clamp 当前选择，未完整恢复 Monaco 的方向选择；不能直接把 `TextModel` 绑定进工作区。
3. 查找/替换尚缺完整 FindController、语言级词边界与 JS RegExp 等价、批量替换的大文件策略；自绘视图缺多光标、viewport 真正按需增量化、markers/decorations、行号与 minimap。
4. Monaco 公共独立 API、语言 providers/workers、diff editor UI、completion/hover/diagnostics、原生 IME/菜单、屏幕阅读器与跨平台验收仍是主要工程量。**绿色测试并不意味着 100% 移植**。
5. 尊重用户已有工作：任何大改之前查看 `git status`，尤其不要覆盖本分支未跟踪的 IDE 目录；用户并未授权提交/推送。项目工作应该留在此仓库，不另建独立项目。

## 2026-09-29 进展

- 光标/编辑引擎：多光标、单词/智能 Home/翻页/粘性列导航、语言感知输入（自动闭合、onEnter、缩进规则）、注释与行操作、缩进猜测、带选区恢复与输入合并的撤销（见 PORTING.md 的「2026-09-29 additions」）。
- 视图：固定行高虚拟化布局、行号槽与折叠、括号匹配、缩进参考线、多选区/光标闪烁、覆盖式滚动条与概览标尺、minimap、装饰（查找匹配）。
- Fast IDE：命令面板（⇧⌘P，含 Monaco 编辑器命令）、快速打开（⌘P，`path:line`）、转到行（⌃G）、VS Code 式标签栏与右键菜单、面包屑、Monaco 式查找控件、状态栏（选区长度、检测到的缩进、编码、EOL、语言）、资源管理器键盘导航、欢迎页、⌘B/⌘J 切换侧栏/聊天。
- 验证：`flutter analyze --no-pub` 无问题；`flutter test --no-pub` 1270 通过、1 跳过；`flutter build macos --debug` 成功（未启动 GUI）。
- 性能（JIT 测试模式，10 万行 3.8MB）：按键约 7ms；全文 Monarch 分片 tokenization 约 1.4s（6ms 切片、可取消，不阻塞 UI），增量约 28ms。

## LSP 多语言支持（2026-09-29）

- **结构**：`lib/ide/lsp/` 是通用客户端。
  - `json_rpc.dart`：Content-Length 帧、请求匹配、`$/cancelRequest`。
  - `lsp_client.dart`：单个连接，UTF-16 能力协商、动态注册、`workspace/configuration`、progress、applyEdit。
  - `lsp_manager.dart`：`LspManager`，实现 `LanguageFeatures` 与 `LanguageDocumentSync`。
  - `lsp_process*.dart`：进程、登记与清理。
  - `catalog/`：Helix 映射、文件匹配、叠加层。
  - `install/`：mason 安装器。
  - `packs/`：用户覆盖 `lsp.json` 与语言包，格式见 `packs/README.md`。
  - 编辑器界面在 `lib/ide/lsp_ui/`，只依赖接口 `lsp/language_features.dart`，测试可用 `test/ide/lsp_ui/fake_language_features.dart` 替代。
- **接入**：`main()` → `MonadApp(languagesFor: standardLspManager)` → `Workbench` → `IdeWorkspace(root, languages: …)`。
  - catalog 与 provider 在后台加载一次，所有项目共享；加载前已打开的文档在加载后由 `LspManager.reloadCatalog()` 重新匹配。
  - 工作区负责 didOpen、增量 didChange（来自 `EditorDocumentModel.changes`）、didSave、didClose；dispose 时关闭服务器。
  - 测试里的 `MonadApp()` 与 `Workbench` 默认不启用 LSP，不会拉起真实服务器。
- **进程**：`lib/platform/child_process_registry.dart` 是通用 pid 登记，`ClaudeProcessRegistry` 继承它；LSP 使用 `AppPaths.dataDir/lsp-processes.json`。
  - 启动时 `reapLspProcesses()`；退出时与 Claude 一起 `stopLspProcesses()`。
  - 只清理命令行仍匹配、且父进程为 1 或本进程的条目。
  - 只杀直接子进程，没有 process group；孙进程靠管道关闭或 initialize 的 `processId` 自行退出。
- **生命周期**：服务器按"工作区文件夹（rootMarkers）× 服务器"共享，打开文件时启动，无文档 5 分钟后关闭。
  - 崩溃后按 1s 起、翻倍、最多 30s 的退避重启；3 分钟内崩溃 5 次则 failed，状态栏点击重试。
  - 找不到可执行文件时为 missing，可安装时状态栏一键安装；缺运行时（node/python3/go/cargo…）会明确提示。
- **生成与许可**：
  - `node tool/generate_lsp_languages.mjs [helix-checkout|languages.toml] [out-dir] [--mason registry.json(.zip)]`，固定 Helix `ba40e547426b0f9896c8bdc699a4ab11f2b37dbc`。
  - `node tool/generate_mason_registry.mjs [registry.json(.zip)] [out-dir]`，固定 mason-registry `2026-09-29-glass-hat`（`27cabd46dfb4e97187a4619d7de966589e3945f7`）。
  - 无参数时下载固定版本到 /tmp；先跑 languages，再跑 mason。
  - 许可声明：`assets/lsp/LICENSE-helix`（MPL-2.0）、`assets/lsp/LICENSE-mason-registry`（Apache-2.0）。
- **验证（2026-09-29）**：
  - `flutter analyze --no-pub` 无问题。
  - `flutter test --no-pub` 1457 通过、2 跳过（`e2e`、`lsp-smoke` 标签）。
  - 冒烟测试 `flutter test --no-pub --run-skipped -t lsp-smoke`（本机 dart 3.13.4 language-server）通过：服务器约 0.2s 就绪；诊断 invalid_assignment 与 unused_local_variable；hover `void print(Object? object)`；定义；补全 75 项；重命名 2 处编辑；符号 `main, Spaced`；格式化 3 处编辑；无残留进程。
  - `flutter build macos --debug` 成功（未启动 GUI）。
- **注意**：
  - 文档路径按 `p.normalize(p.absolute())` 做键，未解析符号链接；服务器返回 realpath URI（如 `/private/var`）时，诊断会落到另一路径。
  - 只监听项目根做 didChangeWatchedFiles。
  - `lsp_manager_test` 的空闲关闭用例在全量高负载下曾偶发超时，单独运行稳定。

## 图标、悬浮提示与编辑器选择（2026-09-30）

- **图标**：Fast IDE 全部改用 VS Code 的 Codicons。
  - 字体来自 VS Code 固定版本 package-lock 里锁定的 `@vscode/codicons@0.0.46-40`（CC-BY-4.0，见 `assets/codicons/LICENSE`）。
  - `node tool/generate_codicons.mjs <vscode-checkout> <codicons-package> assets/codicons lib/theme/codicons.dart` 生成字体副本和 `Codicons` 常量（名称取自 `codiconsLibrary.ts` 与 `codicons.ts`）。
  - 补全和符号的图标、颜色按 `languages.ts` 与 `symbolIcons.ts` 对应。
  - release 构建会裁剪字体，所以 `IconData` 必须是 const。
- **悬浮提示**：`lib/ide/ide_hover.dart` 基于 `RawTooltip` 实现 VS Code 的 workbench hover。
  - 样式、延迟、指针与 VS Code 一致：Dark 2026 配色（2026-09-30 晚改，见下节），紧凑样式 12px，延迟 macOS 1500ms、其他平台 500ms，活动栏和状态栏带指针。
  - `IdeActionButton` 是动作栏按钮（22px、`toolbar.hoverBackground`）。
  - IDE 内不再使用 Material 的 `Tooltip` 和 `IconButton`。
  - `find.byTooltip` 仍可用。
- **编辑器选择**：`Editor.fastIde` 成为标题栏下拉中的一个选项，选中后会记住；主按钮切换到 IDE 布局。`openInEditor` 不会启动它。
- **返回聊天**：标题栏右侧的 `BackToChatButton`（`lib/workspace/back_to_chat_button.dart`）是带图标的实心 `IdeButton`，高 22px。macOS 下位于 IDE 自己的标题栏；Windows 下位于应用绘制的 header，在窗口按钮左侧。IDE 模式下 Windows header 使用 IDE 的底色，没有下边线，左侧不再显示返回聊天的小图标。活动栏底部不再有返回聊天项。
- **布局开关**：聊天和 IDE 的侧边栏开关都用 VS Code 的布局图标（`Codicons.layoutSidebarLeft`/`layoutSidebarLeftOff`，图标表示当前是否打开）。macOS 的 IDE 标题栏去掉了 “Fast Ide” 文字，主侧边栏开关放在红绿灯右侧，面板和聊天的开关仍在右侧。Windows header 的侧边栏开关在菜单栏之后；IDE 模式下它切换 IDE 的主侧边栏，状态放在 `IdeWorkspace.sidebarShown`，IDE 和 header 共用。
- **release 修复**：`FileIcon` 不再给 `SvgPicture.asset` 传 `bundle:`。flutter_svg 会把 loader 发到 isolate，带缓存的 bundle 在 release 下无法发送，导致文件图标全空。已加 isolate 可发送性的回归测试。
- **release 打开文件闪退（已修复）**：Dart 3.13.4 的 AOT 编译器会把循环里只靠布尔局部变量提升的可空字段读取（原 `tokenizeIncremental` 中的 `if (reusable && …) previous.…`）提到循环外无条件执行。`previous` 为 null 时就会读到地址 0xf，触发 SIGSEGV；JIT（debug）下不会出现。
  - 现在可复用的数据先放进普通局部变量，循环里不再读取可空对象。
  - 已在 `dart compile exe` 的独立程序中复现并验证修复。
  - 新代码不要在带 `await` 的循环里依赖"布尔变量提升"来访问可空对象。

## Modern UI 与编辑器悬浮框（2026-09-30）

- **起因**：VS Code 1.139/1.140 默认开启 Modern UI（`workbench.experimental.modernUI`），默认主题为 Dark 2026。此前按经典布局和 Dark Modern 实现，所以活动栏、侧边栏和悬浮框看起来都不对。
- **布局**：`lib/ide/ide_modern_ui.dart` 移植了 Modern UI 的卡片布局（`floatingPanels.css`、`modernUI/browser/media/activityBar.css`、`sashHandles.css`，以及 `activitybarPart.ts` 的浮动尺寸）。
  - 活动栏、侧边栏、编辑器、聊天都是圆角 8 的卡片，1px `surface.border` 边框。
  - 卡片间距 4px；离窗口两侧和状态栏也是 4px。
  - 活动栏卡片宽 44，项 36px，间隔 8，图标 24px。选中项和悬停项的背景是 32px、圆角 4 的方块，没有左侧竖线。
  - 侧边栏在左侧与活动栏相接（接缝是活动栏的边框）；侧边栏隐藏时，活动栏四角都是圆角。
  - 分隔条静止时显示三个 2px 的点，悬停或拖动时整条填 `sash.hoverBorder`。
  - 只实现默认密度，不含 compact。
- **列宽与分隔条**：`lib/ide/ide_columns.dart` 按 VS Code grid（`splitview.ts`）分配侧边栏、编辑器、聊天三列的宽度。
  - 各列最小宽度：侧边栏 170、编辑器 320、聊天 360。各列没有最大宽度。
  - 窗口变窄时，先缩聊天到最小宽度，再缩侧边栏到最小宽度，然后隐藏侧边栏。聊天始终在右侧，不再有窄窗口下把聊天放到底部的布局。
  - 分隔条拖过编辑器的最小宽度后，会继续挤压另一侧的列。拖回原处时，被挤压的列恢复原宽度（按拖动开始时的宽度计算）。
  - 另一侧的列被挤到最小宽度后，再往前拖超过它最小宽度的一半，它会吸附隐藏，被拖的列跟随指针变宽。拖回来时它重新显示（VS Code `splitview.ts` 的 `snapAfter`/`snapBefore`）。拖动过程中始终用拖动开始时的可用宽度计算，因为聊天隐藏后会连带去掉窗口边上的 4px 间隙。
  - 拖到本列最小宽度的一半以下会吸附隐藏，再拖出超过一半时显示。拖动隐藏后，⌘B/⌘J 按隐藏前的宽度重新打开。列隐藏时，它的分隔条就是窗口边缘那 4px 间隙，可以从这里拖出来。
  - 光标表示分隔条能移动的方向：两边都能动时为 `resizeColumn`，只能向左时为 `resizeLeft`，只能向右时为 `resizeRight`（对应 VS Code 的 `.minimum`/`.maximum`）。拖动时在 Overlay 上盖一层遮罩，所以指针越过分隔条后光标保持不变。
  - 双击分隔条会显示对应的列，并恢复默认宽度（侧边栏 240，聊天 420）。
- **悬浮框**：`lib/ide/lsp_ui/hover_markdown.dart` 按 VS Code 编辑器悬浮框渲染 Markdown，参考 `hoverWidget.css`、`hover.css`、`hoverContribution.ts` 和 `editorMarkdownCodeBlockRenderer.ts`。
  - 代码块用编辑器的 Monarch 语法和主题上色：语言取代码块标注（按 id 或别名，大小写不敏感，见 `MonacoLanguageAssets.languageIdForName`），没有标注时用当前编辑器的语言。
  - 代码块不显示语言标签，也不加外框。
  - 行内代码使用 `textCodeBlock.background`，圆角 3。
  - `---` 是贯穿整个悬浮框的半透明分隔线；诊断各自一行，行间有同样的分隔线。
  - 字号和行高跟随编辑器（13 / 1.45）。
  - 签名帮助和补全详情用同一个渲染器。
  - 不支持：状态栏动作行（View Problem / Quick Fix）；表格和 HTML 按纯文本显示。
- **配色**：悬浮框、编辑器小部件、动作按钮（`icon.foreground` #8C8C8C）都改为 Dark 2026。编辑器 token 配色仍用 `vs-dark`。
- **图标粗细**：用 headless Chrome（VS Code 所用的 Chromium）和 Flutter 以同样条件渲染 codicon（24px、#8C8C8C、2x），着色覆盖量几乎相同（如 803 与 805）。显得粗是颜色和经典样式造成的，不是光栅化问题，所以仍用字体渲染。

## 侧边栏、超长行与编辑器外围（2026-09-30）

对照 VS Code 1.140（`6a598d4a`，Modern UI + Dark 2026）完成的内容，每个文件的头注释都写明了出处和偏差：

- **超长行**：移植 `editor.stopRenderingLineAfter`（默认 10000）。超出部分不参与排版和绘制，行尾显示 "Show more (…)" 胶囊（`viewport_layout.dart`、`editor_surface.dart`）。
- **无法打开的文件**：二进制、过大或读取失败的文件以标签页形式打开，内容区是 VS Code 的占位编辑器（`ide_editor_placeholder.dart`），不再显示顶部错误条。
- **语言服务器推荐**：改为右下角通知（`ide_notifications.dart`），不再放在状态栏。
- **右键菜单**：`ide_menu.dart` 自绘，分组、快捷键标注、子菜单与 VS Code 原生菜单一致。
  - 已覆盖：标签页、编辑器、资源管理器、源代码管理（资源、分组、标题的 `…`）、图表、时间线、搜索结果。
- **资源管理器**：视图标题为 "Explorer"，下分 Folders、Outline、Timeline 三个 pane（`ide_panes.dart`）。
  - 大纲移入 pane；活动栏去掉了 Outline 和 Run and Debug（不实现调试）。
  - 文件树（`ide_explorer.dart`）：
    - Git 装饰：颜色、删除线、字母，文件夹用圆点。
    - 内联新建/重命名，名称校验文案与 VS Code 相同；支持 `a/b/c` 这样的嵌套路径。
    - 删除确认：有废纸篓（macOS）时移到废纸篓，否则永久删除；有未保存修改时另行提醒；废纸篓失败时询问是否永久删除。
    - 剪切/复制/粘贴：同名时按 `incrementFileName` 的 simple 规则命名。
    - Reveal in Finder、Copy Path / Copy Relative Path、Find in Folder...
    - 快捷键：mac 下 Enter 重命名、⌘Backspace 删除；其他平台 F2、Delete。
  - 重命名或移动的文件，已打开的编辑器会跟随到新路径（`IdeWorkspace.moved`）；删除时关闭没有未保存修改的编辑器。
- **源代码管理**：`lib/ide/git/`，只通过 `git` 进程访问（`IdeGitService`）。
  - Changes：提交输入框与提交分割按钮、Merge/Staged/Changes 分组、行内动作和菜单。
  - 默认树视图（`scm_tree.dart`）：
    - 单子文件夹链压缩成一行（`scm.compactFolders`），文件夹在前，按 `compareFileNames` 排序。
    - `···` → View & Sort 可切换为列表视图；列表视图下可按 Name / Path / Status 排序。
    - 文件夹行也有 Stage / Unstage / Discard 动作；分组的右键菜单有 Collapse All。
  - Generate Commit Message（输入框右侧的 ✦，`commit_message.dart`）：
    - 通过 `claude -p --model haiku` 调用 Claude Haiku：不带工具、MCP 和斜杠命令，不保存会话，在临时目录运行（不读项目的 CLAUDE.md）。
    - 输入：有暂存时取暂存的 diff，否则取全部改动（包括未跟踪文件）；附带最近 10 条提交的标题，用来沿用仓库的提交风格；再附上改动文件列表。
    - diff 最多 40k 字符：lock 文件和生成文件只保留头部；其余文件从小到大能完整放下的就完整放，剩余额度由大文件均分，在行尾截断并注明省略了多少行。
    - 生成过程中再点一次即取消，输入框保留原内容。
  - 智能提交、Undo Last Commit、Discard（未跟踪文件进废纸篓）、Add to .gitignore。
  - Graph：泳道绘制移植 `scmHistory.ts`；引用徽标、提交展开后显示改动文件、自动加载更多。
  - 动画（`ide_animated_list.dart` 的 `IdeAnimatedList`，Graph 和 Changes 共用）：
    - 按 key 比较前后两次的行：新行从 0 高度展开，删除的行在原位置收起，其余行随之移动，保留状态。
    - 首次构建、大部分行同时变化（如切换视图模式）或系统要求减少动效时，直接显示，不做动画。
    - 刷新和加载更多时保留旧的 Graph 直到新数据到达（`IdeGitRepository` 的 `_graphStale`），不再清空后重建。
  - 活动栏显示待处理数量徽标。
- **时间线**：`git/ide_timeline_view.dart`，数据来自 Git provider。
  - 内容：提交、作者、相对时间（相同时间显示为细线）；文件已暂存时首项为 "Staged Changes"。
  - 操作：Pin、Refresh。
- **搜索**：`lib/ide/search/`。
  - 输入：Match Case、Whole Word、Regex；替换支持 Preserve Case 和 Replace All（带确认）；可设置 files to include / exclude，并可关闭 "Use Exclude Settings and Ignore Files"。
  - 结果：按文件分组，显示计数，匹配有预览；支持单项替换和 Dismiss；消息文案与 VS Code 相同。
  - 引擎（`text_search_io.dart`）在后台 isolate 中运行：仓库内用 `git ls-files --cached --others --exclude-standard` 获取文件列表，因此遵循 `.gitignore`；仓库外遍历目录，并应用默认排除项。跳过二进制文件；最多返回 20000 个结果。
  - 旧的 `ide_tools_panel.dart` 已删除。
- **扩展**：`lib/ide/extensions/`，把语言服务器套进 VS Code 的扩展视图。
  - 顶部是搜索框 "Search Extensions in Marketplace"，下面是 Installed 和 Recommended 两个 pane，带计数徽标。
  - 搜索时合并成一个列表，标题为 "Extensions: Marketplace"；支持 `@installed` 和 `@recommended` 过滤。
  - 每行 72px：图标、名称、描述、发布者，以及 Install 按钮或 Manage 齿轮菜单（Uninstall、Copy、Copy Extension ID）。
  - 数据来自标准 LSP 目录和 mason：在 PATH 上找到的算已安装，但不能卸载；装在应用目录里的可以卸载；有 mason 包的可以安装；都没有的会说明原因。
  - Recommended 列出打开文件缺少的服务器；安装后会重启对应的服务器。
  - 快捷键 ⇧⌘X。
- **Pane**（`ide_panes.dart`）：
  - 展开和折叠有 0.15s 过渡；body 始终保持同一棵 widget 树，动画结束时不会丢失状态。
  - 标题先占位，描述用剩余空间，右侧的动作按钮贴边对齐（之前 Graph 的动作按钮没有贴右边）。
  - 打开 pane 里的菜单时，头部按钮保持显示。
  - 菜单与按钮左对齐，放不下时改为右对齐。
- **拖动分隔条**：按按下时的位置计算，与主窗口相同。拖过最小/最大值后往回拖，不必等指针回到分隔线上才跟随。
- **输入框**（`ide_input.dart`）：
  - 光标高度按字号计算（约 1.2 倍，与浏览器一致），不再占满整行（`ideCaretHeight`）。
  - 文字按 CSS 的 half-leading 在行内垂直居中（`TextLeadingDistribution.even`），与光标对齐。
  - 固定 `VisualDensity.standard`：macOS 默认的 compact 密度会吃掉内边距，使输入框变矮、文字和光标偏移。
  - 多行输入超出时滚动，但不显示滚动条（与 VS Code 一致）。
  - 多行输入放在自己的滚动视图里并套上 `WheelLatch`（与 chat 相同的规则）：在输入框内开始的滚轮手势只滚动输入框，到头也不会带动外面的列表；从外面开始的手势经过输入框时继续滚动外面。
  - 右侧开关按钮与第一行文字垂直居中；与右边框的间距按 VS Code（`.controls` 为 1px，SCM 工具栏为 3px）。
  - 搜索和替换输入框的上下内边距为 3px，比其他输入框矮 2px（26px）；Toggle Search Details 为 25×16，图标 16px，没有背景。
- **快捷键标注与状态栏**：mac 下写 Enter、Tab、Escape、Backspace，不用 ↩ ⇥ ⎋ ⌫，这些符号会被渲染成 emoji。问题计数改用 codicon（`$(error) 1 $(warning) 0`）。
- **偏差**：
  - 没有 diff 编辑器：资源、时间线、提交的文件都打开当前文件。
  - 没有 push、pull、sync、stash、分支命令。
  - 智能提交的 Always/Never 只在当前会话内有效。
  - 不支持多选。
  - 搜索不跨行匹配，没有搜索编辑器和历史。
  - 扩展视图没有扩展详情编辑器，点击只会选中；列表中的版本号显示在安装数的位置。
- **测试**：
  - 单元测试：`test/ide/git/`（`FakeGit` 不启动进程；`git_service_test` 在临时仓库中运行真实 git）、`test/ide/search/`（引擎在临时目录上测试）、`test/ide/extensions/`（mason 在临时目录中运行，PATH 是假的）。
  - 提交信息生成只用假模型测试：`pumpWorkbench` 默认注入一个会抛异常的模型，测试中不会调用真实的 Claude Code。
  - 组件测试：`test/ide/workbench/explorer_ops_test.dart`。
