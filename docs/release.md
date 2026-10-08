# 版本与发布

BaoCode 的版本号怎么定、一个版本怎么发出去、发到哪里、已安装的应用怎么拿到它，以及第一次发布前要准备什么。应用这一侧怎么检查、下载、校验、安装，见 [auto-update.md](auto-update.md)。

- 下载与更新：`https://dl.baocode.dev`（Cloudflare R2）
- 官网：`https://baocode.dev`（Cloudflare Pages，`site/`）
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

---

## 1. 全貌

```
 你的机器                     GitHub                                Cloudflare
 ─────────                    ──────                                ──────────
 tool/bump_version.dart
 改版本号、写更新日志
 git push / git push 标签 ──▶ Actions：release.yml
                               ├ check    版本号对不对，不比已发布的旧
                               ├ remote   远程服务端：在 Mac 上编译一次（Linux、macOS 各两种架构）
                               ├ remote-linux  Linux 版在 Docker 里跑一遍
                               ├ macos    构建、签名、公证（macOS 机器）
                               ├ windows  构建、打安装包（Windows 机器）
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

 git push main（site/ 有改动）──────────────────────────────────▶ Pages：baocode.dev
```

- **网站和安装包分开放**：网站在 Pages 上，推送 `main` 时自动发布；安装包在 R2 上，只有推送 `v*` 标签时才由 CI 发布。Pages 单个文件不能超过 25 MiB，dmg 放不下。
- **流量不收钱**：Pages 的流量不限；R2 的下载流量免费，存储每月 10 GB 以内免费。
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

**只想试一下构建**：Actions → Release → Run workflow。只构建、不发布，产物在这次运行的 Artifacts 里（macOS 包这时是 ad hoc 签名，只能在自己机器上打开）。

## 4. CI 做了什么

`.github/workflows/release.yml`，推送 `v*` 标签时运行：

| Job | 机器 | 做什么 |
| --- | --- | --- |
| `check` | Ubuntu | pubspec.yaml 和 `version.dart` 一致；版本是 `x.y.z+build`；标签是 `v<x.y.z>`；不比 `dl.baocode.dev` 上已发布的版本旧（一样就是重新发布，给个提示） |
| `remote` | macOS 15 | 下载和 Flutter 同版本的 x64 Dart SDK → 编译远程服务端（`--all`：Linux x64/arm64 交叉编译；macOS arm64 用本机的 dart，macOS x64 用 x64 的 dart 经 Rosetta，`dart compile exe` 只能在 Mac 上、按 dart 自己的架构编 macOS 版）→ `tool/test_remote_server_macos.sh`：在这台 Mac 上把两份 macOS 版各跑一遍 → 上传 `remote`（`VERSION`、`servers.json`、`.gz`）和 `remote-linux`（Linux 的两个二进制）两个产物 |
| `remote-linux` | Ubuntu | `tool/test_remote_server.sh`：在 Docker 里的 Ubuntu 20.04 / 24.04、Debian 12、Rocky Linux 8 上，两种架构各跑一遍（arm64 用 QEMU 模拟），要能启动、回答 `initialize`、列出目录 |
| `macos` | macOS 15 | 有证书就导入临时钥匙串 → `tool/build_macos.dart --remote-built`：构建 universal 的 .app，**检查是 universal**（每个可执行文件都有 arm64 和 x86_64）→ 放进 `remote` 任务的 `servers.json` → 用 `ditto --arch` 拆成 Apple silicon（arm64）和 Intel（x64）两个应用，各自检查只剩一种架构，下面每个各做一遍：→ 签名（有证书用 Developer ID，带 hardened runtime；没有就 ad hoc，**不带** hardened runtime，否则系统拒绝加载应用自己的框架、一启动就崩；总要重签，因为放进去的文件要包进签名）→ 做 dmg → 有证书时签 dmg、公证、钉票据 → 打更新用的 zip → **把两个 zip 解开各真正启动一次**（Intel 版经 Rosetta），15 秒内退出就不发 |
| `windows` | Windows | 装 Inno Setup → `tool/build_windows.dart --remote-built`：构建、放进 `servers.json`、打安装包 |
| `publish` | Ubuntu | 汇总产物 → 用更新私钥签 `latest.json`（`tool/release_manifest.dart`，带上 dmg 给网站用）→ 上传远程服务端 → 上传安装包 → 按清单里的链接确认 CDN 给出的文件大小对 → **最后**上传 `latest.json` → 建 GitHub Release（附两个 dmg 和 exe；重新发布时先删掉旧的） |

几个设计上的考虑：

- **`latest.json` 最后传**：应用一读到新清单就会去下载，安装包必须先就位。
- **远程服务端只编译一次**：`remote` 任务编译，macOS 和 Windows 两个应用带的是同一份 `servers.json`（四个平台都有），R2 上一个版本只有一个 `releases/remote/<版本>-<二进制哈希>/`。
- **下载链接带哈希**：`latest.json` 里每个链接末尾是 `?sha256=<文件哈希前 16 位>`。CDN 按完整地址缓存，文件换了地址就换了，不会给出旧文件；应用取文件名时只看路径。
- **`downloads`**：`latest.json` 里多了这一项，是给网站用的（两个 dmg 和 Windows 安装包的链接、大小，键是 `macos-arm64`、`macos-x64`、`windows`），应用不读它。
- **密钥只在 `release` 环境里**，只有 `v*` 标签能用（见 7.2）。PR 和手动运行拿不到。
- Flutter 版本固定在工作流的 `FLUTTER_VERSION`，升级 Flutter 时一起改。

## 5. dl.baocode.dev 上有什么

R2 存储桶，绑定自定义域名 `dl.baocode.dev`，前面是 Cloudflare 的 CDN。

```
releases/
  latest.json                            应用和下载页读的清单          max-age=300
  1.2.0/
    BaoCode-1.2.0-setup.exe              Windows：首次安装和自动更新   immutable，一年
    BaoCode-1.2.0-mac-arm64.zip          macOS Apple silicon：自动更新 immutable，一年
    BaoCode-1.2.0-mac-x64.zip            macOS Intel：自动更新         immutable，一年
    BaoCode-1.2.0-arm64.dmg              macOS Apple silicon：首次安装 immutable，一年
    BaoCode-1.2.0-x64.dmg                macOS Intel：首次安装         immutable，一年
  remote/
    <VERSION>/                           远程服务端，应用连远程主机时按需下载
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

**官网**（首页和 `baocode.dev/download`，`site/site.js`）：浏览器读同一份 `latest.json`，按其中的 `downloads` 换上版本号、两个 dmg 和 Windows 安装包的链接（带哈希）和大小。下载页的 macOS 卡片有 Apple silicon 和 Intel 两个按钮，默认突出 Apple silicon；Chromium 系浏览器能报出处理器架构，Intel Mac 上会改为突出 Intel（`site/download.js`）。需要 R2 的 CORS 允许 `https://baocode.dev`（见 7.1）。读不到时显示页面里写死的版本。

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
5. **Pages**（网站）：Workers & Pages → Create → Pages → 连接 GitHub 仓库；生产分支 `main`，构建命令留空，输出目录 `site`，Build watch paths 填 `site/*`；自定义域名 `baocode.dev`。

### 7.2 GitHub

1. **环境**：Settings → Environments → New environment，名字 `release`。
   - Deployment branches and tags → Selected branches and tags → 加一条 **Tag**，规则 `v*`。只有 `v*` 标签触发的运行能用这个环境里的密钥。
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
| `remote-linux` 失败：Docker 里跑不起来 | 日志里有每个系统、每种架构的结果和服务端的输出。在本机用 `dart run tool/build_remote_server.dart && tool/test_remote_server.sh` 复现（需要 Docker） |
| `remote` 失败：macOS 版没编出来或跑不起来 | 多半是下载 x64 Dart SDK 失败（Flutter 带的 Dart 版本在 dart-archive 上没有对应的包），或 Rosetta 没装上。在 Apple silicon 的 Mac 上用 `dart run tool/build_remote_server.dart --all --macos-x64-dart <x64 sdk>/bin/dart && tool/test_remote_server_macos.sh` 复现 |
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
