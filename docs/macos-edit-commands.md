# macOS：全选、复制、粘贴等编辑命令

记录一次排查：在 macOS 应用里，⌘A 和菜单栏“编辑 > 全选”都没有效果。这里说明原因、现在的实现，以及以后改动时要注意的地方。

## 现象

- 远程控制这台 Mac 时，在输入框或对话历史里按 ⌘A 不会全选。菜单栏的“编辑”会亮一下，说明它收到了这个快捷键，但文字没有被选中。
- 直接点菜单栏里的“编辑 > 全选”也没有效果。复制、粘贴等其他菜单项同样无效。
- 所有 widget 测试都能通过。原因见下文“测试为什么发现不了”。

## 原因

两个问题叠在一起，缺一个都不会出现上面的现象。

### 1. 远程桌面发来的 ⌘ 组合键，Flutter 认为 ⌘ 已经松开

macOS 按键事件的修饰键标志（`modifierFlags`）分两部分：

- 与设备无关的位，例如 `NSEventModifierFlagCommand`（0x100000），表示“有 ⌘ 按着”。
- 与设备相关的位，定义在 IOLLEvent.h，例如左 ⌘ 是 0x8、右 ⌘ 是 0x10，表示“具体是哪个键”。

本机键盘发出的事件两部分都有。远程桌面工具注入的 ⌘A 只带前者：实测单独按 ⌘ 时 `flags=0x110008`，而 A 的事件是 `flags=0x110000`。

Flutter 引擎在处理每个按键事件时，会按左右位来同步修饰键状态（见 `FlutterEmbedderKeyResponder` 的 `synchronizeModifiers`）。A 的事件里既没有左 ⌘ 位也没有右 ⌘ 位，引擎就认为 ⌘ 已经松开，先补发一个合成的 Meta 抬起事件（`synthesized: true`），再把 A 当作普通按键交给 framework。所以 Flutter 的快捷键匹配不到 ⌘A。

原生 app 只检查“是否有 ⌘”，所以在别的 app 里远程操作不受影响。

### 2. 菜单栏的“编辑”命令接不到 Flutter 的内容上

Flutter 不处理某个按键时，引擎会把它继续往下传，最后落到菜单栏，并匹配上“全选 ⌘A”。菜单亮起就是这一步。菜单随后按 macOS 的惯例，把 `selectAll:` 发给当前的 first responder（第一响应者，即 macOS 里当前负责接收键盘和菜单命令的对象）：

- **输入框有焦点时**：first responder 是引擎内部的 `FlutterTextInputPlugin`。它是一个看不见的 `NSTextView`，用来配合输入法。它继承了 `NSTextView` 自带的 `selectAll:`、`copy:`、`paste:` 等方法，但只作用于它自己那份文本，屏幕上的输入框不会有任何变化。
- **对话历史有焦点时**：first responder 是 `FlutterView`，它不响应这些命令，所以什么都不会发生。

这是 Flutter 在 macOS 上的一个缺口：引擎没有把标准编辑命令接到 Flutter 的内容上。因此直接点菜单项也无效。

## 现在的实现

修的是第 2 个问题：让菜单里的编辑命令交给窗口处理，再由窗口转给 Flutter 当前的焦点。

1. [MainMenu.xib](../macos/Runner/Base.lproj/MainMenu.xib)：“编辑”菜单里以下命令的 action 改成了自定义方法名。`FlutterTextInputPlugin` 不认识这些方法名，所以命令会沿着响应链一直传到窗口：

   | 菜单项 | 原 action | 现 action |
   | --- | --- | --- |
   | Undo | `undo:` | `monadUndo:` |
   | Redo | `redo:` | `monadRedo:` |
   | Cut | `cut:` | `monadCut:` |
   | Copy | `copy:` | `monadCopy:` |
   | Paste | `paste:` | `monadPaste:` |
   | Paste and Match Style | `pasteAsPlainText:` | `monadPaste:` |
   | Select All | `selectAll:` | `monadSelectAll:` |

2. [MainFlutterWindow.swift](../macos/Runner/MainFlutterWindow.swift)：窗口实现了这些方法，通过 `monad/window` 通道调用 Dart 端的 `editCommand`，参数是命令名（`undo`、`redo`、`cut`、`copy`、`paste` 或 `selectAll`）。
3. [window_controls.dart](../lib/workspace/window_controls.dart)：`WindowControls.handleEditCommands()` 在 [workbench.dart](../lib/workbench.dart) 启动时注册。收到命令后，`runEditCommand` 把它换成对应的 Intent，交给当前焦点所在的 context 执行：

   | 命令 | Intent |
   | --- | --- |
   | `selectAll` | `SelectAllTextIntent` |
   | `copy` | `CopySelectionTextIntent.copy` |
   | `cut` | `CopySelectionTextIntent.cut` |
   | `paste` | `PasteTextIntent` |
   | `undo` | `UndoTextIntent` |
   | `redo` | `RedoTextIntent` |

   输入框里，由 Quill 的 Actions 处理这些 Intent，粘贴仍会经过 composer 自己的粘贴逻辑（图片、`@` 和 `/` 标签）。对话历史里，由 `SelectionArea` 处理。

加上这些改动后，各种情况的处理如下：

- **本机键盘按 ⌘A**：Flutter 的快捷键直接处理，按键不会传到菜单，所以不会执行两次。
- **远程按 ⌘A**：Flutter 匹配不到快捷键，按键落到菜单，菜单再通过上面的路径执行全选。
- **点菜单项**：直接走上面的路径。

输入框的右键菜单是另一套实现：`showContextMenu` 用原生 `NSMenu` 弹出菜单，选中的项再调用 Quill 的 `cutSelection` 等方法。它不经过菜单栏，但原因类似：Quill 自带的菜单是 Flutter 画的，已经关掉了。

## 以后改动时注意

- **不要把 MainMenu.xib 里的这些 action 改回系统默认的 `selectAll:` 等**：那样命令又会被 `FlutterTextInputPlugin` 截走，全选再次失效。要给“编辑”菜单加新命令，也按同样方式处理：起一个自定义 selector，在窗口里实现，再转成 Intent。
- **“编辑”菜单里的 Delete（`delete:`）没有改**：它的行为取决于当前有没有选区，窗口这一侧拿不到这个信息。
- **菜单项不做启用/禁用判断**：自定义 action 由窗口实现，所以这些菜单项总是可点。比如没有选区时点“复制”，结果是什么都不发生。
- **测试为什么发现不了**：widget 测试里的按键是在 framework 内部模拟的，不经过真实的 `NSEvent`、引擎的修饰键同步和菜单栏。测试 “the Edit menu acts where the focus is” 模拟的是窗口发来的 `editCommand`，能覆盖 Dart 这一段，覆盖不了原生这一段。原生这一段只能在真机上验证。

## 排查方法

遇到“快捷键在真机上无效、测试却能通过”时，需要同时看两层日志：

- **原生层**：在 `MainFlutterWindow` 里临时重写 `sendEvent(_:)` 和 `performKeyEquivalent(with:)`，记录每个按键事件的 `type`、`keyCode`、`modifierFlags`（按十六进制输出，才能看到左右位），以及当时的 `firstResponder`。
- **Flutter 层**：用 `HardwareKeyboard.instance.addHandler` 记录每个 `KeyEvent` 的类型、`logicalKey.keyId`、`synthesized`，以及 `HardwareKeyboard.instance.logicalKeysPressed`。

release 模式下 `debugName` 和各种 `toString()` 输出都是空的，所以要打印按键的数字编号。日志写到文件里，比如 `/tmp`，比 `print` 方便。本次排查就是这样发现的：A 的事件里出现了 `synthesized: true` 的 Meta 抬起，而原生层的 flags 缺少 0x8。

## 未解决的问题

问题 1 还在。远程控制时，菜单里没有的 ⌘ 快捷键仍然无效，例如 ⌘B 收起侧边栏。本机键盘不受影响。

修法：在 `MainFlutterWindow` 的 `sendEvent` 和 `performKeyEquivalent` 两处，记下最近一次 flagsChanged 事件里的左右位；如果按键事件带有修饰键、却缺少左右位，就用记下的值补上，再交给引擎。
