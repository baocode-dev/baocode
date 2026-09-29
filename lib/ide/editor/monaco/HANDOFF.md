# Monaco → Flutter 移植交接（2026-09-29）

## 目标、边界与当前结论

用户的目标是**在当前 Monad Flutter 仓库中完整移植 Monaco Editor**，不是另起项目、嵌入 WebView 或只复刻外观。目录采用上游相对路径 `lib/ide/editor/monaco/vs/`，Flutter 平台适配在 `lib/ide/editor/monaco/flutter/`；应用接入层是 `lib/ide/ide_editor.dart`。目标尚未完成，**不能宣称 100% 兼容**。详细的源码映射、偏差及未完成项分别见同目录的 [PORTING.md](PORTING.md) 和 [PARITY.md](PARITY.md)。

实验性自绘编辑器通过 `--dart-define=MONAD_NATIVE_EDITOR=true` 开启；**默认仍是 Flutter `TextField`**，不要在未完成 IME、辅助功能、原生菜单、多光标和性能验证前切换默认值。用户已看过 macOS 实验效果并表示满意，明确要求后续**不要再观察/操作 GUI**；可以继续静态分析、自动测试及构建，但不需要重新打开预览。

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
