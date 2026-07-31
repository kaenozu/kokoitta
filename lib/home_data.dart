part of 'main.dart';

extension _HomeDataActions on _HomePageState {
  Future<void> _runStartupCleanup() async {
    try {
      await StorageCleanup.run(appData: _data);
    } catch (_) {
      // Cleanup failures must not block application startup.
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
      await _recoverPendingDeletions();
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

  /// 起動時に未確定・期限内のpending deletionを回収する。
  ///
  /// * 削除が未確定（旅行が残っている）→ ファイルを元へ戻す
  /// * 削除確定済みかつ期限内 → Undo可能な状態として復元しSnackBarを出す
  /// * 期限切れはStorageCleanupが確定削除する
  Future<void> _recoverPendingDeletions() async {
    if (_loadError != null || _pendingDeletion != null) return;
    try {
      final root = await getApplicationDocumentsDirectory();
      final recovery = await _pendingDeletionStore.recover(
        root,
        tripExists: (tripId) => _data.trips.any((trip) => trip.id == tripId),
      );
      if (recovery.active.isEmpty || !mounted) return;
      final active = recovery.active.first;
      final remaining = active.expiresAt.difference(
        _pendingDeletionStore.now(),
      );
      _pendingDeletionTimer?.cancel();
      _pendingDeletion = active;
      _pendingDeletionTimer = Timer(
        remaining.isNegative ? Duration.zero : remaining,
        () => unawaited(_expirePendingDeletion()),
      );
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(_undoSnackBar(active));
    } catch (error) {
      debugPrint('PendingDeletion: 起動時回収に失敗しました: $error');
    }
  }

  Future<void> _consumeInitialSharedUris() async {
    try {
      final result = await _HomePageState._shareChannel
          .invokeMethod<Map<dynamic, dynamic>>('getSharedUris');
      if (result == null) return;
      final overLimitCount = result['overLimitCount'] as int? ?? 0;
      if (overLimitCount > 0) {
        _showMessage('300枚の上限を超えています。上限内の枚数を選び直してから取り込んでください');
        return;
      }
      final successes = result['successes'] as List<dynamic>? ?? <dynamic>[];
      final paths = successes
          .map((e) => (e as Map<dynamic, dynamic>)['path'] as String)
          .toList();
      final failureCount =
          ((result['failures'] as List<dynamic>?)?.length ?? 0);
      if (paths.isEmpty) {
        if (failureCount > 0) _showMessage('$failureCount件の取り込みに失敗しました');
        return;
      }
      await _importSharedUris(paths, failureCount: failureCount);
    } on MissingPluginException {
      // Widget tests and unsupported platforms do not provide the Android channel.
    } on PlatformException catch (error) {
      _showError('共有写真の確認', error);
    }
  }

  Future<dynamic> _handleShareMethod(MethodCall call) async {
    if (call.method == 'sharedProgress') {
      final args = call.arguments;
      if (args is Map) {
        _updateState(() {
          _importCompleted = args['completed'] as int? ?? 0;
          _importTotal = args['total'] as int? ?? 0;
        });
      }
      return null;
    }
    if (call.method != 'sharedUris') return null;
    _updateState(() {
      _importCompleted = null;
      _importTotal = null;
    });
    await _initialization;
    if (_loadError != null) return null;
    final arguments = call.arguments;
    if (arguments is Map) {
      final overLimitCount = arguments['overLimitCount'] as int? ?? 0;
      if (overLimitCount > 0) {
        _showMessage('300枚の上限を超えています。上限内の枚数を選び直してから取り込んでください');
        return null;
      }
      final successes = arguments['successes'] as List<dynamic>? ?? <dynamic>[];
      final paths = successes
          .map((e) => (e as Map<dynamic, dynamic>)['path'] as String)
          .toList();
      final failureCount =
          ((arguments['failures'] as List<dynamic>?)?.length ?? 0);
      if (paths.isEmpty) {
        if (failureCount > 0) _showMessage('$failureCount件の取り込みに失敗しました');
        return null;
      }
      await _importSharedUris(paths, failureCount: failureCount);
    }
    return null;
  }

  Future<void> _commitData(AppData next) async {
    await _store.save(next);
    if (!mounted) return;
    _updateState(() => _data = next);
  }

  Future<void> _importSharedUris(
    List<String> uris, {
    int failureCount = 0,
  }) async {
    if (uris.isEmpty || _loadError != null) return;
    try {
      await _coordinator.runMutation(() async {
        final uniqueUris = uris.toSet().toList(growable: false);
        final available = _HomePageState._maxPhotos - _data.photoCount;
        if (available <= 0 || uniqueUris.length > available) {
          await _deleteTemporarySharedFiles(uniqueUris);
          _showMessage('無料版の写真上限300枚を超えるため取り込めません');
          return;
        }

        final copied = await _copySharedFiles(uniqueUris);
        if (copied.isEmpty) return;

        final createsTrip = _data.trips.length < _HomePageState._maxTrips;
        AppData next;
        if (createsTrip) {
          next = addNewTrip(
            _data,
            Trip(
              id: createEntityId('trip'),
              title: '共有からのおでかけ ${_data.trips.length + 1}',
              photos: copied,
            ),
          );
        } else {
          next = _data.copyWith(
            unassignedPhotos: <File>[..._data.unassignedPhotos, ...copied],
          );
        }

        try {
          await _commitData(next);
        } catch (_) {
          await _deleteFiles(copied);
          rethrow;
        }
        var message = createsTrip
            ? '${copied.length}枚を共有から取り込みました'
            : '${copied.length}枚を旅行未設定へ取り込みました';
        if (failureCount > 0) {
          message += '（$failureCount件失敗）';
        }
        _showMessage(message);
      });
    } catch (error) {
      _showError('共有写真の取り込み', error);
    }
  }

  Future<List<File>> _copySharedFiles(List<String> paths) async {
    final directory = await getApplicationDocumentsDirectory();
    final photosDirectory = Directory('${directory.path}/photos');
    await photosDirectory.create(recursive: true);
    final copied = <File>[];
    try {
      for (var index = 0; index < paths.length; index++) {
        final source = File(paths[index]);
        if (!await source.exists()) continue;
        final destination = File(
          '${photosDirectory.path}/${createEntityId('shared')}-${index.toString().padLeft(3, '0')}${_safeExtension(source.path)}',
        );
        copied.add(await source.copy(destination.path));
      }
      return copied;
    } catch (_) {
      await _deleteFiles(copied);
      rethrow;
    } finally {
      await _deleteTemporarySharedFiles(paths);
    }
  }

  Future<void> _deleteTemporarySharedFiles(Iterable<String> paths) async {
    for (final path in paths) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Cache cleanup failure must not discard an otherwise successful import.
      }
    }
  }

  Future<void> _addPhotos({String? tripId}) async {
    if (_loadError != null) return;
    final selected = await _picker.pickMultiImage(
      imageQuality: 85,
      maxWidth: 2048,
    );
    if (selected.isEmpty || !mounted) return;

    try {
      await _coordinator.runMutation(() async {
        final available = _HomePageState._maxPhotos - _data.photoCount;
        if (selected.length > available) {
          _showMessage('追加できるのは残り$available枚です。枚数を減らして選び直してください');
          return;
        }
        if (tripId == null && _data.trips.length >= _HomePageState._maxTrips) {
          _showMessage('旅行は10件までです。既存旅行へ追加するか旅行を整理してください');
          return;
        }

        final copied = await _copyPickedImages(selected);
        if (copied.isEmpty) return;
        final next = tripId == null
            ? addNewTrip(
                _data,
                Trip(
                  id: createEntityId('trip'),
                  title: '新しいおでかけ ${_data.trips.length + 1}',
                  photos: copied,
                ),
              )
            : addPhotosToTrip(_data, tripId, copied);

        try {
          await _commitData(next);
        } catch (_) {
          await _deleteFiles(copied);
          rethrow;
        }
        _showMessage('${copied.length}枚を取り込みました');
      });
    } catch (error) {
      _showError('写真の取り込み', error);
    }
  }

  Future<List<File>> _copyPickedImages(List<XFile> selected) async {
    final directory = await getApplicationDocumentsDirectory();
    final photosDirectory = Directory('${directory.path}/photos');
    await photosDirectory.create(recursive: true);
    final copied = <File>[];
    try {
      for (var index = 0; index < selected.length; index++) {
        final image = selected[index];
        final safeName = image.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
        final destination = File(
          '${photosDirectory.path}/${createEntityId('photo')}-${index.toString().padLeft(3, '0')}-$safeName',
        );
        copied.add(await File(image.path).copy(destination.path));
      }
      return copied;
    } catch (_) {
      await _deleteFiles(copied);
      rethrow;
    }
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
          '「${trip.title}」と写真${trip.photos.length}枚を端末から削除します。すぐに元に戻すことができます。',
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
        final root = await getApplicationDocumentsDirectory();
        // 先に退避とmanifestの永続化を完了させてからAppDataを確定する。
        // 途中で失敗した場合はstage内で元パスへ巻き戻し、データを失わない。
        final pending = await _pendingDeletionStore.stage(
          trip,
          root,
          tripIndex: _data.trips.indexOf(trip),
        );
        try {
          await _commitData(removeTrip(_data, tripId));
        } catch (_) {
          await _pendingDeletionStore.rollback(pending);
          rethrow;
        }
        _setPendingDeletion(pending);
        if (!mounted) return;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(_undoSnackBar(pending));
      });
    } catch (error) {
      _showError('旅行の削除', error);
    }
  }

  Future<void> _undoPendingDeletion() async {
    final pending = _pendingDeletion;
    if (pending == null) return;
    try {
      await _coordinator.runMutation(() async {
        // 期限切れで確定削除が始まっていた場合は二重実行を防ぐ。
        if (_pendingDeletion != pending) return;
        final restoredTrip = await _pendingDeletionStore.restore(pending);
        try {
          await _commitData(
            addNewTrip(_data, restoredTrip, atIndex: pending.tripIndex),
          );
        } catch (_) {
          await _pendingDeletionStore.revertRestore(pending);
          rethrow;
        }
        _pendingDeletionTimer?.cancel();
        _pendingDeletion = null;
        await _pendingDeletionStore.commitRestore(pending);
        _showMessage('旅行と写真を元に戻しました');
      });
    } catch (error) {
      _showError('削除の取り消し', error);
    }
  }

  /// Undo期限を過ぎた削除を確定する。failure時は次回起動のcleanupで再試行される。
  Future<void> _expirePendingDeletion() async {
    final pending = _pendingDeletion;
    if (pending == null) return;
    try {
      await _coordinator.runMutation(() async {
        if (_pendingDeletion != pending) return;
        _pendingDeletion = null;
        try {
          await _pendingDeletionStore.finalize(pending);
        } catch (_) {
          // 削除は次回起動のcleanupが再試行する。二重に実行しない。
        }
      });
    } catch (_) {
      _pendingDeletion = null;
    }
  }

  /// pending削除状態をメモリに反映し、期限到来時の確定削除タイマーを開始する。
  void _setPendingDeletion(PendingDeletion pending) {
    _pendingDeletionTimer?.cancel();
    _pendingDeletion = pending;
    _pendingDeletionTimer = Timer(
      pending.expiresAt.difference(_pendingDeletionStore.now()),
      () => unawaited(_expirePendingDeletion()),
    );
  }

  SnackBar _undoSnackBar(PendingDeletion pending) {
    return SnackBar(
      content: const Text('旅行を削除しました'),
      duration: pending.expiresAt.difference(_pendingDeletionStore.now()),
      action: SnackBarAction(
        label: '元に戻す',
        onPressed: () => unawaited(_undoPendingDeletion()),
      ),
    );
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
