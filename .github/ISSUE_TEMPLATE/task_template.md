---
name: Feature / Task Issue Template
about: エージェントおよび作業者用 Issue テンプレート
title: ''
labels: ''
assignees: ''
---

## Goal
<!-- この Issue で達成したい目的を簡潔に記述してください -->

## Background / Problem
<!-- 背景や解決すべき課題・背景情報を記述してください -->

## Scope
<!-- 作業範囲（対応すること）を明記してください -->

## 変更禁止
<!-- 編集してはならないファイルや機能（ホットスポット等）を明記してください -->

## Requirements
<!-- 満たすべき詳細要件を箇条書きで記述してください -->

## Acceptance Criteria
<!-- 完了条件・受け入れ基準を記述してください -->

## Dependencies
<!-- 依存する他の Issue や前提条件があれば記述してください -->

## Hotspots
<!-- 同時編集注意・原則禁止のファイルがあれば挙げてください -->

## Branch
<!-- 担当ブランチ名を指定してください (例: agent/<issue-number>-<task-name>) -->

## Worktree
<!-- 担当エージェント自身が作成する専用 Worktree 名を指定してください (例: kokoitta-agent-<issue-number>) -->
※ 担当エージェントは指定されたディレクトリ名で自ら Git worktree を作成して作業を行ってください。

## Project
- Project: <!-- 対象プロジェクト名または指定がない場合は特定手順に従う -->
- Initial Status: Todo
- Start Status: In Progress
- Review Status: In Review
- Completion Status: Done

## Validation
<!-- 実行すべき検証手順・テスト内容を記述してください -->

## Completion Report
<!-- 完了時に報告すべき項目（実施内容、確認結果、リスクなど）のチェックリスト -->
- [ ] 実施内容
- [ ] 主な変更ファイル
- [ ] 実行した検証と結果
- [ ] 未確認事項または残存リスク
- [ ] 依存Issueへの影響
- [ ] PR URL
- [ ] GitHub ProjectsのStatus更新結果（更新不可時はエラー報告）
