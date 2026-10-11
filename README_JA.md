# BaoCode

[English](README.md) · [简体中文](README_CN.md) · **日本語** · [Français](README_FR.md) · [Español](README_ES.md)

[Claude Code](https://github.com/anthropics/claude-code) のための、使いやすいデスクトップ UI。ミリ秒単位で応答する高速な IDE を内蔵しています。

[公式サイト](https://baocode.dev) · [ダウンロード](https://baocode.dev/download) · [変更履歴](https://baocode.dev/changelog)

![BaoCode のメイン画面：プロジェクト別のエージェント、並列表示された二つの会話、モデル選択](site/shots/main.png)

> 英語 README の日本語版です。内容に相違がある場合は [English](README.md) を参照してください。リンク先のサイトや文書が日本語に対応しているとは限りません。

## 開発の理由

私たちは毎日 Claude Code を使っています。ターミナルは実行には適していますが、内容を読むには不便です。長い diff は画面外へ流れ、以前の手順を探し直すのは難しく、変更の確認にはアプリの切り替えが必要になります。BaoCode は、私たちが欲しかったそのためのウィンドウです。

BaoCode は意図的に独自のエージェントを持ちません。エージェントは Claude Code です。そのツール、スキル、プラグイン、MCP サーバー、サブエージェント、hooks を活かしながら、BaoCode は読みやすい UI とすぐに使える周辺機能を提供します。すでにインストールされた Claude Code を、既存の設定と `CLAUDE.md` のまま実行します。

## 機能

- **読みやすさを重視した UI。** ファイルの読み込み、検索、コマンドを一行に折りたためます。Claude の変更をファイルごとに保持または取り消せます。チェックポイントは BaoCode のデータフォルダーに保存され、リポジトリの `.git` には入りません。
- **目標。** `/goal` と実現したい内容を入力すると、Claude が目標達成まで作業を続けます。目標と進捗は入力欄の上に表示されます。
- **リッチテキスト入力。** エディターからコピーしたコードはファイルと行への参照として挿入されます。画像の貼り付けやファイルのドロップも、文中の指定位置に配置できます。
- **高速 IDE。** エディター、ターミナル、コミットグラフ付きソース管理を内蔵しています。Claude Code によるコミットメッセージの作成、キーマップ、言語サーバーに対応しています。
- **統一されたテーマ。** エディター、会話、サイドバーに同じテーマを適用できます。
- **スキル、MCP サーバーなど。** プラグイン、MCP サーバー、スキル、サブエージェント、ルール、コマンド、hooks を一か所で管理し、個人用またはプロジェクト単位で設定できます。
- **複数のモデル。** Anthropic API、OpenAI Chat Completions、OpenAI Responses に対応するプロバイダーを追加できます。ローカルプロキシが Claude Code とのプロトコル変換を行い、キーはシステムのキーチェーンに保存されます。
- **SSH 経由のリモートプロジェクト。** UI は手元のマシンに残り、ファイル、Git、検索、ターミナル、言語サーバー、Claude Code はリモートホスト上で動作します（Linux、x64 または arm64）。
- **通知。** エージェントが操作を求めたときや作業を終えたときに、システム通知、音、バッジで知らせます。ウィンドウを閉じてもメニューバーやトレイで作業を続けられます。
- **更新。** バックグラウンドでの自動更新、手動更新、更新の無効化を選べます。

## 速度

BaoCode は GPU に直接 UI を描画するネイティブアプリです。以下は英語 README に記載された数値であり、この翻訳で再測定したものではありません。実際の結果はハードウェア、バージョン、使用状況によって異なります。

| 指標 | BaoCode |
| --- | --- |
| 起動時間 | 約 0.18 秒 |
| 一つのウィンドウのアイドル時メモリ | 約 120 MB |
| 一つのウィンドウのプロセス数 | 2 |
| Windows のダウンロードサイズ | 約 16 MB |

## 必要環境

- macOS 12 以降（Apple silicon と Intel 向けにそれぞれ配布）、または Windows 10 以降（x64）。
- [Claude Code](https://github.com/anthropics/claude-code) がインストールされていること。

## ソースからのビルド

BaoCode は Flutter アプリです。Dart SDK の要件は `^3.13.4` です。

```sh
flutter pub get
flutter run -d macos        # Windows: flutter run -d windows
```

リリース用の成果物を `build/installers/` に作成するには：

```sh
dart run tool/build_macos.dart            # BaoCode-<version>-{arm64,x64}.dmg と BaoCode-<version>-mac-{arm64,x64}.zip
dart run tool/build_windows.dart          # BaoCode-<version>-setup.exe（Inno Setup が必要）
dart run tool/build_remote_server.dart    # Linux x64 / arm64 用の SSH リモートサーバー
```

テスト全体の実行には時間がかかるため、変更に関連するテストだけを実行してください。例：`flutter test test/update`。

`v*` タグを push すると CI がリリースをビルドして公開します。バージョン、署名、公開先については [docs/release.md](docs/release.md) を参照してください。[docs/](docs) には[自動更新](docs/auto-update.md)、[SSH リモート](docs/ssh-remote.md)、[Windows](docs/windows.md) の文書もあります。一部は中国語です。

## リポジトリ構成

| パス | 内容 |
| --- | --- |
| [lib/](lib) | アプリケーション |
| [packages/bao_editor](packages/bao_editor) | エディター、シンタックスハイライト、テーマ、キーバインド |
| [packages/bao_xterm](packages/bao_xterm) | xterm.js の Dart 移植 |
| [packages/bao_pty](packages/bao_pty) | Dart 用疑似端末：macOS / Linux は forkpty、Windows は ConPTY |
| [packages/bao_remote](packages/bao_remote) | SSH 経由でサービスを提供するリモート側 |
| [macos/](macos)、[windows/](windows) | ネイティブランナー |
| [tool/](tool) | ビルド、パッケージング、リリースのスクリプト |
| [site/](site) | [baocode.dev](https://baocode.dev) のソース |
| [docs/](docs) | 設計資料 |

## フィードバック

Issue を歓迎します。上流プロジェクトは Pull Request を受け付けていません。

## ライセンス

BaoCode は [GNU General Public License v3.0](LICENSE)（GPL-3.0-only）で公開されています。[packages/](packages) 内のエディターおよび端末パッケージ（bao_editor、bao_xterm、bao_pty）は MIT ライセンスです。第三者のコンポーネントにはそれぞれのライセンスが適用され、ファイルは対応するソースの隣にあります。

BaoCode は独立したプロジェクトであり、Anthropic との提携や同社による推奨を意味しません。
