import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'backup_invariants.dart';
import 'models.dart';
import 'photo.dart';
import 'validators.dart';

part 'backup_restore.dart';
part 'backup_models.dart';

typedef DocumentsDirectoryProvider = Future<Directory> Function();
typedef BackupFilePicker = Future<File?> Function();

class BackupService {
  BackupService({
    DocumentsDirectoryProvider? documentsDirectoryProvider,
    BackupFilePicker? backupFilePicker,
    this.maxSinglePhotoBytes = backupMaxSinglePhotoBytes,
    this.maxUncompressedBytes = backupMaxUncompressedBytes,
  }) : _documentsDirectoryProvider =
           documentsDirectoryProvider ?? getApplicationDocumentsDirectory,
       _backupFilePicker = backupFilePicker ?? _pickBackupFile;

  static const String appId = 'com.kaenozu.kokoitta_app';
  static const int currentFormatVersion = 3;
  static const int maxTrips = backupMaxTrips;
  static const int maxPhotos = backupMaxPhotos;
  static const int maxCompressedBytes = backupMaxCompressedBytes;
  static const int maxManifestBytes = backupMaxManifestBytes;
  static const int maxTripsBytes = backupMaxTripsBytes;

  /// 写真1枚・合計の容量上限。テストで縮小できるようインスタンス変数とし、
  /// 既定値は共通定数（[backupMaxSinglePhotoBytes] / [backupMaxUncompressedBytes]）を
  /// 参照する。
  final int maxSinglePhotoBytes;
  final int maxUncompressedBytes;

  final DocumentsDirectoryProvider _documentsDirectoryProvider;
  final BackupFilePicker _backupFilePicker;

  Future<File> createBackup(AppData data) {
    return _createBackup(data, folderName: 'backups');
  }

  Future<File> createSafetySnapshot(AppData data) {
    return _createBackup(data, folderName: 'safety-backups');
  }

  Future<PreparedRestore?> prepareRestore() =>
      _BackupRestoreOperations(this).prepareRestore();

  Future<PreparedRestore> prepareRestoreFile(File file) =>
      _BackupRestoreOperations(this).prepareRestoreFile(file);

  Future<PreparedRestore> prepareRestoreBytes(List<int> bytes) =>
      _BackupRestoreOperations(this).prepareRestoreBytes(bytes);

  Future<void> shareBackup(File file) =>
      _BackupRestoreOperations(this).shareBackup(file);

  Future<File> _createBackup(AppData data, {required String folderName}) async {
    _validateBackupSource(data);
    final checksums = <String, String>{};
    final archiveFiles = <({File file, String archivePath})>[];
    var totalBytes = 0;
    var photoCount = 0;

    Future<List<Map<String, Object>>> inspectPhotos(
      Iterable<Photo> photos,
      String group,
    ) async {
      final records = <Map<String, Object>>[];
      var index = 0;
      for (final photo in photos) {
        final file = photo.file;
        if (!await file.exists()) {
          throw FileSystemException('バックアップ対象の写真がありません', file.path);
        }
        final length = await file.length();
        if (length > maxSinglePhotoBytes) {
          throw FormatException('写真1枚の容量が上限を超えています: ${file.path}');
        }
        totalBytes += length;
        photoCount += 1;
        if (totalBytes > maxUncompressedBytes) {
          throw const FormatException('バックアップ対象の写真容量が上限を超えています');
        }
        final archivePath =
            'photos/$group-${index.toString().padLeft(3, '0')}${_safeExtension(file.path)}';
        final digest = await sha256.bind(file.openRead()).first;
        checksums[archivePath] = digest.toString();
        archiveFiles.add((file: file, archivePath: archivePath));
        records.add(<String, Object>{
          'id': photo.id,
          'archivePath': archivePath,
          if (photo.capturedAt != null)
            'capturedAt': photo.capturedAt!.toIso8601String(),
          if (photo.location != null) 'location': photo.location!,
          if (photo.originalName != null) 'originalName': photo.originalName!,
          if (photo.mimeType != null) 'mimeType': photo.mimeType!,
        });
        index += 1;
      }
      return records;
    }

    final tripRecords = <Map<String, Object>>[];
    for (var index = 0; index < data.trips.length; index++) {
      final trip = data.trips[index];
      tripRecords.add(<String, Object>{
        'id': trip.id,
        'title': trip.title,
        'photos': await inspectPhotos(trip.photos, 'trip-$index'),
      });
    }
    final unassignedRecords = await inspectPhotos(
      data.unassignedPhotos,
      'unassigned',
    );

    final records = <String, Object>{
      'trips': tripRecords,
      'unassignedPhotos': unassignedRecords,
      'prefectureStates': data.prefectureStates,
    };
    final manifest = <String, Object>{
      'appId': appId,
      'backupFormatVersion': currentFormatVersion,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'tripCount': tripRecords.length,
      'photoCount': photoCount,
      'totalUncompressedBytes': totalBytes,
      'checksumsAlgorithm': 'sha-256',
      'checksums': checksums,
    };

    final directory = await _documentsDirectoryProvider();
    final backupDirectory = Directory('${directory.path}/$folderName');
    await backupDirectory.create(recursive: true);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${backupDirectory.path}/kokoitta-backup-$timestamp.zip');
    final workDirectory = Directory(
      '${directory.path}/backup-staging/$timestamp',
    );
    await workDirectory.create(recursive: true);
    final manifestFile = File('${workDirectory.path}/manifest.json');
    final recordsFile = File('${workDirectory.path}/trips.json');
    await manifestFile.writeAsString(jsonEncode(manifest), flush: true);
    await recordsFile.writeAsString(jsonEncode(records), flush: true);

    final encoder = ZipFileEncoder();
    var opened = false;
    try {
      encoder.create(file.path);
      opened = true;
      for (final archiveFile in archiveFiles) {
        await encoder.addFile(archiveFile.file, archiveFile.archivePath);
      }
      await encoder.addFile(manifestFile, 'manifest.json');
      await encoder.addFile(recordsFile, 'trips.json');
      await encoder.close();
      opened = false;
      if (await file.length() > maxCompressedBytes) {
        await file.delete();
        throw const FormatException('作成したバックアップの容量が上限を超えています');
      }
      return file;
    } catch (_) {
      if (opened) {
        await encoder.close();
        opened = false;
      }
      if (await file.exists()) await file.delete();
      rethrow;
    } finally {
      if (opened) await encoder.close();
      if (await workDirectory.exists()) {
        await workDirectory.delete(recursive: true);
      }
    }
  }

  /// AppDataの構造的不変条件を、ファイルI/O・ZIP生成より前に検証する。
  ///
  /// 復元側が `prepareRestoreFile()` で拒否する条件（旅行数・写真数の上限、
  /// Photo ID・パス・旅行IDの重複等）を、作成前に共通validatorで同じ定義から
  /// 検査する。違反時は作成側の例外規約に従い、上限超過は [FormatException]、
  /// メモリ上の構造違反は [StateError] を投げる。
  void _validateBackupSource(AppData data) {
    final issue = checkBackupInvariants(
      BackupInvariantCheck(
        tripCount: data.trips.length,
        photoCount: data.photoCount,
        tripIds: data.trips.map((trip) => trip.id),
        photos: data.allPhotos.map(
          (photo) => BackupInvariantPhoto(
            id: photo.id,
            path: canonicalPhotoPath(photo.file),
            metadataStrings: <String>[
              if (photo.capturedAt != null) photo.capturedAt!.toIso8601String(),
              if (photo.location != null) photo.location!,
              if (photo.originalName != null) photo.originalName!,
              if (photo.mimeType != null) photo.mimeType!,
            ],
          ),
        ),
      ),
    );
    if (issue == null) return;
    switch (issue.violation) {
      case BackupInvariantViolation.tooManyTrips:
      case BackupInvariantViolation.tooManyPhotos:
      case BackupInvariantViolation.metadataTooLong:
        throw FormatException(issue.subject);
      case BackupInvariantViolation.duplicateTripId:
      case BackupInvariantViolation.invalidTripId:
      case BackupInvariantViolation.duplicatePhotoId:
      case BackupInvariantViolation.invalidPhotoId:
      case BackupInvariantViolation.duplicatePhotoPath:
        throw StateError(issue.subject);
    }
  }
}
