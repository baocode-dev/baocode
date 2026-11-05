# IDE 工作台架构：服务 + 注册表 + 贡献 + 界面分块

> 一句话：IDE 的状态放在各自的服务里，界面各块只订阅自己用到的服务；命令、快捷键、上下文键、状态栏项、编辑器面板由各功能自己注册。`IdeWorkbenchState` 只负责建服务、把应用给的选项交给它们、拼装界面各块。

照搬 VS Code 的思路（`workbench/services/*`、`registerAction2`、`IContextKeyService`、`IStatusbarService`、`EditorPaneRegistry`、`IHistoryService`、`IStorageService`、`IQuickAccessRegistry`、`workbench/browser/parts/*`），按 Dart/Flutter 的习惯来写：

- 不用反射，也不用装饰器注入。服务的依赖在构造函数里显式传入。
- 变化通知用 `ChangeNotifier` / `ValueListenable`。界面用 `ListenableBuilder` 只重建自己那一块。
- 每个窗口一个服务容器，通过 `InheritedWidget`（`WorkbenchScope`）交给界面。

## 1. 重构前后

重构前，`lib/ide/ide_workbench.dart` 主文件 6135 行，另有 part 文件 `ide_workbench_keys.dart`（1489 行）和 `ide_workbench_extensions.dart`（366 行），所有状态都是 `IdeWorkbenchState` 的私有字段。这带来三个问题：

1. 任何变化都要 `setState`，整棵工作台跟着重建（共 62 处）。
2. 功能之间靠私有字段互相调用，没法单独测试，测试只能走 `pumpWorkbench`。
3. 对话模式的侧栏（`lib/chat/side_panel/side_panel_view.dart`）把 `ideLocalDiffFile`、写回 diff 这类逻辑又写了一遍。

重构后：

- `ide_workbench.dart` 966 行。其中 `IdeWorkbench` 这个 widget 的选项约 215 行，`IdeWorkbenchState` 557 行（建服务约 185 行），`_Host` 约 105 行。两个 part 文件已删除。
- 根部只剩两处 `setState`：`settings.json` 重新读入（很少发生，且到处都读设置），以及语言名表第一次载入。
- 各服务、贡献、界面块都有不走 `pumpWorkbench` 的测试（`test/ide/workbench/services/`、`test/ide/workbench/parts/`）。
- 对话侧栏和 IDE 用同一个 `GitChangesService` 生成本地改动的 diff 并写回。

## 2. 目录

```
lib/ide/workbench/
  services.dart          服务容器 WorkbenchServices + WorkbenchScope；WorkbenchDisposable
  contributions.dart     WorkbenchContribution、WorkbenchRegistrations、WorkbenchHost（宿主接口）
  environment.dart       WorkbenchEnvironment：服务要用的应用选项（settings、颜色主题、宿主命令）
  options.dart           WorkbenchOptions：界面块要用的应用选项（IdeWorkbench 实现它）
  style.dart             WorkbenchStyle：islands、gap、sashWidth
  context_keys.dart      ContextKeyService：上下文键
  actions.dart           WorkbenchAction + ActionRegistry：命令、快捷键
  statusbar.dart         StatusbarService：addEntry / addEntries / 状态消息
  storage.dart           WorkbenchStorage：各服务自己存取视图状态，并负责何时保存
  editor_panes.dart      EditorPaneRegistry：文档 → 面板
  quick_access.dart      QuickAccessRegistry：快速输入的前缀 → 提供者
  views.dart             IdeSideView 等视图枚举
  workspace_binding.dart WorkspaceBinding：服务挂到工作区上、换工作区时卸下
  contributions/         各功能的贡献（注册动作、上下文键、状态栏项、面板、快速访问）
  parts/                 界面分块
lib/ide/services/        有状态的服务（见第 4 节）
```

## 3. 基础设施

### 3.1 服务容器

```dart
class WorkbenchServices {
  T add<T extends Object>(T service);           // 同一类型只能注册一次
  T get<T extends Object>();                    // 没有就抛错
  T? find<T extends Object>();                  // 可选的服务（导航历史在换工作区时短暂没有）
  void remove<T extends Object>({bool owned});  // 绑定工作区的服务，换工作区时移除
  void dispose();                               // 按注册的倒序释放（ChangeNotifier / WorkbenchDisposable）
}

class WorkbenchScope extends InheritedWidget {
  static WorkbenchServices of(BuildContext context);
  static WorkbenchServices? maybeOf(BuildContext context);
}
```

- 每个窗口（即每个 `IdeWorkbench`）一个容器，在 `IdeWorkbenchState._createServices` 里按依赖顺序显式构造，相当于 VS Code 的 `InstantiationService`。
- 容器和窗口同生命周期。换工作区时只有 `NavigationHistoryService` 和工作区本身（`IdeWorkspace` 也登记在容器里）被移除再加回；其余服务由 `WorkspaceBinding` 调它们的 `attach` / `detach`（见 3.7）。
- 界面通过 `WorkbenchScope.of(context).get<T>()` 拿服务，不经过 `IdeWorkbenchState`。

### 3.2 上下文键服务

```dart
class ContextKeyService extends ChangeNotifier {
  ContextKey<T> createKey<T>(String name, T defaultValue);    // 服务持有，状态变时 set
  VoidCallback bind<T>(String name, ValueListenable<T> value); // 跟着一个 ValueListenable
  VoidCallback addProvider(ContextLookup provider);           // 现算的键；返回 null 表示「不归我管」
  Object? getValue(String key);                               // 先查 createKey/bind 的键，再按注册顺序问 provider
}
```

- 原来 `keyContext()` 的大 switch 已经拆光：每个贡献用 `addProvider` 回答自己的键（`terminalFocus`、`listFocus`、`searchViewletFocus`…）。依赖焦点的通用键（`editorTextFocus`、`inputFocus`、`textInputFocus`…）在 `FocusKeysContribution` 里，它排在最后，最后再问文本编辑器自己的键。
- `IdeWorkbenchState.keyContext` 只是 `ContextKeyService.getValue` 的 `@visibleForTesting` 入口。

### 3.3 动作注册表与命令服务

对应 VS Code 的 `registerAction2`：

```dart
class WorkbenchAction {
  const WorkbenchAction({
    required String id,           // 命令 id，不改
    required String title,        // 英文标题
    required void Function(WorkbenchServices s, Object? args) run,
    String? category,
    List<IdeKeybinding> keybindings = const [], // 默认快捷键表里没有的命令才写
    bool palette = true,          // false：只供快捷键调用（列表、视图里的键）
    bool Function(WorkbenchServices s)? precondition,
    bool takesArgs = false,       // 快捷键的 args 要传给 run
    String Function(WorkbenchServices s)? titleFor, // 开关类命令的动态标题
  });
  factory WorkbenchAction.catalog(String id, {...}); // 标题和分类取 commandCatalog 的
}

class ActionRegistry extends ChangeNotifier {
  VoidCallback register(WorkbenchAction action);
  VoidCallback registerAll(Iterable<WorkbenchAction> actions);
  WorkbenchAction? byId(String id);             // 同 id 取先注册的
  List<IdeCommand> commands(WorkbenchServices s, {bool palette = false});
}
```

- `run` 只拿到服务，拿不到 `State`。需要 `BuildContext` 的（弹窗、本地化文案）通过 `WorkbenchHost.context` 取，见 3.6。
- `CommandService`（`lib/ide/services/commands.dart`）在注册表之上加「来源」：文本编辑器自己的命令、应用给的宿主命令按 `addSource` 接进来。`palette()` 给命令面板，`byId()` 给快捷键分发，`runById` 给菜单和宿主；`recent` 记最近运行的命令。
- **同一个 id 有多个提供者**：按注册顺序取第一个。贡献的顺序在 `contributions/all.dart` 的 `createWorkbenchContributions` 里，就是命令的优先顺序。
- `KeybindingDispatchService`（`lib/ide/services/keybindings.dart`）接管按键：早、晚两个 `FocusManager` 处理器，chord 状态和提示，终端里哪些键交给 shell。
- 菜单：右键菜单仍由各视图自己构建，`WorkbenchAction` 不带 `menus` 字段。

### 3.4 状态栏服务

对应 `IStatusbarService.addEntry`：

```dart
class StatusbarService extends ChangeNotifier {
  StatusbarEntryAccessor addEntry(String id, StatusbarAlignment alignment,
      StatusbarEntryBuilder build, {double priority = 0, Listenable? changes});
  StatusbarEntryAccessor addEntries(...); // 一组项（语言状态每项一个）
  List<(double, IdeStatusBarItem)> entries(BuildContext context, StatusbarAlignment alignment);
  void setMessage(String? message, {Duration? hideAfter}); // chord、命令的提示
}
```

- 项是现建的（builder 拿 `BuildContext`，文案本地化），`changes` 变了状态栏重建；状态栏块只订阅它关心的东西（见第 7 节），打字时不重建别的块。
- 行列和「已选 N 行」、缩进、编码、换行符、语言模式是 `EditorStatusContribution` 的项。
- 顺序用 priority 表达，数字大的靠左：左侧远程 100、调试 90、分支 80、问题 70、语言状态 60、状态消息 50；右侧行列 100 … 铃铛 -1000。远程、状态消息、铃铛由 `parts/status_bar.dart` 按这些 priority 合进去。

### 3.5 存储

对应 `IStorageService` 加 `onWillSaveState`：

```dart
abstract interface class WorkbenchStorageParticipant {
  void restoreState(Map<String, Object?> kept);   // 读自己的键
  void saveState(Map<String, Object?> into);      // 写自己的键
}

class WorkbenchStorage implements WorkbenchDisposable {
  WorkbenchStorage({VoidCallback? onChanged, ValueChanged<Map<String, Object?>>? Function()? save});
  VoidCallback register(WorkbenchStorageParticipant participant);
  void restore(Map<String, Object?> kept);
  Map<String, Object?> collect();
  void changed();                       // 某个服务的状态变了：300ms 后保存
  void holdWhile(Future<void> restoring); // 上次的编辑器重新打开期间不保存
  void keep();                          // 立刻保存（应用退到后台、窗口关闭）
}
```

- **存储格式不变**：仍是同一个扁平的 JSON，`IdeWorkbench.viewState` / `onViewState` 不变。各服务的键：
  - `LayoutService`：`sidebarWidth` `chatWidth` `panelHeight` `view`，以及工作区 `IdeLayout.toJson()` 的显隐键（`sidebar` `chat` `panel` 等）；
  - `ScmService`：`gitFavoriteBranches` `gitChangelists`；
  - `SearchViewService`：`search`；
  - `MarkdownPreviewService`：`markdownSource`；
  - `EditorService`：`editors` `active` `editorViews`（最后注册，其余恢复后再打开编辑器）。
- 什么时候保存也归存储管：同样的 JSON 不重复保存；编辑器滚动、光标移动停下 1 秒后才保存（`EditorService.viewChanged`）。`IdeWorkbenchState` 不再收集任何键。

### 3.6 宿主接口与应用选项

服务要弹对话框、拿本地化文案、把编辑器里的改动写回文档，这些离不开界面。做法是给它们一个窄接口 `WorkbenchHost`，由 `IdeWorkbenchState` 里的 `_Host` 实现：

```dart
abstract interface class WorkbenchHost {
  BuildContext? get context;           // 本地化、showIdeDialog；没挂载时为 null
  Future<void> flushEditor();
  void focusEditor();
  void report(Object error);           // 通知中心报错
  void focusSoon();
  bool executeCommand(String id, [Object? args]);
  ...                                  // 打开文件 / 位置、显示视图、显示快速输入模型、聚焦面板
}
```

应用给窗口的选项分两份：服务要用的放 `WorkbenchEnvironment`（`settings`、`colorThemes`、`hostCommands`，也由 `_Host` 实现）；界面块要用的放 `WorkbenchOptions`（工作区、项目、对话、编辑器构造器、提交信息模型、最近的文件夹……），`IdeWorkbench` 本身实现它，界面块构造时拿到。

### 3.7 工作区绑定

`WorkspaceBinding`（对应工作台跟着 `IWorkspaceContextService` 换文件夹，以及 `IEditorService.onDidActiveEditorChange` 的监听者）：

- `attach(workspace)`：资源管理器、语言、SCM、布局、调试、终端根目录挂到工作区上，建这个工作区的 `NavigationHistoryService`。
- 工作区变化时通知各服务：文件夹变了（资源管理器、SCM、终端根目录），文档变了（语言、导航、搜索、自动保存），打字（语言、自动保存、搜索）。
- 前台编辑器换了：自动保存 `onFocusChange`、记导航、显示编辑区、从 Git 日志的位置回到资源管理器、资源管理器跟随。
- `detach()`：全部卸下。`IdeWorkbenchState.didUpdateWidget` 换工作区时 `detach` 再 `attach`。

## 4. 服务清单

| 服务 | 持有的状态 | 主要接口 | 来源（VS Code） |
|---|---|---|---|
| `NavigationHistoryService` | 后退/前进栈、最近使用的编辑器、关掉的编辑器 | `navigate(back:)`、`record`、`reopenClosed` | `historyService.ts` |
| `ScmService` | 当前仓库、SCM 会话、hunks、changelists、收藏分支、Git 日志 | `openChange`、`compareWith`、`showHistory`、`leaveGitLog` | git 扩展 `commands.ts` |
| `GitChangesService` | 无（文件服务、通知、可选的工作区） | `localDiffs`、`write` | git 扩展 |
| `TerminalViewService` | 终端集合（包装 `TerminalService`）、显示的后台任务 | `show`、`create`、`openIn`、`selectDefaultProfile` | `terminalService.ts` |
| `MarkdownPreviewService` | 看源码的 md 文件 | `hasPreview`、`previewing`、`setPreview`、`drops`、`pasteInEditor` | markdown-language-features |
| `DebugViewService` | 调试器（给的或工作区的） | `attach`、`detach`、`toggleRepl`、`runAndDebugKey` | `debugService.ts` |
| `LanguageService` | LSP 功能、符号、推荐的语言服务器 | `attach`、`documentChanged`、`revealSymbol`、`symbolPath`、`recommendServers` | `languageStatus`、`outline` |
| `ProblemsService` / `ReferencesService` | 问题列表、引用结果 | `gotoProblem`、`show`、`list` | `markersView`、`referencesController` |
| `ExplorerService` / `ListService` | `IdeExplorerController`、面板开合；当前有焦点的列表 | `reveal`、`follow`、`rootsChanged` | `explorerService.ts`、`listService.ts` |
| `LayoutService` | 侧栏视图、宽高、面板最大化、各块焦点节点；显隐跟 `IdeLayout` | `showView`、`togglePanel`、`focusPanel`、`resized` | `layoutService.ts` |
| `QuickInputService` | 快速输入的文字、模型 | `show(prefix)`、`showModel`、`quickNavigate`、`close` | `quickInputService.ts` |
| `SearchViewService` | 搜索会话 | `findInFiles`、`replaceInFiles`、`findInFolder` | `searchView.ts` |
| `EditorService` | 文本编辑器、光标、打开中的状态 | `open`、`openLocation`、`select`、`close`、`tabAction`、`caret` | `editorService.ts` |
| `ExtensionsViewService` | 扩展视图的页签、扩展详情页 | `openPage`、`installFromVsix`、`drop`、`selectIconTheme` | `extensionsWorkbenchService` |
| `ConfigurationService` / `AutoSaveService` | 设置开关；自动保存计时 | `flag`、`setFlag`、`formatOnSave`；`schedule`、`saveNow` | `configurationService`、`filesConfigurationService` |
| `ChatService` | 无（应用给的回调） | `addSelection`、`ask`、`back` | （本应用自有） |
| `CommandService` / `KeybindingDispatchService` | 命令来源、最近运行；chord 状态 | 见 3.3 | `commandService`、`keybindingService` |
| 已有：`IdeWorkspace` `IdeNotifications` | 文档；通知 | | `EditorGroupModel`、`notificationService` |

这些服务**不依赖** `IdeWorkbenchState`，只依赖别的服务、`WorkbenchHost` 和 `WorkbenchEnvironment`。

## 5. 贡献的写法

对应 `IWorkbenchContribution`。一个功能写一个贡献，构造时注册，`dispose` 时注销；`WorkbenchRegistrations` 收集注销回调：

```dart
class NavigationContribution extends WorkbenchRegistrations {
  NavigationContribution(WorkbenchServices services) {
    add(
      services.get<ActionRegistry>().registerAll([
        WorkbenchAction.catalog(
          'workbench.action.navigateBack',
          precondition: (s) => s.find<NavigationHistoryService>()?.canGoBack ?? false,
          run: (s, _) => s.find<NavigationHistoryService>()?.navigate(back: true),
        ),
        …
      ]),
    );
    add(services.get<ContextKeyService>().addProvider((key) => switch (key) {
      'canNavigateBack' => …,
      _ => null,
    }));
  }
}
```

- 命令 id、标题、快捷键照搬，原来的 `IdeCommand` 列表已经拆光。
- 快捷键：目录（`commandCatalog` / `defaultKeybindings`）里已有的命令不写 `keybindings`；原来 `IdeCommand.keybindings` 带快捷键的，原样写进 `WorkbenchAction.keybindings`。
- 贡献列表在 `contributions/all.dart`：导航、SCM、终端、编辑器面板、编辑器状态、Markdown、调试、语言、列表、资源管理器、布局、快速输入、搜索、编辑器命令、窗口、扩展，最后是 `FocusKeysContribution`。
- 原来在 `_workbenchCommands` 里、在某些状态下从列表里拿掉的命令，现在一直注册，用 `precondition` 返回 false 表示不可用；快捷键和菜单看到的结果一样。

## 6. 编辑器面板

对应 `EditorInput` 加 `EditorPaneRegistry`，在 `FileViews` 的基础上扩展：

```dart
class EditorPaneRegistry extends ChangeNotifier {
  VoidCallback register(EditorPane pane, {int priority = 0});
  EditorPane? paneFor(IdeDocument doc);   // 没有就用文本编辑器
}
```

- `EditorPanesContribution` 按原来 `_editorArea` 的判断顺序注册：`FileViews` 视图（stash 等）→ 图片/媒体 → 打不开的占位；`MarkdownContribution` 注册 Markdown 预览（`MarkdownPreviewService` 说要预览时）。都不接的，用 `editorBuilder` 或 `IdeEditor`。
- `FileViews.register` 继续可用，`FileView` 被包成 `EditorPane`。
- 开始页、欢迎页、扩展详情页在 `EditorPart` 里：详情页是叠在编辑器上的离屏页，不当成文档。

## 7. 界面分块

对应 `workbench/browser/parts/*`，都在 `lib/ide/workbench/parts/`：

| 块 | 订阅 | 原来的位置 |
|---|---|---|
| `TitleBarPart` | 工作区、快捷键 | `_titleBar` |
| `ActivityBarPart` | `LayoutService`、`ScmService`、快捷键 | `_activityBar` |
| `SideBarPart` / `ExplorerViewPart` | `LayoutService`、`ScmService`、`DebugViewService`、快捷键；`ExplorerService`、工作区、`LanguageService` | `_sidebarPart` / `_explorerView` |
| `EditorPart` | 工作区、`EditorService`、`ExtensionsViewService`、`MarkdownPreviewService`、`DebugViewService`、`ConfigurationService`、快捷键；面包屑另订阅光标和 `LanguageService` | `_editorArea` |
| `PanelPart` | `LayoutService`、`LanguageService`、`ReferencesService`、`TerminalViewService`、`DebugViewService`、快捷键 | `_panelSlot` |
| 状态栏（`workbenchStatusBar` / `workbenchStatusChanges`） | `StatusbarService`、光标、编辑、通知、远程、语言服务器进度 | `_statusBar` |
| `WorkbenchGrid` / `WorkbenchSash` | `LayoutService`、`DebugViewService` | `_split` / `_editorColumn` / `_chatSlot` / `_Sash` |
| `QuickInputPart`、`ExtensionsViewPart` | 各自的服务 | `_quickInput` / extensions part |

- 每块是独立的 widget，从 `WorkbenchScope` 取服务、从构造参数拿 `WorkbenchOptions`，用 `ListenableBuilder` 只重建自己。
- 拖动分隔条改 `LayoutService` 的宽高，再调 `resized()`：网格重建，存储稍后保存。
- `IdeWorkbenchState.build` 只拼装：`WorkbenchScope` → 鼠标前进后退 → 岛屿样式 → 键盘焦点 → 标题栏、网格 → 通知、快速输入的浮层。
- 快捷键改了，带快捷键提示的块（标题栏、活动栏、侧栏、资源管理器、编辑区、面板）各自订阅 `KeybindingService`，不再靠根部整体重建。

## 8. IDE 与对话侧栏共用的规则

- 侧栏和 IDE 用**同一个类**，各自用自己的依赖构造实例。`GitChangesService(files:, notifications:, …)`：IDE 传入工作区的文件服务、通知、工作区（写回进打开的文档），侧栏传入它自己的。`side_panel_view.dart` 的 `_showLocalDiff` 和 IDE 的 `ScmService.openChangeInLog` 都调 `GitChangesService.localDiffs`。
- 跟布局无关的东西（diff 生成和写回、`IdeGitChangeEditor` 决定改动的两边、编辑器面板注册表、Markdown 预览判断）不依赖工作台的布局或焦点；侧栏的 `gitChangeRequest` 也用 `IdeGitChangeEditor`。
- 跟 IDE 布局有关的服务（`LayoutService`、`QuickInputService`、状态栏、各界面块）只在 IDE 用，侧栏不引入；侧栏自己的空状态样式不同，各写各的。

## 9. 迁移记录

每一步一个 PR，新旧代码并存，每个 PR 都单独合进 main 并打了测试包标签：

| 步骤 | PR | 测试包标签 |
|---|---|---|
| 1 本文档 | #780 | `test-workbench-doc-2ee495a3` |
| 2 基础设施 | #782 | `test-workbench-infra-029f64e0` |
| 3 导航 | #783 | `test-workbench-navigation-2d2894d9` |
| 3 Git/SCM、对比、本地历史（侧栏共用） | #784 | `test-workbench-scm-2187cbd3` |
| 3 终端 | #785 | `test-workbench-terminal-06297a51` |
| 3 Markdown 预览 → 编辑器面板 | #786 | `test-workbench-markdown-854f0d34` |
| 3 调试 | #788 | `test-workbench-debug-50ff69cd` |
| 3 LSP / 问题 / 引用 | #789 | `test-workbench-language-2dceec61` |
| 3 资源管理器、列表 | #790 | `test-workbench-explorer-e3a200e2` |
| 4 编辑区 → EditorService + 面板注册表 | #791 | `test-workbench-editor-84ac1b44` |
| 5 布局命令 | #792 | `test-workbench-layout-9cbdb3f9` |
| 5 快速输入、命令服务 | #793 | `test-workbench-quickinput-ec05af68` |
| 5 搜索 | #794 | `test-workbench-search-0109560d` |
| 5 编辑器/窗口命令，删 keys part | #795 | `test-workbench-commands-1e3860ff` |
| 5 扩展，删 extensions part | #796 | `test-workbench-extensions-7cc4c295` |
| 5 快捷键分发 | #797 | `test-workbench-keys-a8a83ba1` |
| 6 界面分块 | #798 | `test-workbench-parts-386159d0` |
| 6 存储与工作区绑定移出 State | #800 | `test-workbench-state-4f0c53b9` |
| 7 收尾：本文档对齐实现 | 本 PR | |

### 兼容性检查（每步都要过）

- 命令 id、快捷键（`default_keybindings.dart`、用户的 `keybindings.json`）、`when` 里的键名不变。
- `settings.json` 的键不变（`files.autoSave`、`editor.formatOnSave`、`workbench.iconTheme` …）。
- 视图状态的 JSON 键和值格式不变。
- 每块迁移都补一份不依赖 `pumpWorkbench` 的单元测试或组件测试，放在 `test/ide/workbench/services/` 或 `test/ide/workbench/parts/`。只跑与改动相关的测试。
