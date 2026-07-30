# ここいった

写真から旅行の記録と都道府県の訪問状態を管理する Flutter Android アプリです。

## 開発・貢献ガイドライン (マルチエージェントプロセス)

本プロジェクトでは複数エージェントおよび開発者が安全に並列作業を行うためのガイドラインを定めています。

- **エージェント向け運用ルール**: [AGENTS.md](AGENTS.md)
- **コントリビューションガイド**: [CONTRIBUTING.md](CONTRIBUTING.md)
- **Issue 作成**: [Issue テンプレート](.github/ISSUE_TEMPLATE/task_template.md)
- **PR 作成**: [PR テンプレート](.github/pull_request_template.md)

## 開発コマンド

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

## データ保護

- アプリ状態はバージョン付き JSON で保存します。
- 写真は1つの旅行、または「旅行未設定」のどちらか一方に所属します。
- 完全復元は ZIP の形式・件数・容量・SHA-256を検証して一時領域へ展開します。
- 復元確定前に現在データの安全バックアップを作成し、保存状態の切替に失敗した場合は新しい写真セットをロールバックします。

## Androidリリース

### トリガー

| 方法 | 条件 | バージョン指定 |
|---|---|---|
| タグ push | `vX.Y.Z` 形式のタグ（例: `v1.2.0`） | タグ名から自動抽出 |
| 手動 (workflow_dispatch) | GitHub Actions の Release 画面から実行 | `version` を必須入力 |

### 必要 Secrets

署名済み APK/AAB のビルドには以下の Secrets が必要です。

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_STORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

Secrets が不足している場合、ワークフローはビルド前に失敗します。

### バージョニング

- **versionName**: タグ `vX.Y.Z` から `X.Y.Z` を抽出して使用。手動実行の場合は入力 `version` をそのまま使用
- **versionCode**: `github.run_number` を使用。再実行時に同じ versionCode になる（上書き防止）
- **Commit SHA**: 手動実行では常に `main` の先端をビルド対象とし、Release タグはその commit SHA に作成される
- **タグと commit の一致**: 同名の Git タグが既に存在し、異なる commit を指している場合は失敗する。同名 Release が既に存在する場合も失敗する
- **出力**: APK と AAB の両方を生成し、GitHub Release に添付する
- 不正なタグ形式（`v1.2`、`1.2.3`、`v1.2.3-beta` など）は検証ステップでビルド前に失敗します

### リリース手順（タグ push）

```bash
# 1. pubspec.yaml の version を更新（必要に応じて）
# 2. タグを作成して push
git tag v1.2.0
git push origin v1.2.0
# 3. GitHub Actions が自動起動し、APK + AAB を GitHub Release へ添付
```

### リリース手順（手動実行）

1. GitHub リポジトリ → Actions → Android Release → Run workflow
2. 入力:
    - **version**: `1.2.0`（`v` なしの semver）
3. ワークフローは `main` の先端をチェックアウトし、ビルド・署名・Release 作成を実行する
4. Release タグ `v1.2.0` は `main` の先端 commit SHA に作成される
5. 同名タグが別の SHA を指している場合、または同名 Release が既に存在する場合は失敗する

### セキュリティ

- 手動リリース（`workflow_dispatch`）は常に `main` ブランチの先端をビルド対象とします。任意の ref を指定することはできません
- 署名 Secrets は `validate` ジョブには渡されません。 `release` ジョブでのみ使用され、ビルド後に削除されます
- `validate` ジョブは `contents: read` 権限のみで実行され、Release 作成は `release` ジョブ（`contents: write`）に分離されています
- 同一バージョンの重複リリースを防ぐため、`concurrency` により直列化されます

### 注意事項

- 同一バージョンの Release が既に存在する場合、ワークフローは早期に失敗します
- 同名の Git タグが既に存在し、異なる commit を指している場合も失敗します
- 再実行（Re-run）は同じ versionCode を生成するため、既存の Release を上書きしません
- 手動リリースでは `main` の先端がビルド対象となり、ログと成果物ファイル名に commit SHA が含まれます
- 署名キーストアと key.properties はビルド後に自動削除されます
- エラー時は validate ジョブのログを確認してください。署名シークレット関連のエラーは fail-fast で停止します

### 同一バージョンの競合防止

- **Concurrency**: 同一バージョンのワークフローが同時に実行されるのを防止します。`push tag` と `workflow_dispatch` の両方を同じ concurrency group で直列化します
- 先に実行中のリリースがある場合、後続の実行はキューイングされ、完了後に開始されます
- `cancel-in-progress: false` のため、進行中のリリースが中断されることはありません
