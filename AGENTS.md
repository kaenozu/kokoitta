# AGENTS.md

このリポジトリで作業するAIエージェントと自動化担当者は、変更前に本書を確認してください。

## 適用範囲

作業方法を次の2種類に分けます。

### 1. ローカル作業

ローカルcloneでファイル編集、format、test、build、commit、push等を行う作業です。

- **1 Issue = 1 Agent = 1 Branch = 1 Worktree**を原則とします。
- 専用branchと専用Git worktreeを作成し、元リポジトリの作業ディレクトリ（`main`のcheckout先等）を直接編集しません。
- 本書のworktree確認・作成・削除規則は、ローカル作業にだけ適用します。

### 2. Remote-only GitHub作業

GitHub API、GitHub Contents API、Pull Request API等だけを使い、ローカルclone、ローカルファイル、ローカルprocessを操作しない作業です。

- **worktreeの作成・存在確認は不要です。**
- Exact default-branch HEADまたは明示されたbase refから専用remote branchを作成します。
- default branchへ直接commitせず、専用branchへcommitしてDraft PRを作成します。
- ローカル差分、ローカルworktree、実行中processの状態を推測したり、remote-only作業の停止理由にしたりしません。
- ローカル検証を実行していない場合は、その事実を明記し、GitHub ActionsのExact HEAD結果を確認します。
- CIで安全に検証できない大規模変更、binary、生成物、秘密情報、Production操作はremote-onlyで実施しません。

途中でローカルコマンドやローカルファイル操作が必要になった場合、その時点から「ローカル作業」として専用worktree規則を適用します。

## 共通ルール

- **1 Issue = 1 Agent = 1 Branch**を原則とします。
- 他のエージェントのbranch、worktree、未コミット差分を変更しません。
- IssueのScopeと変更禁止範囲を厳格に遵守します。
- 無関係なリファクタリング、コード整頓、依存関係更新を混在させません。
- 未確認情報を過去の会話や別担当者の記憶で補完しません。
- default branchへの直接push、force push、履歴改変は行いません。

## ローカル作業の開始前手順

1. `README.md`、`AGENTS.md`、`CONTRIBUTING.md`、担当Issue本文を確認します。
2. 対象リポジトリ、remote、branch、HEAD、差分、worktree、関連Issue・PR、実行中processを確認します。

```bash
git remote -v
git status --short
git branch --show-current
git rev-parse HEAD
git worktree list --porcelain
```

3. 既存実装、テスト、CI設定を確認します。
4. 未関連変更を勝手に削除、stash、reset、上書き、commitしません。
5. 同じworktreeを別セッションが使用中の場合、編集、format、test、build、commit、pushを開始しません。

## Remote-only GitHub作業の開始前手順

1. repositoryのdefault branch、Exact HEAD、権限、関連Issue・PRをGitHubから再取得します。
2. 対象remote branchが既に存在しないこと、または自分の継続作業branchであることを確認します。
3. Exact baseから専用remote branchを作成します。
4. 変更対象ファイルの最新blob SHAと内容を取得してから更新します。
5. 1目的・小さくレビュー可能なcommitに分け、Draft PRを作成します。
6. GitHub Actions、status checks、diffを確認し、未実行検証を明記します。

Remote-only作業では、ローカルworktreeの有無、ローカルdirty状態、ローカルprocessを確認事項やBlockerに含めません。

## ローカルWorktree作成フロー

ローカル作業を開始する場合だけ、以下の標準フローを使用します。

```bash
# 1. リモート情報を更新
git fetch origin

# 2. branchおよびworktreeの重複確認
git branch --list agent/<issue-number>-<task-name>
git worktree list

# 3. 専用worktreeを作成
# Linux/macOS
git worktree add ../kokoitta-agent-<issue-number> \
  -b agent/<issue-number>-<task-name> \
  origin/main

# Windows PowerShell
git worktree add ..\kokoitta-agent-<issue-number> -b agent/<issue-number>-<task-name> origin/main

# 4. 作成したworktreeへ移動
# Linux/macOS
cd ../kokoitta-agent-<issue-number>
# Windows PowerShell
Set-Location ..\kokoitta-agent-<issue-number>

# 5. 移動後確認
git branch --show-current
git status --short
```

既存worktreeやbranchが存在する場合、独断で削除、再作成、`git worktree remove`、`git branch -D`を実行しません。不整合がある場合はファイルを変更せず、Coordinatorまたは該当Issueへ状況を記録します。

ローカル作業完了後は、統合済み、再開条件なし、未コミット差分なしを確認してから不要なworktreeを削除します。作業中または明確な再開条件があるworktreeは維持します。

## GitHub ProjectsのStatus更新

### Todo → In Progress

- ローカル作業：専用branch・worktreeを確認し、編集開始直前に変更します。
- Remote-only作業：Exact baseから専用remote branchを作成し、最初のremote commit直前に変更します。
- worktreeを使用しないremote-only作業に、worktree作成をStatus変更条件として要求しません。

### In Progress → In Review

実装、利用可能な検証、commit、push、Draft PR作成が完了した直後に変更します。未実行検証がある場合はPR本文へ明記します。

### In Review → Done

PRがmergeされ、Issueが完了した段階でDoneを確認します。CoordinatorまたはGitHub Projects自動化による更新を含みます。

### Project操作の安全ルール

- Project名や番号を固定値として埋め込みません。
- 対象Projectは、Issue本文、Coordinator Issue #12、`gh project list --owner kaenozu`の順で特定します。
- 複数候補がある場合は推測で更新しません。
- Project Item ID、Field ID、Option IDを固定値として文書へ記載しません。
- 権限不足やAPI errorを成功扱いにせず、実行内容とerrorを記録します。

## ホットスポット

以下は複数担当による同時編集を原則禁止します。これはローカル作業とremote-only作業の両方に適用します。

- `android/**`
- `.github/workflows/**`
- `lib/backup_*.dart`
- `lib/trip_store.dart`
- `lib/models.dart`
- `lib/home_data.dart`
- `lib/home_backup.dart`
- `pubspec.yaml`
- `pubspec.lock`

担当branch、対象Issue、変更予定ファイルを確認し、競合が避けられない場合は直列化します。

## 禁止操作

- `main`への直接pushまたは直接commit
- `git reset --hard`
- `git clean -fd`
- force push
- Coordinatorの明示指示がないmergeまたはrebase
- 他担当branchのcheckout・書換え・削除
- 他担当worktreeの変更・削除
- 未関連変更の削除、上書き、stash、commit
- 秘密情報、privateデータ、署名鍵のcommit
- 明示許可のないProduction、Play Console、Release、権限変更

## 品質基準

- エラーや例外を握りつぶしません。
- testをskipして成功扱いにしません。
- 型安全性を低下させません。
- データ損失、競合、security、境界値を確認します。
- 機能追加・修正時には回帰テストを追加します。

### ローカル作業

commit前にformatter、静的解析、関連test、全体test、必要なbuild、`git diff --check`を実行します。

### Remote-only作業

- ローカル検証を実行したと虚偽報告しません。
- Draft PRのExact HEADでGitHub Actionsとstatus checksを確認します。
- CIに必要な検証が存在しない場合は、その不足をBlockerまたはResidual Riskとして記録します。
- CI failureは原因を確認し、自分のbranchだけを修正します。
- 複雑な変更をCIだけで安全に検証できない場合、ローカル作業へ切り替えるまでDraftを維持します。

## 完了報告

IssueおよびPRへ次を記録します。

1. 実施内容
2. 主な変更ファイル
3. base branch・base HEAD・最終HEAD
4. 実行した検証と結果
5. 実行していない検証
6. 未確認事項または残存リスク
7. 依存Issueへの影響
8. PR URL
9. ローカル作業の場合のみ、worktreeの状態と削除・維持判断
