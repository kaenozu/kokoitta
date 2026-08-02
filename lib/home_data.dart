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

  /// Roll back a committed import without deleting files while persistence is
  /// still in the committed state.
  Future<bool> _rollbackCommittedImport(
    AppData previousData,
    Iterable<Photo> copiedPhotos,
  ) async {
    try {
      await _store.save(previousData);
      if (mounted) _updateState(() => _data = previousData);
      return await _deleteFiles(copiedPhotos) == 0;
    } catch (_) {
      return false;
    }
  }

  Future<ImportEvent?> _importSharedUris(ImportEvent source) async {
    var copiedCount = 0;
    var successfulFiles = const <ImportedFile>[];
    var failures = <ImportFailure>[...source.failures];
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
          await _deleteFiles(copied.photos);
          copiedCount = 0;
          successfulFiles = const <ImportedFile>[];
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
          await _deleteFiles(copied.photos);
          copiedCount = 0;
          successfulFiles = const <ImportedFile>[];
          rethrow;
        }
        // 保存（commit）中のUIキャンセルは保存完了後にしか検出できない。
        // ストアとメモリをpreviousDataへ巻き戻し、写真も削除する。
        if (_cancelledImportRequestIds.contains(source.requestId)) {
          final rolledBack = await _rollbackCommittedImport(
            previousData,
            copied.photos,
          );
          copiedCount = 0;
          successfulFiles = const <ImportedFile>[];
          if (!rolledBack) {
            failures.add(
              const ImportFailure(
                index: 0,
                errorCode: 'rollback_failed',
                reason: '取り込みの取り消しに失敗しました',
              ),
            );
          }
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
    // キャンセル済みrequestの完了イベント・成功SnackBarは出さない。
    // キャンセル時のUI表示（cancelled event）は_cancelImportが担う。
    if (_cancelledImportRequestIds.contains(source.requestId)) {
      return null;
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
          await _deleteFiles(copied.photos);
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
          await _deleteFiles(copied.photos);
          rethrow;
        }
        // 保存（commit）中のUIキャンセルは保存完了後にしか検出できない。
        // ストアとメモリをpreviousDataへ巻き戻し、写真も削除する。
        if (_cancelledImportRequestIds.contains(requestId)) {
          final rolledBack = await _rollbackCommittedImport(
            previousData,
            copied.photos,
          );
          if (!rolledBack) {
            throw StateError('写真取り込みの取り消しに失敗しました');
          }
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
          '「${trip.title}」と写真${trip.photos.length}枚を端末から削除します。この操作は元に戻せません。',
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
      await _coordinator.runMutation(() async {
        final trip = _data.trips.where((item) => item.id == tripId).firstOrNull;
        if (trip == null) throw StateError('削除する旅行が見つかりません');
        await _commitData(removeTrip(_data, tripId));
        final failures = await _deleteFiles(trip.photos);
        _showMessage(
          failures == 0
              ? '旅行と写真を削除しました'
              : '旅行を削除しましたが、$failures枚のファイル削除に失敗しました',
        );
      });
    } catch (error) {
      _showError('旅行の削除', error);
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

  Future<void> _updatePrefecture(String name, String currentState) async {
    final nextState = currentState == 'unvisited'
        ? 'visited'
        : currentState == 'visited'
        ? 'transit'
        : 'unvisited';
    try {
      await _coordinator.runMutation(() async {
        await _commitData(updatePrefectureState(_data, name, nextState));
      });
    } catch (error) {
      _showError('都道府県の更新', error);
    }
  }
}
