# 自动更新

BaoCode 的自动检查与升级：怎么工作、服务端约定、签名、出问题怎么查，以及以后改代码时要注意什么。版本号怎么定、怎么发版、CI 和 Cloudflare 怎么配，见 [release.md](release.md)。

- 更新服务器：`https://dl.baocode.dev`（Cloudflare R2；`baocode.dev/releases/*` 302 到这里）
- 平台：macOS（Apple silicon 和 Intel 各一个包）、Windows（x64）
- 代码：`lib/update/`，测试：`test/update/`，发布工具：`tool/release_manifest.dart`

## 目录

1. [现状一览](#1-现状一览)
2. [用户看到的行为](#2-用户看到的行为)
3. [整体结构](#3-整体结构)
4. [一次更新的完整流程](#4-一次更新的完整流程)
5. [服务端约定](#5-服务端约定)
6. [签名与密钥](#6-签名与密钥)
7. [发版步骤](#7-发版步骤)
8. [本地测试](#8-本地测试)
9. [文件、设置项与存储位置](#9-文件设置项与存储位置)
10. [故障排查](#10-故障排查)
11. [真机验证清单](#11-真机验证清单)
12. [修改指南](#12-修改指南)
13. [已知限制与待办](#13-已知限制与待办)

---

## 1. 现状一览

| 项目 | 状态 |
| --- | --- |
| 检查、下载、校验、安装（应用侧） | 已完成，单元测试覆盖 |
| Windows 静默安装并自动重启 | 已完成；`tool/baocode.iss` 已支持 `/RELAUNCH` |
| macOS 替换 .app 并自动重启 | 已完成 |
| 发布工具（签名 + 生成清单） | 已完成：`tool/release_manifest.dart` |
| 版本号工具 | 已完成：`tool/bump_version.dart` |
| CI 构建与发布 | 已完成：`.github/workflows/release.yml`，见 [release.md](release.md) |
| macOS 打包（dmg + 更新用 zip） | 已完成：`tool/build_macos.dart` |
| macOS 代码签名与公证 | 脚本已支持；**等 Apple 开发者账号**，见 [release.md 7.3](release.md#73-applemacos-签名与公证) |
| dl.baocode.dev（R2） | **需要准备**：见 [release.md 7.1](release.md#71-cloudflare) |
| 真机端到端验证 | **未做**：见第 11 节 |

签名密钥已经生成：私钥在 `~/.baocode-release/update-signing.key`（不在仓库里），公钥写在 `lib/update/update_signature.dart`。

---

## 2. 用户看到的行为

### 2.1 更新方式：`update.mode`

在 settings.json 里设置，也可以在“设置 → 更新”里选。

| 值 | 界面名称 | 行为 |
| --- | --- | --- |
| `"default"`（默认，不写就是它） | 自动检查并下载 | 启动 30 秒后检查一次，之后每 6 小时检查一次；发现新版本就在后台下载，下载并校验完成后在主窗口弹出通知 |
| `"manual"` | 仅手动检查 | 不自动检查；只有执行“检查更新”时才检查；点“立即重启更新”时才下载 |
| `"none"` | 关闭 | 完全不检查，手动检查也只会提示“更新已关闭” |

修改后立即生效，不用重启：从 `none` / `manual` 切到 `default` 后，30 秒后开始第一次检查；切走后，定时检查停止。

### 2.2 入口

- **通知**：出现在主窗口右下角，常驻不自动消失。
  - 普通更新：`BaoCode 1.2.0 已下载，重启即可完成更新。`，按钮有“立即重启更新”、“稍后”、“跳过此版本”；有更新日志时，齿轮菜单里还有“更新日志”（会打开设置页）。
  - 强制更新（当前版本低于 `minimumVersion`）：只有“立即重启更新”一个按钮。
- **侧边栏底部的“更新”按钮**：在设置齿轮左边，蓝色胶囊样式，有更新待安装时一直显示，点击等同于“立即重启更新”，鼠标悬停时显示版本号。显示条件见 `UpdateService.pending`：已下载完成；`manual` 模式下已发现新版本；跳过的版本（不弹通知、不在后台下载，但按钮照常显示，点击时再下载）；或者是强制更新。已是最新时不显示。
- **命令面板**：“检查更新...”（命令 id `update.checkForUpdate`），聊天布局和 IDE 都有，也可以绑定快捷键。
- **macOS 菜单栏**：应用菜单 →“关于 BaoCode”下面的“检查更新…”。
- **设置 → 更新**：显示当前版本、上次检查时间、“检查更新”按钮、检查结果和下载进度、“立即重启更新”按钮、更新方式下拉框，以及新版本的更新日志。

### 2.3 规则

- **自动检查失败**：只写一行日志，不弹任何提示。**手动检查失败**：弹出错误通知。
- **同一版本只提示一次**：一次运行中，同一个版本只自动提示一次；点了“稍后”，要等下次启动才会再提示。
- **跳过此版本**：自动检查不再弹通知、不在后台下载这个版本，有更新的版本时照常提示；侧边栏的“更新”按钮、手动检查和设置页里仍然可以安装。
- **强制更新**：忽略“跳过”，每次自动检查都会再提示一次。
- **安装前确认**：点“立即重启更新”后，走的是和平时退出完全一样的流程：有未保存的文件就先问保存，有正在运行的 agent 或终端就先确认。用户取消退出，就**什么都不装**，下载好的安装包留着，下次点直接用。
- **只有 release 构建自动更新**：`flutter run` 起的 debug 构建默认不更新（它会替换掉 build 目录里的应用）。设置页会显示“此版本的 BaoCode 不支持自动更新”。设置了 `BAOCODE_UPDATE_URL` 的情况除外，见第 8 节。

---

## 3. 整体结构

### 3.1 文件

| 文件 | 作用 | 依赖 |
| --- | --- | --- |
| `lib/update/version.dart` | `AppVersion`：解析、比较版本号；`appVersionString` 是当前版本 | 纯 Dart |
| `lib/update/update_manifest.dart` | 解析 `latest.json`；`UpdateUrlPolicy` 限制下载链接的域名 | 纯 Dart |
| `lib/update/update_signature.dart` | 签名内容的格式、验签、签名；内置公钥 `updatePublicKey` | 纯 Dart + pinenacl |
| `lib/update/update_settings.dart` | `UpdateMode`（读取 `update.mode`） | 纯 Dart |
| `lib/update/update_service.dart` | `UpdateService`：定时检查、下载、跳过、强制更新、退出时启动安装；定义各个接口 | Flutter foundation |
| `lib/update/update_io.dart` | `IoUpdateBackend`：拉取清单、断点续传下载、校验、清理旧版本 | dart:io |
| `lib/update/installer_io.dart` | `WindowsUpdateInstaller`、`MacUpdateInstaller`、`platformUpdates()` | dart:io |
| `lib/update/installer_stub.dart` | 没有 dart:io 时（web）的空实现 | — |
| `lib/update/update_platform.dart` | 按平台从上面两个里选一个 | — |
| `lib/update/update_controller.dart` | `UpdateController`：通知、“检查更新”、“立即重启更新” | UI 粘合层 |
| `lib/update/update_store.dart` | `GlobalUpdateStore`：跳过的版本、上次检查时间 | GlobalStorage |
| `lib/settings/pages/updates_page.dart` | 设置 → 更新 | UI |
| `tool/release_manifest.dart` | 签名并生成清单、生成密钥 | 只依赖上面的纯 Dart 文件 |

`version.dart`、`update_manifest.dart`、`update_signature.dart` **不能引入 Flutter**：`dart run tool/release_manifest.dart` 也会用到它们，引入 Flutter 后这个工具就跑不起来了。

### 3.2 对象关系

```
main.dart  _startUpdates()
  └─ platformUpdates()                    ← installer_io.dart，按平台挑选实现
       ├─ IoUpdateBackend                 ← 网络 + updates/ 目录（UpdateBackend 接口）
       └─ Windows/MacUpdateInstaller      ← 安装（UpdateInstaller 接口）
  └─ UpdateService(backend, installer, mode, store)   ← 状态机、定时器
  └─ UpdateController(service, quit, openUrl)         ← 交给 AppSettings.updates

Workbench（主窗口）  controller.listen(...)          ← 自动发现的更新、安装失败 → 通知
Workbench（每个窗口） _checkForUpdates()             ← “检查更新”命令 → 本窗口的通知
UpdatesSettingsPage  controller.restartToUpdate()    ← 设置页按钮，结果显示在页面上
main.dart onExitRequested
  └─ confirmQuit() 取消 → service.disarm()
  └─ 确认         → service.launchArmed()           ← 启动安装程序，失败则取消退出
```

可注入的接口都定义在 `update_service.dart`，测试里全部用假实现：

| 接口 | 生产实现 | 负责 |
| --- | --- | --- |
| `UpdateBackend` | `IoUpdateBackend` | `fetchManifest`、`download`、`cleanUp` |
| `UpdateInstaller` / `PreparedUpdate` | `WindowsUpdateInstaller`、`MacUpdateInstaller` | `prepare`（准备）、`launch`（启动） |
| `UpdateProcesses` | `IoUpdateProcesses` | 运行和启动外部程序（ditto、codesign、reg、Setup…） |
| `UpdateStore` | `GlobalUpdateStore` | 跳过的版本、上次检查时间 |

### 3.3 状态（`UpdateStatus`）

```
idle ──检查──▶ checking ──┬─▶ upToDate
                          ├─▶ available ──下载──▶ downloading ──┬─▶ ready
                          │                                     └─▶ failed
                          └─▶ failed（还没找到任何版本时）
```

- 已经找到过新版本、这次检查失败时，状态**保持**原来的 available / downloading / ready，只记录错误。
- 下载进行中又检查了一次时，状态保持 downloading。
- 同一个版本只下载一次：同时调用多次 `download()`，等的是同一个 Future；已经下好的直接返回。

---

## 4. 一次更新的完整流程

### 4.1 检查

1. GET `latest.json`：超时 30 秒，响应最大 1 MB，必须是 200。User-Agent 是 `BaoCode/<当前版本> (<平台>)`。
2. 解析清单，下载链接必须符合 `UpdateUrlPolicy`（见 5.3）。
3. 记录上次检查时间。
4. 清单版本 ≤ 当前版本，或者没有本平台的条目 → 已是最新（upToDate）。
5. 本平台的条目有错 → 检查失败（只影响这个平台）。
6. 否则 → 找到新版本（available）。自动检查还会继续：没被跳过（或者是强制更新），并且这次运行中还没提示过这个版本 → 后台下载 → 发出提示。

### 4.2 下载与校验（`IoUpdateBackend.download`）

1. 删掉 `updates/` 下其他版本的目录（只保留最新一个）。
2. `updates/<版本>/<文件名>` 已经存在并且校验通过 → 直接用，不重新下载。
3. 下载到 `<文件名>.part`：
   - `.part` 已经存在 → 带 `Range: bytes=<已下大小>-` 续传；服务器回 206 就接着写，回 200 就从头写，回 416 就删掉重下。
   - 实际收到的字节数超过清单里的 `size` → 立即中止，删掉文件。
   - 30 秒收不到数据就算超时；中断后 `.part` 会保留，下次接着下。
4. 校验，**按顺序**：大小 → SHA-256 → Ed25519 签名。任何一项不过就删掉 `.part` 并报错。
5. 改名为正式文件名，返回路径。

### 4.3 “立即重启更新”

```
UpdateController.restartToUpdate()
  1. service.prepare()
       ├─ download()（还没下好的话）
       └─ installer.prepare(file)        ← 不能自己替换时抛 ManualUpdateRequired
  2. service.arm(update)                 ← 记下来，退出时再启动
  3. quit()                              ← Windows: ChannelAttentionHost.quit()
                                            macOS:   exitApplication(cancelable)
main.dart onExitRequested
  4. windows.confirmQuit()               ← 未保存文件、运行中的 agent 和终端
       └─ 取消 → service.disarm()，应用继续运行
  5. service.launchArmed()               ← 启动安装程序（它会等应用退出）
       └─ 启动失败 → 取消退出，主窗口提示“更新失败”
  6. 停止 Claude、LSP、PTY 等子进程 → 应用退出
```

### 4.4 Windows 安装

准备阶段（`WindowsUpdateInstaller.prepare`）：

- `baocode.exe` 旁边没有 `unins000.exe` → 抛 `ManualUpdateRequired`（不是用安装包装的，比如直接从 build 目录运行）。
- 判断原来的安装方式：用 `reg.exe query <hive>\…\Uninstall\{6fdd732b-…}_is1 /reg:64` 看 Setup 把卸载项登记在 HKLM（按机器，`/ALLUSERS`）还是 HKCU（按用户，`/CURRENTUSER`）。两边都有（装了两份）或都没有时，退回看 exe 是否在 `%ProgramFiles%`、`%ProgramW6432%` 或 `%ProgramFiles(x86)%` 下面。

启动阶段：在应用退出**之前**，以分离进程的方式直接运行 Setup，中间没有 PowerShell：

```
<setup.exe> /SILENT /SUPPRESSMSGBOXES /NORESTART /CLOSEAPPLICATIONS /RELAUNCH /ALLUSERS 或 /CURRENTUSER /DIR=<exe 所在目录> /WAITPID=<应用 pid> /LOG=updates\install.log
```

- Setup 由还在前台的应用启动，按机器安装时 UAC 弹窗会出现在前面，而不是在任务栏上闪（应用已经退出、没有前台窗口时就会这样，用户看不到）。
- `/WAITPID` 是 `tool/baocode.iss` 自己的参数：`InitializeSetup` 里用 `OpenProcess` + `WaitForSingleObject` 最多等 120 秒，应用退出后再安装；还没退出就继续，`CloseApplications=force` 会把它关掉。
- `/DIR` 指定装回当前 exe 所在的目录，不管 Setup 记录的上次目录是什么，保证覆盖的正是正在运行的这一份。
- `/LOG` 写到 `updates\install.log`；`SetupLogging=yes` 让没带 `/LOG` 的安装（包括 1.0.0 通过 PowerShell 启动的更新）也会在 `%TEMP%\Setup Log <日期> #<n>.txt` 留下日志。
- `/SILENT` 会显示进度窗口但不提问；Inno Setup 会沿用上次勾选的选项（桌面图标、PATH、右键菜单）。
- `tool/baocode.iss` 的 `[Run]` 里有一条 `Check: RelaunchRequested`：只有静默安装并且带了 `/RELAUNCH` 时，才以原用户身份重新打开应用。
- 1.0.0 的应用仍用旧方式（隐藏的 PowerShell 等应用退出后 `Start-Process`，不带 `/WAITPID`、`/DIR`、`/LOG`）启动新版 Setup，新版 Setup 要继续兼容这种命令行。

### 4.5 macOS 安装

准备阶段（`MacUpdateInstaller.prepare`），任何一步不过就停止：

1. 当前应用的位置：`Platform.resolvedExecutable` 往上三级，必须以 `.app` 结尾。
2. 路径里有 `/AppTranslocation/` → `ManualUpdateRequired`（从 dmg 或下载目录直接运行，macOS 把应用挪到了临时位置）。
3. 在 .app 所在的目录里试着建一个文件，建不了 → `ManualUpdateRequired`。
4. `ditto -x -k <zip> updates/<版本>/staging/` 解压，里面必须**恰好有一个** .app。
5. 用 `PlistBuddy` 读两边的 `CFBundleIdentifier`，必须一样（`dev.baocode.desktop`）。
6. 签名检查：当前应用 `codesign --verify --deep --strict` 通过（即正式签名）时，新版本也必须通过，而且 `codesign -d` 读出来的 TeamIdentifier 要相同。当前应用没有有效签名（开发构建、ad hoc）时跳过这一步，此时由下载文件的 Ed25519 签名来保证真实性。

启动阶段：把脚本写到 `updates/<版本>/install.sh`，用 `/bin/bash` 以分离进程的方式运行。脚本会：

1. 把输出追加到 `updates/install.log`。
2. 最多等 120 秒，直到应用进程退出；仍未退出就放弃（什么都不改）。
3. `ditto` 复制成 `<App>.app.baocode-new` → 把旧版改名为 `.baocode-old` → 把新版改名就位 → 删掉旧版；新版就位失败时把旧版改回来。
4. 删掉 staging 目录，`xattr -dr com.apple.quarantine` 清除隔离属性，`open` 打开新版本，最后删掉脚本自己。

### 4.6 下次启动

`UpdateService.start()` 会清理 `updates/` 下所有版本号 ≤ 当前版本的目录，以及名字不是版本号的目录。`install.log` 是文件，不会被清理。

---

## 5. 服务端约定

### 5.1 目录布局

```
https://dl.baocode.dev/
  releases/
    latest.json                         ← 应用读取的清单
    1.2.0/
      BaoCode-1.2.0-setup.exe           ← Windows 更新 / 首次安装
      BaoCode-1.2.0-mac-arm64.zip       ← macOS 更新（Apple silicon）
      BaoCode-1.2.0-mac-x64.zip         ← macOS 更新（Intel）
      BaoCode-1.2.0-arm64.dmg           ← macOS 首次安装（应用不读取）
      BaoCode-1.2.0-x64.dmg
    remote/
      <VERSION>/                        ← 远程服务端，应用连远程主机时按需下载
        baocode-server-linux-x64.gz        （见 docs/ssh-remote.md 第 9.3 节；
        baocode-server-linux-arm64.gz       旧版本的目录要一直保留）
```

下载页 `https://baocode.dev/download` 在官网上（`site/`），应用无法自己更新时会打开它。

`tool/release_manifest.dart` 按 `https://dl.baocode.dev/releases/<marketing 版本>/<文件名>` 生成链接。要改目录结构，就改工具里的 `_releasesBase`。

### 5.2 `latest.json` 格式

```json
{
  "version": "1.2.0+12",
  "pubDate": "2026-10-04T00:00:00Z",
  "notes": { "en": "Faster startup.", "zh": "启动更快。" },
  "minimumVersion": "1.0.0",
  "platforms": {
    "windows-x64": {
      "url": "https://dl.baocode.dev/releases/1.2.0/BaoCode-1.2.0-setup.exe",
      "size": 123456789,
      "sha256": "64 位十六进制",
      "signature": "base64，解码后 64 字节"
    },
    "macos-arm64": {
      "url": "https://dl.baocode.dev/releases/1.2.0/BaoCode-1.2.0-mac-arm64.zip?sha256=0123456789abcdef",
      "size": 123456789,
      "sha256": "...",
      "signature": "..."
    },
    "macos-x64": {
      "url": "https://dl.baocode.dev/releases/1.2.0/BaoCode-1.2.0-mac-x64.zip?sha256=fedcba9876543210",
      "size": 123456789,
      "sha256": "...",
      "signature": "..."
    }
  }
}
```

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `version` | 是 | 和 pubspec.yaml 写法一样：`1.2.0+12`。可以带预发布标识（`1.2.0-beta.1`），也可以省略后面的部分（`1.2` 等于 `1.2.0`） |
| `pubDate` | 否 | ISO 8601 格式，目前只是记录下来 |
| `notes` | 否 | `{语言: 文本}`，也可以直接写一个字符串（当作英文）。界面按应用语言取，取不到用 `en`，再取不到用任意一种 |
| `minimumVersion` | 否 | 低于它的版本视为强制更新。格式写错时整份清单都会被拒绝 |
| `platforms` | 是 | 平台键目前有 `windows-x64`、`macos-arm64`、`macos-x64`。Mac 按自己的处理器选：Apple silicon 取 `macos-arm64`；Intel 取 `macos-x64`；Intel 版在 Apple silicon 上经 Rosetta 运行时（`sysctl.proc_translated` 为 1）取 `macos-arm64`，借这次更新换成原生版（`installer_io.dart` 的 `macUpdatePlatform`）。1.0.0 最早发的是 universal 包、键是 `macos-universal`，那些安装找不到更新，要重新下载 |
| `url` | 是 | 见 5.3 |
| `size` | 是 | 正整数，单位字节 |
| `sha256` | 是 | 64 位十六进制，大小写都可以 |
| `signature` | 是 | 见第 6 节 |

**版本比较**：先按 semver 比 `major.minor.patch`；正式版高于它的预发布版；再比 `+` 后面的 build 号（没写按 0 算）。例如 `1.2.0+12 > 1.2.0+11 > 1.2.0 > 1.2.0-rc.1`。

**容错**：某个平台的条目缺失时，这个平台视为“已是最新”；某个平台的条目有错时，只影响这个平台（该平台的检查报错）；顶层字段有错时，整份清单都会被拒绝。

### 5.3 下载链接规则（`UpdateUrlPolicy`）

允许：

- `https://baocode.dev/...`、`https://<任意子域>.baocode.dev/...`（主机名不区分大小写）

拒绝：

- `http://`、其他协议、相对路径
- 带端口：`https://baocode.dev:8443/`
- 带用户信息：`https://user@baocode.dev/`
- 相似域名：`baocode.dev.evil.example`、`notbaocode.dev`

例外：设置了 `BAOCODE_UPDATE_URL` 时，清单同源（协议 + 主机 + 端口）的链接也会被接受，方便本地测试。

服务器可以把下载重定向到其他域名的 CDN（`HttpClient` 会自动跟随），因为下载内容由 SHA-256 和签名保证，不依赖域名。

### 5.4 对服务器的要求

CI 上传时已经按下面这些设置好（见 [release.md 第 5 节](release.md#5-dlbaocodedev-上有什么)）：

- **`latest.json` 不要缓存太久**：`Cache-Control: max-age=300`。CDN 缓存旧清单会导致新版本推送延迟；撤回某个版本时也要清 CDN 缓存。
- **安装包可以长期缓存**（`immutable`，一年）：清单里的链接末尾带文件哈希（`?sha256=…`），文件换了链接就换了，所以同一个版本重新发布也不会拿到旧文件，见 [release.md 第 2 节](release.md#2-版本号)。
- **建议支持 `Range` 请求**（回 206）：用于断点续传。不支持也没关系，应用会从头重新下载。
- **返回 `Content-Length`**：不强制，但没有的话进度显示不准。
- **上传顺序**：先上传安装包，**最后**上传 `latest.json`。

### 5.5 撤回一个版本

把 `latest.json` 改回上一个版本的内容并重新上传（清掉 CDN 缓存）。已经更新到问题版本的用户不会被“降级”，因为应用只接受比当前版本高的版本。要让这些用户回到正常状态，需要发一个版本号更高的修复版。

---

## 6. 签名与密钥

### 6.1 签的是什么

签名不是对整个文件做的，而是对下面这段 UTF-8 文本做的。每项一行，最后一行后面也有换行：

```
baocode-update-v1
1.2.0+12
windows-x64
123456789
<sha256，小写十六进制>
```

- 文件本身由 SHA-256 绑定。不对整个文件签名，是因为 pinenacl 验签时会把整个消息复制好几份，几百 MB 的安装包撑不住。
- 签名里带版本号：防止把签过名的旧安装包当作新版本下发，诱导用户降级到有漏洞的版本。
- 签名里带平台：防止把一个平台的安装包发给另一个平台。
- 开头的 `baocode-update-v1` 是格式版本号。以后要改签名内容，就换成 `v2`，见第 12 节。

算法是 Ed25519（pinenacl 库，纯 Dart 实现）。公钥 32 字节，签名 64 字节，都用 base64 编码。

### 6.2 密钥

| 项目 | 位置与说明 |
| --- | --- |
| 私钥 | `~/.baocode-release/update-signing.key`，权限 600。内容是一行 base64，解码后是 32 字节的随机种子 |
| 公钥 | `lib/update/update_signature.dart` 的 `updatePublicKey`，当前是 `iBSgPUxNeT4jvgaua22aN/jCDwG+ry8rGc17kMcU4II=` |
| 发布时 | 用环境变量 `BAOCODE_UPDATE_SIGNING_KEY` 指向私钥文件 |

常用命令：

```sh
# 查看私钥对应的公钥（应该和 updatePublicKey 一致）
BAOCODE_UPDATE_SIGNING_KEY=~/.baocode-release/update-signing.key \
  dart run tool/release_manifest.dart --public-key

# 生成新密钥（不会覆盖已有文件），会打印出公钥
dart run tool/release_manifest.dart --generate-key <路径>
```

### 6.3 保管

- **不要**提交到仓库，不要放进网盘的同步目录明文保存，不要发到聊天工具里。
- 离线备份至少两份，例如密码管理器一份、加密 U 盘一份。
- **泄露的后果**：拿到私钥的人可以让所有已安装的 BaoCode 运行他们的程序（当然还需要能控制 dl.baocode.dev 或用户的网络）。
- **丢失的后果**：已经安装的版本再也收不到自动更新，只能让用户手动去下载页重装。

### 6.4 轮换密钥

1. 生成新密钥。
2. 发一个过渡版本 N：内置**新**公钥，但用**旧**私钥签名（已安装的旧版本只认旧公钥）。
3. 版本 N 之后的所有版本都用新私钥签名。
4. 还停留在 N 之前的用户要先更新到 N，才能继续收到更新；不要太快删除旧私钥。

如果私钥已经泄露，就无法安全地完成过渡（攻击者也能签过渡版本）。这种情况只能发一个用新密钥签名的版本，然后在官网公告，让用户手动下载安装。

在第一个正式版本发布前，可以直接换掉现在这把密钥：重新生成，然后替换 `updatePublicKey`。

---

## 7. 发版步骤

见 [release.md](release.md)：用 `tool/bump_version.dart` 改版本号，推送 `v<版本>` 标签，CI 构建、签名、上传到 `dl.baocode.dev`，`latest.json` 最后上传。CI 不可用时的手动步骤见 [release.md 第 9 节](release.md#9-不用-ci手动发布)。

---

## 8. 本地测试

不用发布到 dl.baocode.dev，就能在本机完整走一遍更新流程：

```sh
# 1. 准备一个“更新版本”：版本号比要测试的那个构建高，签名后写到一个目录
mkdir -p /tmp/rel && cp build/installers/BaoCode-1.2.0-mac-arm64.zip /tmp/rel/
BAOCODE_UPDATE_SIGNING_KEY=~/.baocode-release/update-signing.key \
  dart run tool/release_manifest.dart --version 9.0.0 \
  --macos-arm64 /tmp/rel/BaoCode-1.2.0-mac-arm64.zip --manifest /tmp/rel/latest.json

# 2. 把 latest.json 里的 url 换成本地地址（同源的链接会被接受）
sed -i '' 's#https://dl.baocode.dev/releases/9.0.0/#http://127.0.0.1:8080/#' /tmp/rel/latest.json

# 3. 起一个静态服务器
cd /tmp/rel && python3 -m http.server 8080

# 4. 让被测试的应用读本地清单
BAOCODE_UPDATE_URL=http://127.0.0.1:8080/latest.json \
  /Applications/BaoCode.app/Contents/MacOS/BaoCode
```

- 改 url 不会让签名失效，因为签名内容里不包括 url。
- `python3 -m http.server` 不支持 Range，断点续传会退化成从头下载，这是正常的。
- 设置了 `BAOCODE_UPDATE_URL` 时，debug 构建也会启用更新。但是 debug 构建的 .app 在 build 目录里，“更新”会替换掉它，所以最好用拷到别的目录的 release 构建来测。
- 从终端启动应用时，能看到 `update:` 开头的日志。

自动化测试（不会联网，也不会真的安装）：

```sh
flutter test test/update
```

| 测试文件 | 覆盖 |
| --- | --- |
| `version_test.dart` | 版本解析和比较；`appVersionString` 和 pubspec 是否一致 |
| `update_manifest_test.dart` | 字段缺失或错误、平台缺失、非 baocode.dev 的链接、同源例外、序列化往返 |
| `update_signature_test.dart` | 签名往返；改版本号、换密钥、篡改签名都会验签失败；内置公钥格式正确 |
| `update_io_test.dart` | 本地 HttpServer：下载、复用已下载的文件、SHA-256 / 签名 / 大小不对时拒绝、断点续传、服务器不支持 Range、只保留最新版本、清理旧版本 |
| `update_service_test.dart` | 三种模式、30 秒和 6 小时的定时、模式切换、只提示一次、跳过、强制更新、下载去重、arm / disarm / 启动失败 |
| `installer_test.dart` | Windows 的 Setup 参数、按注册表判断安装方式、没有 `unins000` 时的处理；macOS 的解压、bundle id、签名和 Team 检查、无法替换时转下载页、脚本内容（以及 `bash -n` 语法检查） |
| `update_controller_test.dart` | 通知的按钮、强制更新只有一个按钮、跳过、重启、下载页、校验失败 |
| `updates_page_test.dart` | 设置页显示、检查、重启、错误显示、`update.mode` 的读写 |

---

## 9. 文件、设置项与存储位置

数据目录：macOS 是 `~/Library/Application Support/baocode`，Windows 是 `%APPDATA%\baocode`；设置了 `BAOCODE_DATA_DIR` 或者把数据目录迁移过时，以实际位置为准。

| 位置 | 内容 |
| --- | --- |
| `<数据目录>/updates/<版本>/<文件名>` | 下载完并通过校验的安装包 |
| `<数据目录>/updates/<版本>/<文件名>.part` | 下载到一半的文件（下次接着下） |
| `<数据目录>/updates/<版本>/staging/` | macOS 解压出的新 .app |
| `<数据目录>/updates/<版本>/install.sh` | macOS 替换脚本（执行完会删除自己） |
| `<数据目录>/updates/install.log` | macOS 替换脚本的日志（会一直追加） |
| `<数据目录>/User/settings.json` → `update.mode` | 更新方式 |
| `<数据目录>/state/storage.json` → `update.skippedVersion` | 跳过的版本 |
| `<数据目录>/state/storage.json` → `update.lastChecked` | 上次检查时间（UTC ISO 8601） |

| 环境变量 | 作用 |
| --- | --- |
| `BAOCODE_UPDATE_URL` | 改用另一个清单地址；同源的下载链接也会被接受；debug 构建也启用更新 |
| `BAOCODE_UPDATE_SIGNING_KEY` | 发布工具使用的私钥文件路径 |

`updates/` 没有加进 `DataDirectory.items`：迁移数据目录时不会复制它，丢了也只是重新下载一次。

---

## 10. 故障排查

**看日志**：应用用 `debugPrint` 输出以 `update:` 开头的日志。macOS 上从终端运行 `/Applications/BaoCode.app/Contents/MacOS/BaoCode` 就能看到；macOS 的替换过程看 `updates/install.log`。

| 现象 | 可能原因 | 处理 |
| --- | --- | --- |
| 设置页显示“此版本的 BaoCode 不支持自动更新” | 这是 debug 构建，或者不是 macOS / Windows | 用 release 构建；或者设置 `BAOCODE_UPDATE_URL` 测试 |
| 一直显示“已是最新版本” | 清单版本不比当前高（build 号没递增）；清单里没有本平台的条目；CDN 还在返回旧清单 | 检查 `version` 和平台键；清 CDN 缓存 |
| “检查更新失败：Invalid update manifest: …” | 清单格式有错；链接不在 baocode.dev 上 | 错误信息里会说明是哪个字段；用发布工具重新生成 |
| “检查更新失败：HTTP 404 / 超时” | 清单没上传，或者网络不通 | `curl` 一下清单地址 |
| “更新失败：The download is N bytes, not M” | 上传的文件不完整，或者清单里写的不是这个文件的 size | 重新上传；或者对实际上传的文件重新签名 |
| “更新失败：The download does not match its SHA-256” | 上传后文件被替换了，或者签名时用的不是同一个文件 | 对实际上传的文件重新运行发布工具 |
| “更新失败：The download is not signed by BaoCode” | 用错了私钥；手动改过清单的 version / platform / size / sha256 | 用正确的私钥重新签；清单不要手改（url 除外） |
| “更新失败：The download is larger than it should be” | 服务器返回的内容和 size 对不上（比如返回了一个 HTML 错误页） | 检查下载链接 |
| “BaoCode 无法在当前位置自动更新（BaoCode was not installed by its installer）” | Windows 上不是用安装包装的 | 用安装包重新安装 |
| “…（macOS runs BaoCode from a temporary place…）” | macOS 从 dmg 或下载目录直接运行（App Translocation） | 把应用拖到“应用程序”文件夹 |
| “…（Cannot write to …）” | .app 所在的目录不可写 | 换到可写的位置，或者从下载页手动更新 |
| macOS：“The update is another app” | zip 里的 bundle id 不是 `dev.baocode.desktop` | 检查打包 |
| macOS：“The update's code signature is not valid” / “signed by another developer” | 当前应用有正式签名，但新版本没签名，或者签名的 Team 不一样 | 用同一个 Developer ID 签名 |
| 点了“立即重启更新”，应用没退出 | 用户在退出确认框里点了取消；或者安装程序启动失败（会有通知） | 再点一次；看通知里的错误 |
| Windows：应用退出了，但没装、也没重新打开 | 用户拒绝了 UAC；Setup 出错了 | 重新打开应用，会再次提示；可以手动运行 `updates\<版本>\` 下的 setup 看具体报错 |
| macOS：应用退出了，但没有重新打开 | 看 `install.log`：等了 120 秒应用仍未退出，或者复制、改名失败（失败时会还原旧版） | 按日志处理；旧版本还在原位置 |
| macOS：`/Applications` 里残留 `.baocode-old` / `.baocode-new` | 替换过程中被中断 | 确认 `BaoCode.app` 能正常打开后，手动删掉残留 |
| 每次启动都重新下载 | `updates/` 不可写；或者下载完的文件校验不过 | 看日志 |

---

## 11. 真机验证清单

单元测试不会执行真正的安装、替换、提权。下面这些需要在真机上手动走一遍，可以按第 8 节的方法在本地提供更新。

### Windows

- [ ] 按机器安装（Program Files）的旧版本：更新时弹出 UAC → 静默安装 → 应用自动重新打开，版本号已更新
- [ ] 按用户安装（`%LOCALAPPDATA%\Programs`）的旧版本：更新时不弹 UAC，其他同上
- [ ] 桌面图标、PATH、右键菜单这些选项更新后保持原样
- [ ] 有运行中的 agent 时会先弹退出确认框；取消后应用保持运行，安装包还在
- [ ] 拒绝 UAC：应用已经退出，没有安装；重新打开应用后会再次提示
- [ ] 直接从 build 目录运行时，提示去下载页
- [ ] 安装包改动一个字节，或者换一个私钥签名：提示“更新失败”，`updates\` 下没有残留文件
- [ ] 下载到一半断网，恢复后接着下载（需要服务器支持 Range）

### macOS

- [ ] 放在 `/Applications` 里的 release 构建：更新后几秒内新版本自动打开，`/Applications/BaoCode.app` 已经是新版本，没有残留的 `.baocode-*`
- [ ] `install.log` 有记录；`xattr /Applications/BaoCode.app` 里没有 `com.apple.quarantine`
- [ ] 有未保存的文件或运行中的 agent 时，先弹确认框；取消后什么都不发生
- [ ] 从 dmg 里直接运行，以及放在只读目录里时，提示去下载页
- [ ] zip 里的 bundle id 不对时拒绝安装
- [ ] （签名公证做完以后）不同 Team 签名的 zip 被拒绝；同一个 Team 签名、已 staple 的 zip 能正常更新，Gatekeeper 不报警

---

## 12. 修改指南

**改检查的时间**：改 `UpdateService` 的 `firstCheckDelay`（30 秒）和 `checkInterval`（6 小时）这两个默认值，然后同步改 `update_service_test.dart` 里对应的时间。

**改域名或下载页**：域名在 `UpdateUrlPolicy.domain`；清单地址在 `defaultManifestUrl`；下载页在 `ManualUpdateRequired.downloadPage`；发布工具里的链接前缀在 `tool/release_manifest.dart` 的 `_releasesBase`，远程服务端的在 `tool/build_remote_server.dart` 的 `_downloadsBase`；CI 的上传地址在 `.github/workflows/release.yml`；`updates_page` 和文案里也提到了 baocode.dev。改完后跑 `flutter test test/update`。

**加一个平台**（比如 `windows-arm64`、Linux）：

1. 在 `installer_io.dart` 的 `platformUpdates()` 里返回新的平台键和对应的 `UpdateInstaller`。
2. 在发布工具里加对应的参数，并加进 `missing` 检查用的平台集合。
3. 在本文档的 5.2 节里加上新的平台键。

**改签名内容**：不要直接改 `v1` 的格式，否则已安装的旧版本会拒绝新签名的安装包。做法是：

1. 先让应用同时接受 `v1` 和 `v2` 两种格式，发一个版本，用 v1 签名。
2. 等大部分用户都更新到这个版本后，发布工具改成用 v2 签名。

**加新的校验**（比如校验 Authenticode 签名）：加在 `prepare()` 里。不通过时抛 `UpdateVerificationException` 表示拒绝安装；抛 `ManualUpdateRequired` 表示转去下载页。然后在 `installer_test.dart` 里用假的 `UpdateProcesses` 覆盖这两种情况。

**改界面文案**：在 `lib/l10n/app_en.arb` 和 `app_zh.arb` 里改 `update*`、`settingsSectionUpdates`、`cmdCheckForUpdates` 这些键，然后运行 `flutter gen-l10n`。`cmdCheckForUpdates` 的英文必须和命令目录里的标题 `Check for Updates...` 一致，`test/l10n_test.dart` 会检查。

**相关的改动点**（以后排查时有用）：

| 位置 | 做了什么 |
| --- | --- |
| `lib/main.dart` `_startUpdates()` | 创建 service 和 controller，交给 `AppSettings.updates` |
| `lib/main.dart` `onExitRequested` | 取消退出时 `disarm()`；确认退出后 `launchArmed()`，失败就取消退出 |
| `lib/workbench.dart` | `_checkForUpdates`（命令）、`_stopUpdateOffers`（主窗口监听自动发现的更新）、macOS 菜单标题 `checkForUpdates` |
| `lib/settings/settings_dialog.dart` | `SettingsSection.updates`（图标 cloudDownload） |
| `lib/keybindings/default_keybindings.dart` | `checkForUpdatesCommandId = 'update.checkForUpdate'` |
| `macos/Runner/MainFlutterWindow.swift` | `FileMenu.updatesItem`：应用菜单里的“检查更新…” |
| `tool/baocode.iss` | `[Run]` 里的 `RelaunchRequested` |
| `lib/platform/data_dir.dart` | `updatesDir` |

---

## 13. 已知限制与待办

- **macOS 签名与公证等证书**：`tool/build_macos.dart` 和 CI 都已支持，填好 Apple 的密钥就生效（[release.md 7.3](release.md#73-applemacos-签名与公证)）。在那之前，没签名的应用在别人的机器上**第一次安装**时会被 Gatekeeper 拦下。自动更新本身不受影响：下载由应用自己完成，不带 quarantine 属性，替换后脚本还会再清除一次。签名做完后，“同一个 Team”的检查会自动生效。
- **Windows 安装包没有 Authenticode 签名**：首次下载时 SmartScreen 可能会警告。自动更新只依赖 Ed25519 校验，不受影响。
- **没有发布渠道**（stable / beta）和灰度发布：所有用户读的都是同一份 `latest.json`。以后要做的话，可以给清单路径加上渠道（`releases/beta/latest.json`），并加一个设置项选择渠道。
- **没有增量更新**：每次都下载完整的安装包。
- **拒绝 UAC 之后**：应用已经退出，需要用户手动重新打开（下次启动会再提示更新）。
- **macOS 的 /Applications 归 root 所有时**：当前用户能改名 .app 但删不掉旧版本的内容时，`.baocode-old` 可能会残留。
- **服务端还没准备**：R2 存储桶、`dl.baocode.dev`、GitHub 的 `release` 环境，见 [release.md 第 7 节](release.md#7-第一次发布前的准备)。
