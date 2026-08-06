import 'package:flutter/material.dart';

import 'app_theme.dart';

class SettingsBackupView extends StatelessWidget {
  const SettingsBackupView({
    required this.isBusy,
    required this.canCreateBackup,
    required this.canRestore,
    required this.onCreateBackup,
    required this.onRestore,
    super.key,
    this.busyMessage,
    this.lastResult,
  });

  final bool isBusy;
  final bool canCreateBackup;
  final bool canRestore;
  final VoidCallback onCreateBackup;
  final VoidCallback onRestore;
  final String? busyMessage;
  final String? lastResult;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(KokoittaSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const KokoittaSectionHeader(
              title: '設定',
              supportingText: '表示とデータ保護の設定を確認できます。',
            ),
            const SizedBox(height: KokoittaSpacing.lg),
            const KokoittaSectionHeader(
              title: '表示とアクセシビリティ',
              supportingText: '端末のライト・ダーク設定と文字サイズをそのまま使用します。',
            ),
            const SizedBox(height: KokoittaSpacing.md),
            const ListTile(
              leading: Icon(Icons.brightness_auto_outlined),
              title: Text('外観'),
              subtitle: Text('端末のシステム設定に合わせます'),
            ),
            const ListTile(
              leading: Icon(Icons.accessibility_new_outlined),
              title: Text('文字サイズと読み上げ'),
              subtitle: Text('端末の文字サイズとTalkBack設定に対応します'),
            ),
            const Divider(height: KokoittaSpacing.xl),
            const KokoittaSectionHeader(
              title: 'データ保護',
              supportingText: '写真と旅行情報は端末内で処理されます。バックアップは共有先を自分で選べます。',
            ),
            if (isBusy) ...<Widget>[
              const SizedBox(height: KokoittaSpacing.md),
              KokoittaStatePanel(
                tone: KokoittaStateTone.progress,
                title: 'データを処理しています',
                message: busyMessage ?? '完了するまで競合する操作は利用できません。',
                busy: true,
                liveRegion: true,
              ),
            ],
            if (lastResult != null) ...<Widget>[
              const SizedBox(height: KokoittaSpacing.md),
              KokoittaStatePanel(
                tone: KokoittaStateTone.neutral,
                title: '前回の結果',
                message: lastResult,
                liveRegion: true,
              ),
            ],
            const SizedBox(height: KokoittaSpacing.md),
            Semantics(
              button: true,
              enabled: canCreateBackup && !isBusy,
              label: '完全バックアップを作成',
              hint: '旅行、旅行未設定、地図状態、写真をZIPに保存します',
              child: ListTile(
                enabled: canCreateBackup && !isBusy,
                minTileHeight: 56,
                leading: const Icon(Icons.backup_outlined),
                title: const Text('完全バックアップを作成'),
                subtitle: Text(
                  isBusy ? '処理中のため利用できません' : '旅行・地図状態・写真をZIPに保存',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: canCreateBackup && !isBusy ? onCreateBackup : null,
              ),
            ),
            Semantics(
              button: true,
              enabled: canRestore && !isBusy,
              label: '完全復元',
              hint: '検証後に現在のデータを置き換えます',
              child: ListTile(
                enabled: canRestore && !isBusy,
                minTileHeight: 56,
                leading: const Icon(Icons.restore_outlined),
                title: const Text('完全復元'),
                subtitle: Text(
                  isBusy ? '処理中のため利用できません' : 'バックアップを検証して現在のデータを置き換え',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: canRestore && !isBusy ? onRestore : null,
              ),
            ),
            const Divider(height: KokoittaSpacing.xl),
            const KokoittaSectionHeader(
              title: '注意が必要な操作',
              supportingText: '復元は現在のデータを置き換えます。確認画面で件数と影響を確認してから実行します。',
            ),
            const SizedBox(height: KokoittaSpacing.md),
            const KokoittaStatePanel(
              tone: KokoittaStateTone.warning,
              title: '復元前に安全バックアップを作成します',
              message: '復元を確定した場合でも、置き換え前の状態を端末内へ保存します。',
            ),
          ],
        ),
      ),
    );
  }
}
