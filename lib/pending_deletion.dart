/// 旅行と写真のUndo可能な遅延削除。
///
/// 削除対象の写真を`pending-deletions/`配下へ退避し、削除情報をmanifest.jsonに
/// 永続化する。Undo期限（デフォルト30秒）内なら写真を元パスへ戻して旅行を復元
/// でき、期限後は確定削除できる。アプリ終了後もmanifestから状態を回収できる。
///
/// 関連: lib/models.dart, lib/home_data.dart, lib/storage_cleanup.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'models.dart';

/// 復元（Undo）で退避写真の一部しか元へ戻せなかった場合に投げられる例外。
class PartialRestoreException implements Exception {
  const PartialRestoreException(this.failures);

  final List<String> failures;

  @override
  String toString() => '写真の復元が不完全です: ${failures.join('; ')}';
}

/// 退避した写真1枚分のレコード。
///
/// 元の並び順（index）・元パス・退避先パスを1単位として保持することで、
/// 写真が欠損していても復元時の順序と所属を保証する。
class PendingPhotoRecord {
  const PendingPhotoRecord({
    required this.index,
    required this.originalPath,
    this.trashPath,
  });

  final int index;
  final String originalPath;

  /// 退避先パス。退避時点で元ファイルが存在しない場合はnull。
  final String? trashPath;

  Map<String, Object?> toJson() => <String, Object?>{
    'index': index,
    'originalPath': originalPath,
    'trashPath': trashPath,
  };

  factory PendingPhotoRecord.fromJson(Map<String, dynamic> json) {
    final index = json['index'];
    final originalPath = json['originalPath'];
    if (index is! int) throw const FormatException('indexがありません');
    if (originalPath is! String || originalPath.isEmpty) {
      throw const FormatException('originalPathがありません');
    }
    final trashPath = json['trashPath'];
    if (trashPath != null && trashPath is! String) {
      throw const FormatException('trashPathが壊れています');
    }
    return PendingPhotoRecord(
      index: index,
      originalPath: originalPath,
      trashPath: trashPath as String?,
    );
  }
}

/// 削除対象旅行の退避状態。Undo期限と写真所属を保持する。
class PendingDeletion {
  const PendingDeletion({
    required this.trip,
    required this.trashDirectory,
    required this.records,
    required this.expiresAt,
    required this.tripIndex,
  });

  final Trip trip;
  final Directory trashDirectory;
  final List<PendingPhotoRecord> records;
  final DateTime expiresAt;

  /// 削除時点の旅行一覧上の位置。復元時に元の位置へ戻すために使う。
  final int tripIndex;

  bool isExpired(DateTime now) => now.isAfter(expiresAt);

  Map<String, Object?> toJson() => <String, Object?>{
    'tripId': trip.id,
    'title': trip.title,
    'tripIndex': tripIndex,
    'expiresAt': expiresAt.toIso8601String(),
    'records': records.map((record) => record.toJson()).toList(growable: false),
  };

  factory PendingDeletion.fromJson(
    Map<String, dynamic> json, {
    required Directory trashDirectory,
  }) {
    final tripId = json['tripId'];
    final title = json['title'];
    final expiresAtRaw = json['expiresAt'];
    final recordsRaw = json['records'];
    if (tripId is! String || tripId.isEmpty) {
      throw const FormatException('tripIdがありません');
    }
    if (title is! String) throw const FormatException('titleがありません');
    if (expiresAtRaw is! String) {
      throw const FormatException('expiresAtがありません');
    }
    final expiresAt = DateTime.tryParse(expiresAtRaw);
    if (expiresAt == null) throw const FormatException('expiresAtを解析できません');
    if (recordsRaw is! List) throw const FormatException('recordsがありません');
    final records = <PendingPhotoRecord>[];
    for (final raw in recordsRaw) {
      if (raw is! Map) {
        throw const FormatException('recordの形式が正しくありません');
      }
      records.add(PendingPhotoRecord.fromJson(Map<String, dynamic>.from(raw)));
    }
    final tripIndex = json['tripIndex'];
    return PendingDeletion(
      trip: Trip(
        id: tripId,
        title: title,
        photos: <File>[for (final record in records) File(record.originalPath)],
      ),
      trashDirectory: trashDirectory,
      records: records,
      expiresAt: expiresAt,
      tripIndex: tripIndex is int ? tripIndex : -1,
    );
  }
}

/// 起動時回収の結果。
class PendingDeletionRecovery {
  const PendingDeletionRecovery({
    this.active = const <PendingDeletion>[],
    this.rolledBack = const <String>[],
    this.skipped = const <String>[],
  });

  /// 削除確定済みかつ期限内のもの。Undo対象として有効化できる。
  final List<PendingDeletion> active;

  /// 削除が確定していない（旅行がAppData上に残っている）ため元へ戻したもの。
  final List<String> rolledBack;

  /// 壊れたmanifestや管理ディレクトリ外のパスなど、安全のため触らないもの。
  final List<String> skipped;
}

typedef MoveFileFn = Future<void> Function(File source, File destination);
typedef DeleteFileFn = Future<void> Function(File file);

/// 遅延削除の退避・復元・確定削除・起動時回収を担うストア。
class PendingDeletionStore {
  PendingDeletionStore({
    DateTime Function()? now,
    Duration? undoWindow,
    MoveFileFn? moveFile,
    DeleteFileFn? deleteFile,
  }) : _now = now ?? DateTime.now,
       undoWindow = undoWindow ?? defaultUndoWindow,
       _moveFile = moveFile ?? _moveFileDefault,
       _deleteFile = deleteFile ?? ((File file) => file.delete());

  static const Duration defaultUndoWindow = Duration(seconds: 30);
  static const String pendingRootName = 'pending-deletions';
  static const String manifestName = 'manifest.json';

  final DateTime Function() _now;
  final Duration undoWindow;
  final MoveFileFn _moveFile;
  final DeleteFileFn _deleteFile;

  DateTime now() => _now();

  /// 旅行の写真を退避し、Undo期限付きのpending deletionを作成する。
  ///
  /// 途中で失敗した場合は移動済みファイルを元パスへ戻して例外を投げる。
  /// 失敗時点でAppDataは変更していない（呼び出し側が確定する）。
  Future<PendingDeletion> stage(
    Trip trip,
    Directory root, {
    int? tripIndex,
  }) async {
    final trash = Directory(
      '${root.path}/$pendingRootName/${_safeSegment(trip.id)}',
    );
    await trash.create(recursive: true);
    final records = <PendingPhotoRecord>[];
    for (var index = 0; index < trip.photos.length; index++) {
      final source = trip.photos[index];
      records.add(
        PendingPhotoRecord(
          index: index,
          originalPath: source.path,
          trashPath: await source.exists()
              ? '${trash.path}/$index-${_basename(source.path)}'
              : null,
        ),
      );
    }
    final pending = PendingDeletion(
      trip: trip,
      trashDirectory: trash,
      records: records,
      expiresAt: _now().add(undoWindow),
      tripIndex: tripIndex ?? -1,
    );
    try {
      // manifestを先に書くことで、途中クラッシュ時も起動時回収が
      // 旅行の存否に応じてrollbackできるようにする。
      await _writeManifest(pending);
      for (final record in records) {
        final trashPath = record.trashPath;
        if (trashPath == null) continue;
        await _moveFile(File(record.originalPath), File(trashPath));
      }
      return pending;
    } catch (_) {
      await _rollbackRecords(records, trash);
      await _removeTrashIfClean(trash);
      rethrow;
    }
  }

  /// 退避済みファイルを元パスへ戻す。旅行がAppData上に残っている場合
  /// （stage/commit失敗時やクラッシュ回収時）に使う。
  ///
  /// 全レコードがクリーンな状態になった場合のみmanifestと退避ディレクトリを
  /// 削除し、trueを返す。
  Future<bool> rollback(PendingDeletion pending) async {
    final clean = await _rollbackRecords(
      pending.records,
      pending.trashDirectory,
    );
    if (clean) await _removeTrashIfClean(pending.trashDirectory);
    return clean;
  }

  /// Undo実行。全写真を元パスへ戻し、旅行（写真の元の並び順）を返す。
  ///
  /// 1枚でも復元に失敗した場合は移動済みファイルを退避先へ戻し、
  /// [PartialRestoreException]を投げる。退避データは保持されるため再試行できる。
  Future<Trip> restore(PendingDeletion pending) async {
    final failures = <String>[];
    final moved = <PendingPhotoRecord>[];
    for (final record in pending.records) {
      final trashPath = record.trashPath;
      if (trashPath == null) continue;
      final source = File(trashPath);
      final original = File(record.originalPath);
      if (!await source.exists()) {
        // 既に復元済み（再試行時）なら成功扱い、両方欠損なら失敗扱い。
        if (!await original.exists()) {
          failures.add('${record.index}: 退避・元ファイルの両方が見つかりません');
        }
        continue;
      }
      if (await original.exists()) {
        failures.add('${record.index}: 元パスに別のファイルが存在します');
        continue;
      }
      try {
        await original.parent.create(recursive: true);
        await _moveFile(source, original);
        moved.add(record);
      } catch (error) {
        failures.add('${record.index}: $error');
      }
    }
    if (failures.isNotEmpty) {
      // 部分復元を成功扱いしない。移動済みファイルを退避先へ戻し再試行可能にする。
      for (final record in moved) {
        final source = File(record.originalPath);
        final destination = File(record.trashPath!);
        if (await source.exists() && !await destination.exists()) {
          try {
            await _moveFile(source, destination);
          } catch (_) {
            // 戻せない場合は退避先に残り、起動時回収で再処理される。
          }
        }
      }
      throw PartialRestoreException(failures);
    }
    return pending.trip.copyWith(
      photos: <File>[
        for (final record in pending.records) File(record.originalPath),
      ],
    );
  }

  /// 復元後にAppDataのcommitが失敗した場合、元パスへ戻したファイルを
  /// 退避先へ戻してpending状態を維持する。
  Future<void> revertRestore(PendingDeletion pending) async {
    for (final record in pending.records) {
      final trashPath = record.trashPath;
      if (trashPath == null) continue;
      final original = File(record.originalPath);
      final destination = File(trashPath);
      if (!await original.exists() || await destination.exists()) continue;
      try {
        await _moveFile(original, destination);
      } catch (error) {
        debugPrint(
          'PendingDeletion: 復元の巻き戻しに失敗: ${record.originalPath}: $error',
        );
      }
    }
  }

  /// 復元とAppDataのcommitが成功した後に、退避ディレクトリの後始末をする。
  Future<void> commitRestore(PendingDeletion pending) =>
      _removeTrashIfClean(pending.trashDirectory);

  /// Undo期限後に退避写真を物理削除する。
  ///
  /// manifestを最後まで残すことで、途中で失敗しても次回起動のcleanupで
  /// 再試行できる。
  Future<void> finalize(PendingDeletion pending) async {
    final trash = pending.trashDirectory;
    if (!await trash.exists()) return;
    for (final entity in await trash.list().toList()) {
      if (entity is! File || _basename(entity.path) == manifestName) continue;
      await _deleteFile(entity);
    }
    await _removeTrashIfClean(trash);
  }

  /// 起動時に`pending-deletions/`を検査して状態を回収する。
  ///
  /// * 旅行がAppData上に残っている → 削除未確定なのでrollback（元へ戻す）
  /// * 旅行が消えていて期限内 → [PendingDeletionRecovery.active]へ
  /// * 旅行が消えていて期限切れ → StorageCleanupが削除する（触らない）
  /// * 壊れたmanifestや管理外パス → データ保護のため保持し、[skipped]へ
  Future<PendingDeletionRecovery> recover(
    Directory root, {
    required bool Function(String tripId) tripExists,
  }) async {
    final pendingRoot = Directory('${root.path}/$pendingRootName');
    if (!await pendingRoot.exists()) return const PendingDeletionRecovery();
    final active = <PendingDeletion>[];
    final rolledBack = <String>[];
    final skipped = <String>[];
    for (final entity in await pendingRoot.list().toList()) {
      if (entity is! Directory) continue;
      final manifestFile = File('${entity.path}/$manifestName');
      if (!await manifestFile.exists()) {
        skipped.add(entity.path);
        continue;
      }
      PendingDeletion pending;
      try {
        final decoded = jsonDecode(await manifestFile.readAsString());
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('manifestの形式が正しくありません');
        }
        pending = PendingDeletion.fromJson(decoded, trashDirectory: entity);
        _validatePaths(pending, entity, root);
      } catch (error) {
        debugPrint(
          'PendingDeletion: 壊れたpending deletionを保持します: ${entity.path}: $error',
        );
        skipped.add(entity.path);
        continue;
      }
      if (tripExists(pending.trip.id)) {
        await rollback(pending);
        rolledBack.add(entity.path);
      } else if (!pending.isExpired(_now())) {
        active.add(pending);
      }
    }
    return PendingDeletionRecovery(
      active: active,
      rolledBack: rolledBack,
      skipped: skipped,
    );
  }

  Future<void> _writeManifest(PendingDeletion pending) async {
    await File(
      '${pending.trashDirectory.path}/$manifestName',
    ).writeAsString(jsonEncode(pending.toJson()), flush: true);
  }

  Future<bool> _rollbackRecords(
    List<PendingPhotoRecord> records,
    Directory trash,
  ) async {
    var clean = true;
    for (final record in records) {
      final trashPath = record.trashPath;
      if (trashPath == null) continue;
      final source = File(trashPath);
      final original = File(record.originalPath);
      if (!await source.exists()) {
        if (!await original.exists()) clean = false;
        continue;
      }
      if (await original.exists()) {
        clean = false;
        continue;
      }
      try {
        await original.parent.create(recursive: true);
        await _moveFile(source, original);
      } catch (error) {
        debugPrint(
          'PendingDeletion: 退避の巻き戻しに失敗: ${record.originalPath}: $error',
        );
        clean = false;
      }
    }
    return clean;
  }

  /// manifestと退避ディレクトリを、残存ファイルがない場合のみ削除する。
  Future<void> _removeTrashIfClean(Directory trash) async {
    if (!await trash.exists()) return;
    final manifest = File('${trash.path}/$manifestName');
    if (await manifest.exists()) await _deleteFile(manifest);
    if (!await trash.exists()) return;
    final remaining = trash.listSync();
    if (remaining.isEmpty) await trash.delete();
  }

  /// 復元対象・退避先がアプリ管理ディレクトリの外へ逃げていないか検証する。
  void _validatePaths(
    PendingDeletion pending,
    Directory trashDirectory,
    Directory root,
  ) {
    final rootPath = _normalizePath(root.path);
    if (!_normalizePath(pending.trashDirectory.path).startsWith('$rootPath/')) {
      throw const FormatException('退避先が管理ディレクトリの外です');
    }
    final trashPath = _normalizePath(trashDirectory.path);
    for (final record in pending.records) {
      if (record.trashPath != null &&
          !_normalizePath(record.trashPath!).startsWith('$trashPath/')) {
        throw const FormatException('退避ファイルが管理ディレクトリの外です');
      }
      if (!_normalizePath(record.originalPath).startsWith('$rootPath/')) {
        throw const FormatException('元パスが管理ディレクトリの外です');
      }
    }
  }

  static String _normalizePath(String path) => path.replaceAll('\\', '/');

  static String _safeSegment(String value) {
    final sanitized = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return sanitized.isEmpty ? 'unknown' : sanitized;
  }

  static String _basename(String path) {
    final segments = path.split(RegExp(r'[/\\]'));
    return segments.isEmpty ? 'file' : segments.last;
  }

  static Future<void> _moveFileDefault(File source, File destination) async {
    try {
      await source.rename(destination.path);
      return;
    } on FileSystemException {
      // 別ボリューム等でrenameできない場合はcopy + flush + deleteへ切り替える。
    }
    final copied = await source.copy(destination.path);
    final raf = await copied.open(mode: FileMode.append);
    try {
      await raf.flush();
    } finally {
      await raf.close();
    }
    try {
      await source.delete();
    } catch (_) {
      await destination.delete();
      rethrow;
    }
  }
}
