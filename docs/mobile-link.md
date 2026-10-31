# 手机连接（扫码或局域网发现配对、端到端加密、P2P 打洞 + 中继）

手机上的 BaoCode（`../mobile`）通过扫码、或在「附近的电脑」里选择，与桌面端配对。之后手机按**桌面端的公钥**找到它，无论两边在哪个网络：同一网络里直连；跨网时自动打洞直连；打洞不通时经中继转发。两端之间的内容始终端到端加密，中继看不到。

传输层是 [iroh](https://github.com/n0-computer/iroh)（QUIC，Rust）。两端共用一份手写的 Dart 绑定 `packages/bao_iroh`（`rust/` 是 Rust 部分，由 `hook/build.dart` 随 App 一起编译）。不使用 n0 的公共服务（发现、DNS、中继），中继是 BaoCode 自己的。

- 传输：`packages/bao_iroh/`（iroh 端点、连接、成帧的流；C 接口 + `dart:ffi`）
- 协议：`packages/bao_link/`（两端共用：身份、配对、`LinkPeer` 请求/事件、会话增量；`bao_link_io.dart` 另外导出 iroh 实现 `IrohLinkNode`）
- 桌面端：`lib/link/`（`LinkHost` 上线与配对，`WorkspaceBridge` 把 Workspace 暴露给手机），设置页 `lib/settings/pages/mobile_page.dart`（设置 → 手机）
- 手机端：`../mobile/lib/link/`（`PhoneLink` 连接与配对，`link_store.dart` 存储），`lib/state/app_state.dart` 把收到的状态并入界面
- 测试：`packages/bao_iroh/test/`、`packages/bao_link/test/`（含真 iroh 端点；设了 `BAOCODE_RELAY` 时还经真中继进程）、`test/link/`、`test/settings/mobile_page_test.dart`、`../mobile/test/link_test.dart`

## 1. 用户怎么用

1. 桌面端：设置 → 手机 → 「显示二维码」（会顺带打开「允许手机连接」，桌面端随即上线：连上中继、开始在局域网广播）。
2. 手机端：我的 → 已配对的电脑 → 配对新电脑，扫码；扫不了码就在桌面端点「复制链接」，在手机上粘贴。
   也可以不扫码：电脑在显示二维码期间，同一网络里的手机能在配对页的「附近的电脑」里看到它，点一下就会发起配对。
3. 两边都会显示 4 组 3 位数的安全码。核对一致后在手机上点「一致，完成配对」；不一致就在任意一端取消。从「附近的电脑」发起的配对没有二维码里的一次性令牌，所以电脑上也要点「允许」才会保存。
4. 之后手机打开 App 会自动重连，断线后退避重试（2s、4s……最长 30s）；从后台回来、网络变化、在局域网里看到这台电脑时立刻重试。
5. 电脑换了 IP、换了网络都不用管：手机按公钥找它。

两边都显示当前的连接方式：「局域网直连」「打洞直连」或「经中继」，以及往返时延。桌面端设置页还显示它连着哪个中继。

## 2. 连接方式

每台设备是一个 iroh 端点，端点 id 就是设备的 Ed25519 公钥。拨号只需要对方的 id，外加两类「提示」：

- **中继**：对方常驻的中继 URL。桌面端上线后连到一个中继（离它最近、能连上的那个），手机经这个中继先建立连接，然后两端交换各自观察到的地址、尝试 UDP 打洞，成功后流量切到直连，中继退出。打洞不通（对称 NAT、只放行 TCP 的网络）时一直经中继。
- **直连地址**：对方自己的地址（`ip:port`），局域网在前。

内置的中继列表至少两个（`packages/bao_link/lib/src/relays.dart` 的 `defaultLinkRelays`），配对时互相告知，连上后桌面端还会在 `hello` 应答里告诉手机它现在的中继和地址，手机每次连上都会更新保存的提示。当前常驻的中继断开 3 秒后，桌面端换到列表里的另一个（`bao_iroh` 里的看门狗，之后最长每 30 秒再试）；手机拨号时会同时带上它保存的和内置的中继。

**自建中继**：中继服务是 `baocode-relay`（独立仓库），可以自己部署。桌面端「设置 → 手机 → 自建中继」和手机端「已配对的电脑 → 自建中继」里填 URL（多个用逗号分隔），与内置的一起使用。新填的中继在之后配对的手机上才会出现在二维码里；已配对的手机会在下次连上时从 `hello` 应答里得知。

ALPN 是 `baocode/link/2`。iroh 自带 TLS 1.3（双方以各自的 Ed25519 密钥认证），所以连接建立后双方都确知对方的公钥，不需要再做应用层握手。

## 3. 二维码里有什么

`baocode://pair?d=<base64url(JSON)>`，JSON 字段：

| 字段 | 含义 |
| --- | --- |
| `v` | 版本，目前是 2。版本 1（迁移前）的码会提示「电脑上的 BaoCode 版本过旧」 |
| `n` | 桌面端名称 |
| `k` | 桌面端公钥（Ed25519，base64url）：也就是它的端点 id |
| `t` | 一次性令牌（16 字节随机数），只有看到二维码的人知道 |
| `x` | 过期时间（Unix 秒），默认 10 分钟 |
| `r` | 桌面端的中继 URL 列表，常驻的在前 |
| `a` | 桌面端的直连地址 `ip:port`，局域网在前，IPv6 写成 `[addr]:port` |

## 4. 身份与安全

每台设备生成一把长期 Ed25519 密钥，私钥不离开设备：桌面端存在 `state/mobile.json`（权限 600），手机端存在 App 私有目录的 `link.json`。设备 id 是公钥的 hex（64 位，即 iroh 的端点 id），指纹是公钥 SHA-256 前 16 字节，每 4 位 hex 分一组。

传输加密由 iroh 的 QUIC/TLS 1.3 负责：每条连接有临时密钥（前向保密），双方以长期密钥签名认证，经中继时中继只能看到加密后的 QUIC 包和两端的 id。

**安全码**：`SHA256("baocode-safety-v2" ‖ 桌面公钥 ‖ 手机公钥)` 前 12 字节，每 3 字节取模 1000，得到 4 组数字。中间人只有换掉其中一把公钥才能插进来，而那样安全码就对不上。

**配对授权**：桌面端只接受三类手机：
- 已配对的手机，按公钥（连接的对端 id）识别。
- 带着当前二维码令牌的手机。令牌比较是常数时间，过期即作废。这一类在手机发来 `confirm` 后就保存。
- 在「附近的电脑」里找到它、发起请求的手机（hello 带 `request: true`）。只在电脑正在配对（二维码显示中）时接受，否则回 `notPairing`。这一类要等手机发来 `confirm`、并且桌面端用户点了「允许」（`LinkHost.approvePending`）才保存；`confirm` 的应答会一直等到用户点「允许」，用户拒绝则返回 `rejected`。

同一时刻只允许一台手机处于核对状态，另一台再来会收到 `busy`。核对期间桌面端只把它记在内存里。

**从旧版升级**：迁移前的版本用 X25519 密钥和自定义握手，与现在不兼容。升级后两端都会生成新的 Ed25519 身份，旧的配对列为「需要重新配对」（桌面端在「已配对的手机」里，手机端在「已配对的电脑」里），点一下就开始重新配对，也可以移除。

### 4.1 局域网发现

桌面端在「允许手机连接」且「局域网发现」打开时（设置 → 手机，默认开），用 DNS-SD 广播服务 `_baocode._tcp`：
- 端口：iroh 端点绑定的 UDP 端口；
- 服务名：电脑名；
- TXT 记录：`v=2`、`k=<桌面公钥 base64url>`、`p=1|0`（是否正在配对）。

格式见 `packages/bao_link/lib/src/discovery.dart` 的 `LinkAdvert`。实现上：
- 桌面端用 `bonsoir` 插件广播（`link_platform_io.dart`），状态变化时由 `LinkHost._syncAdvert` 重新广播；
- 手机端用 `bonsoir` 浏览（`../mobile/lib/link/desktop_discovery.dart`），看到的地址作为直连提示，并让离线的已配对电脑立刻重连；
- iOS 和 macOS 的 Info.plist 都声明了 `NSBonjourServices` 和 `NSLocalNetworkUsageDescription`。

广播的内容都是公开信息：名字、公钥、是否在配对。有人冒充广播也没用：手机拨的是配对时记下的公钥，只有持有对应私钥的电脑才能完成 TLS 认证。发现只提供地址，不交换密钥。

## 5. 流与成帧

一条连接上有多条 QUIC 流，每条流上是一条条完整的消息：`u32` 长度（大端）、1 字节标志、正文。正文超过 1KB 且压缩后更短时用 deflate 压缩（标志位 0）。单条消息最大 32MB。

- **控制流**：拨号方（手机）打开的第一条流。请求、应答、事件都在上面，按顺序。
- **请求流**：大块数据的请求（`read`、`image`、`icon`、`files`、`botAvatar`、`extensions`，见 `LinkMethods.bulk`）每个单独开一条流：请求写完就关闭发送方向，应答是流上唯一一条消息。这样一个大文件不会堵住控制流上的事件。

## 6. 消息

流上的消息是 JSON（`LinkPeer`）：

- 请求 `{"id", "m", "p"}`；应答 `{"id", "r"}` 或 `{"id", "e": {"c", "m"}}`
- 事件 `{"ev", "p"}`

手机 → 桌面的方法见 `LinkMethods`：

- 配对相关：`hello`、`confirm`、`unpair`
- 状态与订阅：`state`、`open`、`close`
- 翻更早的消息：`earlier`（见「会话增量」）
- 操作会话：`send`、`edit`、`stop`、`answer`、`choose`、`rename`、`pin`、`archive`、`keep`、`undo`
- 后台任务：`stopTask`（停任务或子代理）、`output`（命令输出的最后 64K 字符）、`watchOutput` / `unwatchOutput`（订阅命令输出，见下）
- 文件：`files`（列出项目文件，最多 2 万个，跳过 node_modules 等；附带各会话还没保留的改动）、`read`（读文件，最大 512KB，二进制和过大文件不传；被改过的文件附带改动前的原文，手机据此显示改动）
- 扩展：`extensions`（本机用户级和各本地项目的技能、MCP、插件、子代理，来自「自定义」用的 `CustomizationStore`）
- 新对话：`draft`（项目的「新对话」智能体，和桌面端 New Chat 用的同一个，发消息前不出现在列表里）。手机 `open` 它拿到可选的模型、模式、权限、思考强度，用 `choose` 选好，再 `send` 给它，就按选好的设置开始。
- 图片：`image`（`{project, path}` → `{type, data}`，读项目里的 png/jpeg/gif/webp，最大 8MB，超过返回 `{tooLarge, size}`；回复里 `![](路径)` 引用的截图手机靠它显示）
- 项目图标：`state` 里每个项目带 `icon`（emoji、codicon 加主题色、图片、厂商 logo，格式同桌面端 `ProjectIcon.toJson`）。图片用 `icon`（`{id}` → `{kind, data}`）读取；id 由内容算出，手机按 id 缓存。

`files`、`read` 和新建会话的 `send` 只认侧栏里列出的项目（按项目路径匹配），读文件的路径归一化后必须仍在项目根目录内，所以手机拿不到项目以外的文件。多文件夹工作区和 VS Code 的多根资源管理器一样：每个文件夹以它的名字作为顶层（`mobile/lib/main.dart`），列文件、读文件、会话改动的路径、`@文件` 都按这个命名；手机发来的 `@文件` 会换成文件的完整路径再交给智能体。智能体改了项目以外的文件时，手机拿到的是完整路径，只有这种被该项目智能体改过的文件可以按完整路径读取。`send` 可以带图片（`images`，base64，png/jpeg/gif/webp，桌面端接着会话里的编号往下编，并在文字末尾写上 `[Image #N]`）和 `@文件`（`mentions`，相对项目根目录的路径）。

`edit`：`{session, index, text, images?, mentions?}`，和桌面端「编辑消息」一样：把第 `index` 条用户消息改成新内容重发，它之后的内容全部丢弃、从那里重新跑。`index` 和增量的 `start` 一样从手机拿到的第一条算起（用 `window` 打开时不是会话的第一条）。那里不是用户消息返回 `notFound`，智能体不能回退返回 `unsupported`；旧版桌面端不认识这个方法，返回 `unknown`，手机提示升级桌面端。

桌面 → 手机的事件：`state`（项目和会话列表，有变化时推送，每 150ms 最多一次）、`session`（已订阅会话的增量更新，包括后台任务列表 `tasks`）、`output`（订阅的命令输出）、`unpaired`。手机端的 `LinkPeer` 自己还会产生一个 `resync` 事件（见下）。

**会话增量**：`open` 时先返回整个会话，之后只发从第一个变化的条目开始的部分（`start` + 之后的条目）。判断“变没变”时，先看是不是同一个对象；对象不同再比较 JSON。条目的 JSON 格式见 `lib/link/chat_codec.dart`；手机端 `lib/link/chat_codec.dart` 是同一份文件，只改了头部注释。工具输出、命令输出超过 64KB 的部分会截掉。

增量还会再瘦身（`packages/bao_link/lib/src/session_mirror.dart`）：
- `"partial": true`：`live`、`interaction`、`choices`、`changes`、`tasks`、`earlier`、`goal` 只带变了的（变成没有时带 `null`）；
- `"append": {"index", "path", "text"}`：第 `index` 条（`start` 前面那一条）和上次一样，只是 `path`（键和下标）处的字符串末尾多了 `text`：流式输出的回复只发新增的字，不必每次把整条再发一遍；`start` 起的条目照常整条发送。

手机端的 `LinkSessionMirror` 按 `open`、`earlier` 的应答和之后的增量保存一份副本，把瘦身的增量还原成完整的（和瘦身前一样的）增量交给界面。对不上时（漏了一条）不交给界面，改为发出 `resync` 事件，手机重新 `open` 这个会话。

**命令输出订阅**：`watchOutput {session, task}` → `{text, offset}`（当前输出的最后 64K 字符，`offset` 是输出的总长度）。之后桌面端每 500ms 看一次，有新增就发 `output` 事件 `{session, task, offset, text}`，`text` 是新增的部分，`offset` 是加上它之后的总长度；输出被截断、改写，或者一次新增超过 64K 时，带 `reset: true`，`text` 是最后 64K 的全部。终端页关闭时发 `unwatchOutput`；断线重连后手机重新订阅。

**分页（`window`，手机可选）**：`open` 可以带 `window`（整数 N）：`{"session", "window": N}`。带了之后桌面端只跟踪这个会话的最后 N 条，`session` 事件和 `open` 应答里的 `start`、`count` 都从手机拿到的第一条算起（第 0 条是手机的第一条，不是会话的第一条），`count` 是手机现在有的条数。应答和每个增量里多一个 `earlier`（bool）：手机的第一条之前是否还有更早的。不带 `window` 的 `open` 和以前完全一样：整个（桌面端已加载的）会话，`start` 从会话第一条算起，也没有 `earlier` 字段。

`earlier` 请求：`{"session", "count"?}`（`count` 默认 50）→ `{"items": [...], "earlier": bool}`。`items` 是手机第一条之前的最多 `count` 条，从旧到新排；桌面端内存里没有更早的时，会先从历史记录里读（可能要一会儿，请求会等到读完）。`earlier` 同样表示再往前是否还有。会话要是用 `window` 打开的才能用，否则返回错误；没有 `open` 过的会话也返回错误。

手机的做法：
- 可选。判断桌面端支不支持：带 `window` 打开，应答里有 `earlier` 字段才是支持；旧版桌面端会忽略 `window`，应答没有 `earlier`，这时按老办法处理（拿到整个会话，不要发 `earlier` 请求）。
- 手机本地的列表是「第一条 … 最后一条」。`earlier` 请求返回的 `items` 整个放到本地列表最前面，之后的 `start`、`count` 就从新的第一条算起（比如本来有 40 条，翻回 50 条，本地变成 90 条，后面增量的 `start` 对应这 90 条）。
- 列表顶部在 `earlier` 为 true 时显示「加载更早的消息」，点击或滚到顶时发 `earlier` 请求，请求没回来之前不要重复发；`earlier` 变成 false 就不再显示。每次增量和 `earlier` 应答里的 `earlier` 都以最近一次为准。
- `earlier` 应答的 `items` 为空但 `earlier` 仍是 true（桌面端读历史失败）时，不要自动重试，等用户再点。
- 桌面端自己加载更早的消息，不会改变手机拿到的条目，只可能让 `earlier` 变化。

应答请求（工具权限审批、提问、计划审批）的格式见 `lib/link/interaction_codec.dart`。手机端的模型在 `../mobile/lib/models/interaction.dart`。

## 7. 已知限制

- 桌面端打开很长的会话时先只读最近 10 轮，滚到顶再加载更早的；手机用 `window` 打开时同样分页，旧版手机（不带 `window`）拿到的是桌面端已加载的部分。
- 局域网发现只在同一局域网（同一组播域）内有效；不在同一局域网时靠中继和打洞，连接方式会显示「打洞直连」或「经中继」。
- 手机在 iOS 上第一次使用时会弹出「本地网络」授权，拒绝后既发现不了电脑，也走不了局域网直连（仍可经中继或打洞）。
- 定时任务页在手机端仍是演示数据，没有接到桌面端。
- 通知（智能体需要处理、完成一轮）由手机在本地发出，只在 App 打开或刚切到后台、连接还在时有效；被系统挂起后收不到，远程推送还没有。
- 扩展页只列出、不能在手机上安装或开关；远程（SSH）项目的扩展暂不列出。
- 桌面端取消配对时，如果手机不在线，手机下次连上会被拒，显示为「已在电脑上取消配对」，需要在手机上移除后重新配对。
