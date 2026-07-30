# AGENTS.md

## 基本ルール

- **1 Issue = 1 Agent = 1 Branch = 1 Worktree**
- エージェント自身が専用の Git worktree を作成して作業を行うこと。
- 元リポジトリの作業ディレクトリ（`main` チェックアウト先など）を直接編集しないこと。
- 他のエージェントの worktree またはブランチを編集・変更しないこと。
- Issue の Scope（作業範囲）および変更禁止範囲（ホットスポットなど）を厳格に遵守すること。
- 無関係なリファクタリング、コード整頓、パッケージ依存関係の更新を行わないこと。

## 作業開始前手順

1. `README.md`、`AGENTS.md`、`CONTRIBUTING.md`、および担当する Issue の本文を必ず確認する。
2. 作業ディレクトリの状態を確認する：
   ```bash
   git status --short
   ```
3. 現在のブランチと worktree 一覧を確認する：
   ```bash
   git branch --show-current
   git worktree list
   ```
4. 既存の実装、テスト、CI設定を確認する。
5. 未関連の変更（未コミットの変更等）を勝手に消去・退避・巻き戻し（`reset`, `stash drop` 等）しないこと。

## Worktree 作成フロー

各エージェントは作業開始時、必ず以下の標準フローで専用 worktree を作成して移動してください。

```bash
# 1. リモート情報を更新
git fetch origin

# 2. ブランチおよび Worktree の重複がないか確認
git branch --list agent/<issue-number>-<task-name>
git worktree list

# 3. 専用 Worktree の作成
# Linux/macOS:
git worktree add ../kokoitta-agent-<issue-number> \
  -b agent/<issue-number>-<task-name> \
  origin/main

# Windows PowerShell:
git worktree add ..\kokoitta-agent-<issue-number> -b agent/<issue-number>-<task-name> origin/main

# 4. 作成した Worktree へ移動
# Linux/macOS:
cd ../kokoitta-agent-<issue-number>
# Windows PowerShell:
Set-Location ..\kokoitta-agent-<issue-number>

# 5. 移動後の確認
git branch --show-current
git status --short
```

> **注意・禁止事項:**
> 既存の worktree やブランチが既に存在する場合、独断で削除・再作成・`git worktree remove`・`git branch -D` を行わないでください。不整合がある場合はファイルを変更せず、Coordinator または該当 Issue へ状況をコメントしてください。

## GitHub Projects の Status 更新ルール

各エージェントは、担当 Issue の GitHub Projects における Status を以下の遷移に従って更新してください。

### ステータス遷移ルール
1. **Todo → In Progress**:
   - 専用 worktree の作成およびブランチ確認が完了し、ファイル編集を開始する直前に `In Progress` へ変更する。
   - worktree 作成とブランチ確認が完了する前に `In Progress` に変更しないこと。
2. **In Progress → In Review**:
   - 実装・検証・コミット・push が完了し、Draft PR を作成した直後に `In Review` へ変更する。
3. **In Review → Done**:
   - PR がマージされ Issue が完了した段階で `Done` となっていることを確認する。（マージ後の `Done` への変更は Coordinator または GitHub Projects の自動化で実行・確認される場合を含む）

### Project 操作の安全ルール
- **プロジェクトの特定**:
  - Project 名や Project 番号を文書内に固定値として埋め込まないこと。
  - エージェントは以下の優先順位で対象 Project を特定する：
    1. Issue 本文で指定された Project
    2. Coordinator Issue #12 で指定された Project
    3. `gh project list --owner kaenozu` で一意に確認できた Project
  - 複数候補があり一意に判断できない場合は、推測で更新せず Coordinator へ報告すること。
- **Project Item ID / Field ID の取り扱い**:
  - Project Item ID、Status Field ID、Option ID などを固定値として文書へ記載しないこと。
- **エラー時の扱い**:
  - `gh` CLI 等で Projects を操作するには `project` スコープが必要となる。
  - 権限不足や API エラー等で Projects の更新に失敗した場合は、成功したと虚偽報告せず、実行コマンドとエラー内容を該当 Issue へ記録・報告すること。

## ホットスポット（同時編集の原則禁止）

以下のファイルおよびディレクトリは、複数エージェントによる同時編集を原則禁止します（競合防止のため）。

- `android/**`
- `.github/workflows/**`
- `lib/backup_*.dart`
- `lib/trip_store.dart`
- `lib/models.dart`
- `lib/home_data.dart`
- `lib/home_backup.dart`
- `pubspec.yaml`
- `pubspec.lock`

## 禁止 Git 操作

- `main` への直接 push
- `git reset --hard`
- `git clean -fd`
- Force push (`git push --force`, `git push -f`)
- ChatGPT Coordinator の指示がない `merge` または `rebase`
- 他エージェントのブランチの checkout
- 他エージェントの worktree の変更
- 未関連変更の削除

## 品質基準

- エラーや例外を握りつぶさないこと。
- テストを skip して成功扱いにしないこと。
- 型安全性を低下させないこと。
- データ損失、競合、セキュリティ、境界値（エッジケース）を確認すること。
- 機能追加・修正時には回帰テストを追加すること。
- コミット前に formatter、静的解析、関連テスト、全体テスト、必要な build を実行すること。
- 実行できなかった検証がある場合、それを「成功」扱いにせず明確に報告すること。

## 完了報告フォーマット

作業完了後、Issue および PR 本文へ以下の項目を報告してください。

1. 実施内容
2. 主な変更ファイル
3. 実行した検証と結果
4. 未確認事項または残存リスク
5. 依存 Issue への影響
6. PR URL
