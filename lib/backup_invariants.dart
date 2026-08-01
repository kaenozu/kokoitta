import 'dart:io';

/// Backup作成と復元の双方が参照する上限定数の唯一の定義元。
///
/// 作成側(`BackupService`)と復元側(`backup_restore.dart`)が別々に
/// 定数を定義してドリフトしないよう、すべてこのファイルから参照する。
const int backupMaxTrips = 10;
const int backupMaxPhotos = 300;
const int backupMaxCompressedBytes = 700 * 1024 * 1024;
const int backupMaxSinglePhotoBytes = 40 * 1024 * 1024;
const int backupMaxUncompressedBytes = 900 * 1024 * 1024;
const int backupMaxManifestBytes = 512 * 1024;
const int backupMaxTripsBytes = 2 * 1024 * 1024;

/// ID（旅行ID・写真ID）の長さ上限。復元側の `_requiredString` と同一の値。
const int backupMaxEntityIdLength = 200;

/// 写真metadata文字列の長さ上限。復元側の JSON 検証（1文字列500文字）と同一の値。
const int backupMaxMetadataStringLength = 500;

/// 構造的不変条件違反の種別。
enum BackupInvariantViolation {
  tooManyTrips,
  tooManyPhotos,
  duplicateTripId,
  invalidTripId,
  duplicatePhotoId,
  invalidPhotoId,
  duplicatePhotoPath,
  metadataTooLong,
}

/// 1件の不変条件違反。違反種別と対象（件数・ID・パス）を持つ。
class BackupInvariantIssue {
  const BackupInvariantIssue(this.violation, this.subject);

  final BackupInvariantViolation violation;
  final String subject;

  @override
  String toString() => 'BackupInvariantIssue(${violation.name}: $subject)';
}

/// 共通検査へ渡す写真1枚分の不変条件入力。
///
/// [path] は入力の信頼境界に応じて意味が変わる一意キーである。
/// 作成側は「正規化済みの実ファイルパス」、復元側は「ZIP内のarchivePath」を渡す。
class BackupInvariantPhoto {
  const BackupInvariantPhoto({
    required this.id,
    required this.path,
    this.metadataStrings = const <String>[],
  });

  final String id;
  final String path;
  final List<String> metadataStrings;
}

/// 構造的不変条件の検査対象。入力の具体型（AppData / パース済みBackup）に
/// 依存せず、呼び出し側が adapter で接続する。
class BackupInvariantCheck {
  const BackupInvariantCheck({
    required this.tripCount,
    required this.photoCount,
    required this.tripIds,
    required this.photos,
  });

  final int tripCount;
  final int photoCount;
  final Iterable<String> tripIds;
  final Iterable<BackupInvariantPhoto> photos;
}

/// 作成側と復元側が共通に要求する構造的不変条件を検査し、
/// 最初の違反を返す。違反がなければ `null` を返す。
///
/// 検査内容:
/// - 旅行数・写真数（旅行内＋旅行未設定）の上限
/// - 旅行ID・写真IDの一意性と形式（空でない・長さ上限以内）
/// - 写真パス（作成側: 実ファイル、復元側: ZIPパス）の一意性
/// - 写真metadata文字列の長さ上限
BackupInvariantIssue? checkBackupInvariants(BackupInvariantCheck check) {
  if (check.tripCount > backupMaxTrips) {
    return BackupInvariantIssue(
      BackupInvariantViolation.tooManyTrips,
      '旅行数が上限($backupMaxTrips)を超えています: ${check.tripCount}',
    );
  }
  if (check.photoCount > backupMaxPhotos) {
    return BackupInvariantIssue(
      BackupInvariantViolation.tooManyPhotos,
      '写真枚数が上限($backupMaxPhotos)を超えています: ${check.photoCount}',
    );
  }
  final tripIds = <String>{};
  for (final id in check.tripIds) {
    if (id.isEmpty || id.length > backupMaxEntityIdLength) {
      return BackupInvariantIssue(
        BackupInvariantViolation.invalidTripId,
        '旅行IDが不正です: $id',
      );
    }
    if (!tripIds.add(id)) {
      return BackupInvariantIssue(
        BackupInvariantViolation.duplicateTripId,
        '旅行IDが重複しています: $id',
      );
    }
  }
  final photoIds = <String>{};
  final paths = <String>{};
  for (final photo in check.photos) {
    if (photo.id.isEmpty || photo.id.length > backupMaxEntityIdLength) {
      return BackupInvariantIssue(
        BackupInvariantViolation.invalidPhotoId,
        '写真IDが不正です: ${photo.id}',
      );
    }
    if (!photoIds.add(photo.id)) {
      return BackupInvariantIssue(
        BackupInvariantViolation.duplicatePhotoId,
        '写真IDが重複しています: ${photo.id}',
      );
    }
    if (!paths.add(photo.path)) {
      return BackupInvariantIssue(
        BackupInvariantViolation.duplicatePhotoPath,
        '写真パスが重複しています: ${photo.path}',
      );
    }
    for (final metadata in photo.metadataStrings) {
      if (metadata.length > backupMaxMetadataStringLength) {
        return BackupInvariantIssue(
          BackupInvariantViolation.metadataTooLong,
          '写真メタデータが上限($backupMaxMetadataStringLength)を超えています: ${photo.id}',
        );
      }
    }
  }
  return null;
}

/// 作成側のパス一意キー: 同一物理ファイルを指す別表記（区切り文字・`.`/`..`・
/// Windowsの大文字小文字）を同一キーへ正規化する。
String canonicalPhotoPath(File file) {
  final path = file.absolute.path.replaceAll('\\', '/');
  final normalized = Uri(path: path).normalizePath().path;
  return Platform.isWindows ? normalized.toLowerCase() : normalized;
}
