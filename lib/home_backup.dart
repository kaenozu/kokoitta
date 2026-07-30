part of 'main.dart';

extension _HomeBackupActions on _HomePageState {
  Future<void> _showBackupMenu() async {
    if (!mounted) return;
    final isAnyBusy = _coordinator.isBusy;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'データ保護',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                enabled: _loadError == null && !_coordinator.isBackingUp,
                leading: const Icon(Icons.backup_outlined),
                title: const Text('完全バックアップを作成'),
                subtitle: _coordinator.isBackingUp
                    ? const Text('バックアップ作成中…')
                    : const Text('旅行・旅行未設定・地図状態・写真をZIPに保存'),
                onTap: isAnyBusy
                    ? null
                    : () {
                        Navigator.pop(sheetContext);
                        _createBackup();
                      },
              ),
              ListTile(
                enabled: !_coordinator.isRestoring,
                leading: const Icon(Icons.restore),
                title: const Text('完全復元'),
                subtitle: _coordinator.isRestoring
                    ? const Text('復元処理中…')
                    : const Text('検証後、現在のデータを安全に置き換え'),
                onTap: isAnyBusy
                    ? null
                    : () {
                        Navigator.pop(sheetContext);
                        _restoreBackup();
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createBackup() async {
    try {
      await _coordinator.runBackup(() async {
        final file = await _backupService.createBackup(_data);
        if (mounted) {
          await _backupService.shareBackup(file);
          _showMessage('バックアップを共有しました。端末内には最新5件まで保持されます。');
        }
      });
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
            '${prepared.tripCount}旅行・${prepared.photoCount}枚の写真を確認しました。現在のデータを置き換えますか？\n\n置き換え前のデータは安全バックアップとして端末内に保存します。',
        confirmLabel: '置き換える',
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
      if (mounted) _coordinator.endRestore();
    } catch (error) {
      if (prepared != null) await prepared.discard();
      if (restoreSessionStarted && mounted) _coordinator.endRestore();
      if (!mounted) return;
      _showError('復元', error);
    }
  }

  Future<void> _shareFiles(List<File> photos, String title) async {
    final files = <XFile>[];
    for (final file in photos) {
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
            title: Text(title),
            content: Text(message),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('キャンセル'),
              ),
              FilledButton(
                style: destructive
                    ? FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.error,
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

  Future<int> _deleteFiles(Iterable<File> files) async {
    var failures = 0;
    for (final file in files) {
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

  String _safeExtension(String path) {
    final name = path.split(RegExp(r'[/\\]')).last;
    final separator = name.lastIndexOf('.');
    if (separator < 0) return '.jpg';
    final extension = name.substring(separator).toLowerCase();
    return RegExp(r'^\.[a-z0-9]{1,5}$').hasMatch(extension)
        ? extension
        : '.jpg';
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
