# CONTRIBUTING.md

## 開発環境の基本準備

1. Flutter / Dart SDK および依存関係が正しくセットアップされていることを確認します。
2. リポジトリをクローンした状態から作業を開始します。

## Issue 着手から PR 完了までの流れ

1. **仕様・Scope確認**: 担当する Issue の仕様、Scope、Dependencies、Hotspot（変更禁止ファイル）を確認します。
2. **専用 Worktree 作成**: エージェント自身で専用の Git worktree を作成して移動します。
3. **環境・ブランチ確認**: 現在地とブランチを確認します。
4. **Project Status 更新**: 対象 Project の Status を `In Progress` へ変更します。（失敗時は Issue へ記録）
5. **作業開始コメント**: 担当 Issue へ作業開始コメント（Agent名、Branch名、Worktreeパス等）を投稿します。
6. **実装・検証**: 指定のブランチ上で修正を行い、ローカル検証（フォーマッタ、静的解析、テスト）を実行します。
7. **コミット・push**: 変更内容をコミットし、専用ブランチへ push します。
8. **Draft PR 作成**: GitHub 上で Draft PR を作成し、関連する Issue（`Closes #<issue-number>`）をリンクします。
9. **Project Status 更新**: 対象 Project の Status を `In Review` へ変更します。
10. **レビューと修正**: レビューコメントに対応し、必要に応じて追加コミット・push を行います。
11. **Done 確認**: PR マージ後、Project Status が `Done` になっていることを確認します。（マージ後の `Done` 変更は Coordinator または自動化により確認されます）

## エージェント自身による Worktree 作成手順

```bash
# リモート情報の取得
git fetch origin

# 既存ブランチ・Worktreeの確認
git branch --list agent/<issue-number>-<task-name>
git worktree list

# Worktree の追加
# Linux/macOS:
git worktree add ../kokoitta-agent-<issue-number> \
  -b agent/<issue-number>-<task-name> \
  origin/main

# Windows (PowerShell) の例:
git worktree add ..\kokoitta-agent-<issue-number> -b agent/<issue-number>-<task-name> origin/main

# 作成した Worktree への移動
# Linux/macOS:
cd ../kokoitta-agent-<issue-number>
# Windows (PowerShell):
Set-Location ..\kokoitta-agent-<issue-number>
```

### Branch / Worktree 命名規則
- **Branch 名**: `agent/<issue-number>-<task-name>` (例: `agent/11-multi-agent-process`)
- **Worktree ディレクトリ名**: `kokoitta-agent-<issue-number>` (例: `kokoitta-agent-11`)

## ホットスポットの排他ルール

以下のファイル・ディレクトリは競合が発生しやすいため、事前合意なしでの同時編集を禁止します。
- `android/**`
- `.github/workflows/**`
- `lib/backup_*.dart`
- `lib/trip_store.dart`
- `lib/models.dart`
- `lib/home_data.dart`
- `lib/home_backup.dart`
- `pubspec.yaml`, `pubspec.lock`

## 検証コマンド

変更作業後、必ず以下の確認・検証を実行してください。

```bash
# git diff のチェック
git diff --check

# 静的解析・テストの実行
flutter analyze
flutter test
```

## レビュー・マージ方針

- `main` ブランチへの直接 commit / push は禁止です。
- ChatGPT Coordinator の指示がない限り、手動での `merge` や `rebase` は行わないでください。
- 作業完了後も、Coordinator の指示なく Worktree を削除しないでください（`git worktree remove` や `git branch -D` の独断実行禁止）。

## Coordinator Issue #12 への報告・反映ルール

- 各エージェントは自分自身の担当 Issue および PR へ進捗や作業完了を報告します。
- 補足や他エージェントへの共有が必要な場合は、Coordinator Issue #12 へ**コメント**を投稿してください。
- **注意**: Issue #12 本文のチェックリスト、依存関係、進捗管理表の更新は ChatGPT Coordinator のみが担当します。エージェントが Issue #12 の本文を直接編集してはなりません。
