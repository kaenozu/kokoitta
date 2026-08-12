part of 'main.dart';

class _CopiedImportResult {
  const _CopiedImportResult({
    required this.photos,
    required this.failures,
    this.successfulFiles = const <ImportedFile>[],
  });

  final List<Photo> photos;
  final List<ImportFailure> failures;

  /// Shared inputs corresponding to [photos], in the same order.
  ///
  /// Picker imports do not use this mapping and leave it empty.
  final List<ImportedFile> successfulFiles;
}

extension _HomeDataActions on _HomePageState {
  Future<void> _runStartupCleanup() async {
    try {
      // cleanupは写真ファイルを物理削除するため、写真を変更する全操作と
      // 同一の操作キュー（OperationCoordinator）上で直列化する。
      // actionはキュー実行時に評価されるため、実行時点の最新の確定済み
      // AppDataを参照判定に使用する。
      await _coordinator.runCleanup(() => _cleanupRunner(_data));
    } catch (_) {
      // Cleanup failures must not block application startup.
      // キューは解放され、次回起動のcleanupで再試行される。
    }
  }

  void _scheduleStartupCleanup() {
    if (_isCleanupRunning) return;
    _isCleanupRunning = true;
    unawaited(
      _runStartupCleanup().whenComplete(() {
        _isCleanupRunning = false;
      }),
    );
  }

  Future<void> _initialize() async {
    try {
      final loaded = await _store.load();
      if (!mounted) return;
      _updateState(() {
        _data = loaded;
        _isLoading = false;
      });
      _scheduleStartupCleanup();
      await _consumeInitialSharedUris();
    } catch (error) {
      if (!mounted) return;
      _updateState(() {
        _loadError = _readableError(error);
        _isLoading = false;
      });
    }
  }

  Future<void> _consumeInitialSharedUris() async {
    try {
      final legacy = await _HomePageState._shareChannel.invokeMethod<Object?>(
        'getSharedUris',
      );
      if (legacy == null) return;
      final event = ImportEventParser.parseLegacyResult(legacy);
      if (event.total == 0) return;
      if (!_acceptIncomingImportRequest(event.requestId)) return;
      _setImportEvent(
        event.copyWith(phase: ImportPhase.saving, isTerminal: false),
      );
      final result = await _importSharedUris(event);
      if (result != null) _setImportEvent(result);
    } on MissingPluginException {
      // Widget tests and unsupported platforms do not provide the Android channel.
    } on FormatException catch (error) {
      _showError('共有写真の確認', error);
    } on PlatformException catch (error) {
      _showError('共有写真の確認', error);
    }
  }

  Future<dynamic> _handleShareMethod(MethodCall call) async {
    // 永続データのロード完了を待つ。ロード失敗時は空のAppDataで共有イベントを
    // 処理して既存の保存データを上書きしないよう、イベントを無視する。
    await _initialization;
    if (_loadError != null) return null;
    try {
      final event = ImportEventParser.parseMethodCall(
        call.method,
        call.arguments,
      );
      if (!_acceptIncomingImportRequest(event.requestId)) {
        return null;
      }
      if (!event.isTerminal) {
        _setImportEvent(event);
        return null;
      }
      _setImportEvent(
        event.copyWith(phase: ImportPhase.saving, isTerminal: false),
      );
      final result = await _importSharedUris(event);
      if (result != null) _setImportEvent(result);
    } on FormatException catch (error) {
      _showError('共有写真の取り込み', error);
    } on MissingPluginException {
      // Widget tests and unsupported platforms do not provide the Android channel.
    }
    return null;
  }

  bool _acceptIncomingImportRequest(String requestId) {
    if (_terminalImportRequestIds.contains(requestId)) return false;
    if (_importRequestGate.accepts(requestId)) return true;
    if (_importRequestGate.isActive) return false;
    return _importRequestGate.start(requestId);
  }

  Future<void> _commitData(AppData next) async {
    await _store.save(next);
    if (!mounted) return;
    _updateState(() => _data = next);
  }

  ImportEvent _sharedCancellationResult(
    ImportEvent source, {
    ImportFailure? failure,
  }) {
    if (failure != null) {
      return ImportEvent(
        requestId: source.requestId,
        phase: ImportPhase.failed,
        processed: 1,
        total: 1,
        succeeded: 0,
        failed: 1,
        isTerminal: true,
        failures: <ImportFailure>[failure],
      );
    }
    return ImportEvent(
      requestId: source.requestId,
      phase: ImportPhase.cancelled,
      processed: source.processed,
      total: source.total,
      succeeded: 0,
      failed: source.failures.length,
      isTerminal: true,
      failures: source.failures,
    );
  }

  /// Roll back a committed import, then remove every generated photo file.
  ///
  /// A concrete failure is returned so cancellation cannot be reported as
  /// successful while persistence or file cleanup is still inconsistent.
  Future<ImportFailure?> _rollbackCommittedImport(
    AppData previousData,
    Iterable<Photo> copiedPhotos,
  ) async {
    try {
      await _store.save(previousData);
      if (mounted) _updateState(() => _data = previousData);
    } catch (error) {
      return ImportFailure(
        index: 0,
        errorCode: 'rollback_restore_failed',
        reason: '取り込み前の保存状態へ戻せませんでした: ${_readableError(error)}',
      );
    }

    final deleteFailures = await _deleteFiles(copiedPhotos);
    if (deleteFailures > 0) {
      return ImportFailure(
        index: 0,
        errorCode: 'rollback_cleanup_failed',
        reason: '$deleteFailures枚の生成写真を削除できませんでした',
      );
    }
    return null;
  }

  Future<ImportEvent?> _importSharedUris(ImportEvent source) async {
    var copiedCount = 0;
    var successfulFiles = const <ImportedFile>[];
    var failures = <ImportFailure>[...source.failures];
    ImportEvent? cancellationResult;
    try {
      await _coordinator.runMutation(() async {
        final uniqueFiles = <ImportedFile>[];
        final seen = <String>{};
        for (final file in source.successes) {
          if (seen.add(file.path)) uniqueFiles.add(file);
        }
        final available = _HomePageState._maxPhotos - _data.photoCount;
        if (available <= 0 || uniqueFiles.length > available) {
          failures.addAll(
            await _deleteTemporarySharedFiles(
              uniqueFiles.map((file) => file.path),
            ),
          );
          failures.add(
            const ImportFailure(
              index: 0,
              errorCode: 'photo_quota_exceeded',
              reason: '無料版の写真上限300枚を超えるため取り込めません',
            ),
          );
          return;
        }

        final copied = await _copySharedFiles(uniqueFiles);
        failures = <ImportFailure>[...failures, ...copied.failures];
        copiedCount = copied.photos.length;
        successfulFiles = copied.successfulFiles;
        if (_cancelledImportRequestIds.contains(source.requestId)) {
          final deleteFailures = await _deleteFiles(copied.photos);
          copiedCount = 0;
          successfulFiles = const <ImportedFile>[];
          cancellationResult = _sharedCancellationResult(
            source,
            failure: deleteFailures == 0
                ? null
                : ImportFailure(
                    index: 0,
                    errorCode: 'cancel_cleanup_failed',
                    reason: '$deleteFailures枚の生成写真を削除できませんでした',
                  ),
          );
          return;
        }
        if (copied.photos.isEmpty) return;

        final previousData = _data;
        final createsTrip = _data.trips.length < _HomePageState._maxTrips;
        AppData next;
        if (createsTrip) {
          next = addNewTrip(
            _data,
            Trip(
              id: createEntityId('trip'),
              title: '共有からのおでかけ ${_data.trips.length + 1}',
              photos: copied.photos,
            ),
          );
        } else {
          next = _data.copyWith(
            unassignedPhotos: <Photo>[
              ..._data.unassignedPhotos,
              ...copied.photos,
            ],
          );
        }

        try {
          await _commitData(next);
        } catch (_) {
          final deleteFailures = await _deleteFiles(copied.photos);
          copiedCount = 0;
          successfulFiles = const <ImportedFile>[];
          if (_cancelledImportRequestIds.contains(source.requestId)) {
            cancellationResult = _sharedCancellationResult(
              source,
              failure: deleteFailures == 0
                  ? null
                  : ImportFailure(
                      index: 0,
                      errorCode: 'cancel_cleanup_failed',
                      reason: '$deleteFailures枚の生成写真を削除できませんでした',
                    ),
            );
            return;
          }
          rethrow;
        }
        // 保存（commit）中のUIキャンセルは保存完了後にしか検出できない。
        // ストアとメモリをpreviousDataへ巻き戻し、写真も削除する。
        if (_cancelledImportRequestIds.contains(source.requestId)) {
          final rollbackFailure = await _rollbackCommittedImport(
            previousData,
            copied.photos,
          );
          copiedCount = 0;
          successfulFiles = const <ImportedFile>[];
          cancellationResult = _sharedCancellationResult(
            source,
            failure: rollbackFailure,
          );
          return;
        }
      });
    } catch (error) {
      failures.add(
        ImportFailure(
          index: 0,
          errorCode: 'save_failed',
          reason: _readableError(error),
        ),
      );
    }

    if (cancellationResult != null) {
      if (cancellationResult!.phase == ImportPhase.failed) {
        _showMessage('取り込みの取り消しに失敗しました。旅行と写真を確認してください');
      }
      return cancellationResult;
    }
    if (_cancelledImportRequestIds.contains(source.requestId)) {
      final cleanupFailure = failures
          .where(
            (failure) =>
                failure.errorCode == 'temporary_cleanup_failed' ||
                failure.errorCode == 'cancel_cleanup_failed',
          )
          .firstOrNull;
      final result = _sharedCancellationResult(source, failure: cleanupFailure);
      if (result.phase == ImportPhase.failed) {
        _showMessage('取り込みの取り消しに失敗しました。写真を確認してください');
      }
      return result;
    }

    final phase = failures.isEmpty
        ? ImportPhase.completed
        : copiedCount > 0
        ? ImportPhase.partialFailure
        : ImportPhase.failed;
    final completed = ImportEvent(
      requestId: source.requestId,
      phase: phase,
      processed: copiedCount + failures.length,
      total: copiedCount + failures.length,
      succeeded: copiedCount,
      failed: failures.length,
      isTerminal: true,
      successes: successfulFiles,
      failures: failures,
    );
    if (completed.phase == ImportPhase.completed) {
      _showMessage('$copiedCount枚を共有から取り込みました');
    } else if (completed.phase == ImportPhase.partialFailure) {
      _showMessage('$copiedCount件を取り込みました（${failures.length}件失敗）');
    } else {
      _showMessage('共有写真の取り込みに失敗しました');
    }
    return completed;
  }

  Future<_CopiedImportResult> _copySharedFiles(List<ImportedFile> files) async {
    final directory = await getApplicationDocumentsDirectory();
    final photosDirectory = Directory('${directory.path}/photos');
    await photosDirectory.create(recursive: true);
    final copied = <Photo>[];
    final successfulFiles = <ImportedFile>[];
    final failures = <ImportFailure>[];
    try {
      for (var index = 0; index < files.length; index++) {
        final imported = files[index];
        final source = File(imported.path);
        try {
          if (!await source.exists()) {
            throw const FileSystemException('一時ファイルが見つかりません');
          }
          final destination = File(
            '${photosDirectory.path}/${createEntityId('shared')}-${index.toString().padLeft(3, '0')}${_safeExtension(imported.name)}',
          );
          final copiedFile = await source.copy(destination.path);
          copied.add(
            Photo(
              id: createPhotoId(),
              file: copiedFile,
              capturedAt: null,
              originalName: imported.name,
              mimeType: imported.mimeType,
            ),
          );
          successfulFiles.add(imported);
        } catch (error) {
          failures.add(
            ImportFailure(
              index: index,
              errorCode: 'copy_failed',
              reason: _readableError(error),
            ),
          );
        }
      }
    } finally {
      failures.addAll(
        await _deleteTemporarySharedFiles(files.map((file) => file.path)),
      );
    }
    return _CopiedImportResult(
      photos: copied,
      failures: failures,
      successfulFiles: successfulFiles,
    );
  }

  Future<List<ImportFailure>> _deleteTemporarySharedFiles(
    Iterable<String> paths,
  ) async {
    final failures = <ImportFailure>[];
    var index = 0;
    for (final path in paths) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (error) {
        failures.add(
          ImportFailure(
            index: index,
            errorCode: 'temporary_cleanup_failed',
            reason: _readableError(error),
          ),
        );
      }
      index++;
    }
    return failures;
  }

  Future<void> _addPhotos({String? tripId}) async {
    if (_loadError != null) return;
    final selected = await _picker.pickMultiImage(
      imageQuality: 85,
      maxWidth: 2048,
    );
    if (selected.isEmpty || !mounted) return;
    final requestId = 'picker-${DateTime.now().microsecondsSinceEpoch}';
    if (!_importRequestGate.start(requestId)) return;
    void setPickerEvent({
      required ImportPhase phase,
      required int processed,
      required int succeeded,
      required int failed,
      required bool terminal,
      List<ImportFailure> failures = const <ImportFailure>[],
    }) {
      _setImportEvent(
        ImportEvent(
          requestId: requestId,
          phase: phase,
          processed: processed,
          total: selected.length,
          succeeded: succeeded,
          failed: failed,
          isTerminal: terminal,
          failures: failures,
        ),
      );
    }

    void setPickerCancellationResult(ImportFailure? failure) {
      setPickerEvent(
        phase: failure == null ? ImportPhase.cancelled : ImportPhase.failed,
        processed: failure == null ? 0 : 1,
        succeeded: 0,
        failed: failure == null ? 0 : 1,
        terminal: true,
        failures: failure == null
            ? const <ImportFailure>[]
            : <ImportFailure>[failure],
      );
      if (failure != null) {
        _showMessage('取り込みの取り消しに失敗しました。旅行と写真を確認してください');
      }
    }

    setPickerEvent(
      phase: ImportPhase.preparing,
      processed: 0,
      succeeded: 0,
      failed: 0,
      terminal: false,
    );

    try {
      await _coordinator.runMutation(() async {
        final available = _HomePageState._maxPhotos - _data.photoCount;
        if (selected.length > available) {
          const failure = ImportFailure(
            index: 0,
            errorCode: 'photo_quota_exceeded',
            reason: '追加できる枚数の上限を超えています',
          );
          setPickerEvent(
            phase: ImportPhase.failed,
            processed: selected.length,
            succeeded: 0,
            failed: selected.length,
            terminal: true,
            failures: List<ImportFailure>.filled(selected.length, failure),
          );
          _showMessage('追加できるのは残り$available枚です。枚数を減らして選び直してください');
          return;
        }
        if (tripId == null && _data.trips.length >= _HomePageState._maxTrips) {
          setPickerEvent(
            phase: ImportPhase.failed,
            processed: selected.length,
            succeeded: 0,
            failed: selected.length,
            terminal: true,
            failures: List<ImportFailure>.filled(
              selected.length,
              const ImportFailure(
                index: 0,
                errorCode: 'trip_quota_exceeded',
                reason: '旅行は10件までです',
              ),
            ),
          );
          _showMessage('旅行は10件までです。既存旅行へ追加するか旅行を整理してください');
          return;
        }

        setPickerEvent(
          phase: ImportPhase.copying,
          processed: 0,
          succeeded: 0,
          failed: 0,
          terminal: false,
        );
        final copied = await _copyPickedImages(
          selected,
          onProgress: (processed, succeeded, failed) => setPickerEvent(
            phase: ImportPhase.copying,
            processed: processed,
            succeeded: succeeded,
            failed: failed,
            terminal: false,
          ),
        );
        if (_cancelledImportRequestIds.contains(requestId)) {
          final deleteFailures = await _deleteFiles(copied.photos);
          setPickerCancellationResult(
            deleteFailures == 0
                ? null
                : ImportFailure(
                    index: 0,
                    errorCode: 'cancel_cleanup_failed',
                    reason: '$deleteFailures枚の生成写真を削除できませんでした',
                  ),
          );
          return;
        }
        if (copied.photos.isEmpty) {
          setPickerEvent(
            phase: ImportPhase.failed,
            processed: selected.length,
            succeeded: 0,
            failed: copied.failures.length,
            terminal: true,
            failures: copied.failures,
          );
          return;
        }
        setPickerEvent(
          phase: ImportPhase.saving,
          processed: selected.length,
          succeeded: copied.photos.length,
          failed: copied.failures.length,
          terminal: false,
          failures: copied.failures,
        );
        final previousData = _data;
        final next = tripId == null
            ? addNewTrip(
                _data,
                Trip(
                  id: createEntityId('trip'),
                  title: '新しいおでかけ ${_data.trips.length + 1}',
                  photos: copied.photos,
                ),
              )
            : addPhotosToTrip(_data, tripId, copied.photos);

        try {
          await _commitData(next);
        } catch (_) {
          final deleteFailures = await _deleteFiles(copied.photos);
          if (_cancelledImportRequestIds.contains(requestId)) {
            setPickerCancellationResult(
              deleteFailures == 0
                  ? null
                  : ImportFailure(
                      index: 0,
                      errorCode: 'cancel_cleanup_failed',
                      reason: '$deleteFailures枚の生成写真を削除できませんでした',
                    ),
            );
            return;
          }
          rethrow;
        }
        // 保存（commit）中のUIキャンセルは保存完了後にしか検出できない。
        // ストアとメモリをpreviousDataへ巻き戻し、写真も削除する。
        if (_cancelledImportRequestIds.contains(requestId)) {
          final rollbackFailure = await _rollbackCommittedImport(
            previousData,
            copied.photos,
          );
          setPickerCancellationResult(rollbackFailure);
          return;
        }
        final phase = copied.failures.isEmpty
            ? ImportPhase.completed
            : ImportPhase.partialFailure;
        setPickerEvent(
          phase: phase,
          processed: selected.length,
          succeeded: copied.photos.length,
          failed: copied.failures.length,
          terminal: true,
          failures: copied.failures,
        );
        _showMessage(
          copied.failures.isEmpty
              ? '${copied.photos.length}枚を取り込みました'
              : '${copied.photos.length}枚を取り込みました（${copied.failures.length}件失敗）',
        );
      });
    } catch (error) {
      setPickerEvent(
        phase: ImportPhase.failed,
        processed: selected.length,
        succeeded: 0,
        failed: selected.length,
        terminal: true,
        failures: <ImportFailure>[
          ImportFailure(
            index: 0,
            errorCode: 'import_failed',
            reason: _readableError(error),
          ),
        ],
      );
      _showError('写真の取り込み', error);
    }
  }

  /// 欠損写真の確認・復旧ボトムシートを開く。
  ///
  /// 欠損写真を所属旅行ごとにまとめて表示し、1枚ごとに「選び直す」（再割り当て）
  /// と「破棄」（レコード削除）を提供する。「すべて破棄」で全件一括削除もできる。
  void _showMissingPhotosRecovery() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final missing = _missingPhotos;
          if (missing.isEmpty) {
            return const SafeArea(child: SizedBox.shrink());
          }
          final grouped = <String, List<MissingPhoto>>{};
          for (final entry in missing) {
            grouped
                .putIfAbsent(entry.tripTitle, () => <MissingPhoto>[])
                .add(entry);
          }
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                KokoittaSpacing.md,
                KokoittaSpacing.xs,
                KokoittaSpacing.md,
                KokoittaSpacing.lg,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    '見つからない写真（${missing.length}枚）',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: KokoittaSpacing.xs),
                  Text(
                    '端末内から移動・削除された可能性があります。同じ写真を選び直すか、'
                    '記録を破棄できます。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: KokoittaSpacing.md),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: <Widget>[
                        for (final entry in grouped.entries) ...<Widget>[
                          Padding(
                            padding: const EdgeInsets.only(
                              top: KokoittaSpacing.sm,
                              bottom: KokoittaSpacing.xs,
                            ),
                            child: Text(
                              entry.key.isEmpty ? '旅行に未設定の写真' : entry.key,
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                          ),
                          for (final item in entry.value)
                            _MissingPhotoTile(
                              missing: item,
                              onReassign: () async {
                                await _reassignMissingPhoto(item);
                                if (mounted) {
                                  setSheetState(() {});
                                }
                              },
                              onDiscard: () async {
                                await _discardMissingPhoto(item);
                                if (mounted) {
                                  setSheetState(() {});
                                }
                              },
                            ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: KokoittaSpacing.md),
                  if (missing.length > 1)
                    KokoittaActionButton(
                      label: 'すべて破棄（${missing.length}枚）',
                      icon: Icons.delete_outline,
                      emphasis: KokoittaActionEmphasis.secondary,
                      onPressed: () async {
                        await _discardMissingPhotos(missing);
                        if (mounted) {
                          setSheetState(() {});
                        }
                      },
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 1枚の欠損写真をギャラリーから選び直して再割り当てする。
  Future<void> _reassignMissingPhoto(MissingPhoto missing) async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 2048,
    );
    if (picked == null || !mounted) return;
    try {
      final directory = await getApplicationDocumentsDirectory();
      final photosDirectory = Directory('${directory.path}/photos');
      await photosDirectory.create(recursive: true);
      final source = File(picked.path);
      if (!await source.exists()) {
        throw const FileSystemException('選択した写真を読み込めませんでした');
      }
      final destination = File(
        '${photosDirectory.path}/${createEntityId('reassign')}${_safeExtension(picked.name)}',
      );
      final copied = await source.copy(destination.path);
      await _coordinator.runMutation(() async {
        final data = await _store.reassignMissingPhoto(missing, copied);
        _updateState(() {
          _data = data;
          _missingPhotos = _store.missingPhotos;
        });
      });
      if (mounted) _showMessage('写真を再割り当てしました');
    } catch (error) {
      _showError('写真の再割り当て', error);
    }
  }

  /// 1枚の欠損写真のレコードを保存データから破棄する。
  Future<void> _discardMissingPhoto(MissingPhoto missing) async {
    final confirmed = await _confirmDiscard(missing);
    if (confirmed != true || !mounted) return;
    try {
      await _coordinator.runMutation(() async {
        final data = await _store.discardMissingPhotos(<MissingPhoto>[missing]);
        _updateState(() {
          _data = data;
          _missingPhotos = _store.missingPhotos;
        });
      });
      if (mounted) _showMessage('欠損写真の記録を破棄しました');
    } catch (error) {
      _showError('欠損写真の破棄', error);
    }
  }

  /// 欠損写真のレコードをすべて破棄する。
  Future<void> _discardMissingPhotos(List<MissingPhoto> missing) async {
    final confirmed = await _confirmDiscard(
      missing.first,
      count: missing.length,
    );
    if (confirmed != true || !mounted) return;
    try {
      await _coordinator.runMutation(() async {
        final data = await _store.discardMissingPhotos(missing);
        _updateState(() {
          _data = data;
          _missingPhotos = _store.missingPhotos;
        });
      });
      if (mounted) _showMessage('欠損写真の記録を破棄しました');
    } catch (error) {
      _showError('欠損写真の破棄', error);
    }
  }

  Future<bool?> _confirmDiscard(MissingPhoto missing, {int? count}) {
    final label = count != null ? '写真が$count枚見つかりません' : '写真が見つかりません';
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(label),
        content: Text(
          '破棄すると、この写真の記録（${missing.path}）が保存データから削除されます。'
          '元の写真ファイルが端末にある場合は、先に「選び直す」で再登録できます。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('破棄'),
          ),
        ],
      ),
    );
  }

  Future<_CopiedImportResult> _copyPickedImages(
    List<XFile> selected, {
    required void Function(int processed, int succeeded, int failed) onProgress,
  }) async {
    final directory = await getApplicationDocumentsDirectory();
    final photosDirectory = Directory('${directory.path}/photos');
    await photosDirectory.create(recursive: true);
    final copied = <Photo>[];
    final failures = <ImportFailure>[];
    for (var index = 0; index < selected.length; index++) {
      try {
        final image = selected[index];
        final source = File(image.path);
        final safeName = image.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
        final destination = File(
          '${photosDirectory.path}/${createEntityId('photo')}-${index.toString().padLeft(3, '0')}-$safeName',
        );
        final copiedFile = await source.copy(destination.path);
        // 撮影日時は不明のためnull。ファイル更新日時を撮影日時として
        // 永続化してはならない（推測日時の保存禁止）。
        copied.add(
          Photo(
            id: createPhotoId(),
            file: copiedFile,
            capturedAt: null,
            originalName: image.name,
            mimeType: _mimeTypeOf(image.path),
          ),
        );
      } catch (error) {
        failures.add(
          ImportFailure(
            index: index,
            errorCode: 'copy_failed',
            reason: _readableError(error),
          ),
        );
      }
      onProgress(index + 1, copied.length, failures.length);
    }
    return _CopiedImportResult(photos: copied, failures: failures);
  }

  String? _mimeTypeOf(String path) {
    final fileName = path.split(RegExp(r'[/\\]')).last;
    final separator = fileName.lastIndexOf('.');
    if (separator < 0) return null;
    return switch (fileName.substring(separator + 1).toLowerCase()) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'bmp' => 'image/bmp',
      'heic' => 'image/heic',
      'heif' => 'image/heif',
      _ => null,
    };
  }

  Future<void> _handleTripMenu(Trip trip, String action) async {
    if (action == 'move') {
      final confirmed = await _confirm(
        title: '旅行未設定へ移動',
        message: '「${trip.title}」を削除し、写真${trip.photos.length}枚を旅行未設定へ移動します。',
        confirmLabel: '移動する',
      );
      if (confirmed) await _moveTripToUnassigned(trip.id);
      return;
    }

    final confirmed = await _confirm(
      title: '写真も削除',
      message:
          '「${trip.title}」と写真${trip.photos.length}枚を一時退避して削除します。30秒以内ならUndoできます。',
      confirmLabel: '削除する',
      destructive: true,
    );
    if (confirmed) await _deleteTripAndPhotos(trip.id);
  }

  Future<void> _moveTripToUnassigned(String tripId) async {
    try {
      await _coordinator.runMutation(() async {
        await _commitData(moveTripToUnassigned(_data, tripId));
        _showMessage('写真を旅行未設定へ移動しました');
      });
    } catch (error) {
      _showError('旅行の移動', error);
    }
  }

  Future<void> _deleteTripAndPhotos(String tripId) async {
    try {
      // 初期化失敗時はここで再試行する。それでも失敗したら削除を開始しない。
      var ready = _pendingDeletionAvailable;
      if (!ready) ready = await _buildPendingDeletion();
      final pendingDeletion = _pendingDeletion;
      if (!ready || pendingDeletion == null) {
        throw StateError('削除機能を初期化できませんでした');
      }
      await _coordinator.runMutation(() async {
        final operation = await pendingDeletion.deleteTrip(
          data: _data,
          tripId: tripId,
          saveData: _commitData,
        );
        _schedulePendingExpiry(operation);
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              // Undo可能な窓が切れるまで表示を保ち、期限到達で必ず消えるようにする。
              duration: pendingDeletion.undoWindow,
              content: const Text('旅行と写真を削除しました。30秒以内ならUndoできます'),
              action: SnackBarAction(
                label: 'Undo',
                onPressed: () =>
                    unawaited(_undoPendingDeletion(operation.operationId)),
              ),
            ),
          );
      });
    } catch (error) {
      _showError('旅行の削除', error);
    }
  }

  Future<void> _undoPendingDeletion(String operationId) async {
    try {
      await _coordinator.runMutation(() async {
        final pendingDeletion = _pendingDeletion;
        if (pendingDeletion == null) {
          throw StateError('削除機能を初期化できませんでした');
        }
        await pendingDeletion.undo(
          operationId: operationId,
          data: _data,
          saveData: _commitData,
        );
        _pendingUndoTimers.remove(operationId)?.cancel();
        if (mounted) _showMessageNow('旅行と写真を元に戻しました');
      });
    } catch (error) {
      if (mounted) _showError('削除の取り消し', error);
    }
  }

  Future<void> _finalizePendingDeletion(String operationId) async {
    try {
      final pendingDeletion = _pendingDeletion;
      if (pendingDeletion == null) {
        developer.log(
          'pending deletion finalize skipped: manager unavailable',
          name: 'kokoitta',
        );
        return;
      }
      await _coordinator.runCleanup(() async {
        final finalized = await pendingDeletion.finalizeExpired();
        if (finalized.contains(operationId) && mounted) {
          _showMessageNow('Undo期限が切れたため、写真を完全に削除しました');
        }
      });
    } on StateError catch (error) {
      // 起動時cleanup等が既にキューにある場合は、ユーザーへ誤エラーを表示せず
      // 短時間後に再試行する。恒久的な失敗は次回起動のrecoverで再処理される。
      if (error.message.contains('Cleanup already in progress')) {
        developer.log(
          'pending deletion finalize deferred: cleanup busy',
          name: 'kokoitta',
        );
        _pendingUndoTimers[operationId]?.cancel();
        _pendingUndoTimers[operationId] = Timer(const Duration(seconds: 2), () {
          _pendingUndoTimers.remove(operationId);
          unawaited(_finalizePendingDeletion(operationId));
        });
        return;
      }
      if (mounted) _showError('削除済み写真の回収', error);
    } catch (error) {
      if (mounted) _showError('削除済み写真の回収', error);
    }
  }

  Future<void> _createTripFromUnassigned() async {
    if (_data.trips.length >= _HomePageState._maxTrips) {
      _showMessage('旅行は10件までです。旅行を整理してから実行してください');
      return;
    }
    try {
      await _coordinator.runMutation(() async {
        final trip = Trip(
          id: createEntityId('trip'),
          title: '新しいおでかけ ${_data.trips.length + 1}',
          photos: _data.unassignedPhotos,
        );
        await _commitData(createTripFromUnassigned(_data, trip));
        if (mounted) Navigator.of(context).maybePop();
        _showMessage('旅行未設定の写真を新しい旅行にまとめました');
      });
    } catch (error) {
      _showError('旅行の作成', error);
    }
  }

  /// 都道府県の状態を [nextState] に直接設定する。
  ///
  /// 地図タップ・都道府県リストは BottomSheet での明示選択を経由して
  /// このメソッドを呼ぶ（誤タップによる順送り変更を防ぐ）。
  Future<void> _setPrefectureState(String name, String nextState) async {
    try {
      await _coordinator.runMutation(() async {
        await _commitData(updatePrefectureState(_data, name, nextState));
      });
    } catch (error) {
      _showError('都道府県の更新', error);
    }
  }
}
