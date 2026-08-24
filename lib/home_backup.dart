part of 'main.dart';

extension _HomeBackupActions on _HomePageState {
  Future<void> _showBackupMenu() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => StreamBuilder<OperationStatus>(
        stream: _coordinator.statusStream,
        initialData: _coordinator.status,
        builder: (context, snapshot) => _buildBackupMenu(sheetContext),
      ),
    );
  }

  Widget _buildBackupMenu(BuildContext sheetContext) {
    final isAnyBusy = _coordinator.isBusy;
    final busyMessage = _coordinator.isBackingUp
        ? 'バックアップを作成しています。共有先を選ぶまでお待ちください。'
        : _coordinator.isRestoring
        ? 'バックアップを検証または復元しています。'
        : isAnyBusy
        ? '別のデータ処理が完了するまでお待ちください。'
        : null;
    return FractionallySizedBox(
      heightFactor: 0.92,
      child: SettingsBackupView(
        isBusy: isAnyBusy,
        canCreateBackup: _loadError == null,
        canRestore: true,
        busyMessage: busyMessage,
        onCreateBackup: () {
          Navigator.pop(sheetContext);
          unawaited(_createBackup());
        },
        onRestore: () {
          Navigator.pop(sheetContext);
          unawaited(_restoreBackup());
        },
      ),
    );
  }

  Future<void> _createBackup() async {
    try {
      final file = await _coordinator.runBackup(
        () => _backupService.createBackup(_data),
      );
      if (mounted) {
        await _backupService.shareBackup(file);
        _showMessage('バックアップを共有しました。端末内には最新5件まで保持されます。');
      }
    } catch (error) {
      if (!mounted) return;
      _showError('バックアップ作成', error);
    }
  }

  Future<void> _restoreBackup() async {
    PreparedRestore? prepared;
    var restoreSessionStarted = false;
    try {
      _coordinator.beginRestorePrepare();
      restoreSessionStarted = true;
      prepared = await _backupService.prepareRestore();
      if (prepared == null || !mounted) {
        _coordinator.endRestore();
        return;
      }

      _coordinator.enterRestoreConfirm();
      final confirmed = await _confirm(
        title: '完全復元',
        message:
            '${prepared.tripCount}旅行・${prepared.photoCount}枚の写真を確認しました。現在のデータを置き換えます。\n\n置き換え前のデータは安全バックアップとして端末内に保存します。',
        confirmLabel: '現在のデータを置き換える',
        destructive: true,
      );
      if (!confirmed) {
        await prepared.discard();
        _coordinator.endRestore();
        return;
      }

      await _coordinator.runRestoreCommit(() async {
        final current = _data;
        final oldFiles = current.allPhotos.toList(growable: false);
        final safetyBackup = await _backupService.createSafetySnapshot(current);
        final committed = await prepared!.commit();
        try {
          await _store.save(committed.data);
        } catch (_) {
          await committed.rollback();
          rethrow;
        }

        if (mounted) _updateState(() => _data = committed.data);
        final cleanupFailures = await _deleteFiles(oldFiles);
        final backupName = safetyBackup.path.split(Platform.pathSeparator).last;
        _showMessage(
          cleanupFailures == 0
              ? '復元が完了しました。復元前バックアップ: $backupName'
              : '復元は完了しましたが、旧写真$cleanupFailures枚の削除に失敗しました',
        );
      });
      // CoordinatorはWidgetより長生きするため、セッション解放はmountedに
      // 依存させない。解除を欠かすと以後の全mutationがStateErrorで拒否される。
      _coordinator.endRestore();
    } catch (error) {
      if (prepared != null) await prepared.discard();
      if (restoreSessionStarted) _coordinator.endRestore();
      if (!mounted) return;
      _showError('復元', error);
    }
  }

  Future<void> _shareFiles(List<Photo> photos, String title) async {
    final files = <XFile>[];
    for (final photo in photos) {
      final file = photo.file;
      if (await file.exists()) files.add(XFile(file.path));
    }
    if (files.isEmpty) {
      _showMessage('共有できる写真がありません');
      return;
    }
    try {
      await SharePlus.instance.share(ShareParams(files: files, text: title));
    } catch (error) {
      _showError('写真の共有', error);
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            scrollable: true,
            title: Semantics(header: true, child: Text(title)),
            content: Text(message),
            actionsAlignment: MainAxisAlignment.end,
            actions: <Widget>[
              TextButton(
                autofocus: true,
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('キャンセル'),
              ),
              FilledButton(
                style: destructive
                    ? FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.error,
                        foregroundColor: Theme.of(context).colorScheme.onError,
                      )
                    : null,
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(confirmLabel),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<int> _deleteFiles(Iterable<Photo> photos) async {
    final injected = widget.photoDeleteRunner;
    if (injected != null) return injected(photos);

    var failures = 0;
    for (final photo in photos) {
      final file = photo.file;
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {
        failures += 1;
      }
    }
    return failures;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 表示中のSnackBarを閉じてから新しいSnackBarを表示する。
  ///
  /// 待機列に入ると直前のUndo SnackBarが消えるまで新しい表示が遅れるため、
  /// Undo完了やUndo期限到達など、直前のフィードバックを即座に置き換えたい
  /// 場面で使う。
  void _showMessageNow(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  void _showError(String action, Object error) {
    _showMessage('$actionに失敗しました: ${_readableError(error)}');
  }

  String _readableError(Object error) {
    if (error is FormatException) return error.message.toString();
    if (error is PlatformException) return error.message ?? error.code;
    if (error is FileSystemException) return error.message;
    if (error is StateError) return error.message.toString();
    return '予期しないエラーが発生しました';
  }
}
