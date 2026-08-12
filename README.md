# ここいった

写真から旅行の記録と都道府県の訪問状態を管理する Flutter Android アプリです。

## できること

- 写真から旅行を作成し、旅行一覧・詳細・写真ビューアで振り返る
- 日本地図で都道府県の訪問状態を管理する
- Android共有から写真を取り込む
- バックアップ / 復元でアプリデータを移行する
- ローカル中心で旅行・写真データを管理する

## データ保護の前提

このアプリでは写真と保存データの整合性を重要な不変条件として扱います。

- アプリ状態はバージョン付き JSON で保存します。
- 写真は1つの旅行、または「旅行未設定」のどちらか一方に所属します。
- 完全復元では ZIP の形式・件数・容量・SHA-256 を検証してから一時領域へ展開します。
- 復元確定前に現在データの安全バックアップを作成し、切替失敗時は新しい写真セットをロールバックします。
- private 写真、端末内 path、位置情報、署名秘密値を Issue / PR / ログへ記録しません。

保存形式や復元・削除の安全性を変更する場合は、後方互換性、rollback、回帰テストを先に確認してください。

## 開発

### 必要環境

Flutter / Dart / Android SDK / Java 17 を使用します。実際の固定バージョンはリポジトリ内の設定と CI を正としてください。

### 基本コマンド

```bash
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
cd android && ./gradlew :app:testDebugUnitTest
cd ..
flutter build apk --debug
git diff --check
```

変更範囲に応じて、Widget / golden / Android unit / release workflow の追加検証も実行します。

## 開発・レビュー運用

- エージェント運用: [AGENTS.md](AGENTS.md)
- コントリビューション: [CONTRIBUTING.md](CONTRIBUTING.md)
- Issue テンプレート: [.github/ISSUE_TEMPLATE/task_template.md](.github/ISSUE_TEMPLATE/task_template.md)
- PR テンプレート: [.github/pull_request_template.md](.github/pull_request_template.md)
- UI 最終受入資料: [docs/issue-90-human-acceptance.md](docs/issue-90-human-acceptance.md)

1 Issue = 1 branch / worktree を基本とし、保存・写真・削除・共有・release の hotspot は並行作業時の競合を確認してから変更します。

## Android リリース

Android Release workflow は、検証済みの commit から署名済み APK / AAB を生成し、成果物の applicationId・versionName・versionCode・署名・SHA-256 を確認する設計です。

### トリガー

- `vX.Y.Z` 形式のタグ push
- `main` からの `workflow_dispatch`

### 署名 Secrets

署名情報は `android-release` Environment に保持します。

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_STORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

Secrets を repository、Issue、PR、ログへ記録しないでください。

### リリース安全境界

- タグが指す commit が `main` に含まれることを検証します。
- 同一 version / tag / GitHub Release の衝突は fail-closed で拒否します。
- APK / AAB のメタデータ不一致時は公開しません。
- keystore と一時署名ファイルは失敗経路を含め cleanup します。
- Production 配布、Play Console 操作、Secrets 登録、署名鍵の作成・再発行は別の明示承認が必要です。

## 現在の作業管理

README には変動しやすい個別 Issue / PR の状態を固定しません。最新の実装・受入・release blocker は GitHub Issues / Pull Requests を確認してください。

特に、写真データの欠損・削除回復・実 ContentProvider・UI 最終 QA・正式署名 / Play 内部テストは、コード側の自動テストと実環境受入を分けて管理します。
