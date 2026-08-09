# ここいった

写真から旅行の記録と都道府県の訪問状態を管理する Flutter Android アプリです。

## 開発・貢献ガイドライン (マルチエージェントプロセス)

本プロジェクトでは複数エージェントおよび開発者が安全に並列作業を行うためのガイドラインを定めています。

- **エージェント向け運用ルール**: [AGENTS.md](AGENTS.md)
- **コントリビューションガイド**: [CONTRIBUTING.md](CONTRIBUTING.md)
- **Issue #90 human acceptance checklist**: [docs/issue-90-human-acceptance.md](docs/issue-90-human-acceptance.md)
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

### バージョニングと対象commit

- **versionName**: タグ `vX.Y.Z` から `X.Y.Z` を抽出して使用。手動実行の場合は入力 `version` をそのまま使用
- **versionCode**: `github.run_number` を使用。再実行時に同じ versionCode になる（上書き防止）
- **Commit SHA**: タグ push ではタグが指すcommit、手動実行ではRun workflowを開始したイベント時点の`${{ github.sha }}`を固定して使用する
- 手動実行後に`main`が進んでも、validate・build・GitHub Releaseは同じ固定commitを参照する
- **タグ commit の検証**: タグ pushでは、タグが指すcommitが`main`の履歴に含まれる場合だけ続行する
- **タグと commit の一致**: 同名のGitタグが既に存在し、異なるcommitを指している場合は失敗する。同名Releaseが既に存在する場合も失敗する
- **出力**: APKとAABの両方を生成し、GitHub Releaseに添付する
- 不正なタグ形式（`v1.2`、`1.2.3`、`v1.2.3-beta`など）はビルド前に失敗する

### 成果物メタデータ検査

GitHub Releaseを作成する前に、生成したAPKとAABの実体を検査します。

- APKはAndroid SDKの`apkanalyzer`で`applicationId`、`versionName`、`versionCode`を取得
- AABは固定した`bundletool 1.18.3`で同じ3項目を取得
- 期待するpackageは`com.kaenozu.kokoitta_app`
- 期待するversionName/versionCodeはvalidate jobが解決した値
- APKとAABのどちらか一方でも不一致なら、署名ファイルをcleanupして公開前に失敗する
- 検証後にAPK/AABのSHA-256を記録する。署名秘密値は出力しない

### リリース手順（タグ push）

```bash
# 1. main にリリース対象 commit が含まれることを確認
# 2. pubspec.yaml の version を更新（必要に応じて）
# 3. リリース対象 commit にタグを作成して push
git tag v1.2.0
git push origin v1.2.0
# 4. GitHub Actions がタグの commit をビルドし、APK + AAB を GitHub Release へ添付
```

### リリース手順（手動実行）

1. GitHubリポジトリ → Actions → Android Release → Run workflow
2. Branchは`main`を選択
3. `version`へ`1.2.0`のような`v`なしsemverを入力
4. 実行イベント時点のcommit SHAが対象として固定される
5. validate jobがそのcommitの`main`包含、version、tag/Release競合を検証する
6. release jobは同じcommitから署名済みAPK/AABを生成する
7. 成果物メタデータが期待値と一致した場合だけReleaseタグと成果物を公開する

### セキュリティ

#### 信頼境界（コードで保証）

- 手動リリースは`main`からのみ開始でき、任意ref入力は持たない
- validate jobは実行イベント時のcommitをcheckoutし、そのSHAをrelease jobへ渡す
- タグpushはタグcommitが`main`履歴に含まれることをSecretsなしのvalidate jobで確認する
- release jobは手動実行の`refs/heads/main`または`v*`タグpushの場合だけ実行する
- 署名Secretsはvalidate jobへ渡さず、`android-release` Environmentを使用するrelease jobだけで参照する
- validate jobは`contents: read`、Release作成はrelease jobの`contents: write`へ分離する
- 成果物を検査した後、第三者Actionの前にkeystoreとkey.propertiesを削除する
- cleanupは`if: always()`で失敗経路でも実行し、cleanup失敗時はPublishを中止する
- workflow内Actionは完全commit SHAへ固定する
- 同一バージョンは`concurrency`で直列化する
- version/tag入力は`env:`経由で渡し、`scripts/validate-release.sh`で検証する

#### GitHub設定（人間による設定が必要）

コード外では、次を設定してください。

1. `android-release` Environmentを作成
2. 署名4 SecretsをEnvironment secretsへ登録し、repository secretsには残さない
3. Deployment branchesへ`main`、Deployment tagsへ`v*.*.*`を設定
4. 利用可能なプランではRequired reviewersを設定
5. `v*.*.*`のTag rulesetでタグ作成者を制限
6. `main`のBranch rulesetでPull Requestと必要なstatus checkを必須化

### 注意事項

- 同一バージョンのReleaseが既に存在する場合は早期失敗する
- 同名Gitタグが異なるcommitを指す場合も失敗する
- 再実行は同じversionCodeを使用し、既存Releaseを上書きしない
- 成果物名とログには固定したcommitのshort SHAを含める
- Environment設定、Secrets登録、実署名Releaseは所有者による明示的な運用受入が必要

### 同一バージョンの競合防止

- `push tag`と`workflow_dispatch`を同一versionのconcurrency groupで直列化します
- `cancel-in-progress: false`のため、進行中のReleaseを後続実行が中断しません
