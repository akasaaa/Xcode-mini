# XcodeMini

Xcode を ScriptingBridge 経由で操作する、メニューバー常駐の軽量コントローラ（macOS）。

## 機能

- **workspace 一覧・選択** … Xcode で開いている workspace を切り替え（既定は現在アクティブな workspace）
- **scheme 一覧・選択** … `active scheme` を切り替え（ツールバー非表示の scheme は除外）
- **実行先(run destination)一覧・選択** … `active run destination` を切り替え（シミュレータ・実機・My Mac を含む。scheme 依存）。直近の選択を (workspace, scheme) ごとに記憶
- **実行** … 選択中の scheme / 実行先で `run`（⌘R 相当：ビルド+起動）
- **停止** … 実行中のアクションを `stop`（実行中のときだけ活性化）
- **ステータス表示** … 直近のアクション結果（実行中 / 成功 / 失敗 など）を表示。メニューを開いている間は 0.5 秒間隔で更新

既定では Xcode で現在アクティブな workspace（`active workspace document`）を対象とし、ピッカーで他の開いている workspace に切り替えられます。

## 設計メモ

- **形態**: SwiftUI `MenuBarExtra`（`.window` スタイル）のメニューバー常駐アプリ。
- **方針**: コマンドはファイア&フォーゲットで送る。状態フィードバックは、メニューを開いている間だけ `last scheme action result` を 0.5 秒間隔でポーリングして表示する（閉じると停止）。
- **事前チェック**: 自動化(TCC)許可・Xcode 未起動・workspace 未オープンは事前チェックして案内する。
- **ScriptingBridge**: 必要な範囲だけ手書きの `@objc protocol`（`Sources/XcodeMini/XcodeBridge.swift`）。
  参照用の完全なヘッダは次で再生成できる:
  ```sh
  sdef /Applications/Xcode.app | sdp -fh --basename Xcode
  ```

## ビルド

SwiftPM の素のバイナリは `.app` バンドルではなく Info.plist を持たないため、TCC 自動化許可が取れない。
`build-app.sh` が `swift build` の成果物を `.app` に組み立て、Info.plist
（`LSUIElement` / `NSAppleEventsUsageDescription`）を埋め、ad-hoc 署名する。

```sh
./build-app.sh           # ./dist/XcodeMini.app を生成
./build-app.sh install   # /Applications にもコピー
```

開発中のコンパイル確認だけなら `swift build` でよい（ただし起動・許可取得には `.app` が必要）。

## 使い方

1. `./build-app.sh` でビルドし、`open dist/XcodeMini.app`（または `/Applications` から起動）。
2. メニューバーのハンマーアイコンをクリック。
3. 初回は「アクセスを許可」から Xcode への自動化を許可（拒否済みなら「システム設定を開く」から
   *プライバシーとセキュリティ → オートメーション* で許可）。
4. Xcode で workspace を開いた状態で、scheme / 実行先を選び、実行 / 停止。

> ad-hoc 署名のため、リビルドで自動化許可が再要求されることがある。

## 要件

- macOS 26 以降
- Xcode 26 以降（操作対象）
