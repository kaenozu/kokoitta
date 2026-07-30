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

- `ANDROID_KEYSTORE_BASE64` (keystore を Base64 エンコードした値)
- `ANDROID_STORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

Secrets が不足している場合、ワークフローはビルド前に失敗します。

これらの Secrets は **repository secrets ではなく、`android-release` Environment の Environment secrets として登録してください**。詳細は「セキュリティ」セクションを参照してください。

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

#### 信頼境界（コードで保証）

- 手動リリース（`workflow_dispatch`）は常に `main` ブランチの先端をビルド対象とします。任意の ref を指定することはできません
- `release` ジョブは `if:` 条件により、`workflow_dispatch` では `refs/heads/main`、`push`（タグ）では `refs/tags/v*` の場合のみ実行されます
- 署名 Secrets は `validate` ジョブには渡されません。`release` ジョブでのみ使用され、第三者Action実行前に削除されます
- `validate` ジョブは `contents: read` 権限のみで実行され、Release 作成は `release` ジョブ（`contents: write`）に分離されています
- ビルドと署名の後、第三者Action（`softprops/action-gh-release`）の実行**前**に署名ファイル（keystore, key.properties）を削除します。`if: always()` により失敗経路でも削除が実行され、`continue-on-error: true` により cleanup の失敗が公開を妨げません
- `softprops/action-gh-release` は可変タグ `@v2` ではなく、完全 commit SHA に固定しています（現在のバージョン: v2.6.2）
- 同一バージョンの重複リリースを防ぐため、`concurrency` により直列化されます
- イベント入力（version, tag名）は `env:` 経由で受け渡し、shell 内で直接展開しません。`scripts/validate-release.sh` の semver 検証により shell injection を防止します

#### GitHub 設定（手動設定が必要）

以下の設定は GitHub リポジトリ設定画面で手動で行う必要があります。未設定の場合、**コード上の保護のみでは不十分**であり、特にタグ push 経路では未信頼 workflow 定義による攻撃を完全には防げません。

##### Environment 設定

1. **Environment の作成**
   - リポジトリ → Settings → Environments → `android-release` を作成
2. **Environment secrets の登録**
   - 署名 Secrets（`ANDROID_KEYSTORE_BASE64`, `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`）を repository secrets ではなく、`android-release` Environment の Environment secrets として登録
   - これにより、`release` ジョブが `environment: android-release` を宣言した場合のみ Secrets が注入される
   - repository secrets に登録した場合、任意の workflow からアクセス可能になるため推奨しません
3. **Deployment branches and tags**
   - `Deployment branches` タブで `main` を追加（`Selected branches` モード）
   - `Deployment tags` タブで `v*.*.*` を追加（`Selected tags` モード）
   - これにより、未信頼ブランチや未信頼タグからの workflow 実行時に Environment secrets へのアクセスを遮断します
4. **Required reviewers**（GitHub Enterprise/Team プラン）
   - `Required reviewers` を 1 名以上追加
   - デプロイ承認プロセスが追加され、`release` ジョブは承認されるまで一時停止します
   - 利用可能なプランでない場合、この設定はスキップされます。その場合、タグ push 経路の保護は環境変数と tag ruleset に依存します

##### Ruleset 設定（タグ保護）

タグ push 経路では、workflow 定義ファイル自体がタグが指す commit から実行されるため、コード上で完全に保護することはできません。以下の GitHub Ruleset 設定を推奨します。

1. **Tag ruleset の作成**
   - リポジトリ → Settings → Rules → Rulesets → `New ruleset` → `Tag`
   - 対象タグパターン: `v*.*.*`
   - `Restrict creations` を有効化
   - 許可するユーザー/チームを限定
   - 少なくとも管理者のみがリリースタグを作成できるようにする
2. **Branch ruleset の作成（推奨）**
   - `main` ブランチに対する `Require a pull request before merging` の有効化
   - `Require approvals` の設定

##### Repository secrets の注意

現状の workflow は `release` ジョブが `environment: android-release` を宣言しているため、Environment secrets から Secret を解決します。しかし、**repository secrets にも同じ Secret が存在する場合**、任意の workflow からアクセス可能です。必ず repository secrets からは削除し、Environment secrets のみに設定してください。

#### タグ push のリスクモデル

GitHub Actions の仕様上、タグ push で起動した workflow は、そのタグが指す commit 上の workflow 定義を実行します。つまり、攻撃者が任意の workflow 定義を含むタグを作成できる場合：

1. 悪意のある workflow が `on: push: tags: ['v*.*.*']` を宣言して起動する
2. その workflow が `release` ジョブを宣言し、`environment: android-release` なしで直接 Secrets を参照しようとしても、Environment の branch/tag rules によりアクセスは拒否される
3. ただし、悪意のある workflow が `GITHUB_TOKEN` の `contents: write` 権限を利用して不正な Release を作成する可能性は残る

このリスクを軽減するには、前述の Ruleset 設定でタグ作成を制限する必要があります。

### 注意事項

- 同一バージョンの Release が既に存在する場合、ワークフローは早期に失敗します
- 同名の Git タグが既に存在し、異なる commit を指している場合も失敗します
- 再実行（Re-run）は同じ versionCode を生成するため、既存の Release を上書きしません
- 手動リリースでは `main` の先端がビルド対象となり、ログと成果物ファイル名に commit SHA が含まれます
- 署名キーストアと key.properties は第三者Action（Release公開）の**前に自動削除**されます
- cleanup は失敗経路でも実行されます（`if: always()`）
- エラー時は validate ジョブのログを確認してください。署名シークレット関連のエラーは fail-fast で停止します
- Environment 設定が未完了の場合、タグ push 経路での署名 Secrets 保護は不完全です。リリース前に「セキュリティ」セクションの手動設定を完了してください

### 同一バージョンの競合防止

- **Concurrency**: 同一バージョンのワークフローが同時に実行されるのを防止します。`push tag` と `workflow_dispatch` の両方を同じ concurrency group で直列化します
- 先に実行中のリリースがある場合、後続の実行はキューイングされ、完了後に開始されます
- `cancel-in-progress: false` のため、進行中のリリースが中断されることはありません
