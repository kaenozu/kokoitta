import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'photo.dart';

enum PendingDeletionState {
  staged,
  pending,
  undoFailed,
  undoCommitFailed,
  undoRollbackFailed,
  cleanupFailed,
}

enum PendingDeletionPhysicalState { staged, restored, deleted }

abstract interface class PendingDeletionManifestStore {
  Future<String?> load();
  Future<void> save(String? encoded);
}

class SharedPreferencesPendingDeletionStore
    implements PendingDeletionManifestStore {
  SharedPreferencesPendingDeletionStore({
    Future<SharedPreferences> Function()? preferencesFactory,
  }) : _preferencesFactory =
           preferencesFactory ?? SharedPreferences.getInstance;

  static const key = 'pendingDeletionManifestV1';
  final Future<SharedPreferences> Function() _preferencesFactory;

  @override
  Future<String?> load() async => (await _preferencesFactory()).getString(key);

  @override
  Future<void> save(String? encoded) async {
    final preferences = await _preferencesFactory();
    final ok = encoded == null
        ? await preferences.remove(key)
        : await preferences.setString(key, encoded);
    if (!ok) {
      throw const FileSystemException('pending manifestを保存できませんでした');
    }
  }
}

typedef MovePendingFile = Future<void> Function(String from, String to);
typedef DeletePendingFile = Future<void> Function(String path);

class PendingDeletionItem {
  PendingDeletionItem({
    required this.photo,
    required this.tripId,
    required this.tripIndex,
    required this.photoIndex,
    required this.originalPath,
    required this.trashPath,
    required this.physicalState,
  });

  final Photo photo;
  final String tripId;
  final int tripIndex;
  final int photoIndex;
  final String originalPath;
  final String trashPath;
  PendingDeletionPhysicalState physicalState;

  Map<String, Object?> toJson() => <String, Object?>{
    'photo': <String, Object?>{
      'id': photo.id,
      'path': photo.file.path,
      'capturedAt': photo.capturedAt?.toIso8601String(),
      'location': photo.location,
      'originalName': photo.originalName,
      'mimeType': photo.mimeType,
    },
    'tripId': tripId,
    'tripIndex': tripIndex,
    'photoIndex': photoIndex,
    'originalPath': originalPath,
    'trashPath': trashPath,
    'physicalState': physicalState.name,
  };

  factory PendingDeletionItem.fromJson(Map<String, Object?> json) {
    final photoJson = _map(json['photo'], 'photo');
    final id = _string(photoJson['id'], 'photo.id');
    final path = _string(photoJson['path'], 'photo.path');
    final capturedAt = photoJson['capturedAt'];
    final captured = capturedAt == null
        ? null
        : DateTime.tryParse(_string(capturedAt, 'photo.capturedAt'));
    if (capturedAt != null && captured == null) {
      throw const FormatException('photo.capturedAtが不正です');
    }
    final originalPath = _safeAbsolutePath(json['originalPath']);
    final trashPath = _safeAbsolutePath(json['trashPath']);
    final state = PendingDeletionPhysicalState.values.byName(
      _string(json['physicalState'], 'physicalState'),
    );
    if (path != originalPath) {
      throw const FormatException('photo.pathがoriginalPathと一致しません');
    }
    return PendingDeletionItem(
      photo: Photo(
        id: id,
        file: File(path),
        capturedAt: captured,
        location: _optionalString(photoJson['location']),
        originalName: _optionalString(photoJson['originalName']),
        mimeType: _optionalString(photoJson['mimeType']),
      ),
      tripId: _string(json['tripId'], 'tripId'),
      tripIndex: _nonNegativeInt(json['tripIndex'], 'tripIndex'),
      photoIndex: _nonNegativeInt(json['photoIndex'], 'photoIndex'),
      originalPath: originalPath,
      trashPath: trashPath,
      physicalState: state,
    );
  }
}

class PendingDeletionOperation {
  PendingDeletionOperation({
    required this.operationId,
    required this.trip,
    required this.createdAt,
    required this.expiresAt,
    required this.state,
    required List<PendingDeletionItem> items,
    int? tripIndex,
  }) : items = items,
       tripIndex = tripIndex ?? (items.isEmpty ? 0 : items.first.tripIndex);

  final String operationId;
  final Trip trip;
  final int tripIndex;
  final DateTime createdAt;
  final DateTime expiresAt;
  PendingDeletionState state;
  final List<PendingDeletionItem> items;

  Map<String, Object?> toJson() => <String, Object?>{
    'operationId': operationId,
    'tripIndex': tripIndex,
    'createdAt': createdAt.toIso8601String(),
    'expiresAt': expiresAt.toIso8601String(),
    'state': state.name,
    'trip': <String, Object?>{
      'id': trip.id,
      'title': trip.title,
      'photos': trip.photos
          .map(
            (photo) => <String, Object?>{
              'id': photo.id,
              'path': photo.file.path,
              'capturedAt': photo.capturedAt?.toIso8601String(),
              'location': photo.location,
              'originalName': photo.originalName,
              'mimeType': photo.mimeType,
            },
          )
          .toList(),
    },
    'items': items.map((item) => item.toJson()).toList(),
  };

  factory PendingDeletionOperation.fromJson(Map<String, Object?> json) {
    final tripJson = _map(json['trip'], 'trip');
    final photos = _list(tripJson['photos'], 'trip.photos')
        .map((value) => _photoFromJson(_map(value, 'trip.photos[]')))
        .toList(growable: false);
    final items = _list(json['items'], 'items')
        .map((value) => PendingDeletionItem.fromJson(_map(value, 'items[]')))
        .toList();
    final state = PendingDeletionState.values.byName(
      _string(json['state'], 'state'),
    );
    final createdAt = DateTime.tryParse(
      _string(json['createdAt'], 'createdAt'),
    );
    final expiresAt = DateTime.tryParse(
      _string(json['expiresAt'], 'expiresAt'),
    );
    if (createdAt == null || expiresAt == null) {
      throw const FormatException('manifest日時が不正です');
    }
    final persistedTripIndex = json['tripIndex'];
    return PendingDeletionOperation(
      operationId: _string(json['operationId'], 'operationId'),
      trip: Trip(
        id: _string(tripJson['id'], 'trip.id'),
        title: _string(tripJson['title'], 'trip.title'),
        photos: photos,
      ),
      tripIndex: persistedTripIndex == null
          ? (items.isEmpty ? 0 : items.first.tripIndex)
          : _nonNegativeInt(persistedTripIndex, 'tripIndex'),
      createdAt: createdAt,
      expiresAt: expiresAt,
      state: state,
      items: items,
    );
  }
}

class PendingDeletionManager {
  PendingDeletionManager({
    required this.store,
    required this.trashRoot,
    this.now = _systemNow,
    MovePendingFile? moveFile,
    DeletePendingFile? deleteFile,
    this.undoWindow = const Duration(seconds: 30),
  }) : moveFile = moveFile ?? _rename,
       deleteFile = deleteFile ?? _delete;

  final PendingDeletionManifestStore store;
  final String trashRoot;
  final DateTime Function() now;
  final MovePendingFile moveFile;
  final DeletePendingFile deleteFile;
  final Duration undoWindow;

  Future<List<PendingDeletionOperation>> loadOperations() async {
    final raw = await store.load();
    if (raw == null) return <PendingDeletionOperation>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw const FormatException('manifest rootが不正です');
      }
      final version = decoded['version'];
      final values = decoded['operations'];
      if (version != 1 || values is! List) {
        throw const FormatException('manifest versionが不正です');
      }
      return values
          .map(
            (value) => PendingDeletionOperation.fromJson(
              Map<String, Object?>.from(value as Map),
            ),
          )
          .toList();
    } on FormatException {
      rethrow;
    } catch (error) {
      throw FormatException('pending manifestを読み取れません: $error');
    }
  }

  Future<void> _save(List<PendingDeletionOperation> operations) async {
    if (operations.isEmpty) return store.save(null);
    await store.save(
      jsonEncode(<String, Object?>{
        'version': 1,
        'operations': operations
            .map((operation) => operation.toJson())
            .toList(),
      }),
    );
  }

  Future<PendingDeletionOperation> deleteTrip({
    required AppData data,
    required String tripId,
    required Future<void> Function(AppData data) saveData,
  }) async {
    final operations = await loadOperations();
    if (operations.any((operation) => operation.trip.id == tripId)) {
      throw StateError('同じ旅行の削除が既にpendingです');
    }

    final tripIndex = data.trips.indexWhere((trip) => trip.id == tripId);
    if (tripIndex < 0) {
      throw StateError('削除する旅行が見つかりません');
    }

    final trip = data.trips[tripIndex];
    final operationId =
        'delete-${now().microsecondsSinceEpoch}-${tripId.hashCode.abs()}';
    final operationDirectory = Directory('$trashRoot/$operationId');
    await operationDirectory.create(recursive: true);

    final items = <PendingDeletionItem>[];
    for (var index = 0; index < trip.photos.length; index++) {
      final photo = trip.photos[index];
      final originalPath = _safeAbsolutePath(photo.file.path);
      final trashPath = _safeAbsolutePath(
        '${operationDirectory.path}/$index-${_basename(originalPath)}',
      );
      items.add(
        PendingDeletionItem(
          photo: photo.copyWith(file: File(originalPath)),
          tripId: trip.id,
          tripIndex: tripIndex,
          photoIndex: index,
          originalPath: originalPath,
          trashPath: trashPath,
          physicalState: PendingDeletionPhysicalState.staged,
        ),
      );
    }

    final operation = PendingDeletionOperation(
      operationId: operationId,
      trip: trip,
      tripIndex: tripIndex,
      createdAt: now(),
      expiresAt: now().add(undoWindow),
      state: PendingDeletionState.staged,
      items: items,
    );
    final withOperation = <PendingDeletionOperation>[...operations, operation];
    final moved = <PendingDeletionItem>[];

    // Phase 1: stage physical files and persist the recovery manifest.
    try {
      for (final item in items) {
        await moveFile(item.originalPath, item.trashPath);
        moved.add(item);
      }
      await _save(withOperation);
    } catch (error) {
      final restoreFailures = await _restoreMoved(moved);
      if (restoreFailures.isEmpty) {
        try {
          final persisted = await loadOperations();
          if (persisted.any(
            (candidate) => candidate.operationId == operationId,
          )) {
            await _save(operations);
          }
        } catch (_) {
          // Preserve the original staging error. A partially written manifest
          // is safer than masking the failure with a cleanup exception.
        }
        Error.throwWithStackTrace(error, StackTrace.current);
      }
      operation.state = PendingDeletionState.undoRollbackFailed;
      await _save(withOperation);
      throw StateError(
        '写真の退避に失敗し、${restoreFailures.length}件を元に戻せませんでした: '
        '$error / $restoreFailures',
      );
    }

    // Phase 2: commit the AppData deletion. Before this succeeds, a failure can
    // still be rolled back to the original state.
    final next = data.copyWith(
      trips: <Trip>[...data.trips]..removeAt(tripIndex),
    );
    try {
      await saveData(next);
    } catch (error) {
      final restoreFailures = await _restoreMoved(moved);
      if (restoreFailures.isEmpty) {
        await _save(operations);
        Error.throwWithStackTrace(error, StackTrace.current);
      }
      operation.state = PendingDeletionState.undoRollbackFailed;
      await _save(withOperation);
      throw StateError(
        '旅行削除の保存に失敗し、${restoreFailures.length}件を元に戻せませんでした: '
        '$error / $restoreFailures',
      );
    }

    // Phase 3: AppData is committed. Never restore files or remove the staged
    // manifest from this point, because doing so would orphan the deleted trip.
    operation.state = PendingDeletionState.pending;
    try {
      await _save(withOperation);
      return operation;
    } catch (error) {
      operation.state = PendingDeletionState.staged;
      try {
        await _save(withOperation);
      } catch (safeguardError) {
        throw StateError(
          '旅行削除後のmanifest更新に失敗し、回復用manifestの再保存にも失敗しました: '
          '$error / $safeguardError',
        );
      }
      throw StateError(
        '旅行削除後のmanifest更新に失敗しました。'
        '回復用manifestを保持したため、アプリ再起動後に処理を再開します: $error',
      );
    }
  }

  Future<void> undo({
    required String operationId,
    required AppData data,
    required Future<void> Function(AppData data) saveData,
  }) async {
    final operations = await loadOperations();
    final operation = operations.firstWhere(
      (item) => item.operationId == operationId,
      orElse: () => throw StateError('pending削除が見つかりません'),
    );
    if (!now().isBefore(operation.expiresAt)) {
      throw StateError('Undo期限が切れています');
    }
    if (data.trips.any((trip) => trip.id == operation.trip.id)) {
      throw StateError('復元対象の旅行が既に存在します');
    }

    final restored = <PendingDeletionItem>[];
    try {
      for (final item in operation.items) {
        if (item.physicalState == PendingDeletionPhysicalState.restored) {
          restored.add(item);
          continue;
        }
        if (File(item.originalPath).existsSync()) {
          throw StateError('復元先に別ファイルがあります: ${item.originalPath}');
        }
        await moveFile(item.trashPath, item.originalPath);
        item.physicalState = PendingDeletionPhysicalState.restored;
        restored.add(item);
      }
    } catch (error) {
      operation.state = PendingDeletionState.undoFailed;
      await _save(operations);
      Error.throwWithStackTrace(error, StackTrace.current);
    }

    final trips = <Trip>[...data.trips];
    final insertAt = operation.tripIndex.clamp(0, trips.length);
    final restoredPhotos = [...operation.items]
      ..sort((a, b) => a.photoIndex.compareTo(b.photoIndex));
    trips.insert(
      insertAt,
      operation.trip.copyWith(
        photos: restoredPhotos
            .map((item) => item.photo.copyWith(file: File(item.originalPath)))
            .toList(),
      ),
    );

    try {
      await saveData(data.copyWith(trips: trips));
    } catch (error) {
      final rollbackFailures = await _restageRestored(restored);
      if (rollbackFailures.isEmpty) {
        operation.state = PendingDeletionState.pending;
        await _save(operations);
        Error.throwWithStackTrace(error, StackTrace.current);
      }
      operation.state = PendingDeletionState.undoRollbackFailed;
      await _save(operations);
      throw StateError(
        'Undoの保存に失敗しました（original: $error）。'
        'rollbackで${rollbackFailures.length}件失敗しました: $rollbackFailures',
      );
    }

    operations.remove(operation);
    await _save(operations);
  }

  Future<List<Object>> _restageRestored(
    Iterable<PendingDeletionItem> restored,
  ) async {
    final failures = <Object>[];
    for (final item in restored.toList().reversed) {
      try {
        if (!File(item.originalPath).existsSync()) {
          failures.add(
            StateError('復元元のファイルが見つかりません: ${item.originalPath}'),
          );
          continue;
        }
        await moveFile(item.originalPath, item.trashPath);
        item.physicalState = PendingDeletionPhysicalState.staged;
      } catch (error) {
        failures.add(error);
      }
    }
    return failures;
  }

  Future<List<String>> finalizeExpired({DateTime? at}) async {
    final operations = await loadOperations();
    final finalized = <String>[];
    for (final operation in [...operations]) {
      if ((at ?? now()).isBefore(operation.expiresAt)) continue;
      if (!_isExpiredFinalizable(operation)) continue;

      var failed = false;
      for (final item in operation.items) {
        if (item.physicalState == PendingDeletionPhysicalState.deleted) {
          continue;
        }
        if (item.physicalState == PendingDeletionPhysicalState.restored) {
          failed = true;
          break;
        }
        if (!File(item.trashPath).existsSync()) {
          item.physicalState = PendingDeletionPhysicalState.deleted;
          continue;
        }
        try {
          await deleteFile(item.trashPath);
          item.physicalState = PendingDeletionPhysicalState.deleted;
        } catch (_) {
          failed = true;
        }
      }

      if (failed) {
        operation.state = PendingDeletionState.cleanupFailed;
      } else {
        operations.remove(operation);
        finalized.add(operation.operationId);
      }
      await _save(operations);
    }
    return finalized;
  }

  bool _isExpiredFinalizable(PendingDeletionOperation operation) {
    return switch (operation.state) {
      PendingDeletionState.pending ||
      PendingDeletionState.cleanupFailed => true,
      PendingDeletionState.staged ||
      PendingDeletionState.undoFailed ||
      PendingDeletionState.undoCommitFailed ||
      PendingDeletionState.undoRollbackFailed => false,
    };
  }

  Future<List<Object>> _restoreMoved(
    Iterable<PendingDeletionItem> items,
  ) async {
    final failures = <Object>[];
    for (final item in items.toList().reversed) {
      try {
        if (File(item.originalPath).existsSync()) {
          item.physicalState = PendingDeletionPhysicalState.restored;
          continue;
        }
        if (File(item.trashPath).existsSync()) {
          await moveFile(item.trashPath, item.originalPath);
          item.physicalState = PendingDeletionPhysicalState.restored;
          continue;
        }
        failures.add(
          StateError(
            'originalとtrashの両方にファイルがありません: ${item.originalPath}',
          ),
        );
      } catch (error) {
        failures.add(error);
      }
    }
    return failures;
  }
}

DateTime _systemNow() => DateTime.now().toUtc();
Future<void> _rename(String from, String to) => File(from).rename(to);
Future<void> _delete(String path) => File(path).delete();
String _basename(String path) => path.split(RegExp(r'[/\\]')).last;

String _safeAbsolutePath(Object? value) {
  final raw = _string(value, 'path');
  final normalized = raw.replaceAll('\\', '/');
  if (normalized.startsWith('//') ||
      normalized.contains('/../') ||
      normalized.endsWith('/..') ||
      normalized.split('/').contains('..') ||
      normalized.split('/').contains('.')) {
    throw const FormatException('path traversalまたは正規化前pathは許可されません');
  }
  if (!(normalized.startsWith('/') ||
      RegExp(r'^[A-Za-z]:/').hasMatch(normalized))) {
    throw const FormatException('pathは絶対pathである必要があります');
  }
  return raw;
}

Photo _photoFromJson(Map<String, Object?> json) => Photo(
  id: _string(json['id'], 'photo.id'),
  file: File(_safeAbsolutePath(json['path'])),
  capturedAt: json['capturedAt'] == null
      ? null
      : DateTime.parse(_string(json['capturedAt'], 'photo.capturedAt')),
  location: _optionalString(json['location']),
  originalName: _optionalString(json['originalName']),
  mimeType: _optionalString(json['mimeType']),
);

Map<String, Object?> _map(Object? value, String field) => value is Map
    ? Map<String, Object?>.from(value)
    : throw FormatException('$fieldがMapではありません');

List<Object?> _list(Object? value, String field) => value is List
    ? value.cast<Object?>()
    : throw FormatException('$fieldがListではありません');

String _string(Object? value, String field) =>
    value is String && value.isNotEmpty
    ? value
    : throw FormatException('$fieldが不正です');

String? _optionalString(Object? value) =>
    value == null ? null : _string(value, 'metadata');

int _nonNegativeInt(Object? value, String field) =>
    value is int && value >= 0
    ? value
    : throw FormatException('$fieldが不正です');
