# IDE 工作台架构：服务 + 注册表 + 贡献 + 界面分块

> 一句话：IDE 的状态放进各自的服务里，界面各块只订阅自己用到的服务；命令、快捷键、状态栏项、编辑器面板由各功能自己注册。`IdeWorkbenchState` 最后只负责把各块拼起来。

照搬 VS Code 的思路（`workbench/services/*`、`registerAction2`、`IContextKeyService`、`IStatusbarService`、`EditorPaneRegistry`、`IHistoryService`、`IStorageService`、`workbench/browser/parts/*`），按 Dart/Flutter 的习惯来写：

- 不用反射，也不用装饰器注入。服务的依赖在构造函数里显式传入。
- 变化通知用 `ChangeNotifier` / `ValueListenable`。界面用 `ListenableBuilder` 只重建自己那一块。
- 每个窗口一个服务容器，通过 `InheritedWidget` 交给界面。

## 1. 现状

`lib/ide/ide_workbench.dart` 一共约 7900 行，其中主文件 6135 行，另有 part 文件 `ide_workbench_keys.dart`（1489 行）和 `ide_workbench_extensions.dart`（366 行）。所有状态都是 `IdeWorkbenchState` 的私有字段：

| 功能 | 字段 / 方法（节选） |
|---|---|
| 导航 | `_backStack` `_forwardStack` `_recordNavigation` `_navigate` `_recentlyUsedStack` `_closedEditors` |
| Git / 对比 / 本地历史 | `_openChange` `_openChangeInLog` `_compareFiles` `_compareWith` `_showLocalHistory` `_writeFromDiff` `_ScmKeys` |
| 终端 | `_terminals` `_toggleTerminal` `_newTerminal` `_TerminalKeys` |
| Markdown 预览 | `_markdownSources` `_setMarkdownPreview` `_markdownPreview` |
| 调试 | `_ideDebug` `_attachDebug` `_debugCommands` |
| LSP / 符号 / 引用 / 问题 | `_languages` `_symbols` `_references` `_markers` `_PanelKeys` |
| 资源管理器 | `_explorer` `_explorerTree` `_explorerCommands` |
| 布局 | `_chatWidth` `_sidebarWidth` `_panelHeight` `_view` `_split` `_titleBar` `_activityBar` |
| 状态栏 | `_statusBar()` `_caret` `_statusMessage` |
| 快速输入 | `_quickInput` `_quickModel` `_showQuickInput` `_showQuickModel` |
| 快捷键 | `keyContext()` 的大 switch、`_commandsById` `_onWorkbenchKey` 和 chord 处理 |
| 命令 | `_workbenchCommands()`（468 行）以及各 part 里的 `_xxxCommands()` |
| 持久化 | `_restoreView()` 和 `_viewState` 在一处收集所有键 |

这样带来三个问题：

1. 任何变化都要 `setState`，整棵工作台跟着重建（共 62 处）。
2. 功能之间靠私有字段互相调用，没法单独测试，现有测试只能走 `pumpWorkbench`。
3. 对话模式的侧栏（`lib/chat/side_panel/side_panel_view.dart`）把 `ideLocalDiffFile`、写回 diff 这类逻辑又写了一遍。

## 2. 目录

```
lib/ide/workbench/
  services.dart          服务容器 WorkbenchServices + WorkbenchScope（InheritedWidget）
  context_keys.dart      ContextKeyService：上下文键
  actions.dart           WorkbenchAction + ActionRegistry：命令、快捷键、菜单
  statusbar.dart         StatusbarService：addEntry / 访问器
  storage.dart           WorkbenchStorage：各服务自己存取视图状态
  editor_panes.dart      EditorPaneRegistry：输入 → 面板
  contributions/         各功能的贡献（注册动作、状态栏项、上下文键、面板）
  parts/                 界面分块：标题栏、活动栏、侧栏、编辑区、面板、状态栏
lib/ide/services/        有状态的服务（导航、Git 改动、终端视图、Markdown 预览、调试、语言、资源管理器、布局、快速输入、编辑器）
```

## 3. 基础设施

### 3.1 服务容器

```dart
class WorkbenchServices {
  T add<T extends Object>(T service);   // 同一类型只能注册一次
  T get<T extends Object>();            // 没有就抛错
  T? find<T extends Object>();          // 可选的服务（调试、语言服务等）
  void dispose();                       // 按注册的倒序释放（ChangeNotifier / WorkbenchDisposable）
}

class WorkbenchScope extends InheritedWidget {
  static WorkbenchServices of(BuildContext context);
  static WorkbenchServices? maybeOf(BuildContext context);
}
```

- 每个窗口（即每个 `IdeWorkbench`）一个容器，在 `initState` 里按依赖顺序创建，这一步相当于 VS Code 的 `InstantiationService`，但写成显式的构造调用：

  ```dart
  final history = services.add(NavigationHistoryService(editors: editors, storage: storage));
  ```

- 容器和窗口同生命周期。换工作区（`didUpdateWidget` 里 workspace 变了）时，只有绑定工作区的服务（导航、Git 改动、资源管理器、语言等）用 `remove<T>()` 释放后重新创建，对应现在的 `_detach` / `_attach`；布局、快速输入、状态栏、注册表这些跟着窗口走，不重建。
- 界面通过 `WorkbenchScope.of(context).get<T>()` 拿服务，不经过 `IdeWorkbenchState`。

### 3.2 上下文键服务

```dart
class ContextKeyService extends ChangeNotifier {
  ContextKey<T> createKey<T>(String name, T defaultValue); // 服务自己持有并 set
  VoidCallback addProvider(ContextLookup provider);       // 算出来的键；返回 null 表示「不归我管」
  Object? getValue(String key);                           // 先查 createKey 的键，再按注册顺序问各个 provider
  ContextLookup get lookup;                               // 交给 KeybindingService.resolveEvent(context:)
}
```

- 状态在服务里的键（`canNavigateBack`、`activePanel`、`terminalCount`…）用 `createKey`，服务变化时 `set`。
- 依赖焦点的键（`editorTextFocus`、`listFocus`、`terminalFocus`…）要在按键时现场判断，用 `addProvider`。这和现在 `keyContext()` 里 `?? _xxxContextKey(key)` 的串联是同一个语义。
- 迁移期间，`IdeWorkbenchState.keyContext` 先查 `ContextKeyService`，查不到再走旧 switch。各块迁走后，旧 switch 就变空了。`keyContext` 本身作为 `@visibleForTesting` 入口保留。

### 3.3 动作注册表

对应 VS Code 的 `registerAction2`：

```dart
class WorkbenchAction {
  const WorkbenchAction({
    required this.id,                  // 命令 id，不改
    required this.title,               // 英文标题，同现在的 IdeCommand.label
    this.category,
    this.keybindings = const [],       // 目录里没有的命令才需要（见 registerExtraDefaults）
    this.palette = true,               // false：只供快捷键调用（对应现在的 _keyboardCommands）
    this.precondition,                 // bool Function(WorkbenchServices)，对应现在的 enabled
    required this.run,                 // void Function(WorkbenchServices s, Object? args)
  });
}

class ActionRegistry extends ChangeNotifier {
  VoidCallback register(WorkbenchAction action);
  VoidCallback registerAll(Iterable<WorkbenchAction> actions);
  WorkbenchAction? byId(String id);
  List<IdeCommand> commands(WorkbenchServices services, {bool palette = false});
}
```

- `run` 只能拿到服务，拿不到 `State`。需要 `BuildContext` 的（弹窗、本地化文案）通过服务里的宿主接口取，见 3.6。
- `commands()` 把动作转成现有的 `IdeCommand`，命令面板、`KeybindingService.resolveEvent(canRun:)`、`commandCatalog` 都照旧使用，快捷键解析不用改。
- **同一个 id 有多个提供者**（例如 `list.focusDown` 由资源管理器、搜索结果、问题列表分别实现）：按注册顺序取第一个，和现在 `_commandsById` 的 `putIfAbsent` 一致。所以迁移时贡献的注册顺序要和原来在 `_commandsById` 里的位置对齐。
- 菜单：本次重构不动现有菜单（右键菜单仍由各视图自己构建），`WorkbenchAction` 先不带 `menus` 字段，免得写了不用。

### 3.4 状态栏服务

对应 `IStatusbarService.addEntry`：

```dart
enum StatusbarAlignment { left, right }

class StatusbarEntry {                // 纯数据，渲染时转成 IdeStatusBarItem
  final String text; final IconData? icon; final String? tooltip;
  final String? command;              // 点击执行的命令 id（走 ActionRegistry）
  final VoidCallback? onTap; final void Function(Rect)? onTapRect;
  …                                   // 其余字段同 IdeStatusBarItem
}

class StatusbarService extends ChangeNotifier {
  StatusbarEntryAccessor addEntry(StatusbarEntry entry, String id,
      StatusbarAlignment alignment, {double priority = 0});
  List<IdeStatusBarItem> items(StatusbarAlignment alignment); // 按优先级排序，同优先级按添加顺序
}

class StatusbarEntryAccessor { void update(StatusbarEntry entry); void dispose(); }
```

- 贡献监听自己的服务，变化时调用 `accessor.update`。状态栏块只监听 `StatusbarService`，打字时不会重建别的块。
- 行列和「已选 N 行」改成编辑器状态贡献（`EditorStatusContribution`），监听 `_caret`。缩进、编码、换行符、语言模式也放在这个贡献里。
- 排序和现在一致：左侧依次是远程、调试、分支、问题、语言状态、状态消息；右侧依次是行列、缩进、编码、EOL、语言、铃铛。顺序用 priority 表达：数字大的靠左，两侧都一样（同 VS Code 的 `StatusBarItem.priority`）。

### 3.5 存储

对应 `IStorageService` 加 `onWillSaveState`：

```dart
abstract interface class WorkbenchStorageParticipant {
  void restoreState(Map<String, Object?> kept);   // 读自己的键
  void saveState(Map<String, Object?> into);      // 写自己的键
}

class WorkbenchStorage {
  VoidCallback register(WorkbenchStorageParticipant participant);
  void restore(Map<String, Object?> kept);
  Map<String, Object?> collect();
  void changed();   // 服务的状态变了：稍后保存（就是现在的 _keepViewSoon，300ms 防抖）
}
```

- **存储格式不变**：仍是同一个扁平的 JSON（`sidebarWidth`、`chatWidth`、`panelHeight`、`sidebar`、`chat`、`panel`、`view`、`search`、`markdownSource`、`gitFavoriteBranches`、`gitChangelists`、`editors`、`active`、`editorViews`）。每个服务只读写自己那几个键，用户已经存下的布局和打开的文件升级后照常恢复。
- 迁移期间，`_viewState` 写成 `{...旧的键, ...storage.collect()}`，`_restoreView` 末尾调用 `storage.restore(kept)`，某个键迁走一个就删掉旧代码里的一个。

### 3.6 宿主接口

有些服务要弹对话框、拿本地化文案、或者等编辑器把内容写回（`_flushEditor`），这些都离不开界面。做法是给它们一个窄接口 `WorkbenchHost`，由 `IdeWorkbenchState` 实现，服务通过构造函数拿到：

```dart
abstract interface class WorkbenchHost {
  BuildContext? get context;           // 本地化、showIdeDialog；没挂载时为 null
  Future<void> flushEditor();          // 编辑器里的改动写回文档
  void focusEditor();
  void report(Object error);           // 通知中心报错
}
```

这对应 VS Code 里服务依赖 `IDialogService`、`INotificationService` 的做法。只是在 Flutter 里对话框需要 `BuildContext`，所以收成一个接口。

## 4. 服务清单

| 服务 | 持有的状态 | 主要接口 | 上下文键 / 存储键 | 来源（VS Code） |
|---|---|---|---|---|
| `NavigationHistoryService` | 后退/前进栈、最近使用的编辑器栈、关掉的编辑器 | `record(location)`、`back()`、`forward()`、`canGoBack/Forward`（ValueListenable）、`forget(path)`、`reopenClosed()` | `canNavigateBack` `canNavigateForward` | `historyService.ts` |
| `GitChangesService` | 当前仓库、hunks、changelists、收藏分支 | `openChange(resource)`、`localDiffs(git, state, resources)`、`writeFromDiff`、`compareFiles`、`compareWith`、`showLocalHistory` | `gitFavoriteBranches` `gitChangelists` | git 扩展 `commands.ts`、`compareWith` |
| `TerminalViewService` | 终端集合（包装现有 `TerminalService`）、待开的终端请求 | `toggle()`、`create({profile, cwd})`、`show(task)`、`focus()`、`cycle()`、`rename()` | `terminalFocus` `terminalCount` … | `terminalService.ts`、`terminalView` |
| `MarkdownPreviewService` | 选择看源码的 md 文件（`markdownSources`） | `previewing(doc)`、`setPreview(doc, on)`、`hasPreview(doc)` | `markdownSource` | markdown-language-features `preview` |
| `DebugViewService` | 调试会话的监听 | `attach(debug)`、`detach()`、调试工具栏状态 | `inDebugMode` … | `debugService.ts` |
| `LanguageViewService` | LSP 功能、符号、编辑请求、引用、问题标记、推荐的语言服务器 | `showReferences`、`revealSymbol`、`gotoProblem`、`recommendServers` | `problemsFocus`、`referenceSearchVisible` … | `markersView`、`referencesController` |
| `ExplorerService` | `IdeExplorerController`、文件索引、时间线 | `reveal(path)`、`collapseAll()`、命令所需的当前树 | `filesExplorerFocus` `explorerViewletVisible` … | `explorerService.ts` |
| `LayoutService` | `IdeLayout`、各部分宽高、当前侧栏视图、面板最大化、焦点节点 | `showView(view)`、`togglePanel(tab)`、`focusPart(part)`、`resize` | 宽高、`view`、`sidebar` `chat` `panel`；`activeViewlet`、`panelFocus` … | `layoutService.ts` |
| `QuickInputService` | 当前的快速输入或模型 | `show(prefix)`、`pick(model)`、`close()` | `inQuickOpen` … | `quickInputService.ts` |
| `EditorService` | 包装 `IdeWorkspace` 的文档部分，外加 busy、打开选项和揭示 | `open(path, {range, focus})`、`openDiff`、`openRevision`、`select`、`close`、`active`（ValueListenable） | `editors` `active` `editorViews` | `editorService.ts` |
| 已有：`IdeNotifications` | 通知 | `notify` | | `notificationService` |
| 已有：`IdeScmSession` `IdeSearchSession` `IdeExtensionsSession` | | | `search` | |

这些服务**不依赖** `IdeWorkbenchState`，只依赖别的服务和 `WorkbenchHost`。

## 5. 贡献的写法

对应 `IWorkbenchContribution`。一个功能写一个贡献，构造时注册，`dispose` 时注销：

```dart
class NavigationContribution implements WorkbenchContribution {
  NavigationContribution(WorkbenchServices s) {
    final history = s.get<NavigationHistoryService>();
    _disposers = [
      s.get<ActionRegistry>().registerAll([
        WorkbenchAction(
          id: 'workbench.action.navigateBack',
          title: 'Go Back',
          precondition: (_) => history.canGoBack.value,
          run: (_, _) => history.back(),
        ),
        …
      ]),
      s.get<ContextKeyService>().bindListenable(
          'canNavigateBack', history.canGoBack),
    ];
  }
  late final List<VoidCallback> _disposers;
  @override
  void dispose() { for (final d in _disposers) d(); }
}
```

- 命令 id、标题、快捷键原样照搬，从旧的 `IdeCommand` 列表里**剪切**过来，不能复制一份：旧列表在前，同 id 的新动作永远不会生效。
- 快捷键：目录（`commandCatalog` / `defaultKeybindings`）里已有的命令不写 `keybindings`；只有现在用 `IdeCommand.keybindings` 带快捷键的，才原样写进 `WorkbenchAction.keybindings`。
- 贡献列表集中写在 `lib/ide/workbench/contributions/contributions.dart` 的 `createWorkbenchContributions(services)` 里，顺序就是命令的优先顺序。

## 6. 编辑器面板

对应 `EditorInput` 加 `EditorPaneRegistry`，在 `FileViews` 的基础上扩展：

```dart
class EditorPane {
  final String id;
  final bool Function(EditorPaneInput input) accepts;
  final Widget Function(BuildContext context, EditorPaneInput input) build;
}

class EditorPaneRegistry {
  void register(EditorPane pane, {int priority = 0});
  EditorPane? paneFor(EditorPaneInput input);
}
```

- 输入：`IdeDocument`（文件、diff、修订、媒体、打不开的文件），以及没有文档时的开始页和欢迎页。
- 内置面板按现在 `_editorArea` 的判断顺序注册：`FileViews` 视图（stash 等）→ 图片/媒体预览 → 打不开的占位 → Markdown 预览（`MarkdownPreviewService` 说要预览时）→ 文本编辑器（`editorBuilder` 或 `IdeEditor`）。
- `FileViews.register` 继续可用，它是注册表里的一个来源：`FileView` 被包成 `EditorPane`。stash 不用改。
- 扩展详情页保留现在的离屏页面，挂在编辑区上，不当成文档。

## 7. 界面分块

对应 `workbench/browser/parts/*`：

| 块 | 订阅 | 现在的位置 |
|---|---|---|
| `TitlebarPart` | `LayoutService`、`EditorService.active`、导航 | `_titleBar` |
| `ActivitybarPart` | `LayoutService`、SCM 计数 | `_activityBar` |
| `SidebarPart` | `LayoutService.view` | `_sidebarPart` |
| `EditorPart` | `EditorService`、`EditorPaneRegistry` | `_editorColumn` / `_editorArea` |
| `PanelPart` | `LayoutService.panel`、终端、问题 | `_panelSlot` |
| `StatusbarPart` | `StatusbarService` | `_statusBar` |

- 每块是一个独立的 widget，从 `WorkbenchScope` 取服务，用 `ListenableBuilder` 订阅。
- `LayoutService` 负责宽高、显隐和拖动（`_split` / `_Sash`）。`IdeWorkbenchState.build` 只拼装：`WorkbenchScope` → 键盘焦点 → 各块 → 通知、快速输入的浮层。

## 8. IDE 与对话侧栏共用的规则

- 侧栏和 IDE 用**同一个类**，各自用自己的依赖构造实例。例如 `GitChangesService(files:, notifications:, …)`：IDE 传入 workspace 的文件服务和通知，侧栏传入它自己的。逻辑只写一份。
- 跟布局无关的服务（Git 改动的 diff 生成和写回、本地历史、编辑器面板注册表、Markdown 预览判断）放在 `lib/ide/services/`，不能依赖工作台的布局或焦点。
- 跟 IDE 布局有关的服务（`LayoutService`、`QuickInputService`、状态栏）只在 IDE 用，侧栏不引入。
- 第一项共用的是 `ideLocalDiffFile` 那一段：生成本地改动的 diff 列表，写回出错时发通知。`side_panel_view.dart` 的 `_showLocalDiff` 和工作台的 `_openChangeInLog` 都改为调用 `GitChangesService.localDiffs`。

## 9. 迁移顺序

每一步一个 PR，新旧代码并存，每个 PR 都能单独发版：

1. 本文档。
2. 基础设施：服务容器、上下文键、动作注册表、状态栏服务、存储，并接到旧代码上（旧的 `keyContext` 和 `_commandsById` 先查新注册表，状态栏把注册的项合进去）。不搬功能。
3. 按功能整块迁：导航 → Git/SCM、对比、本地历史（含侧栏共用）→ 终端 → Markdown 预览（改为编辑器面板）→ 调试 → LSP/符号/引用/问题 → 资源管理器。
4. 编辑区：`_editorArea` 改成输入加面板注册表，`IdeWorkspace` 的文档部分升级为 `EditorService`。
5. 命令：拆掉 `_workbenchCommands` 和 keys part 文件，各功能注册自己的动作。
6. 布局：拆成界面分块加 `LayoutService`，`IdeWorkbenchState` 只剩拼装。
7. 收尾：删掉并存的旧代码和不再用的 part 文件，更新本文档。

### 兼容性检查（每步都要过）

- 命令 id、快捷键（`default_keybindings.dart`、用户的 `keybindings.json`）、`when` 里的键名不变。
- `settings.json` 的键不变（`files.autoSave`、`editor.formatOnSave`、`workbench.iconTheme` …）。
- 视图状态的 JSON 键和值格式不变。
- 每块迁移都补一份不依赖 `pumpWorkbench` 的单元测试或组件测试，放在 `test/ide/workbench/services/`。只跑与改动相关的测试。
