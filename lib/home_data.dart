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
            unassignedPhotos: <Photo>[..._data.unassignedPhotos, ...copied],
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

  Future<List<Photo>> _copySharedFiles(List<String> paths) async {
    final directory = await getApplicationDocumentsDirectory();
    final photosDirectory = Directory('${directory.path}/photos');
    await photosDirectory.create(recursive: true);
    final copied = <Photo>[];
    try {
      for (var index = 0; index < paths.length; index++) {
        final source = File(paths[index]);
        if (!await source.exists()) continue;
        final stat = await source.stat();
        final destination = File(
          '${photosDirectory.path}/${createEntityId('shared')}-${index.toString().padLeft(3, '0')}${_safeExtension(source.path)}',
        );
        final copiedFile = await source.copy(destination.path);
        copied.add(
          Photo(
            id: createPhotoId(),
            file: copiedFile,
            capturedAt: stat.modified,
            originalName: _originalNameOfPath(source.path),
            mimeType: _mimeTypeOf(source.path),
          ),
        );
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

  Future<List<Photo>> _copyPickedImages(List<XFile> selected) async {
    final directory = await getApplicationDocumentsDirectory();
    final photosDirectory = Directory('${directory.path}/photos');
    await photosDirectory.create(recursive: true);
    final copied = <Photo>[];
    try {
      for (var index = 0; index < selected.length; index++) {
        final image = selected[index];
        final source = File(image.path);
        final stat = await source.stat();
        final safeName = image.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
        final destination = File(
          '${photosDirectory.path}/${createEntityId('photo')}-${index.toString().padLeft(3, '0')}-$safeName',
        );
        final copiedFile = await source.copy(destination.path);
        copied.add(
          Photo(
            id: createPhotoId(),
            file: copiedFile,
            capturedAt: stat.modified,
            originalName: image.name,
            mimeType: _mimeTypeOf(image.path),
          ),
        );
      }
      return copied;
    } catch (_) {
      await _deleteFiles(copied);
      rethrow;
    }
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

  String? _originalNameOfPath(String path) {
    final fileName = path.split(RegExp(r'[/\\]')).last;
    return fileName.isEmpty ? null : fileName;
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
