# AGENTS.md

## 基本ルール

- **1 Issue = 1 Agent = 1 Branch = 1 Worktree**
- エージェント自身が専用の Git worktree を作成して作業を行うこと。
- 元リポジトリの作業ディレクトリ（`intelligent-bardeen` や `main` のチェックアウト先）を直接編集しないこと。
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
git branch --list <branch>
git worktree list

# 3. 専用 Worktree の作成（例: agent/11-multi-agent-process の場合）
# Linux/macOS:
# git worktree add ../kokoitta-agent-11 -b agent/11-multi-agent-process origin/main
# Windows PowerShell:
git worktree add ..\kokoitta-agent-11 -b agent/11-multi-agent-process origin/main

# 4. 作成した Worktree へ移動
cd ../kokoitta-agent-11  # または Set-Location ..\kokoitta-agent-11

# 5. 移動後の確認
git branch --show-current
git status --short
```

> **注意・禁止事項:**
> 既存の worktree やブランチが既に存在する場合、独断で削除・再作成・`git worktree remove`・`git branch -D` を行わないでください。不整合がある場合はファイルを変更せず、Coordinator または該当 Issue へ状況をコメントしてください。

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
