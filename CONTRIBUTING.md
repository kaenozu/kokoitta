# CONTRIBUTING.md

## 開発環境の基本準備

1. Flutter / Dart SDK および依存関係が正しくセットアップされていることを確認します。
2. リポジトリをクローンした状態から作業を開始します。

## Issue 着手から Draft PR までの流れ

1. 担当する Issue の仕様、Scope、Hotspot（変更禁止ファイル）を確認します。
2. エージェント自身で専用の Git worktree を作成して移動します。
3. 指定のブランチ上で開発および修正を行います。
4. ローカルでの検証（フォーマッタ、静的解析、テスト）を実行します。
5. 変更内容をコミットし、専用ブランチへ push します。
6. GitHub 上で Draft PR を作成し、関連する Issue（例: `Closes #11`）をリンクします。

## エージェント自身による Worktree 作成手順

```bash
# リモート情報の取得
git fetch origin

# 既存ブランチ・Worktreeの確認
git branch --list <branch>
git worktree list

# Worktree の追加
# Windows (PowerShell) の例:
git worktree add ..\kokoitta-agent-<issue_number> -b agent/<issue_number>-<feature-name> origin/main

# 作成した Worktree への移動
Set-Location ..\kokoitta-agent-<issue_number>
```

### Branch / Worktree 命名規則
- **Branch 名**: `agent/<issue_number>-<feature-name>` (例: `agent/11-multi-agent-process`)
- **Worktree ディレクトリ名**: `kokoitta-agent-<issue_number>` (例: `kokoitta-agent-11`)

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

## Coordinator Issue #12 への進捗反映方法

各エージェントは進捗や作業完了のステータスを、全体の統括 Issue である Coordinator Issue #12 へ報告・反映します。
