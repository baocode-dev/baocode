# 版本与发布

BaoCode 的版本号怎么定、一个版本怎么发出去、发到哪里、已安装的应用怎么拿到它，以及第一次发布前要准备什么。应用这一侧怎么检查、下载、校验、安装，见 [auto-update.md](auto-update.md)。

- 下载与更新：`https://dl.baocode.dev`（Cloudflare R2）
- 官网：`https://baocode.dev`（Cloudflare Worker `baocode` 的静态资源，`site/`；Workers Builds 从 GitHub 部署）
- 构建与发布：GitHub Actions，`.github/workflows/release.yml`
- 工具：`tool/bump_version.dart`、`tool/build_macos.dart`、`tool/build_windows.dart`、`tool/build_remote_server.dart`、`tool/release_manifest.dart`

## 目录

1. [全貌](#1-全貌)
2. [版本号](#2-版本号)
3. [发一个版本](#3-发一个版本)
4. [CI 做了什么](#4-ci-做了什么)
5. [dl.baocode.dev 上有什么](#5-dlbaocodedev-上有什么)
6. [更新的数据流](#6-更新的数据流)
7. [第一次发布前的准备](#7-第一次发布前的准备)
8. [出了问题](#8-出了问题)
9. [不用 CI，手动发布](#9-不用-ci手动发布)
10. [手机版](#10-手机版)
11. [浏览器扩展](#11-浏览器扩展)

---

## 1. 全貌

```
 你的机器                     GitHub                                Cloudflare
 ─────────                    ──────                                ──────────
 tool/bump_version.dart
 改版本号、写更新日志
 git push / git push 标签 ──▶ Actions：release.yml
                               ├ check    版本号对不对，不比已发布的旧
                               ├ remote   远程服务端（remote.yml）：在 Mac 上编译一次（Linux、macOS
                               │          各两种架构），Linux 版在 Docker 里跑一遍
                               ├ macos    构建、签名、公证（macOS 机器）
                               ├ windows  构建、打安装包（Windows 机器）
                               ├ linux    构建 .deb 和 tar.gz（x64、arm64 各一台 Ubuntu 22.04），装上启动一遍
                               └ publish  签 latest.json，上传 ────────▶ R2 存储桶
                                          建 GitHub Release              │
                                                                         ▼
                                                              dl.baocode.dev（CDN）
                                                               releases/latest.json
                                                               releases/<版本>/…
                                                               releases/remote/…
                                                                  ▲          ▲
                                     已安装的 BaoCode：每 6 小时读清单 ┘          │
                                     baocode.dev/download：读清单显示版本和链接 ──┘

 git push main ──────────────────────────────────────▶ Workers Builds ─▶ Worker baocode：baocode.dev
 git push 其他分支 ─────────────────────────────────▶ Workers Builds ─▶ 预览版本（不上线）
```

- **网站和安装包分开放**：网站是 Worker 的静态资源，推送 `main` 就发布，和应用的版本无关（见 3 节“发布官网”）；安装包在 R2 上，只有推送 `v*` 标签时才由 CI 发布。静态资源单个文件不能超过 25 MiB，dmg 放不下。
- **流量不收钱**：Worker 静态资源的请求不计费；R2 的下载流量免费，存储每月 10 GB 以内免费。
- **旧地址**：`site/_redirects` 把 `baocode.dev/releases/*` 302 到 `dl.baocode.dev/releases/*`，给改地址前打出来的构建用（应用的 `HttpClient` 会跟随重定向）。

## 2. 版本号

**写法**：`主.次.修订+build`，例如 `1.2.0+12`。写在两处，必须一样（`test/update/version_test.dart` 会检查，CI 也会检查）：

- `pubspec.yaml`：`version: 1.2.0+12`
- `lib/update/version.dart`：`const appVersionString = '1.2.0+12';`

**规则**

- `主.次.修订` 是给人看的版本（marketing 版本），按 semver：修 bug 加修订号，加功能加次版本号，不兼容的大改加主版本号。
- `+build` 是给机器比较的序号，**每次发布都加 1，永远不回退**。应用只接受比自己新的版本（先比 `主.次.修订`，再比 build），build 号没涨，用户就收不到。
- **标签**：`v` + marketing 版本，例如 `v1.2.0`。CI 会核对标签和 pubspec.yaml 是否一致。
- **同一个版本可以重新发布**（比如发出去才发现包有问题，修好后把标签挪到新提交上重推，见第 3 节）。下载链接末尾带着文件哈希（`?sha256=<前 16 位>`），重新发布后是新的地址，CDN 不会给出旧文件。但已经装上这个版本的用户不会再收到它（版本号没变），所以只适合还没人装上、或者问题不影响已装用户的时候；否则发 `1.2.1`。
- **预发布版**（`1.2.0-beta.1`）目前不支持：只有一个更新渠道，所有用户读同一份 `latest.json`，发 beta 就是发给所有人。以后要做的话见 [auto-update.md 第 13 节](auto-update.md#13-已知限制与待办)。

**改版本号用工具**，两处一起改，build 号自动加 1：

```sh
dart run tool/bump_version.dart patch    # 1.2.0+12 → 1.2.1+13
dart run tool/bump_version.dart minor    # 1.2.0+12 → 1.3.0+13
dart run tool/bump_version.dart major    # 1.2.0+12 → 2.0.0+13
dart run tool/bump_version.dart 1.4.0    # 1.2.0+12 → 1.4.0+13
```

**更新日志**：`release-notes/<版本>.en.md` 和 `release-notes/<版本>.zh.md`，是唯一的来源，不另外维护 CHANGELOG.md。它们会出现在：

- `latest.json`：设置 → 更新里显示（纯文本，按应用语言选）
- 网站的更新日志页 `baocode.dev/changelog`、`baocode.dev/zh/changelog`：`tool/build_changelog.dart` 生成 `site/changelog.html`、`site/zh/changelog.html`，跟 notes 一起提交（网站没有构建步骤，Cloudflare 原样发布 `site/`）。更新通知里的「更新日志」按钮直接打开这一页对应版本的位置（`#v1.2.0`）
- GitHub Release 的说明（英文那份）

`bump_version.dart` 会顺手生成草稿（`tool/draft_release_notes.dart`，也可以单独跑）：上一个标签以来的 `feat` / `perf` / `fix` 提交标题，分到「New / Improved / Fixed」（中文「新功能 / 改进 / 修复」）下面，不含 `site`、`ci` 的提交。提交标题是写给开发者的，**草稿要改写成用户看得懂的话**，每版十行左右，中文那份写中文。格式只用普通段落和 `-` 列表：设置页按纯文本显示，标题、加粗之类的 Markdown 符号会原样露出来。

没有 notes 也能发，但 CI 会给出警告：通知里没有「更新日志」按钮，网站上也没有这个版本，GitHub Release 改用自动生成的提交列表。`test/tool/build_changelog_test.dart` 会检查网站页面是不是最新的。

## 3. 发一个版本

以发布 `1.2.0` 为例：

```sh
dart run tool/bump_version.dart minor          # 1.1.3+12 → 1.2.0+13，并生成更新日志草稿
# 改写 release-notes/1.2.0.en.md、release-notes/1.2.0.zh.md
dart run tool/build_changelog.dart             # 生成网站的更新日志页
flutter test test/update/version_test.dart test/tool/build_changelog_test.dart
git add pubspec.yaml lib/update/version.dart release-notes/ site/changelog.html site/zh/changelog.html
git commit -m "chore: release 1.2.0"
git push origin main
git tag v1.2.0
git push origin v1.2.0                          # 从这里开始 CI 接手
```

然后在 GitHub 的 Actions → Release 里看进度（如果给 `release` 环境设了审批人，要点一下 Approve）。macOS 公证要等几分钟，整个流程大约 20～30 分钟。

macOS 最常见的失败是钉票据（`stapler staple`）：Apple 的 CloudKit 会连续几分钟断开连接（-1005，stapler 报 Error 68），公证本身是成功的。`build_macos.dart` 遇到这种情况会退避重试，总共约 12 分钟。还不行的话，`release-retry.yml` 会把失败的任务自动重跑一次（只在第一次失败、且失败任务里有 macOS 构建时）。换一台机器通常就能过。再失败就要手动 Re-run。

完成后确认：

- [ ] `curl -s https://dl.baocode.dev/releases/latest.json` 是新版本
- [ ] `https://baocode.dev/download` 显示新版本，两个按钮都能下载
- [ ] `https://baocode.dev/changelog` 有这个版本
- [ ] 装着旧版本的机器上点“检查更新”，能发现、下载、重启装上

**重新发布同一个版本**（标签挪到新提交上）：

```sh
git push origin :refs/tags/v1.2.0                # 删掉远端的标签
git tag -f v1.2.0 && git push origin v1.2.0      # 打在现在的提交上，重新推
```

CI 会照常构建，覆盖 R2 上的文件，重新建 GitHub Release。

**只想试一下构建**：Actions → Release → Run workflow。只构建、不发布，产物在这次运行的 Artifacts 里（要登录 GitHub 才能下载）。

**打测试包给别人**：在要测的提交上打一个 `test-` 开头的标签并推送：

```sh
git tag test-upstream-import && git push origin test-upstream-import
```

CI 照常构建，然后把安装包传到 `dl.baocode.dev/test/<版本>-<标签去掉 test->-<运行编号>/`，链接写在这次运行的 Summary 里，直接发给测试的人，不用登录 GitHub。用的是 `release` 环境里已有的 R2 令牌（环境允许 `test-*` 标签，见 7.2），不签更新清单。同一个标签再测一次：`git tag -f … && git push -f origin …`。

- 不是更新：`test/` 不在 `releases/` 下，`latest.json` 不变，已安装的应用不会收到它。
- 版本号就是分支上 `pubspec.yaml` 的版本。测试的人之后会照常收到比它新的正式版。
- macOS 包的签名和正式版一样（现在是 ad hoc，第一次打开要在 系统设置 → 隐私与安全性 里点“仍要打开”；配上 7.3 的证书后两者都会正式签名）。
- 远程服务端也会传到 `releases/remote/<它的版本>/`（按内容定版本，不影响已发布的），测试包连 SSH 主机时要用。
- 旧测试包不会自动删：可以在 R2 存储桶的 Settings → Object lifecycle rules 给前缀 `test/` 加一条“30 天后删除”。

**单独发布远程服务端**：在要发的提交上打一个 `server-` 开头的标签并推送：

```sh
git tag server-1.0.7-ssh-fix && git push origin server-1.0.7-ssh-fix
```

`.github/workflows/remote.yml` 编译四个平台的服务端、在 macOS 和 Docker 里的 Linux 上各跑一遍，然后把 `.gz` 和 `servers.json` 传到 `releases/remote/<VERSION>/`，最后更新 `releases/remote/latest.json`（指向这份）。不构建应用、不动应用的 `latest.json`，已安装的应用不受影响。用途是**本机打的包**：本机编出来的服务端 `VERSION` 和 CI 的对不上，线上没有，连主机会报 404；打包时改用已发布的那份：

```sh
dart run tool/build_windows.dart --remote-release            # 最新发布的服务端
dart run tool/build_windows.dart --remote-release <VERSION>  # 指定的那份
dart run tool/build_macos.dart --remote-release              # macOS 同理
```

脚本用 `tool/fetch_remote_server.dart` 取 `servers.json`、确认每个 `.gz` 都能下载，放进 `build/remote-release/` 再打包。应用和服务端是严格一一对应的内部协议（docs/ssh-remote.md），**服务端要从和应用相同（至少 `packages/bao_remote` 相同）的提交发布**，否则连上后可能出错。正式发版（`v*`）也会传 `servers.json`、更新 `releases/remote/latest.json`。

**发布官网**：和应用发版无关，推送到 `main` 就由 Cloudflare Workers Builds 部署到 baocode.dev（GitHub 上这个提交的检查里有“Workers Builds: baocode”）。

- 先预览：推送任何别的分支，Workers Builds 只上传一个预览版本、不上线。预览地址是 `https://<版本 ID 前 8 位>-baocode.leokun-cn.workers.dev`，版本 ID 在那个提交的“Workers Builds: baocode”检查详情里。
- 只发官网：把 `site/` 的改动单独提交推到 `main` 即可，`main` 上没发版的应用代码不受影响（应用只在推 `v*` 标签时发布）。

## 4. CI 做了什么

`.github/workflows/release.yml`，推送 `v*` 标签时运行：

| Job | 机器 | 做什么 |
| --- | --- | --- |
| `check` | Ubuntu | pubspec.yaml 和 `version.dart` 一致；版本是 `x.y.z+build`；标签是 `v<x.y.z>`；不比 `dl.baocode.dev` 上已发布的版本旧（一样就是重新发布，给个提示） |
| `remote` | | 调用 `remote.yml`（推 `server-*` 标签时它也单独运行并发布，见第 3 节），下面两步 |
| `remote` › `build` | macOS 15 | 下载和 Flutter 同版本的 x64 Dart SDK → 编译远程服务端（`--all`：Linux x64/arm64 交叉编译；macOS arm64 用本机的 dart，macOS x64 用 x64 的 dart 经 Rosetta，`dart compile exe` 只能在 Mac 上、按 dart 自己的架构编 macOS 版）→ `tool/test_remote_server_macos.sh`：在这台 Mac 上把两份 macOS 版各跑一遍 → 上传 `remote`（`VERSION`、`servers.json`、`.gz`）和 `remote-linux`（Linux 的两个二进制）两个产物 |
| `remote` › `linux` | Ubuntu | `tool/test_remote_server.sh`：在 Docker 里的 Ubuntu 20.04 / 24.04、Debian 12、Rocky Linux 8 上，两种架构各跑一遍（arm64 用 QEMU 模拟），要能启动、回答 `initialize`、列出目录 |
| `macos` | macOS 15 | 有证书就导入临时钥匙串 → `tool/build_macos.dart --remote-built`：构建 universal 的 .app，**检查是 universal**（每个可执行文件都有 arm64 和 x86_64）→ 放进 `remote` 任务的 `servers.json` → 用 `ditto --arch` 拆成 Apple silicon（arm64）和 Intel（x64）两个应用，各自检查只剩一种架构，下面每个各做一遍：→ 签名（有证书用 Developer ID，带 hardened runtime；没有就 ad hoc，**不带** hardened runtime，否则系统拒绝加载应用自己的框架、一启动就崩；总要重签，因为放进去的文件要包进签名）→ 做 dmg → 有证书时签 dmg、公证、钉票据 → 打更新用的 zip → **把两个 zip 解开各真正启动一次**（Intel 版经 Rosetta），15 秒内退出就不发 |
| `windows` | Windows（x64 在 `windows-latest`，arm64 在 `windows-11-arm`） | 装 Inno Setup → `tool/build_windows.dart --remote-built --arch <x64\|arm64>`：构建、放进 `servers.json`、打安装包。Flutter 只能给本机架构构建，所以 arm64 在 Arm 机器上编；Flutter 的 Windows 压缩包里是 x64 的 Dart，arm64 改为按标签 clone Flutter。arm64 没有打过补丁的引擎（`tool/engine/`），用 Flutter 自带的；OpenSSH 用 `OpenSSH-ARM64.zip`。安装包 `BaoCode-<版本>-setup-arm64.exe`，和 x64 同一个 AppId，互相覆盖安装 |
| `publish` | Ubuntu | 汇总产物 → 用更新私钥签 `latest.json`（`tool/release_manifest.dart`，带上 dmg 给网站用）→ 上传远程服务端 → 上传安装包 → 按清单里的链接确认 CDN 给出的文件大小对 → **最后**上传 `latest.json` → 建 GitHub Release（附两个 dmg 和 exe；重新发布时先删掉旧的） |

几个设计上的考虑：

- **`latest.json` 最后传**：应用一读到新清单就会去下载，安装包必须先就位。
- **远程服务端只编译一次**：`remote` 任务编译，macOS 和 Windows 两个应用带的是同一份 `servers.json`（四个平台都有），R2 上一个版本只有一个 `releases/remote/<版本>-<二进制哈希>/`。
- **下载链接带哈希**：`latest.json` 里每个链接末尾是 `?sha256=<文件哈希前 16 位>`。CDN 按完整地址缓存，文件换了地址就换了，不会给出旧文件；应用取文件名时只看路径。
- **`downloads`**：`latest.json` 里多了这一项，是给网站用的（两个 dmg 和 Windows 安装包的链接、大小，键是 `macos-arm64`、`macos-x64`、`windows`、`windows-arm64`、`linux-x64`、`linux-arm64`），应用不读它。Windows on Arm 的应用按 `windows-arm64` 更新；x64 版在 Arm 上（模拟运行）继续按 `windows-x64` 更新，不自动换。
- **密钥只在 `release` 环境里**，只有 `v*` 标签能用（见 7.2）。PR 和手动运行拿不到。
- Flutter 版本固定在工作流的 `FLUTTER_VERSION`，升级 Flutter 时一起改。

## 5. dl.baocode.dev 上有什么

R2 存储桶，绑定自定义域名 `dl.baocode.dev`，前面是 Cloudflare 的 CDN。

```
releases/
  latest.json                            应用和下载页读的清单          max-age=300
  1.2.0/
    BaoCode-1.2.0-setup.exe              Windows：首次安装和自动更新   immutable，一年
    BaoCode-1.2.0-setup-arm64.exe        Windows on Arm：同上          immutable，一年
    BaoCode-1.2.0-mac-arm64.zip          macOS Apple silicon：自动更新 immutable，一年
    BaoCode-1.2.0-mac-x64.zip            macOS Intel：自动更新         immutable，一年
    BaoCode-1.2.0-arm64.dmg              macOS Apple silicon：首次安装 immutable，一年
    BaoCode-1.2.0-x64.dmg                macOS Intel：首次安装         immutable，一年
  remote/
    latest.json                          最新发布的服务端（--remote-release 用） max-age=60
    <VERSION>/                           远程服务端，应用连远程主机时按需下载
      servers.json                       各平台的地址、大小、SHA-256（--remote-release 用）
      baocode-server-linux-x64.gz        immutable，一年
      baocode-server-linux-arm64.gz
      baocode-server-darwin-x64.gz
      baocode-server-darwin-arm64.gz
```

- **旧版本一直保留**：下载页只链最新版，但 `remote/` 下旧目录还有旧版本的用户在用，删了他们连不上远程主机。
- **`latest.json` 缓存 5 分钟**：Cloudflare 默认不缓存 `.json`，每次都回源到 R2（算一次读取，每月 1000 万次免费）；浏览器和中间代理最多缓存 5 分钟。
- 清单格式、链接规则见 [auto-update.md 第 5 节](auto-update.md#5-服务端约定)。

## 6. 更新的数据流

**发布时**（CI 的 `publish`）：

1. 对每个平台的安装包算 SHA-256，用 Ed25519 私钥签 `baocode-update-v1 / 版本 / 平台 / 大小 / SHA-256` 这段文本。
2. 写出 `latest.json`：版本、日期、更新日志、每个平台的 `url / size / sha256 / signature`。
3. 安装包上传到 `releases/<版本>/`，`latest.json` 覆盖 `releases/latest.json`。

**已安装的应用**（`update.mode` 是默认的“自动检查并下载”时）：

1. 启动 30 秒后、之后每 6 小时，GET `https://dl.baocode.dev/releases/latest.json`。
2. 解析清单；下载链接必须是 `https://*.baocode.dev`。版本不比自己新，或者没有本平台的条目 → 已是最新，结束。
3. 后台下载本平台的安装包（Mac 按处理器取 Apple silicon 或 Intel 的包，见 [auto-update.md 5.2](auto-update.md#52-latestjson-格式)）到 `<数据目录>/updates/<版本>/`，支持断点续传。
4. 依次校验大小 → SHA-256 → Ed25519 签名（公钥内置在应用里）。任何一项不过就删掉，报错。macOS 还会检查新 .app 的 bundle id，以及在当前应用有正式签名时，新 .app 是不是同一个 Team 签的。
5. 主窗口右下角弹通知。用户点“立即重启更新”后，走和平时退出一样的确认（未保存的文件、运行中的 agent 和终端），确认了才安装：
   - Windows：应用退出后，带 `/SILENT /RELAUNCH` 运行新的 setup.exe，覆盖安装到原来的位置，再重新打开。
   - macOS：解压出新 .app，等应用退出后由脚本替换原来的 BaoCode.app，再打开。
6. 新版本启动时清理 `updates/` 里旧版本的下载。

设置和对话放在数据目录里，不在安装目录里，更新不会动它们。

**官网**（首页和 `baocode.dev/download`，`site/site.js`）：浏览器读同一份 `latest.json`，按其中的 `downloads` 换上版本号、两个 dmg 和 Windows 安装包的链接（带哈希）和大小。下载页的 macOS 卡片有 Apple silicon 和 Intel 两个按钮，默认突出 Apple silicon；Chromium 系浏览器能报出处理器架构，Intel Mac 上会改为突出 Intel（`site/download.js`）。需要 R2 的 CORS 允许 `https://baocode.dev`（见 7.1）。读不到时显示页面里写死的版本；页面里的下载链接本身写的是 `/dl/windows`、`/dl/windows-arm64`、`/dl/macos-arm64`、`/dl/macos-x64`（Arm64 的按钮先隐藏，`site.js` 读到清单里有 `windows-arm64` 才显示），由 Worker（`site-worker/index.js`，只接管 `/dl/*`）按当时的 `latest.json` 302 到对应安装包，所以脚本没跑完、被拦或页面被缓存时下到的也是最新版，发版不用改页面里的链接。

**两把“钥匙”管的是不同的事**：

| | 防的是什么 | 没有它会怎样 |
| --- | --- | --- |
| 更新签名私钥（Ed25519） | 有人篡改 `dl.baocode.dev` 上的文件或劫持网络，给所有用户推恶意更新 | 发不了更新；泄露的话，后果见 [auto-update.md 6.3](auto-update.md#63-保管) |
| Apple Developer ID + 公证 | macOS 的 Gatekeeper 拦截从网上下载的未知应用 | 用户第一次打开 dmg 里的应用时被拦：“已损坏，无法打开” |
| Windows 代码签名（还没做） | SmartScreen 的“未知发布者”警告 | 第一次安装时多点一次“仍要运行” |

自动更新只依赖第一把：应用自己下载的文件不带隔离属性，不经过 Gatekeeper 和 SmartScreen。

## 7. 第一次发布前的准备

全部是一次性的。**这些值都直接填进 GitHub 或 Cloudflare 的后台，不要发到聊天里，也不要提交到仓库。**

### 7.1 Cloudflare

1. **R2 存储桶**：R2 → Create bucket，名字比如 `baocode-downloads`。
2. **自定义域名**：存储桶 → Settings → Custom Domains → Connect Domain → `dl.baocode.dev`。不要开 `r2.dev` 公共地址。
3. **CORS**（给下载页读 `latest.json`）：存储桶 → Settings → CORS Policy：
   ```json
   [
     {
       "AllowedOrigins": ["https://baocode.dev"],
       "AllowedMethods": ["GET", "HEAD"],
       "AllowedHeaders": ["*"],
       "MaxAgeSeconds": 3600
     }
   ]
   ```
4. **API 令牌**：R2 → Manage R2 API Tokens → Create API token，权限 **Object Read & Write**，范围**只选这个存储桶**。记下 Access Key ID 和 Secret Access Key（只显示一次），以及页面上的 Account ID。
5. **网站**：Worker `baocode`，静态资源是 `site/`（`_headers`、`_redirects` 照常生效），Settings → Builds 连着 GitHub 仓库（生产分支 `main`），自定义域名 `baocode.dev`。

### 7.2 GitHub

1. **环境**：Settings → Environments → New environment，名字 `release`。
   - Deployment branches and tags → Selected branches and tags → 加三条 **Tag**，规则 `v*`、`test-*` 和 `server-*`。只有这几种标签触发的运行能用这个环境里的密钥；`test-*` 的运行只往 R2 的 `test/` 传安装包，不签、不传 `latest.json`；`server-*` 的只传 `releases/remote/`。
   - 可选：Required reviewers 加上你自己。每次发布要你在 Actions 里点一下批准，多一道保险。
2. **环境密钥**（`release` 环境 → Environment secrets）：

   | 名字 | 值 |
   | --- | --- |
   | `UPDATE_SIGNING_KEY` | `~/.baocode-release/update-signing.key` 的内容（一行 base64） |
   | `R2_ACCOUNT_ID` | Cloudflare 的 Account ID |
   | `R2_ACCESS_KEY_ID` | R2 令牌的 Access Key ID |
   | `R2_SECRET_ACCESS_KEY` | R2 令牌的 Secret Access Key |
   | 下面 7.3 的六个 | 有 Apple 开发者账号之后再加 |

3. **环境变量**（`release` 环境 → Environment variables）：`R2_BUCKET` = 存储桶名字。
4. **保护标签**：Settings → Rules → Rulesets → New tag ruleset，目标 `v*`，限制创建、更新、删除，只允许你自己绕过。这样只有你能发版。

更新签名私钥放进 GitHub 之后，本机和离线备份仍然要留着（见 [auto-update.md 6.3](auto-update.md#63-保管)）。

### 7.3 Apple（macOS 签名与公证）

**需要 Apple 开发者账号吗？** 要。没有的话应用照样能构建、能自动更新，但新用户第一次从网上下载打开时会被 Gatekeeper 拦下（“BaoCode 已损坏，无法打开”），只能在终端里运行 `xattr -dr com.apple.quarantine` 才能打开。对外发布基本绕不过去。

1. **加入 Apple Developer Program**（每年 99 美元）：<https://developer.apple.com/programs/enroll/>
   - 我们**以个人身份**加入：用本人的 Apple ID（要开双重认证）。中国大陆的表单要求填身份证上的中文姓名和身份证号。在 iPhone 或 Mac 的 Apple Developer App 里注册最快，要拍证件做身份验证；也可以在网页上注册。付款后一般一两天内通过。
   - 证书上显示的是个人姓名（`Developer ID Application: <姓名> (<Team ID>)`），用户在签名信息里能看到，双击打开时的提示里看不到。
   - 以后想改成组织：可以联系 Apple 把个人账号转成组织账号（需要 D-U-N-S 编号）。转换前向 Apple 确认 Team ID 不变，否则见下面的注意。
2. **Developer ID Application 证书**：只有账号持有人（Account Holder）能创建。
   - 在 Mac 上打开 Xcode → Settings → Accounts → 登录 Apple ID → Manage Certificates → 左下角 `+` → **Developer ID Application**。
   - 打开“钥匙串访问” → 登录 → 我的证书 → 找到 “Developer ID Application: <名字> (<Team ID>)” → 右键导出为 `.p12`，设一个密码。
   - 终端运行 `security find-identity -v -p codesigning`，复制那一行开头的 40 位十六进制指纹（也可以用引号里的完整名字，但名字里有中文时用指纹更稳）。
3. **公证用的 API 密钥**：App Store Connect → 用户和访问 → 集成 → App Store Connect API → 团队密钥 → `+`，访问权限选 **Developer**。下载 `.p8` 文件（只能下载一次），记下 Key ID 和页面上方的 Issuer ID。
4. **填进 `release` 环境的密钥**：

   | 名字 | 值 |
   | --- | --- |
   | `MACOS_CERTIFICATE` | `base64 -i 证书.p12 \| pbcopy` 复制出来的内容 |
   | `MACOS_CERTIFICATE_PASSWORD` | 导出 `.p12` 时设的密码 |
   | `MACOS_SIGN_IDENTITY` | 第 2 步复制的指纹，例如 `1A2B3C…`（40 位）；或完整名字 `Developer ID Application: <姓名> (<Team ID>)` |
   | `NOTARY_KEY` | `.p8` 文件的全部内容（包括 `-----BEGIN PRIVATE KEY-----` 那两行） |
   | `NOTARY_KEY_ID` | Key ID |
   | `NOTARY_ISSUER` | Issuer ID |

5. 先用 Actions → Release → Run workflow 试一次：手动运行拿不到密钥，所以这一步只验证构建本身。要验证签名和公证，就发一个真实版本，或者在本机按第 9 节手动跑 `tool/build_macos.dart`。

**注意**

- **Team 一旦用上就别换**：应用正式签名之后，只接受同一个 Team 签名的更新（`lib/update/installer_io.dart`）。从 ad hoc 签名的版本（现在的 1.0.0）更新到第一个正式签名的版本没问题；之后换 Team（比如另注册一个组织账号），老用户就得手动重装一次。
- **证书有效期 5 年**：到期前在同一个 Team 下新建一张，换掉 `MACOS_CERTIFICATE` 等密钥即可，Team 不变，老用户不受影响。已经公证过的版本过期后仍然能打开。
- **不需要提供给我**：证书、密码、密钥都只填在 GitHub 里。脚本和工作流已经按上面这些名字写好了，填好就能用。

## 8. 出了问题

| 情况 | 怎么办 |
| --- | --- |
| `check` 失败：版本不一致 / 标签不对 | 按报错改，删掉远端标签（`git push origin :refs/tags/v1.2.0`），重新打标签推送 |
| `check` 失败：比已发布的旧 | `tool/bump_version.dart` 加到比已发布的新 |
| `remote` › `linux` 失败：Docker 里跑不起来 | 日志里有每个系统、每种架构的结果和服务端的输出。在本机用 `dart run tool/build_remote_server.dart && tool/test_remote_server.sh` 复现（需要 Docker） |
| `remote` › `build` 失败：macOS 版没编出来或跑不起来 | 多半是下载 x64 Dart SDK 失败（Flutter 带的 Dart 版本在 dart-archive 上没有对应的包），或 Rosetta 没装上。在 Apple silicon 的 Mac 上用 `dart run tool/build_remote_server.dart --all --macos-x64-dart <x64 sdk>/bin/dart && tool/test_remote_server_macos.sh` 复现 |
| `macos` 失败：Not universal | 某个框架只编了一种架构，日志里列出了是哪个。拆出来的某个包会少这个框架的代码，在用到它时崩溃，所以不发 |
| `macos` 公证失败 | 日志里有 Apple 返回的详细原因（哪个文件、什么问题）。常见原因：某个二进制没开 hardened runtime、没有时间戳 |
| `publish` 在上传 `latest.json` 之前失败 | 用户什么都看不到。修好后按第 3 节重新发布同一个版本即可 |
| 发出去的版本有问题 | 尽快发一个修复版（版本号更高）。也可以把上一版的 `latest.json` 传回去，让还没更新的人停在旧版，但已经更新的人不会被降级。见 [auto-update.md 5.5](auto-update.md#55-撤回一个版本) |
| 用户报“检查更新失败” | 见 [auto-update.md 第 10 节](auto-update.md#10-故障排查) |

## 9. 不用 CI，手动发布

CI 不可用时的备用办法，步骤和 CI 一样：

```sh
# macOS 上：先把四份远程服务端都编好（x64 的 Dart SDK 见 docs/ssh-remote.md 9.1）
dart run tool/build_remote_server.dart --all --macos-x64-dart <x64 sdk>/bin/dart
# 然后打包（有证书的话先设好第 7.3 节对应的环境变量，见 tool/build_macos.dart 开头）
dart run tool/build_macos.dart --remote-built
# Windows 上：把 Mac 上的 build/remote/ 拷过来，用同一份（自己编的没有 macOS 版）
dart run tool/build_windows.dart --remote-built

# 有私钥的机器上，两个平台的包都拷过来之后
BAOCODE_UPDATE_SIGNING_KEY=~/.baocode-release/update-signing.key \
  dart run tool/release_manifest.dart \
    --windows build/installers/BaoCode-1.2.0-setup.exe \
    --macos-arm64 build/installers/BaoCode-1.2.0-mac-arm64.zip \
    --macos-x64   build/installers/BaoCode-1.2.0-mac-x64.zip \
    --dmg-arm64   build/installers/BaoCode-1.2.0-arm64.dmg \
    --dmg-x64     build/installers/BaoCode-1.2.0-x64.dmg \
    --notes-en release-notes/1.2.0.en.md --notes-zh release-notes/1.2.0.zh.md
```

然后按顺序上传到 R2（Cloudflare 后台直接拖，或者用 `wrangler r2 object put`）：

1. `build/installers/remote/<VERSION>/*` → `releases/remote/<VERSION>/`（两台机器的 `<VERSION>` 不同就都传）
2. 安装包 → `releases/1.2.0/`
3. 确认下载链接能打开、大小对
4. **最后** `build/installers/latest.json` → `releases/latest.json`

macOS 本机签名时用的环境变量：

| 变量 | 值 |
| --- | --- |
| `BAOCODE_MACOS_SIGN_IDENTITY` | 证书的 40 位指纹，或 `Developer ID Application: <名字> (<Team ID>)`；证书在钥匙串里 |
| `BAOCODE_NOTARY_KEY` | `.p8` 文件的路径 |
| `BAOCODE_NOTARY_KEY_ID` | Key ID |
| `BAOCODE_NOTARY_ISSUER` | Issuer ID |

只设 `BAOCODE_MACOS_SIGN_IDENTITY` 就只签名、不公证；都不设就是 ad hoc 签名。

## 10. 手机版

手机版（Android 的 APK、iOS 走 TestFlight）由 `.github/workflows/mobile.yml` 构建，和桌面版分开发布，版本号也分开（手机版 `pubspec.yaml` 里的版本，`0.x` 算 Beta）。官网下载页的 Android 按钮是 `/dl/android`，由 `site-worker/index.js` 按 `releases/mobile/latest.json` 跳转到当前版本。

```sh
git tag mobile-v0.1.0 && git push origin mobile-v0.1.0      # 发布：标签要和手机版的版本一致
git tag mobile-test-foo && git push origin mobile-test-foo  # 测试包：APK 传到 dl.baocode.dev/test/mobile-…，iOS 照样传 TestFlight
```

CI 从 `baocode-dev/mobile` 的 main 取代码（放在本仓库旁边，`../monad` 的包照常能找到），分两台机器构建：

- **Android**（Ubuntu）：`flutter build apk --release`，用发布密钥签名。每个版本都要用**同一把密钥**，否则装不上旧版之上，只能卸载重装。
- **iOS**（`macos-26`，要 Xcode 26：App Store Connect 只收 iOS 26 SDK 编的包）：导入 Apple Distribution 证书和 App Store 描述文件 → 把工程里 Runner 目标的 Release 配置改成手动签名（工程本身是自动签名，要登录开发者账号，CI 上没有；只改 Runner，Pods 的目标不能带描述文件）→ `flutter build ipa`，build 号用本工作流的 run number（TestFlight 不收重复的 build 号）→ `xcrun altool --upload-app` 用 App Store Connect API Key 上传到 TestFlight。**`mobile-test-*` 也上传**：iOS 的测试员走 TestFlight。上传后苹果要处理几分钟，测试员才看得到。

APK 上传时用 `--content-type` 说明类型（`application/vnd.android.package-archive`）。

发布时 APK 传到 `releases/mobile/<版本>/`，最后写 `releases/mobile/latest.json`（`version`、`pubDate`、`beta`、`downloads.android` 的 `url / size / sha256`）。桌面版的 `latest.json` 不受影响。

iOS 在 App Store Connect 上的 App 是 **BaoCode**（Apple ID `6825371537`，Bundle ID `dev.baocode.mobile`，Team `77SLP2NCVR`）。证书和描述文件一年一换：到期前用 App Store Connect API（或开发者网站）新建 Apple Distribution 证书、用它重做 App Store 描述文件，换掉下面三个密钥。

TestFlight 上每个 build 都要回答出口合规（加密）问题，否则停在「缺少合规证明」；在手机版的 `Info.plist` 里加 `ITSAppUsesNonExemptEncryption` 就不用每次回答。

**`release` 环境里要有的**（7.2 那些之外）：

| 名字 | 是什么 |
| --- | --- |
| `MOBILE_DEPLOY_KEY` | 读 `baocode-dev/mobile` 的部署密钥（私钥）。公钥加在那个仓库的 Settings → Deploy keys，只读即可 |
| `ANDROID_KEYSTORE` | Android 发布密钥库（`.jks`）的 base64 |
| `ANDROID_KEYSTORE_PASSWORD` | 它的密码（密钥别名 `baocode`，密钥密码与之相同） |
| `IOS_CERTIFICATE` | Apple Distribution 证书 `.p12` 的 base64 |
| `IOS_CERTIFICATE_PASSWORD` | 它的密码 |
| `IOS_PROFILE` | `dev.baocode.mobile` 的 App Store 描述文件（`.mobileprovision`）的 base64 |

上传 TestFlight 用的是 7.3 公证用的那把 App Store Connect API Key（`NOTARY_KEY`、`NOTARY_KEY_ID`、`NOTARY_ISSUER`），它的职能是 App 管理，两件事都够用。

环境的部署规则里要允许 `mobile-*` 标签。

下载页这两张卡片各带一个二维码（`site/qr/android.svg`、`site/qr/ios.svg`，鼠标悬停或点击卡片时显示）：码里是卡片自己那个按钮的链接，也就是 `/dl/android`、`/dl/ios`，扫到就跳到当时最新的那版安装包。链接变了就先跑 `dart run tool/make_download_qr.dart` 重新生成（`test/tool/download_qr_test.dart` 会检查页面、按钮和码三者一致）。**别把 `dl.baocode.dev` 上带哈希的直链写进码里**：那地址每次发版都换，码是要能一直用的。`latest.json` 里已经没有 iOS 的包：`/dl/ios` 跳到 TestFlight 公开测试的链接（`site-worker/index.js` 的 `TESTFLIGHT`，App Store Connect → BaoCode → TestFlight → Public beta），每个 build 都是这一个，上了 App Store 再换。Android 的卡片暂时下线（`MOBILE_OFFLINE`），`/dl/android` 跳回下载页。

> 发布密钥库丢了就再也发不了能覆盖安装的 APK：本机和 CI 之外务必另存一份。

## 11. 浏览器扩展

浏览器扩展（`browser_extension/`，原理见 `lib/browser/browser_bridge.dart`）由 `.github/workflows/extension.yml` 打包发布，版本号就是 `manifest.json` 里的 `version`，和应用、手机版都分开。用户有两种装法，官网下载页「浏览器扩展」一节两个按钮都有：

- **Chrome 应用商店**（`/dl/chrome-web-store`）：自动更新。
- **开发者模式**（`/dl/browser-extension`）：下载 zip，解压后在 `chrome://extensions` 里「加载已解压的扩展程序」。不会自动更新。

两种装法的扩展 ID 一样，都是 `jfjagocghaaheooicmdnhcholmgdkngk`：开发者模式的 zip 里 `manifest.json` 带着 `key`，商店版是第一次上传时带上私钥 `key.pem` 定下的（见 [docs/browser-extension-store](browser-extension-store/README.md#第一次上传)）。应用只认这个 ID（`BrowserBridge.extensionIds`），CI 会检查 `key` 算出来的 ID 和它一致。私钥在 `~/.baocode-signing/browser-extension.pem`，丢了也不影响已上架的扩展（商店有自己的签名），但开发者模式的 ID 就没法再算出来了，务必另存一份。

```sh
# 先改 browser_extension/manifest.json 的 version（商店要求每次上传版本号都更大）
git tag extension-v0.2.0 && git push origin extension-v0.2.0         # 发布：标签要和 manifest 的版本一致
git tag extension-test-foo && git push origin extension-test-foo     # 只打包，传到 dl.baocode.dev/test/extension-…
```

本地打包：`tool/pack_browser_extension.sh`，产物在 `build/browser_extension/`。

CI 做的事：

| Job | 做什么 |
| --- | --- |
| `pack` | 标签和版本一致；`node --check` 检查 `background.js`；`key` 算出的 ID 等于应用认的 ID；manifest 里提到的文件都在；打两个 zip。改了扩展的 PR 也会跑这一步 |
| `share` | `extension-test-*`：两个 zip 都传到 `test/` |
| `publish` | 开发者模式的 zip 传到 `releases/extension/<版本>/`，最后写 `releases/extension/latest.json`（`version`、`pubDate`、`id`、`store`、`downloads.browser-extension`） |
| `store` | 用 Chrome Web Store API 上传商店的 zip 并提交审核，审核通过后自动上架。没配凭据就跳过，提示手动上传（凭据怎么拿见 [docs/browser-extension-store](browser-extension-store/README.md#ci-自动提交之后每个版本)） |

商店地址由官网维护：`latest.json` 的 `store`，默认是用 ID 拼出来的 `https://chromewebstore.google.com/detail/<ID>`，要换别的就在 `release` 环境的变量 `CHROME_WEB_STORE_URL` 里填，再推一次标签（或手动改 `latest.json`），不用发新版应用。官网的 `/dl/chrome-web-store` 跳过去（读不到 `latest.json` 时也跳 ID 地址）；应用里的按钮（`lib/browser/extension_store.dart`）每次运行拉一次，存在缓存目录的 `browser/store`，拉不到用上次存的，从没拉到过就用 ID 地址。

环境的部署规则里要允许 `extension-*` 标签。

**少发扩展**：扩展只做应用做不了的事：通信、共享标签页的边界（应用的任何请求都越不过它）、工具栏按钮。页面里的一切走 DevTools 协议原样转发（`cdp`，带 `sessionId` 时是页面里 iframe、worker 的会话，事件也带 `sessionId`）；标签页、窗口、分组走 `call`（`chrome.tabs.*`、`chrome.windows.*`、`chrome.tabGroups.*`，只能碰共享的标签页，返回的也只有共享的）和 `subscribe`（这几类的事件，只报共享标签页的）；行为开关走 `configure`（如 `followOpeners`：共享标签页打开的新标签页自动共享，默认开）。所以新功能基本只改应用。只有要新的浏览器权限（manifest 的 `permissions`）时才必须发新版扩展，而且用户要重新同意，尽量少加。

**能力和协议版本**：扩展新增的方法写进 `background.js` 的 `CAPABILITIES`，在握手时告诉应用，应用用 `BrowserConnection.can('…')` 判断后再用，旧扩展照样能连。只有改了已有消息的含义、旧的一方会理解错时，才把 `background.js` 的 `BRIDGE` 和 `BrowserBridge.protocol` 一起加一。版本对不上的连接，应用不用它，并在 设置 → 浏览器 里提示用户更新扩展或更新 BaoCode。商店版扩展会自动更新，通常比应用新；所以改协议时尽量让应用同时兼容旧版，先发应用、再发扩展。

**应用这边的 host**：浏览器按 native messaging 启动应用自带的 host，host 再去连应用。macOS 是 `macos/BrowserBridge/host.c`，Xcode 编进 `Contents/MacOS`，应用每次启动把 manifest 写进各浏览器的 `NativeMessagingHosts` 目录，经 Unix socket 连接。Windows 是 `windows/BrowserBridge/host.cpp`，`flutter build windows` 时编成 `baocode-browser-host.exe`，和 manifest `dev.baocode.browser.json` 一起放在 `baocode.exe` 旁边；安装包在 Chrome、Edge、Chromium 的注册表键里指向这个 manifest，卸载时删掉（Brave、Vivaldi 等读 Chrome 的键）。Windows 上 Dart 没有 Unix socket，应用改为监听 127.0.0.1 的随机端口，端口和每次启动新生成的 token 写在临时目录的 `baocode-browser.port`，host 握手时必须带上 token，否则应用直接断开。没经过安装包的本地构建没有注册表键，要测就手动加一条：`reg add HKCU\Software\Google\Chrome\NativeMessagingHosts\dev.baocode.browser /ve /d <构建目录>\dev.baocode.browser.json /f`。改扩展 ID 时 Windows 的 manifest 要一起改，`test/browser/browser_bridge_test.dart` 会检查两边一致。Linux 用的也是 `host.c`：`linux/BrowserBridge/CMakeLists.txt` 在 `flutter build linux` 时把它编成 `baocode-browser-host`，放在 `baocode` 旁边（deb 里是 `/opt/baocode/`）；应用每次启动把 manifest 写进 `~/.config/<浏览器>/NativeMessagingHosts`（设了 `XDG_CONFIG_HOME` 就用它）。socket 放在 `$XDG_RUNTIME_DIR`（只有本用户能进），没有才退回 `$TMPDIR` 或 `/tmp`；`/tmp` 是所有用户共用的，所以 host 连上后会用 `SO_PEERCRED` 核对对方是不是同一个用户，不是就断开，免得别的用户抢先占住 socket、截走浏览器的消息。Snap 版 Chromium 和 Flatpak 装的浏览器有沙箱，启动不了沙箱外的 host，暂不支持，设置 → 浏览器 里会提示改用官方 deb/rpm 包。CI 的 Linux 任务装上 deb 启动后，会检查 manifest 写对了位置，并真的跑一遍 host 连上应用。
